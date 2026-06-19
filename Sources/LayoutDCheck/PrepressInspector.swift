import AppKit
import CoreText
import Foundation
import LayoutDCore

/// Export-time options that influence prepress correctness. Kept as primitives so
/// `LayoutDCheck` stays decoupled from `LayoutDExport` (no module dependency, no
/// import of `PDFXVersion`). The App passes these through from its export settings.
public struct PrepressExportOptions: Equatable, Sendable {
    /// Whether the user selected a legacy PDF/X-style output intent for this export.
    public var pdfxRequested: Bool
    /// Human-readable legacy label (e.g. "PDF/X-1a"), used only for messages.
    public var pdfxLabel: String?
    /// Whether crop marks / bleed marks will be drawn.
    public var drawCropMarks: Bool
    /// Current PDF drawing color pipeline. LayoutD's AppKit/CoreGraphics export is RGB.
    public var outputColorSpace: String

    public init(
        pdfxRequested: Bool = false,
        pdfxLabel: String? = nil,
        drawCropMarks: Bool = false,
        outputColorSpace: String = "RGB"
    ) {
        self.pdfxRequested = pdfxRequested
        self.pdfxLabel = pdfxLabel
        self.drawCropMarks = drawCropMarks
        self.outputColorSpace = outputColorSpace
    }
}

/// Document- and configuration-level prepress checks. Image-level checks
/// (RGB-vs-CMYK, effective DPI, source-file presence) already live in
/// `ProjectInspector.inspectAssets`; this inspector intentionally does **not**
/// repeat them. It covers the gaps that only become visible once you consider the
/// page geometry and the chosen export configuration:
///
/// - honest disclosure that PDF output is an RGB pipeline, not CMYK/PDF-X
///   conformance (the "诚实交接" half of route A);
/// - bleed/crop-mark consistency;
/// - full-bleed pages whose background does not actually reach the bleed box;
/// - placed image effective DPI based on the actual export frame size;
/// - font availability / embedding-permission red flags;
/// - hairline strokes that print unreliably.
public struct PrepressInspector {
    /// Common minimum bleed for offset printing, in millimetres.
    public static let conventionalBleedMM = 3.0
    /// Export-time minimum for placed raster assets, computed from actual frame width.
    public static let minimumEffectiveDPI = 300.0
    /// Strokes thinner than this (in points) risk dropping out or printing unevenly.
    public static let hairlineThresholdPoints = 0.25

    public init() {}

    public func inspect(
        project: BookProject,
        document: LaidOutDocument? = nil,
        options: PrepressExportOptions = .init()
    ) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        issues.append(contentsOf: inspectOutputColorSpace(options: options))
        issues.append(contentsOf: inspectPDFXHonesty(options: options))
        issues.append(contentsOf: inspectBleed(project: project, options: options))
        issues.append(contentsOf: inspectFontEmbedding(project: project))

        if let document {
            issues.append(contentsOf: inspectFullBleedCoverage(project: project, document: document))
            issues.append(contentsOf: inspectPlacedAssetDPI(project: project, document: document))
            issues.append(contentsOf: inspectHairlineStrokes(document: document))
        }

        return issues
    }

    // MARK: - Color-space honesty

    private func inspectOutputColorSpace(options: PrepressExportOptions) -> [LayoutIssue] {
        guard options.outputColorSpace.uppercased() == "RGB" else {
            return []
        }

        return [
            LayoutIssue(
                severity: .warning,
                message: "当前 PDF 导出管线为 RGB；LayoutD 不执行 CMYK 分色，也不冒充 CMYK 印刷文件",
                category: .prepress,
                suggestedFix: "将 LayoutD 导出的高质量 RGB/PDF 作为交接产物；正式 CMYK 转换、分色与印厂规范校验交由印厂、Acrobat 或 PitStop 完成。"
            )
        ]
    }

    // MARK: - PDF/X honesty

    private func inspectPDFXHonesty(options: PrepressExportOptions) -> [LayoutIssue] {
        guard options.pdfxRequested else {
            return []
        }

        let label = options.pdfxLabel ?? "PDF/X"
        return [
            LayoutIssue(
                severity: .warning,
                message: "导出选择了 \(label) 输出意图标签，但当前渲染管线为 RGB，生成文件并非 \(label) 合规文件",
                category: .prepress,
                suggestedFix: "该文件可作为高质量 RGB/PDF 交接；正式印刷请交印厂或 Acrobat/PitStop 做 CMYK 分色与 PDF/X 合规校验，或在导出设置中关闭输出意图标签。"
            )
        ]
    }

    // MARK: - Bleed / crop-mark consistency

    private func inspectBleed(project: BookProject, options: PrepressExportOptions) -> [LayoutIssue] {
        let bleed = project.pageSetup.bleedMM ?? 0
        var issues: [LayoutIssue] = []

        if options.drawCropMarks, bleed <= 0 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "导出要求裁切线/出血标记，但页面出血（bleedMM）为 0",
                    category: .prepress,
                    suggestedFix: "在页面设置中将出血设为常规的 \(formatted(Self.conventionalBleedMM)) mm，否则裁切误差会在成品边缘露白。"
                )
            )
        } else if bleed > 0, bleed < Self.conventionalBleedMM {
            issues.append(
                LayoutIssue(
                    severity: .info,
                    message: "页面出血为 \(formatted(bleed)) mm，低于常规印刷出血 \(formatted(Self.conventionalBleedMM)) mm",
                    category: .prepress,
                    suggestedFix: "如印厂无特殊要求，建议将出血设为 \(formatted(Self.conventionalBleedMM)) mm。"
                )
            )
        }

        return issues
    }

    // MARK: - Full-bleed coverage

    private func inspectFullBleedCoverage(project: BookProject, document: LaidOutDocument) -> [LayoutIssue] {
        let fullBleedStrategies: Set<LayoutStrategy> = [.cover, .fullPageImage, .titlePage]
        guard let plans = project.appliedLayoutPlans, !plans.isEmpty else {
            return []
        }

        let pageWidth = project.pageSetup.pageSize.width
        let pageHeight = project.pageSetup.pageSize.height
        let bleedPoints = (project.pageSetup.bleedMM ?? 0) * 72.0 / 25.4
        let requiredWidth = pageWidth + 2 * bleedPoints
        let requiredHeight = pageHeight + 2 * bleedPoints
        var issues: [LayoutIssue] = []

        for page in document.pages {
            guard let plan = plans[page.number], fullBleedStrategies.contains(plan.strategy) else {
                continue
            }

            let hasFullPageFrame = page.frames.contains { frame in
                guard isVisual(frame.content) else {
                    return false
                }
                let reachesTrim = frame.rect.x <= 1.0
                    && frame.rect.y <= 1.0
                    && frame.rect.x + frame.rect.width >= pageWidth - 1.0
                    && frame.rect.y + frame.rect.height >= pageHeight - 1.0
                let reachesBleed = frame.rect.x <= -bleedPoints + 1.0
                    && frame.rect.y <= -bleedPoints + 1.0
                    && frame.rect.x + frame.rect.width >= pageWidth + bleedPoints - 1.0
                    && frame.rect.y + frame.rect.height >= pageHeight + bleedPoints - 1.0
                return bleedPoints > 0 ? reachesBleed : reachesTrim
            }

            if !hasFullPageFrame {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "第 \(page.number) 页为满版/封面页，但未检测到覆盖 BleedBox 的图框（需要约 \(formatted(requiredWidth)) x \(formatted(requiredHeight)) pt），出血区可能露白",
                        category: .prepress,
                        suggestedFix: "将该页背景图或满版图向四边各延伸 \(formatted(bleedPoints)) pt，确保覆盖 TrimBox 外的 BleedBox。",
                        pageNumber: page.number
                    )
                )
            }
        }

        return issues
    }

    private func isVisual(_ content: FrameContent) -> Bool {
        switch content {
        case .asset, .spreadAsset:
            return true
        case .text, .empty:
            return false
        }
    }

    // MARK: - Actual placed DPI

    private func inspectPlacedAssetDPI(project: BookProject, document: LaidOutDocument) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        let assetsByID = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id, $0) })

        for page in document.pages {
            for frame in page.frames {
                guard let assetId = assetId(from: frame.content),
                      let asset = assetsByID[assetId],
                      let effectiveDPI = effectiveDPI(asset: asset, frameWidthPoints: frame.rect.width),
                      effectiveDPI < Self.minimumEffectiveDPI else {
                    continue
                }

                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "第 \(page.number) 页图片 \(asset.fileName) 按实际导出尺寸计算为 \(Int(effectiveDPI)) DPI，低于 \(Int(Self.minimumEffectiveDPI)) DPI 印前阈值",
                        category: .prepress,
                        suggestedFix: "替换更高像素图片，或缩小该图片在导出页面上的实际占位尺寸。",
                        pageNumber: page.number,
                        frameId: frame.id,
                        assetId: asset.id
                    )
                )
            }
        }

        return issues
    }

    private func assetId(from content: FrameContent) -> UUID? {
        switch content {
        case .asset(let id):
            return id
        case .spreadAsset(let id, _):
            return id
        case .text, .empty:
            return nil
        }
    }

    private func effectiveDPI(asset: Asset, frameWidthPoints: Double) -> Double? {
        guard asset.pixelWidth > 0, frameWidthPoints > 0 else {
            return asset.dpi
        }
        return Double(asset.pixelWidth) / (frameWidthPoints / 72.0)
    }

    // MARK: - Font embedding

    private func inspectFontEmbedding(project: BookProject) -> [LayoutIssue] {
        let fontNames = Set(
            project.styles.paragraphStyles.flatMap { style -> [String] in
                var names = [style.fontName]
                names.append(contentsOf: style.compositeFont?.values.map(\.fontName) ?? [])
                return names
            }
        )
        var issues: [LayoutIssue] = []

        for fontName in fontNames.sorted() {
            guard let nsFont = NSFont(name: fontName, size: 12) else {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "字体 \(fontName) 在当前系统不可用，导出时可能被替换",
                        category: .prepress,
                        suggestedFix: "安装该字体，或在样式/复合字体设置中改用当前系统可用且允许嵌入的字体。"
                    )
                )
                continue
            }

            let font = CTFontCreateWithName(nsFont.fontName as CFString, nsFont.pointSize, nil)
            if let embeddingIssue = embeddingRestriction(for: font, fontName: fontName) {
                issues.append(embeddingIssue)
            }
        }

        return issues
    }

    private func embeddingRestriction(for font: CTFont, fontName: String) -> LayoutIssue? {
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
              table.count >= 10 else {
            return nil
        }

        let fsType = UInt16(table[8]) << 8 | UInt16(table[9])
        let restrictedLicenseEmbedding: UInt16 = 1 << 1
        let bitmapOnlyEmbedding: UInt16 = 1 << 9
        let noSubsetting: UInt16 = 1 << 8

        if fsType & restrictedLicenseEmbedding != 0 || fsType & bitmapOnlyEmbedding != 0 {
            return LayoutIssue(
                severity: .warning,
                message: "字体 \(fontName) 的授权位标记为不可常规嵌入 PDF",
                category: .prepress,
                suggestedFix: "更换为允许 PDF 嵌入的授权字体，或在交付给印厂前完成字体授权与嵌入检查。"
            )
        }

        if fsType & noSubsetting != 0 {
            return LayoutIssue(
                severity: .info,
                message: "字体 \(fontName) 标记为不允许子集嵌入，PDF 体积和印厂处理可能受影响",
                category: .prepress,
                suggestedFix: "确认字体授权，必要时改用允许子集嵌入的字体。"
            )
        }

        return nil
    }

    // MARK: - Hairline strokes

    private func inspectHairlineStrokes(document: LaidOutDocument) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []

        for page in document.pages {
            for frame in page.frames {
                guard let width = frame.strokeWidth, width > 0, width < Self.hairlineThresholdPoints else {
                    continue
                }

                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "第 \(page.number) 页存在发丝线（描边 \(formatted(width)) pt，低于 \(formatted(Self.hairlineThresholdPoints)) pt），印刷可能丢失或不均",
                        category: .prepress,
                        suggestedFix: "将描边加粗到至少 \(formatted(Self.hairlineThresholdPoints)) pt，或改用填色块。",
                        pageNumber: page.number,
                        frameId: frame.id
                    )
                )
            }
        }

        return issues
    }

    // MARK: - Helpers

    private func formatted(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}

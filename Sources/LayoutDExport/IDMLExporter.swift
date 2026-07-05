import CoreText
import Foundation
import LayoutDCore

/// 阶段 E1：把真实 `BookProject` + 排版结果 `LaidOutDocument` 映射成 IDML，交 InDesign
/// 人工精调 + 印前。结构沿用已在 InDesign 中文版验证通过的 spike(竖排 / 复合字体 /
/// 置入图 / 色板全部 round-trip，见 IDMLSpikeExporter）。
///
/// 最小可用版(MVP)的取舍——已覆盖：每页一个 Spread、文本框→Story(段落样式 + 竖排)、
/// 图片框→Rectangle+Image+Link、颜色 token→RGB 色板、复合字体→Fonts.xml 内 CompositeFont。
/// 暂未覆盖(后续增量，见 development-plan 阶段 E1)：固定美术页→MasterSpread、对开跨页、
/// 非矩形蒙版、字体样式名拆分。
///
/// 颜色按 layoutD 的 RGB 管线导出为 RGB 色板；CMYK 分色 / PDF/X 交 InDesign(印前路线 A)。
public struct IDMLExportOptions: Sendable {
    public var facingPages: Bool
    public var cmykColors: Bool

    public init(facingPages: Bool = false, cmykColors: Bool = false) {
        self.facingPages = facingPages
        self.cmykColors = cmykColors
    }
}

public struct IDMLExporter {
    public init() {}

    public enum ExportError: Error, LocalizedError {
        case zipFailed(String)
        /// 灌版打包前的不变量断言闸发现已知 CJK 保真搭档规则被违反（见 IDMLInvariants）。
        case invariantsFailed([IDMLInvariantViolation])
        public var errorDescription: String? {
            switch self {
            case .zipFailed(let d): return "IDML 打包失败：\(d)"
            case .invariantsFailed(let vs):
                return "IDML 保真断言未通过（\(vs.count) 项）：\n" + vs.map { "  · \($0)" }.joined(separator: "\n")
            }
        }
    }

    private let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private let pkgNS = "xmlns:idPkg=\"http://ns.adobe.com/AdobeInDesign/idml/1.0/packaging\""
    private let dom = "16.0"
    // 着重号(Kenten)、避头尾等 CJK 排版特性只在 CJK/World-Ready 段落排版器下渲染；
    // 拉丁排版器会静默忽略 KentenKind。
    //
    // 经真·InDesign 2026 存盘比对(Desktop/未命名-1.idml → /tmp/idml-oracle, 2026-06-23):
    // ① 正确属性名是 Composer(不是 AppliedComposer——InDesign 无此属性、会被忽略);
    // ② 正确值是 "HL Composer J"(CJK/World-Ready, 无 $ID/ 前缀)——"HL Composer Optyca"
    //    其实是拉丁段落排版器(此前注释把中西身份搞反了);
    // ③ 真值挂在段落样式定义与文档 <TextDefault> 上, 不逐 Story 段落内联。
    // 故本导出器把 Composer 写进每个 ParagraphStyle + [No paragraph style] + TextDefault,
    // Story 段落不再写(已删除无效的 AppliedComposer)。
    private let composer = "HL Composer J"

    // MARK: - 入口

    public func export(
        document: LaidOutDocument,
        project: BookProject,
        to url: URL,
        options: IDMLExportOptions = IDMLExportOptions()
    ) throws {
        let pageW = project.pageSetup.pageSize.width
        let pageH = project.pageSetup.pageSize.height
        let pages = document.pages.sorted { $0.number < $1.number }
        let packagedLinks = packagedLinks(for: pages, assets: project.assets)
        let paragraphsByID = Dictionary(
            uniqueKeysWithValues: project.sections
                .flatMap(\.stories)
                .flatMap(\.paragraphs)
                .map { ($0.id, $0) }
        )

        // The global CMYK intent (or the explicit export toggle) flattens every
        // RGB swatch to Process CMYK on emit — non-destructively: stored model
        // values are untouched, only the exported swatches convert.
        let cmykOutput = options.cmykColors || project.pageSetup.colorSpace == .cmyk
        var ctx = BuildContext(project: project, cmykOutput: cmykOutput)
        let includesTOC = pages.contains { page in
            page.frames.contains { !($0.tableOfContentsEntries ?? []).isEmpty }
        }

        // 先扫一遍：注册颜色、字体、复合字体、段落样式所需资源。
        for style in project.styles.paragraphStyles {
            ctx.registerParagraphStyle(style)
        }
        if includesTOC {
            ctx.registerParagraphStyle(tocParagraphStyle(base: ctx.resolvedStyle(id: StyleID.heading2.rawValue), id: "tocLevel1", name: "目录一级"))
            ctx.registerParagraphStyle(tocParagraphStyle(base: ctx.resolvedStyle(id: StyleID.caption.rawValue), id: "tocLevel2", name: "目录二级", indent: 12))
        }
        // 各页 frame 的颜色覆盖也要登记成色板。
        for page in pages {
            for frame in page.frames {
                if let hex = frame.textColorHex { _ = ctx.color(hex) }
                if let hex = frame.backgroundColorHex { _ = ctx.color(hex) }
                if let hex = frame.strokeColorHex { _ = ctx.color(hex) }
                if let component = project.styles.componentStyle(for: frame.kind) {
                    if let hex = component.resolvedFillColorHex(project: project) { _ = ctx.color(hex) }
                    if let hex = component.resolvedStrokeColorHex(project: project) { _ = ctx.color(hex) }
                    if let hex = component.resolvedAccentColorHex(project: project) { _ = ctx.color(hex) }
                }
            }
        }

        // 逐页构建 Spread + Story。
        var spreadRefs: [String] = []
        var storyRefs: [String] = []
        var spreadFiles: [String: String] = [:]
        var storyFiles: [String: String] = [:]
        var storyListIds: [String] = []

        let facing = options.facingPages
        // 对开：首页(pi=0, recto 右)单独成 spread，其后每 2 页一 spread(verso 左 + recto 右)。
        // 每页内容按所在侧水平偏移 dx；非对开时 dx=0、每页独占一个 spread（现状不变）。
        var spreadBuilds: [[(pageSelf: String, pageName: String, transformX: Double, items: [String])]] = []
        for (pi, page) in pages.enumerated() {
            let recto = pi % 2 == 0
            let dx = facing ? (recto ? pageW / 2 : -pageW / 2) : 0
            // 页框 ItemTransform 的 x（绝对）：非对开居中于书脊(-pageW/2)；
            // 对开 recto 右(0, 框[0,pageW])、verso 左(-pageW, 框[-pageW,0])。
            let pageTransformX = facing ? (recto ? 0 : -pageW) : -pageW / 2
            var items: [String] = []

            for (fi, frame) in page.frames.enumerated() {
                switch frame.content {
                case .text(let raw):
                    // 脚注由锚点 Story 内的原生 <Footnote> 承载。LayoutEngine 仍会
                    // 为 Canvas/PDF/PNG 生成页脚 frame；IDML 不能再把那份 frame 当
                    // 普通正文导出，否则 InDesign 会出现两份脚注内容。
                    guard frame.kind != .footnote else { continue }
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        // A hand-drawn box: empty text but carrying a fill/stroke.
                        // Emit it as a rectangle so it isn't silently dropped. A
                        // truly empty flow frame (no fill, no stroke) stays skipped
                        // — it would be invisible in InDesign anyway.
                        let boxFill = frame.backgroundColorHex
                        let boxStroke = frame.strokeColorHex
                        if boxFill != nil || boxStroke != nil {
                            let boxStrokeWidth = frame.strokeWidth ?? (boxStroke != nil ? 1 : 0)
                            items.append(drawnBoxItem(self: "uBox\(pi)_\(fi)", rect: frame.rect,
                                                      fillColor: boxFill, strokeColor: boxStroke,
                                                      strokeWidth: boxStrokeWidth,
                                                      pageW: pageW, pageH: pageH, dx: dx))
                        }
                        continue
                    }
                    let storySelf = "uStory\(pi)_\(fi)"
                    let style = ctx.resolvedStyle(id: frame.styleId)
                    let styleRef = "ParagraphStyle/\(xmlSafe(style.id))"
                    let vertical = style.layoutDirection == .vertical
                    let component = project.styles.componentStyle(for: frame.kind)
                    let resolvedFillHex = frame.backgroundColorHex ?? component?.resolvedFillColorHex(project: project)
                    // 表格底色挪到单元格上（见下方 tableStoryXML），框本身不填色——否则框比
                    // 表格高时底部会露出一块多余色块。
                    let fillColor = frame.kind == .table ? nil : resolvedFillHex
                    let strokeColor = frame.strokeColorHex ?? component?.resolvedStrokeColorHex(project: project)
                    let strokeWidth = frame.strokeWidth ?? component?.strokeWidth ?? 0
                    items.append(textFrameItem(self: "uTF\(pi)_\(fi)", story: storySelf,
                                               rect: frame.rect, fillColor: fillColor,
                                               strokeColor: strokeColor, strokeWidth: strokeWidth,
                                               pageW: pageW, pageH: pageH, dx: dx))
                    // Accent 必须位于有底色的文本框之上，否则会被框架填色遮住。
                    if let accentColor = component?.resolvedAccentColorHex(project: project),
                       let accentWidth = component?.accentWidth, accentWidth > 0 {
                        let accentRect = Rect(x: frame.rect.x, y: frame.rect.y,
                                              width: min(accentWidth, frame.rect.width), height: frame.rect.height)
                        items.append(colorRectangleItem(self: "uAccent\(pi)_\(fi)", rect: accentRect,
                                                        fillColor: accentColor, pageW: pageW, pageH: pageH, dx: dx))
                    }
                    // 原生表格：源段是 .table 且带结构化行列时，Story 内输出 InDesign
                    // <Table>（真行列/可调宽），而非把拍平文本当普通段落画。
                    if frame.kind == .table,
                       let paragraphID = frame.sourceParagraphId,
                       let cells = paragraphsByID[paragraphID]?.tableCells,
                       !cells.isEmpty {
                        let cellFillSwatch = resolvedFillHex.map { ctx.color($0) }
                        storyFiles["Stories/Story_\(storySelf).xml"] = tableStoryXML(
                            self: storySelf, styleRef: styleRef, cells: cells,
                            cellRuns: paragraphsByID[paragraphID]?.tableCellRuns,
                            frameWidth: frame.rect.width, cellFillSwatch: cellFillSwatch)
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                        storyListIds.append(storySelf)
                        continue
                    }
                    if let entries = frame.tableOfContentsEntries, !entries.isEmpty {
                        storyFiles["Stories/Story_\(storySelf).xml"] = tocStoryXML(
                            self: storySelf,
                            entries: entries,
                            frameWidth: frame.rect.width
                        )
                        storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                        storyListIds.append(storySelf)
                        continue
                    }
                    let frameInlineRuns: [InlineRun]?
                    if let paragraphID = frame.sourceParagraphId,
                       let paragraph = paragraphsByID[paragraphID] {
                        frameInlineRuns = inlineRuns(for: text, from: paragraph)
                    } else {
                        frameInlineRuns = nil
                    }
                    let frameFootnotes: [Paragraph]
                    if let paragraphID = frame.sourceParagraphId,
                       let paragraph = paragraphsByID[paragraphID] {
                        frameFootnotes = paragraph.safeAnchoredFootnoteIds.compactMap { paragraphsByID[$0] }
                    } else {
                        frameFootnotes = []
                    }
                    // 脚注正文需要一个带中文复合字体（CF_*）的段落样式，否则 InDesign 退回
                    // 拉丁默认字体、中文显示为豆腐。优先用 caption（小字号、无首行缩进，最像
                    // 脚注），退而求其次用 body；都没有才用空样式。绝不再写死 [No paragraph style]。
                    let emittedStyleIds = Set(ctx.paragraphStyles.map { $0.id })
                    let footnoteStyleRef: String
                    if frameFootnotes.isEmpty {
                        footnoteStyleRef = "ParagraphStyle/$ID/[No paragraph style]"
                    } else if emittedStyleIds.contains(StyleID.caption.rawValue) {
                        footnoteStyleRef = "ParagraphStyle/\(StyleID.caption.rawValue)"
                    } else if emittedStyleIds.contains(StyleID.body.rawValue) {
                        footnoteStyleRef = "ParagraphStyle/\(StyleID.body.rawValue)"
                    } else {
                        footnoteStyleRef = "ParagraphStyle/$ID/[No paragraph style]"
                    }
                    let storyContent = storyXML(self: storySelf, styleRef: styleRef,
                                                vertical: vertical, text: text, inlineRuns: frameInlineRuns,
                                                footnotes: frameFootnotes, footnoteStyleRef: footnoteStyleRef)
                    storyFiles["Stories/Story_\(storySelf).xml"] = storyContent
                    storyRefs.append("\t<idPkg:Story src=\"Stories/Story_\(storySelf).xml\"/>")
                    storyListIds.append(storySelf)
                case .asset(let id), .spreadAsset(let id, _):
                    guard let asset = project.assets.first(where: { $0.id == id }) else { continue }
                    items.append(imageItem(self: "uRect\(pi)_\(fi)", imageSelf: "uImg\(pi)_\(fi)",
                                           linkSelf: "uLink\(pi)_\(fi)", asset: asset,
                                           packagedFileName: packagedLinks[asset.id]?.fileName,
                                           rect: frame.rect, maskShape: frame.maskShape, pageW: pageW, pageH: pageH, dx: dx))
                case .empty:
                    // Drawn shapes have no content → export as an Unassigned Rectangle.
                    // Rectangle: fill (+ optional stroke). Line: a centered thin filled
                    // rectangle whose thin dimension is the stroke weight.
                    if frame.kind == .rectangle, let fill = frame.backgroundColorHex {
                        items.append(colorRectangleItem(
                            self: "uShape\(pi)_\(fi)", rect: frame.rect, fillColor: fill,
                            strokeColor: frame.strokeColorHex, strokeWidth: frame.strokeWidth ?? 0,
                            pageW: pageW, pageH: pageH, dx: dx))
                    } else if frame.kind == .line, let color = frame.strokeColorHex {
                        items.append(graphicLineItem(
                            self: "uShape\(pi)_\(fi)", rect: frame.rect,
                            strokeColor: color, strokeWidth: frame.strokeWidth ?? 1,
                            pageW: pageW, pageH: pageH, dx: dx))
                    }
                    continue
                }
            }

            let pageBuild = (pageSelf: "uPage\(pi)", pageName: "\(page.number)", transformX: pageTransformX, items: items)
            let si = facing ? (pi + 1) / 2 : pi
            if si >= spreadBuilds.count { spreadBuilds.append([]) }
            spreadBuilds[si].append(pageBuild)
        }
        for (si, spreadPages) in spreadBuilds.enumerated() {
            let spreadSelf = "uSpread\(si)"
            spreadFiles["Spreads/Spread_\(spreadSelf).xml"] =
                spreadXML(self: spreadSelf, spreadY: Double(si) * pageH * 1.235,
                          pageW: pageW, pageH: pageH, pages: spreadPages)
            spreadRefs.append("\t<idPkg:Spread src=\"Spreads/Spread_\(spreadSelf).xml\"/>")
        }

        // 组装包内所有部件。
        var files: [String: String] = [
            "mimetype": "application/vnd.adobe.indesign-idml-package",
            "META-INF/container.xml": container(),
            "META-INF/metadata.xml": metadata(),
            "Resources/Graphic.xml": graphic(ctx: ctx),
            "Resources/Fonts.xml": fonts(ctx: ctx),
            "Resources/Styles.xml": styles(ctx: ctx, includesTOC: includesTOC),
            "Resources/Preferences.xml": preferences(pageW: pageW, pageH: pageH, pageCount: pages.count, facing: facing),
            "XML/Tags.xml": tags(),
            "XML/BackingStory.xml": backingStory(),
            "MasterSpreads/MasterSpread_uMasterA.xml": masterSpread(pageW: pageW, pageH: pageH),
            "designmap.xml": designmap(spreadRefs: spreadRefs, storyRefs: storyRefs, storyList: storyListIds)
        ]
        files.merge(spreadFiles) { _, b in b }
        files.merge(storyFiles) { _, b in b }

        // 打包前过一遍不变量断言闸：锁住已知的 CJK 渲染搭档规则，撞回归当场报错而非等 InDesign。
        let violations = IDMLInvariants.check(files: files)
        guard violations.isEmpty else { throw ExportError.invariantsFailed(violations) }

        try writePackage(files: files, to: url)
        try copyPackagedLinks(packagedLinks.values, beside: url)
    }

    private struct PackagedLink {
        let sourceURL: URL
        let fileName: String
    }

    /// 只打包实际置入页面且源文件存在的素材。同一素材重复置入时复用链接；不同素材
    /// basename 冲突时保留扩展名并追加序号（figure.png、figure-2.png）。
    private func packagedLinks(for pages: [LaidOutPage], assets: [Asset]) -> [UUID: PackagedLink] {
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var result: [UUID: PackagedLink] = [:]
        var usedNames: Set<String> = []

        for page in pages {
            for frame in page.frames {
                let assetId: UUID
                switch frame.content {
                case .asset(let id), .spreadAsset(let id, _): assetId = id
                case .text, .empty: continue
                }
                guard result[assetId] == nil,
                      let asset = assetsById[assetId],
                      let sourcePath = asset.sourcePath,
                      !sourcePath.isEmpty else { continue }

                let sourceURL = URL(fileURLWithPath: sourcePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

                let requestedName = URL(fileURLWithPath: asset.fileName).lastPathComponent
                let baseName = requestedName.isEmpty ? sourceURL.lastPathComponent : requestedName
                let uniqueName = uniqueLinkName(baseName, usedNames: &usedNames)
                result[assetId] = PackagedLink(sourceURL: sourceURL, fileName: uniqueName)
            }
        }
        return result
    }

    private func uniqueLinkName(_ fileName: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(fileName).inserted { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var sequence = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(sequence)" : "\(stem)-\(sequence).\(ext)"
            if usedNames.insert(candidate).inserted { return candidate }
            sequence += 1
        }
    }

    private func copyPackagedLinks(_ links: Dictionary<UUID, PackagedLink>.Values, beside outputURL: URL) throws {
        guard !links.isEmpty else { return }
        let fm = FileManager.default
        let linksDirectory = outputURL.deletingLastPathComponent().appendingPathComponent("Links", isDirectory: true)
        try fm.createDirectory(at: linksDirectory, withIntermediateDirectories: true)
        for link in links {
            let destination = linksDirectory.appendingPathComponent(link.fileName)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: link.sourceURL, to: destination)
        }
    }

    // MARK: - 构建上下文（资源注册表）

    private struct BuildContext {
        let project: BookProject
        /// When true, RGB swatches are converted to Process CMYK before keying,
        /// so the whole document exports in a single CMYK color space.
        let cmykOutput: Bool
        var colorOrder: [String] = []          // 规范化 hex
        var colorName: [String: String] = [:]  // hex -> Color Self
        var fontOrder: [String] = []           // 字体家族顺序(InDesign 索引用的家族名)
        var fontStyles: [String: [(style: String, ps: String, full: String, type: String)]] = [:]  // 家族 -> [(样式, PostScript名, 全名, FontType)]
        var appliedFamily: [String: String] = [:]  // layoutD 原始字体名 -> InDesign 家族名
        var appliedStyle: [String: String] = [:]   // layoutD 原始字体名 -> InDesign 样式名
        var compositeFontStyleIds: [String] = []   // 有复合字体、需生成 CompositeFont 的样式 id
        var paragraphStyles: [ParagraphStyle] = []

        init(project: BookProject, cmykOutput: Bool = false) {
            self.project = project
            self.cmykOutput = cmykOutput
            // 预置内建黑色。
            colorOrder = ["000000"]
            colorName = ["000000": "Color/Black"]
        }

        mutating func color(_ raw: String) -> String {
            // RGB canonicalizes to the same 6-hex key as the legacy path, so
            // existing RGB swatches keep their exact Self / order. CMYK colors
            // key on their own canonical string and emit a Space="CMYK" swatch.
            // NOTE: keying/Self stay in the color's *stored* space so every frame
            // reference keeps matching; a CMYK output intent only rewrites the
            // emitted Space/Value/Name in `graphic()`, never the Self.
            let parsed = PrintColor(string: raw) ?? .rgb(r: 0, g: 0, b: 0)
            let key = parsed.canonicalString
            if let n = colorName[key] { return n }
            let name = parsed.idmlSwatchSelf
            colorName[key] = name
            // Built-in Black (RGB #000000 or CMYK 0,0,0,100) reuses the seeded
            // Color/Black swatch and is never re-emitted in Graphic.xml.
            if name != "Color/Black" {
                colorOrder.append(key)
            }
            return name
        }

        /// The text fill color to use, applying the CMYK-mode "black text → K100"
        /// rule: under a CMYK output intent a near-black text color collapses to
        /// `#000000` → the built-in `Color/Black` (Space=CMYK 0 0 0 100), so
        /// body/heading text prints as clean single-black instead of a 4-color
        /// rich black. Colored text is left untouched.
        func textColorHex(_ raw: String?) -> String {
            let hex = raw ?? "#000000"
            if cmykOutput, let color = PrintColor(string: hex), color.isNearBlack {
                return "#000000"
            }
            return hex
        }

        mutating func font(_ name: String) {
            let r = Self.idNames(name)
            appliedFamily[name] = r.family
            appliedStyle[name] = r.style
            if fontStyles[r.family] == nil { fontStyles[r.family] = []; fontOrder.append(r.family) }
            if !(fontStyles[r.family]?.contains { $0.style == r.style } ?? false) {
                fontStyles[r.family]?.append((r.style, r.ps, r.full, r.type))
            }
        }

        /// 用 CoreText 在本机把 layoutD 字体名解析成 InDesign 实际索引用的
        /// (本地化家族名, 本地化样式名, 真实 PostScript 名, 全名)。
        /// InDesign 中文版按本地化家族名(如「苹方-简」)+ PostScript 名匹配已装字体，
        /// 给英文家族名或把家族名当 PS 名都会被判缺失。
        static func idNames(_ raw: String) -> (family: String, style: String, ps: String, full: String, type: String) {
            let (eFam, eSty) = splitFont(raw)
            let attrs: [CFString: Any] = [
                kCTFontFamilyNameAttribute: eFam,
                kCTFontStyleNameAttribute: eSty
            ]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            guard !ps.isEmpty else {
                let fb = eSty == "Regular" ? eFam : "\(eFam) \(eSty)"
                return (eFam, eSty, fb, fb, "OpenTypeCFF")
            }
            let locFam = (CTFontCopyName(font, kCTFontFamilyNameKey) as String?) ?? eFam
            let locSty = (CTFontCopyName(font, kCTFontStyleNameKey) as String?) ?? eSty
            let full = (CTFontCopyFullName(font) as String?) ?? "\(locFam) \(locSty)"
            return (locFam, locSty, ps, full, fontType(desc))
        }

        /// CoreText 字体格式 → IDML FontType 字符串。系统 CJK 字体(苹方/宋体等)是
        /// OpenType-PostScript(CID)，InDesign 装的就是 OpenTypeCID 变体；填成 CFF 会
        /// 让 InDesign 匹配到不可用的「(OTF)」CFF 变体而判缺失。
        static func fontType(_ desc: CTFontDescriptor) -> String {
            guard let raw = CTFontDescriptorCopyAttribute(desc, kCTFontFormatAttribute) as? NSNumber else {
                return "OpenTypeCFF"
            }
            switch raw.int32Value {
            case 1: return "OpenTypeCID"   // OpenTypePostScript（CID-keyed CJK 系统字体）
            case 2: return "OpenTypeTT"    // OpenTypeTrueType
            case 3: return "TrueType"
            case 4: return "Type1"         // PostScript Type1
            default: return "OpenTypeCFF"
            }
        }

        /// 「家族名 + 样式名」连写拆成 (家族, 样式)——InDesign 按家族名匹配已装字体，
        /// 样式走 FontStyle。只在末词是已知字重/样式词时才拆，"Neue"/"SC" 等家族词不动。
        static func splitFont(_ name: String) -> (String, String) {
            let styleWords: Set<String> = [
                "Thin", "Ultralight", "UltraLight", "Extralight", "ExtraLight", "Light",
                "Regular", "Normal", "Medium", "Semibold", "SemiBold", "Demibold", "DemiBold",
                "Bold", "Heavy", "Black", "Italic", "Oblique"
            ]
            let parts = name.split(separator: " ").map(String.init)
            if parts.count >= 2, let last = parts.last, styleWords.contains(last) {
                return (parts.dropLast().joined(separator: " "), last)
            }
            return (name, "Regular")
        }

        mutating func registerParagraphStyle(_ style: ParagraphStyle) {
            // Project styles are token-resolved by ID. Export-only styles (TOC levels)
            // are already derived from a resolved base and do not exist in the project
            // library; resolving those by ID would silently fall back to `.body`.
            guard !paragraphStyles.contains(where: { $0.id == style.id }) else { return }
            let resolved = project.styles.paragraphStyles.contains(where: { $0.id == style.id })
                ? project.styles.paragraphStyle(id: style.id)
                : style
            paragraphStyles.append(resolved)
            _ = color(textColorHex(project.resolvedColorHex(resolved.colorToken)))
            if let cf = resolved.compositeFont, !cf.isEmpty {
                compositeFontStyleIds.append(resolved.id)
                // 按枚举固定顺序遍历，而非字典自然序——字典迭代顺序非确定，会让
                // Fonts.xml 的家族顺序每次导出都变（golden-file 回归对不上）。
                for cls in CompositeFontClass.allCases {
                    if let m = cf[cls] { font(m.fontName) }
                }
                font(resolved.fontName)
            } else {
                font(resolved.fontName)
            }
        }

        func resolvedStyle(id: String?) -> ParagraphStyle {
            project.styles.paragraphStyle(id: id ?? StyleID.body.rawValue)
        }

        static func normalizeHex(_ hex: String) -> String {
            var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if s.hasPrefix("#") { s.removeFirst() }
            if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
            return s.count == 6 ? s : "000000"
        }
    }

    private func xmlSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "_")
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func fmt(_ d: Double) -> String { String(format: "%.3f", d) }

    // MARK: - 几何

    /// frame.rect(页内左上原点、y 向下）→ 单页 spread 坐标(原点在页中心）。
    private func rectGeometry(_ rect: Rect, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let left = rect.x - pageW / 2 + dx
        let top = rect.y - pageH / 2
        let right = rect.x + rect.width - pageW / 2 + dx
        let bottom = rect.y + rect.height - pageH / 2
        func p(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        <Properties><PathGeometry><GeometryPathType PathOpen="false"><PathPointArray>\
        \(p(left, top))\(p(right, top))\(p(right, bottom))\(p(left, bottom))\
        </PathPointArray></GeometryPathType></PathGeometry></Properties>
        """
    }

    /// 非矩形图框蒙版（E2-5）：把图框路径改成多边形/扇面，图片放满 rect 后被该路径裁切。
    /// `.rect`/nil 回退到矩形。八角=切四角的 8 点；扇面=向上张开的环形扇区（弧线用多段折线近似）。
    private func maskGeometry(_ rect: Rect, shape: ImageMaskShape?, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let left = rect.x - pageW / 2 + dx
        let top = rect.y - pageH / 2
        let right = rect.x + rect.width - pageW / 2 + dx
        let bottom = rect.y + rect.height - pageH / 2
        let w = rect.width, h = rect.height
        var pts: [(Double, Double)] = []
        switch shape {
        case .octagon:
            let c = min(w, h) * 0.30   // 四角各切掉的边长
            pts = [(left + c, top), (right - c, top), (right, top + c), (right, bottom - c),
                   (right - c, bottom), (left + c, bottom), (left, bottom - c), (left, top + c)]
        case .fan:
            let cx = (left + right) / 2
            let half = 35.0 * Double.pi / 180.0           // 扇面半张角
            let ro = w / (2 * sin(half))                  // 外半径：外弧最宽处贴框宽
            let cy = top + ro                             // 圆心在框上方外侧，外弧顶贴框顶
            let ri = max(ro - h, ro * 0.32)               // 内半径：内弧贴框底（过矮则留最小内径）
            let seg = 16
            for i in 0...seg {                            // 外弧 左→右
                let t = -half + 2 * half * Double(i) / Double(seg)
                pts.append((cx + ro * sin(t), cy - ro * cos(t)))
            }
            for i in 0...seg {                            // 内弧 右→左
                let t = half - 2 * half * Double(i) / Double(seg)
                pts.append((cx + ri * sin(t), cy - ri * cos(t)))
            }
        default:
            return rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx)
        }
        let body = pts.map { x, y -> String in
            let a = "\(fmt(x)) \(fmt(y))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }.joined()
        return "<Properties><PathGeometry><GeometryPathType PathOpen=\"false\"><PathPointArray>\(body)</PathPointArray></GeometryPathType></PathGeometry></Properties>"
    }

    // MARK: - 页面项

    private func colorRef(_ raw: String?) -> String {
        guard let raw else { return "Swatch/None" }
        guard let color = PrintColor(string: raw) else { return "Color/Black" }
        return color.idmlSwatchSelf
    }

    private func textFrameItem(self id: String, story: String, rect: Rect,
                               fillColor: String?, strokeColor: String?, strokeWidth: Double,
                               pageW: Double, pageH: Double, dx: Double = 0) -> String {
        """
        \t\t<TextFrame Self="\(id)" ParentStory="\(story)" PreviousTextFrame="n" NextTextFrame="n" ContentType="TextType" FillColor="\(colorRef(fillColor))" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t\t<TextFramePreference TextColumnCount="1" TextColumnGutter="12" VerticalJustification="TopAlign"/>
        \t\t</TextFrame>
        """
    }

    private func colorRectangleItem(self id: String, rect: Rect, fillColor: String,
                                    strokeColor: String? = nil, strokeWidth: Double = 0,
                                    pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let strokeRef = strokeColor.map { colorRef($0) } ?? "Swatch/None"
        let weight = strokeColor != nil ? max(strokeWidth, 0) : 0
        return """
        \t\t<Rectangle Self="\(id)" ContentType="Unassigned" FillColor="\(colorRef(fillColor))" StrokeColor="\(strokeRef)" StrokeWeight="\(fmt(weight))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t</Rectangle>
        """
    }

    /// A drawn line → a real InDesign `GraphicLine` (open path, two anchor points)
    /// carrying an actual `StrokeWeight`/`StrokeColor`. Emitting it as a thin filled
    /// rectangle (the earlier approach) made InDesign report the stroke as 0pt and
    /// left it uneditable as a line. Lines are axis-aligned: horizontal along the
    /// vertical centre when wider than tall, else vertical.
    private func graphicLineItem(self id: String, rect: Rect, strokeColor: String, strokeWidth: Double,
                                 pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let horizontal = rect.width >= rect.height
        let (ax1, ay1, ax2, ay2): (Double, Double, Double, Double) = horizontal
            ? (rect.x, rect.y + rect.height / 2, rect.x + rect.width, rect.y + rect.height / 2)
            : (rect.x + rect.width / 2, rect.y, rect.x + rect.width / 2, rect.y + rect.height)
        func pt(_ x: Double, _ y: Double) -> String {
            let a = "\(fmt(x - pageW / 2 + dx)) \(fmt(y - pageH / 2))"
            return "<PathPointType Anchor=\"\(a)\" LeftDirection=\"\(a)\" RightDirection=\"\(a)\"/>"
        }
        return """
        \t\t<GraphicLine Self="\(id)" ContentType="Unassigned" FillColor="Swatch/None" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t<Properties><PathGeometry><GeometryPathType PathOpen="true"><PathPointArray>\(pt(ax1, ay1))\(pt(ax2, ay2))</PathPointArray></GeometryPathType></PathGeometry></Properties>
        \t\t</GraphicLine>
        """
    }

    /// A drawn shape frame (empty text frame carrying only a fill and/or stroke).
    /// Emitted as an unassigned Rectangle so hand-drawn color boxes survive export
    /// instead of being dropped for having no text.
    private func drawnBoxItem(self id: String, rect: Rect, fillColor: String?, strokeColor: String?,
                              strokeWidth: Double, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        """
        \t\t<Rectangle Self="\(id)" ContentType="Unassigned" FillColor="\(colorRef(fillColor))" StrokeColor="\(colorRef(strokeColor))" StrokeWeight="\(fmt(max(strokeWidth, 0)))" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(rectGeometry(rect, pageW: pageW, pageH: pageH, dx: dx))
        \t\t</Rectangle>
        """
    }

    private func imageItem(self id: String, imageSelf: String, linkSelf: String, asset: Asset, packagedFileName: String?, rect: Rect, maskShape: ImageMaskShape? = nil, pageW: Double, pageH: Double, dx: Double = 0) -> String {
        let natW = Double(max(asset.pixelWidth, 1))
        let natH = Double(max(asset.pixelHeight, 1))
        let sx = rect.width / natW, sy = rect.height / natH
        let effX = Int((72.0 / max(sx, 0.0001)).rounded()), effY = Int((72.0 / max(sy, 0.0001)).rounded())
        let left = rect.x - pageW / 2 + dx, top = rect.y - pageH / 2
        let uri = packagedFileName.map { "file:Links/\($0)" } ?? "file:missing-\(asset.fileName)"
        return """
        \t\t<Rectangle Self="\(id)" ContentType="GraphicType" StoryTitle="$ID/" ItemTransform="1 0 0 1 0 0">
        \t\t\t\(maskGeometry(rect, shape: maskShape, pageW: pageW, pageH: pageH, dx: dx))
        \t\t\t<Image Self="\(imageSelf)" Space="$ID/#Links_RGB" ActualPpi="72 72" EffectivePpi="\(effX) \(effY)" ImageRenderingIntent="UseColorSettings" Visible="true" ItemTransform="\(fmt(sx)) 0 0 \(fmt(sy)) \(fmt(left)) \(fmt(top))">
        \t\t\t\t<Properties>
        \t\t\t\t\t<Profile type="string">$ID/Embedded</Profile>
        \t\t\t\t\t<GraphicBounds Left="0" Top="0" Right="\(fmt(natW))" Bottom="\(fmt(natH))"/>
        \t\t\t\t</Properties>
        \t\t\t\t<Link Self="\(linkSelf)" LinkResourceURI="\(esc(uri))" LinkResourceFormat="$ID/" StoredState="Normal" LinkClientID="257" LinkResourceModificationState="None" LinkObjectModificationState="None" LinkResourceSize="0~0" CanEmbed="true" CanUnembed="true" CanPackage="true" ImportPolicy="NoAutoImport" ShowInUI="true"/>
        \t\t\t</Image>
        \t\t</Rectangle>
        """
    }

    // MARK: - 包内部件

    private func designmap(spreadRefs: [String], storyRefs: [String], storyList: [String]) -> String {
        """
        \(header)
        <?aid style="50" type="document" readerVersion="6.0" featureSet="257" product="16.0(202)" ?>
        <Document \(pkgNS) Self="layoutd_doc" DOMVersion="\(dom)" Name="layoutd-export.indd" StoryList="\(storyList.joined(separator: " "))">
        \t<idPkg:Graphic src="Resources/Graphic.xml"/>
        \t<idPkg:Fonts src="Resources/Fonts.xml"/>
        \t<KinsokuTable Self="KinsokuTable/$ID/kSimpChineseKinsokuName" Name="$ID/kSimpChineseKinsokuName"/>
        \t<idPkg:Styles src="Resources/Styles.xml"/>
        \t<idPkg:Preferences src="Resources/Preferences.xml"/>
        \t<idPkg:Tags src="XML/Tags.xml"/>
        \t<idPkg:MasterSpread src="MasterSpreads/MasterSpread_uMasterA.xml"/>
        \(spreadRefs.joined(separator: "\n"))
        \t<idPkg:BackingStory src="XML/BackingStory.xml"/>
        \(storyRefs.joined(separator: "\n"))
        </Document>
        """
    }

    private func container() -> String {
        """
        \(header)
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        \t<rootfiles><rootfile full-path="designmap.xml" media-type="text/xml"/></rootfiles>
        </container>
        """
    }

    private func metadata() -> String {
        """
        \(header)
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        \t<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        \t\t<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:format>application/x-indesign</dc:format></rdf:Description>
        \t</rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func graphic(ctx: BuildContext) -> String {
        var colors = ""
        for key in ctx.colorOrder where key != "000000" {
            guard let color = PrintColor(string: key) else { continue }
            // Under a CMYK output intent, emit this swatch as Process CMYK
            // (Space/Value/Name) while keeping its Self keyed on the stored color,
            // so every FillColor/StrokeColor reference still resolves.
            let emitted = ctx.cmykOutput ? color.asCMYK : color
            let (space, value) = emitted.idmlSpaceValue
            colors += "\t<Color Self=\"\(color.idmlSwatchSelf)\" Model=\"Process\" Space=\"\(space)\" ColorValue=\"\(value)\" ColorOverride=\"Normal\" AlternateSpace=\"NoAlternateColor\" AlternateColorValue=\"\" Name=\"\(esc(emitted.idmlSwatchName))\" ColorEditable=\"true\" ColorRemovable=\"true\" Visible=\"true\" SwatchCreatorID=\"7937\"/>\n"
        }
        return """
        \(header)
        <idPkg:Graphic \(pkgNS) DOMVersion="\(dom)">
        \t<Color Self="Color/Paper" Model="Process" Space="CMYK" ColorValue="0 0 0 0" ColorOverride="Specialpaper" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Paper" ColorEditable="true" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Black" Model="Process" Space="CMYK" ColorValue="0 0 0 100" ColorOverride="Specialblack" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Black" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \t<Color Self="Color/Registration" Model="Registration" Space="CMYK" ColorValue="100 100 100 100" ColorOverride="Specialregistration" AlternateSpace="NoAlternateColor" AlternateColorValue="" Name="Registration" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937"/>
        \(colors)\t<Swatch Self="Swatch/None" Name="None" ColorEditable="false" ColorRemovable="false" Visible="true" SwatchCreatorID="7937" SwatchColorGroupReference="n"/>
        \t<Ink Self="Ink/$ID/Process Cyan" Name="$ID/Process Cyan" AngleForSeparation="75" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.61" PrintInk="true" TrapOrder="1" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Magenta" Name="$ID/Process Magenta" AngleForSeparation="15" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.76" PrintInk="true" TrapOrder="2" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Yellow" Name="$ID/Process Yellow" AngleForSeparation="0" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="0.16" PrintInk="true" TrapOrder="3" InkAlias=""/>
        \t<Ink Self="Ink/$ID/Process Black" Name="$ID/Process Black" AngleForSeparation="45" ConvertToProcess="false" Frequency="70" IsProcessInk="true" NeutralDensity="1.7" PrintInk="true" TrapOrder="4" InkAlias=""/>
        </idPkg:Graphic>
        """
    }

    private func fonts(ctx: BuildContext) -> String {
        var families = ""
        for (i, family) in ctx.fontOrder.enumerated() {
            var fontChildren = ""
            let styles = ctx.fontStyles[family] ?? [(style: "Regular", ps: family, full: family, type: "OpenTypeCFF")]
            for (j, entry) in styles.enumerated() {
                fontChildren += "\t\t<Font Self=\"dFont\(i)_\(j)\" FontFamily=\"\(esc(family))\" Name=\"\(esc(entry.full))\" PostScriptName=\"\(esc(entry.ps))\" Status=\"Installed\" FontStyleName=\"\(esc(entry.style))\" FontType=\"\(entry.type)\" WritingScript=\"0\" FullName=\"\(esc(entry.full))\" FullNameNative=\"\(esc(entry.full))\" FontStyleNameNative=\"\(esc(entry.style))\" PlatformName=\"$ID/\" Version=\"\" TypekitID=\"$ID/\"/>\n"
            }
            families += "\t<FontFamily Self=\"dFontFamily\(i)\" Name=\"\(esc(family))\">\n\(fontChildren)\t</FontFamily>\n"
        }
        var composites = ""
        for sid in ctx.compositeFontStyleIds {
            guard let style = ctx.paragraphStyles.first(where: { $0.id == sid }), let cf = style.compositeFont else { continue }
            let cjk = cf[.chinese]?.fontName ?? style.fontName
            let latin = cf[.latin]?.fontName ?? style.fontName
            let digit = cf[.digit]?.fontName ?? latin
            let name = "CF_\(xmlSafe(sid))"
            func entry(_ slug: String, _ ename: String, _ font: String) -> String {
                let family = ctx.appliedFamily[font] ?? BuildContext.splitFont(font).0
                let fstyle = ctx.appliedStyle[font] ?? BuildContext.splitFont(font).1
                return """
                \t<CompositeFontEntry Self="CompositeFont/\(name)/\(slug)" Name="\(ename)" FontStyle="\(esc(fstyle))" RelativeSize="100" HorizontalScale="100" VerticalScale="100" BaselineShift="0" Locked="false" ScaleOption="false" CustomCharacters="">
                \t\t<Properties><AppliedFont type="string">\(esc(family))</AppliedFont></Properties>
                \t</CompositeFontEntry>
                """
            }
            composites += """
            \t<CompositeFont Self="CompositeFont/\(name)" Name="\(name)">
            \(entry("漢字", "漢字", cjk))
            \(entry("かな", "かな", cjk))
            \(entry("全角約物", "全角約物", cjk))
            \(entry("全角記号", "全角記号", cjk))
            \(entry("半角欧文", "半角欧文", latin))
            \(entry("半角数字", "半角数字", digit))
            \t</CompositeFont>\n
            """
        }
        return """
        \(header)
        <idPkg:Fonts \(pkgNS) DOMVersion="\(dom)">
        \(families)\(composites)</idPkg:Fonts>
        """
    }

    private func tocParagraphStyle(base: ParagraphStyle, id: String, name: String, indent: Double = 0) -> ParagraphStyle {
        var style = base
        style.id = id
        style.displayName = name
        style.firstLineIndent = indent
        style.spaceBefore = 0
        style.spaceAfter = 2
        return style
    }

    private func styles(ctx: BuildContext, includesTOC: Bool) -> String {
        var paras = ""
        for style in ctx.paragraphStyles {
            let colorHex = ctx.textColorHex(ctx.project.resolvedColorHex(style.colorToken))
            let fill = PrintColor(string: colorHex)?.idmlSwatchSelf ?? "Color/Black"
            let isComposite = style.compositeFont?.isEmpty == false
            let famFallback = ctx.appliedFamily[style.fontName] ?? BuildContext.splitFont(style.fontName).0
            let styleFallback = ctx.appliedStyle[style.fontName] ?? BuildContext.splitFont(style.fontName).1
            let applied = isComposite ? "CF_\(xmlSafe(style.id))" : famFallback
            let fontStyleAttr = isComposite ? "" : " FontStyle=\"\(esc(styleFallback))\""
            paras += """
            \t\t<ParagraphStyle Self="ParagraphStyle/\(xmlSafe(style.id))" Imported="false" Name="\(esc(style.displayName))" PointSize="\(fmt(style.fontSize))" Leading="\(fmt(style.lineHeight))" FirstLineIndent="\(fmt(style.firstLineIndent))" SpaceBefore="\(fmt(style.spaceBefore))" SpaceAfter="\(fmt(style.spaceAfter))" FillColor="\(fill)"\(fontStyleAttr) Composer="\(composer)" Justification="LeftJustified" KinsokuType="KinsokuPushInFirst" KinsokuHangType="None">
            \t\t\t<Properties>
            \t\t\t\t<BasedOn type="object">ParagraphStyle/$ID/[No paragraph style]</BasedOn>
            \t\t\t\t<PreviewColor type="enumeration">Nothing</PreviewColor>
            \t\t\t\t<AppliedFont type="string">\(esc(applied))</AppliedFont>
            \t\t\t\t<KinsokuSet type="enumeration">SimplifiedChineseKinsoku</KinsokuSet>
            \t\t\t</Properties>
            \t\t</ParagraphStyle>\n
            """
        }
        let tocStyle = includesTOC ? """
        \t\t<TOCStyle Self="TOCStyle/layoutD_TOC" Name="目录" IncludeBookDocuments="false" CreateBookmarks="true" ReplaceExisting="true">
        \t\t\t<TOCStyleEntry Self="TOCStyleEntry/layoutD_TOC_heading1" AppliedParagraphStyle="ParagraphStyle/heading1" TOCEntryStyle="ParagraphStyle/tocLevel1" IncludePageNumber="true" PageNumberPosition="AfterEntry"/>
        \t\t\t<TOCStyleEntry Self="TOCStyleEntry/layoutD_TOC_heading2" AppliedParagraphStyle="ParagraphStyle/heading2" TOCEntryStyle="ParagraphStyle/tocLevel2" IncludePageNumber="true" PageNumberPosition="AfterEntry"/>
        \t\t</TOCStyle>
        """ : ""
        return """
        \(header)
        <idPkg:Styles \(pkgNS) DOMVersion="\(dom)">
        \t<RootCharacterStyleGroup Self="u_rcsg">
        \t\t<CharacterStyle Self="CharacterStyle/$ID/[No character style]" Imported="false" Name="$ID/[No character style]"/>
        \t</RootCharacterStyleGroup>
        \t<RootParagraphStyleGroup Self="u_rpsg">
        \t\t<ParagraphStyle Self="ParagraphStyle/$ID/[No paragraph style]" Imported="false" Name="$ID/[No paragraph style]" Composer="\(composer)"/>
        \(paras)\t</RootParagraphStyleGroup>
        \(tocStyle)
        \t<RootCellStyleGroup Self="u_rcellsg"><CellStyle Self="CellStyle/$ID/[None]" Name="$ID/[None]"/></RootCellStyleGroup>
        \t<RootTableStyleGroup Self="u_rtsg"><TableStyle Self="TableStyle/$ID/[No table style]" Name="$ID/[No table style]"/></RootTableStyleGroup>
        \t<RootObjectStyleGroup Self="u_rosg"><ObjectStyle Self="ObjectStyle/$ID/[None]" Name="$ID/[None]"/></RootObjectStyleGroup>
        </idPkg:Styles>
        """
    }

    private func preferences(pageW: Double, pageH: Double, pageCount: Int, facing: Bool) -> String {
        // 逐字段对齐 InDesign 自身导出的「非对开」IDML。关键:PagesPerDocument 是
        // “新建文档默认页数”偏好(InDesign 恒写 1),不是实际页数——填成实际页数会让
        // InDesign 误判、插空白页。实际页数由 spread 数量决定。
        // FacingPages 随导出选项切换：对开时 true（页框已按 verso 左/recto 右放好）。
        """
        \(header)
        <idPkg:Preferences \(pkgNS) DOMVersion="\(dom)">
        \t<DocumentPreference PageHeight="\(fmt(pageH))" PageWidth="\(fmt(pageW))" PagesPerDocument="1" FacingPages="\(facing)" DocumentBleedTopOffset="0" DocumentBleedBottomOffset="0" DocumentBleedInsideOrLeftOffset="0" DocumentBleedOutsideOrRightOffset="0" DocumentBleedUniformSize="true" SlugTopOffset="0" SlugBottomOffset="0" SlugInsideOrLeftOffset="0" SlugRightOrOutsideOffset="0" DocumentSlugUniformSize="false" PreserveLayoutWhenShuffling="true" AllowPageShuffle="true" OverprintBlack="true" PageBinding="LeftToRight" ColumnDirection="Horizontal" SpreadHiddenVisibility="false" Intent="PrintIntent" CreatePrimaryTextFrame="false" ColumnGuideLocked="true" MasterTextFrame="false" SnippetImportUsesOriginalLocation="false"/>
        \t<ViewPreference HorizontalMeasurementUnits="Points" VerticalMeasurementUnits="Points" RulerOrigin="PageOrigin"/>
        \t<TextDefault Composer="\(composer)" AppliedLanguage="$ID/Chinese: Simplified" KinsokuType="KinsokuPushInFirst"/>
        </idPkg:Preferences>
        """
    }

    private func tags() -> String {
        """
        \(header)
        <idPkg:Tags \(pkgNS) DOMVersion="\(dom)">
        \t<XMLTag Self="XMLTag/Root" Name="Root"><Properties><TagColor type="enumeration">LightBlue</TagColor></Properties></XMLTag>
        </idPkg:Tags>
        """
    }

    private func backingStory() -> String {
        """
        \(header)
        <idPkg:BackingStory \(pkgNS) DOMVersion="\(dom)">
        \t<XmlStory Self="u_backing" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t</XmlStory>
        </idPkg:BackingStory>
        """
    }

    private func masterSpread(pageW: Double, pageH: Double) -> String {
        """
        \(header)
        <idPkg:MasterSpread \(pkgNS) DOMVersion="\(dom)">
        \t<MasterSpread Self="uMasterA" Name="A-Master" NamePrefix="A" BaseName="主页" ShowMasterItems="true" PageCount="1" OverriddenPageItemProps="">
        \t\t<Page Self="uMasterApage" Name="A" AppliedMaster="n" MasterPageTransform="1 0 0 1 0 0" GeometricBounds="0 0 \(fmt(pageH)) \(fmt(pageW))" ItemTransform="1 0 0 1 \(fmt(-pageW/2)) \(fmt(-pageH/2))"/>
        \t</MasterSpread>
        </idPkg:MasterSpread>
        """
    }

    private func spreadXML(self id: String, spreadY: Double, pageW: Double, pageH: Double,
                           pages: [(pageSelf: String, pageName: String, transformX: Double, items: [String])]) -> String {
        // 每个 spread 在粘贴板上纵向错开(spreadY)，对齐 InDesign 自身做法；
        // 全部叠在原点会让 InDesign 重新分页、插空白页。
        // 非对开：1 页/spread，transformX=0（页框居中于书脊原点，与历史一致）。
        // 对开：2 页/spread（verso transformX=-pageW 左、recto transformX=0 右），BindingLocation=1。
        let pageElements = pages.map { p in
            "\t\t<Page Self=\"\(p.pageSelf)\" Name=\"\(p.pageName)\" AppliedMaster=\"uMasterA\" MasterPageTransform=\"1 0 0 1 0 0\" GeometricBounds=\"0 0 \(fmt(pageH)) \(fmt(pageW))\" ItemTransform=\"1 0 0 1 \(fmt(p.transformX)) \(fmt(-pageH / 2))\" LayoutRule=\"UseMaster\" OverrideList=\"\"/>"
        }.joined(separator: "\n")
        let allItems = pages.flatMap(\.items).joined(separator: "\n")
        let bindingLocation = pages.count > 1 ? 1 : 0
        return """
        \(header)
        <idPkg:Spread \(pkgNS) DOMVersion="\(dom)">
        \t<Spread Self="\(id)" PageTransitionType="None" PageTransitionDirection="NotApplicable" PageTransitionDuration="Medium" ShowMasterItems="true" PageCount="\(pages.count)" BindingLocation="\(bindingLocation)" SpreadHidden="false" AllowPageShuffle="true" ItemTransform="1 0 0 1 0 \(fmt(spreadY))" FlattenerOverride="Default">
        \(pageElements)
        \(allItems)
        \t</Spread>
        </idPkg:Spread>
        """
    }

    private func inlineRuns(for frameText: String, from paragraph: Paragraph) -> [InlineRun]? {
        guard let paragraphRuns = paragraph.inlineRuns, !paragraphRuns.isEmpty else { return nil }
        let sourceCharacters = Array(paragraph.text)
        let frameCharacters = Array(frameText)
        let sourceVisible = sourceCharacters.enumerated().filter { !$0.element.isWhitespace }
        let frameVisible = frameCharacters.enumerated().filter { !$0.element.isWhitespace }
        guard !frameVisible.isEmpty, frameVisible.count <= sourceVisible.count else { return nil }

        let matchingStart = (0...(sourceVisible.count - frameVisible.count)).first { candidate in
            zip(sourceVisible[candidate...], frameVisible).allSatisfy { pair in
                pair.0.element == pair.1.element
            }
        }
        guard let matchingStart else { return nil }

        var emphasisByFrameCharacter = Array(repeating: Set<InlineEmphasis>(), count: frameCharacters.count)
        for (visibleOffset, frameCharacter) in frameVisible.enumerated() {
            let sourceOffset = sourceVisible[matchingStart + visibleOffset].offset
            for run in paragraphRuns where run.location <= sourceOffset && sourceOffset < run.location + run.length {
                emphasisByFrameCharacter[frameCharacter.offset].formUnion(run.emphasis)
            }
        }

        var runs: [InlineRun] = []
        var start: Int?
        var active = Set<InlineEmphasis>()
        for offset in 0...emphasisByFrameCharacter.count {
            let emphasis = offset < emphasisByFrameCharacter.count ? emphasisByFrameCharacter[offset] : []
            if emphasis != active {
                if let start, !active.isEmpty {
                    runs.append(InlineRun(location: start, length: offset - start, emphasis: active))
                }
                start = emphasis.isEmpty ? nil : offset
                active = emphasis
            }
        }
        return runs.isEmpty ? nil : runs
    }

    private func storyXML(
        self id: String,
        styleRef: String,
        vertical: Bool,
        text: String,
        inlineRuns: [InlineRun]? = nil,
        footnotes: [Paragraph] = [],
        footnoteStyleRef: String = "ParagraphStyle/$ID/[No paragraph style]"
    ) -> String {
        let orientation = vertical ? "Vertical" : "Horizontal"
        let direction = vertical ? "RightToLeftDirection" : "LeftToRightDirection"
        // 每个非空行作为一个段落（ParagraphStyleRange）。
        var lineStart = 0
        let paragraphs = text.components(separatedBy: "\n").compactMap { rawLine -> (String, Int)? in
            defer { lineStart += rawLine.count + 1 }
            let leading = rawLine.prefix { $0.isWhitespace }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : (line, lineStart + leading)
        }
        let effectiveParagraphs = paragraphs.isEmpty ? [(text, 0)] : paragraphs
        let body = effectiveParagraphs.map { line, start in
            """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
            \(characterStyleRanges(for: line, globalStart: start, inlineRuns: inlineRuns ?? [], footnotes: footnotes, footnoteStyleRef: footnoteStyleRef))
            \t\t</ParagraphStyleRange>
            """
        }.joined(separator: "\n")
        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="\(orientation)" StoryDirection="\(direction)"/>
        \(body)
        \t</Story>
        </idPkg:Story>
        """
    }

    private func characterStyleRanges(
        for text: String,
        globalStart: Int,
        inlineRuns: [InlineRun],
        footnotes: [Paragraph] = [],
        footnoteStyleRef: String = "ParagraphStyle/$ID/[No paragraph style]"
    ) -> String {
        guard !footnotes.isEmpty else {
            return styledCharacterRanges(for: text, globalStart: globalStart, inlineRuns: inlineRuns)
        }

        // Markdown importer 已把 [^id] 替换为对应的 Unicode 上标，并以出现顺序保存
        // anchoredFootnoteIds。将该上标替换成 Footnote，交由 InDesign 的 FootnoteOption
        // 自动绘制编号；未命中的文本仍走既有行内样式导出。
        let characters = Array(text)
        var cursor = 0
        var output = ""
        for footnote in footnotes {
            guard let marker = footnoteMarker(for: footnote), !marker.isEmpty,
                  let markerStart = firstMatch(of: Array(marker), in: characters, from: cursor) else {
                continue
            }
            if markerStart > cursor {
                output += styledCharacterRanges(
                    for: String(characters[cursor..<markerStart]),
                    globalStart: globalStart + cursor,
                    inlineRuns: inlineRuns
                )
            }
            output += footnoteXML(footnote, styleRef: footnoteStyleRef)
            cursor = markerStart + marker.count
        }
        if cursor < characters.count {
            output += styledCharacterRanges(
                for: String(characters[cursor...]),
                globalStart: globalStart + cursor,
                inlineRuns: inlineRuns
            )
        }
        return output
    }

    private func styledCharacterRanges(for text: String, globalStart: Int, inlineRuns: [InlineRun]) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }
        var styles = Array(repeating: Set<InlineEmphasis>(), count: characters.count)
        for run in inlineRuns {
            let start = max(0, run.location - globalStart)
            let end = min(characters.count, run.location + run.length - globalStart)
            guard start < end else { continue }
            for index in start..<end { styles[index].formUnion(run.emphasis) }
        }

        var ranges: [(String, Set<InlineEmphasis>)] = []
        var start = 0
        for index in 1...characters.count where index == characters.count || styles[index] != styles[start] {
            ranges.append((String(characters[start..<index]), styles[start]))
            start = index
        }
        return ranges.map { content, emphasis in
            // 粗体用 FauxBold（算法加粗），斜体用 Skew（切变倾斜角）而非 FontStyle 字符串：
            // FontStyle="Bold"/"Italic" 要求 Fonts.xml 里真有同名字重/斜体的字体资源，否则
            // InDesign 找不到，会用替代字形顶上（视觉上是粉色高亮，等于没生效）。
            // 中文宋体等常既没有 Bold 也没有 Italic 变体。
            // 注意：FauxItalic="true" 实测在 InDesign 里对 CJK 不出可见倾斜，必须用 Skew
            //（伪斜体/切变，单位度）才稳定可见；12° 是 InDesign 伪斜体常用值。
            var attrs = ""
            if emphasis.contains(.bold) { attrs += " FauxBold=\"true\"" }
            if emphasis.contains(.italic) { attrs += " Skew=\"12\"" }
            if emphasis.contains(.kenten) {
                // 着重号按中文习惯：实心黑圆点 ● 置于字下方（KentenBlackCircle + BelowLeft）。
                // 经真·InDesign 2026 存盘比对(Desktop/未命名-1.idml kenten golden, 2026-06-23):
                // 真值字符级只写这三个属性, 且 KentenAlignment 是段落级、不写在 CharacterStyleRange 上。
                // 此前用日文习惯(KentenSesameDot 芝麻点 + AboveRight 字上方)——中文书不对。
                attrs += " KentenKind=\"KentenBlackCircle\""
                attrs += " KentenPlacement=\"-1\""
                attrs += " KentenPosition=\"BelowLeft\""
            }
            return "\t\t\t<CharacterStyleRange AppliedCharacterStyle=\"CharacterStyle/$ID/[No character style]\"\(attrs)><Content>\(esc(content))</Content></CharacterStyleRange>"
        }.joined(separator: "\n")
    }

    private func footnoteXML(_ paragraph: Paragraph, styleRef: String) -> String {
        let body = styledCharacterRanges(
            for: paragraph.text,
            globalStart: 0,
            inlineRuns: paragraph.inlineRuns ?? []
        )
        // 脚注也是 CJK 段落，统一用 World-Ready 排版器（与正文一致）：对纯脚注无害，
        // 又能在脚注内出现着重号/避头尾时正确排版。
        return """
        \t\t\t<Footnote>
        \t\t\t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
        \(body)
        \t\t\t\t</ParagraphStyleRange>
        \t\t\t</Footnote>
        """
    }

    /// 原生 IDML 表格 Story。InDesign 的 <Table> 子元素顺序固定：先全部 <Column>，
    /// 再全部 <Row>，最后全部 <Cell>（Cell 不嵌在 Row 里，靠 Name="列:行" 定位）。
    /// 第一行视为表头。列宽按框宽均分；单元格四边给 0.5pt 黑边，使其在 InDesign 里
    /// 一眼是真表格。单元格文字复用 styledCharacterRanges，并与正文一样带 World-Ready 排版器。
    private func tableStoryXML(self id: String, styleRef: String, cells: [[String]], cellRuns: [[[InlineRun]]]? = nil, frameWidth: Double, cellFillSwatch: String? = nil) -> String {
        let rowCount = cells.count
        let columnCount = cells.map(\.count).max() ?? 0
        guard rowCount > 0, columnCount > 0 else {
            return storyXML(self: id, styleRef: styleRef, vertical: false, text: "")
        }
        let headerRowCount = 1
        let bodyRowCount = rowCount - headerRowCount
        let columnWidth = frameWidth > 0 ? frameWidth / Double(columnCount) : 80
        let rowHeight = 18.0
        let tableSelf = "\(id)_tbl"

        let columns = (0..<columnCount).map { c in
            "\t\t\t\t\t<Column Self=\"\(tableSelf)Col\(c)\" Name=\"\(c)\" SingleColumnWidth=\"\(fmt(columnWidth))\"/>"
        }.joined(separator: "\n")

        let rows = (0..<rowCount).map { r in
            let rowType = r < headerRowCount ? "HeaderRow" : "BodyRow"
            return "\t\t\t\t\t<Row Self=\"\(tableSelf)Row\(r)\" Name=\"\(r)\" SingleRowHeight=\"\(fmt(rowHeight))\" RowType=\"\(rowType)\"/>"
        }.joined(separator: "\n")

        // 四边 0.5pt 黑边 + 2pt 内边距（与 LayoutEngine.estimatedTableHeight 的 cellInset 一致，
        // 否则估高与 InDesign 实际折行不符会溢流）。
        let border = "TopEdgeStrokeWeight=\"0.5\" BottomEdgeStrokeWeight=\"0.5\" LeftEdgeStrokeWeight=\"0.5\" RightEdgeStrokeWeight=\"0.5\" TopEdgeStrokeColor=\"Color/Black\" BottomEdgeStrokeColor=\"Color/Black\" LeftEdgeStrokeColor=\"Color/Black\" RightEdgeStrokeColor=\"Color/Black\" TopInset=\"2\" BottomInset=\"2\" LeftInset=\"2\" RightInset=\"2\""
        // 底色挂在单元格（而非整框）上，使色块正好贴合表格。
        let fillAttr = cellFillSwatch.map { " FillColor=\"\($0)\"" } ?? ""
        var cellsXML: [String] = []
        for r in 0..<rowCount {
            for c in 0..<columnCount {
                let content = c < cells[r].count ? cells[r][c] : ""
                // 该格的行内格式（粗/斜/傍点），偏移针对该格文本；缺则空（纯文字）。
                let runs: [InlineRun] = (cellRuns.flatMap { r < $0.count && c < $0[r].count ? $0[r][c] : nil }) ?? []
                let cellBody = styledCharacterRanges(for: content, globalStart: 0, inlineRuns: runs)
                cellsXML.append("""
                \t\t\t\t\t<Cell Self="\(tableSelf)Cell\(c)_\(r)" Name="\(c):\(r)" RowSpan="1" ColumnSpan="1" AppliedCellStyle="CellStyle/$ID/[None]"\(fillAttr) \(border)>
                \t\t\t\t\t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)" FirstLineIndent="0" Justification="LeftJustified">
                \(cellBody)
                \t\t\t\t\t\t</ParagraphStyleRange>
                \t\t\t\t\t</Cell>
                """)
            }
        }

        let table = """
        \t\t\t\t<Table Self="\(tableSelf)" AppliedTableStyle="TableStyle/$ID/[No table style]" HeaderRowCount="\(headerRowCount)" FooterRowCount="0" BodyRowCount="\(bodyRowCount)" ColumnCount="\(columnCount)">
        \(columns)
        \(rows)
        \(cellsXML.joined(separator: "\n"))
        \t\t\t\t</Table>
        """

        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="n" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \t\t<ParagraphStyleRange AppliedParagraphStyle="\(styleRef)">
        \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]">
        \(table)
        \t\t\t\t<Content></Content>
        \t\t\t</CharacterStyleRange>
        \t\t</ParagraphStyleRange>
        \t</Story>
        </idPkg:Story>
        """
    }

    /// 目录 Story：每条是独立段落，标题和页码之间是右对齐 tab（点导引线由对应 TOC
    /// 段落样式/TOCStyle 接管）。AppliedTOCStyle 让 InDesign 的“更新目录”按 heading1/
    /// heading2 重建目录，当前条目仅用于首次打开时的可见版面。
    private func tocStoryXML(self id: String, entries: [TableOfContentsEntry], frameWidth: Double) -> String {
        // 制表位（右对齐 + 点导引线）必须用嵌套 <Properties><TabList><ListItem>，
        // 不能用 ParagraphStyleRange 的扁平属性——InDesign 会静默忽略扁平属性，
        // 导致页码不右对齐、无点导引线（属性在、视觉无）。Position 略减 6pt 留切口边距。
        let tabPosition = max(frameWidth - 6.0, 0)
        let tabList = """
        \t\t\t<Properties>
        \t\t\t\t<TabList type="list">
        \t\t\t\t\t<ListItem type="record">
        \t\t\t\t\t\t<Alignment type="enumeration">RightAlign</Alignment>
        \t\t\t\t\t\t<AlignmentCharacter type="string">.</AlignmentCharacter>
        \t\t\t\t\t\t<Leader type="string">.</Leader>
        \t\t\t\t\t\t<Position type="unit">\(fmt(tabPosition))</Position>
        \t\t\t\t\t</ListItem>
        \t\t\t\t</TabList>
        \t\t\t</Properties>
        """
        // 一个 story 里多段并存时，IDML 必须有显式段落分隔符（<Content> 内的字面换行
        // U+000A，InDesign 读作段落回车）；否则多个 ParagraphStyleRange 会被并成一段、
        // 各条目录的 tab/页码串行到同一段里（实测 InDesign 现象）。末条不加，避免空段。
        let body = entries.enumerated().map { index, entry in
            let style = entry.level <= 1 ? "tocLevel1" : "tocLevel2"
            let paragraphBreak = index < entries.count - 1 ? "\n" : ""
            return """
            \t\t<ParagraphStyleRange AppliedParagraphStyle="ParagraphStyle/\(style)">
            \(tabList)
            \t\t\t<CharacterStyleRange AppliedCharacterStyle="CharacterStyle/$ID/[No character style]"><Content>\(esc(entry.title))\t\(entry.pageNumber)\(paragraphBreak)</Content></CharacterStyleRange>
            \t\t</ParagraphStyleRange>
            """
        }.joined(separator: "\n")
        return """
        \(header)
        <idPkg:Story \(pkgNS) DOMVersion="\(dom)">
        \t<Story Self="\(id)" AppliedTOCStyle="TOCStyle/layoutD_TOC" TrackChanges="false" StoryTitle="$ID/" AppliedNamedGrid="n">
        \t\t<StoryPreference OpticalMarginAlignment="false" OpticalMarginSize="12" FrameType="TextFrameType" StoryOrientation="Horizontal" StoryDirection="LeftToRightDirection"/>
        \(body)
        \t</Story>
        </idPkg:Story>
        """
    }

    private func footnoteMarker(for paragraph: Paragraph) -> String? {
        guard case .footnote(let number) = paragraph.kind else { return nil }
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        return String(number).compactMap { digits[$0] }.map(String.init).joined()
    }

    private func firstMatch(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        for index in start...(haystack.count - needle.count) where Array(haystack[index..<(index + needle.count)]) == needle {
            return index
        }
        return nil
    }

    // MARK: - 打包（纯 Swift ZIP32；mimetype store-first）

    private func writePackage(files: [String: String], to outputURL: URL) throws {
        let orderedPaths = ["mimetype"] + files.keys.filter { $0 != "mimetype" }.sorted()
        let entries = orderedPaths.compactMap { path -> ZIPArchiveWriter.Entry? in
            guard let content = files[path] else { return nil }
            return ZIPArchiveWriter.Entry(path: path, data: Data(content.utf8))
        }
        try ZIPArchiveWriter.write(entries: entries, to: outputURL)
    }
}

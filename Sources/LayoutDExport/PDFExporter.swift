import AppKit
import CoreText
import Foundation
import LayoutDCore
import LayoutDEngine

public enum PDFExportError: Error, LocalizedError {
    case couldNotCreateContext

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateContext:
            return "无法创建 PDF 绘制上下文"
        }
    }
}

public enum PDFXVersion: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case pdfx1a = "RGB + SWOP intent"
    case pdfx3 = "RGB + FOGRA39 intent"

    /// Short PDF/X standard name this output intent *resembles* but is not compliant
    /// with — used for honest preflight disclosure messages. `rawValue` stays the
    /// human-facing UI label (and is persisted / CLI-parsed), so it must not carry this.
    public var pdfxStandardName: String? {
        switch self {
        case .none: return nil
        case .pdfx1a: return "PDF/X-1a"
        case .pdfx3: return "PDF/X-3"
        }
    }
}

public struct PDFExporter {
    public init() {}

    public func export(
        document: LaidOutDocument,
        project: BookProject,
        to url: URL,
        pageRange: String? = nil,
        drawCropMarks: Bool = false,
        drawGridGuides: Bool = false,
        pdfxVersion: PDFXVersion = .none
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let pageSize = CGSize(
            width: CGFloat(project.pageSetup.pageSize.width),
            height: CGFloat(project.pageSetup.pageSize.height)
        )
        
        let maxPages = document.pages.count
        let pagesToExport = ExportPageRange.parse(pageRange, maxPages: maxPages)
        
        let bleedMM = project.pageSetup.bleedMM ?? 3.0
        let bleedPoints = CGFloat(bleedMM * 72.0 / 25.4)
        let cropMarkMargin: CGFloat = 20.0
        let extraOffset = drawCropMarks ? (bleedPoints + cropMarkMargin) : 0.0
        
        let mediaWidth = pageSize.width + 2 * extraOffset
        let mediaHeight = pageSize.height + 2 * extraOffset
        
        var auxiliaryInfo: [CFString: Any] = [
            kCGPDFContextTitle: project.metadata.title as CFString,
            kCGPDFContextAuthor: project.metadata.author as CFString
        ]

        if pdfxVersion != .none {
            var outputIntent = [CFString: Any]()
            outputIntent[kCGPDFXRegistryName] = "http://www.color.org" as CFString
            outputIntent[kCGPDFXOutputIntentSubtype] = "GTS_PDFX" as CFString
            
            if pdfxVersion == .pdfx1a {
                outputIntent[kCGPDFXOutputConditionIdentifier] = "CGATS TR 001" as CFString
                outputIntent[kCGPDFXOutputCondition] = "CGATS TR 001 (SWOP)" as CFString
            } else if pdfxVersion == .pdfx3 {
                outputIntent[kCGPDFXOutputConditionIdentifier] = "FOGRA39" as CFString
                outputIntent[kCGPDFXOutputCondition] = "Coated FOGRA39" as CFString
            }
            
            // Try to load local system CMYK profile
            let profilePath = "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc"
            if FileManager.default.fileExists(atPath: profilePath),
               let iccData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
               let profileSpace = CGColorSpace(iccData: iccData as CFData) {
                outputIntent[kCGPDFXDestinationOutputProfile] = profileSpace
            }
            
            auxiliaryInfo[kCGPDFContextOutputIntent] = outputIntent as CFDictionary
        }

        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: mediaWidth, height: mediaHeight)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliaryInfo as CFDictionary) else {
            throw PDFExportError.couldNotCreateContext
        }

        let sortedPages = document.pages.sorted(by: { $0.number < $1.number })

        func cgRectToData(_ rect: CGRect) -> CFData {
            var r = rect
            return Data(bytes: &r, count: MemoryLayout<CGRect>.size) as CFData
        }

        for page in sortedPages {
            guard pagesToExport.contains(page.number) else {
                continue
            }
            
            let pageInfo = NSMutableDictionary()
            let mediaBoxRect = CGRect(x: 0, y: 0, width: mediaWidth, height: mediaHeight)
            pageInfo[kCGPDFContextMediaBox] = cgRectToData(mediaBoxRect)
            
            let trimBoxRect = CGRect(
                x: extraOffset,
                y: extraOffset,
                width: pageSize.width,
                height: pageSize.height
            )
            pageInfo[kCGPDFContextTrimBox] = cgRectToData(trimBoxRect)
            
            let bleedBoxRect = CGRect(
                x: drawCropMarks ? cropMarkMargin : 0,
                y: drawCropMarks ? cropMarkMargin : 0,
                width: pageSize.width + 2 * bleedPoints,
                height: pageSize.height + 2 * bleedPoints
            )
            pageInfo[kCGPDFContextBleedBox] = cgRectToData(bleedBoxRect)
            pageInfo[kCGPDFContextCropBox] = cgRectToData(mediaBoxRect)
            
            context.beginPDFPage(pageInfo as CFDictionary)
            
            context.saveGState()
            if extraOffset > 0 {
                context.translateBy(x: extraOffset, y: extraOffset)
            }
            
            draw(page: page, project: project, in: context, bleedPoints: drawCropMarks ? bleedPoints : 0.0)
            
            context.restoreGState()
            
            if drawCropMarks {
                drawCropMarksAndBleeds(in: context, trimSize: pageSize, bleedPoints: bleedPoints, cropMargin: cropMarkMargin)
            }
            
            if drawGridGuides {
                context.saveGState()
                if extraOffset > 0 {
                    context.translateBy(x: extraOffset, y: extraOffset)
                }
                drawGridAndMarginGuides(in: context, pageNumber: page.number, project: project, pageSize: pageSize)
                context.restoreGState()
            }
            
            context.endPDFPage()
        }

        context.closePDF()
        try data.write(to: url, options: .atomic)
    }

    private func drawCropMarksAndBleeds(
        in context: CGContext,
        trimSize: CGSize,
        bleedPoints: CGFloat,
        cropMargin: CGFloat
    ) {
        context.saveGState()
        
        let extraOffset = bleedPoints + cropMargin
        let mediaWidth = trimSize.width + 2 * extraOffset
        let mediaHeight = trimSize.height + 2 * extraOffset
        
        // 1. Bleed box boundary (dashed red line)
        context.setStrokeColor(NSColor(calibratedRed: 0.8, green: 0.1, blue: 0.1, alpha: 0.8).cgColor)
        context.setLineWidth(0.5)
        let bleedRect = CGRect(
            x: cropMargin,
            y: cropMargin,
            width: mediaWidth - 2 * cropMargin,
            height: mediaHeight - 2 * cropMargin
        )
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bleedRect)
        
        // 2. Trim box boundary (solid cyan/gray line)
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.8, alpha: 0.8).cgColor)
        let trimRect = CGRect(
            x: extraOffset,
            y: extraOffset,
            width: trimSize.width,
            height: trimSize.height
        )
        context.stroke(trimRect)
        
        // 3. Crop marks at corners pointing to the trim box corners
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        
        let gap: CGFloat = 3.0 // gap between crop mark and trim box
        let length: CGFloat = 12.0 // length of crop mark
        
        // Coordinates of the 4 trim corners
        let xLeft = extraOffset
        let xRight = mediaWidth - extraOffset
        let yBottom = extraOffset
        let yTop = mediaHeight - extraOffset
        
        // Top-Left corner
        // Horizontal line
        context.move(to: CGPoint(x: xLeft - gap - length, y: yTop))
        context.addLine(to: CGPoint(x: xLeft - gap, y: yTop))
        // Vertical line
        context.move(to: CGPoint(x: xLeft, y: yTop + gap))
        context.addLine(to: CGPoint(x: xLeft, y: yTop + gap + length))
        
        // Top-Right corner
        // Horizontal line
        context.move(to: CGPoint(x: xRight + gap, y: yTop))
        context.addLine(to: CGPoint(x: xRight + gap + length, y: yTop))
        // Vertical line
        context.move(to: CGPoint(x: xRight, y: yTop + gap))
        context.addLine(to: CGPoint(x: xRight, y: yTop + gap + length))
        
        // Bottom-Left corner
        // Horizontal line
        context.move(to: CGPoint(x: xLeft - gap - length, y: yBottom))
        context.addLine(to: CGPoint(x: xLeft - gap, y: yBottom))
        // Vertical line
        context.move(to: CGPoint(x: xLeft, y: yBottom - gap - length))
        context.addLine(to: CGPoint(x: xLeft, y: yBottom - gap))
        
        // Bottom-Right corner
        // Horizontal line
        context.move(to: CGPoint(x: xRight + gap, y: yBottom))
        context.addLine(to: CGPoint(x: xRight + gap + length, y: yBottom))
        // Vertical line
        context.move(to: CGPoint(x: xRight, y: yBottom - gap - length))
        context.addLine(to: CGPoint(x: xRight, y: yBottom - gap))
        
        context.strokePath()
        context.restoreGState()
    }

    private func drawGridAndMarginGuides(in context: CGContext, pageNumber: Int, project: BookProject, pageSize: CGSize) {
        context.saveGState()
        
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        let columns = project.resolvedColumns(for: pageNumber)
        let leftMargin = CGFloat(pageLeftMargin(for: pageNumber, project: project))
        let rightMargin = CGFloat(pageRightMargin(for: pageNumber, project: project))
        let contentWidth = pageSize.width - leftMargin - rightMargin
        
        // 1. Margins Box
        context.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5).cgColor)
        context.setLineWidth(0.8)
        
        let contentRect = CGRect(
            x: leftMargin,
            y: CGFloat(margins.bottom),
            width: contentWidth,
            height: pageSize.height - CGFloat(margins.top) - CGFloat(margins.bottom)
        )
        context.stroke(contentRect)
        
        // Column Guides
        if columns > 1 {
            context.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.3).cgColor)
            let colWidth = (Double(contentWidth) - Double(columns - 1) * setup.gutter) / Double(columns)
            for i in 0..<columns {
                let colX = Double(leftMargin) + Double(i) * (colWidth + setup.gutter)
                let colRect = CGRect(
                    x: CGFloat(colX),
                    y: CGFloat(margins.bottom),
                    width: CGFloat(colWidth),
                    height: contentRect.height
                )
                context.stroke(colRect)
            }
        }
        
        // 2. Baseline Grid
        context.setStrokeColor(NSColor(calibratedRed: 0.8, green: 0.5, blue: 0.2, alpha: 0.3).cgColor)
        context.setLineWidth(0.5)
        
        let grid = CGFloat(setup.baselineGrid)
        var y: CGFloat = CGFloat(margins.top)
        while y <= pageSize.height - CGFloat(margins.bottom) {
            let pdfY = pageSize.height - y
            context.move(to: CGPoint(x: leftMargin, y: pdfY))
            context.addLine(to: CGPoint(x: pageSize.width - rightMargin, y: pdfY))
            y += grid
        }
        context.strokePath()
        
        context.restoreGState()
    }

    private func pageLeftMargin(for pageNumber: Int, project: BookProject) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.left : margins.right
        }
        return margins.left
    }

    private func pageRightMargin(for pageNumber: Int, project: BookProject) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.right : margins.left
        }
        return margins.right
    }

    private func draw(page: LaidOutPage, project: BookProject, in context: CGContext, bleedPoints: CGFloat) {
        let pageSize = project.pageSetup.pageSize
        context.setFillColor(NSColor.white.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(pageSize.width),
                height: CGFloat(pageSize.height)
            )
        )

        for frame in page.frames {
            draw(frame: frame, pageNumber: page.number, project: project, in: context, pageHeight: CGFloat(pageSize.height), bleedPoints: bleedPoints)
        }

        drawPageNumber(page.number, project: project, in: context)
    }

    private func draw(frame: PageFrame, pageNumber: Int, project: BookProject, in context: CGContext, pageHeight: CGFloat, bleedPoints: CGFloat) {
        let style: ParagraphStyle
        if frame.kind == .footnote {
            style = ParagraphStyle(
                id: "footnote",
                displayName: "脚注",
                fontName: "Songti SC",
                fontSize: 8.5,
                lineHeight: 11,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 4,
                colorToken: "ink"
            )
        } else if frame.kind == .sideNote {
            style = ParagraphStyle(
                id: "sideNote",
                displayName: "旁注",
                fontName: "Songti SC",
                fontSize: 6.0,
                lineHeight: 8.0,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 2,
                colorToken: "ink"
            )
        } else {
            style = project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue)
        }

        let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote || frame.kind == .runningHeader) ? CGFloat(style.fontSize * 0.5) : 0.0

        let layoutRect = CGRect(
            x: CGFloat(frame.rect.x),
            y: CGFloat(frame.rect.y),
            width: CGFloat(frame.rect.width) + extraWidth,
            height: CGFloat(frame.rect.height)
        )
        var rect = pdfRect(fromLayoutRect: layoutRect, pageHeight: pageHeight)

        // Handle full-bleed cover/fullPageImage fixed page export
        if bleedPoints > 0,
           let plan = project.appliedLayoutPlans?[pageNumber],
           plan.strategy == .fullPageImage || plan.strategy == .cover || plan.strategy == .titlePage {
            let pageSize = project.pageSetup.pageSize
            if frame.rect.width >= pageSize.width - 1.0 && frame.rect.height >= pageSize.height - 1.0 {
                rect = CGRect(
                    x: -bleedPoints,
                    y: -bleedPoints,
                    width: CGFloat(pageSize.width) + 2 * bleedPoints,
                    height: CGFloat(pageSize.height) + 2 * bleedPoints
                )
            }
        }

        if let bgHex = frame.backgroundColorHex, let color = NSColor.from(hex: bgHex) {
            context.saveGState()
            context.setFillColor(color.cgColor)
            let path = maskPath(in: rect, shape: frame.maskShape)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        if frame.kind == .footnoteDivider {
            context.saveGState()
            context.setFillColor(NSColor.black.cgColor)
            context.fill(rect)
            context.restoreGState()
            return
        }

        switch frame.content {
        case .text(let text):
            let textRect: CGRect
            if let componentStyle = project.styles.componentStyle(for: frame.kind) {
                if frame.backgroundColorHex == nil {
                    drawComponentBackground(componentStyle, project: project, in: rect, context: context)
                }
                textRect = rect.insetBy(
                    dx: CGFloat(componentStyle.textInsetX),
                    dy: CGFloat(componentStyle.textInsetY)
                )
                drawText(
                    text,
                    styleId: frame.styleId,
                    kind: frame.kind,
                    project: project,
                    rect: textRect,
                    context: context,
                    textColorHex: frame.textColorHex ?? componentStyle.resolvedTextColorHex(project: project),
                    sourceParagraphId: frame.sourceParagraphId
                )
            } else {
                textRect = rect
                drawText(text, styleId: frame.styleId, kind: frame.kind, project: project, rect: textRect, context: context, textColorHex: frame.textColorHex, sourceParagraphId: frame.sourceParagraphId)
            }
        case .asset, .spreadAsset:
            drawImagePlaceholder(frame: frame, project: project, in: context, rect: rect)
        case .empty:
            break
        }

        if let strokeHex = frame.strokeColorHex, let color = NSColor.from(hex: strokeHex) {
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(CGFloat(frame.strokeWidth ?? 1.5))
            let path = maskPath(in: rect, shape: frame.maskShape)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawComponentBackground(_ style: ComponentStyle, project: BookProject, in rect: CGRect, context: CGContext) {
        context.saveGState()
        if let fillHex = style.resolvedFillColorHex(project: project), let fill = NSColor.from(hex: fillHex) {
            context.setFillColor(fill.cgColor)
            context.fill(rect)
        }
        if let strokeHex = style.resolvedStrokeColorHex(project: project), let stroke = NSColor.from(hex: strokeHex), style.strokeWidth > 0 {
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(CGFloat(style.strokeWidth))
            context.stroke(rect)
        }
        if let accentHex = style.resolvedAccentColorHex(project: project), let accent = NSColor.from(hex: accentHex), style.accentWidth > 0 {
            let accentRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(style.accentWidth), height: rect.height)
            context.setFillColor(accent.cgColor)
            context.fill(accentRect)
        }
        context.restoreGState()
    }

    private func drawText(_ text: String, styleId: String?, kind: PageFrameKind, project: BookProject, rect: CGRect, context: CGContext, textColorHex: String? = nil, sourceParagraphId: UUID? = nil) {
        let style: ParagraphStyle
        if kind == .footnote {
            style = ParagraphStyle(
                id: "footnote",
                displayName: "脚注",
                fontName: "Songti SC",
                fontSize: 8.5,
                lineHeight: 11,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 4,
                colorToken: "ink"
            )
        } else if kind == .sideNote {
            style = ParagraphStyle(
                id: "sideNote",
                displayName: "旁注",
                fontName: "Songti SC",
                fontSize: 6.0,
                lineHeight: 8.0,
                firstLineIndent: 0,
                spaceBefore: 0,
                spaceAfter: 2,
                colorToken: "ink"
            )
        } else {
            style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        }

        // Color priority: explicit frame override > paragraph style's color token
        // (resolved through the style library / design tokens) > black fallback.
        let textColor: CGColor
        if let hex = textColorHex, let color = NSColor.from(hex: hex) {
            textColor = color.cgColor
        } else if let tokenHex = project.resolvedColorHex(style.colorToken), let color = NSColor.from(hex: tokenHex) {
            textColor = color.cgColor
        } else {
            textColor = NSColor.black.cgColor
        }

        var mappedRuns: [InlineRun]? = nil
        if let sourceParagraphId = sourceParagraphId,
           let paragraph = project.sections.lazy.flatMap(\.stories).flatMap(\.paragraphs).first(where: { $0.id == sourceParagraphId }),
           let runs = paragraph.inlineRuns {
            mappedRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: text)
        }

        let attributedString = ChineseTypesetting.makeAttributedString(
            text: text,
            style: style,
            foregroundColor: textColor,
            inlineRuns: mappedRuns
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(rect)
        let frameAttrs: [CFString: Any]?
        if style.layoutDirection == .vertical {
            frameAttrs = [kCTFrameProgressionAttributeName: CTFrameProgression.rightToLeft.rawValue as CFNumber]
        } else {
            frameAttrs = nil
        }
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            frameAttrs as CFDictionary?
        )
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func drawImagePlaceholder(frame: PageFrame, project: BookProject, in context: CGContext, rect: CGRect) {
        var assetId: UUID? = nil
        var isLeftHalf: Bool? = nil

        switch frame.content {
        case .asset(let id):
            assetId = id
        case .spreadAsset(let id, let isLeft):
            assetId = id
            isLeftHalf = isLeft
        default:
            break
        }

        if let id = assetId,
           let asset = project.assets.first(where: { $0.id == id }),
           let sourcePath = asset.sourcePath,
           let image = NSImage(contentsOfFile: sourcePath) {
            drawImage(image, isLeftHalf: isLeftHalf, in: rect, project: project, context: context, maskShape: frame.maskShape)
            return
        }

        let path = maskPath(in: rect, shape: frame.maskShape)
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        let label: String
        if let id = assetId, let asset = project.assets.first(where: { $0.id == id }) {
            label = asset.fileName
        } else {
            label = "Image"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(in: rect.insetBy(dx: 8, dy: 8), withAttributes: attributes)
    }

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, in rect: CGRect, project: BookProject, context: CGContext, maskShape: ImageMaskShape?) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let path = maskPath(in: rect, shape: maskShape)

        context.saveGState()
        context.addPath(path)
        context.clip()

        if let isLeft = isLeftHalf {
            let pageSize = project.pageSetup.pageSize
            let leftMargin = pageLeftMargin(for: 2, project: project)
            let rightMargin = pageRightMargin(for: 3, project: project)
            let leftWidth = pageSize.width - leftMargin
            let rightWidth = pageSize.width - rightMargin
            let totalWidth = leftWidth + rightWidth

            let drawRect: CGRect
            if isLeft {
                drawRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(totalWidth), height: rect.height)
            } else {
                drawRect = CGRect(x: rect.minX - CGFloat(leftWidth), y: rect.minY, width: CGFloat(totalWidth), height: rect.height)
            }
            context.draw(cgImage, in: drawRect)
        } else {
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let imageAspect = imageSize.width / imageSize.height
            let rectAspect = rect.width / rect.height
            let drawRect: CGRect
            if imageAspect > rectAspect {
                let height = rect.width / imageAspect
                drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
            } else {
                let width = rect.height * imageAspect
                drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
            }
            context.draw(cgImage, in: drawRect)
        }

        context.restoreGState()
    }

    private func drawPageNumber(_ number: Int, project: BookProject, in context: CGContext) {
        guard number > 1 else {
            return
        }
        guard project.resolvedShowHeadersFooters(for: number) else {
            return
        }

        let pageSize = project.pageSetup.pageSize
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.gray
        ]
        let size = text.size(withAttributes: attributes)
        
        let x: CGFloat
        let setup = project.pageSetup
        if setup.facingPages {
            if number % 2 == 0 {
                x = CGFloat(pageLeftMargin(for: number, project: project))
            } else {
                x = CGFloat(pageSize.width) - CGFloat(pageRightMargin(for: number, project: project)) - size.width
            }
        } else {
            x = CGFloat(pageSize.width) / 2 - size.width / 2
        }

        let rect = CGRect(
            x: x,
            y: 22,
            width: size.width + 2,
            height: size.height + 2
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    private func pdfRect(fromLayoutRect rect: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: pageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func maskPath(in rect: CGRect, shape: ImageMaskShape?) -> CGPath {
        let path = CGMutablePath()
        guard let shape, shape != .rect else {
            path.addRect(rect)
            return path
        }
        
        switch shape {
        case .rect:
            path.addRect(rect)
        case .octagon:
            let delta = min(rect.width, rect.height) * 0.15
            path.move(to: CGPoint(x: rect.minX + delta, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - delta, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + delta))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - delta))
            path.addLine(to: CGPoint(x: rect.maxX - delta, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + delta, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - delta))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + delta))
            path.closeSubpath()
        case .fan:
            let cx = rect.minX + rect.width / 2.0
            let cy = rect.minY - rect.height * 1.5
            let R = rect.height * 2.5
            let r = rect.height * 1.5
            let theta = asin(rect.width / (2.0 * R))
            let startAngle = 0.5 * .pi + theta
            let endAngle = 0.5 * .pi - theta
            
            path.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.addLine(to: CGPoint(x: cx + r * cos(endAngle), y: cy + r * sin(endAngle)))
            path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: endAngle, endAngle: startAngle, clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

private extension NSColor {
    static func from(hex: String) -> NSColor? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        
        guard cleanHex.count == 6 else {
            return nil
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
        
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

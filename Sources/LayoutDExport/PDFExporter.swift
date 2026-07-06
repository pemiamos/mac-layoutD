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

        func cgRectToData(_ rect: CGRect) -> CFData {
            var r = rect
            return Data(bytes: &r, count: MemoryLayout<CGRect>.size) as CFData
        }

        struct PDFSpread {
            let index: Int
            let leftPage: LaidOutPage?
            let rightPage: LaidOutPage?
            
            var pages: [LaidOutPage] {
                [leftPage, rightPage].compactMap { $0 }
            }
        }
        
        var spreads: [PDFSpread] = []
        if project.pageSetup.facingPages {
            let pagesByNumber = Dictionary(uniqueKeysWithValues: document.pages.map { ($0.number, $0) })
            if let p1 = pagesByNumber[1] {
                spreads.append(PDFSpread(index: 0, leftPage: nil, rightPage: p1))
            }
            let maxPageNum = document.pages.map(\.number).max() ?? 1
            if maxPageNum >= 2 {
                for startEven in stride(from: 2, through: maxPageNum, by: 2) {
                    let left = pagesByNumber[startEven]
                    let right = pagesByNumber[startEven + 1]
                    if left != nil || right != nil {
                        spreads.append(PDFSpread(index: startEven / 2, leftPage: left, rightPage: right))
                    }
                }
            }
        } else {
            for page in document.pages.sorted(by: { $0.number < $1.number }) {
                spreads.append(PDFSpread(index: page.number, leftPage: page, rightPage: nil))
            }
        }

        for spread in spreads {
            let containsExportPage = spread.pages.contains { pagesToExport.contains($0.number) }
            guard containsExportPage else {
                continue
            }
            
            let isDoublePage = project.pageSetup.facingPages && spread.index > 0
            let spreadWidth = isDoublePage ? pageSize.width * 2 : pageSize.width
            let spreadHeight = pageSize.height
            
            let pageInfo = NSMutableDictionary()
            let mediaBoxRect = CGRect(x: 0, y: 0, width: spreadWidth + 2 * extraOffset, height: spreadHeight + 2 * extraOffset)
            pageInfo[kCGPDFContextMediaBox] = cgRectToData(mediaBoxRect)
            
            let trimBoxRect = CGRect(
                x: extraOffset,
                y: extraOffset,
                width: spreadWidth,
                height: spreadHeight
            )
            pageInfo[kCGPDFContextTrimBox] = cgRectToData(trimBoxRect)
            
            let bleedBoxRect = CGRect(
                x: drawCropMarks ? cropMarkMargin : 0,
                y: drawCropMarks ? cropMarkMargin : 0,
                width: spreadWidth + 2 * bleedPoints,
                height: spreadHeight + 2 * bleedPoints
            )
            pageInfo[kCGPDFContextBleedBox] = cgRectToData(bleedBoxRect)
            pageInfo[kCGPDFContextCropBox] = cgRectToData(mediaBoxRect)
            
            context.beginPDFPage(pageInfo as CFDictionary)
            
            context.saveGState()
            if extraOffset > 0 {
                context.translateBy(x: extraOffset, y: extraOffset)
            }
            
            if isDoublePage {
                if let leftPage = spread.leftPage {
                    context.saveGState()
                    draw(page: leftPage, project: project, in: context, bleedPoints: drawCropMarks ? bleedPoints : 0.0)
                    context.restoreGState()
                }
                
                if let rightPage = spread.rightPage {
                    context.saveGState()
                    context.translateBy(x: pageSize.width, y: 0)
                    draw(page: rightPage, project: project, in: context, bleedPoints: drawCropMarks ? bleedPoints : 0.0)
                    context.restoreGState()
                }
            } else {
                let page = spread.leftPage ?? spread.rightPage!
                draw(page: page, project: project, in: context, bleedPoints: drawCropMarks ? bleedPoints : 0.0)
            }
            
            context.restoreGState()
            
            if drawCropMarks {
                drawCropMarksAndBleeds(in: context, trimSize: CGSize(width: spreadWidth, height: spreadHeight), bleedPoints: bleedPoints, cropMargin: cropMarkMargin)
            }
            
            if drawGridGuides {
                context.saveGState()
                if extraOffset > 0 {
                    context.translateBy(x: extraOffset, y: extraOffset)
                }
                if isDoublePage {
                    if let leftPage = spread.leftPage {
                        context.saveGState()
                        drawGridAndMarginGuides(in: context, pageNumber: leftPage.number, project: project, pageSize: pageSize)
                        context.restoreGState()
                    }
                    if let rightPage = spread.rightPage {
                        context.saveGState()
                        context.translateBy(x: pageSize.width, y: 0)
                        drawGridAndMarginGuides(in: context, pageNumber: rightPage.number, project: project, pageSize: pageSize)
                        context.restoreGState()
                    }
                } else {
                    let page = spread.leftPage ?? spread.rightPage!
                    drawGridAndMarginGuides(in: context, pageNumber: page.number, project: project, pageSize: pageSize)
                }
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
            let path = maskPath(in: rect, pageHeight: pageHeight, shape: frame.maskShape)
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

        // A line is a centered stroke along its long axis (weight = strokeWidth).
        if frame.kind == .line {
            let color = frame.strokeColorHex.flatMap { NSColor.from(hex: $0) } ?? .black
            let weight = max(CGFloat(frame.strokeWidth ?? 1), 0.25)
            let horizontal = rect.width >= rect.height
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(weight)
            if horizontal {
                context.move(to: CGPoint(x: rect.minX, y: rect.midY))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            } else {
                context.move(to: CGPoint(x: rect.midX, y: rect.minY))
                context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
            context.strokePath()
            context.restoreGState()
            return
        }

        switch frame.content {
        case .text(let text):
            if let componentStyle = project.styles.componentStyle(for: frame.kind) {
                if frame.backgroundColorHex == nil {
                    drawComponentBackground(componentStyle, project: project, in: rect, context: context)
                }
                
                if frame.kind == .table {
                    drawTable(
                        text,
                        style: style,
                        componentStyle: componentStyle,
                        project: project,
                        rect: rect,
                        context: context,
                        textColorHex: frame.textColorHex
                    )
                } else {
                    let textRect = rect.insetBy(
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
                        sourceParagraphId: frame.sourceParagraphId,
                        tableOfContentsEntries: frame.tableOfContentsEntries,
                        exclusionRects: frame.exclusionRects,
                        pageHeight: pageHeight
                    )
                }
            } else {
                let textRect = rect
                drawText(
                    text,
                    styleId: frame.styleId,
                    kind: frame.kind,
                    project: project,
                    rect: textRect,
                    context: context,
                    textColorHex: frame.textColorHex,
                    sourceParagraphId: frame.sourceParagraphId,
                    tableOfContentsEntries: frame.tableOfContentsEntries,
                    exclusionRects: frame.exclusionRects,
                    pageHeight: pageHeight
                )
            }
        case .asset, .spreadAsset:
            drawImagePlaceholder(frame: frame, project: project, in: context, rect: rect, pageHeight: pageHeight)
        case .empty:
            break
        }

        if let strokeHex = frame.strokeColorHex, let color = NSColor.from(hex: strokeHex) {
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(CGFloat(frame.strokeWidth ?? 1.5))
            let path = maskPath(in: rect, pageHeight: pageHeight, shape: frame.maskShape)
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

    private func drawTable(
        _ text: String,
        style: ParagraphStyle,
        componentStyle: ComponentStyle,
        project: BookProject,
        rect: CGRect,
        context: CGContext,
        textColorHex: String?
    ) {
        let tableData = TableLayoutHelper.parseTableText(text)
        let colCount = tableData.columnCount
        let rowCount = tableData.rows.count
        guard colCount > 0, rowCount > 0 else { return }
        
        let strokeColor: NSColor
        if let strokeHex = componentStyle.resolvedStrokeColorHex(project: project) {
            strokeColor = NSColor.from(hex: strokeHex) ?? .black
        } else {
            strokeColor = .black
        }
        let strokeWidth = CGFloat(componentStyle.strokeWidth)
        
        let colWidths = TableLayoutHelper.allocateColumnWidths(
            tableData: tableData,
            totalWidth: Double(rect.width),
            fontName: style.fontName,
            fontSize: style.fontSize,
            zoomScale: 1.0
        )
        let rowHeights = TableLayoutHelper.calculateRowHeights(
            tableData: tableData,
            colWidths: colWidths,
            style: style,
            textInsetX: componentStyle.textInsetX,
            textInsetY: componentStyle.textInsetY,
            zoomScale: 1.0
        )
        
        let textColor: CGColor
        if let hex = textColorHex, let color = NSColor.from(hex: hex) {
            textColor = color.cgColor
        } else if let tokenHex = project.resolvedColorHex(style.colorToken), let color = NSColor.from(hex: tokenHex) {
            textColor = color.cgColor
        } else {
            textColor = NSColor.black.cgColor
        }
        
        // Draw backgrounds and text (from top to bottom)
        var currentY = rect.maxY
        for r in 0..<rowCount {
            let rowHeight = CGFloat(rowHeights[r])
            let cells = tableData.rows[r]
            currentY -= rowHeight
            
            var currentX = rect.minX
            for c in 0..<colCount {
                let cellWidth = CGFloat(colWidths[c])
                let cellRect = CGRect(x: currentX, y: currentY, width: cellWidth, height: rowHeight)
                
                context.saveGState()
                if r == 0 {
                    if let accentHex = componentStyle.resolvedAccentColorHex(project: project), let headerColor = NSColor.from(hex: accentHex) {
                        context.setFillColor(headerColor.withAlphaComponent(0.15).cgColor)
                    } else if let fillHex = componentStyle.resolvedFillColorHex(project: project), let fillColor = NSColor.from(hex: fillHex) {
                        context.setFillColor(fillColor.withAlphaComponent(0.3).cgColor)
                    } else {
                        context.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
                    }
                } else {
                    if let fillHex = componentStyle.resolvedFillColorHex(project: project), let fillColor = NSColor.from(hex: fillHex) {
                        context.setFillColor(fillColor.cgColor)
                    } else {
                        context.setFillColor(NSColor.white.cgColor)
                    }
                }
                context.fill(cellRect)
                context.restoreGState()
                
                let cellText = c < cells.count ? cells[c] : ""
                if !cellText.isEmpty {
                    let insetX = CGFloat(componentStyle.textInsetX)
                    let insetY = CGFloat(componentStyle.textInsetY)
                    let textRect = cellRect.insetBy(dx: insetX, dy: insetY)
                    
                    context.saveGState()
                    context.translateBy(x: textRect.minX, y: textRect.minY)
                    
                    let attrString = ChineseTypesetting.makeAttributedString(
                        text: cellText,
                        style: style,
                        foregroundColor: textColor,
                        zoomScale: 1.0
                    )
                    
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: textRect.width, height: textRect.height), transform: nil)
                    let framesetter = CTFramesetterCreateWithAttributedString(attrString)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
                    
                    context.textMatrix = .identity
                    CTFrameDraw(frame, context)
                    context.restoreGState()
                }
                
                currentX += cellWidth
            }
        }
        
        // Draw grid lines
        context.saveGState()
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth)
        
        // Outer border
        context.stroke(rect)
        
        // Horizontal grid lines
        var currentLineY = rect.maxY
        for r in 0..<(rowCount - 1) {
            currentLineY -= CGFloat(rowHeights[r])
            context.move(to: CGPoint(x: rect.minX, y: currentLineY))
            context.addLine(to: CGPoint(x: rect.maxX, y: currentLineY))
            context.strokePath()
        }
        
        // Vertical grid lines
        var currentLineX = rect.minX
        for c in 0..<(colCount - 1) {
            currentLineX += CGFloat(colWidths[c])
            context.move(to: CGPoint(x: currentLineX, y: rect.minY))
            context.addLine(to: CGPoint(x: currentLineX, y: rect.maxY))
            context.strokePath()
        }
        
        context.restoreGState()
    }

    private func drawText(
        _ text: String,
        styleId: String?,
        kind: PageFrameKind,
        project: BookProject,
        rect: CGRect,
        context: CGContext,
        textColorHex: String? = nil,
        sourceParagraphId: UUID? = nil,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
        exclusionRects: [Rect]? = nil,
        pageHeight: CGFloat = 0
    ) {
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

        let attributedString: NSAttributedString
        if let entries = tableOfContentsEntries, !entries.isEmpty {
            attributedString = ChineseTypesetting.makeTOCAttributedString(
                entries: entries,
                project: project,
                containerWidth: Double(rect.width),
                zoomScale: 1.0,
                foregroundColor: textColor
            )
        } else {
            var mappedRuns: [InlineRun]? = nil
            if let sourceParagraphId = sourceParagraphId,
               let paragraph = project.sections.lazy.flatMap(\.stories).flatMap(\.paragraphs).first(where: { $0.id == sourceParagraphId }),
               let runs = paragraph.inlineRuns {
                mappedRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: text)
            }

            attributedString = ChineseTypesetting.makeAttributedString(
                text: text,
                style: style,
                foregroundColor: textColor,
                inlineRuns: mappedRuns
            )
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(rect)
        
        var frameAttrs: [CFString: Any] = [:]
        if style.layoutDirection == .vertical {
            frameAttrs[kCTFrameProgressionAttributeName] = CTFrameProgression.rightToLeft.rawValue as CFNumber
        }
        
        if let exclusionRects = exclusionRects, !exclusionRects.isEmpty, pageHeight > 0 {
            var exclusionPaths: [CGPath] = []
            for img in exclusionRects {
                let pdfImageRect = CGRect(
                    x: img.x,
                    y: Double(pageHeight) - (img.y + img.height),
                    width: img.width,
                    height: img.height
                )
                let overlap = rect.intersection(pdfImageRect)
                guard overlap.width > 0 && overlap.height > 0 else { continue }
                
                exclusionPaths.append(CGPath(rect: overlap, transform: nil))
            }
            if !exclusionPaths.isEmpty {
                let clippingPaths = exclusionPaths.map { [kCTFramePathClippingPathAttributeName: $0] }
                frameAttrs[kCTFrameClippingPathsAttributeName] = clippingPaths
            }
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
        ChineseTypesetting.drawKentenDots(for: frame, in: context, layoutDirection: style.layoutDirection, zoomScale: 1.0)
        context.restoreGState()
    }

    private func drawImagePlaceholder(frame: PageFrame, project: BookProject, in context: CGContext, rect: CGRect, pageHeight: CGFloat) {
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
            drawImage(image, isLeftHalf: isLeftHalf, in: rect, project: project, context: context, maskShape: frame.maskShape, pageHeight: pageHeight)
            return
        }

        let path = maskPath(in: rect, pageHeight: pageHeight, shape: frame.maskShape)
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
            label = asset.caption ?? (asset.fileName as NSString).lastPathComponent
        } else {
            label = "Image"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(in: rect.insetBy(dx: 8, dy: 8), withAttributes: attributes)
    }

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, in rect: CGRect, project: BookProject, context: CGContext, maskShape: ImageMaskShape?, pageHeight: CGFloat) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let path = maskPath(in: rect, pageHeight: pageHeight, shape: maskShape)

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

    private func maskPath(in rect: CGRect, pageHeight: CGFloat, shape: ImageMaskShape?) -> CGPath {
        let path = CGMutablePath()
        guard let shape else {
            path.addRect(rect)
            return path
        }
        
        let layoutRect = CGRect(
            x: rect.minX,
            y: pageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        
        let points = shape.polygonPoints(in: layoutRect)
        guard !points.isEmpty else {
            path.addRect(rect)
            return path
        }
        
        path.move(to: CGPoint(x: points[0].x, y: pageHeight - points[0].y))
        for i in 1..<points.count {
            path.addLine(to: CGPoint(x: points[i].x, y: pageHeight - points[i].y))
        }
        path.closeSubpath()
        return path
    }
}

private extension NSColor {
    static func from(hex: String) -> NSColor? {
        // "hex" now also carries CMYK (`cmyk(c,m,y,k)`); CMYK renders via the
        // device-CMYK space as a screen approximation.
        guard let color = PrintColor(string: hex) else { return nil }
        switch color {
        case let .rgb(r, g, b):
            return NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                           blue: CGFloat(b) / 255, alpha: 1.0)
        case let .cmyk(c, m, y, k):
            return NSColor(deviceCyan: CGFloat(c) / 100, magenta: CGFloat(m) / 100,
                           yellow: CGFloat(y) / 100, black: CGFloat(k) / 100, alpha: 1.0)
        }
    }
}

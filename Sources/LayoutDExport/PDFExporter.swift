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

public struct PDFExporter {
    public init() {}

    public func export(
        document: LaidOutDocument,
        project: BookProject,
        to url: URL,
        pageRange: String? = nil,
        drawCropMarks: Bool = false,
        drawGridGuides: Bool = false
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
        
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFExportError.couldNotCreateContext
        }

        let sortedPages = document.pages.sorted(by: { $0.number < $1.number })

        for page in sortedPages {
            guard pagesToExport.contains(page.number) else {
                continue
            }
            context.beginPDFPage(nil)
            
            draw(page: page, project: project, in: context)
            
            if drawCropMarks {
                drawCropMarksAndBleeds(in: context, pageSize: pageSize)
            }
            
            if drawGridGuides {
                drawGridAndMarginGuides(in: context, pageNumber: page.number, project: project, pageSize: pageSize)
            }
            
            context.endPDFPage()
        }

        context.closePDF()
        try data.write(to: url, options: .atomic)
    }

    private func drawCropMarksAndBleeds(in context: CGContext, pageSize: CGSize) {
        context.saveGState()
        
        // 1. Bleed guide (3mm = 8.5 pt inside the trim page edges)
        let bleedDistance: CGFloat = 8.5
        context.setStrokeColor(NSColor(calibratedRed: 0.8, green: 0.1, blue: 0.1, alpha: 0.8).cgColor)
        context.setLineWidth(0.5)
        let bleedRect = CGRect(
            x: bleedDistance,
            y: bleedDistance,
            width: pageSize.width - 2 * bleedDistance,
            height: pageSize.height - 2 * bleedDistance
        )
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(bleedRect)
        
        // 2. Trim boundary (solid cyan/gray line)
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.8, alpha: 0.8).cgColor)
        let trimRect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        context.stroke(trimRect)
        
        // 3. Crop marks at corners
        context.setStrokeColor(NSColor.black.cgColor)
        let markLength: CGFloat = 15.0
        
        // Top-Left
        context.move(to: CGPoint(x: 0, y: pageSize.height - bleedDistance))
        context.addLine(to: CGPoint(x: markLength, y: pageSize.height - bleedDistance))
        context.move(to: CGPoint(x: bleedDistance, y: pageSize.height))
        context.addLine(to: CGPoint(x: bleedDistance, y: pageSize.height - markLength))
        
        // Top-Right
        context.move(to: CGPoint(x: pageSize.width, y: pageSize.height - bleedDistance))
        context.addLine(to: CGPoint(x: pageSize.width - markLength, y: pageSize.height - bleedDistance))
        context.move(to: CGPoint(x: pageSize.width - bleedDistance, y: pageSize.height))
        context.addLine(to: CGPoint(x: pageSize.width - bleedDistance, y: pageSize.height - markLength))
        
        // Bottom-Left
        context.move(to: CGPoint(x: 0, y: bleedDistance))
        context.addLine(to: CGPoint(x: markLength, y: bleedDistance))
        context.move(to: CGPoint(x: bleedDistance, y: 0))
        context.addLine(to: CGPoint(x: bleedDistance, y: markLength))
        
        // Bottom-Right
        context.move(to: CGPoint(x: pageSize.width, y: bleedDistance))
        context.addLine(to: CGPoint(x: pageSize.width - markLength, y: bleedDistance))
        context.move(to: CGPoint(x: pageSize.width - bleedDistance, y: 0))
        context.addLine(to: CGPoint(x: pageSize.width - bleedDistance, y: markLength))
        
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

    private func draw(page: LaidOutPage, project: BookProject, in context: CGContext) {
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
            draw(frame: frame, project: project, in: context, pageHeight: CGFloat(pageSize.height))
        }

        drawPageNumber(page.number, project: project, in: context)
    }

    private func draw(frame: PageFrame, project: BookProject, in context: CGContext, pageHeight: CGFloat) {
        let layoutRect = CGRect(
            x: CGFloat(frame.rect.x),
            y: CGFloat(frame.rect.y),
            width: CGFloat(frame.rect.width),
            height: CGFloat(frame.rect.height)
        )
        let rect = pdfRect(fromLayoutRect: layoutRect, pageHeight: pageHeight)

        switch frame.content {
        case .text(let text):
            let textRect: CGRect
            if frame.kind == .callout || frame.kind == .table {
                drawCalloutBackground(in: rect, context: context)
                textRect = rect.insetBy(dx: 8, dy: 6)
            } else {
                textRect = rect
            }
            drawText(text, styleId: frame.styleId, project: project, rect: textRect, context: context)
        case .asset, .spreadAsset:
            drawImagePlaceholder(frame: frame, project: project, in: context, rect: rect)
        case .empty:
            break
        }
    }

    private func drawCalloutBackground(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 1).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1).cgColor)
        context.setLineWidth(0.8)
        context.stroke(rect)

        let accentRect = CGRect(x: rect.minX, y: rect.minY, width: 4, height: rect.height)
        context.setFillColor(NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1).cgColor)
        context.fill(accentRect)
        context.restoreGState()
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, rect: CGRect, context: CGContext) {
        let style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        let attributedString = ChineseTypesetting.makeAttributedString(
            text: text,
            style: style,
            foregroundColor: NSColor.black.cgColor
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(rect)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            path,
            nil
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
            drawImage(image, isLeftHalf: isLeftHalf, in: rect, project: project, context: context)
            return
        }

        context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
        context.stroke(rect)

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

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, in rect: CGRect, project: BookProject, context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        context.saveGState()
        context.clip(to: rect)

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
        let rect = CGRect(
            x: CGFloat(pageSize.width) / 2 - size.width / 2,
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
}

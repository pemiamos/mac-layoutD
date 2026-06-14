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

    public func export(document: LaidOutDocument, project: BookProject, to url: URL) throws {
        let pageSize = CGSize(
            width: CGFloat(project.pageSetup.pageSize.width),
            height: CGFloat(project.pageSetup.pageSize.height)
        )
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFExportError.couldNotCreateContext
        }

        for page in document.pages {
            context.beginPDFPage(nil)
            draw(page: page, project: project, in: context)
            context.endPDFPage()
        }

        context.closePDF()
        try data.write(to: url, options: .atomic)
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
            drawText(text, styleId: frame.styleId, project: project, rect: rect, context: context)
        case .asset:
            drawImagePlaceholder(frame: frame, project: project, in: context, rect: rect)
        case .empty:
            break
        }
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, rect: CGRect, context: CGContext) {
        let style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        var minimumLineHeight = CGFloat(style.lineHeight)
        var maximumLineHeight = CGFloat(style.lineHeight)
        var firstLineIndent = CGFloat(style.firstLineIndent)
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        let paragraphStyle = withUnsafePointer(to: &minimumLineHeight) { minimumLineHeightPointer in
            withUnsafePointer(to: &maximumLineHeight) { maximumLineHeightPointer in
                withUnsafePointer(to: &firstLineIndent) { firstLineIndentPointer in
                    withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
                        let settings = [
                            CTParagraphStyleSetting(
                                spec: .minimumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: minimumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .maximumLineHeight,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: maximumLineHeightPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .firstLineHeadIndent,
                                valueSize: MemoryLayout<CGFloat>.size,
                                value: firstLineIndentPointer
                            ),
                            CTParagraphStyleSetting(
                                spec: .lineBreakMode,
                                valueSize: MemoryLayout<CTLineBreakMode>.size,
                                value: lineBreakModePointer
                            )
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }

        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: NSColor.black.cgColor,
            kCTParagraphStyleAttributeName: paragraphStyle
        ] as CFDictionary
        let attributedString = CFAttributedStringCreate(nil, text as CFString, attributes)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(rect)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: CFAttributedStringGetLength(attributedString)),
            path,
            nil
        )
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func drawImagePlaceholder(frame: PageFrame, project: BookProject, in context: CGContext, rect: CGRect) {
        if case .asset(let id) = frame.content,
           let asset = project.assets.first(where: { $0.id == id }),
           let sourcePath = asset.sourcePath,
           let image = NSImage(contentsOfFile: sourcePath) {
            drawImage(image, in: rect, context: context)
            return
        }

        context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
        context.stroke(rect)

        let label: String
        if case .asset(let id) = frame.content,
           let asset = project.assets.first(where: { $0.id == id }) {
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

    private func drawImage(_ image: NSImage, in rect: CGRect, context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

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

    private func pdfRect(fromLayoutRect rect: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: pageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

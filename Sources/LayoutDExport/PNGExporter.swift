import AppKit
import CoreText
import Foundation
import LayoutDCore

public enum PNGExportError: Error, LocalizedError {
    case couldNotCreateBitmapContext
    case couldNotCreateImage
    case couldNotEncodePNG

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateBitmapContext:
            return "无法创建 PNG 位图绘制上下文"
        case .couldNotCreateImage:
            return "无法生成 PNG 图像"
        case .couldNotEncodePNG:
            return "无法编码 PNG 数据"
        }
    }
}

public struct PNGExporter {
    public init() {}

    public func export(
        document: LaidOutDocument,
        project: BookProject,
        to directoryURL: URL,
        pageRange: String? = nil,
        scale: Double = 2.0
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let safeScale = max(scale, 0.25)
        let pageSize = project.pageSetup.pageSize
        let pixelWidth = Int(ceil(pageSize.width * safeScale))
        let pixelHeight = Int(ceil(pageSize.height * safeScale))
        let pagesToExport = ExportPageRange.parse(pageRange, maxPages: document.pages.count)
        var outputURLs: [URL] = []

        for page in document.pages.sorted(by: { $0.number < $1.number }) where pagesToExport.contains(page.number) {
            guard let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw PNGExportError.couldNotCreateBitmapContext
            }

            context.scaleBy(x: safeScale, y: safeScale)
            draw(page: page, project: project, in: context)

            guard let image = context.makeImage() else {
                throw PNGExportError.couldNotCreateImage
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw PNGExportError.couldNotEncodePNG
            }

            let outputURL = directoryURL.appendingPathComponent(String(format: "page-%03d.png", page.number))
            try data.write(to: outputURL, options: .atomic)
            outputURLs.append(outputURL)
        }

        return outputURLs
    }

    private func draw(page: LaidOutPage, project: BookProject, in context: CGContext) {
        let pageSize = project.pageSetup.pageSize
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height))

        for frame in page.frames {
            draw(frame: frame, project: project, in: context)
        }

        drawPageNumber(page.number, project: project, in: context)
    }

    private func draw(frame: PageFrame, project: BookProject, in context: CGContext) {
        let rect = CGRect(
            x: frame.rect.x,
            y: frame.rect.y,
            width: frame.rect.width,
            height: frame.rect.height
        )

        switch frame.content {
        case .text(let text):
            if frame.kind == .callout || frame.kind == .table {
                context.setFillColor(NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 1).cgColor)
                context.fill(rect)
                context.setStrokeColor(NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1).cgColor)
                context.stroke(rect, width: 0.8)
            }
            drawText(text, styleId: frame.styleId, project: project, in: rect.insetBy(dx: 4, dy: 2), context: context)
        case .asset(let assetId):
            drawAsset(assetId: assetId, project: project, in: rect, context: context)
        case .empty:
            break
        }
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, in rect: CGRect, context: CGContext) {
        context.saveGState()
        let style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        let path = CGMutablePath()
        path.addRect(rect)

        let attributed = CFAttributedStringCreate(nil, text as CFString, textAttributes(style: style))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed!)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.count), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func drawAsset(assetId: UUID, project: BookProject, in rect: CGRect, context: CGContext) {
        guard let asset = project.assets.first(where: { $0.id == assetId }),
              let sourcePath = asset.sourcePath,
              let image = NSImage(contentsOfFile: sourcePath) else {
            context.setFillColor(NSColor(calibratedWhite: 0.91, alpha: 1).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
            context.stroke(rect)
            drawText(assetId.uuidString.prefix(8).description, styleId: StyleID.caption.rawValue, project: project, in: rect.insetBy(dx: 8, dy: 8), context: context)
            return
        }

        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.fill(rect)

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

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

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()
        context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
        context.stroke(rect)
    }

    private func drawPageNumber(_ number: Int, project: BookProject, in context: CGContext) {
        let pageSize = project.pageSetup.pageSize
        let text = "\(number)"
        let rect = CGRect(x: pageSize.width / 2 - 12, y: pageSize.height - 28, width: 24, height: 14)
        drawText(text, styleId: StyleID.caption.rawValue, project: project, in: rect, context: context)
    }

    private func textAttributes(style: ParagraphStyle) -> CFDictionary {
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        var minimumLineHeight = CGFloat(style.lineHeight)
        var maximumLineHeight = CGFloat(style.lineHeight)
        var firstLineIndent = CGFloat(style.firstLineIndent)

        return withUnsafePointer(to: &minimumLineHeight) { minimumLineHeightPointer in
            withUnsafePointer(to: &maximumLineHeight) { maximumLineHeightPointer in
                withUnsafePointer(to: &firstLineIndent) { firstLineIndentPointer in
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
                        )
                    ]
                    let paragraphStyle = CTParagraphStyleCreate(settings, settings.count)
                    return [
                        kCTFontAttributeName: font,
                        kCTParagraphStyleAttributeName: paragraphStyle,
                        kCTForegroundColorAttributeName: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).cgColor
                    ] as CFDictionary
                }
            }
        }
    }
}

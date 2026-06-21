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
        scale: Double = 2.0,
        drawCropMarks: Bool = false
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let safeScale = max(scale, 0.25)
        let pageSize = project.pageSetup.pageSize
        
        let bleedMM = project.pageSetup.bleedMM ?? 3.0
        let bleedPoints = CGFloat(bleedMM * 72.0 / 25.4)
        let cropMargin: CGFloat = 20.0
        let extraOffset = drawCropMarks ? (bleedPoints + cropMargin) : 0.0
        
        let mediaWidth = pageSize.width + 2 * extraOffset
        let mediaHeight = pageSize.height + 2 * extraOffset
        
        let pixelWidth = Int(ceil(mediaWidth * safeScale))
        let pixelHeight = Int(ceil(mediaHeight * safeScale))
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
            
            context.saveGState()
            if extraOffset > 0 {
                context.translateBy(x: extraOffset, y: extraOffset)
            }
            draw(page: page, project: project, in: context, bleedPoints: drawCropMarks ? bleedPoints : 0.0)
            context.restoreGState()
            
            if drawCropMarks {
                drawCropMarksAndBleeds(in: context, trimSize: CGSize(width: pageSize.width, height: pageSize.height), bleedPoints: bleedPoints, cropMargin: cropMargin)
            }

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

    private func draw(page: LaidOutPage, project: BookProject, in context: CGContext, bleedPoints: CGFloat) {
        let pageSize = project.pageSetup.pageSize
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height))

        for frame in page.frames {
            draw(frame: frame, pageNumber: page.number, project: project, in: context, bleedPoints: bleedPoints)
        }

        drawPageNumber(page.number, project: project, in: context)
    }

    private func draw(frame: PageFrame, pageNumber: Int, project: BookProject, in context: CGContext, bleedPoints: CGFloat) {
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

        var rect = CGRect(
            x: frame.rect.x,
            y: frame.rect.y,
            width: frame.rect.width + extraWidth,
            height: frame.rect.height
        )

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
            context.setFillColor(NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).cgColor)
            context.fill(rect)
            context.restoreGState()
            return
        }

        switch frame.content {
        case .text(let text):
            if let componentStyle = project.styles.componentStyle(for: frame.kind) {
                if frame.backgroundColorHex == nil {
                    drawComponentBackground(componentStyle, project: project, in: rect, context: context)
                }
                let textRect = rect.insetBy(
                    dx: CGFloat(componentStyle.textInsetX),
                    dy: CGFloat(componentStyle.textInsetY)
                )
                drawText(
                    text,
                    styleId: frame.styleId,
                    kind: frame.kind,
                    project: project,
                    in: textRect,
                    context: context,
                    textColorHex: frame.textColorHex ?? componentStyle.resolvedTextColorHex(project: project),
                    sourceParagraphId: frame.sourceParagraphId
                )
            } else {
                drawText(text, styleId: frame.styleId, kind: frame.kind, project: project, in: rect.insetBy(dx: 4, dy: 2), context: context, textColorHex: frame.textColorHex, sourceParagraphId: frame.sourceParagraphId)
            }
        case .asset(let assetId):
            drawAsset(assetId: assetId, isLeftHalf: nil, project: project, in: rect, context: context, maskShape: frame.maskShape)
        case .spreadAsset(let assetId, let isLeftHalf):
            drawAsset(assetId: assetId, isLeftHalf: isLeftHalf, project: project, in: rect, context: context, maskShape: frame.maskShape)
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

    private func drawText(_ text: String, styleId: String?, kind: PageFrameKind = .text, project: BookProject, in rect: CGRect, context: CGContext, textColorHex: String? = nil, sourceParagraphId: UUID? = nil) {
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
        // (resolved through the style library / design tokens) > neutral fallback.
        let textColor: CGColor
        if let hex = textColorHex, let color = NSColor.from(hex: hex) {
            textColor = color.cgColor
        } else if let tokenHex = project.resolvedColorHex(style.colorToken), let color = NSColor.from(hex: tokenHex) {
            textColor = color.cgColor
        } else {
            textColor = NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).cgColor
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
        CTFrameDraw(frame, context)
    }

    private func drawAsset(assetId: UUID, isLeftHalf: Bool?, project: BookProject, in rect: CGRect, context: CGContext, maskShape: ImageMaskShape?) {
        let path = maskPath(in: rect, shape: maskShape)
        
        guard let asset = project.assets.first(where: { $0.id == assetId }),
              let sourcePath = asset.sourcePath,
              let image = NSImage(contentsOfFile: sourcePath) else {
            context.saveGState()
            context.setFillColor(NSColor(calibratedWhite: 0.91, alpha: 1).cgColor)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
            
            context.saveGState()
            context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
            context.setLineWidth(1.0)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
            
            drawText(assetId.uuidString.prefix(8).description, styleId: StyleID.caption.rawValue, project: project, in: rect.insetBy(dx: 8, dy: 8), context: context)
            return
        }

        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

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
        
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 0.62, alpha: 1).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
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

    private func drawPageNumber(_ number: Int, project: BookProject, in context: CGContext) {
        guard project.resolvedShowHeadersFooters(for: number) else {
            return
        }
        let pageSize = project.pageSetup.pageSize
        let text = "\(number)"
        
        let style = project.styles.paragraphStyle(id: StyleID.caption.rawValue)
        let font = NSFont(name: style.fontName, size: CGFloat(style.fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(style.fontSize))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        
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
            y: CGFloat(pageSize.height) - 28,
            width: size.width + 2,
            height: size.height + 2
        )
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
        
        // 3. Crop marks at corners
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        
        let gap: CGFloat = 3.0
        let length: CGFloat = 12.0
        
        let xLeft = extraOffset
        let xRight = mediaWidth - extraOffset
        let yTop = extraOffset
        let yBottom = mediaHeight - extraOffset
        
        // Top-Left corner
        // Horizontal line
        context.move(to: CGPoint(x: xLeft - gap - length, y: yTop))
        context.addLine(to: CGPoint(x: xLeft - gap, y: yTop))
        // Vertical line
        context.move(to: CGPoint(x: xLeft, y: yTop - gap - length))
        context.addLine(to: CGPoint(x: xLeft, y: yTop - gap))
        
        // Top-Right corner
        // Horizontal line
        context.move(to: CGPoint(x: xRight + gap, y: yTop))
        context.addLine(to: CGPoint(x: xRight + gap + length, y: yTop))
        // Vertical line
        context.move(to: CGPoint(x: xRight, y: yTop - gap - length))
        context.addLine(to: CGPoint(x: xRight, y: yTop - gap))
        
        // Bottom-Left corner
        // Horizontal line
        context.move(to: CGPoint(x: xLeft - gap - length, y: yBottom))
        context.addLine(to: CGPoint(x: xLeft - gap, y: yBottom))
        // Vertical line
        context.move(to: CGPoint(x: xLeft, y: yBottom + gap))
        context.addLine(to: CGPoint(x: xLeft, y: yBottom + gap + length))
        
        // Bottom-Right corner
        // Horizontal line
        context.move(to: CGPoint(x: xRight + gap, y: yBottom))
        context.addLine(to: CGPoint(x: xRight + gap + length, y: yBottom))
        // Vertical line
        context.move(to: CGPoint(x: xRight, y: yBottom + gap))
        context.addLine(to: CGPoint(x: xRight, y: yBottom + gap + length))
        
        context.strokePath()
        context.restoreGState()
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
            let cy = rect.minY + rect.height * 2.5
            let R = rect.height * 2.5
            let r = rect.height * 1.5
            let theta = asin(rect.width / (2.0 * R))
            let startAngle = 1.5 * .pi - theta
            let endAngle = 1.5 * .pi + theta
            
            path.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            path.addLine(to: CGPoint(x: cx + r * cos(endAngle), y: cy + r * sin(endAngle)))
            path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: endAngle, endAngle: startAngle, clockwise: true)
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

import AppKit
import LayoutDCore

final class CanvasView: NSView {
    var project: BookProject? {
        didSet { updateFrame() }
    }

    var document: LaidOutDocument? {
        didSet {
            updateFrame()
            needsDisplay = true
        }
    }

    var highlightedFrameId: UUID? {
        didSet { needsDisplay = true }
    }

    var selectedFrameId: UUID? {
        didSet { needsDisplay = true }
    }

    var onFrameSelected: ((UUID?) -> Void)?

    private(set) var zoomScale: CGFloat = 1.15
    private let pageGap: CGFloat = 36
    private let canvasInset: CGFloat = 42

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.84, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    func zoomIn() {
        setZoomScale(zoomScale * 1.2)
    }

    func zoomOut() {
        setZoomScale(zoomScale / 1.2)
    }

    func resetZoom() {
        setZoomScale(1.0)
    }

    func fitWidth(availableWidth: CGFloat) {
        guard let project else {
            return
        }
        let pageWidth = CGFloat(project.pageSetup.pageSize.width)
        let targetScale = max((availableWidth - canvasInset * 2) / pageWidth, 0.25)
        setZoomScale(targetScale)
    }

    func scrollToPage(number: Int) {
        guard let pageRect = pageRect(number: number) else {
            return
        }
        scrollToVisible(pageRect.insetBy(dx: -24, dy: -24))
    }

    private func setZoomScale(_ scale: CGFloat) {
        zoomScale = min(max(scale, 0.35), 3.0)
        updateFrame()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let project, let document else { return }

        for page in document.pages {
            draw(page: page, project: project)
        }
    }

    private func draw(page: LaidOutPage, project: BookProject) {
        guard let pageRect = pageRect(number: page.number) else {
            return
        }

        NSColor.white.setFill()
        pageRect.fill()
        NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
        NSBezierPath(rect: pageRect).stroke()

        // Draw padlock icon if the page is locked
        if project.safeLockedPages.contains(page.number) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14)
            ]
            "🔒".draw(at: CGPoint(x: pageRect.maxX - 28, y: pageRect.minY + 12), withAttributes: attributes)
        }

        // Draw spine guide line if facing pages is enabled and it's not the cover page
        if project.pageSetup.facingPages && page.number > 1 {
            NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.0
            let spineX = page.number % 2 == 0 ? pageRect.maxX : pageRect.minX
            path.move(to: CGPoint(x: spineX, y: pageRect.minY))
            path.line(to: CGPoint(x: spineX, y: pageRect.maxY))
            path.stroke()
        }

        drawGuides(project: project, pageRect: pageRect, pageNumber: page.number)

        for frame in page.frames {
            draw(frame: frame, project: project, pageRect: pageRect)
        }

        drawPageNumber(page.number, project: project, pageRect: pageRect)
    }

    private func drawGuides(project: BookProject, pageRect: CGRect, pageNumber: Int) {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        let leftMargin: CGFloat
        let rightMargin: CGFloat
        if setup.facingPages {
            leftMargin = CGFloat(pageNumber % 2 == 1 ? margins.left : margins.right)
            rightMargin = CGFloat(pageNumber % 2 == 1 ? margins.right : margins.left)
        } else {
            leftMargin = CGFloat(margins.left)
            rightMargin = CGFloat(margins.right)
        }

        let marginRect = CGRect(
            x: pageRect.minX + leftMargin * zoomScale,
            y: pageRect.minY + CGFloat(margins.top) * zoomScale,
            width: CGFloat(setup.pageSize.width - Double(leftMargin + rightMargin)) * zoomScale,
            height: CGFloat(setup.pageSize.height - margins.top - margins.bottom) * zoomScale
        )
        NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.47, alpha: 0.25).setStroke()
        NSBezierPath(rect: marginRect).stroke()
    }

    private func draw(frame: PageFrame, project: BookProject, pageRect: CGRect) {
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

        let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote) ? CGFloat(style.fontSize * 0.5) : 0.0

        let rect = CGRect(
            x: pageRect.minX + CGFloat(frame.rect.x) * zoomScale,
            y: pageRect.minY + CGFloat(frame.rect.y) * zoomScale,
            width: (CGFloat(frame.rect.width) + extraWidth) * zoomScale,
            height: CGFloat(frame.rect.height) * zoomScale
        )

        if frame.kind == .footnoteDivider {
            NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).setFill()
            rect.fill()
            return
        }

        switch frame.content {
        case .text(let text):
            drawText(text, styleId: frame.styleId, project: project, rect: rect, kind: frame.kind)
        case .asset(let assetId):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: nil, project: project, rect: rect)
        case .spreadAsset(let assetId, let isLeftHalf):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: isLeftHalf, project: project, rect: rect)
        case .empty:
            break
        }

        if frame.id == highlightedFrameId {
            NSColor.red.withAlphaComponent(0.15).setFill()
            rect.fill()
            NSColor.red.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2.0
            path.stroke()
        }

        if frame.id == selectedFrameId {
            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.15).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2.0
            path.stroke()
        }
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, rect: CGRect, kind: PageFrameKind) {
        if kind == .callout || kind == .table {
            NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1).setStroke()
            NSBezierPath(rect: rect).stroke()
        }

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

        let font = NSFont(name: style.fontName, size: CGFloat(style.fontSize) * zoomScale) ?? .systemFont(ofSize: CGFloat(style.fontSize) * zoomScale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(CGFloat(style.lineHeight - style.fontSize), 0) * zoomScale
        paragraph.firstLineHeadIndent = CGFloat(style.firstLineIndent) * zoomScale

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let attrString = NSMutableAttributedString(string: text, attributes: attributes)
        ChineseTypesetting.applyPunctuationCompression(to: attrString, fontSize: Double(font.pointSize))
        attrString.draw(in: rect.insetBy(dx: 4, dy: 2))
    }

    private func drawAssetPlaceholder(assetId: UUID, isLeftHalf: Bool?, project: BookProject, rect: CGRect) {
        let asset = project.assets.first { $0.id == assetId }
        if let image = loadImage(asset: asset) {
            drawImage(image, isLeftHalf: isLeftHalf, rect: rect, project: project)
            drawImageLabel(asset?.fileName ?? "Image", in: rect)
            return
        }

        NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
        rect.fill()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        NSBezierPath(rect: rect).stroke()

        let label = asset?.fileName ?? "Image"
        drawImageLabel(label, in: rect)
    }

    private func loadImage(asset: Asset?) -> NSImage? {
        guard let sourcePath = asset?.sourcePath else {
            return nil
        }
        return NSImage(contentsOfFile: sourcePath)
    }

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, rect: CGRect, project: BookProject) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        rect.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        let path = NSBezierPath(rect: rect)
        path.addClip()

        if let isLeft = isLeftHalf {
            let pageSize = project.pageSetup.pageSize
            let leftMargin = pageLeftMargin(for: 2, project: project)
            let rightMargin = pageRightMargin(for: 3, project: project)
            let leftWidth = CGFloat(pageSize.width - leftMargin) * zoomScale
            let rightWidth = CGFloat(pageSize.width - rightMargin) * zoomScale
            let totalWidth = leftWidth + rightWidth

            let drawRect: CGRect
            if isLeft {
                drawRect = CGRect(x: rect.minX, y: rect.minY, width: totalWidth, height: rect.height)
            } else {
                drawRect = CGRect(x: rect.minX - leftWidth, y: rect.minY, width: totalWidth, height: rect.height)
            }
            image.draw(in: drawRect)
        } else {
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
            image.draw(in: drawRect)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        NSBezierPath(rect: rect).stroke()
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

    private func drawImageLabel(_ label: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: attributes)
    }

    private func drawPageNumber(_ number: Int, project: BookProject, pageRect: CGRect) {
        guard project.resolvedShowHeadersFooters(for: number) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.gray
        ]
        let numStr = "\(number)"
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: number)
        
        if setup.facingPages {
            let leftMargin = CGFloat(number % 2 == 1 ? margins.left : margins.right)
            let rightMargin = CGFloat(number % 2 == 1 ? margins.right : margins.left)
            let x: CGFloat
            if number % 2 == 0 {
                // Left page, bottom left
                x = pageRect.minX + leftMargin * zoomScale
            } else {
                // Right page, bottom right
                let numSize = numStr.size(withAttributes: attributes)
                x = pageRect.maxX - rightMargin * zoomScale - numSize.width
            }
            numStr.draw(at: CGPoint(x: x, y: pageRect.maxY - 24), withAttributes: attributes)
        } else {
            numStr.draw(
                at: CGPoint(x: pageRect.midX - 4, y: pageRect.maxY - 24),
                withAttributes: attributes
            )
        }
    }

    private func updateFrame() {
        guard let project, let document else { return }
        let pageSize = project.pageSetup.pageSize
        let pageWidth = CGFloat(pageSize.width) * zoomScale
        let pageHeight = CGFloat(pageSize.height) * zoomScale
        
        if project.pageSetup.facingPages {
            let width = pageWidth * 2 + canvasInset * 2
            let S_max = document.pages.count / 2
            let height = canvasInset * 2 + CGFloat(S_max + 1) * pageHeight + CGFloat(S_max) * pageGap
            frame = CGRect(x: 0, y: 0, width: width, height: height)
        } else {
            let height = canvasInset * 2
                + CGFloat(document.pages.count) * pageHeight
                + CGFloat(max(document.pages.count - 1, 0)) * pageGap
            frame = CGRect(
                x: 0,
                y: 0,
                width: pageWidth + canvasInset * 2,
                height: height
            )
        }
    }

    private func pageRect(number: Int) -> CGRect? {
        guard let project, let document, document.pages.contains(where: { $0.number == number }) else {
            return nil
        }

        let pageSize = project.pageSetup.pageSize
        let pageWidth = CGFloat(pageSize.width) * zoomScale
        let pageHeight = CGFloat(pageSize.height) * zoomScale
        
        if project.pageSetup.facingPages {
            let centerX = canvasInset + pageWidth
            if number == 1 {
                return CGRect(x: centerX, y: canvasInset, width: pageWidth, height: pageHeight)
            } else {
                let S = number / 2
                let y = canvasInset + CGFloat(S) * (pageHeight + pageGap)
                let x = number % 2 == 0 ? centerX - pageWidth : centerX
                return CGRect(x: x, y: y, width: pageWidth, height: pageHeight)
            }
        } else {
            return CGRect(
                x: canvasInset,
                y: canvasInset + CGFloat(number - 1) * (pageHeight + pageGap),
                width: pageWidth,
                height: pageHeight
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard project != nil, let document else { return }

        var hitFrame: PageFrame? = nil

        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            if pRect.contains(point) {
                let localX = (point.x - pRect.minX) / zoomScale
                let localY = (point.y - pRect.minY) / zoomScale
                
                if let found = page.frames.reversed().first(where: { frame in
                    let fRect = CGRect(x: frame.rect.x, y: frame.rect.y, width: frame.rect.width, height: frame.rect.height)
                    return fRect.contains(CGPoint(x: localX, y: localY)) && frame.content != .empty
                }) {
                    hitFrame = found
                    break
                }
            }
        }

        if let frame = hitFrame {
            selectedFrameId = frame.id
            onFrameSelected?(frame.id)
        } else {
            selectedFrameId = nil
            onFrameSelected?(nil)
        }
    }
}

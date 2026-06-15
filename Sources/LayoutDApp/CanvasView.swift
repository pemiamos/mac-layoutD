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

        drawGuides(project: project, pageRect: pageRect)

        for frame in page.frames {
            draw(frame: frame, project: project, pageRect: pageRect)
        }

        drawPageNumber(page.number, pageRect: pageRect)
    }

    private func drawGuides(project: BookProject, pageRect: CGRect) {
        let setup = project.pageSetup
        let marginRect = CGRect(
            x: pageRect.minX + CGFloat(setup.margins.left) * zoomScale,
            y: pageRect.minY + CGFloat(setup.margins.top) * zoomScale,
            width: CGFloat(setup.pageSize.width - setup.margins.left - setup.margins.right) * zoomScale,
            height: CGFloat(setup.pageSize.height - setup.margins.top - setup.margins.bottom) * zoomScale
        )
        NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.47, alpha: 0.25).setStroke()
        NSBezierPath(rect: marginRect).stroke()
    }

    private func draw(frame: PageFrame, project: BookProject, pageRect: CGRect) {
        let rect = CGRect(
            x: pageRect.minX + CGFloat(frame.rect.x) * zoomScale,
            y: pageRect.minY + CGFloat(frame.rect.y) * zoomScale,
            width: CGFloat(frame.rect.width) * zoomScale,
            height: CGFloat(frame.rect.height) * zoomScale
        )

        switch frame.content {
        case .text(let text):
            drawText(text, styleId: frame.styleId, project: project, rect: rect, kind: frame.kind)
        case .asset(let assetId):
            drawAssetPlaceholder(assetId: assetId, project: project, rect: rect)
        case .empty:
            break
        }
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, rect: CGRect, kind: PageFrameKind) {
        if kind == .callout || kind == .table {
            NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.93, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1).setStroke()
            NSBezierPath(rect: rect).stroke()
        }

        let style = project.styles.paragraphStyle(id: styleId ?? StyleID.body.rawValue)
        let font = NSFont(name: style.fontName, size: CGFloat(style.fontSize) * zoomScale) ?? .systemFont(ofSize: CGFloat(style.fontSize) * zoomScale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(CGFloat(style.lineHeight - style.fontSize), 0) * zoomScale
        paragraph.firstLineHeadIndent = CGFloat(style.firstLineIndent) * zoomScale

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1),
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect.insetBy(dx: 4, dy: 2), withAttributes: attributes)
    }

    private func drawAssetPlaceholder(assetId: UUID, project: BookProject, rect: CGRect) {
        let asset = project.assets.first { $0.id == assetId }
        if let image = loadImage(asset: asset) {
            drawImage(image, in: rect)
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

    private func drawImage(_ image: NSImage, in rect: CGRect) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        rect.fill()

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

        image.draw(in: drawRect)
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        NSBezierPath(rect: rect).stroke()
    }

    private func drawImageLabel(_ label: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: attributes)
    }

    private func drawPageNumber(_ number: Int, pageRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.gray
        ]
        "\(number)".draw(
            at: CGPoint(x: pageRect.midX - 4, y: pageRect.maxY - 24),
            withAttributes: attributes
        )
    }

    private func updateFrame() {
        guard let project, let document else { return }
        let pageSize = project.pageSetup.pageSize
        let height = canvasInset * 2
            + CGFloat(document.pages.count) * CGFloat(pageSize.height) * zoomScale
            + CGFloat(max(document.pages.count - 1, 0)) * pageGap
        frame = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(pageSize.width) * zoomScale + canvasInset * 2,
            height: height
        )
    }

    private func pageRect(number: Int) -> CGRect? {
        guard let project, let document, document.pages.contains(where: { $0.number == number }) else {
            return nil
        }

        let pageSize = project.pageSetup.pageSize
        return CGRect(
            x: canvasInset,
            y: canvasInset + CGFloat(number - 1) * (CGFloat(pageSize.height) * zoomScale + pageGap),
            width: CGFloat(pageSize.width) * zoomScale,
            height: CGFloat(pageSize.height) * zoomScale
        )
    }
}

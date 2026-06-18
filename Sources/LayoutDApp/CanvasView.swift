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

    var activeScreenMode: ScreenMode = .normal {
        didSet { needsDisplay = true }
    }

    var activeTool: LayoutTool = .selection {
        didSet {
            activeGap = nil
            needsDisplay = true
        }
    }

    var frameBackgroundColors: [UUID: NSColor] = [:] {
        didSet { needsDisplay = true }
    }

    var frameStrokeColors: [UUID: NSColor] = [:] {
        didSet { needsDisplay = true }
    }

    var frameTextColors: [UUID: NSColor] = [:] {
        didSet { needsDisplay = true }
    }

    var onFrameSelected: ((UUID?) -> Void)?
    var onCanvasClick: ((Int, CGPoint) -> Void)?
    var onFrameDragged: ((UUID, Double, Double, Double, Double) -> Void)?
    var onGapDragged: ((UUID, Rect, UUID, Rect) -> Void)?
    var onPageSelected: ((Int) -> Void)?

    struct GapInfo {
        var isVerticalGap: Bool
        var rect: CGRect
        var firstFrameId: UUID
        var secondFrameId: UUID
    }

    private var activeGap: GapInfo? {
        didSet {
            if oldValue?.rect != activeGap?.rect {
                needsDisplay = true
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isDraggingFrame = false
    private var isResizingFrame = false
    private var activeResizeHandleIndex: Int?
    private var dragStartFrameRect: Rect?
    private var dragStartLocalPoint: CGPoint? // absolute canvas point
    
    // Hand tool panning
    private var dragStartPoint: NSPoint?
    private var scrollStartOrigin: NSPoint?
    
    // Gap tool dragging
    private var isDraggingGap = false
    private var dragStartFirstFrameRect: Rect?
    private var dragStartSecondFrameRect: Rect?

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
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

        if activeTool == .gap, let gap = activeGap {
            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.45).setFill()
            let path = NSBezierPath(rect: gap.rect)
            path.fill()
            
            NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.8).setStroke()
            path.lineWidth = 1.0
            path.stroke()
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

        // Draw bleed boundary
        if activeScreenMode == .normal {
            let bleedMM = project.pageSetup.bleedMM ?? 3.0
            let bleedPoints = CGFloat(bleedMM * 72.0 / 25.4)
            let bleedOffset = bleedPoints * zoomScale
            let bleedRect = pageRect.insetBy(dx: -bleedOffset, dy: -bleedOffset)
            
            let bleedPath = NSBezierPath(rect: bleedRect)
            bleedPath.lineWidth = 1.0
            let dashedPattern: [CGFloat] = [4.0, 4.0]
            bleedPath.setLineDash(dashedPattern, count: dashedPattern.count, phase: 0.0)
            NSColor.red.setStroke()
            bleedPath.stroke()
        }

        // Draw padlock icon if the page is locked
        if project.safeLockedPages.contains(page.number) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14)
            ]
            "🔒".draw(at: CGPoint(x: pageRect.maxX - 28, y: pageRect.minY + 12), withAttributes: attributes)
        }

        // Draw spine guide line if facing pages is enabled and it's not the cover page
        if activeScreenMode == .normal && project.pageSetup.facingPages && page.number > 1 {
            NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.0
            let spineX = page.number % 2 == 0 ? pageRect.maxX : pageRect.minX
            path.move(to: CGPoint(x: spineX, y: pageRect.minY))
            path.line(to: CGPoint(x: spineX, y: pageRect.maxY))
            path.stroke()
        }

        if activeScreenMode == .normal {
            drawGuides(project: project, pageRect: pageRect, pageNumber: page.number)
        }

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

        // Draw background color override if any
        if let bgColor = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) {
            bgColor.setFill()
            rect.fill()
        }

        switch frame.content {
        case .text(let text):
            let textColor = resolvedColor(memoryColor: frameTextColors[frame.id], persistedHex: frame.textColorHex)
            let hasBg = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) != nil
            drawText(text, styleId: frame.styleId, project: project, rect: rect, kind: frame.kind, textColorOverride: textColor, hasBgColorOverride: hasBg)
        case .asset(let assetId):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: nil, project: project, rect: rect)
        case .spreadAsset(let assetId, let isLeftHalf):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: isLeftHalf, project: project, rect: rect)
        case .empty:
            break
        }

        // Draw stroke color override if any
        if let strokeColor = resolvedColor(memoryColor: frameStrokeColors[frame.id], persistedHex: frame.strokeColorHex) {
            strokeColor.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = CGFloat(frame.strokeWidth ?? 1.5)
            path.stroke()
        }

        if activeScreenMode == .normal {
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

                if activeTool == .selection {
                    let handles = resizeHandles(for: rect)
                    NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                    NSColor.white.setFill()
                    for hRect in handles {
                        let hPath = NSBezierPath(rect: hRect)
                        hPath.lineWidth = 1.0
                        hPath.fill()
                        hPath.stroke()
                    }
                }
            }

            if activeTool == .directSelection && frame.id == selectedFrameId && frame.kind == .image {
                if case .asset(let assetId) = frame.content,
                   let asset = project.assets.first(where: { $0.id == assetId }),
                   let image = loadImage(asset: asset) {
                    let imageSize = image.size
                    if imageSize.width > 0 && imageSize.height > 0 {
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

                        NSColor.orange.setStroke()
                        let outlinePath = NSBezierPath(rect: drawRect)
                        outlinePath.lineWidth = 1.5
                        outlinePath.stroke()

                        let center = CGPoint(x: drawRect.midX, y: drawRect.midY)
                        let outerRect = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
                        let innerRect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)

                        NSColor.orange.withAlphaComponent(0.2).setFill()
                        NSBezierPath(ovalIn: outerRect).fill()

                        NSColor.orange.setStroke()
                        let outerPath = NSBezierPath(ovalIn: outerRect)
                        outerPath.lineWidth = 1.5
                        outerPath.stroke()

                        let innerPath = NSBezierPath(ovalIn: innerRect)
                        innerPath.lineWidth = 1.0
                        innerPath.stroke()
                    }
                }
            }
        }
    }

    private func drawText(_ text: String, styleId: String?, project: BookProject, rect: CGRect, kind: PageFrameKind, textColorOverride: NSColor? = nil, hasBgColorOverride: Bool = false) {
        if (kind == .callout || kind == .table) && !hasBgColorOverride {
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

        let textColor = textColorOverride ?? NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let attrString = NSMutableAttributedString(string: text, attributes: attributes)
        ChineseTypesetting.applyPunctuationCompression(to: attrString, fontSize: Double(font.pointSize))
        attrString.draw(in: rect.insetBy(dx: 4, dy: 2))
    }

    private func resolvedColor(memoryColor: NSColor?, persistedHex: String?) -> NSColor? {
        memoryColor ?? persistedHex.flatMap(NSColor.fromHex)
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

    private func findFrame(id: UUID, in document: LaidOutDocument) -> (frame: PageFrame, pageNumber: Int)? {
        for page in document.pages {
            if let frame = page.frames.first(where: { $0.id == id }) {
                return (frame, page.number)
            }
        }
        return nil
    }

    private func resizeHandles(for rect: CGRect) -> [CGRect] {
        let size: CGFloat = 6.0
        let half = size / 2.0
        return [
            CGRect(x: rect.minX - half, y: rect.minY - half, width: size, height: size), // Top-Left (0)
            CGRect(x: rect.midX - half, y: rect.minY - half, width: size, height: size), // Top-Middle (1)
            CGRect(x: rect.maxX - half, y: rect.minY - half, width: size, height: size), // Top-Right (2)
            CGRect(x: rect.maxX - half, y: rect.midY - half, width: size, height: size), // Middle-Right (3)
            CGRect(x: rect.maxX - half, y: rect.maxY - half, width: size, height: size), // Bottom-Right (4)
            CGRect(x: rect.midX - half, y: rect.maxY - half, width: size, height: size), // Bottom-Middle (5)
            CGRect(x: rect.minX - half, y: rect.maxY - half, width: size, height: size), // Bottom-Left (6)
            CGRect(x: rect.minX - half, y: rect.midY - half, width: size, height: size)  // Middle-Left (7)
        ]
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if activeTool == .hand {
            NSCursor.openHand.set()
            return
        }
        
        if activeTool == .zoom {
            NSCursor.crosshair.set()
            return
        }
        
        if activeTool == .gap {
            detectGap(at: point)
            if let gap = activeGap {
                if gap.isVerticalGap {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.resizeUpDown.set()
                }
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        
        NSCursor.arrow.set()
    }

    private func detectGap(at point: CGPoint) {
        guard let project, let document else {
            activeGap = nil
            return
        }
        
        let threshold: CGFloat = 30.0 // maximum gap size to detect
        
        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            if pRect.contains(point) {
                let frames = page.frames
                guard frames.count >= 2 else { continue }
                
                for i in 0..<frames.count {
                    for j in 0..<frames.count {
                        if i == j { continue }
                        let frameA = frames[i]
                        let frameB = frames[j]
                        
                        let extraWidthA = (frameA.kind == .text || frameA.kind == .footnote || frameA.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frameA.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                        let extraWidthB = (frameB.kind == .text || frameB.kind == .footnote || frameB.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frameB.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                        
                        let rectA = CGRect(
                            x: pRect.minX + CGFloat(frameA.rect.x) * zoomScale,
                            y: pRect.minY + CGFloat(frameA.rect.y) * zoomScale,
                            width: (CGFloat(frameA.rect.width) + extraWidthA) * zoomScale,
                            height: CGFloat(frameA.rect.height) * zoomScale
                        )
                        
                        let rectB = CGRect(
                            x: pRect.minX + CGFloat(frameB.rect.x) * zoomScale,
                            y: pRect.minY + CGFloat(frameB.rect.y) * zoomScale,
                            width: (CGFloat(frameB.rect.width) + extraWidthB) * zoomScale,
                            height: CGFloat(frameB.rect.height) * zoomScale
                        )
                        
                        // Vertical Gap (A left of B)
                        if rectA.maxX < rectB.minX {
                            let gapDist = rectB.minX - rectA.maxX
                            if gapDist > 0 && gapDist < threshold {
                                let overlapYMin = max(rectA.minY, rectB.minY)
                                let overlapYMax = min(rectA.maxY, rectB.maxY)
                                if overlapYMin < overlapYMax {
                                    let gapRect = CGRect(x: rectA.maxX, y: overlapYMin, width: gapDist, height: overlapYMax - overlapYMin)
                                    if gapRect.contains(point) {
                                        activeGap = GapInfo(isVerticalGap: true, rect: gapRect, firstFrameId: frameA.id, secondFrameId: frameB.id)
                                        return
                                    }
                                }
                            }
                        }
                        
                        // Horizontal Gap (A above B)
                        if rectA.maxY < rectB.minY {
                            let gapDist = rectB.minY - rectA.maxY
                            if gapDist > 0 && gapDist < threshold {
                                let overlapXMin = max(rectA.minX, rectB.minX)
                                let overlapXMax = min(rectA.maxX, rectB.maxX)
                                if overlapXMin < overlapXMax {
                                    let gapRect = CGRect(x: overlapXMin, y: rectA.maxY, width: overlapXMax - overlapXMin, height: gapDist)
                                    if gapRect.contains(point) {
                                        activeGap = GapInfo(isVerticalGap: false, rect: gapRect, firstFrameId: frameA.id, secondFrameId: frameB.id)
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        activeGap = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let project, let document else { return }

        // 1. Hand tool
        if activeTool == .hand {
            dragStartPoint = event.locationInWindow
            if let scrollView = enclosingScrollView {
                scrollStartOrigin = scrollView.contentView.bounds.origin
            }
            NSCursor.closedHand.set()
            return
        }

        // 2. Zoom tool
        if activeTool == .zoom {
            let isOption = event.modifierFlags.contains(.option)
            if isOption {
                zoomOut()
            } else {
                zoomIn()
            }
            return
        }

        // Detect clicked page and frame
        var hitFrame: PageFrame? = nil
        var clickedPageNumber: Int? = nil
        var localPoint: CGPoint? = nil

        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            if pRect.contains(point) {
                clickedPageNumber = page.number
                let localX = (point.x - pRect.minX) / zoomScale
                let localY = (point.y - pRect.minY) / zoomScale
                localPoint = CGPoint(x: localX, y: localY)
                
                if let found = page.frames.reversed().first(where: { frame in
                    let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
                    let fRect = CGRect(x: frame.rect.x, y: frame.rect.y, width: frame.rect.width + extraWidth, height: frame.rect.height)
                    return fRect.contains(CGPoint(x: localX, y: localY))
                }) {
                    hitFrame = found
                    break
                }
            }
        }

        // 3. Page tool selection
        if activeTool == .page, let pageNum = clickedPageNumber {
            onPageSelected?(pageNum)
            return
        }

        // 4. Gap tool dragging
        if activeTool == .gap, let gap = activeGap {
            isDraggingGap = true
            dragStartLocalPoint = point
            
            if let fFrame = findFrame(id: gap.firstFrameId, in: document) {
                dragStartFirstFrameRect = fFrame.frame.rect
            }
            if let sFrame = findFrame(id: gap.secondFrameId, in: document) {
                dragStartSecondFrameRect = sFrame.frame.rect
            }
            return
        }

        // 5. Selection resize handle hit test
        if activeTool == .selection,
           let selId = selectedFrameId,
           let selFrameInfo = findFrame(id: selId, in: document),
           let pRect = pageRect(number: selFrameInfo.pageNumber) {
            
            let extraWidth = (selFrameInfo.frame.kind == .text || selFrameInfo.frame.kind == .footnote || selFrameInfo.frame.kind == .sideNote) ? CGFloat(project.styles.paragraphStyle(id: selFrameInfo.frame.styleId ?? StyleID.body.rawValue).fontSize * 0.5) : 0.0
            let rect = CGRect(
                x: pRect.minX + CGFloat(selFrameInfo.frame.rect.x) * zoomScale,
                y: pRect.minY + CGFloat(selFrameInfo.frame.rect.y) * zoomScale,
                width: (CGFloat(selFrameInfo.frame.rect.width) + extraWidth) * zoomScale,
                height: CGFloat(selFrameInfo.frame.rect.height) * zoomScale
            )
            
            let handles = resizeHandles(for: rect)
            if let index = handles.firstIndex(where: { $0.contains(point) }) {
                isResizingFrame = true
                activeResizeHandleIndex = index
                dragStartFrameRect = selFrameInfo.frame.rect
                dragStartLocalPoint = point
                return
            }
        }

        // 6. Selection or Direct Selection click selection and drag start
        if activeTool == .selection || activeTool == .directSelection {
            if let frame = hitFrame {
                selectedFrameId = frame.id
                onFrameSelected?(frame.id)
                
                isDraggingFrame = true
                dragStartFrameRect = frame.rect
                dragStartLocalPoint = point
            } else {
                selectedFrameId = nil
                onFrameSelected?(nil)
            }
            return
        }

        // Click on empty canvas to create text/image frames for drawing tools
        if let pageNum = clickedPageNumber, let localPt = localPoint {
            onCanvasClick?(pageNum, localPt)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 1. Hand tool panning
        if activeTool == .hand, let startPt = dragStartPoint, let startOrigin = scrollStartOrigin, let scrollView = enclosingScrollView {
            let dx = event.locationInWindow.x - startPt.x
            let dy = event.locationInWindow.y - startPt.y
            
            var newOrigin = NSPoint(
                x: startOrigin.x - dx,
                y: startOrigin.y - dy
            )
            let maxOriginX = max(0.0, bounds.width - scrollView.contentView.bounds.width)
            let maxOriginY = max(0.0, bounds.height - scrollView.contentView.bounds.height)
            newOrigin.x = min(max(newOrigin.x, 0), maxOriginX)
            newOrigin.y = min(max(newOrigin.y, 0), maxOriginY)
            
            scrollView.contentView.scroll(to: newOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        // 2. Selection tool moving
        if isDraggingFrame, let selId = selectedFrameId, let startRect = dragStartFrameRect, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            
            onFrameDragged?(selId, startRect.x + dx, startRect.y + dy, startRect.width, startRect.height)
            return
        }

        // 3. Selection tool resizing
        if isResizingFrame, let selId = selectedFrameId, let startRect = dragStartFrameRect, let startPt = dragStartLocalPoint, let handleIdx = activeResizeHandleIndex {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            
            var newX = startRect.x
            var newY = startRect.y
            var newW = startRect.width
            var newH = startRect.height
            
            let minW = 10.0
            let minH = 10.0
            
            switch handleIdx {
            case 0: // Top-Left
                let targetW = startRect.width - dx
                let targetH = startRect.height - dy
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 1: // Top-Middle
                let targetH = startRect.height - dy
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 2: // Top-Right
                let targetW = startRect.width + dx
                let targetH = startRect.height - dy
                if targetW >= minW {
                    newW = targetW
                }
                if targetH >= minH {
                    newY = startRect.y + dy
                    newH = targetH
                }
            case 3: // Middle-Right
                let targetW = startRect.width + dx
                if targetW >= minW {
                    newW = targetW
                }
            case 4: // Bottom-Right
                let targetW = startRect.width + dx
                let targetH = startRect.height + dy
                if targetW >= minW {
                    newW = targetW
                }
                if targetH >= minH {
                    newH = targetH
                }
            case 5: // Bottom-Middle
                let targetH = startRect.height + dy
                if targetH >= minH {
                    newH = targetH
                }
            case 6: // Bottom-Left
                let targetW = startRect.width - dx
                let targetH = startRect.height + dy
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
                if targetH >= minH {
                    newH = targetH
                }
            case 7: // Middle-Left
                let targetW = startRect.width - dx
                if targetW >= minW {
                    newX = startRect.x + dx
                    newW = targetW
                }
            default:
                break
            }
            
            onFrameDragged?(selId, newX, newY, newW, newH)
            return
        }

        // 4. Gap tool resizing
        if isDraggingGap, let gap = activeGap, let startFirst = dragStartFirstFrameRect, let startSecond = dragStartSecondFrameRect, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            
            if gap.isVerticalGap {
                let minW = 10.0
                let targetW1 = startFirst.width + dx
                let targetW2 = startSecond.width - dx
                if targetW1 >= minW && targetW2 >= minW {
                    let firstRect = Rect(x: startFirst.x, y: startFirst.y, width: targetW1, height: startFirst.height)
                    let secondRect = Rect(x: startSecond.x + dx, y: startSecond.y, width: targetW2, height: startSecond.height)
                    onGapDragged?(gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                }
            } else {
                let minH = 10.0
                let targetH1 = startFirst.height + dy
                let targetH2 = startSecond.height - dy
                if targetH1 >= minH && targetH2 >= minH {
                    let firstRect = Rect(x: startFirst.x, y: startFirst.y, width: startFirst.width, height: targetH1)
                    let secondRect = Rect(x: startSecond.x, y: startSecond.y + dy, width: startSecond.width, height: targetH2)
                    onGapDragged?(gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingFrame = false
        isResizingFrame = false
        isDraggingGap = false
        activeResizeHandleIndex = nil
        dragStartFrameRect = nil
        dragStartLocalPoint = nil
        dragStartFirstFrameRect = nil
        dragStartSecondFrameRect = nil
        dragStartPoint = nil
        scrollStartOrigin = nil
        
        if activeTool == .hand {
            NSCursor.openHand.set()
        }
    }
}

private extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }

        guard cleanHex.count == 6 else {
            return nil
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else {
            return nil
        }

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

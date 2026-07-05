import AppKit
import LayoutDCore

final class CanvasView: NSView {
    var project: BookProject? {
        didSet { updateFrame() }
    }

    var document: LaidOutDocument? {
        didSet {
            // A relayout (e.g. after committing an edit) invalidates the overlay's
            // position; drop it rather than let it float over stale geometry.
            teardownInlineEditor()
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

    /// Full multi-selection (superset of `selectedFrameId`). Every member is drawn
    /// highlighted; resize handles show only when exactly one frame is selected.
    var selectedFrameIds: Set<UUID> = [] {
        didSet { needsDisplay = true }
    }

    var activeScreenMode: ScreenMode = .normal {
        didSet { needsDisplay = true }
    }

    var activeTool: LayoutTool = .selection {
        didSet {
            activeGap = nil
            if activeTool != oldValue { commitInlineEditor() }
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
    /// Shift/⌘-click on a frame: toggle its membership in the multi-selection.
    var onToggleSelection: ((UUID) -> Void)?
    /// Rubber-band (marquee) selection finished. Payload: every frame intersecting
    /// the marquee (empty set clears the selection).
    var onMarqueeSelected: ((Set<UUID>) -> Void)?
    var onCanvasClick: ((Int, CGPoint) -> Void)?
    var onFrameDragged: ((UUID, Double, Double, Double, Double) -> Void)?
    /// Group-drag commit: new page-local rects for every moved frame, applied in one
    /// undoable step. Used when 2+ frames are dragged together.
    var onFramesDragged: (([(id: UUID, rect: Rect)]) -> Void)?
    /// A line's endpoint was dragged → new page-local bounding rect for the line.
    var onLineEndpointDragged: ((UUID, Rect) -> Void)?
    var onGapDragged: ((UUID, Rect, UUID, Rect) -> Void)?
    var onPageSelected: ((Int) -> Void)?
    var onDragStarted: (() -> Void)?
    /// A text/image frame was drawn (rubber-band). Payload: page number + page-local rect.
    var onFrameDrawn: ((Int, Rect) -> Void)?
    /// A single-key toolbox shortcut was pressed while the canvas had focus.
    var onToolShortcut: ((LayoutTool) -> Void)?
    /// In-place text editing finished (double-click a text/caption frame). Payload:
    /// frame id + the new text. Wired to AppState.updateSelectedFrameText.
    var onFrameTextEdited: ((UUID, String) -> Void)?

    // In-place (double-click) text editor overlay
    private var inlineEditor: InlineTextEditorView?
    private var inlineEditingFrameId: UUID?
    var baselineDocument: LaidOutDocument? {
        didSet {
            needsDisplay = true
        }
    }

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
    private var previewFrameRects: [UUID: Rect] = [:]
    private var pendingFrameDragUpdate: (id: UUID, rect: Rect)?
    /// Group-drag: start rects (page-local) of every frame moved together, keyed by id.
    private var groupDragStartRects: [UUID: Rect] = [:]
    private var pendingGroupDragUpdate: [(id: UUID, rect: Rect)]?

    // Line endpoint drag: stretch one end of a selected line along its axis.
    private var isDraggingLineEndpoint = false
    private var lineEndpointFrameId: UUID?
    private var lineEndpointHorizontal = false
    private var lineEndpointFixedCoord: Double = 0   // page-local along-axis coord of the fixed end
    private var lineEndpointOrigRect: Rect?          // page-local rect at drag start (perpendicular dims)
    private var pendingLineEndpointRect: Rect?

    // Marquee (rubber-band) selection state — canvas coordinates.
    private var isMarqueeSelecting = false
    private var marqueeStartPoint: CGPoint?
    private var marqueeRect: CGRect? {
        didSet {
            if oldValue != marqueeRect { needsDisplay = true }
        }
    }
    private var pendingGapDragUpdate: (firstId: UUID, firstRect: Rect, secondId: UUID, secondRect: Rect)?
    
    // Hand tool panning
    private var dragStartPoint: NSPoint?
    private var scrollStartOrigin: NSPoint?
    
    // Gap tool dragging
    private var isDraggingGap = false
    private var dragStartFirstFrameRect: Rect?
    private var dragStartSecondFrameRect: Rect?

    // Frame drawing tools (textFrame / imageFrame) rubber-band state
    private var isDrawingFrame = false
    private var drawFrameStartLocal: CGPoint?
    private var drawFramePageNumber: Int?
    private var drawFrameCurrentRect: Rect?  // page-local points

    private(set) var zoomScale: CGFloat = 1.15
    private let pageGap: CGFloat = 36
    private let canvasInset: CGFloat = 42
    /// Thin dimension (page points) of a line's bounding box. This is the click/hit
    /// area, not the visible weight — the line is drawn as a centered stroke whose
    /// width is the frame's strokeWidth, so it stays a true thin line.
    private let lineToolThickness: Double = 6

    override var isFlipped: Bool { true }

    /// Notifies the workspace when the zoom scale changes (status-bar readout).
    var onZoomChanged: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updatePasteboardColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePasteboardColor()
    }

    /// InDesign-style pasteboard: dark charcoal in dark appearance, light gray otherwise.
    private func updatePasteboardColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor(calibratedWhite: isDark ? 0.25 : 0.84, alpha: 1).cgColor
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
        // The overlay is positioned in zoomed canvas coordinates; commit it before
        // the scale changes so the edited text isn't lost and no stale box lingers.
        commitInlineEditor()
        zoomScale = min(max(scale, 0.35), 3.0)
        onZoomChanged?(zoomScale)
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

        drawRubberBandFrameIfNeeded()
        drawMarqueeIfNeeded()
    }

    /// Renders the in-progress marquee (rubber-band selection) rectangle.
    private func drawMarqueeIfNeeded() {
        guard isMarqueeSelecting, let rect = marqueeRect else { return }
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.12).setFill()
        rect.fill()
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.0
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    /// Renders the in-progress rubber-band rectangle for the frame drawing tools.
    /// Image frames get an InDesign-style diagonal-cross placeholder mark.
    private func drawRubberBandFrameIfNeeded() {
        guard isDrawingFrame,
              let rect = drawFrameCurrentRect,
              let pageNum = drawFramePageNumber,
              let pRect = pageRect(number: pageNum) else { return }

        let screenRect = CGRect(
            x: pRect.minX + CGFloat(rect.x) * zoomScale,
            y: pRect.minY + CGFloat(rect.y) * zoomScale,
            width: CGFloat(rect.width) * zoomScale,
            height: CGFloat(rect.height) * zoomScale
        )
        let color = activeTool == .imageFrame
            ? NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1)
        color.setStroke()

        // The line tool previews a dashed segment (anchor → drag point along the
        // snapped axis), not a rectangle.
        if activeTool == .line {
            let path = NSBezierPath()
            if screenRect.width >= screenRect.height {
                path.move(to: CGPoint(x: screenRect.minX, y: screenRect.midY))
                path.line(to: CGPoint(x: screenRect.maxX, y: screenRect.midY))
            } else {
                path.move(to: CGPoint(x: screenRect.midX, y: screenRect.minY))
                path.line(to: CGPoint(x: screenRect.midX, y: screenRect.maxY))
            }
            path.lineWidth = 1.0
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
            return
        }

        let path = NSBezierPath(rect: screenRect)
        path.lineWidth = 1.0
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()

        if activeTool == .imageFrame {
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: screenRect.minX, y: screenRect.minY))
            cross.line(to: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
            cross.move(to: CGPoint(x: screenRect.maxX, y: screenRect.minY))
            cross.line(to: CGPoint(x: screenRect.minX, y: screenRect.maxY))
            cross.lineWidth = 0.75
            cross.stroke()
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

        // Draw baseline diff (dashed outlines)
        if activeScreenMode == .normal,
           project.appliedLayoutPlans?[page.number] != nil,
           let baselineDocument,
           let baselinePage = baselineDocument.pages.first(where: { $0.number == page.number }) {
            
            NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 0.4).setStroke()
            for bFrame in baselinePage.frames {
                if bFrame.kind == .runningHeader {
                    continue
                }
                
                let rect = CGRect(
                    x: pageRect.minX + CGFloat(bFrame.rect.x) * zoomScale,
                    y: pageRect.minY + CGFloat(bFrame.rect.y) * zoomScale,
                    width: CGFloat(bFrame.rect.width) * zoomScale,
                    height: CGFloat(bFrame.rect.height) * zoomScale
                )
                
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 1.0
                let dashedPattern: [CGFloat] = [3.0, 3.0]
                path.setLineDash(dashedPattern, count: dashedPattern.count, phase: 0.0)
                path.stroke()
            }
        }
        
        // Draw override status label
        if activeScreenMode == .normal && project.appliedLayoutPlans?[page.number] != nil {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.08, alpha: 0.8)
            ]
            "已覆写 (Override)".draw(at: CGPoint(x: pageRect.minX + 12, y: pageRect.minY + 12), withAttributes: attributes)
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

        // Draw annotations for this page
        if let annotations = project.annotations {
            let pageAnnotations = annotations.filter { $0.pageNumber == page.number }
            for annotation in pageAnnotations {
                let x = pageRect.minX + CGFloat(annotation.x) * zoomScale
                let y = pageRect.minY + CGFloat(annotation.y) * zoomScale
                
                // Draw a small circle marker
                let markerRadius: CGFloat = 6.0 * zoomScale
                let markerRect = CGRect(x: x - markerRadius, y: y - markerRadius, width: markerRadius * 2, height: markerRadius * 2)
                let path = NSBezierPath(ovalIn: markerRect)
                NSColor.systemOrange.setFill()
                path.fill()
                NSColor.white.setStroke()
                path.lineWidth = 1.5 * zoomScale
                path.stroke()
                
                // Draw a small label box next to it
                let text = annotation.text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: min(max(8.0 * zoomScale, 7.0), 12.0)),
                    .foregroundColor: NSColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                
                let labelPadding: CGFloat = 3.0 * zoomScale
                let labelRect = CGRect(
                    x: x + markerRadius + 2.0 * zoomScale,
                    y: y - textSize.height / 2.0,
                    width: textSize.width + labelPadding * 2,
                    height: textSize.height + labelPadding
                )
                
                let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 3 * zoomScale, yRadius: 3 * zoomScale)
                NSColor.black.withAlphaComponent(0.75).setFill()
                labelPath.fill()
                
                text.draw(at: CGPoint(x: labelRect.minX + labelPadding, y: labelRect.minY + labelPadding / 2.0), withAttributes: attributes)
            }
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

        let extraWidth = (frame.kind == .text || frame.kind == .footnote || frame.kind == .sideNote || frame.kind == .runningHeader) ? CGFloat(style.fontSize * 0.5) : 0.0

        let effectiveFrameRect = previewFrameRects[frame.id] ?? frame.rect
        let rect = CGRect(
            x: pageRect.minX + CGFloat(effectiveFrameRect.x) * zoomScale,
            y: pageRect.minY + CGFloat(effectiveFrameRect.y) * zoomScale,
            width: (CGFloat(effectiveFrameRect.width) + extraWidth) * zoomScale,
            height: CGFloat(effectiveFrameRect.height) * zoomScale
        )

        // A line is a true stroke, not a filled box: draw a centered segment along its
        // long axis (weight = strokeWidth), and when selected show only two endpoint
        // handles — no bounding rectangle, no 8 resize handles.
        if frame.kind == .line {
            let horizontal = rect.width >= rect.height
            let lineColor = resolvedColor(memoryColor: frameStrokeColors[frame.id], persistedHex: frame.strokeColorHex)
                ?? NSColor.black
            let weightPx = max(CGFloat(frame.strokeWidth ?? 1) * zoomScale, 0.75)
            let p0: CGPoint, p1: CGPoint
            if horizontal {
                p0 = CGPoint(x: rect.minX, y: rect.midY)
                p1 = CGPoint(x: rect.maxX, y: rect.midY)
            } else {
                p0 = CGPoint(x: rect.midX, y: rect.minY)
                p1 = CGPoint(x: rect.midX, y: rect.maxY)
            }
            lineColor.setStroke()
            let path = NSBezierPath()
            path.move(to: p0)
            path.line(to: p1)
            path.lineWidth = weightPx
            path.stroke()

            if activeScreenMode == .normal && selectedFrameIds.contains(frame.id) {
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                let hl = NSBezierPath()
                hl.move(to: p0); hl.line(to: p1)
                hl.lineWidth = 1.0
                hl.stroke()
                if selectedFrameIds.count == 1 {
                    NSColor.white.setFill()
                    for pt in [p0, p1] {
                        let h = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                        let hp = NSBezierPath(rect: h)
                        hp.fill()
                        hp.stroke()
                    }
                }
            }
            return
        }

        if frame.kind == .footnoteDivider {
            NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).setFill()
            rect.fill()
            return
        }

        // Draw background color override if any
        if let bgColor = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) {
            bgColor.setFill()
            let path = maskPath(in: rect, shape: frame.maskShape)
            path.fill()
        }

        switch frame.content {
        case .text(let text):
            let textColor = resolvedColor(memoryColor: frameTextColors[frame.id], persistedHex: frame.textColorHex)
            let hasBg = resolvedColor(memoryColor: frameBackgroundColors[frame.id], persistedHex: frame.backgroundColorHex) != nil
            if let componentStyle = project.styles.componentStyle(for: frame.kind) {
                if !hasBg {
                    drawComponentBackground(componentStyle, project: project, rect: rect)
                }
                let componentTextColor = textColor ?? componentStyle.resolvedTextColorHex(project: project).flatMap(NSColor.fromHex)
                if frame.kind == .table {
                    drawTable(
                        text,
                        style: style,
                        componentStyle: componentStyle,
                        project: project,
                        rect: rect,
                        textColor: componentTextColor
                    )
                } else {
                    drawText(
                        text,
                        styleId: frame.styleId,
                        project: project,
                        rect: rect.insetBy(
                            dx: CGFloat(componentStyle.textInsetX) * zoomScale,
                            dy: CGFloat(componentStyle.textInsetY) * zoomScale
                        ),
                        kind: frame.kind,
                        textColorOverride: componentTextColor,
                        applyDefaultInset: false,
                        sourceParagraphId: frame.sourceParagraphId,
                        tableOfContentsEntries: frame.tableOfContentsEntries,
                        exclusionRects: frame.exclusionRects,
                        frameRect: frame.rect
                    )
                }
            } else {
                drawText(
                    text,
                    styleId: frame.styleId,
                    project: project,
                    rect: rect,
                    kind: frame.kind,
                    textColorOverride: textColor,
                    sourceParagraphId: frame.sourceParagraphId,
                    tableOfContentsEntries: frame.tableOfContentsEntries,
                    exclusionRects: frame.exclusionRects,
                    frameRect: frame.rect
                )
            }
        case .asset(let assetId):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: nil, project: project, rect: rect, maskShape: frame.maskShape)
        case .spreadAsset(let assetId, let isLeftHalf):
            drawAssetPlaceholder(assetId: assetId, isLeftHalf: isLeftHalf, project: project, rect: rect, maskShape: frame.maskShape)
        case .empty:
            break
        }

        // Draw stroke color override if any
        if let strokeColor = resolvedColor(memoryColor: frameStrokeColors[frame.id], persistedHex: frame.strokeColorHex) {
            strokeColor.setStroke()
            let path = maskPath(in: rect, shape: frame.maskShape)
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

            if selectedFrameIds.contains(frame.id) {
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 0.15).setFill()
                rect.fill()
                NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 2.0
                path.stroke()

                // Resize handles only when a single frame is selected — group resize
                // isn't supported yet, so drawing handles on a multi-selection would
                // imply an action that does nothing.
                if activeTool == .selection && selectedFrameIds.count == 1 {
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

    private func drawComponentBackground(_ style: ComponentStyle, project: BookProject, rect: CGRect) {
        if let fillHex = style.resolvedFillColorHex(project: project), let fill = NSColor.fromHex(fillHex) {
            fill.setFill()
            rect.fill()
        }
        if let strokeHex = style.resolvedStrokeColorHex(project: project), let stroke = NSColor.fromHex(strokeHex), style.strokeWidth > 0 {
            stroke.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = CGFloat(style.strokeWidth) * zoomScale
            path.stroke()
        }
        if let accentHex = style.resolvedAccentColorHex(project: project), let accent = NSColor.fromHex(accentHex), style.accentWidth > 0 {
            accent.setFill()
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: CGFloat(style.accentWidth) * zoomScale,
                height: rect.height
            ).fill()
        }
    }

    private func drawTable(
        _ text: String,
        style: ParagraphStyle,
        componentStyle: ComponentStyle,
        project: BookProject,
        rect: CGRect,
        textColor: NSColor?
    ) {
        let tableData = TableLayoutHelper.parseTableText(text)
        let colCount = tableData.columnCount
        let rowCount = tableData.rows.count
        guard colCount > 0, rowCount > 0 else { return }
        
        let strokeColor = resolvedColor(memoryColor: frameStrokeColors[NSUUID() as UUID], persistedHex: componentStyle.strokeColorHex) ?? NSColor.black
        let strokeWidth = CGFloat(componentStyle.strokeWidth) * zoomScale
        
        let colWidths = TableLayoutHelper.allocateColumnWidths(
            tableData: tableData,
            totalWidth: Double(rect.width),
            fontName: style.fontName,
            fontSize: style.fontSize,
            zoomScale: zoomScale
        )
        let rowHeights = TableLayoutHelper.calculateRowHeights(
            tableData: tableData,
            colWidths: colWidths,
            style: style,
            textInsetX: componentStyle.textInsetX,
            textInsetY: componentStyle.textInsetY,
            zoomScale: zoomScale
        )
        
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        
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
                
                cgContext.saveGState()
                if r == 0 {
                    if let accentHex = componentStyle.accentColorHex, let headerColor = NSColor.fromHex(accentHex) {
                        headerColor.withAlphaComponent(0.15).setFill()
                    } else if let fillHex = componentStyle.fillColorHex, let fillColor = NSColor.fromHex(fillHex) {
                        fillColor.withAlphaComponent(0.3).setFill()
                    } else {
                        NSColor(white: 0.9, alpha: 1).setFill()
                    }
                } else {
                    if let fillHex = componentStyle.fillColorHex, let fillColor = NSColor.fromHex(fillHex) {
                        fillColor.setFill()
                    } else {
                        NSColor.white.setFill()
                    }
                }
                cgContext.fill(cellRect)
                cgContext.restoreGState()
                
                let cellText = c < cells.count ? cells[c] : ""
                if !cellText.isEmpty {
                    let insetX = CGFloat(componentStyle.textInsetX) * zoomScale
                    let insetY = CGFloat(componentStyle.textInsetY) * zoomScale
                    let textRect = cellRect.insetBy(dx: insetX, dy: insetY)
                    
                    cgContext.saveGState()
                    cgContext.translateBy(x: textRect.minX, y: textRect.maxY)
                    cgContext.scaleBy(x: 1.0, y: -1.0)
                    
                    let attrString = ChineseTypesetting.makeAttributedString(
                        text: cellText,
                        style: style,
                        foregroundColor: (textColor ?? NSColor.black).cgColor,
                        zoomScale: zoomScale
                    )
                    
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: textRect.width, height: textRect.height), transform: nil)
                    let framesetter = CTFramesetterCreateWithAttributedString(attrString)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
                    
                    cgContext.textMatrix = .identity
                    CTFrameDraw(frame, cgContext)
                    cgContext.restoreGState()
                }
                
                currentX += cellWidth
            }
        }
        
        // Draw grid lines
        cgContext.saveGState()
        cgContext.setStrokeColor(strokeColor.cgColor)
        cgContext.setLineWidth(strokeWidth)
        
        // Outer border
        cgContext.stroke(rect)
        
        // Horizontal grid lines
        var currentLineY = rect.maxY
        for r in 0..<(rowCount - 1) {
            currentLineY -= CGFloat(rowHeights[r])
            cgContext.move(to: CGPoint(x: rect.minX, y: currentLineY))
            cgContext.addLine(to: CGPoint(x: rect.maxX, y: currentLineY))
            cgContext.strokePath()
        }
        
        // Vertical grid lines
        var currentLineX = rect.minX
        for c in 0..<(colCount - 1) {
            currentLineX += CGFloat(colWidths[c])
            cgContext.move(to: CGPoint(x: currentLineX, y: rect.minY))
            cgContext.addLine(to: CGPoint(x: currentLineX, y: rect.maxY))
            cgContext.strokePath()
        }
        
        cgContext.restoreGState()
    }

    private func drawText(
        _ text: String,
        styleId: String?,
        project: BookProject,
        rect: CGRect,
        kind: PageFrameKind,
        textColorOverride: NSColor? = nil,
        applyDefaultInset: Bool = true,
        sourceParagraphId: UUID? = nil,
        tableOfContentsEntries: [TableOfContentsEntry]? = nil,
        exclusionRects: [Rect]? = nil,
        frameRect: Rect? = nil
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

        let tokenColor = project.resolvedColorHex(style.colorToken).flatMap(NSColor.fromHex)
        let rawTextColor = textColorOverride ?? tokenColor ?? NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.14, alpha: 1)
        let textColor = proofedText(rawTextColor) ?? rawTextColor
        
        let drawingRect = applyDefaultInset ? rect.insetBy(dx: 4, dy: 2) : rect
        
        let attrString: NSAttributedString
        if let entries = tableOfContentsEntries, !entries.isEmpty {
            attrString = ChineseTypesetting.makeTOCAttributedString(
                entries: entries,
                project: project,
                containerWidth: Double(drawingRect.width),
                zoomScale: zoomScale,
                foregroundColor: textColor.cgColor
            )
        } else {
            var mappedRuns: [InlineRun]? = nil
            if let sourceParagraphId = sourceParagraphId,
               let paragraph = project.sections.lazy.flatMap(\.stories).flatMap(\.paragraphs).first(where: { $0.id == sourceParagraphId }),
               let runs = paragraph.inlineRuns {
                mappedRuns = InlineRun.mapRuns(runs, from: paragraph.text, to: text)
            }

            attrString = ChineseTypesetting.makeAttributedString(
                text: text,
                style: style,
                foregroundColor: textColor.cgColor,
                zoomScale: zoomScale,
                inlineRuns: mappedRuns
            )
        }
        
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.saveGState()
        cgContext.translateBy(x: drawingRect.minX, y: drawingRect.maxY)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: drawingRect.width, height: drawingRect.height), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        
        var frameAttributes: [CFString: Any] = [:]
        if style.layoutDirection == .vertical {
            frameAttributes[kCTFrameProgressionAttributeName] = CTFrameProgression.rightToLeft.rawValue as CFNumber
        }
        
        if let exclusionRects = exclusionRects, !exclusionRects.isEmpty, let frameRect = frameRect {
            let compStyle = project.styles.componentStyle(for: kind)
            let insetX = applyDefaultInset ? 4.0 : (compStyle?.textInsetX ?? 0.0)
            let insetY = applyDefaultInset ? 2.0 : (compStyle?.textInsetY ?? 0.0)
            let extraWidth = (kind == .text || kind == .footnote || kind == .sideNote || kind == .runningHeader) ? (style.fontSize * 0.5) : 0.0
            
            let textRectPageInset = Rect(
                x: frameRect.x + insetX,
                y: frameRect.y + insetY,
                width: max(0, frameRect.width + extraWidth - insetX * 2),
                height: max(0, frameRect.height - insetY * 2)
            )
            
            var exclusionPaths: [CGPath] = []
            for img in exclusionRects {
                let overlap = textRectPageInset.intersection(img)
                guard overlap.width > 0 && overlap.height > 0 else { continue }
                
                let localMinX = overlap.x - textRectPageInset.x
                let localMinY = textRectPageInset.y + textRectPageInset.height - (overlap.y + overlap.height)
                
                let scaledRect = CGRect(
                    x: CGFloat(localMinX) * zoomScale,
                    y: CGFloat(localMinY) * zoomScale,
                    width: CGFloat(overlap.width) * zoomScale,
                    height: CGFloat(overlap.height) * zoomScale
                )
                exclusionPaths.append(CGPath(rect: scaledRect, transform: nil))
            }
            
            if !exclusionPaths.isEmpty {
                let clippingPaths = exclusionPaths.map { [kCTFramePathClippingPathAttributeName: $0] }
                frameAttributes[kCTFrameClippingPathsAttributeName] = clippingPaths
            }
        }
        
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, frameAttributes as CFDictionary)
        
        cgContext.textMatrix = .identity
        CTFrameDraw(frame, cgContext)
        ChineseTypesetting.drawKentenDots(for: frame, in: cgContext, layoutDirection: style.layoutDirection, zoomScale: zoomScale)
        cgContext.restoreGState()
    }

    private func resolvedColor(memoryColor: NSColor?, persistedHex: String?) -> NSColor? {
        proofed(memoryColor ?? persistedHex.flatMap(NSColor.fromHex))
    }

    /// True when the document is in CMYK output mode.
    private var cmykProof: Bool {
        project?.pageSetup.colorSpace == .cmyk
    }

    /// Soft-proof: in CMYK mode, render colors through the ICC CMYK profile so
    /// RGB fills show their duller print appearance and the canvas matches
    /// InDesign instead of showing the vivid RGB. A no-op in RGB mode.
    private func proofed(_ color: NSColor?) -> NSColor? {
        guard cmykProof, let color else { return color }
        return ICCCMYKProof.proof(color)
    }

    /// Text soft-proof. Mirrors the exporter's "near-black text → K100" rule so
    /// the canvas shows body/heading type as the same clean single-black InDesign
    /// will print, rather than a dull rich-black; other text is ICC-CMYK
    /// proofed like everything else.
    private func proofedText(_ color: NSColor?) -> NSColor? {
        guard cmykProof, let color else { return color }
        if let rgb = color.usingColorSpace(.deviceRGB),
           max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) <= 0.25 {
            return NSColor(deviceCyan: 0, magenta: 0, yellow: 0, black: 1, alpha: 1)
        }
        return ICCCMYKProof.proof(color)
    }

    private func drawAssetPlaceholder(assetId: UUID, isLeftHalf: Bool?, project: BookProject, rect: CGRect, maskShape: ImageMaskShape?) {
        let asset = project.assets.first { $0.id == assetId }
        let path = maskPath(in: rect, shape: maskShape)
        
        if let image = loadImage(asset: asset) {
            drawImage(image, isLeftHalf: isLeftHalf, rect: rect, project: project, maskShape: maskShape)
            drawImageLabel(asset?.fileName ?? "Image", in: rect)
            return
        }

        NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let label = asset?.fileName ?? "Image"
        drawImageLabel(label, in: rect)
    }

    private func loadImage(asset: Asset?) -> NSImage? {
        guard let sourcePath = asset?.sourcePath else {
            return nil
        }
        return NSImage(contentsOfFile: sourcePath)
    }

    private func drawImage(_ image: NSImage, isLeftHalf: Bool?, rect: CGRect, project: BookProject, maskShape: ImageMaskShape?) {
        let path = maskPath(in: rect, shape: maskShape)
        
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        path.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
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
        path.lineWidth = 1.0
        path.stroke()
    }

    private func maskPath(in rect: CGRect, shape: ImageMaskShape?) -> NSBezierPath {
        let path = NSBezierPath()
        guard let shape else {
            path.appendRect(rect)
            return path
        }
        let points = shape.polygonPoints(in: rect)
        guard !points.isEmpty else {
            path.appendRect(rect)
            return path
        }
        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.close()
        return path
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

    /// IDs of every frame whose on-canvas rectangle intersects the marquee.
    private func framesIntersecting(_ marquee: CGRect?) -> Set<UUID> {
        guard let marquee, marquee.width > 1 || marquee.height > 1,
              let document else { return [] }
        var hits: Set<UUID> = []
        for page in document.pages {
            guard let pRect = pageRect(number: page.number) else { continue }
            for frame in page.frames {
                let canvasRect = CGRect(
                    x: pRect.minX + CGFloat(frame.rect.x) * zoomScale,
                    y: pRect.minY + CGFloat(frame.rect.y) * zoomScale,
                    width: CGFloat(frame.rect.width) * zoomScale,
                    height: CGFloat(frame.rect.height) * zoomScale
                )
                if canvasRect.intersects(marquee) {
                    hits.insert(frame.id)
                }
            }
        }
        return hits
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

    // MARK: - In-place text editing (double-click)

    private func beginInlineEdit(frame: PageFrame, pageRect pRect: CGRect, currentText: String) {
        teardownInlineEditor()
        guard let project else { return }

        let editorRect = CGRect(
            x: pRect.minX + CGFloat(frame.rect.x) * zoomScale,
            y: pRect.minY + CGFloat(frame.rect.y) * zoomScale,
            width: max(CGFloat(frame.rect.width) * zoomScale, 24),
            height: max(CGFloat(frame.rect.height) * zoomScale, 18)
        )

        let editor = InlineTextEditorView(frame: editorRect)
        let style = project.styles.paragraphStyle(id: frame.styleId ?? StyleID.body.rawValue)
        editor.font = NSFont.systemFont(ofSize: max(style.fontSize * zoomScale, 6))
        editor.string = currentText
        editor.textContainerInset = NSSize(width: 2, height: 2)
        editor.isRichText = false
        editor.drawsBackground = true
        editor.backgroundColor = NSColor.white
        editor.textColor = NSColor.black
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).cgColor
        editor.layer?.borderWidth = 1.5

        editor.onCommit = { [weak self] text in
            self?.finishInlineEdit(commit: true, text: text)
        }
        editor.onCancel = { [weak self] in
            self?.finishInlineEdit(commit: false, text: nil)
        }

        addSubview(editor)
        inlineEditor = editor
        inlineEditingFrameId = frame.id
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    /// Commits the current inline edit (if any) — used when focus context changes
    /// (tool switch, zoom) so the typed text is preserved rather than dropped.
    private func commitInlineEditor() {
        inlineEditor?.commitIfEditing()
    }

    private func finishInlineEdit(commit: Bool, text: String?) {
        let frameId = inlineEditingFrameId
        teardownInlineEditor()
        if commit, let frameId, let text {
            onFrameTextEdited?(frameId, text)
        }
    }

    private func teardownInlineEditor() {
        guard let editor = inlineEditor else { return }
        inlineEditor = nil
        inlineEditingFrameId = nil
        if editor.window?.firstResponder === editor {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let ch = chars.first else {
            super.keyDown(with: event)
            return
        }
        let shift = event.modifierFlags.contains(.shift)
        let hasOtherModifier = event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false

        // Shift+P → page tool (InDesign). All other shortcuts are bare single keys.
        if shift && ch == "p" && !hasOtherModifier {
            onToolShortcut?(.page)
            return
        }
        if !shift && !hasOtherModifier,
           let tool = LayoutTool.allCases.first(where: { $0.shortcutKey == ch }) {
            onToolShortcut?(tool)
            return
        }
        super.keyDown(with: event)
    }

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

        if activeTool == .textFrame || activeTool == .imageFrame {
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
        // A click reaching the canvas means the click was outside the inline editor
        // (clicks inside it are consumed by the editor). Commit any active edit first.
        commitInlineEditor()

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

        // 2.5 Double-click a text/caption frame → edit its text in place (InDesign-style),
        // as long as the page isn't locked. Works with the selection and type tools.
        if event.clickCount == 2,
           (activeTool == .selection || activeTool == .type),
           let frame = hitFrame,
           frame.kind == .text || frame.kind == .caption,
           case .text(let currentText) = frame.content,
           let pageNum = clickedPageNumber,
           !(project.lockedPages ?? []).contains(pageNum),
           let pRect = pageRect(number: pageNum) {
            selectedFrameId = frame.id
            onFrameSelected?(frame.id)
            beginInlineEdit(frame: frame, pageRect: pRect, currentText: currentText)
            return
        }

        // 3. Frame drawing tools: begin a rubber-band rectangle on the clicked page.
        if activeTool == .textFrame || activeTool == .imageFrame
            || activeTool == .rectangle || activeTool == .line {
            if let pageNum = clickedPageNumber, let localPt = localPoint {
                isDrawingFrame = true
                drawFramePageNumber = pageNum
                drawFrameStartLocal = localPt
                drawFrameCurrentRect = Rect(x: localPt.x, y: localPt.y, width: 0, height: 0)
                needsDisplay = true
            }
            return
        }

        // 4. Page tool selection
        if activeTool == .page, let pageNum = clickedPageNumber {
            onPageSelected?(pageNum)
            return
        }

        // 4. Gap tool dragging
        if activeTool == .gap, let gap = activeGap {
            isDraggingGap = true
            onDragStarted?()
            dragStartLocalPoint = point
            
            if let fFrame = findFrame(id: gap.firstFrameId, in: document) {
                dragStartFirstFrameRect = fFrame.frame.rect
            }
            if let sFrame = findFrame(id: gap.secondFrameId, in: document) {
                dragStartSecondFrameRect = sFrame.frame.rect
            }
            return
        }

        // 4.5 Line endpoint drag hit test: grabbing an end of a selected line stretches
        // its length along the axis (the other end stays fixed).
        if activeTool == .selection,
           selectedFrameIds.count <= 1,
           let selId = selectedFrameId,
           let info = findFrame(id: selId, in: document),
           info.frame.kind == .line,
           let pRect = pageRect(number: info.pageNumber) {
            let r = info.frame.rect
            let horizontal = r.width >= r.height
            let cx0 = pRect.minX + CGFloat(r.x) * zoomScale
            let cy0 = pRect.minY + CGFloat(r.y) * zoomScale
            let cw = CGFloat(r.width) * zoomScale
            let ch = CGFloat(r.height) * zoomScale
            let p0 = horizontal ? CGPoint(x: cx0, y: cy0 + ch / 2) : CGPoint(x: cx0 + cw / 2, y: cy0)
            let p1 = horizontal ? CGPoint(x: cx0 + cw, y: cy0 + ch / 2) : CGPoint(x: cx0 + cw / 2, y: cy0 + ch)
            let tol: CGFloat = 8
            func near(_ p: CGPoint) -> Bool { abs(point.x - p.x) <= tol && abs(point.y - p.y) <= tol }
            var hitIndex: Int? = nil
            if near(p0) { hitIndex = 0 } else if near(p1) { hitIndex = 1 }
            if let idx = hitIndex {
                isDraggingLineEndpoint = true
                onDragStarted?()
                lineEndpointFrameId = selId
                lineEndpointHorizontal = horizontal
                lineEndpointOrigRect = r
                if horizontal {
                    lineEndpointFixedCoord = (idx == 0) ? (r.x + r.width) : r.x
                } else {
                    lineEndpointFixedCoord = (idx == 0) ? (r.y + r.height) : r.y
                }
                dragStartLocalPoint = point
                return
            }
        }

        // 5. Selection resize handle hit test (single selection only — group resize
        // isn't supported, matching the handles we draw).
        if activeTool == .selection,
           selectedFrameIds.count <= 1,
           let selId = selectedFrameId,
           let selFrameInfo = findFrame(id: selId, in: document),
           selFrameInfo.frame.kind != .line,
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
                onDragStarted?()
                activeResizeHandleIndex = index
                dragStartFrameRect = selFrameInfo.frame.rect
                dragStartLocalPoint = point
                return
            }
        }

        // 6. Selection or Direct Selection click selection. Direct Selection is
        // intentionally select-only until image crop/focal-point editing exists.
        if activeTool == .selection || activeTool == .directSelection {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            if let frame = hitFrame {
                if additive {
                    // Shift/⌘-click: toggle this frame in/out of the selection. No drag.
                    onToggleSelection?(frame.id)
                    return
                }

                if selectedFrameIds.contains(frame.id) && selectedFrameIds.count > 1 {
                    // Plain click on an already multi-selected frame → drag the group,
                    // keeping the selection intact.
                    if activeTool == .selection {
                        beginGroupDrag(anchorPoint: point)
                    }
                    return
                }

                // Plain click → select just this frame.
                selectedFrameId = frame.id
                onFrameSelected?(frame.id)
                if activeTool == .selection {
                    isDraggingFrame = true
                    onDragStarted?()
                    dragStartFrameRect = frame.rect
                    dragStartLocalPoint = point
                }
            } else {
                // Empty canvas → begin a marquee. A plain click with no drag collapses
                // to an empty marquee on mouseUp, which clears the selection as before.
                isMarqueeSelecting = true
                marqueeStartPoint = point
                marqueeRect = CGRect(origin: point, size: .zero)
            }
            return
        }

        // Click on empty canvas to create text/image frames for drawing tools
        if let pageNum = clickedPageNumber, let localPt = localPoint {
            onCanvasClick?(pageNum, localPt)
        }
    }

    /// Captures the start rects of every selected frame so they can be moved
    /// together, and arms the drag state.
    private func beginGroupDrag(anchorPoint: CGPoint) {
        guard let document else { return }
        groupDragStartRects.removeAll()
        for id in selectedFrameIds {
            if let info = findFrame(id: id, in: document) {
                groupDragStartRects[id] = info.frame.rect
            }
        }
        guard !groupDragStartRects.isEmpty else { return }
        isDraggingFrame = true
        // No onDragStarted here: the commit happens once in AppState.applyFrameOrigins
        // (via onFramesDragged). Calling it too would push a redundant undo step.
        dragStartLocalPoint = anchorPoint
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // -1. Marquee (rubber-band) selection: grow the rectangle.
        if isMarqueeSelecting, let start = marqueeStartPoint {
            marqueeRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            return
        }

        // Line endpoint drag: move the grabbed end along the axis, other end fixed.
        if isDraggingLineEndpoint, let id = lineEndpointFrameId, let orig = lineEndpointOrigRect,
           let document, let info = findFrame(id: id, in: document),
           let pRect = pageRect(number: info.pageNumber) {
            let localX = Double((point.x - pRect.minX) / zoomScale)
            let localY = Double((point.y - pRect.minY) / zoomScale)
            let fixed = lineEndpointFixedCoord
            let newRect: Rect
            if lineEndpointHorizontal {
                newRect = Rect(x: min(fixed, localX), y: orig.y, width: abs(localX - fixed), height: orig.height)
            } else {
                newRect = Rect(x: orig.x, y: min(fixed, localY), width: orig.width, height: abs(localY - fixed))
            }
            previewFrameRects[id] = newRect
            pendingLineEndpointRect = newRect
            needsDisplay = true
            return
        }

        // 0. Frame drawing tools: grow the rubber-band rectangle (clamped to its page).
        if isDrawingFrame, let start = drawFrameStartLocal, let pageNum = drawFramePageNumber,
           let pRect = pageRect(number: pageNum) {
            let localX = (point.x - pRect.minX) / zoomScale
            let localY = (point.y - pRect.minY) / zoomScale
            if activeTool == .line {
                // Snap the line to whichever axis the drag is longer along, and pin the
                // thin dimension to a fixed rule weight so it reads as a line, not a box.
                let dx = localX - start.x
                let dy = localY - start.y
                let thickness = lineToolThickness
                if abs(dx) >= abs(dy) {
                    drawFrameCurrentRect = Rect(
                        x: Double(min(start.x, localX)), y: Double(start.y),
                        width: Double(abs(dx)), height: thickness
                    )
                } else {
                    drawFrameCurrentRect = Rect(
                        x: Double(start.x), y: Double(min(start.y, localY)),
                        width: thickness, height: Double(abs(dy))
                    )
                }
            } else {
                drawFrameCurrentRect = Rect(
                    x: Double(min(start.x, localX)),
                    y: Double(min(start.y, localY)),
                    width: Double(abs(localX - start.x)),
                    height: Double(abs(localY - start.y))
                )
            }
            needsDisplay = true
            return
        }

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

        // 2a. Group move (2+ frames dragged together).
        if isDraggingFrame, !groupDragStartRects.isEmpty, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            var updates: [(id: UUID, rect: Rect)] = []
            for (id, startRect) in groupDragStartRects {
                let nextRect = Rect(x: startRect.x + dx, y: startRect.y + dy, width: startRect.width, height: startRect.height)
                previewFrameRects[id] = nextRect
                updates.append((id: id, rect: nextRect))
            }
            pendingGroupDragUpdate = updates
            needsDisplay = true
            return
        }

        // 2. Selection tool moving
        if isDraggingFrame, let selId = selectedFrameId, let startRect = dragStartFrameRect, let startPt = dragStartLocalPoint {
            let dx = Double((point.x - startPt.x) / zoomScale)
            let dy = Double((point.y - startPt.y) / zoomScale)
            let nextRect = Rect(x: startRect.x + dx, y: startRect.y + dy, width: startRect.width, height: startRect.height)
            previewFrameRects[selId] = nextRect
            pendingFrameDragUpdate = (selId, nextRect)
            needsDisplay = true
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
            
            let nextRect = Rect(x: newX, y: newY, width: newW, height: newH)
            previewFrameRects[selId] = nextRect
            pendingFrameDragUpdate = (selId, nextRect)
            needsDisplay = true
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
                    previewFrameRects[gap.firstFrameId] = firstRect
                    previewFrameRects[gap.secondFrameId] = secondRect
                    pendingGapDragUpdate = (gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                    needsDisplay = true
                }
            } else {
                let minH = 10.0
                let targetH1 = startFirst.height + dy
                let targetH2 = startSecond.height - dy
                if targetH1 >= minH && targetH2 >= minH {
                    let firstRect = Rect(x: startFirst.x, y: startFirst.y, width: startFirst.width, height: targetH1)
                    let secondRect = Rect(x: startSecond.x, y: startSecond.y + dy, width: startSecond.width, height: targetH2)
                    previewFrameRects[gap.firstFrameId] = firstRect
                    previewFrameRects[gap.secondFrameId] = secondRect
                    pendingGapDragUpdate = (gap.firstFrameId, firstRect, gap.secondFrameId, secondRect)
                    needsDisplay = true
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Line endpoint drag commit.
        if isDraggingLineEndpoint {
            if let id = lineEndpointFrameId, let rect = pendingLineEndpointRect {
                onLineEndpointDragged?(id, rect)
            }
            isDraggingLineEndpoint = false
            lineEndpointFrameId = nil
            lineEndpointOrigRect = nil
            pendingLineEndpointRect = nil
            previewFrameRects.removeAll()
            dragStartLocalPoint = nil
            needsDisplay = true
            return
        }

        // Frame drawing tools: commit the rubber-band rectangle if it has real size.
        // A line is intentionally thin on one axis, so it only needs real length.
        if isDrawingFrame {
            if let rect = drawFrameCurrentRect, let pageNum = drawFramePageNumber {
                let bigEnough = activeTool == .line
                    ? max(rect.width, rect.height) > 8
                    : (rect.width > 8 && rect.height > 8)
                if bigEnough { onFrameDrawn?(pageNum, rect) }
            }
            isDrawingFrame = false
            drawFrameStartLocal = nil
            drawFramePageNumber = nil
            drawFrameCurrentRect = nil
            needsDisplay = true
            return
        }

        // Marquee selection: select every frame intersecting the rubber-band. A
        // zero-ish rectangle (plain click) resolves to an empty set → clears.
        if isMarqueeSelecting {
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            let hits = framesIntersecting(marqueeRect)
            if additive {
                onMarqueeSelected?(selectedFrameIds.union(hits))
            } else {
                onMarqueeSelected?(hits)
            }
            isMarqueeSelecting = false
            marqueeStartPoint = nil
            marqueeRect = nil
            needsDisplay = true
            return
        }

        if let group = pendingGroupDragUpdate {
            onFramesDragged?(group)
        } else if let pending = pendingFrameDragUpdate {
            onFrameDragged?(pending.id, pending.rect.x, pending.rect.y, pending.rect.width, pending.rect.height)
        }
        if let pending = pendingGapDragUpdate {
            onGapDragged?(pending.firstId, pending.firstRect, pending.secondId, pending.secondRect)
        }

        groupDragStartRects.removeAll()
        pendingGroupDragUpdate = nil
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
        previewFrameRects.removeAll()
        pendingFrameDragUpdate = nil
        pendingGapDragUpdate = nil
        needsDisplay = true
        
        if activeTool == .hand {
            NSCursor.openHand.set()
        }
    }
}

/// A minimal in-place text editor for double-click frame editing. Escape cancels,
/// ⌘Return or clicking away commits, plain Return inserts a newline (frames may hold
/// multi-line paragraph text). Guards against double-firing its callbacks.
final class InlineTextEditorView: NSTextView {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var finished = false

    override func keyDown(with event: NSEvent) {
        // Escape (keyCode 53) → cancel.
        if event.keyCode == 53 {
            finish(commit: false)
            return
        }
        // ⌘Return (keyCode 36) → commit.
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            finish(commit: true)
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        // Clicking away / switching focus commits what was typed.
        finish(commit: true)
        return super.resignFirstResponder()
    }

    /// Commits if still actively editing (used on tool-switch / zoom teardown).
    func commitIfEditing() {
        finish(commit: true)
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit {
            onCommit?(string)
        } else {
            onCancel?()
        }
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        // "hex" now also carries CMYK (`cmyk(c,m,y,k)`); CMYK renders through
        // the ICC-managed proof space so the canvas matches InDesign's print
        // simulation instead of AppKit's more saturated device-CMYK space.
        guard let color = PrintColor(string: hex) else { return nil }
        switch color {
        case let .rgb(r, g, b):
            return NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                           blue: CGFloat(b) / 255, alpha: 1.0)
        case let .cmyk(c, m, y, k):
            return ICCCMYKProof.rgb(c: c, m: m, y: y, k: k)
        }
    }
}

/// ICC-managed CMYK↔RGB soft-proofing so the canvas approximates InDesign's
/// print simulation rather than AppKit's `.deviceCMYK`/`.deviceRGB`, which are
/// noticeably more saturated than a real print profile. Loads the system's
/// Generic CMYK Profile (same one `PDFExporter` embeds as a PDF/X output
/// intent) once and reuses it; falls back to the device-CMYK approximation if
/// the profile can't be loaded.
enum ICCCMYKProof {
    private static let cmykSpace: CGColorSpace? = {
        let path = "/System/Library/ColorSync/Profiles/Generic CMYK Profile.icc"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return CGColorSpace(iccData: data as CFData)
    }()

    /// c/m/y/k in 0...100 → on-screen RGB.
    static func rgb(c: Double, m: Double, y: Double, k: Double) -> NSColor {
        let fallback = NSColor(deviceCyan: CGFloat(c) / 100, magenta: CGFloat(m) / 100,
                                yellow: CGFloat(y) / 100, black: CGFloat(k) / 100, alpha: 1.0)
        guard let space = cmykSpace,
              let cgColor = CGColor(colorSpace: space, components: [c / 100, m / 100, y / 100, k / 100, 1.0]),
              let srgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        else { return fallback }
        return NSColor(cgColor: srgb) ?? fallback
    }

    /// Soft-proof an on-screen RGB color as if it were printed in CMYK: round
    /// -trips it through the ICC CMYK profile and back. A no-op (returns the
    /// input) if the profile can't be loaded.
    static func proof(_ color: NSColor) -> NSColor {
        guard let space = cmykSpace,
              let srgbColor = color.usingColorSpace(.deviceRGB)?.cgColor,
              let cmykColor = srgbColor.converted(to: space, intent: .defaultIntent, options: nil),
              let backToSRGB = cmykColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        else { return color }
        return NSColor(cgColor: backToSRGB) ?? color
    }
}

import AppKit
import LayoutDCore
import LayoutDEngine

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
    var onMarqueeSelected: ((Set<UUID>, UUID?) -> Void)?
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
    var inlineEditor: InlineTextEditorView?
    var inlineEditingFrameId: UUID?
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

    var activeGap: GapInfo? {
        didSet {
            if oldValue?.rect != activeGap?.rect {
                needsDisplay = true
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    var isDraggingFrame = false
    var isResizingFrame = false
    var activeResizeHandleIndex: Int?
    var dragStartFrameRect: Rect?
    var dragStartLocalPoint: CGPoint? // absolute canvas point
    var previewFrameRects: [UUID: Rect] = [:]
    var pendingFrameDragUpdate: (id: UUID, rect: Rect)?
    /// Group-drag: start rects (page-local) of every frame moved together, keyed by id.
    var groupDragStartRects: [UUID: Rect] = [:]
    var pendingGroupDragUpdate: [(id: UUID, rect: Rect)]?

    // Line endpoint drag: stretch one end of a selected line along its axis.
    var isDraggingLineEndpoint = false
    var lineEndpointFrameId: UUID?
    var lineEndpointHorizontal = false
    var lineEndpointFixedCoord: Double = 0   // page-local along-axis coord of the fixed end
    var lineEndpointOrigRect: Rect?          // page-local rect at drag start (perpendicular dims)
    var pendingLineEndpointRect: Rect?

    // Marquee (rubber-band) selection state — canvas coordinates.
    var isMarqueeSelecting = false
    var marqueeStartPoint: CGPoint?
    var marqueeRect: CGRect? {
        didSet {
            if oldValue != marqueeRect { needsDisplay = true }
        }
    }
    var pendingGapDragUpdate: (firstId: UUID, firstRect: Rect, secondId: UUID, secondRect: Rect)?
    
    // Hand tool panning
    var dragStartPoint: NSPoint?
    var scrollStartOrigin: NSPoint?
    
    // Gap tool dragging
    var isDraggingGap = false
    var dragStartFirstFrameRect: Rect?
    var dragStartSecondFrameRect: Rect?

    // Frame drawing tools (textFrame / imageFrame) rubber-band state
    var isDrawingFrame = false
    var drawFrameStartLocal: CGPoint?
    var drawFramePageNumber: Int?
    var drawFrameCurrentRect: Rect?  // page-local points

    private(set) var zoomScale: CGFloat = 1.15
    let pageGap: CGFloat = 36
    let canvasInset: CGFloat = 42
    /// Thin dimension (page points) of a line's bounding box. This is the click/hit
    /// area, not the visible weight — the line is drawn as a centered stroke whose
    /// width is the frame's strokeWidth, so it stays a true thin line.
    let lineToolThickness: Double = 6

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

    func setZoomScale(_ scale: CGFloat) {
        // The overlay is positioned in zoomed canvas coordinates; commit it before
        // the scale changes so the edited text isn't lost and no stale box lingers.
        commitInlineEditor()
        zoomScale = min(max(scale, 0.35), 3.0)
        onZoomChanged?(zoomScale)
        updateFrame()
        needsDisplay = true
    }

    func updateFrame() {
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

    func pageRect(number: Int) -> CGRect? {
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

    func findFrame(id: UUID, in document: LaidOutDocument) -> (frame: PageFrame, pageNumber: Int)? {
        for page in document.pages {
            if let frame = page.frames.first(where: { $0.id == id }) {
                return (frame, page.number)
            }
        }
        return nil
    }

    /// Groups for the current document
    var currentFlowGrouping: FlowFrameGrouping? {
        guard let document = document, let project = project else { return nil }
        return groupIntoFlowFrames(pages: document.pages, project: project)
    }

    /// Finds the group containing the given frame on the given page
    func flowGroup(for frameId: UUID, pageNumber: Int) -> FlowFrameGroup? {
        guard let document = document, let project = project else { return nil }
        let sortedPages = document.pages.sorted { $0.number < $1.number }
        guard let pageIndex = sortedPages.firstIndex(where: { $0.number == pageNumber }) else { return nil }
        guard let grouping = currentFlowGrouping else { return nil }
        guard let groups = grouping.groupsByPage[pageIndex] else { return nil }
        
        let targetPage = sortedPages[pageIndex]
        for group in groups {
            for idx in group.memberFrameIndices {
                if idx >= 0 && idx < targetPage.frames.count {
                    if targetPage.frames[idx].id == frameId {
                        return group
                    }
                }
            }
        }
        return nil
    }

    /// Gets all member frame IDs of the group containing the given frame
    func flowGroupMemberIds(for frameId: UUID, pageNumber: Int) -> Set<UUID>? {
        guard let document = document else { return nil }
        let sortedPages = document.pages.sorted { $0.number < $1.number }
        guard let pageIndex = sortedPages.firstIndex(where: { $0.number == pageNumber }) else { return nil }
        guard let group = flowGroup(for: frameId, pageNumber: pageNumber) else { return nil }
        
        let targetPage = sortedPages[pageIndex]
        var memberIds = Set<UUID>()
        for idx in group.memberFrameIndices {
            if idx >= 0 && idx < targetPage.frames.count {
                memberIds.insert(targetPage.frames[idx].id)
            }
        }
        return memberIds
    }

    /// Gets the first member frame ID of the group containing the given frame
    func firstFrameIdOfGroup(for frameId: UUID, pageNumber: Int) -> UUID? {
        guard let group = flowGroup(for: frameId, pageNumber: pageNumber) else { return nil }
        guard let document = document else { return nil }
        let sortedPages = document.pages.sorted { $0.number < $1.number }
        guard let pageIndex = sortedPages.firstIndex(where: { $0.number == pageNumber }) else { return nil }
        let targetPage = sortedPages[pageIndex]
        if let firstIdx = group.memberFrameIndices.first,
           firstIdx >= 0 && firstIdx < targetPage.frames.count {
            return targetPage.frames[firstIdx].id
        }
        return nil
    }

    /// IDs of every frame whose on-canvas rectangle intersects the marquee.
    func framesIntersecting(_ marquee: CGRect?) -> Set<UUID> {
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

        // Expand hits to include entire flow frame groups. `flowGroupMemberIds` recomputes
        // groupIntoFlowFrames over the whole document on every call — calling it per hit
        // here would mean a full-document recompute per frame caught by the marquee, which
        // gets slow fast during a drag over many frames. Compute the grouping once and
        // build a frameId → group-members lookup instead.
        var expandedHits = Set<UUID>()
        if let grouping = currentFlowGrouping {
            let sortedPages = document.pages.sorted { $0.number < $1.number }
            var memberIdsByFrameId: [UUID: Set<UUID>] = [:]
            for (pageIndex, groups) in grouping.groupsByPage {
                guard pageIndex >= 0 && pageIndex < sortedPages.count else { continue }
                let pageFrames = sortedPages[pageIndex].frames
                for group in groups {
                    let ids = Set(group.memberFrameIndices.compactMap { idx in
                        idx >= 0 && idx < pageFrames.count ? pageFrames[idx].id : nil
                    })
                    for id in ids { memberIdsByFrameId[id] = ids }
                }
            }
            for hit in hits {
                expandedHits.formUnion(memberIdsByFrameId[hit] ?? [hit])
            }
        } else {
            expandedHits = hits
        }
        return expandedHits
    }

    func resizeHandles(for rect: CGRect) -> [CGRect] {
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

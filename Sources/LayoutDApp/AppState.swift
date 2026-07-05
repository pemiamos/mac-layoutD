import Combine
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDDesignAI
import LayoutDCheck

final class AppState: ObservableObject {
    @Published var project: BookProject {
        didSet {
            recalculateLayout()
        }
    }
    @Published var laidOutDocument: LaidOutDocument?
    @Published var baselineDocument: LaidOutDocument?
    @Published var report: PreflightReport?
    @Published var plans: [LayoutPlan] = []
    @Published var currentPageNumber: Int = 1 {
        didSet {
            updateAIPlans()
        }
    }
    /// The "primary" / anchor selection. Kept for backward compatibility: the
    /// inspector, coordinate fields, colour edits and every single-frame action key
    /// off this. Assigning it (the plain-click path) *replaces* the whole selection
    /// with just this frame; multi-selection goes through `selectedFrameIds` and the
    /// `toggleFrameSelection` / `setSelection` helpers below.
    @Published var selectedFrameId: UUID? {
        didSet {
            // Keep the "current page" pointed at whatever the user is actually
            // working on. Page-scoped controls (lock/unlock, reset page, save as
            // template) all key off currentPageNumber; without this sync, selecting
            // a frame by scrolling+clicking would leave those controls targeting a
            // different page — e.g. you could be blocked from editing a locked frame
            // while the unlock toggle silently acts on page 1.
            if let id = selectedFrameId,
               let page = findPageNumber(for: id),
               page != currentPageNumber {
                currentPageNumber = page
            }
            colorEditBurstFrame = nil
            // A bare anchor assignment means "select only this" — collapse any
            // multi-selection. Multi-select helpers set this flag so they can move
            // the anchor without wiping the set they just built.
            if !isMutatingSelectionSet {
                selectedFrameIds = selectedFrameId.map { [$0] } ?? []
            }
        }
    }

    /// The full multi-selection (superset of `selectedFrameId`). Alignment and
    /// distribution operate on this. Invariant: empty iff `selectedFrameId == nil`,
    /// and the anchor is always a member when non-nil.
    @Published var selectedFrameIds: Set<UUID> = []
    private var isMutatingSelectionSet = false

    /// Shift/⌘-click: add the frame to the selection (becoming the new anchor) or
    /// remove it if already selected.
    func toggleFrameSelection(_ id: UUID) {
        isMutatingSelectionSet = true
        defer { isMutatingSelectionSet = false }
        if selectedFrameIds.contains(id) {
            selectedFrameIds.remove(id)
            if selectedFrameId == id { selectedFrameId = selectedFrameIds.first }
        } else {
            selectedFrameIds.insert(id)
            selectedFrameId = id
        }
    }

    /// Replace the whole selection at once (marquee rubber-band). `anchor` becomes
    /// the primary; defaults to any member.
    func setSelection(_ ids: Set<UUID>, anchor: UUID? = nil) {
        isMutatingSelectionSet = true
        defer { isMutatingSelectionSet = false }
        selectedFrameIds = ids
        selectedFrameId = anchor ?? ids.first
    }
    @Published var activeTool: LayoutTool = .selection
    
    @Published var activeFormattingTarget: FormattingTarget = .container
    @Published var activeScreenMode: ScreenMode = .normal
    @Published var activeFillColor: Color = Color(nsColor: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.46, alpha: 1))
    @Published var activeStrokeColor: Color = .black
    @Published var isFillActive: Bool = true

    @Published var frameBackgroundColors: [UUID: Color] = [:]
    @Published var frameStrokeColors: [UUID: Color] = [:]
    @Published var frameTextColors: [UUID: Color] = [:]

    /// Last-used PDF export configuration, so the live preflight (and the exported
    /// preflight report) reflect the prepress consequences of the user's chosen
    /// PDF/X / crop-mark settings instead of always assuming defaults.
    @Published var pdfExportOptions = PrepressExportOptions()

    /// Mirror of the canvas zoom scale for the status bar readout (percent).
    @Published var zoomPercent: Int = 115
    
    private var undoStack: [BookProject] = []
    private var redoStack: [BookProject] = []
    private var isPerformingUndoRedo = false
    private var isPerformingRecalculation = false

    /// The stripped project the current `baselineDocument` was laid out from.
    /// Plan-only edits (apply/clear a LayoutPlan, quality-history bookkeeping)
    /// leave this value unchanged, so the second full-book layout is skipped.
    private var baselineSource: BookProject?
    /// How many times the baseline document was actually laid out (test hook).
    private(set) var baselineLayoutCount = 0
    
    let engine = LayoutEngine()
    let inspectorEngine = ProjectInspector()
    let advisor = RuleBasedLayoutAdvisor()
    
    var onLayoutCompleted: ((BookProject, LaidOutDocument) -> Void)?
    
    init(project: BookProject) {
        self.project = project
        recalculateLayout()
    }

    /// Frame currently mid color-adjust. Continuous color-picker changes on this
    /// frame coalesce into a single undo entry (see setSelectedFrame*Color); any
    /// other committed action ends the burst.
    private var colorEditBurstFrame: UUID?

    func commitState() {
        guard !isPerformingUndoRedo else { return }
        colorEditBurstFrame = nil
        undoStack.append(project)
        redoStack.removeAll()
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    func beginUndoGrouping() {
        commitState()
    }
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    func undo() {
        guard canUndo else { return }
        isPerformingUndoRedo = true
        redoStack.append(project)
        project = undoStack.removeLast()
        isPerformingUndoRedo = false
    }
    
    func redo() {
        guard canRedo else { return }
        isPerformingUndoRedo = true
        undoStack.append(project)
        project = redoStack.removeLast()
        isPerformingUndoRedo = false
    }

    func updateProject(_ update: (inout BookProject) -> Void) {
        commitState()
        var currentProject = project
        update(&currentProject)
        self.project = currentProject
    }
    
    func recalculateLayout() {
        guard !isPerformingRecalculation else { return }
        isPerformingRecalculation = true
        defer { isPerformingRecalculation = false }

        let doc = engine.layout(project: project)
        self.laidOutDocument = doc
        
        var baselineProj = project
        baselineProj.appliedLayoutPlans = nil
        // Quality history is bookkeeping appended after every recalculation; it has
        // no effect on layout but would defeat the equality check below.
        baselineProj.qualityMetricsHistory = nil
        if baselineDocument == nil || baselineSource != baselineProj {
            self.baselineDocument = engine.layout(project: baselineProj)
            baselineSource = baselineProj
            baselineLayoutCount += 1
        }
        
        let report = inspectorEngine.preflight(project: project, document: doc, exportOptions: pdfExportOptions)
        self.report = report
        
        updateAIPlans()
        
        // Record quality metrics history if different from the last snapshot
        if let report = self.report {
            let metrics = report.qualityMetrics
            let newEntry = QualityHistoryEntry(
                timestamp: Date(),
                pageCount: metrics.pageCount,
                totalFrames: metrics.totalFrames,
                averageFramesPerPage: metrics.averageFramesPerPage,
                planAppliedPages: metrics.planAppliedPages,
                autoLaidOutPages: metrics.autoLaidOutPages,
                lowResolutionAssets: metrics.lowResolutionAssets,
                missingCaptionAssets: metrics.missingCaptionAssets,
                blockingErrors: metrics.blockingErrors,
                layoutIssues: metrics.layoutIssues
            )
            
            var history = project.safeQualityMetricsHistory
            let shouldAdd: Bool
            if let last = history.last {
                shouldAdd = last.pageCount != newEntry.pageCount ||
                            last.totalFrames != newEntry.totalFrames ||
                            last.averageFramesPerPage != newEntry.averageFramesPerPage ||
                            last.planAppliedPages != newEntry.planAppliedPages ||
                            last.autoLaidOutPages != newEntry.autoLaidOutPages ||
                            last.lowResolutionAssets != newEntry.lowResolutionAssets ||
                            last.missingCaptionAssets != newEntry.missingCaptionAssets ||
                            last.blockingErrors != newEntry.blockingErrors ||
                            last.layoutIssues != newEntry.layoutIssues
            } else {
                shouldAdd = true
            }
            
            if shouldAdd {
                history.append(newEntry)
                if history.count > 30 {
                    history = Array(history.suffix(30))
                }
                project.qualityMetricsHistory = history
            }
        }
        
        onLayoutCompleted?(project, doc)
    }
    
    private func updateAIPlans() {
        guard let doc = laidOutDocument else { return }
        let targetPage = min(max(currentPageNumber, 1), max(doc.pages.count, 1))
        let proposedPlans = advisor.proposePlans(for: project, target: .page(targetPage))
        self.plans = proposedPlans
    }
    
    // MARK: - Selected Element Editing Support
    
    func findPageNumber(for frameId: UUID) -> Int? {
        guard let doc = laidOutDocument else { return nil }
        for page in doc.pages {
            if page.frames.contains(where: { $0.id == frameId }) {
                return page.number
            }
        }
        return nil
    }

    func findParagraphByText(_ text: String) -> Paragraph? {
        for section in project.sections {
            for story in section.stories {
                for paragraph in story.paragraphs {
                    if paragraph.text == text {
                        return paragraph
                    }
                }
            }
        }
        return nil
    }

    func freezePageToPlan(pageNum: Int) -> LayoutPlan {
        let pageSize = project.pageSetup.pageSize
        let docPages = laidOutDocument?.pages ?? []
        guard let targetPage = docPages.first(where: { $0.number == pageNum }) else {
            return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: [])
        }
        
        var blocks: [LayoutPlanBlock] = []
        
        for frame in targetPage.frames {
            // The running header is regenerated per page by the engine, so it must
            // not be frozen into a saved plan. It is identified by its semantic
            // kind rather than its on-page geometry.
            if frame.kind == .runningHeader {
                continue
            }

            let normX = frame.rect.x / pageSize.width
            let normY = frame.rect.y / pageSize.height
            let normW = frame.rect.width / pageSize.width
            let normH = frame.rect.height / pageSize.height

            let kind: LayoutBlockKind
            switch frame.kind {
            case .text: kind = .text
            case .image: kind = .image
            case .caption: kind = .caption
            case .callout: kind = .component
            case .table: kind = .component
            case .footnote: kind = .text
            case .footnoteDivider: kind = .component
            case .sideNote: kind = .text
            case .runningHeader: kind = .text
            case .rectangle: kind = .rectangle
            case .line: kind = .line
            }
            
            let ref: ContentReference
            switch frame.content {
            case .asset(let assetId), .spreadAsset(let assetId, _):
                ref = .asset(assetId)
            case .text(let text):
                if let paragraphId = frame.sourceParagraphId {
                    ref = .paragraph(paragraphId)
                } else if let paragraph = findParagraphByText(text) {
                    ref = .paragraph(paragraph.id)
                } else {
                    ref = .generated(text)
                }
            case .empty:
                ref = .generated("")
            }
            
            let block = LayoutPlanBlock(
                id: frame.id,
                kind: kind,
                role: frame.kind.rawValue,
                frame: Rect(x: normX, y: normY, width: normW, height: normH),
                contentReference: ref,
                backgroundColorHex: frame.backgroundColorHex,
                strokeColorHex: frame.strokeColorHex,
                strokeWidth: frame.strokeWidth,
                textColorHex: frame.textColorHex,
                maskShape: frame.maskShape,
                styleId: frame.styleId
            )
            blocks.append(block)
        }
        
        return LayoutPlan(target: .page(pageNum), strategy: .balanced, blocks: blocks, notes: ["手动自定义版式页"])
    }

    /// Creates a new text or image frame from a drawn rectangle. Writes a
    /// LayoutPlan block (structured override) on the target page so the frame is
    /// undoable, coexists with AI plans, and exports to IDML like any other block.
    /// `rect` is in page-local points and gets normalized to the page size.
    /// Image frames reference the first project asset (re-pickable in the
    /// inspector); returns false without creating anything if none exists.
    @discardableResult
    func createDrawnFrame(kind: LayoutBlockKind, onPage pageNum: Int, rect: Rect) -> Bool {
        let pageSize = project.pageSetup.pageSize

        let contentRef: ContentReference
        let role: String
        // Shapes carry the current fill/stroke so they're visible the moment they're
        // drawn (a colorless box would be invisible). A rectangle takes both fill and
        // stroke; a line (a thin rule) is filled with the stroke colour, no border.
        var backgroundColorHex: String? = nil
        var strokeColorHex: String? = nil
        var strokeWidth: Double? = nil
        switch kind {
        case .image:
            guard let firstAsset = project.assets.first else { return false }
            contentRef = .asset(firstAsset.id)
            role = PageFrameKind.image.rawValue
        case .rectangle:
            contentRef = .generated("")
            role = PageFrameKind.rectangle.rawValue
            if isFillActive { backgroundColorHex = Self.printColor(from: activeFillColor).storageString }
            strokeColorHex = Self.printColor(from: activeStrokeColor).storageString
            strokeWidth = 1.0
        case .line:
            contentRef = .generated("")
            role = PageFrameKind.line.rawValue
            backgroundColorHex = Self.printColor(from: activeStrokeColor).storageString
        default:
            contentRef = .generated("")
            role = PageFrameKind.text.rawValue
        }

        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        let normRect = Rect(
            x: rect.x / pageSize.width,
            y: rect.y / pageSize.height,
            width: rect.width / pageSize.width,
            height: rect.height / pageSize.height
        )
        let block = LayoutPlanBlock(
            kind: kind,
            role: role,
            frame: normRect,
            contentReference: contentRef,
            backgroundColorHex: backgroundColorHex,
            strokeColorHex: strokeColorHex,
            strokeWidth: strokeWidth
        )
        plan.blocks.append(block)
        let noteName: String
        switch kind {
        case .image: noteName = "手动绘制图像框"
        case .rectangle: noteName = "手动绘制矩形"
        case .line: noteName = "手动绘制直线"
        default: noteName = "手动绘制文本框"
        }
        plan.notes = [noteName]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
        self.selectedFrameId = block.id
        return true
    }

    func updateSelectedFrameCoordinate(x: Double?, y: Double?, width: Double?, height: Double?) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) {
            let pageSize = project.pageSetup.pageSize
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(
                pageSize: pageSize,
                x: x,
                y: y,
                width: width,
                height: height
            )
            
            plan.blocks[idx] = block
            plan.notes = ["手动修改元素坐标"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    /// Absolute page rects (points) of every frame in the current selection, with
    /// the page each lives on — the input to alignment/distribution. Read from the
    /// laid-out document, whose `PageFrame.rect` is already in absolute page points.
    private func selectedAbsoluteRects() -> [(id: UUID, pageNumber: Int, rect: Rect)] {
        guard let doc = laidOutDocument else { return [] }
        var result: [(id: UUID, pageNumber: Int, rect: Rect)] = []
        for page in doc.pages {
            for frame in page.frames where selectedFrameIds.contains(frame.id) {
                result.append((frame.id, page.number, frame.rect))
            }
        }
        return result
    }

    /// Aligns every selected frame. `.selection` snaps each to the shared bounding
    /// box (multi-frame「对齐对象」); `.page` / `.margin` snap each to its own page's
    /// box independently. Reuses the LayoutPlan-override + undo path, so it's
    /// undoable and exports to IDML like any manual coordinate change. Only moves
    /// frames — sizes are preserved.
    func alignSelection(_ alignment: FrameAlignment, reference: AlignmentReference) {
        let items = selectedAbsoluteRects()
        guard !items.isEmpty else { return }

        let selectionBox = boundingBox(of: items.map { $0.rect })
        let pageSize = project.pageSetup.pageSize

        var origins: [UUID: (x: Double, y: Double)] = [:]
        for item in items {
            let region: Rect
            switch reference {
            case .selection: region = selectionBox
            case .page: region = Rect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
            case .margin: region = marginRegion(pageNum: item.pageNumber)
            }
            origins[item.id] = alignedFrameOrigin(frame: item.rect, region: region, alignment: alignment)
        }
        applyFrameOrigins(origins, note: "手动对齐元素（\(reference.displayName)·\(alignment.displayName)）")
    }

    /// Distributes the selected frames (3+ required). Extremes stay fixed; the rest
    /// are repositioned so the chosen edge/center — or the gaps — become even.
    func distributeSelection(_ mode: DistributionMode) {
        let items = selectedAbsoluteRects()
        guard items.count >= 3 else { return }
        let origins = distributedOrigins(frames: items.map { (id: $0.id, rect: $0.rect) }, mode: mode)
        applyFrameOrigins(origins, note: "手动分布元素（\(mode.displayName)）")
    }

    /// Writes new top-left origins for a batch of frames in one undoable step,
    /// freezing each touched page to a plan as needed. Shared by alignment,
    /// distribution and group-drag.
    func applyFrameOrigins(_ origins: [UUID: (x: Double, y: Double)], note: String) {
        guard !origins.isEmpty else { return }
        let pageSize = project.pageSetup.pageSize

        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans

        for (id, origin) in origins {
            guard let pageNum = findPageNumber(for: id) else { continue }
            var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
            guard let idx = plan.blocks.firstIndex(where: { $0.id == id }) else { continue }
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(pageSize: pageSize, x: origin.x, y: origin.y)
            plan.blocks[idx] = block
            plan.notes = [note]
            plans[pageNum] = plan
        }

        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    /// The (facing-page-aware) margin box of a page in absolute points. Mirrors the
    /// canvas guides: on facing-page spreads the inner/outer margins swap per parity.
    private func marginRegion(pageNum: Int) -> Rect {
        let pageSize = project.pageSetup.pageSize
        let margins = project.resolvedMargins(for: pageNum)
        let leftM: Double
        let rightM: Double
        if project.pageSetup.facingPages {
            leftM = pageNum % 2 == 1 ? margins.left : margins.right
            rightM = pageNum % 2 == 1 ? margins.right : margins.left
        } else {
            leftM = margins.left
            rightM = margins.right
        }
        return Rect(
            x: leftM,
            y: margins.top,
            width: max(pageSize.width - leftM - rightM, 0),
            height: max(pageSize.height - margins.top - margins.bottom, 0)
        )
    }

    func updateSelectedFrameImage(assetId: UUID) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) {
            var block = plan.blocks[idx]
            block.contentReference = .asset(assetId)
            
            plan.blocks[idx] = block
            plan.notes = ["手动修改图片引用"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    func updateSelectedFrameText(_ text: String) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        guard let idx = plan.blocks.firstIndex(where: { $0.id == frameId }) else { return }
        guard plan.blocks[idx].kind == .text || plan.blocks[idx].kind == .caption else {
            return
        }

        plan.blocks[idx].contentReference = .generated(text)
        plan.notes = ["手动修改元素文字"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func clearCustomLayoutForPage(number: Int) {
        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans.removeValue(forKey: number)
        currentProject.safeAppliedLayoutPlans = plans
        
        var locked = currentProject.safeLockedPages
        locked.remove(number)
        currentProject.safeLockedPages = locked
        
        self.selectedFrameId = nil
        self.project = currentProject
    }

    func clearCustomLayoutForSelectedFramePage() {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        clearCustomLayoutForPage(number: pageNum)
    }

    func applyLayoutPlan(_ plan: LayoutPlan) {
        commitState()
        guard case .page(let pageNum) = plan.target else { return }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func saveCurrentPageLayoutAsTemplate(name: String) {
        commitState()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = trimmedName.isEmpty ? "第 \(currentPageNumber) 页版式" : trimmedName
        let plan = freezePageToPlan(pageNum: currentPageNumber)

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.append(SavedLayoutTemplate(name: templateName, plan: plan))
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applySavedLayoutTemplate(id: UUID, toPage pageNum: Int) {
        guard let template = project.safeSavedLayoutTemplates.first(where: { $0.id == id }) else { return }
        applyLayoutPlan(template.makePlan(target: .page(pageNum)))
    }

    func applyPageLayoutTemplate(_ template: PageLayoutTemplate, toPage pageNum: Int) {
        let primaryAsset = project.assets.first { $0.role != .decorative }
        guard let plan = template.makePlan(
            target: .page(pageNum),
            projectTitle: project.metadata.title,
            primaryAsset: primaryAsset
        ) else { return }
        applyLayoutPlan(plan)
    }

    func renameSavedLayoutTemplate(id: UUID, name: String) {
        commitState()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].name = trimmedName
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func deleteSavedLayoutTemplate(id: UUID) {
        commitState()
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        templates.removeAll { $0.id == id }
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func updateSavedLayoutTemplateParameters(
        id: UUID,
        marginOverride: PageMargins?,
        columnsOverride: Int?,
        showHeadersFooters: Bool?
    ) {
        commitState()
        var currentProject = project
        var templates = currentProject.safeSavedLayoutTemplates
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        templates[index].plan.marginOverride = marginOverride
        templates[index].plan.columnsOverride = columnsOverride
        templates[index].plan.showHeadersFooters = showHeadersFooters
        templates[index].modifiedAt = Date()
        currentProject.safeSavedLayoutTemplates = templates
        self.project = currentProject
    }

    func applyChapterLayoutTemplate(_ template: ChapterLayoutTemplate, sectionIndex: Int, startPage: Int) -> Int {
        var currentProject = project
        let appliedCount = currentProject.applyChapterLayoutTemplate(
            template,
            sectionIndex: sectionIndex,
            startPage: startPage
        )
        guard appliedCount > 0 else {
            return 0
        }
        self.project = currentProject
        return appliedCount
    }

    func lockPage(number: Int) {
        commitState()
        var currentProject = project
        var locked = currentProject.safeLockedPages
        locked.insert(number)
        currentProject.safeLockedPages = locked
        
        var plans = currentProject.safeAppliedLayoutPlans
        if plans[number] == nil {
            plans[number] = freezePageToPlan(pageNum: number)
        }
        currentProject.safeAppliedLayoutPlans = plans
        
        self.project = currentProject
    }

    func unlockPage(number: Int) {
        commitState()
        var currentProject = project
        var locked = currentProject.safeLockedPages
        locked.remove(number)
        currentProject.safeLockedPages = locked
        
        self.project = currentProject
    }

    func updateParagraphStyle(
        id: String,
        fontSize: Double? = nil,
        lineHeight: Double? = nil,
        firstLineIndent: Double? = nil,
        spaceBefore: Double? = nil,
        spaceAfter: Double? = nil
    ) {
        commitState()
        var currentProject = project
        var styles = currentProject.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == id }) {
            var style = styles[idx]
            if let fSize = fontSize {
                style.fontSize = fSize
                style.fontSizeToken = nil
            }
            if let lHeight = lineHeight {
                style.lineHeight = lHeight
                style.lineHeightToken = nil
            }
            if let indent = firstLineIndent {
                style.firstLineIndent = indent
                style.firstLineIndentToken = nil
            }
            if let before = spaceBefore {
                style.spaceBefore = before
                style.spaceBeforeToken = nil
            }
            if let after = spaceAfter {
                style.spaceAfter = after
                style.spaceAfterToken = nil
            }
            styles[idx] = style
            currentProject.styles.paragraphStyles = styles
            self.project = currentProject
        }
    }

    func updateParagraphStyleCompositeFont(
        id: String,
        charClass: CompositeFontClass,
        fontName: String,
        sizeMultiplier: Double,
        baselineOffset: Double
    ) {
        commitState()
        var currentProject = project
        var styles = currentProject.styles.paragraphStyles
        if let idx = styles.firstIndex(where: { $0.id == id }) {
            var style = styles[idx]
            var cf = style.compositeFont ?? [:]
            cf[charClass] = CompositeFontMapping(
                fontName: fontName,
                sizeMultiplier: sizeMultiplier,
                baselineOffset: baselineOffset
            )
            style.compositeFont = cf
            styles[idx] = style
            currentProject.styles.paragraphStyles = styles
            self.project = currentProject
        }
    }

    func applyImportedTokens(_ importedTokens: DesignTokens, baselineGridCompensate: Double? = nil) {
        commitState()
        var currentProject = project
        
        currentProject.styles.tokens = importedTokens
        
        var styles = currentProject.styles.paragraphStyles
        for idx in styles.indices {
            var style = styles[idx]
            
            let fsToken = "paragraph.\(style.id).fontSize"
            if let val = importedTokens.scalar(fsToken) {
                style.fontSizeToken = fsToken
                style.fontSize = val
            }
            
            let lhToken = "paragraph.\(style.id).lineHeight"
            if let val = importedTokens.scalar(lhToken) {
                style.lineHeightToken = lhToken
                style.lineHeight = val
            }
            
            let indentToken = "paragraph.\(style.id).firstLineIndent"
            if let val = importedTokens.scalar(indentToken) {
                style.firstLineIndentToken = indentToken
                style.firstLineIndent = val
            }
            
            let beforeToken = "paragraph.\(style.id).spaceBefore"
            if let val = importedTokens.scalar(beforeToken) {
                style.spaceBeforeToken = beforeToken
                style.spaceBefore = val
            }
            
            let afterToken = "paragraph.\(style.id).spaceAfter"
            if let val = importedTokens.scalar(afterToken) {
                style.spaceAfterToken = afterToken
                style.spaceAfter = val
            }
            
            styles[idx] = style
        }
        currentProject.styles.paragraphStyles = styles
        
        var setup = currentProject.pageSetup
        var newMargins = setup.margins
        
        let mtToken = "page.margin.top"
        if let val = importedTokens.scalar(mtToken) {
            newMargins.top = val
        }
        let mrToken = "page.margin.right"
        if let val = importedTokens.scalar(mrToken) {
            newMargins.right = val
        }
        let mbToken = "page.margin.bottom"
        if let val = importedTokens.scalar(mbToken) {
            newMargins.bottom = val
        }
        let mlToken = "page.margin.left"
        if let val = importedTokens.scalar(mlToken) {
            newMargins.left = val
        }
        
        setup.margins = newMargins // sets margins, triggers didSet (clearing tokens)
        
        // Re-apply tokens after setting margins
        if importedTokens.scalar(mtToken) != nil {
            setup.marginTopToken = mtToken
        }
        if importedTokens.scalar(mrToken) != nil {
            setup.marginRightToken = mrToken
        }
        if importedTokens.scalar(mbToken) != nil {
            setup.marginBottomToken = mbToken
        }
        if importedTokens.scalar(mlToken) != nil {
            setup.marginLeftToken = mlToken
        }
        
        let colsToken = "page.columns"
        if let val = importedTokens.scalar(colsToken) {
            setup.columns = max(1, Int(round(val)))
            setup.columnsToken = colsToken
        }
        let gutToken = "page.gutter"
        if let val = importedTokens.scalar(gutToken) {
            setup.gutter = val
            setup.gutterToken = gutToken
        }
        
        let bgToken = "page.baselineGrid"
        if let val = importedTokens.scalar(bgToken) {
            setup.baselineGrid = val
            setup.baselineGridToken = bgToken
        } else if let comp = baselineGridCompensate {
            setup.baselineGrid = comp
            setup.baselineGridToken = nil
        }
        
        currentProject.pageSetup = setup
        self.project = currentProject
    }

    func applyStyleTemplate(_ template: StyleTemplate) {
        commitState()
        var currentProject = project
        currentProject.styles = template.styleLibrary
        self.project = currentProject
    }

    func applyAvailablePreflightFixes() {
        commitState()
        guard let report else { return }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: report.issues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFix(_ fix: PreflightAutoFixKind, targetingAssetId: UUID? = nil, targetingFrameId: UUID? = nil) {
        commitState()
        let result = PreflightAutoFixer().applyFixes(
            [fix],
            to: project,
            targetingAssetId: targetingAssetId,
            targetingFrameId: targetingFrameId
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func applyPreflightFixes(in category: PreflightIssueCategory) {
        commitState()
        guard let report else { return }
        let categoryIssues = report.issues.filter { $0.category == category }
        let result = PreflightAutoFixer().applyAvailableFixes(
            to: project,
            issues: categoryIssues
        )
        guard !result.appliedFixes.isEmpty else { return }
        self.project = result.project
    }

    func insertPage(at pageNum: Int) {
        commitState()
        var currentProject = project
        let plans = currentProject.safeAppliedLayoutPlans
        
        var newPlans: [Int: LayoutPlan] = [:]
        for (k, v) in plans {
            if k >= pageNum {
                newPlans[k + 1] = v.retargeted(to: .page(k + 1))
            } else {
                newPlans[k] = v
            }
        }
        newPlans[pageNum] = LayoutPlan(
            target: .page(pageNum),
            strategy: .balanced,
            blocks: [],
            notes: ["手动插入空白页"]
        )
        currentProject.safeAppliedLayoutPlans = newPlans
        
        let locked = currentProject.safeLockedPages
        var newLocked = Set<Int>()
        for k in locked {
            if k >= pageNum {
                newLocked.insert(k + 1)
            } else {
                newLocked.insert(k)
            }
        }
        currentProject.safeLockedPages = newLocked
        
        self.project = currentProject
        self.currentPageNumber = pageNum
    }
    
    func deletePage(at pageNum: Int) {
        commitState()
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        plans.removeValue(forKey: pageNum)
        
        var newPlans: [Int: LayoutPlan] = [:]
        for (k, v) in plans {
            if k > pageNum {
                newPlans[k - 1] = v.retargeted(to: .page(k - 1))
            } else {
                newPlans[k] = v
            }
        }
        currentProject.safeAppliedLayoutPlans = newPlans
        
        var locked = currentProject.safeLockedPages
        locked.remove(pageNum)
        var newLocked = Set<Int>()
        for k in locked {
            if k > pageNum {
                newLocked.insert(k - 1)
            } else {
                newLocked.insert(k)
            }
        }
        currentProject.safeLockedPages = newLocked
        
        self.project = currentProject
        self.currentPageNumber = max(1, pageNum - 1)
    }

    // NOTE: free-frame authoring (addFrameToPage) was removed deliberately.
    // layoutD does not let users draw arbitrary frames; manual layout work is
    // limited to fine-tuning existing structured frames so every edit can be
    // captured as a LayoutPlan / override and re-rendered deterministically.

    func deleteFrame(id: UUID) {
        commitState()
        guard let pageNum = findPageNumber(for: id) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        plan.blocks.removeAll { $0.id == id }
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        
        var locked = currentProject.safeLockedPages
        locked.insert(pageNum)
        currentProject.safeLockedPages = locked
        
        self.selectedFrameId = nil
        self.project = currentProject
    }

    func applyColorToSelectedFrame(_ color: Color) {
        commitState()
        guard let frameId = selectedFrameId else { return }
        let hex = Self.printColor(from: color).storageString
        if activeFormattingTarget == .container {
            if isFillActive {
                frameBackgroundColors[frameId] = color
            } else {
                frameStrokeColors[frameId] = color
            }
        } else {
            frameTextColors[frameId] = color
        }
        updateSelectedFrameColors(
            backgroundColorHex: activeFormattingTarget == .container && isFillActive ? hex : nil,
            strokeColorHex: activeFormattingTarget == .container && !isFillActive ? hex : nil,
            textColorHex: activeFormattingTarget == .text ? hex : nil,
            shouldClear: false
        )
    }
    
    func removeColorFromSelectedFrame() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        if activeFormattingTarget == .container {
            if isFillActive {
                frameBackgroundColors.removeValue(forKey: frameId)
            } else {
                frameStrokeColors.removeValue(forKey: frameId)
            }
        } else {
            frameTextColors.removeValue(forKey: frameId)
        }
        updateSelectedFrameColors(
            backgroundColorHex: activeFormattingTarget == .container && isFillActive ? "" : nil,
            strokeColorHex: activeFormattingTarget == .container && !isFillActive ? "" : nil,
            textColorHex: activeFormattingTarget == .text ? "" : nil,
            shouldClear: true
        )
    }

    // MARK: - Direct per-channel color editing (inspector color pickers)
    //
    // These drive fill / stroke / text independently of the toolbar's
    // container-vs-text target, so the inspector can offer three plain color
    // pickers. Continuous picker changes on one frame coalesce into a single
    // undo entry via `colorEditBurstFrame`.

    private func beginColorEditBurst(_ frameId: UUID) {
        if colorEditBurstFrame != frameId {
            commitState()               // resets colorEditBurstFrame to nil
            colorEditBurstFrame = frameId
        }
    }

    /// Converts a SwiftUI `Color` to a `PrintColor`, **preserving CMYK** when the
    /// color still carries a CMYK color space — e.g. picked via the standard
    /// ColorPicker's system panel "CMYK Sliders". SwiftUI↔NSColor bridging keeps
    /// the CMYK space (verified: model stays .cmyk), so the quick color well no
    /// longer silently flattens CMYK to RGB. Falls back to sRGB otherwise.
    static func printColor(from color: Color) -> PrintColor {
        let ns = NSColor(color)
        // `.colorSpace`/component access is only safe on component-based colors.
        if ns.type == .componentBased, ns.colorSpace.colorSpaceModel == .cmyk {
            return .cmyk(c: Double(ns.cyanComponent) * 100, m: Double(ns.magentaComponent) * 100,
                         y: Double(ns.yellowComponent) * 100, k: Double(ns.blackComponent) * 100)
        }
        let rgb = ns.usingColorSpace(.sRGB) ?? ns
        return .rgb(r: Int((Double(rgb.redComponent) * 255).rounded()),
                    g: Int((Double(rgb.greenComponent) * 255).rounded()),
                    b: Int((Double(rgb.blueComponent) * 255).rounded()))
    }

    func setSelectedFrameFillColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameBackgroundColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: Self.printColor(from: color).storageString, strokeColorHex: nil, textColorHex: nil, shouldClear: false)
    }

    func clearSelectedFrameFillColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameBackgroundColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: "", strokeColorHex: nil, textColorHex: nil, shouldClear: true)
    }

    func setSelectedFrameStrokeColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameStrokeColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: Self.printColor(from: color).storageString, textColorHex: nil, shouldClear: false)
    }

    func clearSelectedFrameStrokeColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameStrokeColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: "", textColorHex: nil, shouldClear: true)
    }

    func setSelectedFrameTextColor(_ color: Color) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameTextColors[frameId] = color
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: Self.printColor(from: color).storageString, shouldClear: false)
    }

    func clearSelectedFrameTextColor() {
        commitState()
        guard let frameId = selectedFrameId else { return }
        frameTextColors.removeValue(forKey: frameId)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: "", shouldClear: true)
    }

    // MARK: - PrintColor 通路（CMYK 原生）
    //
    // 与上面吃 SwiftUI `Color` 的快捷 setter 并存：多套系拾色器提交的是
    // `PrintColor`，其 storageString(可能是 `cmyk(...)`)直接写进模型，从而
    // 一路保持到 IDML 导出;画布即时预览用 displayRGB 近似色覆盖。

    private func previewColor(_ pc: PrintColor) -> Color {
        let c = pc.displayRGB
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    func setSelectedFrameFillColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameBackgroundColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: printColor.storageString, strokeColorHex: nil, textColorHex: nil, shouldClear: false)
    }

    func setSelectedFrameStrokeColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameStrokeColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: printColor.storageString, textColorHex: nil, shouldClear: false)
    }

    func setSelectedFrameTextColor(_ printColor: PrintColor) {
        guard let frameId = selectedFrameId else { return }
        beginColorEditBurst(frameId)
        frameTextColors[frameId] = previewColor(printColor)
        updateSelectedFrameColors(backgroundColorHex: nil, strokeColorHex: nil, textColorHex: printColor.storageString, shouldClear: false)
    }

    // MARK: - 色板库（自定义 swatch）

    var customSwatches: [PrintSwatch] { project.customSwatches ?? [] }

    /// 把一个颜色存进项目色板库。重复颜色(相同 storageString)不再新增。
    @discardableResult
    func addCustomSwatch(_ color: PrintColor, name: String? = nil) -> PrintSwatch? {
        var currentProject = project
        var list = currentProject.safeCustomSwatches
        guard !list.contains(where: { $0.colorString == color.storageString }) else { return nil }
        commitState()
        let swatch = PrintSwatch(name: name ?? Self.defaultSwatchName(for: color), color: color)
        list.append(swatch)
        currentProject.safeCustomSwatches = list
        self.project = currentProject
        return swatch
    }

    func removeCustomSwatch(id: UUID) {
        commitState()
        var currentProject = project
        currentProject.safeCustomSwatches.removeAll { $0.id == id }
        self.project = currentProject
    }

    private static func defaultSwatchName(for color: PrintColor) -> String {
        switch color {
        case let .rgb(r, g, b):
            return String(format: "R=%d G=%d B=%d", r, g, b)
        case .cmyk:
            return color.idmlSwatchName
        }
    }

    private func updateSelectedFrameColors(
        backgroundColorHex: String?,
        strokeColorHex: String?,
        textColorHex: String?,
        shouldClear: Bool
    ) {
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else {
            recalculateLayout()
            return
        }

        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)

        guard let index = plan.blocks.firstIndex(where: { $0.id == frameId }) else {
            recalculateLayout()
            return
        }

        if backgroundColorHex != nil {
            plan.blocks[index].backgroundColorHex = shouldClear ? nil : backgroundColorHex
        }
        if strokeColorHex != nil {
            plan.blocks[index].strokeColorHex = shouldClear ? nil : strokeColorHex
            if !shouldClear, plan.blocks[index].strokeWidth == nil {
                plan.blocks[index].strokeWidth = 1.5
            }
        }
        if textColorHex != nil {
            plan.blocks[index].textColorHex = shouldClear ? nil : textColorHex
        }

        plan.notes = ["手动修改元素颜色"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    /// Sets the selected frame's stroke weight (points), InDesign-style. Writes a
    /// plan-block override, undoable. Note the weight only shows if a stroke colour
    /// is also set — matching InDesign, where weight and colour are independent.
    func setSelectedFrameStrokeWidth(_ width: Double) {
        commitState()
        guard let frameId = selectedFrameId,
              let pageNum = findPageNumber(for: frameId) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        guard let index = plan.blocks.firstIndex(where: { $0.id == frameId }) else { return }
        plan.blocks[index].strokeWidth = max(width, 0)
        plan.notes = ["手动修改描边粗细"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }

    func updateFrameCoordinate(id: UUID, x: Double?, y: Double?, width: Double?, height: Double?) {
        updateFrameCoordinatesWithoutUndo(id: id, x: x, y: y, width: width, height: height)
    }

    private func updateFrameCoordinatesWithoutUndo(id: UUID, x: Double?, y: Double?, width: Double?, height: Double?) {
        guard let pageNum = findPageNumber(for: id) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        if let idx = plan.blocks.firstIndex(where: { $0.id == id }) {
            let pageSize = project.pageSetup.pageSize
            var block = plan.blocks[idx]
            block.updateAbsoluteFrame(
                pageSize: pageSize,
                x: x,
                y: y,
                width: width,
                height: height
            )
            plan.blocks[idx] = block
            plan.notes = ["手动修改元素坐标"]
            plans[pageNum] = plan
            currentProject.safeAppliedLayoutPlans = plans
            self.project = currentProject
        }
    }

    func updateGapFrames(firstId: UUID, firstRect: Rect, secondId: UUID, secondRect: Rect) {
        guard let pageNum = findPageNumber(for: firstId) else { return }
        var currentProject = project
        var plans = currentProject.safeAppliedLayoutPlans
        var plan = plans[pageNum] ?? freezePageToPlan(pageNum: pageNum)
        
        let pageSize = project.pageSetup.pageSize
        
        if let idx1 = plan.blocks.firstIndex(where: { $0.id == firstId }) {
            var block1 = plan.blocks[idx1]
            block1.updateAbsoluteFrame(
                pageSize: pageSize,
                x: firstRect.x,
                y: firstRect.y,
                width: firstRect.width,
                height: firstRect.height
            )
            plan.blocks[idx1] = block1
        }
        
        if let idx2 = plan.blocks.firstIndex(where: { $0.id == secondId }) {
            var block2 = plan.blocks[idx2]
            block2.updateAbsoluteFrame(
                pageSize: pageSize,
                x: secondRect.x,
                y: secondRect.y,
                width: secondRect.width,
                height: secondRect.height
            )
            plan.blocks[idx2] = block2
        }
        
        plan.notes = ["间距工具调整元素位置"]
        plans[pageNum] = plan
        currentProject.safeAppliedLayoutPlans = plans
        self.project = currentProject
    }
}


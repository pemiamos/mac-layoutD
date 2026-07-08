import Combine
import SwiftUI
import LayoutDCore
import LayoutDEngine
import LayoutDDesignAI
import LayoutDCheck
import LayoutDImport

final class AppState: ObservableObject {
    var isAsync: Bool = NSClassFromString("XCTestCase") == nil
    var pendingLayoutWorkItem: DispatchWorkItem?
    var layoutVersion = 0
    var isUpdatingQualityHistory = false

    @Published var project: BookProject {
        didSet {
            if !isUpdatingQualityHistory {
                recalculateLayout()
            }
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
    var isMutatingSelectionSet = false
    @Published var activeTool: LayoutTool = .selection
    @Published var projectURL: URL?
    
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
    
    var undoStack: [BookProject] = []
    var redoStack: [BookProject] = []
    var isPerformingUndoRedo = false
    var isPerformingRecalculation = false

    /// The stripped project the current `baselineDocument` was laid out from.
    /// Plan-only edits (apply/clear a LayoutPlan, quality-history bookkeeping)
    /// leave this value unchanged, so the second full-book layout is skipped.
    var baselineSource: BookProject?
    /// How many times the baseline document was actually laid out (test hook).
    var baselineLayoutCount = 0
    
    let engine = LayoutEngine()
    let inspectorEngine = ProjectInspector()
    let advisor = RuleBasedLayoutAdvisor()
    
    var onLayoutCompleted: ((BookProject, LaidOutDocument) -> Void)?
    
    init(project: BookProject) {
        self.project = project
        recalculateLayoutSync()
    }

    /// Frame currently mid color-adjust. Continuous color-picker changes on this
    /// frame coalesce into a single undo entry (see setSelectedFrame*Color); any
    /// other committed action ends the burst.
    var colorEditBurstFrame: UUID?

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
}

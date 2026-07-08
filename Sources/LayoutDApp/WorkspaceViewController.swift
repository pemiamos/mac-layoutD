import AppKit
import Combine
import Foundation
import SwiftUI
import LayoutDCheck
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
import LayoutDImport
import UniformTypeIdentifiers

final class WorkspaceViewController: NSViewController {
    private var appState: AppState
    private var sourceDescription: String
    private let canvas = CanvasView()
    private var selectedFrameCancellable: AnyCancellable?
    private var selectedFrameIdsCancellable: AnyCancellable?
    private var screenModeCancellable: AnyCancellable?
    private var backgroundColorsCancellable: AnyCancellable?
    private var strokeColorsCancellable: AnyCancellable?
    private var textColorsCancellable: AnyCancellable?
    private var activeToolCancellable: AnyCancellable?

    init(project: BookProject, sourceDescription: String) {
        self.sourceDescription = sourceDescription
        self.appState = AppState(project: project)
        super.init(nibName: nil, bundle: nil)
        
        self.appState.onLayoutCompleted = { [weak self] proj, doc in
            guard let self else { return }
            self.canvas.project = proj
            self.canvas.document = doc
            self.canvas.baselineDocument = self.appState.baselineDocument
            self.view.window?.title = "layoutD - \(proj.metadata.title)"
        }
        
        self.selectedFrameCancellable = appState.$selectedFrameId.sink { [weak self] frameId in
            self?.canvas.selectedFrameId = frameId
        }

        self.selectedFrameIdsCancellable = appState.$selectedFrameIds.sink { [weak self] ids in
            self?.canvas.selectedFrameIds = ids
        }

        self.screenModeCancellable = appState.$activeScreenMode.sink { [weak self] mode in
            self?.canvas.activeScreenMode = mode
        }
        
        self.backgroundColorsCancellable = appState.$frameBackgroundColors.sink { [weak self] colors in
            self?.canvas.frameBackgroundColors = colors.mapValues { NSColor($0) }
        }
        
        self.strokeColorsCancellable = appState.$frameStrokeColors.sink { [weak self] colors in
            self?.canvas.frameStrokeColors = colors.mapValues { NSColor($0) }
        }
        
        self.textColorsCancellable = appState.$frameTextColors.sink { [weak self] colors in
            self?.canvas.frameTextColors = colors.mapValues { NSColor($0) }
        }
        
        self.activeToolCancellable = appState.$activeTool.sink { [weak self] tool in
            self?.canvas.activeTool = tool
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    func undo() {
        appState.undo()
    }

    func redo() {
        appState.redo()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Focus the canvas so single-key toolbox shortcuts (V/A/T/F/U/H/Z, ⇧P) fire.
        // Text fields in the panels take focus while editing, which correctly
        // suppresses the shortcuts until focus returns to the canvas.
        view.window?.makeFirstResponder(canvas)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        canvas.project = appState.project
        canvas.document = appState.laidOutDocument
        canvas.baselineDocument = appState.baselineDocument
        
        canvas.onDragStarted = { [weak self] in
            self?.appState.beginUndoGrouping()
        }
        
        canvas.onFrameSelected = { [weak self] frameId in
            guard let self else { return }
            if self.appState.activeTool == .selection || self.appState.activeTool == .directSelection {
                self.appState.selectedFrameId = frameId
            }
        }
        
        canvas.onFrameDragged = { [weak self] frameId, x, y, w, h in
            guard let self else { return }
            self.appState.updateFrameCoordinate(id: frameId, x: x, y: y, width: w, height: h)
        }

        canvas.onToggleSelection = { [weak self] frameId in
            guard let self else { return }
            if self.appState.activeTool == .selection || self.appState.activeTool == .directSelection {
                self.appState.toggleFrameSelection(frameId)
            }
        }

        canvas.onMarqueeSelected = { [weak self] ids, anchor in
            guard let self else { return }
            if self.appState.activeTool == .selection || self.appState.activeTool == .directSelection {
                self.appState.setSelection(ids, anchor: anchor)
            }
        }

        canvas.onFramesDragged = { [weak self] updates in
            guard let self else { return }
            let origins = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, (x: $0.rect.x, y: $0.rect.y)) })
            self.appState.applyFrameOrigins(origins, note: "手动移动多个元素")
        }

        canvas.onLineEndpointDragged = { [weak self] id, rect in
            self?.appState.updateLineGeometry(id: id, rect: rect)
        }

        canvas.onGapDragged = { [weak self] firstId, firstRect, secondId, secondRect in
            guard let self else { return }
            self.appState.updateGapFrames(firstId: firstId, firstRect: firstRect, secondId: secondId, secondRect: secondRect)
        }
        
        canvas.onPageSelected = { [weak self] pageNum in
            guard let self else { return }
            self.appState.currentPageNumber = pageNum
        }

        canvas.onToolShortcut = { [weak self] tool in
            self?.appState.activeTool = tool
        }

        canvas.onFrameTextEdited = { [weak self] frameId, newText in
            guard let self else { return }
            // In-place editor commits against the frame it opened on; make sure that
            // frame is the selection target before writing the generated override.
            self.appState.selectedFrameId = frameId
            self.appState.updateSelectedFrameText(newText)
        }

        canvas.onFrameDrawn = { [weak self] pageNum, rect in
            guard let self else { return }
            switch self.appState.activeTool {
            case .textFrame:
                self.appState.createDrawnFrame(kind: .text, onPage: pageNum, rect: rect)
                // Switch to selection so the freshly drawn frame is ready to adjust,
                // and the inspector's text-content editor is in reach.
                self.appState.activeTool = .selection
            case .imageFrame:
                if self.appState.project.assets.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "没有可用图片"
                    alert.informativeText = "请先在「面板 → 资产」里导入图片，再绘制图像框。绘制后可在检查器「更换图片」重新指定。"
                    alert.runModal()
                } else {
                    self.appState.createDrawnFrame(kind: .image, onPage: pageNum, rect: rect)
                    self.appState.activeTool = .selection
                }
            case .rectangle:
                self.appState.createDrawnFrame(kind: .rectangle, onPage: pageNum, rect: rect)
                self.appState.activeTool = .selection
            case .line:
                self.appState.createDrawnFrame(kind: .line, onPage: pageNum, rect: rect)
                self.appState.activeTool = .selection
            default:
                break
            }
        }
        
        canvas.onCanvasClick = { [weak self] pageNum, localPoint in
            guard let self else { return }
            let tool = self.appState.activeTool

            switch tool {
            case .selection, .directSelection:
                break
            case .textFrame, .imageFrame, .rectangle, .line:
                // Drawn via rubber-band drag (onFrameDrawn), not a plain click.
                break
            case .page:
                break
            case .gap:
                break
            case .type:
                // Pick the text frame under the cursor for editing. The type tool
                // no longer authors free text boxes; it selects existing
                // structured text/caption frames.
                if let document = self.appState.laidOutDocument,
                   let page = document.pages.first(where: { $0.number == pageNum }) {
                    let hit = page.frames.reversed().first { frame in
                        guard frame.kind == .text || frame.kind == .caption else { return false }
                        let fRect = CGRect(x: frame.rect.x, y: frame.rect.y, width: frame.rect.width, height: frame.rect.height)
                        return fRect.contains(localPoint)
                    }
                    if let hit {
                        self.appState.selectedFrameId = hit.id
                    }
                }

            case .zoom:
                self.zoomIn()

            case .hand:
                break

            case .annotation:
                // 1. Check if clicking close to an existing annotation to delete it
                let threshold: Double = 15.0
                if let hitAnnotation = self.appState.project.safeAnnotations.first(where: { ann in
                    ann.pageNumber == pageNum &&
                    sqrt(pow(ann.x - Double(localPoint.x), 2) + pow(ann.y - Double(localPoint.y), 2)) < threshold
                }) {
                    let alert = NSAlert()
                    alert.messageText = "删除批注"
                    alert.informativeText = "确定要删除这条批注吗？\n\"\(hitAnnotation.text)\""
                    alert.addButton(withTitle: "删除")
                    alert.addButton(withTitle: "取消")
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.appState.updateProject { project in
                            var currentAnnotations = project.safeAnnotations
                            currentAnnotations.removeAll(where: { $0.id == hitAnnotation.id })
                            project.safeAnnotations = currentAnnotations
                        }
                    }
                    return
                }

                // 2. Add new annotation
                let alert = NSAlert()
                alert.messageText = "添加批注"
                alert.informativeText = "请输入要在此处添加的校对批注内容："
                alert.addButton(withTitle: "添加")
                alert.addButton(withTitle: "取消")
                
                let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                inputTextField.placeholderString = "批注内容"
                alert.accessoryView = inputTextField
                
                if alert.runModal() == .alertFirstButtonReturn {
                    let text = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.appState.updateProject { project in
                            var currentAnnotations = project.safeAnnotations
                            let newAnnotation = BookAnnotation(
                                pageNumber: pageNum,
                                x: Double(localPoint.x),
                                y: Double(localPoint.y),
                                text: text
                            )
                            currentAnnotations.append(newAnnotation)
                            project.safeAnnotations = currentAnnotations
                        }
                    }
                }
            }
        }
    }

    private func buildInterface() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        let sidebarView = SidebarView(state: appState) { [weak self] pageNum in
            self?.canvas.scrollToPage(number: pageNum)
        }
        let inspectorView = InspectorView(
            state: appState,
            onIssueClick: { [weak self] issue in
                guard let self else { return }
                if let page = issue.pageNumber {
                    self.appState.currentPageNumber = page
                    self.canvas.scrollToPage(number: page)
                }
                self.appState.selectedFrameId = issue.frameId
                self.canvas.highlightedFrameId = issue.frameId
            },
            onApplyPlan: { [weak self] plan in
                guard let self else { return }
                self.appState.applyLayoutPlan(plan)
            }
        )
        let toolbarView = ToolbarView(state: appState)
        let toolbarHost = NSHostingView(rootView: toolbarView)
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbarHost)

        // InDesign 式顶部控制面板：横贯窗口、上下文敏感（选中帧显示 X/Y/宽/高）。
        let controlPanelHost = NSHostingView(rootView: ControlPanelView(state: appState))
        controlPanelHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlPanelHost)

        // InDesign 式底部状态栏：页码导航 + 预检状态灯 + 缩放。
        let statusBarView = StatusBarView(
            state: appState,
            onGoToPage: { [weak self] page in self?.goToPage(page) },
            onZoomIn: { [weak self] in self?.zoomIn() },
            onZoomOut: { [weak self] in self?.zoomOut() },
            onFitWidth: { [weak self] in self?.fitWidth() }
        )
        let statusBarHost = NSHostingView(rootView: statusBarView)
        statusBarHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBarHost)

        canvas.onZoomChanged = { [weak self] scale in
            self?.appState.zoomPercent = Int((scale * 100).rounded())
        }

        let canvasScroll = NSScrollView()
        canvasScroll.documentView = canvas
        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true
        canvasScroll.translatesAutoresizingMaskIntoConstraints = false

        // InDesign 式右侧面板坞：面板（页面/属性/图层/资产/色板）与检查器合并为
        // 一列分段切换；两个 SwiftUI 面板自带滚动，由坞直接托管。
        let dockHost = NSHostingView(rootView: PanelDockView(sidebar: sidebarView, inspector: inspectorView))
        dockHost.translatesAutoresizingMaskIntoConstraints = false
        dockHost.wantsLayer = true
        dockHost.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        splitView.addArrangedSubview(canvasScroll)
        splitView.addArrangedSubview(dockHost)

        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        NSLayoutConstraint.activate([
            controlPanelHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlPanelHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlPanelHost.topAnchor.constraint(equalTo: view.topAnchor),

            toolbarHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarHost.topAnchor.constraint(equalTo: controlPanelHost.bottomAnchor),
            toolbarHost.bottomAnchor.constraint(equalTo: statusBarHost.topAnchor),
            toolbarHost.widthAnchor.constraint(equalToConstant: 42),

            splitView.leadingAnchor.constraint(equalTo: toolbarHost.trailingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: controlPanelHost.bottomAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBarHost.topAnchor),

            statusBarHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dockHost.widthAnchor.constraint(equalToConstant: 320)
        ])
    }

    /// Status-bar page navigation: clamp, sync state, scroll the canvas.
    func goToPage(_ page: Int) {
        let pageCount = appState.laidOutDocument?.pages.count ?? 1
        let target = min(max(page, 1), max(pageCount, 1))
        appState.currentPageNumber = target
        canvas.scrollToPage(number: target)
    }

    func openProject() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Project, Markdown/DOCX Manuscript, or Chapter Package"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "layoutd"),
            UTType.json,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt"),
            UTType(filenameExtension: "docx")
        ].compactMap { $0 }

        guard let window = view.window else {
            return
        }

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = openPanel.url, let self else {
                return
            }

            do {
                let loader = ProjectLoader()
                let loadedProj = try loader.loadProject(inputURL: url)
                self.sourceDescription = loader.sourceDescription(for: url)
                self.appState.currentPageNumber = 1
                self.appState.project = loadedProj
            } catch {
                self.showExportResult(message: "Open failed", detail: error.localizedDescription)
            }
        }
    }

    func saveProject() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save layoutD Project"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + ".layoutd"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "layoutd")].compactMap { $0 }
        savePanel.canCreateDirectories = true

        guard let window = view.window else {
            return
        }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            do {
                let project = projectForSaving(self.appState.project)
                self.appState.project = project
                let data = try ProjectFile.encode(project)
                try data.write(to: url, options: .atomic)
                self.showExportResult(message: "Project saved", detail: url.path)
            } catch {
                self.showExportResult(message: "Save failed", detail: error.localizedDescription)
            }
        }
    }

    func zoomIn() {
        canvas.zoomIn()
    }

    func zoomOut() {
        canvas.zoomOut()
    }

    func actualSize() {
        canvas.resetZoom()
    }

    func fitWidth() {
        canvas.fitWidth(availableWidth: canvas.enclosingScrollView?.contentView.bounds.width ?? canvas.bounds.width)
        canvas.scrollToPage(number: appState.currentPageNumber)
    }

    func previousPage() {
        appState.currentPageNumber = max(1, appState.currentPageNumber - 1)
        canvas.scrollToPage(number: appState.currentPageNumber)
    }

    func nextPage() {
        guard let document = appState.laidOutDocument else {
            return
        }
        appState.currentPageNumber = min(document.pages.count, appState.currentPageNumber + 1)
        canvas.scrollToPage(number: appState.currentPageNumber)
    }

    /// Wraps a SwiftUI settings view for use as an `NSSavePanel`/`NSOpenPanel`
    /// `accessoryView`. A bare `NSHostingView` assigned directly as an accessory
    /// renders correctly but frequently won't receive mouse clicks — the
    /// checkboxes look frozen (exactly the IDML export symptom). Embedding it in a
    /// plain, concretely-sized `NSView` container with pinning constraints
    /// restores hit-testing.
    private func makeExportAccessoryView<Content: View>(_ content: Content) -> NSView {
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let size = hosting.fittingSize
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hosting.widthAnchor.constraint(equalToConstant: size.width)
        ])
        return container
    }

    func exportPDF() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let savePanel = NSSavePanel()
        savePanel.title = "Export PDF"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + ".pdf"
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true

        let settingsState = PDFExportSettingsState()
        let settingsView = PDFExportSettingsView(state: settingsState)
        savePanel.accessoryView = makeExportAccessoryView(settingsView)

        savePanel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            // Remember the chosen prepress-relevant settings so the live preflight
            // panel and any exported preflight report reflect them.
            self.appState.pdfExportOptions = PrepressExportOptions(
                pdfxRequested: settingsState.pdfxVersion != .none,
                pdfxLabel: settingsState.pdfxVersion.pdfxStandardName,
                drawCropMarks: settingsState.drawCropMarks
            )
            self.appState.recalculateLayout()

            do {
                try PDFExporter().export(
                    document: document,
                    project: self.appState.project,
                    to: url,
                    pageRange: settingsState.pageRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : settingsState.pageRange,
                    drawCropMarks: settingsState.drawCropMarks,
                    drawGridGuides: settingsState.drawGridGuides,
                    pdfxVersion: settingsState.pdfxVersion
                )
                self.showExportResult(message: "PDF exported", detail: url.path)
            } catch {
                self.showExportResult(message: "PDF export failed", detail: error.localizedDescription)
            }
        }
    }

    func exportPNGPreviews() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let openPanel = NSOpenPanel()
        openPanel.title = "Export PNG Previews"
        openPanel.prompt = "Export"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false

        let settingsState = PNGExportSettingsState()
        let settingsView = PNGExportSettingsView(state: settingsState)
        openPanel.accessoryView = makeExportAccessoryView(settingsView)

        guard let window = view.window else {
            return
        }

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = openPanel.url, let self else {
                return
            }

            do {
                let outputURLs = try PNGExporter().export(
                    document: document,
                    project: self.appState.project,
                    to: url,
                    pageRange: settingsState.pageRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : settingsState.pageRange,
                    scale: settingsState.scale
                )
                self.showExportResult(
                    message: "PNG previews exported",
                    detail: "\(outputURLs.count) file(s) written to \(url.path)"
                )
            } catch {
                self.showExportResult(message: "PNG export failed", detail: error.localizedDescription)
            }
        }
    }

    func exportIDML() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let savePanel = NSSavePanel()
        savePanel.title = "Export IDML"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + ".idml"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "idml")].compactMap { $0 }
        savePanel.canCreateDirectories = true

        let settingsState = IDMLExportSettingsState()
        // Reflect the document's own page setup as the default, so the exported IDML
        // matches what the user already sees in layoutD's own preview unless they
        // explicitly override it in this dialog.
        settingsState.cmykColors = appState.project.pageSetup.colorSpace == .cmyk
        settingsState.facingPages = appState.project.pageSetup.facingPages
        savePanel.accessoryView = makeExportAccessoryView(IDMLExportSettingsView(state: settingsState))

        guard let window = view.window else { return }
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else { return }

            if settingsState.requireExportReady {
                let report = self.appState.inspectorEngine.preflight(
                    project: self.appState.project,
                    document: document,
                    exportOptions: self.appState.pdfExportOptions
                )
                guard report.exportReady else {
                    let errorCount = report.severityCounts[IssueSeverity.error.rawValue, default: 0]
                    self.showExportResult(
                        message: "IDML export blocked",
                        detail: "Preflight found \(errorCount) blocking error(s). Disable the export-ready requirement or fix them first."
                    )
                    return
                }
            }

            do {
                let options = IDMLExportOptions(
                    facingPages: settingsState.facingPages,
                    cmykColors: settingsState.cmykColors
                )
                try IDMLExporter().export(
                    document: document,
                    project: self.appState.project,
                    to: url,
                    options: options
                )
                self.showExportResult(
                    message: "IDML exported",
                    detail: "\(url.path)\nLinked images were copied to the adjacent Links folder."
                )
            } catch {
                self.showExportResult(message: "IDML export failed", detail: error.localizedDescription)
            }
        }
    }

    func exportPreflightReport() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let report = appState.inspectorEngine.preflight(
            project: appState.project,
            document: document,
            exportOptions: appState.pdfExportOptions
        )
        let savePanel = NSSavePanel()
        savePanel.title = "Export Preflight Report"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + "-preflight.json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true

        guard let window = view.window else {
            return
        }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                try data.write(to: url, options: .atomic)
                self.showExportResult(message: "Preflight report exported", detail: url.path)
            } catch {
                self.showExportResult(message: "Preflight export failed", detail: error.localizedDescription)
            }
        }
    }

    func exportProjectPackage() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Project Package"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + ".layoutd-pack"
        savePanel.allowedContentTypes = [
            UTType(filenameExtension: "layoutd-pack"),
            UTType.zip
        ].compactMap { $0 }
        savePanel.canCreateDirectories = true

        guard let window = view.window else {
            return
        }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            do {
                try ResourceBundlePackager().package(project: self.appState.project, to: url)
                self.showExportResult(message: "Project package exported", detail: url.path)
            } catch {
                self.showExportResult(message: "Package export failed", detail: error.localizedDescription)
            }
        }
    }

    func importLayoutTemplates() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Layout Templates"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [
            UTType.json,
            UTType(filenameExtension: "layoutd-templates")
        ].compactMap { $0 }

        guard let window = view.window else {
            return
        }

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = openPanel.url, let self else {
                return
            }

            do {
                let data = try Data(contentsOf: url)
                let library = try LayoutTemplateLibrary.decode(data)
                var project = self.appState.project
                let beforeCount = project.safeSavedLayoutTemplates.count
                project.importLayoutTemplateLibrary(library)
                let importedCount = project.safeSavedLayoutTemplates.count - beforeCount
                self.appState.project = project
                self.showExportResult(
                    message: "Layout templates imported",
                    detail: "\(importedCount) template(s) imported from \(url.path)"
                )
            } catch {
                self.showExportResult(message: "Template import failed", detail: error.localizedDescription)
            }
        }
    }

    /// Import a layoutD visual spec pack / Figma / DTCG style baseline from the menu
    /// bar and apply it to the current project. Spec packs carry the full
    /// SpecPackImportResult (fonts / role colors / trim), matching the CLI
    /// `--spec-pack` and Inspector「导入样式基线」paths (SPEC-APPLY-1).
    func importStyleBaseline() {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入样式基线 / 规范包（layoutD 规范包 / Figma / DTCG JSON）"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard let window = view.window else { return }

        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = openPanel.url, let self else { return }
            do {
                let data = try Data(contentsOf: url)
                let detected = try StyleBaselineImporter.autoDetectAndParseDetailed(jsonData: data)
                if let specResult = detected.specResult {
                    self.appState.applySpecPackResult(specResult)
                    var detail = "规范包已应用：\(specResult.fontResolutions.count) 项字体、\(specResult.roleColors.count) 个角色色，字体/角色色/开本已落地。"
                    if !specResult.unsupportedFields.isEmpty {
                        detail += "\n\(specResult.unsupportedFields.count) 个字段暂不支持（已忽略）。"
                    }
                    self.showExportResult(message: "规范包导入成功", detail: detail)
                } else {
                    self.appState.applyImportedTokens(detected.tokens)
                    self.showExportResult(
                        message: "样式基线导入成功",
                        detail: "\(detected.format == .figma ? "Figma" : "DTCG") token 已应用（\(detected.tokens.colors.count) 色 / \(detected.tokens.scalars.count) 数值）。"
                    )
                }
            } catch {
                self.showExportResult(message: "样式导入失败", detail: error.localizedDescription)
            }
        }
    }

    func exportLayoutTemplates() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Layout Templates"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + "-templates.layoutd-templates"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "layoutd-templates")].compactMap { $0 }
        savePanel.canCreateDirectories = true

        guard let window = view.window else {
            return
        }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            do {
                let library = LayoutTemplateLibrary(project: self.appState.project)
                let data = try LayoutTemplateLibrary.encode(library)
                try data.write(to: url, options: .atomic)
                self.showExportResult(
                    message: "Layout templates exported",
                    detail: "\(library.templates.count) template(s) written to \(url.path)"
                )
            } catch {
                self.showExportResult(message: "Template export failed", detail: error.localizedDescription)
            }
        }
    }

    private func showExportResult(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func safeFileName(_ title: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return title
            .components(separatedBy: illegalCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension NSToolbarItem.Identifier {
    static let openProject = NSToolbarItem.Identifier("openProject")
    static let saveProject = NSToolbarItem.Identifier("saveProject")
    static let prevPage = NSToolbarItem.Identifier("prevPage")
    static let nextPage = NSToolbarItem.Identifier("nextPage")
    static let zoomOut = NSToolbarItem.Identifier("zoomOut")
    static let zoomActual = NSToolbarItem.Identifier("zoomActual")
    static let zoomIn = NSToolbarItem.Identifier("zoomIn")
    static let fitWidth = NSToolbarItem.Identifier("fitWidth")
    static let lockPage = NSToolbarItem.Identifier("lockPage")
    static let resetPage = NSToolbarItem.Identifier("resetPage")
    static let exportPDF = NSToolbarItem.Identifier("exportPDF")
    static let exportIDML = NSToolbarItem.Identifier("exportIDML")
    static let exportPackage = NSToolbarItem.Identifier("exportPackage")
}

extension WorkspaceViewController: NSToolbarDelegate {
    @objc func toolbarOpen(_ sender: Any?) { openProject() }
    @objc func toolbarSave(_ sender: Any?) { saveProject() }
    @objc func toolbarPrevPage(_ sender: Any?) { previousPage() }
    @objc func toolbarNextPage(_ sender: Any?) { nextPage() }
    @objc func toolbarZoomOut(_ sender: Any?) { zoomOut() }
    @objc func toolbarZoomActual(_ sender: Any?) { actualSize() }
    @objc func toolbarZoomIn(_ sender: Any?) { zoomIn() }
    @objc func toolbarFitWidth(_ sender: Any?) { fitWidth() }
    @objc func toolbarExportPDF(_ sender: Any?) { exportPDF() }
    @objc func toolbarExportIDML(_ sender: Any?) { exportIDML() }
    @objc func toolbarExportPackage(_ sender: Any?) { exportProjectPackage() }
    
    @objc func toolbarToggleLock(_ sender: Any?) {
        let isLocked = appState.project.safeLockedPages.contains(appState.currentPageNumber)
        if isLocked {
            appState.unlockPage(number: appState.currentPageNumber)
        } else {
            appState.lockPage(number: appState.currentPageNumber)
        }
    }
    
    @objc func toolbarResetPage(_ sender: Any?) {
        appState.clearCustomLayoutForPage(number: appState.currentPageNumber)
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .openProject,
            .saveProject,
            .flexibleSpace,
            .prevPage,
            .nextPage,
            .flexibleSpace,
            .zoomOut,
            .zoomActual,
            .zoomIn,
            .fitWidth,
            .flexibleSpace,
            .lockPage,
            .resetPage,
            .flexibleSpace,
            .exportPDF,
            .exportIDML,
            .exportPackage
        ]
    }
    
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // InDesign 式精简：翻页/缩放已移到底部状态栏，窗口工具条只留文档级动作。
        return [
            .openProject,
            .saveProject,
            .flexibleSpace,
            .lockPage,
            .resetPage,
            .flexibleSpace,
            .exportPDF,
            .exportIDML,
            .exportPackage
        ]
    }
    
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier {
        case .openProject:
            item.label = "打开"
            item.paletteLabel = "打开项目"
            item.toolTip = "打开项目、Markdown 或是章节包"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")
            item.target = self
            item.action = #selector(toolbarOpen(_:))
            
        case .saveProject:
            item.label = "保存"
            item.paletteLabel = "保存项目"
            item.toolTip = "保存当前项目"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.target = self
            item.action = #selector(toolbarSave(_:))
            
        case .prevPage:
            item.label = "上一页"
            item.paletteLabel = "上一页"
            item.toolTip = "跳转到上一页"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Page")
            item.target = self
            item.action = #selector(toolbarPrevPage(_:))
            
        case .nextPage:
            item.label = "下一页"
            item.paletteLabel = "下一页"
            item.toolTip = "跳转到下一页"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Page")
            item.target = self
            item.action = #selector(toolbarNextPage(_:))
            
        case .zoomOut:
            item.label = "缩小"
            item.paletteLabel = "缩小"
            item.toolTip = "缩小画布"
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out")
            item.target = self
            item.action = #selector(toolbarZoomOut(_:))
            
        case .zoomActual:
            item.label = "实际大小"
            item.paletteLabel = "实际大小"
            item.toolTip = "恢复实际大小"
            item.image = NSImage(systemSymbolName: "equal", accessibilityDescription: "Actual Size")
            item.target = self
            item.action = #selector(toolbarZoomActual(_:))
            
        case .zoomIn:
            item.label = "放大"
            item.paletteLabel = "放大"
            item.toolTip = "放大画布"
            item.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In")
            item.target = self
            item.action = #selector(toolbarZoomIn(_:))
            
        case .fitWidth:
            item.label = "适应宽度"
            item.paletteLabel = "适应宽度"
            item.toolTip = "缩放画布以适应屏幕宽度"
            item.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: "Fit Width")
            item.target = self
            item.action = #selector(toolbarFitWidth(_:))
            
        case .lockPage:
            item.label = "锁定页"
            item.paletteLabel = "锁定页版式"
            item.toolTip = "锁定或解锁当前页面"
            item.image = NSImage(systemSymbolName: "lock", accessibilityDescription: "Lock Page")
            item.target = self
            item.action = #selector(toolbarToggleLock(_:))
            
        case .resetPage:
            item.label = "重置页"
            item.paletteLabel = "重置当前页版式"
            item.toolTip = "清除自定义版式并恢复默认"
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset Layout")
            item.target = self
            item.action = #selector(toolbarResetPage(_:))
            
        case .exportPDF:
            item.label = "导出 PDF"
            item.paletteLabel = "导出 PDF"
            item.toolTip = "导出排版好的 PDF 书稿"
            item.image = NSImage(systemSymbolName: "arrow.up.doc", accessibilityDescription: "Export PDF")
            item.target = self
            item.action = #selector(toolbarExportPDF(_:))

        case .exportIDML:
            item.label = "导出 IDML"
            item.paletteLabel = "导出 IDML"
            item.toolTip = "导出供 InDesign 精调的 IDML 文件"
            item.image = NSImage(systemSymbolName: "doc.badge.gearshape", accessibilityDescription: "Export IDML")
            item.target = self
            item.action = #selector(toolbarExportIDML(_:))
            
        case .exportPackage:
            item.label = "打包"
            item.paletteLabel = "打包项目素材包"
            item.toolTip = "打包为 ZIP 素材包"
            item.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Export Package")
            item.target = self
            item.action = #selector(toolbarExportPackage(_:))
            
        default:
            return nil
        }
        
        return item
    }
}

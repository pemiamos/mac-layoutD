import AppKit
import Combine
import Foundation
import LayoutDCheck
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
import LayoutDImport
import SwiftUI
import UniformTypeIdentifiers

let commandLineUsage = """
layoutD

Usage:
  swift run layoutD -- [options] [manuscript.md|project.layoutd|chapter-directory] [image-directory]

Options:
  --export-pdf PATH          Export a proof PDF without opening the app window.
  --pdf-pages RANGE          Limit PDF export to pages such as "1,3" or "2-5".
  --pdf-crop-marks          Add crop and bleed guide marks to PDF export.
  --pdf-grid-guides         Add margin, column, and baseline guides to PDF export.
  --pdf-version VERSION     Select PDF/X print version: none, pdfx1a, or pdfx3.
  --export-png DIRECTORY    Export page preview PNG files.
  --png-pages RANGE         Limit PNG export to pages such as "1,3" or "2-5".
  --png-scale VALUE         Set PNG output scale, default 2.0.
  --export-project PATH     Export a structured .layoutd project file.
  --export-package PATH     Export a packaged ZIP resource bundle (.layoutd-pack).
  --export-templates PATH   Export saved layout templates as a reusable JSON library.
  --import-templates PATH   Import a layout template library before export or validation.
  --apply-chapter-template NAME
                            Apply a chapter template: scienceChapter, imageRichChapter, or studyGuideChapter.
  --chapter-template-section N
                            Section number for --apply-chapter-template, default 1.
  --chapter-template-start-page N
                            First page for --apply-chapter-template plans, default 3.
  --preflight-report PATH   Export preflight JSON.
  --validate                Run preflight as a CLI quality gate.
  --apply-preflight-fixes   Apply conservative auto-fixes before export or validation.
  --help, -h                Show this help.
"""

let launchProject = ProjectLoader().loadFromCommandLine()

if launchProject.showHelp {
    print(commandLineUsage)
    exit(EXIT_SUCCESS)
}

if launchProject.exportPDFURL != nil
    || launchProject.exportPNGDirectoryURL != nil
    || launchProject.exportProjectURL != nil
    || launchProject.exportPackageURL != nil
    || launchProject.exportTemplateLibraryURL != nil
    || launchProject.preflightReportURL != nil
    || launchProject.validateOnly {
    do {
        if let loadError = launchProject.loadError {
            fputs("Load failed: \(loadError)\n", stderr)
            exit(EXIT_FAILURE)
        }

        var project = launchProject.project
        var document = LayoutEngine().layout(project: project)
        var report = ProjectInspector().preflight(project: project, document: document)

        if let chapterLayoutTemplate = launchProject.chapterLayoutTemplate {
            let appliedCount = project.applyChapterLayoutTemplate(
                chapterLayoutTemplate,
                sectionIndex: launchProject.chapterLayoutTemplateSectionIndex,
                startPage: launchProject.chapterLayoutTemplateStartPage
            )
            document = LayoutEngine().layout(project: project)
            report = ProjectInspector().preflight(project: project, document: document)
            print("Applied chapter template: \(chapterLayoutTemplate.rawValue), \(appliedCount) page plan(s)")
        }

        if launchProject.applyPreflightFixes {
            let result = PreflightAutoFixer().applyAvailableFixes(
                to: project,
                issues: report.issues
            )
            if !result.appliedFixes.isEmpty {
                project = result.project
                document = LayoutEngine().layout(project: project)
                report = ProjectInspector().preflight(project: project, document: document)
            }
            print("Applied preflight fixes: \(result.appliedFixes.count)")
        }

        if let exportProjectURL = launchProject.exportProjectURL {
            let data = try ProjectFile.encode(projectForSaving(project))
            try createParentDirectory(for: exportProjectURL)
            try data.write(to: exportProjectURL, options: .atomic)
            print("Exported project: \(exportProjectURL.path)")
        }

        if let exportPackageURL = launchProject.exportPackageURL {
            try ResourceBundlePackager().package(project: project, to: exportPackageURL)
            print("Exported project package: \(exportPackageURL.path)")
        }

        if let exportTemplateLibraryURL = launchProject.exportTemplateLibraryURL {
            let library = LayoutTemplateLibrary(project: project)
            let data = try LayoutTemplateLibrary.encode(library)
            try createParentDirectory(for: exportTemplateLibraryURL)
            try data.write(to: exportTemplateLibraryURL, options: .atomic)
            print("Exported layout templates: \(library.templates.count) template(s) to \(exportTemplateLibraryURL.path)")
        }

        if let preflightReportURL = launchProject.preflightReportURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try createParentDirectory(for: preflightReportURL)
            try data.write(to: preflightReportURL, options: .atomic)
            print("Exported preflight report: \(preflightReportURL.path)")
        }

        if let exportPDFURL = launchProject.exportPDFURL {
            try PDFExporter().export(
                document: document,
                project: project,
                to: exportPDFURL,
                pageRange: launchProject.exportPDFPageRange,
                drawCropMarks: launchProject.exportPDFDrawCropMarks,
                drawGridGuides: launchProject.exportPDFDrawGridGuides,
                pdfxVersion: launchProject.pdfxVersion
            )
            print("Exported PDF: \(exportPDFURL.path)")
        }

        if let exportPNGDirectoryURL = launchProject.exportPNGDirectoryURL {
            let outputURLs = try PNGExporter().export(
                document: document,
                project: project,
                to: exportPNGDirectoryURL,
                pageRange: launchProject.exportPNGPageRange,
                scale: launchProject.exportPNGScale
            )
            print("Exported PNG previews: \(outputURLs.count) file(s) to \(exportPNGDirectoryURL.path)")
        }

        if launchProject.validateOnly {
            if report.exportReady {
                print("Validation passed: \(project.metadata.title)")
            } else {
                fputs("Validation failed: \(report.severityCounts[IssueSeverity.error.rawValue, default: 0]) error(s)\n", stderr)
                for issue in report.issues where issue.severity == .error {
                    fputs("- \(issue.message)\n", stderr)
                }
                exit(2)
            }
        }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Export failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(launchProject: launchProject)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

func createParentDirectory(for url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
}

func projectForSaving(_ project: BookProject) -> BookProject {
    var project = project
    project.metadata.modifiedAt = Date()
    return project
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private weak var workspaceController: WorkspaceViewController?
    private let launchProject: LoadedProject

    init(launchProject: LoadedProject) {
        self.launchProject = launchProject
        super.init()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = WorkspaceViewController(
            project: launchProject.project,
            sourceDescription: launchProject.sourceDescription
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "layoutD - \(launchProject.project.metadata.title)"
        window.center()
        window.contentViewController = controller
        window.acceptsMouseMovedEvents = true
        
        let toolbar = NSToolbar(identifier: "LayoutDMainToolbar")
        toolbar.delegate = controller
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.workspaceController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func exportPDF(_ sender: Any?) {
        workspaceController?.exportPDF()
    }

    @objc private func exportPNGPreviews(_ sender: Any?) {
        workspaceController?.exportPNGPreviews()
    }

    @objc private func exportPreflightReport(_ sender: Any?) {
        workspaceController?.exportPreflightReport()
    }

    @objc private func exportProjectPackage(_ sender: Any?) {
        workspaceController?.exportProjectPackage()
    }

    @objc private func importLayoutTemplates(_ sender: Any?) {
        workspaceController?.importLayoutTemplates()
    }

    @objc private func exportLayoutTemplates(_ sender: Any?) {
        workspaceController?.exportLayoutTemplates()
    }

    @objc private func openProject(_ sender: Any?) {
        workspaceController?.openProject()
    }

    @objc private func saveProject(_ sender: Any?) {
        workspaceController?.saveProject()
    }

    @objc private func zoomIn(_ sender: Any?) {
        workspaceController?.zoomIn()
    }

    @objc private func zoomOut(_ sender: Any?) {
        workspaceController?.zoomOut()
    }

    @objc private func actualSize(_ sender: Any?) {
        workspaceController?.actualSize()
    }

    @objc private func fitWidth(_ sender: Any?) {
        workspaceController?.fitWidth()
    }

    @objc private func previousPage(_ sender: Any?) {
        workspaceController?.previousPage()
    }

    @objc private func nextPage(_ sender: Any?) {
        workspaceController?.nextPage()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "Quit layoutD",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            NSMenuItem(
                title: "Open Project, Markdown, or Chapter Package...",
                action: #selector(openProject(_:)),
                keyEquivalent: "o"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(
            NSMenuItem(
                title: "Save Project...",
                action: #selector(saveProject(_:)),
                keyEquivalent: "s"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(
            NSMenuItem(
                title: "Export PDF...",
                action: #selector(exportPDF(_:)),
                keyEquivalent: "e"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(
            NSMenuItem(
                title: "Export PNG Previews...",
                action: #selector(exportPNGPreviews(_:)),
                keyEquivalent: "p"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(
            NSMenuItem(
                title: "Export Preflight Report...",
                action: #selector(exportPreflightReport(_:)),
                keyEquivalent: "r"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(
            NSMenuItem(
                title: "Export Project Package...",
                action: #selector(exportProjectPackage(_:)),
                keyEquivalent: "k"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(
            NSMenuItem(
                title: "Import Layout Templates...",
                action: #selector(importLayoutTemplates(_:)),
                keyEquivalent: "i"
            )
        )
        fileMenu.items.last?.target = self
        fileMenu.addItem(
            NSMenuItem(
                title: "Export Layout Templates...",
                action: #selector(exportLayoutTemplates(_:)),
                keyEquivalent: "t"
            )
        )
        fileMenu.items.last?.target = self
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let viewItems: [(String, Selector, String)] = [
            ("Zoom In", #selector(zoomIn(_:)), "+"),
            ("Zoom Out", #selector(zoomOut(_:)), "-"),
            ("Actual Size", #selector(actualSize(_:)), "0"),
            ("Fit Width", #selector(fitWidth(_:)), "9")
        ]
        for item in viewItems {
            viewMenu.addItem(NSMenuItem(title: item.0, action: item.1, keyEquivalent: item.2))
            viewMenu.items.last?.target = self
        }
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(
            NSMenuItem(
                title: "Previous Page",
                action: #selector(previousPage(_:)),
                keyEquivalent: "["
            )
        )
        viewMenu.items.last?.target = self
        viewMenu.addItem(
            NSMenuItem(
                title: "Next Page",
                action: #selector(nextPage(_:)),
                keyEquivalent: "]"
            )
        )
        viewMenu.items.last?.target = self
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }
}

final class WorkspaceViewController: NSViewController {
    private var appState: AppState
    private var sourceDescription: String
    private let canvas = CanvasView()
    private var sidebarHosting: NSHostingView<SidebarView>?
    private var inspectorHosting: NSHostingView<InspectorView>?
    private var selectedFrameCancellable: AnyCancellable?
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
            self.view.window?.title = "layoutD - \(proj.metadata.title)"
        }
        
        self.selectedFrameCancellable = appState.$selectedFrameId.sink { [weak self] frameId in
            self?.canvas.selectedFrameId = frameId
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

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        canvas.project = appState.project
        canvas.document = appState.laidOutDocument
        
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
        
        canvas.onGapDragged = { [weak self] firstId, firstRect, secondId, secondRect in
            guard let self else { return }
            self.appState.updateGapFrames(firstId: firstId, firstRect: firstRect, secondId: secondId, secondRect: secondRect)
        }
        
        canvas.onPageSelected = { [weak self] pageNum in
            guard let self else { return }
            self.appState.currentPageNumber = pageNum
        }
        
        canvas.onCanvasClick = { [weak self] pageNum, localPoint in
            guard let self else { return }
            let tool = self.appState.activeTool
            let pageSize = self.appState.project.pageSetup.pageSize
            
            let normX = Double(localPoint.x / pageSize.width)
            let normY = Double(localPoint.y / pageSize.height)
            
            switch tool {
            case .selection, .directSelection:
                break
            case .page:
                break
            case .gap:
                break
            case .type:
                let normW = 150.0 / pageSize.width
                let normH = 60.0 / pageSize.height
                let frameRect = Rect(x: normX, y: normY, width: normW, height: normH)
                self.appState.addFrameToPage(pageNum: pageNum, kind: .text, frameRect: frameRect)
                
            case .rectangularFrame:
                let normW = 150.0 / pageSize.width
                let normH = 100.0 / pageSize.height
                let frameRect = Rect(x: normX, y: normY, width: normW, height: normH)
                self.appState.addFrameToPage(pageNum: pageNum, kind: .image, frameRect: frameRect)
                
            case .rectangle:
                let normW = 150.0 / pageSize.width
                let normH = 100.0 / pageSize.height
                let frameRect = Rect(x: normX, y: normY, width: normW, height: normH)
                self.appState.addFrameToPage(pageNum: pageNum, kind: .component, frameRect: frameRect)
                
            case .line:
                let normW = 120.0 / pageSize.width
                let normH = 4.0 / pageSize.height
                let frameRect = Rect(x: normX, y: normY, width: normW, height: normH)
                self.appState.addFrameToPage(pageNum: pageNum, kind: .component, frameRect: frameRect)
                
            case .scissors:
                if let document = self.appState.laidOutDocument,
                   let page = document.pages.first(where: { $0.number == pageNum }) {
                    if let found = page.frames.reversed().first(where: { frame in
                        let fRect = CGRect(x: frame.rect.x, y: frame.rect.y, width: frame.rect.width, height: frame.rect.height)
                        return fRect.contains(localPoint)
                    }) {
                        self.appState.deleteFrame(id: found.id)
                    }
                }
                
            case .zoom:
                self.zoomIn()
                
            case .hand:
                break
            default:
                break
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
        let sidebarHost = NSHostingView(rootView: sidebarView)
        self.sidebarHosting = sidebarHost

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
        let inspectorHost = NSHostingView(rootView: inspectorView)
        self.inspectorHosting = inspectorHost

        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebarHost
        sidebarScroll.hasVerticalScroller = true

        let toolbarView = ToolbarView(state: appState)
        let toolbarHost = NSHostingView(rootView: toolbarView)
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbarHost)

        let canvasScroll = NSScrollView()
        canvasScroll.documentView = canvas
        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true
        canvasScroll.translatesAutoresizingMaskIntoConstraints = false

        let inspectorScroll = NSScrollView()
        inspectorScroll.documentView = inspectorHost
        inspectorScroll.hasVerticalScroller = true

        splitView.addArrangedSubview(canvasScroll)
        splitView.addArrangedSubview(sidebarScroll)
        splitView.addArrangedSubview(inspectorScroll)

        NSLayoutConstraint.activate([
            toolbarHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarHost.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbarHost.widthAnchor.constraint(equalToConstant: 42),
            
            splitView.leadingAnchor.constraint(equalTo: toolbarHost.trailingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            sidebarScroll.widthAnchor.constraint(equalToConstant: 250),
            inspectorScroll.widthAnchor.constraint(equalToConstant: 310)
        ])
    }

    func openProject() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Project, Markdown Manuscript, or Chapter Package"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "layoutd"),
            UTType.json,
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "txt")
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

    func exportPDF() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let savePanel = NSSavePanel()
        savePanel.title = "Export PDF"
        savePanel.nameFieldStringValue = safeFileName(appState.project.metadata.title) + ".pdf"
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true

        let settingsState = PDFExportSettingsState()
        let settingsView = PDFExportSettingsView(state: settingsState)
        let hostingView = NSHostingView(rootView: settingsView)
        savePanel.accessoryView = hostingView

        savePanel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

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
        openPanel.accessoryView = NSHostingView(rootView: settingsView)

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

    func exportPreflightReport() {
        let document = appState.laidOutDocument ?? appState.engine.layout(project: appState.project)
        let report = appState.inspectorEngine.preflight(project: appState.project, document: document)
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

class PDFExportSettingsState: ObservableObject {
    @Published var pageRange: String = ""
    @Published var drawCropMarks: Bool = false
    @Published var drawGridGuides: Bool = false
    @Published var pdfxVersion: PDFXVersion = .none
}

struct PDFExportSettingsView: View {
    @ObservedObject var state: PDFExportSettingsState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PDF 导出选项")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("页码范围:")
                        .frame(width: 80, alignment: .leading)
                    TextField("例如: 3-5, 7", text: $state.pageRange)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                Text("留空导出全部页面，支持 '3-5', '1,3,5' 等")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 85)
            }
            
            HStack {
                Text("印刷标准:")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $state.pdfxVersion) {
                    Text("无 (标准 PDF)").tag(PDFXVersion.none)
                    Text("PDF/X-1a (CMYK 印刷)").tag(PDFXVersion.pdfx1a)
                    Text("PDF/X-3 (色彩管理)").tag(PDFXVersion.pdfx3)
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            
            Toggle("添加印刷裁切线及出血标记", isOn: $state.drawCropMarks)
                .toggleStyle(.checkbox)
            
            Toggle("添加校对基线网格及页边距指示线", isOn: $state.drawGridGuides)
                .toggleStyle(.checkbox)
        }
        .padding(.all, 16)
        .frame(width: 340)
    }
}

class PNGExportSettingsState: ObservableObject {
    @Published var pageRange: String = ""
    @Published var scale: Double = 2.0
}

struct PNGExportSettingsView: View {
    @ObservedObject var state: PNGExportSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PNG 预览导出选项")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("页码范围:")
                        .frame(width: 80, alignment: .leading)
                    TextField("例如: 1-3, 5", text: $state.pageRange)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                Text("留空导出全部页面")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 85)
            }

        }
        .padding(.all, 16)
        .frame(width: 320)
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
            .exportPackage
        ]
    }
    
    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .openProject,
            .saveProject,
            .space,
            .prevPage,
            .nextPage,
            .space,
            .zoomOut,
            .zoomActual,
            .zoomIn,
            .fitWidth,
            .flexibleSpace,
            .lockPage,
            .resetPage,
            .flexibleSpace,
            .exportPDF,
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

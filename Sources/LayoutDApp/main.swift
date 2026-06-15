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

let launchProject = ProjectLoader().loadFromCommandLine()

if launchProject.exportPDFURL != nil
    || launchProject.exportProjectURL != nil
    || launchProject.preflightReportURL != nil
    || launchProject.validateOnly {
    do {
        if let loadError = launchProject.loadError {
            fputs("Load failed: \(loadError)\n", stderr)
            exit(EXIT_FAILURE)
        }

        let document = LayoutEngine().layout(project: launchProject.project)
        let report = ProjectInspector().preflight(project: launchProject.project, document: document)

        if let exportProjectURL = launchProject.exportProjectURL {
            let data = try ProjectFile.encode(launchProject.project)
            try data.write(to: exportProjectURL, options: .atomic)
            print("Exported project: \(exportProjectURL.path)")
        }

        if let preflightReportURL = launchProject.preflightReportURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: preflightReportURL, options: .atomic)
            print("Exported preflight report: \(preflightReportURL.path)")
        }

        if let exportPDFURL = launchProject.exportPDFURL {
            try PDFExporter().export(document: document, project: launchProject.project, to: exportPDFURL)
            print("Exported PDF: \(exportPDFURL.path)")
        }

        if launchProject.validateOnly {
            if report.exportReady {
                print("Validation passed: \(launchProject.project.metadata.title)")
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

    @objc private func exportPreflightReport(_ sender: Any?) {
        workspaceController?.exportPreflightReport()
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
                title: "Open Project or Markdown...",
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
                title: "Export Preflight Report...",
                action: #selector(exportPreflightReport(_:)),
                keyEquivalent: "r"
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
            self?.appState.selectedFrameId = frameId
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
                self.canvas.highlightedFrameId = issue.frameId
            },
            onApplyPlan: { [weak self] plan in
                guard let self else { return }
                var currentProject = self.appState.project
                var plans = currentProject.safeAppliedLayoutPlans
                if case .page(let pageNum) = plan.target {
                    plans[pageNum] = plan
                    currentProject.safeAppliedLayoutPlans = plans
                    self.appState.project = currentProject
                }
            }
        )
        let inspectorHost = NSHostingView(rootView: inspectorView)
        self.inspectorHosting = inspectorHost

        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebarHost
        sidebarScroll.hasVerticalScroller = true

        let canvasScroll = NSScrollView()
        canvasScroll.documentView = canvas
        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true

        let inspectorScroll = NSScrollView()
        inspectorScroll.documentView = inspectorHost
        inspectorScroll.hasVerticalScroller = true

        splitView.addArrangedSubview(sidebarScroll)
        splitView.addArrangedSubview(canvasScroll)
        splitView.addArrangedSubview(inspectorScroll)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: 250),
            inspectorScroll.widthAnchor.constraint(equalToConstant: 310)
        ])
    }

    func openProject() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Open Project or Markdown Manuscript"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
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
                let data = try ProjectFile.encode(self.appState.project)
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
                    drawGridGuides: settingsState.drawGridGuides
                )
                self.showExportResult(message: "PDF exported", detail: url.path)
            } catch {
                self.showExportResult(message: "PDF export failed", detail: error.localizedDescription)
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
            
            Toggle("添加印刷裁切线及出血标记", isOn: $state.drawCropMarks)
                .toggleStyle(.checkbox)
            
            Toggle("添加校对基线网格及页边距指示线", isOn: $state.drawGridGuides)
                .toggleStyle(.checkbox)
        }
        .padding(.all, 16)
        .frame(width: 320)
    }
}

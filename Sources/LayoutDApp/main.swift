import AppKit
import Foundation
import LayoutDCheck
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
import LayoutDImport
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
    private var project: BookProject
    private var sourceDescription: String
    private let engine = LayoutEngine()
    private let inspectorEngine = ProjectInspector()
    private let advisor = RuleBasedLayoutAdvisor()
    private var laidOutDocument: LaidOutDocument?

    private let sidebar = NSTextView()
    private let inspector = NSTextView()
    private let canvas = CanvasView()
    private var currentPageNumber = 1

    init(project: BookProject, sourceDescription: String) {
        self.project = project
        self.sourceDescription = sourceDescription
        super.init(nibName: nil, bundle: nil)
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
        refreshDocument()
    }

    private func buildInterface() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        sidebar.isEditable = false
        sidebar.font = .systemFont(ofSize: 13)
        sidebar.textContainerInset = NSSize(width: 14, height: 14)

        inspector.isEditable = false
        inspector.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        inspector.textContainerInset = NSSize(width: 14, height: 14)

        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebar
        sidebarScroll.hasVerticalScroller = true

        let canvasScroll = NSScrollView()
        canvasScroll.documentView = canvas
        canvasScroll.hasVerticalScroller = true
        canvasScroll.hasHorizontalScroller = true

        let inspectorScroll = NSScrollView()
        inspectorScroll.documentView = inspector
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

    private func refreshDocument() {
        let document = engine.layout(project: project)
        laidOutDocument = document
        currentPageNumber = min(max(currentPageNumber, 1), max(document.pages.count, 1))
        canvas.project = project
        canvas.document = document
        view.window?.title = "layoutD - \(project.metadata.title)"

        let plans = advisor.proposePlans(for: project, target: .page(1))
        let report = inspectorEngine.preflight(project: project, document: document)
        sidebar.string = sidebarText(project: project, document: document)
        inspector.string = inspectorText(project: project, report: report, plans: plans)
    }

    private func sidebarText(project: BookProject, document: LaidOutDocument) -> String {
        var lines: [String] = [
            project.metadata.title,
            sourceDescription,
            project.pageSetup.pageSize.label,
            "Zoom \(Int(canvas.zoomScale * 100))%",
            "当前页 \(currentPageNumber)",
            "",
            "章节"
        ]
        lines += project.sections.map { "• \($0.title)" }
        lines += [
            "",
            "页面",
            "共 \(document.pages.count) 页"
        ]
        lines += document.pages.map { "第 \($0.number) 页 · \($0.frames.count) frames" }
        return lines.joined(separator: "\n")
    }

    private func inspectorText(project: BookProject, report: PreflightReport, plans: [LayoutPlan]) -> String {
        var lines: [String] = [
            "项目检查",
            report.isExportReady ? "状态：可导出" : "状态：需修复错误",
            ""
        ]
        lines += report.summaryLines
        lines += [
            "",
            "Issues: \(report.issues.count)"
        ]
        lines += report.issues.map { issue in
            if let pageNumber = issue.pageNumber {
                return "[\(issue.severity.rawValue)] p.\(pageNumber) \(issue.message)"
            }
            return "[\(issue.severity.rawValue)] \(issue.message)"
        }
        lines += [
            "",
            "AI LayoutPlan 候选"
        ]
        for plan in plans {
            lines.append("- \(plan.strategy.rawValue): \(plan.blocks.count) blocks")
            lines += plan.notes.map { "  \($0)" }
        }
        lines += [
            "",
            "素材库"
        ]
        lines += [
            "缺图注：\(report.assetSummary.missingCaptions)",
            "缺来源：\(report.assetSummary.missingCredits)",
            "低分辨率：\(report.assetSummary.lowResolution)",
            "未知尺寸：\(report.assetSummary.unknownSize)"
        ]
        lines += project.assets.map { "- \($0.fileName) · \($0.role.rawValue) · \($0.dpi.map { "\($0) DPI" } ?? "DPI unknown")" }
        return lines.joined(separator: "\n")
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
                self.project = try loader.loadProject(inputURL: url)
                self.sourceDescription = loader.sourceDescription(for: url)
                self.currentPageNumber = 1
                self.refreshDocument()
            } catch {
                self.showExportResult(message: "Open failed", detail: error.localizedDescription)
            }
        }
    }

    func saveProject() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save layoutD Project"
        savePanel.nameFieldStringValue = safeFileName(project.metadata.title) + ".layoutd"
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
                let data = try ProjectFile.encode(self.project)
                try data.write(to: url, options: .atomic)
                self.showExportResult(message: "Project saved", detail: url.path)
            } catch {
                self.showExportResult(message: "Save failed", detail: error.localizedDescription)
            }
        }
    }

    func zoomIn() {
        canvas.zoomIn()
        updateZoomLabel()
    }

    func zoomOut() {
        canvas.zoomOut()
        updateZoomLabel()
    }

    func actualSize() {
        canvas.resetZoom()
        updateZoomLabel()
    }

    func fitWidth() {
        canvas.fitWidth(availableWidth: canvas.enclosingScrollView?.contentView.bounds.width ?? canvas.bounds.width)
        updateZoomLabel()
        canvas.scrollToPage(number: currentPageNumber)
    }

    func previousPage() {
        guard let document = laidOutDocument else {
            return
        }
        currentPageNumber = max(1, currentPageNumber - 1)
        canvas.scrollToPage(number: currentPageNumber)
        sidebar.string = sidebarText(project: project, document: document)
    }

    func nextPage() {
        guard let document = laidOutDocument else {
            return
        }
        currentPageNumber = min(document.pages.count, currentPageNumber + 1)
        canvas.scrollToPage(number: currentPageNumber)
        sidebar.string = sidebarText(project: project, document: document)
    }

    private func updateZoomLabel() {
        guard let document = laidOutDocument else {
            return
        }
        sidebar.string = sidebarText(project: project, document: document)
    }

    func exportPDF() {
        let document = laidOutDocument ?? engine.layout(project: project)
        let savePanel = NSSavePanel()
        savePanel.title = "Export PDF"
        savePanel.nameFieldStringValue = safeFileName(project.metadata.title) + ".pdf"
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true

        savePanel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = savePanel.url, let self else {
                return
            }

            do {
                try PDFExporter().export(document: document, project: self.project, to: url)
                self.showExportResult(message: "PDF exported", detail: url.path)
            } catch {
                self.showExportResult(message: "PDF export failed", detail: error.localizedDescription)
            }
        }
    }

    func exportPreflightReport() {
        let document = laidOutDocument ?? engine.layout(project: project)
        let report = inspectorEngine.preflight(project: project, document: document)
        let savePanel = NSSavePanel()
        savePanel.title = "Export Preflight Report"
        savePanel.nameFieldStringValue = safeFileName(project.metadata.title) + "-preflight.json"
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

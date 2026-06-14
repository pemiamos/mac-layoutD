import AppKit
import Foundation
import LayoutDCore
import LayoutDDesignAI
import LayoutDEngine
import LayoutDExport
import LayoutDImport

let launchProject = ProjectLoader().loadFromCommandLine()

if let exportPDFURL = launchProject.exportPDFURL {
    do {
        let document = LayoutEngine().layout(project: launchProject.project)
        try PDFExporter().export(document: document, project: launchProject.project, to: exportPDFURL)
        print("Exported PDF: \(exportPDFURL.path)")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("PDF export failed: \(error.localizedDescription)\n", stderr)
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
    private let launchProject: LoadedProject

    init(launchProject: LoadedProject) {
        self.launchProject = launchProject
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

final class WorkspaceViewController: NSViewController {
    private let project: BookProject
    private let sourceDescription: String
    private let engine = LayoutEngine()
    private let advisor = RuleBasedLayoutAdvisor()
    private var laidOutDocument: LaidOutDocument?

    private let sidebar = NSTextView()
    private let inspector = NSTextView()
    private let canvas = CanvasView()

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
        canvas.project = project
        canvas.document = document

        let plans = advisor.proposePlans(for: project, target: .page(1))
        sidebar.string = sidebarText(project: project, document: document)
        inspector.string = inspectorText(project: project, document: document, plans: plans)
    }

    private func sidebarText(project: BookProject, document: LaidOutDocument) -> String {
        var lines: [String] = [
            project.metadata.title,
            sourceDescription,
            project.pageSetup.pageSize.label,
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

    private func inspectorText(project: BookProject, document: LaidOutDocument, plans: [LayoutPlan]) -> String {
        var lines: [String] = [
            "项目检查",
            "Issues: \(document.issues.count)"
        ]
        lines += document.issues.map { "[\($0.severity.rawValue)] \($0.message)" }
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
        lines += project.assets.map { "- \($0.fileName) · \($0.role.rawValue) · \($0.dpi.map { "\($0) DPI" } ?? "DPI unknown")" }
        return lines.joined(separator: "\n")
    }
}

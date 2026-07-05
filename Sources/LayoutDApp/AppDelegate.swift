import AppKit
import Foundation
import LayoutDCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    weak var workspaceController: WorkspaceViewController?
    private let launchProject: LoadedProject

    init(launchProject: LoadedProject) {
        self.launchProject = launchProject
        super.init()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // InDesign 式深色工作区（页面纸张仍为白色，见 CanvasView 的显式绘制）。
        NSApp.appearance = NSAppearance(named: .darkAqua)

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
        // Open at a comfortable default size (not maximized), centered on screen.
        // The whole app stays visible without filling the display; the user can
        // zoom the window manually if they want more canvas. Cap to the visible
        // frame so it always fits on smaller screens.
        window.minSize = NSSize(width: 1024, height: 700)
        window.contentViewController = controller
        window.acceptsMouseMovedEvents = true
        let preferredSize = NSSize(width: 1280, height: 860)
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setContentSize(NSSize(
                width: min(preferredSize.width, visibleFrame.width),
                height: min(preferredSize.height, visibleFrame.height)
            ))
        } else {
            window.setContentSize(preferredSize)
        }
        window.center()
        
        let toolbar = NSToolbar(identifier: "LayoutDMainToolbar")
        toolbar.delegate = controller
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.workspaceController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

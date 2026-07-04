import AppKit
import SwiftUI
import LayoutDCore

/// Hosts the multi-space (RGB/HSB/CMYK) color picker in a **floating utility
/// panel** — a separate window, exactly like the system `NSColorPanel`.
///
/// Why not a SwiftUI `.popover`? Applying a color rewrites the document, which
/// triggers a full-book relayout (~1s on a 161-page book) and re-renders the
/// inspector subtree the popover was anchored to — tearing the popover down mid-
/// edit (the "一点滑块就跳掉、连选择都没了" bug). A standalone window is immune to
/// the main window re-rendering, so sliders, mode switches and 「加入色板」 all
/// keep the picker open. Live canvas preview still works because each apply
/// re-renders the *main* window, not this panel.
@MainActor
final class MultiSpaceColorPanelController {
    static let shared = MultiSpaceColorPanelController()

    private var panel: NSPanel?

    /// Toggles the panel: re-clicking the same trigger (or reopening) closes it;
    /// otherwise (re)opens it near the mouse, wired to the given target.
    func toggle(
        title: String,
        initial: PrintColor,
        state: AppState,
        apply: @escaping (PrintColor) -> Void
    ) {
        if let panel, panel.isVisible {
            close()
            return
        }
        show(title: title, initial: initial, state: state, apply: apply)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func show(
        title: String,
        initial: PrintColor,
        state: AppState,
        apply: @escaping (PrintColor) -> Void
    ) {
        let host = NSHostingController(
            rootView: MultiSpaceColorPanelHost(
                title: title,
                initial: initial,
                state: state,
                apply: apply
            )
        )
        host.sizingOptions = [.preferredContentSize]

        let panel = self.panel ?? makePanel()
        panel.title = title
        panel.contentViewController = host
        panel.layoutIfNeeded()

        positionNearMouse(panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 420),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Opens the panel just below-left of the pointer so it appears next to the
    /// slider trigger the user just clicked, clamped to the active screen.
    private func positionNearMouse(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width - 12, y: mouse.y - size.height + 20)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }
}

/// Thin wrapper so the picker's swatch grid stays in sync with the project: it
/// observes `AppState`, so adding/removing a swatch live-updates the panel while
/// the picker's own channel/mode `@State` persists (view identity is stable).
private struct MultiSpaceColorPanelHost: View {
    let title: String
    let initial: PrintColor
    @ObservedObject var state: AppState
    let apply: (PrintColor) -> Void

    var body: some View {
        ColorPickerPanel(
            title: title,
            color: initial,
            swatches: state.customSwatches,
            onChange: apply,
            onAddSwatch: { state.addCustomSwatch($0) },
            onRemoveSwatch: { state.removeCustomSwatch(id: $0) }
        )
    }
}

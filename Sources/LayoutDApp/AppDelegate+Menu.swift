import AppKit
import Foundation

extension AppDelegate {
    @objc private func exportPDF(_ sender: Any?) {
        workspaceController?.exportPDF()
    }

    @objc private func exportPNGPreviews(_ sender: Any?) {
        workspaceController?.exportPNGPreviews()
    }

    @objc private func exportIDML(_ sender: Any?) {
        workspaceController?.exportIDML()
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

    @objc private func undoAction(_ sender: Any?) {
        workspaceController?.undo()
    }

    @objc private func redoAction(_ sender: Any?) {
        workspaceController?.redo()
    }

    func buildMainMenu() {
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
                title: "Export IDML...",
                action: #selector(exportIDML(_:)),
                keyEquivalent: "d"
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

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            NSMenuItem(
                title: "Undo",
                action: #selector(undoAction(_:)),
                keyEquivalent: "z"
            )
        )
        editMenu.items.last?.target = self
        editMenu.addItem(
            NSMenuItem(
                title: "Redo",
                action: #selector(redoAction(_:)),
                keyEquivalent: "Z"
            )
        )
        editMenu.items.last?.target = self
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

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

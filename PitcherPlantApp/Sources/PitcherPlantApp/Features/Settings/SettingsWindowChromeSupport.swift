import AppKit
import SwiftUI

struct SettingsWindowChromeSupport: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> SettingsWindowChromeView {
        SettingsWindowChromeView()
    }

    func updateNSView(_ nsView: SettingsWindowChromeView, context: Context) {
        nsView.title = title
        nsView.configureWindow()
        nsView.configureWindowOnNextRunLoop()
    }
}

@MainActor
final class SettingsWindowChromeView: NSView, NSToolbarDelegate {
    var title = ""
    private let toolbarIdentifier = NSToolbar.Identifier("PitcherPlantSettingsToolbar")

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
        configureWindowOnNextRunLoop()
    }

    func configureWindow() {
        guard let window else { return }

        window.title = title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.insert(.unifiedTitleAndToolbar)

        if window.toolbar?.identifier != toolbarIdentifier {
            let toolbar = NSToolbar(identifier: toolbarIdentifier)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.sizeMode = .regular
            toolbar.showsBaselineSeparator = true
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            window.toolbar = toolbar
        }
    }

    func configureWindowOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        []
    }
}

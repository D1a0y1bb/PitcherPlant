import AppKit
import SwiftUI

struct ToolbarCustomizationDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarCustomizationView {
        ToolbarCustomizationView()
    }

    func updateNSView(_ nsView: ToolbarCustomizationView, context: Context) {
        nsView.configureToolbar()
        nsView.configureToolbarOnNextRunLoop()
    }
}

@MainActor
final class ToolbarCustomizationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureToolbar()
        configureToolbarOnNextRunLoop()
    }

    func configureToolbar() {
        guard let toolbar = window?.toolbar else { return }

        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
    }

    func configureToolbarOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.configureToolbar()
        }
    }
}

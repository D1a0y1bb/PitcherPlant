import AppKit
import SwiftUI

struct ReportToolbarSearchModifier: ViewModifier {
    let isPresented: Bool
    @Binding var text: String
    let prompt: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPresented {
            content.searchable(text: $text, placement: .toolbar, prompt: prompt)
        } else {
            content
        }
    }
}

extension View {
    func reportToolbarSearch(isPresented: Bool, text: Binding<String>, prompt: String) -> some View {
        modifier(ReportToolbarSearchModifier(isPresented: isPresented, text: text, prompt: prompt))
    }
}

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
        guard let toolbar = window?.toolbar else {
            return
        }

        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
    }

    func configureToolbarOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.configureToolbar()
        }
    }
}

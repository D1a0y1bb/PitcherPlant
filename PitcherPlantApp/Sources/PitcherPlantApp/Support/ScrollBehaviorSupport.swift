import AppKit
import SwiftUI

struct AppScrollIndicatorHidingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                AppScrollIndicatorHidingHost()
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }
}

private struct AppScrollIndicatorHidingHost: NSViewRepresentable {
    func makeNSView(context: Context) -> AppScrollIndicatorHidingView {
        let view = AppScrollIndicatorHidingView()
        view.hideScrollIndicators()
        return view
    }

    func updateNSView(_ nsView: AppScrollIndicatorHidingView, context: Context) {
        nsView.hideScrollIndicators()
    }
}

private final class AppScrollIndicatorHidingView: NSView {
    private var hasScheduledDeferredPass = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideScrollIndicators()
        scheduleDeferredHidePass()
    }

    override func layout() {
        super.layout()
        hideScrollIndicators()
    }

    func hideScrollIndicators() {
        guard let rootView = window?.contentView else {
            return
        }
        Self.hideScrollIndicators(in: rootView)
    }

    private func scheduleDeferredHidePass() {
        guard !hasScheduledDeferredPass else {
            return
        }
        hasScheduledDeferredPass = true

        Task { @MainActor [weak self] in
            let delays: [UInt64] = [60_000_000, 180_000_000, 520_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                self?.hideScrollIndicators()
            }
        }
    }

    private static func hideScrollIndicators(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.verticalScroller?.isHidden = true
            scrollView.verticalScroller?.alphaValue = 0
            scrollView.horizontalScroller?.isHidden = true
            scrollView.horizontalScroller?.alphaValue = 0
        }

        for subview in view.subviews {
            hideScrollIndicators(in: subview)
        }
    }
}

extension View {
    func appHidesScrollIndicators() -> some View {
        modifier(AppScrollIndicatorHidingModifier())
    }
}

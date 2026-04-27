import SwiftUI
import AppKit

@MainActor
private enum PitcherPlantRuntime {
    static let appState = AppState()
}

@main
struct PitcherPlantDesktopApp: App {
    private let appState = PitcherPlantRuntime.appState
    @Environment(\.openWindow) private var openWindow
    private var appearanceSyncKey: String {
        "\(appState.appSettings.appearance.rawValue)-\(appState.effectiveLocale?.identifier ?? "system")"
    }

    var body: some Scene {
        WindowGroup("PitcherPlant", id: AppWindow.main.rawValue) {
            MainWindowView()
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }
        .defaultSize(width: 1220, height: 780)
        .defaultLaunchBehavior(.presented)
        .commands {
            PitcherPlantCommands(
                appState: appState,
                showMainWindow: {
                    openWindow(id: AppWindow.main.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        }

        Settings {
            SettingsRootView()
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }

        MenuBarExtra {
            PitcherPlantMenuBarView(appState: appState)
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
        } label: {
            if appState.appSettings.showMenuBarExtra {
                Image(systemName: "leaf")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AppAppearanceSyncModifier: ViewModifier {
    let appearance: AppAppearance
    let syncKey: String

    func body(content: Content) -> some View {
        content
            .background(WindowAppearanceAccessor(appearance: appearance))
            .onAppear {
                applyAppearance()
            }
            .onChange(of: appearance) { _, _ in
                applyAppearance()
            }
            .onChange(of: syncKey) { _, _ in
                applyAppearance()
            }
    }

    @MainActor
    private func applyAppearance() {
        let nsAppearance = appearance.nsAppearance

        NSApp.appearance = nsAppearance
        NSApp.windows.forEach { window in
            window.applyPitcherPlantAppearance(nsAppearance)
        }
        applyDeferredAppearance(nsAppearance)
    }

    private func applyDeferredAppearance(_ appearance: NSAppearance?) {
        for delay in [0.05, 0.2, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.appearance = appearance
                NSApp.windows.forEach { window in
                    window.applyPitcherPlantAppearance(appearance)
                }
            }
        }
    }
}

private struct WindowAppearanceAccessor: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyAppearance(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyAppearance(from: nsView)
    }

    private func applyAppearance(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.applyPitcherPlantAppearance(appearance.nsAppearance)
            for delay in [0.05, 0.2, 0.45] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    window.applyPitcherPlantAppearance(appearance.nsAppearance)
                }
            }
        }
    }
}

private extension AppAppearance {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

private extension NSWindow {
    func applyPitcherPlantAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        contentView?.appearance = appearance
        contentView?.superview?.appearance = appearance
        standardWindowButton(.closeButton)?.superview?.appearance = appearance
        if let rootView = contentView?.superview {
            rootView.applyPitcherPlantAppearanceToSubviews(appearance)
        }
    }
}

private extension NSView {
    func applyPitcherPlantAppearanceToSubviews(_ appearance: NSAppearance?) {
        self.appearance = appearance
        subviews.forEach { subview in
            subview.applyPitcherPlantAppearanceToSubviews(appearance)
        }
    }
}

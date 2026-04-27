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
                .id(appearanceSyncKey)
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }
        .defaultSize(width: 1220, height: 780)
        .windowResizability(.contentMinSize)
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
                .id(appearanceSyncKey)
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
                .id(appearanceSyncKey)
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
        } label: {
            if appState.appSettings.showMenuBarExtra {
                MenuBarAppIcon()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarAppIcon: View {
    var body: some View {
        Image(systemName: "doc.text.magnifyingglass")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 18, height: 18)
            .accessibilityLabel("PitcherPlant")
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
        titlebarAppearsTransparent = false
        backgroundColor = .windowBackgroundColor
        self.appearance = appearance
        standardWindowButton(.closeButton)?.superview?.appearance = appearance
        contentView?.resetExplicitPitcherPlantAppearance()
        invalidateShadow()
    }
}

private extension NSView {
    func resetExplicitPitcherPlantAppearance() {
        appearance = nil
        needsDisplay = true
        needsLayout = true
        layer?.setNeedsDisplay()
        subviews.forEach { subview in
            subview.resetExplicitPitcherPlantAppearance()
        }
    }
}

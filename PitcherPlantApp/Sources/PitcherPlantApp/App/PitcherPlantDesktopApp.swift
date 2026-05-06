import SwiftUI
import AppKit

@MainActor
private enum PitcherPlantRuntime {
    static let languageBootstrap: Void = AppLanguageRuntime.applySavedLanguagePreference()
    static let appState: AppState = {
        _ = languageBootstrap
        return AppState()
    }()
}

@main
struct PitcherPlantDesktopApp: App {
    @NSApplicationDelegateAdaptor(PitcherPlantAppDelegate.self) private var appDelegate
    private let appState = PitcherPlantRuntime.appState
    @Environment(\.openWindow) private var openWindow
    private var appearanceSyncKey: String {
        "\(appState.appSettings.appearance.rawValue)-\(appState.effectiveLocale?.identifier ?? "system")"
    }

    var body: some Scene {
        WindowGroup("PitcherPlant", id: AppWindow.main.rawValue) {
            MainWindowView()
                .stableMainWindowFrame()
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
                .modifier(AppAppearanceSyncModifier(appearance: appState.appSettings.appearance, syncKey: appearanceSyncKey))
                .modifier(SystemMenuLocalizationModifier(appState: appState, syncKey: appearanceSyncKey))
                .task {
                    await appState.bootstrapIfNeeded()
                    appState.startUpdateMonitoring()
                }
        }
        .defaultSize(width: AppLayout.mainWindowDefaultWidth, height: AppLayout.mainWindowDefaultHeight)
        .defaultLaunchBehavior(.presented)
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(appState.t("about.menuTitle")) {
                    showAboutPanel()
                }
            }

            CommandGroup(after: .appInfo) {
                Button(appState.t("about.checkUpdates")) {
                    appState.checkForUpdatesManually()
                }
            }

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
                .modifier(SystemMenuLocalizationModifier(appState: appState, syncKey: appearanceSyncKey))
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }

        MenuBarExtra {
            PitcherPlantMenuBarView(appState: appState)
                .environment(appState)
                .environment(\.locale, appState.effectiveLocale ?? .current)
                .preferredColorScheme(appState.effectiveColorScheme)
        } label: {
            if appState.appSettings.showMenuBarExtra {
                Image(systemName: "leaf")
                    .symbolRenderingMode(.monochrome)
                    .accessibilityLabel("PitcherPlant")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func showAboutPanel() {
        let version = AppVersionInfo.current
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: version.name,
            .applicationVersion: version.displayVersion,
            .credits: NSAttributedString(string: appState.t("about.credits"))
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AppAppearanceSyncModifier: ViewModifier {
    let appearance: AppAppearance
    let syncKey: String

    func body(content: Content) -> some View {
        content
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
        NSApp.appearance = appearance.nsAppearance
    }
}

private struct SystemMenuLocalizationModifier: ViewModifier {
    let appState: AppState
    let syncKey: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                SystemMenuLocalizer.schedule(appState: appState)
            }
            .onChange(of: syncKey) { _, _ in
                SystemMenuLocalizer.schedule(appState: appState)
            }
    }
}

private final class PitcherPlantAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppLanguageRuntime.applySavedLanguagePreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SystemMenuLocalizer.schedule(appState: PitcherPlantRuntime.appState)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SystemMenuLocalizer.schedule(appState: PitcherPlantRuntime.appState)
    }
}

enum SystemMenuLocalizer {
    @MainActor
    static func schedule(appState: AppState) {
        apply(appState: appState)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            apply(appState: appState)
            try? await Task.sleep(nanoseconds: 280_000_000)
            apply(appState: appState)
            try? await Task.sleep(nanoseconds: 700_000_000)
            apply(appState: appState)
        }
    }

    @MainActor
    private static func apply(appState: AppState) {
        guard let items = NSApp.mainMenu?.items, items.count >= 4 else {
            return
        }

        setTitle(appState.t("systemMenu.file"), at: 1, in: items)
        setTitle(appState.t("systemMenu.edit"), at: 2, in: items)
        setTitle(appState.t("systemMenu.view"), at: 3, in: items)
        setTitle(appState.t("app.taskMenu"), at: 4, in: items)
        setTitle(appState.t("app.viewMenu"), at: 5, in: items)
        setTitle(appState.t("app.reviewMenu"), at: 6, in: items)
        setTitle(appState.t("app.reportMenu"), at: 7, in: items)
        if items.count >= 9 {
            setTitle(appState.t("systemMenu.window"), at: items.count - 2, in: items)
            setTitle(appState.t("systemMenu.help"), at: items.count - 1, in: items)
        }
    }

    @MainActor
    private static func setTitle(_ title: String, at index: Int, in items: [NSMenuItem]) {
        guard items.indices.contains(index) else {
            return
        }
        items[index].title = title
        items[index].submenu?.title = title
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

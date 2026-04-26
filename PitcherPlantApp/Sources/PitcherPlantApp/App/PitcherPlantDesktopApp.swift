import SwiftUI

@MainActor
private enum PitcherPlantRuntime {
    static let appState = AppState()
}

@main
struct PitcherPlantDesktopApp: App {
    private let appState = PitcherPlantRuntime.appState
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("PitcherPlant", id: AppWindow.main.rawValue) {
            MainWindowView()
                .environment(appState)
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
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }
    }
}

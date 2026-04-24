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
        WindowGroup("PitcherPlant") {
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
                openMainWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                },
                openReportsWindow: {
                    openWindow(id: AppWindow.reports.rawValue)
                }
            )
        }

        Window("报告中心", id: AppWindow.reports.rawValue) {
            ReportsWindowView()
                .environment(appState)
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }
        .defaultSize(width: 1320, height: 840)

        Settings {
            SettingsRootView()
                .environment(appState)
                .task {
                    await appState.bootstrapIfNeeded()
                }
        }
    }
}

import SwiftUI

@main
struct PitcherPlantDesktopApp: App {
    @State private var appState = AppState()
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
        .commands {
            PitcherPlantCommands(
                appState: appState,
                openMainWindow: {
                    openWindow(id: AppWindow.main.rawValue)
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

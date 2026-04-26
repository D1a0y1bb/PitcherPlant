import SwiftUI

struct PitcherPlantCommands: Commands {
    let appState: AppState
    let showMainWindow: () -> Void

    var body: some Commands {
        CommandMenu("任务") {
            Button("显示工作台") {
                appState.showWorkspace()
                showMainWindow()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("开始审计") {
                Task {
                    await appState.startAudit()
                    showMainWindow()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(appState.isRunningAudit)

            Button("重新加载数据") {
                Task { await appState.reload() }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandMenu("报告") {
            Button("打开报告中心") {
                appState.showReportsCenter()
                showMainWindow()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("打开最近报告") {
                appState.showReportsCenter(selectLatest: true)
                showMainWindow()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(appState.latestReport == nil)

            Button("在 Finder 显示最近报告") {
                appState.openLatestReportInFinder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(appState.latestReport == nil)

            Divider()

            Button("导出当前报告 PDF") {
                appState.exportSelectedReportAsPDF()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(appState.selectedReport == nil)

            Button("导出当前报告 HTML") {
                appState.exportSelectedReportAsHTML()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.selectedReport == nil)

            Button("删除当前报告记录") {
                Task { await appState.removeSelectedReport() }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(appState.selectedReport == nil)
        }
    }
}

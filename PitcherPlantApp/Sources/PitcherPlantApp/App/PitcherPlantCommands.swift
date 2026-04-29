import SwiftUI

struct PitcherPlantCommands: Commands {
    let appState: AppState
    let showMainWindow: () -> Void

    var body: some Commands {
        CommandMenu(appState.t("app.taskMenu")) {
            Button(appState.t("command.showWorkspace")) {
                appState.showWorkspace()
                showMainWindow()
            }

            Button(appState.isRunningAudit ? appState.t("command.cancelAudit") : appState.t("command.startAudit")) {
                if appState.isRunningAudit {
                    appState.cancelAudit()
                } else {
                    appState.beginAudit()
                    showMainWindow()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button(appState.t("command.reloadData")) {
                Task { await appState.reload() }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandMenu("视图") {
            Button("显示或隐藏检查器") {
                appState.requestInspectorToggle()
                showMainWindow()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(!appState.selectedMainSidebar.allowsInspector)
        }

        CommandMenu("复核") {
            Button("确认违规") {
                Task { await appState.quickReviewSelectedEvidence(.confirmed) }
            }
            .keyboardShortcut("a", modifiers: [])
            .disabled(appState.selectedReportRow == nil)

            Button("标记误报") {
                Task { await appState.quickReviewSelectedEvidence(.falsePositive) }
            }
            .keyboardShortcut("f", modifiers: [])
            .disabled(appState.selectedReportRow == nil)

            Button("忽略证据") {
                Task { await appState.quickReviewSelectedEvidence(.ignored) }
            }
            .keyboardShortcut("i", modifiers: [])
            .disabled(appState.selectedReportRow == nil)

            Button("加入白名单") {
                Task { await appState.quickReviewSelectedEvidence(.whitelisted) }
            }
            .keyboardShortcut("w", modifiers: [])
            .disabled(appState.selectedReportRow == nil)
        }

        CommandMenu(appState.t("app.reportMenu")) {
            Button(appState.t("command.openReports")) {
                appState.showReportsCenter()
                showMainWindow()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(appState.t("command.openLatestReport")) {
                appState.showReportsCenter(selectLatest: true)
                showMainWindow()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(appState.latestReport == nil)

            Button(appState.t("command.showLatestInFinder")) {
                appState.openLatestReportInFinder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(appState.latestReport == nil)

            Divider()

            Button(appState.t("command.exportPDF")) {
                appState.exportSelectedReportAsPDF()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(appState.selectedReport == nil)

            Button(appState.t("command.exportHTML")) {
                appState.exportSelectedReportAsHTML()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.selectedReport == nil)

            Button(appState.t("command.deleteReport")) {
                Task { await appState.removeSelectedReport() }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(appState.selectedReport == nil)
        }
    }
}

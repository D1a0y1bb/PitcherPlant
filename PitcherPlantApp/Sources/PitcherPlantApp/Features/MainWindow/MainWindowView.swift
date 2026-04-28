import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = true
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var settingsSearchText = ""

    var body: some View {
        @Bindable var state = appState

        Group {
            if isInspectorColumnVisible {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar(selection: $state.selectedMainSidebar)
                } content: {
                    contentColumn
                } detail: {
                    inspectorColumn
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar(selection: $state.selectedMainSidebar)
                } detail: {
                    contentColumn
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            inspectorVisible = appState.appSettings.showInspectorByDefault
            updateColumnVisibility()
        }
        .onChange(of: inspectorVisible) { _, visible in
            if appState.selectedMainSidebar.allowsInspector {
                appState.updateSettings { $0.showInspectorByDefault = visible }
            }
            updateColumnVisibility()
        }
        .onChange(of: appState.selectedMainSidebar) { _, _ in
            if appState.selectedMainSidebar != .settings {
                settingsSearchText = ""
            }
            updateColumnVisibility()
        }
        .onChange(of: appState.appSettings.showInspectorByDefault) { _, visible in
            if !appState.selectedMainSidebar.allowsInspector {
                inspectorVisible = visible
            }
            updateColumnVisibility()
        }
        .toolbar {
            mainToolbarItems
        }
        .alert(item: noticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK")) {
                    appState.dismissNotice()
                }
            )
        }
        .environment(\.locale, appState.effectiveLocale ?? .current)
        .preferredColorScheme(appState.effectiveColorScheme)
    }

    private var noticeBinding: Binding<AppNotice?> {
        Binding {
            appState.notice
        } set: { notice in
            if notice == nil {
                appState.dismissNotice()
            }
        }
    }

    private var isInspectorColumnVisible: Bool {
        appState.selectedMainSidebar.allowsInspector && inspectorVisible
    }

    private func updateColumnVisibility() {
        columnVisibility = isInspectorColumnVisible ? .all : .doubleColumn
    }

    private func sidebar(selection: Binding<MainSidebarItem>) -> some View {
        MainSidebarView(selection: selection)
            .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 320)
    }

    private var contentColumn: some View {
        mainContent
            .navigationSplitViewColumnWidth(min: 560, ideal: 820, max: .infinity)
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if appState.selectedMainSidebar.usesReportInspector {
            ReportEvidenceInspectorHost()
        } else {
            JobInspectorView()
        }
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                inspectorVisible.toggle()
            } label: {
                Label(
                    inspectorVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"),
                    systemImage: inspectorVisible ? "sidebar.right" : "sidebar.trailing"
                )
            }
            .disabled(!appState.selectedMainSidebar.allowsInspector)
            .help(inspectorVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"))

            Button {
                Task { await appState.reload() }
            } label: {
                Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help(appState.t("command.reloadData"))

            Button {
                appState.toggleAudit()
            } label: {
                Label(
                    appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"),
                    systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                )
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help(appState.t("command.startAudit"))

            Button {
                appState.selectedMainSidebar = .settings
            } label: {
                Label(appState.t("toolbar.settings"), systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help(appState.t("toolbar.settings"))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.selectedMainSidebar {
        case .workspace:
            WorkspaceDashboardView()
        case .newAudit:
            NewAuditView()
        case .history:
            JobHistoryView()
        case .reports:
            ReportsInlineView()
        case .textEvidence, .codeEvidence, .imageEvidence, .metadataEvidence, .dedupEvidence, .crossBatchEvidence:
            EvidenceFocusedReportsView(kind: appState.selectedMainSidebar.reportSectionKind)
        case .fingerprints:
            FingerprintLibraryView()
        case .whitelist:
            WhitelistLibraryView()
        case .settings:
            SettingsRootView(searchText: $settingsSearchText)
        }
    }
}

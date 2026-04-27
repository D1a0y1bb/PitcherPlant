import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = true
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var settingsSearchText = ""

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            MainSidebarView(selection: $state.selectedMainSidebar)
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 320)
        } content: {
            mainContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if appState.selectedMainSidebar != .settings {
                        MainStatusBar()
                    }
                }
                .modifier(SettingsSearchToolbarModifier(
                    isActive: appState.selectedMainSidebar == .settings,
                    searchText: $settingsSearchText,
                    prompt: appState.t("settings.searchPrompt")
                ))
                .navigationSplitViewColumnWidth(min: 560, ideal: 760, max: .infinity)
        } detail: {
            Group {
                if !isInspectorColumnVisible {
                    EmptyView()
                } else if appState.selectedMainSidebar.usesReportInspector {
                    ReportEvidenceInspectorHost()
                } else {
                    JobInspectorView()
                }
            }
            .navigationSplitViewColumnWidth(
                min: isInspectorColumnVisible ? 340 : 0,
                ideal: isInspectorColumnVisible ? 400 : 0,
                max: isInspectorColumnVisible ? 520 : 0
            )
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
            if appState.selectedMainSidebar == .settings {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await appState.reload() }
                    } label: {
                        Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help(appState.t("command.reloadData"))

                    Button {
                        appState.selectedMainSidebar = .settings
                    } label: {
                        Label(appState.t("toolbar.settings"), systemImage: "gear")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .help(appState.t("toolbar.settings"))
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    if appState.selectedMainSidebar.allowsInspector {
                        Button {
                            inspectorVisible.toggle()
                        } label: {
                            Label(
                                inspectorVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"),
                                systemImage: inspectorVisible ? "sidebar.right" : "sidebar.trailing"
                            )
                        }
                        .help(inspectorVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"))
                    }

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
        }
        .environment(\.locale, appState.effectiveLocale ?? .current)
        .preferredColorScheme(appState.effectiveColorScheme)
    }

    private var isInspectorColumnVisible: Bool {
        appState.selectedMainSidebar.allowsInspector && inspectorVisible
    }

    private func updateColumnVisibility() {
        columnVisibility = .all
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

import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = true
    @State private var settingsSearchText = ""

    var body: some View {
        @Bindable var state = appState

        GeometryReader { geometry in
            HStack(spacing: 0) {
                NavigationSplitView {
                    sidebar(selection: $state.selectedMainSidebar)
                } detail: {
                    contentColumn
                }
                .navigationSplitViewStyle(.balanced)
                .layoutPriority(1)

                if isInspectorColumnVisible {
                    inspectorColumn(width: inspectorWidth(for: geometry.size.width))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy(duration: 0.18), value: isInspectorColumnVisible)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            inspectorVisible = appState.appSettings.showInspectorByDefault
        }
        .onChange(of: inspectorVisible) { _, visible in
            if appState.selectedMainSidebar.allowsInspector {
                appState.updateSettings { $0.showInspectorByDefault = visible }
            }
        }
        .onChange(of: appState.selectedMainSidebar) { _, _ in
            if appState.selectedMainSidebar != .settings {
                settingsSearchText = ""
            }
        }
        .onChange(of: appState.appSettings.showInspectorByDefault) { _, visible in
            if !appState.selectedMainSidebar.allowsInspector {
                inspectorVisible = visible
            }
        }
        .onChange(of: appState.inspectorRequestID) { _, _ in
            if appState.selectedMainSidebar.allowsInspector {
                inspectorVisible = true
            }
        }
        .toolbar {
            mainToolbarItems
        }
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

    private func sidebar(selection: Binding<MainSidebarItem>) -> some View {
        MainSidebarView(selection: selection)
            .navigationSplitViewColumnWidth(
                min: AppLayout.sidebarMinWidth,
                ideal: AppLayout.sidebarIdealWidth,
                max: AppLayout.sidebarMaxWidth
            )
    }

    private var contentColumn: some View {
        mainContent
            .navigationSplitViewColumnWidth(
                min: AppLayout.contentMinWidth,
                ideal: AppLayout.contentIdealWidth,
                max: .infinity
            )
    }

    @ViewBuilder
    private func inspectorColumn(width: CGFloat) -> some View {
        Group {
            if appState.selectedMainSidebar.usesReportInspector {
                ReportEvidenceInspectorHost()
            } else {
                JobInspectorView()
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Divider()
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: -8, y: 0)
    }

    private func inspectorWidth(for windowWidth: CGFloat) -> CGFloat {
        let proportionalWidth = windowWidth * 0.28
        return min(AppLayout.inspectorMaxWidth, max(AppLayout.inspectorMinWidth, proportionalWidth))
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                inspectorVisible.toggle()
            } label: {
                Label(
                    isInspectorColumnVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"),
                    systemImage: isInspectorColumnVisible ? "sidebar.right" : "sidebar.trailing"
                )
            }
            .disabled(!appState.selectedMainSidebar.allowsInspector)
            .help(isInspectorColumnVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"))

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
        case .allEvidence, .favoriteEvidence, .watchedEvidence:
            EvidenceCollectionView(scope: appState.selectedMainSidebar.evidenceCollectionScope ?? .all)
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

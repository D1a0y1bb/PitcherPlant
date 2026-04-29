import AppKit
import SwiftUI

private let inspectorColumnAnimation = Animation.smooth(duration: 0.32, extraBounce: 0)

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var autoCollapsedSidebar = false
    @State private var applyingSidebarPolicy = false
    @State private var windowWidth: CGFloat = 0
    @State private var settingsSearchText = ""
    private let layoutPolicy = MainWindowLayoutPolicy()

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(selection: $state.selectedMainSidebar)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(WindowWidthObserver { width in
            updateWindowWidth(width)
        })
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            inspectorVisible = appState.appSettings.showInspectorByDefault
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: inspectorVisible) { _, visible in
            if appState.selectedMainSidebar.allowsInspector {
                appState.updateSettings { $0.showInspectorByDefault = visible }
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: columnVisibility) { _, visibility in
            handleSidebarVisibilityChange(visibility)
        }
        .onChange(of: appState.selectedMainSidebar) { _, _ in
            if appState.selectedMainSidebar != .settings {
                settingsSearchText = ""
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: appState.appSettings.showInspectorByDefault) { _, visible in
            if !appState.selectedMainSidebar.allowsInspector {
                inspectorVisible = visible
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: appState.inspectorRequestID) { _, _ in
            if appState.selectedMainSidebar.allowsInspector {
                withAnimation(inspectorColumnAnimation) {
                    inspectorVisible = true
                }
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: appState.inspectorToggleRequestID) { _, _ in
            guard appState.selectedMainSidebar.allowsInspector else {
                return
            }
            withAnimation(inspectorColumnAnimation) {
                inspectorVisible.toggle()
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .toolbar {
            mainToolbarItems
        }
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

    private var sidebarCollapsed: Bool {
        columnVisibility == .detailOnly
    }

    private func sidebar(selection: Binding<MainSidebarItem>) -> some View {
        MainSidebarView(selection: selection)
            .navigationSplitViewColumnWidth(
                min: AppLayout.sidebarMinWidth,
                ideal: AppLayout.sidebarIdealWidth,
                max: AppLayout.sidebarMaxWidth
            )
    }

    private var detailColumn: some View {
        detailSplitColumn
        .navigationSplitViewColumnWidth(
            min: detailColumnMinWidth,
            ideal: detailColumnIdealWidth,
            max: .infinity
        )
        .animation(inspectorColumnAnimation, value: isInspectorColumnVisible)
    }

    private var detailSplitColumn: some View {
        HSplitView {
            mainContent
                .frame(
                    minWidth: AppLayout.contentMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .layoutPriority(1)

            if isInspectorColumnVisible {
                inspectorColumn
                    .frame(
                        minWidth: AppLayout.inspectorMinWidth,
                        idealWidth: adaptiveInspectorIdealWidth,
                        maxWidth: adaptiveInspectorMaxWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailColumnMinWidth: CGFloat {
        if isInspectorColumnVisible {
            AppLayout.contentMinWidth + AppLayout.inspectorMinWidth
        } else {
            AppLayout.contentMinWidth
        }
    }

    private var detailColumnIdealWidth: CGFloat {
        if isInspectorColumnVisible {
            AppLayout.contentIdealWidth + AppLayout.inspectorIdealWidth
        } else {
            AppLayout.contentIdealWidth
        }
    }

    private var adaptiveInspectorIdealWidth: CGFloat {
        guard windowWidth > 0 else {
            return AppLayout.inspectorIdealWidth
        }

        if windowWidth >= 1_600 {
            return AppLayout.inspectorMaxWidth
        }

        if sidebarCollapsed, windowWidth >= 960 {
            return AppLayout.inspectorIdealWidth
        }

        if windowWidth >= AppLayout.sidebarCollapseWidthWithInspector {
            return AppLayout.inspectorIdealWidth
        }

        return AppLayout.inspectorMinWidth
    }

    private var adaptiveInspectorMaxWidth: CGFloat {
        guard windowWidth > 0 else {
            return AppLayout.inspectorMaxWidth
        }

        if windowWidth >= 1_600 {
            return AppLayout.inspectorMaxWidth
        }

        if sidebarCollapsed, windowWidth >= 960 {
            return AppLayout.inspectorIdealWidth
        }

        if windowWidth >= AppLayout.sidebarCollapseWidthWithInspector {
            return AppLayout.inspectorIdealWidth
        }

        return AppLayout.inspectorMinWidth
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        Group {
            if appState.selectedMainSidebar.usesReportInspector {
                ReportEvidenceInspectorHost()
            } else {
                JobInspectorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            AppWindowColumnBackground()
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private func applySidebarPolicy(windowWidth: CGFloat) {
        switch layoutPolicy.sidebarAction(
            windowWidth: windowWidth,
            inspectorVisible: isInspectorColumnVisible,
            sidebarCollapsed: sidebarCollapsed,
            autoCollapsedSidebar: autoCollapsedSidebar
        ) {
        case .keep:
            break
        case .collapse:
            autoCollapsedSidebar = true
            applyingSidebarPolicy = true
            columnVisibility = .detailOnly
        case .restore:
            autoCollapsedSidebar = false
            applyingSidebarPolicy = true
            columnVisibility = .all
        }
    }

    private func updateWindowWidth(_ width: CGFloat) {
        guard width > 0, abs(width - windowWidth) >= 1 else {
            return
        }

        windowWidth = width
        applySidebarPolicy(windowWidth: width)
    }

    private func handleSidebarVisibilityChange(_ visibility: NavigationSplitViewVisibility) {
        if applyingSidebarPolicy {
            applyingSidebarPolicy = false
            return
        }

        if visibility == .detailOnly || visibility == .all {
            autoCollapsedSidebar = false
        }
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation(inspectorColumnAnimation) {
                    inspectorVisible.toggle()
                }
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

private struct WindowWidthObserver: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> WindowWidthObserverView {
        let view = WindowWidthObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowWidthObserverView, context: Context) {
        nsView.onChange = onChange
        nsView.publishWindowWidth()
    }
}

@MainActor
private final class WindowWidthObserverView: NSView {
    var onChange: (CGFloat) -> Void = { _ in }
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        publishWindowWidth()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func publishWindowWidth() {
        guard let window else {
            return
        }

        onChange(window.frame.width)
    }

    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }

        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: observedWindow)
        observedWindow = window

        guard let window else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc
    private func windowDidResize(_ notification: Notification) {
        publishWindowWidth()
    }
}

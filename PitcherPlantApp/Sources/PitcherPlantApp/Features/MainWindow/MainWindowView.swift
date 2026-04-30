import AppKit
import SwiftUI

private let inspectorColumnAnimation = Animation.smooth(duration: 0.32, extraBounce: 0)

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = false
    @Namespace private var mainToolbarGlassNamespace
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var autoCollapsedSidebar = false
    @State private var applyingSidebarPolicy = false
    @State private var windowWidth: CGFloat = 0
    @State private var settingsSearchText = ""
    @State private var reportSearchText = ""
    @State private var reportToolbarSearchPresented = false
    @State private var reportToolbarSearchExpanded = false
    @State private var titleSelectorPresented = false
    private let layoutPolicy = MainWindowLayoutPolicy()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(selection: animatedSidebarSelection)
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
            updateReportToolbarSearchPresentation(animated: false)
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
            if !shouldShowReportToolbarSearch {
                reportSearchText = ""
            }
            applySidebarPolicy(windowWidth: windowWidth)
            updateReportToolbarSearchPresentation(animated: true)
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
        .toolbar(removing: .sidebarToggle)
        .toolbar(removing: .title)
        .animation(AppMotion.toolbarGlassAppear, value: appState.selectedMainSidebar)
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

    private var shouldShowReportToolbarSearch: Bool {
        appState.selectedMainSidebar == .reports || appState.selectedMainSidebar.reportSectionKind != nil
    }

    private var animatedSidebarSelection: Binding<MainSidebarItem> {
        Binding {
            appState.selectedMainSidebar
        } set: { item in
            withAnimation(AppMotion.toolbarGlassAppear) {
                appState.selectedMainSidebar = item
            }
        }
    }

    private func sidebar(selection: Binding<MainSidebarItem>) -> some View {
        MainSidebarView(
            selection: selection,
            toggleSidebar: toggleSidebarColumn,
            showNewAuditComposer: showNewAuditComposer,
            showsToolbarControls: !sidebarCollapsed
        )
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
                        idealWidth: AppLayout.inspectorIdealWidth,
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

    private var adaptiveInspectorMaxWidth: CGFloat {
        guard windowWidth > 0 else {
            return AppLayout.inspectorMaxWidth
        }

        let availableDetailWidth = windowWidth - (sidebarCollapsed ? 0 : AppLayout.sidebarMaxWidth)
        let dragLimit = min(AppLayout.inspectorMaxWidth, availableDetailWidth - AppLayout.contentMinWidth)

        return max(AppLayout.inspectorMinWidth, dragLimit)
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

    private func updateReportToolbarSearchPresentation(animated: Bool) {
        guard shouldShowReportToolbarSearch else {
            withAnimation(AppMotion.toolbarGlassAppear) {
                reportToolbarSearchExpanded = false
                reportToolbarSearchPresented = false
            }
            return
        }

        withAnimation(AppMotion.toolbarGlassAppear) {
            reportToolbarSearchPresented = true
            reportToolbarSearchExpanded = false
        }
    }

    private func toggleSidebarColumn() {
        withAnimation(AppMotion.toolbarGlassAppear) {
            autoCollapsedSidebar = false
            columnVisibility = sidebarCollapsed ? .all : .detailOnly
        }
    }

    private func showNewAuditComposer() {
        withAnimation(AppMotion.toolbarGlassAppear) {
            appState.selectedMainSidebar = .newAudit
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            FloatingToolbarCluster(spacing: 10) {
                if sidebarCollapsed {
                    MainSidebarToolbarControls(
                        showsCapsule: true,
                        toggleSidebar: toggleSidebarColumn,
                        showNewAuditComposer: showNewAuditComposer
                    )
                    .transition(.floatingToolbarFusion)
                }

                FloatingToolbarTitleSelector(
                    title: "PitcherPlant",
                    subtitle: appState.t("toolbar.titleMode.standard"),
                    accessibilityLabel: appState.t("toolbar.titleSelector"),
                    isPresented: $titleSelectorPresented
                ) {
                    MainToolbarTitlePopover()
                }
            }
            .animation(AppMotion.toolbarGlassAppear, value: sidebarCollapsed)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .automatic) {
            FloatingToolbarFusionCluster(spacing: 10, forceExpanded: reportToolbarSearchExpanded) {
                FloatingToolbarButtonGroup {
                    mainToolbarUtilityButtons
                    mainToolbarAuditButton
                    mainToolbarSettingsButton
                    if shouldShowReportToolbarSearch, reportToolbarSearchPresented {
                        FloatingToolbarSearchTriggerButton(
                            title: appState.t("reports.searchPrompt"),
                            isExpanded: $reportToolbarSearchExpanded
                        )
                    }
                }
                .glassEffectID("main-toolbar-actions-collapsed", in: mainToolbarGlassNamespace)
                .glassEffectTransition(.matchedGeometry)
            } expanded: {
                FloatingToolbarButtonGroup {
                    mainToolbarUtilityButtons
                }
                .glassEffectID("main-toolbar-utility-actions", in: mainToolbarGlassNamespace)
                .glassEffectTransition(.matchedGeometry)

                FloatingToolbarButtonGroup {
                    mainToolbarAuditButton
                }
                .glassEffectID("main-toolbar-primary-action", in: mainToolbarGlassNamespace)
                .glassEffectTransition(.matchedGeometry)

                FloatingToolbarButtonGroup {
                    mainToolbarSettingsButton
                }
                .glassEffectID("main-toolbar-settings-action", in: mainToolbarGlassNamespace)
                .glassEffectTransition(.matchedGeometry)

                if shouldShowReportToolbarSearch, reportToolbarSearchPresented {
                    FloatingToolbarSearchField(
                        text: $reportSearchText,
                        prompt: appState.t("reports.searchPrompt"),
                        isExpanded: $reportToolbarSearchExpanded,
                        collapsesWhenInactive: true
                    )
                        .glassEffectID("main-toolbar-search-action", in: mainToolbarGlassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                        .transition(.floatingToolbarSearchPresence)
                }
            }
            .animation(AppMotion.toolbarGlassAppear, value: reportToolbarSearchPresented)
            .animation(AppMotion.toolbarSearchExpand, value: reportToolbarSearchExpanded)
            .animation(AppMotion.toolbarGlassAppear, value: appState.selectedMainSidebar)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder
    private var mainToolbarUtilityButtons: some View {
        FloatingToolbarIconButton(
            isInspectorColumnVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"),
            systemImage: isInspectorColumnVisible ? "sidebar.right" : "sidebar.trailing"
        ) {
            withAnimation(inspectorColumnAnimation) {
                inspectorVisible.toggle()
            }
        }
        .disabled(!appState.selectedMainSidebar.allowsInspector)

        FloatingToolbarIconButton(appState.t("toolbar.reload"), systemImage: "arrow.clockwise") {
            Task { await appState.reload() }
        }
        .keyboardShortcut("r", modifiers: .command)
    }

    @ViewBuilder
    private var mainToolbarAuditButton: some View {
        let auditIsRunning = appState.isRunningAudit
        FloatingToolbarIconButton(
            auditIsRunning ? appState.t("toolbar.cancel") : appState.t("toolbar.start"),
            systemImage: auditIsRunning ? "stop.fill" : "play.fill",
            role: auditIsRunning ? .destructive : nil,
            isProminent: true
        ) {
            if appState.isRunningAudit {
                appState.cancelAudit()
            } else {
                appState.beginAudit()
            }
        }
        .id(auditIsRunning)
        .keyboardShortcut(.return, modifiers: .command)
    }

    @ViewBuilder
    private var mainToolbarSettingsButton: some View {
        FloatingToolbarIconButton(appState.t("toolbar.settings"), systemImage: "gear") {
            withAnimation(AppMotion.toolbarGlassAppear) {
                appState.selectedMainSidebar = .settings
            }
        }
        .keyboardShortcut(",", modifiers: .command)
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
            ReportsInlineView(reportQuery: $reportSearchText)
        case .allEvidence, .favoriteEvidence, .watchedEvidence:
            EvidenceCollectionView(scope: appState.selectedMainSidebar.evidenceCollectionScope ?? .all)
        case .textEvidence, .codeEvidence, .imageEvidence, .metadataEvidence, .dedupEvidence, .crossBatchEvidence:
            EvidenceFocusedReportsView(kind: appState.selectedMainSidebar.reportSectionKind, reportQuery: $reportSearchText)
        case .fingerprints:
            FingerprintLibraryView()
        case .whitelist:
            WhitelistLibraryView()
        case .settings:
            SettingsRootView(searchText: $settingsSearchText)
        }
    }
}

private struct MainToolbarTitlePopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        FloatingToolbarPopoverPanel(width: 420) {
            VStack(alignment: .leading, spacing: 8) {
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.auto"),
                    subtitle: appState.t("toolbar.mode.auto.subtitle"),
                    isSelected: false
                )
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.deep"),
                    subtitle: appState.t("toolbar.mode.deep.subtitle"),
                    isSelected: false
                )
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.standard"),
                    subtitle: appState.t("toolbar.mode.standard.subtitle"),
                    isSelected: true
                )
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.quick"),
                    subtitle: appState.t("toolbar.mode.quick.subtitle"),
                    isSelected: false
                )

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(appState.t("toolbar.mode.templates"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 38)

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(appState.t("toolbar.mode.temporary"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 48, height: 28)
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(.primary.opacity(0.12))
                                .frame(width: 24, height: 24)
                                .padding(.leading, 2)
                        }
                }
                .frame(height: 38)
            }
        }
    }
}

private struct MainToolbarModeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.07 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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

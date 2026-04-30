import AppKit
import SwiftUI

private let inspectorColumnAnimation = Animation.smooth(duration: 0.32, extraBounce: 0)
private let titlePopoverToolbarLayerOffset: CGFloat = 50

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
    @State private var titleSelectorGlobalFrame: CGRect = .zero
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
        .background(WindowDefaultFrameCalibrator())
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
        .overlay {
            GeometryReader { proxy in
                mainWindowToolbarOverlay(
                    topSafeAreaInset: proxy.safeAreaInsets.top,
                    rootGlobalFrame: proxy.frame(in: .global)
                )
                    .ignoresSafeArea(.container, edges: .top)
            }
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
                    .layoutPriority(-1)
                    .background(
                        SplitTrailingColumnWidthInitializer(
                            width: AppLayout.inspectorDefaultWidth,
                            resetKey: appState.selectedMainSidebar.rawValue
                        )
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
        if sidebarCollapsed {
            expandWindowForSidebarIfNeeded()
        }
        withAnimation(AppMotion.toolbarGlassAppear) {
            autoCollapsedSidebar = false
            columnVisibility = sidebarCollapsed ? .all : .detailOnly
        }
    }

    private func expandWindowForSidebarIfNeeded() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }
        guard window.styleMask.contains(.fullScreen) == false else {
            return
        }

        let safeWidth = isInspectorColumnVisible
            ? AppLayout.sidebarRestoreWidthWithInspector
            : AppLayout.sidebarRestoreWidthWithoutInspector
        let currentWidth = max(windowWidth, window.frame.width)
        guard currentWidth < safeWidth else {
            return
        }

        resizeWindow(window, toWidth: safeWidth)
    }

    private func resizeWindow(_ window: NSWindow, toWidth requestedWidth: CGFloat) {
        var frame = window.frame
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let targetWidth = min(requestedWidth, visibleFrame?.width ?? requestedWidth)
        let delta = targetWidth - frame.width
        guard delta > 0 else {
            return
        }

        frame.size.width = targetWidth
        frame.origin.x -= delta / 2

        if let visibleFrame {
            let maxX = visibleFrame.maxX - frame.width
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), maxX)
        }

        window.setFrame(frame, display: true, animate: true)
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
                    subtitle: "",
                    accessibilityLabel: appState.t("toolbar.titleSelector"),
                    isPresented: $titleSelectorPresented
                )
                .background(GlobalFrameObserver(frame: $titleSelectorGlobalFrame))
            }
            .animation(AppMotion.toolbarGlassAppear, value: sidebarCollapsed)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private func mainWindowToolbarOverlay(topSafeAreaInset: CGFloat, rootGlobalFrame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            mainWindowTrailingToolbarOverlay(topSafeAreaInset: topSafeAreaInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if titleSelectorPresented, titleSelectorGlobalFrame != .zero {
                Button {
                    withAnimation(AppMotion.toolbarGlassAppear) {
                        titleSelectorPresented = false
                    }
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(20)

                MainToolbarTitlePopover()
                    .padding(4)
                    .offset(
                        x: titleSelectorGlobalFrame.minX - rootGlobalFrame.minX,
                        y: titleSelectorGlobalFrame.maxY - rootGlobalFrame.minY + titlePopoverToolbarLayerOffset
                    )
                    .transition(.floatingToolbarPopoverPresence)
                    .zIndex(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(AppMotion.toolbarGlassAppear, value: titleSelectorPresented)
    }

    private func mainWindowTrailingToolbarOverlay(topSafeAreaInset: CGFloat) -> some View {
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
                mainToolbarSettingsButton
            }
            .glassEffectID("main-toolbar-primary-actions", in: mainToolbarGlassNamespace)
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
        .padding(.top, trailingToolbarTopPadding(topSafeAreaInset: topSafeAreaInset))
        .padding(.trailing, trailingToolbarTrailingPadding(topSafeAreaInset: topSafeAreaInset))
        .animation(AppMotion.toolbarGlassAppear, value: reportToolbarSearchPresented)
        .animation(AppMotion.toolbarSearchExpand, value: reportToolbarSearchExpanded)
        .animation(AppMotion.toolbarGlassAppear, value: appState.selectedMainSidebar)
    }

    private func trailingToolbarTopPadding(topSafeAreaInset: CGFloat) -> CGFloat {
        AppLayout.floatingToolbarTopPadding(topSafeAreaInset: topSafeAreaInset)
    }

    private func trailingToolbarTrailingPadding(topSafeAreaInset: CGFloat) -> CGFloat {
        AppLayout.curvedToolbarTrailingPadding(
            base: 14,
            topPadding: trailingToolbarTopPadding(topSafeAreaInset: topSafeAreaInset),
            cornerRadius: AppLayout.floatingToolbarWindowCornerRadius
        )
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

private enum MainToolbarModeSelection {
    case auto
    case deep
    case standard
    case quick
}

private enum MainToolbarTemplateSelection {
    case defaultAudit
    case evidenceReview
    case fastScreening
}

private struct MainToolbarTitlePopover: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMode: MainToolbarModeSelection = .standard
    @State private var selectedTemplate: MainToolbarTemplateSelection = .defaultAudit
    @State private var templatesExpanded = false
    @State private var temporaryScanEnabled = false

    var body: some View {
        FloatingToolbarPopoverPanel(width: 260) {
            VStack(alignment: .leading, spacing: 4) {
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.auto"),
                    subtitle: appState.t("toolbar.mode.auto.subtitle"),
                    isSelected: selectedMode == .auto
                ) {
                    selectMode(.auto)
                }
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.deep"),
                    subtitle: appState.t("toolbar.mode.deep.subtitle"),
                    isSelected: selectedMode == .deep
                ) {
                    selectMode(.deep)
                }
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.standard"),
                    subtitle: appState.t("toolbar.mode.standard.subtitle"),
                    isSelected: selectedMode == .standard
                ) {
                    selectMode(.standard)
                }
                MainToolbarModeRow(
                    title: appState.t("toolbar.mode.quick"),
                    subtitle: appState.t("toolbar.mode.quick.subtitle"),
                    isSelected: selectedMode == .quick
                ) {
                    selectMode(.quick)
                }

                Divider()
                    .padding(.vertical, 2)

                MainToolbarPanelIconRow(
                    title: appState.t("toolbar.mode.templates"),
                    systemImage: "slider.horizontal.3",
                    trailingSystemImage: "chevron.down",
                    isActive: templatesExpanded,
                    isExpanded: templatesExpanded
                ) {
                    withAnimation(AppMotion.toolbarGlassAppear) {
                        templatesExpanded.toggle()
                    }
                }

                if templatesExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        MainToolbarTemplateRow(
                            title: appState.t("toolbar.mode.template.default"),
                            subtitle: appState.t("toolbar.mode.template.default.subtitle"),
                            isSelected: selectedTemplate == .defaultAudit
                        ) {
                            selectTemplate(.defaultAudit)
                        }
                        MainToolbarTemplateRow(
                            title: appState.t("toolbar.mode.template.review"),
                            subtitle: appState.t("toolbar.mode.template.review.subtitle"),
                            isSelected: selectedTemplate == .evidenceReview
                        ) {
                            selectTemplate(.evidenceReview)
                        }
                        MainToolbarTemplateRow(
                            title: appState.t("toolbar.mode.template.fast"),
                            subtitle: appState.t("toolbar.mode.template.fast.subtitle"),
                            isSelected: selectedTemplate == .fastScreening
                        ) {
                            selectTemplate(.fastScreening)
                        }
                    }
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                Divider()
                    .padding(.vertical, 2)

                MainToolbarPanelToggleRow(
                    title: appState.t("toolbar.mode.temporary"),
                    systemImage: "wand.and.stars",
                    isOn: $temporaryScanEnabled
                )
            }
            .animation(AppMotion.toolbarGlassAppear, value: templatesExpanded)
        }
    }

    private func selectMode(_ mode: MainToolbarModeSelection) {
        withAnimation(AppMotion.toolbarGlassAppear) {
            selectedMode = mode
        }
    }

    private func selectTemplate(_ template: MainToolbarTemplateSelection) {
        withAnimation(AppMotion.toolbarGlassAppear) {
            selectedTemplate = template
        }
    }
}

private struct MainToolbarModeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var action: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(rowFillAlpha))
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(FloatingToolbarPanelButtonStyle(cornerRadius: 11))
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
    }

    private var rowFillAlpha: Double {
        if isSelected {
            return isHovering ? 0.11 : 0.07
        }
        return isHovering ? 0.07 : 0
    }
}

private struct MainToolbarTemplateRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var action: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(height: 31)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(rowFillAlpha))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(FloatingToolbarPanelButtonStyle(cornerRadius: 10))
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
    }

    private var rowFillAlpha: Double {
        if isSelected {
            return isHovering ? 0.10 : 0.06
        }
        return isHovering ? 0.06 : 0
    }
}

private struct MainToolbarPanelToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(rowFillAlpha))
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
        .animation(AppMotion.toolbarGlassHover, value: isOn)
        .accessibilityLabel(title)
    }

    private var rowFillAlpha: Double {
        if isOn {
            return isHovering ? 0.11 : 0.07
        }
        return isHovering ? 0.07 : 0
    }
}

private struct MainToolbarPanelIconRow: View {
    let title: String
    let systemImage: String
    var trailingSystemImage: String?
    var isActive = false
    var isExpanded = false
    var action: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(rowFillAlpha))
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(FloatingToolbarPanelButtonStyle(cornerRadius: 11))
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
        .animation(AppMotion.toolbarGlassHover, value: isExpanded)
    }

    private var rowFillAlpha: Double {
        if isActive {
            return isHovering ? 0.11 : 0.07
        }
        return isHovering ? 0.07 : 0
    }
}

private struct GlobalFrameObserver: View {
    @Binding var frame: CGRect

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global).integral
            } action: { newFrame in
                frame = newFrame
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

private struct WindowDefaultFrameCalibrator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDefaultFrameCalibratorView {
        WindowDefaultFrameCalibratorView()
    }

    func updateNSView(_ nsView: WindowDefaultFrameCalibratorView, context: Context) {
        nsView.scheduleCalibration()
    }
}

@MainActor
private final class WindowDefaultFrameCalibratorView: NSView {
    private var didCalibrate = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleCalibration()
    }

    func scheduleCalibration() {
        DispatchQueue.main.async { [weak self] in
            self?.calibrate()
        }
    }

    private func calibrate() {
        guard didCalibrate == false, let window else {
            return
        }
        guard window.styleMask.contains(.fullScreen) == false else {
            didCalibrate = true
            return
        }

        let targetFrameSize = CGSize(
            width: AppLayout.mainWindowDefaultWidth,
            height: AppLayout.mainWindowDefaultHeight
        )
        let frame = window.frame
        guard abs(frame.width - targetFrameSize.width) > 1 || abs(frame.height - targetFrameSize.height) > 1 else {
            didCalibrate = true
            return
        }

        var nextFrame = frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        nextFrame.size = targetFrameSize
        nextFrame.origin.x = center.x - targetFrameSize.width / 2
        nextFrame.origin.y = center.y - targetFrameSize.height / 2

        if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let maxX = visibleFrame.maxX - nextFrame.width
            let maxY = visibleFrame.maxY - nextFrame.height
            nextFrame.origin.x = min(max(nextFrame.origin.x, visibleFrame.minX), maxX)
            nextFrame.origin.y = min(max(nextFrame.origin.y, visibleFrame.minY), maxY)
        }

        window.setFrame(nextFrame, display: true, animate: false)
        didCalibrate = true
    }
}

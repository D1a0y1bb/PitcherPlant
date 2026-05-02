import AppKit
import SwiftUI

private let inspectorColumnAnimation = Animation.smooth(duration: 0.32, extraBounce: 0)

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var autoCollapsedSidebar = false
    @State private var applyingSidebarPolicy = false
    @State private var windowWidth: CGFloat = 0
    @State private var settingsSearchText = ""
    @State private var reportSearchText = ""
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
        }
        .onChange(of: appState.appSettings.showInspectorByDefault) { _, visible in
            if !appState.selectedMainSidebar.allowsInspector {
                inspectorVisible = visible
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: appState.inspectorRequestID) { _, _ in
            if appState.selectedMainSidebar.allowsInspector {
                withAnimation(motion(inspectorColumnAnimation)) {
                    inspectorVisible = true
                }
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: appState.inspectorToggleRequestID) { _, _ in
            guard appState.selectedMainSidebar.allowsInspector else {
                return
            }
            withAnimation(motion(inspectorColumnAnimation)) {
                inspectorVisible.toggle()
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .toolbar {
            mainToolbarItems
        }
        .navigationTitle("PitcherPlant")
        .reportToolbarSearch(
            isPresented: shouldShowReportToolbarSearch,
            text: $reportSearchText,
            prompt: appState.t("reports.searchPrompt")
        )
        .background(ToolbarCustomizationDisabler().frame(width: 0, height: 0))
        .overlay {
            if let recovery = appState.databaseRecovery {
                DatabaseRecoveryBlockingView(recovery: recovery)
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

    private func motion(_ animation: Animation) -> Animation? {
        AppMotion.enabled(animation, reduceMotion: reduceMotion)
    }

    private var animatedSidebarSelection: Binding<MainSidebarItem> {
        Binding {
            appState.selectedMainSidebar
        } set: { item in
            withAnimation(motion(AppMotion.toolbarGlassAppear)) {
                appState.selectedMainSidebar = item
            }
        }
    }

    private func sidebar(selection: Binding<MainSidebarItem>) -> some View {
        MainSidebarView(
            selection: selection
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
        .animation(motion(inspectorColumnAnimation), value: isInspectorColumnVisible)
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

    private func showNewAuditComposer() {
        withAnimation(AppMotion.toolbarGlassAppear) {
            appState.selectedMainSidebar = .newAudit
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            NativeScanOptionsMenu()
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showNewAuditComposer()
            } label: {
                Label(appState.t("toolbar.newScan"), systemImage: "square.and.pencil")
            }
            .help(appState.t("toolbar.newScan"))
            .accessibilityLabel(appState.t("toolbar.newScan"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(motion(inspectorColumnAnimation)) {
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
            .accessibilityLabel(isInspectorColumnVisible ? appState.t("toolbar.hideInspector") : appState.t("toolbar.showInspector"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await appState.reload() }
            } label: {
                Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help(appState.t("toolbar.reload"))
            .accessibilityLabel(appState.t("toolbar.reload"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button(role: appState.isRunningAudit ? .destructive : nil) {
                if appState.isRunningAudit {
                    appState.cancelAudit()
                } else {
                    appState.beginAudit()
                }
            } label: {
                Label(
                    appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"),
                    systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                )
            }
            .id(appState.isRunningAudit)
            .keyboardShortcut(.return, modifiers: .command)
            .help(appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"))
            .accessibilityLabel(appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(AppMotion.toolbarGlassAppear) {
                    appState.selectedMainSidebar = .settings
                }
            } label: {
                Label(appState.t("toolbar.settings"), systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help(appState.t("toolbar.settings"))
            .accessibilityLabel(appState.t("toolbar.settings"))
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

private struct DatabaseRecoveryBlockingView: View {
    @Environment(AppState.self) private var appState
    let recovery: DatabaseRecoveryState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("数据库需要恢复")
                            .font(.title3.weight(.semibold))
                        Text("主数据库无法打开，应用已暂停写入当前工作区。")
                            .font(AppTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    recoveryPathRow("工作区", recovery.failedRootPath)
                    recoveryPathRow("临时库", recovery.fallbackRootPath)
                    Text(recovery.message)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        appState.backupFailedDatabase()
                    } label: {
                        Label("备份数据库", systemImage: "externaldrive.badge.plus")
                    }

                    Button {
                        appState.revealDatabaseRecoveryWorkspace()
                    } label: {
                        Label("打开工作区", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        appState.continueWithTemporaryDatabase()
                    } label: {
                        Label("确认临时模式", systemImage: "exclamationmark.triangle")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 560, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        }
    }

    private func recoveryPathRow(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.metadata.weight(.semibold))
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct NativeScanOptionsMenu: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("pitcherplant.toolbar.scanMode") private var selectedModeRaw = AuditToolbarScanMode.standard.rawValue
    @SceneStorage("pitcherplant.toolbar.template") private var selectedTemplateRaw = AuditToolbarTemplate.defaultAudit.rawValue

    var body: some View {
        Menu {
            Section(appState.t("toolbar.titleSelector")) {
                scanModeButton(.auto)
                scanModeButton(.deep)
                scanModeButton(.standard)
                scanModeButton(.quick)
            }

            Section(appState.t("toolbar.mode.templates")) {
                templateButton(.defaultAudit)
                templateButton(.evidenceReview)
                templateButton(.fastScreening)
            }

            Toggle(isOn: temporaryScanBinding) {
                Label(appState.t("toolbar.mode.temporary"), systemImage: "wand.and.stars")
            }
        } label: {
            Label(appState.t("toolbar.titleSelector"), systemImage: "slider.horizontal.3")
        }
        .help(appState.t("toolbar.titleSelector"))
        .accessibilityLabel(appState.t("toolbar.titleSelector"))
    }

    private func scanModeButton(_ mode: AuditToolbarScanMode) -> some View {
        Button {
            selectMode(mode)
        } label: {
            Label(scanModeTitle(mode), systemImage: selectedMode == mode ? "checkmark.circle.fill" : "circle")
        }
    }

    private func templateButton(_ template: AuditToolbarTemplate) -> some View {
        Button {
            selectTemplate(template)
        } label: {
            Label(templateTitle(template), systemImage: selectedTemplate == template ? "checkmark.circle.fill" : "circle")
        }
    }

    private var selectedMode: AuditToolbarScanMode {
        AuditToolbarScanMode(rawValue: selectedModeRaw) ?? .standard
    }

    private var selectedTemplate: AuditToolbarTemplate {
        AuditToolbarTemplate(rawValue: selectedTemplateRaw) ?? .defaultAudit
    }

    private var temporaryScanBinding: Binding<Bool> {
        Binding {
            appState.draftConfiguration.toolbarTemporaryScanEnabled
        } set: { enabled in
            appState.updateDraft { configuration in
                configuration.setToolbarTemporaryScanEnabled(enabled)
            }
        }
    }

    private func selectMode(_ mode: AuditToolbarScanMode) {
        selectedModeRaw = mode.rawValue
        let temporaryEnabled = appState.draftConfiguration.toolbarTemporaryScanEnabled
        appState.updateDraft { configuration in
            configuration.applyToolbarScanMode(mode)
            configuration.setToolbarTemporaryScanEnabled(temporaryEnabled)
        }
    }

    private func selectTemplate(_ template: AuditToolbarTemplate) {
        selectedTemplateRaw = template.rawValue
        appState.updateDraft { configuration in
            configuration.applyToolbarTemplate(template)
        }
    }

    private func scanModeTitle(_ mode: AuditToolbarScanMode) -> String {
        switch mode {
        case .auto:
            appState.t("toolbar.mode.auto")
        case .deep:
            appState.t("toolbar.mode.deep")
        case .standard:
            appState.t("toolbar.mode.standard")
        case .quick:
            appState.t("toolbar.mode.quick")
        }
    }

    private func templateTitle(_ template: AuditToolbarTemplate) -> String {
        switch template {
        case .defaultAudit:
            appState.t("toolbar.mode.template.default")
        case .evidenceReview:
            appState.t("toolbar.mode.template.review")
        case .fastScreening:
            appState.t("toolbar.mode.template.fast")
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

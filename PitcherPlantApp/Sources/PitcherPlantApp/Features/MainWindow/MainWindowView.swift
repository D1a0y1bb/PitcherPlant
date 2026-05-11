import AppKit
import SwiftUI

private let inspectorColumnAnimation = Animation.smooth(duration: 0.32, extraBounce: 0)

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("pitcherplant.inspectorVisible") private var inspectorVisible = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var workspacePresentationMode: WorkspacePresentationMode = .map
    @State private var workspaceMapStyleMode: WorkspaceMapStyleMode = .explore
    @State private var workspaceMapDepthMode: WorkspaceMapDepthMode = .twoD
    @State private var isShowingWorkspaceMapModePanel = false
    @State private var autoCollapsedSidebar = false
    @State private var applyingSidebarPolicy = false
    @State private var windowWidth: CGFloat = 0
    @State private var reportSearchText = ""
    private let layoutPolicy = MainWindowLayoutPolicy()
    private let inspectorTransitionPolicy = MainWindowInspectorTransitionPolicy()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(selection: animatedSidebarSelection)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowWidthObserver { width in
            updateWindowWidth(width)
        })
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            appState.startUpdateMonitoring()
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
            if !isReportSearchContext {
                reportSearchText = ""
            }
            if !isWorkspaceMapVisible {
                isShowingWorkspaceMapModePanel = false
            }
            applySidebarPolicy(windowWidth: windowWidth)
        }
        .onChange(of: workspacePresentationMode) { _, _ in
            if !isWorkspaceMapVisible {
                isShowingWorkspaceMapModePanel = false
            }
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
                dismissButton: .default(Text(appState.t("common.ok"))) {
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

    private var isReportSearchContext: Bool {
        appState.selectedMainSidebar == .reports || appState.selectedMainSidebar.reportSectionKind != nil
    }

    private var supportsToolbarSearch: Bool {
        isReportSearchContext
    }

    private var isWorkspaceMapVisible: Bool {
        appState.selectedMainSidebar == .workspace && workspacePresentationMode == .map
    }

    private var toolbarSearchBinding: Binding<String> {
        Binding {
            return reportSearchText
        } set: { value in
            if isReportSearchContext {
                reportSearchText = value
            }
        }
    }

    private var toolbarSearchPrompt: String {
        appState.t("reports.searchPrompt")
    }

    private var workspacePresentationBinding: Binding<WorkspacePresentationMode> {
        $workspacePresentationMode
    }

    private func motion(_ animation: Animation) -> Animation? {
        AppMotion.enabled(animation, reduceMotion: reduceMotion)
    }

    private var animatedSidebarSelection: Binding<MainSidebarItem> {
        Binding {
            appState.selectedMainSidebar
        } set: { item in
            selectMainSidebarItem(item)
        }
    }

    private func selectMainSidebarItem(_ item: MainSidebarItem) {
        let disablesSelectionAnimation = inspectorTransitionPolicy.disablesSelectionAnimation(
            inspectorVisible: isInspectorColumnVisible,
            currentItem: appState.selectedMainSidebar,
            targetItem: item
        )

        if disablesSelectionAnimation {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appState.selectedMainSidebar = item
            }
            return
        }

        withAnimation(motion(AppMotion.toolbarGlassAppear)) {
            appState.selectedMainSidebar = item
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
        searchableMainContent
            .frame(
                minWidth: AppLayout.contentMinWidth,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .navigationSplitViewColumnWidth(
                min: AppLayout.contentMinWidth,
                ideal: AppLayout.contentIdealWidth,
                max: .infinity
            )
            .inspector(isPresented: inspectorPresentation) {
                inspectorColumn
                    .inspectorColumnWidth(
                        min: AppLayout.inspectorMinWidth,
                        ideal: AppLayout.inspectorIdealWidth,
                        max: AppLayout.inspectorMaxWidth
                    )
            }
            .animation(motion(inspectorColumnAnimation), value: isInspectorColumnVisible)
    }

    @ViewBuilder
    private var searchableMainContent: some View {
        if supportsToolbarSearch {
            mainContent
                .searchable(text: toolbarSearchBinding, prompt: toolbarSearchPrompt)
        } else {
            mainContent
        }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding {
            isInspectorColumnVisible
        } set: { visible in
            guard appState.selectedMainSidebar.allowsInspector else {
                inspectorVisible = false
                return
            }
            withAnimation(motion(inspectorColumnAnimation)) {
                inspectorVisible = visible
            }
        }
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
        applySidebarPolicy(windowWidth: windowWidth)
    }

    private func showNewAuditComposer() {
        selectMainSidebarItem(.newAudit)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleWorkspacePresentation() {
        if appState.selectedMainSidebar == .workspace && workspacePresentationMode == .map {
            workspacePresentationMode = .dashboard
        } else {
            workspacePresentationMode = .map
            selectMainSidebarItem(.workspace)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if appState.availableUpdate != nil {
                updateToolbarButton
            }

            NativeScanOptionsMenu()
            importPackageToolbarButton
            newAuditToolbarButton
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            startAuditToolbarButton
            reloadToolbarButton
            workspacePresentationToolbarButton
            inspectorToolbarButton
            settingsToolbarButton
            if isWorkspaceMapVisible {
                workspaceMapModeToolbarButton
                workspaceMapDepthToolbarButton
            }
        }
    }

    private var updateToolbarButton: some View {
        Button {
            appState.presentAvailableUpdate()
        } label: {
            Label(appState.t("update.button.title"), systemImage: "arrow.down")
        }
        .help(appState.t("update.button.help"))
        .accessibilityLabel(appState.t("update.button.accessibility"))
    }

    private var settingsToolbarButton: some View {
        Button {
            openWindow(id: AppWindow.settings.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label(appState.t("toolbar.settings"), systemImage: "gearshape")
        }
        .help(appState.t("toolbar.settings"))
        .accessibilityLabel(appState.t("toolbar.settings"))
    }

    private var workspaceMapModeToolbarButton: some View {
        Button {
            isShowingWorkspaceMapModePanel.toggle()
        } label: {
            Label(appState.t("workspace.map.modePanelTitle"), systemImage: "map.fill")
        }
        .help(appState.t("workspace.map.modePanelTitle"))
        .accessibilityLabel(appState.t("workspace.map.modePanelTitle"))
        .popover(
            isPresented: $isShowingWorkspaceMapModePanel,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            WorkspaceMapModePanel(mapStyleMode: $workspaceMapStyleMode)
        }
    }

    private var workspaceMapDepthToolbarButton: some View {
        Button {
            workspaceMapDepthMode.toggle()
        } label: {
            Text(workspaceMapDepthMode.localizedTitle(appState))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .help(appState.t("workspace.map.depthPicker"))
        .accessibilityLabel(appState.t("workspace.map.depthPicker"))
    }

    private var newAuditToolbarButton: some View {
        Button {
            showNewAuditComposer()
        } label: {
            Label(appState.t("toolbar.newAudit"), systemImage: "plus")
        }
        .help(appState.t("toolbar.newAudit"))
        .accessibilityLabel(appState.t("toolbar.newAudit"))
    }

    private var importPackageToolbarButton: some View {
        Button {
            appState.importSubmissionPackageWithPanel()
        } label: {
            Label(appState.t("audit.importSubmissions"), systemImage: "tray.and.arrow.down")
        }
        .disabled(!appState.canImportSubmissionPackage)
        .help(appState.t("audit.importSubmissions"))
        .accessibilityLabel(appState.t("audit.importSubmissions"))
    }

    private var startAuditToolbarButton: some View {
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

    private var reloadToolbarButton: some View {
        Button {
            Task { await appState.reload() }
        } label: {
            Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .help(appState.t("toolbar.reload"))
        .accessibilityLabel(appState.t("toolbar.reload"))
    }

    private var workspacePresentationToolbarButton: some View {
        let showingMap = appState.selectedMainSidebar == .workspace && workspacePresentationMode == .map
        let title = showingMap ? appState.t("toolbar.showWorkspaceDashboard") : appState.t("toolbar.showWorkspaceMap")
        let systemImage = showingMap ? "square.grid.2x2" : "airplane.departure"

        return Button {
            toggleWorkspacePresentation()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private var inspectorToolbarButton: some View {
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

    @ViewBuilder
    private var mainContent: some View {
        switch appState.selectedMainSidebar {
        case .workspace:
            WorkspaceDashboardView(
                presentationMode: workspacePresentationBinding,
                mapStyleMode: $workspaceMapStyleMode,
                mapDepthMode: $workspaceMapDepthMode
            )
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
                        Text(appState.t("database.recovery.title"))
                            .font(.title3.weight(.semibold))
                        Text(appState.t("database.recovery.description"))
                            .font(AppTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    recoveryPathRow(appState.t("database.recovery.workspace"), recovery.failedRootPath)
                    recoveryPathRow(appState.t("database.recovery.temporary"), recovery.fallbackRootPath)
                    Text(recovery.message)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        appState.backupFailedDatabase()
                    } label: {
                        Label(appState.t("database.recovery.backupButton"), systemImage: "externaldrive.badge.plus")
                    }

                    Button {
                        appState.revealDatabaseRecoveryWorkspace()
                    } label: {
                        Label(appState.t("database.recovery.openWorkspace"), systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        appState.continueWithTemporaryDatabase()
                    } label: {
                        Label(appState.t("database.recovery.confirmTemporary"), systemImage: "exclamationmark.triangle")
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
    @State private var isShowingOptions = false

    var body: some View {
        Button {
            isShowingOptions.toggle()
        } label: {
            Label(appState.t("toolbar.titleSelector"), systemImage: "slider.horizontal.3")
        }
        .help(appState.t("toolbar.titleSelector"))
        .accessibilityLabel(appState.t("toolbar.titleSelector"))
        .popover(isPresented: $isShowingOptions, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            scanOptionsPanel
        }
    }

    private var scanOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                panelSectionTitle(appState.t("toolbar.titleSelector"))
                scanModeButton(.auto)
                scanModeButton(.deep)
                scanModeButton(.standard)
                scanModeButton(.quick)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                panelSectionTitle(appState.t("toolbar.mode.templates"))
                templateButton(.defaultAudit)
                templateButton(.evidenceReview)
                templateButton(.fastScreening)
            }

            Divider()

            Toggle(isOn: temporaryScanBinding) {
                Label(appState.t("toolbar.mode.temporary"), systemImage: "wand.and.stars")
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private func panelSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.metadata.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func scanModeButton(_ mode: AuditToolbarScanMode) -> some View {
        Button {
            selectMode(mode)
            isShowingOptions = false
        } label: {
            optionRow(title: scanModeTitle(mode), isSelected: selectedMode == mode)
        }
        .buttonStyle(.plain)
    }

    private func templateButton(_ template: AuditToolbarTemplate) -> some View {
        Button {
            selectTemplate(template)
            isShowingOptions = false
        } label: {
            optionRow(title: templateTitle(template), isSelected: selectedTemplate == template)
        }
        .buttonStyle(.plain)
    }

    private func optionRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .frame(width: 18, alignment: .center)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
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
    private var lastPublishedWidth: CGFloat = 0
    private var pendingWidth: CGFloat?
    private var publishScheduled = false

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

        let width = window.frame.width
        guard width > 0 else {
            return
        }

        pendingWidth = width
        guard !publishScheduled else {
            return
        }

        publishScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.publishScheduled = false
            guard let width = self.pendingWidth else {
                return
            }
            self.pendingWidth = nil

            guard abs(width - self.lastPublishedWidth) >= 1 else {
                return
            }
            self.lastPublishedWidth = width
            self.onChange(width)
        }
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

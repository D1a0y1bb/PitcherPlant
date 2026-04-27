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
                    Color.clear
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
                        Task { await runAuditAndOpenReport() }
                    } label: {
                        Label(appState.t("toolbar.start"), systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(appState.isRunningAudit)
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
        .frame(minWidth: 1180, minHeight: 760)
    }

    private func runAuditAndOpenReport() async {
        await appState.startAudit()
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

private struct SettingsSearchToolbarModifier: ViewModifier {
    let isActive: Bool
    @Binding var searchText: String
    let prompt: String

    func body(content: Content) -> some View {
        if isActive {
            content
                .searchable(text: $searchText, prompt: prompt)
        } else {
            content
        }
    }
}

private struct EvidenceFocusedReportsView: View {
    @Environment(AppState.self) private var appState
    let kind: ReportSectionKind?

    var body: some View {
        ReportsInlineView()
            .onAppear {
                focusEvidenceKind()
            }
            .onChange(of: kind) { _, _ in
                focusEvidenceKind()
            }
    }

    private func focusEvidenceKind() {
        guard let kind else {
            return
        }
        if appState.selectedReportID == nil {
            appState.selectLatestReport()
        }
        appState.selectReportSection(kind)
    }
}

private struct MainStatusBar: View {
    @Environment(AppState.self) private var appState

    private var statusText: String {
        "\(appState.jobs.count) \(appState.t("status.audits")) · \(appState.reports.count) \(appState.t("status.reports")) · \(appState.fingerprints.count) \(appState.t("status.fingerprints"))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if appState.isRunningAudit {
                ProgressView()
                    .controlSize(.small)
                Text(appState.t("status.auditing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let latestReport = appState.latestReport {
                Text("\(appState.t("status.latest")): \(latestReport.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.t("status.ready"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct MainSidebarView: View {
    @Binding var selection: MainSidebarItem
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selection) {
            Section(appState.t("sidebar.categories")) {
                sidebarRow(.workspace, count: appState.jobs.count)
                sidebarRow(.newAudit)
                sidebarRow(.history, count: appState.jobs.count)
                sidebarRow(.reports, count: appState.reports.count)
            }

            Section(appState.t("sidebar.evidenceTypes")) {
                sidebarRow(.textEvidence, count: evidenceCount(.text))
                sidebarRow(.codeEvidence, count: evidenceCount(.code))
                sidebarRow(.imageEvidence, count: evidenceCount(.image))
                sidebarRow(.metadataEvidence, count: evidenceCount(.metadata))
                sidebarRow(.dedupEvidence, count: evidenceCount(.dedup))
                sidebarRow(.crossBatchEvidence, count: evidenceCount(.crossBatch))
            }

            Section(appState.t("sidebar.libraries")) {
                sidebarRow(.fingerprints, count: appState.fingerprints.count)
                sidebarRow(.whitelist, count: appState.whitelistRules.count)
            }

            Section {
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ item: MainSidebarItem, title: String? = nil, count: Int? = nil) -> some View {
        Label {
            HStack {
                Text(title ?? appState.title(for: item))
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, alignment: .trailing)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }

    private func evidenceCount(_ kind: ReportSectionKind) -> Int {
        appState.reports.reduce(0) { total, report in
            total + (report.displaySection(for: kind)?.table?.rows.count ?? 0)
        }
    }
}

private struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NativePage {
            NativePageHeader(
                title: appState.t("workspace.title"),
                subtitle: "\(appState.jobs.count) \(appState.t("status.audits")) · \(appState.reports.count) \(appState.t("status.reports")) · \(appState.fingerprints.count) \(appState.t("status.fingerprints"))",
                actions: {
                    Button {
                        Task { await appState.startAudit() }
                    } label: {
                        Label(appState.isRunningAudit ? appState.t("audit.running") : appState.t("command.startAudit"), systemImage: "play.fill")
                    }
                    .disabled(appState.isRunningAudit)

                    Button {
                        appState.showReportsCenter()
                    } label: {
                        Label(appState.t("workspace.reportCenter"), systemImage: "sidebar.right")
                    }
                }
            )

            SummaryStrip(items: [
                SummaryItem(title: appState.t("workspace.summary.jobs"), value: "\(appState.jobs.count)", systemImage: "clock.arrow.circlepath"),
                SummaryItem(title: appState.t("workspace.summary.reports"), value: "\(appState.reports.count)", systemImage: "doc.text"),
                SummaryItem(title: appState.t("workspace.summary.fingerprints"), value: "\(appState.fingerprints.count)", systemImage: "number"),
                SummaryItem(title: appState.t("workspace.summary.whitelist"), value: "\(appState.whitelistRules.count)", systemImage: "checkmark.shield")
            ])

            NativeSection(title: appState.t("workspace.recentJobs"), subtitle: "\(min(appState.jobs.count, 8)) \(appState.t("common.countSuffix"))") {
                VStack(spacing: 0) {
                    DenseHeader(columns: [appState.t("audit.directory"), appState.t("common.type"), "Progress", appState.t("common.updatedAt")])
                    ForEach(appState.jobs.prefix(8)) { job in
                        Button {
                            appState.selectedJobID = job.id
                            appState.selectedMainSidebar = .history
                        } label: {
                            JobTableRow(job: job)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }

            NativeSection(title: appState.t("workspace.recentReports"), subtitle: "\(min(appState.reports.count, 8)) \(appState.t("common.countSuffix"))") {
                VStack(spacing: 0) {
                    DenseHeader(columns: ["Title", appState.t("common.type"), appState.t("reports.sectionSummary"), appState.t("common.createdAt")])
                    ForEach(appState.reports.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8)) { report in
                        Button {
                            appState.showReport(report.id)
                        } label: {
                            AuditReportListRow(report: report)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct NewAuditView: View {
    @Environment(AppState.self) private var appState
    @State private var presetName = ""

    var body: some View {
        NativePage {
            NativePageHeader(
                title: appState.t("audit.title"),
                subtitle: appState.t("audit.subtitle"),
                actions: {
                    Button {
                        Task { await runAuditAndOpenReport() }
                    } label: {
                        Label(appState.isRunningAudit ? appState.t("audit.running") : appState.t("command.startAudit"), systemImage: "play.fill")
                    }
                    .disabled(appState.isRunningAudit)
                }
            )

            NativeSection(title: appState.t("audit.paths"), subtitle: appState.t("audit.paths.subtitle")) {
                VStack(spacing: 0) {
                    SettingsTextRow(title: appState.t("audit.directory"), text: Binding(
                        get: { appState.draftConfiguration.directoryPath },
                        set: { newValue in appState.updateDraft { $0.directoryPath = newValue } }
                    ))
                    Divider()
                    SettingsTextRow(title: appState.t("audit.outputDirectory"), text: Binding(
                        get: { appState.draftConfiguration.outputDirectoryPath },
                        set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                    ))
                    Divider()
                    SettingsTextRow(title: appState.t("audit.fileNameTemplate"), text: Binding(
                        get: { appState.draftConfiguration.reportNameTemplate },
                        set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
                    ))
                }
            }

            NativeSection(title: appState.t("audit.parameters"), subtitle: appState.t("audit.parameters.subtitle")) {
                VStack(spacing: 0) {
                    SettingsNumberRow(title: appState.t("audit.textThreshold"), value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsNumberRow(title: appState.t("audit.dedupThreshold"), value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsIntegerRow(title: appState.t("audit.imageThreshold"), value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ))
                    Divider()
                    SettingsIntegerRow(title: appState.t("audit.simhashThreshold"), value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ))
                    Divider()
                    HStack {
                        Text(appState.t("audit.visionOCR"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.draftConfiguration.useVisionOCR },
                            set: { newValue in appState.updateDraft { $0.useVisionOCR = newValue } }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 9)
                    Divider()
                    HStack {
                        Text(appState.t("audit.whitelistMode"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appState.draftConfiguration.whitelistMode },
                            set: { newValue in appState.updateDraft { $0.whitelistMode = newValue } }
                        )) {
                            ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                                Text(appState.title(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 9)
                }
            }

            NativeSection(title: appState.t("audit.preset"), subtitle: appState.t("audit.preset.subtitle")) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        TextField(appState.t("audit.presetName"), text: $presetName)
                            .textFieldStyle(.roundedBorder)
                        Button(appState.t("audit.saveCurrent")) {
                            let name = presetName
                            presetName = ""
                            appState.saveCurrentConfigurationPreset(named: name)
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 8)

                    if appState.configurationPresets.isEmpty {
                        Text(appState.t("audit.emptyPreset"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        Divider()
                        ForEach(appState.configurationPresets) { preset in
                            PresetTableRow(preset: preset)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func runAuditAndOpenReport() async {
        await appState.startAudit()
    }
}

private struct JobHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filteredJobs: [AuditJob] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.jobs }
        return appState.jobs.filter { job in
            [URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent, job.configuration.directoryPath, job.latestMessage, job.status.displayTitle]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(title: appState.t("sidebar.history"), count: filteredJobs.count, query: $query, prompt: appState.t("history.searchPrompt"))
            List(selection: Binding(get: { appState.selectedJobID }, set: { appState.selectedJobID = $0 })) {
                ForEach(filteredJobs) { job in
                    JobTableRow(job: job)
                        .tag(job.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct FingerprintLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filteredRecords: [FingerprintRecord] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.fingerprints }
        return appState.fingerprints.filter { record in
            [record.filename, record.ext, record.author, record.scanDir, record.simhash]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(title: appState.t("sidebar.fingerprints"), count: filteredRecords.count, query: $query, prompt: appState.t("fingerprints.searchPrompt"))
            List(filteredRecords) { record in
                FingerprintTableRow(record: record)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
        }
    }
}

private struct WhitelistLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var newPattern = ""
    @State private var newType: WhitelistRule.RuleType = .filename
    @State private var query = ""

    private var filteredRules: [WhitelistRule] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.whitelistRules }
        return appState.whitelistRules.filter { rule in
            [rule.pattern, rule.type.displayTitle].joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchHeader(title: appState.t("sidebar.whitelist"), count: filteredRules.count, query: $query, prompt: appState.t("whitelist.searchPrompt"))
            HStack(spacing: 10) {
                Picker(appState.t("whitelist.type"), selection: $newType) {
                    ForEach(WhitelistRule.RuleType.allCases, id: \.self) { type in
                        Text(appState.title(for: type)).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                TextField(appState.t("whitelist.newRule"), text: $newPattern)
                    .textFieldStyle(.roundedBorder)

                Button(appState.t("whitelist.save")) {
                    let pattern = newPattern
                    newPattern = ""
                    Task { await appState.addWhitelistRule(pattern: pattern, type: newType) }
                }
                .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            List(filteredRules) { rule in
                WhitelistTableRow(rule: rule)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
        }
    }
}

private struct JobInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let job = appState.selectedJob {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                                    .font(.title2.weight(.semibold))
                                Text(job.configuration.directoryPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            StatusBadge(status: job.status)
                        }

                        Button {
                            appState.restoreDraft(from: job)
                        } label: {
                            Label(appState.t("job.restoreParameters"), systemImage: "arrow.counterclockwise")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(job.latestMessage)
                                Spacer()
                                Text("\(job.progress)%")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            ProgressView(value: Double(job.progress), total: 100)
                        }
                    }

                    InspectorSection(title: appState.t("job.timeline"), subtitle: "\(job.events.count) \(appState.t("common.countSuffix"))") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(job.events.reversed())) { event in
                                TimelineEventRow(event: event)
                                Divider()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView(appState.t("job.noSelection"), systemImage: "clock.badge.questionmark", description: Text(appState.t("job.noSelectionDescription")))
        }
    }
}

private struct PresetTableRow: View {
    @Environment(AppState.self) private var appState
    let preset: AuditConfigurationPreset

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .fontWeight(.medium)
                Text(URL(fileURLWithPath: preset.configuration.directoryPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(appState.t("audit.applyPreset")) { appState.applyPreset(preset) }
            Button(appState.t("audit.runPreset")) {
                Task {
                    await appState.startAudit(using: preset)
                }
            }
                .disabled(appState.isRunningAudit)
            Button(role: .destructive) {
                appState.deletePreset(preset)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }
}

private struct JobTableRow: View {
    let job: AuditJob

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: job.status)
            Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(status: job.status)
                .frame(width: 74, alignment: .trailing)
            Text("\(job.progress)%")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 7)
    }
}

private struct AuditReportListRow: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        HStack(spacing: 12) {
            Text(report.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if report.isLegacy {
                PillLabel(title: "Legacy", tint: .orange)
                    .frame(width: 74, alignment: .trailing)
            } else {
                Text(appState.t("common.native"))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }
            Text("\(report.sections.count)")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 7)
    }
}

private struct FingerprintTableRow: View {
    let record: FingerprintRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(record.filename)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.ext.uppercased())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(record.scanDir)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(record.simhash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 7)
    }
}

private struct WhitelistTableRow: View {
    @Environment(AppState.self) private var appState
    let rule: WhitelistRule

    var body: some View {
        HStack(spacing: 12) {
            Text(rule.pattern)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.title(for: rule.type))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(rule.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)
            Button(role: .destructive) {
                Task { await appState.removeWhitelistRule(rule) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .font(.subheadline)
        .padding(.vertical, 7)
    }
}

private struct TimelineEventRow: View {
    let event: AuditJobEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.subheadline)
                Text("\(event.progress)% · \(event.timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

private struct NativePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct NativePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                actions
            }
        }
    }
}

private struct NativeSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(Rectangle().stroke(.separator.opacity(0.25)))
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

private struct SearchHeader: View {
    @Environment(AppState.self) private var appState
    let title: String
    let count: Int
    @Binding var query: String
    let prompt: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\(count) \(appState.t("common.countSuffix"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(prompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DenseHeader: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: index == 0 ? .leading : .trailing)
                    .frame(width: index == 0 ? nil : (index == 1 ? 74 : index == 2 ? 54 : 128), alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

private struct SummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

private struct SummaryStrip: View {
    let items: [SummaryItem]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items) { item in
                Label {
                    Text("\(item.value) \(item.title)")
                } icon: {
                    Image(systemName: item.systemImage)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.subheadline)
    }
}

private struct SettingsTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 96, alignment: .leading)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsNumberRow<F: ParseableFormatStyle>: View where F.FormatInput == Double, F.FormatOutput == String {
    let title: String
    @Binding var value: Double
    let format: F

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: format)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
        .padding(.vertical, 8)
    }
}

private struct SettingsIntegerRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
        .padding(.vertical, 8)
    }
}

private struct StatusDot: View {
    let status: AuditJobStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .queued: return .secondary.opacity(0.5)
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

private struct PillLabel: View {
    let title: String
    var tint: Color = .secondary

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

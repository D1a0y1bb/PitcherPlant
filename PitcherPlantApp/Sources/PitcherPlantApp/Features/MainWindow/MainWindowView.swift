import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            MainSidebarView(selection: $state.selectedMainSidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            Group {
                switch appState.selectedMainSidebar {
                case .workspace:
                    WorkspaceDashboardView()
                case .newAudit:
                    NewAuditView()
                case .history:
                    JobHistoryView()
                case .fingerprints:
                    FingerprintLibraryView()
                case .whitelist:
                    WhitelistLibraryView()
                case .settings:
                    SettingsRootView()
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 680, max: .infinity)
        } detail: {
            JobInspectorView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await appState.startAudit() }
                } label: {
                    Label("开始审计", systemImage: "play.fill")
                }
                .disabled(appState.isRunningAudit)

                Button {
                    Task { await appState.startAudit() }
                } label: {
                    Label("重新运行", systemImage: "arrow.clockwise")
                }

                Button {
                    appState.openLatestReportInFinder()
                } label: {
                    Label("打开输出目录", systemImage: "folder")
                }

                Button {
                    openWindow(id: AppWindow.reports.rawValue)
                } label: {
                    Label("打开报告中心", systemImage: "sidebar.right")
                }
            }
        }
    }
}

private struct MainSidebarView: View {
    @Binding var selection: MainSidebarItem

    var body: some View {
        List(selection: $selection) {
            ForEach(MainSidebarItem.allCases) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PitcherPlant")
                        .font(.system(size: 30, weight: .semibold))
                    Text("原生 macOS 审计工作台")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    MetricCard(metric: ReportMetric(title: "历史任务", value: "\(appState.jobs.count)", systemImage: "clock"))
                    MetricCard(metric: ReportMetric(title: "报告数量", value: "\(appState.reports.count)", systemImage: "doc.text"))
                    MetricCard(metric: ReportMetric(title: "指纹记录", value: "\(appState.fingerprints.count)", systemImage: "server.rack"))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近报告")
                        .font(.headline)
                    if let report = appState.latestReport {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(report.title)
                                    .font(.title3.weight(.semibold))
                                if report.isLegacy {
                                    Text("Legacy")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(report.scanDirectoryPath)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack(spacing: 10) {
                                Button {
                                    appState.selectLatestReport()
                                    openWindow(id: AppWindow.reports.rawValue)
                                } label: {
                                    Label("打开最近报告", systemImage: "doc.text.magnifyingglass")
                                }
                                .keyboardShortcut("r", modifiers: [.command, .option])

                                Button {
                                    appState.openLatestReportInFinder()
                                } label: {
                                    Label("在 Finder 显示", systemImage: "folder")
                                }
                            }
                            HStack {
                                ForEach(report.metrics, id: \.title) { metric in
                                    MetricCard(metric: metric)
                                }
                            }
                        }
                        .padding(18)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ContentUnavailableView("暂无报告", systemImage: "doc.badge.plus", description: Text("完成一次原生审计后会在这里显示最近结果。"))
                    }
                }

                if let migration = appState.lastMigrationSummary, migration.importedJobs + migration.importedReports + migration.importedFingerprints > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("迁移摘要")
                            .font(.headline)
                        Text("已导入旧任务 \(migration.importedJobs) 条，旧报告 \(migration.importedReports) 份，历史指纹 \(migration.importedFingerprints) 条，白名单 \(migration.importedWhitelistRules) 条。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(24)
        }
    }
}

private struct NewAuditView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("路径") {
                TextField("审计目录", text: Binding(
                    get: { appState.draftConfiguration.directoryPath },
                    set: { newValue in appState.updateDraft { $0.directoryPath = newValue } }
                ))
                TextField("报告目录", text: Binding(
                    get: { appState.draftConfiguration.outputDirectoryPath },
                    set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                ))
                TextField("报告文件名模板", text: Binding(
                    get: { appState.draftConfiguration.reportNameTemplate },
                    set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
                ))
            }

            Section("阈值") {
                HStack {
                    Text("文本阈值")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    .frame(width: 90)
                }
                HStack {
                    Text("图片阈值")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ), format: .number)
                    .frame(width: 90)
                }
                HStack {
                    Text("重复阈值")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    .frame(width: 90)
                }
                HStack {
                    Text("SimHash 位差")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ), format: .number)
                    .frame(width: 90)
                }
                Toggle("启用 Vision OCR", isOn: Binding(
                    get: { appState.draftConfiguration.useVisionOCR },
                    set: { newValue in appState.updateDraft { $0.useVisionOCR = newValue } }
                ))
                Picker("白名单模式", selection: Binding(
                    get: { appState.draftConfiguration.whitelistMode },
                    set: { newValue in appState.updateDraft { $0.whitelistMode = newValue } }
                )) {
                    ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
            }

            Section {
                Button {
                    Task { await appState.startAudit() }
                } label: {
                    Label(appState.isRunningAudit ? "正在运行" : "开始审计", systemImage: "play.fill")
                }
                .disabled(appState.isRunningAudit)
            }
        }
        .formStyle(.grouped)
    }
}

private struct JobHistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedJobID },
            set: { appState.selectedJobID = $0 }
        )) {
            ForEach(appState.jobs) { job in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                            .fontWeight(.medium)
                        Text(job.latestMessage)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusBadge(status: job.status)
                }
                .tag(job.id)
            }
        }
    }
}

private struct FingerprintLibraryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(appState.fingerprints) { record in
            VStack(alignment: .leading, spacing: 4) {
                Text(record.filename).fontWeight(.medium)
                Text("\(record.scanDir) · \(record.simhash)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct WhitelistLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var newPattern = ""
    @State private var newType: WhitelistRule.RuleType = .filename

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("类型", selection: $newType) {
                    ForEach(WhitelistRule.RuleType.allCases, id: \.self) { type in
                        Text(type.displayTitle).tag(type)
                    }
                }
                TextField("新增规则", text: $newPattern)
                Button("保存") {
                    let pattern = newPattern
                    newPattern = ""
                    Task { await appState.addWhitelistRule(pattern: pattern, type: newType) }
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))

            List(appState.whitelistRules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.pattern).fontWeight(.medium)
                        Text(rule.type.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await appState.removeWhitelistRule(rule) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

private struct JobInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let job = appState.selectedJob {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                                .font(.title3.weight(.semibold))
                            Spacer()
                            StatusBadge(status: job.status)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(job.latestMessage)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(job.progress), total: 100)
                            Text("\(job.progress)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("执行时间线")
                            .font(.headline)
                        ForEach(Array(job.events.reversed())) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.message)
                                Text("\(event.progress)% · \(event.timestamp.formatted(date: .abbreviated, time: .standard))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView("未选择任务", systemImage: "clock.badge.questionmark", description: Text("左侧选择一个历史任务查看详情。"))
            }
        }
    }
}

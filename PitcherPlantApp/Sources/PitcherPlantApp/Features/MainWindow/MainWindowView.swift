import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            MainSidebarView(selection: $state.selectedMainSidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } content: {
            mainContent
                .navigationSplitViewColumnWidth(min: 560, ideal: 760, max: .infinity)
        } detail: {
            JobInspectorView()
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    appState.selectedMainSidebar = .workspace
                } label: {
                    Label("工作台", systemImage: "square.grid.2x2")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await runAuditAndOpenReport() }
                } label: {
                    Label("开始", systemImage: "play.fill")
                }
                .disabled(appState.isRunningAudit)

                Button {
                    Task { await runAuditAndOpenReport() }
                } label: {
                    Label("重跑", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRunningAudit)

                Button {
                    appState.openLatestReportInFinder()
                } label: {
                    Label("输出", systemImage: "folder")
                }

                Button {
                    openWindow(id: AppWindow.reports.rawValue)
                } label: {
                    Label("报告中心", systemImage: "sidebar.right")
                }
            }
        }
    }

    private func runAuditAndOpenReport() async {
        if await appState.startAudit() != nil {
            openWindow(id: AppWindow.reports.rawValue)
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
        case .fingerprints:
            FingerprintLibraryView()
        case .whitelist:
            WhitelistLibraryView()
        case .settings:
            SettingsRootView()
        }
    }
}

private struct MainSidebarView: View {
    @Binding var selection: MainSidebarItem
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selection) {
            Section("审计") {
                sidebarRow(.workspace, count: appState.jobs.count)
                sidebarRow(.newAudit)
                sidebarRow(.history, count: appState.jobs.count)
            }

            Section("资产") {
                sidebarRow(.fingerprints, count: appState.fingerprints.count)
                sidebarRow(.whitelist, count: appState.whitelistRules.count)
            }

            Section {
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(systemName: "leaf")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PitcherPlant")
                        .font(.headline)
                    Text("WriteUP 审计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func sidebarRow(_ item: MainSidebarItem, count: Int? = nil) -> some View {
        Label {
            HStack {
                Text(item.title)
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
}

private struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NativePage {
            NativePageHeader(
                title: "工作台",
                subtitle: "\(appState.jobs.count) 个任务 · \(appState.reports.count) 份报告 · \(appState.fingerprints.count) 条指纹",
                actions: {
                    Button {
                        Task { await appState.startAudit() }
                    } label: {
                        Label(appState.isRunningAudit ? "运行中" : "开始审计", systemImage: "play.fill")
                    }
                    .disabled(appState.isRunningAudit)

                    Button {
                        openWindow(id: AppWindow.reports.rawValue)
                    } label: {
                        Label("报告中心", systemImage: "sidebar.right")
                    }
                }
            )

            SummaryStrip(items: [
                SummaryItem(title: "历史任务", value: "\(appState.jobs.count)", systemImage: "clock.arrow.circlepath"),
                SummaryItem(title: "报告", value: "\(appState.reports.count)", systemImage: "doc.text"),
                SummaryItem(title: "指纹", value: "\(appState.fingerprints.count)", systemImage: "number"),
                SummaryItem(title: "白名单", value: "\(appState.whitelistRules.count)", systemImage: "checkmark.shield")
            ])

            NativeSection(title: "最近任务", subtitle: "最近 \(min(appState.jobs.count, 8)) 条") {
                VStack(spacing: 0) {
                    DenseHeader(columns: ["目录", "状态", "进度", "更新时间"])
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

            NativeSection(title: "最近报告", subtitle: "最近 \(min(appState.reports.count, 8)) 份") {
                VStack(spacing: 0) {
                    DenseHeader(columns: ["标题", "类型", "章节", "时间"])
                    ForEach(appState.reports.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8)) { report in
                        Button {
                            appState.selectReport(report.id)
                            openWindow(id: AppWindow.reports.rawValue)
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
    @Environment(\.openWindow) private var openWindow
    @State private var presetName = ""

    var body: some View {
        NativePage {
            NativePageHeader(
                title: "新建审计",
                subtitle: "配置目录、阈值、OCR 和白名单策略",
                actions: {
                    Button {
                        Task { await runAuditAndOpenReport() }
                    } label: {
                        Label(appState.isRunningAudit ? "运行中" : "开始审计", systemImage: "play.fill")
                    }
                    .disabled(appState.isRunningAudit)
                }
            )

            NativeSection(title: "路径", subtitle: "输入审计目录和报告输出位置") {
                VStack(spacing: 0) {
                    SettingsTextRow(title: "审计目录", text: Binding(
                        get: { appState.draftConfiguration.directoryPath },
                        set: { newValue in appState.updateDraft { $0.directoryPath = newValue } }
                    ))
                    Divider()
                    SettingsTextRow(title: "报告目录", text: Binding(
                        get: { appState.draftConfiguration.outputDirectoryPath },
                        set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                    ))
                    Divider()
                    SettingsTextRow(title: "文件名模板", text: Binding(
                        get: { appState.draftConfiguration.reportNameTemplate },
                        set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
                    ))
                }
            }

            NativeSection(title: "检测参数", subtitle: "控制相似度、复用和跨批次阈值") {
                VStack(spacing: 0) {
                    SettingsNumberRow(title: "文本阈值", value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsNumberRow(title: "重复阈值", value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsIntegerRow(title: "图片阈值", value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ))
                    Divider()
                    SettingsIntegerRow(title: "SimHash 位差", value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ))
                    Divider()
                    HStack {
                        Text("Vision OCR")
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
                        Text("白名单模式")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { appState.draftConfiguration.whitelistMode },
                            set: { newValue in appState.updateDraft { $0.whitelistMode = newValue } }
                        )) {
                            ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                                Text(mode.displayTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 9)
                }
            }

            NativeSection(title: "参数预设", subtitle: "保存常用目录和阈值组合") {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        TextField("预设名称", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                        Button("保存当前") {
                            let name = presetName
                            presetName = ""
                            appState.saveCurrentConfigurationPreset(named: name)
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 8)

                    if appState.configurationPresets.isEmpty {
                        Text("保存一套常用参数后，可在这里直接套用或运行。")
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
        if await appState.startAudit() != nil {
            openWindow(id: AppWindow.reports.rawValue)
        }
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
            SearchHeader(title: "历史任务", count: filteredJobs.count, query: $query, prompt: "搜索任务、路径、状态")
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
            SearchHeader(title: "指纹库", count: filteredRecords.count, query: $query, prompt: "搜索文件、作者、SimHash")
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
            SearchHeader(title: "白名单", count: filteredRules.count, query: $query, prompt: "搜索规则")
            HStack(spacing: 10) {
                Picker("类型", selection: $newType) {
                    ForEach(WhitelistRule.RuleType.allCases, id: \.self) { type in
                        Text(type.displayTitle).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                TextField("新增规则", text: $newPattern)
                    .textFieldStyle(.roundedBorder)

                Button("保存") {
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
                            Label("恢复参数", systemImage: "arrow.counterclockwise")
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

                    InspectorSection(title: "执行时间线", subtitle: "最近 \(job.events.count) 条事件") {
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
            ContentUnavailableView("未选择任务", systemImage: "clock.badge.questionmark", description: Text("在历史任务中选择一项后查看详情。"))
        }
    }
}

private struct PresetTableRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
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
            Button("套用") { appState.applyPreset(preset) }
            Button("运行") {
                Task {
                    if await appState.startAudit(using: preset) != nil {
                        openWindow(id: AppWindow.reports.rawValue)
                    }
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
                Text("原生")
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
            Text(rule.type.displayTitle)
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
    let title: String
    let count: Int
    @Binding var query: String
    let prompt: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\(count) 条")
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

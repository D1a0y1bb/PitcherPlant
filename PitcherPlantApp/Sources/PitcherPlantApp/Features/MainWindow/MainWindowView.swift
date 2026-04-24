import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            MainSidebarView(selection: $state.selectedMainSidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } content: {
            mainContent
                .navigationSplitViewColumnWidth(min: 520, ideal: 760, max: .infinity)
        } detail: {
            JobInspectorView()
                .navigationSplitViewColumnWidth(min: 330, ideal: 380, max: 460)
        }
        .navigationSplitViewStyle(.balanced)
        .background(PitcherPlantSurfaceBackground())
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
                    Task { await appState.startAudit() }
                } label: {
                    Label("开始", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(PitcherPlantTheme.accent)
                .disabled(appState.isRunningAudit)

                Button {
                    Task { await appState.startAudit() }
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
                .background(PitcherPlantSurfaceBackground())
        }
    }
}

private struct MainSidebarView: View {
    @Binding var selection: MainSidebarItem

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PitcherPlantTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PitcherPlant")
                            .font(.headline.weight(.semibold))
                        Text("WriteUP 审计")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            List(selection: $selection) {
                Section("审计") {
                    SidebarRow(item: .workspace).tag(MainSidebarItem.workspace)
                    SidebarRow(item: .newAudit).tag(MainSidebarItem.newAudit)
                    SidebarRow(item: .history).tag(MainSidebarItem.history)
                }
                Section("资产") {
                    SidebarRow(item: .fingerprints).tag(MainSidebarItem.fingerprints)
                    SidebarRow(item: .whitelist).tag(MainSidebarItem.whitelist)
                }
                Section("系统") {
                    SidebarRow(item: .settings).tag(MainSidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct SidebarRow: View {
    let item: MainSidebarItem

    var body: some View {
        Label(item.title, systemImage: item.systemImage)
            .font(.system(size: 13.5, weight: .medium))
    }
}

private struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ThemedScrollView {
            HeaderHero(
                eyebrow: "Native macOS Audit Console",
                title: "让 WriteUP 审计像系统工具一样轻快",
                subtitle: "整合文本相似、代码复用、图片复用、元数据碰撞、跨批次指纹和白名单策略。",
                primaryTitle: appState.isRunningAudit ? "正在审计" : "开始审计",
                primaryIcon: "play.fill",
                primaryAction: { Task { await appState.startAudit() } },
                secondaryTitle: "报告中心",
                secondaryIcon: "sidebar.right",
                secondaryAction: { openWindow(id: AppWindow.reports.rawValue) },
                primaryDisabled: appState.isRunningAudit
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                DashboardMetricCard(title: "历史任务", value: "\(appState.jobs.count)", symbol: "clock.arrow.circlepath", tone: .green)
                DashboardMetricCard(title: "报告数量", value: "\(appState.reports.count)", symbol: "doc.text.magnifyingglass", tone: .blue)
                DashboardMetricCard(title: "指纹记录", value: "\(appState.fingerprints.count)", symbol: "server.rack", tone: .teal)
            }

            if let report = appState.latestReport {
                GlassSection(title: "最近报告", subtitle: report.scanDirectoryPath, symbol: "doc.richtext") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(report.title)
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(1)
                                    if report.isLegacy {
                                        PillLabel("Legacy", systemImage: "clock.arrow.circlepath", tint: .orange)
                                    }
                                }
                                Text(report.sourcePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button {
                                appState.selectLatestReport()
                                openWindow(id: AppWindow.reports.rawValue)
                            } label: {
                                Label("打开", systemImage: "arrow.up.forward.app")
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(report.metrics.prefix(6), id: \.title) { metric in
                                MiniMetric(metric: metric)
                            }
                        }
                    }
                }
            } else {
                EmptyGlassState(title: "暂无报告", symbol: "doc.badge.plus", message: "完成一次原生审计后，最近报告和核心指标会显示在这里。")
            }

            if let migration = appState.lastMigrationSummary, migration.importedJobs + migration.importedReports + migration.importedFingerprints > 0 {
                GlassSection(title: "迁移摘要", subtitle: "旧数据已进入 macOS 主线", symbol: "arrow.triangle.2.circlepath") {
                    HStack(spacing: 10) {
                        MiniCount(title: "任务", value: migration.importedJobs)
                        MiniCount(title: "报告", value: migration.importedReports)
                        MiniCount(title: "指纹", value: migration.importedFingerprints)
                        MiniCount(title: "白名单", value: migration.importedWhitelistRules)
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
        ThemedScrollView {
            HeaderHero(
                eyebrow: "Audit Configuration",
                title: "配置一次审计任务",
                subtitle: "保留 Python 版核心参数，使用 Swift 原生解析和报告导出链路执行。",
                primaryTitle: appState.isRunningAudit ? "正在运行" : "开始审计",
                primaryIcon: "play.fill",
                primaryAction: { Task { await appState.startAudit() } },
                secondaryTitle: "保存预设",
                secondaryIcon: "tray.and.arrow.down",
                secondaryAction: {
                    let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    presetName = ""
                    appState.saveCurrentConfigurationPreset(named: name)
                },
                primaryDisabled: appState.isRunningAudit,
                secondaryDisabled: presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            GlassSection(title: "路径", subtitle: "输入审计目录和报告输出位置", symbol: "folder") {
                VStack(spacing: 12) {
                    ConfigTextField(title: "审计目录", symbol: "folder.badge.questionmark", text: Binding(
                        get: { appState.draftConfiguration.directoryPath },
                        set: { newValue in appState.updateDraft { $0.directoryPath = newValue } }
                    ))
                    ConfigTextField(title: "报告目录", symbol: "folder.badge.plus", text: Binding(
                        get: { appState.draftConfiguration.outputDirectoryPath },
                        set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                    ))
                    ConfigTextField(title: "文件名模板", symbol: "doc.text", text: Binding(
                        get: { appState.draftConfiguration.reportNameTemplate },
                        set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
                    ))
                }
            }

            GlassSection(title: "检测参数", subtitle: "控制相似度、图片复用和跨批次匹配阈值", symbol: "slider.horizontal.3") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    NumberSetting(title: "文本阈值", value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    NumberSetting(title: "重复阈值", value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    IntegerSetting(title: "图片阈值", value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ))
                    IntegerSetting(title: "SimHash 位差", value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ))
                }
                Divider().opacity(0.5)
                HStack(spacing: 18) {
                    Toggle("Vision OCR", isOn: Binding(
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
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Spacer()
                }
            }

            GlassSection(title: "参数预设", subtitle: "保存常用目录和阈值组合", symbol: "bookmark") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RoundedSearchField(text: $presetName, placeholder: "预设名称", systemImage: "text.badge.plus")
                        Button("保存当前") {
                            let name = presetName
                            presetName = ""
                            appState.saveCurrentConfigurationPreset(named: name)
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if appState.configurationPresets.isEmpty {
                        EmptyInlineState("保存一套常用参数后，可在这里直接套用或运行。")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.configurationPresets) { preset in
                                PresetRow(preset: preset)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct JobHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filteredJobs: [AuditJob] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return appState.jobs }
        return appState.jobs.filter { job in
            let haystack = [
                URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent,
                job.configuration.directoryPath,
                job.latestMessage,
                job.status.displayTitle
            ].joined(separator: " ").localizedLowercase
            return haystack.contains(query.localizedLowercase)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "历史任务", subtitle: "\(filteredJobs.count) 个任务", query: $query, placeholder: "搜索任务、路径、状态")
            List(selection: Binding(
                get: { appState.selectedJobID },
                set: { appState.selectedJobID = $0 }
            )) {
                ForEach(filteredJobs) { job in
                    JobRow(job: job)
                        .tag(job.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(PitcherPlantSurfaceBackground())
    }
}

private struct FingerprintLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filteredRecords: [FingerprintRecord] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return appState.fingerprints }
        return appState.fingerprints.filter { record in
            [record.filename, record.ext, record.author, record.scanDir, record.simhash]
                .joined(separator: " ")
                .localizedLowercase
                .contains(query.localizedLowercase)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "指纹库", subtitle: "\(filteredRecords.count) 条记录", query: $query, placeholder: "搜索文件、作者、SimHash")
            List(filteredRecords) { record in
                FingerprintRow(record: record)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(PitcherPlantSurfaceBackground())
    }
}

private struct WhitelistLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var newPattern = ""
    @State private var newType: WhitelistRule.RuleType = .filename
    @State private var query = ""

    private var filteredRules: [WhitelistRule] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return appState.whitelistRules }
        return appState.whitelistRules.filter { rule in
            [rule.pattern, rule.type.displayTitle].joined(separator: " ").localizedLowercase.contains(query.localizedLowercase)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(title: "白名单", subtitle: "\(filteredRules.count) 条规则", query: $query, placeholder: "搜索规则")

            GlassCard {
                HStack(spacing: 12) {
                    Picker("类型", selection: $newType) {
                        ForEach(WhitelistRule.RuleType.allCases, id: \.self) { type in
                            Text(type.displayTitle).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)

                    RoundedSearchField(text: $newPattern, placeholder: "新增规则", systemImage: "plus.circle")
                    Button("保存") {
                        let pattern = newPattern
                        newPattern = ""
                        Task { await appState.addWhitelistRule(pattern: pattern, type: newType) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PitcherPlantTheme.accent)
                    .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            List(filteredRules) { rule in
                WhitelistRow(rule: rule)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(PitcherPlantSurfaceBackground())
    }
}

private struct JobInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let job = appState.selectedJob {
                ThemedScrollView(horizontalPadding: 18, verticalPadding: 18) {
                    GlassCard(spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                Text(job.configuration.directoryPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            StatusBadge(status: job.status)
                        }

                        HStack(spacing: 10) {
                            Button {
                                appState.restoreDraft(from: job)
                            } label: {
                                Label("恢复参数", systemImage: "arrow.counterclockwise")
                            }
                            if job.reportID != nil {
                                Button {
                                    if let reportID = job.reportID {
                                        appState.selectedReportID = reportID
                                    }
                                } label: {
                                    Label("定位报告", systemImage: "doc.text.magnifyingglass")
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(job.latestMessage)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(job.progress)%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PitcherPlantTheme.accent)
                            }
                            ProgressView(value: Double(job.progress), total: 100)
                                .tint(PitcherPlantTheme.accent)
                        }
                    }

                    GlassSection(title: "执行时间线", subtitle: "最近 \(job.events.count) 条事件", symbol: "timeline.selection") {
                        VStack(spacing: 10) {
                            ForEach(Array(job.events.reversed())) { event in
                                TimelineEventRow(event: event)
                            }
                        }
                    }
                }
            } else {
                EmptyGlassState(title: "未选择任务", symbol: "clock.badge.questionmark", message: "在历史任务中选择一项后，这里会显示进度、参数和执行时间线。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PitcherPlantSurfaceBackground())
            }
        }
    }
}

private struct PresetRow: View {
    @Environment(AppState.self) private var appState
    let preset: AuditConfigurationPreset

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: "bookmark.fill", tint: .teal)
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .fontWeight(.medium)
                Text("\(URL(fileURLWithPath: preset.configuration.directoryPath).lastPathComponent) · 文本 \(preset.configuration.textThreshold.formatted(.number.precision(.fractionLength(2)))) · 图片 \(preset.configuration.imageThreshold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("套用") { appState.applyPreset(preset) }
            Button("运行") { Task { await appState.startAudit(using: preset) } }
                .disabled(appState.isRunningAudit)
            Button(role: .destructive) {
                appState.deletePreset(preset)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct JobRow: View {
    let job: AuditJob

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: job.status)
            VStack(alignment: .leading, spacing: 5) {
                Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(job.latestMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                StatusBadge(status: job.status)
                Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

private struct FingerprintRow: View {
    let record: FingerprintRecord

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: "number.square.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.filename)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(record.scanDir) · \(record.simhash)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if !record.ext.isEmpty {
                PillLabel(record.ext.uppercased(), systemImage: "doc", tint: .blue)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

private struct WhitelistRow: View {
    @Environment(AppState.self) private var appState
    let rule: WhitelistRule

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: "checkmark.shield.fill", tint: .green)
            VStack(alignment: .leading, spacing: 5) {
                Text(rule.pattern)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(rule.type.displayTitle) · \(rule.createdAt.formatted(date: .abbreviated, time: .shortened))")
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
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

private struct TimelineEventRow: View {
    let event: AuditJobEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(PitcherPlantTheme.accent)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 1, height: 30)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(event.message)
                    .font(.subheadline.weight(.medium))
                Text("\(event.progress)% · \(event.timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ListHeader: View {
    let title: String
    let subtitle: String
    @Binding var query: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RoundedSearchField(text: $query, placeholder: placeholder, systemImage: "magnifyingglass")
                    .frame(width: 280)
            }
        }
        .padding(18)
        .background(.regularMaterial)
    }
}

private struct HeaderHero: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let primaryTitle: String
    let primaryIcon: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryIcon: String
    let secondaryAction: () -> Void
    var primaryDisabled = false
    var secondaryDisabled = false

    var body: some View {
        GlassCard(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [PitcherPlantTheme.accent.opacity(0.96), .mint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PitcherPlantTheme.accent)
                    Text(title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Button(action: primaryAction) {
                            Label(primaryTitle, systemImage: primaryIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PitcherPlantTheme.accent)
                        .disabled(primaryDisabled)

                        Button(action: secondaryAction) {
                            Label(secondaryTitle, systemImage: secondaryIcon)
                        }
                        .disabled(secondaryDisabled)
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }
}

private struct GlassSection<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(spacing: 16) {
            HStack(spacing: 12) {
                IconBubble(systemImage: symbol, tint: PitcherPlantTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            content
        }
    }
}

private struct ThemedScrollView<Content: View>: View {
    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(PitcherPlantSurfaceBackground())
        .scrollContentBackground(.hidden)
    }
}

private struct PitcherPlantSurfaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PitcherPlantTheme.accent.opacity(0.10),
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.mint.opacity(0.16), .clear], center: .topLeading, startRadius: 20, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

private struct GlassCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct RoundedSearchField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

private struct ConfigTextField: View {
    let title: String
    let symbol: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: symbol, tint: .teal)
            Text(title)
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct NumberSetting<F: ParseableFormatStyle>: View where F.FormatInput == Double, F.FormatOutput == String {
    let title: String
    @Binding var value: Double
    let format: F

    var body: some View {
        SettingField(title: title) {
            TextField("", value: $value, format: format)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
    }
}

private struct IntegerSetting: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        SettingField(title: title) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
    }
}

private struct SettingField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            content
        }
        .padding(12)
        .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: Color

    var body: some View {
        GlassCard(spacing: 10) {
            HStack {
                IconBubble(systemImage: symbol, tint: tone)
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MiniMetric: View {
    let metric: ReportMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(metric.value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MiniCount: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct IconBubble: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct StatusDot: View {
    let status: AuditJobStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.45), radius: 6)
    }

    private var color: Color {
        switch status {
        case .queued: return .secondary
        case .running: return PitcherPlantTheme.accent
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

private struct PillLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct EmptyGlassState: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        GlassCard {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message))
                .frame(maxWidth: .infinity, minHeight: 180)
        }
        .padding(22)
    }
}

private struct EmptyInlineState: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

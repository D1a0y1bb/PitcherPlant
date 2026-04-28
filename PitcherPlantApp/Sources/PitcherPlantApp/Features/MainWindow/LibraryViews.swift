import SwiftUI
import AppKit

struct JobHistoryView: View {
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
        VStack(spacing: 14) {
            SearchHeader(title: appState.t("sidebar.history"), count: filteredJobs.count, query: $query, prompt: appState.t("history.searchPrompt"))

            AppTablePanel {
                Table(filteredJobs, selection: Binding(get: { appState.selectedJobID }, set: { appState.selectedJobID = $0 })) {
                    TableColumn(appState.t("audit.directory")) { job in
                        Label(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent, systemImage: job.status.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn(appState.t("common.type")) { job in
                        Text(job.status.displayTitle)
                            .foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn("Progress") { job in
                        Text("\(job.progress)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(76)
                    TableColumn(appState.t("common.updatedAt")) { job in
                        Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 150, ideal: 180)
                }
                .frame(height: nativeTableHeight(rowCount: filteredJobs.count, maxHeight: 520))
            }
        }
        .padding(AppLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FingerprintLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var cleanupTag = ""
    @State private var importTags = ""
    @State private var exportTags = ""

    private var filteredRecords: [FingerprintRecord] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.fingerprints }
        return appState.fingerprints.filter { record in
            [record.filename, record.ext, record.author, record.scanDir, record.simhash, record.batchName ?? "", record.challengeName ?? "", record.teamName ?? "", (record.tags ?? []).joined(separator: " ")]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchHeader(title: appState.t("sidebar.fingerprints"), count: filteredRecords.count, query: $query, prompt: appState.t("fingerprints.searchPrompt"))

            FingerprintActionsView(
                importTags: $importTags,
                exportTags: $exportTags,
                cleanupTag: $cleanupTag,
                cleanupMatchCount: cleanupMatchCount,
                filteredRecords: filteredRecords,
                parsedTags: parsedTags,
                cleanup: confirmAndDeleteFingerprints
            )

            VStack(alignment: .leading, spacing: 6) {
                FingerprintListHeader()
                List(filteredRecords) { record in
                    FingerprintLibraryRow(
                        record: record,
                        context: fingerprintContext(record)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listStyle(.plain)
                .frame(height: nativeTableHeight(rowCount: filteredRecords.count, minHeight: 260, maxHeight: 620))
            }
        }
        .padding(AppLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cleanupMatchCount: Int {
        let tag = cleanupTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.isEmpty == false else { return 0 }
        return appState.fingerprints.filter { record in
            record.tags?.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) == true
        }.count
    }

    private func parsedTags(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func fingerprintContext(_ record: FingerprintRecord) -> String {
        let values = [record.batchName, record.challengeName, record.teamName].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.isEmpty == false }
        return values.isEmpty ? "未标注" : values.joined(separator: " / ")
    }

    private func confirmAndDeleteFingerprints(tag: String, matchCount: Int) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, matchCount > 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认清理指纹标签"
        alert.informativeText = "标签 \(trimmed) 当前命中 \(matchCount) 条指纹。清理后会从本地指纹库移除这些记录。"
        alert.addButton(withTitle: "清理")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cleanupTag = ""
        Task { await appState.deleteFingerprints(tag: trimmed) }
    }
}

private struct FingerprintListHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("文件")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("类型")
                .frame(width: 70, alignment: .leading)
            Text("批次 / 队伍")
                .frame(width: 180, alignment: .leading)
            Text("SimHash")
                .frame(width: 170, alignment: .leading)
            Text("标签")
                .frame(width: 150, alignment: .leading)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

private struct FingerprintLibraryRow: View {
    let record: FingerprintRecord
    let context: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.filename)
                    .font(AppTypography.rowPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.scanDir)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.ext.uppercased())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(context)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 180, alignment: .leading)

            Text(record.simhash)
                .font(AppTypography.smallCode)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text((record.tags ?? []).joined(separator: ", "))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
        }
        .font(AppTypography.rowSecondary)
    }
}

private struct FingerprintActionsView: View {
    @Environment(AppState.self) private var appState
    @Binding var importTags: String
    @Binding var exportTags: String
    @Binding var cleanupTag: String
    let cleanupMatchCount: Int
    let filteredRecords: [FingerprintRecord]
    let parsedTags: (String) -> [String]
    let cleanup: (String, Int) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                actionLabel("导入")
                importControls
            }
            GridRow {
                actionLabel("导出")
                exportControls
            }
            GridRow {
                actionLabel("清理")
                cleanupControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
    }

    private var importControls: some View {
        HStack(spacing: 8) {
            TextField("导入标签，逗号分隔", text: $importTags)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Button {
                appState.importFingerprintPackageWithPanel(tags: parsedTags(importTags))
            } label: {
                Label(appState.t("fingerprints.importPackage"), systemImage: "square.and.arrow.down")
            }
        }
    }

    private var exportControls: some View {
        HStack(spacing: 8) {
            TextField("导出包标签，逗号分隔", text: $exportTags)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Button {
                appState.exportFingerprintPackage(records: filteredRecords, tags: parsedTags(exportTags))
            } label: {
                Label(appState.t("fingerprints.exportPackage"), systemImage: "square.and.arrow.up")
            }
            .disabled(filteredRecords.isEmpty)
        }
    }

    private var cleanupControls: some View {
        HStack(spacing: 8) {
            TextField(appState.t("fingerprints.cleanupTag"), text: $cleanupTag)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text("\(cleanupMatchCount) 条命中")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Button(role: .destructive) {
                cleanup(cleanupTag, cleanupMatchCount)
            } label: {
                Label(appState.t("fingerprints.cleanup"), systemImage: "tag.slash")
            }
            .disabled(cleanupTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cleanupMatchCount == 0)
        }
    }
}

struct WhitelistLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var newPattern = ""
    @State private var newType: WhitelistRule.RuleType = .filename
    @State private var query = ""
    @State private var suggestionFilter: WhitelistSuggestionStatus = .pending
    @State private var suggestions = AppPreferences.loadWhitelistSuggestions()
    @State private var suggestionStatuses = AppPreferences.loadWhitelistSuggestionStatuses()
    @State private var isRefreshingSuggestions = false
    @State private var suggestionMessage: String?

    private var filteredRules: [WhitelistRule] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.whitelistRules }
        return appState.whitelistRules.filter { rule in
            [rule.pattern, rule.type.displayTitle].joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    private var decoratedSuggestions: [WhitelistSuggestion] {
        suggestions.map { suggestion in
            var copy = suggestion
            if ruleExists(copy.rule) {
                copy.status = .accepted
            } else if let status = suggestionStatuses[copy.id] {
                copy.status = status
            }
            return copy
        }
    }

    private var filteredSuggestions: [WhitelistSuggestion] {
        decoratedSuggestions.filter { suggestion in
            suggestion.status == suggestionFilter && suggestionMatchesSearch(suggestion)
        }
    }

    private var pendingSuggestionsForBatch: [WhitelistSuggestion] {
        decoratedSuggestions.filter { suggestion in
            suggestion.status == .pending && suggestionMatchesSearch(suggestion)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchHeader(title: appState.t("sidebar.whitelist"), count: filteredRules.count + filteredSuggestions.count, query: $query, prompt: appState.t("whitelist.searchPrompt"))

            WhitelistRuleEditor(newPattern: $newPattern, newType: $newType)

            WhitelistSuggestionsSection(
                suggestions: filteredSuggestions,
                filter: $suggestionFilter,
                pendingCount: pendingSuggestionsForBatch.count,
                isRefreshing: isRefreshingSuggestions,
                message: suggestionMessage,
                refresh: { Task { await refreshSuggestions() } },
                acceptPending: acceptPendingSuggestions,
                accept: acceptSuggestion,
                dismiss: dismissSuggestion
            )

            WhitelistRulesSection(rules: filteredRules)
        }
        .padding(AppLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            if suggestions.isEmpty {
                await refreshSuggestions()
            }
        }
        .onAppear {
            suggestionStatuses = AppPreferences.loadWhitelistSuggestionStatuses()
            suggestions = AppPreferences.loadWhitelistSuggestions()
        }
    }

    private func suggestionMatchesSearch(_ suggestion: WhitelistSuggestion) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        return [
            suggestion.rule.pattern,
            suggestion.rule.type.displayTitle,
            appState.title(for: suggestion.rule.type),
            suggestion.reason,
            suggestion.status.title,
        ]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(trimmed)
    }

    private func ruleExists(_ rule: WhitelistRule) -> Bool {
        appState.whitelistRules.contains { existing in
            existing.type == rule.type && existing.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
        }
    }

    private func acceptSuggestion(_ suggestion: WhitelistSuggestion) {
        setSuggestionStatus(.accepted, for: suggestion)
        Task {
            await appState.addWhitelistRule(pattern: suggestion.rule.pattern, type: suggestion.rule.type)
        }
    }

    private func dismissSuggestion(_ suggestion: WhitelistSuggestion) {
        setSuggestionStatus(.dismissed, for: suggestion)
    }

    private func acceptPendingSuggestions() {
        let targets = pendingSuggestionsForBatch
        guard targets.isEmpty == false else { return }
        for suggestion in targets {
            setSuggestionStatus(.accepted, for: suggestion)
        }
        Task {
            for suggestion in targets {
                await appState.addWhitelistRule(pattern: suggestion.rule.pattern, type: suggestion.rule.type)
            }
        }
    }

    private func setSuggestionStatus(_ status: WhitelistSuggestionStatus, for suggestion: WhitelistSuggestion) {
        suggestionStatuses[suggestion.id] = status
        suggestions = suggestions.map { item in
            var copy = item
            if copy.id == suggestion.id {
                copy.status = status
            }
            return copy
        }
        AppPreferences.saveWhitelistSuggestionStatuses(suggestionStatuses)
        AppPreferences.saveWhitelistSuggestions(suggestions)
    }

    @MainActor
    private func refreshSuggestions() async {
        guard isRefreshingSuggestions == false else { return }
        isRefreshingSuggestions = true
        suggestionMessage = nil
        let configuration = appState.draftConfiguration
        let directoryURL = URL(fileURLWithPath: configuration.directoryPath)
        let statuses = suggestionStatuses

        do {
            let generated = try await Task.detached(priority: .userInitiated) {
                let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: directoryURL)
                return WhitelistSuggestionService().suggest(from: documents)
            }.value
            suggestions = generated.map { suggestion in
                var copy = suggestion
                if let status = statuses[suggestion.id] {
                    copy.status = status
                }
                return copy
            }
            AppPreferences.saveWhitelistSuggestions(suggestions)
        } catch {
            suggestionMessage = "建议生成失败：\(error.localizedDescription)"
        }

        isRefreshingSuggestions = false
    }
}

private struct WhitelistRuleEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var newPattern: String
    @Binding var newType: WhitelistRule.RuleType

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("新增")
                    .font(AppTypography.tableHeader)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                ruleTypePicker
                ruleField
                saveButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ruleTypePicker: some View {
        Picker(appState.t("whitelist.type"), selection: $newType) {
            ForEach(WhitelistRule.RuleType.allCases, id: \.self) { type in
                Text(appState.title(for: type)).tag(type)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }

    private var ruleField: some View {
        TextField(appState.t("whitelist.newRule"), text: $newPattern)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
    }

    private var saveButton: some View {
        Button(appState.t("whitelist.save")) {
            let pattern = newPattern
            newPattern = ""
            Task { await appState.addWhitelistRule(pattern: pattern, type: newType) }
        }
        .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct WhitelistSuggestionsSection: View {
    @Environment(AppState.self) private var appState
    let suggestions: [WhitelistSuggestion]
    @Binding var filter: WhitelistSuggestionStatus
    let pendingCount: Int
    let isRefreshing: Bool
    let message: String?
    let refresh: () -> Void
    let acceptPending: () -> Void
    let accept: (WhitelistSuggestion) -> Void
    let dismiss: (WhitelistSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("白名单建议")
                        .font(AppTypography.sectionTitle)
                    Text("\(suggestions.count) 条")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                WhitelistSuggestionToolbar(
                    filter: $filter,
                    pendingCount: pendingCount,
                    isRefreshing: isRefreshing,
                    message: message,
                    refresh: refresh,
                    acceptPending: acceptPending
                )
            }

            if suggestions.isEmpty {
                ContentUnavailableView("暂无匹配建议", systemImage: "checklist", description: Text("刷新建议后可接受或忽略候选规则"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WhitelistSuggestionHeader()
                    List(suggestions) { suggestion in
                        WhitelistSuggestionTableRow(
                            suggestion: suggestion,
                            accept: { accept(suggestion) },
                            dismiss: { dismiss(suggestion) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .listStyle(.plain)
                    .frame(height: nativeTableHeight(rowCount: suggestions.count, minHeight: 220, maxHeight: 360))
                }
            }
        }
    }
}

private struct WhitelistSuggestionHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("规则")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("类型")
                .frame(width: 90, alignment: .leading)
            Text("次数")
                .frame(width: 54, alignment: .trailing)
            Text("状态")
                .frame(width: 64, alignment: .trailing)
            Text("操作")
                .frame(width: 52, alignment: .trailing)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
    }
}

private struct WhitelistRulesSection: View {
    @Environment(AppState.self) private var appState
    let rules: [WhitelistRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("现有规则")
                    .font(AppTypography.sectionTitle)
                Text("\(rules.count) 条")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            if rules.isEmpty {
                ContentUnavailableView("暂无匹配规则", systemImage: "shield", description: Text("可在上方输入规则并保存"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WhitelistRuleHeader()
                    List(rules) { rule in
                        WhitelistTableRow(rule: rule)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .listStyle(.plain)
                    .frame(height: nativeTableHeight(rowCount: rules.count, minHeight: 70, maxHeight: 260))
                }
            }
        }
    }
}

private struct WhitelistRuleHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("规则")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("类型")
                .frame(width: 90, alignment: .leading)
            Text("创建时间")
                .frame(width: 132, alignment: .trailing)
            Text("操作")
                .frame(width: 24, alignment: .trailing)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
    }
}

private func nativeTableHeight(rowCount: Int, minHeight: CGFloat = 86, maxHeight: CGFloat = 480) -> CGFloat {
    min(max(CGFloat(rowCount) * 28 + 42, minHeight), maxHeight)
}

private struct WhitelistSuggestionToolbar: View {
    @Binding var filter: WhitelistSuggestionStatus
    let pendingCount: Int
    let isRefreshing: Bool
    let message: String?
    let refresh: () -> Void
    let acceptPending: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    controls
                }
                VStack(alignment: .trailing, spacing: 8) {
                    controls
                }
            }

            if let message {
                Text(message)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var controls: some View {
        Group {
            Picker("建议状态", selection: $filter) {
                ForEach(WhitelistSuggestionStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Button(action: refresh) {
                Label(isRefreshing ? "生成中" : "刷新建议", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)

            Button(action: acceptPending) {
                Label("批量接受", systemImage: "checkmark.seal")
            }
            .disabled(pendingCount == 0 || isRefreshing)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(pendingCount) 条待处理")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}

private struct EmptyWhitelistRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowPrimary)
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 18)
    }
}

private struct WhitelistSuggestionTableRow: View {
    @Environment(AppState.self) private var appState
    let suggestion: WhitelistSuggestion
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.rule.pattern)
                    .font(AppTypography.rowPrimary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(suggestion.reason)
                    .font(AppTypography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(appState.title(for: suggestion.rule.type))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text("\(suggestion.supportCount) 次")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)

            Text(suggestion.status.title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            Button(action: accept) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(suggestion.status == .accepted)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(suggestion.status == .dismissed)
        }
        .font(AppTypography.rowSecondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 7)
    }

}

struct JobInspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let job = appState.selectedJob {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                                    .font(AppTypography.pageTitle)
                                Text(job.configuration.directoryPath)
                                    .font(AppTypography.smallCode)
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

                        HStack(spacing: 8) {
                            Button {
                                appState.beginQueuedAudits()
                            } label: {
                                Label(appState.t("job.runQueue"), systemImage: "play.fill")
                            }
                            .disabled(appState.isRunningAudit || appState.queuedJobCount == 0)

                            if job.status == .failed {
                                Button {
                                    Task { await appState.retryJob(job) }
                                } label: {
                                    Label(appState.t("job.retry"), systemImage: "arrow.clockwise")
                                }
                                .disabled(appState.isRunningAudit)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(job.latestMessage)
                                Spacer()
                                Text("\(job.progress)%")
                            }
                            .font(AppTypography.rowSecondary)
                            .foregroundStyle(.secondary)
                            ProgressView(value: Double(job.progress), total: 100)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    JobInspectorSection(title: appState.t("job.timeline"), subtitle: "\(job.events.count) \(appState.t("common.countSuffix"))") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(job.events.reversed())) { event in
                                TimelineEventRow(event: event)
                            }
                        }
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(appState.t("job.noSelection"), systemImage: "clock.badge.questionmark", description: Text(appState.t("job.noSelectionDescription")))
        }
    }
}

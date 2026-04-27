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
        VStack(spacing: 0) {
            SearchHeader(title: appState.t("sidebar.fingerprints"), count: filteredRecords.count, query: $query, prompt: appState.t("fingerprints.searchPrompt"))
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    TextField("导入标签，逗号分隔", text: $importTags)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)

                    Button {
                        appState.importFingerprintPackageWithPanel(tags: parsedTags(importTags))
                    } label: {
                        Label(appState.t("fingerprints.importPackage"), systemImage: "square.and.arrow.down")
                    }

                    TextField("导出包标签，逗号分隔", text: $exportTags)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)

                    Button {
                        appState.exportFingerprintPackage(records: filteredRecords, tags: parsedTags(exportTags))
                    } label: {
                        Label(appState.t("fingerprints.exportPackage"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(filteredRecords.isEmpty)

                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField(appState.t("fingerprints.cleanupTag"), text: $cleanupTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)

                    Text("\(cleanupMatchCount) 条命中")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        confirmAndDeleteFingerprints(tag: cleanupTag, matchCount: cleanupMatchCount)
                    } label: {
                        Label(appState.t("fingerprints.cleanup"), systemImage: "tag.slash")
                    }
                    .disabled(cleanupTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cleanupMatchCount == 0)

                    Spacer()
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            List(filteredRecords) { record in
                FingerprintTableRow(record: record)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
        }
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
        VStack(spacing: 0) {
            SearchHeader(title: appState.t("sidebar.whitelist"), count: filteredRules.count + filteredSuggestions.count, query: $query, prompt: appState.t("whitelist.searchPrompt"))
            VStack(spacing: 0) {
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

                Divider()

                WhitelistSuggestionToolbar(
                    filter: $suggestionFilter,
                    pendingCount: pendingSuggestionsForBatch.count,
                    isRefreshing: isRefreshingSuggestions,
                    message: suggestionMessage,
                    refresh: { Task { await refreshSuggestions() } },
                    acceptPending: acceptPendingSuggestions
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))

            List {
                if filteredSuggestions.isEmpty == false {
                    Section("白名单建议") {
                        ForEach(filteredSuggestions) { suggestion in
                            WhitelistSuggestionTableRow(
                                suggestion: suggestion,
                                accept: { acceptSuggestion(suggestion) },
                                dismiss: { dismissSuggestion(suggestion) }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    }
                }

                Section("现有规则") {
                    ForEach(filteredRules) { rule in
                        WhitelistTableRow(rule: rule)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
            }
            .listStyle(.plain)
        }
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

private struct WhitelistSuggestionToolbar: View {
    @Binding var filter: WhitelistSuggestionStatus
    let pendingCount: Int
    let isRefreshing: Bool
    let message: String?
    let refresh: () -> Void
    let acceptPending: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("建议状态", selection: $filter) {
                    ForEach(WhitelistSuggestionStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
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

                Spacer()

                Text("\(pendingCount) 条待处理")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if let message {
                Text(message)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                .foregroundStyle(statusColor)
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
        .padding(.vertical, 7)
    }

    private var statusColor: Color {
        switch suggestion.status {
        case .pending: return .secondary
        case .accepted: return .green
        case .dismissed: return .orange
        }
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

                    JobInspectorSection(title: appState.t("job.timeline"), subtitle: "\(job.events.count) \(appState.t("common.countSuffix"))") {
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

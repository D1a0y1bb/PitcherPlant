import SwiftUI
import AppKit

struct JobHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filteredJobs: [AuditJob] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return appState.jobs }
        return appState.jobs.filter { job in
            [URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent, job.configuration.directoryPath, job.latestMessage, appState.title(for: job.status)]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchHeader(title: appState.t("sidebar.history"), count: filteredJobs.count, query: $query, prompt: appState.t("history.searchPrompt"))

            AppTablePanel {
                Table(filteredJobs, selection: Binding(
                    get: { appState.selectedJobID },
                    set: { selectedID in
                        appState.selectedJobID = selectedID
                        if selectedID != nil {
                            appState.requestInspector()
                        }
                    }
                )) {
                    TableColumn(appState.t("audit.directory")) { job in
                        Label(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent, systemImage: job.status.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn(appState.t("common.type")) { job in
                        Text(appState.title(for: job.status))
                            .foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn(appState.t("job.stage")) { job in
                        Text(appState.title(for: job.stage))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn(appState.t("common.progress")) { job in
                        Text("\(job.progress)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(76)
                    TableColumn(appState.t("job.failures")) { job in
                        Text("\(job.failureCount)")
                            .monospacedDigit()
                            .foregroundStyle(job.failureCount > 0 ? .red : .secondary)
                    }
                    .width(56)
                    TableColumn(appState.t("common.updatedAt")) { job in
                        Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 150, ideal: 180)
                }
                .frame(
                    minHeight: 120,
                    idealHeight: nativeTableIdealHeight(rowCount: filteredJobs.count, minHeight: 160, maxHeight: 360),
                    maxHeight: .infinity
                )
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
    @State private var cleanupMatchCount = 0
    @State private var fingerprintQueryRefreshTask: Task<Void, Never>?
    @State private var cleanupCountRefreshTask: Task<Void, Never>?

    private var displayedRecords: [FingerprintRecord] {
        appState.fingerprintLibraryRecords
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchHeader(title: appState.t("sidebar.fingerprints"), count: appState.fingerprintLibraryTotalCount, query: $query, prompt: appState.t("fingerprints.searchPrompt"))

            FingerprintActionsView(
                importTags: $importTags,
                exportTags: $exportTags,
                cleanupTag: $cleanupTag,
                cleanupMatchCount: cleanupMatchCount,
                exportMatchCount: appState.fingerprintLibraryTotalCount,
                query: query,
                parsedTags: parsedTags,
                cleanup: confirmAndDeleteFingerprints
            )

            AppHorizontalOverflow(minWidth: AppLayout.fingerprintTableMinWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    FingerprintListHeader()
                    List(displayedRecords) { record in
                        FingerprintLibraryRow(
                            record: record,
                            context: fingerprintContext(record)
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .listStyle(.plain)
                    .frame(
                        minHeight: 180,
                        idealHeight: nativeTableIdealHeight(rowCount: displayedRecords.count, minHeight: 220, maxHeight: 360),
                        maxHeight: .infinity
                    )
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(AppLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshFingerprintLibrary(immediate: true)
            refreshCleanupMatchCount(immediate: true)
        }
        .onChange(of: query) { _, _ in refreshFingerprintLibrary() }
        .onChange(of: cleanupTag) { _, _ in refreshCleanupMatchCount() }
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
        return values.isEmpty ? appState.t("common.unlabeled") : values.joined(separator: " / ")
    }

    private func confirmAndDeleteFingerprints(tag: String, matchCount: Int) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, matchCount > 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = appState.t("fingerprints.cleanupConfirmTitle")
        alert.informativeText = appState.tf("fingerprints.cleanupConfirmMessage", trimmed, matchCount)
        alert.addButton(withTitle: appState.t("fingerprints.cleanup"))
        alert.addButton(withTitle: appState.t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cleanupTag = ""
        Task { @MainActor in
            await appState.deleteFingerprints(tag: trimmed)
            await appState.refreshFingerprintLibrary(query: query)
            cleanupMatchCount = await appState.fingerprintCount(tag: cleanupTag)
        }
    }

    private func refreshFingerprintLibrary(immediate: Bool = false) {
        fingerprintQueryRefreshTask?.cancel()
        let query = query
        fingerprintQueryRefreshTask = Task { @MainActor in
            if immediate == false {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard Task.isCancelled == false else { return }
            await appState.refreshFingerprintLibrary(query: query)
        }
    }

    private func refreshCleanupMatchCount(immediate: Bool = false) {
        cleanupCountRefreshTask?.cancel()
        let tag = cleanupTag
        cleanupCountRefreshTask = Task { @MainActor in
            if immediate == false {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard Task.isCancelled == false else { return }
            cleanupMatchCount = await appState.fingerprintCount(tag: tag)
        }
    }
}

private struct FingerprintListHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 14) {
            Text(appState.t("common.file"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.t("common.type"))
                .frame(width: 70, alignment: .leading)
            Text(appState.t("fingerprints.context"))
                .frame(width: 180, alignment: .leading)
            Text("SimHash")
                .frame(width: 170, alignment: .leading)
            Text(appState.t("fingerprints.tags"))
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
    let exportMatchCount: Int
    let query: String
    let parsedTags: (String) -> [String]
    let cleanup: (String, Int) -> Void

    var body: some View {
        AppToolbarBand {
            AppHorizontalOverflow(minWidth: AppLayout.fingerprintActionsMinWidth, fitsContentHeight: true) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        actionLabel(appState.t("common.import"))
                        importControls
                    }
                    GridRow {
                        actionLabel(appState.t("common.export"))
                        exportControls
                    }
                    GridRow {
                        actionLabel(appState.t("fingerprints.cleanup"))
                        cleanupControls
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
    }

    private var importControls: some View {
        HStack(spacing: 8) {
            TextField(appState.t("fingerprints.importTagsPrompt"), text: $importTags)
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
            TextField(appState.t("fingerprints.exportTagsPrompt"), text: $exportTags)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Button {
                appState.exportFingerprintPackage(query: query, tags: parsedTags(exportTags))
            } label: {
                Label(appState.t("fingerprints.exportPackage"), systemImage: "square.and.arrow.up")
            }
            .disabled(exportMatchCount == 0)
        }
    }

    private var cleanupControls: some View {
        HStack(spacing: 8) {
            TextField(appState.t("fingerprints.cleanupTag"), text: $cleanupTag)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text(appState.tf("fingerprints.matchCount", cleanupMatchCount))
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
            appState.title(for: suggestion.status),
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
        let suggestionService = WhitelistSuggestionService(reasons: appState.whitelistSuggestionReasons())

        do {
            let generated = try await Task.detached(priority: .userInitiated) {
                let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: directoryURL)
                return suggestionService.suggest(from: documents)
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
            suggestionMessage = appState.tf("whitelist.suggestions.failed", error.localizedDescription)
        }

        isRefreshingSuggestions = false
    }
}

private struct WhitelistRuleEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var newPattern: String
    @Binding var newType: WhitelistRule.RuleType

    var body: some View {
        AppToolbarBand {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(appState.t("common.new"))
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
                    Text(appState.t("whitelist.suggestions"))
                        .font(AppTypography.sectionTitle)
                    Text(appState.tf("common.itemCount", suggestions.count))
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
                ContentUnavailableView(
                    appState.t("whitelist.noMatchedSuggestions"),
                    systemImage: "checklist",
                    description: Text(appState.t("whitelist.noMatchedSuggestionsDescription"))
                )
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
                    .frame(
                        minHeight: 120,
                        idealHeight: nativeTableIdealHeight(rowCount: suggestions.count, minHeight: 160, maxHeight: 260),
                        maxHeight: .infinity
                    )
                }
            }
        }
    }
}

private struct WhitelistSuggestionHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.t("whitelist.rule"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.t("common.type"))
                .frame(width: 90, alignment: .leading)
            Text(appState.t("common.count"))
                .frame(width: 54, alignment: .trailing)
            Text(appState.t("common.status"))
                .frame(width: 64, alignment: .trailing)
            Text(appState.t("common.actions"))
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
                Text(appState.t("whitelist.existingRules"))
                    .font(AppTypography.sectionTitle)
                Text(appState.tf("common.itemCount", rules.count))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            if rules.isEmpty {
                ContentUnavailableView(
                    appState.t("whitelist.noMatchedRules"),
                    systemImage: "shield",
                    description: Text(appState.t("whitelist.noMatchedRulesDescription"))
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WhitelistRuleHeader()
                    List(rules) { rule in
                        WhitelistTableRow(rule: rule)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .listStyle(.plain)
                    .frame(
                        minHeight: 70,
                        idealHeight: nativeTableIdealHeight(rowCount: rules.count, minHeight: 100, maxHeight: 220),
                        maxHeight: .infinity
                    )
                }
            }
        }
    }
}

private struct WhitelistRuleHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.t("whitelist.rule"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.t("common.type"))
                .frame(width: 90, alignment: .leading)
            Text(appState.t("common.createdAt"))
                .frame(width: 132, alignment: .trailing)
            Text(appState.t("common.actions"))
                .frame(width: 24, alignment: .trailing)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
    }
}

private func nativeTableIdealHeight(rowCount: Int, minHeight: CGFloat = 86, maxHeight: CGFloat = 480) -> CGFloat {
    min(max(CGFloat(rowCount) * 28 + 42, minHeight), maxHeight)
}

private struct WhitelistSuggestionToolbar: View {
    @Environment(AppState.self) private var appState
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
            Picker(appState.t("whitelist.suggestionStatus"), selection: $filter) {
                ForEach(WhitelistSuggestionStatus.allCases) { status in
                    Text(appState.title(for: status)).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Button(action: refresh) {
                Label(isRefreshing ? appState.t("whitelist.generating") : appState.t("whitelist.refreshSuggestions"), systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)

            Button(action: acceptPending) {
                Label(appState.t("whitelist.acceptPending"), systemImage: "checkmark.seal")
            }
            .disabled(pendingCount == 0 || isRefreshing)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(appState.tf("whitelist.pendingCount", pendingCount))
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

            Text(appState.tf("common.times", suggestion.supportCount))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)

            Text(appState.title(for: suggestion.status))
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
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top) {
                                jobHeaderText(job)
                                Spacer()
                                StatusBadge(status: job.status)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                StatusBadge(status: job.status)
                                jobHeaderText(job)
                            }
                        }

                        Button {
                            appState.restoreDraft(from: job)
                        } label: {
                            Label(appState.t("job.restoreParameters"), systemImage: "arrow.counterclockwise")
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                jobRunQueueButton
                                if job.status == .failed {
                                    jobRetryButton(job)
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                jobRunQueueButton
                                if job.status == .failed {
                                    jobRetryButton(job)
                                }
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

                    if job.failedFiles.isEmpty == false {
                        JobInspectorSection(title: appState.t("job.failedFiles"), subtitle: appState.tf("common.itemCount", job.failedFiles.count)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(job.failedFiles.prefix(8), id: \.self) { file in
                                    Text(file)
                                        .font(AppTypography.smallCode)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(job.diagnosticSummary, forType: .string)
                                } label: {
                                    Label(appState.t("job.copyDiagnostics"), systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, AppLayout.titlebarScrollContentTopPadding)
                .padding(.bottom, 20)
            }
            .ignoresSafeArea(.container, edges: .top)
        } else {
            InspectorEmptyState(
                title: appState.t("job.noSelection"),
                subtitle: appState.t("job.noSelectionDescription"),
                systemImage: "clock.badge.questionmark"
            )
        }
    }

    private var jobRunQueueButton: some View {
        Button {
            appState.beginQueuedAudits()
        } label: {
            Label(appState.t("job.runQueue"), systemImage: "play.fill")
        }
        .disabled(appState.isRunningAudit || appState.queuedJobCount == 0)
    }

    private func jobRetryButton(_ job: AuditJob) -> some View {
        Button {
            Task { await appState.retryJob(job) }
        } label: {
            Label(appState.t("job.retry"), systemImage: "arrow.clockwise")
        }
        .disabled(appState.isRunningAudit)
    }

    private func jobHeaderText(_ job: AuditJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                .font(AppTypography.sectionTitle)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            Text(job.configuration.directoryPath)
                .font(AppTypography.smallCode)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

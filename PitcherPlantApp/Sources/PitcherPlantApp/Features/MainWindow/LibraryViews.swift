import SwiftUI

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

struct WhitelistLibraryView: View {
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

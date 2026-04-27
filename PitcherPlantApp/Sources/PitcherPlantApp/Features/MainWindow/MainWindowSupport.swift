import SwiftUI

struct SettingsSearchToolbarModifier: ViewModifier {
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

struct EvidenceFocusedReportsView: View {
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

struct MainStatusBar: View {
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

            if let notice = appState.notice {
                Label {
                    Text("\(notice.title): \(notice.message)")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: noticeIcon(for: notice.tone))
                }
                .font(.caption)
                .foregroundStyle(noticeColor(for: notice.tone))

                Button {
                    appState.dismissNotice()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else if appState.isRunningAudit {
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

    private func noticeIcon(for tone: AppNotice.Tone) -> String {
        switch tone {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func noticeColor(for tone: AppNotice.Tone) -> Color {
        switch tone {
        case .info: return .secondary
        case .success: return .green
        case .error: return .red
        }
    }
}

struct MainSidebarView: View {
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

import SwiftUI

struct ReportLibrarySidebar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String
    @Binding var reportFilter: ReportLibraryFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appState.t("reports.title"))
                        .font(AppTypography.sectionTitle)
                    Spacer()
                    Text("\(reports.count)")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                Picker(appState.t("reports.filter"), selection: $reportFilter) {
                    ForEach(ReportLibraryFilter.allCases) { filter in
                        Text(appState.title(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List(selection: Binding(
                get: { appState.selectedReportID },
                set: { appState.selectReport($0) }
            )) {
                if reports.isEmpty {
                    ContentUnavailableView(appState.t("reports.noMatchedReport"), systemImage: "doc.text.magnifyingglass", description: Text(appState.t("reports.noMatchedDescription")))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(reports) { report in
                        ReportLibraryRow(report: report)
                            .tag(report.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $reportQuery, placement: .sidebar, prompt: appState.t("reports.searchPrompt"))
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct ReportLibraryRow: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: report.isLegacy ? "doc.richtext" : "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(report.title)
                        .font(AppTypography.rowPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if report.isLegacy && appState.appSettings.showLegacyBadges {
                        Text("Legacy")
                            .font(AppTypography.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

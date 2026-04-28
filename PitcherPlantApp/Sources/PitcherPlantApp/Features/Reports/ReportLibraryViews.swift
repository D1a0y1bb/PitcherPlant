import SwiftUI

struct ReportLibrarySidebar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String
    @Binding var reportFilter: ReportLibraryFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppToolbarBand {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appState.t("reports.title"))
                            .font(AppTypography.sectionTitle)
                        Spacer()
                        Text("\(reports.count)")
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                    }

                    TextField(appState.t("reports.searchPrompt"), text: $reportQuery)
                        .textFieldStyle(.roundedBorder)

                    Picker(appState.t("reports.filter"), selection: $reportFilter) {
                        ForEach(ReportLibraryFilter.allCases) { filter in
                            Text(appState.title(for: filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            AppTablePanel {
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
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
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
                            .foregroundStyle(.secondary)
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

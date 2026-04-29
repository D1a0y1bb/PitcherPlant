import SwiftUI

struct ReportLibrarySidebar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String

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

                    if reportQuery.isEmpty == false {
                        Text(reportQuery)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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
                .scrollIndicators(.hidden)
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
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(report.title)
                    .font(AppTypography.rowPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

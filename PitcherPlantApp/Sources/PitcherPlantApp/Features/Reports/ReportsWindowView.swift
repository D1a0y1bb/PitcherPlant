import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var reportQuery = ""
    @State private var reportFilter: ReportLibraryFilter = .all

    private var filteredReports: [AuditReport] {
        appState.reports.filter { $0.matchesLibrarySearch(reportQuery, filter: reportFilter) }
    }

    var body: some View {
        NavigationSplitView {
            ReportLibrarySidebar(
                reports: filteredReports,
                reportQuery: $reportQuery,
                reportFilter: $reportFilter
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } content: {
            ReportSectionsAndEvidenceView()
                .navigationSplitViewColumnWidth(min: 520, ideal: 720, max: .infinity)
        } detail: {
            ReportEvidenceInspector()
                .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 560)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in syncVisibleReportSelection() }
        .onChange(of: reportFilter) { _, _ in syncVisibleReportSelection() }
        .onChange(of: appState.reports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.exportSelectedReportAsPDF()
                } label: {
                    Label(appState.t("settings.exportPDF"), systemImage: "doc.richtext")
                }

                Button {
                    appState.exportSelectedReportAsHTML()
                } label: {
                    Label(appState.t("settings.exportHTML"), systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    appState.openSelectedReportSource()
                } label: {
                    Label(appState.t("settings.openFinder"), systemImage: "folder")
                }

                Button(role: .destructive) {
                    Task { await appState.removeSelectedReport() }
                } label: {
                    Label(appState.t("command.deleteReport"), systemImage: "trash")
                }

                Button {
                    Task { await appState.reload() }
                } label: {
                    Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func syncVisibleReportSelection() {
        let visibleIDs = Set(filteredReports.map(\.id))
        guard visibleIDs.isEmpty == false else {
            appState.selectReport(nil)
            return
        }
        if let selectedID = appState.selectedReportID, visibleIDs.contains(selectedID) {
            return
        }
        appState.selectReport(filteredReports.first?.id)
    }
}
struct ReportsInlineView: View {
    @Environment(AppState.self) private var appState
    @State private var reportQuery = ""
    @State private var reportFilter: ReportLibraryFilter = .all

    private var filteredReports: [AuditReport] {
        appState.reports.filter { $0.matchesLibrarySearch(reportQuery, filter: reportFilter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ReportsCenterSelectorBar(
                reports: filteredReports,
                reportQuery: $reportQuery,
                reportFilter: $reportFilter
            )
            Divider()
            ReportSectionsAndEvidenceView(showsReportHeader: false)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in syncVisibleReportSelection() }
        .onChange(of: reportFilter) { _, _ in syncVisibleReportSelection() }
        .onChange(of: appState.reports.map(\.id)) { _, _ in syncVisibleReportSelection() }
    }

    private func syncVisibleReportSelection() {
        let visibleIDs = Set(filteredReports.map(\.id))
        guard visibleIDs.isEmpty == false else {
            appState.selectReport(nil)
            return
        }
        if let selectedID = appState.selectedReportID, visibleIDs.contains(selectedID) {
            return
        }
        appState.selectReport(filteredReports.first?.id)
    }
}

private struct ReportsCenterSelectorBar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String
    @Binding var reportFilter: ReportLibraryFilter

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.t("reports.title"))
                    .font(.headline)
                if let report = appState.selectedReport {
                    Text(report.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(appState.t("reports.noReport"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            TextField(appState.t("reports.searchPrompt"), text: $reportQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)

            Picker(appState.t("reports.filter"), selection: $reportFilter) {
                ForEach(ReportLibraryFilter.allCases) { filter in
                    Text(appState.title(for: filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Menu {
                if reports.isEmpty {
                    Text(appState.t("reports.noMatchedReport"))
                } else {
                    ForEach(reports) { report in
                        Button {
                            appState.selectReport(report.id)
                        } label: {
                            Label(report.title, systemImage: report.isLegacy ? "doc.richtext" : "doc.text.magnifyingglass")
                        }
                    }
                }
            } label: {
                Label(appState.t("reports.selectReport"), systemImage: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)

            Button {
                appState.exportSelectedReportAsPDF()
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            .disabled(appState.selectedReport == nil)

            Button {
                appState.exportSelectedReportAsHTML()
            } label: {
                Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(appState.selectedReport == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ReportEvidenceInspectorHost: View {
    var body: some View {
        ReportEvidenceInspector()
    }
}

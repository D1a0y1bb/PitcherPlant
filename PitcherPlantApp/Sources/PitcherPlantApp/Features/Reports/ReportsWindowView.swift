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
                Menu {
                    Button { appState.exportSelectedReportAsHTML() } label: {
                        Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button { appState.exportSelectedReportAsPDF() } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    Button { appState.exportSelectedReportAsCSV() } label: {
                        Label("CSV", systemImage: "tablecells")
                    }
                    Button { appState.exportSelectedReportAsJSON() } label: {
                        Label("JSON", systemImage: "curlybraces")
                    }
                    Button { appState.exportSelectedReportAsMarkdown() } label: {
                        Label("Markdown", systemImage: "doc.plaintext")
                    }
                    Button { appState.exportSelectedReportAsEvidenceBundle() } label: {
                        Label(appState.t("settings.exportBundle"), systemImage: "archivebox")
                    }
                } label: {
                    Label(appState.t("settings.exportReport"), systemImage: "square.and.arrow.up")
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
        VStack(spacing: 14) {
            ReportsCenterSelectorBar(
                reports: filteredReports,
                reportQuery: $reportQuery,
                reportFilter: $reportFilter
            )
            ReportSectionsAndEvidenceView(showsReportHeader: false)
        }
        .padding(AppLayout.pagePadding)
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in syncVisibleReportSelection() }
        .onChange(of: reportFilter) { _, _ in syncVisibleReportSelection() }
        .onChange(of: appState.reports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .searchable(text: $reportQuery, prompt: appState.t("reports.searchPrompt"))
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
        AppToolbarBand {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.t("reports.title"))
                        .font(AppTypography.sectionTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let report = appState.selectedReport {
                        Text(report.title)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(appState.t("reports.noReport"))
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 124, maxWidth: 180, alignment: .leading)

                Spacer()

                Picker(appState.t("reports.filter"), selection: $reportFilter) {
                    ForEach(ReportLibraryFilter.allCases) { filter in
                        Text(appState.title(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

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

                Menu {
                    Button { appState.exportSelectedReportAsHTML() } label: { Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Button { appState.exportSelectedReportAsPDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                    Button { appState.exportSelectedReportAsCSV() } label: { Label("CSV", systemImage: "tablecells") }
                    Button { appState.exportSelectedReportAsJSON() } label: { Label("JSON", systemImage: "curlybraces") }
                    Button { appState.exportSelectedReportAsMarkdown() } label: { Label("Markdown", systemImage: "doc.plaintext") }
                    Button { appState.exportSelectedReportAsEvidenceBundle() } label: { Label(appState.t("settings.exportBundle"), systemImage: "archivebox") }
                } label: {
                    Label(appState.t("settings.exportReport"), systemImage: "square.and.arrow.up")
                }
                .disabled(appState.selectedReport == nil)
            }
        }
    }
}

struct ReportEvidenceInspectorHost: View {
    var body: some View {
        ReportEvidenceInspector()
    }
}

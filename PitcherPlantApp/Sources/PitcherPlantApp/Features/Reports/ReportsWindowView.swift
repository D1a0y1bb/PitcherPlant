import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var reportQuery = ""

    private var filteredReports: [AuditReport] {
        appState.reports.filter { $0.matchesLibrarySearch(reportQuery) }
    }

    var body: some View {
        NavigationSplitView {
            ReportLibrarySidebar(
                reports: filteredReports,
                reportQuery: $reportQuery
            )
            .navigationSplitViewColumnWidth(
                min: AppLayout.sidebarMinWidth,
                ideal: AppLayout.sidebarIdealWidth,
                max: AppLayout.sidebarMaxWidth
            )
        } content: {
            ReportSectionsAndEvidenceView()
                .navigationSplitViewColumnWidth(
                    min: AppLayout.contentMinWidth,
                    ideal: AppLayout.contentIdealWidth,
                    max: .infinity
                )
                .background {
                    AppWindowColumnBackground()
                        .ignoresSafeArea(.container, edges: .top)
                }
        } detail: {
            ReportEvidenceInspector()
                .navigationSplitViewColumnWidth(
                    min: AppLayout.inspectorMinWidth,
                    ideal: AppLayout.inspectorIdealWidth,
                    max: AppLayout.inspectorMaxWidth
                )
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in syncVisibleReportSelection() }
        .onChange(of: appState.reports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .toolbar {
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                FloatingToolbarCluster {
                    FloatingToolbarButtonGroup {
                        FloatingToolbarMenuButton(appState.t("settings.exportReport"), systemImage: "square.and.arrow.up") {
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
                        }

                        FloatingToolbarIconButton(appState.t("settings.openFinder"), systemImage: "folder") {
                            appState.openSelectedReportSource()
                        }

                        FloatingToolbarIconButton(appState.t("command.deleteReport"), systemImage: "trash", role: .destructive) {
                            Task { await appState.removeSelectedReport() }
                        }

                        FloatingToolbarIconButton(appState.t("toolbar.reload"), systemImage: "arrow.clockwise") {
                            Task { await appState.reload() }
                        }
                    }

                    FloatingToolbarSearchField(text: $reportQuery, prompt: appState.t("reports.searchPrompt"))
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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

    private var filteredReports: [AuditReport] {
        appState.reports.filter { $0.matchesLibrarySearch(reportQuery) }
    }

    var body: some View {
        VStack(spacing: 14) {
            AppToolbarBand {
                ReportsCenterSelectorBar(
                    reports: filteredReports,
                    reportQuery: $reportQuery
                )
            }
            ReportSectionsAndEvidenceView(showsReportHeader: false)
        }
        .padding(AppLayout.pagePadding)
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in syncVisibleReportSelection() }
        .onChange(of: appState.reports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FloatingToolbarSearchField(text: $reportQuery, prompt: appState.t("reports.searchPrompt"))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    titleBlock
                    Spacer()
                    reportMenu
                    exportMenu
                }

                VStack(alignment: .leading, spacing: 10) {
                    titleBlock
                    HStack(spacing: 10) {
                        reportMenu
                        exportMenu
                    }
                }
            }

            Text(reportQuery.isEmpty ? "\(reports.count) \(appState.t("common.countSuffix"))" : "\(reports.count) \(appState.t("reports.matchedReports"))")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appState.t("reports.title"))
                .font(AppTypography.sectionTitle)
                .lineLimit(1)
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
    }

    private var reportMenu: some View {
        Menu {
            if reports.isEmpty {
                Text(appState.t("reports.noMatchedReport"))
            } else {
                ForEach(reports) { report in
                    Button {
                        appState.selectReport(report.id)
                    } label: {
                        Label(report.title, systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
        } label: {
            Label(appState.t("reports.selectReport"), systemImage: "doc.on.doc")
        }
    }

    private var exportMenu: some View {
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

struct ReportEvidenceInspectorHost: View {
    var body: some View {
        ReportEvidenceInspector()
    }
}

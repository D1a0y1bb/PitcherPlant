import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var reportQuery = ""
    @State private var reportQueryRefreshTask: Task<Void, Never>?

    private var filteredReports: [AuditReport] {
        appState.reportLibraryReports
    }

    var body: some View {
        NavigationSplitView {
            ReportLibrarySidebar(
                reports: filteredReports,
                totalCount: appState.reportLibraryTotalCount,
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
                .background(
                    SplitTrailingColumnWidthInitializer(
                        width: AppLayout.inspectorDefaultWidth,
                        resetKey: "reports-window"
                    )
                )
                .navigationSplitViewColumnWidth(
                    min: AppLayout.inspectorMinWidth,
                    ideal: AppLayout.inspectorIdealWidth,
                    max: AppLayout.inspectorMaxWidth
                )
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            refreshReportLibrary(immediate: true)
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in refreshReportLibrary() }
        .onChange(of: appState.reportLibraryReports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .toolbar {
            reportWindowToolbarItems
        }
        .navigationTitle(appState.t("sidebar.reports"))
        .searchable(text: $reportQuery, placement: .toolbar, prompt: appState.t("reports.searchPrompt"))
        .background(ToolbarCustomizationDisabler().frame(width: 0, height: 0))
    }

    private func refreshReportLibrary(immediate: Bool = false) {
        reportQueryRefreshTask?.cancel()
        let query = reportQuery
        reportQueryRefreshTask = Task { @MainActor in
            if immediate == false {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard Task.isCancelled == false else { return }
            await appState.refreshReportLibrary(query: query)
            syncVisibleReportSelection()
        }
    }

    @ToolbarContentBuilder
    private var reportWindowToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
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
            .disabled(appState.selectedReport == nil)
            .help(appState.t("settings.exportReport"))
            .accessibilityLabel(appState.t("settings.exportReport"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.openSelectedReportSource()
            } label: {
                Label(appState.t("settings.openFinder"), systemImage: "folder")
            }
            .disabled(appState.selectedReport == nil)
            .help(appState.t("settings.openFinder"))
            .accessibilityLabel(appState.t("settings.openFinder"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive) {
                Task { await appState.removeSelectedReport() }
            } label: {
                Label(appState.t("command.deleteReport"), systemImage: "trash")
            }
            .disabled(appState.selectedReport == nil)
            .help(appState.t("command.deleteReport"))
            .accessibilityLabel(appState.t("command.deleteReport"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await appState.reload() }
            } label: {
                Label(appState.t("toolbar.reload"), systemImage: "arrow.clockwise")
            }
            .help(appState.t("toolbar.reload"))
            .accessibilityLabel(appState.t("toolbar.reload"))
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
    @Binding var reportQuery: String
    @State private var reportQueryRefreshTask: Task<Void, Never>?

    private var filteredReports: [AuditReport] {
        appState.reportLibraryReports
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
            refreshReportLibrary(immediate: true)
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in refreshReportLibrary() }
        .onChange(of: appState.reportLibraryReports.map(\.id)) { _, _ in syncVisibleReportSelection() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func refreshReportLibrary(immediate: Bool = false) {
        reportQueryRefreshTask?.cancel()
        let query = reportQuery
        reportQueryRefreshTask = Task { @MainActor in
            if immediate == false {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard Task.isCancelled == false else { return }
            await appState.refreshReportLibrary(query: query)
            syncVisibleReportSelection()
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

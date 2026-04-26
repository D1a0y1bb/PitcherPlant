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

private struct ReportLibrarySidebar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String
    @Binding var reportFilter: ReportLibraryFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appState.t("reports.title"))
                        .font(.headline)
                    Spacer()
                    Text("\(reports.count)")
                        .font(.caption)
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

private struct ReportLibraryRow: View {
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
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if report.isLegacy && appState.appSettings.showLegacyBadges {
                        Text("Legacy")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ReportSectionsAndEvidenceView: View {
    @Environment(AppState.self) private var appState
    var showsReportHeader = true
    @State private var evidenceQuery = ""
    @State private var evidenceFilter: ReportEvidenceFilter = .all
    @State private var evidenceSortOrder: ReportEvidenceSortOrder = .default

    private var selectedSection: ReportSection? {
        appState.selectedReportSectionModel
    }

    private var filteredSection: ReportSection? {
        selectedSection?.filteredCopy(query: evidenceQuery, evidenceFilter: evidenceFilter, sortOrder: evidenceSortOrder)
    }

    private var rows: [ReportTableRow] {
        filteredSection?.table?.rows ?? []
    }

    private var totalRowCount: Int {
        selectedSection?.table?.rows.count ?? 0
    }

    var body: some View {
        if let report = appState.selectedReport {
            VStack(spacing: 0) {
                if showsReportHeader {
                    ReportContentHeader(report: report)
                    Divider()
                }

                ReportSectionStrip(report: report)
                Divider()

                if let section = selectedSection {
                    if totalRowCount > 0 {
                        EvidenceToolbar(
                            evidenceQuery: $evidenceQuery,
                            evidenceFilter: $evidenceFilter,
                            evidenceSortOrder: $evidenceSortOrder,
                            visibleRowCount: rows.count,
                            totalRowCount: totalRowCount
                        )
                        Divider()
                        EvidenceList(section: section, rows: rows)
                    } else {
                        ReportSectionReadingView(section: section, report: report)
                    }
                } else {
                    ContentUnavailableView(appState.t("reports.noSection"), systemImage: "list.bullet.rectangle", description: Text(appState.t("reports.noSectionDescription")))
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                if appState.selectedReportSection == nil {
                    appState.selectReportSection(report.preferredEvidenceSection?.kind)
                }
                syncVisibleEvidenceSelection()
            }
            .onChange(of: rows.map(\.id)) { _, _ in syncVisibleEvidenceSelection() }
            .onChange(of: appState.selectedReportSection) { _, _ in syncVisibleEvidenceSelection() }
            .onChange(of: appState.selectedReportID) { _, _ in
                evidenceQuery = ""
                evidenceFilter = .all
                evidenceSortOrder = .default
                syncVisibleEvidenceSelection()
            }
        } else {
            ContentUnavailableView(appState.t("reports.noReport"), systemImage: "doc.text", description: Text(appState.t("reports.noReportDescription")))
        }
    }

    private func syncVisibleEvidenceSelection() {
        guard rows.isEmpty == false else {
            appState.selectedReportRowID = nil
            return
        }
        if let selectedID = appState.selectedReportRowID,
           rows.contains(where: { $0.id == selectedID }) {
            return
        }
        appState.selectedReportRowID = rows.first?.id
    }
}

private struct ReportContentHeader: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(report.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 12) {
                    ForEach(report.metrics.prefix(4), id: \.title) { metric in
                        Label {
                            Text(metric.value)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: metric.systemImage)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Label(URL(fileURLWithPath: report.sourcePath).lastPathComponent, systemImage: "doc")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            if report.isLegacy && appState.appSettings.showLegacyBadges {
                Text("Legacy")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ReportSectionStrip: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(report.displaySections) { section in
                    ReportSectionChip(
                        section: section,
                        isSelected: appState.selectedReportSection == section.kind
                    ) {
                        appState.selectReportSection(section.kind)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ReportSectionChip: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let isSelected: Bool
    let action: () -> Void

    private var rowCount: Int {
        section.table?.rows.count ?? 0
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(appState.title(for: section.kind))
                        .lineLimit(1)
                    if rowCount > 0 {
                        Text("\(rowCount)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReportSectionReadingView: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let report: AuditReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(section.title, systemImage: section.kind.systemImage)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(report.isLegacy ? appState.t("reports.legacyHTML") : appState.t("reports.nativeReport"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t("reports.sectionSummary"))
                        .font(.headline)
                    Text(section.summary.isEmpty ? appState.t("reports.sectionNoStructuredEvidence") : section.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if section.callouts.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appState.t("reports.callouts"))
                            .font(.headline)
                        ForEach(section.callouts, id: \.self) { callout in
                            Label(callout, systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("common.source"))
                        .font(.headline)
                    Text(report.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct EvidenceToolbar: View {
    @Environment(AppState.self) private var appState
    @Binding var evidenceQuery: String
    @Binding var evidenceFilter: ReportEvidenceFilter
    @Binding var evidenceSortOrder: ReportEvidenceSortOrder
    let visibleRowCount: Int
    let totalRowCount: Int

    var body: some View {
        HStack(spacing: 12) {
            TextField(appState.t("reports.searchEvidence"), text: $evidenceQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Picker(appState.t("reports.filter"), selection: $evidenceFilter) {
                ForEach(ReportEvidenceFilter.allCases) { option in
                    Text(appState.title(for: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Menu {
                Picker(appState.t("reports.sort"), selection: $evidenceSortOrder) {
                    ForEach(ReportEvidenceSortOrder.allCases) { option in
                        Text(appState.title(for: option)).tag(option)
                    }
                }
            } label: {
                Label(appState.title(for: evidenceSortOrder), systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)

            Spacer()
            Text("\(visibleRowCount) / \(totalRowCount) \(appState.t("reports.rows"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EvidenceList: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let rows: [ReportTableRow]

    var body: some View {
        if rows.isEmpty, section.table != nil {
            ContentUnavailableView(appState.t("reports.noEvidence"), systemImage: "line.3.horizontal.decrease.circle", description: Text(appState.t("reports.noEvidenceDescription")))
        } else if section.kind == .overview {
            OverviewEvidenceList(rows: rows)
        } else if rows.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.summary)
                        .foregroundStyle(.secondary)
                    ForEach(section.callouts, id: \.self) { callout in
                        Label(callout, systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            List(selection: Binding(
                get: { appState.selectedReportRowID },
                set: { appState.selectedReportRowID = $0 }
            )) {
                DenseEvidenceHeader(headers: section.table?.headers ?? [])
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))

                ForEach(rows) { row in
                    EvidenceListRow(row: row)
                        .tag(row.id)
                        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct DenseEvidenceHeader: View {
    @Environment(AppState.self) private var appState
    let headers: [String]

    var body: some View {
        HStack(spacing: 12) {
            Text(headers[safe: 0] ?? appState.t("reports.objectA"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(headers[safe: 1] ?? appState.t("reports.objectB"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(headers[safe: 2] ?? appState.t("common.score"))
                .frame(width: 70, alignment: .trailing)
            Text(headers[safe: 3] ?? appState.t("common.type"))
                .frame(width: 84, alignment: .leading)
            Text(appState.t("common.badge"))
                .frame(width: 92, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct EvidenceListRow: View {
    let row: ReportTableRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.columns[safe: 0] ?? row.detailTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.columns[safe: 1] ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.columns[safe: 2] ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(row.columns[safe: 3] ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            Text(row.badges.first?.title ?? row.columns[safe: 4] ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
    }
}

private struct OverviewEvidenceList: View {
    @Environment(AppState.self) private var appState
    let rows: [ReportTableRow]

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedReportRowID },
            set: { appState.selectedReportRowID = $0 }
        )) {
            ForEach(rows) { row in
                HStack {
                    Text(row.detailTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(row.columns[safe: 2] ?? "")
                        .foregroundStyle(.secondary)
                }
                .tag(row.id)
                .padding(.vertical, 5)
            }
        }
        .listStyle(.plain)
    }
}

private struct ReportEvidenceInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let row = appState.selectedReportRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Text(row.detailTitle)
                                .font(.title2.weight(.semibold))
                                .lineLimit(3)
                            Spacer()
                        }

                        if !row.badges.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(row.badges, id: \.title) { badge in
                                    ReportBadgeView(badge: badge)
                                }
                            }
                        }
                    }

                    InspectorSection(title: appState.t("reports.evidenceDetails")) {
                        Text(row.detailBody)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !row.attachments.isEmpty {
                        InspectorSection(title: appState.t("reports.attachments")) {
                            ImageEvidenceDetailView(
                                attachments: row.attachments,
                                showsPreviews: appState.appSettings.showAttachmentPreviews
                            )
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else if let section = appState.selectedReportSectionModel {
            if section.table?.rows.isEmpty == false {
                ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
            } else if let report = appState.selectedReport {
                ReportQuickInspector(report: report)
            } else {
                ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
            }
        } else {
            ContentUnavailableView {
                Label(appState.t("reports.noEvidenceSelection"), systemImage: "doc.text.magnifyingglass")
            } description: {
                Text(appState.t("reports.noEvidenceSelectionDescription"))
            }
        }
    }
}

private struct ReportQuickInspector: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("reports.reportProperties"))
                        .font(.title3.weight(.semibold))
                    Text(report.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                InspectorSection(title: appState.t("reports.metrics")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.metrics, id: \.title) { metric in
                            HStack {
                                Label(metric.title, systemImage: metric.systemImage)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(metric.value)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                        }
                    }
                }

                InspectorSection(title: appState.t("common.path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.t("reports.reportFile"))
                            .font(.caption.weight(.semibold))
                        Text(report.sourcePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(appState.t("reports.scanDirectory"))
                            .font(.caption.weight(.semibold))
                        Text(report.scanDirectoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ReportSectionSummaryInspector: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let report: AuditReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title, systemImage: section.kind.systemImage)
                        .font(.title3.weight(.semibold))
                    if let report {
                        Text(report.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                InspectorSection(title: appState.t("reports.sectionSummary")) {
                    Text(section.summary.isEmpty ? appState.t("reports.sectionNoStructuredEvidence") : section.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if section.callouts.isEmpty == false {
                    InspectorSection(title: appState.t("reports.callouts")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.callouts, id: \.self) { callout in
                                Label(callout, systemImage: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let table = section.table {
                    InspectorSection(title: appState.t("reports.evidenceCount")) {
                        Text("\(table.rows.count) \(appState.t("reports.structuredRecords"))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct ImageEvidenceDetailView: View {
    let attachments: [ReportAttachment]
    let showsPreviews: Bool

    private let columns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.title)
                            .font(.subheadline.weight(.semibold))
                        Text(attachment.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showsPreviews, let image = attachment.imageBase64.flatMap(decodedImage) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Text(attachment.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator.opacity(0.25)))
            }
        }
    }

    private func decodedImage(_ value: String) -> NSImage? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct ReportBadgeView: View {
    let badge: ReportBadge

    var body: some View {
        Text(badge.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch badge.tone {
        case .neutral: return Color(nsColor: .separatorColor).opacity(0.16)
        case .accent: return Color.blue.opacity(0.12)
        case .warning: return Color.orange.opacity(0.14)
        case .danger: return Color.red.opacity(0.14)
        case .success: return Color.green.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch badge.tone {
        case .neutral: return .secondary
        case .accent: return .blue
        case .warning: return .orange
        case .danger: return .red
        case .success: return .green
        }
    }
}

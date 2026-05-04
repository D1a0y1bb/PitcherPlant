import SwiftUI

struct ReportSectionsAndEvidenceView: View {
    @Environment(AppState.self) private var appState
    var showsReportHeader = true
    @State private var evidenceSearchText = ""
    @State private var evidenceQuery = ""
    @State private var evidenceFilter: ReportEvidenceFilter = .all
    @State private var evidenceSortOrder: ReportEvidenceSortOrder = .default
    @State private var rowsModel = ReportRowsViewModel.empty
    @State private var queryDebounceTask: Task<Void, Never>?

    private var selectedSection: ReportSection? {
        appState.selectedReportSectionModel
    }

    var body: some View {
        let selectedSection = selectedSection
        let visibleRows = rowsModel.rows
        let visibleRowIDs = rowsModel.visibleRowIDs
        let totalRowCount = rowsModel.totalRowCount

        if let report = appState.selectedReport {
            VStack(spacing: 14) {
                if showsReportHeader {
                    ReportContentHeader(report: report)
                }

                ReportSectionStrip(report: report)

                if let section = selectedSection {
                    if totalRowCount > 0 {
                        AppTablePanel {
                            VStack(spacing: 0) {
                                EvidenceToolbar(
                                    evidenceQuery: $evidenceSearchText,
                                    evidenceFilter: $evidenceFilter,
                                    evidenceSortOrder: $evidenceSortOrder,
                                    visibleRowCount: visibleRows.count,
                                    totalRowCount: totalRowCount
                                )
                                EvidenceList(report: report, section: section, rows: visibleRows)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        ReportSectionReadingView(section: section, report: report)
                    }
                } else {
                    AppEmptyPanel(title: appState.t("reports.noSection"), subtitle: appState.t("reports.noSectionDescription"), systemImage: "list.bullet.rectangle")
                }
            }
            .padding(showsReportHeader ? AppLayout.pagePadding : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                if appState.selectedReportSection == nil {
                    appState.selectReportSection(report.preferredEvidenceSection?.kind)
                }
                refreshRows()
                syncVisibleEvidenceSelection()
            }
            .onChange(of: visibleRowIDs) { _, _ in syncVisibleEvidenceSelection() }
            .onChange(of: evidenceSearchText) { _, value in scheduleQueryUpdate(value) }
            .onChange(of: evidenceQuery) { _, _ in refreshRows() }
            .onChange(of: evidenceFilter) { _, _ in refreshRows() }
            .onChange(of: evidenceSortOrder) { _, _ in refreshRows() }
            .onChange(of: appState.selectedReportSection) { _, _ in
                refreshRows()
                syncVisibleEvidenceSelection()
            }
            .onChange(of: appState.selectedReportID) { _, _ in
                evidenceSearchText = ""
                evidenceQuery = ""
                evidenceFilter = .all
                evidenceSortOrder = .default
                refreshRows()
                syncVisibleEvidenceSelection()
            }
        } else {
            AppEmptyPanel(title: appState.t("reports.noReport"), subtitle: appState.t("reports.noReportDescription"), systemImage: "doc.text")
                .padding(AppLayout.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func syncVisibleEvidenceSelection() {
        guard rowsModel.rows.isEmpty == false else {
            appState.selectedReportRowID = nil
            return
        }
        if let selectedID = appState.selectedReportRowID,
           rowsModel.rows.contains(where: { $0.id == selectedID }) {
            return
        }
        appState.selectedReportRowID = rowsModel.rows.first?.id
    }

    private func refreshRows() {
        rowsModel = ReportRowsViewModel(
            section: selectedSection,
            query: evidenceQuery,
            filter: evidenceFilter,
            sortOrder: evidenceSortOrder
        )
    }

    private func scheduleQueryUpdate(_ value: String) {
        queryDebounceTask?.cancel()
        queryDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard Task.isCancelled == false else { return }
            evidenceQuery = value
        }
    }
}

struct ReportContentHeader: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(report.title)
                    .font(AppTypography.sectionTitle)
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
                .font(AppTypography.metadata)
            }

            Spacer()

        }
    }
}

struct ReportSectionStrip: View {
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
            .padding(.vertical, 2)
        }
    }
}

struct ReportSectionChip: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let isSelected: Bool
    let action: () -> Void

    private var rowCount: Int {
        section.table?.rows.count ?? 0
    }

    var body: some View {
        if isSelected {
            Button(action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(appState.title(for: section.kind))
                .lineLimit(1)
            if rowCount > 0 {
                Text("\(rowCount)")
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
            }
        }
        .font(AppTypography.metadata.weight(.medium))
    }
}

struct ReportSectionReadingView: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let report: AuditReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(section.title, systemImage: section.kind.systemImage)
                        .font(AppTypography.pageTitle)
                    Spacer()
                    Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.metadata.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.t("reports.sectionSummary"))
                        .font(AppTypography.sectionTitle)
                    Text(section.summary.isEmpty ? appState.t("reports.sectionNoStructuredEvidence") : section.summary)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if section.callouts.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appState.t("reports.callouts"))
                            .font(AppTypography.sectionTitle)
                        ForEach(section.callouts, id: \.self) { callout in
                            Label(callout, systemImage: "info.circle")
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("common.source"))
                        .font(AppTypography.sectionTitle)
                    Text(report.sourcePath)
                        .font(AppTypography.smallCode)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
    }
}

struct EvidenceToolbar: View {
    @Environment(AppState.self) private var appState
    @Binding var evidenceQuery: String
    @Binding var evidenceFilter: ReportEvidenceFilter
    @Binding var evidenceSortOrder: ReportEvidenceSortOrder
    let visibleRowCount: Int
    let totalRowCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                searchField
                filterPicker
                sortMenu
                Spacer()
                countLabel
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    searchField
                    Spacer()
                    countLabel
                }
                HStack(spacing: 12) {
                    filterPicker
                    sortMenu
                    Spacer()
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        TextField(appState.t("reports.searchEvidence"), text: $evidenceQuery)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
    }

    private var filterPicker: some View {
        Picker(appState.t("reports.filter"), selection: $evidenceFilter) {
            ForEach(ReportEvidenceFilter.allCases) { option in
                Text(appState.title(for: option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
    }

    private var sortMenu: some View {
        Menu {
            Picker(appState.t("reports.sort"), selection: $evidenceSortOrder) {
                ForEach(ReportEvidenceSortOrder.allCases) { option in
                    Text(appState.title(for: option)).tag(option)
                }
            }
        } label: {
            Label(appState.title(for: evidenceSortOrder), systemImage: "arrow.up.arrow.down")
        }
    }

    private var countLabel: some View {
        Text("\(visibleRowCount) / \(totalRowCount) \(appState.t("reports.rows"))")
            .font(AppTypography.metadata)
            .foregroundStyle(.secondary)
    }
}

struct EvidenceCollectionView: View {
    @Environment(AppState.self) private var appState
    let scope: EvidenceCollectionScope
    @State private var queryText = ""
    @State private var query = ""
    @State private var visibleItems: [EvidenceCollectionItem] = []
    @State private var selectedEvidenceIDs = Set<UUID>()
    @State private var queryDebounceTask: Task<Void, Never>?

    var body: some View {
        let visibleItemIDs = visibleItems.map(\.id)

        VStack(alignment: .leading, spacing: 24) {
            NativePageHeader(
                title: appState.title(for: scope),
                subtitle: "\(visibleItems.count) \(appState.t("reports.rows"))",
                actions: {
                    EmptyView()
                }
            )

            AppToolbarBand {
                HStack(spacing: 12) {
                    TextField(appState.t("evidence.collection.searchPrompt"), text: $queryText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .frame(minWidth: 260, idealWidth: 340, maxWidth: 460)
                    Spacer()
                    Label("\(visibleItems.count)", systemImage: scope.systemImage)
                        .foregroundStyle(.secondary)
                }
            }

            AppTablePanel {
                if visibleItems.isEmpty {
                    AppEmptyPanel(
                        title: appState.t("evidence.collection.empty"),
                        subtitle: appState.t("evidence.collection.emptyDescription"),
                        systemImage: scope.systemImage
                    )
                } else {
                    AppHorizontalOverflow(minWidth: AppLayout.evidenceCollectionTableMinWidth) {
                        EvidenceReviewTableView(
                            rows: EvidenceReviewTableRow.sorted(EvidenceReviewTableRow.rows(items: visibleItems), by: .riskDescending),
                            selection: $selectedEvidenceIDs
                        ) { row in
                            guard let row else {
                                return
                            }
                            appState.selectEvidence(row.target)
                            appState.requestInspector()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppLayout.pagePadding)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshItems()
            syncSelection()
        }
        .onChange(of: queryText) { _, value in scheduleQueryUpdate(value) }
        .onChange(of: query) { _, _ in
            refreshItems()
            syncSelection()
        }
        .onChange(of: appState.reports.map(\.id)) { _, _ in
            refreshItems()
            syncSelection()
        }
        .onChange(of: appState.evidenceReviewRevision) { _, _ in
            refreshItems()
            syncSelection()
        }
        .onChange(of: visibleItemIDs) { _, _ in syncSelection() }
    }

    private func syncSelection() {
        let selectedID = selectedEvidenceIDs.first
        guard let item = selectedID.flatMap({ id in visibleItems.first(where: { ($0.row.evidenceID ?? $0.row.id) == id }) }) ?? visibleItems.first else {
            selectedEvidenceIDs = []
            appState.selectedReportRowID = nil
            return
        }
        selectedEvidenceIDs = [item.row.evidenceID ?? item.row.id]
        appState.selectEvidence(item)
    }

    private func refreshItems() {
        visibleItems = appState.evidenceCollection(for: scope).filter { $0.matchesSearch(query) }
    }

    private func scheduleQueryUpdate(_ value: String) {
        queryDebounceTask?.cancel()
        queryDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard Task.isCancelled == false else { return }
            query = value
        }
    }
}

private struct EvidenceCollectionHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("★")
                Image(systemName: "eye")
            }
            .frame(width: 54, alignment: .center)
            Text(appState.t("reports.evidenceDetails"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.t("reports.title"))
                .frame(width: 180, alignment: .leading)
            Text(appState.t("common.score"))
                .frame(width: 70, alignment: .trailing)
            Text(appState.t("common.badge"))
                .frame(width: 92, alignment: .trailing)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

private struct EvidenceCollectionRow: View {
    let item: EvidenceCollectionItem
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EvidenceFlagButtons(row: item.row, beforeToggle: onSelect)
                .frame(width: 54, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryTitle)
                    .font(AppTypography.rowPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(previewText)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.reportTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.sectionTitle)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(AppTypography.rowSecondary)
            .frame(width: 180, alignment: .leading)

            Text(scoreText)
                .font(AppTypography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)

            Text(badgeText)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.vertical, 3)
    }

    private var primaryTitle: String {
        let lhs = item.row.columns[safe: 0] ?? item.row.detailTitle
        let rhs = item.row.columns[safe: 1] ?? ""
        return rhs.isEmpty ? lhs : "\(lhs) ↔ \(rhs)"
    }

    private var scoreText: String {
        item.row.columns[safe: 2] ?? ""
    }

    private var previewText: String {
        let value = item.row.columns[safe: 3] ?? item.row.detailBody
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var badgeText: String {
        item.row.badges.first?.title ?? item.row.columns[safe: 4] ?? ""
    }
}

struct EvidenceList: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport
    let section: ReportSection
    let rows: [ReportTableRow]
    @State private var selectedEvidenceIDs = Set<UUID>()

    var body: some View {
        if rows.isEmpty, section.table != nil {
            ContentUnavailableView(appState.t("reports.noEvidence"), systemImage: "line.3.horizontal.decrease.circle", description: Text(appState.t("reports.noEvidenceDescription")))
                .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
        } else if section.kind == .overview {
            OverviewEvidenceList(rows: rows)
        } else if section.kind == .crossBatch {
            CrossBatchEvidenceBrowser(rows: rows)
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
            .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
        } else {
            AppHorizontalOverflow(minWidth: AppLayout.evidenceTableMinWidth) {
                EvidenceReviewTableView(
                    rows: EvidenceReviewTableRow.rows(report: report, section: section, rows: rows),
                    selection: $selectedEvidenceIDs
                ) { tableRow in
                    if let tableRow {
                        appState.selectedReportRowID = tableRow.target.evidenceID
                    }
                }
                .onAppear { syncSelection() }
                .onChange(of: appState.selectedReportRowID) { _, _ in syncSelection() }
                .onChange(of: rows.map { $0.evidenceID ?? $0.id }) { _, _ in syncSelection() }
            }
        }
    }

    private func syncSelection() {
        if let selectedID = appState.selectedReportRowID,
           let row = rows.first(where: { ($0.evidenceID ?? $0.id) == selectedID || $0.id == selectedID }) {
            selectedEvidenceIDs = [row.evidenceID ?? row.id]
        } else if let first = rows.first {
            selectedEvidenceIDs = [first.evidenceID ?? first.id]
        } else {
            selectedEvidenceIDs = []
        }
    }
}

private struct EvidenceListHeader: View {
    let headers: [String]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("★")
                Image(systemName: "eye")
            }
            .frame(width: 54, alignment: .center)
            Text(headers[safe: 0] ?? "证据")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(headers[safe: 2] ?? "分数")
                .frame(width: 70, alignment: .trailing)
            Text("标记")
                .frame(width: 92, alignment: .trailing)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

struct EvidenceFlagButtons: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow
    var beforeToggle: () -> Void = {}

    private var isFavorite: Bool {
        row.review?.isFavorite ?? appState.isFavorite(row: row)
    }

    private var isWatching: Bool {
        row.review?.isWatched ?? appState.isWatching(row: row)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                beforeToggle()
                Task { await appState.toggleFavorite(row: row) }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.t(isFavorite ? "evidence.removeFavorite" : "evidence.addFavorite"))
            .accessibilityLabel(Text(appState.t(isFavorite ? "evidence.removeFavorite" : "evidence.addFavorite")))

            Button {
                beforeToggle()
                Task { await appState.toggleWatch(row: row) }
            } label: {
                Image(systemName: isWatching ? "eye.fill" : "eye")
                    .foregroundStyle(isWatching ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(appState.t(isWatching ? "evidence.removeWatch" : "evidence.addWatch"))
            .accessibilityLabel(Text(appState.t(isWatching ? "evidence.removeWatch" : "evidence.addWatch")))
        }
    }
}

private struct AdaptiveEvidenceListRow: View {
    let row: ReportTableRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EvidenceFlagButtons(row: row)
                .frame(width: 54, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryTitle)
                    .font(AppTypography.rowPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(previewText)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(scoreText)
                .font(AppTypography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)

            Text(badgeText)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var primaryTitle: String {
        let lhs = row.columns[safe: 0] ?? row.detailTitle
        let rhs = row.columns[safe: 1] ?? ""
        return rhs.isEmpty ? lhs : "\(lhs) ↔ \(rhs)"
    }

    private var scoreText: String {
        row.columns[safe: 2] ?? ""
    }

    private var previewText: String {
        let value = row.columns[safe: 3] ?? row.detailBody
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var badgeText: String {
        row.badges.first?.title ?? row.columns[safe: 4] ?? ""
    }
}

private enum CrossBatchEvidenceMode: String, CaseIterable, Identifiable {
    case list
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "列表"
        case .graph: return "图谱"
        }
    }
}

struct CrossBatchEvidenceBrowser: View {
    @State private var mode: CrossBatchEvidenceMode = .list
    @State private var selectedBatch = CrossBatchFilter.all
    @State private var selectedTeam = CrossBatchFilter.all
    @State private var selectedTag = CrossBatchFilter.all
    @State private var selectedStatus = CrossBatchFilter.all
    @State private var graph = CrossBatchGraph(nodes: [], edges: [])
    @State private var filteredGraph = CrossBatchGraph(nodes: [], edges: [])

    let rows: [ReportTableRow]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Picker("视图", selection: $mode) {
                        ForEach(CrossBatchEvidenceMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)

                    if mode == .graph {
                        CrossBatchFilterPicker(title: "批次", allTitle: "全部批次", options: graph.batches, selection: $selectedBatch)
                        CrossBatchFilterPicker(title: "队伍", allTitle: "全部队伍", options: graph.teams, selection: $selectedTeam)
                        CrossBatchFilterPicker(title: "标签", allTitle: "全部标签", options: graph.tags, selection: $selectedTag)
                        CrossBatchFilterPicker(title: "状态", allTitle: "全部状态", options: graph.statuses, selection: $selectedStatus)
                        Text("\(filteredGraph.nodes.count) 节点 / \(filteredGraph.edges.count) 边")
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            switch mode {
            case .list:
                CrossBatchList(rows: rows)
            case .graph:
                CrossBatchGraphPanel(graph: filteredGraph)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshGraphAndFiltered()
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            selectedBatch = CrossBatchFilter.all
            selectedTeam = CrossBatchFilter.all
            selectedTag = CrossBatchFilter.all
            selectedStatus = CrossBatchFilter.all
            refreshGraphAndFiltered()
        }
        .onChange(of: selectedBatch) { _, _ in refreshFilteredGraph() }
        .onChange(of: selectedTeam) { _, _ in refreshFilteredGraph() }
        .onChange(of: selectedTag) { _, _ in refreshFilteredGraph() }
        .onChange(of: selectedStatus) { _, _ in refreshFilteredGraph() }
    }

    private func refreshGraphAndFiltered() {
        let updatedGraph = CrossBatchGraphBuilder().build(rows: rows)
        graph = updatedGraph
        filteredGraph = updatedGraph.filtered(
            batch: CrossBatchFilter.value(selectedBatch),
            team: CrossBatchFilter.value(selectedTeam),
            tag: CrossBatchFilter.value(selectedTag),
            status: CrossBatchFilter.value(selectedStatus)
        )
    }

    private func refreshFilteredGraph() {
        filteredGraph = graph.filtered(
            batch: CrossBatchFilter.value(selectedBatch),
            team: CrossBatchFilter.value(selectedTeam),
            tag: CrossBatchFilter.value(selectedTag),
            status: CrossBatchFilter.value(selectedStatus)
        )
    }
}

private enum CrossBatchFilter {
    static let all = "__all__"

    static func value(_ selection: String) -> String? {
        selection == all ? nil : selection
    }
}

struct CrossBatchFilterPicker: View {
    let title: String
    let allTitle: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text(allTitle).tag(CrossBatchFilter.all)
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .frame(width: 132)
    }
}

struct CrossBatchList: View {
    @Environment(AppState.self) private var appState
    let rows: [ReportTableRow]
    @State private var selectedEvidenceIDs = Set<UUID>()

    var body: some View {
        AppHorizontalOverflow(minWidth: AppLayout.evidenceTableMinWidth) {
            if let report = appState.selectedReport {
                let section = appState.selectedReportSectionModel ?? ReportSection(kind: .crossBatch, title: "跨批次", summary: "")
                EvidenceReviewTableView(
                    rows: EvidenceReviewTableRow.rows(report: report, section: section, rows: rows),
                    selection: $selectedEvidenceIDs
                ) { tableRow in
                    if let tableRow {
                        appState.selectedReportRowID = tableRow.target.evidenceID
                    }
                }
                .onAppear { syncSelection() }
                .onChange(of: appState.selectedReportRowID) { _, _ in syncSelection() }
            }
        }
    }

    private func syncSelection() {
        if let selectedID = appState.selectedReportRowID,
           let row = rows.first(where: { ($0.evidenceID ?? $0.id) == selectedID || $0.id == selectedID }) {
            selectedEvidenceIDs = [row.evidenceID ?? row.id]
        } else if let first = rows.first {
            selectedEvidenceIDs = [first.evidenceID ?? first.id]
        } else {
            selectedEvidenceIDs = []
        }
    }
}

struct CrossBatchHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("当前文件")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("历史文件")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("批次")
                .frame(width: 150, alignment: .leading)
            Text("位差")
                .frame(width: 54, alignment: .trailing)
            Text("状态")
                .frame(width: 110, alignment: .leading)
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
    }
}

struct CrossBatchListRow: View {
    let row: ReportTableRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.columns[safe: 0] ?? row.detailTitle)
                .font(AppTypography.rowPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.columns[safe: 1] ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.columns[safe: 2] ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(row.columns[safe: 3] ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(row.columns[safe: 4] ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct CrossBatchGraphPanel: View {
    let graph: CrossBatchGraph
    private let maxDisplayedNodes = 320
    private let maxDisplayedEdges = 520

    private var currentNodes: [CrossBatchGraphNode] {
        Array(graph.nodes.filter { $0.kind == .document && $0.role == .current }.prefix(maxDisplayedNodes))
    }

    private var historicalNodes: [CrossBatchGraphNode] {
        Array(graph.nodes.filter { $0.kind == .document && $0.role == .historical }.prefix(maxDisplayedNodes))
    }

    private var contextNodes: [CrossBatchGraphNode] {
        Array(graph.nodes.filter { $0.kind != .document }.prefix(maxDisplayedNodes))
    }

    private var displayedEdges: [CrossBatchGraphEdge] {
        Array(graph.edges.prefix(maxDisplayedEdges))
    }

    private var hasDisplayCap: Bool {
        graph.nodes.count > maxDisplayedNodes * 3 || graph.edges.count > maxDisplayedEdges
    }

    var body: some View {
        if graph.edges.isEmpty {
            ContentUnavailableView("无匹配边", systemImage: "arrow.triangle.branch", description: Text("调整批次、队伍、标签或状态过滤条件"))
                .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 10) {
                    if hasDisplayCap {
                        Label("大图谱已显示前 \(displayedEdges.count) 条边和每组前 \(maxDisplayedNodes) 个节点", systemImage: "speedometer")
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        CrossBatchNodeColumn(title: "当前节点", nodes: currentNodes)
                        CrossBatchEdgeColumn(edges: displayedEdges)
                        CrossBatchNodeColumn(title: "历史节点", nodes: historicalNodes)
                        CrossBatchNodeColumn(title: "上下文节点", nodes: contextNodes)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
        }
    }
}

struct CrossBatchNodeColumn: View {
    let title: String
    let nodes: [CrossBatchGraphNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) \(nodes.count)")
                .font(AppTypography.tableHeader)
                .foregroundStyle(.secondary)
            ForEach(nodes) { node in
                CrossBatchNodeView(node: node)
            }
        }
        .frame(minWidth: 190, maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CrossBatchNodeView: View {
    let node: CrossBatchGraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(node.fileName, systemImage: node.kind.systemImage)
                .font(AppTypography.rowPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(node.role.title) · \(node.kind.title)")
                .font(AppTypography.metadata.weight(.medium))
                .foregroundStyle(.secondary)
            if node.subtitle.isEmpty == false {
                Text(node.subtitle)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if node.tags.isEmpty == false {
                Text(node.tags.prefix(3).joined(separator: " / "))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct CrossBatchEdgeColumn: View {
    @Environment(AppState.self) private var appState
    let edges: [CrossBatchGraphEdge]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("边 \(edges.count)")
                .font(AppTypography.tableHeader)
                .foregroundStyle(.secondary)
            ForEach(edges) { edge in
                Button {
                    appState.selectedReportRowID = edge.evidenceID
                    appState.requestInspector()
                } label: {
                    CrossBatchEdgeView(edge: edge)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CrossBatchEdgeView: View {
    let edge: CrossBatchGraphEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
                Text("\(edge.currentFile) → \(edge.historicalFile)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("\(edge.distance)")
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(edge.displayBatchName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(edge.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(AppTypography.metadata)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct DenseEvidenceHeader: View {
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
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
    }
}

struct EvidenceListRow: View {
    let row: ReportTableRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.columns[safe: 0] ?? row.detailTitle)
                .font(AppTypography.rowPrimary)
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
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct OverviewEvidenceList: View {
    @Environment(AppState.self) private var appState
    let rows: [ReportTableRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EvidenceListHeader(headers: ["证据", "", appState.t("common.score")])
            List(rows, selection: Binding(
                get: { appState.selectedReportRowID },
                set: { selectedID in
                    appState.selectedReportRowID = selectedID
                    if selectedID != nil {
                        appState.requestInspector()
                    }
                }
            )) { row in
                AdaptiveEvidenceListRow(row: row)
                    .tag(row.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .frame(
                minHeight: AppLayout.reportListMinHeight,
                idealHeight: reportListIdealHeight(rowCount: rows.count),
                maxHeight: .infinity
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func reportListIdealHeight(rowCount: Int) -> CGFloat {
    min(max(CGFloat(rowCount) * 50 + 12, AppLayout.reportListMinHeight), AppLayout.reportListIdealMaxHeight)
}

import SwiftUI

struct ReportSectionsAndEvidenceView: View {
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
                                    evidenceQuery: $evidenceQuery,
                                    evidenceFilter: $evidenceFilter,
                                    evidenceSortOrder: $evidenceSortOrder,
                                    visibleRowCount: rows.count,
                                    totalRowCount: totalRowCount
                                )
                                AppDivider()
                                EvidenceList(section: section, rows: rows)
                            }
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
            .background(.background)
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
            AppEmptyPanel(title: appState.t("reports.noReport"), subtitle: appState.t("reports.noReportDescription"), systemImage: "doc.text")
                .padding(AppLayout.pagePadding)
                .background(.background)
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

            if report.isLegacy && appState.appSettings.showLegacyBadges {
                Text("Legacy")
                    .font(AppTypography.badge)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .appPanelSurface(glass: true)
    }
}

struct ReportSectionStrip: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        AppToolbarBand {
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
            }
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
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
                    Text(report.isLegacy ? appState.t("reports.legacyHTML") : appState.t("reports.nativeReport"))
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
                .padding(12)
                .appPanelSurface()

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
                    .padding(12)
                    .appPanelSurface()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("common.source"))
                        .font(AppTypography.sectionTitle)
                    Text(report.sourcePath)
                        .font(AppTypography.smallCode)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .appPanelSurface()
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
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
        HStack(spacing: 12) {
            TextField(appState.t("reports.searchEvidence"), text: $evidenceQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            Picker(appState.t("reports.filter"), selection: $evidenceFilter) {
                ForEach(ReportEvidenceFilter.allCases) { option in
                    Text(appState.title(for: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

struct EvidenceList: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let rows: [ReportTableRow]

    var body: some View {
        if rows.isEmpty, section.table != nil {
            ContentUnavailableView(appState.t("reports.noEvidence"), systemImage: "line.3.horizontal.decrease.circle", description: Text(appState.t("reports.noEvidenceDescription")))
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
            .scrollContentBackground(.hidden)
        }
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

    let rows: [ReportTableRow]

    private var graph: CrossBatchGraph {
        CrossBatchGraphBuilder().build(rows: rows)
    }

    private var filteredGraph: CrossBatchGraph {
        graph.filtered(
            batch: CrossBatchFilter.value(selectedBatch),
            team: CrossBatchFilter.value(selectedTeam),
            tag: CrossBatchFilter.value(selectedTag),
            status: CrossBatchFilter.value(selectedStatus)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    Spacer()
                    Text("\(filteredGraph.nodes.count) 节点 / \(filteredGraph.edges.count) 边")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)

            AppDivider()

            switch mode {
            case .list:
                CrossBatchList(rows: rows)
            case .graph:
                CrossBatchGraphPanel(graph: filteredGraph)
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            selectedBatch = CrossBatchFilter.all
            selectedTeam = CrossBatchFilter.all
            selectedTag = CrossBatchFilter.all
            selectedStatus = CrossBatchFilter.all
        }
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

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedReportRowID },
            set: { appState.selectedReportRowID = $0 }
        )) {
            CrossBatchHeader()
                .listRowSeparator(.visible)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))

            ForEach(rows) { row in
                CrossBatchListRow(row: row)
                    .tag(row.id)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                .foregroundStyle(statusColor)
                .frame(width: 110, alignment: .leading)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }

    private var statusColor: Color {
        .secondary
    }
}

struct CrossBatchGraphPanel: View {
    let graph: CrossBatchGraph

    private var currentNodes: [CrossBatchGraphNode] {
        graph.nodes.filter { $0.kind == .document && $0.role == .current }
    }

    private var historicalNodes: [CrossBatchGraphNode] {
        graph.nodes.filter { $0.kind == .document && $0.role == .historical }
    }

    private var contextNodes: [CrossBatchGraphNode] {
        graph.nodes.filter { $0.kind != .document }
    }

    var body: some View {
        if graph.edges.isEmpty {
            ContentUnavailableView("无匹配边", systemImage: "arrow.triangle.branch", description: Text("调整批次、队伍、标签或状态过滤条件"))
        } else {
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    CrossBatchNodeColumn(title: "当前节点", nodes: currentNodes)
                    CrossBatchEdgeColumn(edges: graph.edges)
                    CrossBatchNodeColumn(title: "历史节点", nodes: historicalNodes)
                    CrossBatchNodeColumn(title: "上下文节点", nodes: contextNodes)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.background)
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanelSurface(cornerRadius: 10)
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanelSurface(cornerRadius: 10)
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
        List(selection: Binding(
            get: { appState.selectedReportRowID },
            set: { appState.selectedReportRowID = $0 }
        )) {
            ForEach(rows) { row in
                HStack {
                    Text(row.detailTitle)
                        .font(AppTypography.rowPrimary)
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
        .scrollContentBackground(.hidden)
    }
}

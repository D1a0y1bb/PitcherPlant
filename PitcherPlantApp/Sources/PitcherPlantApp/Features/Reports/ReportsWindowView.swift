import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var reportQuery = ""
    @State private var reportFilter: ReportLibraryFilter = .all

    private var filteredReports: [AuditReport] {
        appState.reports.filter { $0.matchesLibrarySearch(reportQuery, filter: reportFilter) }
    }

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedReportID },
                set: { appState.selectReport($0) }
            )) {
                if filteredReports.isEmpty {
                    ContentUnavailableView("无匹配报告", systemImage: "doc.text.magnifyingglass", description: Text("调整筛选条件后会显示符合条件的报告。"))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredReports) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(report.title)
                                    .fontWeight(.medium)
                                if report.isLegacy {
                                    Text("Legacy")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(report.id)
                    }
                }
            }
            .searchable(text: $reportQuery, placement: .sidebar, prompt: "搜索报告")
            .safeAreaInset(edge: .top) {
                Picker("报告筛选", selection: $reportFilter) {
                    ForEach(ReportLibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            if let report = appState.selectedReport {
                List(selection: Binding(
                    get: { appState.selectedReportSection },
                    set: { appState.selectReportSection($0) }
                )) {
                    Section(report.title) {
                        ForEach(report.sections) { section in
                            Label(section.title, systemImage: section.kind.systemImage)
                                .tag(Optional(section.kind))
                        }
                    }
                }
                .onAppear {
                    if appState.selectedReportSection == nil {
                        appState.selectReportSection(report.sections.first?.kind)
                    }
                }
            } else {
                ContentUnavailableView("暂无报告", systemImage: "doc.text", description: Text("完成一次审计或导入旧报告后会显示在这里。"))
            }
        } detail: {
            ReportDetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            syncVisibleReportSelection()
        }
        .onChange(of: reportQuery) { _, _ in
            syncVisibleReportSelection()
        }
        .onChange(of: reportFilter) { _, _ in
            syncVisibleReportSelection()
        }
        .onChange(of: appState.reports.map(\.id)) { _, _ in
            syncVisibleReportSelection()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.exportSelectedReportAsPDF()
                } label: {
                    Label("导出 PDF", systemImage: "doc.richtext")
                }

                Button {
                    appState.exportSelectedReportAsHTML()
                } label: {
                    Label("导出 HTML", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    appState.openSelectedReportSource()
                } label: {
                    Label("在 Finder 打开", systemImage: "folder")
                }

                Button(role: .destructive) {
                    Task { await appState.removeSelectedReport() }
                } label: {
                    Label("删除记录", systemImage: "trash")
                }

                Button {
                    Task { await appState.reload() }
                } label: {
                    Label("重新加载", systemImage: "arrow.clockwise")
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

private struct ReportDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var evidenceQuery = ""
    @State private var evidenceFilter: ReportEvidenceFilter = .all
    @State private var evidenceSortOrder: ReportEvidenceSortOrder = .default

    var body: some View {
        if let report = appState.selectedReport {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Text(report.title)
                            .font(.title2.weight(.semibold))
                        Spacer()
                        if report.isLegacy {
                            Text("Legacy")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 14) {
                        ForEach(report.metrics, id: \.title) { metric in
                            MetricCard(metric: metric)
                        }
                    }

                    if let section = appState.selectedReportSectionModel {
                        ReportSectionView(
                            section: section,
                            evidenceQuery: $evidenceQuery,
                            evidenceFilter: $evidenceFilter,
                            evidenceSortOrder: $evidenceSortOrder
                        )
                    }
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView("未选择报告", systemImage: "sidebar.right", description: Text("左侧选择一个报告查看原生章节与证据。"))
        }
    }
}

private struct ReportSectionView: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    @Binding var evidenceQuery: String
    @Binding var evidenceFilter: ReportEvidenceFilter
    @Binding var evidenceSortOrder: ReportEvidenceSortOrder

    private var filteredSection: ReportSection {
        section.filteredCopy(query: evidenceQuery, evidenceFilter: evidenceFilter, sortOrder: evidenceSortOrder)
    }

    private var filteredRows: [ReportTableRow] {
        filteredSection.table?.rows ?? []
    }

    private var resolvedSelectedRow: ReportTableRow? {
        if let selectedID = appState.selectedReportRowID {
            return filteredRows.first(where: { $0.id == selectedID }) ?? filteredRows.first
        }
        return filteredRows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title3.weight(.semibold))
            Text(section.summary)
                .foregroundStyle(.secondary)

            if section.table != nil {
                ReportSectionToolbar(
                    evidenceQuery: $evidenceQuery,
                    evidenceFilter: $evidenceFilter,
                    evidenceSortOrder: $evidenceSortOrder,
                    visibleRowCount: filteredRows.count,
                    totalRowCount: section.table?.rows.count ?? 0
                )
            }

            if !section.callouts.isEmpty {
                ForEach(section.callouts, id: \.self) { item in
                    Label(item, systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if filteredRows.isEmpty, section.table != nil {
                ContentUnavailableView("无匹配证据", systemImage: "line.3.horizontal.decrease.circle", description: Text("当前章节没有符合搜索和筛选条件的记录。"))
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if section.kind == .overview, let table = filteredSection.table {
                OverviewAssociationView(table: table)
            } else if let table = filteredSection.table {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            GridRow {
                                ForEach(table.headers, id: \.self) { header in
                                    Text(header)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                            ForEach(table.rows) { row in
                                GridRow {
                                    ForEach(Array(row.columns.enumerated()), id: \.offset) { _, cell in
                                        Text(cell)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: 320, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(appState.selectedReportRowID == row.id ? PitcherPlantTheme.accentSoft : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedReportRowID = row.id
                                }
                                Divider()
                            }
                        }
                    }

                    if let selectedRow = resolvedSelectedRow {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(selectedRow.detailTitle)
                                    .font(.headline)
                                Spacer()
                                HStack(spacing: 8) {
                                    ForEach(selectedRow.badges, id: \.title) { badge in
                                        ReportBadgeView(badge: badge)
                                    }
                                }
                            }
                            Text(selectedRow.detailBody)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if !selectedRow.attachments.isEmpty {
                                ImageEvidenceDetailView(attachments: selectedRow.attachments)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .onAppear {
            syncVisibleSelection()
        }
        .onChange(of: filteredRows.map(\.id)) { _, _ in
            syncVisibleSelection()
        }
        .onChange(of: appState.selectedReportSection) { _, _ in
            syncVisibleSelection()
        }
    }

    private func syncVisibleSelection() {
        guard filteredRows.isEmpty == false else {
            appState.selectedReportRowID = nil
            return
        }
        if let selectedID = appState.selectedReportRowID,
           filteredRows.contains(where: { $0.id == selectedID }) {
            return
        }
        appState.selectedReportRowID = filteredRows.first?.id
    }
}

private struct ReportSectionToolbar: View {
    @Binding var evidenceQuery: String
    @Binding var evidenceFilter: ReportEvidenceFilter
    @Binding var evidenceSortOrder: ReportEvidenceSortOrder
    let visibleRowCount: Int
    let totalRowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("搜索当前章节证据", text: $evidenceQuery)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    Picker("排序", selection: $evidenceSortOrder) {
                        ForEach(ReportEvidenceSortOrder.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(evidenceSortOrder.title, systemImage: "arrow.up.arrow.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 12) {
                Picker("证据筛选", selection: $evidenceFilter) {
                    ForEach(ReportEvidenceFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Spacer()

                Text("\(visibleRowCount) / \(totalRowCount) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ImageEvidenceDetailView: View {
    let attachments: [ReportAttachment]

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.title)
                            .font(.subheadline.weight(.semibold))
                        Text(attachment.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let image = attachment.imageBase64.flatMap(decodedImage) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Text(attachment.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func decodedImage(_ value: String) -> NSImage? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
    }
}

private struct OverviewAssociationView: View {
    @Environment(AppState.self) private var appState
    let table: ReportTable

    private var maxWeight: Double {
        Double(table.rows.compactMap { Int($0.columns[safe: 2] ?? "") }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("严重作弊关联")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(table.rows.prefix(12)) { row in
                    Button {
                        appState.selectedReportRowID = row.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.detailTitle)
                                    .foregroundStyle(.primary)
                                    .fontWeight(.medium)
                                Spacer()
                                HStack(spacing: 8) {
                                    ForEach(row.badges, id: \.title) { badge in
                                        ReportBadgeView(badge: badge)
                                    }
                                }
                            }

                            GeometryReader { proxy in
                                let ratio = CGFloat((Double(row.columns[safe: 2].flatMap(Int.init) ?? 0)) / maxWeight)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .separatorColor).opacity(0.12))
                                        .frame(height: 10)
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(PitcherPlantTheme.accent)
                                        .frame(width: max(28, proxy.size.width * ratio), height: 10)
                                }
                            }
                            .frame(height: 10)

                            Text(row.columns[safe: 3] ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(appState.selectedReportRowID == row.id ? PitcherPlantTheme.accentSoft : Color(nsColor: .controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedRow = appState.selectedReportRow {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selectedRow.detailTitle)
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(selectedRow.badges, id: \.title) { badge in
                                ReportBadgeView(badge: badge)
                            }
                        }
                    }
                    Text(selectedRow.detailBody)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch badge.tone {
        case .neutral: return Color(nsColor: .separatorColor).opacity(0.18)
        case .accent: return PitcherPlantTheme.accentSoft
        case .warning: return Color.orange.opacity(0.16)
        case .danger: return Color.red.opacity(0.16)
        case .success: return Color.green.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch badge.tone {
        case .neutral: return .secondary
        case .accent: return PitcherPlantTheme.accent
        case .warning: return .orange
        case .danger: return .red
        case .success: return .green
        }
    }
}

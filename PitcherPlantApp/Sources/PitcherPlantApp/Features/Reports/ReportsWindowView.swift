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

private struct ReportLibrarySidebar: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]
    @Binding var reportQuery: String
    @Binding var reportFilter: ReportLibraryFilter

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedReportID },
            set: { appState.selectReport($0) }
        )) {
            if reports.isEmpty {
                ContentUnavailableView("无匹配报告", systemImage: "doc.text.magnifyingglass", description: Text("调整搜索或筛选条件。"))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(reports) { report in
                    ReportLibraryRow(report: report)
                        .tag(report.id)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $reportQuery, placement: .sidebar, prompt: "搜索报告")
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("报告中心")
                    .font(.headline)
                Picker("报告筛选", selection: $reportFilter) {
                    ForEach(ReportLibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct ReportLibraryRow: View {
    let report: AuditReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(report.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if report.isLegacy {
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
        .padding(.vertical, 3)
    }
}

private struct ReportSectionsAndEvidenceView: View {
    @Environment(AppState.self) private var appState
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

    var body: some View {
        if let report = appState.selectedReport {
            VStack(spacing: 0) {
                ReportContentHeader(report: report)
                Divider()

                HSplitView {
                    List(selection: Binding(
                        get: { appState.selectedReportSection },
                        set: { appState.selectReportSection($0) }
                    )) {
                        ForEach(report.sections) { section in
                            ReportSectionListRow(section: section)
                                .tag(Optional(section.kind))
                        }
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 210, idealWidth: 240, maxWidth: 280)

                    VStack(spacing: 0) {
                        EvidenceToolbar(
                            evidenceQuery: $evidenceQuery,
                            evidenceFilter: $evidenceFilter,
                            evidenceSortOrder: $evidenceSortOrder,
                            visibleRowCount: rows.count,
                            totalRowCount: selectedSection?.table?.rows.count ?? 0
                        )
                        Divider()

                        if let section = selectedSection {
                            EvidenceList(section: section, rows: rows)
                        } else {
                            ContentUnavailableView("未选择章节", systemImage: "list.bullet.rectangle", description: Text("选择一个章节查看证据。"))
                        }
                    }
                    .frame(minWidth: 320)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                if appState.selectedReportSection == nil {
                    appState.selectReportSection(report.sections.first?.kind)
                }
                syncVisibleEvidenceSelection()
            }
            .onChange(of: rows.map(\.id)) { _, _ in syncVisibleEvidenceSelection() }
            .onChange(of: appState.selectedReportSection) { _, _ in syncVisibleEvidenceSelection() }
        } else {
            ContentUnavailableView("暂无报告", systemImage: "doc.text", description: Text("完成一次审计或导入旧报告后会显示在这里。"))
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
    let report: AuditReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if report.isLegacy {
                    Text("Legacy")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 24) {
                ForEach(report.metrics.prefix(4), id: \.title) { metric in
                    Label {
                        Text(metric.value)
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: metric.systemImage)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(20)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ReportSectionListRow: View {
    let section: ReportSection

    private var rowCount: Int {
        section.table?.rows.count ?? 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: section.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(section.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if rowCount > 0 {
                Text("\(rowCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

private struct EvidenceToolbar: View {
    @Binding var evidenceQuery: String
    @Binding var evidenceFilter: ReportEvidenceFilter
    @Binding var evidenceSortOrder: ReportEvidenceSortOrder
    let visibleRowCount: Int
    let totalRowCount: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("搜索当前章节证据", text: $evidenceQuery)
                    .textFieldStyle(.roundedBorder)
                Picker("筛选", selection: $evidenceFilter) {
                    ForEach(ReportEvidenceFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack {
                Menu {
                    Picker("排序", selection: $evidenceSortOrder) {
                        ForEach(ReportEvidenceSortOrder.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(evidenceSortOrder.title, systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                Spacer()
                Text("\(visibleRowCount) / \(totalRowCount) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            ContentUnavailableView("无匹配证据", systemImage: "line.3.horizontal.decrease.circle", description: Text("当前章节没有符合搜索和筛选条件的记录。"))
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
    let headers: [String]

    var body: some View {
        HStack(spacing: 12) {
            Text(headers[safe: 0] ?? "对象 A")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(headers[safe: 1] ?? "对象 B")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(headers[safe: 2] ?? "分数")
                .frame(width: 70, alignment: .trailing)
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

                    InspectorSection(title: "证据详情") {
                        Text(row.detailBody)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !row.attachments.isEmpty {
                        InspectorSection(title: "附件") {
                            ImageEvidenceDetailView(attachments: row.attachments)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView {
                Label("No Evidence Selected", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Select an evidence row to view details")
            }
        }
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

                    if let image = attachment.imageBase64.flatMap(decodedImage) {
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

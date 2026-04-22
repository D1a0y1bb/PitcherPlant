import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(selection: Binding(
                get: { appState.selectedReportID },
                set: { appState.selectReport($0) }
            )) {
                ForEach(appState.reports) { report in
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
}

private struct ReportDetailView: View {
    @Environment(AppState.self) private var appState

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
                        ReportSectionView(section: section)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title3.weight(.semibold))
            Text(section.summary)
                .foregroundStyle(.secondary)

            if !section.callouts.isEmpty {
                ForEach(section.callouts, id: \.self) { item in
                    Label(item, systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if section.kind == .overview, let table = section.table {
                OverviewAssociationView(table: table)
            } else if let table = section.table {
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
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
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

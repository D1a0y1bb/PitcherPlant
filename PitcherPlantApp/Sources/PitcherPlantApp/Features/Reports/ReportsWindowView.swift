import SwiftUI

struct ReportsWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(selection: $state.selectedReportID) {
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
                    set: { appState.selectedReportSection = $0 }
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
                        appState.selectedReportSection = report.sections.first?.kind
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

                    if let section = report.sections.first(where: { $0.kind == appState.selectedReportSection }) ?? report.sections.first {
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

            if let table = section.table {
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
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(row, id: \.self) { cell in
                                    Text(cell)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: 320, alignment: .leading)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

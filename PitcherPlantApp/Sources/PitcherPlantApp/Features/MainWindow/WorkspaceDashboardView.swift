import SwiftUI

private let workspaceFirstRowTopOffset: CGFloat = -6
private let workspaceDashboardSpacing: CGFloat = 18
private let workspaceStatusColumnMinimumWidth: CGFloat = 96
private let workspaceStatusColumnSpacing: CGFloat = 14
private let workspaceCardIconWidth: CGFloat = 22
private let workspaceCardIconFont: Font = AppTypography.rowPrimary
private let workspaceStatusLabelSpacing: CGFloat = 8
private let workspaceStatusLabelValueSpacing: CGFloat = 8
private let workspaceStatusRowsMinimumHeight: CGFloat = 120
private let workspaceStatusRowsSpacing: CGFloat = 30

struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        AppPageShell(spacing: workspaceDashboardSpacing) {
            dashboardRow {
                auditStatusCard
            } trailing: {
                evidenceStatusCard
            }
            .padding(.top, workspaceFirstRowTopOffset)

            dashboardRow {
                recentJobsCard
            } trailing: {
                recentReportsCard
            }

            evidenceOverviewCard
        }
    }

    @ViewBuilder
    private func dashboardRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                trailing()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 18) {
                leading()
                trailing()
            }
        }
    }

    private var reportCount: Int {
        max(appState.reportTotalCount, appState.reports.count)
    }

    private var fingerprintCount: Int {
        max(appState.fingerprintTotalCount, appState.fingerprints.count)
    }

    private var latestJob: AuditJob? {
        appState.jobs.max { lhs, rhs in
            lhs.updatedAt < rhs.updatedAt
        }
    }

    private var queuedCount: Int {
        appState.jobs.filter { $0.status == .queued }.count
    }

    private var runningCount: Int {
        appState.jobs.filter { $0.status == .running }.count
    }

    private var completedCount: Int {
        appState.jobs.filter { $0.status == .succeeded }.count
    }

    private var failedCount: Int {
        appState.jobs.filter { $0.status == .failed }.count
    }

    private var latestProgressText: String {
        guard let latestJob else {
            return "0"
        }
        return "\(latestJob.progress)"
    }

    private var latestStatusText: String {
        guard let latestJob else {
            return appState.t("status.ready")
        }
        return appState.title(for: latestJob.status)
    }

    private var latestDirectoryName: String {
        guard let latestJob else {
            return appState.t("common.none")
        }
        return URL(fileURLWithPath: latestJob.configuration.directoryPath).lastPathComponent
    }

    private var currentReportDirectoryName: String {
        URL(fileURLWithPath: appState.draftConfiguration.outputDirectoryPath).lastPathComponent
    }

    private var totalEvidenceRows: Int {
        evidenceOverviewItems.reduce(0) { partial, item in
            partial + item.count
        }
    }

    private var evidenceOverviewItems: [WorkspaceEvidenceOverviewItem] {
        [
            evidenceOverviewItem(kind: .text, tint: .cyan),
            evidenceOverviewItem(kind: .code, tint: .purple),
            evidenceOverviewItem(kind: .image, tint: .teal),
            evidenceOverviewItem(kind: .metadata, tint: .blue),
            evidenceOverviewItem(kind: .dedup, tint: .orange),
            evidenceOverviewItem(kind: .crossBatch, tint: .pink)
        ]
    }

    private var sortedEvidenceOverviewItems: [WorkspaceEvidenceOverviewItem] {
        let sorted = evidenceOverviewItems.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.title < rhs.title
            }
            return lhs.count > rhs.count
        }
        return totalEvidenceRows > 0 ? sorted : evidenceOverviewItems
    }

    private var topEvidenceOverviewItems: [WorkspaceEvidenceOverviewItem] {
        Array(sortedEvidenceOverviewItems.prefix(3))
    }

    private var lowEvidenceOverviewItems: [WorkspaceEvidenceOverviewItem] {
        Array(sortedEvidenceOverviewItems.dropFirst(3))
    }

    private var auditStatusCard: some View {
        WorkspaceDashboardCard(
            title: appState.t("workspace.auditStatus"),
            subtitle: latestStatusText,
            systemImage: "waveform.path.ecg",
            tint: .blue,
            minHeight: 206
        ) {
            WorkspaceStatusRows(
                metrics: [
                    WorkspaceMetric(title: appState.t("workspace.summary.jobs"), value: "\(appState.jobs.count)", systemImage: "clock.arrow.circlepath", tint: .blue),
                    WorkspaceMetric(title: appState.t("status.running"), value: "\(runningCount)", systemImage: "play.circle", tint: .green),
                    WorkspaceMetric(title: appState.t("workspace.latestProgress"), value: latestProgressText, unit: "%", systemImage: "gauge.with.dots.needle.50percent", tint: .orange)
                ],
                facts: [
                    WorkspaceFact(title: appState.t("status.succeeded"), value: "\(completedCount)", systemImage: "checkmark.circle.fill", tint: .green),
                    WorkspaceFact(title: appState.t("status.failed"), value: "\(failedCount)", systemImage: "exclamationmark.triangle.fill", tint: .orange),
                    WorkspaceFact(title: appState.t("status.queued"), value: "\(queuedCount)", systemImage: "clock", tint: .indigo)
                ]
            )
        }
    }

    private var evidenceStatusCard: some View {
        WorkspaceDashboardCard(
            title: appState.t("workspace.evidenceStatus"),
            subtitle: appState.tf("workspace.evidenceStatusSubtitle", totalEvidenceRows),
            systemImage: "checklist.checked",
            tint: .green,
            minHeight: 206
        ) {
            WorkspaceStatusRows(
                metrics: [
                    WorkspaceMetric(title: appState.t("workspace.summary.reports"), value: "\(reportCount)", systemImage: "doc.text", tint: .indigo),
                    WorkspaceMetric(title: appState.t("workspace.summary.fingerprints"), value: "\(fingerprintCount)", systemImage: "number", tint: .cyan),
                    WorkspaceMetric(title: appState.t("workspace.summary.whitelist"), value: "\(appState.whitelistRules.count)", systemImage: "checkmark.shield", tint: .green)
                ],
                facts: [
                    WorkspaceFact(title: appState.t("audit.visionOCR"), value: appState.draftConfiguration.useVisionOCR ? appState.t("common.enabled") : appState.t("common.disabled"), systemImage: "text.viewfinder", tint: .blue),
                    WorkspaceFact(title: appState.t("audit.whitelistMode"), value: appState.title(for: appState.draftConfiguration.whitelistMode), systemImage: "slider.horizontal.3", tint: .purple),
                    WorkspaceFact(title: appState.t("workspace.reportDirectory"), value: currentReportDirectoryName, systemImage: "folder.badge.gearshape", tint: .orange)
                ]
            )
        }
    }

    private var recentJobsCard: some View {
        let recentJobs = Array(appState.jobs.prefix(1))

        return WorkspaceDashboardCard(
            title: appState.t("workspace.recentJobs"),
            subtitle: "\(recentJobs.count) \(appState.t("common.countSuffix"))",
            systemImage: "clock.arrow.circlepath",
            tint: .orange
        ) {
            RecentJobsCompactList(jobs: recentJobs)
        }
    }

    private var recentReportsCard: some View {
        let recentReports = Array(appState.reports.sorted(by: { $0.createdAt > $1.createdAt }).prefix(1))

        return WorkspaceDashboardCard(
            title: appState.t("workspace.recentReports"),
            subtitle: "\(recentReports.count) \(appState.t("common.countSuffix"))",
            systemImage: "doc.text.magnifyingglass",
            tint: .indigo
        ) {
            RecentReportsCompactList(reports: recentReports)
        }
    }

    private var evidenceOverviewCard: some View {
        WorkspaceDashboardCard(
            title: appState.t("workspace.evidenceOverview"),
            subtitle: appState.t("workspace.evidenceOverviewSubtitle"),
            systemImage: "chart.bar.xaxis",
            tint: .cyan,
            minHeight: 236
        ) {
            WorkspaceEvidenceSummary(
                totalTitle: appState.t("workspace.totalEvidence"),
                totalValue: "\(totalEvidenceRows)",
                topTitle: appState.t("workspace.topEvidence"),
                lowTitle: appState.t("workspace.lowEvidence"),
                totalCount: totalEvidenceRows,
                topItems: topEvidenceOverviewItems,
                lowItems: lowEvidenceOverviewItems
            )
        }
    }

    private func evidenceOverviewItem(kind: ReportSectionKind, tint: Color) -> WorkspaceEvidenceOverviewItem {
        WorkspaceEvidenceOverviewItem(
            title: appState.t(kind.localizationKey),
            count: appState.reports.reduce(0) { partial, report in
                partial + (report.displaySection(for: kind)?.table?.rows.count ?? 0)
            },
            systemImage: kind.systemImage,
            tint: tint
        )
    }
}

private struct WorkspaceMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var unit: String = ""
    let systemImage: String
    let tint: Color
}

private struct WorkspaceFact: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
}

private struct WorkspaceEvidenceOverviewItem: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color
}

private struct WorkspaceStatusRows: View {
    let metrics: [WorkspaceMetric]
    let facts: [WorkspaceFact]

    var body: some View {
        VStack(alignment: .leading, spacing: workspaceStatusRowsSpacing) {
            WorkspaceMetricGrid(metrics: metrics)
            WorkspaceFactStrip(items: facts)
        }
        .frame(maxWidth: .infinity, minHeight: workspaceStatusRowsMinimumHeight, alignment: .topLeading)
    }
}

private struct WorkspaceDashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var minHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    private var panelPadding: EdgeInsets {
        EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    private var contentMinHeight: CGFloat? {
        minHeight.map { max(0, $0 - panelPadding.top - panelPadding.bottom) }
    }

    var body: some View {
        InspectorPanelSurface(
            padding: panelPadding,
            cornerRadius: 18
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .center, spacing: workspaceStatusLabelSpacing) {
                        Image(systemName: systemImage)
                            .font(workspaceCardIconFont)
                            .foregroundStyle(tint)
                            .frame(width: workspaceCardIconWidth, alignment: .leading)
                        Text(title)
                            .font(AppTypography.sectionTitle)
                    }

                    Spacer(minLength: 12)

                    if subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Divider()
                    .opacity(0.65)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: contentMinHeight, alignment: .topLeading)
        }
    }
}

private struct WorkspaceMetricGrid: View {
    let metrics: [WorkspaceMetric]

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: workspaceStatusColumnMinimumWidth), spacing: workspaceStatusColumnSpacing),
            count: min(max(metrics.count, 1), 3)
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: workspaceStatusLabelValueSpacing) {
                    HStack(alignment: .center, spacing: workspaceStatusLabelSpacing) {
                        Image(systemName: metric.systemImage)
                            .font(workspaceCardIconFont)
                            .foregroundStyle(metric.tint)
                            .frame(width: workspaceCardIconWidth, alignment: .leading)
                        Text(metric.title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(AppTypography.metadata)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(metric.value)
                            .font(.title.weight(.semibold).monospacedDigit())

                        if metric.unit.isEmpty == false {
                            Text(metric.unit)
                                .font(AppTypography.supporting.weight(.semibold))
                        }
                    }
                    .foregroundStyle(metric.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, workspaceCardIconWidth + workspaceStatusLabelSpacing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct WorkspaceFactStrip: View {
    let items: [WorkspaceFact]

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: workspaceStatusColumnMinimumWidth), spacing: workspaceStatusColumnSpacing),
            count: min(max(items.count, 1), 3)
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    factItem(item)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    factItem(item)
                }
            }
        }
        .padding(.top, 2)
    }

    private func factItem(_ item: WorkspaceFact) -> some View {
        VStack(alignment: .leading, spacing: workspaceStatusLabelValueSpacing) {
            HStack(alignment: .center, spacing: workspaceStatusLabelSpacing) {
                Image(systemName: item.systemImage)
                    .font(workspaceCardIconFont)
                    .foregroundStyle(item.tint)
                    .frame(width: workspaceCardIconWidth, alignment: .leading)
                Text(item.title)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, workspaceCardIconWidth + workspaceStatusLabelSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceTotalEvidenceGauge: View {
    let title: String
    let value: String
    let count: Int

    private var progress: CGFloat {
        count > 0 ? 0.78 : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [.cyan, .blue, .purple, .cyan], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                Text(title)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkspaceEvidenceSummary: View {
    let totalTitle: String
    let totalValue: String
    let topTitle: String
    let lowTitle: String
    let totalCount: Int
    let topItems: [WorkspaceEvidenceOverviewItem]
    let lowItems: [WorkspaceEvidenceOverviewItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 22) {
                WorkspaceTotalEvidenceGauge(
                    title: totalTitle,
                    value: totalValue,
                    count: totalCount
                )
                .frame(width: 150)

                Divider()

                evidenceColumn(title: topTitle) {
                    WorkspaceEvidenceBarList(items: topItems)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                evidenceColumn(title: lowTitle) {
                    WorkspaceLowEvidenceList(items: lowItems)
                }
                .frame(width: 180, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                WorkspaceTotalEvidenceGauge(
                    title: totalTitle,
                    value: totalValue,
                    count: totalCount
                )

                evidenceColumn(title: topTitle) {
                    WorkspaceEvidenceBarList(items: topItems)
                }

                evidenceColumn(title: lowTitle) {
                    WorkspaceLowEvidenceList(items: lowItems)
                }
            }
        }
    }

    private func evidenceColumn<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
        }
    }
}

private extension ReportSectionKind {
    var localizationKey: String {
        switch self {
        case .overview: return "section.overview"
        case .text: return "section.text"
        case .code: return "section.code"
        case .image: return "section.image"
        case .metadata: return "section.metadata"
        case .dedup: return "section.dedup"
        case .fingerprints: return "section.fingerprints"
        case .crossBatch: return "section.crossBatch"
        }
    }
}

private struct WorkspaceEvidenceBarList: View {
    let items: [WorkspaceEvidenceOverviewItem]

    private var maxCount: Int {
        max(items.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: workspaceStatusLabelSpacing) {
                        Image(systemName: item.systemImage)
                            .font(workspaceCardIconFont)
                            .foregroundStyle(item.tint)
                            .frame(width: workspaceCardIconWidth, alignment: .leading)
                        Text(item.title)
                            .font(AppTypography.metadata.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .font(AppTypography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(item.tint)
                                .frame(width: max(6, proxy.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

private struct WorkspaceLowEvidenceList: View {
    let items: [WorkspaceEvidenceOverviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: workspaceStatusLabelSpacing) {
                    Image(systemName: item.systemImage)
                        .font(workspaceCardIconFont)
                        .foregroundStyle(item.tint)
                        .frame(width: workspaceCardIconWidth, alignment: .leading)
                    Text(item.title)
                        .font(AppTypography.metadata.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(item.count)")
                        .font(AppTypography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RecentJobsCompactList: View {
    @Environment(AppState.self) private var appState
    let jobs: [AuditJob]

    var body: some View {
        VStack(spacing: 0) {
            if jobs.isEmpty {
                WorkspaceEmptyDashboardState(
                    title: appState.t("job.noSelection"),
                    subtitle: appState.t("job.noSelectionDescription"),
                    systemImage: "clock.badge.questionmark"
                )
            } else {
                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                    Button {
                        appState.selectedJobID = job.id
                        appState.selectedMainSidebar = .history
                        appState.requestInspector()
                    } label: {
                        WorkspacePreviewRow(
                            title: URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent,
                            subtitle: job.updatedAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: job.status.systemImage,
                            tint: job.status.dashboardTint,
                            trailingValue: "\(job.progress)%",
                            trailingCaption: appState.title(for: job.status)
                        )
                    }
                    .buttonStyle(.plain)
                    if index < jobs.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct RecentReportsCompactList: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]

    var body: some View {
        VStack(spacing: 0) {
            if reports.isEmpty {
                WorkspaceEmptyDashboardState(
                    title: appState.t("reports.noReport"),
                    subtitle: appState.t("reports.noReportDescription"),
                    systemImage: "doc.text"
                )
            } else {
                ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                    Button {
                        appState.showReport(report.id)
                    } label: {
                        WorkspacePreviewRow(
                            title: report.title,
                            subtitle: report.createdAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "doc.text.magnifyingglass",
                            tint: .indigo,
                            trailingValue: "\(report.sections.count)",
                            trailingCaption: appState.t("reports.sectionSummary")
                        )
                    }
                    .buttonStyle(.plain)
                    if index < reports.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct WorkspacePreviewRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var trailingValue: String = ""
    var trailingCaption: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: systemImage)
                .font(workspaceCardIconFont)
                .foregroundStyle(tint)
                .frame(width: workspaceCardIconWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if trailingValue.isEmpty == false {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(trailingValue)
                        .font(AppTypography.rowPrimary.monospacedDigit())
                        .lineLimit(1)
                    if trailingCaption.isEmpty == false {
                        Text(trailingCaption)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceEmptyDashboardState: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(workspaceCardIconFont)
                .foregroundStyle(.secondary)
                .frame(width: workspaceCardIconWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowPrimary)
                Text(subtitle)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

private extension AuditJobStatus {
    var dashboardTint: Color {
        switch self {
        case .queued: return .gray
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .orange
        }
    }
}

private struct RecentJobsTable: View {
    @Environment(AppState.self) private var appState
    let jobs: [AuditJob]

    var body: some View {
        AppHorizontalOverflow(minWidth: AppLayout.workspaceTableMinWidth, fitsContentHeight: true) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    tableHeader(appState.t("audit.directory"))
                    tableHeader(appState.t("common.type"))
                    tableHeader("Progress")
                    tableHeader(appState.t("common.updatedAt"))
                }

                ForEach(jobs) { job in
                    GridRow {
                        Button {
                            appState.selectedJobID = job.id
                            appState.selectedMainSidebar = .history
                            appState.requestInspector()
                        } label: {
                            Label(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent, systemImage: job.status.systemImage)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .gridColumnAlignment(.leading)

                        Text(job.status.displayTitle)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)

                        Text("\(job.progress)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)

                        Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)
                    }
                    .font(AppTypography.rowSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
    }
}

private struct RecentReportsTable: View {
    @Environment(AppState.self) private var appState
    let reports: [AuditReport]

    var body: some View {
        AppHorizontalOverflow(minWidth: AppLayout.workspaceTableMinWidth, fitsContentHeight: true) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    tableHeader("Title")
                    tableHeader(appState.t("reports.sectionSummary"))
                    tableHeader(appState.t("common.createdAt"))
                }

                ForEach(reports) { report in
                    GridRow {
                        Button {
                            appState.showReport(report.id)
                        } label: {
                            Label(report.title, systemImage: "doc.text.magnifyingglass")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .gridColumnAlignment(.leading)

                        Text("\(report.sections.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 88, alignment: .leading)

                        Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)
                    }
                    .font(AppTypography.rowSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
    }
}


struct NewAuditView: View {
    @Environment(AppState.self) private var appState
    @State private var presetName = ""

    var body: some View {
        NativePage {
            NativePageHeader(
                title: appState.t("audit.title"),
                subtitle: appState.t("audit.subtitle"),
                actions: {
                    Button {
                        appState.toggleAudit()
                    } label: {
                        Label(
                            appState.isRunningAudit ? appState.t("command.cancelAudit") : appState.t("command.startAudit"),
                            systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                        )
                    }
                }
            )

            NativeSection(title: appState.t("audit.paths"), subtitle: appState.t("audit.paths.subtitle")) {
                VStack(spacing: 0) {
                    SettingsTextRow(title: appState.t("audit.directory"), text: Binding(
                        get: { appState.draftConfiguration.directoryPath },
                        set: { newValue in appState.updateDraft { $0.directoryPath = newValue } }
                    ))
                    SettingsTextRow(title: appState.t("audit.outputDirectory"), text: Binding(
                        get: { appState.draftConfiguration.outputDirectoryPath },
                        set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                    ))
                }
            }

            NativeSection(title: appState.t("audit.batchImport"), subtitle: appState.t("audit.batchImport.subtitle")) {
                AppControlRow(title: appState.t("audit.batchImport"), subtitle: appState.t("audit.batchImport.description"), trailingWidth: 190) {
                    Button {
                        appState.importSubmissionPackageWithPanel()
                    } label: {
                        Label(appState.t("audit.importSubmissions"), systemImage: "tray.and.arrow.down")
                    }
                    .disabled(appState.isImportingSubmissionPackage)
                }
            }

            NativeSection(title: appState.t("audit.parameters"), subtitle: appState.t("audit.parameters.subtitle")) {
                VStack(spacing: 0) {
                    SettingsNumberRow(title: appState.t("audit.textThreshold"), value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    SettingsNumberRow(title: appState.t("audit.dedupThreshold"), value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    SettingsIntegerRow(title: appState.t("audit.imageThreshold"), value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ))
                    SettingsIntegerRow(title: appState.t("audit.simhashThreshold"), value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ))
                    AppControlRow(title: appState.t("audit.visionOCR"), trailingWidth: 80) {
                        Toggle("", isOn: Binding(
                            get: { appState.draftConfiguration.useVisionOCR },
                            set: { newValue in appState.updateDraft { $0.useVisionOCR = newValue } }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(Text(appState.t("audit.visionOCR")))
                    }
                    AppControlRow(title: appState.t("audit.whitelistMode"), trailingWidth: 180) {
                        Picker("", selection: Binding(
                            get: { appState.draftConfiguration.whitelistMode },
                            set: { newValue in appState.updateDraft { $0.whitelistMode = newValue } }
                        )) {
                            ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                                Text(appState.title(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .accessibilityLabel(Text(appState.t("audit.whitelistMode")))
                    }
                }
            }

            NativeSection(title: appState.t("audit.preset"), subtitle: appState.t("audit.preset.subtitle")) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        TextField(appState.t("audit.presetName"), text: $presetName)
                            .textFieldStyle(.roundedBorder)
                        Button(appState.t("audit.saveCurrent")) {
                            let name = presetName
                            presetName = ""
                            appState.saveCurrentConfigurationPreset(named: name)
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, AppLayout.rowHorizontalPadding)
                    .padding(.vertical, AppLayout.rowVerticalPadding)

                    if appState.configurationPresets.isEmpty {
                        EmptyInlineRow(title: appState.t("audit.emptyPreset"), subtitle: appState.t("audit.preset.subtitle"), systemImage: "slider.horizontal.3")
                    } else {
                        ForEach(appState.configurationPresets) { preset in
                            PresetTableRow(preset: preset)
                        }
                    }
                }
            }
        }
    }

}

private struct EmptyInlineRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowPrimary)
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 18)
    }
}

import SwiftUI

struct MetricCard: View {
    let metric: ReportMetric

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(metric.title, systemImage: metric.systemImage)
                    .foregroundStyle(.secondary)
                    .font(AppTypography.supporting)
                Text(metric.value)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .groupBoxStyle(.automatic)
    }
}

struct StatusBadge: View {
    @Environment(AppState.self) private var appState
    let status: AuditJobStatus

    var body: some View {
        Text(appState.title(for: status))
            .font(AppTypography.badge)
            .foregroundStyle(.secondary)
    }
}

import SwiftUI

enum PitcherPlantTheme {
    static let accent = Color(red: 0.12, green: 0.53, blue: 0.42)
    static let accentSoft = Color(red: 0.88, green: 0.96, blue: 0.93)
    static let warning = Color(red: 0.82, green: 0.45, blue: 0.22)
    static let danger = Color(red: 0.73, green: 0.23, blue: 0.22)
}

struct MetricCard: View {
    let metric: ReportMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(metric.title, systemImage: metric.systemImage)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(metric.value)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StatusBadge: View {
    @Environment(AppState.self) private var appState
    let status: AuditJobStatus

    var body: some View {
        Text(appState.title(for: status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .queued: return Color(nsColor: .separatorColor).opacity(0.18)
        case .running: return PitcherPlantTheme.accentSoft
        case .succeeded: return Color.green.opacity(0.16)
        case .failed: return Color.red.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .queued: return .secondary
        case .running: return PitcherPlantTheme.accent
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

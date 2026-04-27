import SwiftUI

struct PresetTableRow: View {
    @Environment(AppState.self) private var appState
    let preset: AuditConfigurationPreset

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(AppTypography.rowPrimary)
                    .fontWeight(.medium)
                Text(URL(fileURLWithPath: preset.configuration.directoryPath).lastPathComponent)
                    .font(AppTypography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(appState.t("audit.applyPreset")) { appState.applyPreset(preset) }
            Button(appState.t("audit.runPreset")) {
                appState.beginAudit(using: preset)
            }
                .disabled(appState.isRunningAudit)
            Button(role: .destructive) {
                appState.deletePreset(preset)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }
}

struct JobTableRow: View {
    let job: AuditJob

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: job.status)
            Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(status: job.status)
                .frame(width: 74, alignment: .trailing)
            Text("\(job.progress)%")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .trailing)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct AuditReportListRow: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        HStack(spacing: 12) {
            Text(report.title)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if report.isLegacy {
                PillLabel(title: "Legacy", tint: .orange)
                    .frame(width: 74, alignment: .trailing)
            } else {
                Text(appState.t("common.native"))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }
            Text("\(report.sections.count)")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .trailing)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct FingerprintTableRow: View {
    let record: FingerprintRecord

    private var tagSummary: String {
        let values = [record.batchName, record.challengeName, record.teamName].compactMap { $0 } + (record.tags ?? [])
        return values.isEmpty ? "-" : values.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(record.filename)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.ext.uppercased())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(record.scanDir)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(tagSummary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(record.simhash)
                .font(AppTypography.smallCode)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .trailing)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct WhitelistTableRow: View {
    @Environment(AppState.self) private var appState
    let rule: WhitelistRule

    var body: some View {
        HStack(spacing: 12) {
            Text(rule.pattern)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(appState.title(for: rule.type))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(rule.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)
            Button(role: .destructive) {
                Task { await appState.removeWhitelistRule(rule) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .font(AppTypography.rowSecondary)
        .padding(.vertical, 7)
    }
}

struct TimelineEventRow: View {
    let event: AuditJobEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(AppTypography.rowSecondary)
                Text("\(event.progress)% · \(event.timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

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
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
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
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
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
            Text("\(report.sections.count)")
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
                .frame(width: 128, alignment: .trailing)
        }
        .font(AppTypography.rowSecondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(record.filename)
                    .font(AppTypography.rowPrimary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([record.scanDir, tagSummary].filter { $0 != "-" }.joined(separator: " · "))
                    .font(AppTypography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(record.ext.uppercased())
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
                Text(record.simhash)
                    .font(AppTypography.smallCode)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
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
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 7)
    }
}

struct TimelineEventRow: View {
    let event: AuditJobEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(AppTypography.badge)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(AppTypography.rowSecondary)
                Text(event.metadataLine)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 9)
    }
}

private extension AuditJobEvent {
    var metadataLine: String {
        var parts = ["\(progress)%"]
        if let stage {
            parts.append(stage.displayTitle)
        }
        if let processedCount {
            parts.append("处理 \(processedCount)")
        }
        if let failedCount, failedCount > 0 {
            parts.append("失败 \(failedCount)")
        }
        if let duration {
            parts.append(String(format: "%.2fs", duration))
        }
        parts.append(timestamp.formatted(date: .abbreviated, time: .standard))
        return parts.joined(separator: " · ")
    }
}

import SwiftUI

struct PresetTableRow: View {
    @Environment(AppState.self) private var appState
    let preset: AuditConfigurationPreset

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowIcon(style: .calibrationPreset)

                presetText
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(appState.t("audit.applyPreset")) {
                        appState.applyPreset(preset)
                    }
                    .accessibilityLabel(Text(appState.tf("audit.applyPreset.accessibility", preset.name)))

                    Button(appState.t("audit.runPreset")) {
                        appState.beginAudit(using: preset)
                    }
                    .disabled(appState.isRunningAudit)
                    .accessibilityLabel(Text(appState.tf("audit.runPreset.accessibility", preset.name)))

                    Button(role: .destructive) {
                        appState.deletePreset(preset)
                    } label: {
                        Label(appState.t("audit.deletePreset"), systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .help(appState.t("audit.deletePreset"))
                    .accessibilityLabel(Text(appState.tf("audit.deletePreset.accessibility", preset.name)))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var presetText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.name)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(URL(fileURLWithPath: preset.configuration.directoryPath).lastPathComponent)
                .font(AppTypography.rowSecondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct JobTableRow: View {
    @Environment(AppState.self) private var appState
    let job: AuditJob
    var isSelected = false

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowIcon(style: SettingsRowIconStyle(systemImage: job.status.systemImage, color: .orange))

                jobText
                    .frame(maxWidth: .infinity, alignment: .leading)

                jobMetadata
            }
        }
        .background {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var jobText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                .font(AppTypography.rowPrimary)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(job.latestMessage.isEmpty ? appState.title(for: job.stage) : job.latestMessage)
                .font(AppTypography.rowSecondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var jobMetadata: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 8) {
                StatusBadge(status: job.status)

                Text("\(job.progress)%")
                    .font(AppTypography.rowSecondary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if job.failureCount > 0 {
                    Text(appState.tf("job.failureCountShort", job.failureCount))
                        .font(AppTypography.rowSecondary)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }

            Text(job.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(width: 220, alignment: .trailing)
    }
}

struct AuditReportListRow: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowIcon(style: .reportLibrary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(AppTypography.rowPrimary)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(report.scanDirectoryPath)
                        .font(AppTypography.rowSecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(appState.tf("reports.sectionCount", report.sections.count))
                        .font(AppTypography.rowSecondary)
                        .foregroundStyle(.secondary)
                    Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 160, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsInlineEmptyRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowIcon(style: SettingsRowIconStyle(systemImage: systemImage, color: .gray))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.rowPrimary)
                    Text(subtitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
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
                Label(appState.t("whitelist.deleteRule"), systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(appState.t("whitelist.deleteRule"))
            .accessibilityLabel(Text(appState.t("whitelist.deleteRule")))
        }
        .font(AppTypography.rowSecondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, appState.appSettings.compactRows ? 5 : 9)
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

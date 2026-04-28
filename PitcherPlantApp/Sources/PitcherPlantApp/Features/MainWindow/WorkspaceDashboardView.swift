import SwiftUI

struct WorkspaceDashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NativePage {
            NativePageHeader(
                title: appState.t("workspace.title"),
                subtitle: "\(appState.jobs.count) \(appState.t("status.audits")) · \(appState.reports.count) \(appState.t("status.reports")) · \(appState.fingerprints.count) \(appState.t("status.fingerprints"))",
                actions: {
                    Button {
                        appState.importSubmissionPackageWithPanel()
                    } label: {
                        Label(appState.t("audit.importSubmissions"), systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.toggleAudit()
                    } label: {
                        Label(
                            appState.isRunningAudit ? appState.t("command.cancelAudit") : appState.t("command.startAudit"),
                            systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                        )
                    }

                    Button {
                        appState.showReportsCenter()
                    } label: {
                        Label(appState.t("workspace.reportCenter"), systemImage: "sidebar.right")
                    }
                }
            )

            SummaryStrip(items: [
                SummaryItem(title: appState.t("workspace.summary.jobs"), value: "\(appState.jobs.count)", systemImage: "clock.arrow.circlepath"),
                SummaryItem(title: appState.t("workspace.summary.reports"), value: "\(appState.reports.count)", systemImage: "doc.text"),
                SummaryItem(title: appState.t("workspace.summary.fingerprints"), value: "\(appState.fingerprints.count)", systemImage: "number"),
                SummaryItem(title: appState.t("workspace.summary.whitelist"), value: "\(appState.whitelistRules.count)", systemImage: "checkmark.shield")
            ])

            NativeSection(title: appState.t("workspace.recentJobs"), subtitle: "\(min(appState.jobs.count, 8)) \(appState.t("common.countSuffix"))") {
                VStack(spacing: 0) {
                    DenseHeader(columns: [appState.t("audit.directory"), appState.t("common.type"), "Progress", appState.t("common.updatedAt")])
                    if appState.jobs.isEmpty {
                        EmptyInlineRow(title: appState.t("job.noSelection"), subtitle: appState.t("job.noSelectionDescription"), systemImage: "clock.badge.questionmark")
                    } else {
                        ForEach(appState.jobs.prefix(8)) { job in
                            Button {
                                appState.selectedJobID = job.id
                                appState.selectedMainSidebar = .history
                            } label: {
                                JobTableRow(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            NativeSection(title: appState.t("workspace.recentReports"), subtitle: "\(min(appState.reports.count, 8)) \(appState.t("common.countSuffix"))") {
                VStack(spacing: 0) {
                    DenseHeader(columns: ["Title", appState.t("common.type"), appState.t("reports.sectionSummary"), appState.t("common.createdAt")])
                    if appState.reports.isEmpty {
                        EmptyInlineRow(title: appState.t("reports.noReport"), subtitle: appState.t("reports.noReportDescription"), systemImage: "doc.text")
                    } else {
                        ForEach(appState.reports.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8)) { report in
                            Button {
                                appState.showReport(report.id)
                            } label: {
                                AuditReportListRow(report: report)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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
                    SettingsTextRow(title: appState.t("audit.fileNameTemplate"), text: Binding(
                        get: { appState.draftConfiguration.reportNameTemplate },
                        set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
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

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
                    ForEach(appState.jobs.prefix(8)) { job in
                        Button {
                            appState.selectedJobID = job.id
                            appState.selectedMainSidebar = .history
                        } label: {
                            JobTableRow(job: job)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }

            NativeSection(title: appState.t("workspace.recentReports"), subtitle: "\(min(appState.reports.count, 8)) \(appState.t("common.countSuffix"))") {
                VStack(spacing: 0) {
                    DenseHeader(columns: ["Title", appState.t("common.type"), appState.t("reports.sectionSummary"), appState.t("common.createdAt")])
                    ForEach(appState.reports.sorted(by: { $0.createdAt > $1.createdAt }).prefix(8)) { report in
                        Button {
                            appState.showReport(report.id)
                        } label: {
                            AuditReportListRow(report: report)
                        }
                        .buttonStyle(.plain)
                        Divider()
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
                    Divider()
                    SettingsTextRow(title: appState.t("audit.outputDirectory"), text: Binding(
                        get: { appState.draftConfiguration.outputDirectoryPath },
                        set: { newValue in appState.updateDraft { $0.outputDirectoryPath = newValue } }
                    ))
                    Divider()
                    SettingsTextRow(title: appState.t("audit.fileNameTemplate"), text: Binding(
                        get: { appState.draftConfiguration.reportNameTemplate },
                        set: { newValue in appState.updateDraft { $0.reportNameTemplate = newValue } }
                    ))
                }
            }

            NativeSection(title: appState.t("audit.batchImport"), subtitle: appState.t("audit.batchImport.subtitle")) {
                HStack(spacing: 12) {
                    Label(appState.t("audit.batchImport.description"), systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        appState.importSubmissionPackageWithPanel()
                    } label: {
                        Label(appState.t("audit.importSubmissions"), systemImage: "tray.and.arrow.down")
                    }
                }
                .padding(.vertical, 8)
            }

            NativeSection(title: appState.t("audit.parameters"), subtitle: appState.t("audit.parameters.subtitle")) {
                VStack(spacing: 0) {
                    SettingsNumberRow(title: appState.t("audit.textThreshold"), value: Binding(
                        get: { appState.draftConfiguration.textThreshold },
                        set: { newValue in appState.updateDraft { $0.textThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsNumberRow(title: appState.t("audit.dedupThreshold"), value: Binding(
                        get: { appState.draftConfiguration.dedupThreshold },
                        set: { newValue in appState.updateDraft { $0.dedupThreshold = newValue } }
                    ), format: .number.precision(.fractionLength(2)))
                    Divider()
                    SettingsIntegerRow(title: appState.t("audit.imageThreshold"), value: Binding(
                        get: { appState.draftConfiguration.imageThreshold },
                        set: { newValue in appState.updateDraft { $0.imageThreshold = newValue } }
                    ))
                    Divider()
                    SettingsIntegerRow(title: appState.t("audit.simhashThreshold"), value: Binding(
                        get: { appState.draftConfiguration.simhashThreshold },
                        set: { newValue in appState.updateDraft { $0.simhashThreshold = newValue } }
                    ))
                    Divider()
                    HStack {
                        Text(appState.t("audit.visionOCR"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.draftConfiguration.useVisionOCR },
                            set: { newValue in appState.updateDraft { $0.useVisionOCR = newValue } }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 9)
                    Divider()
                    HStack {
                        Text(appState.t("audit.whitelistMode"))
                        Spacer()
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
                    .padding(.vertical, 9)
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
                    .padding(.vertical, 8)

                    if appState.configurationPresets.isEmpty {
                        Text(appState.t("audit.emptyPreset"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        Divider()
                        ForEach(appState.configurationPresets) { preset in
                            PresetTableRow(preset: preset)
                            Divider()
                        }
                    }
                }
            }
        }
    }

}

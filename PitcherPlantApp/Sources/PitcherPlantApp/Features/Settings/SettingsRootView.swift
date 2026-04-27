import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @Binding private var searchText: String

    init(searchText: Binding<String> = .constant("")) {
        _searchText = searchText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsGroup(title: appState.t("settings.general")) {
                    SettingsPickerRow(
                        title: appState.t("settings.language"),
                        subtitle: appState.t("settings.languageDescription")
                    ) {
                        SettingsMenuPicker(
                            selection: settingsBinding(\.language),
                            options: AppLanguage.allCases,
                            width: SettingsLayout.menuWidth,
                            title: languageTitle
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.menuBar"),
                        subtitle: appState.t("settings.menuBarDescription"),
                        isOn: settingsBinding(\.showMenuBarExtra)
                    )

                    SettingsDivider()

                    SettingsReadOnlyPathRow(
                        title: appState.t("settings.workspace"),
                        subtitle: appState.t("settings.workspaceDescription"),
                        value: appState.workspaceRoot.path
                    )
                }

                SettingsGroup(title: appState.t("settings.appearance")) {
                    SettingsPickerRow(
                        title: appState.t("settings.theme"),
                        subtitle: appState.t("settings.themeDescription")
                    ) {
                        SettingsMenuPicker(
                            selection: settingsBinding(\.appearance),
                            options: AppAppearance.allCases,
                            width: SettingsLayout.menuWidth,
                            title: appearanceTitle
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.inspectorDefault"),
                        subtitle: appState.t("settings.inspectorDefaultDescription"),
                        isOn: settingsBinding(\.showInspectorByDefault)
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.compactRows"),
                        subtitle: appState.t("settings.compactRowsDescription"),
                        isOn: settingsBinding(\.compactRows)
                    )
                }

                SettingsGroup(title: appState.t("settings.auditDefaults")) {
                    SettingsPathRow(
                        title: appState.t("audit.directory"),
                        subtitle: appState.t("settings.auditDirectoryDescription"),
                        text: draftBinding(\.directoryPath)
                    )

                    SettingsDivider()

                    SettingsPathRow(
                        title: appState.t("audit.outputDirectory"),
                        subtitle: appState.t("settings.reportDirectoryDescription"),
                        text: draftBinding(\.outputDirectoryPath)
                    )

                    SettingsDivider()

                    SettingsTextFieldRow(
                        title: appState.t("audit.fileNameTemplate"),
                        subtitle: appState.t("settings.fileNameTemplateDescription"),
                        text: draftBinding(\.reportNameTemplate)
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.textThreshold"),
                        subtitle: appState.t("settings.textThresholdDescription"),
                        value: draftDoubleBinding(\.textThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.dedupThreshold"),
                        subtitle: appState.t("settings.dedupThresholdDescription"),
                        value: draftDoubleBinding(\.dedupThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.imageThreshold"),
                        subtitle: appState.t("settings.imageThresholdDescription"),
                        value: draftIntBinding(\.imageThreshold),
                        hint: "0–64"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.simhashThreshold"),
                        subtitle: appState.t("settings.simhashThresholdDescription"),
                        value: draftIntBinding(\.simhashThreshold),
                        hint: "bit"
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("audit.visionOCR"),
                        subtitle: appState.t("settings.visionOCRDescription"),
                        isOn: draftBoolBinding(\.useVisionOCR)
                    )

                    SettingsDivider()

                    SettingsPickerRow(
                        title: appState.t("audit.whitelistMode"),
                        subtitle: currentValueSubtitle(
                            appState.t("settings.whitelistModeDescription"),
                            value: appState.title(for: appState.draftConfiguration.whitelistMode)
                        )
                    ) {
                        SettingsMenuPicker(
                            selection: draftBinding(\.whitelistMode),
                            options: AuditConfiguration.WhitelistMode.allCases,
                            width: SettingsLayout.menuWidth,
                            title: { appState.title(for: $0) }
                        )
                    }
                }

                SettingsGroup(title: "审计助手") {
                    SettingsPickerRow(
                        title: "助手模式",
                        subtitle: currentValueSubtitle("选择关闭、本地命令或外部 API", value: auditAssistantModeTitle(auditAssistantMode))
                    ) {
                        SettingsMenuPicker(
                            selection: auditAssistantBinding(\.mode),
                            options: AuditAssistantConfiguration.Mode.allCases,
                            width: SettingsLayout.menuWidth,
                            title: auditAssistantModeTitle,
                            systemImage: auditAssistantModeImage
                        )
                    }

                    SettingsDivider()

                    SettingsTextFieldRow(
                        title: auditAssistantEndpointTitle,
                        subtitle: auditAssistantEndpointSubtitle,
                        text: auditAssistantBinding(\.endpointOrCommand)
                    )
                    .disabled(auditAssistantMode == .disabled)

                    SettingsDivider()

                    SettingsAssistantTimeoutRow(
                        title: "超时时间",
                        subtitle: "本地命令和外部 API 的最大等待秒数",
                        value: auditAssistantBinding(\.timeoutSeconds)
                    )
                    .disabled(auditAssistantMode == .disabled)

                    SettingsDivider()

                    SettingsTextFieldRow(
                        title: "Keychain 引用",
                        subtitle: "外部 API 凭据引用，将作为 X-PitcherPlant-Credential-Ref 请求头传递",
                        text: auditAssistantBinding(\.keychainCredentialReference)
                    )
                    .disabled(auditAssistantMode != .externalAPI)
                }

                SettingsGroup(title: appState.t("settings.reports")) {
                    SettingsToggleRow(
                        title: appState.t("settings.preferInAppReports"),
                        subtitle: appState.t("settings.preferInAppReportsDescription"),
                        isOn: settingsBinding(\.preferInAppReports)
                    )

                    SettingsDivider()

                    SettingsPickerRow(
                        title: appState.t("settings.defaultExportFormat"),
                        subtitle: currentValueSubtitle(
                            appState.t("settings.defaultExportFormatDescription"),
                            value: appState.appSettings.defaultExportFormat.displayTitle
                        )
                    ) {
                        SettingsMenuPicker(
                            selection: settingsBinding(\.defaultExportFormat),
                            options: ExportRecord.Format.allCases,
                            width: SettingsLayout.menuWidth,
                            title: { $0.displayTitle }
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.showLegacyBadges"),
                        subtitle: appState.t("settings.showLegacyBadgesDescription"),
                        isOn: settingsBinding(\.showLegacyBadges)
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.attachmentPreview"),
                        subtitle: appState.t("settings.attachmentPreviewDescription"),
                        isOn: settingsBinding(\.showAttachmentPreviews)
                    )
                }

                SettingsGroup(title: appState.t("settings.dataMigration")) {
                    SettingsReadOnlyPathRow(
                        title: appState.t("settings.databaseLocation"),
                        subtitle: appState.t("settings.databaseLocationDescription"),
                        value: appState.database.databaseURL.path
                    )

                    SettingsDivider()

                    SettingsValueRow(
                        title: appState.t("settings.migrationSummary"),
                        subtitle: appState.t("settings.migrationSummaryDescription"),
                        value: summaryText
                    )

                    SettingsDivider()

                    SettingsValueRow(
                        title: appState.t("settings.recordCounts"),
                        subtitle: appState.t("settings.recordCountsDescription"),
                        value: recordCounts
                    )

                    SettingsDivider()

                    SettingsButtonGroupRow(
                        title: appState.t("settings.dataActions"),
                        subtitle: appState.t("settings.dataActionsDescription")
                    ) {
                        Button {
                            NSWorkspace.shared.open(appState.database.databaseURL.deletingLastPathComponent())
                        } label: {
                            Label(appState.t("settings.openDataDirectory"), systemImage: "folder")
                        }

                        Button {
                            Task { await appState.reload() }
                        } label: {
                            Label(appState.t("settings.reloadData"), systemImage: "arrow.clockwise")
                        }
                    }
                }

                SettingsGroup(title: appState.t("settings.shortcuts")) {
                    SettingsActionRow(
                        title: appState.isRunningAudit ? appState.t("command.cancelAudit") : appState.t("command.startAudit"),
                        subtitle: appState.t("settings.startAuditDescription"),
                        buttonTitle: appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"),
                        systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                    ) {
                        appState.toggleAudit()
                    }

                    SettingsDivider()

                    SettingsActionRow(
                        title: appState.t("settings.openReports"),
                        subtitle: appState.t("settings.openReportsDescription"),
                        buttonTitle: appState.t("settings.openReports"),
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        appState.showReportsCenter()
                    }

                    SettingsDivider()

                    SettingsButtonGroupRow(
                        title: appState.t("settings.reportActions"),
                        subtitle: appState.t("settings.reportActionsDescription")
                    ) {
                        Button {
                            appState.exportSelectedReportAsHTML()
                        } label: {
                            Label(appState.t("settings.exportHTML"), systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .disabled(appState.selectedReport == nil)

                        Button {
                            appState.exportSelectedReportAsPDF()
                        } label: {
                            Label(appState.t("settings.exportPDF"), systemImage: "doc.richtext")
                        }
                        .disabled(appState.selectedReport == nil)

                        Button {
                            appState.openSelectedReportSource()
                        } label: {
                            Label(appState.t("settings.openFinder"), systemImage: "folder")
                        }
                        .disabled(appState.selectedReport == nil)
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.settingsSearchQuery, searchText)
    }

    private var summaryText: String {
        guard let summary = appState.lastMigrationSummary else {
            return appState.t("settings.noMigration")
        }
        return "\(appState.t("status.audits")) \(summary.importedJobs) · \(appState.t("status.reports")) \(summary.importedReports) · \(appState.t("status.fingerprints")) \(summary.importedFingerprints) · \(appState.t("sidebar.whitelist")) \(summary.importedWhitelistRules)"
    }

    private var recordCounts: String {
        "\(appState.jobs.count) \(appState.t("status.audits")) · \(appState.reports.count) \(appState.t("status.reports")) · \(appState.fingerprints.count) \(appState.t("status.fingerprints")) · \(appState.whitelistRules.count) \(appState.t("sidebar.whitelist"))"
    }

    private var auditAssistantMode: AuditAssistantConfiguration.Mode {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).mode
    }

    private var auditAssistantEndpointTitle: String {
        switch auditAssistantMode {
        case .disabled: return "Endpoint / Command"
        case .localCommand: return "本地命令"
        case .externalAPI: return "API Endpoint"
        }
    }

    private var auditAssistantEndpointSubtitle: String {
        switch auditAssistantMode {
        case .disabled: return "配置会保留，启用模式后生效"
        case .localCommand: return "通过 zsh -lc 执行，证据 payload 会写入标准输入"
        case .externalAPI: return "以 POST JSON 请求发送证据 payload"
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.appSettings[keyPath: keyPath] },
            set: { value in
                appState.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<AuditConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { appState.draftConfiguration[keyPath: keyPath] },
            set: { value in appState.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func draftDoubleBinding(_ keyPath: WritableKeyPath<AuditConfiguration, Double>) -> Binding<Double> {
        Binding(
            get: { appState.draftConfiguration[keyPath: keyPath] },
            set: { value in appState.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func draftIntBinding(_ keyPath: WritableKeyPath<AuditConfiguration, Int>) -> Binding<Int> {
        Binding(
            get: { appState.draftConfiguration[keyPath: keyPath] },
            set: { value in appState.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func draftBoolBinding(_ keyPath: WritableKeyPath<AuditConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.draftConfiguration[keyPath: keyPath] },
            set: { value in appState.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private func auditAssistantBinding<Value>(_ keyPath: WritableKeyPath<AuditAssistantConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: {
                let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
                return configuration[keyPath: keyPath]
            },
            set: { value in
                appState.updateSettings { settings in
                    var configuration = settings.auditAssistant ?? AuditAssistantConfiguration()
                    configuration[keyPath: keyPath] = value
                    settings.auditAssistant = configuration
                }
            }
        )
    }

    private func appearanceTitle(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: appState.t("common.followSystem")
        case .light: appState.t("common.light")
        case .dark: appState.t("common.dark")
        }
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system: appState.t("common.followSystem")
        case .zhHans: "简体中文"
        case .english: "English"
        }
    }

    private func currentValueSubtitle(_ subtitle: String, value: String) -> String {
        "\(subtitle) · \(appState.t("settings.currentPrefix"))\(value)"
    }

    private func auditAssistantModeTitle(_ mode: AuditAssistantConfiguration.Mode) -> String {
        mode.title
    }

    private func auditAssistantModeImage(_ mode: AuditAssistantConfiguration.Mode) -> String {
        switch mode {
        case .disabled: return "slash.circle"
        case .localCommand: return "terminal"
        case .externalAPI: return "network"
        }
    }
}

private struct SettingsAssistantTimeoutRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsAssistantTimeoutStepper(value: $value)
        }
    }
}

private struct SettingsAssistantTimeoutStepper: View {
    @Binding var value: Double

    private let range: ClosedRange<Double> = 1...300
    private let step: Double = 5

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    value = clamped(value - step)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value <= range.lowerBound)
                .frame(width: 38)

                TextField("秒", value: clampedBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(AppTypography.code.weight(.medium))
                    .frame(width: SettingsLayout.numberFieldWidth)

                Button {
                    value = clamped(value + step)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value >= range.upperBound)
                .frame(width: 38)
            }
            .frame(width: SettingsLayout.stepperWidth, height: 30)
            .settingsPanelSurface(cornerRadius: 8)

            Text("秒")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.hintWidth, alignment: .trailing)
        }
        .frame(width: SettingsLayout.thresholdControlWidth, alignment: .trailing)
    }

    private var clampedBinding: Binding<Double> {
        Binding(
            get: { clamped(value) },
            set: { value = clamped($0) }
        )
    }

    private func clamped(_ candidate: Double) -> Double {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

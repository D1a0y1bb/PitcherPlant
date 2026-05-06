import SwiftUI

enum SettingsRootPresentation: Equatable {
    case standalone
    case embeddedInMainWindow

    var topPadding: CGFloat {
        switch self {
        case .standalone:
            return 28
        case .embeddedInMainWindow:
            return AppLayout.titlebarScrollContentTopPadding
        }
    }
}

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @Binding private var searchText: String
    private let presentation: SettingsRootPresentation
    @State private var selectedCalibrationPreset: AuditCalibrationPreset = .balanced
    @State private var calibrationResult: CalibrationEvaluationResult?
    @State private var calibrationMessage: String?

    init(
        searchText: Binding<String> = .constant(""),
        presentation: SettingsRootPresentation = .standalone
    ) {
        _searchText = searchText
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if presentation == .embeddedInMainWindow {
                AppPageShell(spacing: 28) {
                    settingsContent
                }
            } else {
                ScrollView {
                    settingsContent
                        .padding(.horizontal, 24)
                        .padding(.top, presentation.topPadding)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .environment(\.settingsSearchQuery, searchText)
    }

    @ViewBuilder
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 28) {
                SettingsGroup(title: appState.t("settings.general")) {
                    SettingsPickerRow(
                        title: appState.t("settings.language"),
                        subtitle: appState.t("settings.languageDescription"),
                        icon: .language
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
                        icon: .menuBar,
                        isOn: settingsBinding(\.showMenuBarExtra)
                    )
                }

                SettingsGroup(title: appState.t("settings.appearance")) {
                    SettingsPickerRow(
                        title: appState.t("settings.theme"),
                        subtitle: appState.t("settings.themeDescription"),
                        icon: .theme
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
                        icon: .inspector,
                        isOn: settingsBinding(\.showInspectorByDefault)
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.compactRows"),
                        subtitle: appState.t("settings.compactRowsDescription"),
                        icon: .listDensity,
                        isOn: settingsBinding(\.compactRows)
                    )
                }

                SettingsGroup(title: appState.t("settings.auditDefaults")) {
                    SettingsPathRow(
                        title: appState.t("audit.directory"),
                        subtitle: appState.t("settings.auditDirectoryDescription"),
                        icon: .inputFolder,
                        text: draftBinding(\.directoryPath)
                    )

                    SettingsDivider()

                    SettingsPathRow(
                        title: appState.t("audit.outputDirectory"),
                        subtitle: appState.t("settings.reportDirectoryDescription"),
                        icon: .outputFolder,
                        text: draftBinding(\.outputDirectoryPath)
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.textThreshold"),
                        subtitle: appState.t("settings.textThresholdDescription"),
                        icon: .textThreshold,
                        value: draftDoubleBinding(\.textThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.dedupThreshold"),
                        subtitle: appState.t("settings.dedupThresholdDescription"),
                        icon: .duplicateThreshold,
                        value: draftDoubleBinding(\.dedupThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.imageThreshold"),
                        subtitle: appState.t("settings.imageThresholdDescription"),
                        icon: .imageThreshold,
                        value: draftIntBinding(\.imageThreshold),
                        hint: "0–64"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.simhashThreshold"),
                        subtitle: appState.t("settings.simhashThresholdDescription"),
                        icon: .simhashThreshold,
                        value: draftIntBinding(\.simhashThreshold),
                        hint: "bit"
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("audit.visionOCR"),
                        subtitle: appState.t("settings.visionOCRDescription"),
                        icon: .vision,
                        isOn: draftBoolBinding(\.useVisionOCR)
                    )

                    SettingsDivider()

                    SettingsPickerRow(
                        title: appState.t("audit.whitelistMode"),
                        subtitle: currentValueSubtitle(
                            appState.t("settings.whitelistModeDescription"),
                            value: appState.title(for: appState.draftConfiguration.whitelistMode)
                        ),
                        icon: .whitelist
                    ) {
                        SettingsMenuPicker(
                            selection: draftBinding(\.whitelistMode),
                            options: AuditConfiguration.WhitelistMode.allCases,
                            width: SettingsLayout.menuWidth,
                            title: { appState.title(for: $0) }
                        )
                    }
                }

                SettingsGroup(title: appState.t("settings.calibration")) {
                    SettingsPickerRow(
                        title: appState.t("settings.calibrationPreset"),
                        subtitle: appState.subtitle(for: selectedCalibrationPreset),
                        icon: .calibrationPreset
                    ) {
                        SettingsMenuPicker(
                            selection: $selectedCalibrationPreset,
                            options: AuditCalibrationPreset.allCases,
                            width: SettingsLayout.menuWidth,
                            title: { appState.title(for: $0) }
                        )
                    }

                    SettingsDivider()

                    SettingsButtonGroupRow(
                        title: appState.t("settings.calibrationEvaluation"),
                        subtitle: calibrationSummaryText,
                        icon: .calibrationRun
                    ) {
                        Button {
                            applyCalibrationPreset()
                        } label: {
                            Label(appState.t("settings.applyPreset"), systemImage: "slider.horizontal.3")
                        }

                        Button {
                            runCalibration()
                        } label: {
                            Label(appState.t("settings.runCalibration"), systemImage: "chart.xyaxis.line")
                        }
                    }

                    if let calibrationResult {
                        SettingsDivider()
                        CalibrationResultRows(result: calibrationResult)
                    } else if let calibrationMessage {
                        SettingsDivider()
                        SettingsValueRow(
                            title: appState.t("settings.calibrationStatus"),
                            subtitle: calibrationMessage,
                            icon: .calibrationStatus,
                            value: ""
                        )
                    }
                }

                SettingsGroup(title: appState.t("settings.auditAssistant")) {
                    SettingsPickerRow(
                        title: appState.t("settings.auditAssistantMode"),
                        subtitle: currentValueSubtitle(appState.t("settings.auditAssistantModeDescription"), value: auditAssistantModeTitle(auditAssistantMode)),
                        icon: .assistantMode
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
                        icon: auditAssistantEndpointIcon,
                        text: auditAssistantBinding(\.endpointOrCommand)
                    )
                    .disabled(auditAssistantMode == .disabled)

                    SettingsDivider()

                    SettingsAssistantTimeoutRow(
                        title: appState.t("settings.auditAssistantTimeout"),
                        subtitle: appState.t("settings.auditAssistantTimeoutDescription"),
                        icon: .assistantTimeout,
                        value: auditAssistantBinding(\.timeoutSeconds)
                    )
                    .disabled(auditAssistantMode == .disabled)

                    SettingsDivider()

                    SettingsTextFieldRow(
                        title: appState.t("settings.auditAssistantKeychain"),
                        subtitle: appState.t("settings.auditAssistantKeychainDescription"),
                        icon: .assistantCredential,
                        text: auditAssistantBinding(\.keychainCredentialReference)
                    )
                    .disabled(auditAssistantMode != .externalAPI)
                }

                SettingsGroup(title: appState.t("settings.reports")) {
                    SettingsToggleRow(
                        title: appState.t("settings.preferInAppReports"),
                        subtitle: appState.t("settings.preferInAppReportsDescription"),
                        icon: .reportPreference,
                        isOn: settingsBinding(\.preferInAppReports)
                    )

                    SettingsDivider()

                    SettingsPickerRow(
                        title: appState.t("settings.defaultExportFormat"),
                        subtitle: currentValueSubtitle(
                            appState.t("settings.defaultExportFormatDescription"),
                            value: appState.appSettings.defaultExportFormat.displayTitle
                        ),
                        icon: .exportFormat
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
                        title: appState.t("settings.attachmentPreview"),
                        subtitle: appState.t("settings.attachmentPreviewDescription"),
                        icon: .attachmentPreview,
                        isOn: settingsBinding(\.showAttachmentPreviews)
                    )
                }

                SettingsGroup(title: appState.t("settings.data")) {
                    SettingsReadOnlyPathRow(
                        title: appState.t("settings.databaseLocation"),
                        subtitle: appState.t("settings.databaseLocationDescription"),
                        icon: .database,
                        value: appState.database.databaseURL.path
                    )

                    SettingsDivider()

                    SettingsValueRow(
                        title: appState.t("settings.recordCounts"),
                        subtitle: appState.t("settings.recordCountsDescription"),
                        icon: .recordCounts,
                        value: recordCounts
                    )

                    SettingsDivider()

                    SettingsButtonGroupRow(
                        title: appState.t("settings.dataActions"),
                        subtitle: appState.t("settings.dataActionsDescription"),
                        icon: .dataActions
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
                        icon: appState.isRunningAudit ? .cancelAudit : .startAudit,
                        buttonTitle: appState.isRunningAudit ? appState.t("toolbar.cancel") : appState.t("toolbar.start"),
                        systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                    ) {
                        appState.toggleAudit()
                    }

                    SettingsDivider()

                    SettingsActionRow(
                        title: appState.t("settings.openReports"),
                        subtitle: appState.t("settings.openReportsDescription"),
                        icon: .openReports,
                        buttonTitle: appState.t("settings.openReports"),
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        appState.showReportsCenter()
                    }

                    SettingsDivider()

                    SettingsButtonGroupRow(
                        title: appState.t("settings.reportActions"),
                        subtitle: appState.t("settings.reportActionsDescription"),
                        icon: .reportActions
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
    }

    private var recordCounts: String {
        let reportCount = max(appState.reportTotalCount, appState.reports.count)
        let fingerprintCount = max(appState.fingerprintTotalCount, appState.fingerprints.count)
        return "\(appState.jobs.count) \(appState.t("status.audits")) · \(reportCount) \(appState.t("status.reports")) · \(fingerprintCount) \(appState.t("status.fingerprints")) · \(appState.whitelistRules.count) \(appState.t("sidebar.whitelist"))"
    }

    private var calibrationSummaryText: String {
        if let calibrationResult {
            return appState.tf(
                "settings.calibrationSummary",
                calibrationResult.summary.sampleCount,
                calibrationResult.summary.precision,
                calibrationResult.summary.recall,
                calibrationResult.summary.f1
            )
        }
        return appState.t("settings.calibrationDescription")
    }

    private func applyCalibrationPreset() {
        let preset = selectedCalibrationPreset
        appState.updateDraft { configuration in
            configuration = configuration.applyingCalibrationPreset(preset)
        }
    }

    private func runCalibration() {
        guard let manifestURL = CalibrationManifestLocator.manifestURL(workspaceRoot: appState.workspaceRoot) else {
            calibrationResult = nil
            calibrationMessage = appState.t("settings.calibrationMissingManifest")
            return
        }
        do {
            calibrationResult = try CalibrationService(manifestURL: manifestURL).evaluate(configuration: appState.draftConfiguration)
            calibrationMessage = nil
        } catch {
            calibrationResult = nil
            calibrationMessage = error.localizedDescription
        }
    }

    private var auditAssistantMode: AuditAssistantConfiguration.Mode {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).mode
    }

    private var auditAssistantEndpointTitle: String {
        switch auditAssistantMode {
        case .disabled: return appState.t("settings.auditAssistantEndpointCommand")
        case .localCommand: return appState.t("settings.auditAssistantLocalCommand")
        case .externalAPI: return appState.t("settings.auditAssistantAPIEndpoint")
        }
    }

    private var auditAssistantEndpointSubtitle: String {
        switch auditAssistantMode {
        case .disabled: return appState.t("settings.auditAssistantDisabledSubtitle")
        case .localCommand: return appState.t("settings.auditAssistantLocalSubtitle")
        case .externalAPI: return appState.t("settings.auditAssistantAPISubtitle")
        }
    }

    private var auditAssistantEndpointIcon: SettingsRowIconStyle {
        switch auditAssistantMode {
        case .disabled: return .assistantCommand
        case .localCommand: return .assistantCommand
        case .externalAPI: return .assistantMode
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
        appState.title(for: mode)
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
    var icon: SettingsRowIconStyle = .assistantTimeout
    @Binding var value: Double

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsAssistantTimeoutStepper(value: $value)
        }
    }
}

private struct SettingsAssistantTimeoutStepper: View {
    @Environment(AppState.self) private var appState
    @Binding var value: Double

    private let range: ClosedRange<Double> = 1...300
    private let step: Double = 5

    var body: some View {
        HStack(spacing: 8) {
            TextField(appState.t("common.seconds"), value: clampedBinding, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(AppTypography.code.weight(.medium))
                .frame(width: SettingsLayout.numberFieldWidth + 12)

            Stepper("", value: clampedBinding, in: range, step: step)
                .labelsHidden()
                .frame(width: SettingsLayout.stepperWidth - 46)

            Text(appState.t("common.seconds"))
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

private struct CalibrationResultRows: View {
    @Environment(AppState.self) private var appState
    let result: CalibrationEvaluationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(appState.t("common.type")).frame(width: 80, alignment: .leading)
                Text(appState.t("common.samples")).frame(width: 54, alignment: .trailing)
                Text("P").frame(width: 54, alignment: .trailing)
                Text("R").frame(width: 54, alignment: .trailing)
                Text("F1").frame(width: 54, alignment: .trailing)
                Text(appState.t("settings.calibrationThreshold")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppLayout.rowHorizontalPadding)

            ForEach(result.rows) { row in
                HStack(spacing: 12) {
                    Label(appState.title(for: row.kind), systemImage: row.kind.sectionKind.systemImage)
                        .frame(width: 80, alignment: .leading)
                    Text("\(row.sampleCount)").frame(width: 54, alignment: .trailing)
                    Text(Self.metric(row.metrics.precision)).frame(width: 54, alignment: .trailing)
                    Text(Self.metric(row.metrics.recall)).frame(width: 54, alignment: .trailing)
                    Text(Self.metric(row.metrics.f1)).frame(width: 54, alignment: .trailing)
                    Text(row.thresholdDescription)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(AppTypography.rowSecondary.monospacedDigit())
                .padding(.horizontal, AppLayout.rowHorizontalPadding)
                .padding(.vertical, 5)
                .accessibilityLabel(
                    appState.tf(
                        "settings.calibrationRowAccessibility",
                        appState.title(for: row.kind),
                        row.sampleCount,
                        Self.metric(row.metrics.precision),
                        Self.metric(row.metrics.recall),
                        Self.metric(row.metrics.f1)
                    )
                )
            }
        }
    }

    private static func metric(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

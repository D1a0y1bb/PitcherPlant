import SwiftUI
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedCalibrationPreset: AuditCalibrationPreset = .balanced
    @State private var calibrationMessage: String?
    @State private var activeAboutPanel: SettingsAboutPanel?
    @State private var auditAssistantCredentialDraft = ""
    @State private var auditAssistantBaseURLRevealed = true
    @State private var auditAssistantModelRevealed = true
    @State private var auditAssistantCredentialRevealed = false
    @State private var hasSavedAuditAssistantCredential = false
    @State private var auditAssistantConnectionMessage: String?
    @State private var isTestingAuditAssistant = false
    @State private var settingsNotice: SettingsNotice?

    var body: some View {
        SettingsPaneScroll {
            applicationSettings
            auditDefaultsSettings
            thresholdSettings
            calibrationSettings
            auditAssistantSettings
            reportSettings
            dataSettings
            aboutSettings
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(
            SettingsWindowChromeSupport(title: appState.t("settings.title"))
                .frame(width: 0, height: 0)
        )
        .sheet(item: $activeAboutPanel) { panel in
            SettingsAboutPanelView(panel: panel, version: AppVersionInfo.current)
                .environment(appState)
        }
        .alert(item: $settingsNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(appState.t("common.ok")))
            )
        }
        .onAppear {
            clearInitialControlFocus()
            refreshAuditAssistantCredentialPresence()
        }
    }

    @ViewBuilder
    private var applicationSettings: some View {
        SettingsGroup(title: appState.t("settings.application")) {
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
    }

    private var auditDefaultsSettings: some View {
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
    }

    private var thresholdSettings: some View {
        SettingsGroup(title: appState.t("settings.thresholds")) {
            SettingsNumberFieldRow(
                title: appState.t("audit.textThreshold"),
                subtitle: appState.t("settings.textThresholdDescription"),
                icon: .textThreshold,
                value: draftDoubleBinding(\.textThreshold),
                hint: "0.00-1.00"
            )

            SettingsDivider()

            SettingsNumberFieldRow(
                title: appState.t("audit.dedupThreshold"),
                subtitle: appState.t("settings.dedupThresholdDescription"),
                icon: .duplicateThreshold,
                value: draftDoubleBinding(\.dedupThreshold),
                hint: "0.00-1.00"
            )

            SettingsDivider()

            SettingsIntegerFieldRow(
                title: appState.t("audit.imageThreshold"),
                subtitle: appState.t("settings.imageThresholdDescription"),
                icon: .imageThreshold,
                value: draftIntBinding(\.imageThreshold),
                hint: "0-64"
            )

            SettingsDivider()

            SettingsIntegerFieldRow(
                title: appState.t("audit.simhashThreshold"),
                subtitle: appState.t("settings.simhashThresholdDescription"),
                icon: .simhashThreshold,
                value: draftIntBinding(\.simhashThreshold),
                hint: "0-64"
            )
        }
    }

    private var calibrationSettings: some View {
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

            SettingsActionRow(
                title: appState.t("settings.applyPreset"),
                subtitle: appState.subtitle(for: selectedCalibrationPreset),
                icon: .calibrationRun
            ) {
                applyCalibrationPreset()
            }

            if let calibrationMessage {
                SettingsDivider()
                SettingsValueRow(
                    title: appState.t("settings.calibrationStatus"),
                    subtitle: appState.t("settings.calibrationDescription"),
                    icon: .calibrationStatus,
                    value: calibrationMessage
                )
            }
        }
    }

    private var auditAssistantSettings: some View {
        SettingsGroup(title: appState.t("settings.auditAssistant"), badge: appState.t("settings.betaBadge")) {
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

            SettingsPickerRow(
                title: appState.t("settings.auditAssistantProvider"),
                subtitle: currentValueSubtitle(appState.t("settings.auditAssistantProviderDescription"), value: auditAssistantProviderTitle(auditAssistantProvider)),
                icon: .assistantProvider
            ) {
                SettingsMenuPicker(
                    selection: auditAssistantProviderBinding,
                    options: AuditAssistantConfiguration.Provider.allCases,
                    width: SettingsLayout.wideMenuWidth,
                    title: auditAssistantProviderTitle,
                    systemImage: auditAssistantProviderImage
                )
            }
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsPickerRow(
                title: appState.t("settings.auditAssistantProtocol"),
                subtitle: currentValueSubtitle(appState.t("settings.auditAssistantProtocolDescription"), value: auditAssistantProtocolTitle(auditAssistantProtocol)),
                icon: .assistantProtocol
            ) {
                SettingsMenuPicker(
                    selection: auditAssistantBinding(\.apiProtocol),
                    options: auditAssistantProvider.supportedProtocols,
                    width: SettingsLayout.wideMenuWidth,
                    title: auditAssistantProtocolTitle,
                    systemImage: auditAssistantProtocolImage
                )
            }
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsRevealableTextFieldRow(
                title: appState.t("settings.auditAssistantBaseURL"),
                subtitle: appState.t("settings.auditAssistantBaseURLDescription"),
                icon: .assistantEndpoint,
                text: auditAssistantBinding(\.baseURL),
                isRevealed: $auditAssistantBaseURLRevealed,
                revealTitle: appState.t("settings.showText"),
                concealTitle: appState.t("settings.hideText")
            )
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsRevealableTextFieldRow(
                title: appState.t("settings.auditAssistantModel"),
                subtitle: appState.t("settings.auditAssistantModelDescription"),
                icon: .assistantModel,
                text: auditAssistantBinding(\.model),
                isRevealed: $auditAssistantModelRevealed,
                revealTitle: appState.t("settings.showText"),
                concealTitle: appState.t("settings.hideText")
            )
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsNumberFieldRow(
                title: appState.t("settings.auditAssistantTimeout"),
                subtitle: appState.t("settings.auditAssistantTimeoutDescription"),
                icon: .assistantTimeout,
                value: auditAssistantBinding(\.timeoutSeconds),
                range: 1...300,
                step: 5,
                hint: appState.t("common.seconds"),
                fractionLength: 0
            )
            .disabled(auditAssistantMode == .disabled)

            SettingsDivider()

            SettingsIntegerFieldRow(
                title: appState.t("settings.auditAssistantMaxTokens"),
                subtitle: appState.t("settings.auditAssistantMaxTokensDescription"),
                icon: .assistantTokens,
                value: auditAssistantBinding(\.maxOutputTokens),
                range: 100...8000,
                step: 100,
                hint: appState.t("settings.auditAssistantTokensHint")
            )
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsNumberFieldRow(
                title: appState.t("settings.auditAssistantTemperature"),
                subtitle: appState.t("settings.auditAssistantTemperatureDescription"),
                icon: .assistantTemperature,
                value: auditAssistantBinding(\.temperature),
                range: 0...2,
                step: 0.1,
                hint: "",
                fractionLength: 1
            )
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsPickerRow(
                title: appState.t("settings.auditAssistantDataSharing"),
                subtitle: currentValueSubtitle(appState.t("settings.auditAssistantDataSharingDescription"), value: auditAssistantDataSharingTitle(auditAssistantDataSharingLevel)),
                icon: .assistantData
            ) {
                SettingsMenuPicker(
                    selection: auditAssistantBinding(\.dataSharingLevel),
                    options: AuditAssistantConfiguration.DataSharingLevel.allCases,
                    width: SettingsLayout.menuWidth,
                    title: auditAssistantDataSharingTitle,
                    systemImage: auditAssistantDataSharingImage
                )
            }
            .disabled(auditAssistantMode == .disabled)

            SettingsDivider()

            SettingsRevealableTextFieldRow(
                title: appState.t("settings.auditAssistantAPIKey"),
                subtitle: appState.t("settings.auditAssistantAPIKeyDescription"),
                icon: .assistantCredential,
                placeholder: auditAssistantCredentialPlaceholder,
                text: $auditAssistantCredentialDraft,
                isRevealed: $auditAssistantCredentialRevealed,
                revealTitle: appState.t("settings.showText"),
                concealTitle: appState.t("settings.hideText"),
                onRevealRequest: revealAuditAssistantCredential
            )
            .disabled(auditAssistantMode != .externalAPI)

            SettingsDivider()

            SettingsButtonGroupRow(
                title: appState.t("settings.auditAssistantConnection"),
                subtitle: auditAssistantConnectionMessage ?? appState.t("settings.auditAssistantConnectionDescription"),
                icon: .assistantConnection
            ) {
                Button(appState.t("settings.auditAssistantSaveKey")) {
                    saveAuditAssistantCredential()
                }
                .disabled(auditAssistantMode != .externalAPI)

                Button(appState.t("settings.auditAssistantDeleteKey")) {
                    deleteAuditAssistantCredential()
                }
                .disabled(auditAssistantMode != .externalAPI)

                Button(isTestingAuditAssistant ? appState.t("settings.auditAssistantTesting") : appState.t("settings.auditAssistantTest")) {
                    testAuditAssistantConnection()
                }
                .disabled(auditAssistantMode != .externalAPI || isTestingAuditAssistant)
            }
        }
    }

    private var reportSettings: some View {
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
                    value: appState.title(for: appState.appSettings.defaultExportFormat)
                ),
                icon: .exportFormat
            ) {
                SettingsMenuPicker(
                    selection: settingsBinding(\.defaultExportFormat),
                    options: ExportRecord.Format.allCases,
                    width: SettingsLayout.menuWidth,
                    title: { appState.title(for: $0) }
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
    }

    private var dataSettings: some View {
        SettingsGroup(title: appState.t("settings.data")) {
            SettingsFolderActionRow(
                title: appState.t("settings.databaseLocation"),
                subtitle: appState.t("settings.databaseLocationDescription"),
                icon: .database,
                url: appState.database.databaseURL
            )

            SettingsDivider()

            SettingsValueRow(
                title: appState.t("settings.recordCounts"),
                subtitle: appState.t("settings.recordCountsDescription"),
                icon: .recordCounts,
                value: recordCounts
            )
        }
    }

    private var aboutSettings: some View {
        let version = AppVersionInfo.current

        return SettingsGroup(title: appState.t("settings.about")) {
            SettingsActionRow(
                title: appState.t("settings.reportIssue"),
                subtitle: appState.t("settings.reportIssueDescription"),
                icon: .reportIssue
            ) {
                activeAboutPanel = .reportIssue
            }

            SettingsDivider()

            SettingsActionRow(
                title: appState.t("settings.helpCenter"),
                subtitle: appState.t("settings.helpCenterDescription"),
                icon: .helpCenter
            ) {
                activeAboutPanel = .helpCenter
            }

            SettingsDivider()

            SettingsActionRow(
                title: appState.t("settings.termsOfUse"),
                subtitle: appState.t("settings.termsOfUseDescription"),
                icon: .terms
            ) {
                activeAboutPanel = .termsOfUse
            }

            SettingsDivider()

            SettingsActionRow(
                title: appState.t("settings.privacyPolicy"),
                subtitle: appState.t("settings.privacyPolicyDescription"),
                icon: .privacy
            ) {
                activeAboutPanel = .privacyPolicy
            }

            SettingsDivider()

            SettingsValueRow(
                title: appState.t("settings.version"),
                subtitle: "",
                icon: .about,
                value: version.versionAndBuild
            )

            SettingsDivider()

            SettingsActionRow(
                title: appState.t("about.checkUpdates"),
                subtitle: "",
                icon: .update
            ) {
                appState.checkForUpdatesManually()
            }
        }
    }

    private var recordCounts: String {
        let reportCount = max(appState.reportTotalCount, appState.reports.count)
        let fingerprintCount = max(appState.fingerprintTotalCount, appState.fingerprints.count)
        return "\(appState.jobs.count) \(appState.t("status.audits")) · \(reportCount) \(appState.t("status.reports")) · \(fingerprintCount) \(appState.t("status.fingerprints")) · \(appState.whitelistRules.count) \(appState.t("sidebar.whitelist"))"
    }

    private func applyCalibrationPreset() {
        let preset = selectedCalibrationPreset
        appState.updateDraft { configuration in
            configuration = configuration.applyingCalibrationPreset(preset)
        }
        calibrationMessage = appState.tf("settings.calibrationPresetApplied", appState.title(for: preset))
    }

    private func clearInitialControlFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var auditAssistantMode: AuditAssistantConfiguration.Mode {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).mode
    }

    private var auditAssistantProvider: AuditAssistantConfiguration.Provider {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).provider
    }

    private var auditAssistantProtocol: AuditAssistantConfiguration.APIProtocol {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).apiProtocol
    }

    private var auditAssistantDataSharingLevel: AuditAssistantConfiguration.DataSharingLevel {
        (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).dataSharingLevel
    }

    private var auditAssistantProviderBinding: Binding<AuditAssistantConfiguration.Provider> {
        Binding(
            get: {
                (appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()).provider
            },
            set: { provider in
                appState.updateSettings { settings in
                    var configuration = settings.auditAssistant ?? AuditAssistantConfiguration()
                    configuration.apply(provider: provider)
                    settings.auditAssistant = configuration
                }
                auditAssistantCredentialDraft = ""
                auditAssistantCredentialRevealed = false
                refreshAuditAssistantCredentialPresence()
            }
        )
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

    private func auditAssistantProviderTitle(_ provider: AuditAssistantConfiguration.Provider) -> String {
        appState.title(for: provider)
    }

    private func auditAssistantProtocolTitle(_ apiProtocol: AuditAssistantConfiguration.APIProtocol) -> String {
        appState.title(for: apiProtocol)
    }

    private func auditAssistantDataSharingTitle(_ level: AuditAssistantConfiguration.DataSharingLevel) -> String {
        appState.title(for: level)
    }

    private func auditAssistantModeImage(_ mode: AuditAssistantConfiguration.Mode) -> String {
        switch mode {
        case .disabled: return "slash.circle"
        case .externalAPI: return "network"
        }
    }

    private func auditAssistantProviderImage(_ provider: AuditAssistantConfiguration.Provider) -> String {
        switch provider {
        case .customOpenAICompatible: return "slider.horizontal.3"
        case .openAI: return "sparkles"
        case .anthropic: return "text.bubble"
        case .gemini: return "diamond"
        case .deepSeek: return "magnifyingglass"
        case .kimi: return "moon"
        case .miniMax: return "m.circle"
        }
    }

    private func auditAssistantProtocolImage(_ apiProtocol: AuditAssistantConfiguration.APIProtocol) -> String {
        switch apiProtocol {
        case .openAIChatCompletions: return "text.bubble"
        case .openAIResponses: return "sparkles"
        case .anthropicMessages: return "message"
        case .geminiGenerateContent: return "diamond"
        case .miniMaxChatCompletion: return "m.circle"
        }
    }

    private func auditAssistantDataSharingImage(_ level: AuditAssistantConfiguration.DataSharingLevel) -> String {
        switch level {
        case .summaryOnly: return "lock"
        case .evidenceDetail: return "doc.text"
        case .fullContext: return "doc.richtext"
        }
    }

    private var auditAssistantCredentialPlaceholder: String {
        if auditAssistantCredentialDraft.isEmpty && hasSavedAuditAssistantCredential {
            return appState.t("settings.auditAssistantKeySavedPlaceholder")
        }
        return appState.t("settings.auditAssistantAPIKey")
    }

    private func refreshAuditAssistantCredentialPresence() {
        do {
            let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
            let store = AuditAssistantCredentialStore()
            try store.migrateLegacyDefaultCredentialIfNeeded(to: configuration.credentialID)
            hasSavedAuditAssistantCredential = try store.exists(id: configuration.credentialID)
            if hasSavedAuditAssistantCredential == false {
                auditAssistantCredentialDraft = ""
                auditAssistantCredentialRevealed = false
            }
        } catch {
            hasSavedAuditAssistantCredential = false
            auditAssistantConnectionMessage = error.localizedDescription
        }
    }

    private func revealAuditAssistantCredential() -> Bool {
        guard auditAssistantCredentialDraft.isEmpty, hasSavedAuditAssistantCredential else {
            return true
        }

        do {
            let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
            auditAssistantCredentialDraft = try AuditAssistantCredentialStore().read(
                id: configuration.credentialID,
                allowAuthenticationUI: true
            )
            hasSavedAuditAssistantCredential = true
            return true
        } catch {
            auditAssistantConnectionMessage = error.localizedDescription
            presentSettingsNotice(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private func saveAuditAssistantCredential(showAlert: Bool = true) -> Bool {
        guard auditAssistantCredentialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            let message = appState.t("settings.auditAssistantKeyEmpty")
            auditAssistantConnectionMessage = message
            if showAlert {
                presentSettingsNotice(message)
            }
            return false
        }

        do {
            let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
            try AuditAssistantCredentialStore().save(auditAssistantCredentialDraft, id: configuration.credentialID)
            hasSavedAuditAssistantCredential = true
            auditAssistantCredentialRevealed = true
            auditAssistantConnectionMessage = appState.t("settings.auditAssistantKeySaved")
            if showAlert {
                presentSettingsNotice(appState.t("settings.auditAssistantKeySaved"))
            }
            return true
        } catch {
            auditAssistantConnectionMessage = error.localizedDescription
            if showAlert {
                presentSettingsNotice(error.localizedDescription)
            }
            return false
        }
    }

    private func deleteAuditAssistantCredential() {
        do {
            let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
            try AuditAssistantCredentialStore().deleteIfPresent(id: configuration.credentialID)
            auditAssistantCredentialDraft = ""
            hasSavedAuditAssistantCredential = false
            auditAssistantCredentialRevealed = false
            auditAssistantConnectionMessage = appState.t("settings.auditAssistantKeyDeleted")
            presentSettingsNotice(appState.t("settings.auditAssistantKeyDeleted"))
        } catch {
            auditAssistantConnectionMessage = error.localizedDescription
            presentSettingsNotice(error.localizedDescription)
        }
    }

    private func testAuditAssistantConnection() {
        let credential: String
        do {
            credential = try auditAssistantCredentialForConnectionTest()
        } catch AuditAssistantCredentialStore.CredentialError.missingCredential {
            let message = appState.t("settings.auditAssistantKeyEmpty")
            auditAssistantConnectionMessage = message
            presentSettingsNotice(message)
            return
        } catch {
            auditAssistantConnectionMessage = error.localizedDescription
            presentSettingsNotice(error.localizedDescription)
            return
        }

        isTestingAuditAssistant = true
        auditAssistantConnectionMessage = appState.t("settings.auditAssistantTesting")
        Task { @MainActor in
            do {
                let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
                let result = try await AuditAssistantService().testConnection(
                    configuration: configuration,
                    credentialOverride: credential,
                    language: appState.appSettings.language
                )
                let message = appState.tf("settings.auditAssistantTestSucceeded", result.model)
                auditAssistantConnectionMessage = message
                presentSettingsNotice(message)
            } catch {
                auditAssistantConnectionMessage = error.localizedDescription
                presentSettingsNotice(error.localizedDescription)
            }
            isTestingAuditAssistant = false
        }
    }

    private func auditAssistantCredentialForConnectionTest() throws -> String {
        let draft = auditAssistantCredentialDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isEmpty == false {
            return draft
        }
        guard hasSavedAuditAssistantCredential else {
            throw AuditAssistantCredentialStore.CredentialError.missingCredential
        }
        let configuration = appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
        return try AuditAssistantCredentialStore().read(
            id: configuration.credentialID,
            allowAuthenticationUI: true
        )
    }

    private func presentSettingsNotice(_ message: String) {
        settingsNotice = SettingsNotice(title: appState.t("settings.auditAssistant"), message: message)
    }
}

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SettingsPaneScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                content
            }
            .frame(maxWidth: SettingsLayout.pageMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, SettingsLayout.pageHorizontalPadding)
            .padding(.top, SettingsLayout.pageTopPadding)
            .padding(.bottom, SettingsLayout.pageBottomPadding)
        }
    }
}

private enum SettingsAboutPanel: String, Identifiable {
    case reportIssue
    case helpCenter
    case termsOfUse
    case privacyPolicy

    var id: String { rawValue }
}

private struct SettingsAboutPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let panel: SettingsAboutPanel
    let version: AppVersionInfo
    @State private var reportText = ""
    @State private var includeScreenshot = true
    @State private var screenshot: SettingsIssueScreenshot?
    @State private var screenshotStatusKey: String?
    @State private var isCapturingScreenshot = false

    var body: some View {
        switch panel {
        case .reportIssue:
            reportIssueView
        case .helpCenter, .termsOfUse, .privacyPolicy:
            informationView
        }
    }

    private var reportIssueView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(appState.t("settings.reportIssueTitle"))
                    .font(.title2.weight(.semibold))

                Text(appState.t("settings.reportIssuePrompt"))
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    SettingsReportTextView(text: $reportText, maxLength: 2000)

                    if reportText.isEmpty {
                        Text(appState.t("settings.reportIssuePlaceholder"))
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, SettingsReportTextViewMetrics.textInset.width)
                            .padding(.top, SettingsReportTextViewMetrics.textInset.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 190)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("\(reportText.count) / 2000")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(appState.t("settings.reportIssueReviewNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(appState.t("settings.reportIssueIncludeScreenshot"), isOn: $includeScreenshot)
                    .toggleStyle(.checkbox)
                    .font(.headline)
                    .onChange(of: includeScreenshot) { _, newValue in
                        if newValue {
                            captureScreenshotIfNeeded()
                        } else {
                            screenshot = nil
                            screenshotStatusKey = nil
                        }
                    }

                if includeScreenshot {
                    screenshotPreview
                }

                SettingsDiagnosticSummary(version: version)
            }
            .padding(30)

            Divider()

            HStack {
                Spacer()
                Button(appState.t("common.cancel")) {
                    dismiss()
                }
                Button(appState.t("settings.reportIssueSubmit")) {
                    submitReport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (includeScreenshot && isCapturingScreenshot)
                )
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .frame(width: 620)
        .onAppear {
            captureScreenshotIfNeeded()
        }
    }

    @ViewBuilder
    private var screenshotPreview: some View {
        if isCapturingScreenshot {
            Text(appState.t("settings.reportIssueScreenshotCapturing"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let screenshot {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: screenshot.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t("settings.reportIssueScreenshotReady"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(screenshot.url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let screenshotStatusKey {
            Text(appState.t(screenshotStatusKey))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var informationView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                SettingsDiagnosticSummary(version: version)
            }
            .padding(30)

            Divider()

            HStack {
                Spacer()
                Button(appState.t("common.ok")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .frame(width: 520)
    }

    private var title: String {
        switch panel {
        case .reportIssue:
            appState.t("settings.reportIssue")
        case .helpCenter:
            appState.t("settings.helpCenter")
        case .termsOfUse:
            appState.t("settings.termsOfUse")
        case .privacyPolicy:
            appState.t("settings.privacyPolicy")
        }
    }

    private var message: String {
        switch panel {
        case .reportIssue:
            appState.t("settings.reportIssueDescription")
        case .helpCenter:
            appState.t("settings.helpCenterBody")
        case .termsOfUse:
            appState.t("settings.termsOfUseBody")
        case .privacyPolicy:
            appState.t("settings.privacyPolicyBody")
        }
    }

    private func submitReport() {
        guard var components = URLComponents(string: "https://github.com/D1a0y1bb/PitcherPlant/issues/new") else {
            dismiss()
            return
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: "[Settings] \(reportText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))"),
            URLQueryItem(name: "body", value: issueBody)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }

    private var issueBody: String {
        """
        ## What happened
        \(reportText.trimmingCharacters(in: .whitespacesAndNewlines))

        ## App information
        App: \(version.name)
        Version: \(version.versionAndBuild)
        Bundle: \(version.bundleIdentifier)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(screenshotReportText)
        """
    }

    private var screenshotReportText: String {
        guard includeScreenshot else {
            return "Include screenshot: no"
        }
        guard let screenshot else {
            return "Include screenshot: requested, capture unavailable"
        }
        return """
        Include screenshot: yes
        Screenshot file: \(screenshot.url.path)
        Please upload this PNG manually when the GitHub issue page opens.
        """
    }

    private func captureScreenshotIfNeeded() {
        guard includeScreenshot, !isCapturingScreenshot else {
            return
        }

        isCapturingScreenshot = true

        Task { @MainActor in
            let result = await SettingsIssueScreenshotCapture.captureCurrentAppWindow()
            switch result {
            case .success(let capturedScreenshot):
                screenshot = capturedScreenshot
                screenshotStatusKey = nil
            case .failure(let error):
                screenshot = nil
                screenshotStatusKey = error.statusKey
            }
            isCapturingScreenshot = false
        }
    }
}

private enum SettingsReportTextViewMetrics {
    static let textInset = NSSize(width: 24, height: 26)
}

private struct SettingsReportTextView: NSViewRepresentable {
    @Binding var text: String
    let maxLength: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = SettingsReportTextViewMetrics.textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SettingsReportTextView

        init(parent: SettingsReportTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            if textView.string.count > parent.maxLength {
                let trimmed = String(textView.string.prefix(parent.maxLength))
                textView.string = trimmed
                parent.text = trimmed
                return
            }

            parent.text = textView.string
        }
    }
}

private struct SettingsIssueScreenshot: Identifiable {
    let id = UUID()
    let image: NSImage
    let url: URL
}

private enum SettingsIssueScreenshotCaptureError: Error {
    case permissionDenied
    case windowUnavailable
    case captureFailed
    case saveFailed

    var statusKey: String {
        switch self {
        case .permissionDenied:
            "settings.reportIssueScreenshotDenied"
        case .windowUnavailable:
            "settings.reportIssueScreenshotUnavailable"
        case .captureFailed, .saveFailed:
            "settings.reportIssueScreenshotFailed"
        }
    }
}

@MainActor
private enum SettingsIssueScreenshotCapture {
    static func captureCurrentAppWindow() async -> Result<SettingsIssueScreenshot, SettingsIssueScreenshotCaptureError> {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return .failure(.permissionDenied)
        }

        guard let windowID = candidateWindowID else {
            return .failure(.windowUnavailable)
        }

        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return .failure(.windowUnavailable)
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(1, Int(filter.contentRect.width * scale))
            configuration.height = max(1, Int(filter.contentRect.height * scale))
            configuration.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )

            guard let data = image.pngData else {
                return .failure(.saveFailed)
            }

            let timestamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PitcherPlant-Report-Screenshot-\(timestamp).png")

            try data.write(to: url, options: .atomic)
            return .success(SettingsIssueScreenshot(image: image, url: url))
        } catch {
            return .failure(.captureFailed)
        }
    }

    private static var candidateWindowID: CGWindowID? {
        let visibleWindows = NSApp.windows.filter { window in
            window.isVisible
                && !window.isMiniaturized
                && window.windowNumber > 0
                && window.sheetParent == nil
                && window.level == .normal
                && window.contentView != nil
        }

        if let sheetParent = visibleWindows.first(where: { $0.attachedSheet != nil }) {
            return CGWindowID(sheetParent.windowNumber)
        }
        if let mainWindow = NSApp.mainWindow, visibleWindows.contains(where: { $0 === mainWindow }) {
            return CGWindowID(mainWindow.windowNumber)
        }
        return visibleWindows.first.map { CGWindowID($0.windowNumber) }
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct SettingsDiagnosticSummary: View {
    @Environment(AppState.self) private var appState
    let version: AppVersionInfo

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text(appState.t("settings.infoApp"))
                    .foregroundStyle(.secondary)
                Text(version.name)
            }
            GridRow {
                Text(appState.t("settings.infoVersion"))
                    .foregroundStyle(.secondary)
                Text(version.versionAndBuild)
            }
            GridRow {
                Text(appState.t("settings.infoBundle"))
                    .foregroundStyle(.secondary)
                Text(version.bundleIdentifier)
            }
            GridRow {
                Text("macOS")
                    .foregroundStyle(.secondary)
                Text(ProcessInfo.processInfo.operatingSystemVersionString)
            }
        }
        .font(.footnote)
        .textSelection(.enabled)
    }
}

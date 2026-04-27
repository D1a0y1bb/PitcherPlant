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
                SettingsGroup(title: appState.t("settings.general"), systemImage: "gearshape") {
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

                SettingsGroup(title: appState.t("settings.appearance"), systemImage: "paintbrush") {
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

                SettingsGroup(title: appState.t("settings.auditDefaults"), systemImage: "slider.horizontal.3") {
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
                        SettingsMappedToggle(
                            isOn: draftWhitelistHideBinding()
                        )
                    }
                }

                SettingsGroup(title: appState.t("settings.reports"), systemImage: "doc.text.magnifyingglass") {
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
                        SettingsMappedToggle(
                            isOn: exportPDFBinding()
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

                SettingsGroup(title: appState.t("settings.dataMigration"), systemImage: "externaldrive") {
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

                SettingsGroup(title: appState.t("settings.shortcuts"), systemImage: "command") {
                    SettingsActionRow(
                        title: appState.t("command.startAudit"),
                        subtitle: appState.t("settings.startAuditDescription"),
                        buttonTitle: appState.t("toolbar.start"),
                        systemImage: "play.fill"
                    ) {
                        Task { await appState.startAudit() }
                    }
                    .disabled(appState.isRunningAudit)

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
            .padding(28)
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

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.appSettings[keyPath: keyPath] },
            set: { value in
                appState.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func draftBinding(_ keyPath: WritableKeyPath<AuditConfiguration, String>) -> Binding<String> {
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

    private func draftWhitelistHideBinding() -> Binding<Bool> {
        Binding(
            get: { appState.draftConfiguration.whitelistMode == .hide },
            set: { enabled in
                appState.updateDraft { $0.whitelistMode = enabled ? .hide : .mark }
            }
        )
    }

    private func exportPDFBinding() -> Binding<Bool> {
        Binding(
            get: { appState.appSettings.defaultExportFormat == .pdf },
            set: { enabled in
                appState.updateSettings { $0.defaultExportFormat = enabled ? .pdf : .html }
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
}

private enum SettingsLayout {
    static let sectionIconWidth: CGFloat = 18
    static let sectionTitleSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 14
    static let trailingWidth: CGFloat = 360
    static let menuWidth: CGFloat = 220
    static let numberFieldWidth: CGFloat = 58
    static let stepperWidth: CGFloat = 156
    static let hintWidth: CGFloat = 70
    static let thresholdControlWidth: CGFloat = stepperWidth + 8 + hintWidth
    static let pathControlHeight: CGFloat = 30
    static let pathButtonWidth: CGFloat = 96
    static let compactPathWidth: CGFloat = 360
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: SettingsLayout.sectionTitleSpacing) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsLayout.sectionIconWidth, alignment: .center)

                Text(title)
                    .font(.headline)
            }
            .padding(.leading, SettingsLayout.horizontalPadding)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsStatusPill(value)
        }
    }
}

private struct SettingsPathRow: View {
    @Environment(AppState.self) private var appState
    let title: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        SettingsPathBlockRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, minHeight: SettingsLayout.pathControlHeight, maxHeight: SettingsLayout.pathControlHeight)

                Button {
                    chooseDirectory()
                } label: {
                    Label(appState.t("settings.choose"), systemImage: "folder")
                        .frame(width: SettingsLayout.pathButtonWidth)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = appState.t("settings.choose")

        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }
}

private struct SettingsReadOnlyPathRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsPathDisplay(value: value)
        }
    }
}

private struct SettingsPathDisplay: View {
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 9)
        .frame(width: SettingsLayout.compactPathWidth, height: SettingsLayout.pathControlHeight, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.14))
        }
    }
}

private struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        SettingsPathBlockRow(title: title, subtitle: subtitle) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: SettingsLayout.pathControlHeight, maxHeight: SettingsLayout.pathControlHeight)
        }
    }
}

private struct SettingsNumberFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let hint: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsNumberStepper(
                value: $value,
                range: 0...1,
                step: 0.05,
                hint: hint
            )
        }
    }
}

private struct SettingsIntegerFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let hint: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsIntegerStepper(
                value: $value,
                range: 0...64,
                step: 1,
                hint: hint
            )
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingsMappedToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            content
        }
    }
}

private struct SettingsButtonGroupRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                content
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct SettingsMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let width: CGFloat
    let title: (Value) -> String
    var systemImage: ((Value) -> String)?

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                menuLabel(for: option)
                    .tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: width, alignment: .trailing)
    }

    @ViewBuilder
    private func menuLabel(for option: Value) -> some View {
        if let systemImage {
            Label(title(option), systemImage: systemImage(option))
        } else {
            Text(title(option))
        }
    }
}

private struct SettingsNumberStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let hint: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button {
                    value = clamped(value - step)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value <= range.lowerBound)

                TextField(hint, value: clampedBinding, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .frame(width: SettingsLayout.numberFieldWidth)

                Button {
                    value = clamped(value + step)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value >= range.upperBound)
            }
            .frame(width: SettingsLayout.stepperWidth, height: 30)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.separator.opacity(0.14))
            }

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.hintWidth, alignment: .leading)
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

private struct SettingsIntegerStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let hint: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button {
                    value = clamped(value - step)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value <= range.lowerBound)

                TextField(hint, value: clampedBinding, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .frame(width: SettingsLayout.numberFieldWidth)

                Button {
                    value = clamped(value + step)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(SettingsStepperButtonStyle())
                .disabled(value >= range.upperBound)
            }
            .frame(width: SettingsLayout.stepperWidth, height: 30)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.separator.opacity(0.14))
            }

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.hintWidth, alignment: .leading)
        }
        .frame(width: SettingsLayout.thresholdControlWidth, alignment: .trailing)
    }

    private var clampedBinding: Binding<Int> {
        Binding(
            get: { clamped(value) },
            set: { value = clamped($0) }
        )
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

private struct SettingsStepperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct SettingsControlRow<Content: View>: View {
    @Environment(\.settingsSearchQuery) private var searchQuery
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowText(title: title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                content
                    .controlSize(.small)
                    .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
            }
        }
        .opacity(searchOpacity)
    }

    private var searchOpacity: Double {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 1
        }
        return settingMatchesSearch(title, subtitle, query: searchQuery) ? 1 : 0.28
    }
}

private struct SettingsPathBlockRow<Content: View>: View {
    @Environment(\.settingsSearchQuery) private var searchQuery
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowContainer {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRowText(title: title, subtitle: subtitle)
                content
                    .controlSize(.small)
            }
        }
        .opacity(searchOpacity)
    }

    private var searchOpacity: Double {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 1
        }
        return settingMatchesSearch(title, subtitle, query: searchQuery) ? 1 : 0.28
    }
}

private struct SettingsRowContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsLayout.horizontalPadding)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
    }
}

private struct SettingsRowText: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsStatusPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.64))
            .clipShape(Capsule())
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.42))
            .frame(height: 0.5)
            .padding(.horizontal, SettingsLayout.horizontalPadding)
    }
}

private func settingMatchesSearch(_ title: String, _ subtitle: String, query: String) -> Bool {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return true
    }
    return title.localizedCaseInsensitiveContains(trimmedQuery)
        || subtitle.localizedCaseInsensitiveContains(trimmedQuery)
}

private extension EnvironmentValues {
    @Entry var settingsSearchQuery = ""
}

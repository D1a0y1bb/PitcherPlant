import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader()

                SettingsGroup(title: appState.t("settings.general"), systemImage: "gearshape") {
                    SettingsPickerRow(
                        title: appState.t("settings.language"),
                        subtitle: appState.t("settings.languageDescription")
                    ) {
                        Picker(appState.t("settings.language"), selection: settingsBinding(\.language)) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: SettingsLayout.pickerWidth)
                    }

                    SettingsDivider()

                    SettingsPickerRow(
                        title: appState.t("settings.defaultPage"),
                        subtitle: appState.t("settings.defaultPageDescription")
                    ) {
                        Picker(appState.t("settings.defaultPage"), selection: settingsBinding(\.defaultSidebarItem)) {
                            ForEach(MainSidebarItem.allCases) { item in
                                Label(appState.title(for: item), systemImage: item.systemImage).tag(item)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: SettingsLayout.pickerWidth)
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
                        Picker(appState.t("settings.theme"), selection: settingsBinding(\.appearance)) {
                            Text(appState.t("common.followSystem")).tag(AppAppearance.system)
                            Text(appState.t("common.light")).tag(AppAppearance.light)
                            Text(appState.t("common.dark")).tag(AppAppearance.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: SettingsLayout.segmentedWidth)
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
                        subtitle: appState.t("settings.whitelistModeDescription")
                    ) {
                        Picker(appState.t("audit.whitelistMode"), selection: draftWhitelistModeBinding()) {
                            ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                                Text(appState.title(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: SettingsLayout.shortSegmentedWidth)
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
                        subtitle: appState.t("settings.defaultExportFormatDescription")
                    ) {
                        Picker(appState.t("settings.defaultExportFormat"), selection: settingsBinding(\.defaultExportFormat)) {
                            ForEach(ExportRecord.Format.allCases, id: \.self) { format in
                                Text(format.displayTitle).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: SettingsLayout.shortSegmentedWidth)
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
            .frame(maxWidth: SettingsLayout.contentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
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

    private func draftWhitelistModeBinding() -> Binding<AuditConfiguration.WhitelistMode> {
        Binding(
            get: { appState.draftConfiguration.whitelistMode },
            set: { value in appState.updateDraft { $0.whitelistMode = value } }
        )
    }
}

private struct SettingsPageHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.t("settings.title"))
                .font(.title2.weight(.semibold))
            Text("PitcherPlant · macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private enum SettingsLayout {
    static let contentWidth: CGFloat = 820
    static let horizontalPadding: CGFloat = 14
    static let pickerWidth: CGFloat = 200
    static let segmentedWidth: CGFloat = 230
    static let shortSegmentedWidth: CGFloat = 142
    static let numberFieldWidth: CGFloat = 74

    static var dividerLeadingPadding: CGFloat {
        horizontalPadding + 36
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)
            }

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

                Button(appState.t("settings.choose")) {
                    chooseDirectory()
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
        SettingsPathBlockRow(title: title, subtitle: subtitle) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.separator.opacity(0.16))
                }
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
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: SettingsLayout.numberFieldWidth)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: SettingsLayout.numberFieldWidth)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

private struct SettingsControlRow<Content: View>: View {
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
            }
        }
    }
}

private struct SettingsPathBlockRow<Content: View>: View {
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
        Divider()
            .padding(.leading, SettingsLayout.dividerLeadingPadding)
    }
}

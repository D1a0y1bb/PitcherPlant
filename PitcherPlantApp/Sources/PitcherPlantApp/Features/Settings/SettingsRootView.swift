import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader()

                SettingsFormSection(title: appState.t("settings.general"), systemImage: "gearshape") {
                    SettingsPickerRow(title: appState.t("settings.language")) {
                        Picker(appState.t("settings.language"), selection: settingsBinding(\.language)) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.pickerWidth)
                    }

                    SettingsDivider()

                    SettingsPickerRow(title: appState.t("settings.defaultPage")) {
                        Picker(appState.t("settings.defaultPage"), selection: settingsBinding(\.defaultSidebarItem)) {
                            ForEach(MainSidebarItem.allCases) { item in
                                Label(appState.title(for: item), systemImage: item.systemImage).tag(item)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.pickerWidth)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.menuBar"),
                        subtitle: appState.t("menu.searchPrompt"),
                        isOn: settingsBinding(\.showMenuBarExtra)
                    )

                    SettingsDivider()

                    SettingsValueRow(title: appState.t("settings.workspace"), value: appState.workspaceRoot.path)
                }

                SettingsFormSection(title: appState.t("settings.appearance"), systemImage: "paintbrush") {
                    SettingsPickerRow(title: appState.t("settings.theme")) {
                        Picker(appState.t("settings.theme"), selection: settingsBinding(\.appearance)) {
                            Text(appState.t("common.followSystem")).tag(AppAppearance.system)
                            Text(appState.t("common.light")).tag(AppAppearance.light)
                            Text(appState.t("common.dark")).tag(AppAppearance.dark)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
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
                        subtitle: "34–44 pt",
                        isOn: settingsBinding(\.compactRows)
                    )
                }

                SettingsFormSection(title: appState.t("settings.auditDefaults"), systemImage: "slider.horizontal.3") {
                    SettingsPathRow(
                        title: appState.t("audit.directory"),
                        text: draftBinding(\.directoryPath)
                    )

                    SettingsDivider()

                    SettingsPathRow(
                        title: appState.t("audit.outputDirectory"),
                        text: draftBinding(\.outputDirectoryPath)
                    )

                    SettingsDivider()

                    SettingsTextFieldRow(
                        title: appState.t("audit.fileNameTemplate"),
                        text: draftBinding(\.reportNameTemplate)
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.textThreshold"),
                        value: draftDoubleBinding(\.textThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsNumberFieldRow(
                        title: appState.t("audit.dedupThreshold"),
                        value: draftDoubleBinding(\.dedupThreshold),
                        hint: "0.00–1.00"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.imageThreshold"),
                        value: draftIntBinding(\.imageThreshold),
                        hint: "0–64"
                    )

                    SettingsDivider()

                    SettingsIntegerFieldRow(
                        title: appState.t("audit.simhashThreshold"),
                        value: draftIntBinding(\.simhashThreshold),
                        hint: "bit"
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("audit.visionOCR"),
                        subtitle: "Vision",
                        isOn: draftBoolBinding(\.useVisionOCR)
                    )

                    SettingsDivider()

                    SettingsPickerRow(title: appState.t("audit.whitelistMode")) {
                        Picker(appState.t("audit.whitelistMode"), selection: draftWhitelistModeBinding()) {
                            ForEach(AuditConfiguration.WhitelistMode.allCases, id: \.self) { mode in
                                Text(appState.title(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: SettingsLayout.shortSegmentedWidth)
                    }
                }

                SettingsFormSection(title: appState.t("settings.reports"), systemImage: "doc.text.magnifyingglass") {
                    SettingsToggleRow(
                        title: appState.t("settings.preferInAppReports"),
                        subtitle: appState.t("reports.subtitle"),
                        isOn: settingsBinding(\.preferInAppReports)
                    )

                    SettingsDivider()

                    SettingsPickerRow(title: appState.t("settings.defaultExportFormat")) {
                        Picker(appState.t("settings.defaultExportFormat"), selection: settingsBinding(\.defaultExportFormat)) {
                            ForEach(ExportRecord.Format.allCases, id: \.self) { format in
                                Text(format.displayTitle).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: SettingsLayout.shortSegmentedWidth)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.showLegacyBadges"),
                        subtitle: appState.t("common.legacy"),
                        isOn: settingsBinding(\.showLegacyBadges)
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: appState.t("settings.attachmentPreview"),
                        subtitle: appState.t("reports.attachments"),
                        isOn: settingsBinding(\.showAttachmentPreviews)
                    )
                }

                SettingsFormSection(title: appState.t("settings.dataMigration"), systemImage: "externaldrive") {
                    SettingsValueRow(title: appState.t("settings.databaseLocation"), value: appState.database.databaseURL.path)

                    SettingsDivider()

                    SettingsValueRow(title: appState.t("settings.migrationSummary"), value: summaryText)

                    SettingsDivider()

                    SettingsValueRow(title: appState.t("settings.recordCounts"), value: recordCounts)

                    SettingsDivider()

                    SettingsButtonGroupRow(title: appState.t("settings.dataActions")) {
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

                SettingsFormSection(title: appState.t("settings.shortcuts"), systemImage: "command") {
                    SettingsButtonGroupRow(title: appState.t("settings.quickOpen")) {
                        Button {
                            appState.selectedMainSidebar = .newAudit
                        } label: {
                            Label(appState.t("command.startAudit"), systemImage: "play.fill")
                        }

                        Button {
                            appState.showReportsCenter()
                        } label: {
                            Label(appState.t("settings.openReports"), systemImage: "doc.text.magnifyingglass")
                        }
                    }

                    SettingsDivider()

                    SettingsButtonGroupRow(title: appState.t("settings.reportActions")) {
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
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private enum SettingsLayout {
    static let labelWidth: CGFloat = 164
    static let columnSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 18
    static let pickerWidth: CGFloat = 230
    static let segmentedWidth: CGFloat = 280
    static let shortSegmentedWidth: CGFloat = 168
    static let textFieldWidth: CGFloat = 470
    static let numberFieldWidth: CGFloat = 90

    static var dividerLeadingPadding: CGFloat {
        horizontalPadding + labelWidth + columnSpacing
    }
}

private struct SettingsFormSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.separator.opacity(0.18))
            }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        SettingsRowShell(title: title) {
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsPathRow: View {
    @Environment(AppState.self) private var appState
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsRowShell(title: title) {
            HStack(spacing: 8) {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: SettingsLayout.textFieldWidth)

                Button(appState.t("settings.choose")) {
                    chooseDirectory()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SettingsRowShell(title: title) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: SettingsLayout.textFieldWidth)
        }
    }
}

private struct SettingsNumberFieldRow: View {
    let title: String
    @Binding var value: Double
    let hint: String

    var body: some View {
        SettingsRowShell(title: title) {
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
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
    @Binding var value: Int
    let hint: String

    var body: some View {
        SettingsRowShell(title: title) {
            HStack(spacing: 8) {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
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
        SettingsRowShell(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .frame(width: 28, alignment: .leading)
        }
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowShell(title: title) {
            content
        }
    }
}

private struct SettingsButtonGroupRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowShell(title: title) {
            HStack(spacing: 8) {
                content
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct SettingsRowShell<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: SettingsLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: SettingsLayout.labelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SettingsLayout.horizontalPadding)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsLayout.dividerLeadingPadding)
    }
}

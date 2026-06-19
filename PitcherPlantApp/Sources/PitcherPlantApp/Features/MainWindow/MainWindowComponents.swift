import SwiftUI

struct NativePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppPageShell(spacing: 24) {
            content
        }
    }
}

struct NativePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    actions
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                HStack(spacing: 8) {
                    actions
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.pageTitle)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(AppTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NativeSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        AppSectionPanel(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct JobInspectorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        AppInspectorPanel(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct SearchHeader: View {
    @Environment(AppState.self) private var appState
    let title: String
    let count: Int
    @Binding var query: String
    let prompt: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                searchField
            }

            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                searchField
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("\(count) \(appState.t("common.countSuffix"))")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        TextField(prompt, text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
    }
}

struct DenseHeader: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: index == 0 ? .leading : .trailing)
                    .frame(width: index == 0 ? nil : (index == 1 ? 74 : index == 2 ? 54 : 128), alignment: .trailing)
            }
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 8)
    }
}

struct SummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

struct SummaryStrip: View {
    let items: [SummaryItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(max(items.count, 1), 4)), spacing: 12) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.value)
                            .font(.title2.weight(.semibold))
                        Text(item.title)
                            .font(AppTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }
}

struct SettingsTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        AppControlRow(title: title) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsPathPickerRow: View {
    @Environment(AppState.self) private var appState
    let title: String
    var subtitle = ""
    var icon: SettingsRowIconStyle = .generic
    @Binding var text: String
    var canCreateDirectories = false

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsFieldChrome {
                TextField(title, text: $text)
                    .textFieldStyle(.plain)
                    .font(AppTypography.smallCode)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(title))

                Button {
                    chooseDirectory()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(appState.t("settings.choose"))
                .accessibilityLabel(Text(appState.t("settings.choose")))
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreateDirectories
        panel.prompt = appState.t("settings.choose")
        panel.directoryURL = startingDirectoryURL()

        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }

    private func startingDirectoryURL() -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        let parentURL = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return parentURL
        }

        return nil
    }
}

struct SettingsNumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let hint: String

    var body: some View {
        AppControlRow(title: title, trailingWidth: SettingsLayout.thresholdControlWidth) {
            SettingsNumberStepper(
                title: title,
                value: $value,
                range: range,
                step: step,
                hint: hint
            )
        }
    }
}

struct SettingsIntegerRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let hint: String

    var body: some View {
        AppControlRow(title: title, trailingWidth: SettingsLayout.thresholdControlWidth) {
            SettingsIntegerStepper(
                title: title,
                value: $value,
                range: range,
                step: step,
                hint: hint
            )
        }
    }
}

struct StatusDot: View {
    let status: AuditJobStatus

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }

    private var systemImage: String {
        switch status {
        case .queued: return "clock"
        case .running: return "play.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct PlainBadgeLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.badge)
            .foregroundStyle(.secondary)
    }
}

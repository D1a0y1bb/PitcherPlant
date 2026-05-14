import SwiftUI
import AppKit

enum SettingsLayout {
    static let pageMaxWidth: CGFloat = 850
    static let pageHorizontalPadding: CGFloat = 34
    static let pageTopPadding: CGFloat = 30
    static let pageBottomPadding: CGFloat = 40
    static let sectionSpacing: CGFloat = 20
    static let groupHorizontalPadding: CGFloat = 14
    static let rowLeadingPadding: CGFloat = 14
    static let rowTrailingPadding: CGFloat = 14
    static let rowIconSize: CGFloat = 20
    static let rowMinHeight: CGFloat = 38
    static let groupCornerRadius: CGFloat = 14
    static let dividerLeadingPadding: CGFloat = rowLeadingPadding
    static let trailingWidth: CGFloat = 380
    static let menuWidth: CGFloat = 156
    static let wideMenuWidth: CGFloat = 240
    static let numberFieldWidth: CGFloat = 62
    static let stepperWidth: CGFloat = 26
    static let thresholdControlSpacing: CGFloat = 4
    static let hintWidth: CGFloat = 70
    static let thresholdControlWidth: CGFloat = numberFieldWidth + thresholdControlSpacing + stepperWidth
    static let pathControlHeight: CGFloat = 34
    static let compactPathWidth: CGFloat = trailingWidth
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var badge: String?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppTypography.sectionTitle)

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                        }
                        .accessibilityLabel(Text(badge))
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsLayout.groupHorizontalPadding)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsLayout.groupCornerRadius, style: .continuous)
                    .fill(groupFill)
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsLayout.groupCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupFill: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)
    }
}

struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsStatusText(value)
        }
    }
}

struct SettingsPathRow: View {
    @Environment(AppState.self) private var appState
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @Binding var text: String

    var body: some View {
        Button {
            chooseDirectory()
        } label: {
            SettingsRowContainer {
                HStack(alignment: .center, spacing: 16) {
                    SettingsRowIcon(style: icon)

                    SettingsRowText(title: title, subtitle: subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(subtitle)
        .accessibilityLabel(Text(title))
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
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
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}

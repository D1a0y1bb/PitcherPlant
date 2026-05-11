import SwiftUI
import AppKit

enum SettingsLayout {
    static let pageMaxWidth: CGFloat = 780
    static let pageHorizontalPadding: CGFloat = 48
    static let pageTopPadding: CGFloat = 42
    static let pageBottomPadding: CGFloat = 44
    static let sectionSpacing: CGFloat = 34
    static let groupHorizontalPadding: CGFloat = 18
    static let rowLeadingPadding: CGFloat = 18
    static let rowTrailingPadding: CGFloat = 14
    static let rowIconSize: CGFloat = 24
    static let rowMinHeight: CGFloat = 56
    static let groupCornerRadius: CGFloat = 14
    static let dividerLeadingPadding: CGFloat = rowLeadingPadding + rowIconSize + 18
    static let trailingWidth: CGFloat = 330
    static let menuWidth: CGFloat = 190
    static let numberFieldWidth: CGFloat = 50
    static let stepperWidth: CGFloat = 132
    static let hintWidth: CGFloat = 70
    static let thresholdControlWidth: CGFloat = stepperWidth + 8 + hintWidth
    static let pathControlHeight: CGFloat = 34
    static let compactPathWidth: CGFloat = trailingWidth
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionTitle)
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
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsEditablePathControl(
                title: title,
                text: $text,
                chooseDirectory: chooseDirectory
            )
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

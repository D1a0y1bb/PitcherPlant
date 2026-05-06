import SwiftUI

enum SettingsLayout {
    static let horizontalPadding: CGFloat = 14
    static let groupHorizontalPadding: CGFloat = 20
    static let rowLeadingPadding: CGFloat = 18
    static let rowIconSize: CGFloat = 28
    static let rowIconCornerRadius: CGFloat = 7
    static let rowMinHeight: CGFloat = 56
    static let dividerLeadingPadding: CGFloat = rowLeadingPadding + rowIconSize + 16
    static let trailingWidth: CGFloat = 360
    static let menuWidth: CGFloat = 220
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsLayout.groupHorizontalPadding)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
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

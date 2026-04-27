import SwiftUI

enum SettingsLayout {
    static let horizontalPadding: CGFloat = 14
    static let rowLeadingPadding: CGFloat = horizontalPadding
    static let trailingWidth: CGFloat = 360
    static let menuWidth: CGFloat = 220
    static let numberFieldWidth: CGFloat = 50
    static let stepperWidth: CGFloat = 132
    static let hintWidth: CGFloat = 70
    static let thresholdControlWidth: CGFloat = stepperWidth + 8 + hintWidth
    static let pathControlHeight: CGFloat = 34
    static let compactPathWidth: CGFloat = trailingWidth
    static let controlCornerRadius: CGFloat = 9
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionTitle)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    content
                }
                .settingsPanelSurface(cornerRadius: 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, -SettingsLayout.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsStatusPill(value)
        }
    }
}

struct SettingsPathRow: View {
    @Environment(AppState.self) private var appState
    let title: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
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

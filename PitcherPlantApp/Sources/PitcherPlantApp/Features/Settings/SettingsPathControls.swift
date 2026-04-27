import SwiftUI

struct SettingsEditablePathControl: View {
    let title: String
    @Binding var text: String
    let chooseDirectory: () -> Void

    var body: some View {
        Button {
            chooseDirectory()
        } label: {
            Label {
                Text(text.isEmpty ? title : text)
                    .font(AppTypography.smallCode)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "folder")
            }
            .frame(width: SettingsLayout.trailingWidth, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
    }
}

struct SettingsReadOnlyPathRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsPathDisplay(value: value)
        }
    }
}

struct SettingsPathDisplay: View {
    let value: String

    var body: some View {
        TextField("", text: .constant(value))
            .textFieldStyle(.roundedBorder)
            .font(AppTypography.smallCode)
            .disabled(true)
            .frame(width: SettingsLayout.compactPathWidth, alignment: .leading)
    }
}

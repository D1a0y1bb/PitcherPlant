import SwiftUI

struct SettingsEditablePathControl: View {
    let title: String
    @Binding var text: String
    let chooseDirectory: () -> Void

    var body: some View {
        Button {
            chooseDirectory()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(text.isEmpty ? title : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(width: SettingsLayout.trailingWidth, height: SettingsLayout.pathControlHeight, alignment: .leading)
            .settingsControlBackground()
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .frame(width: SettingsLayout.compactPathWidth, height: SettingsLayout.pathControlHeight, alignment: .leading)
        .settingsControlBackground()
    }
}


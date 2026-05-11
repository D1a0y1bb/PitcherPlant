import AppKit
import SwiftUI

struct SettingsEditablePathControl: View {
    let title: String
    @Binding var text: String
    let chooseDirectory: () -> Void

    var body: some View {
        Button {
            chooseDirectory()
        } label: {
            HStack(spacing: 6) {
                Text(text.isEmpty ? title : text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
    }
}

struct SettingsReadOnlyPathRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    let value: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsPathDisplay(title: title, value: value)
        }
    }
}

struct SettingsPathDisplay: View {
    let title: String
    let value: String

    var body: some View {
        Text(value)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: SettingsLayout.compactPathWidth, alignment: .trailing)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
            .help(value)
    }
}

struct SettingsFolderActionRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    let url: URL

    var body: some View {
        SettingsActionRow(title: title, subtitle: subtitle, icon: icon) {
            NSWorkspace.shared.open(directoryURL)
        }
        .accessibilityValue(Text(url.path))
        .help(url.path)
    }

    private var directoryURL: URL {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? url : url.deletingLastPathComponent()
        }
        return url.pathExtension.isEmpty ? url : url.deletingLastPathComponent()
    }
}

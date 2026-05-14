import SwiftUI

struct SettingsControlRow<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: SettingsRowIconStyle
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowIcon(style: icon)

                SettingsRowText(title: title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                content
                    .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
            }
        }
        .help(subtitle)
    }
}

struct SettingsRowContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SettingsLayout.rowLeadingPadding)
            .padding(.trailing, SettingsLayout.rowTrailingPadding)
            .padding(.vertical, 2)
            .frame(minHeight: SettingsLayout.rowMinHeight)
    }
}

struct SettingsRowIconStyle {
    let systemImage: String
    let color: Color
}

extension SettingsRowIconStyle {
    static let language = SettingsRowIconStyle(systemImage: "globe", color: .blue)
    static let theme = SettingsRowIconStyle(systemImage: "circle.lefthalf.filled", color: .indigo)
    static let inspector = SettingsRowIconStyle(systemImage: "sidebar.right", color: .teal)
    static let listDensity = SettingsRowIconStyle(systemImage: "list.bullet.rectangle", color: .purple)
    static let inputFolder = SettingsRowIconStyle(systemImage: "folder", color: .blue)
    static let outputFolder = SettingsRowIconStyle(systemImage: "tray.and.arrow.down", color: .green)
    static let textThreshold = SettingsRowIconStyle(systemImage: "text.quote", color: .mint)
    static let duplicateThreshold = SettingsRowIconStyle(systemImage: "doc.on.doc", color: .orange)
    static let imageThreshold = SettingsRowIconStyle(systemImage: "photo", color: .pink)
    static let simhashThreshold = SettingsRowIconStyle(systemImage: "number", color: .cyan)
    static let vision = SettingsRowIconStyle(systemImage: "eye", color: .purple)
    static let whitelist = SettingsRowIconStyle(systemImage: "checkmark.shield", color: .green)
    static let calibrationPreset = SettingsRowIconStyle(systemImage: "slider.horizontal.3", color: .orange)
    static let calibrationRun = SettingsRowIconStyle(systemImage: "chart.xyaxis.line", color: .blue)
    static let calibrationStatus = SettingsRowIconStyle(systemImage: "info.circle", color: .blue)
    static let assistantMode = SettingsRowIconStyle(systemImage: "sparkles", color: .purple)
    static let assistantProvider = SettingsRowIconStyle(systemImage: "network", color: .blue)
    static let assistantProtocol = SettingsRowIconStyle(systemImage: "point.3.connected.trianglepath.dotted", color: .indigo)
    static let assistantEndpoint = SettingsRowIconStyle(systemImage: "link", color: .teal)
    static let assistantModel = SettingsRowIconStyle(systemImage: "cpu", color: .purple)
    static let assistantTimeout = SettingsRowIconStyle(systemImage: "timer", color: .orange)
    static let assistantTokens = SettingsRowIconStyle(systemImage: "number", color: .cyan)
    static let assistantTemperature = SettingsRowIconStyle(systemImage: "thermometer.medium", color: .orange)
    static let assistantData = SettingsRowIconStyle(systemImage: "lock.doc", color: .green)
    static let assistantCredential = SettingsRowIconStyle(systemImage: "key", color: .yellow)
    static let assistantConnection = SettingsRowIconStyle(systemImage: "checkmark.seal", color: .green)
    static let reportPreference = SettingsRowIconStyle(systemImage: "doc.text.magnifyingglass", color: .blue)
    static let exportFormat = SettingsRowIconStyle(systemImage: "square.and.arrow.up", color: .purple)
    static let attachmentPreview = SettingsRowIconStyle(systemImage: "paperclip", color: .teal)
    static let database = SettingsRowIconStyle(systemImage: "cylinder.split.1x2", color: .blue)
    static let recordCounts = SettingsRowIconStyle(systemImage: "number.square", color: .orange)
    static let dataActions = SettingsRowIconStyle(systemImage: "externaldrive", color: .green)
    static let reportIssue = SettingsRowIconStyle(systemImage: "exclamationmark.bubble", color: .red)
    static let helpCenter = SettingsRowIconStyle(systemImage: "questionmark.circle", color: .blue)
    static let terms = SettingsRowIconStyle(systemImage: "list.bullet.rectangle.portrait", color: .primary)
    static let privacy = SettingsRowIconStyle(systemImage: "lock", color: .primary)
    static let about = SettingsRowIconStyle(systemImage: "circle.fill", color: .primary)
    static let update = SettingsRowIconStyle(systemImage: "arrow.up.circle", color: .primary)
    static let generic = SettingsRowIconStyle(systemImage: "gearshape", color: .gray)
}

struct SettingsRowIcon: View {
    let style: SettingsRowIconStyle

    var body: some View {
        Image(systemName: style.systemImage)
            .font(.system(size: 14, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .frame(width: SettingsLayout.rowIconSize, height: SettingsLayout.rowIconSize)
            .accessibilityHidden(true)
    }
}

struct SettingsRowText: View {
    let title: String
    let subtitle: String

    var body: some View {
        Text(title)
            .font(.body.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(subtitle)
    }
}

struct SettingsStatusText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(height: 0.5)
            .padding(.leading, SettingsLayout.dividerLeadingPadding)
            .padding(.trailing, SettingsLayout.rowTrailingPadding)
    }
}

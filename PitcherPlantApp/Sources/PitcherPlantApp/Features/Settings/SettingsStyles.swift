import SwiftUI

struct SettingsControlRow<Content: View>: View {
    @Environment(\.settingsSearchQuery) private var searchQuery
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
        .opacity(searchOpacity)
        .help(subtitle)
    }

    private var searchOpacity: Double {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 1
        }
        return settingMatchesSearch(title, subtitle, query: searchQuery) ? 1 : 0.28
    }
}

struct SettingsRowContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SettingsLayout.rowLeadingPadding)
            .padding(.trailing, SettingsLayout.groupHorizontalPadding)
            .padding(.vertical, 10)
            .frame(minHeight: SettingsLayout.rowMinHeight)
    }
}

struct SettingsRowIconStyle {
    let systemImage: String
    let color: Color
}

extension SettingsRowIconStyle {
    static let language = SettingsRowIconStyle(systemImage: "globe", color: .blue)
    static let menuBar = SettingsRowIconStyle(systemImage: "menubar.rectangle", color: .orange)
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
    static let assistantCommand = SettingsRowIconStyle(systemImage: "terminal", color: .blue)
    static let assistantTimeout = SettingsRowIconStyle(systemImage: "timer", color: .orange)
    static let assistantCredential = SettingsRowIconStyle(systemImage: "key", color: .yellow)
    static let reportPreference = SettingsRowIconStyle(systemImage: "doc.text.magnifyingglass", color: .blue)
    static let exportFormat = SettingsRowIconStyle(systemImage: "square.and.arrow.up", color: .purple)
    static let attachmentPreview = SettingsRowIconStyle(systemImage: "paperclip", color: .teal)
    static let database = SettingsRowIconStyle(systemImage: "cylinder.split.1x2", color: .blue)
    static let recordCounts = SettingsRowIconStyle(systemImage: "number.square", color: .orange)
    static let dataActions = SettingsRowIconStyle(systemImage: "externaldrive", color: .green)
    static let startAudit = SettingsRowIconStyle(systemImage: "play.fill", color: .green)
    static let cancelAudit = SettingsRowIconStyle(systemImage: "stop.fill", color: .red)
    static let openReports = SettingsRowIconStyle(systemImage: "doc.text.magnifyingglass", color: .indigo)
    static let reportActions = SettingsRowIconStyle(systemImage: "square.and.arrow.up.on.square", color: .pink)
    static let generic = SettingsRowIconStyle(systemImage: "gearshape", color: .gray)
}

struct SettingsRowIcon: View {
    let style: SettingsRowIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsLayout.rowIconCornerRadius, style: .continuous)
                .fill(style.color)

            Image(systemName: style.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: SettingsLayout.rowIconSize, height: SettingsLayout.rowIconSize)
        .accessibilityHidden(true)
    }
}

struct SettingsRowText: View {
    let title: String
    let subtitle: String

    var body: some View {
        Text(title)
            .font(AppTypography.rowPrimary.weight(.semibold))
            .lineLimit(2)
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
            .font(AppTypography.metadata)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsLayout.dividerLeadingPadding)
            .padding(.trailing, SettingsLayout.groupHorizontalPadding)
    }
}

private func settingMatchesSearch(_ title: String, _ subtitle: String, query: String) -> Bool {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return true
    }
    return title.localizedCaseInsensitiveContains(trimmedQuery)
        || subtitle.localizedCaseInsensitiveContains(trimmedQuery)
}

extension EnvironmentValues {
    @Entry var settingsSearchQuery = ""
}

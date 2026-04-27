import SwiftUI

struct SettingsControlRow<Content: View>: View {
    @Environment(\.settingsSearchQuery) private var searchQuery
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRowContainer {
            HStack(alignment: .center, spacing: 16) {
                SettingsRowText(title: title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                content
                    .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
            }
        }
        .opacity(searchOpacity)
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
            .padding(.trailing, SettingsLayout.horizontalPadding)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
    }
}

struct SettingsRowText: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.rowPrimary)
            Text(subtitle)
                .font(AppTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            .padding(.leading, SettingsLayout.rowLeadingPadding)
            .padding(.trailing, SettingsLayout.horizontalPadding)
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

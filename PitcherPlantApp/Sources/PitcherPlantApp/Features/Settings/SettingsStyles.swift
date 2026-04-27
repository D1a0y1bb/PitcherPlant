import SwiftUI

struct SettingsStepperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SettingsPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .settingsPillLabel(alignment: .center)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .opacity(isEnabled ? 1 : 0.48)
    }
}

extension View {
    @ViewBuilder
    func settingsPillLabel(width: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        if let width {
            self
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: width, height: SettingsLayout.pathControlHeight, alignment: alignment)
                .settingsControlBackground()
        } else {
            self
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: SettingsLayout.pathControlHeight, alignment: alignment)
                .settingsControlBackground()
        }
    }

    func settingsControlBackground() -> some View {
        self
            .settingsPanelSurface(cornerRadius: SettingsLayout.controlCornerRadius)
    }

    @ViewBuilder
    func settingsPanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay {
                shape.stroke(Color(nsColor: .separatorColor).opacity(0.18))
            }
    }
}

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
                    .controlSize(.small)
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
                .font(.body.weight(.semibold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsStatusPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.64))
            .clipShape(Capsule())
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.42))
            .frame(height: 0.5)
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

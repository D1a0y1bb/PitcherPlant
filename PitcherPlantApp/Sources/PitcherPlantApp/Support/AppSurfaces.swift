import SwiftUI

enum AppLayout {
    static let pagePadding: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let rowMinHeight: CGFloat = 54
    static let controlColumnWidth: CGFloat = 360
}

struct AppPageShell<Content: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, AppLayout.pagePadding)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct AppSectionPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var contentPadding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentPadding)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .groupBoxStyle(.automatic)
    }
}

struct AppToolbarBand<Content: View>: View {
    var glass: Bool = true
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.automatic)
    }
}

struct AppInspectorPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupBoxStyle(.automatic)
    }
}

struct AppTablePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .groupBoxStyle(.automatic)
    }
}

struct AppEmptyPanel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(AppTypography.rowPrimary)
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .padding(18)
        }
        .groupBoxStyle(.automatic)
    }
}

struct AppDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, AppLayout.rowHorizontalPadding)
            .padding(.trailing, AppLayout.rowHorizontalPadding)
    }
}

struct AppControlRow<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var trailingWidth: CGFloat = AppLayout.controlColumnWidth
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.rowPrimary)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            content
                .frame(width: trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, AppLayout.rowVerticalPadding)
        .frame(minHeight: AppLayout.rowMinHeight)
    }
}

struct AppPanelSurfaceModifier: ViewModifier {
    var glass: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if glass, #available(macOS 26.0, *) {
            content
                .glassEffect(.regular)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    private func fallback(content: Content) -> some View {
        GroupBox {
            content
        }
        .groupBoxStyle(.automatic)
    }
}

extension View {
    func appPanelSurface(glass: Bool = false) -> some View {
        modifier(AppPanelSurfaceModifier(glass: glass))
    }
}

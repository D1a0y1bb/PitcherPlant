import SwiftUI

enum AppLayout {
    static let pagePadding: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let rowMinHeight: CGFloat = 54
    static let controlColumnWidth: CGFloat = 360
    static let surfaceCornerRadius: CGFloat = 18
}

struct LiquidGlassSurface<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets()
    var cornerRadius: CGFloat = AppLayout.surfaceCornerRadius
    var isInteractive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                isInteractive ? .regular.interactive() : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

struct AppPageShell<Content: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(.horizontal, AppLayout.pagePadding)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct AppSectionPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var contentPadding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        LiquidGlassSurface(
            padding: EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 10) {
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

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(contentPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppToolbarBand<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    @ViewBuilder var content: Content

    var body: some View {
        LiquidGlassSurface(padding: padding, cornerRadius: 16, isInteractive: true) {
            content
        }
    }
}

struct AppInspectorPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        LiquidGlassSurface(
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        ) {
            VStack(alignment: .leading, spacing: 10) {
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

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppTablePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AppEmptyPanel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(subtitle)
        )
        .frame(maxWidth: .infinity, minHeight: 160)
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

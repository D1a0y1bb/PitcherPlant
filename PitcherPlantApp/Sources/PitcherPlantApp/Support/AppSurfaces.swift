import SwiftUI

enum AppLayout {
    static let mainWindowMinWidth: CGFloat = 820
    static let mainWindowMinHeight: CGFloat = 620
    static let mainWindowChromeHeightReserve: CGFloat = 52
    static let mainWindowContentMinHeight: CGFloat = mainWindowMinHeight - mainWindowChromeHeightReserve
    static let mainWindowDefaultWidth: CGFloat = 1220
    static let mainWindowDefaultHeight: CGFloat = 704
    static let sidebarMinWidth: CGFloat = 230
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 300
    static let sidebarContentTopMargin: CGFloat = 10
    static let sidebarContentBottomMargin: CGFloat = 18
    static let contentMinWidth: CGFloat = 240
    static let contentIdealWidth: CGFloat = 620
    static let inspectorMinWidth: CGFloat = 340
    static let inspectorDefaultWidth: CGFloat = inspectorMinWidth
    static let inspectorIdealWidth: CGFloat = inspectorDefaultWidth
    static let inspectorMaxWidth: CGFloat = 440
    static let sidebarCollapseWidthWithInspector: CGFloat = 1080
    static let sidebarRestoreWidthWithInspector: CGFloat = mainWindowDefaultWidth
    static let sidebarCollapseWidthWithoutInspector: CGFloat = 860
    static let sidebarRestoreWidthWithoutInspector: CGFloat = 1040
    static let workspaceTableMinWidth: CGFloat = 560
    static let evidenceTableMinWidth: CGFloat = 640
    static let evidenceCollectionTableMinWidth: CGFloat = 720
    static let fingerprintTableMinWidth: CGFloat = 840
    static let fingerprintActionsMinWidth: CGFloat = 600
    static let reportListMinHeight: CGFloat = 180
    static let reportListIdealMaxHeight: CGFloat = 420
    static let pagePadding: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let rowMinHeight: CGFloat = 54
    static let controlColumnWidth: CGFloat = 360
    static let surfaceCornerRadius: CGFloat = 18
    static let titlebarScrollContentTopPadding: CGFloat = 76
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

extension View {
    func stableMainWindowFrame() -> some View {
        frame(
            minWidth: AppLayout.mainWindowMinWidth,
            maxWidth: .infinity,
            minHeight: AppLayout.mainWindowContentMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
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
            .padding(.top, AppLayout.titlebarScrollContentTopPadding)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct AppSectionPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var contentPadding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ContentPlainSection(title: title, subtitle: subtitle, contentPadding: contentPadding) {
            content
        }
    }
}

struct ContentPlainSection<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var contentPadding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppToolbarBand<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(controlBandFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 0.75)
            }
    }

    private var controlBandFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.035)
        }
        return Color.black.opacity(0.025)
    }
}

struct InspectorPanelSurface<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(readabilityFill)
            }
            .overlay {
                shape
                    .strokeBorder(Color.primary.opacity(strokeAlpha), lineWidth: 0.75)
            }
    }

    private var readabilityFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.045)
        }
        return Color.black.opacity(0.035)
    }

    private var strokeAlpha: Double {
        colorScheme == .dark ? 0.16 : 0.11
    }

}

enum AppMotion {
    static let toolbarGlassAppear = Animation.smooth(duration: 0.46, extraBounce: 0.08)

    static func enabled(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

struct AppInspectorPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        InspectorPanelSurface {
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

struct AppHorizontalOverflow<Content: View>: View {
    let minWidth: CGFloat
    var showsIndicators = true
    var fitsContentHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        if fitsContentHeight {
            ScrollView(.horizontal, showsIndicators: showsIndicators) {
                content
                    .frame(minWidth: minWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: showsIndicators) {
                    content
                        .frame(width: max(proxy.size.width, minWidth), alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

struct InspectorEmptyState: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        InspectorPanelSurface(
            padding: EdgeInsets(top: 28, leading: 22, bottom: 28, trailing: 22),
            cornerRadius: 18
        ) {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: 300)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

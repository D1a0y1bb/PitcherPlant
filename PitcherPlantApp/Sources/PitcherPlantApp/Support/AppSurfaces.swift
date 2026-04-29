import AppKit
import SwiftUI

enum AppLayout {
    static let mainWindowMinWidth: CGFloat = 820
    static let mainWindowMinHeight: CGFloat = 560
    static let mainWindowChromeHeightReserve: CGFloat = 52
    static let mainWindowContentMinHeight: CGFloat = mainWindowMinHeight - mainWindowChromeHeightReserve
    static let mainWindowDefaultWidth: CGFloat = 1220
    static let mainWindowDefaultHeight: CGFloat = 780
    static let sidebarMinWidth: CGFloat = 230
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 300
    static let contentMinWidth: CGFloat = 240
    static let contentIdealWidth: CGFloat = 620
    static let inspectorMinWidth: CGFloat = 340
    static let inspectorIdealWidth: CGFloat = 380
    static let inspectorMaxWidth: CGFloat = 520
    static let sidebarCollapseWidthWithInspector: CGFloat = 1160
    static let sidebarRestoreWidthWithInspector: CGFloat = 1280
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
            .compositingGroup()
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
            GlassEffectContainer(spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .padding(.horizontal, AppLayout.pagePadding)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollEdgeEffectStyle(.hard, for: .top)
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

struct FloatingToolbarButtonGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .floatingToolbarCapsule()
    }
}

struct FloatingToolbarCluster<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(alignment: .center, spacing: spacing) {
                content
            }
        }
    }
}

struct FloatingToolbarIconButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let isProminent: Bool
    let action: () -> Void
    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            FloatingToolbarIconGlyph(
                systemImage: systemImage,
                role: role,
                isProminent: isProminent,
                isHovering: isHovering
            )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FloatingToolbarMenuButton<Content: View>: View {
    let title: String
    let systemImage: String
    let isProminent: Bool
    @ViewBuilder var content: Content
    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        isProminent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isProminent = isProminent
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            FloatingToolbarIconGlyph(
                systemImage: systemImage,
                role: nil,
                isProminent: isProminent,
                isHovering: isHovering
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct FloatingToolbarSearchField: View {
    @Binding var text: String
    let prompt: String
    var width: CGFloat = 320
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.body)

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear")
            }
        }
        .frame(width: width, height: 36)
        .padding(.horizontal, 11)
        .floatingToolbarCapsule(isFocused: isFocused)
    }
}

private struct FloatingToolbarIconGlyph: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    let role: ButtonRole?
    let isProminent: Bool
    let isHovering: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .frame(width: 29, height: 26)
            .background {
                Capsule()
                    .fill(hoverFill)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.36)
            .animation(.smooth(duration: 0.12), value: isHovering)
    }

    private var hoverFill: Color {
        if role == .destructive {
            return .red.opacity(isProminent ? 0.12 : 0.10)
        }
        return .primary.opacity(isProminent ? 0.11 : 0.09)
    }
}

extension View {
    func floatingToolbarCapsule(isFocused: Bool = false) -> some View {
        background {
            Capsule()
                .fill(Color(nsColor: NSColor.controlBackgroundColor.withAlphaComponent(isFocused ? 0.18 : 0.10)))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: NSColor.separatorColor.withAlphaComponent(isFocused ? 0.26 : 0.14)), lineWidth: 0.75)
        }
        .glassEffect(.clear.interactive(), in: Capsule())
        .compositingGroup()
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

struct AppWindowColumnBackground: View {
    var body: some View {
        Rectangle()
            .fill(.windowBackground)
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
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: showsIndicators) {
                    content
                        .frame(width: max(proxy.size.width, minWidth), alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
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
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(AppTypography.supporting)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
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

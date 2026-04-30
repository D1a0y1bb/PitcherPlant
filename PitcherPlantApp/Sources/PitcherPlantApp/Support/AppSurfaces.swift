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
    static let inspectorIdealWidth: CGFloat = inspectorMinWidth
    static let inspectorMaxWidth: CGFloat = 720
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
    static let floatingToolbarControlHeight: CGFloat = 36
    static let floatingToolbarWindowCornerRadius: CGFloat = 30
    static let floatingToolbarSidebarCornerRadius: CGFloat = 28

    static func floatingToolbarTopPadding(topSafeAreaInset: CGFloat) -> CGFloat {
        guard topSafeAreaInset > floatingToolbarControlHeight else {
            return 4
        }
        return max(4, (topSafeAreaInset - floatingToolbarControlHeight) / 2)
    }

    static func curvedToolbarTrailingPadding(
        base: CGFloat,
        topPadding: CGFloat,
        cornerRadius: CGFloat
    ) -> CGFloat {
        base + ceil(cornerInset(topOffset: topPadding, cornerRadius: cornerRadius))
    }

    private static func cornerInset(topOffset: CGFloat, cornerRadius: CGFloat) -> CGFloat {
        guard cornerRadius > 0, topOffset < cornerRadius else {
            return 0
        }

        let y = min(max(topOffset, 0), cornerRadius)
        let distanceFromCenterY = cornerRadius - y
        let arcReach = sqrt(max(0, cornerRadius * cornerRadius - distanceFromCenterY * distanceFromCenterY))
        return max(0, cornerRadius - arcReach)
    }
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
    var showsCapsule = true
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        if showsCapsule {
            groupContent
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .floatingToolbarCapsule(isHovered: isHovering)
                .onHover { hovering in
                    withAnimation(AppMotion.toolbarGlassHover) {
                        isHovering = hovering
                    }
                }
        } else {
            groupContent
        }
    }

    private var groupContent: some View {
        HStack(spacing: 5) {
            content
        }
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

struct FloatingToolbarFusionCluster<Collapsed: View, Expanded: View>: View {
    var spacing: CGFloat = 10
    var forceExpanded = false
    @ViewBuilder var collapsed: Collapsed
    @ViewBuilder var expanded: Expanded
    @State private var isHovering = false

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassFusion) {
                isHovering = hovering
            }
        }
        .animation(AppMotion.toolbarGlassFusion, value: effectiveExpanded)
    }

    @ViewBuilder
    private var content: some View {
        if effectiveExpanded {
            HStack(alignment: .center, spacing: spacing) {
                expanded
            }
            .transition(.floatingToolbarFusion)
        } else {
            HStack(alignment: .center, spacing: 0) {
                collapsed
            }
            .transition(.floatingToolbarFusion)
        }
    }

    private var effectiveExpanded: Bool {
        isHovering || forceExpanded
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
        .buttonStyle(FloatingToolbarButtonStyle())
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
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
        .buttonStyle(FloatingToolbarButtonStyle())
        .menuIndicator(.hidden)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
    }
}

struct FloatingToolbarTitleSelector: View {
    let title: String
    let subtitle: String
    let accessibilityLabel: String
    @Binding var isPresented: Bool
    @State private var isHovering = false

    init(
        title: String,
        subtitle: String,
        accessibilityLabel: String,
        isPresented: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityLabel = accessibilityLabel
        self._isPresented = isPresented
    }

    var body: some View {
        Button {
            withAnimation(AppMotion.toolbarGlassAppear) {
                isPresented.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isPresented ? 90 : 0))
            }
            .lineLimit(1)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .floatingToolbarCapsule(isFocused: isPresented || isHovering)
            .contentShape(Capsule())
        }
        .buttonStyle(FloatingToolbarButtonStyle())
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
        .animation(AppMotion.toolbarGlassHover, value: isHovering)
        .animation(AppMotion.toolbarGlassAppear, value: isPresented)
    }
}

struct FloatingToolbarPopoverPanel<Content: View>: View {
    var width: CGFloat = 260
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: Content
    @State private var isHovering = false

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: width, alignment: .leading)
                .floatingToolbarRoundedPanel(cornerRadius: cornerRadius, isHovered: isHovering)
                .onHover { hovering in
                    withAnimation(AppMotion.toolbarGlassHover) {
                        isHovering = hovering
                    }
                }
        }
    }
}

struct FloatingToolbarSearchField: View {
    @Binding var text: String
    let prompt: String
    var width: CGFloat = 240
    @Binding var isExpanded: Bool
    var collapsesWhenInactive = false
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    @State private var isExpansionLocked = false
    @State private var isHoverExpansionReady = false
    @State private var hoverExpansionReadyToken = 0
    @State private var expansionLockToken = 0
    @State private var collapseToken = 0

    init(text: Binding<String>, prompt: String, width: CGFloat = 240, isExpanded: Bool = true) {
        self._text = text
        self.prompt = prompt
        self.width = width
        self._isExpanded = .constant(isExpanded)
        self.collapsesWhenInactive = false
    }

    init(
        text: Binding<String>,
        prompt: String,
        width: CGFloat = 240,
        isExpanded: Binding<Bool>,
        collapsesWhenInactive: Bool = true
    ) {
        self._text = text
        self.prompt = prompt
        self.width = width
        self._isExpanded = isExpanded
        self.collapsesWhenInactive = collapsesWhenInactive
    }

    var body: some View {
        HStack(spacing: isExpanded ? 8 : 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if isExpanded {
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(.body)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }

            if isExpanded, text.isEmpty == false {
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
        .frame(width: isExpanded ? width : 36, height: 36)
        .padding(.horizontal, isExpanded ? 11 : 0)
        .floatingToolbarCapsule(isFocused: isFocused)
        .scaleEffect(isFocused ? 1.015 : 1, anchor: .center)
        .contentShape(Capsule())
        .onTapGesture {
            guard collapsesWhenInactive, isExpanded == false else {
                return
            }
            expandSearch()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                isFocused = true
            }
        }
        .onHover { hovering in
            isHovering = hovering
            updateExpansionForInteraction()
        }
        .onAppear {
            prepareHoverExpansionReadiness()
        }
        .onDisappear {
            hoverExpansionReadyToken += 1
            isHoverExpansionReady = false
            isHovering = false
        }
        .onChange(of: isFocused) { _, _ in
            updateExpansionForInteraction()
        }
        .onChange(of: text) { _, _ in
            updateExpansionForInteraction()
        }
        .animation(AppMotion.toolbarGlassHover, value: isFocused)
        .animation(AppMotion.toolbarSearchExpand, value: isExpanded)
    }

    private func updateExpansionForInteraction() {
        guard collapsesWhenInactive else {
            return
        }
        if isFocused || text.isEmpty == false {
            expandSearch()
            return
        }

        if isHovering {
            if isHoverExpansionReady {
                expandSearch()
            }
            return
        }

        scheduleCollapseIfInactive()
    }

    private func prepareHoverExpansionReadiness() {
        guard collapsesWhenInactive else {
            return
        }

        hoverExpansionReadyToken += 1
        let token = hoverExpansionReadyToken
        isHoverExpansionReady = false

        if text.isEmpty == false {
            isHoverExpansionReady = true
            expandSearch()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppMotion.toolbarSearchHoverSettleDelay)
            guard hoverExpansionReadyToken == token else {
                return
            }
            isHoverExpansionReady = true
            updateExpansionForInteraction()
        }
    }

    private func expandSearch() {
        collapseToken += 1
        guard isExpanded == false else {
            return
        }
        withAnimation(AppMotion.toolbarSearchExpand) {
            isExpanded = true
        }
        lockExpansionDuringAnimation()
    }

    private func lockExpansionDuringAnimation() {
        expansionLockToken += 1
        let token = expansionLockToken
        isExpansionLocked = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppMotion.toolbarSearchExpansionLockDelay)
            guard expansionLockToken == token else {
                return
            }
            isExpansionLocked = false
            scheduleCollapseIfInactive()
        }
    }

    private func scheduleCollapseIfInactive() {
        guard isExpansionLocked == false else {
            return
        }

        collapseToken += 1
        let token = collapseToken

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppMotion.toolbarSearchCollapseDelay)
            guard collapseToken == token else {
                return
            }
            guard isHovering == false, isFocused == false, text.isEmpty else {
                return
            }
            withAnimation(AppMotion.toolbarSearchExpand) {
                isExpanded = false
            }
        }
    }
}

struct FloatingToolbarSearchTriggerButton: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            expand()
        } label: {
            FloatingToolbarIconGlyph(
                systemImage: "magnifyingglass",
                role: nil,
                isProminent: false,
                isHovering: isHovering
            )
        }
        .buttonStyle(FloatingToolbarButtonStyle())
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(AppMotion.toolbarGlassHover) {
                isHovering = hovering
            }
        }
    }

    private func expand() {
        guard isExpanded == false else {
            return
        }
        withAnimation(AppMotion.toolbarSearchExpand) {
            isExpanded = true
        }
    }
}

struct FloatingToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
                    .padding(.horizontal, -1)
                    .padding(.vertical, -1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1, anchor: .center)
            .shadow(color: Color.primary.opacity(configuration.isPressed ? 0.10 : 0), radius: 9, y: 0)
            .animation(AppMotion.toolbarGlassPress, value: configuration.isPressed)
    }
}

struct FloatingToolbarPanelButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.965 : 1, anchor: .center)
            .shadow(color: Color.primary.opacity(configuration.isPressed ? 0.08 : 0), radius: 8, y: 0)
            .animation(AppMotion.toolbarGlassPress, value: configuration.isPressed)
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
            .animation(AppMotion.toolbarGlassHover, value: isHovering)
    }

    private var hoverFill: Color {
        if role == .destructive {
            return .red.opacity(isProminent ? 0.12 : 0.10)
        }
        return .primary.opacity(isProminent ? 0.11 : 0.09)
    }
}

extension View {
    func floatingToolbarCapsule(isFocused: Bool = false, isHovered: Bool = false) -> some View {
        background {
            Capsule()
                .fill(Color(nsColor: NSColor.controlBackgroundColor.withAlphaComponent(capsuleFillAlpha(isFocused: isFocused, isHovered: isHovered))))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: NSColor.separatorColor.withAlphaComponent(capsuleStrokeAlpha(isFocused: isFocused, isHovered: isHovered))), lineWidth: 0.75)
        }
        .glassEffect(.clear.interactive(), in: Capsule())
        .compositingGroup()
    }

    func floatingToolbarRoundedPanel(
        cornerRadius: CGFloat,
        isFocused: Bool = false,
        isHovered: Bool = false
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor.withAlphaComponent(capsuleFillAlpha(isFocused: isFocused, isHovered: isHovered))))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: NSColor.separatorColor.withAlphaComponent(capsuleStrokeAlpha(isFocused: isFocused, isHovered: isHovered))), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .compositingGroup()
    }

    private func capsuleFillAlpha(isFocused: Bool, isHovered: Bool) -> CGFloat {
        if isFocused {
            return 0.18
        }
        if isHovered {
            return 0.13
        }
        return 0.07
    }

    private func capsuleStrokeAlpha(isFocused: Bool, isHovered: Bool) -> CGFloat {
        if isFocused {
            return 0.26
        }
        if isHovered {
            return 0.19
        }
        return 0.11
    }
}

enum AppMotion {
    static let toolbarGlassAppear = Animation.smooth(duration: 0.46, extraBounce: 0.08)
    static let toolbarGlassFusion = Animation.smooth(duration: 0.82, extraBounce: 0.22)
    static let toolbarGlassHover = Animation.smooth(duration: 0.22, extraBounce: 0.10)
    static let toolbarGlassPress = Animation.smooth(duration: 0.20, extraBounce: 0.38)
    static let toolbarSearchHoverSettleDelay: UInt64 = 620_000_000
    static let toolbarSearchExpansionLockDelay: UInt64 = 1_250_000_000
    static let toolbarSearchCollapseDelay: UInt64 = 260_000_000
    static let toolbarSearchExpand = Animation.smooth(duration: 1.18, extraBounce: 0.20)
}

extension AnyTransition {
    static var floatingToolbarFusion: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
        )
    }

    static var floatingToolbarSearchPresence: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: FloatingToolbarSearchPresenceModifier(progress: 0),
                identity: FloatingToolbarSearchPresenceModifier(progress: 1)
            ),
            removal: .modifier(
                active: FloatingToolbarSearchPresenceModifier(progress: 0),
                identity: FloatingToolbarSearchPresenceModifier(progress: 1)
            )
        )
    }

    static var floatingToolbarPopoverPresence: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: FloatingToolbarPopoverPresenceModifier(progress: 0),
                identity: FloatingToolbarPopoverPresenceModifier(progress: 1)
            ),
            removal: .modifier(
                active: FloatingToolbarPopoverPresenceModifier(progress: 0),
                identity: FloatingToolbarPopoverPresenceModifier(progress: 1)
            )
        )
    }
}

private struct FloatingToolbarSearchPresenceModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.985 + progress * 0.015, anchor: .trailing)
            .blur(radius: (1 - progress) * 2)
    }
}

private struct FloatingToolbarPopoverPresenceModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + progress * 0.06, anchor: .topLeading)
            .offset(y: (1 - progress) * -8)
            .blur(radius: (1 - progress) * 2.5)
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

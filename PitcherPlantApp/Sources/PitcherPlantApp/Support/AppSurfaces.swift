import AppKit
import SwiftUI

enum AppLayout {
    static let mainWindowMinWidth: CGFloat = 820
    static let mainWindowMinHeight: CGFloat = 560
    static let mainWindowChromeHeightReserve: CGFloat = 52
    static let mainWindowContentMinHeight: CGFloat = mainWindowMinHeight - mainWindowChromeHeightReserve
    static let mainWindowDefaultWidth: CGFloat = 1220
    static let mainWindowDefaultHeight: CGFloat = 704
    static let sidebarMinWidth: CGFloat = 230
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 300
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
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollEdgeEffectStyle(.soft, for: .top)
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

struct InspectorReadableGlassPanel<Content: View>: View {
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
                ZStack {
                    shape
                        .fill(.regularMaterial)
                    shape
                        .fill(readabilityFill)
                }
            }
            .overlay {
                shape
                    .strokeBorder(Color.primary.opacity(strokeAlpha), lineWidth: 0.75)
            }
            .glassEffect(.regular, in: shape)
            .shadow(color: Color.black.opacity(shadowAlpha), radius: 8, y: 4)
    }

    private var readabilityFill: Color {
        if colorScheme == .dark {
            return Color.black.opacity(0.30)
        }
        return Color(nsColor: NSColor.windowBackgroundColor.withAlphaComponent(0.58))
    }

    private var strokeAlpha: Double {
        colorScheme == .dark ? 0.16 : 0.11
    }

    private var shadowAlpha: Double {
        colorScheme == .dark ? 0.14 : 0.045
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
        .onHover { hovering in
            withAnimation(AppMotion.enabled(AppMotion.toolbarGlassFusion, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .animation(AppMotion.enabled(AppMotion.toolbarGlassFusion, reduceMotion: reduceMotion), value: effectiveExpanded)
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

struct SplitTrailingColumnWidthInitializer: NSViewRepresentable {
    var width: CGFloat
    var resetKey: String

    func makeNSView(context: Context) -> SplitTrailingColumnWidthInitializerView {
        let view = SplitTrailingColumnWidthInitializerView()
        view.width = width
        view.resetKey = resetKey
        return view
    }

    func updateNSView(_ nsView: SplitTrailingColumnWidthInitializerView, context: Context) {
        nsView.width = width
        nsView.resetKey = resetKey
        nsView.scheduleApply()
    }
}

@MainActor
final class SplitTrailingColumnWidthInitializerView: NSView {
    var width: CGFloat = AppLayout.inspectorDefaultWidth
    var resetKey = ""
    private var lastAppliedKey = ""
    private var applyScheduled = false
    private var lookupRetryCount = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleApply()
    }

    override func layout() {
        super.layout()
        scheduleApply()
    }

    func scheduleApply() {
        guard applyScheduled == false else {
            return
        }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.applyPreferredWidth()
        }
    }

    private func applyPreferredWidth() {
        guard let splitView = nearestSplitView() else {
            retryLookup()
            return
        }
        guard splitView.arrangedSubviews.count >= 2, splitView.bounds.width > width else {
            retryLookup()
            return
        }
        lookupRetryCount = 0

        let key = "\(resetKey)-\(Int(width.rounded()))-\(Int(splitView.bounds.width.rounded()))"
        guard lastAppliedKey != key else {
            return
        }
        lastAppliedKey = key

        let dividerIndex = max(0, splitView.arrangedSubviews.count - 2)
        let position = max(0, splitView.bounds.width - width - splitView.dividerThickness)
        splitView.setPosition(position, ofDividerAt: dividerIndex)
        splitView.adjustSubviews()
    }

    private func retryLookup() {
        guard lookupRetryCount < 6 else {
            return
        }

        lookupRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.applyPreferredWidth()
        }
    }

    private func nearestSplitView() -> NSSplitView? {
        var candidate = superview
        while let view = candidate {
            if let splitView = view as? NSSplitView {
                return splitView
            }
            candidate = view.superview
        }
        return nil
    }
}

struct FloatingToolbarIconButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let isProminent: Bool
    let symbolRenderingMode: SymbolRenderingMode
    let symbolOffset: CGSize
    let action: () -> Void
    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isProminent: Bool = false,
        symbolRenderingMode: SymbolRenderingMode = .hierarchical,
        symbolOffset: CGSize = .zero,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isProminent = isProminent
        self.symbolRenderingMode = symbolRenderingMode
        self.symbolOffset = symbolOffset
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            FloatingToolbarIconGlyph(
                systemImage: systemImage,
                role: role,
                isProminent: isProminent,
                isHovering: isHovering,
                symbolRenderingMode: symbolRenderingMode,
                symbolOffset: symbolOffset
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
            let animation = isPresented ? AppMotion.toolbarPopoverDismiss : AppMotion.toolbarPopoverPresent
            withAnimation(animation) {
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
        .animation(isPresented ? AppMotion.toolbarPopoverPresent : AppMotion.toolbarPopoverDismiss, value: isPresented)
    }
}

struct FloatingToolbarPopoverPanel<Content: View>: View {
    var width: CGFloat = 260
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: width, alignment: .leading)
                .floatingToolbarRoundedPanel(cornerRadius: cornerRadius, isHovered: isHovering, colorScheme: colorScheme)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(AppMotion.enabled(AppMotion.toolbarGlassHover, reduceMotion: reduceMotion), value: isFocused)
        .animation(AppMotion.enabled(AppMotion.toolbarSearchExpand, reduceMotion: reduceMotion), value: isExpanded)
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
        withAnimation(AppMotion.enabled(AppMotion.toolbarSearchExpand, reduceMotion: reduceMotion)) {
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
            withAnimation(AppMotion.enabled(AppMotion.toolbarSearchExpand, reduceMotion: reduceMotion)) {
                isExpanded = false
            }
        }
    }
}

struct FloatingToolbarSearchTriggerButton: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            withAnimation(AppMotion.enabled(AppMotion.toolbarGlassHover, reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
    }

    private func expand() {
        guard isExpanded == false else {
            return
        }
        withAnimation(AppMotion.enabled(AppMotion.toolbarSearchExpand, reduceMotion: reduceMotion)) {
            isExpanded = true
        }
    }
}

struct FloatingToolbarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(AppMotion.enabled(AppMotion.toolbarGlassPress, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct FloatingToolbarPanelButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.965 : 1, anchor: .center)
            .shadow(color: Color.primary.opacity(configuration.isPressed ? 0.08 : 0), radius: 8, y: 0)
            .animation(AppMotion.enabled(AppMotion.toolbarGlassPress, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct FloatingToolbarIconGlyph: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    let role: ButtonRole?
    let isProminent: Bool
    let isHovering: Bool
    var symbolRenderingMode: SymbolRenderingMode = .hierarchical
    var symbolOffset: CGSize = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(symbolRenderingMode)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .frame(width: 29, height: 26)
            .offset(symbolOffset)
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
        isHovered: Bool = false,
        colorScheme: ColorScheme = .light
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return background {
            ZStack {
                shape
                    .fill(.regularMaterial)
                shape
                    .fill(panelReadabilityFill(colorScheme: colorScheme, isFocused: isFocused, isHovered: isHovered))
            }
        }
        .overlay {
            shape
                .strokeBorder(Color(nsColor: NSColor.separatorColor.withAlphaComponent(panelStrokeAlpha(isFocused: isFocused, isHovered: isHovered))), lineWidth: 0.75)
        }
        .contentShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .shadow(color: Color.black.opacity(panelShadowAlpha(isFocused: isFocused, isHovered: isHovered)), radius: 26, y: 14)
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

    private func panelReadabilityFill(colorScheme: ColorScheme, isFocused: Bool, isHovered: Bool) -> Color {
        if colorScheme == .dark {
            return Color.black.opacity(panelDarkReadabilityFillAlpha(isFocused: isFocused, isHovered: isHovered))
        }
        return Color(nsColor: NSColor.windowBackgroundColor.withAlphaComponent(panelLightReadabilityFillAlpha(isFocused: isFocused, isHovered: isHovered)))
    }

    private func panelLightReadabilityFillAlpha(isFocused: Bool, isHovered: Bool) -> CGFloat {
        if isFocused {
            return 0.82
        }
        if isHovered {
            return 0.78
        }
        return 0.74
    }

    private func panelDarkReadabilityFillAlpha(isFocused: Bool, isHovered: Bool) -> Double {
        if isFocused {
            return 0.54
        }
        if isHovered {
            return 0.50
        }
        return 0.46
    }

    private func panelStrokeAlpha(isFocused: Bool, isHovered: Bool) -> CGFloat {
        if isFocused {
            return 0.36
        }
        if isHovered {
            return 0.31
        }
        return 0.24
    }

    private func panelShadowAlpha(isFocused: Bool, isHovered: Bool) -> Double {
        if isFocused {
            return 0.17
        }
        if isHovered {
            return 0.15
        }
        return 0.13
    }
}

enum AppMotion {
    static let toolbarGlassAppear = Animation.smooth(duration: 0.46, extraBounce: 0.08)
    static let toolbarGlassFusion = Animation.smooth(duration: 0.82, extraBounce: 0.22)
    static let toolbarGlassHover = Animation.smooth(duration: 0.22, extraBounce: 0.10)
    static let toolbarGlassPress = Animation.smooth(duration: 0.20, extraBounce: 0.38)
    static let toolbarPopoverPresent = Animation.smooth(duration: 0.48, extraBounce: 0.10)
    static let toolbarPopoverDismiss = Animation.smooth(duration: 0.50, extraBounce: 0.02)
    static let toolbarSearchHoverSettleDelay: UInt64 = 620_000_000
    static let toolbarSearchExpansionLockDelay: UInt64 = 1_250_000_000
    static let toolbarSearchCollapseDelay: UInt64 = 260_000_000
    static let toolbarSearchExpand = Animation.smooth(duration: 1.18, extraBounce: 0.20)

    static func enabled(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
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
                active: FloatingToolbarPopoverDismissModifier(progress: 0),
                identity: FloatingToolbarPopoverDismissModifier(progress: 1)
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
            .scaleEffect(x: 1, y: 0.94 + progress * 0.06, anchor: .top)
            .offset(y: (1 - progress) * -14)
            .blur(radius: (1 - progress) * 2)
    }
}

private struct FloatingToolbarPopoverDismissModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(
                x: 1,
                y: 0.82 + progress * 0.18,
                anchor: .top
            )
            .offset(y: (1 - progress) * -18)
            .blur(radius: (1 - progress) * 1.4)
    }
}

struct AppInspectorPanel<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        InspectorReadableGlassPanel {
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
        InspectorReadableGlassPanel(
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

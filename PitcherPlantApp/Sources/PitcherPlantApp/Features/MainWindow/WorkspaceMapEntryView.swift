import MapKit
import SwiftUI

private let workspaceMapPanelMaxWidth: CGFloat = 520
private let workspaceMapRouteLineBaseWidth: CGFloat = 2.4

struct WorkspaceMapEntryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var presentationMode: WorkspacePresentationMode
    @Binding var mapStyleMode: WorkspaceMapStyleMode
    @Binding var mapDepthMode: WorkspaceMapDepthMode
    @Namespace private var mapScope
    @State private var planePulse = false

    private let nodes = WorkspaceMapNode.defaultNodes
    private let routes = WorkspaceMapRoute.defaultRoutes

    var body: some View {
        ZStack(alignment: .topLeading) {
            routeMap
                .zIndex(0)

            VStack(alignment: .leading, spacing: 0) {
                headerPanel
                    .frame(maxWidth: workspaceMapPanelMaxWidth, alignment: .leading)
                    .padding(.top, AppLayout.titlebarScrollContentTopPadding)
                    .padding(.horizontal, AppLayout.pagePadding)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                planePulse = true
            }
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .camera(WorkspaceMapNode.camera(for: mapDepthMode)), interactionModes: .all, scope: mapScope) {
            ForEach(routes) { route in
                MapPolyline(coordinates: route.coordinates, contourStyle: .geodesic)
                    .stroke(
                        route.tint.opacity(route.opacity),
                        style: StrokeStyle(lineWidth: route.lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }

            ForEach(nodes) { node in
                Marker(node.localizedTitle(appState), systemImage: node.systemImage, coordinate: node.coordinate)
                    .tint(node.tint)
            }

            ForEach(routes.filter(\.showsPlane)) { route in
                Annotation(route.localizedTitle(appState), coordinate: route.planeCoordinate, anchor: .center) {
                    WorkspaceMapPlaneAnnotation(tint: route.tint, pulse: planePulse)
                }
            }
        }
        .id("\(mapStyleMode.rawValue)-\(mapDepthMode.rawValue)")
        .mapStyle(mapStyleMode.mapStyle(for: mapDepthMode))
        .mapControls {
            MapCompass(scope: mapScope)
            MapZoomStepper(scope: mapScope)
        }
        .accessibilityLabel(appState.t("workspace.map.accessibility"))
    }

    private var headerPanel: some View {
        LiquidGlassSurface(
            padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
            cornerRadius: 20
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(appState.t("workspace.map.eyebrow"), systemImage: "airplane.departure")
                        .font(AppTypography.metadata.weight(.semibold))
                        .foregroundStyle(.blue)

                    Text(appState.t("workspace.map.title"))
                        .font(.title.weight(.semibold))
                        .lineLimit(2)

                    Text(appState.t("workspace.map.subtitle"))
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .opacity(0.62)

                VStack(alignment: .leading, spacing: 8) {
                    WorkspaceMapStatusLine(
                        title: appState.t("workspace.map.currentStatus"),
                        value: latestStatusText,
                        systemImage: latestStatusImage,
                        tint: latestStatusTint
                    )

                    WorkspaceMapStatusLine(
                        title: appState.t("workspace.map.currentRoute"),
                        value: currentRouteText,
                        systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up",
                        tint: .orange
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        appState.importSubmissionPackageWithPanel()
                    } label: {
                        Label(appState.t("audit.importSubmissions"), systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!appState.canImportSubmissionPackage)

                    Button {
                        appState.selectedMainSidebar = .newAudit
                    } label: {
                        Label(appState.t("toolbar.newAudit"), systemImage: "plus")
                    }

                    Button {
                        presentationMode = .dashboard
                    } label: {
                        Label(appState.t("workspace.map.openDashboard"), systemImage: "square.grid.2x2")
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var reportCount: Int {
        max(appState.reportTotalCount, appState.reports.count)
    }

    private var latestJob: AuditJob? {
        appState.jobs.max { lhs, rhs in
            lhs.updatedAt < rhs.updatedAt
        }
    }

    private var latestStatusText: String {
        if appState.isRunningAudit {
            return appState.t("status.auditing")
        }
        guard let latestJob else {
            return appState.t("status.ready")
        }
        return appState.title(for: latestJob.status)
    }

    private var latestStatusImage: String {
        if appState.isRunningAudit {
            return "play.circle"
        }
        return latestJob?.status.systemImage ?? "checkmark.circle"
    }

    private var latestStatusTint: Color {
        if appState.isRunningAudit {
            return .blue
        }
        switch latestJob?.status {
        case .queued:
            return .gray
        case .running:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .orange
        case nil:
            return .green
        }
    }

    private var currentRouteText: String {
        if reportCount == 0 && appState.jobs.isEmpty {
            return appState.t("workspace.map.emptyRoute")
        }
        if let latestJob {
            let directory = URL(fileURLWithPath: latestJob.configuration.directoryPath).lastPathComponent
            return appState.tf("workspace.map.latestRoute", directory)
        }
        return appState.t("workspace.map.reportRoute")
    }
}

struct WorkspaceMapModePanel: View {
    @Environment(AppState.self) private var appState
    @Binding var mapStyleMode: WorkspaceMapStyleMode

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(WorkspaceMapStyleMode.allCases) { style in
                    WorkspaceMapModeTile(
                        title: style.localizedTitle(appState),
                        isSelected: mapStyleMode == style
                    ) {
                        mapStyleMode = style
                    } preview: {
                        WorkspaceMapModePreview(style: style)
                    }
                }
            }

            WorkspaceMapProviderFooter()
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(width: 380)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

enum WorkspaceMapStyleMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case explore
    case driving
    case hybrid
    case satellite

    var id: String { rawValue }

    @MainActor
    func localizedTitle(_ appState: AppState) -> String {
        switch self {
        case .explore:
            return appState.t("workspace.map.style.explore")
        case .driving:
            return appState.t("workspace.map.style.driving")
        case .satellite:
            return appState.t("workspace.map.style.satellite")
        case .hybrid:
            return appState.t("workspace.map.style.hybrid")
        }
    }

    func mapStyle(for depthMode: WorkspaceMapDepthMode) -> MapStyle {
        switch self {
        case .explore:
            return .standard(
                elevation: depthMode.elevation,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        case .driving:
            return .standard(
                elevation: depthMode.elevation,
                emphasis: .automatic,
                pointsOfInterest: .excludingAll,
                showsTraffic: true
            )
        case .satellite:
            return .imagery(elevation: depthMode.elevation)
        case .hybrid:
            return .hybrid(
                elevation: depthMode.elevation,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        }
    }
}

enum WorkspaceMapDepthMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case twoD
    case threeD

    var id: String { rawValue }

    var elevation: MapStyle.Elevation {
        switch self {
        case .twoD:
            return .flat
        case .threeD:
            return .realistic
        }
    }

    var pitch: Double {
        switch self {
        case .twoD:
            return 0
        case .threeD:
            return 55
        }
    }

    @MainActor
    func localizedTitle(_ appState: AppState) -> String {
        switch self {
        case .twoD:
            return appState.t("workspace.map.depth.2d")
        case .threeD:
            return appState.t("workspace.map.depth.3d")
        }
    }

    mutating func toggle() {
        switch self {
        case .twoD:
            self = .threeD
        case .threeD:
            self = .twoD
        }
    }
}

struct WorkspaceMapModeTile<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(width: 72, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.blue : Color.white.opacity(0.42), lineWidth: isSelected ? 2.5 : 1)
                    }
                    .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceMapModePreview: View {
    let style: WorkspaceMapStyleMode

    var body: some View {
        Map(initialPosition: .region(previewRegion), interactionModes: [])
            .mapStyle(style.previewMapStyle)
            .allowsHitTesting(false)
            .overlay(alignment: .center) {
                if style == .driving {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.yellow, .black.opacity(0.72))
                        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                }
            }
    }

    private var previewRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.075)
        )
    }
}

private struct WorkspaceMapProviderFooter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            Label {
                Text(appState.t("workspace.map.providerLine"))
            } icon: {
                Image(systemName: "map.fill")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }
}

private extension WorkspaceMapStyleMode {
    var previewMapStyle: MapStyle {
        switch self {
        case .explore:
            return .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .driving:
            return .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll, showsTraffic: true)
        case .hybrid:
            return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true)
        case .satellite:
            return .imagery(elevation: .flat)
        }
    }
}

private struct WorkspaceMapNode: Identifiable {
    let id: String
    let titleKey: String
    let coordinate: CLLocationCoordinate2D
    let systemImage: String
    let tint: Color

    @MainActor
    func localizedTitle(_ appState: AppState) -> String {
        appState.t(titleKey)
    }

    static let hub = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    static let report = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    static let evidence = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    static let review = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
    static let fingerprint = CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198)

    @MainActor
    static func camera(for depthMode: WorkspaceMapDepthMode) -> MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 23.8, longitude: 122.8),
            distance: 5_700_000,
            heading: 40,
            pitch: depthMode.pitch
        )
    }

    static let defaultNodes: [WorkspaceMapNode] = [
        WorkspaceMapNode(id: "hub", titleKey: "workspace.map.node.workspace", coordinate: hub, systemImage: "folder", tint: .green),
        WorkspaceMapNode(id: "report", titleKey: "workspace.map.node.reports", coordinate: report, systemImage: "doc.text.magnifyingglass", tint: .indigo),
        WorkspaceMapNode(id: "evidence", titleKey: "workspace.map.node.evidence", coordinate: evidence, systemImage: "checklist.checked", tint: .orange),
        WorkspaceMapNode(id: "review", titleKey: "workspace.map.node.review", coordinate: review, systemImage: "checkmark.seal", tint: .pink),
        WorkspaceMapNode(id: "fingerprint", titleKey: "workspace.map.node.fingerprints", coordinate: fingerprint, systemImage: "number", tint: .cyan)
    ]
}

private struct WorkspaceMapRoute: Identifiable {
    let id: String
    let titleKey: String
    let coordinates: [CLLocationCoordinate2D]
    let planeCoordinate: CLLocationCoordinate2D
    let tint: Color
    let lineWidth: CGFloat
    let opacity: Double
    let showsPlane: Bool

    @MainActor
    func localizedTitle(_ appState: AppState) -> String {
        appState.t(titleKey)
    }

    static let defaultRoutes: [WorkspaceMapRoute] = [
        WorkspaceMapRoute(
            id: "reports",
            titleKey: "workspace.map.route.reports",
            coordinates: [WorkspaceMapNode.hub, WorkspaceMapNode.report],
            planeCoordinate: CLLocationCoordinate2D(latitude: 34.2, longitude: 134.4),
            tint: .indigo,
            lineWidth: workspaceMapRouteLineBaseWidth + 1.4,
            opacity: 0.76,
            showsPlane: true
        ),
        WorkspaceMapRoute(
            id: "evidence",
            titleKey: "workspace.map.route.evidence",
            coordinates: [WorkspaceMapNode.hub, WorkspaceMapNode.evidence],
            planeCoordinate: CLLocationCoordinate2D(latitude: 35.2, longitude: 124.8),
            tint: .orange,
            lineWidth: workspaceMapRouteLineBaseWidth + 0.8,
            opacity: 0.68,
            showsPlane: true
        ),
        WorkspaceMapRoute(
            id: "review",
            titleKey: "workspace.map.route.review",
            coordinates: [WorkspaceMapNode.hub, WorkspaceMapNode.review],
            planeCoordinate: CLLocationCoordinate2D(latitude: 25.6, longitude: 116.5),
            tint: .pink,
            lineWidth: workspaceMapRouteLineBaseWidth,
            opacity: 0.62,
            showsPlane: true
        ),
        WorkspaceMapRoute(
            id: "fingerprints",
            titleKey: "workspace.map.route.fingerprints",
            coordinates: [WorkspaceMapNode.hub, WorkspaceMapNode.fingerprint],
            planeCoordinate: CLLocationCoordinate2D(latitude: 11.8, longitude: 108.9),
            tint: .cyan,
            lineWidth: workspaceMapRouteLineBaseWidth,
            opacity: 0.58,
            showsPlane: true
        )
    ]
}

private struct WorkspaceMapPlaneAnnotation: View {
    let tint: Color
    let pulse: Bool

    var body: some View {
        Image(systemName: "airplane")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(tint)
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            .scaleEffect(pulse ? 1.12 : 0.94)
            .accessibilityHidden(true)
    }
}

private struct WorkspaceMapStatusLine: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(AppTypography.rowPrimary)
                .foregroundStyle(tint)
                .frame(width: 22, alignment: .leading)

            Text(title)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(AppTypography.metadata.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

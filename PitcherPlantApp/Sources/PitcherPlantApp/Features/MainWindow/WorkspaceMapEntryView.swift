import MapKit
import SwiftUI

struct WorkspaceMapEntryView: View {
    @Environment(AppState.self) private var appState
    @Binding var mapStyleMode: WorkspaceMapStyleMode
    @Binding var mapDepthMode: WorkspaceMapDepthMode
    @Namespace private var mapScope

    var body: some View {
        routeMap
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
    }

    private var routeMap: some View {
        Map(initialPosition: .camera(WorkspaceMapCamera.camera(for: mapDepthMode)), interactionModes: .all, scope: mapScope)
            .id("\(mapStyleMode.rawValue)-\(mapDepthMode.rawValue)")
            .mapStyle(mapStyleMode.mapStyle(for: mapDepthMode))
            .mapControls {
                MapCompass(scope: mapScope)
                MapZoomStepper(scope: mapScope)
            }
            .accessibilityLabel(appState.t("workspace.map.accessibility"))
    }
}

private enum WorkspaceMapCamera {
    @MainActor
    static func camera(for depthMode: WorkspaceMapDepthMode) -> MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 23.8, longitude: 122.8),
            distance: 5_700_000,
            heading: 40,
            pitch: depthMode.pitch
        )
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

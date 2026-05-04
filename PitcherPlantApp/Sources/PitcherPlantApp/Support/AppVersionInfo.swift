import Foundation

struct AppVersionInfo: Equatable {
    let name: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let releaseTag: String?
    let minimumSystemVersion: String
    let copyright: String
    let sourceRepositoryURL: URL?
    let releasesURL: URL?
    let updateCheckURL: URL?

    static var current: AppVersionInfo {
        AppVersionInfo(bundle: .main)
    }

    var displayVersion: String {
        releaseTag.map(Self.displayReleaseTag) ?? version
    }

    var versionAndBuild: String {
        guard !build.isEmpty, build != "Unknown" else {
            return displayVersion
        }
        return "\(displayVersion) (\(build))"
    }

    var comparableVersion: String {
        releaseTag ?? version
    }

    init(bundle: Bundle) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    init(infoDictionary: [String: Any], bundleIdentifier: String?) {
        name = Self.firstString(
            for: ["CFBundleDisplayName", "CFBundleName"],
            in: infoDictionary
        ) ?? "PitcherPlant"
        version = Self.firstString(
            for: ["CFBundleShortVersionString", "CFBundleVersion"],
            in: infoDictionary
        ) ?? "Unknown"
        build = Self.firstString(for: ["CFBundleVersion"], in: infoDictionary) ?? "Unknown"
        self.bundleIdentifier = bundleIdentifier ?? "Unknown"
        releaseTag = Self.firstString(for: ["PPReleaseTag"], in: infoDictionary)
        minimumSystemVersion = Self.firstString(for: ["LSMinimumSystemVersion"], in: infoDictionary) ?? "Unknown"
        copyright = Self.firstString(for: ["NSHumanReadableCopyright"], in: infoDictionary) ?? ""
        sourceRepositoryURL = Self.firstURL(for: ["PPSourceRepositoryURL"], in: infoDictionary)
        releasesURL = Self.firstURL(for: ["PPReleasesURL"], in: infoDictionary)
        updateCheckURL = Self.firstURL(for: ["PPUpdateCheckURL"], in: infoDictionary)
    }

    private static func firstString(for keys: [String], in infoDictionary: [String: Any]) -> String? {
        keys.compactMap { key in
            let value = infoDictionary[key] as? String
            return value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first { !$0.isEmpty && !Self.isUnresolvedBuildSetting($0) }
    }

    private static func firstURL(for keys: [String], in infoDictionary: [String: Any]) -> URL? {
        firstString(for: keys, in: infoDictionary)
            .flatMap(URL.init(string:))
    }

    private static func displayReleaseTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private static func isUnresolvedBuildSetting(_ value: String) -> Bool {
        value.hasPrefix("$(") && value.hasSuffix(")")
    }
}

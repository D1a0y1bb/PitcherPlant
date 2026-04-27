import Foundation

struct AppVersionInfo: Equatable {
    let name: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let releaseTag: String?

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
    }

    private static func firstString(for keys: [String], in infoDictionary: [String: Any]) -> String? {
        keys.compactMap { key in
            let value = infoDictionary[key] as? String
            return value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first { !$0.isEmpty }
    }

    private static func displayReleaseTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}

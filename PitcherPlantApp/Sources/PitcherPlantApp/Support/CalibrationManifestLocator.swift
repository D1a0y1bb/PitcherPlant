import Foundation

enum CalibrationManifestLocator {
    private static let resourcePath = "Calibration/manifest.json"
    // App resources use `Calibration`; test fixtures intentionally use lowercase
    // `calibration`, so both source-tree locations are listed explicitly.
    private static let sourceCandidates = [
        "PitcherPlantApp/Resources/Calibration/manifest.json",
        "Resources/Calibration/manifest.json",
        "PitcherPlantApp/Tests/PitcherPlantAppTests/Fixtures/calibration/manifest.json",
        "Tests/PitcherPlantAppTests/Fixtures/calibration/manifest.json",
    ]

    static func manifestURL(
        workspaceRoot: URL,
        fileManager: FileManager = .default,
        bundles: [Bundle] = runtimeBundles()
    ) -> URL? {
        bundledManifestURL(in: bundles, fileManager: fileManager)
            ?? sourceTreeManifestURL(workspaceRoot: workspaceRoot, fileManager: fileManager)
    }

    private static func bundledManifestURL(in bundles: [Bundle], fileManager: FileManager) -> URL? {
        for bundle in uniqueBundles(bundles) {
            if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "Calibration") {
                return validatedManifestURL(url, fileManager: fileManager)
            }
            if let url = bundle.url(forResource: "manifest", withExtension: "json") {
                return validatedManifestURL(url, fileManager: fileManager)
            }
            if let resourceURL = bundle.resourceURL {
                let direct = resourceURL.appendingPathComponent(resourcePath)
                if let direct = validatedManifestURL(direct, fileManager: fileManager) {
                    return direct
                }
                let flattened = resourceURL.appendingPathComponent("manifest.json")
                if let flattened = validatedManifestURL(flattened, fileManager: fileManager) {
                    return flattened
                }
            }
        }
        return nil
    }

    private static func sourceTreeManifestURL(workspaceRoot: URL, fileManager: FileManager) -> URL? {
        sourceCandidates
            .map { workspaceRoot.appendingPathComponent($0) }
            .first { validatedManifestURL($0, fileManager: fileManager) != nil }
    }

    private static func runtimeBundles() -> [Bundle] {
        [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
    }

    private static func uniqueBundles(_ bundles: [Bundle]) -> [Bundle] {
        var seen = Set<String>()
        return bundles.filter { bundle in
            let key = bundle.bundleURL.path
            return seen.insert(key).inserted
        }
    }

    private static func validatedManifestURL(_ url: URL, fileManager: FileManager) -> URL? {
        guard fileManager.fileExists(atPath: url.path),
              isCalibrationManifest(at: url) else {
            return nil
        }
        return url
    }

    private static func isCalibrationManifest(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["version"] is Int,
              let cases = root["cases"] as? [[String: Any]],
              !cases.isEmpty else {
            return false
        }
        return cases.allSatisfy { entry in
            entry["id"] is String && entry["kind"] is String
        }
    }
}

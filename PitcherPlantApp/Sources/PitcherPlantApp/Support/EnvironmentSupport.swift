import Foundation

struct ProjectLocator {
    func workspaceRoot() -> URL {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<8 {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("PitcherPlant.py").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }
}

enum AppPreferences {
    private static let prefix = "pitcherplant.macos"

    static func loadDraftConfiguration(for root: URL) -> AuditConfiguration {
        let defaults = UserDefaults.standard
        let key = "\(prefix).draft.\(root.path)"
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AuditConfiguration.self, from: data) else {
            return AuditConfiguration.defaults(for: root)
        }
        return config
    }

    static func saveDraftConfiguration(_ configuration: AuditConfiguration, for root: URL) {
        let defaults = UserDefaults.standard
        let key = "\(prefix).draft.\(root.path)"
        let data = try? JSONEncoder().encode(configuration)
        defaults.set(data, forKey: key)
    }
}

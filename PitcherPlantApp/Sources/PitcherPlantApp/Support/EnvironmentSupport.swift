import Foundation

struct ProjectLocator {
    func workspaceRoot() -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let explicitRoot = environment["PITCHERPLANT_WORKSPACE_ROOT"], explicitRoot.isEmpty == false {
            let url = URL(fileURLWithPath: explicitRoot)
            if isWorkspaceRoot(url, fileManager: fileManager) {
                return url
            }
        }

        let startingPoints = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for start in startingPoints {
            if let root = searchUpward(from: start, fileManager: fileManager) {
                return root
            }
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    private func searchUpward(from start: URL, fileManager: FileManager) -> URL? {
        var candidate = start.standardizedFileURL
        for _ in 0..<16 {
            if isWorkspaceRoot(candidate, fileManager: fileManager) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate {
                break
            }
            candidate = parent
        }
        return nil
    }

    private func isWorkspaceRoot(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.appendingPathComponent("PitcherPlant.py").path) {
            return true
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("PitcherPlantApp/Package.swift").path) {
            return true
        }
        return fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("Sources/PitcherPlantApp").path)
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

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
        var resolvedRoot: URL?
        for _ in 0..<16 {
            if isWorkspaceRoot(candidate, fileManager: fileManager) {
                resolvedRoot = candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate {
                break
            }
            candidate = parent
        }
        return resolvedRoot
    }

    private func isWorkspaceRoot(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.appendingPathComponent("PitcherPlantApp/Package.swift").path) {
            return true
        }
        return fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("Sources/PitcherPlantApp").path)
    }
}

enum AppPreferences {
    private static let prefix = "pitcherplant.macos"

    static func loadDraftConfiguration(for root: URL, defaults: UserDefaults = .standard) -> AuditConfiguration {
        let key = "\(prefix).draft.\(root.path)"
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AuditConfiguration.self, from: data) else {
            return AuditConfiguration.defaults(for: root)
        }
        return config
    }

    static func saveDraftConfiguration(_ configuration: AuditConfiguration, for root: URL, defaults: UserDefaults = .standard) {
        let key = "\(prefix).draft.\(root.path)"
        let data = try? JSONEncoder().encode(configuration)
        defaults.set(data, forKey: key)
    }

    static func loadPresets(for root: URL, defaults: UserDefaults = .standard) -> [AuditConfigurationPreset] {
        let key = "\(prefix).presets.\(root.path)"
        guard let data = defaults.data(forKey: key),
              let presets = try? JSONDecoder().decode([AuditConfigurationPreset].self, from: data) else {
            return []
        }
        return presets.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    @discardableResult
    static func savePreset(
        named name: String,
        configuration: AuditConfiguration,
        for root: URL,
        defaults: UserDefaults = .standard
    ) -> [AuditConfigurationPreset] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return loadPresets(for: root, defaults: defaults)
        }

        var presets = loadPresets(for: root, defaults: defaults)
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index].configuration = configuration
            presets[index].updatedAt = .now
        } else {
            presets.append(AuditConfigurationPreset(name: trimmed, configuration: configuration))
        }
        return storePresets(presets, for: root, defaults: defaults)
    }

    @discardableResult
    static func deletePreset(
        id: UUID,
        for root: URL,
        defaults: UserDefaults = .standard
    ) -> [AuditConfigurationPreset] {
        let presets = loadPresets(for: root, defaults: defaults).filter { $0.id != id }
        return storePresets(presets, for: root, defaults: defaults)
    }

    @discardableResult
    private static func storePresets(
        _ presets: [AuditConfigurationPreset],
        for root: URL,
        defaults: UserDefaults
    ) -> [AuditConfigurationPreset] {
        let sorted = presets.sorted(by: { $0.updatedAt > $1.updatedAt })
        let key = "\(prefix).presets.\(root.path)"
        let data = try? JSONEncoder().encode(sorted)
        defaults.set(data, forKey: key)
        return sorted
    }
}

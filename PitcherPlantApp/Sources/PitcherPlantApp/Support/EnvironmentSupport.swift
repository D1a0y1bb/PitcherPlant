import Foundation

struct ProjectLocator {
    private let savedWorkspaceRootKey = "pitcherplant.macos.workspaceRoot"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func workspaceRoot() -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let explicitRoot = environment["PITCHERPLANT_WORKSPACE_ROOT"], explicitRoot.isEmpty == false {
            let url = URL(fileURLWithPath: explicitRoot)
            if isWorkspaceRoot(url, fileManager: fileManager) || isUsableWorkspace(url, fileManager: fileManager) {
                prepareUserWorkspace(url, fileManager: fileManager)
                saveWorkspaceRoot(url)
                return url
            }
        }

        if let savedRoot = defaults.string(forKey: savedWorkspaceRootKey), savedRoot.isEmpty == false {
            let url = URL(fileURLWithPath: savedRoot)
            if isUsableWorkspace(url, fileManager: fileManager) {
                prepareUserWorkspace(url, fileManager: fileManager)
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
                saveWorkspaceRoot(root)
                return root
            }
        }

        let fallback = applicationSupportWorkspace(fileManager: fileManager)
        prepareUserWorkspace(fallback, fileManager: fileManager)
        saveWorkspaceRoot(fallback)
        return fallback
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

    private func isUsableWorkspace(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func applicationSupportWorkspace(fileManager: FileManager) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        return support
            .appendingPathComponent("PitcherPlant", isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    private func prepareUserWorkspace(_ url: URL, fileManager: FileManager) {
        let directories = [
            url,
            AuditConfiguration.defaultInputDirectory(for: url),
            AuditConfiguration.defaultOutputDirectory(for: url)
        ]
        for directory in directories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func saveWorkspaceRoot(_ url: URL) {
        defaults.set(url.path, forKey: savedWorkspaceRootKey)
    }
}

enum AppPreferences {
    private static let prefix = "pitcherplant.macos"

    static func loadAppSettings(defaults: UserDefaults = .standard) -> AppSettings {
        let key = "\(prefix).appSettings"
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    static func saveAppSettings(_ settings: AppSettings, defaults: UserDefaults = .standard) {
        let key = "\(prefix).appSettings"
        let data = try? JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }

    static func loadWhitelistSuggestionStatuses(defaults: UserDefaults = .standard) -> [UUID: WhitelistSuggestionStatus] {
        let key = "\(prefix).whitelistSuggestionStatuses"
        guard let data = defaults.data(forKey: key),
              let statuses = try? JSONDecoder().decode([String: WhitelistSuggestionStatus].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: statuses.compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, value)
        })
    }

    static func saveWhitelistSuggestionStatuses(_ statuses: [UUID: WhitelistSuggestionStatus], defaults: UserDefaults = .standard) {
        let key = "\(prefix).whitelistSuggestionStatuses"
        let payload = Dictionary(uniqueKeysWithValues: statuses.map { ($0.key.uuidString, $0.value) })
        let data = try? JSONEncoder().encode(payload)
        defaults.set(data, forKey: key)
    }

    static func loadWhitelistSuggestions(defaults: UserDefaults = .standard) -> [WhitelistSuggestion] {
        let key = "\(prefix).whitelistSuggestions"
        guard let data = defaults.data(forKey: key),
              let suggestions = try? JSONDecoder().decode([WhitelistSuggestion].self, from: data) else {
            return []
        }
        let statuses = loadWhitelistSuggestionStatuses(defaults: defaults)
        return suggestions.map { suggestion in
            var copy = suggestion
            if let status = statuses[suggestion.id] {
                copy.status = status
            }
            return copy
        }
    }

    static func saveWhitelistSuggestions(_ suggestions: [WhitelistSuggestion], defaults: UserDefaults = .standard) {
        let key = "\(prefix).whitelistSuggestions"
        let data = try? JSONEncoder().encode(suggestions)
        defaults.set(data, forKey: key)
    }

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

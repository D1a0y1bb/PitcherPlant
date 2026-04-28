import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func configurationDefaultsBuildPaths() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant")
    let defaults = AuditConfiguration.defaults(for: root)
    #expect(defaults.directoryPath.contains("/tmp/pitcherplant/WriteupSamples"))
    #expect(defaults.outputDirectoryPath.contains("/tmp/pitcherplant/GeneratedReports/full"))
}

@Test
func projectLocatorUsesSavedWorkspaceAndCreatesDefaultDirectories() throws {
    let suiteName = "pitcherplant.locator.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-workspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defaults.set(root.path, forKey: "pitcherplant.macos.workspaceRoot")

    let resolved = ProjectLocator(defaults: defaults).workspaceRoot()

    #expect(resolved.path == root.path)
    #expect(FileManager.default.fileExists(atPath: AuditConfiguration.defaultInputDirectory(for: root).path))
    #expect(FileManager.default.fileExists(atPath: AuditConfiguration.defaultOutputDirectory(for: root).path))
}

@Test
func projectLocatorRejectsFilesystemRootSavedWorkspace() throws {
    let suiteName = "pitcherplant.locator.root.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.set("/", forKey: "pitcherplant.macos.workspaceRoot")

    let resolved = ProjectLocator(defaults: defaults).workspaceRoot()

    #expect(resolved.path != "/")
    #expect(AuditConfiguration.defaultInputDirectory(for: resolved).path != "/Fixtures/WriteupSamples/date")
    #expect(defaults.string(forKey: "pitcherplant.macos.workspaceRoot") == resolved.path)
}

@Test
func appVersionInfoReadsBundleMetadata() {
    let version = AppVersionInfo(
        infoDictionary: [
            "CFBundleDisplayName": "PitcherPlant",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "12",
            "PPReleaseTag": "v0.1.0-rc.5"
        ],
        bundleIdentifier: "com.pitcherplant.desktop"
    )

    #expect(version.name == "PitcherPlant")
    #expect(version.version == "0.1.0")
    #expect(version.build == "12")
    #expect(version.bundleIdentifier == "com.pitcherplant.desktop")
    #expect(version.releaseTag == "v0.1.0-rc.5")
    #expect(version.displayVersion == "0.1.0-rc.5")
    #expect(version.versionAndBuild == "0.1.0-rc.5 (12)")
}

@Test
func presetStorageRoundTripsByWorkspaceRoot() throws {
    let suiteName = "pitcherplant.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-presets")
    let configuration = AuditConfiguration.defaults(for: root)

    let saved = AppPreferences.savePreset(named: "常用目录", configuration: configuration, for: root, defaults: defaults)
    #expect(saved.count == 1)
    #expect(saved.first?.name == "常用目录")

    let loaded = AppPreferences.loadPresets(for: root, defaults: defaults)
    #expect(loaded.count == 1)
    #expect(loaded.first?.configuration == configuration)

    let remaining = AppPreferences.deletePreset(id: try #require(loaded.first?.id), for: root, defaults: defaults)
    #expect(remaining.isEmpty)
}

@Test
func appSettingsRoundTripPreservesEnumSelections() throws {
    let suiteName = "pitcherplant.tests.settings.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }

    let settings = AppSettings(
        language: .english,
        appearance: .dark,
        showInspectorByDefault: false,
        compactRows: false,
        showMenuBarExtra: true,
        preferInAppReports: false,
        defaultExportFormat: .pdf,
        showAttachmentPreviews: true
    )
    AppPreferences.saveAppSettings(settings, defaults: defaults)

    let loaded = AppPreferences.loadAppSettings(defaults: defaults)
    #expect(loaded == settings)
}

@Test
func systemAppearanceLeavesColorSchemeUnspecified() {
    #expect(AppAppearance.system.colorScheme == nil)
}

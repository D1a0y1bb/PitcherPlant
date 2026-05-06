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
func toolbarScanModesWriteRealAuditConfiguration() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant")
    var configuration = AuditConfiguration.defaults(for: root)

    configuration.applyToolbarScanMode(.quick)

    #expect(configuration.textThreshold > AuditConfiguration.standardTextThreshold)
    #expect(configuration.dedupThreshold > AuditConfiguration.standardDedupThreshold)
    #expect(configuration.imageThreshold < AuditConfiguration.standardImageThreshold)
    #expect(configuration.simhashThreshold < AuditConfiguration.standardSimhashThreshold)
    #expect(configuration.useVisionOCR == false)

    configuration.applyToolbarTemplate(.evidenceReview)
    #expect(configuration.reportNameTemplate.contains("EvidenceReview"))
    #expect(configuration.useVisionOCR == true)
    #expect(configuration.imageThreshold > AuditConfiguration.standardImageThreshold)

    configuration.setToolbarTemporaryScanEnabled(true)
    #expect(configuration.toolbarTemporaryScanEnabled == true)
    #expect(configuration.reportNameTemplate.hasPrefix("temporary_"))

    configuration.setToolbarTemporaryScanEnabled(false)
    #expect(configuration.toolbarTemporaryScanEnabled == false)
    #expect(configuration.reportNameTemplate.hasPrefix("temporary_") == false)
}

@Test
func releaseWorkflowPublishesAdHocArtifactsWhenSigningSecretsAreMissing() throws {
    let root = try testRepositoryRoot()
    let workflow = try String(
        contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
        encoding: .utf8
    )

    #expect(workflow.contains("SIGNING_SECRETS_AVAILABLE=\"false\""))
    #expect(workflow.contains("DISTRIBUTION=\"ad-hoc\""))
    #expect(workflow.contains("fetch-depth: 0"))
    #expect(workflow.contains("bundle_marketing_version=$BUNDLE_MARKETING_VERSION"))
    #expect(workflow.contains("RC_BUILD_NUMBER="))
    #expect(workflow.contains("bundle_build_number=$BUNDLE_BUILD_NUMBER"))
    #expect(workflow.contains("MARKETING_VERSION=\"${{ steps.release.outputs.bundle_marketing_version }}\""))
    #expect(workflow.contains("CURRENT_PROJECT_VERSION=\"${{ steps.release.outputs.bundle_build_number }}\""))
    #expect(workflow.contains("RELEASE_BUILD_NUMBER: ${{ steps.release.outputs.bundle_build_number }}"))
    #expect(workflow.contains("SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}"))
    #expect(workflow.contains("Missing required secret: SPARKLE_ED_PRIVATE_KEY"))
    #expect(workflow.contains("gh release create"))
    #expect(workflow.contains("./script/package_release.sh --distribution developer-id --notarize"))
    #expect(workflow.contains("./script/package_release.sh --distribution ad-hoc"))
    #expect(workflow.contains("Publishing a GitHub Release requires developer-id distribution.") == false)
}

@Test
func calibrationManifestLocatorFindsPackagedAppResource() throws {
    let root = try testRepositoryRoot()
    let manifestURL = try #require(CalibrationManifestLocator.manifestURL(workspaceRoot: root, bundles: []))

    #expect(manifestURL.path.hasSuffix("PitcherPlantApp/Resources/Calibration/manifest.json"))

    let result = try CalibrationService(manifestURL: manifestURL)
        .evaluate(configuration: AuditConfiguration.defaults(for: root))
    #expect(result.summary.sampleCount > 0)
}

@Test
func calibrationManifestLocatorFindsFlatXcodeBundleResource() throws {
    let root = try testRepositoryRoot()
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-calibration-bundle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let bundleRoot = temporaryRoot.appendingPathComponent("PitcherPlantMock.bundle", isDirectory: true)
    let resources = bundleRoot.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.pitcherplant.tests.bundle</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
    """.write(to: bundleRoot.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

    try FileManager.default.copyItem(
        at: root.appendingPathComponent("PitcherPlantApp/Resources/Calibration/manifest.json"),
        to: resources.appendingPathComponent("manifest.json")
    )
    let bundle = try #require(Bundle(url: bundleRoot))
    let manifestURL = try #require(CalibrationManifestLocator.manifestURL(workspaceRoot: temporaryRoot, bundles: [bundle]))

    #expect(manifestURL.path.hasSuffix("Contents/Resources/manifest.json"))
}

@Test
func projectLocatorUsesSavedWorkspaceAndCreatesDefaultDirectories() throws {
    let suiteName = "pitcherplant.locator.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { clearTestDefaults(suiteName, defaults: defaults) }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-workspace-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
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
    defer { clearTestDefaults(suiteName, defaults: defaults) }
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
            "PPReleaseTag": "v0.1.0-rc.5",
            "LSMinimumSystemVersion": "26.0",
            "NSHumanReadableCopyright": "Copyright 2026",
            "PPSourceRepositoryURL": "https://github.com/D1a0y1bb/PitcherPlant",
            "PPReleasesURL": "https://github.com/D1a0y1bb/PitcherPlant/releases",
            "PPUpdateCheckURL": "https://github.com/D1a0y1bb/PitcherPlant/releases/latest/download/appcast.xml?cachebust=1"
        ],
        bundleIdentifier: "com.pitcherplant.desktop"
    )

    #expect(version.name == "PitcherPlant")
    #expect(version.version == "0.1.0")
    #expect(version.build == "12")
    #expect(version.bundleIdentifier == "com.pitcherplant.desktop")
    #expect(version.releaseTag == "v0.1.0-rc.5")
    #expect(version.displayVersion == "0.1.0-rc.5")
    #expect(version.versionAndBuild == "0.1.0-rc.5")
    #expect(version.comparableVersion == "v0.1.0-rc.5")
    #expect(version.minimumSystemVersion == "26.0")
    #expect(version.copyright == "Copyright 2026")
    #expect(version.sourceRepositoryURL?.absoluteString == "https://github.com/D1a0y1bb/PitcherPlant")
    #expect(version.releasesURL?.absoluteString == "https://github.com/D1a0y1bb/PitcherPlant/releases")
    #expect(version.updateCheckURL?.absoluteString == "https://github.com/D1a0y1bb/PitcherPlant/releases/latest/download/appcast.xml?cachebust=1")
}

@Test
func appVersionInfoKeepsPrereleaseDisplayVersion() {
    let version = AppVersionInfo(
        infoDictionary: [
            "CFBundleDisplayName": "PitcherPlant",
            "CFBundleShortVersionString": "0.1.2-beta",
            "CFBundleVersion": "18",
            "PPReleaseTag": "v0.1.2-beta"
        ],
        bundleIdentifier: "com.pitcherplant.desktop"
    )

    #expect(version.displayVersion == "0.1.2-beta")
    #expect(version.versionAndBuild == "0.1.2-beta")
    #expect(AppVersionInfo.formattedDisplayVersion("0.1.1", build: "17") == "0.1.1")
}

@Test
func appSemanticVersionOrdersStableAndPrereleaseTags() throws {
    let prerelease = try #require(AppSemanticVersion("v0.2.0-rc.1"))
    let final = try #require(AppSemanticVersion("0.2.0"))
    let short = try #require(AppSemanticVersion("1.0"))
    let padded = try #require(AppSemanticVersion("1.0.0"))

    #expect(prerelease < final)
    #expect(final > prerelease)
    #expect(short == padded)
}

@Test
func updateCheckServiceDetectsAvailableGitHubRelease() async throws {
    let endpoint = URL(string: "https://api.example.test/repos/D1a0y1bb/PitcherPlant/releases/latest")!
    let response = UpdateCheckHTTPResponse(statusCode: 200)
    let payload = """
    {
      "tag_name": "v0.2.0",
      "name": "v0.2.0",
      "html_url": "https://github.com/D1a0y1bb/PitcherPlant/releases/tag/v0.2.0",
      "published_at": "2026-05-04T08:00:00Z",
      "body": "Release notes",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "PitcherPlant-macOS.dmg",
          "browser_download_url": "https://github.com/D1a0y1bb/PitcherPlant/releases/download/v0.2.0/PitcherPlant-macOS.dmg",
          "size": 2048
        }
      ]
    }
    """
    let service = UpdateCheckService(
        dataLoader: { request in
            #expect(request.url == endpoint)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            return (Data(payload.utf8), response)
        },
        now: { Date(timeIntervalSince1970: 42) }
    )

    let result = try await service.check(currentVersion: updateTestVersion(updateURL: endpoint))

    #expect(result.availability == .updateAvailable)
    #expect(result.latestRelease.version == "0.2.0")
    #expect(result.latestRelease.primaryDownload?.name == "PitcherPlant-macOS.dmg")
    #expect(result.latestRelease.primaryDownload?.displaySize.isEmpty == false)
    #expect(result.checkedAt == Date(timeIntervalSince1970: 42))
}

@Suite(.serialized)
struct AppcastUpdateCheckTests {
    @Test
    func updateCheckServiceDetectsAvailableAppcastRelease() async throws {
        let endpoint = URL(string: "https://github.com/D1a0y1bb/PitcherPlant/releases/latest/download/appcast.xml?cachebust=1")!
        let response = UpdateCheckHTTPResponse(statusCode: 200)
        let payload = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>PitcherPlant Updates</title>
                <item>
                    <title>v0.1.1</title>
                    <pubDate>Wed, 06 May 2026 10:00:00 +0000</pubDate>
                    <sparkle:version>128</sparkle:version>
                    <sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
                    <enclosure
                        url="https://github.com/D1a0y1bb/PitcherPlant/releases/download/v0.1.1/PitcherPlant-macOS.zip"
                        length="4096"
                        type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """
        let service = UpdateCheckService(
            dataLoader: { request in
                #expect(request.url == endpoint)
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/rss+xml, application/xml;q=0.9, */*;q=0.8")
                #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == nil)
                return (Data(payload.utf8), response)
            },
            now: { Date(timeIntervalSince1970: 42) }
        )

        let result = try await service.check(currentVersion: updateTestVersion(releaseTag: "v0.1.0-rc.13", updateURL: endpoint))

        #expect(result.availability == .updateAvailable)
        #expect(result.latestRelease.tagName == "v0.1.1")
        #expect(result.latestRelease.version == "0.1.1")
        #expect(result.latestRelease.primaryDownload?.name == "PitcherPlant-macOS.zip")
        #expect(result.latestRelease.primaryDownload?.displaySize.isEmpty == false)
    }

    @Test
    func updateCheckServiceKeepsCurrentAppcastReleaseUpToDate() async throws {
        let endpoint = URL(string: "https://github.com/D1a0y1bb/PitcherPlant/releases/latest/download/appcast.xml?cachebust=1")!
        let response = UpdateCheckHTTPResponse(statusCode: 200)
        let payload = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>PitcherPlant Updates</title>
                <item>
                    <title>v0.1.0-rc.13</title>
                    <pubDate>Tue, 05 May 2026 17:26:46 +0000</pubDate>
                    <sparkle:version>13</sparkle:version>
                    <sparkle:shortVersionString>0.1.0-rc.13</sparkle:shortVersionString>
                    <enclosure
                        url="https://github.com/D1a0y1bb/PitcherPlant/releases/download/v0.1.0-rc.13/PitcherPlant-macOS.zip"
                        length="4096"
                        type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """
        let service = UpdateCheckService(
            dataLoader: { request in
                #expect(request.url == endpoint)
                return (Data(payload.utf8), response)
            },
            now: { Date(timeIntervalSince1970: 42) }
        )

        let result = try await service.check(currentVersion: updateTestVersion(releaseTag: "v0.1.0-rc.13", updateURL: endpoint))

        #expect(result.availability == .upToDate)
        #expect(result.latestRelease.tagName == "v0.1.0-rc.13")
        #expect(result.latestRelease.version == "0.1.0-rc.13")
    }
}

@Test
func updateCheckServiceUsesBundleReleaseTagForReleaseCandidateComparison() async throws {
    let endpoint = URL(string: "https://api.example.test/repos/D1a0y1bb/PitcherPlant/releases/latest")!
    let response = UpdateCheckHTTPResponse(statusCode: 200)
    let payload = """
    {
      "tag_name": "v0.1.0-rc.6",
      "name": "v0.1.0-rc.6",
      "html_url": "https://github.com/D1a0y1bb/PitcherPlant/releases/tag/v0.1.0-rc.6",
      "published_at": "2026-05-04T08:00:00Z",
      "body": "",
      "draft": false,
      "prerelease": false,
      "assets": []
    }
    """
    let service = UpdateCheckService(
        dataLoader: { _ in (Data(payload.utf8), response) },
        now: { Date(timeIntervalSince1970: 42) }
    )

    let current = updateTestVersion(
        version: "0.1.0",
        releaseTag: "v0.1.0-rc.5",
        updateURL: endpoint
    )
    let result = try await service.check(currentVersion: current)

    #expect(result.availability == .updateAvailable)
    #expect(result.currentVersion.comparableVersion == "v0.1.0-rc.5")
    #expect(result.latestRelease.version == "0.1.0-rc.6")
}

@Test
func updateCheckServiceSelectsFirstStableReleaseFromArray() async throws {
    let endpoint = URL(string: "https://api.example.test/repos/D1a0y1bb/PitcherPlant/releases")!
    let response = UpdateCheckHTTPResponse(statusCode: 200)
    let payload = """
    [
      {
        "tag_name": "v0.3.0-beta.1",
        "name": "Beta",
        "html_url": "https://github.com/D1a0y1bb/PitcherPlant/releases/tag/v0.3.0-beta.1",
        "published_at": "2026-05-04T08:00:00Z",
        "body": "",
        "draft": false,
        "prerelease": true,
        "assets": []
      },
      {
        "tag_name": "v0.2.0",
        "name": "Stable",
        "html_url": "https://github.com/D1a0y1bb/PitcherPlant/releases/tag/v0.2.0",
        "published_at": "2026-05-03T08:00:00Z",
        "body": "",
        "draft": false,
        "prerelease": false,
        "assets": []
      }
    ]
    """
    let service = UpdateCheckService(
        dataLoader: { _ in (Data(payload.utf8), response) },
        now: { Date(timeIntervalSince1970: 42) }
    )

    let result = try await service.check(currentVersion: updateTestVersion(version: "0.2.0", updateURL: endpoint))

    #expect(result.availability == .upToDate)
    #expect(result.latestRelease.displayName == "Stable")
}

@Test
func updateCheckServiceMapsMissingReleaseToLocalizedError() async throws {
    let endpoint = URL(string: "https://api.example.test/repos/D1a0y1bb/PitcherPlant/releases/latest")!
    let response = UpdateCheckHTTPResponse(statusCode: 404)
    let service = UpdateCheckService(
        dataLoader: { _ in (Data(), response) },
        now: { Date(timeIntervalSince1970: 42) }
    )

    do {
        _ = try await service.check(currentVersion: updateTestVersion(updateURL: endpoint))
        Issue.record("更新检查应该把 404 映射为 releaseNotFound")
    } catch let error as UpdateCheckError {
        #expect(error == .releaseNotFound)
        #expect(error.localizedDescription == "当前发布源暂无正式 Release。")
    }
}

@Test
func presetStorageRoundTripsByWorkspaceRoot() throws {
    let suiteName = "pitcherplant.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }
    defer { clearTestDefaults(suiteName, defaults: defaults) }
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
    defer { clearTestDefaults(suiteName, defaults: defaults) }

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
func chineseLanguageRuntimePrefersSparkleChineseLocalization() throws {
    let suiteName = "pitcherplant.tests.language.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }
    defer { clearTestDefaults(suiteName, defaults: defaults) }

    AppLanguageRuntime.apply(.zhHans, defaults: defaults)

    let languages = try #require(defaults.stringArray(forKey: "AppleLanguages"))
    #expect(languages.prefix(3).elementsEqual(["zh_CN", "zh-Hans", "en"]))
    #expect(AppLanguageRuntime.sparkleLocalizationResourceName(for: .zhHans) == "zh_CN")
}

@Test
func englishLanguageRuntimeAvoidsChineseFallbackForSparkle() throws {
    let suiteName = "pitcherplant.tests.language.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }
    defer { clearTestDefaults(suiteName, defaults: defaults) }

    AppLanguageRuntime.apply(.english, defaults: defaults)

    let languages = try #require(defaults.stringArray(forKey: "AppleLanguages"))
    #expect(languages == ["en"])
    #expect(AppLanguageRuntime.sparkleLocalizationResourceName(for: .english) == "Base")
}

@Test
func sparkleNoUpdateCopyOmitsCurrentlyRunningVersionLine() {
    let key = "%@ %@ is currently the newest version available.\n(You are currently running version\u{00a0}%@.)"

    let chinese = AppLanguageRuntime.sparkleLocalizedStringOverride(forKey: key, language: .zhHans)
    let english = AppLanguageRuntime.sparkleLocalizedStringOverride(forKey: key, language: .english)

    #expect(chinese == "%1$@ %2$@是当前的最新版本。")
    #expect(english == "%1$@ %2$@ is currently the newest version available.")
    #expect(chinese?.contains("正在运行") == false)
    #expect(english?.contains("currently running") == false)
}

@Test
func systemAppearanceLeavesColorSchemeUnspecified() {
    #expect(AppAppearance.system.colorScheme == nil)
}

private func clearTestDefaults(_ suiteName: String, defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: suiteName)
    defaults.synchronize()
}

private func updateTestVersion(
    version: String = "0.1.0",
    releaseTag: String = "",
    updateURL: URL
) -> AppVersionInfo {
    AppVersionInfo(
        infoDictionary: [
            "CFBundleDisplayName": "PitcherPlant",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
            "PPReleaseTag": releaseTag,
            "PPReleasesURL": "https://github.com/D1a0y1bb/PitcherPlant/releases",
            "PPUpdateCheckURL": updateURL.absoluteString
        ],
        bundleIdentifier: "com.pitcherplant.desktop"
    )
}

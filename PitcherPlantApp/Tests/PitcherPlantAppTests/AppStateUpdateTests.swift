import Foundation
import Testing
@testable import PitcherPlantApp

@Test
@MainActor
func silentUpdateCheckFailurePreservesExistingAvailableUpdate() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-update-state-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let updateURL = URL(string: "https://updates.example.test/appcast.xml")!
    let appState = AppState(workspaceRoot: root)
    let existingUpdate = UpdateCheckResult(
        currentVersion: AppVersionInfo(
            infoDictionary: [
                "CFBundleDisplayName": "PitcherPlant",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "PPUpdateCheckURL": updateURL.absoluteString
            ],
            bundleIdentifier: "com.pitcherplant.desktop"
        ),
        latestRelease: UpdateReleaseInfo(
            tagName: "v0.2.0",
            name: "v0.2.0",
            version: "0.2.0",
            htmlURL: URL(string: "https://github.com/D1a0y1bb/PitcherPlant/releases/tag/v0.2.0")!,
            publishedAt: Date(timeIntervalSince1970: 42),
            body: "Release notes",
            assets: []
        ),
        availability: .updateAvailable,
        checkedAt: Date(timeIntervalSince1970: 42)
    )
    appState.availableUpdate = existingUpdate

    let failingService = UpdateCheckService(
        dataLoader: { _ in
            throw UpdateCheckError.httpStatus(503)
        },
        now: { Date(timeIntervalSince1970: 99) }
    )

    await appState.performSilentUpdateCheck(updateCheckService: failingService)

    #expect(appState.availableUpdate == existingUpdate)
}

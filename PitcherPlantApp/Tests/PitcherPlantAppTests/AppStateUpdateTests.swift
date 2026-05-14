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

@Test
@MainActor
func assistantSuggestionsUseExplicitReportIDWhenSelectionChanges() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-assistant-report-binding-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let appState = AppState(workspaceRoot: root)
    try await appState.database.prepare()

    let evidenceID = UUID()
    let row = ReportTableRow(
        columns: ["alpha.md"],
        detailTitle: "共享作者",
        detailBody: "需要人工复核",
        evidenceID: evidenceID,
        evidenceType: .metadata
    )
    let firstReportID = UUID()
    let secondReportID = UUID()
    try await appState.database.saveReport(assistantSuggestionReport(id: firstReportID, title: "First", root: root, row: row))
    try await appState.database.saveReport(assistantSuggestionReport(id: secondReportID, title: "Second", root: root, row: row))
    await appState.reload()

    appState.selectReport(secondReportID)
    let result = AuditAssistantResult(
        summary: "Use the report captured when the task started",
        provider: .customOpenAICompatible,
        model: "gpt-5.4-mini",
        requestHash: "explicit-report-id"
    )

    await appState.saveAssistantSuggestion(reportID: firstReportID, for: row, result: result)

    let firstSuggestion = await appState.latestAssistantSuggestion(reportID: firstReportID, for: row)
    let secondSuggestion = try await appState.database.latestAssistantSuggestion(reportID: secondReportID, evidenceID: evidenceID)

    #expect(firstSuggestion?.result.summary == "Use the report captured when the task started")
    #expect(secondSuggestion == nil)
}

private func assistantSuggestionReport(id: UUID, title: String, root: URL, row: ReportTableRow) -> AuditReport {
    AuditReport(
        id: id,
        title: title,
        sourcePath: root.appendingPathComponent("\(title).html").path,
        scanDirectoryPath: root.path,
        metrics: [],
        sections: [
            ReportSection(
                kind: .metadata,
                title: "Metadata",
                summary: "",
                table: ReportTable(headers: ["File"], rows: [row])
            )
        ]
    )
}

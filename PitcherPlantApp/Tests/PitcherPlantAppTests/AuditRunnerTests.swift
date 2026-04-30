import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func auditRunnerProducesNativeReportRowsForAppViewing() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-native-audit-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let reports = root.appendingPathComponent("reports", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
    try """
    SSRF 解法：读取 index.php 后使用 php://filter 披露源码，拼接 payload 完成利用。
    关键步骤包含 curl、base64 decode 和最终 flag 提取。
    """.write(to: source.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
    try """
    SSRF 解法：读取 index.php 后使用 php://filter 披露源码，拼接 payload 完成利用。
    关键步骤包含 curl、base64 decode 和最终 flag 提取。
    """.write(to: source.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = source.path
    configuration.outputDirectoryPath = reports.path
    configuration.reportNameTemplate = "native-{date}.html"
    configuration.textThreshold = 0.70

    let result = try await AuditRunner().run(
        configuration: configuration,
        importedFingerprints: [],
        whitelistRules: []
    ) { _, _ in }

    let textSection = try #require(result.report.sections.first(where: { $0.kind == .text }))

    #expect(textSection.table?.rows.isEmpty == false)
    #expect(textSection.table?.rows.first?.detailBody.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: result.report.sourcePath))
    #expect(result.summary.documentCount == 2)
    #expect(result.summary.historicalFingerprintCount == 0)
    #expect(result.summary.duration >= 0)
}

@Test
@MainActor
func auditRunnerEmitsLargeRunWarningAndSummary() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-large-run-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let reports = root.appendingPathComponent("reports", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
    try "shared writeup body".write(to: source.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = source.path
    configuration.outputDirectoryPath = reports.path
    configuration.reportNameTemplate = "large-{date}.html"
    var events: [(AuditStage, String)] = []

    let result = try await AuditRunner().run(
        configuration: configuration,
        importedFingerprints: [
            FingerprintRecord(filename: "old.md", ext: "md", author: "", size: 12, simhash: "0000000000000000", scanDir: "old")
        ],
        whitelistRules: [],
        limits: AuditRunLimits(largeDocumentCount: 1, largeImageCount: 1, largeHistoricalFingerprintCount: 1)
    ) { stage, message in
        events.append((stage, message))
    }

    #expect(result.summary.documentCount == 1)
    #expect(result.summary.historicalFingerprintCount == 1)
    #expect(events.contains(where: { $0.0 == .parsed && $0.1.contains("预计耗时较长") }))
}

@Test
@MainActor
func appStateCancelAuditUpdatesRunningStateImmediately() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-cancel-state-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let appState = AppState(workspaceRoot: root)

    appState.isRunningAudit = true
    appState.cancelAudit()

    #expect(appState.isRunningAudit == false)
}

@Test
@MainActor
func auditRunnerCancellationAndAppStateMessageAreUserReadable() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-cancel-\(UUID().uuidString)", isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let reports = root.appendingPathComponent("reports", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
    try "cancel me".write(to: source.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = source.path
    configuration.outputDirectoryPath = reports.path

    do {
        _ = try await AuditRunner().run(
            configuration: configuration,
            importedFingerprints: [],
            whitelistRules: []
        ) { stage, _ in
            if stage == .parsed {
                throw CancellationError()
            }
        }
        Issue.record("取消路径应抛出 CancellationError")
    } catch is CancellationError {
        #expect(AppState.auditFailureMessage(for: CancellationError()) == "审计已取消。")
    }
}

@Test
func auditJobCompletionStoresRunSummaryEvent() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-summary")
    let job = AuditJob(configuration: AuditConfiguration.defaults(for: root))
    let reportID = UUID()
    let summary = AuditRunSummary(
        documentCount: 3,
        imageCount: 2,
        historicalFingerprintCount: 1,
        duration: 1.25
    )
    let message = AppState.auditSummaryMessage(for: summary)

    let completed = job.completed(reportID: reportID, summaryMessage: message)

    #expect(completed.status == .succeeded)
    #expect(completed.reportID == reportID)
    #expect(completed.latestMessage == message)
    #expect(completed.events.last?.message == message)
    #expect(message.contains("3 个文档"))
    #expect(message.contains("2 张图片"))
    #expect(message.contains("1 条历史指纹"))
}

@Test
func auditJobEventsCarryStructuredStagePayloads() throws {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-structured-event")
    let job = AuditJob(configuration: AuditConfiguration.defaults(for: root))
        .advanced(
            stage: .scan,
            message: "扫描文件完成",
            processedCount: 12,
            failedCount: 1,
            failedFiles: ["broken.docx"],
            duration: 0.42
        )

    let event = try #require(job.events.last)

    #expect(event.stage == .scan)
    #expect(event.processedCount == 12)
    #expect(event.failedCount == 1)
    #expect(event.failedFiles == ["broken.docx"])
    #expect(event.duration == 0.42)
}

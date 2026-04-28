import Foundation
import GRDB
import Testing
@testable import PitcherPlantApp

@Test
func databaseStorePersistsStructuredJobEventsAndReportSections() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()

    var job = AuditJob(configuration: AuditConfiguration.defaults(for: root))
    job = job.advanced(stage: .initialize, message: "初始化")
    job = job.advanced(stage: .parsed, message: "解析文档完成")
    try await store.upsertJob(job)

    let report = AuditReport(
        jobID: job.id,
        title: "结构化报告",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [ReportMetric(title: "章节", value: "2", systemImage: "doc.text")],
        sections: [
            ReportSection(kind: .overview, title: "总览", summary: "结构化总览"),
            ReportSection(kind: .code, title: "代码", summary: "结构化代码")
        ]
    )
    try await store.saveReport(report)
    try await store.recordExport(
        ExportRecord(
            reportID: report.id,
            reportTitle: report.title,
            format: .html,
            destinationPath: root.appendingPathComponent("exported.html").path
        )
    )

    let loadedJobs = try await store.loadJobs()
    let loadedReports = try await store.loadReports()
    let exports = try await store.loadExportRecords()

    #expect(loadedJobs.first?.events.count == job.events.count)
    #expect(loadedJobs.first?.events.last?.message == "解析文档完成")
    #expect(loadedReports.first?.sections.map(\.title) == ["总览", "代码"])
    #expect(try await store.debugTableRowCount(named: "audit_job_events") == job.events.count)
    #expect(try await store.debugTableRowCount(named: "report_sections") == 2)
    #expect(exports.first?.format == .html)
    #expect(exports.first?.reportTitle == "结构化报告")
    #expect(try await store.debugTableRowCount(named: "export_records") == 1)
}

@Test
func databaseStoreUpgradesObsoleteReportSchemaAndKeepsReports() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-obsolete-schema-\(UUID().uuidString)", isDirectory: true)
    let support = root.appendingPathComponent(".pitcherplant-macos", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

    let dbURL = support.appendingPathComponent("PitcherPlantMac.sqlite")
    let report = AuditReport(
        title: "旧结构报告",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        createdAt: Date(timeIntervalSince1970: 1_777_248_000),
        metrics: [ReportMetric(title: "章节", value: "1", systemImage: "doc.text")],
        sections: [ReportSection(kind: .overview, title: "总览", summary: "旧结构总览")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let reportPayload = try #require(String(data: encoder.encode(report), encoding: .utf8))

    let dbQueue = try DatabaseQueue(path: dbURL.path)
    try await dbQueue.write { db in
        try db.execute(
            sql: """
            CREATE TABLE audit_reports (
                id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at DATETIME NOT NULL,
                title TEXT NOT NULL,
                source_path TEXT NOT NULL,
                scan_directory_path TEXT NOT NULL,
                job_id TEXT,
                is_legacy INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        try db.execute(sql: "CREATE TABLE app_migrations (id TEXT PRIMARY KEY, created_at DATETIME NOT NULL)")
        try db.execute(
            sql: """
            INSERT INTO audit_reports (id, payload, created_at, title, source_path, scan_directory_path, job_id, is_legacy)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                report.id.uuidString,
                reportPayload,
                report.createdAt,
                report.title,
                report.sourcePath,
                report.scanDirectoryPath,
                nil,
                1
            ]
        )
        try db.execute(
            sql: "INSERT INTO app_migrations (id, created_at) VALUES (?, ?)",
            arguments: ["obsolete-import", report.createdAt]
        )
    }

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()

    let loaded = try #require(try await store.loadReports().first)
    #expect(loaded.title == "旧结构报告")
    #expect(loaded.displaySections.map(\.title) == ["总览"])
    #expect(try await store.debugTableColumns(named: "audit_reports").contains("is_legacy") == false)
    #expect(try await store.debugTableExists(named: "app_migrations") == false)
}

@Test
func databaseStoreMarksInterruptedRunningJobs() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-interrupted-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()

    var job = AuditJob(configuration: AuditConfiguration.defaults(for: root))
    job = job.advanced(stage: .parsed, message: "解析文档完成")
    try await store.upsertJob(job)

    let marked = try await store.markInterruptedJobs()
    let loadedJob = try #require(try await store.loadJobs().first)

    #expect(marked == 1)
    #expect(loadedJob.status == .failed)
    #expect(loadedJob.latestMessage.contains("中断"))
}

@Test
func databaseStoreFallsBackWhenWorkspaceRootIsReadOnly() async throws {
    let readOnlyRoot = URL(fileURLWithPath: "/System", isDirectory: true)
    let store = try DatabaseStore(rootDirectory: readOnlyRoot)

    try await store.prepare()

    #expect(try await store.debugTableRowCount(named: "audit_jobs") == 0)
}

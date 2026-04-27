import Foundation
import GRDB
import Testing
@testable import PitcherPlantApp

@Test
func legacyHtmlImportMapsSectionsTablesAndMetrics() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-legacy-html-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacyURL = root.appendingPathComponent("legacy-report.html")
    try legacyReportFixtureHTML.write(to: legacyURL, atomically: true, encoding: .utf8)
    let report = try LegacyStateImporter.importLegacyReport(at: legacyURL)

    #expect(report.isLegacy)
    #expect(report.metrics.count >= 3)
    #expect(report.sections.count >= 8)
    #expect(report.sections.first(where: { $0.kind == .overview })?.table?.rows.isEmpty == false)
    #expect(report.sections.first(where: { $0.kind == .code })?.table != nil)
    #expect(report.sections.first(where: { $0.title.contains("图片证据详列") })?.table?.rows.isEmpty == false)
}

@Test
func legacySQLiteMigrationPreservesTimestampAndWhitelist() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-legacy-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacyURL = root.appendingPathComponent("PitcherPlant.sqlite")
    let legacyQueue = try DatabaseQueue(path: legacyURL.path)
    try await legacyQueue.write { db in
        try db.execute(sql: "CREATE TABLE fingerprints (id INTEGER PRIMARY KEY AUTOINCREMENT, filename TEXT, ext TEXT, author TEXT, size INTEGER, simhash TEXT, scan_dir TEXT, scanned_at TEXT)")
        try db.execute(sql: "CREATE TABLE whitelist (pattern TEXT UNIQUE, type TEXT)")
        try db.execute(sql: "INSERT INTO fingerprints (filename, ext, author, size, simhash, scan_dir, scanned_at) VALUES (?, ?, ?, ?, ?, ?, ?)", arguments: ["a.md", ".md", "alice", 12, "0000000000000000", "date1", "2026-04-20 12:34:56"])
        try db.execute(sql: "INSERT INTO whitelist (pattern, type) VALUES (?, ?)", arguments: ["alice", "author"])
    }

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()
    let summary = try await MigrationService(workspaceRoot: root).runIfNeeded(database: store)
    let records = try await store.loadFingerprintRecords()
    let rules = try await store.loadWhitelistRules()
    let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: try #require(records.first?.scannedAt))

    #expect(summary.importedFingerprints == 1)
    #expect(summary.importedWhitelistRules == 1)
    #expect(components.year == 2026)
    #expect(components.month == 4)
    #expect(components.day == 20)
    #expect(components.hour == 12)
    #expect(components.minute == 34)
    #expect(components.second == 56)
    #expect(rules.first?.type == .author)
    #expect(rules.first?.pattern == "alice")
}

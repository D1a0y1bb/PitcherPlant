import Foundation
import GRDB
import Testing
@testable import PitcherPlantApp

@Test
func configurationDefaultsBuildPaths() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant")
    let defaults = AuditConfiguration.defaults(for: root)
    #expect(defaults.directoryPath.contains("/tmp/pitcherplant/date"))
    #expect(defaults.outputDirectoryPath.contains("/tmp/pitcherplant/reports/full"))
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
func codeSimilarityAnalyzerBuildsStructuredEvidence() {
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.swift"),
        filename: "a.swift",
        ext: "swift",
        content: "",
        cleanText: "",
        codeBlocks: [
            """
            func login(user: String, password: String) -> Bool {
                if user.isEmpty || password.isEmpty { return false }
                let digest = user + ":" + password
                return digest.count > 4
            }
            """
        ],
        author: "",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.swift"),
        filename: "b.swift",
        ext: "swift",
        content: "",
        cleanText: "",
        codeBlocks: [
            """
            func login(name: String, secret: String) -> Bool {
                if name.isEmpty || secret.isEmpty { return false }
                let digest = name + ":" + secret
                return digest.count > 4
            }
            """
        ],
        author: "",
        images: []
    )

    let matches = CodeSimilarityAnalyzer().analyze(documents: [docA, docB])
    let pair = try! #require(matches.first)
    #expect(pair.score >= 0.60)
    #expect(pair.detailLines.count >= 4)
    #expect(pair.attachments.count == 3)
    #expect(pair.evidence.contains("片段"))
}

@Test
func legacyHtmlImportMapsSectionsTablesAndMetrics() throws {
    let root = try testWorkspaceRoot()
    let legacyURL = root.appendingPathComponent("report.html")
    let report = try LegacyStateImporter.importLegacyReport(at: legacyURL)

    #expect(report.isLegacy)
    #expect(report.metrics.count >= 3)
    #expect(report.sections.count >= 8)
    #expect(report.sections.first(where: { $0.kind == .overview })?.table?.rows.isEmpty == false)
    #expect(report.sections.first(where: { $0.kind == .code })?.table != nil)
    #expect(report.sections.first(where: { $0.title.contains("图片证据详列") })?.table?.rows.isEmpty == false)
}

@Test
func reportLibrarySearchMatchesLegacyAndSectionEvidence() {
    let section = ReportSection(
        kind: .code,
        title: "代码/脚本抄袭分析",
        summary: "结构 token 比对",
        table: ReportTable(
            headers: ["文件 A", "文件 B"],
            rows: [
                ReportTableRow(
                    columns: ["alpha.swift", "beta.swift"],
                    detailTitle: "alpha.swift ↔ beta.swift",
                    detailBody: "命中了相同的结构片段",
                    badges: [ReportBadge(title: "高危", tone: .danger)]
                )
            ]
        )
    )
    let nativeReport = AuditReport(
        title: "2026-04-22 原生报告",
        sourcePath: "/tmp/native.html",
        scanDirectoryPath: "/tmp/date",
        metrics: [],
        sections: [section]
    )
    let legacyReport = AuditReport(
        title: "2026-04-20 Legacy 报告",
        sourcePath: "/tmp/legacy.html",
        scanDirectoryPath: "/tmp/date",
        isLegacy: true,
        metrics: [],
        sections: [ReportSection(kind: .overview, title: "Legacy 报告", summary: "旧版导入")]
    )

    #expect(nativeReport.matchesLibrarySearch("结构片段", filter: .all))
    #expect(nativeReport.matchesLibrarySearch("原生", filter: .nativeOnly))
    #expect(legacyReport.matchesLibrarySearch("", filter: .legacyOnly))
}

@Test
func sectionFilteringRespectsQueryFilterAndSortOrder() {
    let section = ReportSection(
        kind: .image,
        title: "图片证据详列",
        summary: "支持 OCR 证据",
        table: ReportTable(
            headers: ["文件 A", "文件 B"],
            rows: [
                ReportTableRow(
                    columns: ["b.png", "c.png"],
                    detailTitle: "B 组",
                    detailBody: "包含截图",
                    badges: [ReportBadge(title: "关注", tone: .warning)],
                    attachments: [ReportAttachment(title: "A", subtitle: "图", body: "证据", imageBase64: nil)]
                ),
                ReportTableRow(
                    columns: ["a.png", "d.png"],
                    detailTitle: "A 组",
                    detailBody: "高危匹配",
                    badges: [ReportBadge(title: "高危", tone: .danger)],
                    attachments: []
                )
            ]
        )
    )

    let attachmentOnly = section.filteredCopy(query: "", evidenceFilter: .withAttachments, sortOrder: .default)
    #expect(attachmentOnly.table?.rows.count == 1)
    #expect(attachmentOnly.table?.rows.first?.detailTitle == "B 组")

    let highRisk = section.filteredCopy(query: "高危", evidenceFilter: .highRisk, sortOrder: .severity)
    #expect(highRisk.table?.rows.count == 1)
    #expect(highRisk.table?.rows.first?.detailTitle == "A 组")

    let titled = section.filteredCopy(query: "", evidenceFilter: .all, sortOrder: .title)
    #expect(titled.table?.rows.map(\.detailTitle) == ["A 组", "B 组"])
}

@Test
func pdfIngestionExtractsEmbeddedImagesBeforePageFallback() throws {
    let root = try testWorkspaceRoot()
    let fixtureDirectory = root.appendingPathComponent("date/date6/145-flag{LNU_cyber}")

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = fixtureDirectory.path
    configuration.useVisionOCR = false

    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: fixtureDirectory)
    let pdfDocument = try #require(documents.first(where: { $0.ext == "pdf" }))

    #expect(pdfDocument.images.isEmpty == false)
    #expect(pdfDocument.images.contains(where: { $0.source.contains(":X") }))
}

private func testWorkspaceRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<12 {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("report.html").path),
           FileManager.default.fileExists(atPath: candidate.appendingPathComponent("date").path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

@Test
func databaseStoreFallsBackWhenWorkspaceRootIsReadOnly() async throws {
    let readOnlyRoot = URL(fileURLWithPath: "/System", isDirectory: true)
    let store = try DatabaseStore(rootDirectory: readOnlyRoot)

    try await store.prepare()

    #expect(try await store.debugTableRowCount(named: "audit_jobs") == 0)
}

@Test
func ingestionSkipsOfficeTempsAndReadsLossyText() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-ingestion-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0xff, 0xfe, 0x66, 0x6c, 0x61, 0x67]).write(to: root.appendingPathComponent("lossy.txt"))
    try "temporary content".write(to: root.appendingPathComponent("~$draft.txt"), atomically: true, encoding: .utf8)

    let configuration = AuditConfiguration.defaults(for: root)
    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: root)

    #expect(documents.map(\.filename) == ["lossy.txt"])
    #expect(documents.first?.content.isEmpty == false)
}

@Test
func normalizerRemovesLegacyNoisePatternsDuringIngestion() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-normalizer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let noisy = "flag{secret} \(String(repeating: "a", count: 32)) \(String(repeating: "Q", count: 60)) ```print(1)``` useful evidence"
    try noisy.write(to: root.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

    let configuration = AuditConfiguration.defaults(for: root)
    let document = try #require(DocumentIngestionService(configuration: configuration).ingestDocuments(in: root).first)

    #expect(document.cleanText == "useful evidence")
}

@Test
func textSimilarityBuildsContextEvidenceAndParaphraseMarker() throws {
    let prefixA = String(repeating: "A", count: 140)
    let prefixB = String(repeating: "B", count: 140)
    let shared = "共同利用 SSRF 读取 metadata endpoint 并提取临时凭证"
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.md"),
        filename: "a.md",
        ext: "md",
        content: "\(prefixA) \(shared) 后续分析",
        cleanText: "共同 利用 ssrf 读取 metadata endpoint 提取 临时 凭证",
        codeBlocks: [],
        author: "",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.md"),
        filename: "b.md",
        ext: "md",
        content: "\(prefixB) \(shared) 复现过程",
        cleanText: "共同 利用 ssrf 读取 metadata endpoint 提取 临时 凭证",
        codeBlocks: [],
        author: "",
        images: []
    )

    let pair = try #require(TextSimilarityAnalyzer().analyze(documents: [docA, docB], threshold: 0.5).first)

    #expect(pair.evidence.contains("SSRF") || pair.evidence.contains("ssrf"))
    #expect(pair.detailLines.contains(where: { $0.contains("最长公共片段") }))
    #expect(pair.attachments.count >= 2)
}

@Test
func metadataCollisionUsesLastModifiedByAuthor() {
    let docA = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/a.docx"),
        filename: "a.docx",
        ext: "docx",
        content: "alpha",
        cleanText: "alpha",
        codeBlocks: [],
        author: "",
        lastModifiedBy: "SharedEditor",
        images: []
    )
    let docB = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/b.docx"),
        filename: "b.docx",
        ext: "docx",
        content: "beta",
        cleanText: "beta",
        codeBlocks: [],
        author: "SharedEditor",
        images: []
    )

    let collision = MetadataCollisionAnalyzer().analyze(documents: [docA, docB]).first

    #expect(collision?.author == "SharedEditor")
    #expect(collision?.files.sorted() == ["a.docx", "b.docx"])
}

@Test
func imageReuseCountsExamplesAndUsesThreeHashes() throws {
    let leftImage = ParsedImage(
        source: "docx word/media/a.png",
        perceptualHash: "0000000000000000",
        averageHash: "ffffffffffffffff",
        differenceHash: "aaaaaaaaaaaaaaaa",
        ocrPreview: "login screenshot",
        thumbnailBase64: "ZmFrZQ=="
    )
    let rightImage = ParsedImage(
        source: "pdf page 1",
        perceptualHash: "0000000000000001",
        averageHash: "fffffffffffffffe",
        differenceHash: "aaaaaaaaaaaaaaab",
        ocrPreview: "login screenshot copy",
        thumbnailBase64: "ZmFrZTI="
    )
    let docA = ParsedDocument(url: URL(fileURLWithPath: "/tmp/a.docx"), filename: "a.docx", ext: "docx", content: "", cleanText: "", codeBlocks: [], author: "", images: [leftImage])
    let docB = ParsedDocument(url: URL(fileURLWithPath: "/tmp/b.pdf"), filename: "b.pdf", ext: "pdf", content: "", cleanText: "", codeBlocks: [], author: "", images: [rightImage])

    let pair = try #require(ImageReuseAnalyzer().analyze(documents: [docA, docB], threshold: 1).first)

    #expect(pair.evidence.contains("命中图片数：1"))
    #expect(pair.detailLines.contains(where: { $0.contains("pHash") }))
    #expect(pair.attachments.count >= 2)
}

@Test
func exportedHTMLIncludesRowDetailsAndAttachments() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let report = AuditReport(
        title: "导出详情",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [],
        sections: [
            ReportSection(
                kind: .image,
                title: "图片证据详列",
                summary: "包含附件",
                table: ReportTable(
                    headers: ["A", "B"],
                    rows: [ReportTableRow(
                        columns: ["a", "b"],
                        detailTitle: "详情标题",
                        detailBody: "OCR 详情正文",
                        attachments: [ReportAttachment(title: "截图", subtitle: "page 1", body: "OCR 预览", imageBase64: "ZmFrZQ==")]
                    )]
                )
            )
        ]
    )

    let url = root.appendingPathComponent("export.html")
    try ReportExporter.exportHTML(report: report, to: url)
    let html = try String(contentsOf: url, encoding: .utf8)

    #expect(html.contains("OCR 详情正文"))
    #expect(html.contains("OCR 预览"))
    #expect(html.contains("data:image/jpeg;base64,ZmFrZQ=="))
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

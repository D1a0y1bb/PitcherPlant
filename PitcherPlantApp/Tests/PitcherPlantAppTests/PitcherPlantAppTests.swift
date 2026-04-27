import Foundation
import GRDB
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
        showLegacyBadges: false,
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
    let fixtureDirectory = root.appendingPathComponent("Fixtures/WriteupSamples/date/date6/145-flag{LNU_cyber}")

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
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Fixtures/WriteupSamples/date").path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private let legacyReportFixtureHTML = """
<html>
<body>
<div class="card"><div class="card-title">报告数</div><div class="card-value">2</div></div>
<div class="card warning"><div class="card-title">高危</div><div class="card-value">1</div></div>
<div class="card"><div class="card-title">文件</div><div class="card-value">4</div></div>
<div id="tab_overview" class="section tab-section"><h2>总览</h2><div class="hint">整体风险可复核</div><table><tr><th>项目</th><th>值</th></tr><tr><td>样例</td><td>1</td></tr></table></div>
<div id="tab_text" class="section tab-section"><h2>文本相似分析</h2><table><tr><th>文件 A</th><th>文件 B</th><th>分数</th></tr><tr><td>a.md</td><td>b.md</td><td>0.91</td></tr></table></div>
<div id="tab_code" class="section tab-section"><h2>代码/脚本抄袭分析</h2><table><tr><th>文件 A</th><th>文件 B</th><th>分数</th></tr><tr><td>a.swift</td><td>b.swift</td><td>0.86</td></tr></table></div>
<div id="tab_image" class="section tab-section"><h2>图片证据详列</h2><table><tr><th>图片 A</th><th>图片 B</th><th>分数</th></tr><tr><td>one.png</td><td>two.png</td><td>0.94</td></tr></table></div>
<div id="tab_meta" class="section tab-section"><h2>元数据碰撞</h2><table><tr><th>字段</th><th>值</th></tr><tr><td>作者</td><td>alice</td></tr></table></div>
<div id="tab_dup" class="section tab-section"><h2>重复提交检测</h2><table><tr><th>文件 A</th><th>文件 B</th></tr><tr><td>same-a.md</td><td>same-b.md</td></tr></table></div>
<div id="tab_cross" class="section tab-section"><h2>跨批次复用</h2><table><tr><th>当前</th><th>历史</th></tr><tr><td>now.md</td><td>old.md</td></tr></table></div>
<div id="tab_summary" class="section tab-section"><h2>结论</h2><table><tr><th>结论</th><th>说明</th></tr><tr><td>复核</td><td>需要人工确认</td></tr></table></div>
</body>
</html>
"""

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
func ingestionFallsBackForMislabeledTextDocxAndSkipsBrokenDocx() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-mislabeled-docx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "plain writeup stored with docx extension".write(to: root.appendingPathComponent("plain.docx"), atomically: true, encoding: .utf8)
    try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: root.appendingPathComponent("broken.docx"))

    let configuration = AuditConfiguration.defaults(for: root)
    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: root)

    #expect(documents.map(\.filename) == ["plain.docx"])
    #expect(documents.first?.content.contains("plain writeup") == true)
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
func fingerprintAnalyzerUsesWrappingStableHash() {
    let document = ParsedDocument(
        url: URL(fileURLWithPath: "/tmp/wrapping.md"),
        filename: "wrapping.md",
        ext: "md",
        content: "",
        cleanText: "this token forces fnv hash wrapping during fingerprint generation",
        codeBlocks: [],
        author: "alice",
        images: []
    )

    let record = FingerprintAnalyzer().buildRecords(documents: [document], scanDirectory: "date").first

    #expect(record?.filename == "wrapping.md")
    #expect(record?.simhash.count == 16)
}

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

    #expect(result.report.isLegacy == false)
    #expect(textSection.table?.rows.isEmpty == false)
    #expect(textSection.table?.rows.first?.detailBody.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: result.report.sourcePath))
}

@Test
func auditReportPrefersBusinessEvidenceForInlineReview() throws {
    let overviewRow = ReportTableRow(columns: ["总览", "", "1"], detailTitle: "总览行", detailBody: "总览")
    let textRow = ReportTableRow(columns: ["a.md", "b.md", "0.91"], detailTitle: "文本证据", detailBody: "文本相似")
    let report = AuditReport(
        title: "选择测试",
        sourcePath: "/tmp/report.html",
        scanDirectoryPath: "/tmp/date",
        metrics: [],
        sections: [
            ReportSection(
                kind: .overview,
                title: "总览",
                summary: "summary",
                table: ReportTable(headers: ["A", "B", "C"], rows: [overviewRow])
            ),
            ReportSection(
                kind: .text,
                title: "文本相似",
                summary: "summary",
                table: ReportTable(headers: ["A", "B", "C"], rows: [textRow])
            )
        ]
    )

    #expect(report.preferredEvidenceSection?.kind == .text)
    #expect(report.preferredEvidenceSection?.table?.rows.first?.detailTitle == "文本证据")
}

@Test
func auditReportMergesDuplicateDisplaySections() throws {
    let firstRow = ReportTableRow(columns: ["a.swift", "b.swift", "0.82"], detailTitle: "代码证据 A", detailBody: "A")
    let secondRow = ReportTableRow(columns: ["c.swift", "d.swift", "0.91"], detailTitle: "代码证据 B", detailBody: "B")
    let report = AuditReport(
        title: "Legacy 重复章节",
        sourcePath: "/tmp/report.html",
        scanDirectoryPath: "/tmp/date",
        metrics: [],
        sections: [
            ReportSection(kind: .overview, title: "总览", summary: "summary"),
            ReportSection(
                kind: .code,
                title: "代码",
                summary: "first",
                table: ReportTable(headers: ["A", "B", "分数"], rows: [firstRow])
            ),
            ReportSection(
                kind: .code,
                title: "代码",
                summary: "second",
                table: ReportTable(headers: ["A", "B", "分数"], rows: [secondRow])
            )
        ]
    )

    let codeSection = try #require(report.displaySection(for: .code))

    #expect(report.displaySections.map(\.kind) == [.overview, .code])
    #expect(codeSection.table?.rows.map(\.detailTitle) == ["代码证据 A", "代码证据 B"])
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
func exportedHTMLEscapesAttributeContentAndRejectsUnsafeImagePayload() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-export-escaping-\(UUID().uuidString)", isDirectory: true)
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
                        attachments: [
                            ReportAttachment(title: ##"截图" onerror="alert(1)""##, subtitle: "page 1", body: "OCR 预览", imageBase64: "ZmFrZQ=="),
                            ReportAttachment(title: "恶意图片", subtitle: "page 2", body: "payload", imageBase64: #"ZmFrZQ==" onerror="alert(1)"#)
                        ]
                    )]
                )
            )
        ]
    )

    let url = root.appendingPathComponent("export.html")
    try ReportExporter.exportHTML(report: report, to: url)
    let html = try String(contentsOf: url, encoding: .utf8)

    #expect(html.contains(#"alt="截图&quot; onerror=&quot;alert(1)&quot;""#))
    #expect(html.contains(#"src="data:image/jpeg;base64,ZmFrZQ==""#))
    #expect(html.contains(#"src="ZmFrZQ==&quot; onerror=&quot;alert(1)&quot;""#) == false)
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

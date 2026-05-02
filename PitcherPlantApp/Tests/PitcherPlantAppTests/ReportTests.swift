import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func reportLibrarySearchMatchesSectionEvidence() {
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
    let report = AuditReport(
        title: "2026-04-22 原生报告",
        sourcePath: "/tmp/native.html",
        scanDirectoryPath: "/tmp/date",
        metrics: [],
        sections: [section]
    )

    #expect(report.matchesLibrarySearch("结构片段"))
    #expect(report.matchesLibrarySearch("原生"))
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

    let model = ReportRowsViewModel(section: section, query: "截图", filter: .withAttachments, sortOrder: .default)
    #expect(model.totalRowCount == 2)
    #expect(model.rows.map(\.detailTitle) == ["B 组"])
}

@Test
@MainActor
func evidenceImageCacheReusesDecodedImages() throws {
    let cache = EvidenceImageCache()
    let pixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="

    let first = try #require(cache.image(for: pixelPNG))
    let second = try #require(cache.image(for: pixelPNG))

    #expect(first === second)
    #expect(cache.cachedImageCount() == 1)
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
        title: "重复章节",
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
func exportedCSVUsesDedicatedCrossBatchColumns() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-cross-batch-csv-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let row = ReportTableRow(
        columns: ["current.md", "history.md", "spring-2026", "2", "疑似复用"],
        detailTitle: "current.md ↔ history.md",
        detailBody: "跨批次复用",
        evidenceID: UUID(),
        evidenceType: .crossBatch,
        riskAssessment: RiskAssessment(score: 0.875, reasons: ["跨批次复用"]),
        metadata: [
            CrossBatchGraphMetadataKey.batchName: "spring-2026",
            CrossBatchGraphMetadataKey.distance: "2",
            CrossBatchGraphMetadataKey.status: "疑似复用",
        ]
    )
    let report = AuditReport(
        title: "跨批次 CSV",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [],
        sections: [
            ReportSection(
                kind: .crossBatch,
                title: "跨批次",
                summary: "导出测试",
                table: ReportTable(headers: ["当前文件", "历史文件", "批次", "位差", "状态"], rows: [row])
            )
        ]
    )

    let csvURL = root.appendingPathComponent("report.csv")
    try ReportExporter.exportCSV(report: report, to: csvURL)
    let lines = try String(contentsOf: csvURL, encoding: .utf8).components(separatedBy: .newlines)

    #expect(lines.first?.contains("cross_batch_batch") == true)
    #expect(lines.first?.contains("cross_batch_distance") == true)
    #expect(lines.first?.contains("cross_batch_status") == true)
    #expect(lines.dropFirst().first?.contains(#""88%","spring-2026","2","疑似复用""#) == true)
}

@Test
func codeLineDiffBuilderPairsModifiedInsertedAndDeletedLines() {
    let rows = CodeLineDiffBuilder.rows(
        left: """
        let token = fetch()
        if token.isEmpty { return }
        print(token)
        """,
        right: """
        let token = fetch()
        if token.count == 0 { return }
        audit(token)
        print(token)
        """,
        contextRadius: 10
    )

    #expect(rows.contains { $0.change == .modified && $0.leftLineNumber == 2 && $0.rightLineNumber == 2 })
    #expect(rows.contains { $0.change == .inserted && $0.leftLineNumber == nil && $0.rightText.contains("audit") })
    #expect(rows.contains { $0.change == .unchanged && $0.leftText.contains("print") && $0.rightText.contains("print") })
}

@Test
func documentIngestionRegistryCoversExtendedParserFamilies() {
    let supported = DocumentIngestionService.supportedExtensions

    #expect(["pdf", "docx", "md", "txt", "html", "htm", "rtf", "pptx"].allSatisfy { supported.contains($0) })
    #expect(["png", "jpg", "webp"].allSatisfy { supported.contains($0) })
    #expect(["py", "swift", "go", "js", "sh"].allSatisfy { supported.contains($0) })
}

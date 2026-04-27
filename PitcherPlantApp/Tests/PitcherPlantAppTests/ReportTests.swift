import Foundation
import Testing
@testable import PitcherPlantApp

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

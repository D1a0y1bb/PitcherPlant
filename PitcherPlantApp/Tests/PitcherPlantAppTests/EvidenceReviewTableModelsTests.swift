import Foundation
import AppKit
import Testing
@testable import PitcherPlantApp

@Test
func evidenceReviewTableRowsMapReportEvidenceForAuditorScanning() throws {
    let reportID = UUID()
    let highEvidenceID = UUID()
    let lowEvidenceID = UUID()
    let highRow = ReportTableRow(
        id: highEvidenceID,
        columns: ["alpha.md", "beta.md", "93.00%", "共享 exploit 步骤"],
        detailTitle: "alpha.md ↔ beta.md",
        detailBody: "高风险文本复用",
        evidenceID: highEvidenceID,
        evidenceType: .text,
        riskAssessment: RiskAssessment(score: 0.93, reasons: ["文本复用"]),
        whitelistStatus: WhitelistEvaluation(status: .marked, matchedRuleType: .textSnippet, reason: "官方模板", scoreMultiplier: 0.6)
    )
    let lowRow = ReportTableRow(
        id: lowEvidenceID,
        columns: ["gamma.md", "delta.md", "41.00%", "少量公共命令"],
        detailTitle: "gamma.md ↔ delta.md",
        detailBody: "低风险公共片段",
        evidenceID: lowEvidenceID,
        evidenceType: .code,
        riskAssessment: RiskAssessment(score: 0.41, reasons: ["代码结构"])
    )
    let section = ReportSection(
        kind: .text,
        title: "文本证据",
        summary: "",
        table: ReportTable(headers: ["A", "B", "Score", "Detail"], rows: [lowRow, highRow])
    )
    let report = AuditReport(
        id: reportID,
        title: "Spring Final",
        sourcePath: "/tmp/report.html",
        scanDirectoryPath: "/tmp/submissions",
        metrics: [],
        sections: [section]
    )

    let rows = EvidenceReviewTableRow.rows(report: report, section: section)
    let sorted = EvidenceReviewTableRow.sorted(rows, by: .riskDescending)

    #expect(rows.count == 2)
    #expect(sorted.map(\.target.evidenceID) == [highEvidenceID, lowEvidenceID])
    #expect(sorted[0].target.reportID == reportID)
    #expect(sorted[0].leftObject == "alpha.md")
    #expect(sorted[0].rightObject == "beta.md")
    #expect(sorted[0].scoreText == "93.00%")
    #expect(sorted[0].riskLevel == .high)
    #expect(sorted[0].reviewDecision == .pending)
    #expect(sorted[0].whitelistStatus == .marked)
}

@Test
func evidenceReviewTableRowsUseCompositeIDForSelectionAndKeepEvidenceIDForReview() {
    let sharedEvidenceID = UUID()
    let firstReport = AuditReport(
        id: UUID(),
        title: "Team Alpha",
        sourcePath: "/tmp/alpha.html",
        scanDirectoryPath: "/tmp/alpha",
        metrics: [],
        sections: []
    )
    let secondReport = AuditReport(
        id: UUID(),
        title: "Team Beta",
        sourcePath: "/tmp/beta.html",
        scanDirectoryPath: "/tmp/beta",
        metrics: [],
        sections: []
    )
    let section = ReportSection(kind: .text, title: "文本证据", summary: "")
    let firstRow = ReportTableRow(
        id: UUID(),
        columns: ["alpha.md", "beta.md", "0.90", "shared"],
        detailTitle: "alpha.md",
        detailBody: "shared",
        evidenceID: sharedEvidenceID,
        evidenceType: .text
    )
    let secondRow = ReportTableRow(
        id: UUID(),
        columns: ["gamma.md", "delta.md", "0.88", "shared"],
        detailTitle: "gamma.md",
        detailBody: "shared",
        evidenceID: sharedEvidenceID,
        evidenceType: .text
    )

    let rows = [
        EvidenceReviewTableRow(report: firstReport, section: section, row: firstRow),
        EvidenceReviewTableRow(report: secondReport, section: section, row: secondRow),
    ]

    #expect(Set(rows.map(\.id)).count == 2)
    #expect(Set(rows.map(\.target.id)) == Set(rows.map(\.id)))
    #expect(Set(rows.map(\.target.evidenceID)).count == 1)
}

@Test
func crossBatchSelectionIDMatchesEvidenceReviewTableRowID() {
    let evidenceID = UUID()
    let report = AuditReport(
        id: UUID(),
        title: "Cross Batch",
        sourcePath: "/tmp/cross.html",
        scanDirectoryPath: "/tmp/submissions",
        metrics: [],
        sections: []
    )
    let section = ReportSection(kind: .crossBatch, title: "跨批次", summary: "")
    let row = ReportTableRow(
        id: UUID(),
        columns: ["current.md", "history.md", "0.86", "same proof"],
        detailTitle: "current.md ↔ history.md",
        detailBody: "same proof",
        evidenceID: evidenceID,
        evidenceType: .crossBatch
    )

    let tableRow = EvidenceReviewTableRow(report: report, section: section, row: row)
    let selectionID = EvidenceReviewTableRow.selectionID(reportID: report.id, sectionKind: section.kind, row: row)

    #expect(selectionID == tableRow.id)
    #expect(selectionID == tableRow.target.id)
    #expect(selectionID != evidenceID)
    #expect(tableRow.target.evidenceID == evidenceID)
}

@Test
func evidenceImageCacheDecodesBase64ImageAsynchronously() async {
    let cache = EvidenceImageCache()
    let tinyImage = "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="

    let decoded = await cache.image(for: tinyImage, maxPixelSize: 32)
    let decodedAgain = await cache.image(for: tinyImage, maxPixelSize: 32)
    let cachedCount = await cache.cachedImageCount()
    _ = await cache.image(for: tinyImage, maxPixelSize: 64)
    let cachedCountAfterSecondSize = await cache.cachedImageCount()

    #expect(decoded != nil)
    #expect(decodedAgain != nil)
    #expect(decoded?.image.size.width == decodedAgain?.image.size.width)
    #expect(cachedCount == 1)
    #expect(cachedCountAfterSecondSize == 2)
}

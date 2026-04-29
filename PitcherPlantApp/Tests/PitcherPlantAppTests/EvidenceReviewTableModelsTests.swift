import Foundation
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
    #expect(sorted[0].whitelistStatusText == "白名单降权")
}

@Test
func evidenceReviewTableRowsUseUniqueSelectionIDsAcrossReports() {
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
    #expect(Set(rows.map(\.target.id)).count == 2)
    #expect(Set(rows.map(\.target.evidenceID)).count == 1)
}

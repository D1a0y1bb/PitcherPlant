import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func whitelistEvaluationMarksAndHidesAllEvidenceFamilies() throws {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-whitelist-eval", isDirectory: true)
    let sharedText = "官方题面公共说明用于环境连接和提交格式说明"
    let sharedCode = """
    func normalizeTemplate(_ value: String) -> String {
        let lowered = value.lowercased()
        return lowered.replacingOccurrences(of: "flag", with: "token")
    }
    """
    let image = ParsedImage(
        source: "pdf-page-1-image-1",
        perceptualHash: "abcdefabcdefabcd",
        averageHash: "1234561234561234",
        differenceHash: "9999999999999999",
        ocrPreview: "official screenshot",
        thumbnailBase64: ""
    )
    let documents = [
        ParsedDocument(
            url: root.appendingPathComponent("Alpha/shared-template/alpha.md"),
            filename: "alpha.md",
            ext: "md",
            content: "\(sharedText)\n```swift\n\(sharedCode)\n```",
            cleanText: TextNormalizer.clean(sharedText),
            codeBlocks: [sharedCode],
            author: "SharedEditor",
            lastModifiedBy: "SharedEditor",
            images: [image]
        ),
        ParsedDocument(
            url: root.appendingPathComponent("Beta/shared-template/beta.md"),
            filename: "beta.md",
            ext: "md",
            content: "\(sharedText)\n```swift\n\(sharedCode)\n```",
            cleanText: TextNormalizer.clean(sharedText),
            codeBlocks: [sharedCode],
            author: "SharedEditor",
            lastModifiedBy: "SharedEditor",
            images: [image]
        ),
    ]
    let rules = [
        WhitelistRule(type: .textSnippet, pattern: sharedText),
        WhitelistRule(type: .codeTemplate, pattern: "normalizeTemplate"),
        WhitelistRule(type: .imageHash, pattern: "abcdefabcdefabcd"),
        WhitelistRule(type: .metadata, pattern: "SharedEditor"),
        WhitelistRule(type: .pathPattern, pattern: "shared-template"),
        WhitelistRule(type: .filename, pattern: "alpha.md"),
        WhitelistRule(type: .author, pattern: "SharedEditor"),
    ]

    let markedText = try #require(TextSimilarityAnalyzer().analyze(
        documents: documents,
        threshold: 0.75,
        whitelistRules: rules,
        whitelistMode: .mark
    ).first)
    #expect(markedText.whitelistEvaluation?.matchedRuleType == .textSnippet)
    #expect(markedText.whitelistEvaluation?.hidden == false)
    #expect(markedText.score < 1.0)

    let markedCode = try #require(CodeSimilarityAnalyzer().analyze(
        documents: documents,
        whitelistRules: rules,
        whitelistMode: .mark
    ).first)
    #expect(markedCode.whitelistEvaluation?.matchedRuleType == .codeTemplate)

    let markedImage = try #require(ImageReuseAnalyzer().analyze(
        documents: documents,
        threshold: 5,
        whitelistRules: rules,
        whitelistMode: .mark
    ).first)
    #expect(markedImage.whitelistEvaluation?.matchedRuleType == .imageHash)

    let markedMetadata = try #require(MetadataCollisionAnalyzer().analyze(
        documents: documents,
        whitelistRules: rules,
        whitelistMode: .mark
    ).first)
    #expect(markedMetadata.whitelistEvaluation?.matchedRuleType == .metadata)
    let metadataRecord = try #require(RiskScoringService().evidenceRecords(
        textPairs: [],
        codePairs: [],
        imagePairs: [],
        metadataCollisions: [markedMetadata],
        dedupPairs: [],
        crossBatch: []
    ).first)
    #expect(metadataRecord.score < 0.70)
    #expect(try #require(RiskScoringService().aggregate(records: [metadataRecord]).first).assessment.score < 0.10)

    #expect(TextSimilarityAnalyzer().analyze(
        documents: documents,
        threshold: 0.75,
        whitelistRules: rules,
        whitelistMode: .hide
    ).isEmpty)
}

@Test
func evidenceSourceReferenceAndWhitelistStatusSurviveExports() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-source-reference-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let source = EvidenceSourceReference(
        filePath: "/tmp/writeups/alpha.md",
        pageNumber: 1,
        textRange: EvidenceTextRange(location: 12, length: 20),
        lineRange: EvidenceLineRange(start: 3, end: 5),
        imageIndex: 2,
        hashAnchor: "abcdefabcdefabcd",
        sourceLabel: "pdf-page-1-image-2"
    )
    let whitelist = WhitelistEvaluation(
        status: .marked,
        matchedRuleID: UUID(),
        matchedRuleType: .imageHash,
        reason: "命中公共截图 hash",
        scoreMultiplier: 0.35,
        hidden: false
    )
    let attachment = ReportAttachment(
        title: "截图",
        subtitle: "旧来源",
        body: "OCR preview",
        imageBase64: "ZmFrZQ==",
        sourceReference: source
    )
    let row = ReportTableRow(
        columns: ["alpha.md", "beta.md", "35%", "公共截图"],
        detailTitle: "alpha.md ↔ beta.md",
        detailBody: "白名单降权",
        badges: [],
        attachments: [attachment],
        evidenceID: UUID(),
        evidenceType: .image,
        riskAssessment: RiskAssessment(score: 0.35, reasons: ["图片复用"]),
        whitelistStatus: whitelist
    )
    let report = AuditReport(
        title: "来源引用导出",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [],
        sections: [
            ReportSection(
                kind: .image,
                title: "图片证据",
                summary: "导出测试",
                table: ReportTable(headers: ["A", "B", "Score", "Evidence"], rows: [row])
            )
        ]
    )

    let data = try JSONEncoder.pitcherPlantTest.encode(report)
    let decoded = try JSONDecoder.pitcherPlantTest.decode(AuditReport.self, from: data)
    #expect(decoded.sections.first?.table?.rows.first?.attachments.first?.sourceReference?.lineRange?.start == 3)
    #expect(decoded.sections.first?.table?.rows.first?.whitelistStatus?.matchedRuleType == .imageHash)

    let htmlURL = root.appendingPathComponent("report.html")
    let csvURL = root.appendingPathComponent("report.csv")
    let mdURL = root.appendingPathComponent("report.md")
    try ReportExporter.exportHTML(report: report, to: htmlURL)
    try ReportExporter.exportCSV(report: report, to: csvURL)
    try ReportExporter.exportMarkdown(report: report, to: mdURL)

    #expect(try String(contentsOf: htmlURL, encoding: .utf8).contains("pdf-page-1-image-2"))
    #expect(try String(contentsOf: csvURL, encoding: .utf8).contains("imageHash"))
    #expect(try String(contentsOf: mdURL, encoding: .utf8).contains("命中公共截图 hash"))
}

@Test
func recallStatsAndCalibrationMetricsExposeQualitySignals() throws {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-quality", isDirectory: true)
    let documents = (0..<120).map { index in
        ParsedDocument(
            url: root.appendingPathComponent("doc-\(index).md"),
            filename: "doc-\(index).md",
            ext: "md",
            content: index == 1 || index == 91 ? "shared credential replay persistence token" : "unique topic \(index) artifact \(index)",
            cleanText: index == 1 || index == 91 ? "shared credential replay persistence token" : "unique topic \(index) artifact \(index)",
            codeBlocks: [],
            author: "Author-\(index % 17)",
            images: []
        )
    }

    let result = CandidateRecallService(fullScanLimit: 20).candidatePairsWithStats(for: documents, purpose: .metadata)
    #expect(result.stats.strategy == .indexed)
    #expect(result.stats.elapsedMilliseconds >= 0)
    #expect(result.stats.possiblePairCount == 7_140)
    #expect(result.stats.candidatePairCount < result.stats.possiblePairCount)

    let metrics = CalibrationMetrics(
        expectedPairs: [CandidatePair(left: 1, right: 91)],
        detectedPairs: [CandidatePair(left: 1, right: 91)],
        totalPairCount: result.stats.possiblePairCount
    )
    #expect(metrics.recall == 1.0)
    #expect(metrics.truePositiveCount == 1)
    #expect(metrics.falseNegativeCount == 0)
    #expect(metrics.f1 >= 0.85)
}

private extension JSONEncoder {
    static var pitcherPlantTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pitcherPlantTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PitcherPlantApp

@Test
func riskScoringAggregatesEvidenceIntoHighRiskOverview() throws {
    let pair = SuspiciousPair(fileA: "alpha.md", fileB: "beta.md", score: 1.0, evidence: "shared exploit path")
    let records = RiskScoringService().evidenceRecords(
        textPairs: [pair],
        codePairs: [pair],
        imagePairs: [pair],
        metadataCollisions: [MetadataCollision(author: "SharedEditor", files: ["alpha.md", "beta.md"])],
        dedupPairs: [],
        crossBatch: [
            CrossBatchMatch(
                currentFile: "alpha.md",
                previousFile: "beta.md",
                previousScan: "previous-round",
                distance: 0,
                status: "疑似复用"
            )
        ]
    )

    let aggregate = try #require(RiskScoringService().aggregate(records: records).first)
    let overviewRow = try #require(EvidenceRecordFactory.overviewRows(from: [aggregate]).first)

    #expect(aggregate.assessment.level == .high)
    #expect(aggregate.assessment.evidenceCount == 5)
    #expect(Set(aggregate.evidenceTypes) == [.text, .code, .image, .metadata, .crossBatch])
    #expect(overviewRow.evidenceID == aggregate.id)
    #expect(overviewRow.riskAssessment?.level == .high)
}

@Test
func databasePersistsReviewsBatchesItemsAndDocumentFeatures() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-operational-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()

    let reportID = UUID()
    let evidenceID = UUID()
    let review = EvidenceReview(
        reportID: reportID,
        evidenceID: evidenceID,
        evidenceType: .text,
        decision: .confirmed,
        severity: .high,
        reviewerNote: "人工确认",
        isFavorite: true,
        isWatched: true
    )
    try await store.upsertEvidenceReview(review)

    let loadedReview = try #require(try await store.loadEvidenceReviews(reportID: reportID).first)
    #expect(loadedReview.decision == .confirmed)
    #expect(loadedReview.severity == .high)
    #expect(loadedReview.isFavorite)
    #expect(loadedReview.isWatched)

    let batch = SubmissionBatch(name: "round-one", sourcePath: root.path, destinationPath: root.path, itemCount: 1)
    let item = SubmissionItem(batchID: batch.id, teamName: "Alpha", rootPath: root.path, fileCount: 2, ignoredCount: 1)
    try await store.upsertSubmissionBatch(batch, items: [item])

    let loadedBatch = try #require(try await store.loadSubmissionBatches().first)
    let loadedItem = try #require(try await store.loadSubmissionItems(batchID: batch.id).first)
    #expect(loadedBatch.itemCount == 1)
    #expect(loadedItem.teamName == "Alpha")
    #expect(loadedItem.ignoredCount == 1)

    let document = parsedDocument(filename: "alpha.md", root: root, content: "shared risk evidence", author: "Alpha")
    try await store.upsertDocumentFeatures([DocumentFeature(document: document)])
    let feature = try #require(try await store.loadDocumentFeatures().first)
    #expect(feature.documentPath.hasSuffix("alpha.md"))
    #expect(feature.simhash.count == 16)

    try await store.deleteEvidenceReview(id: review.id)
    #expect(try await store.loadEvidenceReviews(reportID: reportID).isEmpty)
}

@Test
func evidenceReviewDecodesLegacyFavoriteWatchDefaults() throws {
    let json = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "reportID": "22222222-2222-2222-2222-222222222222",
      "evidenceID": "33333333-3333-3333-3333-333333333333",
      "evidenceType": "text",
      "decision": "pending",
      "severity": null,
      "reviewerNote": "",
      "createdAt": "2026-04-28T00:00:00Z",
      "updatedAt": "2026-04-28T00:00:00Z"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let review = try decoder.decode(EvidenceReview.self, from: Data(json.utf8))

    #expect(review.isFavorite == false)
    #expect(review.isWatched == false)
}

@Test
@MainActor
func evidenceFlagTogglesPreserveReviewDisposition() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-evidence-flags-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let appState = AppState(workspaceRoot: root)
    try await appState.database.prepare()

    let reportID = UUID()
    let evidenceID = UUID()
    let row = ReportTableRow(
        id: evidenceID,
        columns: ["alpha.md", "beta.md", "0.97", "shared exploit"],
        detailTitle: "alpha.md ↔ beta.md",
        detailBody: "shared exploit",
        evidenceID: evidenceID,
        evidenceType: .text,
        riskAssessment: RiskAssessment(score: 0.97, reasons: ["文本复用"])
    )
    let report = AuditReport(
        id: reportID,
        title: "Flag Report",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [],
        sections: [
            ReportSection(
                kind: .text,
                title: "文本证据",
                summary: "",
                table: ReportTable(headers: ["A", "B", "Score", "Detail"], rows: [row])
            )
        ]
    )
    try await appState.database.saveReport(report)
    try await appState.database.upsertEvidenceReview(EvidenceReview(
        reportID: reportID,
        evidenceID: evidenceID,
        evidenceType: .text,
        decision: .confirmed,
        severity: .high,
        reviewerNote: "保留这条备注"
    ))
    await appState.reload()
    appState.selectReport(reportID)
    appState.selectReportSection(.text)

    let selectedRow = try #require(appState.selectedReportRow)
    await appState.toggleFavorite(row: selectedRow)
    let favoriteReview = try #require(try await appState.database.loadEvidenceReviews(reportID: reportID).first)
    #expect(favoriteReview.decision == .confirmed)
    #expect(favoriteReview.severity == .high)
    #expect(favoriteReview.reviewerNote == "保留这条备注")
    #expect(favoriteReview.isFavorite)
    #expect(favoriteReview.isWatched == false)

    let reloadedRow = try #require(appState.selectedReportRow)
    await appState.toggleWatch(row: reloadedRow)
    let watchedReview = try #require(try await appState.database.loadEvidenceReviews(reportID: reportID).first)
    #expect(watchedReview.decision == .confirmed)
    #expect(watchedReview.severity == .high)
    #expect(watchedReview.reviewerNote == "保留这条备注")
    #expect(watchedReview.isFavorite)
    #expect(watchedReview.isWatched)
}

@Test
@MainActor
func evidenceCollectionFiltersFlagsAndRestoresSelection() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-evidence-collection-\(UUID().uuidString)", isDirectory: true)
    let appState = AppState(workspaceRoot: root)
    let favoriteReportID = UUID()
    let watchedReportID = UUID()
    let favoriteEvidenceID = UUID()
    let watchedEvidenceID = UUID()
    let favoriteRow = ReportTableRow(
        id: favoriteEvidenceID,
        columns: ["favorite.md", "source.md", "0.91", "favorite body"],
        detailTitle: "Favorite Evidence",
        detailBody: "favorite body",
        evidenceID: favoriteEvidenceID,
        evidenceType: .code
    )
    let watchedRow = ReportTableRow(
        id: watchedEvidenceID,
        columns: ["watched.md", "source.md", "0.88", "watched body"],
        detailTitle: "Watched Evidence",
        detailBody: "watched body",
        evidenceID: watchedEvidenceID,
        evidenceType: .image
    )
    appState.reports = [
        AuditReport(
            id: favoriteReportID,
            title: "Favorite Report",
            sourcePath: root.appendingPathComponent("favorite.html").path,
            scanDirectoryPath: root.path,
            metrics: [],
            sections: [
                ReportSection(kind: .code, title: "代码证据", summary: "", table: ReportTable(headers: [], rows: [favoriteRow]))
            ]
        ),
        AuditReport(
            id: watchedReportID,
            title: "Watched Report",
            sourcePath: root.appendingPathComponent("watched.html").path,
            scanDirectoryPath: root.path,
            metrics: [],
            sections: [
                ReportSection(kind: .image, title: "图片证据", summary: "", table: ReportTable(headers: [], rows: [watchedRow]))
            ]
        )
    ]
    appState.evidenceReviews = [
        EvidenceReview(reportID: favoriteReportID, evidenceID: favoriteEvidenceID, evidenceType: .code, isFavorite: true),
        EvidenceReview(reportID: watchedReportID, evidenceID: watchedEvidenceID, evidenceType: .image, isWatched: true)
    ]

    let favorites = appState.evidenceCollection(for: .favorites)
    let watched = appState.evidenceCollection(for: .watched)
    let all = appState.evidenceCollection(for: .all)

    #expect(favorites.map(\.row.evidenceID) == [favoriteEvidenceID])
    #expect(watched.map(\.row.evidenceID) == [watchedEvidenceID])
    #expect(all.count == 2)

    let watchedItem = try #require(watched.first)
    appState.selectEvidence(watchedItem)

    #expect(appState.selectedReportID == watchedReportID)
    #expect(appState.selectedReportSection == .image)
    #expect(appState.selectedReportRowID == watchedEvidenceID)
}

@Test
func submissionImportBuildsTeamItemsAndQueuedJobs() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-submissions-\(UUID().uuidString)", isDirectory: true)
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-submission-support-\(UUID().uuidString)", isDirectory: true)
    let alpha = root.appendingPathComponent("001 Alpha", isDirectory: true)
    let beta = root.appendingPathComponent("002 Beta", isDirectory: true)
    try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
    try "alpha writeup".write(to: alpha.appendingPathComponent("solve.md"), atomically: true, encoding: .utf8)
    try "ignored binary".write(to: alpha.appendingPathComponent("tool.exe"), atomically: true, encoding: .utf8)
    try "beta writeup".write(to: beta.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)

    let result = try SubmissionImportService().importPackage(at: root, into: support)
    let names = Set(result.items.map(\.teamName))

    #expect(result.batch.itemCount == 2)
    #expect(names == ["Alpha", "Beta"])
    #expect(result.items.first(where: { $0.teamName == "Alpha" })?.fileCount == 1)
    #expect(result.items.first(where: { $0.teamName == "Alpha" })?.ignoredCount == 1)

    let jobs = SubmissionImportService().auditJobs(
        from: result,
        outputDirectory: root.appendingPathComponent("reports", isDirectory: true),
        template: "{team}-audit-{date}.html"
    )

    #expect(jobs.count == 2)
    #expect(jobs.allSatisfy { $0.batchID == result.batch.id })
    #expect(jobs.contains { $0.configuration.reportNameTemplate.hasPrefix("Alpha-audit-") })
}

@Test
func submissionImportEnforcesZipLimitsAndScansFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-submission-zip-limits-\(UUID().uuidString)", isDirectory: true)
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-submission-support-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let zipURL = root.appendingPathComponent("submissions.zip")
    do {
        let archive = try Archive(url: zipURL, accessMode: .create, pathEncoding: nil)
        try addZipFile(to: archive, path: "001 Alpha/solve.md", contents: "ok")
        try addZipFile(to: archive, path: "001 Alpha/extra.txt", contents: "ok")
        try addZipFile(to: archive, path: "001 Alpha/huge.md", contents: String(repeating: "x", count: 32))
    }

    var options = SubmissionImportOptions()
    options.maxSingleFileBytes = 8
    options.maxScannedFileCount = 1
    let result = try SubmissionImportService().importPackage(at: zipURL, into: support, options: options)
    let item = try #require(result.items.first)

    #expect(item.teamName == "Alpha")
    #expect(item.fileCount == 1)
    #expect(result.issues.contains { $0.message.contains("单文件大小超过限制") })
    #expect(result.issues.contains { $0.message.contains("扫描文件数量超过限制") })
    #expect(FileManager.default.fileExists(atPath: result.batch.destinationPath + "/001 Alpha/huge.md") == false)
}

@Test
func auditJobRetryRequeuesAndPreservesAttemptHistory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-retry-\(UUID().uuidString)", isDirectory: true)
    var job = AuditJob(configuration: AuditConfiguration.defaults(for: root))
    job = job.failed("解析失败")

    let retried = job.retried()

    #expect(retried.status == .queued)
    #expect(retried.stage == .queued)
    #expect(retried.progress == 0)
    #expect(retried.errorMessage == nil)
    #expect(retried.attempt == 2)
    #expect(retried.events.last?.message.contains("第 2 次尝试") == true)
}

@Test
func whitelistSuggestionsCoverTemplatesHashesMetadataAndPaths() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-whitelist-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("shared-template", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let sharedLine = "官方题面公共说明用于环境连接和提交格式说明"
    let code = """
    func normalizeTemplate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }
        let lowered = trimmed.lowercased()
        return lowered.replacingOccurrences(of: "flag", with: "token")
    }
    """
    let image = ParsedImage(
        source: "common.png",
        perceptualHash: "abcdefabcdefabcd",
        averageHash: "1234561234561234",
        differenceHash: "9999999999999999",
        ocrPreview: "common screenshot",
        thumbnailBase64: "ZmFrZQ=="
    )
    let documents = (0..<4).map { index in
        ParsedDocument(
            url: root.appendingPathComponent("team-\(index).md"),
            filename: "team-\(index).md",
            ext: "md",
            content: "\(sharedLine)\n```swift\n\(code)\n```",
            cleanText: sharedLine,
            codeBlocks: [code],
            author: "SharedEditor",
            images: [image]
        )
    }

    let suggestions = WhitelistSuggestionService().suggest(from: documents)
    let types = Set(suggestions.map(\.rule.type))

    #expect(types.contains(.textSnippet))
    #expect(types.contains(.codeTemplate))
    #expect(types.contains(.imageHash))
    #expect(types.contains(.metadata))
    #expect(types.contains(.pathPattern))
}

@Test
func candidateRecallKeepsLargeRunsBelowFullPairCount() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-candidate-recall", isDirectory: true)
    let documents = (0..<6).map { index in
        ParsedDocument(
            url: root.appendingPathComponent("doc-\(index).md"),
            filename: "doc-\(index).md",
            ext: "md",
            content: "unique topic \(index) with enough terms for keyword signature",
            cleanText: "unique topic \(index) with enough terms for keyword signature",
            codeBlocks: [],
            author: "Author-\(index)",
            images: index == 0 || index == 5 ? [
                ParsedImage(
                    source: "shared.png",
                    perceptualHash: "abcdefabcdefabcd",
                    averageHash: "1234561234561234",
                    differenceHash: "9999999999999999",
                    ocrPreview: "",
                    thumbnailBase64: ""
                )
            ] : []
        )
    }

    let pairs = CandidateRecallService(fullScanLimit: 2).candidatePairs(for: documents, purpose: .image)

    #expect(pairs.contains(CandidatePair(left: 0, right: 5)))
    #expect(pairs.count < 15)
}

@Test
@MainActor
func exportFormatsIncludeReviewAndAttachments() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-export-formats-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let evidenceID = UUID()
    let review = EvidenceReview(
        reportID: UUID(),
        evidenceID: evidenceID,
        evidenceType: .image,
        decision: .confirmed,
        severity: .high,
        reviewerNote: "截图一致"
    )
    let row = ReportTableRow(
        id: evidenceID,
        columns: ["alpha.png", "beta.png", "98%", "same screenshot"],
        detailTitle: "alpha.png ↔ beta.png",
        detailBody: "图片 hash 完全一致",
        attachments: [ReportAttachment(title: "截图", subtitle: "page 1", body: "OCR", imageBase64: "ZmFrZQ==")],
        evidenceID: evidenceID,
        evidenceType: .image,
        riskAssessment: RiskAssessment(score: 0.98, reasons: ["图片复用"]),
        review: review
    )
    let report = AuditReport(
        title: "导出格式",
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

    let csvURL = root.appendingPathComponent("report.csv")
    let jsonURL = root.appendingPathComponent("report.json")
    let markdownURL = root.appendingPathComponent("report.md")
    let bundleURL = root.appendingPathComponent("bundle.zip")

    try ReportExporter.exportCSV(report: report, to: csvURL)
    try ReportExporter.exportJSON(report: report, to: jsonURL)
    try ReportExporter.exportMarkdown(report: report, to: markdownURL)
    try ReportExporter.exportEvidenceBundle(report: report, to: bundleURL)

    let csv = try String(contentsOf: csvURL, encoding: .utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AuditReport.self, from: Data(contentsOf: jsonURL))
    let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
    let listing = try processOutput("/usr/bin/unzip", arguments: ["-l", bundleURL.path])

    #expect(csv.contains("confirmed"))
    #expect(decoded.sections.first?.table?.rows.first?.review?.reviewerNote == "截图一致")
    #expect(markdown.contains("确认违规"))
    #expect(markdown.contains("高"))
    #expect(listing.contains("report.html"))
    #expect(listing.contains("report.md"))
    #expect(listing.contains("report.pdf"))
    #expect(listing.contains("evidence.csv"))
    #expect(listing.contains("report.json"))
    #expect(listing.contains("attachments/image-"))
}

@Test
@MainActor
func longReportPDFPreservesTailEvidenceInStandaloneAndBundle() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-long-pdf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let tailMarker = "PDF_TAIL_MARKER_\(UUID().uuidString)"
    let rows = (0..<180).map { index in
        ReportTableRow(
            columns: ["team-\(index)", "match-\(index)", "91%"],
            detailTitle: "长报告证据 \(index)",
            detailBody: index == 179 ? tailMarker : "重复证据说明 \(index) " + String(repeating: "detail ", count: 12),
            evidenceID: UUID(),
            evidenceType: .text,
            riskAssessment: RiskAssessment(score: 0.91, reasons: ["长报告测试"])
        )
    }
    let report = AuditReport(
        title: "长报告 PDF 导出",
        sourcePath: root.appendingPathComponent("report.html").path,
        scanDirectoryPath: root.path,
        metrics: [ReportMetric(title: "证据", value: "\(rows.count)", systemImage: "doc.text")],
        sections: [
            ReportSection(
                kind: .text,
                title: "文本相似",
                summary: "验证长报告尾部证据进入 PDF",
                table: ReportTable(headers: ["A", "B", "Score"], rows: rows)
            )
        ]
    )

    let pdfURL = root.appendingPathComponent("report.pdf")
    let bundleURL = root.appendingPathComponent("bundle.zip")
    let bundledPDFURL = root.appendingPathComponent("bundled-report.pdf")
    try ReportExporter.exportPDF(report: report, to: pdfURL)
    try ReportExporter.exportEvidenceBundle(report: report, to: bundleURL)

    let archive = try Archive(url: bundleURL, accessMode: .read, pathEncoding: nil)
    let entry = try #require(archive["report.pdf"])
    _ = try archive.extract(entry, to: bundledPDFURL)

    #expect(try pdfText(at: pdfURL).contains(tailMarker))
    #expect(try pdfText(at: bundledPDFURL).contains(tailMarker))
}

@Test
func fingerprintPackageRoundTripsAndCleanupByTag() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-fingerprint-package-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let records = [
        FingerprintRecord(
            filename: "alpha.md",
            ext: "md",
            author: "alice",
            size: 120,
            simhash: "1111111111111111",
            scanDir: "round-one",
            tags: ["course-2026"],
            batchName: "spring",
            challengeName: "web",
            teamName: "Alpha"
        ),
        FingerprintRecord(
            filename: "beta.md",
            ext: "md",
            author: "bob",
            size: 140,
            simhash: "2222222222222222",
            scanDir: "round-one"
        ),
        FingerprintRecord(
            filename: "broken.md",
            ext: "md",
            author: "",
            size: 0,
            simhash: "",
            scanDir: "round-one"
        ),
    ]

    let packageURL = root.appendingPathComponent("fingerprints.zip")
    let service = FingerprintPackageService()
    try service.exportPackage(records: records, to: packageURL, packageName: "Spring Round", tags: ["archive"])
    let imported = try service.importPackage(from: packageURL, additionalTags: ["imported"])

    #expect(imported.manifest.packageName == "Spring Round")
    #expect(imported.manifest.importedAt != nil)
    #expect(imported.manifest.source == packageURL.path)
    #expect(imported.manifest.recordCount == 2)
    #expect(imported.manifest.tags.contains("archive"))
    #expect(imported.manifest.tags.contains("imported"))
    #expect(imported.importedCount == 2)
    #expect(imported.skippedCount == 1)
    #expect(imported.records.allSatisfy { $0.tags?.contains("archive") == true })
    #expect(imported.records.allSatisfy { $0.tags?.contains("imported") == true })

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()
    try await store.upsertFingerprintRecords(imported.records)
    #expect(try await store.loadFingerprintRecords().count == 2)

    let deletedCount = try await store.deleteFingerprintRecords(tag: "imported")
    #expect(deletedCount == 2)
    #expect(try await store.loadFingerprintRecords().isEmpty)
}

private func parsedDocument(filename: String, root: URL, content: String, author: String) -> ParsedDocument {
    ParsedDocument(
        url: root.appendingPathComponent(filename),
        filename: filename,
        ext: URL(fileURLWithPath: filename).pathExtension.isEmpty ? "md" : URL(fileURLWithPath: filename).pathExtension,
        content: content,
        cleanText: TextNormalizer.clean(content),
        codeBlocks: CodeBlockExtractor.extract(from: content),
        author: author,
        images: []
    )
}

private func processOutput(_ executable: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "PitcherPlantTests.Process",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output]
        )
    }
    return output
}

private func addZipFile(to archive: Archive, path: String, contents: String) throws {
    let data = Data(contents.utf8)
    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
        let start = Int(position)
        let end = min(start + size, data.count)
        return data.subdata(in: start..<end)
    }
}

private func pdfText(at url: URL) throws -> String {
    guard let document = PDFDocument(url: url), let text = document.string else {
        throw NSError(
            domain: "PitcherPlantTests.PDF",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无法读取 PDF 文本：\(url.path)"]
        )
    }
    return text
}

import Foundation

struct AuditRunner {
    func run(
        configuration: AuditConfiguration,
        importedFingerprints: [FingerprintRecord],
        whitelistRules: [WhitelistRule],
        limits: AuditRunLimits = .defaults,
        progress: @escaping @MainActor @Sendable (AuditStage, String) async throws -> Void
    ) async throws -> AuditRunResult {
        let startedAt = Date()
        try await progress(.initialize, AuditStage.initialize.displayTitle)
        try Task.checkCancellation()

        let directoryURL = URL(fileURLWithPath: configuration.directoryPath)
        let ingestion = DocumentIngestionService(configuration: configuration)
        let documents = try ingestion.ingestDocuments(in: directoryURL)
        try await progress(.parsed, AuditStage.parsed.displayTitle)
        try await warnIfLargeRun(
            documents: documents,
            importedFingerprints: importedFingerprints,
            limits: limits,
            progress: progress
        )
        try Task.checkCancellation()

        let textAnalyzer = TextSimilarityAnalyzer()
        let textPairs = textAnalyzer.analyze(documents: documents, threshold: configuration.textThreshold)
        try await progress(.text, AuditStage.text.displayTitle)
        try Task.checkCancellation()

        let codePairs = CodeSimilarityAnalyzer().analyze(documents: documents)
        try await progress(.code, AuditStage.code.displayTitle)
        try Task.checkCancellation()

        let imagePairs = ImageReuseAnalyzer().analyze(documents: documents, threshold: configuration.imageThreshold)
        try await progress(.image, AuditStage.image.displayTitle)
        try Task.checkCancellation()

        let metadataCollisions = MetadataCollisionAnalyzer().analyze(documents: documents)
        try await progress(.metadata, AuditStage.metadata.displayTitle)
        try Task.checkCancellation()

        let dedupPairs = DedupAnalyzer().analyze(documents: documents, threshold: configuration.dedupThreshold)
        let currentFingerprints = FingerprintAnalyzer().buildRecords(documents: documents, scanDirectory: directoryURL.lastPathComponent)
        let crossBatch = CrossBatchReuseAnalyzer().analyze(
            current: currentFingerprints,
            historical: importedFingerprints,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode,
            threshold: configuration.simhashThreshold
        )
        try Task.checkCancellation()

        let title = directoryURL.lastPathComponent.isEmpty ? "PitcherPlant 报告" : directoryURL.lastPathComponent
        let timestamp = DateFormatter.pitcherPlantFileName.string(from: .now)
        let sourceURL = URL(fileURLWithPath: configuration.outputDirectoryPath)
            .appendingPathComponent(configuration.reportNameTemplate
                .replacingOccurrences(of: "{dir}", with: title)
                .replacingOccurrences(of: "{date}", with: timestamp))

        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let report = ReportAssembler().assemble(
            title: title,
            sourceURL: sourceURL,
            scanDirectory: directoryURL.path,
            textPairs: textPairs,
            codePairs: codePairs,
            imagePairs: imagePairs,
            metadataCollisions: metadataCollisions,
            dedupPairs: dedupPairs,
            fingerprints: currentFingerprints,
            crossBatch: crossBatch
        )
        try ReportExporter.exportHTML(report: report, to: sourceURL)
        let summary = AuditRunSummary(
            documentCount: documents.count,
            imageCount: documents.reduce(0) { $0 + $1.images.count },
            historicalFingerprintCount: importedFingerprints.count,
            duration: Date().timeIntervalSince(startedAt)
        )
        return AuditRunResult(report: report, fingerprints: currentFingerprints, summary: summary)
    }

    private func warnIfLargeRun(
        documents: [ParsedDocument],
        importedFingerprints: [FingerprintRecord],
        limits: AuditRunLimits,
        progress: @escaping @MainActor @Sendable (AuditStage, String) async throws -> Void
    ) async throws {
        let imageCount = documents.reduce(0) { $0 + $1.images.count }
        let overLimit = documents.count >= limits.largeDocumentCount
            || imageCount >= limits.largeImageCount
            || importedFingerprints.count >= limits.largeHistoricalFingerprintCount
        guard overLimit else {
            return
        }
        let message = "样本规模较大：文档 \(documents.count) 个、图片 \(imageCount) 张、历史指纹 \(importedFingerprints.count) 条，预计耗时较长。"
        try await progress(.parsed, message)
    }
}

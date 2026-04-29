import Foundation

struct AuditRunner {
    func run(
        configuration: AuditConfiguration,
        importedFingerprints: [FingerprintRecord],
        whitelistRules: [WhitelistRule],
        cachedDocumentFeatures: [DocumentFeature] = [],
        scanID: UUID? = nil,
        batchID: UUID? = nil,
        limits: AuditRunLimits = .defaults,
        progress: @escaping @MainActor @Sendable (AuditStage, String) async throws -> Void
    ) async throws -> AuditRunResult {
        let startedAt = Date()
        try await progress(.initialize, AuditStage.initialize.displayTitle)
        try Task.checkCancellation()

        let directoryURL = URL(fileURLWithPath: configuration.directoryPath)
        try await progress(.scan, AuditStage.scan.displayTitle)
        let ingestion = DocumentIngestionService(configuration: configuration)
        let documents = try ingestion.ingestDocuments(in: directoryURL)
        try await progress(.parse, "\(AuditStage.parse.displayTitle)：\(documents.count) 个文档")
        let featureResult = DocumentFeatureStore().buildFeatureResult(
            for: documents,
            scanID: scanID,
            batchID: batchID,
            cachedFeatures: cachedDocumentFeatures
        )
        let features = featureResult.features
        try await progress(.features, "生成特征：复用 \(featureResult.reusedCount)，重建 \(featureResult.rebuiltCount)")
        try await progress(.parsed, AuditStage.parsed.displayTitle)
        try await warnIfLargeRun(
            documents: documents,
            importedFingerprints: importedFingerprints,
            limits: limits,
            progress: progress
        )
        try Task.checkCancellation()
        let recallStats = recallStats(for: features)
        let candidatePairCount = recallStats.reduce(0) { $0 + $1.candidatePairCount }
        let skippedBucketCount = recallStats.reduce(0) { $0 + $1.skippedOversizedBucketCount }
        try await progress(.recall, "候选召回：\(candidatePairCount) 对候选，跳过 \(skippedBucketCount) 个大 bucket")
        try Task.checkCancellation()

        let textAnalyzer = TextSimilarityAnalyzer()
        let textPairs = textAnalyzer.analyze(
            documents: documents,
            threshold: configuration.textThreshold,
            features: features,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode
        )
        try await progress(.text, AuditStage.text.displayTitle)
        try Task.checkCancellation()

        let codePairs = CodeSimilarityAnalyzer().analyze(
            documents: documents,
            features: features,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode
        )
        try await progress(.code, AuditStage.code.displayTitle)
        try Task.checkCancellation()

        let imagePairs = ImageReuseAnalyzer().analyze(
            documents: documents,
            threshold: configuration.imageThreshold,
            features: features,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode
        )
        try await progress(.image, AuditStage.image.displayTitle)
        try Task.checkCancellation()

        let metadataCollisions = MetadataCollisionAnalyzer().analyze(
            documents: documents,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode
        )
        try await progress(.metadata, AuditStage.metadata.displayTitle)
        try Task.checkCancellation()

        let dedupPairs = DedupAnalyzer().analyze(
            documents: documents,
            threshold: configuration.dedupThreshold,
            features: features,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode
        )
        let currentFingerprints = FingerprintAnalyzer().buildRecords(documents: documents, scanDirectory: directoryURL.lastPathComponent)
        let crossBatch = CrossBatchReuseAnalyzer().analyze(
            current: currentFingerprints,
            historical: importedFingerprints,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode,
            threshold: configuration.simhashThreshold
        )
        try await progress(.crossBatch, AuditStage.crossBatch.displayTitle)
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
        try await progress(.aggregate, AuditStage.aggregate.displayTitle)
        try ReportExporter.exportHTML(report: report, to: sourceURL)
        try await progress(.export, AuditStage.export.displayTitle)
        let summary = AuditRunSummary(
            documentCount: documents.count,
            imageCount: documents.reduce(0) { $0 + $1.images.count },
            historicalFingerprintCount: importedFingerprints.count,
            duration: Date().timeIntervalSince(startedAt),
            recallStats: recallStats
        )
        return AuditRunResult(report: report, fingerprints: currentFingerprints, summary: summary, documentFeatureResult: featureResult)
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

    private func recallStats(for features: [DocumentFeature]) -> [RecallStats] {
        let service = CandidateRecallService()
        return [
            service.candidatePairsWithStats(for: features, purpose: .text).stats,
            service.candidatePairsWithStats(for: features, purpose: .code).stats,
            service.candidatePairsWithStats(for: features, purpose: .image).stats,
            service.candidatePairsWithStats(for: features, purpose: .dedup).stats,
            service.candidatePairsWithStats(for: features, purpose: .metadata).stats,
        ]
    }
}

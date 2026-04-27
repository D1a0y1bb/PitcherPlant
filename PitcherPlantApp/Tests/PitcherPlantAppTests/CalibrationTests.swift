import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func calibrationManifestThresholdsCoverCoreEvidenceTypes() throws {
    let manifest = try loadCalibrationManifest()

    for calibrationCase in manifest.cases {
        switch calibrationCase.kind {
        case .text:
            let documents = calibrationCase.parsedDocuments()
            let results = TextSimilarityAnalyzer().analyze(
                documents: documents,
                threshold: calibrationCase.threshold ?? 0.75
            )
            try assertExpectedPairs(calibrationCase.expectedPairs, in: results, minimumScore: calibrationCase.minimumScore)
            try assertQuality(calibrationCase, detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)), totalPairCount: pairCount(for: documents.count), lookup: lookup(for: documents))
        case .code:
            let documents = calibrationCase.parsedDocuments()
            let results = CodeSimilarityAnalyzer().analyze(documents: documents)
            try assertExpectedPairs(calibrationCase.expectedPairs, in: results, minimumScore: calibrationCase.minimumScore)
            try assertQuality(calibrationCase, detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)), totalPairCount: pairCount(for: documents.count), lookup: lookup(for: documents))
        case .image:
            let documents = calibrationCase.parsedDocuments()
            let results = ImageReuseAnalyzer().analyze(
                documents: documents,
                threshold: calibrationCase.imageThreshold ?? 5
            )
            try assertExpectedPairs(calibrationCase.expectedPairs, in: results, minimumScore: calibrationCase.minimumScore)
            try assertQuality(calibrationCase, detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)), totalPairCount: pairCount(for: documents.count), lookup: lookup(for: documents))
        case .dedup:
            let documents = calibrationCase.parsedDocuments()
            let results = DedupAnalyzer().analyze(
                documents: documents,
                threshold: calibrationCase.threshold ?? 0.85
            )
            try assertExpectedPairs(calibrationCase.expectedPairs, in: results, minimumScore: calibrationCase.minimumScore)
            try assertQuality(calibrationCase, detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)), totalPairCount: pairCount(for: documents.count), lookup: lookup(for: documents))
        case .crossBatch:
            let current = calibrationCase.currentFingerprintRecords()
            let historical = calibrationCase.historicalFingerprintRecords()
            let results = CrossBatchReuseAnalyzer().analyze(
                current: current,
                historical: historical,
                whitelistRules: [],
                whitelistMode: .mark,
                threshold: calibrationCase.simhashThreshold ?? 4
            )
            try assertExpectedCrossBatchPairs(calibrationCase.expectedPairs, in: results)
            let lookup = lookup(for: current + historical)
            try assertQuality(
                calibrationCase,
                detectedPairs: candidatePairs(from: results, lookup: lookup),
                totalPairCount: current.count * historical.count,
                lookup: lookup
            )
        }
    }
}

@Test
func documentFeatureStoreReusesInvalidatesAndIdentifiesCleanupCandidates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-feature-cache-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let alphaURL = root.appendingPathComponent("alpha.md")
    let betaURL = root.appendingPathComponent("beta.md")
    try "stable shared evidence token alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
    try "stale beta evidence".write(to: betaURL, atomically: true, encoding: .utf8)

    let builder = DocumentFeatureStore()
    let firstScan = UUID()
    let batchID = UUID()
    let alpha = parsedDocument(url: alphaURL, content: "stable shared evidence token alpha")
    let beta = parsedDocument(url: betaURL, content: "stale beta evidence")

    let first = builder.buildFeatureResult(for: [alpha, beta], scanID: firstScan, batchID: batchID, cachedFeatures: [])
    #expect(first.rebuiltCount == 2)
    #expect(first.reusedCount == 0)
    #expect(first.features.allSatisfy { $0.featureVersion == DocumentFeature.currentFeatureVersion })
    #expect(first.features.allSatisfy { $0.contentHash.isEmpty == false })

    let secondScan = UUID()
    let second = builder.buildFeatureResult(for: [alpha], scanID: secondScan, batchID: batchID, cachedFeatures: first.features)
    let reused = try #require(second.features.first)
    #expect(second.reusedCount == 1)
    #expect(second.rebuiltCount == 0)
    #expect(reused.scanID == secondScan)
    #expect(reused.batchID == batchID)
    #expect(second.orphanedFeatureIDs == [first.features[1].id])

    try "changed shared evidence token alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
    let changedAlpha = parsedDocument(url: alphaURL, content: "changed shared evidence token alpha")
    let third = builder.buildFeatureResult(for: [changedAlpha], scanID: UUID(), batchID: batchID, cachedFeatures: first.features)
    #expect(third.reusedCount == 0)
    #expect(third.rebuiltCount == 1)
    #expect(third.invalidatedFeatureIDs == [first.features[0].id])
}

private func loadCalibrationManifest() throws -> CalibrationManifest {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/calibration/manifest.json")
    let decoder = JSONDecoder()
    return try decoder.decode(CalibrationManifest.self, from: Data(contentsOf: url))
}

private func assertExpectedPairs(_ expectedPairs: [[String]], in results: [SuspiciousPair], minimumScore: Double?) throws {
    for expectedPair in expectedPairs {
        let left = try #require(expectedPair.first)
        let right = try #require(expectedPair.dropFirst().first)
        let result = try #require(results.first { pair in
            Set([pair.fileA, pair.fileB]) == Set([left, right])
        })
        if let minimumScore {
            #expect(result.score >= minimumScore)
        }
    }
}

private func assertExpectedCrossBatchPairs(_ expectedPairs: [[String]], in results: [CrossBatchMatch]) throws {
    for expectedPair in expectedPairs {
        let current = try #require(expectedPair.first)
        let previous = try #require(expectedPair.dropFirst().first)
        #expect(results.contains { match in
            match.currentFile == current && match.previousFile == previous
        })
    }
}

private func assertQuality(
    _ calibrationCase: CalibrationCase,
    detectedPairs: [CandidatePair],
    totalPairCount: Int,
    lookup: [String: Int]
) throws {
    let expectedPairs = try candidatePairs(from: calibrationCase.expectedPairs, lookup: lookup)
    let rejectedPairs = try candidatePairs(from: calibrationCase.rejectedPairs ?? [], lookup: lookup)
    let metrics = CalibrationMetrics(
        expectedPairs: expectedPairs,
        detectedPairs: detectedPairs,
        totalPairCount: totalPairCount
    )

    print("Calibration \(calibrationCase.id): precision=\(metrics.precision), recall=\(metrics.recall), f1=\(metrics.f1), TP=\(metrics.truePositiveCount), FP=\(metrics.falsePositiveCount), FN=\(metrics.falseNegativeCount)")

    #expect(metrics.precision >= (calibrationCase.minimumPrecision ?? 0.85))
    #expect(metrics.recall >= (calibrationCase.minimumRecall ?? 1.0))
    #expect(metrics.f1 >= (calibrationCase.minimumF1 ?? 0.85))

    let detected = Set(detectedPairs)
    for rejectedPair in rejectedPairs {
        #expect(detected.contains(rejectedPair) == false)
    }
}

private func candidatePairs(from results: [SuspiciousPair], lookup: [String: Int]) throws -> [CandidatePair] {
    try results.map { result in
        try candidatePair(left: result.fileA, right: result.fileB, lookup: lookup)
    }
}

private func candidatePairs(from results: [CrossBatchMatch], lookup: [String: Int]) throws -> [CandidatePair] {
    try results.map { result in
        try candidatePair(left: result.currentFile, right: result.previousFile, lookup: lookup)
    }
}

private func candidatePairs(from pairs: [[String]], lookup: [String: Int]) throws -> [CandidatePair] {
    try pairs.map { pair in
        let left = try #require(pair.first)
        let right = try #require(pair.dropFirst().first)
        return try candidatePair(left: left, right: right, lookup: lookup)
    }
}

private func candidatePair(left: String, right: String, lookup: [String: Int]) throws -> CandidatePair {
    let leftIndex = try #require(lookup[left])
    let rightIndex = try #require(lookup[right])
    return CandidatePair(left: min(leftIndex, rightIndex), right: max(leftIndex, rightIndex))
}

private func lookup(for documents: [ParsedDocument]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: documents.enumerated().map { ($0.element.filename, $0.offset) })
}

private func lookup(for records: [FingerprintRecord]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.filename, $0.offset) })
}

private func pairCount(for count: Int) -> Int {
    count * max(count - 1, 0) / 2
}

private func parsedDocument(url: URL, content: String) -> ParsedDocument {
    ParsedDocument(
        url: url,
        filename: url.lastPathComponent,
        ext: url.pathExtension.isEmpty ? "md" : url.pathExtension,
        content: content,
        cleanText: TextNormalizer.clean(content),
        codeBlocks: CodeBlockExtractor.extract(from: content),
        author: "",
        images: []
    )
}

private struct CalibrationManifest: Decodable {
    let version: Int
    let cases: [CalibrationCase]
}

private struct CalibrationCase: Decodable {
    enum Kind: String, Decodable {
        case text
        case code
        case image
        case dedup
        case crossBatch
    }

    let id: String
    let kind: Kind
    let threshold: Double?
    let imageThreshold: Int?
    let simhashThreshold: Int?
    let minimumScore: Double?
    let minimumPrecision: Double?
    let minimumRecall: Double?
    let minimumF1: Double?
    let expectedPairs: [[String]]
    let rejectedPairs: [[String]]?
    let documents: [CalibrationDocument]?
    let currentFingerprints: [CalibrationFingerprint]?
    let historicalFingerprints: [CalibrationFingerprint]?

    func parsedDocuments() -> [ParsedDocument] {
        (documents ?? []).map(\.parsedDocument)
    }

    func currentFingerprintRecords() -> [FingerprintRecord] {
        (currentFingerprints ?? []).map(\.record)
    }

    func historicalFingerprintRecords() -> [FingerprintRecord] {
        (historicalFingerprints ?? []).map(\.record)
    }
}

private struct CalibrationDocument: Decodable {
    let filename: String
    let ext: String
    let content: String
    let cleanText: String
    let codeBlocks: [String]?
    let images: [CalibrationImage]?

    var parsedDocument: ParsedDocument {
        ParsedDocument(
            url: URL(fileURLWithPath: "/tmp/pitcherplant-calibration").appendingPathComponent(filename),
            filename: filename,
            ext: ext,
            content: content,
            cleanText: cleanText,
            codeBlocks: codeBlocks ?? [],
            author: "",
            images: (images ?? []).map(\.parsedImage)
        )
    }
}

private struct CalibrationImage: Decodable {
    let source: String
    let perceptualHash: String
    let averageHash: String
    let differenceHash: String
    let ocrPreview: String

    var parsedImage: ParsedImage {
        ParsedImage(
            source: source,
            perceptualHash: perceptualHash,
            averageHash: averageHash,
            differenceHash: differenceHash,
            ocrPreview: ocrPreview,
            thumbnailBase64: ""
        )
    }
}

private struct CalibrationFingerprint: Decodable {
    let filename: String
    let ext: String
    let author: String
    let size: Int
    let simhash: String
    let scanDir: String

    var record: FingerprintRecord {
        FingerprintRecord(
            filename: filename,
            ext: ext,
            author: author,
            size: size,
            simhash: simhash,
            scanDir: scanDir
        )
    }
}

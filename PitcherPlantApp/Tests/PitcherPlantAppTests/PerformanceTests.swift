import Foundation
import GRDB
import Testing
@testable import PitcherPlantApp

@Test
func candidateRecallIndexesLargeSyntheticCorpusAndKeepsPositivePairs() throws {
    let baseline = try loadPerformanceBaseline().candidateRecall
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-performance", isDirectory: true)
    let positivePairs: Set<CandidatePair> = [
        CandidatePair(left: 12, right: 812),
        CandidatePair(left: 128, right: 913),
        CandidatePair(left: 240, right: 640),
    ]
    let documents = (0..<baseline.documentCount).map { index in
        syntheticDocument(index: index, root: root)
    }

    let result = CandidateRecallService().candidatePairsWithStats(for: documents, purpose: .text)
    let recalledPositiveCount = positivePairs.intersection(result.pairs).count
    let positiveRecall = Double(recalledPositiveCount) / Double(positivePairs.count)

    #expect(result.stats.strategy == .indexed)
    #expect(result.stats.possiblePairCount == baseline.documentCount * (baseline.documentCount - 1) / 2)
    #expect(result.stats.candidatePairCount <= baseline.maxCandidatePairs)
    #expect(result.stats.evaluatedPairCount <= baseline.maxEvaluatedPairs)
    #expect(positiveRecall >= baseline.minimumPositiveRecall)
}

@Test
func hammingBKTreeMatchesBruteForceResults() throws {
    let historical = (0..<2_500).map { index in
        FingerprintRecord(
            filename: "historical-\(index).md",
            ext: "md",
            author: "",
            size: index,
            simhash: String(format: "%016llx", UInt64(index * 17)),
            scanDir: "history"
        )
    }
    let target = String(format: "%016llx", UInt64(17 * 42))
    let threshold = 2

    let indexedIDs = Set(HammingBKTree(records: historical)
        .query(simhash: target, threshold: threshold)
        .map(\.record.id))
    let bruteForceIDs = Set(historical
        .filter { HashDistance.hamming(target, $0.simhash) <= threshold }
        .map(\.id))

    #expect(indexedIDs == bruteForceIDs)
}

@Test
func codeLineDiffBuilderUsesBoundedPreviewForHugeInputs() {
    let left = (0..<700).map { "left line \($0)" }.joined(separator: "\n")
    let right = (0..<700).map { "right line \($0)" }.joined(separator: "\n")

    let rows = CodeLineDiffBuilder.rows(left: left, right: right)

    #expect(rows.count <= 121)
    #expect(rows.first?.leftText.contains("快速预览") == true)
}

@Test
func documentFeatureDatabaseNormalizesCachedPayloadAndCleansStaleRows() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-feature-db-\(UUID().uuidString)", isDirectory: true)
    let support = root.appendingPathComponent(".pitcherplant-macos", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

    let dbURL = support.appendingPathComponent("PitcherPlantMac.sqlite")
    let cachedID = UUID()
    let cachedPayload = """
    {"author":"Alice","codeTokenSignature":[],"documentPath":"\(root.path)/cached.md","ext":"md","filename":"cached.md","id":"\(cachedID.uuidString)","imageHashPrefixes":[],"keywordSignature":["cached","evidence","token"],"simhash":"1111111111111111","textLength":21,"updatedAt":"2026-04-27T00:00:00Z"}
    """
    let cachedDB = try DatabaseQueue(path: dbURL.path)
    try await cachedDB.write { db in
        try db.execute(
            sql: """
            CREATE TABLE document_features (
                id TEXT PRIMARY KEY,
                document_path TEXT NOT NULL,
                simhash TEXT NOT NULL,
                text_length INTEGER NOT NULL,
                updated_at DATETIME NOT NULL,
                payload TEXT NOT NULL
            )
            """
        )
        try db.execute(
            sql: """
            INSERT INTO document_features (id, document_path, simhash, text_length, updated_at, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                cachedID.uuidString,
                "\(root.path)/cached.md",
                "1111111111111111",
                21,
                Date(timeIntervalSince1970: 1_777_248_000),
                cachedPayload
            ]
        )
    }

    let store = try DatabaseStore(rootDirectory: root)
    try await store.prepare()

    let cached = try #require(try await store.loadDocumentFeatures().first { $0.id == cachedID })
    #expect(cached.featureVersion == 1)
    #expect(cached.contentHash == "")
    #expect(cached.scanID == nil)
    #expect(cached.batchID == nil)

    let scanID = UUID()
    let batchID = UUID()
    let current = DocumentFeature(
        document: syntheticDocument(index: 0, root: root),
        scanID: scanID,
        batchID: batchID
    )
    try await store.upsertDocumentFeatures([current])

    let loadedForScan = try await store.loadDocumentFeatures(scanID: scanID)
    #expect(loadedForScan.map(\.id) == [current.id])
    #expect(loadedForScan.first?.sourceSize != nil)

    let deleted = try await store.cleanupDocumentFeatures(excludingDocumentPaths: [current.documentPath], batchID: batchID)
    #expect(deleted == 0)

    let removed = try await store.deleteDocumentFeatures(ids: [current.id, cachedID])
    #expect(removed == 2)
    #expect(try await store.loadDocumentFeatures().isEmpty)
}

private func syntheticDocument(index: Int, root: URL) -> ParsedDocument {
    let positiveTokens: String
    switch index {
    case 12, 812:
        positiveTokens = "shared-cobalt beacon persistence token credential replay"
    case 128, 913:
        positiveTokens = "shared-ssrf metadata endpoint temporary credential curl"
    case 240, 640:
        positiveTokens = "shared-deserialization gadget chain unsafe pickle payload"
    default:
        positiveTokens = "unique-\(index) topic-\(index) proof-\(index) artifact-\(index)"
    }
    let content = "\(positiveTokens) filler-\(index) marker-\(index) report-\(index)"
    return ParsedDocument(
        url: root.appendingPathComponent("doc-\(index).md"),
        filename: "doc-\(index).md",
        ext: "md",
        content: content,
        cleanText: content,
        codeBlocks: [],
        author: "Author-\(index)",
        images: []
    )
}

private func loadPerformanceBaseline() throws -> PerformanceBaselines {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
        let baselineURL = candidate
            .deletingLastPathComponent()
            .appendingPathComponent("Docs/performance-baselines.json")
        if FileManager.default.fileExists(atPath: baselineURL.path) {
            return try JSONDecoder().decode(PerformanceBaselines.self, from: Data(contentsOf: baselineURL))
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private struct PerformanceBaselines: Decodable {
    let candidateRecall: CandidateRecallBaseline
}

private struct CandidateRecallBaseline: Decodable {
    let documentCount: Int
    let maxCandidatePairs: Int
    let maxEvaluatedPairs: Int
    let minimumPositiveRecall: Double
}

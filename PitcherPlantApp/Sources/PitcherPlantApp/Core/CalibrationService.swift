import Foundation

enum AuditCalibrationPreset: String, CaseIterable, Identifiable, Sendable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: return "保守"
        case .balanced: return "均衡"
        case .aggressive: return "激进"
        }
    }

    var subtitle: String {
        switch self {
        case .conservative: return "提高阈值，优先降低误报"
        case .balanced: return "使用当前默认阈值"
        case .aggressive: return "降低文本阈值，提高可疑召回"
        }
    }
}

struct CalibrationEvaluationResult: Hashable, Sendable {
    struct Row: Identifiable, Hashable, Sendable {
        var id: EvidenceType { kind }
        var kind: EvidenceType
        var metrics: CalibrationMetrics
        var sampleCount: Int
        var thresholdDescription: String
        var evaluatedAt: Date
    }

    struct Summary: Hashable, Sendable {
        var sampleCount: Int
        var precision: Double
        var recall: Double
        var f1: Double
    }

    var rows: [Row]
    var summary: Summary
    var evaluatedAt: Date
}

struct CalibrationService {
    var manifestURL: URL
    var now: @Sendable () -> Date = { Date() }

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
    }

    func evaluate(configuration: AuditConfiguration) throws -> CalibrationEvaluationResult {
        let manifest = try loadManifest()
        let evaluatedAt = now()
        let rows = try manifest.cases.map { calibrationCase in
            try evaluate(calibrationCase, configuration: configuration, evaluatedAt: evaluatedAt)
        }
        let sampleCount = rows.reduce(0) { $0 + $1.sampleCount }
        let precision = average(rows.map(\.metrics.precision))
        let recall = average(rows.map(\.metrics.recall))
        let f1 = average(rows.map(\.metrics.f1))
        return CalibrationEvaluationResult(
            rows: rows,
            summary: CalibrationEvaluationResult.Summary(
                sampleCount: sampleCount,
                precision: precision,
                recall: recall,
                f1: f1
            ),
            evaluatedAt: evaluatedAt
        )
    }

    private func evaluate(
        _ calibrationCase: CalibrationCase,
        configuration: AuditConfiguration,
        evaluatedAt: Date
    ) throws -> CalibrationEvaluationResult.Row {
        switch calibrationCase.kind {
        case .text:
            let documents = calibrationCase.parsedDocuments()
            let results = TextSimilarityAnalyzer().analyze(
                documents: documents,
                threshold: calibrationCase.threshold ?? configuration.textThreshold
            )
            return try row(
                kind: .text,
                expectedPairs: calibrationCase.expectedPairs,
                detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)),
                totalPairCount: pairCount(for: documents.count),
                lookup: lookup(for: documents),
                sampleCount: documents.count,
                thresholdDescription: String(format: "文本 %.2f", calibrationCase.threshold ?? configuration.textThreshold),
                evaluatedAt: evaluatedAt
            )
        case .code:
            let documents = calibrationCase.parsedDocuments()
            let results = CodeSimilarityAnalyzer().analyze(documents: documents)
            return try row(
                kind: .code,
                expectedPairs: calibrationCase.expectedPairs,
                detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)),
                totalPairCount: pairCount(for: documents.count),
                lookup: lookup(for: documents),
                sampleCount: documents.count,
                thresholdDescription: "代码结构",
                evaluatedAt: evaluatedAt
            )
        case .image:
            let documents = calibrationCase.parsedDocuments()
            let threshold = calibrationCase.imageThreshold ?? configuration.imageThreshold
            let results = ImageReuseAnalyzer().analyze(documents: documents, threshold: threshold)
            return try row(
                kind: .image,
                expectedPairs: calibrationCase.expectedPairs,
                detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)),
                totalPairCount: pairCount(for: documents.count),
                lookup: lookup(for: documents),
                sampleCount: documents.count,
                thresholdDescription: "图片位差 \(threshold)",
                evaluatedAt: evaluatedAt
            )
        case .dedup:
            let documents = calibrationCase.parsedDocuments()
            let results = DedupAnalyzer().analyze(
                documents: documents,
                threshold: calibrationCase.threshold ?? configuration.dedupThreshold
            )
            return try row(
                kind: .dedup,
                expectedPairs: calibrationCase.expectedPairs,
                detectedPairs: candidatePairs(from: results, lookup: lookup(for: documents)),
                totalPairCount: pairCount(for: documents.count),
                lookup: lookup(for: documents),
                sampleCount: documents.count,
                thresholdDescription: String(format: "重复 %.2f", calibrationCase.threshold ?? configuration.dedupThreshold),
                evaluatedAt: evaluatedAt
            )
        case .crossBatch:
            let current = calibrationCase.currentFingerprintRecords()
            let historical = calibrationCase.historicalFingerprintRecords()
            let threshold = calibrationCase.simhashThreshold ?? configuration.simhashThreshold
            let results = CrossBatchReuseAnalyzer().analyze(
                current: current,
                historical: historical,
                whitelistRules: [],
                whitelistMode: configuration.whitelistMode,
                threshold: threshold
            )
            let lookup = lookup(for: current + historical)
            return try row(
                kind: .crossBatch,
                expectedPairs: calibrationCase.expectedPairs,
                detectedPairs: candidatePairs(from: results, lookup: lookup),
                totalPairCount: current.count * historical.count,
                lookup: lookup,
                sampleCount: current.count + historical.count,
                thresholdDescription: "SimHash 位差 \(threshold)",
                evaluatedAt: evaluatedAt
            )
        }
    }

    private func row(
        kind: EvidenceType,
        expectedPairs: [[String]],
        detectedPairs: [CandidatePair],
        totalPairCount: Int,
        lookup: [String: Int],
        sampleCount: Int,
        thresholdDescription: String,
        evaluatedAt: Date
    ) throws -> CalibrationEvaluationResult.Row {
        let metrics = CalibrationMetrics(
            expectedPairs: try candidatePairs(from: expectedPairs, lookup: lookup),
            detectedPairs: detectedPairs,
            totalPairCount: totalPairCount
        )
        return CalibrationEvaluationResult.Row(
            kind: kind,
            metrics: metrics,
            sampleCount: sampleCount,
            thresholdDescription: thresholdDescription,
            evaluatedAt: evaluatedAt
        )
    }

    private func loadManifest() throws -> CalibrationManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(CalibrationManifest.self, from: Data(contentsOf: manifestURL))
    }

    private func average(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

extension AuditConfiguration {
    func applyingCalibrationPreset(_ preset: AuditCalibrationPreset) -> AuditConfiguration {
        var copy = self
        switch preset {
        case .conservative:
            copy.textThreshold = min(textThreshold + 0.08, 0.98)
            copy.dedupThreshold = min(dedupThreshold + 0.05, 0.99)
            copy.imageThreshold = max(imageThreshold - 1, 1)
            copy.simhashThreshold = max(simhashThreshold - 1, 1)
        case .balanced:
            break
        case .aggressive:
            copy.textThreshold = max(textThreshold - 0.08, 0.35)
            copy.dedupThreshold = max(dedupThreshold - 0.05, 0.50)
            copy.imageThreshold = min(imageThreshold + 2, 32)
            copy.simhashThreshold = min(simhashThreshold + 2, 32)
        }
        return copy
    }
}

private struct CalibrationManifest: Decodable {
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
    let expectedPairs: [[String]]
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
        FingerprintRecord(filename: filename, ext: ext, author: author, size: size, simhash: simhash, scanDir: scanDir)
    }
}

private func lookup(for documents: [ParsedDocument]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: documents.enumerated().map { ($0.element.filename, $0.offset) })
}

private func lookup(for records: [FingerprintRecord]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.filename, $0.offset) })
}

private func pairCount(for documentCount: Int) -> Int {
    documentCount * max(documentCount - 1, 0) / 2
}

private func candidatePairs(from results: [SuspiciousPair], lookup: [String: Int]) -> [CandidatePair] {
    results.compactMap { result in
        guard let left = lookup[result.fileA], let right = lookup[result.fileB] else { return nil }
        return CandidatePair(left: min(left, right), right: max(left, right))
    }
}

private func candidatePairs(from results: [CrossBatchMatch], lookup: [String: Int]) -> [CandidatePair] {
    results.compactMap { result in
        guard let left = lookup[result.currentFile], let right = lookup[result.previousFile] else { return nil }
        return CandidatePair(left: min(left, right), right: max(left, right))
    }
}

private func candidatePairs(from pairs: [[String]], lookup: [String: Int]) throws -> [CandidatePair] {
    try pairs.map { pair in
        guard pair.count >= 2,
              let leftName = pair.first,
              let rightName = pair.dropFirst().first,
              let left = lookup[leftName],
              let right = lookup[rightName] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return CandidatePair(left: min(left, right), right: max(left, right))
    }
}

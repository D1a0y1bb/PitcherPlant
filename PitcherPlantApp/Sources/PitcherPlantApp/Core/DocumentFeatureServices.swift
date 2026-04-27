import Foundation

struct CandidatePair: Hashable, Sendable {
    let left: Int
    let right: Int
}

struct CandidateRecallResult: Sendable {
    let pairs: [CandidatePair]
    let stats: RecallStats
}

struct RecallStats: Hashable, Sendable {
    enum Strategy: String, Hashable, Sendable {
        case fullScan
        case indexed
    }

    let strategy: Strategy
    let documentCount: Int
    let possiblePairCount: Int
    let candidatePairCount: Int
    let evaluatedPairCount: Int
    let indexedBucketCount: Int
    let skippedOversizedBucketCount: Int
}

struct CandidateRecallService {
    enum Purpose: Sendable {
        case text
        case code
        case image
        case dedup
    }

    var fullScanLimit = 80
    var maxIndexedBucketSize = 160

    func candidatePairs(for documents: [ParsedDocument], purpose: Purpose) -> [CandidatePair] {
        candidatePairsWithStats(for: documents, purpose: purpose).pairs
    }

    func candidatePairsWithStats(for documents: [ParsedDocument], purpose: Purpose) -> CandidateRecallResult {
        let possiblePairCount = pairCount(for: documents.count)
        guard documents.count > 1 else {
            return CandidateRecallResult(
                pairs: [],
                stats: RecallStats(
                    strategy: .fullScan,
                    documentCount: documents.count,
                    possiblePairCount: possiblePairCount,
                    candidatePairCount: 0,
                    evaluatedPairCount: 0,
                    indexedBucketCount: 0,
                    skippedOversizedBucketCount: 0
                )
            )
        }
        if documents.count <= fullScanLimit {
            let pairs = allPairs(count: documents.count)
            return CandidateRecallResult(
                pairs: pairs,
                stats: RecallStats(
                    strategy: .fullScan,
                    documentCount: documents.count,
                    possiblePairCount: possiblePairCount,
                    candidatePairCount: pairs.count,
                    evaluatedPairCount: pairs.count,
                    indexedBucketCount: 0,
                    skippedOversizedBucketCount: 0
                )
            )
        }

        let features = documents.map { DocumentFeature(document: $0) }
        return candidatePairsWithStats(for: features, purpose: purpose, possiblePairCount: possiblePairCount)
    }

    func candidatePairsWithStats(for features: [DocumentFeature], purpose: Purpose) -> CandidateRecallResult {
        guard features.count > 1 else {
            return CandidateRecallResult(
                pairs: [],
                stats: RecallStats(
                    strategy: .indexed,
                    documentCount: features.count,
                    possiblePairCount: 0,
                    candidatePairCount: 0,
                    evaluatedPairCount: 0,
                    indexedBucketCount: 0,
                    skippedOversizedBucketCount: 0
                )
            )
        }
        return candidatePairsWithStats(for: features, purpose: purpose, possiblePairCount: pairCount(for: features.count))
    }

    private func candidatePairsWithStats(
        for features: [DocumentFeature],
        purpose: Purpose,
        possiblePairCount: Int
    ) -> CandidateRecallResult {
        if features.count <= fullScanLimit {
            let pairs = allPairs(count: features.count)
            return CandidateRecallResult(
                pairs: pairs,
                stats: RecallStats(
                    strategy: .fullScan,
                    documentCount: features.count,
                    possiblePairCount: possiblePairCount,
                    candidatePairCount: pairs.count,
                    evaluatedPairCount: pairs.count,
                    indexedBucketCount: 0,
                    skippedOversizedBucketCount: 0
                )
            )
        }

        let indexed = indexedPairs(for: features, purpose: purpose)
        var pairs = Set<CandidatePair>()

        func add(_ left: Int, _ right: Int) {
            guard left != right else { return }
            pairs.insert(CandidatePair(left: min(left, right), right: max(left, right)))
        }

        for pair in indexed.pairs {
            if shouldRecall(left: features[pair.left], right: features[pair.right], purpose: purpose) {
                add(pair.left, pair.right)
            }
        }

        let sortedPairs = pairs.sorted {
            if $0.left == $1.left {
                return $0.right < $1.right
            }
            return $0.left < $1.left
        }
        return CandidateRecallResult(
            pairs: sortedPairs,
            stats: RecallStats(
                strategy: .indexed,
                documentCount: features.count,
                possiblePairCount: possiblePairCount,
                candidatePairCount: sortedPairs.count,
                evaluatedPairCount: indexed.pairs.count,
                indexedBucketCount: indexed.bucketCount,
                skippedOversizedBucketCount: indexed.skippedOversizedBucketCount
            )
        )
    }

    private func allPairs(count: Int) -> [CandidatePair] {
        var pairs: [CandidatePair] = []
        for left in 0..<count {
            for right in 0..<count where right > left {
                pairs.append(CandidatePair(left: left, right: right))
            }
        }
        return pairs
    }

    private func pairCount(for documentCount: Int) -> Int {
        documentCount * max(documentCount - 1, 0) / 2
    }

    private func indexedPairs(
        for features: [DocumentFeature],
        purpose: Purpose
    ) -> (pairs: Set<CandidatePair>, bucketCount: Int, skippedOversizedBucketCount: Int) {
        var postings: [String: [Int]] = [:]
        for (index, feature) in features.enumerated() {
            for key in Set(bucketKeys(for: feature, purpose: purpose)) {
                postings[key, default: []].append(index)
            }
        }

        var pairs = Set<CandidatePair>()
        var bucketCount = 0
        var skippedOversizedBucketCount = 0

        for indices in postings.values {
            let bucket = Array(Set(indices)).sorted()
            guard bucket.count > 1 else { continue }
            bucketCount += 1
            guard bucket.count <= maxIndexedBucketSize else {
                skippedOversizedBucketCount += 1
                continue
            }
            for leftOffset in 0..<bucket.count {
                for rightOffset in (leftOffset + 1)..<bucket.count {
                    pairs.insert(CandidatePair(left: bucket[leftOffset], right: bucket[rightOffset]))
                }
            }
        }

        return (pairs, bucketCount, skippedOversizedBucketCount)
    }

    private func bucketKeys(for feature: DocumentFeature, purpose: Purpose) -> [String] {
        switch purpose {
        case .text, .dedup:
            return textBucketKeys(for: feature)
        case .code:
            return textBucketKeys(for: feature) + feature.codeTokenSignature.map { "code:\($0)" }
        case .image:
            return feature.imageHashPrefixes.map { "image:\($0)" }
        }
    }

    private func textBucketKeys(for feature: DocumentFeature) -> [String] {
        var keys: [String] = []
        let author = feature.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if author.isEmpty == false {
            keys.append("author:\(author)")
        }
        keys += simhashBandKeys(feature.simhash)
        keys += feature.keywordSignature.prefix(18).map { "keyword:\($0.lowercased())" }
        return keys
    }

    private func simhashBandKeys(_ simhash: String) -> [String] {
        let normalized = simhash.lowercased()
        guard normalized.count >= 16 else {
            return normalized.isEmpty ? [] : ["simhash:\(normalized)"]
        }
        let characters = Array(normalized)
        var keys: [String] = []
        for band in 0..<4 {
            let start = band * 4
            let value = String(characters[start..<(start + 4)])
            keys.append("simhash:\(band):\(value)")
        }
        return keys
    }

    private func shouldRecall(left: DocumentFeature, right: DocumentFeature, purpose: Purpose) -> Bool {
        switch purpose {
        case .text, .dedup:
            return textRecall(left: left, right: right)
        case .code:
            return textRecall(left: left, right: right)
                || Set(left.codeTokenSignature).intersection(right.codeTokenSignature).count >= 8
        case .image:
            return Set(left.imageHashPrefixes).intersection(right.imageHashPrefixes).isEmpty == false
        }
    }

    private func textRecall(left: DocumentFeature, right: DocumentFeature) -> Bool {
        if left.author.isEmpty == false && left.author == right.author {
            return true
        }
        if HashDistance.hamming(left.simhash, right.simhash) <= 12 {
            return true
        }
        let maxLength = max(left.textLength, right.textLength, 1)
        let lengthRatio = Double(abs(left.textLength - right.textLength)) / Double(maxLength)
        let sharedKeywords = Set(left.keywordSignature).intersection(right.keywordSignature).count
        return lengthRatio <= 0.35 && sharedKeywords >= 3
    }
}

struct DocumentFeatureBuildResult: Sendable {
    let features: [DocumentFeature]
    let reusedCount: Int
    let rebuiltCount: Int
    let invalidatedFeatureIDs: [UUID]
    let orphanedFeatureIDs: [UUID]
}

struct DocumentFeatureStore {
    var now: @Sendable () -> Date = { Date() }

    func buildFeatures(for documents: [ParsedDocument]) -> [DocumentFeature] {
        buildFeatureResult(for: documents).features
    }

    func buildFeatureResult(
        for documents: [ParsedDocument],
        scanID: UUID? = nil,
        batchID: UUID? = nil,
        cachedFeatures: [DocumentFeature] = []
    ) -> DocumentFeatureBuildResult {
        let buildDate = now()
        let cachedByPath = Dictionary(grouping: cachedFeatures, by: \.documentPath).compactMapValues { features in
            features.max(by: { $0.updatedAt < $1.updatedAt })
        }
        var features: [DocumentFeature] = []
        var reusedCount = 0
        var rebuiltCount = 0
        var invalidatedFeatureIDs: [UUID] = []
        let currentPaths = Set(documents.map { $0.url.path })

        for document in documents {
            let candidate = DocumentFeature(document: document, scanID: scanID, batchID: batchID, updatedAt: buildDate)
            if let cached = cachedByPath[candidate.documentPath], cached.isReusable(for: candidate) {
                features.append(cached.refreshed(scanID: scanID, batchID: batchID, updatedAt: buildDate))
                reusedCount += 1
            } else {
                if let cached = cachedByPath[candidate.documentPath] {
                    invalidatedFeatureIDs.append(cached.id)
                }
                features.append(candidate)
                rebuiltCount += 1
            }
        }

        let orphanedFeatureIDs = cachedFeatures
            .filter { feature in
                currentPaths.contains(feature.documentPath) == false
                    && (batchID == nil || feature.batchID == nil || feature.batchID == batchID)
            }
            .map(\.id)

        return DocumentFeatureBuildResult(
            features: features,
            reusedCount: reusedCount,
            rebuiltCount: rebuiltCount,
            invalidatedFeatureIDs: invalidatedFeatureIDs,
            orphanedFeatureIDs: orphanedFeatureIDs
        )
    }
}

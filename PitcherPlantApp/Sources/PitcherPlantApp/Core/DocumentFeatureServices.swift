import Foundation

struct CandidatePair: Hashable, Sendable {
    let left: Int
    let right: Int
}

struct CandidateRecallService {
    enum Purpose: Sendable {
        case text
        case code
        case image
        case dedup
    }

    var fullScanLimit = 80

    func candidatePairs(for documents: [ParsedDocument], purpose: Purpose) -> [CandidatePair] {
        guard documents.count > 1 else { return [] }
        if documents.count <= fullScanLimit {
            return allPairs(count: documents.count)
        }

        let features = documents.map { DocumentFeature(document: $0) }
        var pairs = Set<CandidatePair>()

        func add(_ left: Int, _ right: Int) {
            guard left != right else { return }
            pairs.insert(CandidatePair(left: min(left, right), right: max(left, right)))
        }

        for left in documents.indices {
            for right in documents.indices where right > left {
                if shouldRecall(left: features[left], right: features[right], purpose: purpose) {
                    add(left, right)
                }
            }
        }

        return pairs.sorted {
            if $0.left == $1.left {
                return $0.right < $1.right
            }
            return $0.left < $1.left
        }
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

struct DocumentFeatureStore {
    func buildFeatures(for documents: [ParsedDocument]) -> [DocumentFeature] {
        documents.map { DocumentFeature(document: $0) }
    }
}

import Foundation

struct TextSimilarityAnalyzer {
    func analyze(
        documents: [ParsedDocument],
        threshold: Double,
        features: [DocumentFeature]? = nil,
        whitelistRules: [WhitelistRule] = [],
        whitelistMode: AuditConfiguration.WhitelistMode = .mark
    ) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...5, charNGramRange: 3...7, wordWeight: 0.6, charWeight: 0.4)
        let candidates = candidatePairs(documents: documents, features: features, purpose: .text)
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        var pairs: [SuspiciousPair] = []

        for candidate in candidates {
            let left = candidate.left
            let right = candidate.right
            let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
            if score >= threshold {
                let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
                let pair = SuspiciousPair(
                    fileA: documents[left].filename,
                    fileB: documents[right].filename,
                    score: score,
                    evidence: evidence.summary,
                    detailLines: [
                        "文本相似度：\(String(format: "%.2f%%", score * 100))",
                        "最长公共片段：\(evidence.longestCommonLength)",
                        "AI 洗稿标记：\(score >= threshold && evidence.longestCommonLength < 20 ? "是" : "否")"
                    ],
                    attachments: [
                        ReportAttachment(
                            title: documents[left].filename,
                            subtitle: "上下文 A",
                            body: evidence.leftContext,
                            imageBase64: nil,
                            sourceReference: sourceReference(for: documents[left], label: "上下文 A", body: evidence.leftContext)
                        ),
                        ReportAttachment(
                            title: documents[right].filename,
                            subtitle: "上下文 B",
                            body: evidence.rightContext,
                            imageBase64: nil,
                            sourceReference: sourceReference(for: documents[right], label: "上下文 B", body: evidence.rightContext)
                        )
                    ]
                )
                if let evaluated = whitelist.apply(to: pair, type: .text, left: documents[left], right: documents[right]) {
                    pairs.append(evaluated)
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct DedupAnalyzer {
    func analyze(
        documents: [ParsedDocument],
        threshold: Double,
        features: [DocumentFeature]? = nil,
        whitelistRules: [WhitelistRule] = [],
        whitelistMode: AuditConfiguration.WhitelistMode = .mark
    ) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...3, charNGramRange: 3...5, wordWeight: 0.5, charWeight: 0.5)
        let candidates = candidatePairs(documents: documents, features: features, purpose: .dedup)
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        var pairs: [SuspiciousPair] = []
        for candidate in candidates {
            let left = candidate.left
            let right = candidate.right
            let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
            guard score >= threshold else { continue }
            let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
            let pair = SuspiciousPair(
                fileA: documents[left].filename,
                fileB: documents[right].filename,
                score: score,
                evidence: evidence.summary,
                detailLines: ["重复检测相似度：\(String(format: "%.2f%%", score * 100))", "最长公共片段：\(evidence.longestCommonLength)"],
                attachments: [
                    ReportAttachment(
                        title: documents[left].filename,
                        subtitle: "重复上下文 A",
                        body: evidence.leftContext,
                        imageBase64: nil,
                        sourceReference: sourceReference(for: documents[left], label: "重复上下文 A", body: evidence.leftContext)
                    ),
                    ReportAttachment(
                        title: documents[right].filename,
                        subtitle: "重复上下文 B",
                        body: evidence.rightContext,
                        imageBase64: nil,
                        sourceReference: sourceReference(for: documents[right], label: "重复上下文 B", body: evidence.rightContext)
                    )
                ]
            )
            if let evaluated = whitelist.apply(to: pair, type: .dedup, left: documents[left], right: documents[right]) {
                pairs.append(evaluated)
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct CodeSimilarityAnalyzer {
    func analyze(
        documents: [ParsedDocument],
        features: [DocumentFeature]? = nil,
        whitelistRules: [WhitelistRule] = [],
        whitelistMode: AuditConfiguration.WhitelistMode = .mark
    ) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let candidates = candidatePairs(documents: documents, features: features, purpose: .code)
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        var results: [SuspiciousPair] = []
        for candidate in candidates {
            let left = candidate.left
            let right = candidate.right
            let lhsBlocks = CodeBlockExtractor.candidates(from: documents[left].codeBlocks)
            let rhsBlocks = CodeBlockExtractor.candidates(from: documents[right].codeBlocks)
            guard !lhsBlocks.isEmpty, !rhsBlocks.isEmpty else { continue }

            guard let bestMatch = bestMatch(left: lhsBlocks, right: rhsBlocks) else {
                continue
            }

            if bestMatch.score >= 0.60 {
                let detailLines = [
                    "词元相似度：\(String(format: "%.2f%%", bestMatch.lexicalScore * 100))",
                    "结构相似度：\(String(format: "%.2f%%", bestMatch.structuralScore * 100))",
                    "共享标记数：\(bestMatch.sharedTokenCount)",
                    "共享覆盖率：\(String(format: "%.2f%%", bestMatch.sharedTokenRatio * 100))",
                    "命中片段：\(bestMatch.left.label) ↔ \(bestMatch.right.label)"
                ]
                let pair = SuspiciousPair(
                    fileA: documents[left].filename,
                    fileB: documents[right].filename,
                    score: bestMatch.score,
                    evidence: bestMatch.summary,
                    detailLines: detailLines,
                    attachments: [
                        ReportAttachment(
                            title: documents[left].filename,
                            subtitle: bestMatch.left.label,
                            body: bestMatch.left.preview,
                            imageBase64: nil,
                            sourceReference: sourceReference(for: documents[left], label: bestMatch.left.label, body: bestMatch.left.preview)
                        ),
                        ReportAttachment(
                            title: documents[right].filename,
                            subtitle: bestMatch.right.label,
                            body: bestMatch.right.preview,
                            imageBase64: nil,
                            sourceReference: sourceReference(for: documents[right], label: bestMatch.right.label, body: bestMatch.right.preview)
                        ),
                        ReportAttachment(
                            title: "评分细节",
                            subtitle: "词元 / 结构 / 共享标记",
                            body: detailLines.joined(separator: "\n"),
                            imageBase64: nil
                        ),
                    ]
                )
                if let evaluated = whitelist.apply(to: pair, type: .code, left: documents[left], right: documents[right]) {
                    results.append(evaluated)
                }
            }
        }
        return results.sorted(by: { $0.score > $1.score })
    }

    private func bestMatch(left: [CodeBlockCandidate], right: [CodeBlockCandidate]) -> CodeMatch? {
        var best: CodeMatch?

        for lhs in left {
            for rhs in right {
                let lexicalScore = JaccardSimilarity.score(
                    left: lhs.lexicalSignature,
                    right: rhs.lexicalSignature,
                    shingleSize: 5
                )
                let structuralScore = JaccardSimilarity.score(
                    left: lhs.structuralSignature,
                    right: rhs.structuralSignature,
                    shingleSize: 4
                )
                let lhsTokenSet = Set(lhs.lexicalTokens)
                let rhsTokenSet = Set(rhs.lexicalTokens)
                let sharedTokenCount = lhsTokenSet.intersection(rhsTokenSet).count
                let sharedTokenRatio = Double(sharedTokenCount) / Double(max(lhsTokenSet.union(rhsTokenSet).count, 1))
                let combinedScore = min(1.0, (0.40 * lexicalScore) + (0.40 * structuralScore) + (0.20 * sharedTokenRatio))
                let summary = [
                    "片段 \(lhs.label) ↔ \(rhs.label)",
                    "共享标记 \(sharedTokenCount)",
                    lhs.preview
                ].joined(separator: " | ")
                let candidate = CodeMatch(
                    score: combinedScore,
                    lexicalScore: lexicalScore,
                    structuralScore: structuralScore,
                    sharedTokenCount: sharedTokenCount,
                    sharedTokenRatio: sharedTokenRatio,
                    summary: summary,
                    left: lhs,
                    right: rhs
                )
                if let currentBest = best {
                    if candidate.score > currentBest.score {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }

        return best
    }
}

struct ImageReuseAnalyzer {
    func analyze(
        documents: [ParsedDocument],
        threshold: Int,
        features: [DocumentFeature]? = nil,
        whitelistRules: [WhitelistRule] = [],
        whitelistMode: AuditConfiguration.WhitelistMode = .mark
    ) -> [SuspiciousPair] {
        let candidates = candidatePairs(documents: documents, features: features, purpose: .image)
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        var pairs: [SuspiciousPair] = []
        for candidate in candidates {
            let left = candidate.left
            let right = candidate.right
            let leftImages = documents[left].images
            let rightImages = documents[right].images
            guard !leftImages.isEmpty, !rightImages.isEmpty else { continue }

            var examples: [(distance: Int, lhs: ParsedImage, rhs: ParsedImage)] = []
            for lhs in leftImages {
                for rhs in rightImages {
                    let distance = HashDistance.hamming(lhs.perceptualHash, rhs.perceptualHash)
                        + HashDistance.hamming(lhs.averageHash, rhs.averageHash)
                        + HashDistance.hamming(lhs.differenceHash, rhs.differenceHash)
                    if distance <= threshold * 3 {
                        examples.append((distance, lhs, rhs))
                    }
                }
            }
            if examples.isEmpty == false {
                let sortedExamples = examples.sorted(by: { $0.distance < $1.distance })
                let first = sortedExamples[0]
                let bestDistance = first.distance
                let normalized = 1.0 - (Double(bestDistance) / Double(max(threshold * 3, 1)))
                var attachments: [ReportAttachment] = []
                for (index, example) in sortedExamples.prefix(5).enumerated() {
                    attachments.append(ReportAttachment(
                        title: "\(documents[left].filename) 示例 \(index + 1)",
                        subtitle: example.lhs.source,
                        body: example.lhs.ocrPreview.isEmpty ? "未提取到 OCR 预览" : example.lhs.ocrPreview,
                        imageBase64: example.lhs.thumbnailBase64.isEmpty ? nil : example.lhs.thumbnailBase64,
                        sourceReference: sourceReference(for: documents[left], image: example.lhs, imageIndex: index + 1)
                    ))
                    attachments.append(ReportAttachment(
                        title: "\(documents[right].filename) 示例 \(index + 1)",
                        subtitle: example.rhs.source,
                        body: example.rhs.ocrPreview.isEmpty ? "未提取到 OCR 预览" : example.rhs.ocrPreview,
                        imageBase64: example.rhs.thumbnailBase64.isEmpty ? nil : example.rhs.thumbnailBase64,
                        sourceReference: sourceReference(for: documents[right], image: example.rhs, imageIndex: index + 1)
                    ))
                }
                let pair = SuspiciousPair(
                    fileA: documents[left].filename,
                    fileB: documents[right].filename,
                    score: max(0.0, normalized),
                    evidence: ["命中图片数：\(examples.count)", first.lhs.source, first.rhs.source, first.lhs.ocrPreview, first.rhs.ocrPreview].filter { !$0.isEmpty }.joined(separator: " | "),
                    detailLines: [
                        "命中图片数：\(examples.count)",
                        "pHash 位差：\(HashDistance.hamming(first.lhs.perceptualHash, first.rhs.perceptualHash))",
                        "aHash 位差：\(HashDistance.hamming(first.lhs.averageHash, first.rhs.averageHash))",
                        "dHash 位差：\(HashDistance.hamming(first.lhs.differenceHash, first.rhs.differenceHash))",
                        "最佳总位差：\(bestDistance)"
                    ],
                    attachments: attachments
                )
                if let evaluated = whitelist.apply(to: pair, type: .image, left: documents[left], right: documents[right]) {
                    pairs.append(evaluated)
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct MetadataCollisionAnalyzer {
    func analyze(
        documents: [ParsedDocument],
        whitelistRules: [WhitelistRule] = [],
        whitelistMode: AuditConfiguration.WhitelistMode = .mark
    ) -> [MetadataCollision] {
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        return Dictionary(grouping: documents.compactMap { document -> (String, String)? in
            let candidates = [document.author, document.lastModifiedBy]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let author = candidates.first else { return nil }
            let ignored = ["administrator", "admin", "user", "microsoft office user"]
            guard ignored.contains(author.lowercased()) == false else { return nil }
            return (author, document.filename)
        }, by: { $0.0 })
            .filter { $0.value.count > 1 }
            .compactMap { author, grouped -> MetadataCollision? in
                let files = grouped.map(\.1).sorted()
                let matchingDocuments = documents.filter { files.contains($0.filename) }
                let evaluation = whitelist.evaluateMetadata(author: author, files: files, documents: matchingDocuments)
                if evaluation.hidden {
                    return nil
                }
                return MetadataCollision(
                    author: author,
                    files: files,
                    whitelistEvaluation: evaluation.isClear ? nil : evaluation
                )
            }
            .sorted(by: { $0.files.count > $1.files.count })
    }
}

struct FingerprintAnalyzer {
    func buildRecords(documents: [ParsedDocument], scanDirectory: String) -> [FingerprintRecord] {
        documents.map { document in
            let source = inferredSourceFields(for: document, scanDirectory: scanDirectory)
            return FingerprintRecord(
                filename: document.filename,
                ext: document.ext,
                author: document.author,
                size: document.cleanText.count,
                simhash: SimHasher.hexHash(for: document.cleanText),
                scanDir: scanDirectory,
                batchName: scanDirectory,
                challengeName: source.challengeName,
                teamName: source.teamName
            )
        }
    }

    private func inferredSourceFields(for document: ParsedDocument, scanDirectory: String) -> (challengeName: String?, teamName: String?) {
        let parentName = document.url.deletingLastPathComponent().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard parentName.isEmpty == false, parentName != scanDirectory else {
            return (nil, nil)
        }

        let challengeName = document.url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            challengeName.isEmpty || challengeName == scanDirectory ? nil : challengeName,
            parentName
        )
    }
}

struct CrossBatchReuseAnalyzer {
    func analyze(
        current: [FingerprintRecord],
        historical: [FingerprintRecord],
        whitelistRules: [WhitelistRule],
        whitelistMode: AuditConfiguration.WhitelistMode,
        threshold: Int
    ) -> [CrossBatchMatch] {
        let whitelist = WhitelistEvaluationService(rules: whitelistRules, mode: whitelistMode)
        var matches: [CrossBatchMatch] = []
        for record in current {
            for previous in historical {
                let distance = HashDistance.hamming(record.simhash, previous.simhash)
                guard distance <= threshold else { continue }

                let evaluation = whitelist.evaluate(crossBatch: CrossBatchMatch(
                    currentFile: record.filename,
                    previousFile: previous.filename,
                    previousScan: previous.scanDir,
                    distance: distance,
                    status: "疑似复用",
                    sourceReportID: previous.sourceReportID,
                    batchName: previous.batchName,
                    teamName: previous.teamName,
                    challengeName: previous.challengeName,
                    currentBatchName: record.batchName,
                    currentTeamName: record.teamName,
                    currentChallengeName: record.challengeName,
                    currentSimhash: record.simhash,
                    historicalSimhash: previous.simhash,
                    currentAuthor: record.author,
                    historicalAuthor: previous.author,
                    tags: normalizedTags((record.tags ?? []) + (previous.tags ?? []))
                ))
                if evaluation.hidden {
                    continue
                }
                let status = evaluation.isClear ? "疑似复用" : "白名单(\(evaluation.matchedRuleType?.rawValue ?? "rule"))"
                matches.append(
                    CrossBatchMatch(
                        currentFile: record.filename,
                        previousFile: previous.filename,
                        previousScan: previous.scanDir,
                        distance: distance,
                        status: status,
                        sourceReportID: previous.sourceReportID,
                        batchName: previous.batchName,
                        teamName: previous.teamName,
                        challengeName: previous.challengeName,
                        currentBatchName: record.batchName,
                        currentTeamName: record.teamName,
                        currentChallengeName: record.challengeName,
                        currentSimhash: record.simhash,
                        historicalSimhash: previous.simhash,
                        currentAuthor: record.author,
                        historicalAuthor: previous.author,
                        tags: normalizedTags((record.tags ?? []) + (previous.tags ?? [])),
                        whitelistEvaluation: evaluation.isClear ? nil : evaluation
                    )
                )
            }
        }
        return matches.sorted(by: { $0.distance < $1.distance })
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false })).sorted()
    }
}

private func candidatePairs(
    documents: [ParsedDocument],
    features: [DocumentFeature]?,
    purpose: CandidateRecallService.Purpose
) -> [CandidatePair] {
    if let features, features.count == documents.count {
        return CandidateRecallService().candidatePairsWithStats(for: features, purpose: purpose).pairs
    }
    return CandidateRecallService().candidatePairs(for: documents, purpose: purpose)
}

private func sourceReference(for document: ParsedDocument, label: String, body: String) -> EvidenceSourceReference {
    let location = max(document.content.range(of: body)?.lowerBound.utf16Offset(in: document.content) ?? 0, 0)
    let length = min(max(body.count, 0), max(document.content.count - location, 0))
    return EvidenceSourceReference(
        filePath: document.url.path,
        textRange: EvidenceTextRange(location: location, length: length),
        lineRange: lineRange(in: document.content, matching: body),
        sourceLabel: label
    )
}

private func sourceReference(for document: ParsedDocument, image: ParsedImage, imageIndex: Int) -> EvidenceSourceReference {
    EvidenceSourceReference(
        filePath: document.url.path,
        pageNumber: pageNumber(from: image.source),
        imageIndex: imageIndex,
        hashAnchor: image.perceptualHash,
        sourceLabel: image.source
    )
}

private func lineRange(in content: String, matching body: String) -> EvidenceLineRange? {
    guard content.isEmpty == false else {
        return nil
    }
    let prefix: Substring
    if let range = content.range(of: body), body.isEmpty == false {
        prefix = content[..<range.lowerBound]
    } else {
        prefix = ""
    }
    let start = prefix.filter { $0 == "\n" }.count + 1
    let lineCount = max(body.filter { $0 == "\n" }.count + 1, 1)
    return EvidenceLineRange(start: start, end: start + lineCount - 1)
}

private func pageNumber(from source: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: #"page[-_ ]?(\d+)"#, options: [.caseInsensitive]) else {
        return nil
    }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    guard let match = regex.firstMatch(in: source, range: range),
          let numberRange = Range(match.range(at: 1), in: source) else {
        return nil
    }
    return Int(source[numberRange])
}

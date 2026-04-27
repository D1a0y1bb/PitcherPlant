import Foundation

struct TextSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...5, charNGramRange: 3...7, wordWeight: 0.6, charWeight: 0.4)
        var pairs: [SuspiciousPair] = []

        for left in documents.indices {
            for right in documents.indices where right > left {
                let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
                if score >= threshold {
                    let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
                    pairs.append(
                        SuspiciousPair(
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
                                ReportAttachment(title: documents[left].filename, subtitle: "上下文 A", body: evidence.leftContext, imageBase64: nil),
                                ReportAttachment(title: documents[right].filename, subtitle: "上下文 B", body: evidence.rightContext, imageBase64: nil)
                            ]
                        )
                    )
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct DedupAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...3, charNGramRange: 3...5, wordWeight: 0.5, charWeight: 0.5)
        var pairs: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
                let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
                guard score >= threshold else { continue }
                let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
                pairs.append(
                    SuspiciousPair(
                        fileA: documents[left].filename,
                        fileB: documents[right].filename,
                        score: score,
                        evidence: evidence.summary,
                        detailLines: ["重复检测相似度：\(String(format: "%.2f%%", score * 100))", "最长公共片段：\(evidence.longestCommonLength)"],
                        attachments: [
                            ReportAttachment(title: documents[left].filename, subtitle: "重复上下文 A", body: evidence.leftContext, imageBase64: nil),
                            ReportAttachment(title: documents[right].filename, subtitle: "重复上下文 B", body: evidence.rightContext, imageBase64: nil)
                        ]
                    )
                )
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct CodeSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        var results: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
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
                    results.append(
                        SuspiciousPair(
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
                                    imageBase64: nil
                                ),
                                ReportAttachment(
                                    title: documents[right].filename,
                                    subtitle: bestMatch.right.label,
                                    body: bestMatch.right.preview,
                                    imageBase64: nil
                                ),
                                ReportAttachment(
                                    title: "评分细节",
                                    subtitle: "词元 / 结构 / 共享标记",
                                    body: detailLines.joined(separator: "\n"),
                                    imageBase64: nil
                                ),
                            ]
                        )
                    )
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
    func analyze(documents: [ParsedDocument], threshold: Int) -> [SuspiciousPair] {
        var pairs: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
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
                            imageBase64: example.lhs.thumbnailBase64.isEmpty ? nil : example.lhs.thumbnailBase64
                        ))
                        attachments.append(ReportAttachment(
                            title: "\(documents[right].filename) 示例 \(index + 1)",
                            subtitle: example.rhs.source,
                            body: example.rhs.ocrPreview.isEmpty ? "未提取到 OCR 预览" : example.rhs.ocrPreview,
                            imageBase64: example.rhs.thumbnailBase64.isEmpty ? nil : example.rhs.thumbnailBase64
                        ))
                    }
                    pairs.append(
                        SuspiciousPair(
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
                    )
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct MetadataCollisionAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [MetadataCollision] {
        Dictionary(grouping: documents.compactMap { document -> (String, String)? in
            let candidates = [document.author, document.lastModifiedBy]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let author = candidates.first else { return nil }
            let ignored = ["administrator", "admin", "user", "microsoft office user"]
            guard ignored.contains(author.lowercased()) == false else { return nil }
            return (author, document.filename)
        }, by: { $0.0 })
            .filter { $0.value.count > 1 }
            .map { MetadataCollision(author: $0.key, files: $0.value.map(\.1).sorted()) }
            .sorted(by: { $0.files.count > $1.files.count })
    }
}

struct FingerprintAnalyzer {
    func buildRecords(documents: [ParsedDocument], scanDirectory: String) -> [FingerprintRecord] {
        documents.map { document in
            FingerprintRecord(
                filename: document.filename,
                ext: document.ext,
                author: document.author,
                size: document.cleanText.count,
                simhash: SimHasher.hexHash(for: document.cleanText),
                scanDir: scanDirectory
            )
        }
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
        var matches: [CrossBatchMatch] = []
        for record in current {
            for previous in historical {
                let distance = HashDistance.hamming(record.simhash, previous.simhash)
                guard distance <= threshold else { continue }

                let status = whitelistStatus(record: record, previous: previous, rules: whitelistRules)
                if whitelistMode == .hide, status != "疑似复用" {
                    continue
                }
                matches.append(
                    CrossBatchMatch(
                        currentFile: record.filename,
                        previousFile: previous.filename,
                        previousScan: previous.scanDir,
                        distance: distance,
                        status: status
                    )
                )
            }
        }
        return matches.sorted(by: { $0.distance < $1.distance })
    }

    private func whitelistStatus(record: FingerprintRecord, previous: FingerprintRecord, rules: [WhitelistRule]) -> String {
        for rule in rules {
            switch rule.type {
            case .author where !record.author.isEmpty && record.author == rule.pattern:
                return "白名单(author)"
            case .filename where record.filename == rule.pattern || previous.filename == rule.pattern:
                return "白名单(filename)"
            case .simhash where record.simhash == rule.pattern || previous.simhash == rule.pattern:
                return "白名单(simhash)"
            default:
                continue
            }
        }
        return "疑似复用"
    }
}


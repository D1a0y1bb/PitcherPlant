import Foundation

struct WhitelistEvaluationService {
    let rules: [WhitelistRule]
    let mode: AuditConfiguration.WhitelistMode

    init(rules: [WhitelistRule], mode: AuditConfiguration.WhitelistMode) {
        self.rules = rules
        self.mode = mode
    }

    func apply(
        to pair: SuspiciousPair,
        type: EvidenceType,
        left: ParsedDocument,
        right: ParsedDocument
    ) -> SuspiciousPair? {
        let evaluation = evaluate(pair: pair, type: type, left: left, right: right)
        if evaluation.hidden {
            return nil
        }
        return pair.withWhitelistEvaluation(evaluation)
    }

    func evaluate(
        pair: SuspiciousPair,
        type: EvidenceType,
        left: ParsedDocument,
        right: ParsedDocument
    ) -> WhitelistEvaluation {
        let documents = [left, right]
        switch type {
        case .text:
            return firstMatch(
                preferredTypes: [.textSnippet],
                fallbackTypes: [.filename, .pathPattern, .author],
                values: pairValues(pair, documents: documents) + documents.flatMap { [$0.content, $0.cleanText] }
            )
        case .code:
            return firstMatch(
                preferredTypes: [.codeTemplate],
                fallbackTypes: [.filename, .pathPattern, .author],
                values: pairValues(pair, documents: documents) + documents.flatMap(\.codeBlocks)
            )
        case .image:
            let imageValues = documents.flatMap(\.images).flatMap { image in
                [
                    image.source,
                    image.perceptualHash,
                    image.averageHash,
                    image.differenceHash,
                    image.ocrPreview,
                ]
            }
            return firstMatch(
                preferredTypes: [.imageHash],
                fallbackTypes: [.filename, .pathPattern],
                values: pairValues(pair, documents: documents) + imageValues
            )
        case .metadata:
            return evaluateMetadata(author: "", files: [pair.fileA, pair.fileB], documents: documents)
        case .dedup:
            return firstMatch(
                preferredTypes: [.filename, .pathPattern, .textSnippet],
                fallbackTypes: [.author],
                values: pairValues(pair, documents: documents)
            )
        case .crossBatch:
            return firstMatch(
                preferredTypes: [.filename, .simhash, .author],
                fallbackTypes: [.pathPattern, .metadata],
                values: pairValues(pair, documents: documents)
            )
        }
    }

    func evaluateMetadata(author: String, files: [String], documents: [ParsedDocument]) -> WhitelistEvaluation {
        let values = [author]
            + files
            + documents.flatMap { document in
                [
                    document.filename,
                    document.url.path,
                    document.author,
                    document.lastModifiedBy,
                ]
            }
        return firstMatch(
            preferredTypes: [.metadata],
            fallbackTypes: [.author, .filename, .pathPattern],
            values: values
        )
    }

    func evaluate(crossBatch match: CrossBatchMatch) -> WhitelistEvaluation {
        var values: [String] = []
        values.append(match.currentFile)
        values.append(match.previousFile)
        values.append(match.previousScan)
        values.append(match.sourceReportID?.uuidString ?? "")
        values.append(match.batchName ?? "")
        values.append(match.teamName ?? "")
        values.append(match.challengeName ?? "")
        values.append(match.currentBatchName ?? "")
        values.append(match.currentTeamName ?? "")
        values.append(match.currentChallengeName ?? "")
        values.append(match.currentSimhash ?? "")
        values.append(match.historicalSimhash ?? "")
        values.append(match.currentAuthor ?? "")
        values.append(match.historicalAuthor ?? "")
        values.append(contentsOf: match.tags)
        return firstMatch(
            preferredTypes: [.simhash, .filename, .author],
            fallbackTypes: [.metadata, .pathPattern, .textSnippet],
            values: values
        )
    }

    private func pairValues(_ pair: SuspiciousPair, documents: [ParsedDocument]) -> [String] {
        [
            pair.fileA,
            pair.fileB,
            pair.evidence,
        ] + pair.detailLines
            + pair.attachments.flatMap { [$0.title, $0.subtitle, $0.body, $0.sourceReference?.displayText ?? ""] }
            + documents.flatMap { [$0.filename, $0.url.path, $0.author, $0.lastModifiedBy] }
    }

    private func firstMatch(
        preferredTypes: [WhitelistRule.RuleType],
        fallbackTypes: [WhitelistRule.RuleType],
        values: [String]
    ) -> WhitelistEvaluation {
        let normalizedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        for type in preferredTypes + fallbackTypes {
            guard let rule = rules.first(where: { $0.type == type && matches(rule: $0, values: normalizedValues) }) else {
                continue
            }
            return evaluation(for: rule)
        }
        return WhitelistEvaluation()
    }

    private func matches(rule: WhitelistRule, values: [String]) -> Bool {
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pattern.isEmpty == false else { return false }
        switch rule.type {
        case .filename:
            return values.contains { value in
                value.caseInsensitiveCompare(pattern) == .orderedSame
                    || URL(fileURLWithPath: value).lastPathComponent.caseInsensitiveCompare(pattern) == .orderedSame
            }
        case .simhash, .imageHash:
            return values.contains { $0.localizedCaseInsensitiveContains(pattern) }
        case .pathPattern:
            return values.contains { value in
                value.localizedCaseInsensitiveContains(pattern)
            }
        case .author, .metadata:
            return values.contains { value in
                value.caseInsensitiveCompare(pattern) == .orderedSame
                    || value.localizedCaseInsensitiveContains(pattern)
            }
        case .textSnippet, .codeTemplate:
            return values.contains { value in
                value.localizedCaseInsensitiveContains(pattern)
            }
        }
    }

    private func evaluation(for rule: WhitelistRule) -> WhitelistEvaluation {
        let hidden = mode == .hide
        return WhitelistEvaluation(
            status: hidden ? .hidden : .marked,
            matchedRuleID: rule.id,
            matchedRuleType: rule.type,
            reason: "命中白名单规则 \(rule.type.displayTitle)：\(rule.pattern)",
            scoreMultiplier: hidden ? 0 : 0.35,
            hidden: hidden
        )
    }
}

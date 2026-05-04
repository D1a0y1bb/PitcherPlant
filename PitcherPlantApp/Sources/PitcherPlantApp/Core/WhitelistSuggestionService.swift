import Foundation

struct WhitelistSuggestion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let rule: WhitelistRule
    let reason: String
    let supportCount: Int
    var status: WhitelistSuggestionStatus

    init(rule: WhitelistRule, reason: String, supportCount: Int, status: WhitelistSuggestionStatus = .pending) {
        self.id = UUID.pitcherPlantStable(namespace: "whitelist-suggestion", components: [rule.type.rawValue, rule.pattern, reason])
        self.rule = rule
        self.reason = reason
        self.supportCount = supportCount
        self.status = status
    }
}

enum WhitelistSuggestionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case accepted
    case dismissed

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .pending: return "whitelist.suggestionStatus.pending"
        case .accepted: return "whitelist.suggestionStatus.accepted"
        case .dismissed: return "whitelist.suggestionStatus.dismissed"
        }
    }
}

struct WhitelistSuggestionService: Sendable {
    struct Reasons: Sendable {
        var textTemplate: String
        var codeTemplate: String
        var imageHash: String
        var metadata: String
        var pathPattern: String

        static let fallback = Reasons(
            textTemplate: "Repeated across multiple WriteUPs; suitable as a shared prompt or template snippet",
            codeTemplate: "Structured code template appears repeatedly",
            imageHash: "Image hash appears frequently; likely an official screenshot or shared asset",
            metadata: "Metadata appears across multiple files and is suitable for downgrading",
            pathPattern: "Directory names repeat and are suitable for import ignore or downgrade rules"
        )
    }

    var reasons: Reasons = .fallback

    func suggest(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        var suggestions: [WhitelistSuggestion] = []
        suggestions += suggestTextTemplates(from: documents)
        suggestions += suggestCodeTemplates(from: documents)
        suggestions += suggestImageHashes(from: documents)
        suggestions += suggestMetadata(from: documents)
        suggestions += suggestPathPatterns(from: documents)
        return suggestions.sorted {
            if $0.supportCount == $1.supportCount {
                return $0.rule.pattern < $1.rule.pattern
            }
            return $0.supportCount > $1.supportCount
        }
    }

    private func suggestTextTemplates(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let snippets = documents.flatMap { document in
            document.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 24 && $0.count <= 180 }
        }
        return groupedSuggestions(
            values: snippets,
            type: .textSnippet,
            minCount: 3,
            reason: reasons.textTemplate
        )
    }

    private func suggestCodeTemplates(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let blocks = documents.flatMap(\.codeBlocks)
            .map { block in
                CodeBlockExtractor.candidates(from: [block]).first?.structuralSignature ?? ""
            }
            .filter { $0.count >= 32 }
        return groupedSuggestions(
            values: blocks,
            type: .codeTemplate,
            minCount: 3,
            reason: reasons.codeTemplate
        )
    }

    private func suggestImageHashes(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let hashes = documents.flatMap(\.images).map(\.perceptualHash).filter { $0 != String(repeating: "0", count: 16) }
        return groupedSuggestions(
            values: hashes,
            type: .imageHash,
            minCount: 3,
            reason: reasons.imageHash
        )
    }

    private func suggestMetadata(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let authors = documents.flatMap { [$0.author, $0.lastModifiedBy] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        return groupedSuggestions(
            values: authors,
            type: .metadata,
            minCount: 4,
            reason: reasons.metadata
        )
    }

    private func suggestPathPatterns(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let paths = documents.map { URL(fileURLWithPath: $0.url.path).deletingLastPathComponent().lastPathComponent }
            .filter { $0.count >= 3 }
        return groupedSuggestions(
            values: paths,
            type: .pathPattern,
            minCount: 4,
            reason: reasons.pathPattern
        )
    }

    private func groupedSuggestions(values: [String], type: WhitelistRule.RuleType, minCount: Int, reason: String) -> [WhitelistSuggestion] {
        Dictionary(grouping: values, by: { $0 })
            .compactMap { value, matches -> WhitelistSuggestion? in
                guard matches.count >= minCount else { return nil }
                return WhitelistSuggestion(
                    rule: WhitelistRule(type: type, pattern: String(value.prefix(220))),
                    reason: reason,
                    supportCount: matches.count
                )
            }
    }
}

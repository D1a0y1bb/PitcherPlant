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

    var title: String {
        switch self {
        case .pending: return "待处理"
        case .accepted: return "已接受"
        case .dismissed: return "已忽略"
        }
    }
}

struct WhitelistSuggestionService {
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
            reason: "多份 WriteUP 反复出现，适合作为公共题面或模板片段"
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
            reason: "结构化代码模板重复出现"
        )
    }

    private func suggestImageHashes(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let hashes = documents.flatMap(\.images).map(\.perceptualHash).filter { $0 != String(repeating: "0", count: 16) }
        return groupedSuggestions(
            values: hashes,
            type: .imageHash,
            minCount: 3,
            reason: "图片 hash 高频重复，可能是官方截图或公共素材"
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
            reason: "元数据在多份文件中出现，适合降权处理"
        )
    }

    private func suggestPathPatterns(from documents: [ParsedDocument]) -> [WhitelistSuggestion] {
        let paths = documents.map { URL(fileURLWithPath: $0.url.path).deletingLastPathComponent().lastPathComponent }
            .filter { $0.count >= 3 }
        return groupedSuggestions(
            values: paths,
            type: .pathPattern,
            minCount: 4,
            reason: "路径目录名重复出现，适合做导入忽略或降权规则"
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

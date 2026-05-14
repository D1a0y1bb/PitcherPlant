import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct AuditAssistantConfiguration: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case timeoutSeconds
        case provider
        case apiProtocol
        case baseURL
        case model
        case maxOutputTokens
        case temperature
        case dataSharingLevel
        case credentialID
    }

    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case disabled
        case externalAPI

        static let allCases: [Mode] = [.disabled, .externalAPI]

        var id: String { rawValue }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            switch try container.decode(String.self) {
            case Self.externalAPI.rawValue:
                self = .externalAPI
            default:
                self = .disabled
            }
        }
    }

    enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
        case customOpenAICompatible
        case openAI
        case anthropic
        case gemini
        case deepSeek
        case kimi
        case miniMax

        static let allCases: [Provider] = [
            .customOpenAICompatible,
            .openAI,
            .anthropic,
            .gemini,
            .deepSeek,
            .kimi,
            .miniMax
        ]

        var id: String { rawValue }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Self(rawValue: try container.decode(String.self)) ?? .customOpenAICompatible
        }

        var defaultProtocol: APIProtocol {
            switch self {
            case .openAI:
                return .openAIResponses
            case .anthropic:
                return .anthropicMessages
            case .gemini:
                return .geminiGenerateContent
            case .miniMax:
                return .miniMaxChatCompletion
            case .customOpenAICompatible, .deepSeek, .kimi:
                return .openAIChatCompletions
            }
        }

        var supportedProtocols: [APIProtocol] {
            switch self {
            case .customOpenAICompatible:
                return [.openAIChatCompletions, .openAIResponses, .anthropicMessages]
            case .openAI:
                return [.openAIResponses, .openAIChatCompletions]
            case .anthropic:
                return [.anthropicMessages]
            case .gemini:
                return [.geminiGenerateContent]
            case .deepSeek, .kimi:
                return [.openAIChatCompletions]
            case .miniMax:
                return [.miniMaxChatCompletion]
            }
        }

        var defaultCredentialID: String {
            "pitcherplant.audit-assistant.\(rawValue)"
        }

        var defaultBaseURL: String {
            switch self {
            case .customOpenAICompatible:
                return "https://api.masterjie.eu.cc/v1"
            case .openAI:
                return "https://api.openai.com/v1"
            case .anthropic:
                return "https://api.anthropic.com/v1"
            case .gemini:
                return "https://generativelanguage.googleapis.com/v1beta"
            case .deepSeek:
                return "https://api.deepseek.com/v1"
            case .kimi:
                return "https://api.moonshot.cn/v1"
            case .miniMax:
                return "https://api.minimax.io/v1"
            }
        }

        var defaultModel: String {
            switch self {
            case .customOpenAICompatible:
                return "gpt-5.4-mini"
            case .openAI:
                return "gpt-5.2"
            case .anthropic:
                return "claude-sonnet-4-6"
            case .gemini:
                return "gemini-2.5-flash"
            case .deepSeek:
                return "deepseek-v4-flash"
            case .kimi:
                return "kimi-k2.5"
            case .miniMax:
                return "MiniMax-M2.7"
            }
        }

    }

    enum APIProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
        case openAIChatCompletions
        case openAIResponses
        case anthropicMessages
        case geminiGenerateContent
        case miniMaxChatCompletion

        static let allCases: [APIProtocol] = [
            .openAIChatCompletions,
            .openAIResponses,
            .anthropicMessages,
            .geminiGenerateContent,
            .miniMaxChatCompletion
        ]

        var id: String { rawValue }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Self(rawValue: try container.decode(String.self)) ?? .openAIChatCompletions
        }
    }

    enum DataSharingLevel: String, Codable, CaseIterable, Identifiable, Sendable {
        case summaryOnly
        case evidenceDetail
        case fullContext

        var id: String { rawValue }
    }

    var mode: Mode = .disabled
    var timeoutSeconds: Double = 20
    var provider: Provider = .customOpenAICompatible
    var apiProtocol: APIProtocol = Provider.customOpenAICompatible.defaultProtocol
    var baseURL: String = Provider.customOpenAICompatible.defaultBaseURL
    var model: String = Provider.customOpenAICompatible.defaultModel
    var maxOutputTokens: Int = 900
    var temperature: Double = 0.2
    var dataSharingLevel: DataSharingLevel = .evidenceDetail
    var credentialID: String = Provider.customOpenAICompatible.defaultCredentialID

    init(
        mode: Mode = .disabled,
        timeoutSeconds: Double = 20,
        provider: Provider = .customOpenAICompatible,
        apiProtocol: APIProtocol? = nil,
        baseURL: String = Provider.customOpenAICompatible.defaultBaseURL,
        model: String = Provider.customOpenAICompatible.defaultModel,
        maxOutputTokens: Int = 900,
        temperature: Double = 0.2,
        dataSharingLevel: DataSharingLevel = .evidenceDetail,
        credentialID: String? = nil
    ) {
        self.mode = mode
        self.timeoutSeconds = timeoutSeconds
        self.provider = provider
        self.apiProtocol = apiProtocol ?? provider.defaultProtocol
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.dataSharingLevel = dataSharingLevel
        self.credentialID = credentialID ?? provider.defaultCredentialID
    }

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? defaults.provider
        apiProtocol = try container.decodeIfPresent(APIProtocol.self, forKey: .apiProtocol) ?? provider.defaultProtocol
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? provider.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? defaults.maxOutputTokens
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        dataSharingLevel = try container.decodeIfPresent(DataSharingLevel.self, forKey: .dataSharingLevel) ?? defaults.dataSharingLevel
        credentialID = try container.decodeIfPresent(String.self, forKey: .credentialID) ?? provider.defaultCredentialID
    }

    var effectiveProtocol: APIProtocol {
        apiProtocol
    }

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }
}

struct AuditAssistantRequestContext: Codable, Hashable, Sendable {
    struct Risk: Codable, Hashable, Sendable {
        var score: Double
        var level: String
        var reasons: [String]
        var evidenceCount: Int
    }

    struct Review: Codable, Hashable, Sendable {
        var decision: String
        var severity: String?
        var note: String
        var isFavorite: Bool
        var isWatched: Bool
    }

    struct Badge: Codable, Hashable, Sendable {
        var title: String
        var tone: String
    }

    struct Attachment: Codable, Hashable, Sendable {
        var title: String
        var subtitle: String
        var bodyPreview: String
        var sourceReference: String
        var containsImagePreview: Bool
    }

    struct Whitelist: Codable, Hashable, Sendable {
        var status: String
        var reason: String
        var matchedRuleType: String?
        var scoreMultiplier: Double
    }

    var evidenceID: UUID
    var evidenceType: String
    var title: String
    var detail: String
    var columns: [String]
    var badges: [Badge]
    var attachments: [Attachment]
    var risk: Risk?
    var review: Review?
    var metadata: [String: String]
    var whitelist: Whitelist?
    var dataSharingLevel: AuditAssistantConfiguration.DataSharingLevel

    var requestHash: String {
        let data = (try? AuditAssistantCoding.encoder.encode(self)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct AuditAssistantResult: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var summary: String
    var triggerReasons: [String] = []
    var checkpoints: [String] = []
    var suggestedDecision: EvidenceDecision?
    var suggestedSeverity: RiskLevel?
    var noteDraft: String = ""
    var provider: AuditAssistantConfiguration.Provider
    var model: String
    var requestID: String?
    var tokenUsage: [String: Int] = [:]
    var requestHash: String = ""
    var createdAt: Date = .now

    var displayText: String {
        var parts = [summary]
        if triggerReasons.isEmpty == false {
            parts.append("触发原因：\(triggerReasons.joined(separator: "；"))")
        }
        if checkpoints.isEmpty == false {
            parts.append("建议核查：\(checkpoints.joined(separator: "；"))")
        }
        if noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            parts.append("备注草稿：\(noteDraft)")
        }
        return parts.joined(separator: "\n")
    }

    static func localFallback(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration = AuditAssistantConfiguration()
    ) -> AuditAssistantResult {
        let risk = row.riskAssessment?.level.title ?? "未评级"
        let reviewTitle = review?.decision.title ?? "待复核"
        let reasons = row.riskAssessment?.reasons ?? row.badges.map(\.title)
        let files = row.columns.prefix(2).joined(separator: " 与 ")
        let summary = "\(files) 命中\(reasons.joined(separator: "、"))，系统风险等级为\(risk)，当前复核状态为\(reviewTitle)。"
        return AuditAssistantResult(
            summary: summary,
            triggerReasons: reasons,
            checkpoints: ["核对详情面板中的上下文", "检查代码片段和附件来源", "确认是否已有白名单或人工复核记录"],
            suggestedDecision: review?.decision,
            suggestedSeverity: review?.severity ?? row.riskAssessment?.level,
            noteDraft: "\(summary) 建议继续人工复核原始证据。",
            provider: configuration.provider,
            model: configuration.effectiveModel,
            requestHash: AuditAssistantService.context(for: row, review: review, configuration: configuration).requestHash
        )
    }
}

struct AuditAssistantSuggestionRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let reportID: UUID
    let evidenceID: UUID
    var result: AuditAssistantResult
    var provider: AuditAssistantConfiguration.Provider
    var model: String
    var requestHash: String
    var createdAt: Date

    init(reportID: UUID, evidenceID: UUID, result: AuditAssistantResult) {
        self.id = UUID.pitcherPlantStable(namespace: "assistant-suggestion", components: [
            reportID.uuidString,
            evidenceID.uuidString,
            result.requestHash,
            result.createdAt.ISO8601Format()
        ])
        self.reportID = reportID
        self.evidenceID = evidenceID
        self.result = result
        self.provider = result.provider
        self.model = result.model
        self.requestHash = result.requestHash
        self.createdAt = result.createdAt
    }
}

struct AuditAssistantCredentialStore {
    static let legacyDefaultCredentialID = "pitcherplant.audit-assistant.default"

    enum CredentialError: LocalizedError {
        case missingCredential
        case encodingFailed
        case keychainFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingCredential:
                return "缺少审计助手 API Key。"
            case .encodingFailed:
                return "API Key 编码失败。"
            case .keychainFailure(let status):
                return "Keychain 操作失败：\(status)。"
            }
        }
    }

    private let service: String

    init(service: String = "com.pitcherplant.desktop.audit-assistant") {
        self.service = service
    }

    func save(_ apiKey: String, id: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), trimmed.isEmpty == false else {
            throw CredentialError.encodingFailed
        }
        try delete(id: id, ignoreMissing: true)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainFailure(status)
        }
    }

    func read(id: String, allowAuthenticationUI: Bool = false) throws -> String {
        let context = authenticationContext(allowAuthenticationUI: allowAuthenticationUI)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            throw CredentialError.missingCredential
        }
        guard status == errSecSuccess else {
            throw CredentialError.keychainFailure(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8), value.isEmpty == false else {
            throw CredentialError.missingCredential
        }
        return value
    }

    func exists(id: String) throws -> Bool {
        let context = authenticationContext(allowAuthenticationUI: false)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess || status == errSecInteractionNotAllowed {
            return true
        }
        if status == errSecItemNotFound {
            return false
        }
        throw CredentialError.keychainFailure(status)
    }

    @discardableResult
    func migrateLegacyDefaultCredentialIfNeeded(to id: String) throws -> Bool {
        let targetID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard targetID.isEmpty == false, targetID != Self.legacyDefaultCredentialID else {
            return false
        }
        guard try exists(id: targetID) == false, try exists(id: Self.legacyDefaultCredentialID) else {
            return false
        }
        let value = try read(id: Self.legacyDefaultCredentialID, allowAuthenticationUI: false)
        try save(value, id: targetID)
        return true
    }

    func delete(id: String) throws {
        try delete(id: id, ignoreMissing: false)
    }

    func deleteIfPresent(id: String) throws {
        try delete(id: id, ignoreMissing: true)
    }

    private func authenticationContext(allowAuthenticationUI: Bool) -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = allowAuthenticationUI == false
        return context
    }

    private func delete(id: String, ignoreMissing: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || (ignoreMissing && status == errSecItemNotFound) else {
            throw CredentialError.keychainFailure(status)
        }
    }
}

struct AuditAssistantService {
    enum AssistantError: LocalizedError, Equatable {
        case disabled
        case invalidEndpoint
        case missingModel
        case missingCredential
        case emptyResponse
        case timeout
        case httpStatus(Int, String)
        case unsupportedProviderProtocol(String, String)
        case unsupportedResponse(String)
        case responseTooLarge

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "审计助手已关闭。"
            case .invalidEndpoint:
                return "API 地址格式无效。"
            case .missingModel:
                return "缺少模型名称。"
            case .missingCredential:
                return "缺少审计助手 API Key。"
            case .emptyResponse:
                return "审计助手没有返回内容。"
            case .timeout:
                return "审计助手执行超时。"
            case .httpStatus(let status, let message):
                return "外部 API 返回 HTTP \(status)：\(message)"
            case .unsupportedProviderProtocol(let provider, let apiProtocol):
                return "\(provider) 不支持 \(apiProtocol) 接口协议。"
            case .unsupportedResponse(let message):
                return "无法解析外部 API 响应：\(message)"
            case .responseTooLarge:
                return "外部 API 响应过大。"
            }
        }
    }

    private let credentialStore: AuditAssistantCredentialStore
    private let urlSession: URLSession
    private let responseLimitBytes = 2_000_000

    init(
        credentialStore: AuditAssistantCredentialStore = AuditAssistantCredentialStore(),
        urlSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.urlSession = urlSession
    }

    func explanation(for row: ReportTableRow, review: EvidenceReview?, configuration: AuditAssistantConfiguration) async throws -> String {
        try await suggestion(for: row, review: review, configuration: configuration).displayText
    }

    func suggestion(for row: ReportTableRow, review: EvidenceReview?, configuration: AuditAssistantConfiguration) async throws -> AuditAssistantResult {
        switch configuration.mode {
        case .disabled:
            throw AssistantError.disabled
        case .externalAPI:
            return try await externalAPIExplanation(for: row, review: review, configuration: configuration)
        }
    }

    func localExplanation(for row: ReportTableRow, review: EvidenceReview?) -> String {
        localExplanation(for: row, review: review, configuration: AuditAssistantConfiguration()).displayText
    }

    func localExplanation(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration
    ) -> AuditAssistantResult {
        .localFallback(for: row, review: review, configuration: configuration)
    }

    static func context(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration
    ) -> AuditAssistantRequestContext {
        let effectiveReview = review ?? row.review
        let attachments: [AuditAssistantRequestContext.Attachment]
        switch configuration.dataSharingLevel {
        case .summaryOnly:
            attachments = []
        case .evidenceDetail, .fullContext:
            attachments = row.attachments.map { attachment in
                AuditAssistantRequestContext.Attachment(
                    title: attachment.title,
                    subtitle: attachment.subtitle,
                    bodyPreview: attachment.body.truncatedForAssistant(maxLength: configuration.dataSharingLevel == .fullContext ? 2_000 : 700),
                    sourceReference: attachment.sourceReferenceText,
                    containsImagePreview: attachment.imageBase64?.isEmpty == false
                )
            }
        }

        let detail: String
        switch configuration.dataSharingLevel {
        case .summaryOnly:
            detail = row.detailTitle
        case .evidenceDetail:
            detail = row.detailBody.truncatedForAssistant(maxLength: 2_500)
        case .fullContext:
            detail = row.detailBody.truncatedForAssistant(maxLength: 6_000)
        }

        return AuditAssistantRequestContext(
            evidenceID: row.evidenceID ?? row.id,
            evidenceType: row.evidenceType?.rawValue ?? "overview",
            title: row.detailTitle,
            detail: detail,
            columns: row.columns,
            badges: row.badges.map { .init(title: $0.title, tone: $0.tone.rawValue) },
            attachments: attachments,
            risk: row.riskAssessment.map {
                .init(score: $0.score, level: $0.level.rawValue, reasons: $0.reasons, evidenceCount: $0.evidenceCount)
            },
            review: effectiveReview.map {
                .init(
                    decision: $0.decision.rawValue,
                    severity: $0.severity?.rawValue,
                    note: $0.reviewerNote,
                    isFavorite: $0.isFavorite,
                    isWatched: $0.isWatched
                )
            },
            metadata: configuration.dataSharingLevel == .summaryOnly ? [:] : (row.metadata ?? [:]),
            whitelist: row.whitelistStatus.map {
                .init(
                    status: $0.status.rawValue,
                    reason: $0.reason,
                    matchedRuleType: $0.matchedRuleType?.rawValue,
                    scoreMultiplier: $0.scoreMultiplier
                )
            },
            dataSharingLevel: configuration.dataSharingLevel
        )
    }

    func payload(for row: ReportTableRow, review: EvidenceReview?) -> [String: String] {
        [
            "evidence_id": row.evidenceID?.uuidString ?? row.id.uuidString,
            "evidence_type": row.evidenceType?.rawValue ?? "overview",
            "title": row.detailTitle,
            "risk": row.riskAssessment?.level.rawValue ?? "none",
            "decision": review?.decision.rawValue ?? EvidenceDecision.pending.rawValue,
            "detail": row.detailBody,
        ]
    }

    func testConnection(configuration: AuditAssistantConfiguration, credentialOverride: String? = nil) async throws -> AuditAssistantResult {
        var testConfiguration = configuration
        testConfiguration.mode = .externalAPI
        let row = ReportTableRow(
            columns: ["connection-test.md"],
            detailTitle: "审计助手连接测试",
            detailBody: "请返回一段简短的连接测试结果。",
            badges: [ReportBadge(title: "连接测试", tone: .accent)],
            evidenceType: .metadata,
            riskAssessment: RiskAssessment(score: 0.1, reasons: ["连接测试"])
        )
        return try await externalAPIExplanation(for: row, review: nil, configuration: testConfiguration, credentialOverride: credentialOverride)
    }

    private func externalAPIExplanation(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration,
        credentialOverride: String? = nil
    ) async throws -> AuditAssistantResult {
        let context = Self.context(for: row, review: review, configuration: configuration)
        let credential = try credentialOverride ?? credential(for: configuration)
        let providerRequest = try AuditAssistantProviderAdapter.request(
            configuration: configuration,
            context: context,
            credential: credential
        )

        let (data, response) = try await urlSession.data(for: providerRequest.request)
        guard data.count <= responseLimitBytes else {
            throw AssistantError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantError.unsupportedResponse("缺少 HTTP 响应。")
        }
        let requestID = Self.requestID(from: httpResponse)
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AssistantError.httpStatus(httpResponse.statusCode, text.truncatedForAssistant(maxLength: 600))
        }

        let parsed = try AuditAssistantProviderAdapter.outputText(
            from: data,
            apiProtocol: providerRequest.apiProtocol
        )
        var result = Self.result(
            from: parsed.text,
            provider: configuration.provider,
            model: parsed.model ?? configuration.effectiveModel,
            requestID: requestID,
            tokenUsage: parsed.usage,
            requestHash: context.requestHash
        )
        if result.model.isEmpty {
            result.model = configuration.effectiveModel
        }
        return result
    }

    private func credential(for configuration: AuditAssistantConfiguration) throws -> String? {
        let credentialID = configuration.credentialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard credentialID.isEmpty == false else {
            throw AssistantError.missingCredential
        }
        do {
            try credentialStore.migrateLegacyDefaultCredentialIfNeeded(to: credentialID)
            return try credentialStore.read(id: credentialID)
        } catch AuditAssistantCredentialStore.CredentialError.missingCredential {
            throw AssistantError.missingCredential
        }
    }

    static func result(
        from rawText: String,
        provider: AuditAssistantConfiguration.Provider,
        model: String,
        requestID: String?,
        tokenUsage: [String: Int],
        requestHash: String
    ) -> AuditAssistantResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = try? AuditAssistantCoding.decoder.decode(AuditAssistantResult.self, from: Data(trimmed.utf8)) {
            var enriched = result
            enriched.provider = provider
            enriched.model = result.model.isEmpty ? model : result.model
            enriched.requestID = result.requestID ?? requestID
            enriched.tokenUsage = result.tokenUsage.isEmpty ? tokenUsage : result.tokenUsage
            enriched.requestHash = result.requestHash.isEmpty ? requestHash : result.requestHash
            return enriched
        }
        if let payload = try? AuditAssistantCoding.decoder.decode(ModelAssistantPayload.self, from: Data(trimmed.utf8)) {
            return AuditAssistantResult(
                summary: payload.summary,
                triggerReasons: payload.triggerReasons,
                checkpoints: payload.checkpoints,
                suggestedDecision: Self.decision(from: payload.suggestedDecision),
                suggestedSeverity: Self.severity(from: payload.suggestedSeverity),
                noteDraft: payload.noteDraft,
                provider: provider,
                model: model,
                requestID: requestID,
                tokenUsage: tokenUsage,
                requestHash: requestHash
            )
        }
        return AuditAssistantResult(
            summary: trimmed.isEmpty ? "审计助手没有返回可显示内容。" : trimmed,
            provider: provider,
            model: model,
            requestID: requestID,
            tokenUsage: tokenUsage,
            requestHash: requestHash
        )
    }

    private static func decision(from rawValue: String?) -> EvidenceDecision? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if let exact = EvidenceDecision(rawValue: normalized) {
            return exact
        }
        switch normalized {
        case "pending_review", "review", "manual_review", "needs_review", "建议人工复核", "人工复核", "待复核":
            return .pending
        case "confirm", "confirmed", "确认", "确认违规", "已确认":
            return .confirmed
        case "false_positive", "falsepositive", "误报", "排除", "排除风险":
            return .falsePositive
        case "ignore", "ignored", "忽略", "暂不处理":
            return .ignored
        case "whitelist", "whitelisted", "白名单", "加入白名单":
            return .whitelisted
        case "null", "none", "":
            return nil
        default:
            return nil
        }
    }

    private static func severity(from rawValue: String?) -> RiskLevel? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let exact = RiskLevel(rawValue: normalized) {
            return exact
        }
        switch normalized {
        case "无", "无风险", "none":
            return RiskLevel.none
        case "null", "":
            return nil
        case "低", "低风险", "low":
            return .low
        case "中", "中等", "中风险", "medium":
            return .medium
        case "高", "高风险", "high":
            return .high
        default:
            return nil
        }
    }

    private static func requestID(from response: HTTPURLResponse) -> String? {
        for key in ["request-id", "x-request-id", "cf-ray"] {
            if let value = response.value(forHTTPHeaderField: key), value.isEmpty == false {
                return value
            }
        }
        return nil
    }
}

struct AuditAssistantProviderRequest {
    var request: URLRequest
    var apiProtocol: AuditAssistantConfiguration.APIProtocol
}

struct AuditAssistantProviderOutput {
    var text: String
    var model: String?
    var usage: [String: Int]
}

enum AuditAssistantProviderAdapter {
    static func request(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let apiProtocol = configuration.effectiveProtocol
        guard configuration.provider.supportedProtocols.contains(apiProtocol) else {
            throw AuditAssistantService.AssistantError.unsupportedProviderProtocol(
                configuration.provider.rawValue,
                apiProtocol.rawValue
            )
        }

        switch apiProtocol {
        case .openAIChatCompletions:
            return try openAIChatRequest(configuration: configuration, context: context, credential: credential)
        case .openAIResponses:
            return try openAIResponsesRequest(configuration: configuration, context: context, credential: credential)
        case .anthropicMessages:
            return try anthropicRequest(configuration: configuration, context: context, credential: credential)
        case .geminiGenerateContent:
            return try geminiRequest(configuration: configuration, context: context, credential: credential)
        case .miniMaxChatCompletion:
            return try miniMaxRequest(configuration: configuration, context: context, credential: credential)
        }
    }

    static func outputText(
        from data: Data,
        apiProtocol: AuditAssistantConfiguration.APIProtocol
    ) throws -> AuditAssistantProviderOutput {
        switch apiProtocol {
        case .openAIChatCompletions, .miniMaxChatCompletion:
            let response = try AuditAssistantCoding.decoder.decode(ChatCompletionResponse.self, from: data)
            let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.isEmpty == false else { throw AuditAssistantService.AssistantError.emptyResponse }
            return AuditAssistantProviderOutput(text: text, model: response.model, usage: response.usage?.flattened ?? [:])
        case .openAIResponses:
            let response = try AuditAssistantCoding.decoder.decode(ResponsesAPIResponse.self, from: data)
            let parts = response.output.flatMap { $0.content ?? [] }.compactMap(\.text)
            let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { throw AuditAssistantService.AssistantError.emptyResponse }
            return AuditAssistantProviderOutput(text: text, model: response.model, usage: response.usage?.flattened ?? [:])
        case .anthropicMessages:
            let response = try AuditAssistantCoding.decoder.decode(AnthropicMessagesResponse.self, from: data)
            let text = response.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { throw AuditAssistantService.AssistantError.emptyResponse }
            return AuditAssistantProviderOutput(text: text, model: response.model, usage: response.usage?.flattened ?? [:])
        case .geminiGenerateContent:
            let response = try AuditAssistantCoding.decoder.decode(GeminiGenerateContentResponse.self, from: data)
            let text = response.candidates
                .flatMap { $0.content.parts }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { throw AuditAssistantService.AssistantError.emptyResponse }
            return AuditAssistantProviderOutput(text: text, model: response.modelVersion, usage: response.usageMetadata?.flattened ?? [:])
        }
    }

    private static func openAIChatRequest(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let model = try modelName(configuration)
        var request = try baseRequest(
            baseURL: configuration.effectiveBaseURL,
            path: "chat/completions",
            credential: credential,
            authorizationStyle: .bearer,
            timeout: configuration.timeoutSeconds
        )
        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: assistantSystemPrompt),
                .init(role: "user", content: prompt(for: context))
            ],
            maxTokens: configuration.maxOutputTokens,
            temperature: configuration.temperature
        )
        request.httpBody = try AuditAssistantCoding.encoder.encode(body)
        return AuditAssistantProviderRequest(request: request, apiProtocol: .openAIChatCompletions)
    }

    private static func openAIResponsesRequest(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let model = try modelName(configuration)
        var request = try baseRequest(
            baseURL: configuration.effectiveBaseURL,
            path: "responses",
            credential: credential,
            authorizationStyle: .bearer,
            timeout: configuration.timeoutSeconds
        )
        let body = ResponsesAPIRequest(
            model: model,
            input: "\(assistantSystemPrompt)\n\n\(prompt(for: context))",
            maxOutputTokens: configuration.maxOutputTokens,
            temperature: configuration.temperature
        )
        request.httpBody = try AuditAssistantCoding.encoder.encode(body)
        return AuditAssistantProviderRequest(request: request, apiProtocol: .openAIResponses)
    }

    private static func anthropicRequest(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let model = try modelName(configuration)
        var request = try baseRequest(
            baseURL: configuration.effectiveBaseURL,
            path: "messages",
            credential: credential,
            authorizationStyle: .anthropic,
            timeout: configuration.timeoutSeconds
        )
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body = AnthropicMessagesRequest(
            model: model,
            maxTokens: configuration.maxOutputTokens,
            system: assistantSystemPrompt,
            messages: [.init(role: "user", content: prompt(for: context))],
            temperature: configuration.temperature
        )
        request.httpBody = try AuditAssistantCoding.encoder.encode(body)
        return AuditAssistantProviderRequest(request: request, apiProtocol: .anthropicMessages)
    }

    private static func geminiRequest(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let model = try modelName(configuration)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var request = try baseRequest(
            baseURL: configuration.effectiveBaseURL,
            path: "models/\(encodedModel):generateContent",
            credential: credential,
            authorizationStyle: .gemini,
            timeout: configuration.timeoutSeconds
        )
        let body = GeminiGenerateContentRequest(
            contents: [.init(parts: [.init(text: "\(assistantSystemPrompt)\n\n\(prompt(for: context))")])],
            generationConfig: .init(
                temperature: configuration.temperature,
                maxOutputTokens: configuration.maxOutputTokens
            )
        )
        request.httpBody = try AuditAssistantCoding.encoder.encode(body)
        return AuditAssistantProviderRequest(request: request, apiProtocol: .geminiGenerateContent)
    }

    private static func miniMaxRequest(
        configuration: AuditAssistantConfiguration,
        context: AuditAssistantRequestContext,
        credential: String?
    ) throws -> AuditAssistantProviderRequest {
        let model = try modelName(configuration)
        var request = try baseRequest(
            baseURL: configuration.effectiveBaseURL,
            path: "text/chatcompletion_v2",
            credential: credential,
            authorizationStyle: .bearer,
            timeout: configuration.timeoutSeconds
        )
        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: assistantSystemPrompt),
                .init(role: "user", content: prompt(for: context))
            ],
            maxTokens: configuration.maxOutputTokens,
            temperature: configuration.temperature
        )
        request.httpBody = try AuditAssistantCoding.encoder.encode(body)
        return AuditAssistantProviderRequest(request: request, apiProtocol: .miniMaxChatCompletion)
    }

    private enum AuthorizationStyle {
        case bearer
        case anthropic
        case gemini
    }

    private static func baseRequest(
        baseURL: String,
        path: String,
        credential: String?,
        authorizationStyle: AuthorizationStyle,
        timeout: Double
    ) throws -> URLRequest {
        guard let url = endpoint(baseURL: baseURL, path: path) else {
            throw AuditAssistantService.AssistantError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard key.isEmpty == false else {
            throw AuditAssistantService.AssistantError.missingCredential
        }
        switch authorizationStyle {
        case .bearer:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }

    private static func endpoint(baseURL: String, path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard trimmed.isEmpty == false else {
            return nil
        }
        return URL(string: "\(trimmed)/\(path)")
    }

    private static func modelName(_ configuration: AuditAssistantConfiguration) throws -> String {
        let model = configuration.effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.isEmpty == false else {
            throw AuditAssistantService.AssistantError.missingModel
        }
        return model
    }

    private static let assistantSystemPrompt = """
    你是 PitcherPlant 的审计复核助手，只能辅助审计员理解证据，不能替代机器评分或人工结论。请基于输入 JSON 给出可执行的复核建议。不要声称已经确认违规，除非证据字段本身支持该判断。输出必须是 JSON 对象，字段为 summary、trigger_reasons、checkpoints、suggested_decision、suggested_severity、note_draft。suggested_decision 只能是 pending、confirmed、falsePositive、ignored、whitelisted 或 null；suggested_severity 只能是 none、low、medium、high 或 null。
    """

    private static func prompt(for context: AuditAssistantRequestContext) -> String {
        let contextJSON = (try? AuditAssistantCoding.string(from: context)) ?? "{}"
        return "请分析这条 PitcherPlant 审计证据，并返回规定 JSON。\n\n证据 JSON：\n\(contextJSON)"
    }
}

private struct ModelAssistantPayload: Decodable {
    var summary: String
    var triggerReasons: [String]
    var checkpoints: [String]
    var suggestedDecision: String?
    var suggestedSeverity: String?
    var noteDraft: String

    enum CodingKeys: String, CodingKey {
        case summary
        case triggerReasons = "trigger_reasons"
        case checkpoints
        case suggestedDecision = "suggested_decision"
        case suggestedSeverity = "suggested_severity"
        case noteDraft = "note_draft"
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var maxTokens: Int
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }

    var model: String?
    var choices: [Choice]
    var usage: TokenUsage?
}

private struct ResponsesAPIRequest: Encodable {
    var model: String
    var input: String
    var maxOutputTokens: Int
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
        case temperature
    }
}

private struct ResponsesAPIResponse: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            var text: String?
        }
        var content: [Content]?
    }

    var model: String?
    var output: [Output]
    var usage: TokenUsage?
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var maxTokens: Int
    var system: String
    var messages: [Message]
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case temperature
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct Content: Decodable {
        var text: String?
    }

    var model: String?
    var content: [Content]
    var usage: TokenUsage?
}

private struct GeminiGenerateContentRequest: Encodable {
    struct Content: Encodable {
        var parts: [Part]
    }

    struct Part: Encodable {
        var text: String
    }

    struct GenerationConfig: Encodable {
        var temperature: Double
        var maxOutputTokens: Int
    }

    var contents: [Content]
    var generationConfig: GenerationConfig
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                var text: String?
            }
            var parts: [Part]
        }
        var content: Content
    }

    var candidates: [Candidate]
    var modelVersion: String?
    var usageMetadata: TokenUsage?
}

private struct TokenUsage: Decodable, Hashable {
    private var values: [String: Int] = [:]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var parsed: [String: Int] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(Int.self, forKey: key) {
                parsed[key.stringValue] = value
            }
        }
        values = parsed
    }

    var flattened: [String: Int] {
        values
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum AuditAssistantCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func string<T: Encodable>(from value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private extension String {
    func truncatedForAssistant(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        let end = index(startIndex, offsetBy: maxLength)
        return "\(self[..<end])…"
    }
}

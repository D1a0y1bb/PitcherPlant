import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func assistantContextIncludesReviewRiskMetadataAndWhitelistWithoutImageData() throws {
    let row = assistantFixtureRow()
    let review = EvidenceReview(
        reportID: UUID(),
        evidenceID: try #require(row.evidenceID),
        evidenceType: .metadata,
        decision: .confirmed,
        severity: .high,
        reviewerNote: "人工确认可疑"
    )
    let context = AuditAssistantService.context(
        for: row,
        review: review,
        configuration: AuditAssistantConfiguration(dataSharingLevel: .evidenceDetail)
    )

    #expect(context.evidenceID == row.evidenceID)
    #expect(context.risk?.level == RiskLevel.high.rawValue)
    #expect(context.risk?.reasons == ["共享作者", "跨批次命中"])
    #expect(context.review?.decision == EvidenceDecision.confirmed.rawValue)
    #expect(context.review?.note == "人工确认可疑")
    #expect(context.metadata["author"] == "alice")
    #expect(context.whitelist?.status == WhitelistEvaluation.Status.marked.rawValue)
    #expect(context.attachments.first?.containsImagePreview == true)

    let encoded = try JSONEncoder().encode(context)
    let text = String(data: encoded, encoding: .utf8) ?? ""
    #expect(text.contains("R0lGODlh") == false)
}

@Test
func assistantContextRespectsDataSharingLevels() throws {
    let row = assistantFixtureRow()

    let summary = AuditAssistantService.context(
        for: row,
        review: nil,
        configuration: AuditAssistantConfiguration(dataSharingLevel: .summaryOnly)
    )
    #expect(summary.detail == row.detailTitle)
    #expect(summary.attachments.isEmpty)
    #expect(summary.metadata.isEmpty)

    let detail = AuditAssistantService.context(
        for: row,
        review: nil,
        configuration: AuditAssistantConfiguration(dataSharingLevel: .evidenceDetail)
    )
    #expect(detail.detail.contains("两份 WriteUP"))
    #expect(detail.attachments.first?.bodyPreview == "附件摘要")
    #expect(detail.attachments.first?.containsImagePreview == true)

    let full = AuditAssistantService.context(
        for: row,
        review: nil,
        configuration: AuditAssistantConfiguration(dataSharingLevel: .fullContext)
    )
    #expect(full.metadata["author"] == "alice")
    let encoded = try JSONEncoder().encode(full)
    let text = String(data: encoded, encoding: .utf8) ?? ""
    #expect(text.contains("R0lGODlh") == false)
}

@Test
func openAICompatibleRequestBuildsChatCompletionShape() throws {
    let row = assistantFixtureRow()
    let context = AuditAssistantService.context(for: row, review: nil, configuration: AuditAssistantConfiguration())
    let configuration = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .customOpenAICompatible,
        apiProtocol: .openAIChatCompletions,
        baseURL: "https://api.example.com/v1",
        model: "gpt-test",
        maxOutputTokens: 300,
        temperature: 0.1
    )

    let providerRequest = try AuditAssistantProviderAdapter.request(
        configuration: configuration,
        context: context,
        credential: "test-key"
    )
    #expect(providerRequest.request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
    #expect(providerRequest.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

    let body = try #require(providerRequest.request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["model"] as? String == "gpt-test")
    #expect(object["max_tokens"] as? Int == 300)
    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages.contains { $0["role"] as? String == "system" })
    #expect(messages.contains { ($0["content"] as? String)?.contains("审计证据") == true })
}

@Test
func providerRequestBuildersCoverConfiguredProtocols() throws {
    let context = AuditAssistantService.context(for: assistantFixtureRow(), review: nil, configuration: AuditAssistantConfiguration())

    let responses = try AuditAssistantProviderAdapter.request(
        configuration: AuditAssistantConfiguration(
            mode: .externalAPI,
            provider: .openAI,
            apiProtocol: .openAIResponses,
            baseURL: "https://api.openai.test/v1",
            model: "gpt-test",
            maxOutputTokens: 456,
            temperature: 0.3
        ),
        context: context,
        credential: "openai-key"
    )
    #expect(responses.request.url?.absoluteString == "https://api.openai.test/v1/responses")
    #expect(responses.request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key")
    let responsesBody = try requestBodyObject(responses.request)
    #expect(responsesBody["model"] as? String == "gpt-test")
    #expect(responsesBody["max_output_tokens"] as? Int == 456)

    let anthropic = try AuditAssistantProviderAdapter.request(
        configuration: AuditAssistantConfiguration(
            mode: .externalAPI,
            provider: .anthropic,
            apiProtocol: .anthropicMessages,
            baseURL: "https://api.anthropic.test/v1",
            model: "claude-test"
        ),
        context: context,
        credential: "anthropic-key"
    )
    #expect(anthropic.request.url?.absoluteString == "https://api.anthropic.test/v1/messages")
    #expect(anthropic.request.value(forHTTPHeaderField: "x-api-key") == "anthropic-key")
    #expect(anthropic.request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

    let gemini = try AuditAssistantProviderAdapter.request(
        configuration: AuditAssistantConfiguration(
            mode: .externalAPI,
            provider: .gemini,
            apiProtocol: .geminiGenerateContent,
            baseURL: "https://generativelanguage.googleapis.test/v1beta",
            model: "gemini-test"
        ),
        context: context,
        credential: "gemini-key"
    )
    #expect(gemini.request.url?.absoluteString == "https://generativelanguage.googleapis.test/v1beta/models/gemini-test:generateContent")
    #expect(gemini.request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")

    let miniMax = try AuditAssistantProviderAdapter.request(
        configuration: AuditAssistantConfiguration(
            mode: .externalAPI,
            provider: .miniMax,
            apiProtocol: .miniMaxChatCompletion,
            baseURL: "https://api.minimax.test/v1",
            model: "MiniMax-Test"
        ),
        context: context,
        credential: "minimax-key"
    )
    #expect(miniMax.request.url?.absoluteString == "https://api.minimax.test/v1/text/chatcompletion_v2")
    #expect(miniMax.request.value(forHTTPHeaderField: "Authorization") == "Bearer minimax-key")
}

@Test
func providerRequestRejectsUnsupportedProtocolPairings() throws {
    let context = AuditAssistantService.context(for: assistantFixtureRow(), review: nil, configuration: AuditAssistantConfiguration())
    let configuration = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .openAI,
        apiProtocol: .geminiGenerateContent,
        baseURL: "https://api.openai.test/v1",
        model: "gpt-test"
    )

    do {
        _ = try AuditAssistantProviderAdapter.request(
            configuration: configuration,
            context: context,
            credential: "test-key"
        )
        Issue.record("OpenAI provider should not accept Gemini protocol")
    } catch AuditAssistantService.AssistantError.unsupportedProviderProtocol(let provider, let apiProtocol) {
        #expect(provider == AuditAssistantConfiguration.Provider.openAI.rawValue)
        #expect(apiProtocol == AuditAssistantConfiguration.APIProtocol.geminiGenerateContent.rawValue)
    }
}

@Test
func customOpenAICompatibleProviderRequiresExplicitBaseURL() throws {
    #expect(AuditAssistantConfiguration.Provider.customOpenAICompatible.defaultBaseURL.isEmpty)

    let context = AuditAssistantService.context(for: assistantFixtureRow(), review: nil, configuration: AuditAssistantConfiguration())
    let configuration = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .customOpenAICompatible,
        apiProtocol: .openAIChatCompletions,
        model: "gpt-5.4-mini"
    )

    do {
        _ = try AuditAssistantProviderAdapter.request(
            configuration: configuration,
            context: context,
            credential: "test-key"
        )
        Issue.record("Custom OpenAI-compatible providers should require an explicit base URL")
    } catch AuditAssistantService.AssistantError.invalidEndpoint {}
}

@Test
func disabledAssistantDoesNotGenerateSuggestions() async throws {
    do {
        _ = try await AuditAssistantService().suggestion(
            for: assistantFixtureRow(),
            review: nil,
            configuration: AuditAssistantConfiguration(mode: .disabled)
        )
        Issue.record("Disabled assistant should not generate suggestions")
    } catch AuditAssistantService.AssistantError.disabled {}
}

@Test
func providerResponseParsersExtractTextAndUsage() throws {
    let chat = """
    {"model":"gpt-test","choices":[{"message":{"content":"{\\"summary\\":\\"通过\\",\\"trigger_reasons\\":[\\"共享作者\\"],\\"checkpoints\\":[\\"核对附件\\"],\\"suggested_decision\\":\\"confirmed\\",\\"suggested_severity\\":\\"high\\",\\"note_draft\\":\\"建议复核\\"}"}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    """
    let chatOutput = try AuditAssistantProviderAdapter.outputText(from: Data(chat.utf8), apiProtocol: .openAIChatCompletions)
    let result = AuditAssistantService.result(
        from: chatOutput.text,
        provider: .customOpenAICompatible,
        model: chatOutput.model ?? "",
        requestID: "req-1",
        tokenUsage: chatOutput.usage,
        requestHash: "hash"
    )
    #expect(result.summary == "通过")
    #expect(result.suggestedDecision == .confirmed)
    #expect(result.suggestedSeverity == .high)
    #expect(result.tokenUsage["total_tokens"] == 15)

    let responses = """
    {"model":"gpt-test","output":[{"content":[{"text":"PITCHERPLANT_OK"}]}],"usage":{"input_tokens":3,"output_tokens":2}}
    """
    let responsesOutput = try AuditAssistantProviderAdapter.outputText(from: Data(responses.utf8), apiProtocol: .openAIResponses)
    #expect(responsesOutput.text == "PITCHERPLANT_OK")

    let anthropic = """
    {"model":"claude-test","content":[{"type":"text","text":"ANTHROPIC_OK"}],"usage":{"input_tokens":3,"output_tokens":2}}
    """
    let anthropicOutput = try AuditAssistantProviderAdapter.outputText(from: Data(anthropic.utf8), apiProtocol: .anthropicMessages)
    #expect(anthropicOutput.text == "ANTHROPIC_OK")

    let gemini = """
    {"modelVersion":"gemini-test","candidates":[{"content":{"parts":[{"text":"GEMINI_OK"}]}}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2}}
    """
    let geminiOutput = try AuditAssistantProviderAdapter.outputText(from: Data(gemini.utf8), apiProtocol: .geminiGenerateContent)
    #expect(geminiOutput.text == "GEMINI_OK")
}

@Test
func assistantResultNormalizesChineseModelSuggestions() throws {
    let raw = """
    {
      "summary": "需要人工复核",
      "trigger_reasons": ["文本相似"],
      "checkpoints": ["核对来源"],
      "suggested_decision": "建议人工复核",
      "suggested_severity": "中风险",
      "note_draft": "建议继续复核。"
    }
    """
    let result = AuditAssistantService.result(
        from: raw,
        provider: .customOpenAICompatible,
        model: "gpt-5.4-mini",
        requestID: "req-zh",
        tokenUsage: [:],
        requestHash: "hash"
    )

    #expect(result.suggestedDecision == .pending)
    #expect(result.suggestedSeverity == .medium)
}

@Test
func externalAssistantAPIReportsHTTPStatusErrors() async throws {
    AssistantURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "https://api.openai.test/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["x-request-id": "req-rate-limit"]
        )
        return (try #require(response), Data("{\"error\":\"rate limited\"}".utf8))
    }
    defer { AssistantURLProtocol.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AssistantURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let assistantConfiguration = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .openAI,
        apiProtocol: .openAIChatCompletions,
        baseURL: "https://api.openai.test/v1",
        model: "gpt-test",
        credentialID: "test-key"
    )
    let credentialStore = AuditAssistantCredentialStore(service: "com.pitcherplant.desktop.audit-assistant.tests.\(UUID().uuidString)")
    try credentialStore.save("test-key", id: "test-key")
    defer { try? credentialStore.delete(id: "test-key") }

    do {
        _ = try await AuditAssistantService(
            credentialStore: credentialStore,
            urlSession: session
        ).suggestion(
            for: assistantFixtureRow(),
            review: nil,
            configuration: assistantConfiguration
        )
        Issue.record("HTTP 429 不应被当成成功建议")
    } catch AuditAssistantService.AssistantError.httpStatus(let status, let message) {
        #expect(status == 429)
        #expect(message.contains("rate limited"))
    } catch {
        Issue.record("预期 HTTP status 错误，实际为 \(error)")
    }
}

@Test
func appSettingsDoNotPersistAPIKey() throws {
    let suiteName = "PitcherPlant.AssistantSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var settings = AppSettings.defaults
    settings.auditAssistant = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .customOpenAICompatible,
        apiProtocol: .openAIChatCompletions,
        baseURL: "https://gateway.example.com/v1",
        model: "gpt-5.4-mini",
        credentialID: "unit-test-key"
    )
    AppPreferences.saveAppSettings(settings, defaults: defaults)

    let savedData = try #require(defaults.data(forKey: "pitcherplant.macos.appSettings"))
    let savedText = String(data: savedData, encoding: .utf8) ?? ""
    #expect(savedText.contains("unit-test-secret") == false)
    #expect(savedText.contains("unit-test-key"))

    let loaded = AppPreferences.loadAppSettings(defaults: defaults)
    #expect(loaded.auditAssistant?.provider == .customOpenAICompatible)
    #expect(loaded.auditAssistant?.model == "gpt-5.4-mini")
}

@Test
func assistantSettingsExposeOnlyDisabledAndAPIKeyModes() throws {
    #expect(AuditAssistantConfiguration.Mode.allCases == [.disabled, .externalAPI])
    #expect(AuditAssistantConfiguration.Provider.allCases == [
        .customOpenAICompatible,
        .openAI,
        .anthropic,
        .gemini,
        .deepSeek,
        .kimi,
        .miniMax
    ])
    #expect(AuditAssistantConfiguration.APIProtocol.allCases == [
        .openAIChatCompletions,
        .openAIResponses,
        .anthropicMessages,
        .geminiGenerateContent,
        .miniMaxChatCompletion
    ])
    #expect(AuditAssistantConfiguration.Provider.openAI.supportedProtocols == [.openAIResponses, .openAIChatCompletions])
    #expect(AuditAssistantConfiguration.Provider.gemini.supportedProtocols == [.geminiGenerateContent])
    #expect(AuditAssistantConfiguration.Provider.miniMax.supportedProtocols == [.miniMaxChatCompletion])
    #expect(AuditAssistantConfiguration.Provider.customOpenAICompatible.defaultModel == "gpt-5.4-mini")
    #expect(AuditAssistantConfiguration.Provider.openAI.defaultModel == "gpt-5.2")
}

@Test
func assistantConfigurationProviderSwitchKeepsCustomGatewayExplicit() throws {
    var configuration = AuditAssistantConfiguration(
        mode: .externalAPI,
        provider: .openAI,
        apiProtocol: .openAIResponses,
        baseURL: "https://api.openai.com/v1",
        model: "gpt-5.2"
    )

    configuration.apply(provider: .customOpenAICompatible)

    #expect(configuration.provider == .customOpenAICompatible)
    #expect(configuration.apiProtocol == .openAIResponses)
    #expect(configuration.baseURL.isEmpty)
    #expect(configuration.baseURL.contains("masterjie") == false)

    configuration.baseURL = "https://gateway.example.com/v1"
    configuration.apply(provider: .customOpenAICompatible)

    #expect(configuration.baseURL == "https://gateway.example.com/v1")
}

@Test
func legacyAssistantModesDecodeIntoCurrentAPIKeyShape() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let legacyLocal = try decoder.decode(
        AuditAssistantConfiguration.self,
        from: Data(#"{"mode":"localCommand","endpointOrCommand":"echo legacy"}"#.utf8)
    )
    #expect(legacyLocal.mode == AuditAssistantConfiguration.Mode.disabled)
    #expect(legacyLocal.provider == AuditAssistantConfiguration.Provider.customOpenAICompatible)
    #expect(legacyLocal.apiProtocol == AuditAssistantConfiguration.APIProtocol.openAIChatCompletions)

    let legacyWebhook = try decoder.decode(
        AuditAssistantConfiguration.self,
        from: Data(#"{"mode":"externalAPI","provider":"customWebhook","apiProtocol":"customWebhook","endpointOrCommand":"https://assistant.example.test/webhook","keychainCredentialReference":"legacy-ref"}"#.utf8)
    )
    #expect(legacyWebhook.mode == AuditAssistantConfiguration.Mode.externalAPI)
    #expect(legacyWebhook.provider == AuditAssistantConfiguration.Provider.customOpenAICompatible)
    #expect(legacyWebhook.apiProtocol == AuditAssistantConfiguration.APIProtocol.openAIChatCompletions)

    let encoded = String(data: try encoder.encode(legacyWebhook), encoding: .utf8) ?? ""
    #expect(encoded.contains("endpointOrCommand") == false)
    #expect(encoded.contains("keychainCredentialReference") == false)
    #expect(encoded.contains("customWebhook") == false)
}

@Test
func keychainCredentialStoreRoundTripsAssistantKey() throws {
    let store = AuditAssistantCredentialStore()
    let id = "pitcherplant.tests.\(UUID().uuidString)"
    defer { try? store.delete(id: id) }

    #expect(try store.exists(id: id) == false)
    try store.save("unit-test-secret", id: id)
    #expect(try store.exists(id: id) == true)
    #expect(try store.read(id: id) == "unit-test-secret")

    try store.save("unit-test-secret-updated", id: id)
    #expect(try store.exists(id: id) == true)
    #expect(try store.read(id: id) == "unit-test-secret-updated")

    try store.delete(id: id)
    #expect(try store.exists(id: id) == false)
    do {
        _ = try store.read(id: id)
        Issue.record("删除后不应再读取到 Keychain 凭据")
    } catch AuditAssistantCredentialStore.CredentialError.missingCredential {}
}

@Test
func keychainCredentialStoreNormalizesCredentialIDs() throws {
    let store = AuditAssistantCredentialStore(service: "com.pitcherplant.desktop.audit-assistant.tests.\(UUID().uuidString)")
    let id = "pitcherplant.tests.normalized.\(UUID().uuidString)"
    defer { try? store.delete(id: id) }

    try store.save("unit-test-secret", id: "  \(id)  \n")

    #expect(try store.exists(id: id))
    #expect(try store.exists(id: "\n\(id) "))
    #expect(try store.read(id: id) == "unit-test-secret")
    #expect(try store.read(id: " \(id)\n") == "unit-test-secret")

    try store.delete(id: " \(id)\n")
    #expect(try store.exists(id: id) == false)
}

@Test
func keychainCredentialStoreMigratesLegacyDefaultKey() throws {
    let store = AuditAssistantCredentialStore(service: "com.pitcherplant.desktop.audit-assistant.tests.\(UUID().uuidString)")
    let legacyID = AuditAssistantCredentialStore.legacyDefaultCredentialID
    let targetID = "pitcherplant.tests.migrated.\(UUID().uuidString)"
    defer {
        try? store.delete(id: targetID)
        try? store.delete(id: legacyID)
    }

    try store.save("legacy-unit-test-secret", id: legacyID)
    #expect(try store.migrateLegacyDefaultCredentialIfNeeded(to: targetID))
    #expect(try store.read(id: targetID) == "legacy-unit-test-secret")
    #expect(try store.exists(id: legacyID) == false)
    #expect(try store.migrateLegacyDefaultCredentialIfNeeded(to: targetID) == false)
}

@Test
func keychainCredentialDeleteRemovesLegacyDefaultKey() throws {
    let store = AuditAssistantCredentialStore(service: "com.pitcherplant.desktop.audit-assistant.tests.\(UUID().uuidString)")
    let legacyID = AuditAssistantCredentialStore.legacyDefaultCredentialID
    let targetID = "pitcherplant.tests.deleted.\(UUID().uuidString)"
    defer {
        try? store.delete(id: targetID)
        try? store.delete(id: legacyID)
    }

    try store.save("target-unit-test-secret", id: targetID)
    try store.save("legacy-unit-test-secret", id: legacyID)

    try store.deleteCredentialAndLegacyIfPresent(id: targetID)

    #expect(try store.exists(id: targetID) == false)
    #expect(try store.exists(id: legacyID) == false)
    #expect(try store.migrateLegacyDefaultCredentialIfNeeded(to: targetID) == false)
}

@Test
func keychainCredentialMigrationRemovesStaleLegacyWhenTargetExists() throws {
    let store = AuditAssistantCredentialStore(service: "com.pitcherplant.desktop.audit-assistant.tests.\(UUID().uuidString)")
    let legacyID = AuditAssistantCredentialStore.legacyDefaultCredentialID
    let targetID = "pitcherplant.tests.existing.\(UUID().uuidString)"
    defer {
        try? store.delete(id: targetID)
        try? store.delete(id: legacyID)
    }

    try store.save("target-unit-test-secret", id: targetID)
    try store.save("legacy-unit-test-secret", id: legacyID)

    #expect(try store.migrateLegacyDefaultCredentialIfNeeded(to: targetID) == false)

    #expect(try store.read(id: targetID) == "target-unit-test-secret")
    #expect(try store.exists(id: legacyID) == false)
}

private func assistantFixtureRow() -> ReportTableRow {
    let evidenceID = UUID()
    return ReportTableRow(
        columns: ["alpha.md", "beta.md", "相似度 93%"],
        detailTitle: "跨批次元数据命中",
        detailBody: "两份 WriteUP 使用相同作者和近似提交时间。",
        badges: [ReportBadge(title: "高风险", tone: .danger)],
        attachments: [
            ReportAttachment(
                title: "alpha.md",
                subtitle: "第 1 页",
                body: "附件摘要",
                imageBase64: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
            )
        ],
        evidenceID: evidenceID,
        evidenceType: .metadata,
        riskAssessment: RiskAssessment(score: 0.91, level: .high, reasons: ["共享作者", "跨批次命中"], evidenceCount: 2),
        metadata: ["author": "alice"],
        whitelistStatus: WhitelistEvaluation(status: .marked, matchedRuleType: .author, reason: "训练样例作者", scoreMultiplier: 0.5)
    )
}

private func requestBodyObject(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private final class AssistantURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

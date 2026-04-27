import Foundation

struct AuditAssistantConfiguration: Codable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case disabled
        case localCommand
        case externalAPI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .disabled: return "关闭"
            case .localCommand: return "本地命令"
            case .externalAPI: return "外部 API"
            }
        }
    }

    var mode: Mode = .disabled
    var endpointOrCommand: String = ""
    var timeoutSeconds: Double = 20
    var keychainCredentialReference: String = ""
}

struct AuditAssistantService {
    enum AssistantError: LocalizedError {
        case disabled
        case missingEndpoint
        case invalidEndpoint
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .disabled: return "审计助手已关闭。"
            case .missingEndpoint: return "缺少本地命令或 API 地址。"
            case .invalidEndpoint: return "API 地址格式无效。"
            case .emptyResponse: return "审计助手没有返回内容。"
            }
        }
    }

    func explanation(for row: ReportTableRow, review: EvidenceReview?, configuration: AuditAssistantConfiguration) async throws -> String {
        switch configuration.mode {
        case .disabled:
            return localExplanation(for: row, review: review)
        case .localCommand:
            return try await localCommandExplanation(for: row, review: review, configuration: configuration)
        case .externalAPI:
            return try await externalAPIExplanation(for: row, review: review, configuration: configuration)
        }
    }

    func localExplanation(for row: ReportTableRow, review: EvidenceReview?) -> String {
        let risk = row.riskAssessment?.level.title ?? "未评级"
        let reviewTitle = review?.decision.title ?? "待复核"
        let reasons = row.riskAssessment?.reasons.joined(separator: "、") ?? row.badges.map(\.title).joined(separator: "、")
        let files = row.columns.prefix(2).joined(separator: " 与 ")
        return "\(files) 命中\(reasons)，系统风险等级为\(risk)，当前复核状态为\(reviewTitle)。建议审计员优先核对详情面板中的上下文、代码片段和附件来源。"
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

    private func localCommandExplanation(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration
    ) async throws -> String {
        let command = configuration.endpointOrCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.isEmpty == false else {
            throw AssistantError.missingEndpoint
        }

        let payloadData = try JSONEncoder().encode(payload(for: row, review: review))

        return try await withTimeout(seconds: configuration.timeoutSeconds) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try process.run()
            input.fileHandleForWriting.write(payloadData)
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = error.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: stdout.isEmpty ? stderr : stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.isEmpty == false else {
                throw AssistantError.emptyResponse
            }
            return text
        }
    }

    private func externalAPIExplanation(
        for row: ReportTableRow,
        review: EvidenceReview?,
        configuration: AuditAssistantConfiguration
    ) async throws -> String {
        let endpoint = configuration.endpointOrCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty == false else {
            throw AssistantError.missingEndpoint
        }
        guard let url = URL(string: endpoint) else {
            throw AssistantError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if configuration.keychainCredentialReference.isEmpty == false {
            request.setValue(configuration.keychainCredentialReference, forHTTPHeaderField: "X-PitcherPlant-Credential-Ref")
        }
        request.httpBody = try JSONEncoder().encode(payload(for: row, review: review))

        let (data, _) = try await URLSession.shared.data(for: request)
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.isEmpty == false else {
            throw AssistantError.emptyResponse
        }
        return text
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let duration = UInt64(max(seconds, 1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: duration)
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

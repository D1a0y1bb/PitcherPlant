import Darwin
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
        case timeout

        var errorDescription: String? {
            switch self {
            case .disabled: return "审计助手已关闭。"
            case .missingEndpoint: return "缺少本地命令或 API 地址。"
            case .invalidEndpoint: return "API 地址格式无效。"
            case .emptyResponse: return "审计助手没有返回内容。"
            case .timeout: return "审计助手执行超时。"
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

        return try await LocalCommandExecution(command: command, payloadData: payloadData)
            .run(timeoutSeconds: configuration.timeoutSeconds)
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

    private final class LocalCommandExecution: @unchecked Sendable {
        private let command: String
        private let payloadData: Data
        private let process = Process()
        private let input = Pipe()
        private let outputFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pitcherplant-assistant-\(UUID().uuidString).stdout")
        private let errorFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pitcherplant-assistant-\(UUID().uuidString).stderr")
        private var outputFileHandle: FileHandle?
        private var errorFileHandle: FileHandle?
        private var processID: pid_t?

        init(command: String, payloadData: Data) {
            self.command = command
            self.payloadData = payloadData
        }

        func run(timeoutSeconds: Double) async throws -> String {
            try prepareOutputFiles()
            defer {
                cleanupOutputFiles()
            }

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardInput = input
            process.standardOutput = outputFileHandle
            process.standardError = errorFileHandle

            try process.run()
            processID = process.processIdentifier
            _ = setpgid(process.processIdentifier, process.processIdentifier)
            input.fileHandleForWriting.write(payloadData)
            input.fileHandleForWriting.closeFile()

            let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0.1))
            do {
                while process.isRunning {
                    if Date() >= deadline {
                        terminate()
                        throw AssistantError.timeout
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            } catch {
                terminate()
                throw error
            }

            return try readOutput()
        }

        private func readOutput() throws -> String {
            closeOutputFiles()
            let stdout = (try? Data(contentsOf: outputFileURL)) ?? Data()
            let stderr = (try? Data(contentsOf: errorFileURL)) ?? Data()
            let text = String(data: stdout.isEmpty ? stderr : stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.isEmpty == false else {
                throw AssistantError.emptyResponse
            }
            return text
        }

        private func prepareOutputFiles() throws {
            _ = FileManager.default.createFile(atPath: outputFileURL.path, contents: nil)
            _ = FileManager.default.createFile(atPath: errorFileURL.path, contents: nil)
            outputFileHandle = try FileHandle(forWritingTo: outputFileURL)
            errorFileHandle = try FileHandle(forWritingTo: errorFileURL)
        }

        private func closeOutputFiles() {
            outputFileHandle?.closeFile()
            outputFileHandle = nil
            errorFileHandle?.closeFile()
            errorFileHandle = nil
        }

        private func cleanupOutputFiles() {
            closeOutputFiles()
            try? FileManager.default.removeItem(at: outputFileURL)
            try? FileManager.default.removeItem(at: errorFileURL)
        }

        private func terminate() {
            guard process.isRunning else {
                return
            }
            let descendantIDs = descendantProcessIDs(of: process.processIdentifier)
            signal(descendantIDs, SIGTERM)
            signalProcessGroup(SIGTERM)
            process.terminate()

            let deadline = Date().addingTimeInterval(0.2)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }

            let remainingDescendantIDs = descendantProcessIDs(of: process.processIdentifier)
            signal(Set(descendantIDs + remainingDescendantIDs), SIGKILL)
            signalProcessGroup(SIGKILL)
        }

        private func signal<S: Sequence>(_ processIDs: S, _ signal: Int32) where S.Element == pid_t {
            for processID in processIDs where processID > 0 {
                kill(processID, signal)
            }
        }

        private func signalProcessGroup(_ signal: Int32) {
            if let processID {
                kill(-processID, signal)
            }
            if process.isRunning {
                kill(process.processIdentifier, signal)
            }
        }

        private func descendantProcessIDs(of rootID: pid_t) -> [pid_t] {
            let snapshotProcess = Process()
            snapshotProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
            snapshotProcess.arguments = ["-axo", "pid=,ppid="]
            let snapshotOutput = Pipe()
            snapshotProcess.standardOutput = snapshotOutput
            snapshotProcess.standardError = Pipe()

            do {
                try snapshotProcess.run()
            } catch {
                return []
            }
            snapshotProcess.waitUntilExit()

            let data = snapshotOutput.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            let pairs: [(pid_t, pid_t)] = output.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard fields.count == 2,
                      let processID = pid_t(String(fields[0])),
                      let parentID = pid_t(String(fields[1])) else {
                    return nil
                }
                return (processID, parentID)
            }

            let childrenByParent = Dictionary(grouping: pairs, by: \.1)
                .mapValues { $0.map(\.0) }
            var descendants: [pid_t] = []
            var stack = childrenByParent[rootID] ?? []
            while let processID = stack.popLast() {
                descendants.append(processID)
                stack.append(contentsOf: childrenByParent[processID] ?? [])
            }
            return descendants
        }
    }
}

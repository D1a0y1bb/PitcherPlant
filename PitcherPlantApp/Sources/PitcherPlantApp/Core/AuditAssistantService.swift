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
        let timeoutSeconds = configuration.timeoutSeconds

        let executionTask = Task.detached(priority: .utility) {
            try await LocalCommandExecution(command: command, payloadData: payloadData)
                .run(timeoutSeconds: timeoutSeconds)
        }
        return try await withTaskCancellationHandler {
            try await executionTask.value
        } onCancel: {
            executionTask.cancel()
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

    private final class LocalCommandExecution: @unchecked Sendable {
        private let command: String
        private let payloadData: Data
        private let outputFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pitcherplant-assistant-\(UUID().uuidString).stdout")
        private let errorFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pitcherplant-assistant-\(UUID().uuidString).stderr")
        private var inputReadDescriptor: Int32 = -1
        private var inputWriteDescriptor: Int32 = -1
        private var outputDescriptor: Int32 = -1
        private var errorDescriptor: Int32 = -1
        private var processID: pid_t?
        private var processHasExited = false

        init(command: String, payloadData: Data) {
            self.command = command
            self.payloadData = payloadData
        }

        func run(timeoutSeconds: Double) async throws -> String {
            try Task.checkCancellation()
            try prepareProcessIO()
            defer {
                cleanupDescriptors()
                cleanupOutputFiles()
            }

            try spawnProcessGroup()
            closeDescriptor(&inputReadDescriptor)
            closeDescriptor(&outputDescriptor)
            closeDescriptor(&errorDescriptor)
            try writePayloadAndCloseInput()

            let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0.1))
            do {
                while reapIfExited() == false {
                    if Date() >= deadline {
                        await terminate()
                        throw AssistantError.timeout
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            } catch AssistantError.timeout {
                throw AssistantError.timeout
            } catch {
                await terminate()
                throw error
            }

            return try readOutput()
        }

        private func readOutput() throws -> String {
            cleanupDescriptors()
            let stdout = (try? Data(contentsOf: outputFileURL)) ?? Data()
            let stderr = (try? Data(contentsOf: errorFileURL)) ?? Data()
            let text = String(data: stdout.isEmpty ? stderr : stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.isEmpty == false else {
                throw AssistantError.emptyResponse
            }
            return text
        }

        private func prepareProcessIO() throws {
            var pipeDescriptors = [Int32](repeating: 0, count: 2)
            guard pipe(&pipeDescriptors) == 0 else {
                throw posixError(errno)
            }
            inputReadDescriptor = pipeDescriptors[0]
            inputWriteDescriptor = pipeDescriptors[1]
            outputDescriptor = try openOutputFile(at: outputFileURL)
            errorDescriptor = try openOutputFile(at: errorFileURL)
        }

        private func openOutputFile(at url: URL) throws -> Int32 {
            let descriptor = url.path.withCString { path in
                open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
            }
            guard descriptor >= 0 else {
                throw posixError(errno)
            }
            return descriptor
        }

        private func spawnProcessGroup() throws {
            var fileActions: posix_spawn_file_actions_t?
            var attributes: posix_spawnattr_t?
            var fileActionsInitialized = false
            var attributesInitialized = false
            try checkSpawnSetup(posix_spawn_file_actions_init(&fileActions))
            fileActionsInitialized = true
            try checkSpawnSetup(posix_spawnattr_init(&attributes))
            attributesInitialized = true
            defer {
                if fileActionsInitialized {
                    posix_spawn_file_actions_destroy(&fileActions)
                }
                if attributesInitialized {
                    posix_spawnattr_destroy(&attributes)
                }
            }

            try checkSpawnSetup(posix_spawn_file_actions_adddup2(&fileActions, inputReadDescriptor, STDIN_FILENO))
            try checkSpawnSetup(posix_spawn_file_actions_adddup2(&fileActions, outputDescriptor, STDOUT_FILENO))
            try checkSpawnSetup(posix_spawn_file_actions_adddup2(&fileActions, errorDescriptor, STDERR_FILENO))
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&fileActions, inputWriteDescriptor))
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&fileActions, inputReadDescriptor))
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&fileActions, outputDescriptor))
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&fileActions, errorDescriptor))

            try checkSpawnSetup(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)))
            try checkSpawnSetup(posix_spawnattr_setpgroup(&attributes, 0))

            let shellPath = "/bin/zsh"
            let arguments = [shellPath, "-lc", command]
            var cArguments: [UnsafeMutablePointer<CChar>?] = []
            for argument in arguments {
                guard let cArgument = strdup(argument) else {
                    throw posixError(ENOMEM)
                }
                cArguments.append(cArgument)
            }
            cArguments.append(nil)
            defer {
                for argument in cArguments {
                    free(argument)
                }
            }

            var spawnedProcessID: pid_t = 0
            let result = posix_spawn(
                &spawnedProcessID,
                shellPath,
                &fileActions,
                &attributes,
                cArguments,
                environ
            )
            guard result == 0 else {
                throw posixError(result)
            }
            processID = spawnedProcessID
            processHasExited = false
        }

        private func writePayloadAndCloseInput() throws {
            defer {
                closeDescriptor(&inputWriteDescriptor)
            }
            var offset = 0
            try payloadData.withUnsafeBytes { buffer in
                while offset < buffer.count {
                    guard let baseAddress = buffer.baseAddress else {
                        return
                    }
                    let written = write(inputWriteDescriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                    if written > 0 {
                        offset += written
                    } else if written == -1 && errno == EINTR {
                        continue
                    } else if written == -1 && errno == EPIPE {
                        return
                    } else {
                        throw posixError(errno)
                    }
                }
            }
        }

        private func reapIfExited() -> Bool {
            guard let processID, processHasExited == false else {
                return true
            }

            var status: Int32 = 0
            while true {
                let result = waitpid(processID, &status, WNOHANG)
                if result == processID {
                    processHasExited = true
                    return true
                }
                if result == 0 {
                    return false
                }
                if errno == EINTR {
                    continue
                }
                if errno == ECHILD {
                    processHasExited = true
                    return true
                }
                return false
            }
        }

        private func cleanupDescriptors() {
            closeDescriptor(&inputReadDescriptor)
            closeDescriptor(&inputWriteDescriptor)
            closeDescriptor(&outputDescriptor)
            closeDescriptor(&errorDescriptor)
        }

        private func closeDescriptor(_ descriptor: inout Int32) {
            if descriptor >= 0 {
                close(descriptor)
                descriptor = -1
            }
        }

        private func cleanupOutputFiles() {
            try? FileManager.default.removeItem(at: outputFileURL)
            try? FileManager.default.removeItem(at: errorFileURL)
        }

        private func terminate() async {
            guard let processID, processHasExited == false else {
                return
            }
            let descendantIDs = descendantProcessIDs(of: processID)
            signal(descendantIDs, SIGTERM)
            await wait(nanoseconds: 100_000_000)

            let stubbornDescendantIDs = descendantProcessIDs(of: processID)
            signal(Set(descendantIDs + stubbornDescendantIDs), SIGKILL)
            await wait(nanoseconds: 100_000_000)

            signalProcessGroup(SIGTERM)
            kill(processID, SIGTERM)
            await waitForProcessExit(nanoseconds: 200_000_000)

            let remainingDescendantIDs = descendantProcessIDs(of: processID)
            signal(Set(descendantIDs + stubbornDescendantIDs + remainingDescendantIDs), SIGKILL)
            signalProcessGroup(SIGKILL)
            kill(processID, SIGKILL)
            await waitForProcessExit(nanoseconds: 200_000_000)
        }

        private func waitForProcessExit(nanoseconds: UInt64) async {
            let deadline = Date().addingTimeInterval(Double(nanoseconds) / 1_000_000_000)
            while reapIfExited() == false && Date() < deadline {
                await wait(nanoseconds: 20_000_000)
            }
            _ = reapIfExited()
        }

        private func wait(nanoseconds: UInt64) async {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {}
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
        }

        private func checkSpawnSetup(_ result: Int32) throws {
            guard result == 0 else {
                throw posixError(result)
            }
        }

        private func posixError(_ code: Int32) -> POSIXError {
            POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
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

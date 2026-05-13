import Darwin
import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func localAssistantCommandTimesOutAndStopsWaiting() async throws {
    let row = ReportTableRow(
        columns: ["alpha.md", "beta.md"],
        detailTitle: "相似证据",
        detailBody: "两份报告包含相同片段"
    )
    let configuration = AuditAssistantConfiguration(
        mode: .localCommand,
        endpointOrCommand: "sleep 5",
        timeoutSeconds: 0.2
    )
    let startedAt = Date()

    do {
        _ = try await AuditAssistantService().explanation(for: row, review: nil, configuration: configuration)
        Issue.record("本地助手命令应该超时")
    } catch AuditAssistantService.AssistantError.timeout {
        #expect(Date().timeIntervalSince(startedAt) < 2.0)
    } catch {
        Issue.record("预期超时错误，实际为 \(error)")
    }
}

@Test
func localAssistantCommandKillsProcessesThatIgnoreTerm() async throws {
    let row = ReportTableRow(
        columns: ["alpha.md", "beta.md"],
        detailTitle: "相似证据",
        detailBody: "两份报告包含相同片段"
    )
    let configuration = AuditAssistantConfiguration(
        mode: .localCommand,
        endpointOrCommand: "trap '' TERM; sleep 5",
        timeoutSeconds: 0.2
    )
    let startedAt = Date()

    do {
        _ = try await AuditAssistantService().explanation(for: row, review: nil, configuration: configuration)
        Issue.record("忽略 TERM 的本地助手命令应该超时并退出")
    } catch AuditAssistantService.AssistantError.timeout {
        #expect(Date().timeIntervalSince(startedAt) < 2.0)
    } catch {
        Issue.record("预期超时错误，实际为 \(error)")
    }
}

@Test
func localAssistantCommandCleansBackgroundChildProcessAfterTimeout() async throws {
    let row = ReportTableRow(
        columns: ["alpha.md", "beta.md"],
        detailTitle: "相似证据",
        detailBody: "两份报告包含相同片段"
    )
    let markerURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-assistant-child-\(UUID().uuidString).pid")
    defer {
        if let childID = try? readProcessID(from: markerURL) {
            kill(childID, SIGKILL)
        }
        try? FileManager.default.removeItem(at: markerURL)
    }

    let configuration = AuditAssistantConfiguration(
        mode: .localCommand,
        endpointOrCommand: """
        ( trap '' TERM; while true; do sleep 1; done ) &
        echo $! > '\(markerURL.path)'
        wait
        """,
        timeoutSeconds: 0.2
    )

    do {
        _ = try await AuditAssistantService().explanation(for: row, review: nil, configuration: configuration)
        Issue.record("后台子进程残留场景应该超时")
    } catch AuditAssistantService.AssistantError.timeout {
        let childID = try #require(try await readProcessIDWhenReady(from: markerURL))
        let cleaned = await waitForProcessToExit(childID, timeoutSeconds: 2.0)
        #expect(cleaned)
    } catch {
        Issue.record("预期超时错误，实际为 \(error)")
    }
}

@Test
func localAssistantCommandCancellationCleansBackgroundChildProcess() async throws {
    let row = ReportTableRow(
        columns: ["alpha.md", "beta.md"],
        detailTitle: "相似证据",
        detailBody: "两份报告包含相同片段"
    )
    let markerURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-assistant-cancel-child-\(UUID().uuidString).pid")
    defer {
        if let childID = try? readProcessID(from: markerURL) {
            kill(childID, SIGKILL)
        }
        try? FileManager.default.removeItem(at: markerURL)
    }

    let configuration = AuditAssistantConfiguration(
        mode: .localCommand,
        endpointOrCommand: """
        ( trap '' TERM; while true; do sleep 1; done ) &
        echo $! > '\(markerURL.path)'
        wait
        """,
        timeoutSeconds: 10
    )
    let task = Task {
        try await AuditAssistantService().explanation(for: row, review: nil, configuration: configuration)
    }
    let childID = try #require(try await readProcessIDWhenReady(from: markerURL))

    task.cancel()
    do {
        _ = try await task.value
        Issue.record("取消本地助手命令后不应该成功返回")
    } catch {}

    let cleaned = await waitForProcessToExit(childID, timeoutSeconds: 2.0)
    #expect(cleaned)
}

private func readProcessID(from url: URL) throws -> pid_t? {
    let text = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int32(text) else {
        return nil
    }
    return pid_t(value)
}

private func readProcessIDWhenReady(from url: URL) async throws -> pid_t? {
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if let processID = try? readProcessID(from: url) {
            return processID
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    return nil
}

private func waitForProcessToExit(_ processID: pid_t, timeoutSeconds: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if kill(processID, 0) != 0 && errno == ESRCH {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return kill(processID, 0) != 0 && errno == ESRCH
}

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

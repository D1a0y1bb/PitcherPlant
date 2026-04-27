import Foundation

struct AuditAssistantConfiguration: Codable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case disabled
        case localCommand
        case externalAPI
    }

    var mode: Mode = .disabled
    var endpointOrCommand: String = ""
}

struct AuditAssistantService {
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
}

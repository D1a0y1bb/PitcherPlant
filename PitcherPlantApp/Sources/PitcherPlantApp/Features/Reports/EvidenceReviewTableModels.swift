import Foundation

struct EvidenceReviewTarget: Identifiable, Codable, Hashable, Sendable {
    var reportID: UUID
    var reportTitle: String
    var sectionKind: ReportSectionKind
    var sectionTitle: String
    var rowID: UUID
    var evidenceID: UUID
    var evidenceType: EvidenceType

    var id: UUID {
        UUID.pitcherPlantStable(
            namespace: "evidence-review-target",
            components: [
                reportID.uuidString,
                sectionKind.rawValue,
                rowID.uuidString,
                evidenceID.uuidString,
            ]
        )
    }
}

enum EvidenceReviewTableSortOrder: String, CaseIterable, Identifiable, Sendable {
    case riskDescending
    case scoreDescending
    case titleAscending
    case reviewStatus

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .riskDescending: return "evidence.reviewSort.riskDescending"
        case .scoreDescending: return "evidence.reviewSort.scoreDescending"
        case .titleAscending: return "evidence.reviewSort.titleAscending"
        case .reviewStatus: return "evidence.reviewSort.reviewStatus"
        }
    }
}

struct EvidenceReviewTableRow: Identifiable, Hashable, Sendable {
    let target: EvidenceReviewTarget
    let reportTitle: String
    let sectionTitle: String
    let riskLevel: RiskLevel
    let evidenceType: EvidenceType
    let leftObject: String
    let rightObject: String
    let challengeText: String
    let scoreValue: Double
    let scoreText: String
    let ruleText: String
    let reviewDecision: EvidenceDecision
    let whitelistStatus: WhitelistEvaluation.Status?
    let updatedAt: Date
    let row: ReportTableRow

    var id: UUID { target.id }

    init(report: AuditReport, section: ReportSection, row: ReportTableRow) {
        let evidenceID = row.evidenceID ?? row.id
        let evidenceType = row.evidenceType ?? EvidenceType(rawValue: section.kind.rawValue) ?? .text
        let review = row.review
        self.target = EvidenceReviewTarget(
            reportID: report.id,
            reportTitle: report.title,
            sectionKind: section.kind,
            sectionTitle: section.title,
            rowID: row.id,
            evidenceID: evidenceID,
            evidenceType: evidenceType
        )
        self.reportTitle = report.title
        self.sectionTitle = section.title
        self.riskLevel = review?.severity ?? row.riskAssessment?.level ?? .none
        self.evidenceType = evidenceType
        self.leftObject = row.columns[safe: 0] ?? row.detailTitle
        self.rightObject = row.columns[safe: 1] ?? ""
        self.challengeText = Self.challengeText(report: report, section: section, row: row)
        self.scoreText = row.columns[safe: 2] ?? row.riskAssessment?.formattedScore ?? ""
        self.scoreValue = Self.parseScore(scoreText, fallback: row.riskAssessment?.score ?? 0)
        self.ruleText = row.columns[safe: 3] ?? row.riskAssessment?.reasons.joined(separator: "、") ?? row.detailBody
        self.reviewDecision = review?.decision ?? .pending
        self.whitelistStatus = row.whitelistStatus?.status
        self.updatedAt = review?.updatedAt ?? .distantPast
        self.row = row
    }

    static func rows(report: AuditReport, section: ReportSection) -> [EvidenceReviewTableRow] {
        rows(report: report, section: section, rows: section.table?.rows ?? [])
    }

    static func rows(report: AuditReport, section: ReportSection, rows: [ReportTableRow]) -> [EvidenceReviewTableRow] {
        rows.map { EvidenceReviewTableRow(report: report, section: section, row: $0) }
    }

    static func rows(items: [EvidenceCollectionItem]) -> [EvidenceReviewTableRow] {
        items.map { item in
            let report = AuditReport(
                id: item.reportID,
                title: item.reportTitle,
                sourcePath: "",
                scanDirectoryPath: "",
                metrics: [],
                sections: []
            )
            let section = ReportSection(kind: item.sectionKind, title: item.sectionTitle, summary: "")
            return EvidenceReviewTableRow(report: report, section: section, row: item.row)
        }
    }

    static func sorted(_ rows: [EvidenceReviewTableRow], by sortOrder: EvidenceReviewTableSortOrder) -> [EvidenceReviewTableRow] {
        rows.sorted { lhs, rhs in
            switch sortOrder {
            case .riskDescending:
                if lhs.riskLevel.priority == rhs.riskLevel.priority {
                    return lhs.scoreValue > rhs.scoreValue
                }
                return lhs.riskLevel.priority > rhs.riskLevel.priority
            case .scoreDescending:
                if lhs.scoreValue == rhs.scoreValue {
                    return lhs.leftObject.localizedStandardCompare(rhs.leftObject) == .orderedAscending
                }
                return lhs.scoreValue > rhs.scoreValue
            case .titleAscending:
                return lhs.leftObject.localizedStandardCompare(rhs.leftObject) == .orderedAscending
            case .reviewStatus:
                if lhs.reviewDecision.rawValue == rhs.reviewDecision.rawValue {
                    return lhs.scoreValue > rhs.scoreValue
                }
                return lhs.reviewDecision.rawValue < rhs.reviewDecision.rawValue
            }
        }
    }

    private static func challengeText(report: AuditReport, section: ReportSection, row: ReportTableRow) -> String {
        if let value = row.metadata?["challenge"], value.isEmpty == false {
            return value
        }
        if section.kind == .crossBatch, let value = row.columns[safe: 2], value.isEmpty == false {
            return value
        }
        return section.title.isEmpty ? report.title : section.title
    }

    private static func parseScore(_ text: String, fallback: Double) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") {
            let value = trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return min(max((Double(value) ?? fallback * 100) / 100, 0), 1)
        }
        if let value = Double(trimmed) {
            return value > 1 ? min(max(value / 100, 0), 1) : min(max(value, 0), 1)
        }
        return min(max(fallback, 0), 1)
    }
}

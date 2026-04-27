import Foundation

enum ReportLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case nativeOnly
    case legacyOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .nativeOnly: return "原生"
        case .legacyOnly: return "Legacy"
        }
    }

    func includes(_ report: AuditReport) -> Bool {
        switch self {
        case .all:
            return true
        case .nativeOnly:
            return report.isLegacy == false
        case .legacyOnly:
            return report.isLegacy
        }
    }
}

enum ReportEvidenceFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case highRisk
    case withAttachments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .highRisk: return "高危"
        case .withAttachments: return "带附件"
        }
    }

    func matches(_ row: ReportTableRow) -> Bool {
        switch self {
        case .all:
            return true
        case .highRisk:
            return row.riskAssessment?.level == .high || row.badges.contains(where: { $0.tone == .danger })
        case .withAttachments:
            return row.attachments.isEmpty == false
        }
    }
}

enum ReportEvidenceSortOrder: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case severity
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return "默认顺序"
        case .severity: return "风险优先"
        case .title: return "按标题"
        }
    }

    func sort(_ rows: [ReportTableRow]) -> [ReportTableRow] {
        switch self {
        case .default:
            return rows
        case .severity:
            return rows.sorted {
                if $0.severityRank == $1.severityRank {
                    if $0.attachments.count == $1.attachments.count {
                        return $0.detailTitle.localizedStandardCompare($1.detailTitle) == .orderedAscending
                    }
                    return $0.attachments.count > $1.attachments.count
                }
                return $0.severityRank > $1.severityRank
            }
        case .title:
            return rows.sorted {
                $0.detailTitle.localizedStandardCompare($1.detailTitle) == .orderedAscending
            }
        }
    }
}

extension AuditReport {
    func matchesLibrarySearch(_ query: String, filter: ReportLibraryFilter) -> Bool {
        guard filter.includes(self) else {
            return false
        }
        let trimmed = query.normalizedSearchQuery
        guard trimmed.isEmpty == false else {
            return true
        }
        return searchCorpus.localizedCaseInsensitiveContains(trimmed)
            || sections.contains(where: { $0.matchesSearch(trimmed) })
    }

    private var searchCorpus: String {
        let metricCorpus = metrics.map { [$0.title, $0.value].joined(separator: " ") }
        return ([title, sourcePath, scanDirectoryPath] + metricCorpus).joined(separator: "\n")
    }
}

extension ReportSection {
    func filteredCopy(query: String, evidenceFilter: ReportEvidenceFilter, sortOrder: ReportEvidenceSortOrder) -> ReportSection {
        guard let table else {
            return self
        }
        let trimmed = query.normalizedSearchQuery
        let rows = table.rows.filter { row in
            evidenceFilter.matches(row) && (trimmed.isEmpty || row.matchesSearch(trimmed))
        }
        var copy = self
        copy.table = ReportTable(headers: table.headers, rows: sortOrder.sort(rows))
        return copy
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.normalizedSearchQuery
        guard trimmed.isEmpty == false else {
            return true
        }
        let calloutCorpus = callouts.joined(separator: "\n")
        let headerCorpus = table?.headers.joined(separator: "\n") ?? ""
        return [title, summary, calloutCorpus, headerCorpus]
            .joined(separator: "\n")
            .localizedCaseInsensitiveContains(trimmed)
            || (table?.rows.contains(where: { $0.matchesSearch(trimmed) }) ?? false)
    }
}

extension ReportTableRow {
    fileprivate func matchesSearch(_ query: String) -> Bool {
        searchableCorpus.localizedCaseInsensitiveContains(query)
    }

    fileprivate var searchableCorpus: String {
        let badgeCorpus = badges.map(\.title).joined(separator: "\n")
        let attachmentCorpus = attachments
            .flatMap { [$0.title, $0.subtitle, $0.body] }
            .joined(separator: "\n")
        return (columns + [detailTitle, detailBody, badgeCorpus, attachmentCorpus]).joined(separator: "\n")
    }

    fileprivate var severityRank: Int {
        max(rowRiskPriority, badges.map(\.tone.priority).max() ?? 0)
    }

    private var rowRiskPriority: Int {
        riskAssessment?.level.priority ?? 0
    }
}

private extension ReportBadge.Tone {
    var priority: Int {
        switch self {
        case .danger: return 4
        case .warning: return 3
        case .accent: return 2
        case .success: return 1
        case .neutral: return 0
        }
    }
}

private extension String {
    var normalizedSearchQuery: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

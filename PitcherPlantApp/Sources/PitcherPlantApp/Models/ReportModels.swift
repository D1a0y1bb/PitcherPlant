import Foundation

struct ReportMetric: Codable, Hashable, Sendable {
    let title: String
    let value: String
    let systemImage: String
}

struct ReportBadge: Codable, Hashable, Sendable {
    let title: String
    let tone: Tone

    enum Tone: String, Codable, Hashable, Sendable {
        case neutral
        case accent
        case warning
        case danger
        case success
    }
}

struct ReportAttachment: Codable, Hashable, Sendable {
    let title: String
    let subtitle: String
    let body: String
    let imageBase64: String?
}

enum ReportSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case text
    case code
    case image
    case metadata
    case dedup
    case fingerprints
    case crossBatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .text: return "文本"
        case .code: return "代码"
        case .image: return "图片"
        case .metadata: return "元数据"
        case .dedup: return "重复"
        case .fingerprints: return "指纹"
        case .crossBatch: return "跨批次"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .text: return "text.quote"
        case .code: return "curlybraces"
        case .image: return "photo.on.rectangle"
        case .metadata: return "person.text.rectangle"
        case .dedup: return "doc.on.doc"
        case .fingerprints: return "key.viewfinder"
        case .crossBatch: return "arrow.triangle.branch"
        }
    }
}

struct ReportTableRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var columns: [String]
    var detailTitle: String
    var detailBody: String
    var badges: [ReportBadge]
    var attachments: [ReportAttachment]
    var evidenceID: UUID?
    var evidenceType: EvidenceType?
    var riskAssessment: RiskAssessment?
    var review: EvidenceReview?
    var metadata: [String: String]?

    init(
        id: UUID = UUID(),
        columns: [String],
        detailTitle: String,
        detailBody: String,
        badges: [ReportBadge] = [],
        attachments: [ReportAttachment] = [],
        evidenceID: UUID? = nil,
        evidenceType: EvidenceType? = nil,
        riskAssessment: RiskAssessment? = nil,
        review: EvidenceReview? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.columns = columns
        self.detailTitle = detailTitle
        self.detailBody = detailBody
        self.badges = badges
        self.attachments = attachments
        self.evidenceID = evidenceID
        self.evidenceType = evidenceType
        self.riskAssessment = riskAssessment
        self.review = review
        self.metadata = metadata
    }
}

struct ReportTable: Codable, Hashable, Sendable {
    var headers: [String]
    var rows: [ReportTableRow]
}

struct ReportSection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: ReportSectionKind
    var title: String
    var summary: String
    var callouts: [String]
    var table: ReportTable?

    init(
        id: UUID = UUID(),
        kind: ReportSectionKind,
        title: String,
        summary: String,
        callouts: [String] = [],
        table: ReportTable? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.callouts = callouts
        self.table = table
    }
}

struct AuditReport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let jobID: UUID?
    let title: String
    let sourcePath: String
    let scanDirectoryPath: String
    let createdAt: Date
    let isLegacy: Bool
    let metrics: [ReportMetric]
    let sections: [ReportSection]

    init(
        id: UUID = UUID(),
        jobID: UUID? = nil,
        title: String,
        sourcePath: String,
        scanDirectoryPath: String,
        createdAt: Date = .now,
        isLegacy: Bool = false,
        metrics: [ReportMetric],
        sections: [ReportSection]
    ) {
        self.id = id
        self.jobID = jobID
        self.title = title
        self.sourcePath = sourcePath
        self.scanDirectoryPath = scanDirectoryPath
        self.createdAt = createdAt
        self.isLegacy = isLegacy
        self.metrics = metrics
        self.sections = sections
    }

    var sourceURL: URL {
        URL(fileURLWithPath: sourcePath)
    }

    var preferredEvidenceSection: ReportSection? {
        let sections = displaySections
        let primaryKinds: [ReportSectionKind] = [.text, .code, .image, .metadata, .dedup, .crossBatch]
        if let primarySection = sections.first(where: { section in
            primaryKinds.contains(section.kind) && section.table?.rows.isEmpty == false
        }) {
            return primarySection
        }
        return sections.first(where: { $0.table?.rows.isEmpty == false }) ?? sections.first
    }

    var displaySections: [ReportSection] {
        var seen = Set<ReportSectionKind>()
        return sections.compactMap { section in
            guard seen.insert(section.kind).inserted else {
                return nil
            }
            return displaySection(for: section.kind)
        }
    }

    func displaySection(for kind: ReportSectionKind?) -> ReportSection? {
        guard let kind else {
            return displaySections.first
        }
        let matches = sections.filter { $0.kind == kind }
        guard matches.count > 1 else {
            return matches.first
        }

        let summaries = matches
            .map(\.summary)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let callouts = Array(
            NSOrderedSet(array: matches.flatMap(\.callouts))
                .compactMap { $0 as? String }
                .prefix(8)
        )
        let tables = matches.compactMap(\.table)
        let rows = tables.flatMap(\.rows)
        let headers = tables.first?.headers ?? ["条目", "摘要", "分数", "详情"]
        let titleSet = Set(matches.map(\.title))

        return ReportSection(
            id: matches[0].id,
            kind: kind,
            title: titleSet.count == 1 ? matches[0].title : kind.title,
            summary: summaries.isEmpty ? "\(kind.title)章节来自多个旧报告区块。" : summaries.joined(separator: "\n\n"),
            callouts: callouts,
            table: rows.isEmpty ? nil : ReportTable(headers: headers, rows: rows)
        )
    }
}

struct FingerprintRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let ext: String
    let author: String
    let size: Int
    let simhash: String
    let scanDir: String
    let scannedAt: Date
    var tags: [String]?
    var sourceReportID: UUID?
    var batchName: String?
    var challengeName: String?
    var teamName: String?
    var submissionItemID: UUID?

    init(
        id: UUID = UUID(),
        filename: String,
        ext: String,
        author: String,
        size: Int,
        simhash: String,
        scanDir: String,
        scannedAt: Date = .now,
        tags: [String]? = nil,
        sourceReportID: UUID? = nil,
        batchName: String? = nil,
        challengeName: String? = nil,
        teamName: String? = nil,
        submissionItemID: UUID? = nil
    ) {
        self.id = id
        self.filename = filename
        self.ext = ext
        self.author = author
        self.size = size
        self.simhash = simhash
        self.scanDir = scanDir
        self.scannedAt = scannedAt
        self.tags = tags
        self.sourceReportID = sourceReportID
        self.batchName = batchName
        self.challengeName = challengeName
        self.teamName = teamName
        self.submissionItemID = submissionItemID
    }
}

struct ExportRecord: Codable, Identifiable, Hashable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable {
        case html
        case pdf
        case csv
        case json
        case markdown
        case bundle

        var displayTitle: String {
            switch self {
            case .html, .pdf, .csv, .json:
                return rawValue.uppercased()
            case .markdown:
                return "Markdown"
            case .bundle:
                return "Evidence Bundle"
            }
        }
    }

    let id: UUID
    let reportID: UUID
    let reportTitle: String
    let format: Format
    let destinationPath: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        reportID: UUID,
        reportTitle: String,
        format: Format,
        destinationPath: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.reportID = reportID
        self.reportTitle = reportTitle
        self.format = format
        self.destinationPath = destinationPath
        self.createdAt = createdAt
    }
}

struct WhitelistRule: Codable, Identifiable, Hashable, Sendable {
    enum RuleType: String, Codable, CaseIterable, Sendable {
        case author
        case filename
        case simhash
        case textSnippet
        case codeTemplate
        case imageHash
        case metadata
        case pathPattern

        var displayTitle: String {
            switch self {
            case .author: return "作者"
            case .filename: return "文件名"
            case .simhash: return "SimHash"
            case .textSnippet: return "文本片段"
            case .codeTemplate: return "代码模板"
            case .imageHash: return "图片 Hash"
            case .metadata: return "元数据"
            case .pathPattern: return "路径规则"
            }
        }

        var localizationKey: String {
            switch self {
            case .author: return "whitelist.author"
            case .filename: return "whitelist.filename"
            case .simhash: return "SimHash"
            case .textSnippet: return "whitelist.textSnippet"
            case .codeTemplate: return "whitelist.codeTemplate"
            case .imageHash: return "whitelist.imageHash"
            case .metadata: return "whitelist.metadata"
            case .pathPattern: return "whitelist.pathPattern"
            }
        }
    }

    let id: UUID
    let type: RuleType
    let pattern: String
    let createdAt: Date

    init(id: UUID = UUID(), type: RuleType, pattern: String, createdAt: Date = .now) {
        self.id = id
        self.type = type
        self.pattern = pattern
        self.createdAt = createdAt
    }
}

struct MigrationSummary: Hashable, Sendable {
    let importedJobs: Int
    let importedReports: Int
    let importedFingerprints: Int
    let importedWhitelistRules: Int
    let lastConfiguration: AuditConfiguration?
}

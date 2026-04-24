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

    init(
        id: UUID = UUID(),
        columns: [String],
        detailTitle: String,
        detailBody: String,
        badges: [ReportBadge] = [],
        attachments: [ReportAttachment] = []
    ) {
        self.id = id
        self.columns = columns
        self.detailTitle = detailTitle
        self.detailBody = detailBody
        self.badges = badges
        self.attachments = attachments
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

    init(
        id: UUID = UUID(),
        filename: String,
        ext: String,
        author: String,
        size: Int,
        simhash: String,
        scanDir: String,
        scannedAt: Date = .now
    ) {
        self.id = id
        self.filename = filename
        self.ext = ext
        self.author = author
        self.size = size
        self.simhash = simhash
        self.scanDir = scanDir
        self.scannedAt = scannedAt
    }
}

struct ExportRecord: Codable, Identifiable, Hashable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable {
        case html
        case pdf

        var displayTitle: String {
            rawValue.uppercased()
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

        var displayTitle: String {
            switch self {
            case .author: return "作者"
            case .filename: return "文件名"
            case .simhash: return "SimHash"
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

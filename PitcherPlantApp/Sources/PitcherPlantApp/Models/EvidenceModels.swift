import Foundation

enum EvidenceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case code
    case image
    case metadata
    case dedup
    case crossBatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "文本"
        case .code: return "代码"
        case .image: return "图片"
        case .metadata: return "元数据"
        case .dedup: return "重复"
        case .crossBatch: return "跨批次"
        }
    }

    var sectionKind: ReportSectionKind {
        switch self {
        case .text: return .text
        case .code: return .code
        case .image: return .image
        case .metadata: return .metadata
        case .dedup: return .dedup
        case .crossBatch: return .crossBatch
        }
    }
}

enum RiskLevel: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "未评级"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var badgeTone: ReportBadge.Tone {
        switch self {
        case .none: return .neutral
        case .low: return .accent
        case .medium: return .warning
        case .high: return .danger
        }
    }

    var priority: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

struct RiskAssessment: Codable, Hashable, Sendable {
    var score: Double
    var level: RiskLevel
    var reasons: [String]
    var evidenceCount: Int

    init(score: Double, level: RiskLevel? = nil, reasons: [String], evidenceCount: Int = 1) {
        let clamped = min(max(score, 0), 1)
        self.score = clamped
        self.level = level ?? RiskLevel(score: clamped)
        self.reasons = reasons
        self.evidenceCount = evidenceCount
    }

    var formattedScore: String {
        String(format: "%.0f", score * 100)
    }
}

extension RiskLevel {
    init(score: Double) {
        if score >= 0.80 {
            self = .high
        } else if score >= 0.60 {
            self = .medium
        } else if score >= 0.35 {
            self = .low
        } else {
            self = .none
        }
    }
}

enum EvidenceDecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case confirmed
    case falsePositive
    case ignored
    case whitelisted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待复核"
        case .confirmed: return "确认违规"
        case .falsePositive: return "误报"
        case .ignored: return "忽略"
        case .whitelisted: return "白名单"
        }
    }

    var badgeTone: ReportBadge.Tone {
        switch self {
        case .pending: return .neutral
        case .confirmed: return .danger
        case .falsePositive: return .success
        case .ignored: return .neutral
        case .whitelisted: return .success
        }
    }
}

struct EvidenceReview: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let reportID: UUID
    let evidenceID: UUID
    var evidenceType: EvidenceType
    var decision: EvidenceDecision
    var severity: RiskLevel?
    var reviewerNote: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        reportID: UUID,
        evidenceID: UUID,
        evidenceType: EvidenceType,
        decision: EvidenceDecision = .pending,
        severity: RiskLevel? = nil,
        reviewerNote: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.reportID = reportID
        self.evidenceID = evidenceID
        self.evidenceType = evidenceType
        self.decision = decision
        self.severity = severity
        self.reviewerNote = reviewerNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updated(decision: EvidenceDecision, severity: RiskLevel?, reviewerNote: String) -> EvidenceReview {
        var copy = self
        copy.decision = decision
        copy.severity = severity
        copy.reviewerNote = reviewerNote
        copy.updatedAt = .now
        return copy
    }
}

struct EvidenceRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let type: EvidenceType
    let fileA: String
    let fileB: String
    let score: Double
    let evidence: String
    let detailLines: [String]
    let attachments: [ReportAttachment]
    let riskAssessment: RiskAssessment

    init(
        id: UUID? = nil,
        type: EvidenceType,
        fileA: String,
        fileB: String,
        score: Double,
        evidence: String,
        detailLines: [String] = [],
        attachments: [ReportAttachment] = [],
        riskAssessment: RiskAssessment? = nil
    ) {
        self.id = id ?? UUID.pitcherPlantStable(namespace: "evidence", components: [type.rawValue, fileA, fileB, evidence])
        self.type = type
        self.fileA = fileA
        self.fileB = fileB
        self.score = min(max(score, 0), 1)
        self.evidence = evidence
        self.detailLines = detailLines
        self.attachments = attachments
        self.riskAssessment = riskAssessment ?? RiskAssessment(
            score: min(max(score, 0), 1),
            reasons: [type.title],
            evidenceCount: 1
        )
    }

    func reportRow(label: String, extraBadges: [ReportBadge] = []) -> ReportTableRow {
        let riskBadge = ReportBadge(title: "\(riskAssessment.level.title)风险 \(riskAssessment.formattedScore)", tone: riskAssessment.level.badgeTone)
        return ReportTableRow(
            id: id,
            columns: [fileA, fileB, String(format: "%.2f%%", score * 100), evidence],
            detailTitle: "\(fileA) ↔ \(fileB)",
            detailBody: detailBody(label: label),
            badges: [riskBadge] + extraBadges,
            attachments: attachments,
            evidenceID: id,
            evidenceType: type,
            riskAssessment: riskAssessment
        )
    }

    private func detailBody(label: String) -> String {
        var parts = ["\(label)：\(String(format: "%.2f%%", score * 100))"]
        if detailLines.isEmpty == false {
            parts.append(detailLines.joined(separator: "\n"))
        }
        if riskAssessment.reasons.isEmpty == false {
            parts.append("风险原因：\(riskAssessment.reasons.joined(separator: "、"))")
        }
        parts.append("证据：\(evidence)")
        return parts.joined(separator: "\n\n")
    }
}

struct RiskAggregate: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileA: String
    let fileB: String
    let assessment: RiskAssessment
    let evidenceTypes: [EvidenceType]
    let records: [EvidenceRecord]

    var reasonSummary: String {
        assessment.reasons.joined(separator: " + ")
    }
}

struct SubmissionBatch: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case imported
        case queued
        case audited
        case failed
    }

    let id: UUID
    var name: String
    var sourcePath: String
    var destinationPath: String
    var status: Status
    var itemCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        destinationPath: String,
        status: Status = .imported,
        itemCount: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.status = status
        self.itemCount = itemCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SubmissionItem: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case ready
        case queued
        case audited
        case failed
    }

    let id: UUID
    let batchID: UUID
    var teamName: String
    var rootPath: String
    var fileCount: Int
    var ignoredCount: Int
    var problemCount: Int
    var status: Status
    var createdAt: Date

    init(
        id: UUID = UUID(),
        batchID: UUID,
        teamName: String,
        rootPath: String,
        fileCount: Int,
        ignoredCount: Int = 0,
        problemCount: Int = 0,
        status: Status = .ready,
        createdAt: Date = .now
    ) {
        self.id = id
        self.batchID = batchID
        self.teamName = teamName
        self.rootPath = rootPath
        self.fileCount = fileCount
        self.ignoredCount = ignoredCount
        self.problemCount = problemCount
        self.status = status
        self.createdAt = createdAt
    }
}

struct DocumentFeature: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let documentPath: String
    let filename: String
    let ext: String
    let textLength: Int
    let simhash: String
    let keywordSignature: [String]
    let codeTokenSignature: [String]
    let imageHashPrefixes: [String]
    let author: String
    let updatedAt: Date

    init(document: ParsedDocument, updatedAt: Date = .now) {
        self.id = UUID.pitcherPlantStable(namespace: "document-feature", components: [document.url.path])
        self.documentPath = document.url.path
        self.filename = document.filename
        self.ext = document.ext
        self.textLength = document.cleanText.count
        self.simhash = SimHasher.hexHash(for: document.cleanText)
        self.keywordSignature = DocumentFeature.keywords(from: document.cleanText)
        self.codeTokenSignature = Array(Set(CodeBlockExtractor.candidates(from: document.codeBlocks).flatMap(\.lexicalTokens))).sorted()
        self.imageHashPrefixes = document.images.flatMap { image in
            [image.perceptualHash, image.averageHash, image.differenceHash].map { String($0.prefix(6)) }
        }
        self.author = document.author.isEmpty ? document.lastModifiedBy : document.author
        self.updatedAt = updatedAt
    }

    private static func keywords(from text: String) -> [String] {
        let tokens = text.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        let counts = Dictionary(grouping: tokens, by: { $0 }).mapValues(\.count)
        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(24)
            .map(\.key)
    }
}

extension UUID {
    static func pitcherPlantStable(namespace: String, components: [String]) -> UUID {
        let value = ([namespace] + components).joined(separator: "\u{1F}")
        var left: UInt64 = 1469598103934665603
        var right: UInt64 = 1099511628211
        for byte in value.utf8 {
            left ^= UInt64(byte)
            left = left &* 1099511628211
            right ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            right = right &* 1469598103934665603
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((left >> UInt64((7 - index) * 8)) & 0xff)
            bytes[index + 8] = UInt8((right >> UInt64((7 - index) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

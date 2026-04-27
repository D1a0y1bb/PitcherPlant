import Foundation

struct AuditRunResult {
    let report: AuditReport
    let fingerprints: [FingerprintRecord]
    let summary: AuditRunSummary
}

struct AuditRunSummary: Hashable, Sendable {
    let documentCount: Int
    let imageCount: Int
    let historicalFingerprintCount: Int
    let duration: TimeInterval
}

struct AuditRunLimits: Hashable, Sendable {
    let largeDocumentCount: Int
    let largeImageCount: Int
    let largeHistoricalFingerprintCount: Int

    static let defaults = AuditRunLimits(
        largeDocumentCount: 120,
        largeImageCount: 400,
        largeHistoricalFingerprintCount: 2_000
    )
}

struct ParsedDocument: Hashable, Sendable {
    let url: URL
    let filename: String
    let ext: String
    let content: String
    let cleanText: String
    let codeBlocks: [String]
    let author: String
    let lastModifiedBy: String
    let images: [ParsedImage]

    init(
        url: URL,
        filename: String,
        ext: String,
        content: String,
        cleanText: String,
        codeBlocks: [String],
        author: String,
        lastModifiedBy: String = "",
        images: [ParsedImage]
    ) {
        self.url = url
        self.filename = filename
        self.ext = ext
        self.content = content
        self.cleanText = cleanText
        self.codeBlocks = codeBlocks
        self.author = author
        self.lastModifiedBy = lastModifiedBy
        self.images = images
    }
}

struct ParsedImage: Hashable, Sendable {
    let source: String
    let perceptualHash: String
    let averageHash: String
    let differenceHash: String
    let ocrPreview: String
    let thumbnailBase64: String

    init(
        source: String,
        perceptualHash: String = "",
        averageHash: String,
        differenceHash: String,
        ocrPreview: String,
        thumbnailBase64: String
    ) {
        self.source = source
        self.perceptualHash = perceptualHash.isEmpty ? averageHash : perceptualHash
        self.averageHash = averageHash
        self.differenceHash = differenceHash
        self.ocrPreview = ocrPreview
        self.thumbnailBase64 = thumbnailBase64
    }
}

struct SuspiciousPair: Hashable, Sendable {
    let fileA: String
    let fileB: String
    let score: Double
    let evidence: String
    let detailLines: [String]
    let attachments: [ReportAttachment]

    init(
        fileA: String,
        fileB: String,
        score: Double,
        evidence: String,
        detailLines: [String] = [],
        attachments: [ReportAttachment] = []
    ) {
        self.fileA = fileA
        self.fileB = fileB
        self.score = score
        self.evidence = evidence
        self.detailLines = detailLines
        self.attachments = attachments
    }
}

struct MetadataCollision: Hashable, Sendable {
    let author: String
    let files: [String]
}

struct CrossBatchMatch: Hashable, Sendable {
    let currentFile: String
    let previousFile: String
    let previousScan: String
    let distance: Int
    let status: String
    let sourceReportID: UUID?
    let batchName: String?
    let teamName: String?
    let challengeName: String?
    let currentBatchName: String?
    let currentTeamName: String?
    let currentChallengeName: String?
    let currentSimhash: String?
    let historicalSimhash: String?
    let currentAuthor: String?
    let historicalAuthor: String?
    let tags: [String]

    init(
        currentFile: String,
        previousFile: String,
        previousScan: String,
        distance: Int,
        status: String,
        sourceReportID: UUID? = nil,
        batchName: String? = nil,
        teamName: String? = nil,
        challengeName: String? = nil,
        currentBatchName: String? = nil,
        currentTeamName: String? = nil,
        currentChallengeName: String? = nil,
        currentSimhash: String? = nil,
        historicalSimhash: String? = nil,
        currentAuthor: String? = nil,
        historicalAuthor: String? = nil,
        tags: [String] = []
    ) {
        self.currentFile = currentFile
        self.previousFile = previousFile
        self.previousScan = previousScan
        self.distance = distance
        self.status = status
        self.sourceReportID = sourceReportID
        self.batchName = Self.normalized(batchName)
        self.teamName = Self.normalized(teamName)
        self.challengeName = Self.normalized(challengeName)
        self.currentBatchName = Self.normalized(currentBatchName)
        self.currentTeamName = Self.normalized(currentTeamName)
        self.currentChallengeName = Self.normalized(currentChallengeName)
        self.currentSimhash = Self.normalized(currentSimhash)
        self.historicalSimhash = Self.normalized(historicalSimhash)
        self.currentAuthor = Self.normalized(currentAuthor)
        self.historicalAuthor = Self.normalized(historicalAuthor)
        self.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false })).sorted()
    }

    var displayBatchName: String {
        batchName ?? previousScan
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

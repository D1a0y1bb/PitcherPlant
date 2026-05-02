import Foundation

struct AuditRunResult: Sendable {
    let report: AuditReport
    let fingerprints: [FingerprintRecord]
    let summary: AuditRunSummary
    let documentFeatureResult: DocumentFeatureBuildResult?
    let documents: [ParsedDocument]
}

struct AuditRunPreflight: Hashable, Sendable {
    let scannedFileCount: Int
    let totalBytes: Int64
    let historicalFingerprintCount: Int
    let supportedFileCount: Int

    var estimatedDocumentCount: Int {
        supportedFileCount
    }

    func exceeds(_ limits: AuditRunLimits) -> Bool {
        supportedFileCount >= limits.largeDocumentCount
            || historicalFingerprintCount >= limits.largeHistoricalFingerprintCount
    }

    func warningMessage(limits: AuditRunLimits) -> String? {
        guard exceeds(limits) else {
            return nil
        }
        let formattedBytes = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "样本规模较大：预计文档 \(supportedFileCount) 个、扫描 \(scannedFileCount) 个文件、大小 \(formattedBytes)、历史指纹 \(historicalFingerprintCount) 条，预计耗时较长。"
    }
}

struct AuditRunSummary: Hashable, Sendable {
    let documentCount: Int
    let imageCount: Int
    let historicalFingerprintCount: Int
    let duration: TimeInterval
    let recallStats: [RecallStats]

    init(
        documentCount: Int,
        imageCount: Int,
        historicalFingerprintCount: Int,
        duration: TimeInterval,
        recallStats: [RecallStats] = []
    ) {
        self.documentCount = documentCount
        self.imageCount = imageCount
        self.historicalFingerprintCount = historicalFingerprintCount
        self.duration = duration
        self.recallStats = recallStats
    }
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
    let whitelistEvaluation: WhitelistEvaluation?

    init(
        fileA: String,
        fileB: String,
        score: Double,
        evidence: String,
        detailLines: [String] = [],
        attachments: [ReportAttachment] = [],
        whitelistEvaluation: WhitelistEvaluation? = nil
    ) {
        self.fileA = fileA
        self.fileB = fileB
        self.score = score
        self.evidence = evidence
        self.detailLines = detailLines
        self.attachments = attachments
        self.whitelistEvaluation = whitelistEvaluation
    }

    func withWhitelistEvaluation(_ evaluation: WhitelistEvaluation) -> SuspiciousPair {
        guard evaluation.isClear == false else { return self }
        return SuspiciousPair(
            fileA: fileA,
            fileB: fileB,
            score: score * evaluation.scoreMultiplier,
            evidence: evidence,
            detailLines: detailLines + [
                "白名单状态：\(evaluation.status.title)",
                "白名单原因：\(evaluation.reason)"
            ],
            attachments: attachments,
            whitelistEvaluation: evaluation
        )
    }
}

struct MetadataCollision: Hashable, Sendable {
    let author: String
    let files: [String]
    let whitelistEvaluation: WhitelistEvaluation?

    init(author: String, files: [String], whitelistEvaluation: WhitelistEvaluation? = nil) {
        self.author = author
        self.files = files
        self.whitelistEvaluation = whitelistEvaluation
    }
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
    let whitelistEvaluation: WhitelistEvaluation?

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
        tags: [String] = [],
        whitelistEvaluation: WhitelistEvaluation? = nil
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
        self.whitelistEvaluation = whitelistEvaluation
    }

    var displayBatchName: String {
        batchName ?? previousScan
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

enum AppWindow: String {
    case main
}

enum MainSidebarItem: String, Codable, CaseIterable, Identifiable, Sendable {
    case workspace
    case allEvidence
    case favoriteEvidence
    case watchedEvidence
    case newAudit
    case history
    case reports
    case textEvidence
    case codeEvidence
    case imageEvidence
    case metadataEvidence
    case dedupEvidence
    case crossBatchEvidence
    case fingerprints
    case whitelist
    case scrollEdgeLab
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "工作台"
        case .allEvidence: return "全部证据"
        case .favoriteEvidence: return "收藏"
        case .watchedEvidence: return "关注"
        case .newAudit: return "新建审计"
        case .history: return "历史任务"
        case .reports: return "报告中心"
        case .textEvidence: return "文本"
        case .codeEvidence: return "代码"
        case .imageEvidence: return "图片"
        case .metadataEvidence: return "元数据"
        case .dedupEvidence: return "重复"
        case .crossBatchEvidence: return "跨批次"
        case .fingerprints: return "指纹库"
        case .whitelist: return "白名单"
        case .scrollEdgeLab: return "滚动边缘测试"
        case .settings: return "设置"
        }
    }

    var localizationKey: String {
        switch self {
        case .workspace: return "sidebar.workspace"
        case .allEvidence: return "sidebar.allEvidence"
        case .favoriteEvidence: return "sidebar.favorites"
        case .watchedEvidence: return "sidebar.watched"
        case .newAudit: return "sidebar.newAudit"
        case .history: return "sidebar.history"
        case .reports: return "sidebar.reports"
        case .textEvidence: return "sidebar.textEvidence"
        case .codeEvidence: return "sidebar.codeEvidence"
        case .imageEvidence: return "sidebar.imageEvidence"
        case .metadataEvidence: return "sidebar.metadataEvidence"
        case .dedupEvidence: return "sidebar.dedupEvidence"
        case .crossBatchEvidence: return "sidebar.crossBatchEvidence"
        case .fingerprints: return "sidebar.fingerprints"
        case .whitelist: return "sidebar.whitelist"
        case .scrollEdgeLab: return "sidebar.scrollEdgeLab"
        case .settings: return "sidebar.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .workspace: return "square.grid.2x2.fill"
        case .allEvidence: return "list.bullet"
        case .favoriteEvidence: return "star.fill"
        case .watchedEvidence: return "eye.fill"
        case .newAudit: return "play.circle.fill"
        case .history: return "clock.arrow.circlepath"
        case .reports: return "doc.text.magnifyingglass"
        case .textEvidence: return "text.quote"
        case .codeEvidence: return "curlybraces"
        case .imageEvidence: return "photo.on.rectangle"
        case .metadataEvidence: return "person.text.rectangle"
        case .dedupEvidence: return "doc.on.doc"
        case .crossBatchEvidence: return "arrow.triangle.branch"
        case .fingerprints: return "server.rack"
        case .whitelist: return "checklist"
        case .scrollEdgeLab: return "rectangle.topthird.inset.filled"
        case .settings: return "gearshape.fill"
        }
    }

    var reportSectionKind: ReportSectionKind? {
        switch self {
        case .textEvidence: return .text
        case .codeEvidence: return .code
        case .imageEvidence: return .image
        case .metadataEvidence: return .metadata
        case .dedupEvidence: return .dedup
        case .crossBatchEvidence: return .crossBatch
        default: return nil
        }
    }

    var evidenceCollectionScope: EvidenceCollectionScope? {
        switch self {
        case .allEvidence: return .all
        case .favoriteEvidence: return .favorites
        case .watchedEvidence: return .watched
        default: return nil
        }
    }

    var usesReportInspector: Bool {
        self == .reports || reportSectionKind != nil || evidenceCollectionScope != nil
    }

    var allowsInspector: Bool {
        switch self {
        case .workspace, .allEvidence, .favoriteEvidence, .watchedEvidence, .history, .reports, .textEvidence, .codeEvidence, .imageEvidence, .metadataEvidence, .dedupEvidence, .crossBatchEvidence:
            return true
        case .newAudit, .fingerprints, .whitelist, .scrollEdgeLab, .settings:
            return false
        }
    }
}

enum EvidenceCollectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case watched

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .all: return "sidebar.allEvidence"
        case .favorites: return "sidebar.favorites"
        case .watched: return "sidebar.watched"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .favorites: return "star.fill"
        case .watched: return "eye.fill"
        }
    }
}

enum AuditJobStatus: String, Codable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed

    var displayTitle: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "运行中"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        }
    }

    var localizationKey: String {
        switch self {
        case .queued: return "status.queued"
        case .running: return "status.running"
        case .succeeded: return "status.succeeded"
        case .failed: return "status.failed"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: return "clock"
        case .running: return "play.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

enum AuditStage: String, Codable, CaseIterable {
    case queued
    case initialize
    case scan
    case parse
    case parsed
    case ocrImages
    case features
    case recall
    case text
    case code
    case image
    case metadata
    case crossBatch
    case aggregate
    case export
    case done

    var progress: Int {
        switch self {
        case .queued: return 0
        case .initialize: return 5
        case .scan: return 8
        case .parse: return 15
        case .parsed: return 15
        case .ocrImages: return 22
        case .features: return 28
        case .recall: return 32
        case .text: return 35
        case .code: return 55
        case .image: return 75
        case .metadata: return 85
        case .crossBatch: return 88
        case .aggregate: return 92
        case .export: return 96
        case .done: return 100
        }
    }

    var displayTitle: String {
        switch self {
        case .queued: return "等待开始"
        case .initialize: return "初始化"
        case .scan: return "扫描文件"
        case .parse: return "解析文档"
        case .parsed: return "解析文档完成"
        case .ocrImages: return "OCR / 图片提取"
        case .features: return "生成特征"
        case .recall: return "候选召回"
        case .text: return "文本分析完成"
        case .code: return "代码分析完成"
        case .image: return "图片分析完成"
        case .metadata: return "元数据分析完成"
        case .crossBatch: return "跨批次匹配"
        case .aggregate: return "风险聚合"
        case .export: return "报告导出"
        case .done: return "报告生成完成"
        }
    }

    var localizationKey: String {
        switch self {
        case .queued: return "stage.queued"
        case .initialize: return "stage.initialize"
        case .scan: return "stage.scan"
        case .parse: return "stage.parse"
        case .parsed: return "stage.parsed"
        case .ocrImages: return "stage.ocrImages"
        case .features: return "stage.features"
        case .recall: return "stage.recall"
        case .text: return "stage.text"
        case .code: return "stage.code"
        case .image: return "stage.image"
        case .metadata: return "stage.metadata"
        case .crossBatch: return "stage.crossBatch"
        case .aggregate: return "stage.aggregate"
        case .export: return "stage.export"
        case .done: return "stage.done"
        }
    }
}

struct AuditConfiguration: Codable, Hashable, Sendable {
    static let standardTextThreshold = 0.75
    static let standardImageThreshold = 5
    static let standardDedupThreshold = 0.85
    static let standardSimhashThreshold = 4
    static let defaultReportNameTemplate = "{dir}_PitcherPlant_{date}.html"

    var directoryPath: String
    var outputDirectoryPath: String
    var reportNameTemplate: String
    var textThreshold: Double
    var imageThreshold: Int
    var dedupThreshold: Double
    var simhashThreshold: Int
    var useVisionOCR: Bool
    var whitelistMode: WhitelistMode

    enum WhitelistMode: String, Codable, CaseIterable, Sendable {
        case mark
        case hide

        var displayTitle: String {
            switch self {
            case .mark: return "标记"
            case .hide: return "隐藏"
            }
        }

        var localizationKey: String {
            switch self {
            case .mark: return "mode.mark"
            case .hide: return "mode.hide"
            }
        }
    }

    static func defaults(for root: URL) -> AuditConfiguration {
        return AuditConfiguration(
            directoryPath: defaultInputDirectory(for: root).path,
            outputDirectoryPath: defaultOutputDirectory(for: root).path,
            reportNameTemplate: defaultReportNameTemplate,
            textThreshold: standardTextThreshold,
            imageThreshold: standardImageThreshold,
            dedupThreshold: standardDedupThreshold,
            simhashThreshold: standardSimhashThreshold,
            useVisionOCR: true,
            whitelistMode: .mark
        )
    }

    static func defaultInputDirectory(for root: URL) -> URL {
        let bundledFixturePath = root.appendingPathComponent("Fixtures/WriteupSamples/date", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundledFixturePath.path) {
            return bundledFixturePath
        }
        return root.appendingPathComponent("WriteupSamples", isDirectory: true)
    }

    static func defaultOutputDirectory(for root: URL) -> URL {
        root.appendingPathComponent("GeneratedReports/full", isDirectory: true)
    }
}

enum AuditToolbarScanMode: String, CaseIterable, Sendable {
    case auto
    case deep
    case standard
    case quick
}

enum AuditToolbarTemplate: String, CaseIterable, Sendable {
    case defaultAudit
    case evidenceReview
    case fastScreening
}

extension AuditConfiguration {
    private static let temporaryReportPrefix = "temporary_"

    var toolbarTemporaryScanEnabled: Bool {
        reportNameTemplate.hasPrefix(Self.temporaryReportPrefix)
    }

    mutating func applyToolbarScanMode(_ mode: AuditToolbarScanMode) {
        switch mode {
        case .auto, .standard:
            applyStandardScanProfile()
        case .deep:
            textThreshold = 0.67
            dedupThreshold = 0.78
            imageThreshold = 8
            simhashThreshold = 7
            useVisionOCR = true
            whitelistMode = .mark
        case .quick:
            textThreshold = 0.86
            dedupThreshold = 0.92
            imageThreshold = 3
            simhashThreshold = 2
            useVisionOCR = false
            whitelistMode = .mark
        }
    }

    mutating func applyToolbarTemplate(_ template: AuditToolbarTemplate) {
        let temporaryEnabled = toolbarTemporaryScanEnabled
        switch template {
        case .defaultAudit:
            applyStandardScanProfile()
            reportNameTemplate = Self.defaultReportNameTemplate
        case .evidenceReview:
            textThreshold = 0.70
            dedupThreshold = 0.80
            imageThreshold = 8
            simhashThreshold = 6
            useVisionOCR = true
            whitelistMode = .mark
            reportNameTemplate = "{dir}_EvidenceReview_{date}.html"
        case .fastScreening:
            applyToolbarScanMode(.quick)
            reportNameTemplate = "{dir}_QuickScreen_{date}.html"
        }
        setToolbarTemporaryScanEnabled(temporaryEnabled)
    }

    mutating func setToolbarTemporaryScanEnabled(_ enabled: Bool) {
        if enabled {
            guard toolbarTemporaryScanEnabled == false else {
                return
            }
            reportNameTemplate = Self.temporaryReportPrefix + reportNameTemplate
        } else if toolbarTemporaryScanEnabled {
            reportNameTemplate.removeFirst(Self.temporaryReportPrefix.count)
        }
    }

    private mutating func applyStandardScanProfile() {
        textThreshold = Self.standardTextThreshold
        imageThreshold = Self.standardImageThreshold
        dedupThreshold = Self.standardDedupThreshold
        simhashThreshold = Self.standardSimhashThreshold
        useVisionOCR = true
        whitelistMode = .mark
    }
}

struct AuditConfigurationPreset: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var configuration: AuditConfiguration
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        configuration: AuditConfiguration,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AuditJobEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let message: String
    let progress: Int
    var stage: AuditStage?
    var processedCount: Int?
    var failedCount: Int?
    var failedFiles: [String]
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        message: String,
        progress: Int,
        stage: AuditStage? = nil,
        processedCount: Int? = nil,
        failedCount: Int? = nil,
        failedFiles: [String] = [],
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.progress = progress
        self.stage = stage
        self.processedCount = processedCount
        self.failedCount = failedCount
        self.failedFiles = failedFiles
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case message
        case progress
        case stage
        case processedCount
        case failedCount
        case failedFiles
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        message = try container.decode(String.self, forKey: .message)
        progress = try container.decode(Int.self, forKey: .progress)
        stage = try container.decodeIfPresent(AuditStage.self, forKey: .stage)
        processedCount = try container.decodeIfPresent(Int.self, forKey: .processedCount)
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount)
        failedFiles = try container.decodeIfPresent([String].self, forKey: .failedFiles) ?? []
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}

struct AuditJob: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var configuration: AuditConfiguration
    var status: AuditJobStatus
    var stage: AuditStage
    var progress: Int
    var latestMessage: String
    var createdAt: Date
    var updatedAt: Date
    var reportID: UUID?
    var errorMessage: String?
    var events: [AuditJobEvent]
    var attempt: Int?
    var batchID: UUID?
    var submissionItemID: UUID?

    init(id: UUID = UUID(), configuration: AuditConfiguration) {
        self.id = id
        self.configuration = configuration
        self.status = .queued
        self.stage = .queued
        self.progress = 0
        self.latestMessage = "任务已创建"
        self.createdAt = .now
        self.updatedAt = .now
        self.events = [AuditJobEvent(message: "任务已创建", progress: 0)]
        self.attempt = 1
    }

    func advanced(
        stage: AuditStage,
        message: String,
        processedCount: Int? = nil,
        failedCount: Int? = nil,
        failedFiles: [String] = [],
        duration: TimeInterval? = nil
    ) -> AuditJob {
        var copy = self
        copy.status = .running
        copy.stage = stage
        copy.progress = stage.progress
        copy.latestMessage = message
        copy.updatedAt = .now
        copy.events.append(AuditJobEvent(
            message: message,
            progress: stage.progress,
            stage: stage,
            processedCount: processedCount,
            failedCount: failedCount,
            failedFiles: failedFiles,
            duration: duration
        ))
        copy.events = Array(copy.events.suffix(20))
        return copy
    }

    func completed(reportID: UUID, summaryMessage: String? = nil) -> AuditJob {
        var copy = advanced(stage: .done, message: AuditStage.done.displayTitle)
        copy.status = .succeeded
        copy.reportID = reportID
        if let summaryMessage, !summaryMessage.isEmpty {
            copy.latestMessage = summaryMessage
            copy.events.append(AuditJobEvent(message: summaryMessage, progress: AuditStage.done.progress))
            copy.events = Array(copy.events.suffix(20))
        }
        return copy
    }

    func failed(_ message: String) -> AuditJob {
        var copy = self
        copy.status = .failed
        copy.errorMessage = message
        copy.latestMessage = message
        copy.updatedAt = .now
        copy.events.append(AuditJobEvent(message: "任务失败: \(message)", progress: progress))
        copy.events = Array(copy.events.suffix(20))
        return copy
    }

    func retried() -> AuditJob {
        var copy = self
        copy.status = .queued
        copy.stage = .queued
        copy.progress = 0
        copy.errorMessage = nil
        copy.latestMessage = "任务已重新排队"
        copy.updatedAt = .now
        copy.attempt = (attempt ?? 1) + 1
        copy.events.append(AuditJobEvent(message: "第 \(copy.attempt ?? 1) 次尝试已排队", progress: 0))
        copy.events = Array(copy.events.suffix(20))
        return copy
    }

    var failureCount: Int {
        events.reduce(errorMessage == nil ? 0 : 1) { partial, event in
            partial + (event.failedCount ?? 0)
        }
    }

    var failedFiles: [String] {
        Array(NSOrderedSet(array: events.flatMap(\.failedFiles)).compactMap { $0 as? String })
    }

    var diagnosticSummary: String {
        var lines = [
            "任务：\(configuration.directoryPath)",
            "状态：\(status.displayTitle)",
            "阶段：\(stage.displayTitle)",
            "进度：\(progress)%",
        ]
        if let errorMessage {
            lines.append("错误：\(errorMessage)")
        }
        if failedFiles.isEmpty == false {
            lines.append("失败文件：")
            lines.append(contentsOf: failedFiles.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

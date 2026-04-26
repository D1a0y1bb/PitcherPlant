import Foundation

enum AppWindow: String {
    case main
}

enum MainSidebarItem: String, Codable, CaseIterable, Identifiable, Sendable {
    case workspace
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
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "工作台"
        case .newAudit: return "新建审计"
        case .history: return "历史任务"
        case .reports: return "报告中心"
        case .textEvidence: return "文本证据"
        case .codeEvidence: return "代码证据"
        case .imageEvidence: return "图片证据"
        case .metadataEvidence: return "元数据证据"
        case .dedupEvidence: return "重复证据"
        case .crossBatchEvidence: return "跨批次证据"
        case .fingerprints: return "指纹库"
        case .whitelist: return "白名单"
        case .settings: return "设置"
        }
    }

    var localizationKey: String {
        switch self {
        case .workspace: return "sidebar.workspace"
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
        case .settings: return "sidebar.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .workspace: return "square.grid.2x2.fill"
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

    var usesReportInspector: Bool {
        self == .reports || reportSectionKind != nil
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
}

enum AuditStage: String, Codable, CaseIterable {
    case queued
    case initialize
    case parsed
    case text
    case code
    case image
    case metadata
    case done

    var progress: Int {
        switch self {
        case .queued: return 0
        case .initialize: return 5
        case .parsed: return 15
        case .text: return 35
        case .code: return 55
        case .image: return 75
        case .metadata: return 85
        case .done: return 100
        }
    }

    var displayTitle: String {
        switch self {
        case .queued: return "等待开始"
        case .initialize: return "初始化"
        case .parsed: return "解析文档完成"
        case .text: return "文本分析完成"
        case .code: return "代码分析完成"
        case .image: return "图片分析完成"
        case .metadata: return "元数据分析完成"
        case .done: return "报告生成完成"
        }
    }

    var localizationKey: String {
        switch self {
        case .queued: return "stage.queued"
        case .initialize: return "stage.initialize"
        case .parsed: return "stage.parsed"
        case .text: return "stage.text"
        case .code: return "stage.code"
        case .image: return "stage.image"
        case .metadata: return "stage.metadata"
        case .done: return "stage.done"
        }
    }
}

struct AuditConfiguration: Codable, Hashable, Sendable {
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
        let dateDir = root.appendingPathComponent("date").path
        let reportsDir = root.appendingPathComponent("reports/full").path
        return AuditConfiguration(
            directoryPath: dateDir,
            outputDirectoryPath: reportsDir,
            reportNameTemplate: "{dir}_PitcherPlant_{date}.html",
            textThreshold: 0.75,
            imageThreshold: 5,
            dedupThreshold: 0.85,
            simhashThreshold: 4,
            useVisionOCR: true,
            whitelistMode: .mark
        )
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

    init(id: UUID = UUID(), timestamp: Date = .now, message: String, progress: Int) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.progress = progress
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
    }

    func advanced(stage: AuditStage, message: String) -> AuditJob {
        var copy = self
        copy.status = .running
        copy.stage = stage
        copy.progress = stage.progress
        copy.latestMessage = message
        copy.updatedAt = .now
        copy.events.append(AuditJobEvent(message: message, progress: stage.progress))
        copy.events = Array(copy.events.suffix(20))
        return copy
    }

    func completed(reportID: UUID) -> AuditJob {
        var copy = advanced(stage: .done, message: AuditStage.done.displayTitle)
        copy.status = .succeeded
        copy.reportID = reportID
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
}

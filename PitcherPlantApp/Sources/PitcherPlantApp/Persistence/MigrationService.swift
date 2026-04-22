import Foundation
import GRDB

struct MigrationService {
    private let workspaceRoot: URL

    init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    func runIfNeeded(database: DatabaseStore) async throws -> MigrationSummary {
        let migrationName = "initial-python-import-v1"
        if try await database.hasMigration(named: migrationName) {
            return MigrationSummary(
                importedJobs: 0,
                importedReports: 0,
                importedFingerprints: 0,
                importedWhitelistRules: 0,
                lastConfiguration: nil
            )
        }

        var importedJobs = 0
        var importedReports = 0
        var importedFingerprints = 0
        var importedWhitelistRules = 0
        var importedLastConfig: AuditConfiguration?

        let webStateURL = workspaceRoot.appendingPathComponent(".pitcherplant-web-state.json")
        if FileManager.default.fileExists(atPath: webStateURL.path) {
            let state = try LegacyStateImporter.importState(from: webStateURL, workspaceRoot: workspaceRoot)
            importedLastConfig = state.lastConfiguration
            for job in state.jobs {
                try await database.upsertJob(job)
                importedJobs += 1
            }
            for report in state.reports {
                if try await database.reportExists(forSourcePath: report.sourcePath) == false {
                    try await database.saveReport(report)
                    importedReports += 1
                }
            }
        }

        let reportsDirectory = workspaceRoot.appendingPathComponent("reports")
        if FileManager.default.fileExists(atPath: reportsDirectory.path) {
            let enumerator = FileManager.default.enumerator(at: reportsDirectory, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "html" else {
                    continue
                }
                if try await database.reportExists(forSourcePath: url.path) == false {
                    let report = try LegacyStateImporter.importLegacyReport(at: url)
                    try await database.saveReport(report)
                    importedReports += 1
                }
            }
        }

        let oldDBURL = workspaceRoot.appendingPathComponent("PitcherPlant.sqlite")
        if FileManager.default.fileExists(atPath: oldDBURL.path) {
            let importResult = try await importHistoricalDatabase(from: oldDBURL, into: database)
            importedFingerprints += importResult.fingerprints
            importedWhitelistRules += importResult.whitelistRules
        }

        try await database.markMigration(name: migrationName)
        return MigrationSummary(
            importedJobs: importedJobs,
            importedReports: importedReports,
            importedFingerprints: importedFingerprints,
            importedWhitelistRules: importedWhitelistRules,
            lastConfiguration: importedLastConfig
        )
    }

    private func importHistoricalDatabase(from url: URL, into database: DatabaseStore) async throws -> (fingerprints: Int, whitelistRules: Int) {
        let queue = try DatabaseQueue(path: url.path)
        var importedFingerprints = 0
        var importedWhitelistRules = 0

        let records: [FingerprintRecord] = try await queue.read { db in
            if try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'fingerprints'") == nil {
                return []
            }
            let rows = try Row.fetchAll(db, sql: "SELECT filename, ext, author, size, simhash, scan_dir, scanned_at FROM fingerprints")
            return rows.compactMap { row in
                let scannedAt = iso8601Formatter().date(from: row["scanned_at"] ?? "") ?? .now
                return FingerprintRecord(
                    filename: row["filename"] ?? "",
                    ext: row["ext"] ?? "",
                    author: row["author"] ?? "",
                    size: row["size"] ?? 0,
                    simhash: row["simhash"] ?? "",
                    scanDir: row["scan_dir"] ?? "",
                    scannedAt: scannedAt
                )
            }
        }
        if !records.isEmpty {
            try await database.insertFingerprints(records)
            importedFingerprints = records.count
        }

        let whitelistRows: [WhitelistRule] = try await queue.read { db in
            if try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'whitelist'") == nil {
                return []
            }
            let rows = try Row.fetchAll(db, sql: "SELECT pattern, type FROM whitelist")
            return rows.compactMap { row in
                guard let typeRaw: String = row["type"], let type = WhitelistRule.RuleType(rawValue: typeRaw) else {
                    return nil
                }
                let pattern: String = row["pattern"] ?? ""
                return WhitelistRule(type: type, pattern: pattern)
            }
        }
        for rule in whitelistRows {
            try await database.upsertWhitelistRule(rule)
            importedWhitelistRules += 1
        }

        return (importedFingerprints, importedWhitelistRules)
    }
}

private enum LegacyStateImporter {
    struct ImportedState {
        var jobs: [AuditJob]
        var reports: [AuditReport]
        var lastConfiguration: AuditConfiguration?
    }

    private struct LegacyPayload: Decodable {
        struct LegacyJob: Decodable {
            struct LegacyEvent: Decodable {
                let message: String
                let progress: Int?
                let timestamp: String?
            }

            struct LegacyConfig: Decodable {
                let name_template: String?
                let text_thresh: Double?
                let img_thresh: Int?
                let dedup_thresh: Double?
                let simhash_thresh: Int?
                let whitelist_mode: String?
                let use_cv: Bool?
            }

            let id: String
            let status: String
            let progress: Int?
            let message: String?
            let directory: String
            let output_dir: String
            let report_path: String?
            let created_at: String?
            let updated_at: String?
            let error: String?
            let events: [LegacyEvent]?
            let config: LegacyConfig?
        }

        struct LegacyConfig: Decodable {
            let directory: String?
            let output_dir: String?
            let name_template: String?
            let text_thresh: Double?
            let img_thresh: Int?
            let dedup_thresh: Double?
            let simhash_thresh: Int?
            let whitelist_mode: String?
            let use_cv: Bool?
        }

        let jobs: [LegacyJob]
        let last_config: LegacyConfig?
    }

    static func importState(from url: URL, workspaceRoot: URL) throws -> ImportedState {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(LegacyPayload.self, from: data)

        let migratedJobs = payload.jobs.map { legacy in
            let config = AuditConfiguration(
                directoryPath: legacy.directory,
                outputDirectoryPath: legacy.output_dir,
                reportNameTemplate: legacy.config?.name_template ?? "{dir}_PitcherPlant_{date}.html",
                textThreshold: legacy.config?.text_thresh ?? 0.75,
                imageThreshold: legacy.config?.img_thresh ?? 5,
                dedupThreshold: legacy.config?.dedup_thresh ?? 0.85,
                simhashThreshold: legacy.config?.simhash_thresh ?? 4,
                useVisionOCR: legacy.config?.use_cv ?? true,
                whitelistMode: AuditConfiguration.WhitelistMode(rawValue: legacy.config?.whitelist_mode ?? "mark") ?? .mark
            )
            var job = AuditJob(configuration: config)
            job.status = AuditJobStatus(rawValue: legacy.status) ?? .queued
            job.progress = legacy.progress ?? 0
            job.latestMessage = legacy.message ?? ""
            job.errorMessage = legacy.error
            job.events = (legacy.events ?? []).map {
                AuditJobEvent(
                    timestamp: date(from: $0.timestamp),
                    message: $0.message,
                    progress: $0.progress ?? 0
                )
            }
            job.createdAt = date(from: legacy.created_at)
            job.updatedAt = date(from: legacy.updated_at)
            return job
        }

        let migratedReports = try payload.jobs.compactMap { legacy -> AuditReport? in
            guard let reportPath = legacy.report_path, FileManager.default.fileExists(atPath: reportPath) else {
                return nil
            }
            return try importLegacyReport(at: URL(fileURLWithPath: reportPath))
        }

        let lastConfiguration = payload.last_config.map {
            AuditConfiguration(
                directoryPath: $0.directory ?? workspaceRoot.appendingPathComponent("date").path,
                outputDirectoryPath: $0.output_dir ?? workspaceRoot.appendingPathComponent("reports/full").path,
                reportNameTemplate: $0.name_template ?? "{dir}_PitcherPlant_{date}.html",
                textThreshold: $0.text_thresh ?? 0.75,
                imageThreshold: $0.img_thresh ?? 5,
                dedupThreshold: $0.dedup_thresh ?? 0.85,
                simhashThreshold: $0.simhash_thresh ?? 4,
                useVisionOCR: $0.use_cv ?? true,
                whitelistMode: AuditConfiguration.WhitelistMode(rawValue: $0.whitelist_mode ?? "mark") ?? .mark
            )
        }

        return ImportedState(jobs: migratedJobs, reports: migratedReports, lastConfiguration: lastConfiguration)
    }

    static func importLegacyReport(at url: URL) throws -> AuditReport {
        let html = try String(contentsOf: url, encoding: .utf8)
        let sections = parseSections(from: html)
        let metrics = [
            ReportMetric(title: "来源", value: "Legacy HTML", systemImage: "clock.arrow.circlepath"),
            ReportMetric(title: "章节", value: "\(sections.count)", systemImage: "square.stack.3d.down.right"),
            ReportMetric(title: "路径", value: url.lastPathComponent, systemImage: "doc.richtext"),
        ]
        return AuditReport(
            title: url.deletingPathExtension().lastPathComponent,
            sourcePath: url.path,
            scanDirectoryPath: url.deletingLastPathComponent().path,
            isLegacy: true,
            metrics: metrics,
            sections: sections
        )
    }

    private static func parseSections(from html: String) -> [ReportSection] {
        let pattern = #"<h2>(.*?)</h2>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [
                ReportSection(kind: .overview, title: "Legacy 报告", summary: "已导入旧版 HTML 报告。"),
            ]
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var sections: [ReportSection] = []

        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else {
                continue
            }
            let rawTitle = String(html[range]).replacingOccurrences(of: "&gt;", with: ">")
            let title = rawTitle.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let kind = inferSectionKind(title: title)
            sections.append(
                ReportSection(
                    kind: kind,
                    title: title,
                    summary: "该章节来自旧版 HTML 报告，当前已建立索引，可外部打开原始文件查看完整内容。",
                    callouts: ["原始文件路径：\(title)"]
                )
            )
        }

        if sections.isEmpty {
            sections.append(
                ReportSection(kind: .overview, title: "Legacy 报告", summary: "已导入旧版 HTML 报告。")
            )
        }
        return sections
    }

    private static func inferSectionKind(title: String) -> ReportSectionKind {
        if title.contains("文本") { return .text }
        if title.contains("代码") { return .code }
        if title.contains("图片") { return .image }
        if title.contains("元数据") { return .metadata }
        if title.contains("重复") { return .dedup }
        if title.contains("指纹") { return .fingerprints }
        if title.contains("跨批次") || title.contains("二次审计") { return .crossBatch }
        return .overview
    }

    private static func date(from value: String?) -> Date {
        guard let value else { return .now }
        if let date = dateFormatter.date(from: value) {
            return date
        }
        return iso8601Formatter().date(from: value) ?? .now
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}

private func iso8601Formatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

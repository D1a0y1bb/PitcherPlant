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
                let scannedAt = LegacyDateParser.date(from: row["scanned_at"] ?? "") ?? .now
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

enum LegacyStateImporter {
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
        let parsedMetrics = parseMetrics(from: html)
        let metrics = parsedMetrics.isEmpty ? [
            ReportMetric(title: "来源", value: "Legacy HTML", systemImage: "clock.arrow.circlepath"),
            ReportMetric(title: "章节", value: "\(sections.count)", systemImage: "square.stack.3d.down.right"),
            ReportMetric(title: "路径", value: url.lastPathComponent, systemImage: "doc.richtext"),
        ] : parsedMetrics
        return AuditReport(
            title: url.deletingPathExtension().lastPathComponent,
            sourcePath: url.path,
            scanDirectoryPath: url.deletingLastPathComponent().path,
            isLegacy: true,
            metrics: metrics,
            sections: sections
        )
    }

    private static func parseMetrics(from html: String) -> [ReportMetric] {
        let pattern = #"<div class="card(?: ([^"]+))?">[\s\S]*?<div class="card-title">(.*?)</div>[\s\S]*?<div class="card-value">(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.compactMap { match in
            guard let titleRange = Range(match.range(at: 2), in: html),
                  let valueRange = Range(match.range(at: 3), in: html) else {
                return nil
            }
            let tone = Range(match.range(at: 1), in: html).map { String(html[$0]) } ?? ""
            let title = condenseWhitespace(plainText(fromHTMLFragment: String(html[titleRange])))
            let value = condenseWhitespace(plainText(fromHTMLFragment: String(html[valueRange])))
            guard !title.isEmpty, !value.isEmpty else {
                return nil
            }
            return ReportMetric(title: title, value: value, systemImage: systemImage(forLegacyMetricTitle: title, tone: tone))
        }
    }

    private static func parseSections(from html: String) -> [ReportSection] {
        let blocks = extractTabSectionBlocks(from: html)
        guard !blocks.isEmpty else {
            return [
                ReportSection(kind: .overview, title: "Legacy 报告", summary: "已导入旧版 HTML 报告。"),
            ]
        }

        var sections: [ReportSection] = []

        for block in blocks {
            guard let title = firstMatch(in: block, pattern: #"<h2>([\s\S]*?)</h2>"#) else {
                continue
            }
            let kind = inferSectionKind(title: title)
            let hints = parseHintTexts(from: block)
            let tableBundles = parseTables(from: block, sectionTitle: title)
            let blockRows = tableBundles.isEmpty ? parseEvidenceBlocks(from: block, sectionTitle: title) : []
            let table = buildLegacyTable(from: tableBundles, fallbackRows: blockRows)
            let summary = legacySummary(for: title, hints: hints, table: table)
            sections.append(
                ReportSection(
                    kind: kind,
                    title: title,
                    summary: summary,
                    callouts: Array(hints.prefix(4)),
                    table: table
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

    private static func extractTabSectionBlocks(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<div id="tab_[^"]+" class="section tab-section"[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else {
            return []
        }

        var blocks: [String] = []
        for (index, match) in matches.enumerated() {
            guard let start = Range(match.range, in: html)?.lowerBound else {
                continue
            }
            let end: String.Index
            if index + 1 < matches.count, let nextStart = Range(matches[index + 1].range, in: html)?.lowerBound {
                end = nextStart
            } else {
                end = html.endIndex
            }
            blocks.append(String(html[start..<end]))
        }
        return blocks
    }

    private static func parseHintTexts(from block: String) -> [String] {
        let hints = matches(in: block, pattern: #"<div class="hint"[^>]*>([\s\S]*?)</div>"#)
            .map { condenseWhitespace(plainText(fromHTMLFragment: $0)) }
            .filter { !$0.isEmpty }
        if !hints.isEmpty {
            return hints
        }

        if let summary = firstMeaningfulParagraph(in: block) {
            return [summary]
        }
        return []
    }

    private static func parseTables(from block: String, sectionTitle: String) -> [LegacyTableBundle] {
        let tableFragments = matches(in: block, pattern: #"<table[^>]*>([\s\S]*?)</table>"#)
        return tableFragments.compactMap { tableHTML in
            let headers = matches(in: tableHTML, pattern: #"<th[^>]*>([\s\S]*?)</th>"#)
                .map { condenseWhitespace(plainText(fromHTMLFragment: $0)) }
                .filter { !$0.isEmpty }

            let rowMatches = matches(in: tableHTML, pattern: #"<tr[^>]*>([\s\S]*?)</tr>"#)
            let rows = rowMatches.compactMap { rowHTML -> ReportTableRow? in
                let cells = parseCells(from: rowHTML)
                guard !cells.isEmpty else {
                    return nil
                }

                let condensedColumns = cells.map { trimmedColumn($0.text) }
                let rowTitle = detailTitle(for: condensedColumns, fallback: sectionTitle)
                let headerLabels = headers.isEmpty ? generatedHeaders(count: cells.count) : headers
                let bodyLines = zip(headerLabels, cells).map { "\($0.0)：\($0.1.text)" }
                let attachments = cells.flatMap(\.attachments)

                return ReportTableRow(
                    columns: condensedColumns,
                    detailTitle: rowTitle,
                    detailBody: bodyLines.joined(separator: "\n\n"),
                    badges: [],
                    attachments: attachments
                )
            }

            guard !rows.isEmpty else {
                return nil
            }

            return LegacyTableBundle(headers: headers.isEmpty ? generatedHeaders(count: rows.first?.columns.count ?? 0) : headers, rows: rows)
        }
    }

    private static func parseEvidenceBlocks(from block: String, sectionTitle: String) -> [ReportTableRow] {
        let blockMatches = matches(in: block, pattern: #"<div class="block"[^>]*>([\s\S]*?)</div>"#)
        return blockMatches.enumerated().compactMap { index, blockHTML in
            let title = firstMatch(in: blockHTML, pattern: #"<div class="block-title"[^>]*>([\s\S]*?)</div>"#) ?? "\(sectionTitle) \(index + 1)"
            let hints = matches(in: blockHTML, pattern: #"<div class="hint"[^>]*>([\s\S]*?)</div>"#)
                .map { condenseWhitespace(plainText(fromHTMLFragment: $0)) }
                .filter { !$0.isEmpty }
            let snippets = matches(in: blockHTML, pattern: #"<div class="snippet"[^>]*>([\s\S]*?)</div>"#)
                .map { plainText(fromHTMLFragment: $0) }
                .filter { !$0.isEmpty }
            let attachments = snippets.enumerated().map {
                ReportAttachment(
                    title: title,
                    subtitle: "证据 \($0.offset + 1)",
                    body: $0.element,
                    imageBase64: nil
                )
            }

            guard !hints.isEmpty || !snippets.isEmpty else {
                return nil
            }

            let summary = hints.first ?? String(snippets.first?.prefix(80) ?? "")
            let detail = (hints + snippets).joined(separator: "\n\n")
            return ReportTableRow(
                columns: [title, trimmedColumn(summary), "\(snippets.count)", trimmedColumn(detail)],
                detailTitle: title,
                detailBody: detail,
                badges: [ReportBadge(title: "Legacy", tone: .accent)],
                attachments: attachments
            )
        }
    }

    private static func buildLegacyTable(from bundles: [LegacyTableBundle], fallbackRows: [ReportTableRow]) -> ReportTable? {
        if !bundles.isEmpty {
            let headerSets = Set(bundles.map { $0.headers.joined(separator: "|||") })
            if headerSets.count == 1, let headers = bundles.first?.headers {
                return ReportTable(headers: headers, rows: bundles.flatMap(\.rows))
            }

            let rows = bundles.flatMap(\.rows).map { row in
                ReportTableRow(
                    id: row.id,
                    columns: [
                        row.detailTitle,
                        row.columns.first ?? "",
                        row.columns.dropFirst().first ?? "",
                        trimmedColumn(row.detailBody)
                    ],
                    detailTitle: row.detailTitle,
                    detailBody: row.detailBody,
                    badges: row.badges,
                    attachments: row.attachments
                )
            }
            return ReportTable(headers: ["条目", "摘要", "数值", "详情"], rows: rows)
        }

        guard !fallbackRows.isEmpty else {
            return nil
        }
        return ReportTable(headers: ["条目", "摘要", "证据数", "详情"], rows: fallbackRows)
    }

    private static func legacySummary(for title: String, hints: [String], table: ReportTable?) -> String {
        if let firstHint = hints.first, !firstHint.isEmpty {
            return firstHint
        }
        if let table {
            return "该章节来自旧版 HTML 报告，已映射 \(table.rows.count) 条证据到原生报告中心。"
        }
        return "该章节来自旧版 HTML 报告，当前已建立索引，可在原生报告中心查看摘要与证据。"
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

private struct LegacyTableBundle {
    let headers: [String]
    let rows: [ReportTableRow]
}

private struct LegacyCell {
    let text: String
    let attachments: [ReportAttachment]
}

private func parseCells(from rowHTML: String) -> [LegacyCell] {
    let fragments = matches(in: rowHTML, pattern: #"<td[^>]*>([\s\S]*?)</td>"#)
    return fragments.map { cellHTML in
        let text = plainText(fromHTMLFragment: cellHTML)
        let images = matches(in: cellHTML, pattern: #"src="data:image/[^;]+;base64,([^"]+)""#)
        let attachments = images.enumerated().map {
            ReportAttachment(
                title: "Legacy 图片证据",
                subtitle: "图像 \($0.offset + 1)",
                body: text,
                imageBase64: $0.element
            )
        }
        return LegacyCell(text: text, attachments: attachments)
    }
}

private func matches(in text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    return results.compactMap { match in
        let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let range = Range(capture, in: text) else {
            return nil
        }
        return String(text[range])
    }
}

private func firstMatch(in text: String, pattern: String) -> String? {
    matches(in: text, pattern: pattern).first.map {
        condenseWhitespace(plainText(fromHTMLFragment: $0))
    }
}

private func firstMeaningfulParagraph(in block: String) -> String? {
    let fragments = matches(in: block, pattern: #"<div[^>]*>([\s\S]*?)</div>"#)
    for fragment in fragments {
        let plain = condenseWhitespace(plainText(fromHTMLFragment: fragment))
        if plain.count >= 12 {
            return plain
        }
    }
    return nil
}

private func plainText(fromHTMLFragment fragment: String) -> String {
    let wrapped = "<div>\(fragment)</div>"
    if let data = wrapped.data(using: .utf8),
       let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
       ) {
        return condenseWhitespace(
            attributed.string
                .replacingOccurrences(of: "\u{00a0}", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
        )
    }

    let stripped = wrapped.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    return condenseWhitespace(stripped)
}

private func condenseWhitespace(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
        .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func trimmedColumn(_ text: String, limit: Int = 120) -> String {
    let condensed = condenseWhitespace(text)
    return condensed.count > limit ? String(condensed.prefix(limit)) + "…" : condensed
}

private func detailTitle(for columns: [String], fallback: String) -> String {
    let leading = columns.filter { !$0.isEmpty }.prefix(2)
    if !leading.isEmpty {
        return leading.joined(separator: " ↔ ")
    }
    return fallback
}

private func generatedHeaders(count: Int) -> [String] {
    guard count > 0 else {
        return ["内容"]
    }
    return (1...count).map { "列\($0)" }
}

private func systemImage(forLegacyMetricTitle title: String, tone: String) -> String {
    if title.contains("文本") || title.contains("代码") {
        return "exclamationmark.triangle.fill"
    }
    if title.contains("图片") {
        return "photo.fill.on.rectangle.fill"
    }
    if title.contains("元数据") {
        return "person.crop.rectangle"
    }
    switch tone {
    case "danger":
        return "exclamationmark.triangle.fill"
    case "warning":
        return "photo.fill.on.rectangle.fill"
    default:
        return "square.stack.3d.down.right"
    }
}

private func iso8601Formatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

private enum LegacyDateParser {
    static func date(from value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        if let iso = iso8601Formatter().date(from: value) {
            return iso
        }
        return pythonFormatter.date(from: value)
    }

    private static let pythonFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}

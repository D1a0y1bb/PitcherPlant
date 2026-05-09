import Foundation
import GRDB

struct DatabasePage<Element: Sendable>: Sendable {
    let values: [Element]
    let totalCount: Int
    let limit: Int
    let offset: Int
}

struct ReportCounts: Hashable, Sendable {
    let reportCount: Int
    let sectionCount: Int
    let evidenceRowCount: Int
}

private struct SQLiteSearchPattern {
    let value: String
    let usesEscape: Bool
}

actor DatabaseStore {
    private let dbQueue: DatabaseQueue
    private let dbURL: URL

    nonisolated var databaseURL: URL {
        dbURL
    }

    init(rootDirectory: URL) throws {
        let supportURL = try Self.resolveSupportDirectory(rootDirectory: rootDirectory)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        self.dbURL = supportURL.appendingPathComponent("PitcherPlantMac.sqlite")
        self.dbQueue = try DatabaseQueue(path: dbURL.path)
    }

    private static func resolveSupportDirectory(rootDirectory: URL) throws -> URL {
        let preferred = rootDirectory.appendingPathComponent(".pitcherplant-macos", isDirectory: true)
        if isWritableDirectoryCandidate(preferred) {
            return preferred
        }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("PitcherPlant", isDirectory: true)
            .appendingPathComponent(".pitcherplant-macos", isDirectory: true)
    }

    private static func isWritableDirectoryCandidate(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appendingPathComponent(".write-probe-\(UUID().uuidString)")
            try Data().write(to: probe)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    func prepare() async throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create-schema") { db in
            try db.create(table: "audit_jobs", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
                table.column("updated_at", .datetime).notNull()
                table.column("directory_path", .text).notNull().indexed()
                table.column("status", .text).notNull().indexed()
                table.column("stage", .text).notNull()
                table.column("progress", .integer).notNull()
                table.column("report_id", .text)
            }
            try db.create(table: "audit_reports", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("title", .text).notNull().indexed()
                table.column("source_path", .text).notNull().indexed()
                table.column("scan_directory_path", .text).notNull().indexed()
                table.column("job_id", .text)
                table.column("search_index", .text)
            }
            try db.create(table: "audit_job_events", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("job_id", .text).notNull().indexed()
                table.column("timestamp", .datetime).notNull()
                table.column("message", .text).notNull()
                table.column("progress", .integer).notNull()
                table.column("payload", .text)
            }
            try db.create(table: "report_sections", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("report_id", .text).notNull().indexed()
                table.column("position", .integer).notNull()
                table.column("kind", .text).notNull()
                table.column("title", .text).notNull()
                table.column("summary", .text).notNull()
                table.column("payload", .text).notNull()
            }
            try db.create(table: "fingerprints", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("identity_key", .text)
                table.column("payload", .text).notNull()
                table.column("simhash", .text).notNull()
                table.column("scanned_at", .datetime)
                table.column("tag_index", .text)
                table.column("search_index", .text)
            }
            try db.create(table: "whitelist_rules", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
            }
            try db.create(table: "export_records", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("report_id", .text).notNull().indexed()
                table.column("report_title", .text).notNull().indexed()
                table.column("format", .text).notNull().indexed()
                table.column("destination_path", .text).notNull()
                table.column("created_at", .datetime).notNull().indexed()
            }
            try createOperationalTables(db)
        }

        migrator.registerMigration("normalize-job-events-and-report-sections-v1") { db in
            try db.create(table: "audit_job_events", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("job_id", .text).notNull().indexed()
                table.column("timestamp", .datetime).notNull()
                table.column("message", .text).notNull()
                table.column("progress", .integer).notNull()
                table.column("payload", .text)
            }
            try ensureColumn("payload", in: "audit_job_events", type: .text, db: db)
            try db.create(table: "report_sections", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("report_id", .text).notNull().indexed()
                table.column("position", .integer).notNull()
                table.column("kind", .text).notNull()
                table.column("title", .text).notNull()
                table.column("summary", .text).notNull()
                table.column("payload", .text).notNull()
            }

            let jobRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_jobs")
            for row in jobRows {
                let jobID: String = row["id"]
                let payload: String = row["payload"]
                let job = try JSONDecoder.pitcherPlant.decodeString(AuditJob.self, from: payload)
                try db.execute(sql: "DELETE FROM audit_job_events WHERE job_id = ?", arguments: [jobID])
                for event in job.events {
                    try db.execute(
                        sql: """
                        INSERT INTO audit_job_events (id, job_id, timestamp, message, progress, payload)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [event.id.uuidString, jobID, event.timestamp, event.message, event.progress, try JSONEncoder.pitcherPlant.encodeToString(event)]
                    )
                }
            }

            let reportRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_reports")
            for row in reportRows {
                let reportID: String = row["id"]
                let payload: String = row["payload"]
                let report = try JSONDecoder.pitcherPlant.decodeString(AuditReport.self, from: payload)
                try db.execute(sql: "DELETE FROM report_sections WHERE report_id = ?", arguments: [reportID])
                for (index, section) in report.sections.enumerated() {
                    let sectionPayload = try JSONEncoder.pitcherPlant.encodeToString(section)
                    try db.execute(
                        sql: """
                        INSERT INTO report_sections (id, report_id, position, kind, title, summary, payload)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            section.id.uuidString,
                            reportID,
                            index,
                            section.kind.rawValue,
                            section.title,
                            section.summary,
                            sectionPayload
                        ]
                    )
                }
            }
        }

        migrator.registerMigration("add-indexed-columns-and-export-records-v1") { db in
            try ensureColumn("directory_path", in: "audit_jobs", type: .text, db: db)
            try ensureColumn("status", in: "audit_jobs", type: .text, db: db)
            try ensureColumn("stage", in: "audit_jobs", type: .text, db: db)
            try ensureColumn("progress", in: "audit_jobs", type: .integer, db: db)
            try ensureColumn("report_id", in: "audit_jobs", type: .text, db: db)

            try ensureColumn("title", in: "audit_reports", type: .text, db: db)
            try ensureColumn("source_path", in: "audit_reports", type: .text, db: db)
            try ensureColumn("scan_directory_path", in: "audit_reports", type: .text, db: db)
            try ensureColumn("job_id", in: "audit_reports", type: .text, db: db)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_jobs_directory_path_idx ON audit_jobs(directory_path)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_jobs_status_idx ON audit_jobs(status)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_title_idx ON audit_reports(title)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_source_path_idx ON audit_reports(source_path)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_scan_dir_idx ON audit_reports(scan_directory_path)")

            try db.create(table: "export_records", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("report_id", .text).notNull().indexed()
                table.column("report_title", .text).notNull().indexed()
                table.column("format", .text).notNull().indexed()
                table.column("destination_path", .text).notNull()
                table.column("created_at", .datetime).notNull().indexed()
            }

            let jobRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_jobs")
            for row in jobRows {
                let jobID: String = row["id"]
                let payload: String = row["payload"]
                let job = try JSONDecoder.pitcherPlant.decodeString(AuditJob.self, from: payload)
                try db.execute(
                    sql: """
                    UPDATE audit_jobs
                    SET directory_path = ?, status = ?, stage = ?, progress = ?, report_id = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        job.configuration.directoryPath,
                        job.status.rawValue,
                        job.stage.rawValue,
                        job.progress,
                        job.reportID?.uuidString,
                        jobID
                    ]
                )
            }

            let reportRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_reports")
            for row in reportRows {
                let reportID: String = row["id"]
                let payload: String = row["payload"]
                let report = try JSONDecoder.pitcherPlant.decodeString(AuditReport.self, from: payload)
                try db.execute(
                    sql: """
                    UPDATE audit_reports
                    SET title = ?, source_path = ?, scan_directory_path = ?, job_id = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        report.title,
                        report.sourcePath,
                        report.scanDirectoryPath,
                        report.jobID?.uuidString,
                        reportID
                    ]
                )
            }
        }

        migrator.registerMigration("add-review-batch-feature-tables-v1") { db in
            try createOperationalTables(db)
        }

        migrator.registerMigration("extend-document-features-cache-v1") { db in
            try extendDocumentFeaturesSchema(db)
        }

        migrator.registerMigration("remove-obsolete-report-state-v1") { db in
            try removeObsoleteReportState(db)
        }

        migrator.registerMigration("add-audit-job-event-payload-v1") { db in
            try ensureColumn("payload", in: "audit_job_events", type: .text, db: db)
            let rows = try Row.fetchAll(db, sql: "SELECT id, timestamp, message, progress FROM audit_job_events WHERE payload IS NULL OR payload = ''")
            for row in rows {
                let event = AuditJobEvent(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    timestamp: row["timestamp"],
                    message: row["message"],
                    progress: row["progress"]
                )
                try db.execute(
                    sql: "UPDATE audit_job_events SET payload = ? WHERE id = ?",
                    arguments: [try JSONEncoder.pitcherPlant.encodeToString(event), row["id"] as String]
                )
            }
        }

        migrator.registerMigration("add-fingerprint-query-columns-v1") { db in
            try ensureColumn("scanned_at", in: "fingerprints", type: .datetime, db: db)
            try ensureColumn("tag_index", in: "fingerprints", type: .text, db: db)
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM fingerprints")
            for row in rows {
                let id: String = row["id"]
                let payload: String = row["payload"]
                let record = try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: payload)
                try db.execute(
                    sql: "UPDATE fingerprints SET scanned_at = ?, tag_index = ? WHERE id = ?",
                    arguments: [record.scannedAt, fingerprintTagIndex(record.tags), id]
                )
            }
            try createFingerprintIndexes(db)
        }

        migrator.registerMigration("add-library-search-indexes-v1") { db in
            try ensureColumn("search_index", in: "audit_reports", type: .text, db: db)
            try ensureColumn("search_index", in: "fingerprints", type: .text, db: db)
            try createReportTableRows(db)

            let reportRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_reports")
            for row in reportRows {
                let reportID: String = row["id"]
                let payload: String = row["payload"]
                let report = try JSONDecoder.pitcherPlant.decodeString(AuditReport.self, from: payload)
                try db.execute(
                    sql: "UPDATE audit_reports SET search_index = ? WHERE id = ?",
                    arguments: [reportSearchIndex(report), reportID]
                )
                try replaceReportTableRows(for: report, db: db)
            }

            let fingerprintRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM fingerprints")
            for row in fingerprintRows {
                let id: String = row["id"]
                let payload: String = row["payload"]
                let record = try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: payload)
                try db.execute(
                    sql: "UPDATE fingerprints SET search_index = ? WHERE id = ?",
                    arguments: [fingerprintSearchIndex(record), id]
                )
            }
            try createLibrarySearchIndexes(db)
        }

        migrator.registerMigration("add-fingerprint-identity-key-v1") { db in
            try ensureColumn("identity_key", in: "fingerprints", type: .text, db: db)
            try normalizeFingerprintIdentities(db)
            try createFingerprintIndexes(db)
            try rebuildFingerprintSearchTable(db)
        }

        migrator.registerMigration("add-report-row-metadata-and-trigram-search-v1") { db in
            try createReportTableRows(db)
            try createSearchTables(db)
            try backfillReportRowMetadata(db)
            try rebuildSearchTables(db)
            try createLibrarySearchIndexes(db)
        }

        try migrator.migrate(dbQueue)
    }

    func upsertJob(_ job: AuditJob) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(job)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_jobs (id, payload, updated_at, directory_path, status, stage, progress, report_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    updated_at = excluded.updated_at,
                    directory_path = excluded.directory_path,
                    status = excluded.status,
                    stage = excluded.stage,
                    progress = excluded.progress,
                    report_id = excluded.report_id
                """,
                arguments: [
                    job.id.uuidString,
                    payload,
                    job.updatedAt,
                    job.configuration.directoryPath,
                    job.status.rawValue,
                    job.stage.rawValue,
                    job.progress,
                    job.reportID?.uuidString,
                ]
            )
            try upsertJobEvents(job.events, jobID: job.id.uuidString, db: db)
            try trimJobEvents(jobID: job.id.uuidString, keep: 20, db: db)
        }
    }

    func appendJobEvents(jobID: UUID, events: [AuditJobEvent]) throws {
        guard events.isEmpty == false else {
            return
        }
        try dbQueue.write { db in
            try upsertJobEvents(events, jobID: jobID.uuidString, db: db)
            try trimJobEvents(jobID: jobID.uuidString, keep: 20, db: db)
        }
    }

    func loadJobs() throws -> [AuditJob] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_jobs ORDER BY updated_at DESC")
            let eventsByJobID = try fetchJobEventsByJobID(db)
            return try rows.map { row in
                let jobID: String = row["id"]
                var job = try JSONDecoder.pitcherPlant.decodeString(AuditJob.self, from: row["payload"])
                if let events = eventsByJobID[jobID], !events.isEmpty {
                    job.events = events
                }
                return job
            }
        }
    }

    @discardableResult
    func markInterruptedJobs(message: String) throws -> Int {
        try dbQueue.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_jobs WHERE status = ?", arguments: [AuditJobStatus.running.rawValue])
            for row in rows {
                let jobID: String = row["id"]
                let payload: String = row["payload"]
                var job = try JSONDecoder.pitcherPlant.decodeString(AuditJob.self, from: payload)
                job = job.failed(message)
                let updatedPayload = try JSONEncoder.pitcherPlant.encodeToString(job)
                try db.execute(
                    sql: """
                    UPDATE audit_jobs
                    SET payload = ?, updated_at = ?, directory_path = ?, status = ?, stage = ?, progress = ?, report_id = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        updatedPayload,
                        job.updatedAt,
                        job.configuration.directoryPath,
                        job.status.rawValue,
                        job.stage.rawValue,
                        job.progress,
                        job.reportID?.uuidString,
                        jobID,
                    ]
                )
                try upsertJobEvents(job.events, jobID: jobID, db: db)
                try trimJobEvents(jobID: jobID, keep: 20, db: db)
            }
            return rows.count
        }
    }

    func saveReport(_ report: AuditReport) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(report)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_reports (id, payload, created_at, title, source_path, scan_directory_path, job_id, search_index)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    created_at = excluded.created_at,
                    title = excluded.title,
                    source_path = excluded.source_path,
                    scan_directory_path = excluded.scan_directory_path,
                    job_id = excluded.job_id,
                    search_index = excluded.search_index
                """,
                arguments: [
                    report.id.uuidString,
                    payload,
                    report.createdAt,
                    report.title,
                    report.sourcePath,
                    report.scanDirectoryPath,
                    report.jobID?.uuidString,
                    reportSearchIndex(report),
                ]
            )
            try upsertReportSearchIndex(reportID: report.id.uuidString, searchIndex: reportSearchIndex(report), db: db)
            try db.execute(sql: "DELETE FROM report_sections WHERE report_id = ?", arguments: [report.id.uuidString])
            for (index, section) in report.sections.enumerated() {
                let sectionPayload = try JSONEncoder.pitcherPlant.encodeToString(section)
                try db.execute(
                    sql: """
                    INSERT INTO report_sections (id, report_id, position, kind, title, summary, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        section.id.uuidString,
                        report.id.uuidString,
                        index,
                        section.kind.rawValue,
                        section.title,
                        section.summary,
                        sectionPayload
                    ]
                )
            }
            try replaceReportTableRows(for: report, db: db)
        }
    }

    func reportExists(forSourcePath sourcePath: String) throws -> Bool {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT id FROM audit_reports WHERE source_path = ?", arguments: [sourcePath]) != nil
        }
    }

    func loadReports() throws -> [AuditReport] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_reports ORDER BY created_at DESC")
            let sectionsByReportID = try fetchSectionsByReportID(db)
            return try rows.map { row in
                let reportID: String = row["id"]
                var report = try JSONDecoder.pitcherPlant.decodeString(AuditReport.self, from: row["payload"])
                if let sections = sectionsByReportID[reportID], !sections.isEmpty {
                    report = AuditReport(
                        id: report.id,
                        jobID: report.jobID,
                        title: report.title,
                        sourcePath: report.sourcePath,
                        scanDirectoryPath: report.scanDirectoryPath,
                        createdAt: report.createdAt,
                        metrics: report.metrics,
                        sections: sections
                    )
                }
                return report
            }
        }
    }

    func loadReportsPage(limit: Int, offset: Int = 0) throws -> DatabasePage<AuditReport> {
        let sanitizedLimit = max(1, limit)
        let sanitizedOffset = max(0, offset)
        return try dbQueue.read { db in
            let totalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_reports") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, created_at, title, source_path, scan_directory_path, job_id
                FROM audit_reports
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [sanitizedLimit, sanitizedOffset]
            )
            let reports = rows.map(reportSummary(from:))
            return DatabasePage(values: reports, totalCount: totalCount, limit: sanitizedLimit, offset: sanitizedOffset)
        }
    }

    func searchReports(query: String, limit: Int, offset: Int = 0) throws -> DatabasePage<AuditReport> {
        let sanitizedLimit = max(1, limit)
        let sanitizedOffset = max(0, offset)
        let trimmed = query.normalizedSearchQuery
        guard trimmed.isEmpty == false else {
            return try loadReportsPage(limit: sanitizedLimit, offset: sanitizedOffset)
        }

        return try dbQueue.read { db in
            let pattern = Self.sqliteSearchPattern(trimmed)
            let searchPredicate = pattern.usesEscape
                ? "audit_reports_fts.search_index LIKE ? ESCAPE '\\'"
                : "audit_reports_fts.search_index LIKE ?"
            let totalCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM audit_reports
                JOIN audit_reports_fts ON audit_reports_fts.record_id = audit_reports.id
                WHERE \(searchPredicate)
                """,
                arguments: [pattern.value]
            ) ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT audit_reports.id,
                       audit_reports.created_at,
                       audit_reports.title,
                       audit_reports.source_path,
                       audit_reports.scan_directory_path,
                       audit_reports.job_id
                FROM audit_reports
                JOIN audit_reports_fts ON audit_reports_fts.record_id = audit_reports.id
                WHERE \(searchPredicate)
                ORDER BY audit_reports.created_at DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [pattern.value, sanitizedLimit, sanitizedOffset]
            )
            let reports = rows.map(reportSummary(from:))
            return DatabasePage(values: reports, totalCount: totalCount, limit: sanitizedLimit, offset: sanitizedOffset)
        }
    }

    func loadReport(id: UUID) throws -> AuditReport? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT id, payload FROM audit_reports WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            var report = try JSONDecoder.pitcherPlant.decodeString(AuditReport.self, from: row["payload"])
            let sections = try fetchSectionsByReportID(db, reportIDs: [id.uuidString])[id.uuidString] ?? []
            if sections.isEmpty == false {
                report = report.replacingSections(sections)
            }
            return report
        }
    }

    func loadReportSections(reportID: UUID) throws -> [ReportSection] {
        try dbQueue.read { db in
            try fetchSectionsByReportID(db, reportIDs: [reportID.uuidString])[reportID.uuidString] ?? []
        }
    }

    func loadReportCounts() throws -> ReportCounts {
        try dbQueue.read { db in
            let reportCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audit_reports") ?? 0
            let sectionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report_sections") ?? 0
            let evidenceRowCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report_table_rows") ?? 0
            return ReportCounts(reportCount: reportCount, sectionCount: sectionCount, evidenceRowCount: evidenceRowCount)
        }
    }

    func loadEvidenceRows(
        reportID: UUID,
        sectionKind: ReportSectionKind? = nil,
        query: String = "",
        filter: ReportEvidenceFilter = .all,
        sortOrder: ReportEvidenceSortOrder = .default,
        limit: Int,
        offset: Int = 0
    ) throws -> DatabasePage<ReportTableRow> {
        let sanitizedLimit = max(1, limit)
        let sanitizedOffset = max(0, offset)
        let trimmed = query.normalizedSearchQuery
        return try dbQueue.read { db in
            var clauses = ["report_table_rows.report_id = ?"]
            var arguments: StatementArguments = [reportID.uuidString]
            var joins = ""
            if let sectionKind {
                clauses.append("report_table_rows.kind = ?")
                arguments += [sectionKind.rawValue]
            }
            if trimmed.isEmpty == false {
                let pattern = Self.sqliteSearchPattern(trimmed)
                joins = "JOIN report_table_rows_fts ON report_table_rows_fts.storage_id = report_table_rows.storage_id"
                clauses.append(pattern.usesEscape ? "report_table_rows_fts.search_index LIKE ? ESCAPE '\\'" : "report_table_rows_fts.search_index LIKE ?")
                arguments += [pattern.value]
            }
            switch filter {
            case .all:
                break
            case .highRisk:
                clauses.append("report_table_rows.is_high_risk = 1")
            case .withAttachments:
                clauses.append("report_table_rows.attachment_count > 0")
            }
            let whereClause = clauses.joined(separator: " AND ")
            let totalCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM report_table_rows \(joins) WHERE \(whereClause)",
                arguments: arguments
            ) ?? 0
            arguments += [sanitizedLimit, sanitizedOffset]
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT report_table_rows.payload
                FROM report_table_rows
                \(joins)
                WHERE \(whereClause)
                ORDER BY \(Self.evidenceRowOrderClause(for: sortOrder))
                LIMIT ? OFFSET ?
                """,
                arguments: arguments
            )
            let page = try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(ReportTableRow.self, from: row["payload"])
            }
            return DatabasePage(values: page, totalCount: totalCount, limit: sanitizedLimit, offset: sanitizedOffset)
        }
    }

    func deleteReport(reportID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM audit_reports WHERE id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM report_sections WHERE report_id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM report_table_rows WHERE report_id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM audit_reports_fts WHERE record_id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM report_table_rows_fts WHERE report_id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM evidence_reviews WHERE report_id = ?", arguments: [reportID.uuidString])
        }
    }

    func upsertEvidenceReview(_ review: EvidenceReview) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(review)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO evidence_reviews (id, report_id, evidence_id, evidence_type, decision, severity, reviewer_note, updated_at, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    report_id = excluded.report_id,
                    evidence_id = excluded.evidence_id,
                    evidence_type = excluded.evidence_type,
                    decision = excluded.decision,
                    severity = excluded.severity,
                    reviewer_note = excluded.reviewer_note,
                    updated_at = excluded.updated_at,
                    payload = excluded.payload
                """,
                arguments: [
                    review.id.uuidString,
                    review.reportID.uuidString,
                    review.evidenceID.uuidString,
                    review.evidenceType.rawValue,
                    review.decision.rawValue,
                    review.severity?.rawValue,
                    review.reviewerNote,
                    review.updatedAt,
                    payload
                ]
            )
        }
    }

    func loadEvidenceReviews(reportID: UUID? = nil) throws -> [EvidenceReview] {
        try dbQueue.read { db in
            let rows: [Row]
            if let reportID {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM evidence_reviews WHERE report_id = ? ORDER BY updated_at DESC", arguments: [reportID.uuidString])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM evidence_reviews ORDER BY updated_at DESC")
            }
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(EvidenceReview.self, from: row["payload"])
            }
        }
    }

    func deleteEvidenceReview(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM evidence_reviews WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func insertFingerprints(_ records: [FingerprintRecord]) throws {
        guard !records.isEmpty else {
            return
        }
        try dbQueue.write { db in
            for record in records {
                let stableRecord = record.withStableIdentity()
                let payload = try JSONEncoder.pitcherPlant.encodeToString(stableRecord)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO fingerprints (id, identity_key, payload, simhash, scanned_at, tag_index, search_index)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        stableRecord.id.uuidString,
                        stableRecord.identityKey,
                        payload,
                        stableRecord.simhash,
                        stableRecord.scannedAt,
                        fingerprintTagIndex(stableRecord.tags),
                        fingerprintSearchIndex(stableRecord)
                    ]
                )
                if db.changesCount > 0 {
                    try upsertFingerprintSearchIndex(stableRecord, db: db)
                }
            }
        }
    }

    func upsertFingerprintRecords(_ records: [FingerprintRecord]) throws {
        guard !records.isEmpty else {
            return
        }
        try dbQueue.write { db in
            for record in records {
                let stableRecord = record.withStableIdentity()
                let payload = try JSONEncoder.pitcherPlant.encodeToString(stableRecord)
                try db.execute(
                    sql: """
                    INSERT INTO fingerprints (id, identity_key, payload, simhash, scanned_at, tag_index, search_index)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(identity_key) DO UPDATE SET
                        id = excluded.id,
                        payload = excluded.payload,
                        simhash = excluded.simhash,
                        scanned_at = excluded.scanned_at,
                        tag_index = excluded.tag_index,
                        search_index = excluded.search_index
                    """,
                    arguments: [
                        stableRecord.id.uuidString,
                        stableRecord.identityKey,
                        payload,
                        stableRecord.simhash,
                        stableRecord.scannedAt,
                        fingerprintTagIndex(stableRecord.tags),
                        fingerprintSearchIndex(stableRecord)
                    ]
                )
                try upsertFingerprintSearchIndex(stableRecord, db: db)
            }
        }
    }

    func loadFingerprintRecords() throws -> [FingerprintRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM fingerprints ORDER BY scanned_at DESC")
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }
        }
    }

    func loadFingerprintPage(limit: Int, offset: Int = 0) throws -> DatabasePage<FingerprintRecord> {
        let sanitizedLimit = max(1, limit)
        let sanitizedOffset = max(0, offset)
        return try dbQueue.read { db in
            let totalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fingerprints") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM fingerprints ORDER BY scanned_at DESC LIMIT ? OFFSET ?",
                arguments: [sanitizedLimit, sanitizedOffset]
            )
            let records = try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }
            return DatabasePage(values: records, totalCount: totalCount, limit: sanitizedLimit, offset: sanitizedOffset)
        }
    }

    func searchFingerprintRecords(query: String, limit: Int, offset: Int = 0) throws -> DatabasePage<FingerprintRecord> {
        let sanitizedLimit = max(1, limit)
        let sanitizedOffset = max(0, offset)
        let trimmed = query.normalizedSearchQuery
        guard trimmed.isEmpty == false else {
            return try loadFingerprintPage(limit: sanitizedLimit, offset: sanitizedOffset)
        }

        return try dbQueue.read { db in
            let pattern = Self.sqliteSearchPattern(trimmed)
            let searchPredicate = pattern.usesEscape
                ? "fingerprints_fts.search_index LIKE ? ESCAPE '\\'"
                : "fingerprints_fts.search_index LIKE ?"
            let totalCount = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM fingerprints
                JOIN fingerprints_fts ON fingerprints_fts.record_id = fingerprints.id
                WHERE \(searchPredicate)
                """,
                arguments: [pattern.value]
            ) ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT fingerprints.payload
                FROM fingerprints
                JOIN fingerprints_fts ON fingerprints_fts.record_id = fingerprints.id
                WHERE \(searchPredicate)
                ORDER BY fingerprints.scanned_at DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [pattern.value, sanitizedLimit, sanitizedOffset]
            )
            let records = try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }
            return DatabasePage(values: records, totalCount: totalCount, limit: sanitizedLimit, offset: sanitizedOffset)
        }
    }

    func loadFingerprintRecords(matching query: String) throws -> [FingerprintRecord] {
        let trimmed = query.normalizedSearchQuery
        guard trimmed.isEmpty == false else {
            return try loadFingerprintRecords()
        }

        return try dbQueue.read { db in
            let pattern = Self.sqliteSearchPattern(trimmed)
            let searchPredicate = pattern.usesEscape
                ? "fingerprints_fts.search_index LIKE ? ESCAPE '\\'"
                : "fingerprints_fts.search_index LIKE ?"
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT fingerprints.payload
                FROM fingerprints
                JOIN fingerprints_fts ON fingerprints_fts.record_id = fingerprints.id
                WHERE \(searchPredicate)
                ORDER BY fingerprints.scanned_at DESC
                """,
                arguments: [pattern.value]
            )
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }
        }
    }

    func countFingerprintRecords(tag: String) throws -> Int {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTag.isEmpty == false else {
            return 0
        }

        return try dbQueue.read { db in
            let needle = "\n\(normalizedTag)\n"
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM fingerprints WHERE instr(tag_index, ?) > 0",
                arguments: [needle]
            ) ?? 0
        }
    }

    func deleteFingerprintRecords(tag: String) throws -> Int {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else {
            return 0
        }

        return try dbQueue.write { db in
            let needle = "\n\(normalizedTag)\n"
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, payload FROM fingerprints WHERE instr(tag_index, ?) > 0",
                arguments: [needle]
            )
            let idsToDelete = try rows.compactMap { row -> String? in
                let payload: String = row["payload"]
                let record = try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: payload)
                return record.tags?.contains(normalizedTag) == true ? row["id"] : nil
            }
            for id in idsToDelete {
                try db.execute(sql: "DELETE FROM fingerprints WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM fingerprints_fts WHERE record_id = ?", arguments: [id])
            }
            return idsToDelete.count
        }
    }

    func deleteFingerprintRecord(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM fingerprints WHERE id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM fingerprints_fts WHERE record_id = ?", arguments: [id.uuidString])
        }
    }

    func upsertWhitelistRule(_ rule: WhitelistRule) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(rule)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO whitelist_rules (id, payload)
                VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """,
                arguments: [rule.id.uuidString, payload]
            )
        }
    }

    func loadWhitelistRules() throws -> [WhitelistRule] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM whitelist_rules")
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(WhitelistRule.self, from: row["payload"])
            }.sorted(by: { $0.createdAt > $1.createdAt })
        }
    }

    func deleteWhitelistRule(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM whitelist_rules WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func upsertSubmissionBatch(_ batch: SubmissionBatch, items: [SubmissionItem]) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(batch)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO submission_batches (id, payload, created_at, updated_at, status)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    updated_at = excluded.updated_at,
                    status = excluded.status
                """,
                arguments: [batch.id.uuidString, payload, batch.createdAt, batch.updatedAt, batch.status.rawValue]
            )
            try db.execute(sql: "DELETE FROM submission_items WHERE batch_id = ?", arguments: [batch.id.uuidString])
            for item in items {
                let itemPayload = try JSONEncoder.pitcherPlant.encodeToString(item)
                try db.execute(
                    sql: """
                    INSERT INTO submission_items (id, batch_id, team_name, root_path, status, payload)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [item.id.uuidString, batch.id.uuidString, item.teamName, item.rootPath, item.status.rawValue, itemPayload]
                )
            }
        }
    }

    func loadSubmissionBatches() throws -> [SubmissionBatch] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM submission_batches ORDER BY updated_at DESC")
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(SubmissionBatch.self, from: row["payload"])
            }
        }
    }

    func loadSubmissionItems(batchID: UUID? = nil) throws -> [SubmissionItem] {
        try dbQueue.read { db in
            let rows: [Row]
            if let batchID {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM submission_items WHERE batch_id = ? ORDER BY team_name ASC", arguments: [batchID.uuidString])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM submission_items ORDER BY team_name ASC")
            }
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(SubmissionItem.self, from: row["payload"])
            }
        }
    }

    func upsertDocumentFeatures(_ features: [DocumentFeature]) throws {
        guard features.isEmpty == false else { return }
        try dbQueue.write { db in
            for feature in features {
                let payload = try JSONEncoder.pitcherPlant.encodeToString(feature)
                try db.execute(
                    sql: """
                    INSERT INTO document_features (
                        id,
                        document_path,
                        scan_id,
                        batch_id,
                        content_hash,
                        source_mtime,
                        source_size,
                        feature_version,
                        simhash,
                        text_length,
                        updated_at,
                        payload
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        document_path = excluded.document_path,
                        scan_id = excluded.scan_id,
                        batch_id = excluded.batch_id,
                        content_hash = excluded.content_hash,
                        source_mtime = excluded.source_mtime,
                        source_size = excluded.source_size,
                        feature_version = excluded.feature_version,
                        simhash = excluded.simhash,
                        text_length = excluded.text_length,
                        updated_at = excluded.updated_at,
                        payload = excluded.payload
                    """,
                    arguments: [
                        feature.id.uuidString,
                        feature.documentPath,
                        feature.scanID?.uuidString,
                        feature.batchID?.uuidString,
                        feature.contentHash,
                        feature.sourceMTime,
                        feature.sourceSize,
                        feature.featureVersion,
                        feature.simhash,
                        feature.textLength,
                        feature.updatedAt,
                        payload
                    ]
                )
            }
        }
    }

    func loadDocumentFeatures(
        scanID: UUID? = nil,
        batchID: UUID? = nil,
        pathPrefix: String? = nil,
        onlyUnbatched: Bool = false
    ) throws -> [DocumentFeature] {
        try dbQueue.read { db in
            var clauses: [String] = []
            var arguments: StatementArguments = []
            if let scanID {
                clauses.append("scan_id = ?")
                arguments += [scanID.uuidString]
            }
            if let batchID {
                clauses.append("batch_id = ?")
                arguments += [batchID.uuidString]
            }
            if onlyUnbatched {
                clauses.append("batch_id IS NULL")
            }
            if let pathPrefix = Self.normalizedPathPrefix(pathPrefix) {
                clauses.append("(document_path = ? OR document_path LIKE ? ESCAPE '\\')")
                arguments += [pathPrefix, Self.sqliteLikeEscapedPrefix(pathPrefix)]
            }
            let whereClause = clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))"
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM document_features\(whereClause) ORDER BY updated_at DESC",
                arguments: arguments
            )
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(DocumentFeature.self, from: row["payload"])
            }
        }
    }

    private static func normalizedPathPrefix(_ pathPrefix: String?) -> String? {
        guard var pathPrefix = pathPrefix?.trimmingCharacters(in: .whitespacesAndNewlines),
              pathPrefix.isEmpty == false
        else {
            return nil
        }
        while pathPrefix.count > 1 && pathPrefix.hasSuffix("/") {
            pathPrefix.removeLast()
        }
        return pathPrefix
    }

    private static func sqliteLikeEscapedPrefix(_ pathPrefix: String) -> String {
        let escaped = pathPrefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "\(escaped)/%"
    }

    private static func sqliteSearchPattern(_ query: String) -> SQLiteSearchPattern {
        let lowered = query.lowercased()
        if lowered.contains(where: { $0 == "%" || $0 == "_" || $0 == "\\" }) {
            return SQLiteSearchPattern(value: "%\(sqliteLikeEscapedLiteral(lowered))%", usesEscape: true)
        }
        return SQLiteSearchPattern(value: "%\(lowered)%", usesEscape: false)
    }

    private static func sqliteLikeEscapedLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func evidenceRowOrderClause(for sortOrder: ReportEvidenceSortOrder) -> String {
        switch sortOrder {
        case .default:
            return "report_table_rows.section_position ASC, report_table_rows.row_position ASC"
        case .severity:
            return """
            report_table_rows.severity_rank DESC,
            report_table_rows.attachment_count DESC,
            report_table_rows.title_sort ASC,
            report_table_rows.section_position ASC,
            report_table_rows.row_position ASC
            """
        case .title:
            return """
            report_table_rows.title_sort ASC,
            report_table_rows.section_position ASC,
            report_table_rows.row_position ASC
            """
        }
    }

    @discardableResult
    func deleteDocumentFeatures(ids: [UUID]) throws -> Int {
        guard ids.isEmpty == false else { return 0 }
        return try dbQueue.write { db in
            var deleted = 0
            for id in ids {
                try db.execute(sql: "DELETE FROM document_features WHERE id = ?", arguments: [id.uuidString])
                deleted += db.changesCount
            }
            return deleted
        }
    }

    @discardableResult
    func cleanupDocumentFeatures(excludingDocumentPaths documentPaths: Set<String>, batchID: UUID? = nil) throws -> Int {
        guard let batchID else { return 0 }
        return try dbQueue.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, document_path FROM document_features WHERE batch_id = ?",
                arguments: [batchID.uuidString]
            )

            var deleted = 0
            for row in rows {
                let path: String = row["document_path"]
                guard documentPaths.contains(path) == false else { continue }
                let id: String = row["id"]
                try db.execute(sql: "DELETE FROM document_features WHERE id = ?", arguments: [id])
                deleted += db.changesCount
            }
            return deleted
        }
    }

    func recordExport(_ record: ExportRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO export_records (id, report_id, report_title, format, destination_path, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    report_id = excluded.report_id,
                    report_title = excluded.report_title,
                    format = excluded.format,
                    destination_path = excluded.destination_path,
                    created_at = excluded.created_at
                """,
                arguments: [
                    record.id.uuidString,
                    record.reportID.uuidString,
                    record.reportTitle,
                    record.format.rawValue,
                    record.destinationPath,
                    record.createdAt
                ]
            )
        }
    }

    func loadExportRecords(limit: Int? = nil) throws -> [ExportRecord] {
        try dbQueue.read { db in
            let sql: String
            let arguments: StatementArguments
            if let limit {
                sql = """
                SELECT id, report_id, report_title, format, destination_path, created_at
                FROM export_records
                ORDER BY created_at DESC
                LIMIT ?
                """
                arguments = [limit]
            } else {
                sql = """
                SELECT id, report_id, report_title, format, destination_path, created_at
                FROM export_records
                ORDER BY created_at DESC
                """
                arguments = []
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let reportID = UUID(uuidString: row["report_id"]),
                      let formatRaw: String = row["format"],
                      let format = ExportRecord.Format(rawValue: formatRaw) else {
                    return nil
                }
                let reportTitle: String = row["report_title"]
                let destinationPath: String = row["destination_path"]
                let createdAt: Date = row["created_at"]
                return ExportRecord(
                    id: id,
                    reportID: reportID,
                    reportTitle: reportTitle,
                    format: format,
                    destinationPath: destinationPath,
                    createdAt: createdAt
                )
            }
        }
    }

    func debugTableRowCount(named table: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table.quotedDatabaseIdentifier)") ?? 0
        }
    }

    func debugTableExists(named table: String) throws -> Bool {
        try dbQueue.read { db in
            try tableExists(table, db: db)
        }
    }

    func debugTableColumns(named table: String) throws -> [String] {
        try dbQueue.read { db in
            try db.columns(in: table).map(\.name)
        }
    }

    private func fetchJobEventsByJobID(_ db: Database) throws -> [String: [AuditJobEvent]] {
        let rows = try Row.fetchAll(db, sql: "SELECT job_id, timestamp, message, progress, id, payload FROM audit_job_events ORDER BY timestamp ASC")
        var grouped: [String: [AuditJobEvent]] = [:]
        for row in rows {
            let jobID: String = row["job_id"]
            let payload: String? = row["payload"]
            let event: AuditJobEvent
            if let payload, payload.isEmpty == false,
               let decoded = try? JSONDecoder.pitcherPlant.decodeString(AuditJobEvent.self, from: payload) {
                event = decoded
            } else {
                event = AuditJobEvent(
                    id: UUID(uuidString: row["id"]) ?? UUID(),
                    timestamp: row["timestamp"],
                    message: row["message"],
                    progress: row["progress"]
                )
            }
            grouped[jobID, default: []].append(event)
        }
        return grouped
    }

    private func fetchSectionsByReportID(_ db: Database, reportIDs: Set<String>? = nil) throws -> [String: [ReportSection]] {
        let rows: [Row]
        if let reportIDs, reportIDs.isEmpty {
            rows = []
        } else if let reportIDs {
            var arguments: StatementArguments = []
            for reportID in reportIDs {
                arguments += [reportID]
            }
            let placeholders = Array(repeating: "?", count: reportIDs.count).joined(separator: ",")
            rows = try Row.fetchAll(
                db,
                sql: "SELECT report_id, payload FROM report_sections WHERE report_id IN (\(placeholders)) ORDER BY position ASC",
                arguments: arguments
            )
        } else {
            rows = try Row.fetchAll(db, sql: "SELECT report_id, payload FROM report_sections ORDER BY position ASC")
        }
        var grouped: [String: [ReportSection]] = [:]
        for row in rows {
            let reportID: String = row["report_id"]
            let payload: String = row["payload"]
            let section = try JSONDecoder.pitcherPlant.decodeString(ReportSection.self, from: payload)
            grouped[reportID, default: []].append(section)
        }
        return grouped
    }
}

private extension AuditReport {
    func replacingSections(_ sections: [ReportSection]) -> AuditReport {
        AuditReport(
            id: id,
            jobID: jobID,
            title: title,
            sourcePath: sourcePath,
            scanDirectoryPath: scanDirectoryPath,
            createdAt: createdAt,
            metrics: metrics,
            sections: sections
        )
    }
}

private extension ReportTableRow {
    func matchesEvidenceQuery(_ query: String) -> Bool {
        let badgeCorpus = badges.map(\.title).joined(separator: "\n")
        let attachmentCorpus = attachments
            .flatMap { [$0.title, $0.subtitle, $0.body] }
            .joined(separator: "\n")
        return (columns + [detailTitle, detailBody, badgeCorpus, attachmentCorpus])
            .joined(separator: "\n")
            .localizedCaseInsensitiveContains(query)
    }
}

private extension FingerprintRecord {
    func matchesLibrarySearch(_ query: String) -> Bool {
        [
            filename,
            ext,
            author,
            scanDir,
            simhash,
            batchName ?? "",
            challengeName ?? "",
            teamName ?? "",
            (tags ?? []).joined(separator: " ")
        ]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(query)
    }
}

private func upsertJobEvents(_ events: [AuditJobEvent], jobID: String, db: Database) throws {
    for event in events {
        try db.execute(
            sql: """
            INSERT INTO audit_job_events (id, job_id, timestamp, message, progress, payload)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                job_id = excluded.job_id,
                timestamp = excluded.timestamp,
                message = excluded.message,
                progress = excluded.progress,
                payload = excluded.payload
            """,
            arguments: [
                event.id.uuidString,
                jobID,
                event.timestamp,
                event.message,
                event.progress,
                try JSONEncoder.pitcherPlant.encodeToString(event)
            ]
        )
    }
}

private func trimJobEvents(jobID: String, keep: Int, db: Database) throws {
    try db.execute(
        sql: """
        DELETE FROM audit_job_events
        WHERE job_id = ?
          AND id NOT IN (
              SELECT id FROM audit_job_events
              WHERE job_id = ?
              ORDER BY timestamp DESC
              LIMIT ?
          )
        """,
        arguments: [jobID, jobID, max(1, keep)]
    )
}

private func ensureColumn(_ name: String, in table: String, type: Database.ColumnType, db: Database) throws {
    let existing = try db.columns(in: table)
    guard existing.contains(where: { $0.name == name }) == false else {
        return
    }
    try db.alter(table: table) { t in
        t.add(column: name, type)
    }
}

private func removeObsoleteReportState(_ db: Database) throws {
    if try tableExists("audit_reports", db: db),
       try db.columns(in: "audit_reports").contains(where: { $0.name == "is_legacy" }) {
        try db.create(table: "audit_reports_without_legacy") { table in
            table.column("id", .text).primaryKey()
            table.column("payload", .text).notNull()
            table.column("created_at", .datetime).notNull()
            table.column("title", .text).notNull()
            table.column("source_path", .text).notNull()
            table.column("scan_directory_path", .text).notNull()
            table.column("job_id", .text)
        }
        try db.execute(sql: """
            INSERT INTO audit_reports_without_legacy (id, payload, created_at, title, source_path, scan_directory_path, job_id)
            SELECT id, payload, created_at, title, source_path, scan_directory_path, job_id
            FROM audit_reports
            """)
        try db.drop(table: "audit_reports")
        try db.execute(sql: "ALTER TABLE audit_reports_without_legacy RENAME TO audit_reports")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_title_idx ON audit_reports(title)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_source_path_idx ON audit_reports(source_path)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_scan_dir_idx ON audit_reports(scan_directory_path)")
    }

    if try tableExists("app_migrations", db: db) {
        try db.drop(table: "app_migrations")
    }
}

private func tableExists(_ table: String, db: Database) throws -> Bool {
    try Row.fetchOne(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        arguments: [table]
    ) != nil
}

private func createReportTableRows(_ db: Database) throws {
    try db.create(table: "report_table_rows", ifNotExists: true) { table in
        table.column("storage_id", .text).primaryKey()
        table.column("report_id", .text).notNull().indexed()
        table.column("section_id", .text).notNull().indexed()
        table.column("row_id", .text).notNull().indexed()
        table.column("section_position", .integer).notNull()
        table.column("row_position", .integer).notNull()
        table.column("kind", .text).notNull().indexed()
        table.column("search_index", .text).notNull()
        table.column("attachment_count", .integer).notNull().defaults(to: 0)
        table.column("is_high_risk", .boolean).notNull().defaults(to: false)
        table.column("severity_rank", .integer).notNull().defaults(to: 0)
        table.column("title_sort", .text).notNull().defaults(to: "")
        table.column("payload", .text).notNull()
    }
    try ensureColumn("attachment_count", in: "report_table_rows", type: .integer, db: db)
    try ensureColumn("is_high_risk", in: "report_table_rows", type: .boolean, db: db)
    try ensureColumn("severity_rank", in: "report_table_rows", type: .integer, db: db)
    try ensureColumn("title_sort", in: "report_table_rows", type: .text, db: db)
}

private func createOperationalTables(_ db: Database) throws {
    try db.create(table: "evidence_reviews", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("report_id", .text).notNull().indexed()
        table.column("evidence_id", .text).notNull().indexed()
        table.column("evidence_type", .text).notNull().indexed()
        table.column("decision", .text).notNull().indexed()
        table.column("severity", .text)
        table.column("reviewer_note", .text).notNull()
        table.column("updated_at", .datetime).notNull().indexed()
        table.column("payload", .text).notNull()
    }
    try db.create(table: "submission_batches", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("payload", .text).notNull()
        table.column("created_at", .datetime).notNull().indexed()
        table.column("updated_at", .datetime).notNull().indexed()
        table.column("status", .text).notNull().indexed()
    }
    try db.create(table: "submission_items", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("batch_id", .text).notNull().indexed()
        table.column("team_name", .text).notNull().indexed()
        table.column("root_path", .text).notNull()
        table.column("status", .text).notNull().indexed()
        table.column("payload", .text).notNull()
    }
    try db.create(table: "document_features", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("document_path", .text).notNull().indexed()
        table.column("scan_id", .text)
        table.column("batch_id", .text)
        table.column("content_hash", .text)
        table.column("source_mtime", .datetime)
        table.column("source_size", .integer)
        table.column("feature_version", .integer)
        table.column("simhash", .text).notNull().indexed()
        table.column("text_length", .integer).notNull().indexed()
        table.column("updated_at", .datetime).notNull().indexed()
        table.column("payload", .text).notNull()
    }
    try createReportTableRows(db)
}

private func extendDocumentFeaturesSchema(_ db: Database) throws {
    try createOperationalTables(db)
    try ensureColumn("scan_id", in: "document_features", type: .text, db: db)
    try ensureColumn("batch_id", in: "document_features", type: .text, db: db)
    try ensureColumn("content_hash", in: "document_features", type: .text, db: db)
    try ensureColumn("source_mtime", in: "document_features", type: .datetime, db: db)
    try ensureColumn("source_size", in: "document_features", type: .integer, db: db)
    try ensureColumn("feature_version", in: "document_features", type: .integer, db: db)

    let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM document_features")
    for row in rows {
        let id: String = row["id"]
        let payload: String = row["payload"]
        let feature = try JSONDecoder.pitcherPlant.decodeString(DocumentFeature.self, from: payload)
        let normalizedPayload = try JSONEncoder.pitcherPlant.encodeToString(feature)
        try db.execute(
            sql: """
            UPDATE document_features
            SET scan_id = ?, batch_id = ?, content_hash = ?, source_mtime = ?, source_size = ?,
                feature_version = ?, simhash = ?, text_length = ?, updated_at = ?, payload = ?
            WHERE id = ?
            """,
            arguments: [
                feature.scanID?.uuidString,
                feature.batchID?.uuidString,
                feature.contentHash,
                feature.sourceMTime,
                feature.sourceSize,
                feature.featureVersion,
                feature.simhash,
                feature.textLength,
                feature.updatedAt,
                normalizedPayload,
                id
            ]
        )
    }

    try createDocumentFeatureIndexes(db)
}

private func createDocumentFeatureIndexes(_ db: Database) throws {
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS document_features_scan_id_idx ON document_features(scan_id)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS document_features_batch_id_idx ON document_features(batch_id)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS document_features_content_hash_idx ON document_features(content_hash)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS document_features_feature_version_idx ON document_features(feature_version)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS document_features_path_hash_idx ON document_features(document_path, content_hash)")
}

private func createFingerprintIndexes(_ db: Database) throws {
    if try db.columns(in: "fingerprints").contains(where: { $0.name == "identity_key" }) {
        try db.execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS fingerprints_identity_key_unique_idx ON fingerprints(identity_key)")
    }
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS fingerprints_scanned_at_idx ON fingerprints(scanned_at)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS fingerprints_simhash_idx ON fingerprints(simhash)")
}

private func createSearchTables(_ db: Database) throws {
    try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS audit_reports_fts USING fts5(record_id UNINDEXED, search_index, tokenize='trigram')")
    try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS report_table_rows_fts USING fts5(storage_id UNINDEXED, report_id UNINDEXED, search_index, tokenize='trigram')")
    try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS fingerprints_fts USING fts5(record_id UNINDEXED, search_index, tokenize='trigram')")
}

private func normalizeFingerprintIdentities(_ db: Database) throws {
    struct Entry {
        let rowID: String
        let stableRecord: FingerprintRecord
    }

    let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM fingerprints")
    let entries = try rows.map { row in
        let rowID: String = row["id"]
        let payload: String = row["payload"]
        let record = try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: payload)
        return Entry(rowID: rowID, stableRecord: record.withStableIdentity())
    }

    var keepByIdentity: [String: Int] = [:]
    for (index, entry) in entries.enumerated() {
        if let existingIndex = keepByIdentity[entry.stableRecord.identityKey] {
            let existing = entries[existingIndex]
            if entry.stableRecord.scannedAt > existing.stableRecord.scannedAt {
                keepByIdentity[entry.stableRecord.identityKey] = index
            }
        } else {
            keepByIdentity[entry.stableRecord.identityKey] = index
        }
    }

    let keptIndexes = Set(keepByIdentity.values)
    for (index, entry) in entries.enumerated() where keptIndexes.contains(index) == false {
        try db.execute(sql: "DELETE FROM fingerprints WHERE id = ?", arguments: [entry.rowID])
    }

    for index in keptIndexes {
        let entry = entries[index]
        let record = entry.stableRecord
        let payload = try JSONEncoder.pitcherPlant.encodeToString(record)
        try db.execute(
            sql: """
            UPDATE fingerprints
            SET id = ?, identity_key = ?, payload = ?, simhash = ?, scanned_at = ?,
                tag_index = ?, search_index = ?
            WHERE id = ?
            """,
            arguments: [
                record.id.uuidString,
                record.identityKey,
                payload,
                record.simhash,
                record.scannedAt,
                fingerprintTagIndex(record.tags),
                fingerprintSearchIndex(record),
                entry.rowID
            ]
        )
    }
}

private func createLibrarySearchIndexes(_ db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_created_at_idx ON audit_reports(created_at)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS audit_reports_search_index_idx ON audit_reports(search_index)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS fingerprints_search_index_idx ON fingerprints(search_index)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS report_table_rows_report_position_idx ON report_table_rows(report_id, section_position, row_position)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS report_table_rows_report_search_idx ON report_table_rows(report_id, search_index)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS report_table_rows_report_kind_idx ON report_table_rows(report_id, kind)")
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS report_table_rows_report_filter_idx ON report_table_rows(report_id, kind, is_high_risk, attachment_count)")
}

private func backfillReportRowMetadata(_ db: Database) throws {
    let rows = try Row.fetchAll(db, sql: "SELECT storage_id, payload FROM report_table_rows")
    for row in rows {
        let storageID: String = row["storage_id"]
        let payload: String = row["payload"]
        let reportRow = try JSONDecoder.pitcherPlant.decodeString(ReportTableRow.self, from: payload)
        let metadata = reportRowQueryMetadata(reportRow)
        try db.execute(
            sql: """
            UPDATE report_table_rows
            SET attachment_count = ?, is_high_risk = ?, severity_rank = ?, title_sort = ?, search_index = ?
            WHERE storage_id = ?
            """,
            arguments: [
                metadata.attachmentCount,
                metadata.isHighRisk,
                metadata.severityRank,
                metadata.titleSort,
                reportRowSearchIndex(reportRow),
                storageID,
            ]
        )
    }
}

private func rebuildSearchTables(_ db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM audit_reports_fts")
    try db.execute(sql: "DELETE FROM report_table_rows_fts")
    try db.execute(sql: "DELETE FROM fingerprints_fts")

    let reportRows = try Row.fetchAll(db, sql: "SELECT id, search_index FROM audit_reports WHERE search_index IS NOT NULL")
    for row in reportRows {
        try upsertReportSearchIndex(reportID: row["id"], searchIndex: row["search_index"], db: db)
    }

    let evidenceRows = try Row.fetchAll(db, sql: "SELECT storage_id, report_id, search_index FROM report_table_rows")
    for row in evidenceRows {
        try upsertReportRowSearchIndex(storageID: row["storage_id"], reportID: row["report_id"], searchIndex: row["search_index"], db: db)
    }

    let fingerprintRows = try Row.fetchAll(db, sql: "SELECT id, search_index FROM fingerprints WHERE search_index IS NOT NULL")
    for row in fingerprintRows {
        try upsertFingerprintSearchIndex(recordID: row["id"], searchIndex: row["search_index"], db: db)
    }
}

private func rebuildFingerprintSearchTable(_ db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM fingerprints_fts")
    let fingerprintRows = try Row.fetchAll(db, sql: "SELECT id, search_index FROM fingerprints WHERE search_index IS NOT NULL")
    for row in fingerprintRows {
        try upsertFingerprintSearchIndex(recordID: row["id"], searchIndex: row["search_index"], db: db)
    }
}

private func upsertReportSearchIndex(reportID: String, searchIndex: String, db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM audit_reports_fts WHERE record_id = ?", arguments: [reportID])
    try db.execute(
        sql: "INSERT INTO audit_reports_fts (record_id, search_index) VALUES (?, ?)",
        arguments: [reportID, searchIndex]
    )
}

private func upsertReportRowSearchIndex(storageID: String, reportID: String, searchIndex: String, db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM report_table_rows_fts WHERE storage_id = ?", arguments: [storageID])
    try db.execute(
        sql: "INSERT INTO report_table_rows_fts (storage_id, report_id, search_index) VALUES (?, ?, ?)",
        arguments: [storageID, reportID, searchIndex]
    )
}

private func upsertFingerprintSearchIndex(_ record: FingerprintRecord, db: Database) throws {
    try upsertFingerprintSearchIndex(recordID: record.id.uuidString, searchIndex: fingerprintSearchIndex(record), db: db)
}

private func upsertFingerprintSearchIndex(recordID: String, searchIndex: String, db: Database) throws {
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM fingerprints_fts WHERE record_id = ?", arguments: [recordID])
    try db.execute(
        sql: "INSERT INTO fingerprints_fts (record_id, search_index) VALUES (?, ?)",
        arguments: [recordID, searchIndex]
    )
}

private func replaceReportTableRows(for report: AuditReport, db: Database) throws {
    try createReportTableRows(db)
    try createSearchTables(db)
    try db.execute(sql: "DELETE FROM report_table_rows WHERE report_id = ?", arguments: [report.id.uuidString])
    try db.execute(sql: "DELETE FROM report_table_rows_fts WHERE report_id = ?", arguments: [report.id.uuidString])
    for (sectionPosition, section) in report.sections.enumerated() where section.kind != .overview {
        guard let rows = section.table?.rows else {
            continue
        }
        for (rowPosition, row) in rows.enumerated() {
            let payload = try JSONEncoder.pitcherPlant.encodeToString(row)
            let searchIndex = reportRowSearchIndex(row)
            let metadata = reportRowQueryMetadata(row)
            let storageID = "\(report.id.uuidString):\(section.id.uuidString):\(row.id.uuidString)"
            try db.execute(
                sql: """
                INSERT INTO report_table_rows (
                    storage_id,
                    report_id,
                    section_id,
                    row_id,
                    section_position,
                    row_position,
                    kind,
                    search_index,
                    attachment_count,
                    is_high_risk,
                    severity_rank,
                    title_sort,
                    payload
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    storageID,
                    report.id.uuidString,
                    section.id.uuidString,
                    row.id.uuidString,
                    sectionPosition,
                    rowPosition,
                    section.kind.rawValue,
                    searchIndex,
                    metadata.attachmentCount,
                    metadata.isHighRisk,
                    metadata.severityRank,
                    metadata.titleSort,
                    payload,
                ]
            )
            try upsertReportRowSearchIndex(storageID: storageID, reportID: report.id.uuidString, searchIndex: searchIndex, db: db)
        }
    }
}

private struct ReportRowQueryMetadata {
    let attachmentCount: Int
    let isHighRisk: Bool
    let severityRank: Int
    let titleSort: String
}

private func reportRowQueryMetadata(_ row: ReportTableRow) -> ReportRowQueryMetadata {
    let badgePriority = row.badges.map { badgeTonePriority($0.tone) }.max() ?? 0
    let severityRank = max(row.riskAssessment?.level.priority ?? 0, badgePriority)
    return ReportRowQueryMetadata(
        attachmentCount: row.attachments.count,
        isHighRisk: row.riskAssessment?.level == .high || row.badges.contains(where: { $0.tone == .danger }),
        severityRank: severityRank,
        titleSort: row.detailTitle.lowercased()
    )
}

private func badgeTonePriority(_ tone: ReportBadge.Tone) -> Int {
    switch tone {
    case .danger: return 4
    case .warning: return 3
    case .accent: return 2
    case .success: return 1
    case .neutral: return 0
    }
}

private func reportSummary(from row: Row) -> AuditReport {
    let reportID: String = row["id"]
    let jobIDString: String? = row["job_id"]
    return AuditReport(
        id: UUID(uuidString: reportID) ?? UUID.pitcherPlantStable(namespace: "report-summary", components: [reportID]),
        jobID: jobIDString.flatMap(UUID.init(uuidString:)),
        title: row["title"],
        sourcePath: row["source_path"],
        scanDirectoryPath: row["scan_directory_path"],
        createdAt: row["created_at"],
        metrics: [],
        sections: []
    )
}

private func reportSearchIndex(_ report: AuditReport) -> String {
    let metricCorpus = report.metrics.map { [$0.title, $0.value].joined(separator: " ") }
    let sectionCorpus = report.sections.map(sectionSearchIndex)
    return normalizedSearchIndex([report.title, report.sourcePath, report.scanDirectoryPath] + metricCorpus + sectionCorpus)
}

private func sectionSearchIndex(_ section: ReportSection) -> String {
    let calloutCorpus = section.callouts.joined(separator: "\n")
    let headerCorpus = section.table?.headers.joined(separator: "\n") ?? ""
    let rowCorpus = section.table?.rows.map(reportRowSearchIndex).joined(separator: "\n") ?? ""
    return normalizedSearchIndex([section.title, section.summary, calloutCorpus, headerCorpus, rowCorpus])
}

private func reportRowSearchIndex(_ row: ReportTableRow) -> String {
    let badgeCorpus = row.badges.map(\.title).joined(separator: "\n")
    let attachmentCorpus = row.attachments
        .flatMap { [$0.title, $0.subtitle, $0.body] }
        .joined(separator: "\n")
    return normalizedSearchIndex(row.columns + [row.detailTitle, row.detailBody, badgeCorpus, attachmentCorpus])
}

private func fingerprintSearchIndex(_ record: FingerprintRecord) -> String {
    normalizedSearchIndex([
        record.filename,
        record.ext,
        record.author,
        record.scanDir,
        record.simhash,
        record.batchName ?? "",
        record.challengeName ?? "",
        record.teamName ?? "",
        (record.tags ?? []).joined(separator: " "),
    ])
}

private func normalizedSearchIndex(_ values: [String]) -> String {
    values
        .joined(separator: "\n")
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func fingerprintTagIndex(_ tags: [String]?) -> String {
    let normalized = Array(Set((tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false })).sorted()
    guard normalized.isEmpty == false else {
        return "\n"
    }
    return "\n\(normalized.joined(separator: "\n"))\n"
}

private extension JSONEncoder {
    static let pitcherPlant: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PitcherPlant.Encoding", code: 1)
        }
        return string
    }
}

private extension JSONDecoder {
    static let pitcherPlant: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func decodeString<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decode(type, from: Data(string.utf8))
    }
}

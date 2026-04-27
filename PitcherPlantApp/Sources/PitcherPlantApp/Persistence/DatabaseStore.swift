import Foundation
import GRDB

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
                table.column("is_legacy", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "audit_job_events", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("job_id", .text).notNull().indexed()
                table.column("timestamp", .datetime).notNull()
                table.column("message", .text).notNull()
                table.column("progress", .integer).notNull()
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
                table.column("payload", .text).notNull()
                table.column("simhash", .text).notNull()
            }
            try db.create(table: "whitelist_rules", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
            }
            try db.create(table: "app_migrations", ifNotExists: true) { table in
                table.column("name", .text).primaryKey()
                table.column("created_at", .datetime).notNull()
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

            let jobRows = try Row.fetchAll(db, sql: "SELECT id, payload FROM audit_jobs")
            for row in jobRows {
                let jobID: String = row["id"]
                let payload: String = row["payload"]
                let job = try JSONDecoder.pitcherPlant.decodeString(AuditJob.self, from: payload)
                try db.execute(sql: "DELETE FROM audit_job_events WHERE job_id = ?", arguments: [jobID])
                for event in job.events {
                    try db.execute(
                        sql: """
                        INSERT INTO audit_job_events (id, job_id, timestamp, message, progress)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [event.id.uuidString, jobID, event.timestamp, event.message, event.progress]
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
            try ensureColumn("is_legacy", in: "audit_reports", type: .boolean, db: db)

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
                    SET title = ?, source_path = ?, scan_directory_path = ?, job_id = ?, is_legacy = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        report.title,
                        report.sourcePath,
                        report.scanDirectoryPath,
                        report.jobID?.uuidString,
                        report.isLegacy,
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
            try db.execute(sql: "DELETE FROM audit_job_events WHERE job_id = ?", arguments: [job.id.uuidString])
            for event in job.events {
                try db.execute(
                    sql: """
                    INSERT INTO audit_job_events (id, job_id, timestamp, message, progress)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [event.id.uuidString, job.id.uuidString, event.timestamp, event.message, event.progress]
                )
            }
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
    func markInterruptedJobs(message: String = "上次审计运行被中断，请重新开始审计。") throws -> Int {
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
                try db.execute(sql: "DELETE FROM audit_job_events WHERE job_id = ?", arguments: [jobID])
                for event in job.events {
                    try db.execute(
                        sql: """
                        INSERT INTO audit_job_events (id, job_id, timestamp, message, progress)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        arguments: [event.id.uuidString, jobID, event.timestamp, event.message, event.progress]
                    )
                }
            }
            return rows.count
        }
    }

    func saveReport(_ report: AuditReport) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(report)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_reports (id, payload, created_at, title, source_path, scan_directory_path, job_id, is_legacy)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    created_at = excluded.created_at,
                    title = excluded.title,
                    source_path = excluded.source_path,
                    scan_directory_path = excluded.scan_directory_path,
                    job_id = excluded.job_id,
                    is_legacy = excluded.is_legacy
                """,
                arguments: [
                    report.id.uuidString,
                    payload,
                    report.createdAt,
                    report.title,
                    report.sourcePath,
                    report.scanDirectoryPath,
                    report.jobID?.uuidString,
                    report.isLegacy,
                ]
            )
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
                        isLegacy: report.isLegacy,
                        metrics: report.metrics,
                        sections: sections
                    )
                }
                return report
            }
        }
    }

    func deleteReport(reportID: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM audit_reports WHERE id = ?", arguments: [reportID.uuidString])
            try db.execute(sql: "DELETE FROM report_sections WHERE report_id = ?", arguments: [reportID.uuidString])
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
                let payload = try JSONEncoder.pitcherPlant.encodeToString(record)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO fingerprints (id, payload, simhash)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [record.id.uuidString, payload, record.simhash]
                )
            }
        }
    }

    func upsertFingerprintRecords(_ records: [FingerprintRecord]) throws {
        guard !records.isEmpty else {
            return
        }
        try dbQueue.write { db in
            for record in records {
                let payload = try JSONEncoder.pitcherPlant.encodeToString(record)
                try db.execute(
                    sql: """
                    INSERT INTO fingerprints (id, payload, simhash)
                    VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        payload = excluded.payload,
                        simhash = excluded.simhash
                    """,
                    arguments: [record.id.uuidString, payload, record.simhash]
                )
            }
        }
    }

    func loadFingerprintRecords() throws -> [FingerprintRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM fingerprints")
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }.sorted(by: { $0.scannedAt > $1.scannedAt })
        }
    }

    func deleteFingerprintRecords(tag: String) throws -> Int {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else {
            return 0
        }

        return try dbQueue.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM fingerprints")
            let idsToDelete = try rows.compactMap { row -> String? in
                let payload: String = row["payload"]
                let record = try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: payload)
                return record.tags?.contains(normalizedTag) == true ? row["id"] : nil
            }
            for id in idsToDelete {
                try db.execute(sql: "DELETE FROM fingerprints WHERE id = ?", arguments: [id])
            }
            return idsToDelete.count
        }
    }

    func deleteFingerprintRecord(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM fingerprints WHERE id = ?", arguments: [id.uuidString])
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

    func loadDocumentFeatures(scanID: UUID? = nil, batchID: UUID? = nil) throws -> [DocumentFeature] {
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
        try dbQueue.write { db in
            let rows: [Row]
            if let batchID {
                rows = try Row.fetchAll(db, sql: "SELECT id, document_path FROM document_features WHERE batch_id = ?", arguments: [batchID.uuidString])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT id, document_path FROM document_features")
            }

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

    func hasMigration(named name: String) throws -> Bool {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT name FROM app_migrations WHERE name = ?", arguments: [name]) != nil
        }
    }

    func markMigration(name: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO app_migrations (name, created_at)
                VALUES (?, ?)
                """,
                arguments: [name, Date()]
            )
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

    private func fetchJobEventsByJobID(_ db: Database) throws -> [String: [AuditJobEvent]] {
        let rows = try Row.fetchAll(db, sql: "SELECT job_id, timestamp, message, progress, id FROM audit_job_events ORDER BY timestamp ASC")
        var grouped: [String: [AuditJobEvent]] = [:]
        for row in rows {
            let jobID: String = row["job_id"]
            let event = AuditJobEvent(
                id: UUID(uuidString: row["id"]) ?? UUID(),
                timestamp: row["timestamp"],
                message: row["message"],
                progress: row["progress"]
            )
            grouped[jobID, default: []].append(event)
        }
        return grouped
    }

    private func fetchSectionsByReportID(_ db: Database) throws -> [String: [ReportSection]] {
        let rows = try Row.fetchAll(db, sql: "SELECT report_id, payload FROM report_sections ORDER BY position ASC")
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

private func ensureColumn(_ name: String, in table: String, type: Database.ColumnType, db: Database) throws {
    let existing = try db.columns(in: table)
    guard existing.contains(where: { $0.name == name }) == false else {
        return
    }
    try db.alter(table: table) { t in
        t.add(column: name, type)
    }
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

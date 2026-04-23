import Foundation
import GRDB

actor DatabaseStore {
    private let dbQueue: DatabaseQueue
    private let dbURL: URL

    init(rootDirectory: URL) throws {
        let supportURL = rootDirectory.appendingPathComponent(".pitcherplant-macos", isDirectory: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        self.dbURL = supportURL.appendingPathComponent("PitcherPlantMac.sqlite")
        self.dbQueue = try DatabaseQueue(path: dbURL.path)
    }

    func prepare() async throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create-schema") { db in
            try db.create(table: "audit_jobs", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "audit_reports", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .text).notNull()
                table.column("created_at", .datetime).notNull()
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

        try migrator.migrate(dbQueue)
    }

    func upsertJob(_ job: AuditJob) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(job)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_jobs (id, payload, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
                """,
                arguments: [job.id.uuidString, payload, job.updatedAt]
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

    func saveReport(_ report: AuditReport) throws {
        let payload = try JSONEncoder.pitcherPlant.encodeToString(report)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_reports (id, payload, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, created_at = excluded.created_at
                """,
                arguments: [report.id.uuidString, payload, report.createdAt]
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
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM audit_reports")
            return try rows.compactMap { row in
                try JSONDecoder.pitcherPlant.decode(AuditReport.self, from: row["payload"])
            }.contains(where: { $0.sourcePath == sourcePath })
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

    func loadFingerprintRecords() throws -> [FingerprintRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM fingerprints")
            return try rows.map { row in
                try JSONDecoder.pitcherPlant.decodeString(FingerprintRecord.self, from: row["payload"])
            }.sorted(by: { $0.scannedAt > $1.scannedAt })
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

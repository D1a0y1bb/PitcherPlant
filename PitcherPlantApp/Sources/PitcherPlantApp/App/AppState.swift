import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AppNotice: Identifiable, Equatable {
    enum Tone: String, Equatable {
        case info
        case success
        case error
    }

    let id = UUID()
    let title: String
    let message: String
    let tone: Tone
}

@MainActor
@Observable
final class AppState {
    let workspaceRoot: URL
    let database: DatabaseStore
    let migrationService: MigrationService
    let auditRunner: AuditRunner

    var hasBootstrapped = false

    var selectedMainSidebar: MainSidebarItem = .workspace
    var selectedJobID: UUID?
    var selectedReportID: UUID?
    var selectedReportSection: ReportSectionKind?
    var selectedReportRowID: UUID?

    var jobs: [AuditJob] = []
    var reports: [AuditReport] = []
    var fingerprints: [FingerprintRecord] = []
    var whitelistRules: [WhitelistRule] = []
    var configurationPresets: [AuditConfigurationPreset] = []
    var exportRecords: [ExportRecord] = []
    var evidenceReviews: [EvidenceReview] = []
    var submissionBatches: [SubmissionBatch] = []
    var appSettings: AppSettings

    var draftConfiguration: AuditConfiguration
    var latestReport: AuditReport?
    var lastMigrationSummary: MigrationSummary?
    var initializationMessage: String?
    var notice: AppNotice?
    var isRunningAudit = false
    private var currentAuditTask: Task<AuditReport?, Never>?

    init() {
        let locator = ProjectLocator()
        self.workspaceRoot = locator.workspaceRoot()
        let settings = AppPreferences.loadAppSettings()
        self.appSettings = settings
        self.selectedMainSidebar = .workspace
        let databaseResult = Self.makeDatabase(rootDirectory: workspaceRoot)
        self.database = databaseResult.database
        self.initializationMessage = databaseResult.message
        self.migrationService = MigrationService(workspaceRoot: workspaceRoot)
        self.auditRunner = AuditRunner()
        self.draftConfiguration = AppPreferences.loadDraftConfiguration(for: workspaceRoot)
    }

    private static func makeDatabase(rootDirectory: URL) -> (database: DatabaseStore, message: String?) {
        do {
            return (try DatabaseStore(rootDirectory: rootDirectory), nil)
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("PitcherPlant", isDirectory: true)
                .appendingPathComponent("AppStateFallback", isDirectory: true)
            do {
                let database = try DatabaseStore(rootDirectory: fallbackRoot)
                return (database, "数据库已切换到临时可写目录：\(error.localizedDescription)")
            } catch {
                preconditionFailure("PitcherPlant database initialization failed: \(error)")
            }
        }
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }
        hasBootstrapped = true
        do {
            try await database.prepare()
            lastMigrationSummary = try await migrationService.runIfNeeded(database: database)
            _ = try await database.markInterruptedJobs()
        } catch {
            showNotice(title: t("notice.bootstrapFailed"), message: error.localizedDescription, tone: .error)
        }
        await reload()
        if let migratedConfig = lastMigrationSummary?.lastConfiguration {
            draftConfiguration = migratedConfig
            AppPreferences.saveDraftConfiguration(migratedConfig, for: workspaceRoot)
        }
    }

    func reload() async {
        do {
            jobs = try await database.loadJobs()
            evidenceReviews = try await database.loadEvidenceReviews()
            let loadedReports = try await database.loadReports()
            reports = loadedReports.map(reportWithReviews)
            fingerprints = try await database.loadFingerprintRecords()
            whitelistRules = try await database.loadWhitelistRules()
            configurationPresets = AppPreferences.loadPresets(for: workspaceRoot)
            exportRecords = try await database.loadExportRecords(limit: 20)
            submissionBatches = try await database.loadSubmissionBatches()
            latestReport = reports.sorted(by: { $0.createdAt > $1.createdAt }).first

            if selectedJobID == nil {
                selectedJobID = jobs.first?.id
            }
            if selectedReportID == nil {
                selectedReportID = latestReport?.id
            }
            if let report = selectedReport, selectedReportSection == nil {
                selectedReportSection = report.preferredEvidenceSection?.kind
            }
            syncReportSelection()
        } catch {
            showNotice(title: t("notice.reloadFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    var selectedJob: AuditJob? {
        jobs.first(where: { $0.id == selectedJobID })
    }

    var queuedJobCount: Int {
        jobs.filter { $0.status == .queued }.count
    }

    var selectedReport: AuditReport? {
        reports.first(where: { $0.id == selectedReportID })
    }

    var selectedReportSectionModel: ReportSection? {
        guard let report = selectedReport else { return nil }
        return report.displaySection(for: selectedReportSection)
    }

    var selectedReportRow: ReportTableRow? {
        guard let rows = selectedReportSectionModel?.table?.rows else { return nil }
        if let selectedReportRowID {
            return rows.first(where: { $0.id == selectedReportRowID }) ?? rows.first
        }
        return rows.first
    }

    func updateDraft(_ transform: (inout AuditConfiguration) -> Void) {
        transform(&draftConfiguration)
        AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&appSettings)
        AppPreferences.saveAppSettings(appSettings)
    }

    var effectiveLocale: Locale? {
        appSettings.language == .system ? nil : LocalizationStrings.locale(for: appSettings.language)
    }

    var effectiveColorScheme: ColorScheme? {
        appSettings.appearance.colorScheme
    }

    func saveCurrentConfigurationPreset(named name: String) {
        configurationPresets = AppPreferences.savePreset(
            named: name,
            configuration: draftConfiguration,
            for: workspaceRoot
        )
    }

    func applyPreset(_ preset: AuditConfigurationPreset) {
        draftConfiguration = preset.configuration
        AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
    }

    func deletePreset(_ preset: AuditConfigurationPreset) {
        configurationPresets = AppPreferences.deletePreset(id: preset.id, for: workspaceRoot)
    }

    func restoreDraft(from job: AuditJob) {
        draftConfiguration = job.configuration
        selectedMainSidebar = .newAudit
        selectedJobID = job.id
        AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
    }

    @discardableResult
    func startAudit(using preset: AuditConfigurationPreset) async -> AuditReport? {
        applyPreset(preset)
        return await startAudit()
    }

    func beginAudit() {
        guard !isRunningAudit, currentAuditTask == nil else {
            return
        }
        currentAuditTask = Task {
            let report = await startAudit()
            currentAuditTask = nil
            return report
        }
    }

    func beginQueuedAudits() {
        guard !isRunningAudit, currentAuditTask == nil, queuedJobCount > 0 else {
            return
        }
        currentAuditTask = Task {
            let report = await processQueuedAudits()
            currentAuditTask = nil
            return report
        }
    }

    func beginAudit(using preset: AuditConfigurationPreset) {
        applyPreset(preset)
        beginAudit()
    }

    func cancelAudit() {
        guard isRunningAudit else {
            return
        }
        currentAuditTask?.cancel()
    }

    func toggleAudit() {
        if isRunningAudit {
            cancelAudit()
        } else {
            beginAudit()
        }
    }

    func selectReport(_ reportID: UUID?) {
        guard let reportID else {
            selectedReportID = nil
            selectedReportSection = nil
            selectedReportRowID = nil
            return
        }
        selectedReportID = reportID
        syncReportSelection()
    }

    func selectLatestReport() {
        guard let report = latestReport ?? reports.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            selectedReportID = nil
            selectedReportSection = nil
            selectedReportRowID = nil
            return
        }
        selectedReportID = report.id
        syncReportSelection()
    }

    func showReportsCenter(selectLatest: Bool = false) {
        if selectLatest || selectedReportID == nil {
            selectLatestReport()
        } else {
            syncReportSelection()
        }
        selectedMainSidebar = .reports
        NSApp.activate(ignoringOtherApps: true)
    }

    func showReport(_ reportID: UUID?) {
        selectReport(reportID)
        selectedMainSidebar = .reports
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWorkspace() {
        selectedMainSidebar = .workspace
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectReportSection(_ kind: ReportSectionKind?) {
        selectedReportSection = kind
        selectedReportRowID = selectedReportSectionModel?.table?.rows.first?.id
    }

    func openLatestReportInFinder() {
        guard let report = latestReport else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([report.sourceURL])
    }

    func openLatestReportSource() {
        guard let report = latestReport else {
            return
        }
        NSWorkspace.shared.open(report.sourceURL)
    }

    func openSelectedReportSource() {
        guard let report = selectedReport else {
            return
        }
        NSWorkspace.shared.open(report.sourceURL)
    }

    func removeSelectedReport() async {
        guard let report = selectedReport else {
            return
        }
        do {
            try await database.deleteReport(reportID: report.id)
            await reload()
        } catch {
            showNotice(title: t("notice.deleteReportFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func review(for row: ReportTableRow) -> EvidenceReview? {
        let evidenceID = row.evidenceID ?? row.id
        return evidenceReviews.first { $0.evidenceID == evidenceID && $0.reportID == selectedReportID }
            ?? row.review
    }

    func saveReview(for row: ReportTableRow, decision: EvidenceDecision, severity: RiskLevel?, note: String) async {
        guard let report = selectedReport else {
            return
        }
        let evidenceID = row.evidenceID ?? row.id
        let existing = review(for: row)
        let review = existing?.updated(decision: decision, severity: severity, reviewerNote: note)
            ?? EvidenceReview(
                id: UUID.pitcherPlantStable(namespace: "evidence-review", components: [report.id.uuidString, evidenceID.uuidString]),
                reportID: report.id,
                evidenceID: evidenceID,
                evidenceType: row.evidenceType ?? EvidenceType(rawValue: selectedReportSection?.rawValue ?? "") ?? .text,
                decision: decision,
                severity: severity,
                reviewerNote: note
            )
        do {
            try await database.upsertEvidenceReview(review)
            await reload()
        } catch {
            showNotice(title: t("notice.reviewSaveFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func quickReviewSelectedEvidence(_ decision: EvidenceDecision) async {
        guard let row = selectedReportRow else {
            return
        }
        await saveReview(for: row, decision: decision, severity: row.riskAssessment?.level, note: review(for: row)?.reviewerNote ?? "")
        if decision == .whitelisted, let pattern = row.columns.first, pattern.isEmpty == false {
            await addWhitelistRule(pattern: pattern, type: .filename)
        }
    }

    func addWhitelistRule(pattern: String, type: WhitelistRule.RuleType) async {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let rule = WhitelistRule(type: type, pattern: trimmed)
        do {
            try await database.upsertWhitelistRule(rule)
            await reload()
        } catch {
            showNotice(title: t("notice.whitelistSaveFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func removeWhitelistRule(_ rule: WhitelistRule) async {
        do {
            try await database.deleteWhitelistRule(id: rule.id)
            await reload()
        } catch {
            showNotice(title: t("notice.whitelistDeleteFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func importFingerprintPackageWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip, .json]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importFingerprintPackage(at: url) }
        }
    }

    func importFingerprintPackage(at url: URL, tags: [String] = []) async {
        do {
            let result = try FingerprintPackageService().importPackage(from: url, additionalTags: tags)
            try await database.upsertFingerprintRecords(result.records)
            await reload()
            let skipped = result.skippedCount > 0 ? "，跳过 \(result.skippedCount) 条无效记录" : ""
            showNotice(title: t("notice.fingerprintImportSucceeded"), message: "导入 \(result.importedCount) 条指纹\(skipped)", tone: .success)
        } catch {
            showNotice(title: t("notice.fingerprintImportFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func exportFingerprintPackage(records selectedRecords: [FingerprintRecord]? = nil) {
        let recordsToExport = selectedRecords ?? fingerprints
        guard !recordsToExport.isEmpty else {
            showNotice(title: t("notice.fingerprintExportFailed"), message: t("fingerprints.empty"), tone: .error)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "PitcherPlant-Fingerprints-\(Self.safeTimestamp()).zip"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try FingerprintPackageService().exportPackage(
                    records: recordsToExport,
                    to: url,
                    packageName: "PitcherPlant Fingerprints"
                )
                showNotice(title: t("notice.fingerprintExportSucceeded"), message: url.path, tone: .success)
            } catch {
                showNotice(title: t("notice.fingerprintExportFailed"), message: error.localizedDescription, tone: .error)
            }
        }
    }

    func deleteFingerprints(tag: String) async {
        do {
            let deletedCount = try await database.deleteFingerprintRecords(tag: tag)
            await reload()
            showNotice(title: t("notice.fingerprintCleanupSucceeded"), message: "清理 \(deletedCount) 条指纹", tone: .success)
        } catch {
            showNotice(title: t("notice.fingerprintCleanupFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func exportSelectedReportAsHTML() {
        exportSelectedReport(format: .html)
    }

    func exportSelectedReportAsPDF() {
        exportSelectedReport(format: .pdf)
    }

    func exportSelectedReportAsCSV() {
        exportSelectedReport(format: .csv)
    }

    func exportSelectedReportAsJSON() {
        exportSelectedReport(format: .json)
    }

    func exportSelectedReportAsMarkdown() {
        exportSelectedReport(format: .markdown)
    }

    func exportSelectedReportAsEvidenceBundle() {
        exportSelectedReport(format: .bundle)
    }

    func exportSelectedReport(format: ExportRecord.Format) {
        guard let report = selectedReport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType(for: format)]
        panel.nameFieldStringValue = "\(report.title).\(fileExtension(for: format))"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try export(report: report, format: format, to: url)
                Task {
                    do {
                        try await database.recordExport(
                            ExportRecord(
                                reportID: report.id,
                                reportTitle: report.title,
                                format: format,
                                destinationPath: url.path
                            )
                        )
                        await reload()
                        showNotice(title: t("notice.exportSucceeded"), message: url.path, tone: .success)
                    } catch {
                        showNotice(title: t("notice.exportRecordFailed"), message: error.localizedDescription, tone: .error)
                    }
                }
            } catch {
                showNotice(title: t("notice.exportFailed"), message: error.localizedDescription, tone: .error)
            }
        }
    }

    func importSubmissionPackageWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, .folder]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importSubmissionPackage(at: url) }
        }
    }

    func importSubmissionPackage(at url: URL) async {
        do {
            let service = SubmissionImportService()
            let result = try service.importPackage(
                at: url,
                into: database.databaseURL.deletingLastPathComponent()
            )
            try await database.upsertSubmissionBatch(result.batch, items: result.items)
            let jobsToQueue = service.auditJobs(
                from: result,
                outputDirectory: URL(fileURLWithPath: draftConfiguration.outputDirectoryPath),
                template: draftConfiguration.reportNameTemplate
            )
            for job in jobsToQueue {
                try await database.upsertJob(job)
            }
            await reload()
            showNotice(title: t("notice.importSucceeded"), message: "\(result.items.count) 个提交已入队", tone: .success)
            beginQueuedAudits()
        } catch {
            showNotice(title: t("notice.importFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    @discardableResult
    func startAudit() async -> AuditReport? {
        guard !isRunningAudit else {
            return nil
        }
        isRunningAudit = true
        defer { isRunningAudit = false }

        let job = AuditJob(configuration: draftConfiguration)
        return await performAudit(job: job, saveDraft: true, selectCompletedReport: true)
    }

    func retryJob(_ job: AuditJob) async {
        guard job.status == .failed else {
            return
        }
        do {
            try await database.upsertJob(job.retried())
            await reload()
            beginQueuedAudits()
        } catch {
            showNotice(title: t("notice.retryFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    @discardableResult
    private func processQueuedAudits() async -> AuditReport? {
        guard !isRunningAudit else {
            return nil
        }
        isRunningAudit = true
        defer { isRunningAudit = false }

        var latestReport: AuditReport?
        while !Task.isCancelled {
            await reload()
            guard let queuedJob = jobs
                .filter({ $0.status == .queued })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first
            else {
                break
            }
            if let report = await performAudit(job: queuedJob, saveDraft: false, selectCompletedReport: false) {
                latestReport = report
            }
        }

        await reload()
        if let latestReport, !Task.isCancelled {
            selectReportForInlineReview(latestReport)
        }
        return latestReport
    }

    @discardableResult
    private func performAudit(job initialJob: AuditJob, saveDraft: Bool, selectCompletedReport: Bool) async -> AuditReport? {
        var job = initialJob
        let configuration = job.configuration
        selectedJobID = job.id
        do {
            try Task.checkCancellation()
            try await database.upsertJob(job)
            await reload()

            let historicalFingerprints = fingerprints
            let rules = whitelistRules
            let result = try await auditRunner.run(
                configuration: configuration,
                importedFingerprints: historicalFingerprints,
                whitelistRules: rules
            ) { stage, message in
                job = job.advanced(stage: stage, message: message)
                try await self.database.upsertJob(job)
                await self.reload()
            }

            job = job.completed(reportID: result.report.id, summaryMessage: Self.auditSummaryMessage(for: result.summary))
            try await database.upsertJob(job)
            try await database.saveReport(result.report)
            if !result.fingerprints.isEmpty {
                try await database.insertFingerprints(result.fingerprints)
            }
            if let documents = try? DocumentIngestionService(configuration: configuration).ingestDocuments(in: URL(fileURLWithPath: configuration.directoryPath)) {
                let features = DocumentFeatureStore().buildFeatures(for: documents)
                try? await database.upsertDocumentFeatures(features)
            }
            if selectCompletedReport {
                selectReportForInlineReview(result.report)
            }
            if saveDraft {
                AppPreferences.saveDraftConfiguration(configuration, for: workspaceRoot)
            }
            await reload()
            if selectCompletedReport {
                selectReportForInlineReview(result.report)
            }
            return result.report
        } catch {
            job = job.failed(Self.auditFailureMessage(for: error))
            try? await database.upsertJob(job)
            await reload()
            showNotice(title: error is CancellationError ? t("notice.auditCancelled") : t("notice.auditFailed"), message: job.latestMessage, tone: error is CancellationError ? .info : .error)
            return nil
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func showNotice(title: String, message: String, tone: AppNotice.Tone) {
        notice = AppNotice(title: title, message: message, tone: tone)
    }

    nonisolated static func auditFailureMessage(for error: Error) -> String {
        if error is CancellationError {
            return "审计已取消。"
        }
        return error.localizedDescription
    }

    nonisolated static func auditSummaryMessage(for summary: AuditRunSummary) -> String {
        let duration = summary.duration.formatted(.number.precision(.fractionLength(1)))
        return "完成：\(summary.documentCount) 个文档 / \(summary.imageCount) 张图片 / \(summary.historicalFingerprintCount) 条历史指纹，耗时 \(duration) 秒"
    }

    nonisolated private static func safeTimestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    private func selectReportForInlineReview(_ report: AuditReport) {
        latestReport = report
        selectedReportID = report.id
        let section = report.preferredEvidenceSection
        selectedReportSection = section?.kind
        selectedReportRowID = section?.table?.rows.first?.id
        selectedMainSidebar = .reports
        NSApp.activate(ignoringOtherApps: true)
    }

    private func syncReportSelection() {
        guard let report = selectedReport ?? reports.first else {
            selectedReportSection = nil
            selectedReportRowID = nil
            return
        }
        selectedReportID = report.id
        if selectedReportSection == nil || report.displaySections.contains(where: { $0.kind == selectedReportSection }) == false {
            selectedReportSection = report.preferredEvidenceSection?.kind
        }
        if let section = selectedReportSectionModel, let rows = section.table?.rows, !rows.isEmpty {
            if selectedReportRowID == nil || rows.contains(where: { $0.id == selectedReportRowID }) == false {
                selectedReportRowID = rows.first?.id
            }
        } else {
            selectedReportRowID = nil
        }
    }

    private func reportWithReviews(_ report: AuditReport) -> AuditReport {
        let reviewsByEvidenceID = Dictionary(uniqueKeysWithValues: evidenceReviews
            .filter { $0.reportID == report.id }
            .map { ($0.evidenceID, $0) })
        let sections = report.sections.map { section in
            var copy = section
            if let table = section.table {
                copy.table = ReportTable(
                    headers: table.headers,
                    rows: table.rows.map { row in
                        var rowCopy = row
                        if let review = reviewsByEvidenceID[row.evidenceID ?? row.id] {
                            rowCopy.review = review
                            rowCopy.badges = rowCopy.badges.filter { badge in
                                EvidenceDecision.allCases.contains(where: { $0.title == badge.title }) == false
                            } + [ReportBadge(title: review.decision.title, tone: review.decision.badgeTone)]
                            if let severity = review.severity, let current = rowCopy.riskAssessment {
                                rowCopy.riskAssessment = RiskAssessment(
                                    score: current.score,
                                    level: severity,
                                    reasons: current.reasons,
                                    evidenceCount: current.evidenceCount
                                )
                            }
                        }
                        return rowCopy
                    }
                )
            }
            return copy
        }
        return AuditReport(
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

    private func export(report: AuditReport, format: ExportRecord.Format, to url: URL) throws {
        switch format {
        case .html:
            try ReportExporter.exportHTML(report: report, to: url)
        case .pdf:
            try ReportExporter.exportPDF(report: report, to: url)
        case .csv:
            try ReportExporter.exportCSV(report: report, to: url)
        case .json:
            try ReportExporter.exportJSON(report: report, to: url)
        case .markdown:
            try ReportExporter.exportMarkdown(report: report, to: url)
        case .bundle:
            try ReportExporter.exportEvidenceBundle(report: report, to: url)
        }
    }

    private func contentType(for format: ExportRecord.Format) -> UTType {
        switch format {
        case .html: return .html
        case .pdf: return .pdf
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .markdown: return .text
        case .bundle: return .zip
        }
    }

    private func fileExtension(for format: ExportRecord.Format) -> String {
        switch format {
        case .html: return "html"
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .json: return "json"
        case .markdown: return "md"
        case .bundle: return "zip"
        }
    }
}

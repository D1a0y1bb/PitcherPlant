import AppKit
import Foundation
import Observation
import SwiftUI

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
            reports = try await database.loadReports()
            fingerprints = try await database.loadFingerprintRecords()
            whitelistRules = try await database.loadWhitelistRules()
            configurationPresets = AppPreferences.loadPresets(for: workspaceRoot)
            exportRecords = try await database.loadExportRecords(limit: 20)
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

    func exportSelectedReportAsHTML() {
        guard let report = selectedReport else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(report.title).html"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ReportExporter.exportHTML(report: report, to: url)
                Task {
                    do {
                        try await database.recordExport(
                            ExportRecord(
                                reportID: report.id,
                                reportTitle: report.title,
                                format: .html,
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

    func exportSelectedReportAsPDF() {
        guard let report = selectedReport else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(report.title).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ReportExporter.exportPDF(report: report, to: url)
                Task {
                    do {
                        try await database.recordExport(
                            ExportRecord(
                                reportID: report.id,
                                reportTitle: report.title,
                                format: .pdf,
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

    @discardableResult
    func startAudit() async -> AuditReport? {
        guard !isRunningAudit else {
            return nil
        }
        isRunningAudit = true
        defer { isRunningAudit = false }

        var job = AuditJob(configuration: draftConfiguration)
        selectedJobID = job.id
        do {
            try Task.checkCancellation()
            try await database.upsertJob(job)
            await reload()

            let historicalFingerprints = fingerprints
            let rules = whitelistRules
            let result = try await auditRunner.run(
                configuration: draftConfiguration,
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
            selectReportForInlineReview(result.report)
            AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
            await reload()
            selectReportForInlineReview(result.report)
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
}

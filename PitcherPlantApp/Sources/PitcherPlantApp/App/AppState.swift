import AppKit
import Foundation
import Observation
import SwiftUI

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

    var draftConfiguration: AuditConfiguration
    var latestReport: AuditReport?
    var lastMigrationSummary: MigrationSummary?
    var isRunningAudit = false

    init() {
        let locator = ProjectLocator()
        self.workspaceRoot = locator.workspaceRoot()
        self.database = try! DatabaseStore(rootDirectory: workspaceRoot)
        self.migrationService = MigrationService(workspaceRoot: workspaceRoot)
        self.auditRunner = AuditRunner()
        self.draftConfiguration = AppPreferences.loadDraftConfiguration(for: workspaceRoot)
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }
        hasBootstrapped = true
        do {
            try await database.prepare()
            lastMigrationSummary = try await migrationService.runIfNeeded(database: database)
        } catch {
            print("PitcherPlant bootstrap error: \(error)")
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
            latestReport = reports.sorted(by: { $0.createdAt > $1.createdAt }).first

            if selectedJobID == nil {
                selectedJobID = jobs.first?.id
            }
            if selectedReportID == nil {
                selectedReportID = latestReport?.id
            }
            if let report = selectedReport, selectedReportSection == nil {
                selectedReportSection = report.sections.first?.kind
            }
            syncReportSelection()
        } catch {
            print("PitcherPlant reload error: \(error)")
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
        if let selectedReportSection {
            return report.sections.first(where: { $0.kind == selectedReportSection }) ?? report.sections.first
        }
        return report.sections.first
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

    func selectReport(_ reportID: UUID?) {
        selectedReportID = reportID
        syncReportSelection()
    }

    func selectReportSection(_ kind: ReportSectionKind?) {
        selectedReportSection = kind
        selectedReportRowID = selectedReportSectionModel?.table?.rows.first?.id
    }

    func openReportsWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func openLatestReportInFinder() {
        guard let report = latestReport else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([report.sourceURL])
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
            print("PitcherPlant delete report error: \(error)")
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
            print("PitcherPlant save whitelist error: \(error)")
        }
    }

    func removeWhitelistRule(_ rule: WhitelistRule) async {
        do {
            try await database.deleteWhitelistRule(id: rule.id)
            await reload()
        } catch {
            print("PitcherPlant delete whitelist error: \(error)")
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
            } catch {
                print("PitcherPlant export html error: \(error)")
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
            } catch {
                print("PitcherPlant export pdf error: \(error)")
            }
        }
    }

    func startAudit() async {
        guard !isRunningAudit else {
            return
        }
        isRunningAudit = true
        var job = AuditJob(configuration: draftConfiguration)
        selectedJobID = job.id
        do {
            try await database.upsertJob(job)
            await reload()

            let historicalFingerprints = fingerprints
            let rules = whitelistRules
            let result = try await auditRunner.run(
                configuration: draftConfiguration,
                importedFingerprints: historicalFingerprints,
                whitelistRules: rules
            ) { stage, message in
                Task { @MainActor in
                    job = job.advanced(stage: stage, message: message)
                    try? await self.database.upsertJob(job)
                    await self.reload()
                }
            }

            job = job.completed(reportID: result.report.id)
            try await database.upsertJob(job)
            try await database.saveReport(result.report)
            if !result.fingerprints.isEmpty {
                try await database.insertFingerprints(result.fingerprints)
            }
            AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
            await reload()
        } catch {
            job = job.failed(error.localizedDescription)
            try? await database.upsertJob(job)
            await reload()
        }
        isRunningAudit = false
    }

    private func syncReportSelection() {
        guard let report = selectedReport ?? reports.first else {
            selectedReportSection = nil
            selectedReportRowID = nil
            return
        }
        if selectedReportSection == nil || report.sections.contains(where: { $0.kind == selectedReportSection }) == false {
            selectedReportSection = report.sections.first?.kind
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

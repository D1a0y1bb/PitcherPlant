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

struct DatabaseRecoveryState: Identifiable, Equatable {
    let id = UUID()
    let failedRootPath: String
    let fallbackRootPath: String
    let message: String
}

struct EvidenceCollectionItem: Identifiable, Hashable, Sendable {
    let id: String
    let reportID: UUID
    let reportTitle: String
    let sectionKind: ReportSectionKind
    let sectionTitle: String
    var row: ReportTableRow

    init(report: AuditReport, section: ReportSection, row: ReportTableRow) {
        let evidenceID = row.evidenceID ?? row.id
        self.id = "\(report.id.uuidString):\(evidenceID.uuidString)"
        self.reportID = report.id
        self.reportTitle = report.title
        self.sectionKind = section.kind
        self.sectionTitle = section.title
        self.row = row
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return true
        }
        return searchCorpus.localizedCaseInsensitiveContains(trimmed)
    }

    private var searchCorpus: String {
        let badgeCorpus = row.badges.map(\.title).joined(separator: "\n")
        let attachmentCorpus = row.attachments
            .flatMap { [$0.title, $0.subtitle, $0.body] }
            .joined(separator: "\n")
        return ([reportTitle, sectionTitle, row.detailTitle, row.detailBody, badgeCorpus, attachmentCorpus] + row.columns)
            .joined(separator: "\n")
    }
}

private struct EvidenceReviewKey: Hashable {
    let reportID: UUID
    let evidenceID: UUID
}

@MainActor
@Observable
final class AppState {
    let workspaceRoot: URL
    let database: DatabaseStore

    var hasBootstrapped = false

    var selectedMainSidebar: MainSidebarItem = .workspace
    var selectedJobID: UUID?
    var selectedReportID: UUID?
    var selectedReportSection: ReportSectionKind?
    var selectedReportRowID: UUID?
    var inspectorRequestID = UUID()
    var inspectorToggleRequestID = UUID()

    var jobs: [AuditJob] = []
    var reports: [AuditReport] = []
    var reportTotalCount = 0
    var reportLibraryReports: [AuditReport] = []
    var reportLibraryTotalCount = 0
    var fingerprints: [FingerprintRecord] = []
    var fingerprintTotalCount = 0
    var fingerprintLibraryRecords: [FingerprintRecord] = []
    var fingerprintLibraryTotalCount = 0
    var whitelistRules: [WhitelistRule] = []
    var configurationPresets: [AuditConfigurationPreset] = []
    var exportRecords: [ExportRecord] = []
    var evidenceReviews: [EvidenceReview] = []
    var evidenceReviewRevision = 0
    var submissionBatches: [SubmissionBatch] = []
    var whitelistSuggestions: [WhitelistSuggestion] = []
    var appSettings: AppSettings

    var draftConfiguration: AuditConfiguration
    var latestReport: AuditReport?
    var initializationMessage: String?
    var databaseRecovery: DatabaseRecoveryState?
    var notice: AppNotice?
    var availableUpdate: UpdateCheckResult?
    var lastUpdateCheckDate: Date?
    var isRunningAudit = false
    var isImportingSubmissionPackage = false
    private var currentAuditTask: Task<AuditReport?, Never>?
    private var currentAuditWorkerTask: Task<AuditRunResult, Error>?
    private var updateMonitorTask: Task<Void, Never>?
    private let appUpdater = AppUpdater()
    private static let reportPageLimit = 500
    private static let fingerprintPageLimit = 500
    private static let updateMonitorIntervalSeconds: UInt64 = 30 * 60

    init(workspaceRoot: URL? = nil) {
        let resolvedRoot = workspaceRoot ?? ProjectLocator().workspaceRoot()
        self.workspaceRoot = resolvedRoot
        let settings = AppPreferences.loadAppSettings()
        self.appSettings = settings
        self.selectedMainSidebar = .workspace
        let databaseResult = Self.makeDatabase(rootDirectory: resolvedRoot, language: settings.language)
        self.database = databaseResult.database
        self.initializationMessage = databaseResult.message
        self.databaseRecovery = databaseResult.recovery
        self.draftConfiguration = AppPreferences.loadDraftConfiguration(for: resolvedRoot)
    }

    private static func makeDatabase(rootDirectory: URL, language: AppLanguage) -> (database: DatabaseStore, message: String?, recovery: DatabaseRecoveryState?) {
        do {
            return (try DatabaseStore(rootDirectory: rootDirectory), nil, nil)
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("PitcherPlant", isDirectory: true)
                .appendingPathComponent("AppStateFallback", isDirectory: true)
            do {
                let database = try DatabaseStore(rootDirectory: fallbackRoot)
                let message = localized("database.recovery.initFailed", language: language, error.localizedDescription)
                let recovery = DatabaseRecoveryState(
                    failedRootPath: rootDirectory.path,
                    fallbackRootPath: fallbackRoot.path,
                    message: message
                )
                return (database, localized("database.recovery.pending", language: language, error.localizedDescription), recovery)
            } catch {
                preconditionFailure("PitcherPlant database initialization failed: \(error)")
            }
        }
    }

    nonisolated private static func localized(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(
            format: LocalizationStrings.text(key, language: language),
            locale: LocalizationStrings.locale(for: language),
            arguments: arguments
        )
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else {
            return
        }
        guard databaseRecovery == nil else {
            return
        }
        hasBootstrapped = true
        do {
            try await database.prepare()
            _ = try await database.markInterruptedJobs(message: t("database.recovery.interrupted"))
        } catch {
            showNotice(title: t("notice.bootstrapFailed"), message: error.localizedDescription, tone: .error)
        }
        await reload()
    }

    func continueWithTemporaryDatabase() {
        databaseRecovery = nil
        showNotice(
            title: t("database.recovery.temporaryTitle"),
            message: t("database.recovery.temporaryMessage"),
            tone: .info
        )
        Task {
            await bootstrapIfNeeded()
        }
    }

    func revealDatabaseRecoveryWorkspace() {
        guard let databaseRecovery else {
            return
        }
        let root = URL(fileURLWithPath: databaseRecovery.failedRootPath)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func backupFailedDatabase() {
        guard let databaseRecovery else {
            return
        }
        let supportDirectory = URL(fileURLWithPath: databaseRecovery.failedRootPath)
            .appendingPathComponent(".pitcherplant-macos", isDirectory: true)
        let databaseURL = supportDirectory.appendingPathComponent("PitcherPlantMac.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            showNotice(title: t("database.recovery.backupMissing"), message: databaseURL.path, tone: .error)
            return
        }

        let timestamp = DateFormatter.pitcherPlantFileName.string(from: .now)
        let backupURL = supportDirectory.appendingPathComponent("PitcherPlantMac-\(timestamp).sqlite.backup")
        do {
            try FileManager.default.copyItem(at: databaseURL, to: backupURL)
            showNotice(title: t("database.recovery.backupSucceeded"), message: backupURL.path, tone: .success)
        } catch {
            showNotice(title: t("database.recovery.backupFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func reload() async {
        do {
            jobs = try await database.loadJobs()
            evidenceReviews = try await database.loadEvidenceReviews()
            let reportPage = try await database.loadReportsPage(limit: Self.reportPageLimit)
            var loadedReports = reportPage.values
            reportTotalCount = reportPage.totalCount
            if let selectedReportID,
               loadedReports.contains(where: { $0.id == selectedReportID }) == false,
               let selectedReport = try await database.loadReport(id: selectedReportID) {
                loadedReports.append(selectedReport)
            }
            reports = loadedReports.map(reportWithReviews)
            reportLibraryReports = reports
            reportLibraryTotalCount = reportTotalCount
            let fingerprintPage = try await database.loadFingerprintPage(limit: Self.fingerprintPageLimit)
            fingerprints = fingerprintPage.values
            fingerprintTotalCount = fingerprintPage.totalCount
            fingerprintLibraryRecords = fingerprints
            fingerprintLibraryTotalCount = fingerprintTotalCount
            whitelistRules = try await database.loadWhitelistRules()
            configurationPresets = AppPreferences.loadPresets(for: workspaceRoot)
            exportRecords = try await database.loadExportRecords(limit: 20)
            submissionBatches = try await database.loadSubmissionBatches()
            whitelistSuggestions = AppPreferences.loadWhitelistSuggestions()
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
            evidenceReviewRevision += 1
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
            ?? reportLibraryReports.first(where: { $0.id == selectedReportID })
    }

    var selectedReportSectionModel: ReportSection? {
        guard let report = selectedReport else { return nil }
        return report.displaySection(for: selectedReportSection)
    }

    var selectedReportRow: ReportTableRow? {
        guard let rows = selectedReportSectionModel?.table?.rows else { return nil }
        if let selectedReportRowID {
            return rows.first(where: { $0.matchesSelection(selectedReportRowID) }) ?? rows.first
        }
        return rows.first
    }

    var allEvidenceCount: Int {
        evidenceCollection(for: .all).count
    }

    var favoriteEvidenceCount: Int {
        evidenceCollection(for: .favorites).count
    }

    var watchedEvidenceCount: Int {
        evidenceCollection(for: .watched).count
    }

    func updateDraft(_ transform: (inout AuditConfiguration) -> Void) {
        transform(&draftConfiguration)
        AppPreferences.saveDraftConfiguration(draftConfiguration, for: workspaceRoot)
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        let previousLanguage = appSettings.language
        transform(&appSettings)
        AppPreferences.saveAppSettings(appSettings)
        if appSettings.language != previousLanguage {
            AppLanguageRuntime.apply(appSettings.language)
        }
        SystemMenuLocalizer.schedule(appState: self)
    }

    func requestInspector() {
        inspectorRequestID = UUID()
    }

    func requestInspectorToggle() {
        inspectorToggleRequestID = UUID()
    }

    func startUpdateMonitoring() {
        guard updateMonitorTask == nil else {
            return
        }
        updateMonitorTask = Task {
            await performSilentUpdateCheck()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.updateMonitorIntervalSeconds * 1_000_000_000)
                await performSilentUpdateCheck()
            }
        }
    }

    func checkForUpdatesManually() {
        NSApp.activate(ignoringOtherApps: true)
        appUpdater.checkForUpdates()
    }

    func presentAvailableUpdate() {
        guard availableUpdate != nil else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        appUpdater.checkForUpdates()
    }

    private func performSilentUpdateCheck() async {
        do {
            let result = try await UpdateCheckService().check()
            guard !Task.isCancelled else {
                return
            }
            lastUpdateCheckDate = result.checkedAt
            switch result.availability {
            case .updateAvailable:
                availableUpdate = result
            case .upToDate, .unknown:
                availableUpdate = nil
            }
        } catch is CancellationError {
        } catch {
            availableUpdate = nil
        }
    }

    func refreshReportLibrary(query: String = "") async {
        do {
            let page = try await database.searchReports(query: query, limit: Self.reportPageLimit)
            reportLibraryReports = page.values.map(reportWithReviews)
            reportLibraryTotalCount = page.totalCount
            if query.normalizedSearchQuery.isEmpty {
                reports = reportLibraryReports
                reportTotalCount = page.totalCount
                latestReport = reports.sorted(by: { $0.createdAt > $1.createdAt }).first
            }
            syncReportSelection()
        } catch {
            showNotice(title: t("notice.reloadFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func refreshFingerprintLibrary(query: String = "") async {
        do {
            let page = try await database.searchFingerprintRecords(query: query, limit: Self.fingerprintPageLimit)
            fingerprintLibraryRecords = page.values
            fingerprintLibraryTotalCount = page.totalCount
            if query.normalizedSearchQuery.isEmpty {
                fingerprints = page.values
                fingerprintTotalCount = page.totalCount
            }
        } catch {
            showNotice(title: t("notice.reloadFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func fingerprintCount(tag: String) async -> Int {
        (try? await database.countFingerprintRecords(tag: tag)) ?? 0
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
            defer {
                currentAuditWorkerTask?.cancel()
                currentAuditWorkerTask = nil
                isRunningAudit = false
                currentAuditTask = nil
            }
            return await startAudit()
        }
    }

    func beginQueuedAudits() {
        guard !isRunningAudit, currentAuditTask == nil, queuedJobCount > 0 else {
            return
        }
        currentAuditTask = Task {
            defer {
                currentAuditWorkerTask?.cancel()
                currentAuditWorkerTask = nil
                isRunningAudit = false
                currentAuditTask = nil
            }
            return await processQueuedAudits()
        }
    }

    func beginAudit(using preset: AuditConfigurationPreset) {
        applyPreset(preset)
        beginAudit()
    }

    func cancelAudit() {
        guard isRunningAudit || currentAuditTask != nil || currentAuditWorkerTask != nil else {
            return
        }
        currentAuditTask?.cancel()
        currentAuditWorkerTask?.cancel()
        isRunningAudit = false
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

    func isFavorite(row: ReportTableRow) -> Bool {
        review(for: row)?.isFavorite ?? row.review?.isFavorite ?? false
    }

    func isWatching(row: ReportTableRow) -> Bool {
        review(for: row)?.isWatched ?? row.review?.isWatched ?? false
    }

    func toggleFavoriteSelectedEvidence() async {
        guard let row = selectedReportRow else {
            return
        }
        await toggleFavorite(row: row)
    }

    func toggleWatchSelectedEvidence() async {
        guard let row = selectedReportRow else {
            return
        }
        await toggleWatch(row: row)
    }

    func toggleFavorite(row: ReportTableRow) async {
        await saveEvidenceFlags(for: row, isFavorite: !isFavorite(row: row), isWatched: nil)
    }

    func toggleWatch(row: ReportTableRow) async {
        await saveEvidenceFlags(for: row, isFavorite: nil, isWatched: !isWatching(row: row))
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

    func evidenceCollection(for scope: EvidenceCollectionScope) -> [EvidenceCollectionItem] {
        let reviewLookup = evidenceReviewLookup
        return reports.flatMap { report in
            report.sections.flatMap { section in
                guard section.kind != .overview, let rows = section.table?.rows else {
                    return [EvidenceCollectionItem]()
                }
                return rows.compactMap { row in
                    let rowWithReview = rowWithEffectiveReview(row, reportID: report.id, reviewLookup: reviewLookup)
                    switch scope {
                    case .all:
                        return EvidenceCollectionItem(report: report, section: section, row: rowWithReview)
                    case .favorites:
                        guard rowWithReview.review?.isFavorite == true else { return nil }
                        return EvidenceCollectionItem(report: report, section: section, row: rowWithReview)
                    case .watched:
                        guard rowWithReview.review?.isWatched == true else { return nil }
                        return EvidenceCollectionItem(report: report, section: section, row: rowWithReview)
                    }
                }
            }
        }
    }

    func selectEvidence(_ item: EvidenceCollectionItem) {
        selectedReportID = item.reportID
        selectedReportSection = item.sectionKind
        selectedReportRowID = item.row.evidenceID ?? item.row.id
    }

    func selectEvidence(_ target: EvidenceReviewTarget) {
        selectedReportID = target.reportID
        selectedReportSection = target.sectionKind
        selectedReportRowID = target.evidenceID
    }

    func quickReviewSelectedEvidence(_ decision: EvidenceDecision) async {
        guard let row = selectedReportRow else {
            return
        }
        let existing = review(for: row)
        await quickReview(row: row, decision: decision, severity: existing?.severity ?? row.riskAssessment?.level, note: existing?.reviewerNote ?? "")
    }

    func applyReviewDecision(
        to targets: [EvidenceReviewTarget],
        decision: EvidenceDecision,
        severity: RiskLevel?,
        note: String
    ) async {
        guard targets.isEmpty == false else {
            return
        }

        var seenTargets = Set<EvidenceReviewKey>()
        var uniqueTargets: [EvidenceReviewTarget] = []
        for target in targets {
            let key = EvidenceReviewKey(reportID: target.reportID, evidenceID: target.evidenceID)
            if seenTargets.insert(key).inserted {
                uniqueTargets.append(target)
            }
        }
        let reviewedEvidenceIDs = Set(uniqueTargets.map(\.evidenceID))

        for target in uniqueTargets {
            let existing = evidenceReviews.first { review in
                review.reportID == target.reportID && review.evidenceID == target.evidenceID
            } ?? reportRow(for: target)?.review
            let review = existing?.updated(decision: decision, severity: severity, reviewerNote: note)
                ?? EvidenceReview(
                    id: UUID.pitcherPlantStable(namespace: "evidence-review", components: [target.reportID.uuidString, target.evidenceID.uuidString]),
                    reportID: target.reportID,
                    evidenceID: target.evidenceID,
                    evidenceType: target.evidenceType,
                    decision: decision,
                    severity: severity,
                    reviewerNote: note
                )
            do {
                try await database.upsertEvidenceReview(review)
                if decision == .whitelisted,
                   let row = reportRow(for: target),
                   let candidate = whitelistRuleCandidate(for: row) {
                    let rule = WhitelistRule(type: candidate.type, pattern: candidate.pattern)
                    try await database.upsertWhitelistRule(rule)
                }
            } catch {
                showNotice(title: t("notice.reviewSaveFailed"), message: error.localizedDescription, tone: .error)
            }
        }

        let selectedBeforeReload = selectedReportRowID
        await reload()
        advanceSelectionAfterBatchReview(reviewedEvidenceIDs: reviewedEvidenceIDs, selectedBeforeReload: selectedBeforeReload)
    }

    func quickReview(row: ReportTableRow, decision: EvidenceDecision, severity: RiskLevel?, note: String) async {
        await saveReview(for: row, decision: decision, severity: severity, note: note)
        if decision == .whitelisted, let candidate = whitelistRuleCandidate(for: row) {
            await addWhitelistRule(pattern: candidate.pattern, type: candidate.type)
        }
    }

    private func saveEvidenceFlags(for row: ReportTableRow, isFavorite: Bool?, isWatched: Bool?) async {
        guard let report = selectedReport else {
            return
        }
        let evidenceID = row.evidenceID ?? row.id
        let existing = review(for: row)
        let review = existing?.updatedFlags(isFavorite: isFavorite, isWatched: isWatched)
            ?? EvidenceReview(
                id: UUID.pitcherPlantStable(namespace: "evidence-review", components: [report.id.uuidString, evidenceID.uuidString]),
                reportID: report.id,
                evidenceID: evidenceID,
                evidenceType: row.evidenceType ?? EvidenceType(rawValue: selectedReportSection?.rawValue ?? "") ?? .text,
                isFavorite: isFavorite ?? false,
                isWatched: isWatched ?? false
            )
        do {
            try await database.upsertEvidenceReview(review)
            await reload()
        } catch {
            showNotice(title: t("notice.reviewSaveFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    private func reportRow(for target: EvidenceReviewTarget) -> ReportTableRow? {
        reports
            .first(where: { $0.id == target.reportID })?
            .displaySection(for: target.sectionKind)?
            .table?
            .rows
            .first { $0.matchesSelection(target.evidenceID) || $0.id == target.rowID }
    }

    private func advanceSelectionAfterBatchReview(reviewedEvidenceIDs: Set<UUID>, selectedBeforeReload: UUID?) {
        guard let selectedBeforeReload,
              reviewedEvidenceIDs.contains(selectedBeforeReload),
              let rows = selectedReportSectionModel?.table?.rows,
              rows.isEmpty == false,
              let currentIndex = rows.firstIndex(where: { $0.matchesSelection(selectedBeforeReload) }) else {
            return
        }

        let orderedCandidates = Array(rows.dropFirst(currentIndex + 1)) + Array(rows.prefix(currentIndex))
        if let next = orderedCandidates.first(where: { row in
            let evidenceID = row.evidenceID ?? row.id
            return reviewedEvidenceIDs.contains(evidenceID) == false && (review(for: row)?.decision ?? .pending) == .pending
        }) {
            selectedReportRowID = next.evidenceID ?? next.id
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

    func acceptWhitelistSuggestion(_ suggestion: WhitelistSuggestion) async {
        await setWhitelistSuggestionStatus(suggestion, status: .accepted)
        await addWhitelistRule(pattern: suggestion.rule.pattern, type: suggestion.rule.type)
    }

    func dismissWhitelistSuggestion(_ suggestion: WhitelistSuggestion) {
        setWhitelistSuggestionStatusInMemory(suggestion, status: .dismissed)
    }

    func acceptAllPendingWhitelistSuggestions() async {
        let pending = whitelistSuggestions.filter { $0.status == .pending }
        for suggestion in pending {
            await acceptWhitelistSuggestion(suggestion)
        }
    }

    func importFingerprintPackageWithPanel(tags: [String] = []) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip, .json]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await importFingerprintPackage(at: url, tags: tags) }
        }
    }

    func importFingerprintPackage(at url: URL, tags: [String] = []) async {
        do {
            let result = try FingerprintPackageService().importPackage(from: url, additionalTags: tags)
            try await database.upsertFingerprintRecords(result.records)
            await reload()
            let message = result.skippedCount > 0
                ? tf("notice.fingerprintImportSucceededWithSkippedMessage", result.importedCount, result.skippedCount)
                : tf("notice.fingerprintImportSucceededMessage", result.importedCount)
            showNotice(title: t("notice.fingerprintImportSucceeded"), message: message, tone: .success)
        } catch {
            showNotice(title: t("notice.fingerprintImportFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    func exportFingerprintPackage(records selectedRecords: [FingerprintRecord]? = nil, query: String? = nil, tags: [String] = []) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "PitcherPlant-Fingerprints-\(Self.safeTimestamp()).zip"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let recordsToExport: [FingerprintRecord]
                    if let selectedRecords {
                        recordsToExport = selectedRecords
                    } else if let query {
                        recordsToExport = try await database.loadFingerprintRecords(matching: query)
                    } else {
                        recordsToExport = try await database.loadFingerprintRecords()
                    }
                    guard recordsToExport.isEmpty == false else {
                        showNotice(title: t("notice.fingerprintExportFailed"), message: t("fingerprints.empty"), tone: .error)
                        return
                    }
                    try await Task.detached(priority: .userInitiated) {
                        try FingerprintPackageService().exportPackage(
                            records: recordsToExport,
                            to: url,
                            packageName: "PitcherPlant Fingerprints",
                            tags: tags,
                            source: "PitcherPlant macOS"
                        )
                    }.value
                    showNotice(title: t("notice.fingerprintExportSucceeded"), message: url.path, tone: .success)
                } catch {
                    showNotice(title: t("notice.fingerprintExportFailed"), message: error.localizedDescription, tone: .error)
                }
            }
        }
    }

    func deleteFingerprints(tag: String) async {
        do {
            let deletedCount = try await database.deleteFingerprintRecords(tag: tag)
            await reload()
            showNotice(title: t("notice.fingerprintCleanupSucceeded"), message: tf("notice.fingerprintCleanupSucceededMessage", deletedCount), tone: .success)
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
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try Self.export(report: report, format: format, to: url)
                    }.value
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
                    showNotice(title: t("notice.exportFailed"), message: error.localizedDescription, tone: .error)
                }
            }
        }
    }

    func importSubmissionPackageWithPanel() {
        guard isImportingSubmissionPackage == false else {
            return
        }
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
        guard isImportingSubmissionPackage == false else {
            return
        }
        isImportingSubmissionPackage = true
        defer { isImportingSubmissionPackage = false }

        let supportDirectory = database.databaseURL.deletingLastPathComponent()
        let outputDirectory = URL(fileURLWithPath: draftConfiguration.outputDirectoryPath)
        let reportNameTemplate = draftConfiguration.reportNameTemplate
        do {
            let imported = try await Task.detached(priority: .userInitiated) {
                let service = SubmissionImportService()
                let result = try service.importPackage(at: url, into: supportDirectory)
                let jobs = service.auditJobs(
                    from: result,
                    outputDirectory: outputDirectory,
                    template: reportNameTemplate
                )
                return (result, jobs)
            }.value
            let result = imported.0
            let jobsToQueue = imported.1
            try await database.upsertSubmissionBatch(result.batch, items: result.items)
            for job in jobsToQueue {
                try await database.upsertJob(job)
            }
            await reload()
            showNotice(title: t("notice.importSucceeded"), message: tf("notice.importQueuedSubmissionsMessage", result.items.count), tone: .success)
            beginQueuedAudits()
        } catch {
            showNotice(title: t("notice.importFailed"), message: error.localizedDescription, tone: .error)
        }
    }

    @discardableResult
    func startAudit() async -> AuditReport? {
        guard !Task.isCancelled, !isRunningAudit else {
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
        guard !Task.isCancelled, !isRunningAudit else {
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

            let historicalFingerprints = try await database.loadFingerprintRecords()
            let rules = whitelistRules
            let cachedFeatures = try await database.loadDocumentFeatures(batchID: job.batchID)
            let progressFallbackJob = job
            let scanID = job.id
            let batchID = job.batchID
            let progressHandler: @MainActor @Sendable (AuditStage, String) async throws -> Void = { stage, message in
                try await self.recordAuditProgress(
                    jobID: progressFallbackJob.id,
                    fallback: progressFallbackJob,
                    stage: stage,
                    message: message
                )
            }
            let auditWorkerTask = Task.detached(priority: .userInitiated) {
                try await AuditRunner().run(
                    configuration: configuration,
                    importedFingerprints: historicalFingerprints,
                    whitelistRules: rules,
                    cachedDocumentFeatures: cachedFeatures,
                    scanID: scanID,
                    batchID: batchID,
                    progress: progressHandler
                )
            }
            currentAuditWorkerTask = auditWorkerTask
            defer { currentAuditWorkerTask = nil }

            let result = try await auditWorkerTask.value
            try Task.checkCancellation()

            job = jobs.first(where: { $0.id == progressFallbackJob.id }) ?? job
            job = job.completed(reportID: result.report.id, summaryMessage: auditSummaryMessage(for: result.summary))
            try await database.upsertJob(job)
            replaceJobInMemory(job)
            try await database.saveReport(result.report)
            if !result.fingerprints.isEmpty {
                let fingerprints = try await fingerprintsWithSourceContext(
                    result.fingerprints,
                    reportID: result.report.id,
                    job: job
                )
                try await database.insertFingerprints(fingerprints)
            }
            if let featureResult = result.documentFeatureResult {
                if featureResult.invalidatedFeatureIDs.isEmpty == false {
                    _ = try await database.deleteDocumentFeatures(ids: featureResult.invalidatedFeatureIDs)
                }
                try await database.upsertDocumentFeatures(featureResult.features)
                if featureResult.orphanedFeatureIDs.isEmpty == false {
                    _ = try await database.deleteDocumentFeatures(ids: featureResult.orphanedFeatureIDs)
                }
            }
            refreshWhitelistSuggestions(from: result.documents)
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
            job = job.failed(auditFailureMessage(for: error))
            try? await database.upsertJob(job)
            replaceJobInMemory(job)
            await reload()
            showNotice(title: error is CancellationError ? t("notice.auditCancelled") : t("notice.auditFailed"), message: job.latestMessage, tone: error is CancellationError ? .info : .error)
            return nil
        }
    }

    private func replaceJobInMemory(_ job: AuditJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        selectedJobID = job.id
    }

    private func recordAuditProgress(
        jobID: UUID,
        fallback: AuditJob,
        stage: AuditStage,
        message: String
    ) async throws {
        let currentJob = jobs.first(where: { $0.id == jobID }) ?? fallback
        let updatedJob = currentJob.advanced(stage: stage, message: message)
        try await database.upsertJob(updatedJob)
        replaceJobInMemory(updatedJob)
    }

    func dismissNotice() {
        notice = nil
    }

    func showNotice(title: String, message: String, tone: AppNotice.Tone) {
        notice = AppNotice(title: title, message: message, tone: tone)
    }

    func auditFailureMessage(for error: Error) -> String {
        Self.auditFailureMessage(for: error, language: appSettings.language)
    }

    func auditSummaryMessage(for summary: AuditRunSummary) -> String {
        Self.auditSummaryMessage(for: summary, language: appSettings.language)
    }

    nonisolated static func auditFailureMessage(for error: Error, language: AppLanguage = .zhHans) -> String {
        if error is CancellationError {
            return localized("audit.failure.cancelled", language: language)
        }
        return error.localizedDescription
    }

    nonisolated static func auditSummaryMessage(for summary: AuditRunSummary, language: AppLanguage = .zhHans) -> String {
        let locale = LocalizationStrings.locale(for: language)
        let duration = String(format: "%.1f", locale: locale, summary.duration)
        let base = localized(
            "audit.summary.base",
            language: language,
            summary.documentCount,
            summary.imageCount,
            summary.historicalFingerprintCount,
            duration
        )
        guard summary.recallStats.isEmpty == false else {
            return base
        }
        let candidatePairs = summary.recallStats.reduce(0) { $0 + $1.candidatePairCount }
        let possiblePairs = summary.recallStats.reduce(0) { $0 + $1.possiblePairCount }
        let elapsed = summary.recallStats.reduce(0) { $0 + $1.elapsedMilliseconds }
        return localized(
            "audit.summary.recall",
            language: language,
            base,
            candidatePairs,
            possiblePairs,
            String(format: "%.1f", locale: locale, elapsed)
        )
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
            if selectedReportRowID == nil || rows.contains(where: { $0.matchesSelection(selectedReportRowID) }) == false {
                selectedReportRowID = rows.first?.id
            }
        } else {
            selectedReportRowID = nil
        }
    }

    private func refreshWhitelistSuggestions(from documents: [ParsedDocument]) {
        let statuses = AppPreferences.loadWhitelistSuggestionStatuses()
        let existingRules = Set(whitelistRules.map { "\($0.type.rawValue):\($0.pattern)" })
        let suggestions = WhitelistSuggestionService(reasons: whitelistSuggestionReasons())
            .suggest(from: documents)
            .map { suggestion in
                var copy = suggestion
                if let status = statuses[suggestion.id] {
                    copy.status = status
                } else if existingRules.contains("\(suggestion.rule.type.rawValue):\(suggestion.rule.pattern)") {
                    copy.status = .accepted
                }
                return copy
            }
        whitelistSuggestions = suggestions
        AppPreferences.saveWhitelistSuggestions(suggestions)
    }

    func whitelistSuggestionReasons() -> WhitelistSuggestionService.Reasons {
        WhitelistSuggestionService.Reasons(
            textTemplate: t("whitelist.reason.textTemplate"),
            codeTemplate: t("whitelist.reason.codeTemplate"),
            imageHash: t("whitelist.reason.imageHash"),
            metadata: t("whitelist.reason.metadata"),
            pathPattern: t("whitelist.reason.pathPattern")
        )
    }

    private func setWhitelistSuggestionStatus(_ suggestion: WhitelistSuggestion, status: WhitelistSuggestionStatus) async {
        setWhitelistSuggestionStatusInMemory(suggestion, status: status)
    }

    private func setWhitelistSuggestionStatusInMemory(_ suggestion: WhitelistSuggestion, status: WhitelistSuggestionStatus) {
        var statuses = AppPreferences.loadWhitelistSuggestionStatuses()
        statuses[suggestion.id] = status
        AppPreferences.saveWhitelistSuggestionStatuses(statuses)
        whitelistSuggestions = whitelistSuggestions.map { item in
            guard item.id == suggestion.id else { return item }
            var copy = item
            copy.status = status
            return copy
        }
        AppPreferences.saveWhitelistSuggestions(whitelistSuggestions)
    }

    private func whitelistRuleCandidate(for row: ReportTableRow) -> (pattern: String, type: WhitelistRule.RuleType)? {
        let body = ([row.detailBody] + row.attachments.flatMap { [$0.title, $0.subtitle, $0.body] })
            .joined(separator: "\n")
        let evidenceText = row.columns.dropFirst(3).first ?? body
        let type = row.evidenceType ?? EvidenceType(rawValue: selectedReportSection?.rawValue ?? "") ?? .dedup

        switch type {
        case .text:
            return cleanedWhitelistCandidate(row.attachments.first?.body ?? evidenceText, type: .textSnippet)
        case .code:
            return cleanedWhitelistCandidate(row.attachments.first?.body ?? evidenceText, type: .codeTemplate)
        case .image:
            if let hash = firstHashCandidate(in: body) {
                return (hash, .imageHash)
            }
            return cleanedWhitelistCandidate(evidenceText, type: .imageHash)
        case .metadata:
            return cleanedWhitelistCandidate(evidenceText, type: .metadata)
        case .dedup:
            return cleanedWhitelistCandidate(row.columns.first ?? evidenceText, type: .filename)
        case .crossBatch:
            return cleanedWhitelistCandidate(row.columns.first ?? evidenceText, type: .filename)
        }
    }

    private func fingerprintsWithSourceContext(
        _ records: [FingerprintRecord],
        reportID: UUID,
        job: AuditJob
    ) async throws -> [FingerprintRecord] {
        let batch = job.batchID.flatMap { batchID in
            submissionBatches.first(where: { $0.id == batchID })
        }
        let item: SubmissionItem?
        if let itemID = job.submissionItemID {
            item = try await database.loadSubmissionItems(batchID: job.batchID).first(where: { $0.id == itemID })
        } else {
            item = nil
        }
        return records.map { record in
            var copy = record
            copy.sourceReportID = reportID
            copy.batchName = batch?.name ?? record.batchName
            copy.teamName = item?.teamName ?? record.teamName
            copy.submissionItemID = item?.id ?? job.submissionItemID
            if copy.challengeName == nil {
                copy.challengeName = inferChallengeName(from: record, item: item)
            }
            return copy
        }
    }

    private func inferChallengeName(from record: FingerprintRecord, item: SubmissionItem?) -> String? {
        if let item {
            let itemURL = URL(fileURLWithPath: item.rootPath)
            let scanURL = URL(fileURLWithPath: record.scanDir)
            let parent = scanURL.deletingLastPathComponent().lastPathComponent
            if parent.isEmpty == false, parent != itemURL.lastPathComponent {
                return parent
            }
        }
        return nil
    }

    private func cleanedWhitelistCandidate(_ value: String, type: WhitelistRule.RuleType) -> (pattern: String, type: WhitelistRule.RuleType)? {
        let pattern = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard pattern.isEmpty == false else { return nil }
        return (String(pattern.prefix(220)), type)
    }

    private func firstHashCandidate(in value: String) -> String? {
        let pattern = #"[A-Fa-f0-9]{16,64}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let matchRange = Range(match.range, in: value) else {
            return nil
        }
        return String(value[matchRange])
    }

    private func reportWithReviews(_ report: AuditReport) -> AuditReport {
        let reviewLookup = evidenceReviewLookup
        let sections = report.sections.map { section in
            var copy = section
            if let table = section.table {
                copy.table = ReportTable(
                    headers: table.headers,
                    rows: table.rows.map { rowWithEffectiveReview($0, reportID: report.id, reviewLookup: reviewLookup) }
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
            metrics: report.metrics,
            sections: sections
        )
    }

    private var evidenceReviewLookup: [EvidenceReviewKey: EvidenceReview] {
        Dictionary(
            evidenceReviews.map { review in
                (EvidenceReviewKey(reportID: review.reportID, evidenceID: review.evidenceID), review)
            },
            uniquingKeysWith: { current, next in
                current.updatedAt >= next.updatedAt ? current : next
            }
        )
    }

    private func rowWithEffectiveReview(
        _ row: ReportTableRow,
        reportID: UUID,
        reviewLookup: [EvidenceReviewKey: EvidenceReview]
    ) -> ReportTableRow {
        let evidenceID = row.evidenceID ?? row.id
        guard let review = reviewLookup[EvidenceReviewKey(reportID: reportID, evidenceID: evidenceID)] ?? row.review else {
            return row
        }
        var rowCopy = row
        rowCopy.review = review
        if review.hasReviewerDisposition {
            rowCopy.badges = rowCopy.badges.filter { badge in
                EvidenceDecision.allCases.contains(where: { $0.title == badge.title }) == false
            } + [ReportBadge(title: review.decision.title, tone: review.decision.badgeTone)]
        }
        if let severity = review.severity, let current = rowCopy.riskAssessment {
            rowCopy.riskAssessment = RiskAssessment(
                score: current.score,
                level: severity,
                reasons: current.reasons,
                evidenceCount: current.evidenceCount
            )
        }
        return rowCopy
    }

    nonisolated private static func export(report: AuditReport, format: ExportRecord.Format, to url: URL) throws {
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

private extension ReportTableRow {
    func matchesSelection(_ selection: UUID?) -> Bool {
        guard let selection else { return false }
        return id == selection || evidenceID == selection
    }
}

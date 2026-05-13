import AppKit
import CryptoKit
import ImageIO
import SwiftUI

final class EvidenceDecodedImage: @unchecked Sendable {
    let image: NSImage

    init(image: NSImage) {
        self.image = image
    }
}

actor EvidenceImageCache {
    static let shared = EvidenceImageCache()
    private var imagesByKey: [String: EvidenceDecodedImage] = [:]
    private var accessOrder: [String] = []
    private let limit = 160

    func image(for base64: String, maxPixelSize: Int) async -> EvidenceDecodedImage? {
        let key = Self.cacheKey(for: base64, maxPixelSize: maxPixelSize)
        if let image = imagesByKey[key] {
            return image
        }

        guard let image = await Self.decodeImage(base64: base64, maxPixelSize: maxPixelSize) else {
            return nil
        }
        imagesByKey[key] = image
        accessOrder.append(key)
        trimIfNeeded()
        return image
    }

    func cachedImageCount() -> Int {
        imagesByKey.count
    }

    nonisolated static func cacheKey(for value: String, maxPixelSize: Int) -> String {
        "\(stableContentDigest(value))|\(maxPixelSize)"
    }

    private nonisolated static func decodeImage(base64: String, maxPixelSize: Int) async -> EvidenceDecodedImage? {
        await Task.detached(priority: .utility) {
            guard let data = Data(base64Encoded: base64) else {
                return nil
            }

            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    ] as CFDictionary
                  ) else {
                return NSImage(data: data).map { EvidenceDecodedImage(image: $0) }
            }

            let size = CGSize(width: cgImage.width, height: cgImage.height)
            return EvidenceDecodedImage(image: NSImage(cgImage: cgImage, size: size))
        }.value
    }

    private func trimIfNeeded() {
        while accessOrder.count > limit, let key = accessOrder.first {
            accessOrder.removeFirst()
            imagesByKey.removeValue(forKey: key)
        }
    }
}

actor CodeDiffCache {
    static let shared = CodeDiffCache()
    private var rowsByKey: [String: [CodeLineDiffRow]] = [:]
    private var accessOrder: [String] = []
    private let limit = 80

    func rows(left: String, right: String) -> [CodeLineDiffRow] {
        let key = Self.key(left: left, right: right)
        if let rows = rowsByKey[key] {
            return rows
        }
        let rows = CodeLineDiffBuilder.rows(left: left, right: right)
        rowsByKey[key] = rows
        accessOrder.append(key)
        trimIfNeeded()
        return rows
    }

    nonisolated static func key(left: String, right: String) -> String {
        "\(stableContentDigest(left))|\(stableContentDigest(right))"
    }

    private func trimIfNeeded() {
        while accessOrder.count > limit, let key = accessOrder.first {
            accessOrder.removeFirst()
            rowsByKey.removeValue(forKey: key)
        }
    }
}

struct CodeDiffSummary: Hashable, Sendable {
    let shared: Int
    let leftOnly: Int
    let rightOnly: Int
    let fragment: String?
}

actor CodeDiffSummaryCache {
    static let shared = CodeDiffSummaryCache()
    private var summariesByKey: [String: CodeDiffSummary] = [:]
    private var accessOrder: [String] = []
    private let limit = 80

    func summary(left: String, right: String) -> CodeDiffSummary {
        let key = CodeDiffCache.key(left: left, right: right)
        if let summary = summariesByKey[key] {
            return summary
        }

        let leftTokens = Set(EvidenceTokenAnalyzer.tokens(in: left))
        let rightTokens = Set(EvidenceTokenAnalyzer.tokens(in: right))
        let summary = CodeDiffSummary(
            shared: leftTokens.intersection(rightTokens).count,
            leftOnly: leftTokens.subtracting(rightTokens).count,
            rightOnly: rightTokens.subtracting(leftTokens).count,
            fragment: EvidenceTokenAnalyzer.bestSharedFragment(left: left, right: right)
        )
        summariesByKey[key] = summary
        accessOrder.append(key)
        trimIfNeeded()
        return summary
    }

    private func trimIfNeeded() {
        while accessOrder.count > limit, let key = accessOrder.first {
            accessOrder.removeFirst()
            summariesByKey.removeValue(forKey: key)
        }
    }
}

actor EvidenceTextAnalysisCache {
    static let shared = EvidenceTextAnalysisCache()
    private var highlightsByKey: [String: [String]] = [:]
    private var accessOrder: [String] = []
    private let limit = 120

    func sharedHighlights(in values: [String], fallback: String) -> [String] {
        let key = Self.key(values: values, fallback: fallback)
        if let highlights = highlightsByKey[key] {
            return highlights
        }
        let highlights = EvidenceTokenAnalyzer.sharedHighlights(in: values, fallback: fallback)
        highlightsByKey[key] = highlights
        accessOrder.append(key)
        trimIfNeeded()
        return highlights
    }

    private nonisolated static func key(values: [String], fallback: String) -> String {
        let valueKey = values.map(stableContentDigest).joined(separator: "|")
        return "\(valueKey)|\(stableContentDigest(fallback))"
    }

    private func trimIfNeeded() {
        while accessOrder.count > limit, let key = accessOrder.first {
            accessOrder.removeFirst()
            highlightsByKey.removeValue(forKey: key)
        }
    }
}

private actor CodeAttachmentRenderCache {
    static let shared = CodeAttachmentRenderCache()
    private var attachmentsByKey: [String: [ReportAttachment]] = [:]
    private var accessOrder: [String] = []
    private let limit = 80

    func renderedAttachments(_ attachments: [ReportAttachment], mode: CodeViewerMode) -> [ReportAttachment] {
        let key = Self.key(attachments: attachments, mode: mode)
        if let rendered = attachmentsByKey[key] {
            return rendered
        }
        let rendered = attachments.map { $0.transformedBody(mode.render($0.body)) }
        attachmentsByKey[key] = rendered
        accessOrder.append(key)
        trimIfNeeded()
        return rendered
    }

    private nonisolated static func key(attachments: [ReportAttachment], mode: CodeViewerMode) -> String {
        let bodyKey = attachments.map(attachmentCacheKey).joined(separator: "|")
        return "\(mode.rawValue)|\(bodyKey)"
    }

    private nonisolated static func attachmentCacheKey(_ attachment: ReportAttachment) -> String {
        let source = attachment.sourceReference
        let pageNumber = source?.pageNumber.map { String($0) } ?? ""
        let textRange = source?.textRange.map { "\($0.location):\($0.length)" } ?? ""
        let lineRange = source?.lineRange.map { "\($0.start):\($0.end)" } ?? ""
        let imageIndex = source?.imageIndex.map { String($0) } ?? ""
        let imageDigest = attachment.imageBase64.map(stableContentDigest) ?? ""
        let bodyDigest = stableContentDigest(attachment.body)
        return stableContentDigest([
            attachment.title,
            attachment.subtitle,
            attachment.sourceReferenceText,
            source?.filePath ?? "",
            pageNumber,
            textRange,
            lineRange,
            imageIndex,
            source?.hashAnchor ?? "",
            source?.sourceLabel ?? "",
            imageDigest,
            bodyDigest,
        ].joined(separator: "\u{1f}"))
    }

    private func trimIfNeeded() {
        while accessOrder.count > limit, let key = accessOrder.first {
            accessOrder.removeFirst()
            attachmentsByKey.removeValue(forKey: key)
        }
    }
}

private func stableContentDigest(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

struct ReportEvidenceInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let row = appState.selectedReportRow {
                ReportInspectorScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(row.detailTitle)
                                .font(AppTypography.sectionTitle)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !row.badges.isEmpty {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(row.badges, id: \.title) { badge in
                                            ReportBadgeView(badge: badge)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(row.badges, id: \.title) { badge in
                                            ReportBadgeView(badge: badge)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        EvidenceReviewPanel(row: row)

                        InspectorSection(title: appState.t("reports.evidenceDetails")) {
                            Text(row.detailBody)
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        EvidenceSemanticDetailView(row: row)

                        if !row.attachments.isEmpty {
                            InspectorSection(title: appState.t("reports.attachments")) {
                                ImageEvidenceDetailView(
                                    attachments: row.attachments,
                                    showsPreviews: appState.appSettings.showAttachmentPreviews
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let section = appState.selectedReportSectionModel {
                if section.table?.rows.isEmpty == false {
                    ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
                } else if let report = appState.selectedReport {
                    ReportQuickInspector(report: report)
                } else {
                    ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
                }
            } else {
                InspectorEmptyState(
                    title: appState.t("reports.noEvidenceSelection"),
                    subtitle: appState.t("reports.noEvidenceSelectionDescription"),
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReportInspectorScrollView<Content: View>: View {
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(width: max(proxy.size.width - horizontalPadding * 2, 1), alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, max(verticalPadding, AppLayout.titlebarScrollContentTopPadding))
                .padding(.bottom, verticalPadding)
            }
            .ignoresSafeArea(.container, edges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ReportQuickInspector: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        ReportInspectorScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("reports.reportProperties"))
                        .font(AppTypography.sectionTitle)
                    Text(report.title)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                InspectorSection(title: appState.t("reports.metrics")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.metrics, id: \.title) { metric in
                            HStack {
                                Label(metric.title, systemImage: metric.systemImage)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(metric.value)
                                    .fontWeight(.medium)
                            }
                            .font(AppTypography.metadata)
                        }
                    }
                }

                InspectorSection(title: appState.t("common.path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.t("reports.reportFile"))
                            .font(AppTypography.tableHeader)
                        Text(report.sourcePath)
                            .font(AppTypography.smallCode)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(appState.t("reports.scanDirectory"))
                            .font(AppTypography.tableHeader)
                        Text(report.scanDirectoryPath)
                            .font(AppTypography.smallCode)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReportSectionSummaryInspector: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let report: AuditReport?

    var body: some View {
        ReportInspectorScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title, systemImage: section.kind.systemImage)
                        .font(AppTypography.sectionTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let report {
                        Text(report.title)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                InspectorSection(title: appState.t("reports.sectionSummary")) {
                    Text(section.summary.isEmpty ? appState.t("reports.sectionNoStructuredEvidence") : section.summary)
                        .font(AppTypography.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if section.callouts.isEmpty == false {
                    InspectorSection(title: appState.t("reports.callouts")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.callouts, id: \.self) { callout in
                                Label(callout, systemImage: "info.circle")
                                    .font(AppTypography.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let table = section.table {
                    InspectorSection(title: appState.t("reports.evidenceCount")) {
                        Text("\(table.rows.count) \(appState.t("reports.structuredRecords"))")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        AppInspectorPanel(title: title) {
            content
        }
    }
}

private struct InspectorWidthSwitch<Regular: View, Compact: View>: View {
    var regularMinWidth: CGFloat = 320
    @ViewBuilder var regular: () -> Regular
    @ViewBuilder var compact: () -> Compact

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= regularMinWidth {
                    regular()
                } else {
                    compact()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 28)
    }
}

struct EvidenceReviewPanel: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow
    @State private var decision: EvidenceDecision = .pending
    @State private var severity: RiskLevel = .none
    @State private var note = ""

    var body: some View {
        InspectorSection(title: appState.t("reports.review")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        reviewLabel(appState.t("review.quick"))
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { quickReviewButtons }
                            VStack(alignment: .leading, spacing: 8) { quickReviewButtons }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        reviewLabel(appState.t("review.decision"))
                        Picker(appState.t("review.decision"), selection: $decision) {
                            ForEach(EvidenceDecision.allCases) { option in
                                Text(appState.title(for: option)).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        reviewLabel(appState.t("review.severity"))
                        InspectorWidthSwitch(regularMinWidth: 330) {
                            Picker(appState.t("review.severity"), selection: $severity) {
                                ForEach(RiskLevel.allCases) { option in
                                    Text(appState.title(for: option)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .labelsHidden()

                            .frame(maxWidth: .infinity)
                        } compact: {
                            Picker(appState.t("review.severity"), selection: $severity) {
                                ForEach(RiskLevel.allCases) { option in
                                    Text(appState.title(for: option)).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                TextEditor(text: $note)
                    .font(AppTypography.body)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72, idealHeight: 92, maxHeight: 120)

                Button {
                    Task {
                        await appState.saveReview(
                            for: row,
                            decision: decision,
                            severity: severity == .none ? nil : severity,
                            note: note
                        )
                    }
                } label: {
                    Label(appState.t("review.save"), systemImage: "square.and.arrow.down")
                }
            }
        }
        .onAppear { syncFromSnapshot(reviewSnapshot) }
        .onChange(of: reviewSnapshot) { _, snapshot in syncFromSnapshot(snapshot) }
    }

    private var reviewSnapshot: EvidenceReviewSnapshot {
        let review = appState.review(for: row)
        return EvidenceReviewSnapshot(
            rowID: row.id,
            reviewID: review?.id,
            decision: review?.decision ?? .pending,
            severity: review?.severity,
            fallbackSeverity: row.riskAssessment?.level,
            note: review?.reviewerNote ?? "",
            updatedAt: review?.updatedAt
        )
    }

    private func reviewLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
    }

    private var quickReviewButtons: some View {
        Group {
            Button {
                Task { await saveQuickReview(.confirmed) }
            } label: {
                Label(appState.t("review.confirm"), systemImage: "checkmark.seal")
            }
            Button {
                Task { await saveQuickReview(.falsePositive) }
            } label: {
                Label(appState.t("review.falsePositive"), systemImage: "xmark.seal")
            }
            Button {
                Task { await saveQuickReview(.whitelisted) }
            } label: {
                Label(appState.t("review.whitelist"), systemImage: "checkmark.shield")
            }
        }
    }

    private func saveQuickReview(_ decision: EvidenceDecision) async {
        let selectedSeverity = severity == .none ? nil : severity
        await appState.quickReview(row: row, decision: decision, severity: selectedSeverity, note: note)
    }

    private func syncFromSnapshot(_ snapshot: EvidenceReviewSnapshot) {
        decision = snapshot.decision
        severity = snapshot.severity ?? snapshot.fallbackSeverity ?? .none
        note = snapshot.note
    }
}

private struct EvidenceReviewSnapshot: Hashable {
    let rowID: UUID
    let reviewID: UUID?
    let decision: EvidenceDecision
    let severity: RiskLevel?
    let fallbackSeverity: RiskLevel?
    let note: String
    let updatedAt: Date?
}

struct EvidenceSemanticDetailView: View {
    let row: ReportTableRow

    var body: some View {
        switch row.evidenceType {
        case .text, .dedup:
            TextEvidenceComparisonView(row: row)
        case .code:
            CodeEvidenceComparisonView(row: row)
        case .metadata, .crossBatch, nil:
            AssistantEvidenceExplanationView(row: row)
        case .image:
            EmptyView()
        }
    }
}

struct TextEvidenceComparisonView: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow
    @State private var selectedHighlightIndex = 0
    @State private var highlights: [String] = []

    private var textAttachments: [ReportAttachment] {
        Array(row.attachments.filter { $0.imageBase64 == nil }.prefix(2))
    }

    var body: some View {
        let selectedHighlight = highlights[safe: selectedHighlightIndex]
        if textAttachments.isEmpty == false {
            InspectorSection(title: appState.t("reports.textViewer")) {
                EvidenceHighlightNavigator(
                    tokens: highlights,
                    selectedIndex: $selectedHighlightIndex,
                    title: appState.t("reports.sharedTokens")
                )

                VStack(alignment: .leading, spacing: 12) {
                    evidenceContextCards(
                        attachments: textAttachments,
                        fallback: row.evidencePreview,
                        style: .text,
                        highlights: highlights,
                        selectedHighlight: selectedHighlight
                    )
                }
            }
            .task(id: row.id) { await updateHighlights() }
            .onChange(of: highlights.count) { _, count in
                selectedHighlightIndex = min(selectedHighlightIndex, max(count - 1, 0))
            }
        }
    }

    private func updateHighlights() async {
        highlights = await EvidenceTextAnalysisCache.shared.sharedHighlights(
            in: textAttachments.map { $0.body },
            fallback: row.evidencePreview
        )
    }
}

struct CodeEvidenceComparisonView: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow
    @State private var selectedMode: CodeViewerMode = .original
    @State private var selectedHighlightIndex = 0
    @State private var highlights: [String] = []
    @State private var renderedAttachments: [ReportAttachment] = []
    @State private var renderedMode: CodeViewerMode?
    @State private var renderedRowID: UUID?

    private var codeAttachments: [ReportAttachment] {
        Array(row.attachments.filter { $0.imageBase64 == nil }.prefix(2))
    }

    var body: some View {
        let selectedHighlight = highlights[safe: selectedHighlightIndex]
        let attachmentsForMode = renderedMode == selectedMode && renderedRowID == row.id && renderedAttachments.isEmpty == false ? renderedAttachments : codeAttachments
        if codeAttachments.count == 2 {
            InspectorSection(title: appState.t("reports.codeViewer")) {
                ViewThatFits(in: .horizontal) {
                    Picker(appState.t("reports.codeView"), selection: $selectedMode) {
                        ForEach(CodeViewerMode.allCases) { mode in
                            Text(appState.t(mode.localizationKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()

                    Picker(appState.t("reports.codeView"), selection: $selectedMode) {
                        ForEach(CodeViewerMode.allCases) { mode in
                            Text(appState.t(mode.localizationKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CodeDiffSummaryView(rowID: row.id, left: codeAttachments[0].body, right: codeAttachments[1].body)
                CodeLineDiffView(rowID: row.id, left: codeAttachments[0].body, right: codeAttachments[1].body)
                EvidenceHighlightNavigator(tokens: highlights, selectedIndex: $selectedHighlightIndex, title: appState.t("reports.sharedHighlights"))

                VStack(alignment: .leading, spacing: 12) {
                    evidenceContextCards(
                        attachments: attachmentsForMode,
                        fallback: row.detailBody,
                        style: .code,
                        highlights: highlights,
                        selectedHighlight: selectedHighlight
                    )
                }
                Text(row.detailBody)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
            .task(id: row.id) { await updateHighlights() }
            .task(id: CodeRenderRequest(rowID: row.id, mode: selectedMode)) { await updateRenderedAttachments() }
            .onChange(of: highlights.count) { _, count in
                selectedHighlightIndex = min(selectedHighlightIndex, max(count - 1, 0))
            }
        }
    }

    private func updateHighlights() async {
        highlights = await EvidenceTextAnalysisCache.shared.sharedHighlights(
            in: codeAttachments.map { $0.body },
            fallback: row.detailBody
        )
    }

    private func updateRenderedAttachments() async {
        let mode = selectedMode
        let rowID = row.id
        let rendered = await CodeAttachmentRenderCache.shared.renderedAttachments(codeAttachments, mode: mode)
        guard Task.isCancelled == false, mode == selectedMode else {
            return
        }
        renderedMode = mode
        renderedRowID = rowID
        renderedAttachments = rendered
    }
}

private struct CodeRenderRequest: Hashable {
    let rowID: UUID
    let mode: CodeViewerMode
}

@ViewBuilder
private func evidenceContextCards(
    attachments: [ReportAttachment],
    fallback: String,
    style: EvidenceContextStyle,
    highlights: [String],
    selectedHighlight: String?
) -> some View {
    ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
        EvidenceContextCard(
            attachment: attachment,
            fallback: fallback,
            style: style,
            highlights: highlights,
            focusedHighlight: selectedHighlight
        )
    }
}

struct AssistantEvidenceExplanationView: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow
    @State private var phase: AssistantPhase = .idle
    @State private var cachedExplanation: String?

    var body: some View {
        InspectorSection(title: appState.t("reports.assistantExplanation")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        Task { await runAssistant() }
                    } label: {
                        Label(buttonTitle, systemImage: "sparkles")
                    }
                    .disabled(phase == .loading)

                    if phase == .loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .buttonStyle(.borderless)

                Text(displayedExplanation)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .onChange(of: row.id) { _, _ in
            phase = .idle
            cachedExplanation = nil
        }
    }

    private var buttonTitle: String {
        if cachedExplanation != nil {
            return appState.t("reports.regenerateExplanation")
        }
        return appState.t("reports.generateExplanation")
    }

    private var displayedExplanation: String {
        switch phase {
        case .idle:
            return cachedExplanation ?? AuditAssistantService().localExplanation(for: row, review: appState.review(for: row))
        case .loading:
            return cachedExplanation ?? appState.t("reports.generatingExplanation")
        case .loaded(let text):
            return text
        case .failed(let message):
            return message
        }
    }

    private func runAssistant() async {
        phase = .loading
        do {
            let text = try await AuditAssistantService().explanation(
                for: row,
                review: appState.review(for: row),
                configuration: appState.appSettings.auditAssistant ?? AuditAssistantConfiguration()
            )
            cachedExplanation = text
            phase = .loaded(text)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private enum AssistantPhase: Equatable {
        case idle
        case loading
        case loaded(String)
        case failed(String)

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }
}

struct ImageEvidenceDetailView: View {
    @Environment(AppState.self) private var appState
    let attachments: [ReportAttachment]
    let showsPreviews: Bool
    @State private var selectedPairIndex = 0
    @State private var zoom = 1.0

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if imagePairs.isEmpty {
                attachmentGrid(attachments)
            } else {
                imageComparisonToolbar

                VStack(alignment: .leading, spacing: 12) {
                    imageComparisonCards
                }

                let remaining = attachments.filter { $0.imageBase64 == nil }
                if remaining.isEmpty == false {
                    attachmentGrid(remaining)
                }
            }
        }
        .onChange(of: imagePairs.count) { _, count in
            selectedPairIndex = min(selectedPairIndex, max(count - 1, 0))
        }
    }

    private var imageComparisonCards: some View {
        ForEach(Array(currentPair.enumerated()), id: \.offset) { index, attachment in
            ImageComparisonCard(
                label: index == 0 ? "A" : "B",
                attachment: attachment,
                showsPreview: showsPreviews,
                zoom: zoom
            )
        }
    }

    private var imagePairs: [[ReportAttachment]] {
        let images = attachments.filter { $0.imageBase64 != nil }
        return stride(from: 0, to: images.count, by: 2).map { index in
            Array(images[index..<min(index + 2, images.count)])
        }
    }

    private var currentPair: [ReportAttachment] {
        imagePairs[safe: selectedPairIndex] ?? []
    }

    private var imageComparisonToolbar: some View {
        ViewThatFits(in: .horizontal) {
            imageComparisonToolbarContent
            VStack(alignment: .leading, spacing: 8) {
                Text(appState.t("reports.imageComparison"))
                    .font(AppTypography.tableHeader)
                    .foregroundStyle(.secondary)
                imagePairControls
                imageZoomControls
            }
        }
        .buttonStyle(.borderless)
    }

    private var imageComparisonToolbarContent: some View {
        HStack(spacing: 10) {
            Text(appState.t("reports.imageComparison"))
                .font(AppTypography.tableHeader)
                .foregroundStyle(.secondary)
            imagePairControls
            imageZoomControls
        }
    }

    private var imagePairControls: some View {
        HStack(spacing: 6) {
            if imagePairs.count > 1 {
                Button {
                    selectedPairIndex = max(selectedPairIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(selectedPairIndex == 0)
                .help(appState.t("reports.previousImagePair"))
                .accessibilityLabel(Text(appState.t("reports.previousImagePair")))

                Text("\(selectedPairIndex + 1) / \(imagePairs.count)")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)

                Button {
                    selectedPairIndex = min(selectedPairIndex + 1, imagePairs.count - 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selectedPairIndex >= imagePairs.count - 1)
                .help(appState.t("reports.nextImagePair"))
                .accessibilityLabel(Text(appState.t("reports.nextImagePair")))
            }
        }
    }

    private var imageZoomControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $zoom, in: 0.5...3.0, step: 0.1)
                .frame(width: 72)
                .accessibilityLabel(Text(appState.t("reports.zoomLevel")))
                .accessibilityValue(Text("\(Int(zoom * 100))%"))
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func attachmentGrid(_ values: [ReportAttachment]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, attachment in
                AttachmentSummaryCard(
                    attachment: attachment,
                    showsPreview: showsPreviews
                )
            }
        }
    }
}

private enum EvidenceContextStyle {
    case text
    case code
}

private struct EvidenceContextCard: View {
    @Environment(AppState.self) private var appState
    let attachment: ReportAttachment
    let fallback: String
    let style: EvidenceContextStyle
    let highlights: [String]
    let focusedHighlight: String?

    private var content: String {
        let trimmed = attachment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : attachment.body
    }

    private var displayedContent: String {
        String(content.prefix(6_000))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(attachment.title)
                        .font(AppTypography.rowPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(metricText)
                        .font(AppTypography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Label(attachment.sourceReferenceText, systemImage: "link")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let filePath = attachment.sourceReference?.filePath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
                    } label: {
                        Label(appState.t("reports.openSourceFile"), systemImage: "arrow.up.right.square")
                    }
                    .font(AppTypography.metadata)
                    .buttonStyle(.link)
                }
            }

            if style == .code {
                ScrollView([.horizontal, .vertical]) {
                    Text(EvidenceTextHighlighter.attributed(displayedContent, highlights: visibleHighlights))
                        .font(AppTypography.code)
                        .textSelection(.enabled)
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                }
                .frame(minHeight: 132, maxHeight: 240)
            } else {
                Text(EvidenceTextHighlighter.attributed(displayedContent, highlights: visibleHighlights))
                    .font(AppTypography.body)
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var metricText: String {
        let lineCount = max(displayedContent.components(separatedBy: .newlines).count, 1)
        let suffix = content.count > displayedContent.count ? "+" : ""
        return appState.tf("reports.evidenceContentMetric", lineCount, displayedContent.count, suffix)
    }

    private var visibleHighlights: [String] {
        if let focusedHighlight, focusedHighlight.isEmpty == false {
            return [focusedHighlight]
        }
        return highlights
    }
}

private struct EvidenceHighlightNavigator: View {
    @Environment(AppState.self) private var appState
    let tokens: [String]
    @Binding var selectedIndex: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    navigatorTitle
                    navigatorTokenSummary
                }
                VStack(alignment: .leading, spacing: 4) {
                    navigatorTitle
                    navigatorTokenSummary
                }
            }

            if tokens.isEmpty == false {
                HStack(spacing: 8) {
                    Button {
                        selectedIndex = max(selectedIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(selectedIndex == 0)
                    .help(appState.t("reports.previousSharedToken"))
                    .accessibilityLabel(Text(appState.t("reports.previousSharedToken")))

                    Text("\(selectedIndex + 1) / \(tokens.count)：\(tokens[safe: selectedIndex] ?? "")")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        selectedIndex = min(selectedIndex + 1, tokens.count - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(selectedIndex >= tokens.count - 1)
                    .help(appState.t("reports.nextSharedToken"))
                    .accessibilityLabel(Text(appState.t("reports.nextSharedToken")))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var navigatorTitle: some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
    }

    private var navigatorTokenSummary: some View {
        Group {
            if tokens.isEmpty {
                Text(appState.t("reports.sharedFragment.empty"))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.tertiary)
            } else {
                FlowTokenLine(tokens: tokens)
            }
        }
    }
}

private enum CodeViewerMode: String, CaseIterable, Identifiable {
    case original
    case normalized
    case structure

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .original: return "reports.codeView.original"
        case .normalized: return "reports.codeView.normalized"
        case .structure: return "reports.codeView.structure"
        }
    }

    func render(_ source: String) -> String {
        switch self {
        case .original:
            return source
        case .normalized:
            return EvidenceTokenAnalyzer.tokens(in: source).joined(separator: " ")
        case .structure:
            return EvidenceTokenAnalyzer.structureTokens(in: source).joined(separator: " ")
        }
    }
}

private struct CodeDiffSummaryView: View {
    @Environment(AppState.self) private var appState
    let rowID: UUID
    let left: String
    let right: String
    @State private var summary: CodeDiffSummary?

    var body: some View {
        Group {
            if let summary {
                let fragment = summary.fragment ?? appState.t("reports.sharedFragment.empty")

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Label(appState.tf("reports.diff.sharedCount", summary.shared), systemImage: "equal.square")
                            Label(appState.tf("reports.diff.leftOnlyCount", summary.leftOnly), systemImage: "arrow.left.square")
                            Label(appState.tf("reports.diff.rightOnlyCount", summary.rightOnly), systemImage: "arrow.right.square")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label(appState.tf("reports.diff.sharedCount", summary.shared), systemImage: "equal.square")
                            Label(appState.tf("reports.diff.leftOnlyCount", summary.leftOnly), systemImage: "arrow.left.square")
                            Label(appState.tf("reports.diff.rightOnlyCount", summary.rightOnly), systemImage: "arrow.right.square")
                        }
                    }
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)

                    Text(appState.tf("reports.diff.longestSharedFragment", fragment))
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
        }
        .task(id: rowID) {
            summary = await CodeDiffSummaryCache.shared.summary(left: left, right: right)
        }
    }
}

private struct CodeLineDiffView: View {
    @Environment(AppState.self) private var appState
    let rowID: UUID
    let left: String
    let right: String
    @State private var rows: [CodeLineDiffRow] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appState.t("reports.lineDiff"))
                .font(AppTypography.tableHeader)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                        GridRow {
                            diffHeader("L")
                            diffHeader(appState.t("reports.diff.left"))
                            diffHeader("R")
                            diffHeader(appState.t("reports.diff.right"))
                            diffHeader(appState.t("common.status"))
                        }

                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                lineNumber(row.leftLineNumber)
                                diffCell(row.leftText, change: row.change, side: .left)
                                lineNumber(row.rightLineNumber)
                                diffCell(row.rightText, change: row.change, side: .right)
                                Text(changeTitle(row.change))
                                    .font(AppTypography.metadata.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 120, maxHeight: 220)
            }
        }
        .task(id: rowID) {
            isLoading = true
            rows = await CodeDiffCache.shared.rows(left: left, right: right)
            isLoading = false
        }
    }

    private enum Side {
        case left
        case right
    }

    private func diffHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.tableHeader)
            .foregroundStyle(.secondary)
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 32, alignment: .trailing)
    }

    private func diffCell(_ value: String, change: CodeLineDiffRow.Change, side: Side) -> some View {
        Text(value.isEmpty ? " " : value)
            .font(AppTypography.smallCode)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(minWidth: 240, alignment: .leading)
    }

    private func changeTitle(_ change: CodeLineDiffRow.Change) -> String {
        switch change {
        case .unchanged: return appState.t("reports.diff.change.unchanged")
        case .inserted: return appState.t("reports.diff.change.inserted")
        case .deleted: return appState.t("reports.diff.change.deleted")
        case .modified: return appState.t("reports.diff.change.modified")
        }
    }

}

private struct FlowTokenLine: View {
    let tokens: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(tokens.prefix(8), id: \.self) { token in
                    Text(token)
                        .font(AppTypography.badge)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AttachmentSummaryCard: View {
    let attachment: ReportAttachment
    let showsPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AttachmentHeader(attachment: attachment)

            if showsPreview, let imageBase64 = attachment.imageBase64 {
                EvidenceAsyncImage(
                    base64: imageBase64,
                    maxPixelSize: 640,
                    identity: attachment.imageLoadIdentity
                ) { image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200)
                }
            }

            Text(attachment.body)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ImageComparisonCard: View {
    let label: String
    let attachment: ReportAttachment
    let showsPreview: Bool
    let zoom: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label)
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)

                AttachmentHeader(attachment: attachment)
            }

            if showsPreview, let imageBase64 = attachment.imageBase64 {
                EvidenceAsyncImage(
                    base64: imageBase64,
                    maxPixelSize: 1_200,
                    identity: attachment.imageLoadIdentity
                ) { image in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: displaySize(for: image).width, height: displaySize(for: image).height)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                }
            }

            Text(attachment.body)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func displaySize(for image: NSImage) -> CGSize {
        let baseWidth = min(max(image.size.width, 180), 340)
        let ratio = image.size.height / max(image.size.width, 1)
        let baseHeight = min(max(baseWidth * ratio, 150), 260)
        return CGSize(width: baseWidth * CGFloat(zoom), height: baseHeight * CGFloat(zoom))
    }
}

private struct EvidenceAsyncImage<Content: View>: View {
    let base64: String
    let maxPixelSize: Int
    let identity: String
    @ViewBuilder var content: (NSImage) -> Content
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(image)
            } else if failed {
                EmptyView()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .task(id: "\(identity)|\(maxPixelSize)") {
            failed = false
            image = nil
            if let decoded = await EvidenceImageCache.shared.image(for: base64, maxPixelSize: maxPixelSize) {
                guard Task.isCancelled == false else { return }
                image = decoded.image
            } else {
                guard Task.isCancelled == false else { return }
                failed = true
            }
        }
    }
}

private struct AttachmentHeader: View {
    let attachment: ReportAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.title)
                .font(AppTypography.rowPrimary)
                .lineLimit(1)
            Label(attachment.sourceReferenceText, systemImage: "link")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum EvidenceTokenAnalyzer {
    static func sharedHighlights(in values: [String], fallback: String) -> [String] {
        let texts = values.map { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = trimmed.isEmpty ? fallback : value
            return String(source.prefix(8_000))
        }
        guard texts.isEmpty == false else { return [] }

        var candidates: [String] = []
        if texts.count >= 2, let fragment = bestSharedFragment(left: texts[0], right: texts[1]) {
            candidates.append(fragment)
        }

        let tokenSets = texts.map { Set(tokens(in: $0)) }
        if let first = tokenSets.first {
            let shared = tokenSets.dropFirst().reduce(first) { partial, next in
                partial.intersection(next)
            }
            candidates.append(contentsOf: shared.sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs < rhs }
                return lhs.count > rhs.count
            })
        }

        return unique(candidates)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
            .prefix(12)
            .map { String($0.prefix(48)) }
    }

    static func tokens(in text: String) -> [String] {
        text.lowercased().split { character in
            !(character.isLetter || character.isNumber || character == "_")
        }
        .map(String.init)
        .filter { $0.count >= 3 && $0.count <= 80 }
    }

    static func structureTokens(in text: String) -> [String] {
        text.split(separator: "\n").flatMap { line -> [String] in
            var tokens: [String] = []
            if line.contains("func ") || line.contains("def ") || line.contains("function ") {
                tokens.append("function")
            }
            if line.contains("if ") || line.contains("if(") {
                tokens.append("branch")
            }
            if line.contains("for ") || line.contains("while ") || line.contains("for(") || line.contains("while(") {
                tokens.append("loop")
            }
            if line.contains("return") {
                tokens.append("return")
            }
            if line.contains("try ") || line.contains("catch") {
                tokens.append("error")
            }
            return tokens.isEmpty ? ["stmt"] : tokens
        }
    }

    static func bestSharedFragment(left: String, right: String) -> String? {
        let leftChars = Array(left.prefix(800))
        let rightChars = Array(right.prefix(800))
        guard leftChars.isEmpty == false, rightChars.isEmpty == false else { return nil }

        var previous = Array(repeating: 0, count: rightChars.count + 1)
        var bestLength = 0
        var bestLeftEnd = 0

        for leftIndex in 1...leftChars.count {
            var current = Array(repeating: 0, count: rightChars.count + 1)
            for rightIndex in 1...rightChars.count {
                if leftChars[leftIndex - 1] == rightChars[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1] + 1
                    if current[rightIndex] > bestLength {
                        bestLength = current[rightIndex]
                        bestLeftEnd = leftIndex
                    }
                }
            }
            previous = current
        }

        guard bestLength >= 8 else { return nil }
        let lower = max(bestLeftEnd - bestLength, 0)
        let fragment = String(leftChars[lower..<bestLeftEnd])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fragment.isEmpty ? nil : fragment
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized.lowercased()
            if normalized.isEmpty == false, seen.insert(key).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

private extension ReportAttachment {
    var imageLoadIdentity: String {
        [
            title,
            subtitle,
            sourceReferenceText,
            imageBase64.map(stableContentDigest) ?? "",
        ].joined(separator: "|")
    }

    func transformedBody(_ body: String) -> ReportAttachment {
        ReportAttachment(
            title: title,
            subtitle: subtitle,
            body: body,
            imageBase64: imageBase64,
            sourceReference: sourceReference
        )
    }
}

private enum EvidenceTextHighlighter {
    static func attributed(_ text: String, highlights: [String]) -> AttributedString {
        var result = AttributedString(text)
        for highlight in highlights where highlight.isEmpty == false {
            var searchStart = result.startIndex
            while searchStart != result.endIndex,
                  let range = result[searchStart..<result.endIndex].range(
                    of: highlight,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  ) {
                result[range].backgroundColor = Color(nsColor: .selectedTextBackgroundColor)
                result[range].foregroundColor = Color.primary
                searchStart = range.upperBound
            }
        }
        return result
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension ReportTableRow {
    var evidencePreview: String {
        columns[safe: 3] ?? detailBody
    }
}

struct ReportBadgeView: View {
    let badge: ReportBadge

    var body: some View {
        Text(badge.title)
            .font(AppTypography.badge)
            .foregroundStyle(.secondary)
    }
}

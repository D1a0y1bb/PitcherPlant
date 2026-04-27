import SwiftUI

struct ReportEvidenceInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let row = appState.selectedReportRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Text(row.detailTitle)
                                .font(.title2.weight(.semibold))
                                .lineLimit(3)
                            Spacer()
                        }

                        if !row.badges.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(row.badges, id: \.title) { badge in
                                    ReportBadgeView(badge: badge)
                                }
                            }
                        }
                    }

                    EvidenceReviewPanel(row: row)

                    InspectorSection(title: appState.t("reports.evidenceDetails")) {
                        Text(row.detailBody)
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
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else if let section = appState.selectedReportSectionModel {
            if section.table?.rows.isEmpty == false {
                ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
            } else if let report = appState.selectedReport {
                ReportQuickInspector(report: report)
            } else {
                ReportSectionSummaryInspector(section: section, report: appState.selectedReport)
            }
        } else {
            ContentUnavailableView {
                Label(appState.t("reports.noEvidenceSelection"), systemImage: "doc.text.magnifyingglass")
            } description: {
                Text(appState.t("reports.noEvidenceSelectionDescription"))
            }
        }
    }
}

struct ReportQuickInspector: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.t("reports.reportProperties"))
                        .font(.title3.weight(.semibold))
                    Text(report.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

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
                            .font(.caption)
                        }
                    }
                }

                InspectorSection(title: appState.t("common.path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.t("reports.reportFile"))
                            .font(.caption.weight(.semibold))
                        Text(report.sourcePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(appState.t("reports.scanDirectory"))
                            .font(.caption.weight(.semibold))
                        Text(report.scanDirectoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct ReportSectionSummaryInspector: View {
    @Environment(AppState.self) private var appState
    let section: ReportSection
    let report: AuditReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title, systemImage: section.kind.systemImage)
                        .font(.title3.weight(.semibold))
                    if let report {
                        Text(report.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                InspectorSection(title: appState.t("reports.sectionSummary")) {
                    Text(section.summary.isEmpty ? appState.t("reports.sectionNoStructuredEvidence") : section.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if section.callouts.isEmpty == false {
                    InspectorSection(title: appState.t("reports.callouts")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.callouts, id: \.self) { callout in
                                Label(callout, systemImage: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let table = section.table {
                    InspectorSection(title: appState.t("reports.evidenceCount")) {
                        Text("\(table.rows.count) \(appState.t("reports.structuredRecords"))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Divider()
        }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        Task { await appState.quickReviewSelectedEvidence(.confirmed) }
                    } label: {
                        Label(appState.t("review.confirm"), systemImage: "checkmark.seal")
                    }
                    Button {
                        Task { await appState.quickReviewSelectedEvidence(.falsePositive) }
                    } label: {
                        Label(appState.t("review.falsePositive"), systemImage: "xmark.seal")
                    }
                    Button {
                        Task { await appState.quickReviewSelectedEvidence(.whitelisted) }
                    } label: {
                        Label(appState.t("review.whitelist"), systemImage: "checkmark.shield")
                    }
                }
                .buttonStyle(.borderless)

                Picker(appState.t("review.decision"), selection: $decision) {
                    ForEach(EvidenceDecision.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker(appState.t("review.severity"), selection: $severity) {
                    ForEach(RiskLevel.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                TextEditor(text: $note)
                    .font(.caption)
                    .frame(minHeight: 72)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.35)))

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
        .onAppear(perform: syncFromState)
        .onChange(of: row.id) { _, _ in syncFromState() }
    }

    private func syncFromState() {
        let review = appState.review(for: row)
        decision = review?.decision ?? .pending
        severity = review?.severity ?? row.riskAssessment?.level ?? .none
        note = review?.reviewerNote ?? ""
    }
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

    var body: some View {
        let textAttachments = Array(row.attachments.filter { $0.imageBase64 == nil }.prefix(2))
        if textAttachments.count == 2 {
            InspectorSection(title: appState.t("reports.textViewer")) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(textAttachments.enumerated()), id: \.offset) { _, attachment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(attachment.title)
                                .font(.caption.weight(.semibold))
                            Text(attachment.body.isEmpty ? row.evidencePreview : attachment.body)
                                .font(.system(.caption, design: .serif))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.25)))
                    }
                }
            }
        }
    }
}

struct CodeEvidenceComparisonView: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow

    var body: some View {
        let codeAttachments = Array(row.attachments.filter { $0.imageBase64 == nil }.prefix(2))
        if codeAttachments.count == 2 {
            InspectorSection(title: appState.t("reports.codeViewer")) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(codeAttachments.enumerated()), id: \.offset) { _, attachment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(attachment.subtitle)
                                .font(.caption.weight(.semibold))
                            ScrollView(.horizontal) {
                                Text(attachment.body)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.25)))
                    }
                }
                Text(row.detailBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct AssistantEvidenceExplanationView: View {
    @Environment(AppState.self) private var appState
    let row: ReportTableRow

    var body: some View {
        InspectorSection(title: appState.t("reports.assistantExplanation")) {
            Text(AuditAssistantService().localExplanation(for: row, review: appState.review(for: row)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct ImageEvidenceDetailView: View {
    let attachments: [ReportAttachment]
    let showsPreviews: Bool

    private let columns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.title)
                            .font(.subheadline.weight(.semibold))
                        Text(attachment.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showsPreviews, let image = attachment.imageBase64.flatMap(decodedImage) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Text(attachment.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator.opacity(0.25)))
            }
        }
    }

    private func decodedImage(_ value: String) -> NSImage? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
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
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch badge.tone {
        case .neutral: return Color(nsColor: .separatorColor).opacity(0.16)
        case .accent: return Color.blue.opacity(0.12)
        case .warning: return Color.orange.opacity(0.14)
        case .danger: return Color.red.opacity(0.14)
        case .success: return Color.green.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch badge.tone {
        case .neutral: return .secondary
        case .accent: return .blue
        case .warning: return .orange
        case .danger: return .red
        case .success: return .green
        }
    }
}

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
        let highlights = EvidenceTokenAnalyzer.sharedHighlights(in: textAttachments.map { $0.body }, fallback: row.evidencePreview)
        if textAttachments.isEmpty == false {
            InspectorSection(title: appState.t("reports.textViewer")) {
                EvidenceSharedTokenStrip(tokens: highlights, title: "共享 token")

                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(textAttachments.enumerated()), id: \.offset) { _, attachment in
                        EvidenceContextCard(
                            attachment: attachment,
                            fallback: row.evidencePreview,
                            style: .text,
                            highlights: highlights
                        )
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
        let highlights = EvidenceTokenAnalyzer.sharedHighlights(in: codeAttachments.map { $0.body }, fallback: row.detailBody)
        if codeAttachments.count == 2 {
            InspectorSection(title: appState.t("reports.codeViewer")) {
                EvidenceSharedTokenStrip(tokens: highlights, title: "共享标记")

                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(codeAttachments.enumerated()), id: \.offset) { _, attachment in
                        EvidenceContextCard(
                            attachment: attachment,
                            fallback: row.detailBody,
                            style: .code,
                            highlights: highlights
                        )
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
    @State private var selectedPairIndex = 0
    @State private var zoom = 1.0

    private let columns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if imagePairs.isEmpty {
                attachmentGrid(attachments)
            } else {
                imageComparisonToolbar

                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(currentPair.enumerated()), id: \.offset) { index, attachment in
                        ImageComparisonCard(
                            label: index == 0 ? "A" : "B",
                            attachment: attachment,
                            showsPreview: showsPreviews,
                            zoom: zoom,
                            decodedImage: decodedImage
                        )
                    }
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
        HStack(spacing: 10) {
            Text("图片 A/B 对比")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if imagePairs.count > 1 {
                Button {
                    selectedPairIndex = max(selectedPairIndex - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(selectedPairIndex == 0)

                Text("\(selectedPairIndex + 1) / \(imagePairs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    selectedPairIndex = min(selectedPairIndex + 1, imagePairs.count - 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selectedPairIndex >= imagePairs.count - 1)
            }

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: $zoom, in: 0.5...3.0, step: 0.1)
                .frame(width: 120)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .buttonStyle(.borderless)
    }

    private func attachmentGrid(_ values: [ReportAttachment]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, attachment in
                AttachmentSummaryCard(
                    attachment: attachment,
                    showsPreview: showsPreviews,
                    decodedImage: decodedImage
                )
            }
        }
    }

    private func decodedImage(_ value: String) -> NSImage? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return NSImage(data: data)
    }
}

private enum EvidenceContextStyle {
    case text
    case code
}

private struct EvidenceContextCard: View {
    let attachment: ReportAttachment
    let fallback: String
    let style: EvidenceContextStyle
    let highlights: [String]

    private var content: String {
        let trimmed = attachment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : attachment.body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(attachment.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(metricText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Label(attachment.sourceReferenceText, systemImage: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if style == .code {
                ScrollView([.horizontal, .vertical]) {
                    Text(EvidenceTextHighlighter.attributed(content, highlights: highlights))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                }
                .frame(minHeight: 132, maxHeight: 240)
            } else {
                Text(EvidenceTextHighlighter.attributed(content, highlights: highlights))
                    .font(.system(.caption, design: .serif))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.25)))
    }

    private var metricText: String {
        let lineCount = max(content.components(separatedBy: .newlines).count, 1)
        return "\(lineCount) 行 · \(content.count) 字"
    }
}

private struct EvidenceSharedTokenStrip: View {
    let tokens: [String]
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if tokens.isEmpty {
                Text("暂无稳定共享片段")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowTokenLine(tokens: tokens)
            }
        }
    }
}

private struct FlowTokenLine: View {
    let tokens: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tokens.prefix(8), id: \.self) { token in
                Text(token)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.11), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct AttachmentSummaryCard: View {
    let attachment: ReportAttachment
    let showsPreview: Bool
    let decodedImage: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AttachmentHeader(attachment: attachment)

            if showsPreview, let image = attachment.imageBase64.flatMap(decodedImage) {
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

private struct ImageComparisonCard: View {
    let label: String
    let attachment: ReportAttachment
    let showsPreview: Bool
    let zoom: Double
    let decodedImage: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor, in: Circle())

                AttachmentHeader(attachment: attachment)
            }

            if showsPreview, let image = attachment.imageBase64.flatMap(decodedImage) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize(for: image).width, height: displaySize(for: image).height)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(attachment.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator.opacity(0.25)))
    }

    private func displaySize(for image: NSImage) -> CGSize {
        let baseWidth = min(max(image.size.width, 180), 340)
        let ratio = image.size.height / max(image.size.width, 1)
        let baseHeight = min(max(baseWidth * ratio, 150), 260)
        return CGSize(width: baseWidth * CGFloat(zoom), height: baseHeight * CGFloat(zoom))
    }
}

private struct AttachmentHeader: View {
    let attachment: ReportAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Label(attachment.sourceReferenceText, systemImage: "link")
                .font(.caption)
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
            return trimmed.isEmpty ? fallback : value
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

    private static func tokens(in text: String) -> [String] {
        text.lowercased().split { character in
            !(character.isLetter || character.isNumber || character == "_")
        }
        .map(String.init)
        .filter { $0.count >= 3 && $0.count <= 80 }
    }

    private static func bestSharedFragment(left: String, right: String) -> String? {
        let leftChars = Array(left.prefix(1_600))
        let rightChars = Array(right.prefix(1_600))
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
                result[range].backgroundColor = Color.yellow.opacity(0.28)
                result[range].foregroundColor = Color.primary
                searchStart = range.upperBound
            }
        }
        return result
    }
}

private extension ReportAttachment {
    var sourceReferenceText: String {
        if let reflected = reflectedSourceReference {
            return reflected
        }
        if subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return subtitle
        }
        return title
    }

    private var reflectedSourceReference: String? {
        let labels = ["sourceReference", "source", "sourcePath", "location"]
        for child in Mirror(reflecting: self).children {
            guard let label = child.label, labels.contains(label),
                  let unwrapped = unwrapOptional(child.value) else {
                continue
            }
            let text = String(describing: unwrapped).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                return text
            }
        }
        return nil
    }

    private func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        return mirror.children.first?.value
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

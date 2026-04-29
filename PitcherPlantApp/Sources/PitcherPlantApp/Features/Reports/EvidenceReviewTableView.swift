import SwiftUI

struct EvidenceReviewTableView: View {
    @Environment(AppState.self) private var appState
    let rows: [EvidenceReviewTableRow]
    @Binding var selection: Set<UUID>
    var onSelectionChange: (EvidenceReviewTableRow?) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("风险") { row in
                Label(row.riskLevel.title, systemImage: riskImage(for: row.riskLevel))
                    .foregroundStyle(riskStyle(for: row.riskLevel))
                    .accessibilityLabel("风险 \(row.riskLevel.title)，分数 \(row.scoreText)")
            }
            .width(86)

            TableColumn("类型") { row in
                Label(row.evidenceType.title, systemImage: row.evidenceType.sectionKind.systemImage)
                    .foregroundStyle(.secondary)
            }
            .width(90)

            TableColumn("对象 A") { row in
                Button {
                    select(row, opensInspector: true)
                } label: {
                    Text(row.leftObject)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("打开证据详情")
            }
            .width(min: 160, ideal: 220)

            TableColumn("对象 B") { row in
                Text(row.rightObject)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 150, ideal: 210)

            TableColumn("题目 / 章节") { row in
                Text(row.challengeText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 120, ideal: 160)

            TableColumn("分数") { row in
                Text(row.scoreText)
                    .font(AppTypography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("分数 \(row.scoreText)")
            }
            .width(78)

            TableColumn("命中规则") { row in
                Text(row.ruleText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 180, ideal: 260)

            TableColumn("复核") { row in
                Text(row.reviewDecision.title)
                    .foregroundStyle(row.reviewDecision.badgeTone.semanticStyle)
                    .accessibilityLabel("复核状态 \(row.reviewDecision.title)")
            }
            .width(92)

            TableColumn("白名单") { row in
                Text(row.whitelistStatusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(118)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            Button("确认违规") {
                Task { await apply(.confirmed, selectedIDs: selectedIDs) }
            }
            Button("标记误报") {
                Task { await apply(.falsePositive, selectedIDs: selectedIDs) }
            }
            Button("忽略证据") {
                Task { await apply(.ignored, selectedIDs: selectedIDs) }
            }
            Button("加入白名单") {
                Task { await apply(.whitelisted, selectedIDs: selectedIDs) }
            }
        } primaryAction: { selectedIDs in
            if let selectedID = selectedIDs.first,
               let row = rows.first(where: { $0.id == selectedID }) {
                select(row, opensInspector: true)
            }
        }
        .onChange(of: selection) { _, selected in
            guard let selectedID = selected.first,
                  let row = rows.first(where: { $0.id == selectedID }) else {
                onSelectionChange(nil)
                return
            }
            onSelectionChange(row)
        }
        .frame(minHeight: AppLayout.reportListMinHeight, maxHeight: .infinity)
    }

    private func select(_ row: EvidenceReviewTableRow, opensInspector: Bool) {
        selection = [row.id]
        onSelectionChange(row)
        if opensInspector {
            appState.requestInspector()
        }
    }

    private func apply(_ decision: EvidenceDecision, selectedIDs: Set<UUID>) async {
        let targets = rows
            .filter { selectedIDs.contains($0.id) }
            .map(\.target)
        await appState.applyReviewDecision(to: targets, decision: decision, severity: nil, note: "")
    }

    private func riskImage(for risk: RiskLevel) -> String {
        switch risk {
        case .none: return "circle"
        case .low: return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }

    private func riskStyle(for risk: RiskLevel) -> AnyShapeStyle {
        switch risk {
        case .none: return AnyShapeStyle(.secondary)
        case .low: return AnyShapeStyle(.blue)
        case .medium: return AnyShapeStyle(.orange)
        case .high: return AnyShapeStyle(.red)
        }
    }
}

private extension ReportBadge.Tone {
    var semanticStyle: AnyShapeStyle {
        switch self {
        case .neutral: return AnyShapeStyle(.secondary)
        case .accent: return AnyShapeStyle(.blue)
        case .warning: return AnyShapeStyle(.orange)
        case .danger: return AnyShapeStyle(.red)
        case .success: return AnyShapeStyle(.green)
        }
    }
}

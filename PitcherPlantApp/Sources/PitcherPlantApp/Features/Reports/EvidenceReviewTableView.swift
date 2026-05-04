import SwiftUI

struct EvidenceReviewTableView: View {
    @Environment(AppState.self) private var appState
    let rows: [EvidenceReviewTableRow]
    @Binding var selection: Set<UUID>
    var onSelectionChange: (EvidenceReviewTableRow?) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn(appState.t("evidence.table.risk")) { row in
                Label(appState.title(for: row.riskLevel), systemImage: riskImage(for: row.riskLevel))
                    .foregroundStyle(riskStyle(for: row.riskLevel))
                    .accessibilityLabel(Text(appState.tf("evidence.table.accessibility.riskScore", appState.title(for: row.riskLevel), row.scoreText)))
            }
            .width(86)

            TableColumn(appState.t("evidence.table.type")) { row in
                Label(appState.title(for: row.evidenceType), systemImage: row.evidenceType.sectionKind.systemImage)
                    .foregroundStyle(.secondary)
            }
            .width(90)

            TableColumn(appState.t("reports.objectA")) { row in
                Button {
                    select(row, opensInspector: true)
                } label: {
                    Text(row.leftObject)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(appState.t("evidence.table.openDetails"))
            }
            .width(min: 160, ideal: 220)

            TableColumn(appState.t("reports.objectB")) { row in
                Text(row.rightObject)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 150, ideal: 210)

            TableColumn(appState.t("evidence.table.challengeSection")) { row in
                Text(row.challengeText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 120, ideal: 160)

            TableColumn(appState.t("common.score")) { row in
                Text(row.scoreText)
                    .font(AppTypography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(appState.tf("evidence.table.accessibility.score", row.scoreText)))
            }
            .width(78)

            TableColumn(appState.t("evidence.table.rule")) { row in
                Text(row.ruleText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 180, ideal: 260)

            TableColumn(appState.t("reports.review")) { row in
                Text(appState.title(for: row.reviewDecision))
                    .foregroundStyle(row.reviewDecision.badgeTone.semanticStyle)
                    .accessibilityLabel(Text(appState.tf("evidence.table.accessibility.reviewStatus", appState.title(for: row.reviewDecision))))
            }
            .width(92)

            TableColumn(appState.t("sidebar.whitelist")) { row in
                Text(appState.title(for: row.whitelistStatus ?? .clear))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(118)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            Button(appState.t("review.confirm")) {
                Task { await apply(.confirmed, selectedIDs: selectedIDs) }
            }
            Button(appState.t("review.falsePositive")) {
                Task { await apply(.falsePositive, selectedIDs: selectedIDs) }
            }
            Button(appState.t("review.ignore")) {
                Task { await apply(.ignored, selectedIDs: selectedIDs) }
            }
            Button(appState.t("review.whitelist")) {
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

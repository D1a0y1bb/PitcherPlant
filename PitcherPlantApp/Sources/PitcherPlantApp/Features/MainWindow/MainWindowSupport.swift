import SwiftUI

struct EvidenceFocusedReportsView: View {
    @Environment(AppState.self) private var appState
    let kind: ReportSectionKind?
    @Binding var reportQuery: String

    var body: some View {
        ReportsInlineView(reportQuery: $reportQuery)
            .onAppear {
                focusEvidenceKind()
            }
            .onChange(of: kind) { _, _ in
                focusEvidenceKind()
            }
    }

    private func focusEvidenceKind() {
        guard let kind else {
            return
        }
        if appState.selectedReportID == nil {
            appState.selectLatestReport()
        }
        appState.selectReportSection(kind)
    }
}

struct MainSidebarView: View {
    @Binding var selection: MainSidebarItem
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection(
                    title: appState.t("sidebar.categories"),
                    items: [.workspace, .newAudit, .history, .reports]
                )

                sidebarSection(
                    title: appState.t("sidebar.evidenceCollections"),
                    items: [.allEvidence, .favoriteEvidence, .watchedEvidence]
                )

                sidebarSection(
                    title: appState.t("sidebar.evidenceTypes"),
                    items: [.textEvidence, .codeEvidence, .imageEvidence, .metadataEvidence, .dedupEvidence, .crossBatchEvidence]
                )

                sidebarSection(
                    title: appState.t("sidebar.libraries"),
                    items: [.fingerprints, .whitelist, .settings]
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, AppLayout.sidebarContentTopMargin)
            .padding(.bottom, AppLayout.sidebarContentBottomMargin)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarSection(title: String, items: [MainSidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.tableHeader)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    sidebarRow(item)
                }
            }
        }
    }

    private func sidebarRow(_ item: MainSidebarItem) -> some View {
        let isSelected = selection == item

        return Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(iconColor(for: item))
                Text(appState.title(for: item))
                    .font(AppTypography.rowPrimary.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconColor(for item: MainSidebarItem) -> Color {
        switch item {
        case .workspace: return .orange
        case .allEvidence: return .blue
        case .favoriteEvidence: return .yellow
        case .watchedEvidence: return .cyan
        case .newAudit: return .green
        case .history: return .orange
        case .reports: return .indigo
        case .textEvidence: return .mint
        case .codeEvidence: return .purple
        case .imageEvidence: return .teal
        case .metadataEvidence: return .cyan
        case .dedupEvidence: return .brown
        case .crossBatchEvidence: return .pink
        case .fingerprints: return .blue
        case .whitelist: return .green
        case .settings: return .orange
        }
    }

}

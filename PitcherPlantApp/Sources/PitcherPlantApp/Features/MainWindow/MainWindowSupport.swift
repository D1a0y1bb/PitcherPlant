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
        // Adapted from PortKiller's MIT-licensed SidebarView/FavoriteWatchButtons patterns.
        List(selection: $selection) {
            Section(appState.t("sidebar.categories")) {
                sidebarRow(.workspace)
                sidebarRow(.newAudit)
                sidebarRow(.history)
                sidebarRow(.reports)
            }

            Section(appState.t("sidebar.evidenceCollections")) {
                sidebarRow(.allEvidence)
                sidebarRow(.favoriteEvidence)
                sidebarRow(.watchedEvidence)
            }

            Section(appState.t("sidebar.evidenceTypes")) {
                sidebarRow(.textEvidence)
                sidebarRow(.codeEvidence)
                sidebarRow(.imageEvidence)
                sidebarRow(.metadataEvidence)
                sidebarRow(.dedupEvidence)
                sidebarRow(.crossBatchEvidence)
            }

            Section(appState.t("sidebar.libraries")) {
                sidebarRow(.fingerprints)
                sidebarRow(.whitelist)
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, AppLayout.sidebarContentTopMargin, for: .scrollContent)
        .contentMargins(.bottom, AppLayout.sidebarContentBottomMargin, for: .scrollContent)
    }

    private func sidebarRow(_ item: MainSidebarItem, title: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .frame(width: 18, alignment: .center)
                .foregroundStyle(iconColor(for: item))
            Text(title ?? appState.title(for: item))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.leading, 8)
        .tag(item)
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

import SwiftUI

struct ScrollEdgeLabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        AppPageShell(spacing: 16) {
            header
            Divider()
            ForEach(1...36, id: \.self) { index in
                labRow(index)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.t("scrollEdgeLab.title"))
                .font(.title2.bold())
            Text(appState.t("scrollEdgeLab.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func labRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(appState.tf("scrollEdgeLab.rowTitle", index))
                    .font(.headline)
            }
            Text(appState.t("scrollEdgeLab.rowBody"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

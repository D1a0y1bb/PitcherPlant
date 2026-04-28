import SwiftUI

struct NativePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppPageShell(spacing: 24) {
            content
        }
    }
}

struct NativePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.pageTitle)
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                actions
            }
        }
    }
}

struct NativeSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        AppSectionPanel(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct JobInspectorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        AppInspectorPanel(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct SearchHeader: View {
    @Environment(AppState.self) private var appState
    let title: String
    let count: Int
    @Binding var query: String
    let prompt: String

    var body: some View {
        AppToolbarBand {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                    Text("\(count) \(appState.t("common.countSuffix"))")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(prompt, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
        }
    }
}

struct DenseHeader: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(column)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: index == 0 ? .leading : .trailing)
                    .frame(width: index == 0 ? nil : (index == 1 ? 74 : index == 2 ? 54 : 128), alignment: .trailing)
            }
        }
        .font(AppTypography.tableHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppLayout.rowHorizontalPadding)
        .padding(.vertical, 8)
    }
}

struct SummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

struct SummaryStrip: View {
    let items: [SummaryItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(max(items.count, 1), 4)), spacing: 12) {
            ForEach(items) { item in
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.value)
                                .font(.title2.weight(.semibold))
                            Text(item.title)
                                .font(AppTypography.supporting)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .groupBoxStyle(.automatic)
            }
        }
    }
}

struct SettingsTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        AppControlRow(title: title) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsNumberRow<F: ParseableFormatStyle>: View where F.FormatInput == Double, F.FormatOutput == String {
    let title: String
    @Binding var value: Double
    let format: F

    var body: some View {
        AppControlRow(title: title, trailingWidth: 120) {
            TextField("", value: $value, format: format)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsIntegerRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        AppControlRow(title: title, trailingWidth: 120) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct StatusDot: View {
    let status: AuditJobStatus

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }

    private var systemImage: String {
        switch status {
        case .queued: return "clock"
        case .running: return "play.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct PlainBadgeLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.badge)
            .foregroundStyle(.secondary)
    }
}

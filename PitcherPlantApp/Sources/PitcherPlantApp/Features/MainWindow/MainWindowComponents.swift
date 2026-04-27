import SwiftUI

struct NativePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                    .font(.title2.weight(.semibold))
                Text(subtitle)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(Rectangle().stroke(.separator.opacity(0.25)))
        }
    }
}

struct JobInspectorSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\(count) \(appState.t("common.countSuffix"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(prompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
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
        HStack(spacing: 18) {
            ForEach(items) { item in
                Label {
                    Text("\(item.value) \(item.title)")
                } icon: {
                    Image(systemName: item.systemImage)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.subheadline)
    }
}

struct SettingsTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 96, alignment: .leading)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 8)
    }
}

struct SettingsNumberRow<F: ParseableFormatStyle>: View where F.FormatInput == Double, F.FormatOutput == String {
    let title: String
    @Binding var value: Double
    let format: F

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: format)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
        .padding(.vertical, 8)
    }
}

struct SettingsIntegerRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
        .padding(.vertical, 8)
    }
}

struct StatusDot: View {
    let status: AuditJobStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .queued: return .secondary.opacity(0.5)
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

struct PillLabel: View {
    let title: String
    var tint: Color = .secondary

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

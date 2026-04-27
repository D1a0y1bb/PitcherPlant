import SwiftUI

struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsTextControl(title: title, text: $text)
        }
    }
}

struct SettingsTextControl: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(AppTypography.smallCode)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: SettingsLayout.trailingWidth, alignment: .trailing)
    }
}

struct SettingsNumberFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let hint: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsNumberStepper(
                value: $value,
                range: 0...1,
                step: 0.05,
                hint: hint
            )
        }
    }
}

struct SettingsIntegerFieldRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let hint: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            SettingsIntegerStepper(
                value: $value,
                range: 0...64,
                step: 1,
                hint: hint
            )
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct SettingsPickerRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            content
        }
    }
}

struct SettingsButtonGroupRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                content
            }
            .buttonStyle(.bordered)
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle) {
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct SettingsMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let width: CGFloat
    let title: (Value) -> String
    var systemImage: ((Value) -> String)?

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    menuLabel(for: option)
                }
            }
        } label: {
            HStack(spacing: 7) {
                menuLabel(for: selection)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
            }
            .font(AppTypography.supporting.weight(.medium))
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    @ViewBuilder
    private func menuLabel(for option: Value) -> some View {
        if let systemImage {
            Label(title(option), systemImage: systemImage(option))
        } else {
            Text(title(option))
        }
    }
}

struct SettingsNumberStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let hint: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(hint, value: clampedBinding, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(AppTypography.code.weight(.medium))
                .frame(width: SettingsLayout.numberFieldWidth + 12)

            Stepper("", value: clampedBinding, in: range, step: step)
                .labelsHidden()
                .frame(width: SettingsLayout.stepperWidth - 46)

            Text(hint)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.hintWidth, alignment: .trailing)
        }
        .frame(width: SettingsLayout.thresholdControlWidth, alignment: .trailing)
    }

    private var clampedBinding: Binding<Double> {
        Binding(
            get: { clamped(value) },
            set: { value = clamped($0) }
        )
    }

    private func clamped(_ candidate: Double) -> Double {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

struct SettingsIntegerStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let hint: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(hint, value: clampedBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(AppTypography.code.weight(.medium))
                .frame(width: SettingsLayout.numberFieldWidth + 12)

            Stepper("", value: clampedBinding, in: range, step: step)
                .labelsHidden()
                .frame(width: SettingsLayout.stepperWidth - 46)

            Text(hint)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: SettingsLayout.hintWidth, alignment: .trailing)
        }
        .frame(width: SettingsLayout.thresholdControlWidth, alignment: .trailing)
    }

    private var clampedBinding: Binding<Int> {
        Binding(
            get: { clamped(value) },
            set: { value = clamped($0) }
        )
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

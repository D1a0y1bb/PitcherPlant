import SwiftUI

struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @Binding var text: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
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
            .frame(maxWidth: SettingsLayout.trailingWidth, alignment: .trailing)
            .accessibilityLabel(Text(title))
    }
}

struct SettingsNumberFieldRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0.05
    let hint: String
    var fractionLength = 2

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsNumberStepper(
                title: title,
                value: $value,
                range: range,
                step: step,
                hint: hint,
                fractionLength: fractionLength
            )
        }
    }
}

struct SettingsIntegerFieldRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...64
    var step: Int = 1
    let hint: String

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            SettingsIntegerStepper(
                title: title,
                value: $value,
                range: range,
                step: step,
                hint: hint
            )
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
    }
}

struct SettingsPickerRow<Content: View>: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
            content
        }
    }
}

struct SettingsButtonGroupRow<Content: View>: View {
    let title: String
    let subtitle: String
    var icon: SettingsRowIconStyle = .generic
    @ViewBuilder var content: Content

    var body: some View {
        SettingsControlRow(title: title, subtitle: subtitle, icon: icon) {
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
    var icon: SettingsRowIconStyle = .generic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContainer {
                HStack(alignment: .center, spacing: 16) {
                    SettingsRowIcon(style: icon)

                    SettingsRowText(title: title, subtitle: subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(Text(title))
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
            HStack(spacing: 8) {
                Text(title(selection))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    }
                    .accessibilityHidden(true)
            }
            .font(AppTypography.body.weight(.medium))
            .frame(width: width, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: .trailing)
        .accessibilityValue(Text(title(selection)))
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
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let hint: String
    var fractionLength = 2

    var body: some View {
        HStack(spacing: SettingsLayout.thresholdControlSpacing) {
            TextField(hint, value: clampedBinding, format: .number.precision(.fractionLength(fractionLength)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(AppTypography.code.weight(.medium))
                .frame(width: SettingsLayout.numberFieldWidth)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(formattedValue(clamped(value))))

            SettingsStepperButtons(
                increment: { value = clamped(clamped(value) + step) },
                decrement: { value = clamped(clamped(value) - step) },
                canIncrement: clamped(value) < range.upperBound,
                canDecrement: clamped(value) > range.lowerBound,
                accessibilityLabel: title
            )
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

    private func formattedValue(_ value: Double) -> String {
        if fractionLength == 0 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.\(fractionLength)f", value)
    }
}

struct SettingsIntegerStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let hint: String

    var body: some View {
        HStack(spacing: SettingsLayout.thresholdControlSpacing) {
            TextField(hint, value: clampedBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(AppTypography.code.weight(.medium))
                .frame(width: SettingsLayout.numberFieldWidth)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text("\(clamped(value))"))

            SettingsStepperButtons(
                increment: { value = clamped(clamped(value) + step) },
                decrement: { value = clamped(clamped(value) - step) },
                canIncrement: clamped(value) < range.upperBound,
                canDecrement: clamped(value) > range.lowerBound,
                accessibilityLabel: title
            )
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

private struct SettingsStepperButtons: View {
    let increment: () -> Void
    let decrement: () -> Void
    let canIncrement: Bool
    let canDecrement: Bool
    let accessibilityLabel: String

    var body: some View {
        VStack(spacing: 0) {
            stepButton(
                systemImage: "chevron.up",
                isEnabled: canIncrement,
                action: increment,
                accessibilitySuffix: "increase"
            )

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 5)

            stepButton(
                systemImage: "chevron.down",
                isEnabled: canDecrement,
                action: decrement,
                accessibilitySuffix: "decrease"
            )
        }
        .frame(width: SettingsLayout.stepperWidth, height: 32)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.075))
        }
    }

    private func stepButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
        accessibilitySuffix: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(width: SettingsLayout.stepperWidth, height: 15.75)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("\(accessibilityLabel) \(accessibilitySuffix)"))
    }
}

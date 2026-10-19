import SwiftUI

// Palette-drawn replacements for system controls whose iOS 26 look ignores the palette (night chrome experiment `ctl`,
// see `NightChrome`). Every replacement is used only at night on iOS 26; elsewhere the call sites draw the system
// control exactly as before. The bars (tab bar, back button, Done, search) are in `NightBars.swift`.

extension Text {
    /// A placeholder (the prompt of a text field) in the palette's dim text colour. The system draws placeholders in a
    /// neutral grey, which is not red (night chrome experiment `ph`).
    func placeholder(_ palette: Palette) -> Text {
        NightChrome.isActive("ph", night: palette.isNight) ? foregroundStyle(palette.tertiaryText) : self
    }
}

/// Puts the night switch in place of the system one for everything below it (night chrome experiment `ctl`). The system
/// switch of iOS 26 has a grey track when off and no visible thumb when on.
struct NightControlsModifier: ViewModifier {
    let isOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn {
            content.toggleStyle(NightToggleStyle())
        } else {
            content
        }
    }
}

/// A switch drawn in the palette: a capsule with a thumb that moves, the label on its leading side.
struct NightToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        NightToggleRow(configuration: configuration)
    }
}

private struct NightToggleRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                track
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private var track: some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? palette.surfaceRaised : palette.surface)
            Capsule()
                .strokeBorder(configuration.isOn ? palette.accent : palette.stroke, lineWidth: 1.5)
            Circle()
                .fill(configuration.isOn ? palette.accent : palette.tertiaryText)
                .frame(width: 25, height: 25)
                .padding(3)
        }
        .frame(width: 51, height: 31)
        .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        .accessibilityHidden(true)
    }
}

/// A segmented picker that is the system one by day and on iOS 25 and earlier, and a palette-drawn one at night on
/// iOS 26 (night chrome experiment `ctl`): the system one has a grey track and near-invisible unselected labels there.
struct ThemedSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Environment(\.palette) private var palette

    init(_ title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            HStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    segment(option)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.stroke, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.surfaceRaised : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A slider that is the system one by day and on iOS 25 and earlier, and a palette-drawn one at night on iOS 26 (night
/// chrome experiment `ctl`): the system slider draws grey tick dots for its steps there. Callers add `.accessibilityValue`.
struct ThemedSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @Environment(\.palette) private var palette

    var body: some View {
        if NightChrome.isActive("ctl", night: palette.isNight) {
            NightSlider(title: title, value: $value, range: range, step: step, palette: palette)
        } else {
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
        }
    }
}

private struct NightSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let palette: Palette

    private let thumb: CGFloat = 26

    private var span: Double { max(range.upperBound - range.lowerBound, Double.leastNonzeroMagnitude) }

    /// The value rounded to the nearest step and kept inside the range.
    private func snapped(_ raw: Double) -> Double {
        let steps = ((raw - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumb, 1)
            let fraction = CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.stroke)
                    .frame(height: 4)
                Capsule()
                    .fill(palette.accent)
                    .frame(width: thumb / 2 + travel * fraction, height: 4)
                Circle()
                    .fill(palette.accent)
                    .frame(width: thumb, height: thumb)
                    .offset(x: travel * fraction)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = min(max(Double((drag.location.x - thumb / 2) / travel), 0), 1)
                    value = snapped(range.lowerBound + position * span)
                }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(value + step)
            case .decrement: value = snapped(value - step)
            @unknown default: break
            }
        }
    }
}

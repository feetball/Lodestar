import SwiftUI

/// A themed form section: palette-coloured header and footer, rows drawn on the palette's surface colour.
struct SettingsSection<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .foregroundStyle(palette.secondaryText)
        } footer: {
            if let footer {
                Text(footer)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.stroke)
    }
}

/// Secondary explanatory text under a control.
struct SettingsCaption: View {
    @Environment(\.palette) private var palette
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A switch with an optional explanation underneath.
struct SettingsToggleRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            if let caption {
                SettingsCaption(caption)
            }
        }
    }
}

/// A slider with its title and current value on one line. VoiceOver reads the value text.
struct SettingsSliderRow: View {
    @Environment(\.palette) private var palette
    let title: String
    /// The value as the user should read it, e.g. "0.12 s".
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityHidden(true)
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .accessibilityValue(valueText)
        }
    }
}

/// One choice of a `SettingsMenuPicker`.
struct SettingsMenuOption<Value: Hashable>: Identifiable {
    let title: String
    let value: Value
    var id: Value { value }
}

/// A row that opens a menu to pick one value. The chosen value is drawn in the accent colour: a system `Picker`
/// shows it in a light grey, which does not belong in a night palette.
struct SettingsMenuPicker<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let title: String
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? AppFormat.missing
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 8)
                Text(selectedTitle)
                    .foregroundStyle(palette.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(palette.accent)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}

/// A labelled numeric text field. Valid input is applied while typing; invalid input is flagged and reverted when
/// editing ends. The decimal mark may be "." or ",".
struct SettingsNumberField: View {
    @Environment(\.palette) private var palette
    private let title: String
    private let prefix: String
    private let unit: String
    private let range: ClosedRange<Double>
    private let fractionDigits: Int
    private let placeholder: String
    private let isRequired: Bool
    @Binding private var value: Double?
    @State private var text: String
    @FocusState private var isFocused: Bool

    /// A field for a number that always has a value; clearing the field does not change it. `prefix` is shown
    /// before the number (e.g. "f/"), `unit` after it.
    init(title: String, prefix: String = "", unit: String = "", value: Binding<Double>, range: ClosedRange<Double>,
         fractionDigits: Int = 1) {
        let optional = Binding<Double?>(
            get: { value.wrappedValue },
            set: { newValue in
                if let newValue { value.wrappedValue = newValue }
            })
        self.init(title: title, prefix: prefix, unit: unit, binding: optional, isRequired: true, range: range,
                  fractionDigits: fractionDigits, placeholder: "")
    }

    /// A field for a number that may be unknown; clearing the field sets it to `nil`.
    init(title: String, prefix: String = "", unit: String = "", optionalValue: Binding<Double?>,
         range: ClosedRange<Double>, fractionDigits: Int = 1, placeholder: String = "Unknown") {
        self.init(title: title, prefix: prefix, unit: unit, binding: optionalValue, isRequired: false, range: range,
                  fractionDigits: fractionDigits, placeholder: placeholder)
    }

    private init(title: String, prefix: String, unit: String, binding: Binding<Double?>, isRequired: Bool,
                 range: ClosedRange<Double>, fractionDigits: Int, placeholder: String) {
        self.title = title
        self.prefix = prefix
        self.unit = unit
        self.range = range
        self.fractionDigits = fractionDigits
        self.placeholder = placeholder
        self.isRequired = isRequired
        _value = binding
        _text = State(initialValue: SettingsNumberText.text(for: binding.wrappedValue,
                                                            fractionDigits: fractionDigits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                if !prefix.isEmpty {
                    Text(prefix)
                        .foregroundStyle(palette.secondaryText)
                }
                TextField(title, text: $text, prompt: Text(placeholder).foregroundStyle(palette.tertiaryText))
                    .keyboardType(range.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .foregroundStyle(isInvalid ? palette.critical : palette.primaryText)
                    .frame(maxWidth: 120)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            if isInvalid {
                Text(rangeHint)
                    .font(.footnote)
                    .foregroundStyle(palette.critical)
            }
        }
        .onChange(of: text) { _, newText in
            applyTyped(newText)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = SettingsNumberText.text(for: value, fractionDigits: fractionDigits) }
        }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = SettingsNumberText.text(for: newValue, fractionDigits: fractionDigits) }
        }
    }

    private var rangeHint: String {
        let lower = SettingsNumberText.text(for: range.lowerBound, fractionDigits: fractionDigits)
        let upper = SettingsNumberText.text(for: range.upperBound, fractionDigits: fractionDigits)
        return "Enter a value from \(lower) to \(upper)."
    }

    /// Whether the text, as it stands, cannot be applied.
    private var isInvalid: Bool {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return isRequired }
        return SettingsNumberText.parse(text, in: range) == nil
    }

    private func applyTyped(_ newText: String) {
        guard isFocused else { return }
        if newText.trimmingCharacters(in: .whitespaces).isEmpty {
            if !isRequired { value = nil }
        } else if let parsed = SettingsNumberText.parse(newText, in: range), parsed != value {
            value = parsed
        }
    }
}

/// Applies the app palette and colour scheme to the root of a presented sheet. Sheets are presented outside the
/// window's overlay, so they set up the theme themselves.
struct SettingsSheetRoot<Content: View>: View {
    @Environment(AppModel.self) private var app
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .themedRoot(app.palette, redFilter: app.settings.redFilterOverlay)
            .presentationBackground(app.palette.background)
    }
}

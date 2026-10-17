import Foundation

/// Reading and writing the text of a numeric settings field.
enum SettingsNumberText {
    /// The longest text that is read as a number.
    private static let maximumLength = 16

    /// The number the text spells, or `nil` when it is not a finite number inside `range`. "." and "," both work as
    /// the decimal mark, and U+2212 as the minus sign.
    static func parse(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        guard normalized.count <= maximumLength, let number = Double(normalized), number.isFinite,
              range.contains(number) else { return nil }
        return number
    }

    /// The value as text with at most `fractionDigits` decimals and no trailing zeros, e.g. "2.8" or "24".
    /// Always uses "." as the decimal mark and no grouping, so the text can be edited and parsed back. Empty for
    /// `nil` and for numbers that are not finite.
    static func text(for value: Double?, fractionDigits: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

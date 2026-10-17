import Foundation

/// Locale-independent number formatting for the catalog's display strings.
enum CatalogFormat {
    /// The minus sign used in display text (U+2212), as in the formatting module.
    static let minus = "\u{2212}"

    /// A magnitude-style number with exactly one decimal, such as "3.4" or "−1.4".
    ///
    /// Values that round to zero print as "0.0" without a sign; non-finite values print as an em dash.
    static func oneDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "\u{2014}" }
        let tenths = Int((min(abs(value), 1e9) * 10).rounded())
        let sign = value < 0 && tenths != 0 ? minus : ""
        return "\(sign)\(tenths / 10).\(tenths % 10)"
    }

    /// A non-negative number rounded to one decimal, without a trailing ".0" ("12", "8.4").
    static func trimmedOneDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "\u{2014}" }
        let tenths = Int((min(abs(value), 1e9) * 10).rounded())
        return tenths % 10 == 0 ? String(tenths / 10) : "\(tenths / 10).\(tenths % 10)"
    }
}

/// The typography used when formatting angles, coordinates, durations and exposure times.
///
/// Every formatter in `AngleFormatter` takes a style and defaults to `.unicode`. Text produced in
/// the `.ascii` style contains only 7-bit characters and is still understood by the parsers in
/// `AngleFormatter`.
public enum TypographyStyle: Sendable, Hashable, CaseIterable {
    /// Typographic symbols: U+2212 minus sign, `°`, `′`, `″` and an em dash for missing values.
    case unicode

    /// Plain ASCII for logs, file names and exports: hyphen-minus, `d`, `'`, `"` and `--` for
    /// missing values.
    case ascii
}

extension TypographyStyle {
    /// The sign written in front of negative values.
    var minus: String {
        switch self {
        case .unicode: return "\u{2212}"
        case .ascii: return "-"
        }
    }

    /// The degree symbol.
    var degree: String {
        switch self {
        case .unicode: return "\u{00B0}"
        case .ascii: return "d"
        }
    }

    /// The arcminute symbol.
    var arcminute: String {
        switch self {
        case .unicode: return "\u{2032}"
        case .ascii: return "'"
        }
    }

    /// The arcsecond symbol.
    var arcsecond: String {
        switch self {
        case .unicode: return "\u{2033}"
        case .ascii: return "\""
        }
    }

    /// Text shown in place of a value that is missing, not finite or out of range.
    var placeholder: String {
        switch self {
        case .unicode: return "\u{2014}"
        case .ascii: return "--"
        }
    }
}

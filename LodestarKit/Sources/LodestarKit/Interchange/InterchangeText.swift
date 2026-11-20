import Foundation

/// Locale-independent text for the numbers and dates of the interchange formats, built from integers like
/// `NumberText` (no `String(format:)`, no date formatter), so Swift and Kotlin write the same characters.
enum InterchangeText {
    /// A finite number with at most `maximumDecimals` places and no trailing zeros ("-5.391", "12", "0.5"); "0" when it
    /// is not finite.
    static func decimal(_ value: Double, maximumDecimals: Int) -> String {
        guard value.isFinite, let magnitude = NumberText.trimmed(magnitude: abs(value), maxDecimals: maximumDecimals) else {
            return "0"
        }
        return value < 0 && magnitude != "0" ? "-" + magnitude : magnitude
    }

    /// A finite number with exactly `decimals` places ("-5.39100"); "0" when it is not finite or too large to render.
    static func fixed(_ value: Double, decimals: Int) -> String {
        guard let point = NumberText.fixedPoint(magnitude: value.isFinite ? abs(value) : 0, decimals: decimals) else {
            return "0"
        }
        return value.isFinite && value < 0 && !point.isZero ? "-" + point.text : point.text
    }

    /// `fixed` for an angle in [0, 360) such as a right ascension or a position angle: one that rounds up to 360
    /// (359.999996 with five places) is written as zero, so that the text still reads back inside the range.
    static func fixedAngle(_ degrees: Double, decimals: Int) -> String {
        let text = fixed(degrees, decimals: decimals)
        guard degrees >= 0, degrees < 360, text == fixed(360, decimals: decimals) else { return text }
        return fixed(0, decimals: decimals)
    }

    /// `a / b` rounded towards negative infinity, for a positive `b`.
    static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        return a % b != 0 && a < 0 ? quotient - 1 : quotient
    }

    /// The seconds since 1970-01-01T00:00:00Z of a date, rounded down; 0 for a date that is not representable.
    static func wholeSeconds(of date: Date) -> Int64 {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        guard seconds.isFinite, abs(seconds) < 1e15 else { return 0 }
        return Int64(seconds)
    }

    /// The proleptic Gregorian date of a day count since 1970-01-01 (Howard Hinnant's `civil_from_days`).
    static func civil(daysSinceEpoch: Int64) -> (year: Int64, month: Int, day: Int) {
        let shifted = daysSinceEpoch + 719_468
        let era = floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * monthIndex + 2) / 5 + 1)
        let month = Int(monthIndex < 10 ? monthIndex + 3 : monthIndex - 9)
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    /// "2026-11-18" for a day count since 1970-01-01.
    static func dateText(daysSinceEpoch: Int64) -> String {
        let date = civil(daysSinceEpoch: daysSinceEpoch)
        return "\(NumberText.padded(date.year, width: 4))-\(NumberText.padded(Int64(date.month), width: 2))-\(NumberText.padded(Int64(date.day), width: 2))"
    }

    /// "2026-11-18T22:15:00Z" for whole seconds since 1970-01-01T00:00:00Z (an `xsd:dateTime` in UTC).
    static func dateTimeText(epochSeconds: Int64) -> String {
        let days = floorDivide(epochSeconds, 86_400)
        let secondOfDay = epochSeconds - days * 86_400
        let hour = secondOfDay / 3_600
        let minute = secondOfDay % 3_600 / 60
        let second = secondOfDay % 60
        return "\(dateText(daysSinceEpoch: days))T\(NumberText.padded(hour, width: 2)):\(NumberText.padded(minute, width: 2)):\(NumberText.padded(second, width: 2))Z"
    }

    /// `text` with the characters XML 1.0 cannot carry removed and `& < > " '` escaped.
    static func xml(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x26: result.append(contentsOf: "&amp;".unicodeScalars)
            case 0x3C: result.append(contentsOf: "&lt;".unicodeScalars)
            case 0x3E: result.append(contentsOf: "&gt;".unicodeScalars)
            case 0x22: result.append(contentsOf: "&quot;".unicodeScalars)
            case 0x27: result.append(contentsOf: "&apos;".unicodeScalars)
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: result.append(scalar)
            default: break
            }
        }
        return String(result)
    }

    /// Whether a scalar is dropped from user text: control characters (the caller decides about line breaks), format
    /// characters other than the joiners and direction marks that scripts and emoji need, private use, unassigned and
    /// surrogate code points.
    private static func isDroppedCategory(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .format where UserText.isJoinerOrDirectionMark(scalar): false
        case .control, .format, .privateUse, .unassigned, .surrogate: true
        default: false
        }
    }

    /// `text` on one line: control characters and runs of white space become single spaces, the ends are trimmed and the
    /// result is cut to `limit` Unicode scalars.
    static func singleLine(_ text: String, limit: Int) -> String {
        var result = String.UnicodeScalarView()
        var kept = 0
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                pendingSpace = kept > 0
                continue
            }
            if isDroppedCategory(scalar) { continue }
            let needed = pendingSpace ? 2 : 1
            if kept + needed > limit { break }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(scalar)
            kept += needed
        }
        return String(result)
    }

    /// `text` with control characters other than line feeds removed, carriage returns (and CRLF) read as line feeds,
    /// and the result cut to `limit` Unicode scalars: for notes that may have several lines.
    static func multiLine(_ text: String, limit: Int) -> String {
        var result = String.UnicodeScalarView()
        var kept = 0
        var previousWasReturn = false
        for scalar in text.unicodeScalars {
            if kept >= limit { break }
            let wasReturn = previousWasReturn
            previousWasReturn = scalar == "\r"
            if scalar == "\r" || scalar == "\n" {
                if scalar == "\n" && wasReturn { continue }
                result.append("\n")
                kept += 1
                continue
            }
            if scalar == "\t" {
                result.append(" ")
                kept += 1
                continue
            }
            if isDroppedCategory(scalar) { continue }
            result.append(scalar)
            kept += 1
        }
        return String(result)
    }
}

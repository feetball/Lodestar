import Foundation

/// A line of fixed-width text addressed by 1-based inclusive column ranges, as the MPC documents its formats.
struct FixedWidthLine {
    private let scalars: [Unicode.Scalar]

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    /// The number of characters (Unicode scalars) in the line.
    var length: Int { scalars.count }

    /// The characters of columns `first` to `last` without surrounding spaces and tabs; empty if the columns are
    /// blank or beyond the end of the line.
    func text(_ first: Int, _ last: Int) -> String {
        var from = first - 1
        var to = last < scalars.count ? last : scalars.count
        while from < to && (scalars[from].value == 0x20 || scalars[from].value == 0x09) { from += 1 }
        while to > from && (scalars[to - 1].value == 0x20 || scalars[to - 1].value == 0x09) { to -= 1 }
        if from >= to { return "" }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[from..<to])
        return String(result)
    }
}

/// Strict number and calendar helpers for the record parsers.
enum RecordFields {
    /// The longest field text kept in an error payload.
    static let errorTextLength = 40

    /// `text` cut to `errorTextLength` characters (Unicode scalars), for an error payload.
    static func excerpt(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > errorTextLength else { return text }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[0..<errorTextLength])
        return String(result)
    }

    /// Reads a plain decimal number: an optional sign, digits with an optional point (`12`, `-0.5`, `.5`, `5.`),
    /// and, if `allowExponent`, an exponent (`3.7E-6`). Nothing else is accepted (no NaN, no infinity, no hex, no
    /// suffixes, no embedded spaces). Returns `nil` for anything else or a value that is not finite.
    static func decimal(_ text: String, allowExponent: Bool = false) -> Double? {
        let bytes = Array(text.utf8)
        let count = bytes.count
        if count == 0 || count > 40 { return nil }
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        var index = 0
        if bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
        var digits = 0
        while index < count && isDigit(bytes[index]) {
            index += 1
            digits += 1
        }
        if index < count && bytes[index] == 0x2E {
            index += 1
            while index < count && isDigit(bytes[index]) {
                index += 1
                digits += 1
            }
        }
        if digits == 0 { return nil }
        if allowExponent && index < count && (bytes[index] == 0x65 || bytes[index] == 0x45) {
            index += 1
            if index < count && (bytes[index] == 0x2B || bytes[index] == 0x2D) { index += 1 }
            var exponentDigits = 0
            while index < count && isDigit(bytes[index]) {
                index += 1
                exponentDigits += 1
            }
            if exponentDigits == 0 { return nil }
        }
        if index != count { return nil }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// Reads an integer of up to nine digits with an optional sign; `nil` for anything else.
    static func integer(_ text: String) -> Int? {
        let bytes = Array(text.utf8)
        let count = bytes.count
        if count == 0 { return nil }
        var index = 0
        if bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
        if index == count || count - index > 9 { return nil }
        for position in index..<count where bytes[position] < 0x30 || bytes[position] > 0x39 { return nil }
        return Int(text)
    }

    /// The number of days in a month of the Gregorian calendar.
    static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        if month == 2 {
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        }
        return (month == 4 || month == 6 || month == 9 || month == 11) ? 30 : 31
    }

    /// The first year of the Gregorian calendar that the parsers accept, 1583.
    static let minimumYear = 1583

    /// The last year that the parsers accept, 9999.
    static let maximumYear = 9999

    /// The Julian Day of 0h on a Gregorian calendar date.
    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        JulianDate.julianDay(year: year, month: month, day: day)
    }
}

/// A calendar date unpacked from the MPC's five-character packed form.
struct PackedDate: Hashable {
    let year: Int
    let month: Int
    let day: Int
}

/// Unpacking of the Minor Planet Center's packed designations and dates
/// (https://www.minorplanetcenter.net/iau/info/PackedDes.html).
enum PackedDesignation {
    /// The value of a base-62 digit: 0–9, A–Z (10–35), a–z (36–61); `nil` for any other character.
    static func value(_ character: Unicode.Scalar) -> Int? {
        switch character.value {
        case 0x30...0x39: Int(character.value) - 0x30
        case 0x41...0x5A: Int(character.value) - 0x41 + 10
        case 0x61...0x7A: Int(character.value) - 0x61 + 36
        default: nil
        }
    }

    private static func century(_ character: Unicode.Scalar) -> Int? {
        switch character {
        case "I": 18
        case "J": 19
        case "K": 20
        default: nil
        }
    }

    private static func digit(_ character: Unicode.Scalar) -> Int? {
        character.value >= 0x30 && character.value <= 0x39 ? Int(character.value) - 0x30 : nil
    }

    private static func isHalfMonthLetter(_ character: Unicode.Scalar) -> Bool {
        character.value >= 0x41 && character.value <= 0x5A && character != "I"
    }

    /// The minor-planet number of a five-character packed number (`00433`, `A0001`, `~0000`), or `nil`.
    static func number(_ text: String) -> Int? {
        let characters = Array(text.unicodeScalars)
        guard characters.count == 5 else { return nil }
        let first = characters[0]
        if first == "~" {
            var total = 0
            for position in 1...4 {
                guard let v = value(characters[position]) else { return nil }
                total = total * 62 + v
            }
            return 620_000 + total
        }
        guard let leading = value(first) else { return nil }
        var rest = 0
        for position in 1...4 {
            guard let v = digit(characters[position]) else { return nil }
            rest = rest * 10 + v
        }
        let number = leading * 10_000 + rest
        return number >= 1 ? number : nil
    }

    /// The cycle count or comet order of the two characters at positions 4 and 5 of a packed provisional designation.
    private static func order(_ high: Unicode.Scalar, _ low: Unicode.Scalar) -> Int? {
        guard let h = value(high), let l = digit(low) else { return nil }
        return h * 10 + l
    }

    /// The readable provisional designation of a seven-character packed minor-planet designation: `J95X01L` is
    /// `1995 XL1`, `K08Aa0A` is `2008 AA360`, and the survey designations `PLS2040` and `T1S3138` are `2040 P-L` and
    /// `3138 T-1`. `nil` if the text is not a valid packed designation.
    static func minorPlanet(_ text: String) -> String? {
        let characters = Array(text.unicodeScalars)
        guard characters.count == 7 else { return nil }
        let prefix = String(String.UnicodeScalarView(characters[0..<3]))
        let survey: String? = switch prefix {
        case "PLS": "P-L"
        case "T1S": "T-1"
        case "T2S": "T-2"
        case "T3S": "T-3"
        default: nil
        }
        if let survey {
            var number = 0
            for position in 3...6 {
                guard let v = digit(characters[position]) else { return nil }
                number = number * 10 + v
            }
            return number >= 1 ? "\(number) \(survey)" : nil
        }
        guard let century = century(characters[0]), let tens = digit(characters[1]), let ones = digit(characters[2]) else {
            return nil
        }
        guard isHalfMonthLetter(characters[3]) else { return nil }
        guard let cycle = order(characters[4], characters[5]) else { return nil }
        guard isHalfMonthLetter(characters[6]) else { return nil }
        let year = century * 100 + tens * 10 + ones
        return "\(year) \(characters[3])\(characters[6])\(cycle > 0 ? String(cycle) : "")"
    }

    /// The readable provisional designation of a seven-character packed comet designation without the type letter:
    /// `J95A010` is `1995 A1`, `K88AA30` is `2088 A103` and a split comet `J94P01b` is `1994 P1-B`. `nil` if invalid.
    static func cometProvisional(_ text: String) -> String? {
        let characters = Array(text.unicodeScalars)
        guard characters.count == 7 else { return nil }
        guard let century = century(characters[0]), let tens = digit(characters[1]), let ones = digit(characters[2]) else {
            return nil
        }
        guard isHalfMonthLetter(characters[3]) else { return nil }
        guard let order = order(characters[4], characters[5]), order >= 1 else { return nil }
        let fragment = characters[6]
        let suffix: String
        if fragment == "0" {
            suffix = ""
        } else if fragment.value >= 0x61 && fragment.value <= 0x7A {
            suffix = "-" + String(Unicode.Scalar(fragment.value - 0x20)!)
        } else {
            return nil
        }
        let year = century * 100 + tens * 10 + ones
        return "\(year) \(characters[3])\(order)\(suffix)"
    }

    /// The date of a five-character packed date (`K2669` is 2026 June 9), or `nil`: century letter, two year digits,
    /// month `1`–`9`, `A`–`C`, day `1`–`9`, `A`–`V`. The day must exist in that month.
    static func date(_ text: String) -> PackedDate? {
        let characters = Array(text.unicodeScalars)
        guard characters.count == 5 else { return nil }
        guard let century = century(characters[0]), let tens = digit(characters[1]), let ones = digit(characters[2]) else {
            return nil
        }
        guard let month = value(characters[3]), let day = value(characters[4]) else { return nil }
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        let year = century * 100 + tens * 10 + ones
        guard day <= RecordFields.daysInMonth(year, month) else { return nil }
        return PackedDate(year: year, month: month, day: day)
    }
}

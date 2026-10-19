import Foundation

/// The pieces of a minor planet's name: its number, its designation (number or provisional designation) and its name.
struct AsteroidIdentity: Hashable {
    let number: Int?
    let designation: String
    let name: String
}

/// Splitting of the titles the catalogs print into designation and name.
enum SmallBodyNaming {
    /// Splits a comet title into its designation and its name: `"C/2023 A3 (Tsuchinshan-ATLAS)"` into `C/2023 A3` and
    /// `Tsuchinshan-ATLAS`, `"12P/Pons-Brooks"` into `12P` and `Pons-Brooks`, `"P/2026 N2"` into itself and an empty name.
    /// `title` must be trimmed.
    static func cometParts(_ title: String) -> (designation: String, name: String) {
        let text = Array(title.unicodeScalars)
        if let slash = firstIndex(of: "/", in: text), slash > 0, isNumberedCometPrefix(text[0..<slash]) {
            return (string(text[0..<slash]), string(trimmed(text[(slash + 1)...])))
        }
        if text.last == ")", let open = firstIndex(of: " (", in: text), open > 0 {
            let designation = string(trimmed(text[0..<open]))
            let name = string(trimmed(text[(open + 2)..<(text.count - 1)]))
            if !designation.isEmpty { return (designation, name) }
        }
        return (title, "")
    }

    /// The comet number of a numbered designation such as `12P` or `73P-B` (the leading digits), or `nil`.
    static func cometNumber(_ designation: String) -> Int? {
        let text = Array(designation.unicodeScalars)
        var end = 0
        while end < text.count && isDigit(text[end]) { end += 1 }
        if end == 0 || end > 4 || end >= text.count { return nil }
        if !"PCDXI".unicodeScalars.contains(text[end]) { return nil }
        if end + 1 < text.count && text[end + 1] != "-" { return nil }
        guard let number = Int(string(text[0..<end])) else { return nil }
        return number >= 1 ? number : nil
    }

    /// Digits, then one of `PCDXI`, then optionally `-` and one or two capital letters.
    private static func isNumberedCometPrefix(_ prefix: ArraySlice<Unicode.Scalar>) -> Bool {
        let characters = Array(prefix)
        var index = 0
        while index < characters.count && isDigit(characters[index]) { index += 1 }
        if index == 0 || index >= characters.count { return false }
        if !"PCDXI".unicodeScalars.contains(characters[index]) { return false }
        index += 1
        if index == characters.count { return true }
        if characters[index] != "-" { return false }
        let letters = characters.count - index - 1
        if letters < 1 || letters > 2 { return false }
        for position in (index + 1)..<characters.count where !isCapital(characters[position]) { return false }
        return true
    }

    /// Reads the readable designation of an MPCORB line: `"(4) Vesta"` is number 4, name `Vesta`; `"(44594) 1999 OX3"`
    /// is number 44594, name `1999 OX3`; `"2024 YR4"` is an unnumbered asteroid. `text` must be trimmed and not empty.
    static func asteroidReadable(_ text: String) -> AsteroidIdentity {
        let characters = Array(text.unicodeScalars)
        if characters.first == "(", let close = firstIndex(of: ")", in: characters), close > 1 {
            let inner = characters[1..<close]
            let rest = string(trimmed(characters[(close + 1)...]))
            if let number = digitsToNumber(inner) {
                return AsteroidIdentity(number: number, designation: String(number), name: rest)
            }
        }
        return AsteroidIdentity(number: nil, designation: text, name: "")
    }

    /// Reads the full name of the JPL Small-Body Database: `"4 Vesta (A807 FA)"` is number 4, name `Vesta`;
    /// `"44594 (1999 OX3)"` is number 44594, name `1999 OX3`; `"(2024 YR4)"` is an unnumbered asteroid.
    /// `text` must be trimmed and not empty.
    static func asteroidFullName(_ text: String) -> AsteroidIdentity {
        let characters = Array(text.unicodeScalars)
        if characters.first == "(" && characters.last == ")" && characters.count > 2 {
            let inner = characters[1..<(characters.count - 1)]
            if !inner.contains("(") && !inner.contains(")") {
                return AsteroidIdentity(number: nil, designation: string(trimmed(inner)), name: "")
            }
        }
        if isProvisionalDesignation(characters) { return AsteroidIdentity(number: nil, designation: text, name: "") }
        var end = 0
        while end < characters.count && isDigit(characters[end]) { end += 1 }
        if end >= 1 && end <= 8 && (end == characters.count || characters[end] == " ") {
            if let number = digitsToNumber(characters[0..<end]) {
                let rest = trimmed(characters[end...])
                return AsteroidIdentity(number: number, designation: String(number), name: nameWithoutProvisional(Array(rest)))
            }
        }
        return AsteroidIdentity(number: nil, designation: text, name: "")
    }

    /// Four digits, a space, two capital letters and optional digits: `2024 YR4`, which is not a number followed by a name.
    private static func isProvisionalDesignation(_ text: [Unicode.Scalar]) -> Bool {
        if text.count < 7 { return false }
        for index in 0..<4 where !isDigit(text[index]) { return false }
        if text[4] != " " || !isCapital(text[5]) || !isCapital(text[6]) { return false }
        for index in 7..<text.count where !isDigit(text[index]) { return false }
        return true
    }

    /// `"Vesta (A807 FA)"` becomes `Vesta`; `"(1999 OX3)"` becomes `1999 OX3`; anything else is unchanged.
    private static func nameWithoutProvisional(_ rest: [Unicode.Scalar]) -> String {
        if rest.last != ")" { return string(rest[...]) }
        if rest.first == "(" {
            let inner = rest[1..<(rest.count - 1)]
            return !inner.contains("(") && !inner.contains(")") ? string(trimmed(inner)) : string(rest[...])
        }
        if let open = lastIndex(of: " (", in: rest), open > 0 {
            return string(trimmed(rest[0..<open]))
        }
        return string(rest[...])
    }

    private static func digitsToNumber(_ text: ArraySlice<Unicode.Scalar>) -> Int? {
        if text.isEmpty || text.count > 8 { return nil }
        for character in text where !isDigit(character) { return nil }
        guard let number = Int(string(text)) else { return nil }
        return number >= 1 ? number : nil
    }

    // MARK: Scalar helpers

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 0x30 && scalar.value <= 0x39 }

    private static func isCapital(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 0x41 && scalar.value <= 0x5A }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        string(scalars[...])
    }

    /// `scalars` without leading and trailing spaces and tabs.
    private static func trimmed(_ scalars: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        var from = scalars.startIndex
        var to = scalars.endIndex
        while from < to && (scalars[from].value == 0x20 || scalars[from].value == 0x09) { from += 1 }
        while to > from && (scalars[to - 1].value == 0x20 || scalars[to - 1].value == 0x09) { to -= 1 }
        return scalars[from..<to]
    }

    /// The index of the first occurrence of `pattern` (a short ASCII text) in `text`.
    private static func firstIndex(of pattern: String, in text: [Unicode.Scalar]) -> Int? {
        let needle = Array(pattern.unicodeScalars)
        if needle.count > text.count { return nil }
        for start in 0...(text.count - needle.count) where Array(text[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }

    /// The index of the last occurrence of `pattern` in `text`.
    private static func lastIndex(of pattern: String, in text: [Unicode.Scalar]) -> Int? {
        let needle = Array(pattern.unicodeScalars)
        if needle.count > text.count { return nil }
        for start in stride(from: text.count - needle.count, through: 0, by: -1)
        where Array(text[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }
}

/// The columns of a CSV table that `ObservingListCodec` uses, found by their header names.
///
/// Header names are compared without case, punctuation and spacing; "Right Ascension (j2000)", "RA_J2000" and "ra" all
/// name a right ascension. Columns of coordinates of the date (jNow) or of the B1950 equinox are ignored, because the
/// codec returns J2000 places.
struct ObservingListColumns: Equatable {
    /// What a coordinate column says about its unit.
    enum Unit: Equatable {
        /// The header gives no unit: a plain number is read as degrees, sexagesimal text as the parser reads it.
        case unspecified
        case degrees
        case hours
    }

    var designation: Int?
    var name: Int?
    /// Telescopius' "Label", the custom name of a list entry.
    var label: Int?
    var alternates: Int?
    var rightAscension: Int?
    var declination: Int?
    var rightAscensionUnit = Unit.unspecified
    var isTelescopius = false

    private static let designationHeaders: Set<String> = [
        "designation", "catalogue entry", "catalog entry", "catalogue", "catalog", "catalogue number", "catalog number",
        "object", "object id", "target id", "id",
    ]
    private static let nameHeaders: Set<String> = [
        "name", "familiar name", "common name", "target", "target name", "object name",
    ]
    private static let alternateHeaders: Set<String> = ["alternative entries", "alternate entries", "aliases", "alias"]
    private static let rightAscensionFirstTokens: Set<String> = ["ra", "ra2000", "raj2000"]
    private static let declinationFirstTokens: Set<String> = ["dec", "dec2000", "decj2000", "declination", "decl"]
    private static let otherEpochTokens: Set<String> = ["jnow", "b1950", "date"]

    /// The header's words: lower case letters and digits, split at everything else.
    static func tokens(of header: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in header.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                current.append(scalar)
            } else if !current.isEmpty {
                result.append(String(current).lowercased())
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { result.append(String(current).lowercased()) }
        return result
    }

    /// Finds the columns, or returns nil when the header has no name or designation column and no pair of coordinates.
    init?(header: [String]) {
        for (index, text) in header.enumerated() {
            let words = Self.tokens(of: text)
            guard let first = words.first else { continue }
            let key = words.joined(separator: " ")
            let isOtherEpoch = words.contains { Self.otherEpochTokens.contains($0) }
            if Self.rightAscensionFirstTokens.contains(first) || (first == "right" && words.dropFirst().first == "ascension") {
                if !isOtherEpoch && rightAscension == nil {
                    rightAscension = index
                    rightAscensionUnit = Self.unit(of: words)
                }
            } else if Self.declinationFirstTokens.contains(first) {
                if !isOtherEpoch && declination == nil { declination = index }
            } else if key == "label" {
                if label == nil { label = index }
            } else if Self.alternateHeaders.contains(key) {
                if alternates == nil { alternates = index }
            } else if Self.designationHeaders.contains(key) {
                if designation == nil { designation = index }
                if key == "catalogue entry" { isTelescopius = true }
            } else if Self.nameHeaders.contains(key) {
                if name == nil { name = index }
            }
        }
        let hasCoordinates = rightAscension != nil && declination != nil
        guard designation != nil || name != nil || label != nil || hasCoordinates else { return nil }
    }

    private static func unit(of words: [String]) -> Unit {
        for word in words {
            switch word {
            case "deg", "degs", "degree", "degrees": return .degrees
            case "h", "hr", "hrs", "hour", "hours": return .hours
            default: continue
            }
        }
        return .unspecified
    }
}

/// Reads the coordinates of import files with the shared angle parsers.
enum ObservingListCoordinates {
    /// Arcseconds that Telescopius writes as two quotation marks (`03h 46' 24""`) become one.
    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\"\"", with: "\"")
    }

    /// The value of text that is only a number (optional "+", digits, one "." or "," decimal mark), or nil.
    private static func plainNumber(_ text: String) -> Double? {
        var integer = ""
        var fraction = ""
        var hasMark = false
        var isFirst = true
        for scalar in text.unicodeScalars {
            if isFirst && scalar == "+" {
                isFirst = false
                continue
            }
            isFirst = false
            if scalar.value >= 0x30 && scalar.value <= 0x39 {
                if hasMark { fraction.unicodeScalars.append(scalar) } else { integer.unicodeScalars.append(scalar) }
            } else if (scalar == "." || scalar == ",") && !hasMark {
                hasMark = true
            } else {
                return nil
            }
        }
        guard !integer.isEmpty || !fraction.isEmpty else { return nil }
        return Double("\(integer.isEmpty ? "0" : integer).\(fraction.isEmpty ? "0" : fraction)")
    }

    /// A right ascension in degrees, [0, 360), or nil.
    ///
    /// A plain number is degrees unless `unit` says hours; sexagesimal text is hours of time unless it is marked with
    /// `°` or `d` (see `AngleFormatter.parseRightAscension(_:)`).
    static func rightAscension(_ text: String, unit: ObservingListColumns.Unit) -> Double? {
        let cleaned = normalized(text)
        if let number = plainNumber(cleaned) {
            let degrees = unit == .hours ? number * 15 : number
            return degrees >= 0 && degrees < 360 ? degrees : nil
        }
        guard let hours = AngleFormatter.parseRightAscension(cleaned) else { return nil }
        return hours * 15
    }

    /// A declination in degrees, [-90, 90], or nil.
    static func declination(_ text: String) -> Double? {
        AngleFormatter.parseDeclination(normalized(text))
    }
}

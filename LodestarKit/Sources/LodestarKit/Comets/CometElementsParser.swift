import Foundation

/// Reader for the Minor Planet Center's comet orbit file
/// (https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt, about 164 kB and 1000 lines, updated daily; the fixed-width
/// format is described at https://www.minorplanetcenter.net/iau/info/CometOrbitFormat.html, "Ephemerides and Orbital
/// Elements Format").
///
/// Columns (1-based, inclusive): 1–4 periodic-comet number, 5 orbit type, 6–12 packed provisional designation,
/// 15–18 / 20–21 / 23–29 year, month and day (TT) of perihelion, 31–39 perihelion distance, 42–49 eccentricity,
/// 52–59 argument of perihelion, 62–69 ascending node, 72–79 inclination (all J2000.0), 82–89 epoch `YYYYMMDD`
/// (optional), 92–95 absolute magnitude, 97–100 slope parameter `k` (total magnitude `H + 5 log Δ + 2.5 k log r`),
/// 103–158 designation and name. Every field is validated: numbers must be plain decimals within their ranges, the
/// date must exist, and the orbit type must be one of `C P D X I A`. Orbit type `A` (an asteroid on a cometary
/// orbit) gives an `SmallBodyKind.asteroid`, every other type a `SmallBodyKind.comet`.
public enum CometElementsParser {
    /// The shortest line that holds all orbital elements (through the inclination in column 79).
    public static let minimumLineLength = 79

    /// The longest line accepted; real lines have about 170 characters.
    public static let maximumLineLength = 400

    /// The slope parameter assumed when a line gives an absolute magnitude but no slope, 4.0 (K1 = 10).
    public static let defaultSlopeParameter = 4.0

    /// Reads one line of the file.
    ///
    /// - Throws: `SmallBodyParseError` if the line is too short or too long, a field is malformed or out of range, or no
    ///   designation can be made.
    public static func parseLine(_ line: String) throws -> SmallBody {
        let columns = FixedWidthLine(line)
        if columns.length > maximumLineLength { throw SmallBodyParseError.lineTooLong(length: columns.length, maximum: maximumLineLength) }
        if columns.length < minimumLineLength { throw SmallBodyParseError.lineTooShort(length: columns.length, minimum: minimumLineLength) }

        // Identity.
        let numberText = columns.text(1, 4)
        var number: Int?
        if !numberText.isEmpty {
            guard let value = RecordFields.integer(numberText), value >= 1 else {
                throw SmallBodyParseError.malformedField(.cometNumber, text: RecordFields.excerpt(numberText))
            }
            number = value
        }
        let typeText = columns.text(5, 5)
        if typeText.isEmpty { throw SmallBodyParseError.missingField(.orbitType) }
        guard typeText.unicodeScalars.count == 1, "CPDXIA".contains(typeText) else {
            throw SmallBodyParseError.malformedField(.orbitType, text: RecordFields.excerpt(typeText))
        }

        // Time of perihelion.
        let year = try integerField(columns, 15, 18, .perihelionYear)
        if year < RecordFields.minimumYear || year > RecordFields.maximumYear {
            throw SmallBodyParseError.fieldOutOfRange(.perihelionYear, value: Double(year))
        }
        let month = try integerField(columns, 20, 21, .perihelionMonth)
        if month < 1 || month > 12 { throw SmallBodyParseError.fieldOutOfRange(.perihelionMonth, value: Double(month)) }
        let day = try decimalField(columns, 23, 29, .perihelionDay, 0.0, 32.0)
        if day >= 32.0 { throw SmallBodyParseError.fieldOutOfRange(.perihelionDay, value: day) }
        let perihelionTime = RecordFields.julianDay(year: year, month: month, day: 1) + (day - 1.0)

        // Orbit.
        let perihelionDistance = try decimalField(columns, 31, 39, .perihelionDistance, 0.0, SmallBodyElements.maximumPerihelionDistanceAU)
        let eccentricity = try decimalField(columns, 42, 49, .eccentricity, 0.0, SmallBodyElements.maximumEccentricity)
        let argumentOfPerihelion = try decimalField(columns, 52, 59, .argumentOfPerihelion, 0.0, 360.0)
        let ascendingNode = try decimalField(columns, 62, 69, .longitudeOfAscendingNode, 0.0, 360.0)
        let inclination = try decimalField(columns, 72, 79, .inclination, 0.0, 180.0)

        // Epoch, if given.
        var epoch: Double?
        let epochText = columns.text(82, 89)
        if !epochText.isEmpty {
            guard epochText.utf8.count == 8, let packed = RecordFields.integer(epochText) else {
                throw SmallBodyParseError.malformedField(.epoch, text: RecordFields.excerpt(epochText))
            }
            let epochYear = packed / 10_000
            let epochMonth = (packed / 100) % 100
            let epochDay = packed % 100
            if epochYear < RecordFields.minimumYear || epochYear > RecordFields.maximumYear || epochMonth < 1
                || epochMonth > 12 || epochDay < 1 || epochDay > RecordFields.daysInMonth(epochYear, epochMonth) {
                throw SmallBodyParseError.malformedField(.epoch, text: epochText)
            }
            epoch = RecordFields.julianDay(year: epochYear, month: epochMonth, day: epochDay)
        }

        guard let orbit = SmallBodyElements(
            perihelionDistanceAU: perihelionDistance, eccentricity: eccentricity, inclination: inclination,
            argumentOfPerihelion: argumentOfPerihelion, longitudeOfAscendingNode: ascendingNode,
            perihelionJulianDayTT: perihelionTime, epochJulianDayTT: epoch) else {
            throw SmallBodyParseError.inconsistentElements(reason: "the elements do not describe an orbit")
        }

        // Brightness.
        var photometry: SmallBodyPhotometry?
        let magnitudeText = columns.text(92, 95)
        let slopeText = columns.text(97, 100)
        var slope: Double?
        if !slopeText.isEmpty {
            guard let value = RecordFields.decimal(slopeText) else {
                throw SmallBodyParseError.malformedField(.slopeParameter, text: RecordFields.excerpt(slopeText))
            }
            if value < 0 || value > 24 { throw SmallBodyParseError.fieldOutOfRange(.slopeParameter, value: value) }
            slope = value
        }
        if !magnitudeText.isEmpty {
            guard let magnitude = RecordFields.decimal(magnitudeText) else {
                throw SmallBodyParseError.malformedField(.absoluteMagnitude, text: RecordFields.excerpt(magnitudeText))
            }
            if magnitude < -20 || magnitude > 40 {
                throw SmallBodyParseError.fieldOutOfRange(.absoluteMagnitude, value: magnitude)
            }
            guard let magnitudes = CometMagnitudes.fromMPC(absoluteMagnitude: magnitude, slopeParameter: slope ?? defaultSlopeParameter) else {
                throw SmallBodyParseError.fieldOutOfRange(.absoluteMagnitude, value: magnitude)
            }
            photometry = .comet(magnitudes)
        }

        // Designation and name.
        let orbitType = typeText
        let title = columns.text(103, 158)
        let designation: String
        let name: String
        if !title.isEmpty {
            let parts = SmallBodyNaming.cometParts(title)
            designation = parts.designation
            name = parts.name
            if number == nil { number = SmallBodyNaming.cometNumber(designation) }
        } else {
            designation = try fallbackDesignation(number: number, orbitType: orbitType, packed: columns.text(6, 12))
            name = ""
        }
        let kind: SmallBodyKind = orbitType == "A" ? .asteroid : .comet
        guard let body = SmallBody(designation: designation, name: name, kind: kind, number: number, orbit: orbit, photometry: photometry) else {
            throw SmallBodyParseError.invalidDesignation(text: RecordFields.excerpt(title.isEmpty ? designation : title))
        }
        return body
    }

    /// Reads a whole `CometEls.txt`, skipping lines that are not valid orbit records (and counting them in the result).
    /// Duplicated objects are skipped after their first occurrence.
    ///
    /// - Throws: `SmallBodyParseError.inputTooLarge` if `text` has more than 64 Mi characters.
    public static func parse(_ text: String) throws -> SmallBodyParseResult {
        try SmallBodyBatch.parse(text, skipHeader: false, parseLine: parseLine)
    }

    private static func integerField(_ columns: FixedWidthLine, _ first: Int, _ last: Int, _ field: SmallBodyField) throws -> Int {
        let text = columns.text(first, last)
        if text.isEmpty { throw SmallBodyParseError.missingField(field) }
        guard let value = RecordFields.integer(text) else {
            throw SmallBodyParseError.malformedField(field, text: RecordFields.excerpt(text))
        }
        return value
    }

    /// A decimal field in `minimum...maximum`; the upper bound is inclusive unless the caller tests it itself.
    private static func decimalField(_ columns: FixedWidthLine, _ first: Int, _ last: Int, _ field: SmallBodyField,
                                     _ minimum: Double, _ maximum: Double) throws -> Double {
        let text = columns.text(first, last)
        if text.isEmpty { throw SmallBodyParseError.missingField(field) }
        guard let value = RecordFields.decimal(text) else {
            throw SmallBodyParseError.malformedField(field, text: RecordFields.excerpt(text))
        }
        if value < minimum || value > maximum { throw SmallBodyParseError.fieldOutOfRange(field, value: value) }
        return value
    }

    /// `12P` (with a fragment letter `12P-B` when the packed field holds one) or `C/1995 O1`, from the packed columns.
    private static func fallbackDesignation(number: Int?, orbitType: String, packed: String) throws -> String {
        if let number {
            let scalars = Array(packed.unicodeScalars)
            let fragment: String
            if scalars.count == 1, scalars[0].value >= 0x61, scalars[0].value <= 0x7A {
                fragment = "-" + String(Unicode.Scalar(scalars[0].value - 0x20)!)
            } else {
                fragment = ""
            }
            return "\(number)\(orbitType)\(fragment)"
        }
        guard let provisional = PackedDesignation.cometProvisional(packed) else {
            throw SmallBodyParseError.invalidDesignation(text: RecordFields.excerpt(packed))
        }
        return "\(orbitType)/\(provisional)"
    }
}

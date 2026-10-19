import Foundation

/// Reader for the Minor Planet Center's one-line minor-planet orbit format, as used in `MPCORB.DAT` (about 320 MB, one
/// line per asteroid) and its extracts `NEA.txt` (8.7 MB), `PHA.txt` (0.5 MB), `Distant.txt` and `Unusual.txt`; the
/// format is described at https://www.minorplanetcenter.net/iau/info/MPOrbitFormat.html.
///
/// Columns (1-based, inclusive): 1–7 packed number or provisional designation, 9–13 absolute magnitude H, 15–19 slope
/// parameter G, 21–25 packed epoch (TT), 27–35 mean anomaly, 38–46 argument of perihelion, 49–57 ascending node,
/// 60–68 inclination (J2000.0), 71–79 eccentricity, 81–91 mean daily motion (degrees), 93–103 semi-major axis (AU),
/// 167–194 readable designation (optional). H and G may be blank; the other elements are required and checked against
/// each other (mean motion and semi-major axis must agree to 1 %). Only elliptic orbits (`e < 1`) exist in this format.
public enum MinorPlanetElementsParser {
    /// The shortest line that holds all elements (through the semi-major axis in column 103).
    public static let minimumLineLength = 103

    /// The longest line accepted; real lines have about 200 characters.
    public static let maximumLineLength = 400

    /// An absolute magnitude of this value or more (the MPC writes 99.99) means "unknown": the body has no photometry.
    public static let unknownMagnitude = 99.0

    /// Reads one orbit line.
    ///
    /// - Throws: `SmallBodyParseError` if the line is too short or too long, a field is malformed or out of range, the
    ///   mean motion and the semi-major axis disagree, or no designation can be made.
    public static func parseLine(_ line: String) throws -> SmallBody {
        let columns = FixedWidthLine(line)
        if columns.length > maximumLineLength { throw SmallBodyParseError.lineTooLong(length: columns.length, maximum: maximumLineLength) }
        if columns.length < minimumLineLength { throw SmallBodyParseError.lineTooShort(length: columns.length, minimum: minimumLineLength) }

        // Epoch and elements.
        let epochText = columns.text(21, 25)
        if epochText.isEmpty { throw SmallBodyParseError.missingField(.epoch) }
        guard let epochDate = PackedDesignation.date(epochText) else {
            throw SmallBodyParseError.malformedField(.epoch, text: RecordFields.excerpt(epochText))
        }
        let epoch = RecordFields.julianDay(year: epochDate.year, month: epochDate.month, day: epochDate.day)
        let meanAnomaly = try decimalField(columns, 27, 35, .meanAnomaly, 0.0, 360.0)
        let argumentOfPerihelion = try decimalField(columns, 38, 46, .argumentOfPerihelion, 0.0, 360.0)
        let ascendingNode = try decimalField(columns, 49, 57, .longitudeOfAscendingNode, 0.0, 360.0)
        let inclination = try decimalField(columns, 60, 68, .inclination, 0.0, 180.0)
        let eccentricity = try decimalField(columns, 71, 79, .eccentricity, 0.0, 1.0)
        if eccentricity >= 1.0 { throw SmallBodyParseError.fieldOutOfRange(.eccentricity, value: eccentricity) }
        let meanMotion = try decimalField(columns, 81, 91, .meanMotion, 0.0, 40.0)
        if meanMotion <= 0.0 { throw SmallBodyParseError.fieldOutOfRange(.meanMotion, value: meanMotion) }
        let semiMajorAxis = try decimalField(columns, 93, 103, .semiMajorAxis, 0.0, 10_000.0)
        if semiMajorAxis <= 0.0 { throw SmallBodyParseError.fieldOutOfRange(.semiMajorAxis, value: semiMajorAxis) }
        let expectedMotion = AstroMath.degrees(
            OrbitPropagator.gaussianGravitationalConstant / (semiMajorAxis * semiMajorAxis.squareRoot()))
        if abs(expectedMotion - meanMotion) > 0.01 * meanMotion {
            throw SmallBodyParseError.inconsistentElements(
                reason: "the mean motion \(meanMotion) and the semi-major axis \(semiMajorAxis) disagree")
        }
        guard let orbit = SmallBodyElements.fromMeanAnomaly(
            semiMajorAxisAU: semiMajorAxis, eccentricity: eccentricity, inclination: inclination,
            argumentOfPerihelion: argumentOfPerihelion, longitudeOfAscendingNode: ascendingNode,
            meanAnomaly: meanAnomaly, epochJulianDayTT: epoch) else {
            throw SmallBodyParseError.inconsistentElements(reason: "the elements do not describe an orbit")
        }

        // Brightness.
        var photometry: SmallBodyPhotometry?
        let magnitudeText = columns.text(9, 13)
        let slopeText = columns.text(15, 19)
        var slope: Double?
        if !slopeText.isEmpty {
            guard let value = RecordFields.decimal(slopeText) else {
                throw SmallBodyParseError.malformedField(.slopeParameter, text: RecordFields.excerpt(slopeText))
            }
            if value < -0.25 || value > 1.0 { throw SmallBodyParseError.fieldOutOfRange(.slopeParameter, value: value) }
            slope = value
        }
        if !magnitudeText.isEmpty {
            guard let magnitude = RecordFields.decimal(magnitudeText) else {
                throw SmallBodyParseError.malformedField(.absoluteMagnitude, text: RecordFields.excerpt(magnitudeText))
            }
            if magnitude < unknownMagnitude && (magnitude < -5 || magnitude > 40) {
                throw SmallBodyParseError.fieldOutOfRange(.absoluteMagnitude, value: magnitude)
            }
            if magnitude < unknownMagnitude {
                guard let magnitudes = AsteroidMagnitudes(absoluteMagnitude: magnitude,
                                                         slopeParameter: slope ?? AsteroidMagnitudes.defaultSlopeParameter) else {
                    throw SmallBodyParseError.fieldOutOfRange(.absoluteMagnitude, value: magnitude)
                }
                photometry = .asteroid(magnitudes)
            }
        }

        // Designation and name.
        let packed = columns.text(1, 7)
        if packed.isEmpty { throw SmallBodyParseError.missingField(.packedDesignation) }
        let readableText = columns.text(167, 194)
        let readable = readableText.isEmpty ? nil : SmallBodyNaming.asteroidReadable(readableText)
        let number: Int? = packed.unicodeScalars.count == 5 ? PackedDesignation.number(packed) : nil
        let designation: String
        var name = ""
        if let number {
            designation = String(number)
            if let readable, readable.number == number { name = readable.name }
        } else {
            let provisional = packed.unicodeScalars.count == 7 ? PackedDesignation.minorPlanet(packed) : nil
            if let provisional {
                designation = provisional
            } else if let readable, readable.number == nil {
                designation = readable.designation
            } else {
                throw SmallBodyParseError.invalidDesignation(text: RecordFields.excerpt(packed))
            }
        }
        guard let body = SmallBody(designation: designation, name: name, kind: .asteroid, number: number, orbit: orbit,
                                   photometry: photometry) else {
            throw SmallBodyParseError.invalidDesignation(text: RecordFields.excerpt(packed))
        }
        return body
    }

    /// Reads a whole file in this format, skipping lines that are not valid orbit records (and counting them in the
    /// result). The header of `MPCORB.DAT` (everything up to the line of dashes) and blank lines are ignored without
    /// being counted; the blank lines that separate the sections of `MPCORB.DAT` likewise. A second occurrence of an
    /// object is skipped as a duplicate.
    ///
    /// - Throws: `SmallBodyParseError.inputTooLarge` if `text` has more than 64 Mi characters.
    public static func parse(_ text: String) throws -> SmallBodyParseResult {
        try SmallBodyBatch.parse(text, skipHeader: true, parseLine: parseLine)
    }

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
}

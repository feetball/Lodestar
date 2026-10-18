import Foundation

/// A field of an orbit record, named in `SmallBodyParseError`s.
public enum SmallBodyField: String, CaseIterable, Hashable, Sendable {
    /// The periodic-comet number (columns 1–4 of a comet line).
    case cometNumber
    /// The orbit type letter (`C`, `P`, `D`, `X`, `I` or `A`).
    case orbitType
    /// The packed provisional designation.
    case packedDesignation
    /// The year of perihelion passage.
    case perihelionYear
    /// The month of perihelion passage.
    case perihelionMonth
    /// The day (with fraction) of perihelion passage.
    case perihelionDay
    /// The perihelion time (JPL Julian Day).
    case perihelionTime
    /// The perihelion distance.
    case perihelionDistance
    /// The eccentricity.
    case eccentricity
    /// The argument of perihelion.
    case argumentOfPerihelion
    /// The longitude of the ascending node.
    case longitudeOfAscendingNode
    /// The inclination.
    case inclination
    /// The epoch of the elements.
    case epoch
    /// The absolute magnitude (H, or M1 of a comet).
    case absoluteMagnitude
    /// The slope parameter (G of an asteroid, k or K1 of a comet).
    case slopeParameter
    /// The nuclear magnitude M2 or its slope K2 or phase coefficient PC.
    case nuclearMagnitude
    /// The mean anomaly at the epoch.
    case meanAnomaly
    /// The mean daily motion.
    case meanMotion
    /// The semi-major axis.
    case semiMajorAxis
    /// The designation or name.
    case designation

    /// The English name of the field.
    public var displayName: String {
        switch self {
        case .cometNumber: "comet number"
        case .orbitType: "orbit type"
        case .packedDesignation: "packed designation"
        case .perihelionYear: "year of perihelion"
        case .perihelionMonth: "month of perihelion"
        case .perihelionDay: "day of perihelion"
        case .perihelionTime: "time of perihelion"
        case .perihelionDistance: "perihelion distance"
        case .eccentricity: "eccentricity"
        case .argumentOfPerihelion: "argument of perihelion"
        case .longitudeOfAscendingNode: "longitude of the ascending node"
        case .inclination: "inclination"
        case .epoch: "epoch"
        case .absoluteMagnitude: "absolute magnitude"
        case .slopeParameter: "slope parameter"
        case .nuclearMagnitude: "nuclear magnitude"
        case .meanAnomaly: "mean anomaly"
        case .meanMotion: "mean motion"
        case .semiMajorAxis: "semi-major axis"
        case .designation: "designation"
        }
    }
}

/// Why an orbit record could not be read. `description` is a sentence for logs.
public enum SmallBodyParseError: Error, Hashable, Sendable {
    /// The line ends before the last required column.
    case lineTooShort(length: Int, minimum: Int)
    /// The line is longer than any valid record.
    case lineTooLong(length: Int, maximum: Int)
    /// A required field is blank or absent.
    case missingField(SmallBodyField)
    /// A field is not a number (or not a date or letter) of the expected form. `text` is the field, cut to 40 characters.
    case malformedField(SmallBodyField, text: String)
    /// A field is a number outside its permitted range.
    case fieldOutOfRange(SmallBodyField, value: Double)
    /// No usable designation could be read or unpacked.
    case invalidDesignation(text: String)
    /// The fields of the record contradict each other.
    case inconsistentElements(reason: String)
    /// The same object occurs twice in a file; the first occurrence is kept.
    case duplicateObject(id: String)
    /// The text is not usable JSON of the expected shape.
    case invalidJSON(reason: String)
    /// The service answered that it has no (unique) such object, or the record is of an unsupported kind.
    case unsupportedObject(reason: String)
    /// The text is longer than the parser accepts.
    case inputTooLarge(length: Int, maximum: Int)
}

extension SmallBodyParseError: LocalizedError, CustomStringConvertible {
    /// A sentence that says what is wrong.
    public var description: String {
        switch self {
        case .lineTooShort(let length, let minimum):
            "The line has \(length) characters; at least \(minimum) are required."
        case .lineTooLong(let length, let maximum):
            "The line has \(length) characters; at most \(maximum) are allowed."
        case .missingField(let field):
            "The \(field.displayName) is missing."
        case .malformedField(let field, let text):
            "The \(field.displayName) \"\(text)\" is not valid."
        case .fieldOutOfRange(let field, let value):
            "The \(field.displayName) \(value) is out of range."
        case .invalidDesignation(let text):
            "The designation \"\(text)\" is not valid."
        case .inconsistentElements(let reason):
            "The orbital elements are inconsistent: \(reason)."
        case .duplicateObject(let id):
            "The object \(id) occurs more than once."
        case .invalidJSON(let reason):
            "The JSON is not valid: \(reason)."
        case .unsupportedObject(let reason):
            "The object cannot be used: \(reason)."
        case .inputTooLarge(let length, let maximum):
            "The input has \(length) characters; at most \(maximum) are accepted."
        }
    }

    /// The same sentence as `description`.
    public var errorDescription: String? { description }
}

/// One line a batch parser skipped.
public struct SmallBodyLineRejection: Hashable, Sendable {
    /// The 1-based line number in the input.
    public let lineNumber: Int
    /// Why the line was skipped.
    public let error: SmallBodyParseError

    public init(lineNumber: Int, error: SmallBodyParseError) {
        self.lineNumber = lineNumber
        self.error = error
    }
}

/// The outcome of parsing a whole file leniently: every valid record, and a count of the lines skipped. Blank lines
/// and the header of an MPCORB file are not counted as rejected.
public struct SmallBodyParseResult: Hashable, Sendable {
    /// The bodies in file order, without duplicates.
    public let bodies: [SmallBody]
    /// How many non-blank lines were skipped.
    public let rejectedLineCount: Int
    /// The first `maximumReportedRejections` skipped lines with their reasons.
    public let rejections: [SmallBodyLineRejection]

    /// The number of rejections that are kept in `rejections`, 50.
    public static let maximumReportedRejections = 50

    public init(bodies: [SmallBody], rejectedLineCount: Int, rejections: [SmallBodyLineRejection]) {
        self.bodies = bodies
        self.rejectedLineCount = rejectedLineCount
        self.rejections = rejections
    }
}

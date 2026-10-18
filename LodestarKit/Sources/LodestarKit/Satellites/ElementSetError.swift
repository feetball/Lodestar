import Foundation

/// Why an orbital element set (a TLE or a CelesTrak OMM record) was rejected.
///
/// Parsing a batch never throws for a single bad record: the record is skipped and reported in
/// `ElementSetBatch.skipped`. The errors below describe one record, or (for `malformedJSON`, `inputTooLarge`) a
/// whole input that cannot be read at all. `description` is one sentence that names the field and says what is wrong.
public enum ElementSetError: Error, Hashable, Sendable {
    /// A TLE line is not exactly 69 characters long (after trailing white space is removed).
    case invalidLineLength(line: Int, length: Int)
    /// A TLE line does not start with its line number ("1 " or "2 ").
    case unexpectedLineNumber(line: Int)
    /// The modulo-10 checksum in column 69 of a TLE line does not match the line.
    case checksumMismatch(line: Int, expected: Int, found: Int)
    /// A field cannot be read: `text` is not a number, a date or an identifier of the expected shape.
    case invalidField(field: String, text: String)
    /// A field is a number but outside the range that is physically or formally possible.
    case valueOutOfRange(field: String, value: Double)
    /// The catalog numbers on the two lines of a TLE differ.
    case catalogNumberMismatch(line1: Int, line2: Int)
    /// A required field is absent from a record.
    case missingField(field: String)
    /// The input is not valid JSON, or its top level is neither an array nor an object.
    case malformedJSON(reason: String)
    /// An element of a JSON array is not an object of OMM fields.
    case invalidRecord(reason: String)
    /// The input has more than `limit` characters.
    case inputTooLarge(limit: Int)
}

extension ElementSetError: LocalizedError, CustomStringConvertible {
    /// A sentence that names the field and says what is wrong.
    public var description: String {
        switch self {
        case .invalidLineLength(let line, let length):
            "TLE line \(line) has \(length) characters instead of 69."
        case .unexpectedLineNumber(let line):
            "TLE line \(line) does not start with its line number."
        case .checksumMismatch(let line, let expected, let found):
            "TLE line \(line) has checksum digit \(found) but its contents add up to \(expected)."
        case .invalidField(let field, let text):
            "The field \(field) cannot be read from \"\(text)\"."
        case .valueOutOfRange(let field, let value):
            "The field \(field) is out of range: \(value)."
        case .catalogNumberMismatch(let line1, let line2):
            "The two TLE lines belong to different objects (\(line1) and \(line2))."
        case .missingField(let field):
            "The required field \(field) is missing."
        case .malformedJSON(let reason):
            "The element sets are not valid JSON: \(reason)"
        case .invalidRecord(let reason):
            "The record is not an OMM object: \(reason)"
        case .inputTooLarge(let limit):
            "The element sets are larger than \(limit) characters."
        }
    }

    /// The same sentence as `description`.
    public var errorDescription: String? { description }
}

/// A record that a batch parse skipped.
public struct SkippedElementSet: Hashable, Sendable {
    /// Zero-based position of the record in the input (the n-th TLE, the n-th array element).
    public let index: Int
    /// The object name, when it could be read.
    public let name: String?
    /// Why it was skipped.
    public let error: ElementSetError

    public init(index: Int, name: String?, error: ElementSetError) {
        self.index = index
        self.name = name
        self.error = error
    }
}

/// The result of parsing many element sets at once: the valid ones and a report of the rest.
public struct ElementSetBatch: Hashable, Sendable {
    /// The valid element sets, in input order.
    public let elements: [OrbitalElements]
    /// The first `ElementSetParser.maximumReportedSkips` skipped records.
    public let skipped: [SkippedElementSet]
    /// How many records were skipped in total.
    public let skippedCount: Int

    public init(elements: [OrbitalElements], skipped: [SkippedElementSet], skippedCount: Int) {
        self.elements = elements
        self.skipped = skipped
        self.skippedCount = skippedCount
    }

    /// The newest element set of each object (by catalog number), in order of first appearance. Feeds that mix
    /// several downloads can contain one object twice.
    public func latestPerObject() -> ElementSetBatch {
        var newest: [Int: OrbitalElements] = [:]
        newest.reserveCapacity(elements.count * 2)
        var order: [Int] = []
        order.reserveCapacity(elements.count)
        for candidate in elements {
            if let current = newest[candidate.catalogNumber] {
                if candidate.epoch > current.epoch { newest[candidate.catalogNumber] = candidate }
            } else {
                order.append(candidate.catalogNumber)
                newest[candidate.catalogNumber] = candidate
            }
        }
        var kept: [OrbitalElements] = []
        kept.reserveCapacity(order.count)
        for number in order {
            if let entry = newest[number] { kept.append(entry) }
        }
        return ElementSetBatch(elements: kept, skipped: skipped, skippedCount: skippedCount)
    }
}

import Foundation

/// Reads orbital element sets from the two formats CelesTrak publishes: GP data in OMM JSON (preferred; it has no
/// limit on the catalog number) and classic two-line element sets (TLE).
///
/// Every field is validated (see `OrbitalElements`). A single set is parsed with `parseTwoLine` and throws an
/// `ElementSetError`; the batch functions skip bad records and report them in `ElementSetBatch.skipped`.
///
/// Cost: about 10 microseconds per record; a 10 000-record Starlink download (5 MB of JSON) parses in well under a
/// second. The functions are pure and thread safe.
public enum ElementSetParser {
    /// The largest input accepted, in characters.
    public static let maximumInputCharacters = 64_000_000
    /// The most records a batch parse looks at; the rest of the input is ignored.
    public static let maximumRecordCount = 200_000
    /// The most skipped records a batch lists in `ElementSetBatch.skipped` (the total is in `skippedCount`).
    public static let maximumReportedSkips = 50

    private static let lineLength = 69

    // MARK: Two-line sets

    /// Parses one two-line element set.
    ///
    /// Each line must have 69 characters (trailing white space is ignored), the right line number, a correct
    /// modulo-10 checksum, and well-formed fields. The catalog number may be a five-digit number or an Alpha-5
    /// number (a letter and four digits, 100 000 ... 339 999). Blank optional fields (designator, element set
    /// number, revolution number, ephemeris type) are accepted.
    ///
    /// - Parameters:
    ///   - line1: The first line.
    ///   - line2: The second line.
    ///   - name: The object name from a preceding name line, if any ("0 " of the 3LE format is removed).
    /// - Throws: An `ElementSetError` describing the first problem found.
    public static func parseTwoLine(line1: String, line2: String, name: String? = nil) throws -> OrbitalElements {
        let first = trimTrailing(Array(line1.unicodeScalars))
        let second = trimTrailing(Array(line2.unicodeScalars))
        guard first.count == lineLength else { throw ElementSetError.invalidLineLength(line: 1, length: first.count) }
        guard second.count == lineLength else { throw ElementSetError.invalidLineLength(line: 2, length: second.count) }
        guard first[0] == "1" && first[1] == " " else { throw ElementSetError.unexpectedLineNumber(line: 1) }
        guard second[0] == "2" && second[1] == " " else { throw ElementSetError.unexpectedLineNumber(line: 2) }
        try checkChecksum(first, number: 1)
        try checkChecksum(second, number: 2)
        try checkSeparators(first, firstLineSeparators)
        try checkSeparators(second, secondLineSeparators)

        let catalogNumber = try catalogNumberOf(substring(first, 2, 7))
        let secondCatalogNumber = try catalogNumberOf(substring(second, 2, 7))
        guard catalogNumber == secondCatalogNumber else {
            throw ElementSetError.catalogNumberMismatch(line1: catalogNumber, line2: secondCatalogNumber)
        }

        let classification: Character = first[7] == " " ? "U" : Character(first[7])
        let objectId = designator(substring(first, 9, 17))

        let yearText = substring(first, 18, 20)
        guard isDigits(yearText) else { throw ElementSetError.invalidField(field: "EPOCH", text: substring(first, 18, 32)) }
        let shortYear = Int(yearText) ?? 0
        let year = shortYear < 57 ? shortYear + 2000 : shortYear + 1900
        let days = try decimal(substring(first, 20, 32), name: "EPOCH")
        let daysInYear = year % 4 == 0 ? 366.0 : 365.0
        guard days >= 1.0 && days < daysInYear + 1.0 else { throw ElementSetError.valueOutOfRange(field: "EPOCH", value: days) }
        let calendar = ElementCalendar.monthDayTime(year: year, days: days)

        let meanMotionDot = try decimal(substring(first, 33, 43), name: "MEAN_MOTION_DOT")
        let meanMotionDdot = try impliedExponent(substring(first, 44, 52), name: "MEAN_MOTION_DDOT")
        let bstar = try impliedExponent(substring(first, 53, 61), name: "BSTAR")
        var ephemerisType = 0
        if first[62] != " " { ephemerisType = try digit(first[62], name: "EPHEMERIS_TYPE") }
        let elementSetNumber = try integer(substring(first, 64, 68), name: "ELEMENT_SET_NO")

        let inclination = try decimal(substring(second, 8, 16), name: "INCLINATION")
        let node = try decimal(substring(second, 17, 25), name: "RA_OF_ASC_NODE")
        let eccentricityText = substring(second, 26, 33)
        guard isDigits(eccentricityText) else { throw ElementSetError.invalidField(field: "ECCENTRICITY", text: eccentricityText) }
        let eccentricity = Double(Int(eccentricityText) ?? 0) / 1.0e7
        let argument = try decimal(substring(second, 34, 42), name: "ARG_OF_PERICENTER")
        let anomaly = try decimal(substring(second, 43, 51), name: "MEAN_ANOMALY")
        let meanMotion = try decimal(substring(second, 52, 63), name: "MEAN_MOTION")
        let revolutions = try integer(substring(second, 63, 68), name: "REV_AT_EPOCH")

        return try OrbitalElements.make(
            name: name.flatMap { cleanName($0) },
            objectId: objectId,
            catalogNumber: catalogNumber,
            classification: classification,
            year: year,
            month: calendar.month,
            day: calendar.day,
            hour: calendar.hour,
            minute: calendar.minute,
            second: calendar.second,
            meanMotion: meanMotion,
            eccentricity: eccentricity,
            inclination: inclination,
            rightAscensionOfAscendingNode: node,
            argumentOfPericenter: argument,
            meanAnomaly: anomaly,
            ephemerisType: ephemerisType,
            elementSetNumber: elementSetNumber,
            revolutionNumberAtEpoch: revolutions,
            bstar: bstar,
            meanMotionDot: meanMotionDot,
            meanMotionDdot: meanMotionDdot
        )
    }

    /// Parses a text with many two-line sets: the 2LE format (pairs of lines) or the 3LE format (a name line
    /// before each pair). Blank lines are ignored; a record that fails validation is skipped and reported.
    ///
    /// - Throws: `ElementSetError.inputTooLarge` if the text is longer than `maximumInputCharacters`.
    public static func parseTwoLineText(_ text: String) throws -> ElementSetBatch {
        guard text.utf16.count <= maximumInputCharacters else { throw ElementSetError.inputTooLarge(limit: maximumInputCharacters) }
        let lines = splitLines(text)
        var elements: [OrbitalElements] = []
        var skipped: [SkippedElementSet] = []
        var skippedCount = 0
        var recordIndex = 0
        var pendingName: String?
        var index = 0
        while index < lines.count && recordIndex < maximumRecordCount {
            let line = lines[index]
            if line.isEmpty {
                pendingName = nil
                index += 1
                continue
            }
            let isFirstLine = line.count >= 2 && line[0] == "1" && line[1] == " "
            let nextIsSecondLine = index + 1 < lines.count && lines[index + 1].count >= 2
                && lines[index + 1][0] == "2" && lines[index + 1][1] == " "
            if isFirstLine && nextIsSecondLine {
                do {
                    elements.append(try parseTwoLine(line1: string(line), line2: string(lines[index + 1]), name: pendingName))
                } catch let error as ElementSetError {
                    skippedCount += 1
                    if skipped.count < maximumReportedSkips {
                        skipped.append(SkippedElementSet(index: recordIndex, name: pendingName.flatMap { cleanName($0) }, error: error))
                    }
                } catch {
                    skippedCount += 1
                }
                recordIndex += 1
                pendingName = nil
                index += 2
            } else if (isFirstLine && line.count >= 60) || (line.count >= 60 && line[0] == "2" && line[1] == " ") {
                // A line 1 without its line 2, or a line 2 without its line 1.
                skippedCount += 1
                if skipped.count < maximumReportedSkips {
                    skipped.append(SkippedElementSet(
                        index: recordIndex,
                        name: pendingName.flatMap { cleanName($0) },
                        error: .unexpectedLineNumber(line: isFirstLine ? 2 : 1)
                    ))
                }
                recordIndex += 1
                pendingName = nil
                index += 1
            } else {
                pendingName = string(line)
                index += 1
            }
        }
        return ElementSetBatch(elements: elements, skipped: skipped, skippedCount: skippedCount)
    }

    /// The modulo-10 checksum of the first 68 characters of a TLE line: digits count, `-` counts 1, rest 0.
    public static func checksum(_ line: String) -> Int {
        checksum(Array(line.unicodeScalars))
    }

    private static func checksum(_ line: [Unicode.Scalar]) -> Int {
        var sum = 0
        let end = min(line.count, lineLength - 1)
        var index = 0
        while index < end {
            let scalar = line[index]
            if let value = digitValue(scalar) {
                sum += value
            } else if scalar == "-" {
                sum += 1
            }
            index += 1
        }
        return sum % 10
    }

    // MARK: OMM JSON

    /// Parses CelesTrak GP data in OMM JSON: an array of objects (`FORMAT=json`) or a single object. Numeric
    /// values may be JSON numbers or numeric strings (Space-Track writes strings). A record that is not an
    /// object, lacks a required field or fails validation is skipped and reported.
    ///
    /// Required members: `EPOCH`, `MEAN_MOTION`, `ECCENTRICITY`, `INCLINATION`, `RA_OF_ASC_NODE`,
    /// `ARG_OF_PERICENTER`, `MEAN_ANOMALY`, `NORAD_CAT_ID`, `BSTAR`. Optional: `OBJECT_NAME`, `OBJECT_ID`,
    /// `CLASSIFICATION_TYPE` (default `U`), `EPHEMERIS_TYPE`, `ELEMENT_SET_NO`, `REV_AT_EPOCH`, `MEAN_MOTION_DOT`,
    /// `MEAN_MOTION_DDOT` (default 0). Other members are ignored. `EPOCH` is an ISO 8601 UTC time such as
    /// `2026-10-18T03:28:15.076416` (a trailing `Z` is accepted).
    ///
    /// - Throws: `ElementSetError.inputTooLarge` if the text is longer than `maximumInputCharacters`;
    ///   `ElementSetError.malformedJSON` if the text is not JSON or the top level is neither array nor object.
    public static func parseJson(_ json: String) throws -> ElementSetBatch {
        guard json.utf16.count <= maximumInputCharacters else { throw ElementSetError.inputTooLarge(limit: maximumInputCharacters) }
        return try parseJson(Data(json.utf8))
    }

    /// `parseJson(_:)` for a download that has not been decoded to text yet (UTF-8 bytes).
    public static func parseJson(_ bytes: Data) throws -> ElementSetBatch {
        guard bytes.count <= maximumInputCharacters else { throw ElementSetError.inputTooLarge(limit: maximumInputCharacters) }
        var first: UInt8?
        for byte in bytes {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
            first = byte
            break
        }
        let decoder = JSONDecoder()
        var records: [OmmRecord?]
        if first == 0x5B {  // [
            do {
                records = try decoder.decode([LossyRecord].self, from: bytes).map(\.record)
            } catch {
                throw ElementSetError.malformedJSON(reason: String(describing: error).prefix(120).description)
            }
        } else if first == 0x7B {  // {
            do {
                records = [try decoder.decode(OmmRecord.self, from: bytes)]
            } catch {
                throw ElementSetError.malformedJSON(reason: String(describing: error).prefix(120).description)
            }
        } else if first == nil {
            throw ElementSetError.malformedJSON(reason: "the input is empty")
        } else {
            throw ElementSetError.malformedJSON(reason: "the top level is neither an array nor an object")
        }

        var elements: [OrbitalElements] = []
        var skipped: [SkippedElementSet] = []
        var skippedCount = 0
        var recordIndex = 0
        for record in records {
            if recordIndex >= maximumRecordCount { break }
            var name: String?
            do {
                guard let record else { throw ElementSetError.invalidRecord(reason: "the element is not an object") }
                if case .text(let text)? = record.values["OBJECT_NAME"] { name = text }
                elements.append(try ommRecord(record))
            } catch let error as ElementSetError {
                skippedCount += 1
                if skipped.count < maximumReportedSkips {
                    skipped.append(SkippedElementSet(index: recordIndex, name: name.flatMap { cleanName($0) }, error: error))
                }
            } catch {
                skippedCount += 1
            }
            recordIndex += 1
        }
        return ElementSetBatch(elements: elements, skipped: skipped, skippedCount: skippedCount)
    }

    /// One JSON member value as the OMM reader sees it.
    fileprivate enum OmmValue {
        case number(Double)
        case text(String)
        /// A boolean, array or object; the text describes it for messages.
        case other(String)
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Consumes any JSON value.
    private struct Ignored: Decodable {
        init(from decoder: Decoder) throws {}
    }

    fileprivate struct OmmValueBox: Decodable {
        let value: OmmValue

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = .number(number)
            } else if let text = try? container.decode(String.self) {
                value = .text(text)
            } else if let flag = try? container.decode(Bool.self) {
                value = .other(flag ? "true" : "false")
            } else if (try? container.decode([Ignored].self)) != nil {
                value = .other("<array>")
            } else if (try? container.decode([String: Ignored].self)) != nil {
                value = .other("<object>")
            } else {
                value = .other("<unreadable>")
            }
        }
    }

    fileprivate struct OmmRecord: Decodable {
        var values: [String: OmmValue] = [:]

        static let keys = [
            "OBJECT_NAME", "OBJECT_ID", "EPOCH", "MEAN_MOTION", "ECCENTRICITY", "INCLINATION", "RA_OF_ASC_NODE",
            "ARG_OF_PERICENTER", "MEAN_ANOMALY", "EPHEMERIS_TYPE", "CLASSIFICATION_TYPE", "NORAD_CAT_ID",
            "ELEMENT_SET_NO", "REV_AT_EPOCH", "BSTAR", "MEAN_MOTION_DOT", "MEAN_MOTION_DDOT",
        ]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            for key in Self.keys {
                guard let codingKey = DynamicKey(stringValue: key) else { continue }
                if let box = try container.decodeIfPresent(OmmValueBox.self, forKey: codingKey) {
                    values[key] = box.value
                }
            }
        }
    }

    /// An array element that never fails to decode: `record` is `nil` for an element of the wrong shape.
    private struct LossyRecord: Decodable {
        let record: OmmRecord?

        init(from decoder: Decoder) throws {
            record = try? OmmRecord(from: decoder)
        }
    }

    private static func ommRecord(_ record: OmmRecord) throws -> OrbitalElements {
        let epoch = try isoEpoch(requiredText(record, "EPOCH"))
        let classificationText = try optionalText(record, "CLASSIFICATION_TYPE")
        let classification: Character
        if let classificationText {
            let scalars = Array(classificationText.unicodeScalars)
            guard scalars.count == 1 else {
                throw ElementSetError.invalidField(field: "CLASSIFICATION_TYPE", text: String(classificationText.prefix(40)))
            }
            classification = Character(scalars[0])
        } else {
            classification = "U"
        }
        return try OrbitalElements.make(
            name: optionalText(record, "OBJECT_NAME"),
            objectId: optionalText(record, "OBJECT_ID"),
            catalogNumber: integerValue(record, "NORAD_CAT_ID", required: true, defaultValue: 0),
            classification: classification,
            year: epoch.year,
            month: epoch.month,
            day: epoch.day,
            hour: epoch.hour,
            minute: epoch.minute,
            second: epoch.second,
            meanMotion: numberValue(record, "MEAN_MOTION", required: true),
            eccentricity: numberValue(record, "ECCENTRICITY", required: true),
            inclination: numberValue(record, "INCLINATION", required: true),
            rightAscensionOfAscendingNode: numberValue(record, "RA_OF_ASC_NODE", required: true),
            argumentOfPericenter: numberValue(record, "ARG_OF_PERICENTER", required: true),
            meanAnomaly: numberValue(record, "MEAN_ANOMALY", required: true),
            ephemerisType: integerValue(record, "EPHEMERIS_TYPE", required: false, defaultValue: 0),
            elementSetNumber: integerValue(record, "ELEMENT_SET_NO", required: false, defaultValue: 0),
            revolutionNumberAtEpoch: integerValue(record, "REV_AT_EPOCH", required: false, defaultValue: 0),
            bstar: numberValue(record, "BSTAR", required: true),
            meanMotionDot: numberValue(record, "MEAN_MOTION_DOT", required: false),
            meanMotionDdot: numberValue(record, "MEAN_MOTION_DDOT", required: false)
        )
    }

    /// The member as a finite number: a JSON number or a numeric string; `nil` when absent or `null`.
    private static func numberOrNil(_ record: OmmRecord, _ key: String) throws -> Double? {
        guard let member = record.values[key] else { return nil }
        switch member {
        case .other(let description):
            throw ElementSetError.invalidField(field: key, text: description)
        case .text(let text):
            guard let value = strictNumber(text), value.isFinite else {
                throw ElementSetError.invalidField(field: key, text: String(text.prefix(40)))
            }
            return value
        case .number(let value):
            guard value.isFinite else { throw ElementSetError.invalidField(field: key, text: String(value)) }
            return value
        }
    }

    private static func numberValue(_ record: OmmRecord, _ key: String, required: Bool) throws -> Double {
        if let value = try numberOrNil(record, key) { return value }
        if required { throw ElementSetError.missingField(field: key) }
        return 0
    }

    private static func integerValue(_ record: OmmRecord, _ key: String, required: Bool, defaultValue: Int) throws -> Int {
        guard let value = try numberOrNil(record, key) else {
            if required { throw ElementSetError.missingField(field: key) }
            return defaultValue
        }
        if value != value.rounded(.down) || value < -2_147_483_648.0 || value > 2_147_483_647.0 {
            throw ElementSetError.valueOutOfRange(field: key, value: value)
        }
        return Int(value)
    }

    private static func requiredText(_ record: OmmRecord, _ key: String) throws -> String {
        guard let text = try optionalText(record, key) else { throw ElementSetError.missingField(field: key) }
        return text
    }

    private static func optionalText(_ record: OmmRecord, _ key: String) throws -> String? {
        guard let member = record.values[key] else { return nil }
        switch member {
        case .text(let text):
            return text
        case .number(let value):
            throw ElementSetError.invalidField(field: key, text: String(describing: value).prefix(40).description)
        case .other(let description):
            throw ElementSetError.invalidField(field: key, text: description)
        }
    }

    /// The components of an ISO 8601 UTC epoch.
    private struct EpochComponents {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Double
    }

    /// Reads `YYYY-MM-DDTHH:MM:SS[.f...]` with an optional `Z` or `+00:00` suffix (a space may replace the `T`).
    private static func isoEpoch(_ text: String) throws -> EpochComponents {
        let invalid = ElementSetError.invalidField(field: "EPOCH", text: String(text.prefix(40)))
        let scalars = Array(text.unicodeScalars)
        var end = scalars.count
        if end > 0 && scalars[end - 1] == "Z" {
            end -= 1
        } else if end >= 6 {
            let tail = String(String.UnicodeScalarView(scalars[(end - 6)..<end]))
            if tail == "+00:00" || tail == "-00:00" { end -= 6 }
        }
        guard end >= 19 else { throw invalid }
        guard scalars[4] == "-", scalars[7] == "-", scalars[10] == "T" || scalars[10] == " ",
              scalars[13] == ":", scalars[16] == ":" else { throw invalid }
        guard let year = fixedDigits(scalars, 0, 4), let month = fixedDigits(scalars, 5, 2),
              let day = fixedDigits(scalars, 8, 2), let hour = fixedDigits(scalars, 11, 2),
              let minute = fixedDigits(scalars, 14, 2), let wholeSecond = fixedDigits(scalars, 17, 2) else { throw invalid }
        var second = Double(wholeSecond)
        if end > 19 {
            guard scalars[19] == ".", end != 20, end - 20 <= 15 else { throw invalid }
            let fractionText = String(String.UnicodeScalarView(scalars[20..<end]))
            guard isDigits(fractionText), let fraction = Double("0.\(fractionText)") else { throw invalid }
            second += fraction
        }
        return EpochComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    private static func fixedDigits(_ scalars: [Unicode.Scalar], _ start: Int, _ count: Int) -> Int? {
        var value = 0
        for offset in 0..<count {
            guard let digit = digitValue(scalars[start + offset]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// A number in JSON grammar (`-12.5e3`), as a string member may hold it; `nil` if the text is anything else.
    private static func strictNumber(_ text: String) -> Double? {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        let length = scalars.count
        if index < length && scalars[index] == "-" { index += 1 }
        let integerStart = index
        while index < length && digitValue(scalars[index]) != nil { index += 1 }
        if index == integerStart { return nil }
        if index - integerStart > 1 && scalars[integerStart] == "0" { return nil }
        if index < length && scalars[index] == "." {
            index += 1
            let fractionStart = index
            while index < length && digitValue(scalars[index]) != nil { index += 1 }
            if index == fractionStart { return nil }
        }
        if index < length && (scalars[index] == "e" || scalars[index] == "E") {
            index += 1
            if index < length && (scalars[index] == "+" || scalars[index] == "-") { index += 1 }
            let exponentStart = index
            while index < length && digitValue(scalars[index]) != nil { index += 1 }
            if index == exponentStart { return nil }
        }
        if index != length { return nil }
        return Double(text)
    }

    // MARK: Two-line fields

    private static let firstLineSeparators = [1, 8, 17, 32, 43, 52, 61, 63]
    private static let secondLineSeparators = [1, 7, 16, 25, 33, 42, 51]

    private static func checkSeparators(_ line: [Unicode.Scalar], _ columns: [Int]) throws {
        for column in columns where line[column] != " " {
            throw ElementSetError.invalidField(field: "separator", text: substring(line, max(0, column - 3), column + 4))
        }
    }

    private static func checkChecksum(_ line: [Unicode.Scalar], number: Int) throws {
        let last = line[lineLength - 1]
        guard let found = digitValue(last) else {
            throw ElementSetError.invalidField(field: "checksum", text: String(Character(last)))
        }
        let expected = checksum(line)
        if expected != found { throw ElementSetError.checksumMismatch(line: number, expected: expected, found: found) }
    }

    /// A decimal in TLE spelling: optional sign, digits with an optional point, e.g. `51.6328`, `-.00000084`.
    private static func decimal(_ field: String, name: String) throws -> Double {
        let text = Array(field.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        var index = 0
        var negative = false
        if index < text.count && (text[index] == "+" || text[index] == "-") {
            negative = text[index] == "-"
            index += 1
        }
        let start = index
        var digits = 0
        var points = 0
        while index < text.count {
            let scalar = text[index]
            if digitValue(scalar) != nil {
                digits += 1
            } else if scalar == "." {
                points += 1
            } else {
                break
            }
            index += 1
        }
        guard index == text.count, digits > 0, points <= 1 else { throw ElementSetError.invalidField(field: name, text: field) }
        var body = String(String.UnicodeScalarView(text[start...]))
        if body.hasPrefix(".") { body = "0" + body }
        if body.hasSuffix(".") { body += "0" }
        guard let magnitude = Double(body) else { throw ElementSetError.invalidField(field: name, text: field) }
        return negative ? -magnitude : magnitude
    }

    /// `±ddddd±e`: five digits with an implied leading point and a power of ten, e.g. ` 14456-3`. Blank is 0.
    private static func impliedExponent(_ field: String, name: String) throws -> Double {
        if field.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) { return 0 }
        let scalars = Array(field.unicodeScalars)
        guard scalars.count == 8 else { throw ElementSetError.invalidField(field: name, text: field) }
        let sign = scalars[0]
        guard sign == " " || sign == "+" || sign == "-" else { throw ElementSetError.invalidField(field: name, text: field) }
        let digits = substring(scalars, 1, 6)
        guard isDigits(digits) else { throw ElementSetError.invalidField(field: name, text: field) }
        let exponentSign = scalars[6]
        guard exponentSign == "+" || exponentSign == "-" || exponentSign == " " else {
            throw ElementSetError.invalidField(field: name, text: field)
        }
        guard let exponentDigit = digitValue(scalars[7]) else { throw ElementSetError.invalidField(field: name, text: field) }
        let exponent = exponentDigit * (exponentSign == "-" ? -1 : 1)
        let mantissa = Double(Int(digits) ?? 0) / 1.0e5
        let value = mantissa * pow(10.0, Double(exponent))
        return sign == "-" ? -value : value
    }

    /// A non-negative integer field that may be blank (then 0).
    private static func integer(_ field: String, name: String) throws -> Int {
        let text = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 0 }
        guard isDigits(text), let value = Int(text) else { throw ElementSetError.invalidField(field: name, text: field) }
        return value
    }

    private static func digit(_ scalar: Unicode.Scalar, name: String) throws -> Int {
        guard let value = digitValue(scalar) else {
            throw ElementSetError.invalidField(field: name, text: String(Character(scalar)))
        }
        return value
    }

    /// The catalog number of five characters: digits, or Alpha-5 (a letter, without I and O, and four digits).
    private static func catalogNumberOf(_ field: String) throws -> Int {
        let scalars = Array(field.unicodeScalars)
        var start = 0
        while start < scalars.count && scalars[start] == " " { start += 1 }
        let text = Array(scalars[start...])
        guard !text.isEmpty else { throw ElementSetError.invalidField(field: "NORAD_CAT_ID", text: field) }
        let first = text[0]
        if digitValue(first) != nil {
            guard isDigits(String(String.UnicodeScalarView(text))), let value = Int(String(String.UnicodeScalarView(text))) else {
                throw ElementSetError.invalidField(field: "NORAD_CAT_ID", text: field)
            }
            return value
        }
        if text.count == 5, first.value >= 65 && first.value <= 90, first != "I", first != "O",
           isDigits(String(String.UnicodeScalarView(text[1...]))) {
            var value = Int(first.value) - 65 + 10
            if first.value > 73 { value -= 1 }
            if first.value > 79 { value -= 1 }
            return value * 10_000 + (Int(String(String.UnicodeScalarView(text[1...]))) ?? 0)
        }
        throw ElementSetError.invalidField(field: "NORAD_CAT_ID", text: field)
    }

    /// `98067A  ` becomes `1998-067A`; a blank field is `nil`; anything else is kept as written.
    private static func designator(_ field: String) -> String? {
        let text = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let scalars = Array(text.unicodeScalars)
        if scalars.count >= 6 && scalars.count <= 8 && isDigits(substring(scalars, 0, 5))
            && scalars[5...].allSatisfy({ $0.value >= 65 && $0.value <= 90 }) {
            let shortYear = Int(substring(scalars, 0, 2)) ?? 0
            let year = shortYear < 57 ? shortYear + 2000 : shortYear + 1900
            return "\(year)-\(substring(scalars, 2, 5))\(substring(scalars, 5, scalars.count))"
        }
        return text
    }

    // MARK: Text helpers

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        scalar.value >= 48 && scalar.value <= 57 ? Int(scalar.value) - 48 : nil
    }

    private static func isDigits(_ text: String) -> Bool {
        if text.isEmpty { return false }
        for scalar in text.unicodeScalars where digitValue(scalar) == nil { return false }
        return true
    }

    private static func substring(_ scalars: [Unicode.Scalar], _ start: Int, _ end: Int) -> String {
        String(String.UnicodeScalarView(scalars[start..<end]))
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    private static func trimTrailing(_ line: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var end = line.count
        while end > 0 && (line[end - 1] == " " || line[end - 1] == "\r" || line[end - 1] == "\n" || line[end - 1] == "\t") {
            end -= 1
        }
        return end == line.count ? line : Array(line[0..<end])
    }

    /// A name line of the 3LE format; the Space-Track "0 " prefix is removed.
    private static func cleanName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.hasPrefix("0 ") ? String(trimmed.dropFirst(2)) : trimmed
        return OrbitalElements.cleanText(text, maximumLength: OrbitalElements.maximumNameLength)
    }

    private static func splitLines(_ text: String) -> [[Unicode.Scalar]] {
        var lines: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines.append(trimTrailing(current))
                current = []
            } else {
                current.append(scalar)
            }
        }
        lines.append(trimTrailing(current))
        return lines
    }
}

import Foundation

/// A value of a JSON document, as `JSONReader` reads it.
indirect enum JSONValue: Hashable {
    /// An object; a repeated name keeps its last value.
    case object([String: JSONValue])
    /// An array.
    case array([JSONValue])
    /// A string.
    case string(String)
    /// A number, as the nearest `Double`.
    case number(Double)
    /// `true` or `false`.
    case bool(Bool)
    /// `null`.
    case null
}

/// Why `JSONReader` refused a document.
enum JSONFailure: Hashable {
    /// The text is not JSON (RFC 8259) or contains a number that is not finite or a string with a lone surrogate.
    case invalid
    /// Objects and arrays are nested deeper than `JSONReader.maximumNesting`.
    case tooDeep
}

/// Thrown by `JSONReader` with the `failure` that stopped it.
struct JSONReaderError: Error, Hashable {
    let failure: JSONFailure
}

/// A strict JSON reader (RFC 8259) for the small answers of web services; the Kotlin twin reads the same grammar, so
/// both languages accept and refuse the same documents. No comments, no trailing commas, no single quotes, no `NaN`,
/// no leading zeros, no byte-order mark; only space, tab, line feed and carriage return are whitespace; raw control
/// characters are not allowed in strings; `\u` escapes must pair their surrogates.
struct JSONReader {
    /// The deepest accepted nesting of objects and arrays, 32.
    static let maximumNesting = 32

    private let bytes: [UInt8]
    private var position = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// Reads the whole text as one JSON value.
    mutating func readDocument() throws -> JSONValue {
        skipWhitespace()
        let value = try readValue(depth: 0)
        skipWhitespace()
        if position != bytes.count { throw JSONReaderError(failure: .invalid) }
        return value
    }

    private func invalid() -> JSONReaderError { JSONReaderError(failure: .invalid) }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { position += 1 } else { break }
        }
    }

    private mutating func readValue(depth: Int) throws -> JSONValue {
        guard position < bytes.count else { throw invalid() }
        switch bytes[position] {
        case 0x7B: return try readObject(depth: depth + 1)
        case 0x5B: return try readArray(depth: depth + 1)
        case 0x22: return .string(try readString())
        case 0x74: return try readLiteral("true", .bool(true))
        case 0x66: return try readLiteral("false", .bool(false))
        case 0x6E: return try readLiteral("null", .null)
        default: return try readNumber()
        }
    }

    private mutating func readLiteral(_ word: String, _ value: JSONValue) throws -> JSONValue {
        let expected = Array(word.utf8)
        guard position + expected.count <= bytes.count, Array(bytes[position..<(position + expected.count)]) == expected else {
            throw invalid()
        }
        position += expected.count
        return value
    }

    private mutating func readObject(depth: Int) throws -> JSONValue {
        if depth > Self.maximumNesting { throw JSONReaderError(failure: .tooDeep) }
        position += 1
        var members = [String: JSONValue]()
        skipWhitespace()
        if position < bytes.count && bytes[position] == 0x7D {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x22 else { throw invalid() }
            let key = try readString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x3A else { throw invalid() }
            position += 1
            skipWhitespace()
            members[key] = try readValue(depth: depth)
            skipWhitespace()
            guard position < bytes.count else { throw invalid() }
            let separator = bytes[position]
            position += 1
            if separator == 0x7D { return .object(members) }
            if separator != 0x2C { throw invalid() }
        }
    }

    private mutating func readArray(depth: Int) throws -> JSONValue {
        if depth > Self.maximumNesting { throw JSONReaderError(failure: .tooDeep) }
        position += 1
        var items = [JSONValue]()
        skipWhitespace()
        if position < bytes.count && bytes[position] == 0x5D {
            position += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try readValue(depth: depth))
            skipWhitespace()
            guard position < bytes.count else { throw invalid() }
            let separator = bytes[position]
            position += 1
            if separator == 0x5D { return .array(items) }
            if separator != 0x2C { throw invalid() }
        }
    }

    private mutating func readString() throws -> String {
        position += 1
        var result = [UInt8]()
        while true {
            guard position < bytes.count else { throw invalid() }
            let byte = bytes[position]
            position += 1
            if byte == 0x22 { return String(decoding: result, as: UTF8.self) }
            if byte < 0x20 { throw invalid() }
            if byte != 0x5C {
                result.append(byte)
                continue
            }
            guard position < bytes.count else { throw invalid() }
            let escape = bytes[position]
            position += 1
            switch escape {
            case 0x22: result.append(0x22)
            case 0x5C: result.append(0x5C)
            case 0x2F: result.append(0x2F)
            case 0x62: result.append(0x08)
            case 0x66: result.append(0x0C)
            case 0x6E: result.append(0x0A)
            case 0x72: result.append(0x0D)
            case 0x74: result.append(0x09)
            case 0x75:
                let unit = try readHexUnit()
                var value = unit
                if unit >= 0xD800 && unit <= 0xDBFF {
                    guard position + 1 < bytes.count, bytes[position] == 0x5C, bytes[position + 1] == 0x75 else { throw invalid() }
                    position += 2
                    let low = try readHexUnit()
                    guard low >= 0xDC00 && low <= 0xDFFF else { throw invalid() }
                    value = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                } else if unit >= 0xDC00 && unit <= 0xDFFF {
                    throw invalid()
                }
                guard let scalar = Unicode.Scalar(UInt32(value)) else { throw invalid() }
                result.append(contentsOf: Array(String(Character(scalar)).utf8))
            default: throw invalid()
            }
        }
    }

    private mutating func readHexUnit() throws -> Int {
        guard position + 4 <= bytes.count else { throw invalid() }
        var unit = 0
        for offset in 0..<4 {
            let byte = bytes[position + offset]
            let digit: Int
            switch byte {
            case 0x30...0x39: digit = Int(byte) - 0x30
            case 0x41...0x46: digit = Int(byte) - 0x41 + 10
            case 0x61...0x66: digit = Int(byte) - 0x61 + 10
            default: throw invalid()
            }
            unit = unit * 16 + digit
        }
        position += 4
        return unit
    }

    private mutating func readNumber() throws -> JSONValue {
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        let start = position
        if position < bytes.count && bytes[position] == 0x2D { position += 1 }
        guard position < bytes.count else { throw invalid() }
        if bytes[position] == 0x30 {
            position += 1
        } else if bytes[position] >= 0x31 && bytes[position] <= 0x39 {
            while position < bytes.count && isDigit(bytes[position]) { position += 1 }
        } else {
            throw invalid()
        }
        if position < bytes.count && bytes[position] == 0x2E {
            position += 1
            let digitsStart = position
            while position < bytes.count && isDigit(bytes[position]) { position += 1 }
            if position == digitsStart { throw invalid() }
        }
        if position < bytes.count && (bytes[position] == 0x65 || bytes[position] == 0x45) {
            position += 1
            if position < bytes.count && (bytes[position] == 0x2B || bytes[position] == 0x2D) { position += 1 }
            let digitsStart = position
            while position < bytes.count && isDigit(bytes[position]) { position += 1 }
            if position == digitsStart { throw invalid() }
        }
        guard let value = Double(String(decoding: bytes[start..<position], as: UTF8.self)), value.isFinite else {
            throw invalid()
        }
        return .number(value)
    }
}

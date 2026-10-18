import Foundation

/// A parsed JSON document. The engine has its own strict parser (RFC 8259 grammar, bounded size and depth) so that
/// Alpaca replies are validated identically in both languages.
public enum MountJSON: Hashable, Sendable {
    /// `null`.
    case null
    /// `true` or `false`.
    case bool(Bool)
    /// A finite number.
    case number(Double)
    /// A string.
    case text(String)
    /// An array.
    case array([MountJSON])
    /// An object; with duplicate keys the last one wins.
    case object([String: MountJSON])

    /// Documents longer than this many UTF-16 units are rejected.
    public static let maximumLength = 262_144
    /// Nesting deeper than this is rejected.
    public static let maximumDepth = 32

    /// The member `name` of an object (exact match first, then ignoring ASCII case), or nil.
    public func field(_ name: String) -> MountJSON? {
        guard case let .object(fields) = self else { return nil }
        if let exact = fields[name] { return exact }
        let wanted = MountText.asciiLowercased(name)
        for (key, value) in fields where MountText.asciiLowercased(key) == wanted { return value }
        return nil
    }

    /// Parses `text`; throws `MountError.malformedReply` for anything that is not exactly one JSON value.
    public static func parse(_ text: String) throws -> MountJSON {
        if text.utf16.count > maximumLength { throw MountError.malformedReply(detail: "JSON document too long") }
        var reader = MountJSONReader(text)
        return try reader.readDocument()
    }
}

/// ASCII helpers shared by the protocol layers.
enum MountText {
    static func asciiLowercased(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90, let lowered = Unicode.Scalar(scalar.value + 32) {
                result.append(lowered)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// Latin-1 view of bytes: every byte becomes the character with the same code.
    static func latin1(_ bytes: [UInt8]) -> String {
        var result = String.UnicodeScalarView()
        for byte in bytes { result.append(Unicode.Scalar(byte)) }
        return String(result)
    }

    /// One byte per character of `text` (character codes above 255 are cut to their low byte).
    static func latin1Bytes(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
    }

    /// The ASCII bytes of `text`; characters above 0x7E are replaced by '?'.
    static func ascii(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { $0.value >= 0x20 && $0.value <= 0x7E ? UInt8($0.value) : UInt8(ascii: "?") }
    }

    /// `text` without control characters, cut to `limit` characters.
    static func sanitized(_ text: String, limit: Int) -> String {
        var result = String.UnicodeScalarView()
        var count = 0
        for scalar in text.unicodeScalars {
            if count >= limit { break }
            if scalar.value >= 0x20 && scalar.value != 0x7F {
                result.append(scalar)
                count += 1
            }
        }
        return String(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MountJSONReader {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) { scalars = Array(text.unicodeScalars) }

    mutating func readDocument() throws -> MountJSON {
        skipWhitespace()
        let value = try readValue(depth: 0)
        skipWhitespace()
        if index != scalars.count { throw fail("trailing characters") }
        return value
    }

    private func fail(_ reason: String) -> MountError { MountError.malformedReply(detail: "JSON: \(reason)") }

    private mutating func skipWhitespace() {
        while index < scalars.count {
            let value = scalars[index].value
            if value == 0x20 || value == 0x09 || value == 0x0A || value == 0x0D { index += 1 } else { break }
        }
    }

    private mutating func readValue(depth: Int) throws -> MountJSON {
        if depth > MountJSON.maximumDepth { throw fail("nesting too deep") }
        if index >= scalars.count { throw fail("unexpected end") }
        let scalar = scalars[index]
        switch scalar {
        case "{": return try readObject(depth: depth)
        case "[": return try readArray(depth: depth)
        case "\"": return .text(try readString())
        case "t": return try readLiteral("true", .bool(true))
        case "f": return try readLiteral("false", .bool(false))
        case "n": return try readLiteral("null", .null)
        default:
            if scalar == "-" || (scalar.value >= 0x30 && scalar.value <= 0x39) { return try readNumber() }
            throw fail("unexpected character")
        }
    }

    private mutating func readLiteral(_ word: String, _ value: MountJSON) throws -> MountJSON {
        let expected = Array(word.unicodeScalars)
        guard index + expected.count <= scalars.count, Array(scalars[index ..< index + expected.count]) == expected else {
            throw fail("invalid literal")
        }
        index += expected.count
        return value
    }

    private mutating func readObject(depth: Int) throws -> MountJSON {
        index += 1
        var fields: [String: MountJSON] = [:]
        skipWhitespace()
        if index < scalars.count && scalars[index] == "}" {
            index += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            if index >= scalars.count || scalars[index] != "\"" { throw fail("object key expected") }
            let key = try readString()
            skipWhitespace()
            if index >= scalars.count || scalars[index] != ":" { throw fail("':' expected") }
            index += 1
            skipWhitespace()
            fields[key] = try readValue(depth: depth + 1)
            skipWhitespace()
            if index >= scalars.count { throw fail("unexpected end") }
            let scalar = scalars[index]
            index += 1
            if scalar == "}" { return .object(fields) }
            if scalar != "," { throw fail("',' or '}' expected") }
        }
    }

    private mutating func readArray(depth: Int) throws -> MountJSON {
        index += 1
        var items: [MountJSON] = []
        skipWhitespace()
        if index < scalars.count && scalars[index] == "]" {
            index += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try readValue(depth: depth + 1))
            skipWhitespace()
            if index >= scalars.count { throw fail("unexpected end") }
            let scalar = scalars[index]
            index += 1
            if scalar == "]" { return .array(items) }
            if scalar != "," { throw fail("',' or ']' expected") }
        }
    }

    private mutating func readString() throws -> String {
        index += 1
        var result = String.UnicodeScalarView()
        while true {
            if index >= scalars.count { throw fail("unterminated string") }
            let scalar = scalars[index]
            index += 1
            if scalar == "\"" { return String(result) }
            if scalar == "\\" {
                result.append(contentsOf: try readEscape().unicodeScalars)
            } else if scalar.value < 0x20 {
                throw fail("control character in string")
            } else {
                result.append(scalar)
            }
        }
    }

    private mutating func readEscape() throws -> String {
        if index >= scalars.count { throw fail("unterminated escape") }
        let scalar = scalars[index]
        index += 1
        switch scalar {
        case "\"": return "\""
        case "\\": return "\\"
        case "/": return "/"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "u":
            let unit = try readHex4()
            if unit >= 0xD800 && unit <= 0xDBFF {
                guard index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" else {
                    throw fail("invalid surrogate pair")
                }
                index += 2
                let low = try readHex4()
                guard low >= 0xDC00 && low <= 0xDFFF,
                      let combined = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)) else {
                    throw fail("invalid surrogate pair")
                }
                return String(Character(combined))
            }
            if unit >= 0xDC00 && unit <= 0xDFFF { throw fail("invalid surrogate pair") }
            guard let single = Unicode.Scalar(unit) else { throw fail("invalid \\u escape") }
            return String(Character(single))
        default:
            throw fail("invalid escape")
        }
    }

    private mutating func readHex4() throws -> UInt32 {
        guard index + 4 <= scalars.count else { throw fail("invalid \\u escape") }
        var value: UInt32 = 0
        for offset in 0 ..< 4 {
            let code = scalars[index + offset].value
            let digit: UInt32
            switch code {
            case 0x30 ... 0x39: digit = code - 0x30
            case 0x41 ... 0x46: digit = code - 0x41 + 10
            case 0x61 ... 0x66: digit = code - 0x61 + 10
            default: throw fail("invalid \\u escape")
            }
            value = value * 16 + digit
        }
        index += 4
        return value
    }

    private func isDigit(_ at: Int) -> Bool { at < scalars.count && scalars[at].value >= 0x30 && scalars[at].value <= 0x39 }

    private mutating func readNumber() throws -> MountJSON {
        let start = index
        if scalars[index] == "-" { index += 1 }
        if index >= scalars.count { throw fail("invalid number") }
        if scalars[index] == "0" {
            index += 1
        } else if scalars[index].value >= 0x31 && scalars[index].value <= 0x39 {
            while isDigit(index) { index += 1 }
        } else {
            throw fail("invalid number")
        }
        if index < scalars.count && scalars[index] == "." {
            index += 1
            let digitsStart = index
            while isDigit(index) { index += 1 }
            if index == digitsStart { throw fail("invalid number") }
        }
        if index < scalars.count && (scalars[index] == "e" || scalars[index] == "E") {
            index += 1
            if index < scalars.count && (scalars[index] == "+" || scalars[index] == "-") { index += 1 }
            let digitsStart = index
            while isDigit(index) { index += 1 }
            if index == digitsStart { throw fail("invalid number") }
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: scalars[start ..< index])
        guard let value = Double(String(text)) else { throw fail("invalid number") }
        if !value.isFinite { throw fail("number out of range") }
        return .number(value)
    }
}

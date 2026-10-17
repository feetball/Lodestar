/// Parser for sexagesimal and decimal angle text typed or pasted by a person.
///
/// The text is split into tokens (numbers, signs, unit marks, hemisphere letters and colons, see
/// `AngleTextParser+Lexing.swift`) and then matched against one grammar:
///
///     value  = [hemisphere] [sign] field { separator field } [hemisphere]
///     field  = number [unit]
///     unit   = h | d | ° | m | ′ | s | ″          (in that order, one per field)
///
/// Anything the grammar does not cover, including every ambiguous input, is rejected with `nil`.
/// The parser never traps: the input is length-capped, only ASCII digits are read, numbers are
/// converted from sanitised digit strings, and all arithmetic is on finite `Double`s.
enum AngleTextParser {
    /// The kind of value being read, which decides the letters, units and range that are valid.
    enum Quantity {
        /// Hours of right ascension in [0, 24); `n`, `e` and `w` are not accepted.
        case rightAscension
        /// Declination or latitude in [-90, 90]; hemisphere letters `n` and `s`.
        case declination
        /// Longitude in (-180, 180]; hemisphere letters `e` and `w`.
        case longitude
    }

    /// Longest accepted input, in Unicode scalars.
    static let maximumLength = 64

    // MARK: Tokens

    /// What a unit mark stands for, by position within the value.
    enum Mark: Equatable {
        /// `h`: hours of time. Only valid on the first field of a right ascension.
        case hour
        /// `d`, `°`: degrees. On a right ascension they request the degrees form.
        case degree
        /// `m`, `′`: minutes of time or arc.
        case minute
        /// `s`, `″`: seconds of time or arc.
        case second
    }

    /// A unit mark and whether it was written as a letter (`d`, `m`, `s`) or as a symbol.
    struct UnitMark: Equatable {
        let kind: Mark
        let isLetter: Bool
    }

    struct Token {
        enum Kind: Equatable {
            /// An unsigned decimal number; `isWhole` is false when it had a decimal mark.
            case number(value: Double, isWhole: Bool)
            case sign(isNegative: Bool)
            case colon
            case mark(UnitMark)
            case hemisphere(isNegative: Bool)
            /// The letter `s` in a declination or latitude, where it is either the seconds unit
            /// or the southern hemisphere.
            case southOrSeconds
        }

        let kind: Kind
        /// Whether whitespace separated this token from the previous one.
        let followsSpace: Bool
    }

    /// One parsed `number [unit]` field.
    private struct Field {
        let value: Double
        let isWhole: Bool
        let mark: UnitMark?
    }

    /// A cursor over the token list.
    private struct TokenReader {
        private let tokens: [Token]
        private var position = 0

        init(_ tokens: [Token]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { position >= tokens.count }

        var upcoming: Token? { isAtEnd ? nil : tokens[position] }

        var upcomingIsNumber: Bool {
            if case .number? = upcoming?.kind { return true }
            return false
        }

        /// Whether the next token is an "s" written directly against the token before it.
        var upcomingIsAttachedSouthOrSeconds: Bool {
            guard let token = upcoming, token.kind == .southOrSeconds else { return false }
            return !token.followsSpace
        }

        /// Consumes a hemisphere letter and returns whether it is the negative one (south or west).
        mutating func takeHemisphere() -> Bool? {
            switch upcoming?.kind {
            case .hemisphere(let isNegative)?:
                position += 1
                return isNegative
            case .southOrSeconds?:
                position += 1
                return true
            default:
                return nil
            }
        }

        /// Consumes a sign and returns whether it is a minus.
        mutating func takeSign() -> Bool? {
            guard case .sign(let isNegative)? = upcoming?.kind else { return nil }
            position += 1
            return isNegative
        }

        mutating func takeNumber() -> (value: Double, isWhole: Bool)? {
            guard case .number(let value, let isWhole)? = upcoming?.kind else { return nil }
            position += 1
            return (value, isWhole)
        }

        mutating func takeMark() -> UnitMark? {
            guard case .mark(let mark)? = upcoming?.kind else { return nil }
            position += 1
            return mark
        }

        mutating func takeColon() -> Bool {
            guard upcoming?.kind == .colon else { return false }
            position += 1
            return true
        }

        /// Consumes the upcoming token, which the caller has already inspected.
        mutating func skip() {
            position += 1
        }
    }

    // MARK: Parsing

    /// Parses `text` as the given quantity, returning hours for right ascension and degrees
    /// otherwise, or `nil` when the text is not valid.
    static func parse(_ text: String, as quantity: Quantity) -> Double? {
        let scalars = Array(text.unicodeScalars.prefix(maximumLength + 1))
        guard scalars.count <= maximumLength,
              let tokens = tokenize(scalars, for: quantity) else { return nil }

        var reader = TokenReader(tokens)
        let leadingHemisphere = reader.takeHemisphere()
        let explicitSign = reader.takeSign()
        guard let fields = readFields(from: &reader) else { return nil }
        let trailingHemisphere = reader.takeHemisphere()

        // A hemisphere letter may lead or trail the value, not both.
        guard reader.isAtEnd,
              leadingHemisphere == nil || trailingHemisphere == nil,
              let magnitude = combinedMagnitude(of: fields),
              let isNegative = mergedSign(hemisphere: leadingHemisphere ?? trailingHemisphere, sign: explicitSign)
        else { return nil }

        return value(
            magnitude: magnitude,
            isNegative: isNegative,
            firstMark: fields[0].mark?.kind,
            quantity: quantity
        )
    }

    /// Reads one to three `number [unit]` fields, separated by whitespace or colons.
    private static func readFields(from reader: inout TokenReader) -> [Field]? {
        var fields: [Field] = []
        while true {
            guard let number = reader.takeNumber() else { return nil }

            var mark = reader.takeMark()
            if mark == nil, fields.count == 2, reader.upcomingIsAttachedSouthOrSeconds {
                // "40d30m15s" reads the attached letter as the seconds unit. That is only
                // unambiguous when degrees and minutes were also written as letters; "40 30 15S"
                // could equally mean 40°30′15″ south, so it is rejected.
                guard fields[0].mark == UnitMark(kind: .degree, isLetter: true),
                      fields[1].mark == UnitMark(kind: .minute, isLetter: true) else { return nil }
                reader.skip()
                mark = UnitMark(kind: .second, isLetter: true)
            }
            guard markFits(mark, atFieldIndex: fields.count) else { return nil }
            fields.append(Field(value: number.value, isWhole: number.isWhole, mark: mark))

            // After a colon another field must follow; otherwise fields continue only while
            // numbers do.
            guard reader.takeColon() || reader.upcomingIsNumber else { break }
        }
        return fields.count <= 3 ? fields : nil
    }

    /// Whether a unit mark is allowed on the field at `index`: hours or degrees first, then
    /// minutes, then seconds.
    private static func markFits(_ mark: UnitMark?, atFieldIndex index: Int) -> Bool {
        guard let mark else { return true }
        switch (index, mark.kind) {
        case (0, .hour), (0, .degree), (1, .minute), (2, .second): return true
        default: return false
        }
    }

    /// Combines the fields into one value in the units of the first field, or returns nil unless
    /// only the last field is fractional and minutes and seconds are below 60.
    private static func combinedMagnitude(of fields: [Field]) -> Double? {
        var total = 0.0
        var divisor = 1.0
        for (index, field) in fields.enumerated() {
            if index < fields.count - 1 && !field.isWhole { return nil }
            if index > 0 && field.value >= 60 { return nil }
            total += field.value / divisor
            divisor *= 60
        }
        return total
    }

    /// Merges a hemisphere letter and an explicit sign into one sign, returning whether the value is
    /// negative. A sign next to a hemisphere letter is redundant at best and contradictory at worst,
    /// so only the harmless "+40 N" is accepted.
    private static func mergedSign(hemisphere: Bool?, sign: Bool?) -> Bool? {
        switch (hemisphere, sign) {
        case (nil, nil):
            return false
        case let (hemisphere?, nil):
            return hemisphere
        case let (nil, sign?):
            return sign
        case let (hemisphere?, sign?):
            guard !hemisphere, !sign else { return nil }
            return false
        }
    }

    /// Applies the unit and range rules of `quantity` to a parsed magnitude.
    private static func value(
        magnitude: Double,
        isNegative: Bool,
        firstMark: Mark?,
        quantity: Quantity
    ) -> Double? {
        switch quantity {
        case .rightAscension:
            // A right ascension is hours unless degrees were explicitly requested with "°" or "d".
            guard !isNegative, firstMark == nil || firstMark == .hour || firstMark == .degree else { return nil }
            let hours = firstMark == .degree ? magnitude / 15 : magnitude
            return (0.0..<24.0).contains(hours) ? hours : nil

        case .declination:
            guard firstMark == nil || firstMark == .degree else { return nil }
            let degrees = isNegative ? -magnitude : magnitude
            return abs(degrees) <= 90 ? normalizingZero(degrees) : nil

        case .longitude:
            guard firstMark == nil || firstMark == .degree else { return nil }
            var degrees = isNegative ? -magnitude : magnitude
            // West-negative values reach -180°; east-positive values may run to 360°.
            guard (-180.0...360.0).contains(degrees) else { return nil }
            if degrees > 180 {
                degrees -= 360
            } else if degrees <= -180 {
                degrees += 360
            }
            return normalizingZero(degrees)
        }
    }

    /// Returns positive zero for negative zero, so "-0" never produces "-0.0".
    private static func normalizingZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}

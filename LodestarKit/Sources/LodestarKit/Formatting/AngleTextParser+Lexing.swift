// Lexing: turns the scalars of an input string into `AngleTextParser.Token`s.
extension AngleTextParser {

    /// Splits scalars into tokens, or returns nil when any scalar is not part of the grammar.
    static func tokenize(_ scalars: [Unicode.Scalar], for quantity: Quantity) -> [Token]? {
        var tokens: [Token] = []
        var index = 0
        var followsSpace = false

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace {
                followsSpace = true
                index += 1
                continue
            }

            let kind: Token.Kind
            if isDigit(scalar) || scalar == "." || scalar == "," {
                guard let parsed = number(in: scalars, from: index) else { return nil }
                kind = parsed.kind
                index = parsed.next
            } else {
                guard let symbol = symbol(for: scalar, quantity: quantity) else { return nil }
                kind = symbol
                index += 1
            }
            tokens.append(Token(kind: kind, followsSpace: followsSpace))
            followsSpace = false
        }
        return mergingDoubledPrimes(tokens)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    private static func isDecimalMark(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "." || scalar == ","
    }

    /// Reads an unsigned number starting at `start`. Both "." and "," are accepted as the decimal
    /// mark, but a comma only counts when a digit follows it so that "40, 30" is not read as 40.30.
    private static func number(in scalars: [Unicode.Scalar], from start: Int) -> (kind: Token.Kind, next: Int)? {
        var index = start
        var integerDigits = ""
        var fractionDigits = ""
        var hasDecimalMark = false

        while index < scalars.count, isDigit(scalars[index]) {
            integerDigits.unicodeScalars.append(scalars[index])
            index += 1
        }
        if index < scalars.count, isDecimalMark(scalars[index]) {
            let followedByDigit = index + 1 < scalars.count && isDigit(scalars[index + 1])
            if scalars[index] == "." || followedByDigit {
                hasDecimalMark = true
                index += 1
                while index < scalars.count, isDigit(scalars[index]) {
                    fractionDigits.unicodeScalars.append(scalars[index])
                    index += 1
                }
            }
        }
        guard !integerDigits.isEmpty || !fractionDigits.isEmpty else { return nil }
        // A second decimal mark ("1.2.3", "1,5,5", or a comma after "40") makes the number ambiguous.
        if index < scalars.count, isDecimalMark(scalars[index]) { return nil }

        let literal = "\(integerDigits.isEmpty ? "0" : integerDigits).\(fractionDigits.isEmpty ? "0" : fractionDigits)"
        guard let value = Double(literal), value.isFinite else { return nil }
        return (.number(value: value, isWhole: !hasDecimalMark), index)
    }

    /// Classifies a single non-digit, non-space scalar.
    private static func symbol(for scalar: Unicode.Scalar, quantity: Quantity) -> Token.Kind? {
        switch scalar.value {
        case 0x2B:
            return .sign(isNegative: false)
        case 0x2D, 0x2010...0x2013, 0x2212, 0xFE63, 0xFF0D:
            // Hyphen-minus, hyphens, dashes, minus sign, small and fullwidth hyphen-minus.
            return .sign(isNegative: true)
        case 0x3A:
            return .colon
        case 0xB0, 0xBA, 0x2DA:
            // Degree sign, masculine ordinal indicator (often typed by mistake) and ring above.
            return .mark(UnitMark(kind: .degree, isLetter: false))
        case 0x27, 0x2018, 0x2019, 0xB4, 0x2B9, 0x2032:
            // Apostrophe, curly single quotes (smart punctuation), acute accent, modifier prime, prime.
            return .mark(UnitMark(kind: .minute, isLetter: false))
        case 0x22, 0x201C, 0x201D, 0x2BA, 0x2033:
            // Quotation mark, curly double quotes, modifier double prime, double prime.
            return .mark(UnitMark(kind: .second, isLetter: false))
        case 0x48, 0x68:
            return .mark(UnitMark(kind: .hour, isLetter: true))
        case 0x44, 0x64:
            return .mark(UnitMark(kind: .degree, isLetter: true))
        case 0x4D, 0x6D:
            return .mark(UnitMark(kind: .minute, isLetter: true))
        case 0x53, 0x73:
            return quantity == .declination
                ? .southOrSeconds
                : .mark(UnitMark(kind: .second, isLetter: true))
        case 0x4E, 0x6E:
            return quantity == .declination ? .hemisphere(isNegative: false) : nil
        case 0x45, 0x65:
            return quantity == .longitude ? .hemisphere(isNegative: false) : nil
        case 0x57, 0x77:
            return quantity == .longitude ? .hemisphere(isNegative: true) : nil
        default:
            return nil
        }
    }

    /// Two adjacent minute symbols ("''" or "′′") are a seconds symbol.
    private static func mergingDoubledPrimes(_ tokens: [Token]) -> [Token] {
        let minuteSymbol = Token.Kind.mark(UnitMark(kind: .minute, isLetter: false))
        let secondSymbol = Token.Kind.mark(UnitMark(kind: .second, isLetter: false))
        var merged: [Token] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if index + 1 < tokens.count,
               token.kind == minuteSymbol,
               tokens[index + 1].kind == minuteSymbol,
               !tokens[index + 1].followsSpace {
                merged.append(Token(kind: secondSymbol, followsSpace: token.followsSpace))
                index += 2
            } else {
                merged.append(token)
                index += 1
            }
        }
        return merged
    }
}

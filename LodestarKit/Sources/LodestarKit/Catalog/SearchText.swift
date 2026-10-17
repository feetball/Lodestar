import Foundation

/// Text normalization for catalog search.
///
/// A search key is the text reduced to lower-case ASCII letters and digits:
/// - case, diacritics and character width are ignored ("Ｍ３１" is "m31", "Boötes" is "bootes");
/// - Greek letters become their English names ("α" is "alpha") and superscript or subscript digits
///   become plain digits ("α¹" is "alpha1");
/// - punctuation and whitespace are dropped, apostrophes silently ("Barnard's" is "barnards") and
///   everything else as a word boundary, which the key remembers in `wordStarts`;
/// - leading zeros of numbers are dropped ("NGC 0224" is "ngc224"), keeping a lone zero;
/// - scripts and symbols without a Latin reading (emoji, CJK, ...) count as punctuation.
///
/// Queries and the texts they are matched against go through the same function, so every
/// spelling that reduces to the same key matches.
enum SearchText {
    /// The longest key in bytes; longer text is cut off.
    static let maximumKeyLength = 64
    /// The most Unicode scalars of a query that are considered.
    static let maximumQueryScalars = 64

    /// A normalized text.
    struct Key: Hashable, Sendable {
        /// Lower-case ASCII letters and digits, at most `maximumKeyLength` bytes.
        var bytes: [UInt8]
        /// Bit *i* is set when `bytes[i]` is the first byte of a word.
        var wordStarts: UInt64
    }

    /// The key of `text`, looking at no more than `maximumScalars` Unicode scalars.
    static func key(for text: String, maximumScalars: Int = .max) -> Key {
        var builder = KeyBuilder()
        var scalarCount = 0
        for scalar in text.unicodeScalars {
            if scalarCount >= maximumScalars || builder.isFull { break }
            scalarCount += 1
            builder.read(scalar)
        }
        return builder.finish()
    }

    /// Whether `lhs` sorts before `rhs` in natural order: byte by byte, but runs of digits compare
    /// by value ("m2" before "m10"). Keys carry no leading zeros, so a longer run is a larger number.
    static func naturalPrecedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        var i = 0, j = 0
        while i < lhs.count, j < rhs.count {
            let x = lhs[i], y = rhs[j]
            if isDigit(x), isDigit(y) {
                var iEnd = i, jEnd = j
                while iEnd < lhs.count, isDigit(lhs[iEnd]) { iEnd += 1 }
                while jEnd < rhs.count, isDigit(rhs[jEnd]) { jEnd += 1 }
                if iEnd - i != jEnd - j { return iEnd - i < jEnd - j }
                for offset in 0..<(iEnd - i) where lhs[i + offset] != rhs[j + offset] {
                    return lhs[i + offset] < rhs[j + offset]
                }
                i = iEnd
                j = jEnd
            } else {
                if x != y { return x < y }
                i += 1
                j += 1
            }
        }
        return lhs.count - i < rhs.count - j
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
}

/// Accumulates the bytes and word boundaries of a search key, one Unicode scalar at a time.
private struct KeyBuilder {
    private var bytes: [UInt8] = []
    private var wordStarts: UInt64 = 0
    private var atWordStart = true
    private var inDigitRun = false
    /// Leading zeros of the current number that have been seen but not yet stored.
    private var pendingZeros = 0

    init() {
        bytes.reserveCapacity(24)
    }

    var isFull: Bool { bytes.count >= SearchText.maximumKeyLength }

    mutating func finish() -> SearchText.Key {
        flushZeros()
        return SearchText.Key(bytes: bytes, wordStarts: wordStarts)
    }

    mutating func read(_ scalar: Unicode.Scalar, allowDecomposition: Bool = true) {
        let value = scalar.value
        switch value {
        case 0x30...0x39:
            digit(UInt8(truncatingIfNeeded: value))
        case 0x61...0x7A:
            letter(UInt8(truncatingIfNeeded: value))
        case 0x41...0x5A:
            letter(UInt8(truncatingIfNeeded: value) | 0x20)
        case 0x27, 0x60, 0x2018, 0x2019, 0x201B, 0x02BC:
            break
        case 0x00...0x7F:
            separator()
        case 0xFF01...0xFF5E:
            if let ascii = Unicode.Scalar(value - 0xFEE0) { read(ascii, allowDecomposition: false) }
        case 0x0391...0x03A1, 0x03A3...0x03A9, 0x03B1...0x03C9, 0x03D1, 0x03D5, 0x03D6, 0x03F0, 0x03F1, 0x03F4, 0x03F5:
            if let index = GreekAlphabet.index(of: scalar) { greek(index) }
        case 0x00B2: digit(0x32)
        case 0x00B3: digit(0x33)
        case 0x00B9: digit(0x31)
        case 0x2070: digit(0x30)
        case 0x2074...0x2079: digit(UInt8(truncatingIfNeeded: value - 0x2074) + 0x34)
        case 0x2080...0x2089: digit(UInt8(truncatingIfNeeded: value - 0x2080) + 0x30)
        case 0x00AD, 0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x200B...0x200F,
             0x20D0...0x20FF, 0x2060, 0xFE00...0xFE0F, 0xFE20...0xFE2F, 0xFEFF:
            break
        case 0x00D8, 0x00F8:
            letter(0x6F)
        case 0x00C6, 0x00E6:
            letter(0x61)
            letter(0x65)
        case 0x0152, 0x0153:
            letter(0x6F)
            letter(0x65)
        case 0x00DF:
            letter(0x73)
            letter(0x73)
        case 0x00D0, 0x00F0, 0x0110, 0x0111:
            letter(0x64)
        case 0x00DE, 0x00FE:
            letter(0x74)
            letter(0x68)
        case 0x0141, 0x0142:
            letter(0x6C)
        case 0x0126, 0x0127:
            letter(0x68)
        case 0x0131:
            letter(0x69)
        case 0x0166, 0x0167:
            letter(0x74)
        default:
            decompose(scalar, allowDecomposition: allowDecomposition)
        }
    }

    /// Reads a scalar through its compatibility decomposition (accented letters, ligatures,
    /// circled digits, ...). A scalar that does not decompose counts as punctuation.
    private mutating func decompose(_ scalar: Unicode.Scalar, allowDecomposition: Bool) {
        guard allowDecomposition else {
            separator()
            return
        }
        let decomposed = String(scalar).decomposedStringWithCompatibilityMapping
        var changed = false
        for part in decomposed.unicodeScalars {
            if part == scalar { break }
            changed = true
            read(part, allowDecomposition: false)
        }
        if !changed { separator() }
    }

    private mutating func greek(_ index: Int) {
        atWordStart = true
        for byte in GreekAlphabet.nameBytes[index] {
            letter(byte)
        }
    }

    private mutating func letter(_ byte: UInt8) {
        flushZeros()
        append(byte)
        inDigitRun = false
    }

    private mutating func digit(_ byte: UInt8) {
        if byte == 0x30 {
            if inDigitRun {
                append(byte)
            } else {
                pendingZeros += 1
            }
        } else {
            pendingZeros = 0
            append(byte)
            inDigitRun = true
        }
    }

    private mutating func separator() {
        flushZeros()
        atWordStart = true
        inDigitRun = false
    }

    /// Stores one zero for a number that consisted of zeros only.
    private mutating func flushZeros() {
        guard pendingZeros > 0 else { return }
        pendingZeros = 0
        append(0x30)
        inDigitRun = true
    }

    private mutating func append(_ byte: UInt8) {
        guard bytes.count < SearchText.maximumKeyLength else { return }
        if atWordStart {
            wordStarts |= 1 << UInt64(bytes.count)
            atWordStart = false
        }
        bytes.append(byte)
    }
}

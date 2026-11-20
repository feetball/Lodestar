import Foundation

/// Reads the header of a gzip file (RFC 1952) so that an app can hand the raw DEFLATE data to its own inflater: iOS
/// `Compression` (`COMPRESSION_ZLIB` is raw DEFLATE) and `java.util.zip.Inflater(true)` on Android. The engine does not
/// inflate anything itself.
///
/// Only the first member of a file is looked at; files with more than one member (concatenated gzip files) are not
/// what the terrain tiles are. The optional header checksum (`FHCRC`) is skipped, not verified: the inflater checks the
/// data itself, and the trailer's own CRC-32 can be checked by the caller.
public enum GzipHeader {
    /// The length of the trailer: the CRC-32 and the uncompressed length, four bytes each.
    public static let trailerLength = 8

    /// The most bytes a file name or comment may have before the header is rejected.
    public static let maximumTextLength = 4096

    private static let fixedLength = 10
    private static let headerChecksumFlag = 0x02
    private static let extraFlag = 0x04
    private static let nameFlag = 0x08
    private static let commentFlag = 0x10
    private static let reservedFlags = 0xE0
    private static let deflateMethod = 8

    /// The range of the raw DEFLATE data in `data`: from the end of the header (magic, method, flags, and the optional
    /// extra field, file name, comment and header checksum that the flags announce) to the start of the 8-byte
    /// trailer. Offsets count from the first byte of `data`, whatever its `startIndex` is.
    ///
    /// Returns `nil` when `data` is not a gzip file the engine understands: wrong magic number or compression method,
    /// reserved flags set, a header (or a name or comment longer than `maximumTextLength`) that is cut short, or no
    /// room for at least one byte of data before the trailer.
    public static func payloadRange(of data: Data) -> Range<Int>? {
        guard let start = headerLength(of: data) else { return nil }
        let end = data.count - trailerLength
        guard start < end else { return nil }
        return start..<end
    }

    /// The length of the uncompressed data from the trailer's `ISIZE` field (little endian, modulo 2³²), or `nil`
    /// when `payloadRange(of:)` is `nil` or the number does not fit an `Int32`. The apps use it to size the output of
    /// the inflater and to refuse a file that would inflate to something else than a tile.
    public static func uncompressedLength(of data: Data) -> Int? {
        guard payloadRange(of: data) != nil else { return nil }
        var value = 0
        for offset in 1...4 {
            value = (value << 8) | byte(data, data.count - offset)
        }
        return value <= Int(Int32.max) ? value : nil
    }

    /// The number of header bytes, or `nil` when the header is not valid or is cut short.
    private static func headerLength(of data: Data) -> Int? {
        guard data.count >= fixedLength + trailerLength else { return nil }
        guard byte(data, 0) == 0x1F, byte(data, 1) == 0x8B, byte(data, 2) == deflateMethod else { return nil }
        let flags = byte(data, 3)
        guard flags & reservedFlags == 0 else { return nil }
        var position = fixedLength
        if flags & extraFlag != 0 {
            guard position + 2 <= data.count else { return nil }
            position += 2 + (byte(data, position) | (byte(data, position + 1) << 8))
            guard position <= data.count else { return nil }
        }
        if flags & nameFlag != 0 {
            guard let next = afterTerminator(in: data, from: position) else { return nil }
            position = next
        }
        if flags & commentFlag != 0 {
            guard let next = afterTerminator(in: data, from: position) else { return nil }
            position = next
        }
        if flags & headerChecksumFlag != 0 { position += 2 }
        guard position <= data.count else { return nil }
        return position
    }

    /// The position after the zero byte that ends the text starting at `start`, or `nil` without one in range.
    private static func afterTerminator(in data: Data, from start: Int) -> Int? {
        let limit = min(data.count, start + maximumTextLength + 1)
        var position = start
        while position < limit {
            if byte(data, position) == 0 { return position + 1 }
            position += 1
        }
        return nil
    }

    private static func byte(_ data: Data, _ index: Int) -> Int {
        Int(data[data.startIndex + index])
    }
}

import XCTest
@testable import LodestarKit

/// Hand-built gzip headers (RFC 1952) for `GzipHeader`.
final class GzipHeaderTests: XCTestCase {
    private let text = Data("name.hgt".utf8) + Data([0])

    /// A gzip file of one member: a header with `flags` and `middle` (the optional fields), `payload`, a trailer.
    private func file(flags: Int = 0, middle: Data = Data(), payload: Data = Data([0x03, 0x00]), isize: UInt64 = 0x01_8B_BA_42,
                      method: Int = 8, magic: [Int] = [0x1F, 0x8B]) -> Data {
        var header = [UInt8](repeating: 0, count: 10)
        header[0] = UInt8(magic[0])
        header[1] = UInt8(magic[1])
        header[2] = UInt8(method)
        header[3] = UInt8(flags)
        header[8] = 2
        header[9] = 0xFF
        var trailer = [UInt8](repeating: 0, count: 8)
        for offset in 0...3 { trailer[4 + offset] = UInt8(truncatingIfNeeded: isize >> UInt64(8 * offset)) }
        return Data(header) + middle + payload + Data(trailer)
    }

    // MARK: Header cases

    func testMinimalHeaderHasTheDataAfterTenBytes() {
        XCTAssertEqual(GzipHeader.payloadRange(of: file()), 10..<12)
    }

    func testFileNameIsSkipped() {
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x08, middle: text)), 19..<21)
    }

    func testCommentIsSkipped() {
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x10, middle: Data("made by hand".utf8) + Data([0]))), 23..<25)
    }

    func testExtraFieldIsSkipped() {
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x04, middle: Data([3, 0, 1, 2, 3]))), 15..<17)
    }

    func testHeaderChecksumIsSkipped() {
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x02, middle: Data([0x12, 0x34]))), 12..<14)
    }

    func testAllOptionalFieldsInTheirOrder() {
        // Extra field (length 258 = 2 + 256 bytes, so the length's high byte counts), name, comment, checksum.
        let extra = Data([0x02, 0x01]) + Data(repeating: 0, count: 258)
        let middle = extra + text + Data("c".utf8) + Data([0]) + Data([0x55, 0x66])
        let start = 10 + 2 + 258 + 9 + 2 + 2
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x1E, middle: middle)), start..<(start + 2))
    }

    func testHeaderOfARealTileFile() {
        // The first 22 bytes of elevation-tiles-prod/skadi/N47/N47E008.hgt.gz: the file name flag, "N47E008.hgt".
        let header = Data([0x1F, 0x8B, 0x08, 0x08, 0x02, 0x3A, 0x1B, 0x57, 0x02, 0xFF]) + Data("N47E008.hgt".utf8) + Data([0])
        let data = header + Data(repeating: 0, count: 100) + Data([0xD4, 0x2B, 0xA5, 0x74, 0x42, 0xBA, 0x8B, 0x01])
        XCTAssertEqual(GzipHeader.payloadRange(of: data), 22..<122)
        XCTAssertEqual(GzipHeader.uncompressedLength(of: data), 25_934_402)
    }

    func testPayloadRangeCountsFromTheStartOfTheData() {
        let data = file(flags: 0x08, middle: text)
        let shifted = (Data([9, 9, 9]) + data).dropFirst(3)
        XCTAssertNotEqual(shifted.startIndex, 0)
        XCTAssertEqual(GzipHeader.payloadRange(of: shifted), GzipHeader.payloadRange(of: data))
    }

    // MARK: Rejections

    func testWrongMagicOrMethodIsRejected() {
        XCTAssertNil(GzipHeader.payloadRange(of: file(magic: [0x1F, 0x8C])))
        XCTAssertNil(GzipHeader.payloadRange(of: file(magic: [0x1E, 0x8B])))
        XCTAssertNil(GzipHeader.payloadRange(of: file(method: 7)))
        XCTAssertNil(GzipHeader.payloadRange(of: file(method: 0)))
    }

    func testReservedFlagsAreRejected() {
        for flag in [0x20, 0x40, 0x80] { XCTAssertNil(GzipHeader.payloadRange(of: file(flags: flag))) }
    }

    func testCutShortHeadersAreRejected() {
        XCTAssertNil(GzipHeader.payloadRange(of: Data()))
        XCTAssertNil(GzipHeader.payloadRange(of: Data([0x1F, 0x8B, 8])))
        // A name without its zero byte.
        XCTAssertNil(GzipHeader.payloadRange(of: file(flags: 0x08, middle: Data("no end".utf8), payload: Data())))
        // An extra field longer than the file.
        XCTAssertNil(GzipHeader.payloadRange(of: file(flags: 0x04, middle: Data([0xFF, 0xFF, 1, 2]))))
        // The extra field's length bytes overlap the trailer, and no data is left.
        XCTAssertNil(GzipHeader.payloadRange(of: file(flags: 0x04, payload: Data())))
    }

    func testNameLongerThanTheLimitIsRejected() {
        let long = Data(repeating: UInt8(ascii: "a"), count: GzipHeader.maximumTextLength + 1) + Data([0])
        XCTAssertNil(GzipHeader.payloadRange(of: file(flags: 0x08, middle: long)))
        let allowed = Data(repeating: UInt8(ascii: "a"), count: GzipHeader.maximumTextLength) + Data([0])
        XCTAssertEqual(GzipHeader.payloadRange(of: file(flags: 0x08, middle: allowed)),
                       (10 + allowed.count)..<(12 + allowed.count))
    }

    func testNoRoomForDataIsRejected() {
        XCTAssertNil(GzipHeader.payloadRange(of: file(payload: Data())))
        XCTAssertNil(GzipHeader.payloadRange(of: Data(count: 17)))
        XCTAssertEqual(GzipHeader.payloadRange(of: file(payload: Data([3]))), 10..<11)
    }

    // MARK: Uncompressed length

    func testUncompressedLengthIsTheLittleEndianTrailerField() {
        XCTAssertEqual(GzipHeader.uncompressedLength(of: file()), 25_934_402)
        XCTAssertEqual(GzipHeader.uncompressedLength(of: file(isize: 2_884_802)), 2_884_802)
        XCTAssertEqual(GzipHeader.uncompressedLength(of: file(isize: 0)), 0)
        XCTAssertEqual(GzipHeader.uncompressedLength(of: file(isize: UInt64(Int32.max))), Int(Int32.max))
    }

    func testUncompressedLengthIsNilWhenItDoesNotFitOrTheFileIsNotGzip() {
        XCTAssertNil(GzipHeader.uncompressedLength(of: file(isize: 0x8000_0000)))
        XCTAssertNil(GzipHeader.uncompressedLength(of: file(isize: 0xFFFF_FFFF)))
        XCTAssertNil(GzipHeader.uncompressedLength(of: file(method: 7)))
        XCTAssertNil(GzipHeader.uncompressedLength(of: Data()))
    }
}

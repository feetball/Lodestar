import XCTest
@testable import LodestarKit

final class MountJSONTests: XCTestCase {
    func testLiteralsNumbersAndStrings() throws {
        XCTAssertEqual(try MountJSON.parse("null"), .null)
        XCTAssertEqual(try MountJSON.parse(" true "), .bool(true))
        XCTAssertEqual(try MountJSON.parse("false"), .bool(false))
        XCTAssertEqual(try MountJSON.parse("0"), .number(0.0))
        XCTAssertEqual(try MountJSON.parse("-12.5"), .number(-12.5))
        XCTAssertEqual(try MountJSON.parse("1e2"), .number(100.0))
        XCTAssertEqual(try MountJSON.parse("1E-2"), .number(0.01))
        XCTAssertEqual(try MountJSON.parse("1.2e+1"), .number(12.0))
        XCTAssertEqual(try MountJSON.parse("\"hello\""), .text("hello"))
        XCTAssertEqual(try MountJSON.parse("\"\""), .text(""))
    }

    func testStringEscapes() throws {
        XCTAssertEqual(try MountJSON.parse("\"a\\\"b\\\\c\\/d\\b\\f\\n\\r\\t\""), .text("a\"b\\c/d\u{08}\u{0C}\n\r\t"))
        XCTAssertEqual(try MountJSON.parse("\"\\u00e9\""), .text("\u{E9}"))
        XCTAssertEqual(try MountJSON.parse("\"\\ud83d\\ude00\""), .text("\u{1F600}"))
        XCTAssertEqual(try MountJSON.parse("\"é😀\""), .text("é😀"))
    }

    func testArraysAndObjects() throws {
        XCTAssertEqual(try MountJSON.parse("[]"), .array([]))
        XCTAssertEqual(try MountJSON.parse(" { } "), .object([:]))
        let parsed = try MountJSON.parse("{\"Value\": [1, 2.5, \"x\", null, true, {\"a\": []}], \"ErrorNumber\": 0}")
        guard case let .array(items)? = parsed.field("Value") else { return XCTFail("expected an array") }
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items[1], .number(2.5))
        XCTAssertEqual(items[5], .object(["a": .array([])]))
        XCTAssertEqual(parsed.field("ErrorNumber"), .number(0.0))
        // Duplicate keys: the last one wins.
        XCTAssertEqual(try MountJSON.parse("{\"a\":1,\"a\":2}").field("a"), .number(2.0))
    }

    func testFieldLookupIgnoresAsciiCase() throws {
        let parsed = try MountJSON.parse("{\"clienttransactionid\": 7, \"ServerTransactionID\": 9}")
        XCTAssertEqual(parsed.field("ClientTransactionID"), .number(7.0))
        XCTAssertEqual(parsed.field("servertransactionid"), .number(9.0))
        XCTAssertNil(parsed.field("Value"))
        XCTAssertNil(MountJSON.number(1.0).field("Value"))
    }

    func testMalformedDocumentsAreRejected() {
        let bad = [
            "", " ", "nul", "tru", "True", "NaN", "Infinity", "+1", "01", "1.", ".5", "1e", "1e+", "-", "--1", "0x10", "1 2",
            "\"abc", "\"a\nb\"", "\"\\x\"", "\"\\u12\"", "\"\\ud83d\"", "\"\\ude00\"", "\"\\ud83d\\u0041\"", "[1,]", "[1 2]", "[", "]",
            "{\"a\"}", "{\"a\":}", "{a:1}", "{\"a\":1,}", "{\"a\":1", "{1:2}", "'a'", "[1]x", "{} {}", "1e999",
        ]
        for text in bad { assertMalformed(try MountJSON.parse(text), text) }
    }

    func testLimits() throws {
        let deepEnough = String(repeating: "[", count: MountJSON.maximumDepth) + String(repeating: "]", count: MountJSON.maximumDepth)
        _ = try MountJSON.parse(deepEnough)
        let tooDeep = String(repeating: "[", count: MountJSON.maximumDepth + 2) + String(repeating: "]", count: MountJSON.maximumDepth + 2)
        assertMalformed(try MountJSON.parse(tooDeep))
        let long = "\"" + String(repeating: "a", count: MountJSON.maximumLength) + "\""
        assertMalformed(try MountJSON.parse(long))
    }
}

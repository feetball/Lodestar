import XCTest
@testable import LodestarKit

/// The strict JSON reader that the Small-Body Database parser uses (identical grammar in Kotlin and Swift).
final class CometsJSONTests: XCTestCase {
    private func read(_ text: String) throws -> JSONValue {
        var reader = JSONReader(text)
        return try reader.readDocument()
    }

    private func failure(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> JSONFailure? {
        do {
            _ = try read(text)
            XCTFail("expected a failure for \(text)", file: file, line: line)
        } catch let error as JSONReaderError {
            return error.failure
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
        return nil
    }

    func testReadsScalars() throws {
        XCTAssertEqual(try read("null"), .null)
        XCTAssertEqual(try read("true"), .bool(true))
        XCTAssertEqual(try read(" \t\r\nfalse\n "), .bool(false))
        XCTAssertEqual(try read("0"), .number(0.0))
        XCTAssertEqual(try read("12"), .number(12.0))
        XCTAssertEqual(try read("-1.5e3"), .number(-1500.0))
        XCTAssertEqual(try read("0.25"), .number(0.25))
        XCTAssertEqual(try read("1E2"), .number(100.0))
        XCTAssertEqual(try read("1e+2"), .number(100.0))
        XCTAssertEqual(try read("2.5E-3"), .number(0.0025))
        XCTAssertEqual(try read("2461599.841466614"), .number(2_461_599.841_466_614))
        XCTAssertEqual(try read("1e-400"), .number(0.0)) // underflows to zero, which is finite
        XCTAssertEqual(try read("\"\""), .string(""))
        XCTAssertEqual(try read("\"abc\""), .string("abc"))
    }

    func testReadsStringEscapesAndUnicode() throws {
        XCTAssertEqual(try read("\"a\\\"b\\\\c\\/d\\b\\f\\n\\r\\t\""), .string("a\"b\\c/d\u{08}\u{0C}\n\r\t"))
        XCTAssertEqual(try read("\"\\u0041\\u00e9\""), .string("A\u{00E9}"))
        XCTAssertEqual(try read("\"\\ud83d\\ude00\""), .string("\u{1F600}"))
        XCTAssertEqual(try read("\"\u{00E9}\u{1F600} x\""), .string("\u{00E9}\u{1F600} x"))
        XCTAssertEqual(try read("\"\\u0000\""), .string("\u{0000}"))
        XCTAssertEqual(try read("\"\u{007F}\""), .string("\u{007F}"))
    }

    func testReadsStructures() throws {
        XCTAssertEqual(try read("{}"), .object([:]))
        XCTAssertEqual(try read("[]"), .array([]))
        XCTAssertEqual(try read(" { } "), .object([:]))
        XCTAssertEqual(try read("[1, \"x\" ,null]"), .array([.number(1.0), .string("x"), .null]))
        guard case .object(let nested) = try read("{\"a\": {\"b\": [true, {\"c\": 3}]}, \"d\": \"e\"}") else {
            return XCTFail("expected an object")
        }
        XCTAssertEqual(Set(nested.keys), ["a", "d"])
        XCTAssertEqual(nested["d"], .string("e"))
        // A repeated name keeps the last value.
        guard case .object(let repeated) = try read("{\"k\": 1, \"k\": 2}") else { return XCTFail("expected an object") }
        XCTAssertEqual(repeated["k"], .number(2.0))
        // Names may be empty and may contain escapes.
        guard case .object(let odd) = try read("{\"\": 1, \"a\\nb\": 2}") else { return XCTFail("expected an object") }
        XCTAssertEqual(odd[""], .number(1.0))
        XCTAssertEqual(odd["a\nb"], .number(2.0))
    }

    func testRefusesInvalidNumbers() {
        for text in ["01", "1.", ".5", "+1", "-", "1e", "1e+", "--1", "0x10", "NaN", "Infinity", "-Infinity", "1e999", "-1e999",
                     "1.5.2", "1,5", "0.", "-.5", "1 2"] {
            XCTAssertEqual(failure(text), .invalid, text)
        }
    }

    func testRefusesInvalidStrings() {
        for text in ["\"abc", "\"a\nb\"", "\"a\tb\"", "\"\\x\"", "\"\\u12\"", "\"\\u12G4\"", "\"\\ud800\"", "\"\\ud800x\"",
                     "\"\\ud800\\u0041\"", "\"\\udc00\"", "\"\\", "\"\\u", "\"\\ud83d\\", "'single'", "\"\\U0041\"",
                     "\"\\u\u{0662}\u{0662}\u{0662}\u{0662}\""] {
            XCTAssertEqual(failure(text), .invalid, text)
        }
        // A lone surrogate cannot be written in a Swift string; the Kotlin twin tests raw lone surrogates as well.
    }

    func testRefusesInvalidStructures() {
        for text in ["", " ", "{", "}", "[", "]", "[1,]", "[,1]", "[1 2]", "{\"a\":1,}", "{\"a\" 1}", "{a: 1}", "{'a': 1}", "{\"a\":}",
                     "{\"a\":1 \"b\":2}", "{} {}", "[] x", "1 2", "tru", "nul", "True", "falsey", "// c\n{}", "/* c */ {}",
                     "{\"a\": 1} // c", "\u{FEFF}{}", "\u{00A0}{}", "\u{000B}{}", "[1;2]", "{\"a\":1;}", "{1: 2}", "{\"a\"}", "[",
                     "{\"a\":[}"] {
            XCTAssertEqual(failure(text), .invalid, text)
        }
    }

    func testLimitsNesting() throws {
        XCTAssertEqual(JSONReader.maximumNesting, 32)
        _ = try read(String(repeating: "[", count: 32) + String(repeating: "]", count: 32))
        _ = try read(String(repeating: "{\"a\":", count: 32) + "1" + String(repeating: "}", count: 32))
        XCTAssertEqual(failure(String(repeating: "[", count: 33) + String(repeating: "]", count: 33)), .tooDeep)
        XCTAssertEqual(failure(String(repeating: "{\"a\":", count: 33) + "1" + String(repeating: "}", count: 33)), .tooDeep)
        // The depth is reported even if the text ends early.
        XCTAssertEqual(failure(String(repeating: "[", count: 40)), .tooDeep)
        // Brackets in strings are not nesting.
        _ = try read("[\"" + String(repeating: "[", count: 100) + "\"]")
    }
}

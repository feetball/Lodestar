import XCTest
@testable import LodestarKit

/// The CSV reader and writer, against RFC 4180 (https://www.rfc-editor.org/rfc/rfc4180).
final class InterchangeCSVTests: XCTestCase {
    private func parse(_ text: String, maximumRecords: Int = 100) throws -> CsvTable {
        try InterchangeCSV.parse(Array(text.unicodeScalars), maximumRecords: maximumRecords)
    }

    private func rows(_ text: String) throws -> [[String]] {
        try parse(text).records.map(\.fields)
    }

    func testPlainRecordsWithAnyLineBreak() throws {
        XCTAssertEqual(try rows("a,b,c\r\n1,2,3\r\n"), [["a", "b", "c"], ["1", "2", "3"]])
        XCTAssertEqual(try rows("a,b\n1,2"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(try rows("a,b\r1,2\r"), [["a", "b"], ["1", "2"]])
    }

    func testQuotedFieldsKeepDelimitersQuotesAndLineBreaks() throws {
        let table = try parse("name,note\r\n\"Flame, Horsehead\",\"say \"\"hi\"\"\"\r\n\"two\r\nlines\",x\r\n")
        XCTAssertEqual(table.records.map(\.fields), [
            ["name", "note"],
            ["Flame, Horsehead", "say \"hi\""],
            ["two\r\nlines", "x"],
        ])
        XCTAssertEqual(table.records.map(\.line), [1, 2, 3])
    }

    func testLineNumbersFollowQuotedLineBreaks() throws {
        let table = try parse("a\n\"x\ny\"\n\nb\n")
        XCTAssertEqual(table.records.map(\.fields), [["a"], ["x\ny"], ["b"]])
        XCTAssertEqual(table.records.map(\.line), [1, 2, 5])
    }

    func testEmptyLinesAreSkippedButEmptyQuotedFieldsAreNot() throws {
        XCTAssertEqual(try rows("a\n\n\nb\n"), [["a"], ["b"]])
        XCTAssertEqual(try rows("a,b\n,\n\"\"\n"), [["a", "b"], ["", ""], [""]])
    }

    func testLenientReadingOfSloppyExports() throws {
        // A quotation mark inside an unquoted field is kept, as Telescopius writes arcseconds.
        XCTAssertEqual(try rows("a,03h 46' 24\"\",x\n"), [["a", "03h 46' 24\"\"", "x"]])
        // Text after a closing quotation mark is appended.
        XCTAssertEqual(try rows("\"ab\"cd,e\n"), [["abcd", "e"]])
        // A byte order mark is dropped.
        XCTAssertEqual(try rows("\u{FEFF}a,b\n"), [["a", "b"]])
    }

    func testDelimiterIsDetectedFromTheFirstLine() throws {
        XCTAssertEqual(try parse("a;b;c\n1;2;3\n").delimiter, ";")
        XCTAssertEqual(try parse("a\tb\n1\t2\n").delimiter, "\t")
        XCTAssertEqual(try parse("a,b;c\n").delimiter, ",")
        XCTAssertEqual(try parse("\"a;b;c\",d\n").delimiter, ",")
        XCTAssertEqual(try rows("a;b\n1,5;2\n"), [["a", "b"], ["1,5", "2"]])
    }

    func testRecordLimitMarksTheTableTruncated() throws {
        let text = "h\n1\n2\n3\n4\n"
        let table = try parse(text, maximumRecords: 3)
        XCTAssertEqual(table.records.count, 3)
        XCTAssertTrue(table.isTruncated)
        XCTAssertFalse(try parse(text, maximumRecords: 5).isTruncated)
        XCTAssertFalse(try parse("h\n1\n2\n\n\n", maximumRecords: 3).isTruncated)
    }

    func testAnUnclosedQuoteIsAnError() {
        XCTAssertThrowsError(try parse("a,b\n1,\"oops\n2,3\n")) { error in
            XCTAssertEqual(error as? InterchangeError, .unterminatedQuote(line: 2))
        }
    }

    func testEmptyAndBlankInputGiveNoRecords() throws {
        XCTAssertEqual(try rows(""), [])
        XCTAssertEqual(try rows("\n\r\n"), [])
    }

    func testWritingQuotesOnlyWhatNeedsIt() {
        XCTAssertEqual(InterchangeCSV.field("plain"), "plain")
        XCTAssertEqual(InterchangeCSV.field("a,b"), "\"a,b\"")
        XCTAssertEqual(InterchangeCSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(InterchangeCSV.field("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(InterchangeCSV.encode([["a", "b,c"], ["1", ""]]), "a,\"b,c\"\r\n1,\r\n")
    }

    func testWrittenRowsReadBackTheSame() throws {
        let original = [["Name", "Note"], ["M 31, \"Andromeda\"", "line 1\nline 2"], ["", "ünïcode ★"], ["x", ""]]
        XCTAssertEqual(try rows(InterchangeCSV.encode(original)), original)
    }

    func testFormulaGuard() {
        for text in ["=1+1", "+1", "-1", "@SUM(A1)", "\tx", "\rx"] {
            XCTAssertEqual(InterchangeCSV.guarded(text), "'" + text)
            XCTAssertEqual(InterchangeCSV.unguarded(InterchangeCSV.guarded(text)), text)
        }
        XCTAssertEqual(InterchangeCSV.guarded("M 31"), "M 31")
        XCTAssertEqual(InterchangeCSV.guarded(""), "")
        XCTAssertEqual(InterchangeCSV.unguarded("'plain"), "'plain")
        XCTAssertEqual(InterchangeCSV.unguarded("'"), "'")
    }
}

/// The number, date and text helpers behind the writers.
final class InterchangeTextTests: XCTestCase {
    func testDecimalAndFixedNumbers() {
        XCTAssertEqual(InterchangeText.decimal(-5.391, maximumDecimals: 5), "-5.391")
        XCTAssertEqual(InterchangeText.decimal(12, maximumDecimals: 3), "12")
        XCTAssertEqual(InterchangeText.decimal(0.5, maximumDecimals: 1), "0.5")
        XCTAssertEqual(InterchangeText.decimal(-0.0001, maximumDecimals: 2), "0")
        XCTAssertEqual(InterchangeText.decimal(.nan, maximumDecimals: 2), "0")
        XCTAssertEqual(InterchangeText.fixed(-5.391, decimals: 5), "-5.39100")
        XCTAssertEqual(InterchangeText.fixed(83.822083, decimals: 5), "83.82208")
        XCTAssertEqual(InterchangeText.fixed(-0.000001, decimals: 5), "0.00000")
        XCTAssertEqual(InterchangeText.fixed(.infinity, decimals: 2), "0.00")
    }

    func testAnAngleThatRoundsUpToAFullTurnIsWrittenAsZero() {
        // Plain `fixed` shows the carry: 359.999996 at five places is 360.00000, outside [0, 360).
        XCTAssertEqual(InterchangeText.fixed(359.999996, decimals: 5), "360.00000")
        XCTAssertEqual(InterchangeText.fixedAngle(359.999996, decimals: 5), "0.00000")
        XCTAssertEqual(InterchangeText.fixedAngle(359.999996, decimals: 2), "0.00")
        XCTAssertEqual(InterchangeText.fixedAngle(359.99999, decimals: 5), "359.99999")
        XCTAssertEqual(InterchangeText.fixedAngle(359.999994, decimals: 5), "359.99999")
        XCTAssertEqual(InterchangeText.fixedAngle(0, decimals: 5), "0.00000")
        XCTAssertEqual(InterchangeText.fixedAngle(83.822083, decimals: 5), "83.82208")
        // Only an angle of the range is wrapped; a value outside it is written as it is.
        XCTAssertEqual(InterchangeText.fixedAngle(360, decimals: 5), "360.00000")
        XCTAssertEqual(InterchangeText.fixedAngle(-0.000001, decimals: 5), "0.00000")
    }

    func testDatesFromEpochDays() {
        XCTAssertEqual(InterchangeText.dateText(daysSinceEpoch: 0), "1970-01-01")
        XCTAssertEqual(InterchangeText.dateText(daysSinceEpoch: -1), "1969-12-31")
        XCTAssertEqual(InterchangeText.dateText(daysSinceEpoch: 11_016), "2000-02-29")
        XCTAssertEqual(InterchangeText.dateText(daysSinceEpoch: 20_775), "2026-11-18")
        // 2026-11-18T22:15:30Z, the number Python's calendar.timegm gives.
        XCTAssertEqual(InterchangeText.dateTimeText(epochSeconds: 1_795_040_130), "2026-11-18T22:15:30Z")
        XCTAssertEqual(InterchangeText.dateTimeText(epochSeconds: -1), "1969-12-31T23:59:59Z")
        XCTAssertEqual(InterchangeText.dateTimeText(epochSeconds: 951_782_400), "2000-02-29T00:00:00Z")
    }

    func testXMLEscapingDropsWhatXMLCannotCarry() {
        XCTAssertEqual(InterchangeText.xml("a & b < c > \"d\" 'e'"), "a &amp; b &lt; c &gt; &quot;d&quot; &apos;e&apos;")
        XCTAssertEqual(InterchangeText.xml("ok\u{0}\u{1}\u{B}\u{FFFE}x\ny\tz"), "okx\ny\tz")
        XCTAssertEqual(InterchangeText.xml("★ \u{1F31F}"), "★ \u{1F31F}")
    }

    func testSingleLineAndMultiLineCleaning() {
        XCTAssertEqual(InterchangeText.singleLine("  a \t b\n\nc  ", limit: 100), "a b c")
        XCTAssertEqual(InterchangeText.singleLine("abcdef", limit: 3), "abc")
        XCTAssertEqual(InterchangeText.singleLine("ab cd", limit: 3), "ab")
        XCTAssertEqual(InterchangeText.singleLine("a\u{200B}b\u{7}c", limit: 100), "ab c")
        XCTAssertEqual(InterchangeText.multiLine("a\r\nb\rc\nd\u{7}\te", limit: 100), "a\nb\nc\nd e")
        XCTAssertEqual(InterchangeText.multiLine("abcdef", limit: 4), "abcd")
    }

    func testSingleLineAndMultiLineKeepJoinersAndDirectionMarks() {
        // A family emoji: man, woman and girl joined by U+200D.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        // "mikhaham" (I want): the ZWNJ keeps the prefix from joining the stem, and the marks surround it.
        let persian = "\u{200F}\u{645}\u{6CC}\u{200C}\u{62E}\u{648}\u{627}\u{647}\u{645}\u{200E}"
        XCTAssertEqual(InterchangeText.singleLine(family, limit: 100), family)
        XCTAssertEqual(InterchangeText.singleLine(persian, limit: 100), persian)
        XCTAssertEqual(InterchangeText.singleLine("  \(persian) \t \(family)\n", limit: 100), "\(persian) \(family)")
        XCTAssertEqual(InterchangeText.multiLine("\(family)\r\n\(persian)", limit: 100), "\(family)\n\(persian)")
        XCTAssertEqual(InterchangeText.singleLine(family, limit: 100).count, 1, "the sequence stays one character")
    }

    func testSingleLineAndMultiLineStillDropOtherFormatCharacters() {
        // U+202E (right-to-left override) and U+2066 (left-to-right isolate) can reorder or hide the text around them.
        XCTAssertEqual(InterchangeText.singleLine("gpj\u{202E}.exe", limit: 100), "gpj.exe")
        XCTAssertEqual(InterchangeText.multiLine("a\u{202E}b\u{2066}c\u{2069}", limit: 100), "abc")
        XCTAssertEqual(InterchangeText.multiLine("a\u{200B}b\u{FEFF}c\u{E0067}d", limit: 100), "abcd")
    }
}

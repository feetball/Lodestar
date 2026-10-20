import Foundation
import XCTest
@testable import AppCore

/// `SettingsNumberText`: reading and writing the text of a numeric settings field.
final class SettingsNumberTextTests: XCTestCase {
    // MARK: Parsing

    func testAPlainNumberInsideTheRangeIsRead() {
        XCTAssertEqual(SettingsNumberText.parse("2.8", in: 0...10), 2.8)
        XCTAssertEqual(SettingsNumberText.parse("24", in: 4...2000), 24)
        XCTAssertEqual(SettingsNumberText.parse("0", in: 0...1), 0)
    }

    func testACommaWorksAsTheDecimalMark() {
        XCTAssertEqual(SettingsNumberText.parse("2,8", in: 0...10), 2.8)
        XCTAssertEqual(SettingsNumberText.parse("0,95", in: 0...1), 0.95)
    }

    func testTheTypographicMinusWorksAsTheMinusSign() {
        XCTAssertEqual(SettingsNumberText.parse("\u{2212}5", in: -10...10), -5)
        XCTAssertEqual(SettingsNumberText.parse("\u{2212}12,5", in: -60...60), -12.5)
        XCTAssertEqual(SettingsNumberText.parse("-5", in: -10...10), -5)
    }

    func testSurroundingWhitespaceAndNewlinesAreIgnored() {
        XCTAssertEqual(SettingsNumberText.parse("  24  ", in: 0...100), 24)
        XCTAssertEqual(SettingsNumberText.parse("\n12\t", in: 0...100), 12)
    }

    func testTheRangeBoundsAreIncluded() {
        XCTAssertEqual(SettingsNumberText.parse("0", in: 0...1), 0)
        XCTAssertEqual(SettingsNumberText.parse("1", in: 0...1), 1)
        XCTAssertNil(SettingsNumberText.parse("1.0001", in: 0...1))
        XCTAssertNil(SettingsNumberText.parse("-0.0001", in: 0...1))
    }

    func testANumberOutsideTheRangeIsRejected() {
        XCTAssertNil(SettingsNumberText.parse("5", in: 6...10))
        XCTAssertNil(SettingsNumberText.parse("11", in: 6...10))
        XCTAssertNil(SettingsNumberText.parse("-1", in: 0...10))
    }

    func testTextThatIsNotANumberIsRejected() {
        XCTAssertNil(SettingsNumberText.parse("", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("   ", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("abc", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("2.8mm", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("2.8.1", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("2,8,1", in: 0...10))
        XCTAssertNil(SettingsNumberText.parse("--5", in: -10...10))
        XCTAssertNil(SettingsNumberText.parse("5 6", in: 0...10))
    }

    func testNonFiniteNumbersAreRejectedEvenInAnInfiniteRange() {
        let everything = -Double.infinity...Double.infinity
        XCTAssertNil(SettingsNumberText.parse("nan", in: everything))
        XCTAssertNil(SettingsNumberText.parse("NaN", in: everything))
        XCTAssertNil(SettingsNumberText.parse("inf", in: everything))
        XCTAssertNil(SettingsNumberText.parse("-inf", in: everything))
        XCTAssertNil(SettingsNumberText.parse("infinity", in: everything))
        XCTAssertNil(SettingsNumberText.parse("1e999", in: everything))
    }

    func testTextOfMoreThanSixteenCharactersIsRejected() {
        let wide = 0...1e18
        XCTAssertEqual(SettingsNumberText.parse("1234567890123456", in: wide), 1_234_567_890_123_456)
        XCTAssertNil(SettingsNumberText.parse("12345678901234567", in: wide))
        // The limit counts the trimmed text.
        XCTAssertEqual(SettingsNumberText.parse("   1234567890123456   ", in: wide), 1_234_567_890_123_456)
        XCTAssertNil(SettingsNumberText.parse("0.000000000000000001", in: 0...1))
    }

    // MARK: Writing

    func testAWholeNumberHasNoDecimalMark() {
        XCTAssertEqual(SettingsNumberText.text(for: 24, fractionDigits: 1), "24")
        XCTAssertEqual(SettingsNumberText.text(for: 0, fractionDigits: 2), "0")
        XCTAssertEqual(SettingsNumberText.text(for: 5.0, fractionDigits: 3), "5")
    }

    func testTrailingZerosAreDropped() {
        XCTAssertEqual(SettingsNumberText.text(for: 2.8, fractionDigits: 1), "2.8")
        XCTAssertEqual(SettingsNumberText.text(for: 2.5, fractionDigits: 3), "2.5")
        XCTAssertEqual(SettingsNumberText.text(for: 0.5, fractionDigits: 4), "0.5")
    }

    func testTheFractionIsLimitedToTheGivenDigits() {
        XCTAssertEqual(SettingsNumberText.text(for: 2.84, fractionDigits: 1), "2.8")
        XCTAssertEqual(SettingsNumberText.text(for: 12.3456, fractionDigits: 2), "12.35")
        XCTAssertEqual(SettingsNumberText.text(for: 12.3, fractionDigits: 0), "12")
        XCTAssertEqual(SettingsNumberText.text(for: 12.7, fractionDigits: 0), "13")
    }

    func testTheTextUsesAPointAndNoGroupingWhateverTheLocale() {
        XCTAssertEqual(SettingsNumberText.text(for: 1_234_567.5, fractionDigits: 1), "1234567.5")
        XCTAssertEqual(SettingsNumberText.text(for: 1e15, fractionDigits: 0), "1000000000000000")
        XCTAssertEqual(SettingsNumberText.text(for: 1234.5, fractionDigits: 2), "1234.5")
    }

    func testANegativeNumberKeepsAHyphenMinus() {
        XCTAssertEqual(SettingsNumberText.text(for: -3.5, fractionDigits: 1), "-3.5")
        XCTAssertEqual(SettingsNumberText.text(for: -60, fractionDigits: 0), "-60")
    }

    func testNoNumberGivesEmptyText() {
        XCTAssertEqual(SettingsNumberText.text(for: nil, fractionDigits: 2), "")
        XCTAssertEqual(SettingsNumberText.text(for: Double.nan, fractionDigits: 2), "")
        XCTAssertEqual(SettingsNumberText.text(for: Double.infinity, fractionDigits: 2), "")
        XCTAssertEqual(SettingsNumberText.text(for: -Double.infinity, fractionDigits: 2), "")
    }

    func testWrittenTextCanBeReadBack() {
        for value in [2.8, 24.0, 0.95, 135.0, 4.5, -12.5, 1010.0] {
            let text = SettingsNumberText.text(for: value, fractionDigits: 2)
            XCTAssertEqual(SettingsNumberText.parse(text, in: -2000...2000), value, "\(value) became \"\(text)\"")
        }
    }
}

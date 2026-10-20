import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `SettingsFormat`: coordinates, elevations, accuracies and time zones as Settings and Onboarding show them.
final class SettingsFormatTests: XCTestCase {
    private let minus = "\u{2212}"
    private let noBreakSpace = "\u{00A0}"
    private let plusMinus = "\u{00B1}"
    private let anyDate = Date(timeIntervalSince1970: 0)
    /// 2024-07-01 12:00 UTC, in daylight saving time in the northern hemisphere.
    private let july = Date(timeIntervalSince1970: 1_719_835_200)
    /// 2024-01-15 12:00 UTC, in winter in the northern hemisphere.
    private let january = Date(timeIntervalSince1970: 1_705_320_000)

    private func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: Coordinates

    func testCoordinatesHaveFourDecimalsAndHemisphereLetters() {
        let boulder = GeographicLocation(latitude: 40.015, longitude: -105.2705)
        XCTAssertEqual(SettingsFormat.coordinates(of: boulder), "40.0150\u{00B0} N, 105.2705\u{00B0} W")
        let sydney = GeographicLocation(latitude: -33.8688, longitude: 151.2093)
        XCTAssertEqual(SettingsFormat.coordinates(of: sydney), "33.8688\u{00B0} S, 151.2093\u{00B0} E")
    }

    func testCoordinatesAtTheOriginAreNorthAndEast() {
        XCTAssertEqual(SettingsFormat.coordinates(of: GeographicLocation(latitude: 0, longitude: 0)),
                       "0.0000\u{00B0} N, 0.0000\u{00B0} E")
    }

    func testCoordinatesAtTheAntimeridianAreEast() {
        XCTAssertEqual(SettingsFormat.coordinates(of: GeographicLocation(latitude: 10, longitude: 180)),
                       "10.0000\u{00B0} N, 180.0000\u{00B0} E")
        XCTAssertEqual(SettingsFormat.coordinates(of: GeographicLocation(latitude: 90, longitude: 0)),
                       "90.0000\u{00B0} N, 0.0000\u{00B0} E")
    }

    // MARK: Elevation

    func testElevationIsWholeMetresWithANonBreakingSpace() {
        XCTAssertEqual(SettingsFormat.elevation(1650), "1650\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.elevation(0), "0\(noBreakSpace)m")
    }

    func testElevationIsRoundedToTheNearestMetre() {
        XCTAssertEqual(SettingsFormat.elevation(1650.4), "1650\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.elevation(1650.6), "1651\(noBreakSpace)m")
    }

    func testElevationHasNoGroupingSeparator() {
        XCTAssertEqual(SettingsFormat.elevation(12000), "12000\(noBreakSpace)m")
    }

    func testANegativeElevationEndsInMetres() {
        let text = SettingsFormat.elevation(-50)
        XCTAssertTrue(text.hasSuffix("\(noBreakSpace)m"))
        XCTAssertEqual(digits(text), "50")
    }

    // MARK: Accuracy

    func testAnInvalidAccuracyIsThePlaceholder() {
        XCTAssertEqual(SettingsFormat.accuracy(metres: .nan), AppFormat.missing)
        XCTAssertEqual(SettingsFormat.accuracy(metres: .infinity), AppFormat.missing)
        XCTAssertEqual(SettingsFormat.accuracy(metres: -1), AppFormat.missing)
    }

    func testAnAccuracyBelowAKilometreIsWholeMetres() {
        XCTAssertEqual(SettingsFormat.accuracy(metres: 35), "\(plusMinus)35\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 0), "\(plusMinus)0\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 34.6), "\(plusMinus)35\(noBreakSpace)m")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 999), "\(plusMinus)999\(noBreakSpace)m")
    }

    func testAnAccuracyOfAKilometreOrMoreIsKilometresWithOneDecimal() {
        let text = SettingsFormat.accuracy(metres: 2400)
        XCTAssertTrue(text.hasPrefix(plusMinus))
        XCTAssertTrue(text.hasSuffix("\(noBreakSpace)km"))
        XCTAssertEqual(digits(text), "24")
        XCTAssertEqual(digits(SettingsFormat.accuracy(metres: 1000)), "10")
        XCTAssertEqual(digits(SettingsFormat.accuracy(metres: 15_000)), "150")
    }

    func testAnAccuracyInAnEnglishLocaleUsesAPointForTheDecimalMark() throws {
        try XCTSkipUnless(Locale.autoupdatingCurrent.decimalSeparator == ".", "The decimal mark follows the user's locale.")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 2400), "\(plusMinus)2.4\(noBreakSpace)km")
        XCTAssertEqual(SettingsFormat.accuracy(metres: 1000), "\(plusMinus)1.0\(noBreakSpace)km")
    }

    // MARK: UTC offset

    func testWholeHourOffsetsHaveNoMinutes() {
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: -6 * 3600)!, at: anyDate), "UTC\(minus)6")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 2 * 3600)!, at: anyDate), "UTC+2")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 0)!, at: anyDate), "UTC+0")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 12 * 3600)!, at: anyDate), "UTC+12")
    }

    func testPartHourOffsetsShowTheMinutes() {
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!, at: anyDate), "UTC+5:30")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 5 * 3600 + 45 * 60)!, at: anyDate), "UTC+5:45")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: -(3 * 3600 + 1800))!, at: anyDate), "UTC\(minus)3:30")
    }

    func testMinutesBelowTenAreZeroPadded() {
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 5 * 3600 + 5 * 60)!, at: anyDate), "UTC+5:05")
    }

    func testAnOffsetOfLessThanAnHourKeepsItsSign() {
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: -1800)!, at: anyDate), "UTC\(minus)0:30")
        XCTAssertEqual(SettingsFormat.utcOffset(of: TimeZone(secondsFromGMT: 1800)!, at: anyDate), "UTC+0:30")
    }

    func testTheOffsetOfARegionalZoneFollowsDaylightSavingTime() throws {
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertEqual(SettingsFormat.utcOffset(of: denver, at: july), "UTC\(minus)6")
        XCTAssertEqual(SettingsFormat.utcOffset(of: denver, at: january), "UTC\(minus)7")
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(SettingsFormat.utcOffset(of: kolkata, at: july), "UTC+5:30")
    }

    // MARK: Nominal zones

    func testAFixedOffsetZoneIsNominal() {
        XCTAssertTrue(SettingsFormat.isNominal(TimeZone(secondsFromGMT: 3600)!))
        XCTAssertTrue(SettingsFormat.isNominal(TimeZone(secondsFromGMT: -6 * 3600)!))
        XCTAssertTrue(SettingsFormat.isNominal(TimeZone(secondsFromGMT: 0)!))
    }

    func testARegionalZoneIsNotNominal() throws {
        XCTAssertFalse(SettingsFormat.isNominal(try XCTUnwrap(TimeZone(identifier: "America/Denver"))))
        XCTAssertFalse(SettingsFormat.isNominal(try XCTUnwrap(TimeZone(identifier: "Europe/London"))))
    }

    // MARK: Describing a zone

    func testARegionalZoneIsDescribedByNameAndOffset() throws {
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertEqual(SettingsFormat.describe(denver, at: july), "America/Denver \u{00B7} UTC\(minus)6")
        XCTAssertEqual(SettingsFormat.describe(denver, at: january), "America/Denver \u{00B7} UTC\(minus)7")
    }

    func testUnderscoresInAZoneNameBecomeSpaces() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(SettingsFormat.describe(newYork, at: july), "America/New York \u{00B7} UTC\(minus)4")
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(SettingsFormat.describe(kolkata, at: july), "Asia/Kolkata \u{00B7} UTC+5:30")
    }

    func testAnEstimatedZoneIsDescribedByItsOffsetAlone() {
        XCTAssertEqual(SettingsFormat.describe(TimeZone(secondsFromGMT: -6 * 3600)!, at: july),
                       "UTC\(minus)6 (estimated from longitude)")
        XCTAssertEqual(SettingsFormat.describe(TimeZone(secondsFromGMT: 5 * 3600 + 1800)!, at: july),
                       "UTC+5:30 (estimated from longitude)")
    }
}

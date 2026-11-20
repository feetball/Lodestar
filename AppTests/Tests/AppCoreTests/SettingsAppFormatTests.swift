import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `AppFormat`: times in the observer's zone, angles in the chosen coordinate style, and the placeholders.
///
/// Times, dates and magnitudes follow the user's locale in the code under test, so the tests compare them with each
/// other, or read only their digits, rather than spelling out a locale's text.
final class SettingsAppFormatTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let plusThree = TimeZone(secondsFromGMT: 3 * 3600)!
    private let plusFiveThirty = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!
    private let epoch = Date(timeIntervalSince1970: 0)
    private let minus = "\u{2212}"
    private let dash = "\u{2014}"

    /// The ASCII digits of `text`, with everything else dropped.
    private func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: Placeholder

    func testThePlaceholderIsAnEmDash() {
        XCTAssertEqual(AppFormat.missing, dash)
    }

    // MARK: Time

    func testAMissingTimeIsThePlaceholder() {
        XCTAssertEqual(AppFormat.time(nil, in: utc), dash)
    }

    func testATimeIsShownInTheGivenZone() {
        // Midnight UTC and the same instant at UTC+3 (03:00) differ; the wall time 00:00 at UTC+3 is three hours earlier.
        XCTAssertNotEqual(AppFormat.time(epoch, in: utc), AppFormat.time(epoch, in: plusThree))
        XCTAssertEqual(AppFormat.time(epoch, in: utc), AppFormat.time(Date(timeIntervalSince1970: -3 * 3600), in: plusThree))
        XCTAssertFalse(AppFormat.time(epoch, in: utc).isEmpty)
    }

    func testATimeDoesNotDependOnTheDate() {
        let sameWallTimeNextDay = Date(timeIntervalSince1970: 86_400)
        XCTAssertEqual(AppFormat.time(epoch, in: utc), AppFormat.time(sameWallTimeNextDay, in: utc))
    }

    func testADateAndTimeIsShownInTheGivenZone() {
        XCTAssertEqual(AppFormat.dateTime(epoch, in: utc), AppFormat.dateTime(Date(timeIntervalSince1970: -3 * 3600), in: plusThree))
        XCTAssertNotEqual(AppFormat.dateTime(epoch, in: utc), AppFormat.dateTime(epoch, in: plusThree))
        // A zone that is ahead enough moves the date, not only the time.
        let lateEvening = Date(timeIntervalSince1970: 23 * 3600)
        XCTAssertNotEqual(AppFormat.dateTime(lateEvening, in: utc), AppFormat.dateTime(lateEvening, in: plusFiveThirty))
    }

    func testADayFollowsTheDateInTheGivenZone() {
        XCTAssertEqual(AppFormat.day(epoch, in: utc), AppFormat.day(Date(timeIntervalSince1970: -3 * 3600), in: plusThree))
        XCTAssertNotEqual(AppFormat.day(epoch, in: utc), AppFormat.day(Date(timeIntervalSince1970: 86_400), in: utc))
        // 23:00 UTC on 1 January is already 2 January at UTC+5:30.
        let lateEvening = Date(timeIntervalSince1970: 23 * 3600)
        XCTAssertNotEqual(AppFormat.day(lateEvening, in: utc), AppFormat.day(lateEvening, in: plusFiveThirty))
        XCTAssertEqual(AppFormat.day(lateEvening, in: plusFiveThirty), AppFormat.day(Date(timeIntervalSince1970: 86_400), in: utc))
    }

    func testADayShowsNoTimeOfDay() {
        XCTAssertEqual(AppFormat.day(epoch, in: utc), AppFormat.day(Date(timeIntervalSince1970: 7 * 3600), in: utc))
    }

    // MARK: Relative

    func testARelativeTimeInTheFutureReadsIn() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(7_500), from: now), "in 2h 05m")
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(30), from: now), "in 30s")
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(270), from: now), "in 4m 30s")
    }

    func testARelativeTimeInThePastReadsAgo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(-330), from: now), "5m 30s ago")
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(-3_600), from: now), "1h 00m ago")
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(-45), from: now), "45s ago")
    }

    func testARelativeTimeOfZeroReadsIn() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AppFormat.relative(now, from: now), "in 0s")
    }

    func testARelativeTimeRoundsUpToTheNextUnit() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(59.6), from: now), "in 1m 00s")
        XCTAssertEqual(AppFormat.relative(now.addingTimeInterval(7_180), from: now), "in 2h 00m")
    }

    // MARK: Right ascension and declination

    func testRightAscensionInTheSexagesimalStyle() {
        let coordinate = EquatorialCoordinate(rightAscensionHours: 5.5, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(coordinate, style: .sexagesimal), "05h 30m 00.0s")
        let other = EquatorialCoordinate(rightAscensionHours: 18.6153, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(other, style: .sexagesimal), "18h 36m 55.1s")
    }

    func testRightAscensionOfZeroIsMidnight() {
        let coordinate = EquatorialCoordinate(rightAscensionHours: 0, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(coordinate, style: .sexagesimal), "00h 00m 00.0s")
    }

    func testRightAscensionJustBelowTwentyFourHoursCarriesToZero() {
        // 23h 59m 59.97s rounds to the next whole hour, which is 00h.
        let carried = EquatorialCoordinate(rightAscensionHours: 23.999991667, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(carried, style: .sexagesimal), "00h 00m 00.0s")
        // 23h 59m 59.93s does not.
        let notCarried = EquatorialCoordinate(rightAscensionHours: 23.99998, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(notCarried, style: .sexagesimal), "23h 59m 59.9s")
    }

    func testRightAscensionInTheDecimalStyleIsDegreesWithThreeDecimals() {
        let coordinate = EquatorialCoordinate(rightAscensionHours: 5.5, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(coordinate, style: .decimal), "82.500\u{00B0}")
        let zero = EquatorialCoordinate(rightAscension: 0, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(zero, style: .decimal), "0.000\u{00B0}")
        let high = EquatorialCoordinate(rightAscension: 359.99, declination: 0)
        XCTAssertEqual(AppFormat.rightAscension(high, style: .decimal), "359.990\u{00B0}")
    }

    func testDeclinationInTheSexagesimalStyle() {
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 45.25), style: .sexagesimal),
                       "+45\u{00B0} 15\u{2032} 00\u{2033}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: -5.5), style: .sexagesimal),
                       "\(minus)05\u{00B0} 30\u{2032} 00\u{2033}")
        let orionLike = EquatorialCoordinate(rightAscension: 0, declination: 41.0 + 16.0 / 60.0 + 9.0 / 3600.0)
        XCTAssertEqual(AppFormat.declination(orionLike, style: .sexagesimal), "+41\u{00B0} 16\u{2032} 09\u{2033}")
    }

    func testDeclinationRoundsAndCarriesUpward() {
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 29.99999), style: .sexagesimal),
                       "+30\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 89.9999), style: .sexagesimal),
                       "+90\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: -29.99999), style: .sexagesimal),
                       "\(minus)30\u{00B0} 00\u{2032} 00\u{2033}")
    }

    func testADeclinationThatRoundsToZeroCarriesAPlusSign() {
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: -0.0001), style: .sexagesimal),
                       "+00\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: -0.0001), style: .decimal),
                       "+0.000\u{00B0}")
    }

    func testDeclinationInTheDecimalStyleHasASignAndThreeDecimals() {
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 45.25), style: .decimal),
                       "+45.250\u{00B0}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: -5.5), style: .decimal),
                       "\(minus)5.500\u{00B0}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 0), style: .decimal),
                       "+0.000\u{00B0}")
        XCTAssertEqual(AppFormat.declination(EquatorialCoordinate(rightAscension: 0, declination: 41.2692), style: .decimal),
                       "+41.269\u{00B0}")
    }

    // MARK: Altitude and azimuth

    func testAltitudeHasASignAndOneDecimal() {
        XCTAssertEqual(AppFormat.altitude(34.2), "+34.2\u{00B0}")
        XCTAssertEqual(AppFormat.altitude(-5.26), "\(minus)5.3\u{00B0}")
        XCTAssertEqual(AppFormat.altitude(90), "+90.0\u{00B0}")
        XCTAssertEqual(AppFormat.altitude(0), "+0.0\u{00B0}")
    }

    func testAnAltitudeThatRoundsToZeroIsPositive() {
        XCTAssertEqual(AppFormat.altitude(-0.04), "+0.0\u{00B0}")
        XCTAssertEqual(AppFormat.altitude(0.04), "+0.0\u{00B0}")
    }

    func testAnUnknownAltitudeIsThePlaceholder() {
        XCTAssertEqual(AppFormat.altitude(.nan), dash)
        XCTAssertEqual(AppFormat.altitude(.infinity), dash)
    }

    func testAzimuthShowsTheDegreesAndTheCompassPoint() {
        XCTAssertEqual(AppFormat.azimuth(0), "0.0\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(90), "90.0\u{00B0} E")
        XCTAssertEqual(AppFormat.azimuth(135), "135.0\u{00B0} SE")
        XCTAssertEqual(AppFormat.azimuth(180), "180.0\u{00B0} S")
        XCTAssertEqual(AppFormat.azimuth(270), "270.0\u{00B0} W")
        XCTAssertEqual(AppFormat.azimuth(123.4), "123.4\u{00B0} ESE")
    }

    func testAzimuthJustBelowAFullTurnWrapsToNorthNever360() {
        XCTAssertEqual(AppFormat.azimuth(359.99), "0.0\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(359.96), "0.0\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(359.94), "359.9\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(360), "0.0\u{00B0} N")
    }

    func testAzimuthIsWrappedIntoOneTurn() {
        XCTAssertEqual(AppFormat.azimuth(-90), "270.0\u{00B0} W")
        XCTAssertEqual(AppFormat.azimuth(450), "90.0\u{00B0} E")
    }

    func testTheCompassPointChangesAtTheLowerBoundaryOfASector() {
        // Each sector includes its lower boundary: 348.75 is north, 11.25 is north-northeast.
        XCTAssertEqual(AppFormat.azimuth(348.75), "348.8\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(348.7), "348.7\u{00B0} NNW")
        XCTAssertEqual(AppFormat.azimuth(11.2), "11.2\u{00B0} N")
        XCTAssertEqual(AppFormat.azimuth(11.25), "11.3\u{00B0} NNE")
    }

    // MARK: Separation

    func testAnUnknownSeparationIsThePlaceholder() {
        XCTAssertEqual(AppFormat.separation(.nan), dash)
        XCTAssertEqual(AppFormat.separation(.infinity), dash)
        XCTAssertEqual(AppFormat.separation(-.infinity), dash)
    }

    func testLargeSeparationsAreWholeDegrees() {
        XCTAssertEqual(AppFormat.separation(12.3), "12\u{00B0}")
        XCTAssertEqual(AppFormat.separation(10), "10\u{00B0}")
        XCTAssertEqual(AppFormat.separation(180), "180\u{00B0}")
    }

    func testSeparationsFromOneToTenDegreesHaveOneDecimal() {
        XCTAssertEqual(AppFormat.separation(9.9), "9.9\u{00B0}")
        XCTAssertEqual(AppFormat.separation(3.4), "3.4\u{00B0}")
        XCTAssertEqual(AppFormat.separation(1), "1.0\u{00B0}")
    }

    func testSeparationsBelowOneDegreeAreWholeArcminutes() {
        XCTAssertEqual(AppFormat.separation(0.75), "45\u{2032}")
        XCTAssertEqual(AppFormat.separation(0.5), "30\u{2032}")
        XCTAssertEqual(AppFormat.separation(0.1), "6\u{2032}")
        XCTAssertEqual(AppFormat.separation(0.0333333), "2\u{2032}")
    }

    func testSeparationsBelowOneArcminuteAreWholeArcseconds() {
        XCTAssertEqual(AppFormat.separation(0.01), "36\u{2033}")
        XCTAssertEqual(AppFormat.separation(0.001), "4\u{2033}")
        XCTAssertEqual(AppFormat.separation(0.0001), "0\u{2033}")
        XCTAssertEqual(AppFormat.separation(0), "0\u{2033}")
    }

    func testSeparationJustBelowTheNextUnitStaysInTheSmallerUnit() {
        // 59.4 arcminutes and 59.4 arcseconds do not round up to a whole degree or minute.
        XCTAssertEqual(AppFormat.separation(0.99), "59\u{2032}")
        XCTAssertEqual(AppFormat.separation(0.0165), "59\u{2033}")
    }

    func testSeparationIsAMagnitudeSoTheSignIsDropped() {
        XCTAssertEqual(AppFormat.separation(-12.3), "12\u{00B0}")
        XCTAssertEqual(AppFormat.separation(-0.5), "30\u{2032}")
        XCTAssertEqual(AppFormat.separation(-0.01), "36\u{2033}")
    }

    // MARK: Magnitude

    func testAnUnknownMagnitudeIsThePlaceholder() {
        XCTAssertEqual(AppFormat.magnitude(nil), dash)
        XCTAssertEqual(AppFormat.magnitude(Double.nan), dash)
        XCTAssertEqual(AppFormat.magnitude(Double.infinity), dash)
        XCTAssertEqual(AppFormat.magnitude(-Double.infinity), dash)
    }

    func testAMagnitudeIsPrefixedAndHasOneDecimal() {
        let text = AppFormat.magnitude(3.4)
        XCTAssertTrue(text.hasPrefix("mag "))
        XCTAssertEqual(digits(text), "34")
        XCTAssertFalse(text.contains(minus))
        XCTAssertEqual(digits(AppFormat.magnitude(12.34)), "123")
        XCTAssertEqual(digits(AppFormat.magnitude(0)), "00")
    }

    func testANegativeMagnitudeUsesTheTypographicMinus() {
        let text = AppFormat.magnitude(-1.5)
        XCTAssertTrue(text.hasPrefix("mag \(minus)"))
        XCTAssertEqual(digits(text), "15")
        XCTAssertFalse(text.contains("-"))
    }

    func testAMagnitudeThatRoundsToZeroHasNoMinusSign() {
        let text = AppFormat.magnitude(-0.04)
        XCTAssertFalse(text.contains(minus))
        XCTAssertFalse(text.contains("-"))
        XCTAssertEqual(digits(text), "00")
        // -0.06 rounds to -0.1, which keeps its sign.
        let small = AppFormat.magnitude(-0.06)
        XCTAssertTrue(small.hasPrefix("mag \(minus)"))
        XCTAssertEqual(digits(small), "01")
    }

    func testAMagnitudeInAnEnglishLocaleUsesAPointForTheDecimalMark() throws {
        try XCTSkipUnless(Locale.autoupdatingCurrent.decimalSeparator == ".", "The decimal mark follows the user's locale.")
        XCTAssertEqual(AppFormat.magnitude(3.4), "mag 3.4")
        XCTAssertEqual(AppFormat.magnitude(-1.5), "mag \(minus)1.5")
        XCTAssertEqual(AppFormat.magnitude(-0.04), "mag 0.0")
        XCTAssertEqual(AppFormat.magnitude(12.34), "mag 12.3")
    }

    // MARK: Percent

    func testAnUnknownPercentIsThePlaceholder() {
        XCTAssertEqual(AppFormat.percent(nil), dash)
        XCTAssertEqual(AppFormat.percent(Double.nan), dash)
        XCTAssertEqual(AppFormat.percent(Double.infinity), dash)
    }

    func testAPercentIsWholeNumbers() {
        XCTAssertEqual(AppFormat.percent(0.64), "64%")
        XCTAssertEqual(AppFormat.percent(0), "0%")
        XCTAssertEqual(AppFormat.percent(1), "100%")
        XCTAssertEqual(AppFormat.percent(0.5), "50%")
    }

    func testAPercentRoundsToTheNearestWholeNumber() {
        XCTAssertEqual(AppFormat.percent(0.994), "99%")
        XCTAssertEqual(AppFormat.percent(0.996), "100%")
        XCTAssertEqual(AppFormat.percent(0.004), "0%")
    }

    func testAPercentOutsideZeroToOneIsNotClamped() {
        XCTAssertEqual(AppFormat.percent(1.5), "150%")
        XCTAssertEqual(AppFormat.percent(-0.2), "-20%")
    }
}

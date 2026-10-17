import Foundation
import XCTest
@testable import LodestarKit

// U+2212 MINUS SIGN, written out so the tests cannot silently compare against a hyphen.
private let minus = "\u{2212}"

private func isASCII(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy(\.isASCII)
}

// MARK: - Formatting angles and coordinates

final class AngleFormatterTests: XCTestCase {

    // MARK: Right ascension

    func testRightAscensionOfOrionNebula() {
        let hours = 5.0 + 35.0 / 60 + 17.3 / 3600
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours), "05h 35m 17.3s")
    }

    func testRightAscensionZeroAndWholeHours() {
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 0), "00h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: -0.0), "00h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 12.5), "12h 30m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 23), "23h 00m 00.0s")
    }

    func testRightAscensionSecondsDecimals() {
        let hours = 5.0 + 35.0 / 60 + 17.3 / 3600
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: 0), "05h 35m 17s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: 2), "05h 35m 17.30s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: 3), "05h 35m 17.300s")
    }

    func testRightAscensionDecimalsAreClamped() {
        let hours = 5.0 + 35.0 / 60 + 17.3 / 3600
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: -4), "05h 35m 17s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: 99), "05h 35m 17.300000s")
    }

    func testRightAscensionRoundingCarriesIntoMinutesAndHours() {
        // 59.96 s at one decimal rounds to 60.0 s, which must carry rather than print "60.0s".
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 5 + 35.0 / 60 + 59.96 / 3600), "05h 36m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 5 + 59.0 / 60 + 59.96 / 3600), "06h 00m 00.0s")
        // Kept at two decimals the same value needs no carry.
        XCTAssertEqual(
            AngleFormatter.formatRightAscension(hours: 5 + 35.0 / 60 + 59.96 / 3600, secondsDecimals: 2),
            "05h 35m 59.96s"
        )
        // 59.96 s with no decimals rounds up as well.
        XCTAssertEqual(
            AngleFormatter.formatRightAscension(hours: 5 + 35.0 / 60 + 59.6 / 3600, secondsDecimals: 0),
            "05h 36m 00s"
        )
    }

    func testRightAscensionWrapsTwentyFourHoursToZero() {
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 23 + 59.0 / 60 + 59.99 / 3600), "00h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 23.99999999), "00h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 23.9999), "23h 59m 59.6s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 24), "00h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 25.5), "01h 30m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: 48), "00h 00m 00.0s")
    }

    func testRightAscensionNegativeValuesWrap() {
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: -1), "23h 00m 00.0s")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: -0.5), "23h 30m 00.0s")
        // A negative value that rounds to a whole 24 hours must not print "24h".
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: -1e-20), "00h 00m 00.0s")
    }

    func testRightAscensionNonFiniteAndHugeInput() {
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: .nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: .infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: -.infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatRightAscension(hours: .nan, style: .ascii), "--")
        let huge = AngleFormatter.formatRightAscension(hours: 1e300)
        XCTAssertTrue(huge.hasSuffix("s"))
        XCTAssertNotEqual(huge, "\u{2014}")
    }

    // MARK: Declination

    func testDeclinationNegative() {
        let degrees = -(5.0 + 23.0 / 60 + 28.0 / 3600)
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: degrees), "\(minus)05\u{00B0} 23\u{2032} 28\u{2033}")
    }

    func testDeclinationPositiveHasPlusSign() {
        let degrees = 41.0 + 16.0 / 60 + 9.0 / 3600
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: degrees), "+41\u{00B0} 16\u{2032} 09\u{2033}")
    }

    func testDeclinationZeroHasPlusSignEvenWhenNegativeZero() {
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 0), "+00\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -0.0), "+00\u{00B0} 00\u{2032} 00\u{2033}")
        // -0.36 arcsecond rounds to zero and must not read "-00° 00′ 00″".
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -0.0001), "+00\u{00B0} 00\u{2032} 00\u{2033}")
    }

    func testDeclinationKeepsSignWhenDegreesAreZero() {
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -0.5), "\(minus)00\u{00B0} 30\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 0.5), "+00\u{00B0} 30\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -1.0 / 3600), "\(minus)00\u{00B0} 00\u{2032} 01\u{2033}")
    }

    func testDeclinationSecondsDecimals() {
        let degrees = -(5.0 + 23.0 / 60 + 28.0 / 3600)
        XCTAssertEqual(
            AngleFormatter.formatDeclination(degrees: degrees, secondsDecimals: 1),
            "\(minus)05\u{00B0} 23\u{2032} 28.0\u{2033}"
        )
        XCTAssertEqual(
            AngleFormatter.formatDeclination(degrees: 12.345678, secondsDecimals: 2),
            "+12\u{00B0} 20\u{2032} 44.44\u{2033}"
        )
    }

    func testDeclinationRoundingCarries() {
        // 59.6 arcseconds round up to the next arcminute, and 59′ 59.6″ up to the next degree.
        XCTAssertEqual(
            AngleFormatter.formatDeclination(degrees: 10 + 59.0 / 60 + 59.6 / 3600),
            "+11\u{00B0} 00\u{2032} 00\u{2033}"
        )
        XCTAssertEqual(
            AngleFormatter.formatDeclination(degrees: 10 + 20.0 / 60 + 59.6 / 3600),
            "+10\u{00B0} 21\u{2032} 00\u{2033}"
        )
        XCTAssertEqual(
            AngleFormatter.formatDeclination(degrees: -(10 + 59.0 / 60 + 59.96 / 3600), secondsDecimals: 1),
            "\(minus)11\u{00B0} 00\u{2032} 00.0\u{2033}"
        )
    }

    func testDeclinationPolesAndClamping() {
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 90), "+90\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -90), "\(minus)90\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 89.99999), "+90\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 91), "+90\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -200), "\(minus)90\u{00B0} 00\u{2032} 00\u{2033}")
    }

    func testDeclinationNonFinite() {
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: .nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: .infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: -.infinity, style: .ascii), "--")
    }

    func testDeclinationAsciiStyle() {
        let degrees = -(5.0 + 23.0 / 60 + 28.0 / 3600)
        let text = AngleFormatter.formatDeclination(degrees: degrees, style: .ascii)
        XCTAssertEqual(text, "-05d 23' 28\"")
        XCTAssertTrue(isASCII(text))
        XCTAssertEqual(AngleFormatter.formatDeclination(degrees: 41.27, style: .ascii), "+41d 16' 12\"")
    }

    // MARK: Decimal degrees

    func testFormatDegrees() {
        XCTAssertEqual(AngleFormatter.formatDegrees(123.4), "123.4\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(0), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(-12.34), "\(minus)12.3\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(45.678, decimals: 2), "45.68\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(123.5, decimals: 0), "124\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(-123.5, decimals: 0), "\(minus)124\u{00B0}")
    }

    func testFormatDegreesDoesNotWrap() {
        XCTAssertEqual(AngleFormatter.formatDegrees(359.96), "360.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(720), "720.0\u{00B0}")
    }

    func testFormatDegreesNeverPrintsNegativeZero() {
        XCTAssertEqual(AngleFormatter.formatDegrees(-0.0), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(-0.04), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatDegrees(-0.05), "\(minus)0.1\u{00B0}")
    }

    func testFormatDegreesNonFiniteAndHuge() {
        XCTAssertEqual(AngleFormatter.formatDegrees(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDegrees(.infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDegrees(1e300), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDegrees(.nan, style: .ascii), "--")
    }

    func testFormatDegreesAsciiStyle() {
        XCTAssertEqual(AngleFormatter.formatDegrees(123.4, style: .ascii), "123.4d")
        XCTAssertEqual(AngleFormatter.formatDegrees(-12.34, style: .ascii), "-12.3d")
    }

    func testFormatSignedDegrees() {
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(45.34), "+45.3\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(-5.2), "\(minus)5.2\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(0), "+0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(-0.04), "+0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(-90, decimals: 0), "\(minus)90\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatSignedDegrees(-5.2, style: .ascii), "-5.2d")
    }

    func testFormatAzimuthWrapsAfterRounding() {
        XCTAssertEqual(AngleFormatter.formatAzimuth(123.4), "123.4\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(0), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(359.94), "359.9\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(359.96), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(360), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(-10), "350.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(720.5), "0.5\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(-1e-20), "0.0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(359.5, decimals: 0), "0\u{00B0}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatAzimuth(123.4, style: .ascii), "123.4d")
    }

    func testFormatDMS() {
        XCTAssertEqual(AngleFormatter.formatDMS(123.4567), "123\u{00B0} 27\u{2032} 24\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(123.4567, secondsDecimals: 2), "123\u{00B0} 27\u{2032} 24.12\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(0), "0\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(5 + 3.0 / 60 + 8.0 / 3600), "5\u{00B0} 03\u{2032} 08\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(-5.5), "\(minus)5\u{00B0} 30\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(-0.5), "\(minus)0\u{00B0} 30\u{2032} 00\u{2033}")
    }

    func testFormatDMSCarriesAndSigns() {
        XCTAssertEqual(AngleFormatter.formatDMS(359.99999), "360\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(10 + 59.0 / 60 + 59.6 / 3600), "11\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(-0.0), "0\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(-0.0001), "0\u{00B0} 00\u{2032} 00\u{2033}")
        XCTAssertEqual(AngleFormatter.formatDMS(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDMS(1e300), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDMS(-5.5, style: .ascii), "-5d 30' 00\"")
    }

    // MARK: Latitude and longitude

    func testLatitude() {
        XCTAssertEqual(AngleFormatter.formatLatitude(40.015), "40.0150\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(-33.8688), "33.8688\u{00B0} S")
        XCTAssertEqual(AngleFormatter.formatLatitude(40.0149, decimals: 2), "40.01\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(40.5, decimals: 0), "41\u{00B0} N")
    }

    func testLatitudeEdges() {
        XCTAssertEqual(AngleFormatter.formatLatitude(0), "0.0000\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(-0.0), "0.0000\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(-0.00001), "0.0000\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(90), "90.0000\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(-90), "90.0000\u{00B0} S")
        XCTAssertEqual(AngleFormatter.formatLatitude(95), "90.0000\u{00B0} N")
        XCTAssertEqual(AngleFormatter.formatLatitude(-95), "90.0000\u{00B0} S")
        XCTAssertEqual(AngleFormatter.formatLatitude(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatLatitude(40.015, style: .ascii), "40.0150d N")
    }

    func testLongitude() {
        XCTAssertEqual(AngleFormatter.formatLongitude(-105.2705), "105.2705\u{00B0} W")
        XCTAssertEqual(AngleFormatter.formatLongitude(2.3522), "2.3522\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(151.2093, decimals: 1), "151.2\u{00B0} E")
    }

    func testLongitudeWrapsIntoHalfOpenRange() {
        XCTAssertEqual(AngleFormatter.formatLongitude(0), "0.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(-0.00001), "0.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(180), "180.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(-180), "180.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(190), "170.0000\u{00B0} W")
        XCTAssertEqual(AngleFormatter.formatLongitude(-190), "170.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(360), "0.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(540), "180.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(-540), "180.0000\u{00B0} E")
    }

    func testLongitudeAntimeridianRoundingIsEast() {
        // -179.99999 rounds to 180.0000, which is written as east like 180 itself.
        XCTAssertEqual(AngleFormatter.formatLongitude(-179.99999), "180.0000\u{00B0} E")
        XCTAssertEqual(AngleFormatter.formatLongitude(-179.9999), "179.9999\u{00B0} W")
    }

    func testLongitudeNonFinite() {
        XCTAssertEqual(AngleFormatter.formatLongitude(.nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatLongitude(.infinity, style: .ascii), "--")
        XCTAssertEqual(AngleFormatter.formatLongitude(-105.2705, style: .ascii), "105.2705d W")
    }

    func testLocaleDoesNotAffectOutput() {
        // Output is built from integers, so the decimal mark is always a period.
        XCTAssertEqual(AngleFormatter.formatDegrees(1234.5), "1234.5\u{00B0}")
        XCTAssertFalse(AngleFormatter.formatLatitude(40.015).contains(","))
    }

    func testCompassPointForwarder() {
        XCTAssertEqual(AngleFormatter.compassPoint(azimuth: 90), .east)
        XCTAssertEqual(AngleFormatter.compassPoint(azimuth: 200), .southSouthwest)
    }

    func testTypographyStyleCases() {
        XCTAssertEqual(TypographyStyle.allCases, [.unicode, .ascii])
    }

    // MARK: Number helpers

    func testNumberTextHelpers() {
        XCTAssertEqual(NumberText.clampedDecimals(-3), 0)
        XCTAssertEqual(NumberText.clampedDecimals(4), 4)
        XCTAssertEqual(NumberText.clampedDecimals(60), 6)
        XCTAssertEqual(NumberText.powerOfTen(0), 1)
        XCTAssertEqual(NumberText.powerOfTen(6), 1_000_000)
        XCTAssertEqual(NumberText.powerOfTen(-2), 1)
        XCTAssertEqual(NumberText.padded(7, width: 2), "07")
        XCTAssertEqual(NumberText.padded(123, width: 2), "123")
        XCTAssertEqual(NumberText.trimmed(magnitude: 2.5, maxDecimals: 2), "2.5")
        XCTAssertEqual(NumberText.trimmed(magnitude: 13, maxDecimals: 2), "13")
        XCTAssertEqual(NumberText.trimmed(magnitude: 100, maxDecimals: 1), "100")
        XCTAssertEqual(NumberText.trimmed(magnitude: 0, maxDecimals: 2), "0")
        XCTAssertEqual(NumberText.trimmed(magnitude: 0.25, maxDecimals: 2), "0.25")
        XCTAssertEqual(NumberText.trimmed(magnitude: 9.96, maxDecimals: 1), "10")
        XCTAssertNil(NumberText.trimmed(magnitude: -1, maxDecimals: 1))
        XCTAssertNil(NumberText.trimmed(magnitude: .nan, maxDecimals: 1))
        XCTAssertNil(NumberText.fixedPoint(magnitude: 1e300, decimals: 6))
        XCTAssertNil(NumberText.sexagesimal(magnitude: 1e300, secondsDecimals: 6))
        XCTAssertNil(NumberText.sexagesimal(magnitude: -1, secondsDecimals: 0))
    }
}

// MARK: - Compass points

final class CompassPointTests: XCTestCase {

    func testSixteenPointsInCompassOrder() {
        let expected = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        XCTAssertEqual(CompassPoint.allCases.map(\.abbreviation), expected)
        XCTAssertEqual(CompassPoint.allCases.map(\.rawValue), Array(0..<16))
    }

    func testFullNames() {
        let expected = [
            "North", "North-northeast", "Northeast", "East-northeast",
            "East", "East-southeast", "Southeast", "South-southeast",
            "South", "South-southwest", "Southwest", "West-southwest",
            "West", "West-northwest", "Northwest", "North-northwest",
        ]
        XCTAssertEqual(CompassPoint.allCases.map(\.fullName), expected)
    }

    func testCenterAzimuthsAreEvenlySpaced() {
        for (index, point) in CompassPoint.allCases.enumerated() {
            XCTAssertEqual(point.centerAzimuth, Double(index) * 22.5)
        }
    }

    func testEveryCenterMapsToItself() {
        for point in CompassPoint.allCases {
            XCTAssertEqual(CompassPoint(azimuth: point.centerAzimuth), point)
            XCTAssertEqual(AngleFormatter.compassPoint(azimuth: point.centerAzimuth), point)
        }
    }

    func testBoundariesBelongToTheClockwiseSector() {
        // Boundaries lie at 11.25° + k × 22.5°. They are exact in binary floating point, and
        // each sector includes its lower boundary.
        for sector in 0..<16 {
            let boundary = 11.25 + Double(sector) * 22.5
            let next = CompassPoint.allCases[(sector + 1) % 16]
            let previous = CompassPoint.allCases[sector]
            XCTAssertEqual(CompassPoint(azimuth: boundary), next, "azimuth \(boundary)")
            XCTAssertEqual(CompassPoint(azimuth: boundary.nextDown), previous, "azimuth just below \(boundary)")
            XCTAssertEqual(CompassPoint(azimuth: boundary.nextUp), next, "azimuth just above \(boundary)")
        }
    }

    func testNorthSpansTheWrapAround() {
        XCTAssertEqual(CompassPoint(azimuth: 0), .north)
        XCTAssertEqual(CompassPoint(azimuth: 11.2499), .north)
        XCTAssertEqual(CompassPoint(azimuth: 11.25), .northNortheast)
        XCTAssertEqual(CompassPoint(azimuth: 348.7499), .northNorthwest)
        XCTAssertEqual(CompassPoint(azimuth: 348.75), .north)
        XCTAssertEqual(CompassPoint(azimuth: 359.999), .north)
        XCTAssertEqual(CompassPoint(azimuth: 360), .north)
    }

    func testAzimuthsAreWrapped() {
        XCTAssertEqual(CompassPoint(azimuth: -90), .west)
        XCTAssertEqual(CompassPoint(azimuth: -11.25), .north)
        XCTAssertEqual(CompassPoint(azimuth: -11.2501), .northNorthwest)
        XCTAssertEqual(CompassPoint(azimuth: 450), .east)
        XCTAssertEqual(CompassPoint(azimuth: 720), .north)
        XCTAssertEqual(CompassPoint(azimuth: 371.25), .northNortheast)
        XCTAssertEqual(CompassPoint(azimuth: -1e-20), .north)
        XCTAssertEqual(CompassPoint(azimuth: -360), .north)
        XCTAssertTrue(CompassPoint.allCases.contains(CompassPoint(azimuth: 1e300)))
    }

    func testNonFiniteAzimuthFallsBackToNorth() {
        XCTAssertEqual(CompassPoint(azimuth: .nan), .north)
        XCTAssertEqual(CompassPoint(azimuth: .infinity), .north)
        XCTAssertEqual(CompassPoint(azimuth: -.infinity), .north)
    }

    func testCardinalAndIntercardinalPoints() {
        XCTAssertEqual(CompassPoint(azimuth: 45), .northeast)
        XCTAssertEqual(CompassPoint(azimuth: 90), .east)
        XCTAssertEqual(CompassPoint(azimuth: 135), .southeast)
        XCTAssertEqual(CompassPoint(azimuth: 180), .south)
        XCTAssertEqual(CompassPoint(azimuth: 225), .southwest)
        XCTAssertEqual(CompassPoint(azimuth: 270), .west)
        XCTAssertEqual(CompassPoint(azimuth: 315), .northwest)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(CompassPoint.westSouthwest)
        XCTAssertEqual(try JSONDecoder().decode(CompassPoint.self, from: data), .westSouthwest)
    }
}

// MARK: - Durations and exposure times

final class DurationFormattingTests: XCTestCase {

    func testDurationUnits() {
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 0), "0s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 12), "12s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 59), "59s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 60), "1m 00s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 65), "1m 05s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 270), "4m 30s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3599), "59m 59s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3600), "1h 00m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3900), "1h 05m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 9 * 3600 + 17 * 60), "9h 17m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 25 * 3600), "25h 00m")
    }

    func testDurationRoundingCarries() {
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 11.6), "12s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 59.4), "59s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 59.6), "1m 00s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 119.5), "2m 00s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3599.4), "59m 59s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3599.6), "1h 00m")
        // Above an hour seconds are dropped by rounding to the nearest minute.
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3629), "1h 00m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 3631), "1h 01m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 7200 - 31), "1h 59m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 7200 - 29), "2h 00m")
    }

    func testNegativeDurations() {
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -270), "\(minus)4m 30s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -3900), "\(minus)1h 05m")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -12), "\(minus)12s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -0.2), "0s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -0.0), "0s")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -270, style: .ascii), "-4m 30s")
    }

    func testDurationNonFiniteAndHuge() {
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: .nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: .infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: -.infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 1e12), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: 1e300), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatDuration(seconds: .nan, style: .ascii), "--")
        XCTAssertNotEqual(AngleFormatter.formatDuration(seconds: 9.9e11), "\u{2014}")
    }

    func testExposureFractions() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1.0 / 250), "1/250 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.004), "1/250 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1.0 / 8000), "1/8000 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.0005), "1/2000 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.1), "1/10 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.2499), "1/4 s")
    }

    func testExposureFractionsCannotOverflow() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1e-12), "1/1000000000 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: .leastNonzeroMagnitude), "1/1000000000 s")
    }

    func testExposureSubSecondDecimals() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.25), "0.25 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.3), "0.3 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.5), "0.5 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.8), "0.8 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.333), "0.33 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0.999), "1 s")
    }

    func testExposureShortSeconds() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1), "1 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1.04), "1 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 1.25), "1.3 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 2.5), "2.5 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 4), "4 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 9.96), "10 s")
    }

    func testExposureWholeSecondsAndMinutes() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 10), "10 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 13), "13 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 13.4), "13 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 13.9), "14 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 30), "30 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 59.4), "59 s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 59.5), "1m 00s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 60), "1m 00s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 150), "2m 30s")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 3600), "1h 00m")
    }

    func testExposureInvalidValues() {
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: -1), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: .nan), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: .infinity), "\u{2014}")
        XCTAssertEqual(AngleFormatter.formatExposure(seconds: 0, style: .ascii), "--")
    }

    func testExposureOutputIsPlainWhenAsciiRequested() {
        for seconds in [0.002, 0.8, 2.5, 13, 150, 7300] {
            XCTAssertTrue(isASCII(AngleFormatter.formatExposure(seconds: seconds, style: .ascii)))
        }
    }
}

// MARK: - Parsing

final class AngleParserTests: XCTestCase {

    private func assertValue(
        _ value: Double?,
        _ expected: Double,
        _ text: String,
        accuracy: Double = 1e-9,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value else {
            XCTFail("expected \(expected) for \(text.debugDescription), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(value, expected, accuracy: accuracy, "for \(text.debugDescription)", file: file, line: line)
    }

    private func assertRA(_ text: String, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        assertValue(AngleFormatter.parseRightAscension(text), expected, text, file: file, line: line)
    }

    private func assertDec(_ text: String, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        assertValue(AngleFormatter.parseDeclination(text), expected, text, file: file, line: line)
        // Latitude shares the grammar and range of declination.
        assertValue(AngleFormatter.parseLatitude(text), expected, text, file: file, line: line)
    }

    private func assertLon(_ text: String, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        assertValue(AngleFormatter.parseLongitude(text), expected, text, file: file, line: line)
    }

    private func assertNoRA(_ inputs: [String], file: StaticString = #filePath, line: UInt = #line) {
        for text in inputs {
            XCTAssertNil(AngleFormatter.parseRightAscension(text), "RA \(text.debugDescription)", file: file, line: line)
        }
    }

    private func assertNoDec(_ inputs: [String], file: StaticString = #filePath, line: UInt = #line) {
        for text in inputs {
            XCTAssertNil(AngleFormatter.parseDeclination(text), "Dec \(text.debugDescription)", file: file, line: line)
            XCTAssertNil(AngleFormatter.parseLatitude(text), "Lat \(text.debugDescription)", file: file, line: line)
        }
    }

    private func assertNoLon(_ inputs: [String], file: StaticString = #filePath, line: UInt = #line) {
        for text in inputs {
            XCTAssertNil(AngleFormatter.parseLongitude(text), "Lon \(text.debugDescription)", file: file, line: line)
        }
    }

    // MARK: Right ascension

    func testRightAscensionAcceptedForms() {
        let orion = 5.0 + 35.0 / 60 + 17.3 / 3600
        assertRA("5 35 17.3", orion)
        assertRA("5h35m17.3s", orion)
        assertRA("5h 35m 17.3s", orion)
        assertRA("5 h 35 m 17.3 s", orion)
        assertRA("05:35:17.3", orion)
        assertRA("05:35:17", 5.0 + 35.0 / 60 + 17.0 / 3600)
        assertRA("5.588", 5.588)
        assertRA("5,588", 5.588)
        assertRA("5H35M17.3S", orion)
        assertRA("  5h 35m 17.3s  ", orion)
        assertRA("\t5\u{00A0}35\u{00A0}17.3\n", orion)
        assertRA("5h:35m:17.3s", orion)
    }

    func testRightAscensionPartialForms() {
        assertRA("0", 0)
        assertRA("0h", 0)
        assertRA("00:00:00", 0)
        assertRA("12h", 12)
        assertRA("12 h 30 m", 12.5)
        assertRA("12h 30.5m", 12 + 30.5 / 60)
        assertRA("5h35", 5 + 35.0 / 60)
        assertRA("5:35", 5 + 35.0 / 60)
        assertRA("+5.5", 5.5)
        // A decimal mark may trail or lead its digits while a value is being typed.
        assertRA("5.", 5)
        assertRA(".5", 0.5)
        assertDec("40.", 40)
        assertRA("23:59:59.9", 23 + 59.0 / 60 + 59.9 / 3600)
        assertRA("23.99999999", 23.99999999)
    }

    func testRightAscensionDegreesRequireAnExplicitMark() {
        assertRA("83.8°", 83.8 / 15)
        assertRA("83.8d", 83.8 / 15)
        assertRA("83.8 D", 83.8 / 15)
        assertRA("83° 49′ 17″", (83 + 49.0 / 60 + 17.0 / 3600) / 15)
        assertRA("83d49m17s", (83 + 49.0 / 60 + 17.0 / 3600) / 15)
        assertRA("0°", 0)
        assertRA("359.9°", 359.9 / 15)
        // A bare number is hours; 83.8 hours is out of range rather than guessed to be degrees.
        assertNoRA(["83.8", "83 49 17", "360°", "360d", "-1°", "400°"])
    }

    func testRightAscensionAcceptsPrimeMarksOnTimeFields() {
        let orion = 5.0 + 35.0 / 60 + 17.3 / 3600
        assertRA("5h 35\u{2032} 17.3\u{2033}", orion)
        assertRA("5h 35' 17.3\"", orion)
    }

    func testRightAscensionRejectsOutOfRangeAndNegative() {
        assertNoRA(["24", "24h", "24:00:00", "24.0001", "100", "-1", "\(minus)0.5", "-0", "\(minus)5h"])
    }

    func testRightAscensionRejectsInvalidFields() {
        assertNoRA([
            "5h 60m", "5h 35m 60s", "5:60", "5:59:60", "5h 75m",
            "5h 35.5m 10s", "5.5h 35m", "5.0 35 17", "1 2 3 4", "5:35:17:3",
            "5h5h", "5m", "17.3s", "5s 3m", "5m 3h", "h5", "m", "s", "h",
            "5h 35m 17.3s extra", "5x", "RA 5h",
        ])
    }

    func testRightAscensionRejectsHemisphereLetters() {
        assertNoRA(["N 5", "5 N", "5 E", "5 W", "E5", "5h 35m 17s W"])
    }

    func testRightAscensionRejectsMalformedSeparators() {
        assertNoRA(["", " ", "\n\t", "5:", ":5", "5::35", "5 : : 35", "5 17.3.4", "5..5", "5.5.5", "5,5,5", "5 , 35", ",", "."])
    }

    // MARK: Declination and latitude

    func testDeclinationAcceptedForms() {
        let value = -(5.0 + 23.0 / 60 + 28.0 / 3600)
        assertDec("\(minus)05\u{00B0} 23\u{2032} 28\u{2033}", value)
        assertDec("-05 23 28", value)
        assertDec("-5d 23m 28s", value)
        assertDec("-5d23m28s", value)
        assertDec("-5:23:28", value)
        assertDec("\(minus)5.391111111111111", value)
        assertDec("5 23 28 S", value)
        assertDec("S 5 23 28", value)
        assertDec("S5 23 28", value)
        assertDec("5°23′28″S", value)
        assertDec("5\u{00B0}23\u{2032}28\u{2033} S", value)
        assertDec("+41:16:09", 41 + 16.0 / 60 + 9.0 / 3600)
        assertDec("41 16 09 N", 41 + 16.0 / 60 + 9.0 / 3600)
        assertDec("N 41 16 09", 41 + 16.0 / 60 + 9.0 / 3600)
        assertDec("+41\u{00B0} 16\u{2032} 09\u{2033}", 41 + 16.0 / 60 + 9.0 / 3600)
    }

    func testDeclinationDecimalForms() {
        assertDec("5.391", 5.391)
        assertDec("5,391", 5.391)
        assertDec("-5.391", -5.391)
        assertDec("+0.5", 0.5)
        assertDec("5.391S", -5.391)
        assertDec("5.391 S", -5.391)
        assertDec("5.391 s", -5.391)
        assertDec("5.391N", 5.391)
        assertDec("S 5.391", -5.391)
        assertDec("s5.391", -5.391)
        assertDec("40.015°", 40.015)
        assertDec("40.015 °", 40.015)
        assertDec("40.015°N", 40.015)
        assertDec("40.015° N", 40.015)
        assertDec("40,015° N", 40.015)
        assertDec("+90 N", 90)
        assertDec("+5 N", 5)
    }

    func testDeclinationUnitStyles() {
        let value = 40.0 + 0.0 / 60 + 54.0 / 3600
        assertDec("40°0′54″", value)
        assertDec("40° 0' 54\"", value)
        assertDec("40\u{00B0}0\u{2019}54\u{201D}", value)
        assertDec("40\u{00BA}0\u{2032}54\u{2033}", value)
        assertDec("40\u{02DA}0\u{2032}54\u{2033}", value)
        assertDec("40\u{00B0}0\u{00B4}54\u{201D}", value)
        assertDec("40\u{00B0}0\u{02B9}54\u{02BA}", value)
        assertDec("40°0′54′′", value)
        assertDec("40°0'54''", value)
        assertDec("40\u{00B0}0\u{2019}54\u{2019}\u{2019}", value)
        assertDec("40 0 54", value)
        assertDec("40d0m54s", value)
        assertDec("40D0M54S", value)
        assertDec("40d 0m 54s", value)
        assertDec("40:0:54", value)
    }

    func testDeclinationUnicodeMinusVariants() {
        for sign in ["-", "\u{2212}", "\u{2013}", "\u{2012}", "\u{2010}", "\u{2011}", "\u{FE63}", "\u{FF0D}"] {
            assertDec("\(sign)5.391", -5.391)
            assertDec("\(sign) 5.391", -5.391)
            assertDec("\(sign)5\u{00B0} 30\u{2032}", -5.5)
        }
    }

    func testDeclinationSouthernHemisphereAfterLetterSeconds() {
        let value = -(40.0 + 30.0 / 60 + 15.0 / 3600)
        assertDec("40d30m15s S", value)
        assertDec("40d 30m 15s S", value)
        assertDec("40d30m15sS", value)
        assertDec("40d30m15 S", value)
        assertDec("S 40d 30m 15s", value)
        assertDec("40d30m15s N", -value)
        assertDec("40d30m15s", -value)
    }

    func testNegativeDegreesZeroKeepsItsSign() {
        assertDec("\(minus)00\u{00B0} 30\u{2032}", -0.5)
        assertDec("-0 30", -0.5)
        assertDec("-0°30'", -0.5)
        assertDec("-00:30:00", -0.5)
        assertDec("00 30 S", -0.5)
        assertDec("\(minus)00\u{00B0} 00\u{2032} 01\u{2033}", -1.0 / 3600)
        assertDec("+00\u{00B0} 30\u{2032}", 0.5)
    }

    func testNegativeZeroResultIsPositiveZero() throws {
        for text in ["-0", "\(minus)0\u{00B0}", "0 S", "S 0", "-0 0 0", "-0.0"] {
            let declination = try XCTUnwrap(AngleFormatter.parseDeclination(text), text)
            XCTAssertEqual(declination, 0)
            XCTAssertEqual(declination.sign, .plus, "\(text.debugDescription) must not produce negative zero")
            let longitude = try XCTUnwrap(AngleFormatter.parseLongitude(text.replacingOccurrences(of: "S", with: "W")), text)
            XCTAssertEqual(longitude.sign, .plus)
        }
    }

    func testDeclinationBoundaries() {
        assertDec("90", 90)
        assertDec("-90", -90)
        assertDec("90°00′00″", 90)
        assertDec("\(minus)90° 0′ 0″", -90)
        assertDec("89.99999999", 89.99999999)
        assertDec("89 59 59.999", 89 + 59.0 / 60 + 59.999 / 3600)
        assertDec("90 N", 90)
        assertDec("90 S", -90)
        assertNoDec(["90.0001", "-90.0001", "91", "-91", "180", "360", "90° 0′ 1″", "\(minus)90 0 1", "1e3", "100 S"])
    }

    func testDeclinationRejectsInvalidFields() {
        assertNoDec([
            "89 60 0", "89 59 60", "5 75", "5 3 2 1", "1.5 30", "1.5 30 10", "5 30.5 10",
            "5h", "5h 30m", "5 23 28 E", "5 23 28 W", "E 5", "W 5",
            "5\u{2032} 3\u{00B0}", "5\u{2033}", "5\u{00B0}\u{00B0}", "5\u{00B0}\u{2032}", "\u{00B0}",
            "5 30\u{2032} 15\u{00B0}", "5d 30d", "5m", "5h 5h",
        ])
    }

    func testDeclinationRejectsSignAndHemisphereTogether() {
        assertNoDec(["-5 S", "\(minus)5 S", "S -5", "S \(minus)5", "+5 S", "-5 N", "N -5", "N 5 S", "S 5 N", "N5N", "SS5", "5SS"])
    }

    func testDeclinationRejectsAmbiguousSouthOrSeconds() {
        // An "s" glued to the third field is either seconds or south; without the d/m/s letter
        // style around it the text is rejected instead of guessed.
        assertNoDec(["40 30 15S", "40 30 15s", "40\u{00B0} 30\u{2032} 15S", "40\u{00B0}30\u{2032}15s", "40d 30 15s", "40 30m 15s"])
    }

    func testDeclinationRejectsMalformedText() {
        assertNoDec([
            "", " ", "-", "+", "S", "N", "s", "°", "abc", "Dec -5", "5 N 3", "40,015,5", "40, 30", "40, -105",
            "40.015, -105.27", "5 -3", "5-3", "5.5.5", "5..5", ":5", "5:", "5::3", "5 3 2 1", "--5", "+-5", "5 N N",
            "40d30m15s.", "40\u{00B0}30\u{2032}15\u{2033}.", "40 .", ". 40",
        ])
    }

    func testLatitudeAcceptedForms() {
        assertValue(AngleFormatter.parseLatitude("40.015 N"), 40.015, "40.015 N")
        assertValue(AngleFormatter.parseLatitude("N 40.015"), 40.015, "N 40.015")
        assertValue(AngleFormatter.parseLatitude("40.0150\u{00B0} N"), 40.015, "40.0150° N")
        assertValue(AngleFormatter.parseLatitude("33.8688\u{00B0} S"), -33.8688, "33.8688° S")
        assertValue(AngleFormatter.parseLatitude("-33.8688"), -33.8688, "-33.8688")
        assertValue(AngleFormatter.parseLatitude("33\u{00B0}52\u{2032}08\u{2033}S"), -(33 + 52.0 / 60 + 8.0 / 3600), "33°52′08″S")
        assertValue(AngleFormatter.parseLatitude("0"), 0, "0")
        assertValue(AngleFormatter.parseLatitude("S90"), -90, "S90")
        assertNoDec(["90.1 N", "100 S", "E 5", "5 W", "40.015 NN", "-91"])
    }

    // MARK: Longitude

    func testLongitudeAcceptedForms() {
        let dms = -(105.0 + 16.0 / 60 + 14.0 / 3600)
        assertLon("-105.2705", -105.2705)
        assertLon("\(minus)105.2705", -105.2705)
        assertLon("105.2705 W", -105.2705)
        assertLon("105.2705W", -105.2705)
        assertLon("105.2705\u{00B0} W", -105.2705)
        assertLon("W 105.2705", -105.2705)
        assertLon("W105.2705", -105.2705)
        assertLon("w 105.2705", -105.2705)
        assertLon("105,2705 w", -105.2705)
        assertLon("E 105.2705", 105.2705)
        assertLon("105.2705 E", 105.2705)
        assertLon("+105.2705", 105.2705)
        assertLon("105\u{00B0}16\u{2032}14\u{2033} W", dms)
        assertLon("105 16 14 W", dms)
        assertLon("105:16:14 W", dms)
        assertLon("105d16m14s W", dms)
        assertLon("105d16m14sW", dms)
        assertLon("105d 16m 14s w", dms)
        assertLon("W 105d 16m 14s", dms)
        assertLon("\(minus)105\u{00B0} 16\u{2032} 14\u{2033}", dms)
        assertLon("2.3522 E", 2.3522)
    }

    func testLongitudeAcceptsEastDegreesFrom180To360() {
        assertLon("254.7295", -105.2705)
        assertLon("E 254.7295", -105.2705)
        assertLon("254.7295 E", -105.2705)
        assertLon("181", -179)
        assertLon("359.5", -0.5)
        assertLon("E 270", -90)
        assertLon("270\u{00B0} 0\u{2032} 0\u{2033}", -90)
    }

    func testLongitudeBoundaries() {
        assertLon("0", 0)
        assertLon("0°", 0)
        assertLon("180", 180)
        assertLon("-180", 180)
        assertLon("W 180", 180)
        assertLon("E 180", 180)
        assertLon("180°00′00″", 180)
        assertLon("360", 0)
        assertLon("179.9999", 179.9999)
        assertLon("-179.9999", -179.9999)
        assertLon("180.0001", -179.9999)
        assertNoLon(["-181", "-180.0001", "361", "360.0001", "W 181", "270 W", "E 361", "\(minus)181", "1000", "-360"])
    }

    func testLongitudeRejectsInvalidText() {
        assertNoLon([
            "", " ", "W", "E", "N 5", "5 N", "5 N 3", "105 16 60", "105 60 0", "105d 16m 14s X", "5h", "5 S",
            "-5 W", "+5 W", "W -5", "W 5 E", "E5E", "1e2", "105.2705, -40", "105.2705 W 40", "5 3 2 1", "NaN", "inf",
        ])
    }

    // MARK: Hostile input

    func testNonNumbersAreRejected() {
        let words = ["NaN", "nan", "-nan", "inf", "-inf", "Infinity", "-Infinity", "+infinity", "0x10", "1e5", "1E-5", "1e400", "0b101", "NULL", "null", "true"]
        assertNoRA(words)
        assertNoDec(words)
        assertNoLon(words)
    }

    func testNonAsciiDigitsAreRejected() {
        let digits = ["\u{0665}", "\u{FF15}", "\u{0966}", "\u{00B2}", "\u{2155}", "5\u{0665}", "\u{FF15}.\u{FF15}", "\u{2460}"]
        assertNoRA(digits)
        assertNoDec(digits)
        assertNoLon(digits)
    }

    func testStrayUnicodeIsRejected() {
        let strays = ["5\u{200B}", "\u{FEFF}5", "5\u{0301}", "5 \u{1F31F}", "\u{2014}5", "5\u{2014}", "\u{2014}", "5\u{00B0}\u{200D}", "5\u{0000}", "5\u{0007}"]
        assertNoRA(strays)
        assertNoDec(strays)
        assertNoLon(strays)
    }

    func testHugeNumbersAreRejected() {
        let huge = String(repeating: "9", count: 64)
        assertNoRA([huge, huge + "."])
        assertNoDec([huge])
        assertNoLon([huge])
        assertNoRA(["99999999999999999999999999"])
        assertNoDec(["99999999999999999999999999", "0.0000000000000000000000000001 99999999999999999999"])
        assertNoLon(["99999999999999999999999999"])
    }

    func testTinyNumbersAreAccepted() {
        let tiny = "0." + String(repeating: "0", count: 61) + "1"
        XCTAssertEqual(tiny.count, 64)
        assertValue(AngleFormatter.parseDeclination(tiny), 0, tiny, accuracy: 1e-60)
        assertValue(AngleFormatter.parseRightAscension(tiny), 0, tiny, accuracy: 1e-60)
    }

    func testLengthIsCappedAtSixtyFourCharacters() {
        let accepted = "5." + String(repeating: "0", count: 61) + "1"
        XCTAssertEqual(accepted.unicodeScalars.count, 64)
        assertValue(AngleFormatter.parseDeclination(accepted), 5, accepted)
        assertValue(AngleFormatter.parseRightAscension(accepted), 5, accepted)
        assertValue(AngleFormatter.parseLongitude(accepted), 5, accepted)

        let rejected = "5." + String(repeating: "0", count: 62) + "1"
        XCTAssertEqual(rejected.unicodeScalars.count, 65)
        assertNoRA([rejected])
        assertNoDec([rejected])
        assertNoLon([rejected])

        // Whitespace counts towards the cap, so padding cannot be used to smuggle in extra input.
        assertNoDec([String(repeating: " ", count: 64) + "5"])
        assertValue(AngleFormatter.parseDeclination(String(repeating: " ", count: 63) + "5"), 5, "padded")
    }

    func testVeryLongInputIsRejectedQuickly() {
        let megabyte = String(repeating: "1", count: 1_000_000)
        assertNoRA([megabyte])
        assertNoDec([megabyte])
        assertNoLon([megabyte])
    }

    func testMultiScalarCharactersCountPerScalar() {
        // 33 combining sequences are 66 scalars: over the cap even though they are 33 characters.
        let sequence = String(repeating: "5\u{0301}", count: 33)
        XCTAssertEqual(sequence.count, 33)
        assertNoDec([sequence])
    }

    // MARK: Grammar properties

    /// The same sexagesimal value written in every supported style.
    private func styles(_ whole: Int, _ minutes: Int, _ seconds: String) -> [String] {
        [
            "\(whole) \(minutes) \(seconds)",
            "\(whole):\(minutes):\(seconds)",
            "\(whole)d\(minutes)m\(seconds)s",
            "\(whole)d \(minutes)m \(seconds)s",
            "\(whole)D\(minutes)M\(seconds)S",
            "\(whole)\u{00B0}\(minutes)\u{2032}\(seconds)\u{2033}",
            "\(whole)\u{00B0} \(minutes)\u{2032} \(seconds)\u{2033}",
            "\(whole)\u{00B0} \(minutes)' \(seconds)\"",
            "\(whole)\u{00BA}\(minutes)\u{2019}\(seconds)\u{201D}",
            "\(whole)\u{00B0}\(minutes)'\(seconds)''",
        ]
    }

    private func randomSexagesimal(_ generator: inout SplitMix64, wholeLimit: UInt64) -> (whole: Int, minutes: Int, seconds: String, value: Double) {
        let whole = Int(generator.next() % wholeLimit)
        let minutes = Int(generator.next() % 60)
        let tenths = Int(generator.next() % 600)
        let seconds = tenths % 10 == 0 && generator.next() % 2 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
        let value = Double(whole) + Double(minutes) / 60 + Double(tenths) / 10 / 3600
        return (whole, minutes, seconds, value)
    }

    func testEveryDeclinationStyleAgrees() {
        var generator = SplitMix64(seed: 101)
        for _ in 0..<200 {
            let sample = randomSexagesimal(&generator, wholeLimit: 90)
            for text in styles(sample.whole, sample.minutes, sample.seconds) {
                let decorated: [(String, Double)] = [
                    (text, sample.value),
                    ("+" + text, sample.value),
                    ("-" + text, -sample.value),
                    ("\(minus)" + text, -sample.value),
                    ("\u{2013}" + text, -sample.value),
                    (text + " N", sample.value),
                    ("N " + text, sample.value),
                    (text + " S", -sample.value),
                    ("S " + text, -sample.value),
                    (text + "  s", -sample.value),
                ]
                for (input, expected) in decorated {
                    assertValue(AngleFormatter.parseDeclination(input), expected, input, accuracy: 1e-9)
                    assertValue(AngleFormatter.parseLatitude(input), expected, input, accuracy: 1e-9)
                }
            }
            // Symbol styles can carry the hemisphere letter without a space.
            for text in styles(sample.whole, sample.minutes, sample.seconds).suffix(5) where !text.hasSuffix("S") {
                assertValue(AngleFormatter.parseDeclination(text + "S"), -sample.value, text + "S", accuracy: 1e-9)
                assertValue(AngleFormatter.parseDeclination(text + "N"), sample.value, text + "N", accuracy: 1e-9)
            }
        }
    }

    func testEveryLongitudeStyleAgrees() {
        var generator = SplitMix64(seed: 202)
        for _ in 0..<200 {
            let sample = randomSexagesimal(&generator, wholeLimit: 180)
            for text in styles(sample.whole, sample.minutes, sample.seconds) {
                let decorated: [(String, Double)] = [
                    (text, sample.value),
                    ("+" + text, sample.value),
                    ("-" + text, -sample.value),
                    ("\(minus)" + text, -sample.value),
                    (text + " E", sample.value),
                    ("E " + text, sample.value),
                    (text + " W", -sample.value),
                    ("W " + text, -sample.value),
                    (text + "w", -sample.value),
                ]
                for (input, expected) in decorated {
                    // Negative zero longitudes and the antimeridian have their own tests.
                    let wrapped = expected == -180 ? 180 : expected
                    assertValue(AngleFormatter.parseLongitude(input), wrapped, input, accuracy: 1e-9)
                }
            }
        }
    }

    func testEveryRightAscensionStyleAgrees() {
        var generator = SplitMix64(seed: 303)
        for _ in 0..<200 {
            let sample = randomSexagesimal(&generator, wholeLimit: 24)
            let hourStyles = [
                "\(sample.whole) \(sample.minutes) \(sample.seconds)",
                "\(sample.whole):\(sample.minutes):\(sample.seconds)",
                "\(sample.whole)h\(sample.minutes)m\(sample.seconds)s",
                "\(sample.whole)h \(sample.minutes)m \(sample.seconds)s",
                "\(sample.whole) h \(sample.minutes) m \(sample.seconds) s",
                "\(sample.whole)H\(sample.minutes)M\(sample.seconds)S",
                "\(sample.whole)h\(sample.minutes)\u{2032}\(sample.seconds)\u{2033}",
            ]
            for text in hourStyles {
                assertValue(AngleFormatter.parseRightAscension(text), sample.value, text, accuracy: 1e-9)
                assertValue(AngleFormatter.parseRightAscension("+" + text), sample.value, "+" + text, accuracy: 1e-9)
                assertNoRA(["-" + text, text + " N", text + "x", "x" + text, text + " 1"])
            }

            // The degrees form divides by 15 and needs a degree mark on the first field.
            let degrees = randomSexagesimal(&generator, wholeLimit: 360)
            let degreeStyles = [
                "\(degrees.whole)d\(degrees.minutes)m\(degrees.seconds)s",
                "\(degrees.whole)\u{00B0}\(degrees.minutes)\u{2032}\(degrees.seconds)\u{2033}",
                "\(degrees.whole)\u{00B0} \(degrees.minutes) \(degrees.seconds)",
            ]
            for text in degreeStyles {
                assertValue(AngleFormatter.parseRightAscension(text), degrees.value / 15, text, accuracy: 1e-9)
            }
        }
    }

    func testTrailingOrLeadingJunkAlwaysFails() {
        var generator = SplitMix64(seed: 404)
        for _ in 0..<100 {
            let sample = randomSexagesimal(&generator, wholeLimit: 90)
            for text in styles(sample.whole, sample.minutes, sample.seconds) {
                assertNoDec([text + "x", "x" + text, text + " 1", "1 " + text, text + " N N", text + " ?", text + "\u{200B}"])
                assertNoLon([text + "x", "x" + text, text + " 1", text + " E E"])
            }
        }
    }

    func testFuzzNeverTrapsAndResultsStayInRange() {
        let alphabet: [Character] = Array("0123456789 .,:+-\u{2212}\u{00B0}\u{2032}\u{2033}'\"\u{2019}hdmsHDMSNEWnewx\u{00E9}\u{0665}\u{200B}\n\t")
        var generator = SplitMix64(seed: 0x5EED_0F_5747)
        for _ in 0..<40_000 {
            let length = Int(generator.next() % 21)
            var text = ""
            for _ in 0..<length {
                text.append(alphabet[Int(generator.next() % UInt64(alphabet.count))])
            }
            if let hours = AngleFormatter.parseRightAscension(text) {
                XCTAssertTrue(hours >= 0 && hours < 24, "RA \(text.debugDescription) -> \(hours)")
            }
            if let declination = AngleFormatter.parseDeclination(text) {
                XCTAssertTrue(declination.isFinite && abs(declination) <= 90, "Dec \(text.debugDescription) -> \(declination)")
                XCTAssertFalse(declination == 0 && declination.sign == .minus, "negative zero for \(text.debugDescription)")
            }
            if let longitude = AngleFormatter.parseLongitude(text) {
                XCTAssertTrue(longitude > -180 && longitude <= 180, "Lon \(text.debugDescription) -> \(longitude)")
                XCTAssertFalse(longitude == 0 && longitude.sign == .minus, "negative zero for \(text.debugDescription)")
            }
        }
    }

    func testFuzzOfValidShapedInput() {
        // Structured random strings: mostly valid, so the accepted paths are exercised too.
        var generator = SplitMix64(seed: 42)
        let separators = [" ", ":", "", "\u{00B0}", "d", "h", "m", "'", "\u{2032}", "\u{2033}", "s", "\"", " S", " N", " W", " E"]
        var accepted = 0
        for _ in 0..<40_000 {
            var text = Int(generator.next() % 2) == 0 ? "" : ["-", "+", "\u{2212}", "S ", "N ", "W ", "E "][Int(generator.next() % 7)]
            let fields = 1 + Int(generator.next() % 3)
            for index in 0..<fields {
                text += String(generator.next() % 400)
                if Int(generator.next() % 4) == 0 { text += "." + String(generator.next() % 1000) }
                text += separators[Int(generator.next() % UInt64(separators.count))]
                if index < fields - 1 && Int(generator.next() % 2) == 0 { text += " " }
            }
            for parse in [AngleFormatter.parseRightAscension, AngleFormatter.parseDeclination, AngleFormatter.parseLatitude, AngleFormatter.parseLongitude] {
                if let value = parse(text) {
                    accepted += 1
                    XCTAssertTrue(value.isFinite, text)
                }
            }
        }
        XCTAssertGreaterThan(accepted, 1000, "the generator should reach the accepting paths")
    }
}

// MARK: - Round trips

final class FormattingRoundTripTests: XCTestCase {

    func testRightAscensionRoundTrip() throws {
        var generator = SplitMix64(seed: 7)
        for style in TypographyStyle.allCases {
            for _ in 0..<2_000 {
                let hours = Double(generator.next() % 24_000_000) / 1_000_000
                let text = AngleFormatter.formatRightAscension(hours: hours, secondsDecimals: 3, style: style)
                let parsed = try XCTUnwrap(AngleFormatter.parseRightAscension(text), text)
                // Seconds are printed to the millisecond: half of that, in hours, plus rounding slack.
                XCTAssertEqual(parsed, hours, accuracy: 0.0005 / 3600 + 1e-12, text)
            }
        }
    }

    func testDeclinationRoundTrip() throws {
        var generator = SplitMix64(seed: 8)
        for style in TypographyStyle.allCases {
            for _ in 0..<2_000 {
                let degrees = Double(generator.next() % 180_000_000) / 1_000_000 - 90
                let text = AngleFormatter.formatDeclination(degrees: degrees, secondsDecimals: 2, style: style)
                let parsed = try XCTUnwrap(AngleFormatter.parseDeclination(text), text)
                XCTAssertEqual(parsed, degrees, accuracy: 0.005 / 3600 + 1e-12, text)
                let latitude = try XCTUnwrap(AngleFormatter.parseLatitude(text), text)
                XCTAssertEqual(latitude, parsed)
            }
        }
    }

    func testDeclinationRoundTripAtTheEdges() throws {
        for degrees in [-90.0, 90.0, 0.0, -0.5, 0.5, -1.0 / 3600, 89.9999999] {
            let text = AngleFormatter.formatDeclination(degrees: degrees)
            let parsed = try XCTUnwrap(AngleFormatter.parseDeclination(text), text)
            XCTAssertEqual(parsed, degrees, accuracy: 0.5 / 3600 + 1e-12, text)
        }
    }

    func testDMSRoundTrip() throws {
        var generator = SplitMix64(seed: 9)
        for style in TypographyStyle.allCases {
            for _ in 0..<2_000 {
                let degrees = Double(generator.next() % 358_000_000) / 1_000_000 - 179
                let text = AngleFormatter.formatDMS(degrees, secondsDecimals: 1, style: style)
                let parsed = try XCTUnwrap(AngleFormatter.parseLongitude(text), text)
                // Seconds are printed to a tenth: half of that, in degrees, plus rounding slack.
                XCTAssertEqual(parsed, degrees, accuracy: 0.05 / 3600 + 1e-12, text)
            }
        }
    }

    func testLatitudeAndLongitudeRoundTrip() throws {
        var generator = SplitMix64(seed: 10)
        for style in TypographyStyle.allCases {
            for _ in 0..<2_000 {
                let latitude = Double(generator.next() % 180_000_000) / 1_000_000 - 90
                let longitude = Double(generator.next() % 360_000_000) / 1_000_000 - 180
                let latitudeText = AngleFormatter.formatLatitude(latitude, style: style)
                let longitudeText = AngleFormatter.formatLongitude(longitude, style: style)
                let parsedLatitude = try XCTUnwrap(AngleFormatter.parseLatitude(latitudeText), latitudeText)
                let parsedLongitude = try XCTUnwrap(AngleFormatter.parseLongitude(longitudeText), longitudeText)
                // Four decimals: half a unit in the last place, plus rounding slack.
                XCTAssertEqual(parsedLatitude, latitude, accuracy: 0.00006, latitudeText)
                // Longitudes next to the antimeridian may legitimately come back on the other side.
                let difference = abs(parsedLongitude - longitude).truncatingRemainder(dividingBy: 360)
                XCTAssertLessThan(min(difference, 360 - difference), 0.00006, longitudeText)
            }
        }
    }

    func testAsciiStyleIsPureAsciiAndStillParses() throws {
        let declination = AngleFormatter.formatDeclination(degrees: -5.391, secondsDecimals: 1, style: .ascii)
        XCTAssertEqual(declination, "-05d 23' 27.6\"")
        XCTAssertTrue(isASCII(declination))
        XCTAssertEqual(try XCTUnwrap(AngleFormatter.parseDeclination(declination)), -5.391, accuracy: 0.05 / 3600)

        let samples = [
            AngleFormatter.formatRightAscension(hours: 5.588, style: .ascii),
            AngleFormatter.formatDegrees(-12.3, style: .ascii),
            AngleFormatter.formatSignedDegrees(12.3, style: .ascii),
            AngleFormatter.formatAzimuth(300, style: .ascii),
            AngleFormatter.formatDMS(-1.5, style: .ascii),
            AngleFormatter.formatLatitude(-33.8688, style: .ascii),
            AngleFormatter.formatLongitude(-105.2705, style: .ascii),
            AngleFormatter.formatDeclination(degrees: .nan, style: .ascii),
            AngleFormatter.formatDuration(seconds: -3900, style: .ascii),
            AngleFormatter.formatExposure(seconds: 0.002, style: .ascii),
        ]
        for sample in samples {
            XCTAssertTrue(isASCII(sample), sample)
        }
        XCTAssertEqual(try XCTUnwrap(AngleFormatter.parseLatitude("33.8688d S")), -33.8688, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(AngleFormatter.parseLongitude("105.2705d W")), -105.2705, accuracy: 1e-9)
    }

    func testPlaceholdersAreNotParseable() {
        for style in TypographyStyle.allCases {
            let placeholder = AngleFormatter.formatDegrees(.nan, style: style)
            XCTAssertNil(AngleFormatter.parseRightAscension(placeholder))
            XCTAssertNil(AngleFormatter.parseDeclination(placeholder))
            XCTAssertNil(AngleFormatter.parseLongitude(placeholder))
        }
    }
}

// MARK: - Deterministic random numbers

/// A small, seeded generator so the randomised tests are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

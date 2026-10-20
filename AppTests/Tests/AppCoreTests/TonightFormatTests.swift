import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The words and numbers of the Tonight cards (`TonightFormat`).
///
/// Times follow the user's 12/24-hour setting, so the tests check the shape of a time window (where the non-breaking
/// spaces and the dash are) and build the expected text from `AppFormat.time`, never from a literal clock string.
final class TonightFormatTests: XCTestCase {
    private static let catalogResult = Result { try Catalog.loadBundled() }

    private let nbsp = "\u{00A0}"
    private let dot = "\u{00B7}"

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    private func instant(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: iso), iso)
    }

    /// Skips the test where numbers are not written like "3.4" (the code formats them with the user's locale).
    private func requirePointDecimals() throws {
        try XCTSkipUnless(3.4.formatted(.number.precision(.fractionLength(1))) == "3.4",
                          "numbers are not written with a decimal point in this locale")
    }

    private func catalogObject(_ id: String) throws -> CelestialObject {
        let catalog = try Self.catalogResult.get()
        return try XCTUnwrap(catalog.object(id: id), id)
    }

    // MARK: Non-breaking text

    func testSolidTurnsEverySpaceIntoANonBreakingSpace() {
        XCTAssertEqual(TonightFormat.solid("10:54 PM"), "10:54\(nbsp)PM")
        XCTAssertEqual(TonightFormat.solid("a b c"), "a\(nbsp)b\(nbsp)c")
        XCTAssertEqual(TonightFormat.solid("  "), "\(nbsp)\(nbsp)")
    }

    func testSolidLeavesTextWithoutSpacesAndEmptyTextAlone() {
        XCTAssertEqual(TonightFormat.solid("mag3.6"), "mag3.6")
        XCTAssertEqual(TonightFormat.solid(""), "")
    }

    func testDottedJoinsSegmentsWithADotThatStaysWithTheSegmentBefore() {
        XCTAssertEqual(TonightFormat.dotted(["a", "b", "c"]), "a\(nbsp)\(dot) b\(nbsp)\(dot) c")
        XCTAssertEqual(TonightFormat.dotted(["only"]), "only")
        XCTAssertEqual(TonightFormat.dotted([]), "")
    }

    // MARK: Windows

    func testAWindowHasOneBreakableSpaceAndItSitsAfterTheDash() throws {
        let denver = try zone("America/Denver")
        let interval = DateInterval(start: try instant("2026-10-11T03:40:00Z"), end: try instant("2026-10-11T10:12:00Z"))
        let text = TonightFormat.window(interval, in: denver)
        // Every space inside the two times is non-breaking; the only plain space follows the en dash.
        XCTAssertEqual(text.filter { $0 == " " }.count, 1)
        let parts = text.components(separatedBy: "\u{2013} ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].hasSuffix(nbsp), "the dash stays with the time before it: \(text)")
        XCTAssertEqual(parts[0], TonightFormat.solid(AppFormat.time(interval.start, in: denver)) + nbsp)
        XCTAssertEqual(parts[1], TonightFormat.solid(AppFormat.time(interval.end, in: denver)))
    }

    func testAWindowIsWrittenInTheGivenTimeZone() throws {
        let interval = DateInterval(start: try instant("2026-10-11T03:40:00Z"), end: try instant("2026-10-11T10:12:00Z"))
        XCTAssertNotEqual(TonightFormat.window(interval, in: try zone("America/Denver")),
                          TonightFormat.window(interval, in: try zone("UTC")))
    }

    func testNoWindowsReadAsThePlaceholder() throws {
        XCTAssertEqual(TonightFormat.windows([], in: try zone("UTC")), AppFormat.missing)
        XCTAssertEqual(AppFormat.missing, "\u{2014}")
    }

    func testSeveralWindowsAreSeparatedByCommas() throws {
        let utc = try zone("UTC")
        let first = DateInterval(start: try instant("2026-10-11T01:00:00Z"), end: try instant("2026-10-11T02:00:00Z"))
        let second = DateInterval(start: try instant("2026-10-11T05:00:00Z"), end: try instant("2026-10-11T06:30:00Z"))
        XCTAssertEqual(TonightFormat.windows([first], in: utc), TonightFormat.window(first, in: utc))
        XCTAssertEqual(TonightFormat.windows([first, second], in: utc),
                       TonightFormat.window(first, in: utc) + ", " + TonightFormat.window(second, in: utc))
    }

    func testSpokenWindowsUseToAndAnd() throws {
        let utc = try zone("UTC")
        let first = DateInterval(start: try instant("2026-10-11T01:00:00Z"), end: try instant("2026-10-11T02:00:00Z"))
        let second = DateInterval(start: try instant("2026-10-11T05:00:00Z"), end: try instant("2026-10-11T06:30:00Z"))
        func spoken(_ interval: DateInterval) -> String {
            "\(AppFormat.time(interval.start, in: utc)) to \(AppFormat.time(interval.end, in: utc))"
        }
        XCTAssertEqual(TonightFormat.spokenWindows([first], in: utc), spoken(first))
        XCTAssertEqual(TonightFormat.spokenWindows([first, second], in: utc), spoken(first) + " and " + spoken(second))
        XCTAssertEqual(TonightFormat.spokenWindows([], in: utc), "")
    }

    // MARK: Durations

    func testDurationBelowAnHourIsInMinutes() {
        XCTAssertEqual(TonightFormat.duration(hours: 0.75), "45m")
        XCTAssertEqual(TonightFormat.duration(hours: 0.01), "1m")
        XCTAssertEqual(TonightFormat.duration(hours: 59.0 / 60.0), "59m")
    }

    func testDurationFromAnHourUpIsInHoursAndPaddedMinutes() {
        XCTAssertEqual(TonightFormat.duration(hours: 1.0), "1h\(nbsp)00m")
        XCTAssertEqual(TonightFormat.duration(hours: 1.0 + 5.0 / 60.0), "1h\(nbsp)05m")
        XCTAssertEqual(TonightFormat.duration(hours: 6.0 + 32.0 / 60.0), "6h\(nbsp)32m")
        XCTAssertEqual(TonightFormat.duration(hours: 10.0 + 59.0 / 60.0), "10h\(nbsp)59m")
        XCTAssertEqual(TonightFormat.duration(hours: 24.0), "24h\(nbsp)00m")
    }

    func testDurationRoundsToTheNearestMinuteBeforeChoosingTheForm() {
        // 59.7 minutes rounds up to a whole hour.
        XCTAssertEqual(TonightFormat.duration(hours: 59.7 / 60.0), "1h\(nbsp)00m")
        // 29 seconds is below half a minute.
        XCTAssertEqual(TonightFormat.duration(hours: 29.0 / 3600.0), "0m")
    }

    func testDurationOfNothingNegativeOrNotANumberIsZero() {
        XCTAssertEqual(TonightFormat.duration(hours: 0), "0m")
        XCTAssertEqual(TonightFormat.duration(hours: -2.5), "0m")
        XCTAssertEqual(TonightFormat.duration(hours: .nan), "0m")
        XCTAssertEqual(TonightFormat.duration(hours: .infinity), "0m")
    }

    // MARK: Night labels and zone names

    func testNightLabels() {
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: 0), "Tonight")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: 1), "Tomorrow night")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: -1), "Last night")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: 2), "In 2 nights")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: 30), "In 30 nights")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: -2), "2 nights ago")
        XCTAssertEqual(TonightFormat.nightLabel(nightsFromTonight: -14), "14 nights ago")
    }

    func testZoneNameFollowsDaylightSavingTime() throws {
        let denver = try zone("America/Denver")
        XCTAssertEqual(TonightFormat.zoneName(denver, at: try instant("2026-07-01T12:00:00Z")), "MDT")
        XCTAssertEqual(TonightFormat.zoneName(denver, at: try instant("2026-01-15T12:00:00Z")), "MST")
    }

    // MARK: Directions

    func testDirectionNamesTheCompassPointAndTheAzimuth() {
        XCTAssertEqual(TonightFormat.direction(azimuth: 158.2, altitude: 40), "SSE \(dot) 158\u{00B0}")
        XCTAssertEqual(TonightFormat.direction(azimuth: 0, altitude: 10), "N \(dot) 0\u{00B0}")
        XCTAssertEqual(TonightFormat.direction(azimuth: 270, altitude: 10), "W \(dot) 270\u{00B0}")
    }

    func testDirectionWrapsAnAzimuthNearAFullTurn() {
        XCTAssertEqual(TonightFormat.direction(azimuth: 359.8, altitude: 10), "N \(dot) 0\u{00B0}")
    }

    func testNearTheZenithTheDirectionIsOverhead() {
        XCTAssertEqual(TonightFormat.overheadAltitude, 85.0)
        XCTAssertEqual(TonightFormat.direction(azimuth: 158.2, altitude: 84.9), "SSE \(dot) 158\u{00B0}")
        XCTAssertEqual(TonightFormat.direction(azimuth: 158.2, altitude: 85.0), "Overhead")
        XCTAssertEqual(TonightFormat.direction(azimuth: 158.2, altitude: 89.9), "Overhead")
    }

    func testFacingNamesTheCompassPoint() {
        XCTAssertEqual(TonightFormat.facing(azimuth: 158.2, altitude: 40), "facing SSE")
        XCTAssertEqual(TonightFormat.facing(azimuth: 90, altitude: 40), "facing E")
        XCTAssertEqual(TonightFormat.facing(azimuth: 158.2, altitude: 84.9), "facing SSE")
        XCTAssertEqual(TonightFormat.facing(azimuth: 158.2, altitude: 85), "overhead")
    }

    func testSpokenFacingWritesTheCompassPointOut() {
        XCTAssertEqual(TonightFormat.spokenFacing(azimuth: 158.2, altitude: 40), "facing south-southeast")
        XCTAssertEqual(TonightFormat.spokenFacing(azimuth: 315, altitude: 40), "facing northwest")
        XCTAssertEqual(TonightFormat.spokenFacing(azimuth: 158.2, altitude: 85), "overhead")
    }

    // MARK: Clock positions

    func testClockPositionPlacesTwelveOClockAtZeroDegrees() {
        XCTAssertEqual(TonightFormat.clockPosition(angle: 0), "12:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 360), "12:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 359.9), "12:00")
    }

    func testClockPositionGivesThirtyDegreesPerHour() {
        XCTAssertEqual(TonightFormat.clockPosition(angle: 30), "1:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 90), "3:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 180), "6:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 315), "10:30")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 345), "11:30")
    }

    func testClockPositionTreatsTheFirstHourAfterTwelveAsTwelve() {
        XCTAssertEqual(TonightFormat.clockPosition(angle: 15), "12:30")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 29), "12:58")
    }

    func testClockPositionNormalisesNegativeAndLargeAngles() {
        XCTAssertEqual(TonightFormat.clockPosition(angle: -30), "11:00")
        XCTAssertEqual(TonightFormat.clockPosition(angle: 390), "1:00")
    }

    func testClockPositionOfAnUnknownAngleIsThePlaceholder() {
        XCTAssertEqual(TonightFormat.clockPosition(angle: .nan), AppFormat.missing)
        XCTAssertEqual(TonightFormat.clockPosition(angle: .infinity), AppFormat.missing)
    }

    // MARK: Objects

    func testDesignationIsShownWhenItDiffersFromTheName() throws {
        let andromeda = try catalogObject("dso.M31")
        XCTAssertEqual(andromeda.name, "Andromeda Galaxy")
        XCTAssertEqual(TonightFormat.designation(of: andromeda), "M 31")
    }

    func testDesignationIsLeftOutWhenItIsTheName() throws {
        // M 2 has no common name, so its name is its first designation.
        let m2 = try catalogObject("dso.M2")
        XCTAssertEqual(m2.name, "M 2")
        XCTAssertNil(TonightFormat.designation(of: m2))
    }

    func testDesignationOfACometIsItsOfficialDesignation() {
        let comet = tsuchinshanAtlas()
        XCTAssertEqual(TonightFormat.designation(of: comet), "C/2023 A3")
    }

    func testDescriptionHasTypeConstellationMagnitudeAndSize() throws {
        try requirePointDecimals()
        let andromeda = try catalogObject("dso.M31")
        let expected = ["Galaxy", "Andromeda", "mag\(nbsp)3.4", "178\u{2032}\(nbsp)\u{00D7}\(nbsp)70\u{2032}"]
            .joined(separator: "\(nbsp)\(dot) ")
        XCTAssertEqual(TonightFormat.description(of: andromeda), expected)
    }

    func testDescriptionOfAnObjectWithoutMagnitudeOrSizeIsJustItsType() {
        XCTAssertEqual(TonightFormat.description(of: tsuchinshanAtlas()), "Comet")
    }

    // MARK: Fixtures

    /// C/2023 A3 (Tsuchinshan-ATLAS), an MPC comet line of 2026-10-18.
    private func tsuchinshanAtlas() -> CelestialObject {
        let line = "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  "
            + "C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98"
        guard let body = try? CometElementsParser.parseLine(line) else {
            XCTFail("the comet line did not parse")
            return CelestialObject.custom(name: "unparsed", j2000: EquatorialCoordinate(rightAscension: 0, declination: 0))
        }
        return CelestialObject(smallBody: body)
    }
}

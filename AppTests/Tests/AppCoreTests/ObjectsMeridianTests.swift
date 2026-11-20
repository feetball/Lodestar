import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `ObjectDetailMeridian` (Features/Objects/ObjectDetailMeridian.swift): the hour angle and the transits of the Now card.
final class ObjectsMeridianTests: XCTestCase {
    private let minus = "\u{2212}"
    private let denver = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 1600))
    private let moment = Date(timeIntervalSince1970: 1_792_551_600)

    private func meridian(hourAngle: Double, next: Date? = nil, previous: Date? = nil) -> ObjectDetailMeridian {
        ObjectDetailMeridian(hourAngle: hourAngle, next: next, previous: previous, date: moment)
    }

    // MARK: The hour angle

    func testTheHourAngleInSexagesimalHasASignAndMinutes() {
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(-1.3833, style: .sexagesimal), "\(minus)1h 23m")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(25.0 / 60.0, style: .sexagesimal), "+0h 25m")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0, style: .sexagesimal), "0h 00m")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(-5.0 / 60.0, style: .sexagesimal), "\(minus)0h 05m")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0.001, style: .sexagesimal), "0h 00m", "under half a minute is none")
    }

    func testTheHourAngleInDecimalHasThreeDecimals() {
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(-1.389, style: .decimal), "\(minus)1.389 h")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0.417, style: .decimal), "+0.417 h")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0, style: .decimal), "0.000 h")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0.0504, style: .decimal), "+0.050 h")
        XCTAssertEqual(ObjectDetailMeridian.hourAngleText(0.0094, style: .decimal), "+0.009 h")
    }

    func testAHourAngleThatIsNotUsableIsMissing() {
        for style in CoordinateStyle.allCases {
            XCTAssertEqual(ObjectDetailMeridian.hourAngleText(.nan, style: style), AppFormat.missing)
            XCTAssertEqual(ObjectDetailMeridian.hourAngleText(30, style: style), AppFormat.missing)
        }
    }

    func testTheCardUsesTheStyleItIsGiven() {
        let value = meridian(hourAngle: -1.3833)
        XCTAssertEqual(value.hourAngleText(style: .sexagesimal), "\(minus)1h 23m")
        XCTAssertEqual(value.hourAngleText(style: .decimal), "\(minus)1.383 h")
    }

    // MARK: The transits

    func testATransitAheadIsSaidInHoursAndMinutes() {
        XCTAssertEqual(ObjectDetailMeridian.transitIn(seconds: 83 * 60), "transits in 1 h 23 min")
        XCTAssertEqual(ObjectDetailMeridian.transitIn(seconds: 3600), "transits in 1 h")
        XCTAssertEqual(ObjectDetailMeridian.transitIn(seconds: 25 * 60), "transits in 25 min")
        XCTAssertEqual(ObjectDetailMeridian.transitIn(seconds: 10), "transits now")
        XCTAssertEqual(ObjectDetailMeridian.transitIn(seconds: -500), "transits now", "a past instant counts as now")
        XCTAssertNil(ObjectDetailMeridian.transitIn(seconds: .nan))
    }

    func testATransitBehindIsSaidInHoursAndMinutes() {
        XCTAssertEqual(ObjectDetailMeridian.transitedAgo(seconds: 25 * 60), "transited 25 min ago")
        XCTAssertEqual(ObjectDetailMeridian.transitedAgo(seconds: 2 * 3600 + 5 * 60), "transited 2 h 5 min ago")
        XCTAssertEqual(ObjectDetailMeridian.transitedAgo(seconds: 10), "transited just now")
        XCTAssertNil(ObjectDetailMeridian.transitedAgo(seconds: .infinity))
    }

    func testDurationsAreWrittenInTheShortestWay() {
        XCTAssertEqual(ObjectDetailMeridian.durationText(minutes: 25), "25 min")
        XCTAssertEqual(ObjectDetailMeridian.durationText(minutes: 60), "1 h")
        XCTAssertEqual(ObjectDetailMeridian.durationText(minutes: 83), "1 h 23 min")
    }

    func testAnObjectEastOfTheMeridianTransitsAhead() {
        let value = meridian(hourAngle: -1.3833, next: moment.addingTimeInterval(83 * 60), previous: moment.addingTimeInterval(-86_000))
        XCTAssertEqual(value.transitText, "transits in 1 h 23 min")
        XCTAssertEqual(value.rowText(style: .sexagesimal), "\(minus)1h 23m \u{00B7} transits in 1 h 23 min")
    }

    func testAnObjectWestOfTheMeridianTransitedBehind() {
        let value = meridian(hourAngle: 25.0 / 60.0, next: moment.addingTimeInterval(86_000),
                             previous: moment.addingTimeInterval(-25 * 60))
        XCTAssertEqual(value.transitText, "transited 25 min ago")
        XCTAssertEqual(value.rowText(style: .sexagesimal), "+0h 25m \u{00B7} transited 25 min ago")
    }

    func testWithoutATransitTheRowIsTheHourAngleAlone() {
        XCTAssertNil(meridian(hourAngle: -2).transitText)
        XCTAssertNil(meridian(hourAngle: 2).transitText)
        XCTAssertEqual(meridian(hourAngle: -2).rowText(style: .decimal), "\(minus)2.000 h")
    }

    // MARK: Working it out

    private func star() -> CelestialObject {
        CelestialObject.custom(name: "Star", j2000: EquatorialCoordinate(rightAscension: 100, declination: 20))
    }

    func testAnObjectGetsItsHourAngleAndTransits() throws {
        let object = star()
        let apparent = SkyFrame(date: moment, observer: denver).apparentEquatorial(of: object)
        let value = try XCTUnwrap(ObjectDetailMeridian.of(object, observer: denver, date: moment, apparent: apparent))
        XCTAssertEqual(value.date, moment)
        XCTAssertEqual(value.hourAngle, MeridianClock.hourAngle(of: apparent, at: moment, observer: denver), accuracy: 1e-12)
        XCTAssertGreaterThan(value.hourAngle, -12)
        XCTAssertLessThanOrEqual(value.hourAngle, 12)
        let transits = MeridianClock.transit(for: object, around: moment, observer: denver)
        XCTAssertEqual(value.next, transits.next)
        XCTAssertEqual(value.previous, transits.previous)
    }

    func testAnObjectThatCannotBeEvaluatedHasNoHourAngle() {
        let object = star()
        let apparent = SkyFrame(date: moment, observer: denver).apparentEquatorial(of: object)
        XCTAssertNil(ObjectDetailMeridian.of(object, observer: denver, date: moment, apparent: apparent, isEvaluable: false))
    }

    func testACelestialPoleHasNoHourAngle() throws {
        let pole = try XCTUnwrap(try Catalog.loadBundled().object(id: "special.ncp"))
        let place = EquatorialCoordinate(rightAscension: 0, declination: 90)
        XCTAssertNil(ObjectDetailMeridian.of(pole, observer: denver, date: moment, apparent: place))
    }

    func testAPlaceThatIsNotAPlaceHasNoHourAngle() {
        let apparent = EquatorialCoordinate(rightAscension: .nan, declination: 0)
        XCTAssertNil(ObjectDetailMeridian.of(star(), observer: denver, date: moment, apparent: apparent))
    }
}

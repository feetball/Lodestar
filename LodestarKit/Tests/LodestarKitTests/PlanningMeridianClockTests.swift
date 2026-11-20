import XCTest
@testable import LodestarKit

/// The hour angle, the meridian transit and the flip countdown of `MeridianClock`.
///
/// Reference instants are the upper culminations of Sirius and the Moon that Skyfield (JPL DE440s) finds in
/// `riseset.json` (Boulder and Sydney, window of 2026-01-15); the sidereal day is 86 164.0905 s (IERS).
final class PlanningMeridianClockTests: XCTestCase {
    private let boulder = PlanningTestSupport.boulder.observer
    private let sydney = PlanningTestSupport.sydney.observer

    /// Sirius as in the fixture generator (Hipparcos, ICRS J2000.0).
    private let sirius = EquatorialCoordinate(rightAscension: 101.28715539, declination: -16.71611582)
    private let siriusMotion = ProperMotion(raMilliarcsecondsPerYear: -546.01, decMilliarcsecondsPerYear: -1223.08)

    /// Skyfield's upper culminations (`riseset.json`): Sirius at Boulder and Sydney, the Moon at Boulder.
    private let boulderSiriusTransit = Date(timeIntervalSince1970: 1_768_543_477.041)
    private let sydneySiriusTransit = Date(timeIntervalSince1970: 1_768_482_089.926)
    private let boulderMoonCulmination = Date(timeIntervalSince1970: 1_768_584_605.891)

    private let siderealDay = 86_164.0905
    private let siderealRatio = 360.985_647_366_29 / 360.0

    private func siriusHourAngle(at date: Date, _ observer: Observer) -> Double {
        let apparent = SkyFrame(date: date, observer: observer).apparentPlace(j2000: sirius, properMotion: siriusMotion)
        return MeridianClock.hourAngle(of: apparent, at: date, observer: observer)
    }

    private func moonHourAngle(at date: Date, _ observer: Observer) -> Double {
        let apparent = SkyFrame(date: date, observer: observer).topocentricEquatorial(of: .moon)
        return MeridianClock.hourAngle(of: apparent, at: date, observer: observer)
    }

    // MARK: Hour angle

    func testHourAngleIsZeroAtSkyfieldsTransitOfSirius() {
        XCTAssertEqual(siriusHourAngle(at: boulderSiriusTransit, boulder), 0, accuracy: 0.0005)
        XCTAssertEqual(siriusHourAngle(at: sydneySiriusTransit, sydney), 0, accuracy: 0.0005)
    }

    func testHourAngleIsNegativeBeforeTheTransitAndPositiveAfterItAtTheSiderealRate() {
        for hours in [0.25, 1.0, 5.0, 11.0] {
            let after = boulderSiriusTransit.addingTimeInterval(hours * 3_600)
            let before = boulderSiriusTransit.addingTimeInterval(-hours * 3_600)
            XCTAssertEqual(siriusHourAngle(at: after, boulder), hours * siderealRatio, accuracy: 0.001, "\(hours) h after")
            XCTAssertEqual(siriusHourAngle(at: before, boulder), -hours * siderealRatio, accuracy: 0.001, "\(hours) h before")
        }
    }

    func testHourAngleWrapsAtTwelveHours() {
        let date = boulderSiriusTransit
        let siderealTime = SkyFrame(date: date, observer: boulder).localApparentSiderealTime
        // The places whose hour angle is 179.85° (11.99 h) and 180.15° (−11.99 h).
        let justBefore = EquatorialCoordinate(rightAscension: siderealTime - 179.85, declination: 10)
        let justAfter = EquatorialCoordinate(rightAscension: siderealTime - 180.15, declination: 10)
        XCTAssertEqual(MeridianClock.hourAngle(of: justBefore, at: date, observer: boulder), 11.99, accuracy: 1e-9)
        XCTAssertEqual(MeridianClock.hourAngle(of: justAfter, at: date, observer: boulder), -11.99, accuracy: 1e-9)
        // A quarter of a turn either side of the meridian is ±6 h.
        let west = EquatorialCoordinate(rightAscension: siderealTime - 90, declination: 0)
        let east = EquatorialCoordinate(rightAscension: siderealTime + 90, declination: 0)
        XCTAssertEqual(MeridianClock.hourAngle(of: west, at: date, observer: boulder), 6, accuracy: 1e-9)
        XCTAssertEqual(MeridianClock.hourAngle(of: east, at: date, observer: boulder), -6, accuracy: 1e-9)
    }

    func testHourAngleOfAnUnusableCoordinateIsNotANumber() {
        let notANumber = EquatorialCoordinate(rightAscension: .nan, declination: 0)
        let infinite = EquatorialCoordinate(rightAscension: .infinity, declination: 0)
        XCTAssertTrue(MeridianClock.hourAngle(of: notANumber, at: boulderSiriusTransit, observer: boulder).isNaN)
        XCTAssertTrue(MeridianClock.hourAngle(of: infinite, at: boulderSiriusTransit, observer: boulder).isNaN)
    }

    // MARK: Transit

    func testTransitOfSiriusMatchesSkyfield() throws {
        for (observer, expected) in [(boulder, boulderSiriusTransit), (sydney, sydneySiriusTransit)] {
            let before = MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion,
                                               around: expected.addingTimeInterval(-3 * 3_600), observer: observer)
            XCTAssertEqual(try XCTUnwrap(before.next).timeIntervalSince(expected), 0, accuracy: 1.5)
            let after = MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion,
                                              around: expected.addingTimeInterval(3 * 3_600), observer: observer)
            XCTAssertEqual(try XCTUnwrap(after.previous).timeIntervalSince(expected), 0, accuracy: 1.5)
        }
    }

    func testTransitsBracketTheDateAWholeSiderealDayApart() throws {
        let date = boulderSiriusTransit.addingTimeInterval(5_000)
        let transits = MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion, around: date, observer: boulder)
        let next = try XCTUnwrap(transits.next)
        let previous = try XCTUnwrap(transits.previous)
        XCTAssertTrue(previous <= date && date < next)
        XCTAssertEqual(next.timeIntervalSince(previous), siderealDay, accuracy: 1)
        XCTAssertEqual(previous.timeIntervalSince(boulderSiriusTransit), 0, accuracy: 1.5)
    }

    func testTransitsAreSearchedWithinOneDayOfTheDate() throws {
        XCTAssertEqual(MeridianClock.searchHalfSpan, 86_400)
        for offset in [-40_000.0, 0, 10, 43_000, 80_000] {
            let date = boulderSiriusTransit.addingTimeInterval(offset)
            let transits = MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion, around: date, observer: boulder)
            let next = try XCTUnwrap(transits.next, "next at \(offset)")
            let previous = try XCTUnwrap(transits.previous, "previous at \(offset)")
            XCTAssertTrue(next > date && next.timeIntervalSince(date) <= 86_400, "next at \(offset)")
            XCTAssertTrue(previous <= date && date.timeIntervalSince(previous) <= 86_400, "previous at \(offset)")
        }
    }

    func testHourAngleIsZeroAtEveryTransitTheSearchFinds() throws {
        let date = boulderSiriusTransit.addingTimeInterval(7_200)
        let ceresBody = try CatalogSmallBodyFixture.ceres
        let ceres = CelestialObject(smallBody: ceresBody)
        let cases: [(String, MeridianTransits)] = [
            ("Sirius", MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion, around: date, observer: boulder)),
            ("Moon", MeridianClock.transit(for: .moon, around: date, observer: boulder)),
            ("Jupiter", MeridianClock.transit(for: .jupiter, around: date, observer: boulder)),
            ("Ceres", MeridianClock.transit(for: ceres, around: date, observer: boulder)),
        ]
        for (name, transits) in cases {
            for transit in [transits.next, transits.previous].compactMap({ $0 }) {
                let frame = SkyFrame(date: transit, observer: boulder)
                let apparent: EquatorialCoordinate
                switch name {
                case "Sirius": apparent = frame.apparentPlace(j2000: sirius, properMotion: siriusMotion)
                case "Moon": apparent = frame.topocentricEquatorial(of: .moon)
                case "Jupiter": apparent = frame.topocentricEquatorial(of: .jupiter)
                default: apparent = try XCTUnwrap(frame.topocentricEquatorial(of: ceresBody))
                }
                XCTAssertEqual(MeridianClock.hourAngle(of: apparent, at: transit, observer: boulder), 0, accuracy: 0.0001,
                               "\(name) at \(transit)")
            }
        }
    }

    func testTheMoonCrossesTheMeridianAwayFromItsHighestPoint() throws {
        // The Moon moves in declination, so its greatest altitude (Skyfield's culmination) is not at hour angle 0: here
        // by 39 s (over January 2026 the gap reaches 4 min at Boulder and 12 min at Tromsø).
        let date = boulderMoonCulmination.addingTimeInterval(-6 * 3_600)
        let transit = try XCTUnwrap(MeridianClock.transit(for: .moon, around: date, observer: boulder).next)
        XCTAssertEqual(transit.timeIntervalSince(boulderMoonCulmination), -39, accuracy: 3)
        XCTAssertEqual(moonHourAngle(at: transit, boulder), 0, accuracy: 0.0001)
        // The Moon drifts east, so its hour angle grows a little slower than a star's: 0.0105 h after 39 s.
        XCTAssertEqual(moonHourAngle(at: boulderMoonCulmination, boulder), 0.0105, accuracy: 0.001)
    }

    func testTheMoonsOtherTransitCanBeBeyondADay() throws {
        // The Moon transits every 24 h 50 min: just after one, the next is out of the day's reach, and just before
        // one, the previous is.
        let date = boulderMoonCulmination.addingTimeInterval(-6 * 3_600)
        let transit = try XCTUnwrap(MeridianClock.transit(for: .moon, around: date, observer: boulder).next)
        let after = MeridianClock.transit(for: .moon, around: transit.addingTimeInterval(60), observer: boulder)
        XCTAssertNil(after.next)
        XCTAssertEqual(try XCTUnwrap(after.previous).timeIntervalSince(transit), 0, accuracy: 0.5)
        let before = MeridianClock.transit(for: .moon, around: transit.addingTimeInterval(-60), observer: boulder)
        XCTAssertNil(before.previous)
        XCTAssertEqual(try XCTUnwrap(before.next).timeIntervalSince(transit), 0, accuracy: 0.5)
    }

    func testTheMoonTransitsAboutTwentyFourFiftyApart() throws {
        let transits = MeridianClock.transit(for: .moon, around: boulderMoonCulmination.addingTimeInterval(-3_600),
                                             observer: boulder)
        let first = try XCTUnwrap(transits.next)
        let second = try XCTUnwrap(MeridianClock.transit(for: .moon, around: first.addingTimeInterval(3_600),
                                                         observer: boulder).next)
        XCTAssertEqual(second.timeIntervalSince(first), 24.84 * 3_600, accuracy: 20 * 60)
    }

    // MARK: Catalog objects

    func testObjectOverloadsFollowThePositionOverloads() throws {
        let catalog = try CatalogFixture.catalog()
        let date = boulderSiriusTransit.addingTimeInterval(7_200)
        let star = try XCTUnwrap(catalog.object(id: "star.hip32349"))
        let fixed = MeridianClock.transit(for: star, around: date, observer: boulder)
        let position = MeridianClock.transit(forJ2000: sirius, properMotion: siriusMotion, around: date, observer: boulder)
        XCTAssertEqual(fixed.previous, position.previous)
        XCTAssertEqual(fixed.next, position.next)
        XCTAssertEqual(try XCTUnwrap(fixed.previous).timeIntervalSince(boulderSiriusTransit), 0, accuracy: 1.5)
        let moon = try XCTUnwrap(catalog.object(id: "moon"))
        XCTAssertEqual(MeridianClock.transit(for: moon, around: date, observer: boulder),
                       MeridianClock.transit(for: .moon, around: date, observer: boulder))
    }

    func testACelestialPoleNeverTransits() throws {
        let catalog = try CatalogFixture.catalog()
        for id in ["special.ncp", "special.scp"] {
            let pole = try XCTUnwrap(catalog.object(id: id), id)
            XCTAssertEqual(MeridianClock.transit(for: pole, around: boulderSiriusTransit, observer: boulder),
                           MeridianTransits(next: nil, previous: nil), id)
        }
    }

    func testACometOrAsteroidTransitsLikeAnyObject() throws {
        let ceres = CelestialObject(smallBody: try CatalogSmallBodyFixture.ceres)
        let transits = MeridianClock.transit(for: ceres, around: boulderSiriusTransit, observer: boulder)
        let next = try XCTUnwrap(transits.next)
        let previous = try XCTUnwrap(transits.previous)
        // Ceres is a main-belt asteroid: a transit comes about a sidereal day (plus its own motion, 53 s here) after the last.
        // A solar day would be 236 s longer than the sidereal one, which the tolerance must refuse.
        XCTAssertEqual(next.timeIntervalSince(previous), siderealDay, accuracy: 90)
    }

    // MARK: Flip window

    func testFlipCountdownWithATenDegreeLimitIsFortyMinutesOfSiderealTime() throws {
        let window = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: 10))
        // 10° of hour angle is 40 minutes of sidereal time, 2400 sidereal seconds: a little less of clock time.
        XCTAssertEqual(window.secondsUntilLimit, 2_400 / siderealRatio, accuracy: 1e-6)
        XCTAssertEqual(window.secondsUntilLimit / 60, 39.89, accuracy: 0.005)
        XCTAssertFalse(window.isPastLimit)
    }

    func testFlipCountdownWithoutALimitRunsToTheMeridian() throws {
        let window = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: -1, limitDegrees: 0))
        XCTAssertEqual(window.secondsUntilLimit, 3_600 / siderealRatio, accuracy: 1e-6)
        XCTAssertFalse(window.isPastLimit)
        // The countdown agrees with the sky: Sirius is on the meridian one clock hour after this instant.
        let date = boulderSiriusTransit.addingTimeInterval(-3_600)
        let countdown = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: siriusHourAngle(at: date, boulder), limitDegrees: 0))
        XCTAssertEqual(countdown.secondsUntilLimit, 3_600, accuracy: 2)
    }

    func testTheMountMustFlipOnceTheLimitIsReached() throws {
        let atLimit = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 10.0 / 15.0, limitDegrees: 10))
        XCTAssertEqual(atLimit.secondsUntilLimit, 0, accuracy: 1e-9)
        XCTAssertTrue(atLimit.isPastLimit)
        let past = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 1, limitDegrees: 10))
        XCTAssertTrue(past.isPastLimit)
        // 5° (20 sidereal minutes) beyond the limit.
        XCTAssertEqual(past.secondsUntilLimit, -1_200 / siderealRatio, accuracy: 1e-6)
        let unlimited = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0.001, limitDegrees: 0))
        XCTAssertTrue(unlimited.isPastLimit)
    }

    func testFlipWindowWrapsTheHourAngleAndClampsTheLimit() throws {
        let wrapped = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 13, limitDegrees: 0))
        let equivalent = try XCTUnwrap(MeridianClock.flipWindow(hourAngle: -11, limitDegrees: 0))
        XCTAssertEqual(wrapped.secondsUntilLimit, equivalent.secondsUntilLimit, accuracy: 1e-6)
        XCTAssertEqual(MeridianClock.limitDegreesRange, 0...30)
        XCTAssertEqual(try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: 30)).secondsUntilLimit,
                       try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: 45)).secondsUntilLimit)
        XCTAssertEqual(try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: 0)).secondsUntilLimit,
                       try XCTUnwrap(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: -5)).secondsUntilLimit)
    }

    func testFlipWindowRefusesInputThatIsNotFinite() {
        XCTAssertNil(MeridianClock.flipWindow(hourAngle: .nan, limitDegrees: 0))
        XCTAssertNil(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: .nan))
        XCTAssertNil(MeridianClock.flipWindow(hourAngle: .infinity, limitDegrees: 0))
        XCTAssertNil(MeridianClock.flipWindow(hourAngle: 0, limitDegrees: -.infinity))
    }
}

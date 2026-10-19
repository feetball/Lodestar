import XCTest
@testable import LodestarKit

/// Supermoons, micromoons and blue moons.
///
/// References: JPL Horizons API (DE441), Moon target 301, geocentric centre distance (quantity 20) at the full Moon of 2026:
/// Jan 3 10:03 UT 362 312.4 km, May 1 17:23 401 999.5 km, May 31 08:45 406 134.7 km, Jun 29 23:57 405 254.0 km, Nov 24 14:53
/// 360 766.1 km, Dec 24 01:28 356 738.3 km. Full Moon times from the kit's phase calculator (checked against the USNO
/// tables to the minute). Blue moons: the full Moons of 2018-01-02 and 2018-01-31, 2018-03-02 and 2018-03-31 and of
/// 2020-10-01 and 2020-10-31 (14:49 UT, which is already 1 November in eastern Australia) are well known.
final class EventsMoonSpecialTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private func specials(_ from: String, _ to: String, _ zone: TimeZone = .gmt) -> [(AstronomicalEvent, FullMoonSpecial)] {
        Support.specials(FullMoonSpecialFinder.events(from: Support.utc(from), to: Support.utc(to), timeZone: zone))
    }

    func testSpecialFullMoonsOf2026() {
        let found = specials("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        XCTAssertEqual(found.count, 6)
        guard found.count == 6 else { return }
        let expected: [(String, [FullMoonCategory], Double)] = [
            ("2026-01-03T10:03:00Z", [.supermoon], 362_312.4),
            ("2026-05-01T17:23:00Z", [.micromoon], 401_999.5),
            ("2026-05-31T08:45:00Z", [.micromoon, .blueMoon], 406_134.7),
            ("2026-06-29T23:57:00Z", [.micromoon], 405_254.0),
            ("2026-11-24T14:53:00Z", [.supermoon], 360_766.1),
            ("2026-12-24T01:28:00Z", [.supermoon], 356_738.3),
        ]
        for index in expected.indices {
            Support.assertInstant(expected[index].0, found[index].0.date, tolerance: 120, "full Moon \(index)")
            XCTAssertEqual(found[index].1.categories, expected[index].1, "categories \(index)")
            Support.assertNear(expected[index].2, found[index].1.distanceKilometers, tolerance: 15, "distance \(index)")
        }
    }

    func testSupermoonOfJanuary2026() {
        // The brief asks for a supermoon in 2026: 3 January, 362 312 km, the Moon's disc 1978″ wide.
        let january = specials("2026-01-01T00:00:00Z", "2026-01-31T23:59:59Z")
        XCTAssertEqual(january.count, 1)
        guard let supermoon = january.first?.1 else { return }
        XCTAssertEqual(supermoon.categories, [.supermoon])
        XCTAssertTrue(supermoon.distanceKilometers <= FullMoonSpecialFinder.supermoonMaximumDistanceKilometers)
        Support.assertNear(1978.0, supermoon.angularDiameterArcseconds, tolerance: 3.0, "angular diameter")
    }

    func testDefinitionsAreDocumentedConstants() {
        XCTAssertEqual(FullMoonSpecialFinder.supermoonMaximumDistanceKilometers, 362_500.0)
        XCTAssertEqual(FullMoonSpecialFinder.micromoonMinimumDistanceKilometers, 400_600.0)
        // Equal margins from the extreme perigee (356 371 km) and apogee (406 720 km) of the lunar orbit.
        Support.assertNear(FullMoonSpecialFinder.supermoonMaximumDistanceKilometers - 356_371.0,
                           406_720.0 - FullMoonSpecialFinder.micromoonMinimumDistanceKilometers, tolerance: 100, "symmetry")
        XCTAssertEqual(FullMoonCategory.allCases.map(\.rawValue), ["supermoon", "micromoon", "blueMoon"])
        XCTAssertEqual(FullMoonCategory(rawValue: "blueMoon"), .blueMoon)
    }

    func testBlueMoonsOf2018() {
        let found = specials("2018-01-01T00:00:00Z", "2018-12-31T23:59:59Z")
        let blue = found.filter { $0.1.categories.contains(.blueMoon) }
        XCTAssertEqual(blue.count, 2)
        guard blue.count == 2 else { return }
        Support.assertInstant("2018-01-31T13:27:00Z", blue[0].0.date, tolerance: 120, "January blue moon")
        Support.assertInstant("2018-03-31T12:37:00Z", blue[1].0.date, tolerance: 120, "March blue moon")
        // The January 31 full Moon was also a supermoon (the "super blue blood moon", total eclipse that day).
        XCTAssertTrue(blue[0].1.categories.contains(.supermoon))
    }

    func testBlueMoonDependsOnTheTimeZone() throws {
        // 2020: full Moons on October 1 21:05 UT and October 31 14:49 UT. In Sydney (UTC+11 in October) the second one
        // falls on 1 November at 01:49, so there is no blue moon there; in UTC and in New York there is.
        let utc = specials("2020-10-01T00:00:00Z", "2020-11-02T00:00:00Z", .gmt)
        XCTAssertEqual(utc.filter { $0.1.categories.contains(.blueMoon) }.count, 1)
        let newYork = specials("2020-10-01T00:00:00Z", "2020-11-02T00:00:00Z", try XCTUnwrap(TimeZone(identifier: "America/New_York")))
        XCTAssertEqual(newYork.filter { $0.1.categories.contains(.blueMoon) }.count, 1)
        let sydney = specials("2020-10-01T00:00:00Z", "2020-11-02T00:00:00Z", try XCTUnwrap(TimeZone(identifier: "Australia/Sydney")))
        XCTAssertEqual(sydney.filter { $0.1.categories.contains(.blueMoon) }.count, 0)
    }

    func testBlueMoonNeedsTheFirstFullMoonOfTheMonthEvenBeforeTheRange() {
        // The range starts after the first full Moon of May 2026 (May 1): the second (May 31) is still blue.
        let found = specials("2026-05-15T00:00:00Z", "2026-06-15T00:00:00Z")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.1.categories, [.micromoon, .blueMoon])
        // And a range that holds only the first full Moon of the month does not make it blue.
        let first = specials("2026-04-25T00:00:00Z", "2026-05-10T00:00:00Z")
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.1.categories, [.micromoon])
    }

    func testEveryReportedMoonIsAFullMoon() {
        for (event, _) in specials("2025-01-01T00:00:00Z", "2027-12-31T23:59:59Z") {
            Support.assertNear(180.0, Ephemeris.lunarElongation(at: JulianDate(date: event.date)), tolerance: 1e-3, "\(event.date)")
        }
    }

    func testSupermoonVisibilityAtMoonrise() throws {
        // The December 2026 supermoon (24 Dec 01:28 UT) at Boulder: 18:28 MST on December 23, with the Moon high in the
        // east after sunset; the window starts after sunset and holds the Moon above 10°.
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let options = EventOptions(kinds: [.fullMoonSpecial], timeZone: denver)
        let events = EventCalculator.events(from: Support.utc("2026-12-20T00:00:00Z"), to: Support.utc("2026-12-28T00:00:00Z"),
                                            observer: Support.boulder.observer, options: options)
        XCTAssertEqual(events.count, 1)
        let visibility = try XCTUnwrap(events.first?.visibility)
        XCTAssertEqual(visibility.darknessLimit, RiseSetCalculator.sunHorizonAltitude)
        XCTAssertTrue(visibility.altitude > 10, "the Moon at the instant of full: \(visibility.altitude)")
        let window = try XCTUnwrap(visibility.bestWindow)
        let night = TwilightCalculator.night(startingOn: Support.utc("2026-12-23T19:00:00Z"), observer: Support.boulder.observer,
                                             timeZone: denver)
        let sunset = try XCTUnwrap(night.sunset)
        XCTAssertTrue(window.start >= sunset.addingTimeInterval(-1), "the window starts after sunset")
        XCTAssertTrue(window.end <= (try XCTUnwrap(night.sunrise)).addingTimeInterval(1))
        XCTAssertEqual(events[0].aimTargets, [.body(.moon)])
    }
}

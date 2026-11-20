import XCTest
@testable import LodestarKit

/// `TwilightCalculator.nightUnderWay`: the rule that says which night "tonight" is, shared by the Tonight screen, the
/// Objects list and the widgets.
final class EphemerisTonightRuleTests: XCTestCase {
    private func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, in timeZone: TimeZone) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return gregorian(timeZone).date(from: components) ?? .distantPast
    }

    private func observer(_ latitude: Double, _ longitude: Double) -> Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude))
    }

    /// What `nightUnderWay` says at `date`, with the engine's own twilight lookup.
    private func underWay(at date: Date, observer: Observer, in zone: TimeZone) -> (day: Date, twilight: NightTwilight)? {
        TwilightCalculator.nightUnderWay(at: date, calendar: gregorian(zone)) { day in
            TwilightCalculator.night(startingOn: day, observer: observer, timeZone: zone)
        }
    }

    // MARK: A night at mid latitudes

    func testAtThreeInTheMorningTonightIsTheNightThatBeganYesterday() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let boulder = observer(40.0, -105.27)
        let found = try XCTUnwrap(underWay(at: date(2026, 10, 18, hour: 3, in: zone), observer: boulder, in: zone))

        XCTAssertEqual(found.twilight.interval.start, date(2026, 10, 17, hour: 12, in: zone))
        XCTAssertEqual(found.twilight.interval.end, date(2026, 10, 18, hour: 12, in: zone))
        XCTAssertEqual(gregorian(zone).startOfDay(for: found.day), date(2026, 10, 17, in: zone))
        XCTAssertEqual(found.twilight, TwilightCalculator.night(startingOn: found.day, observer: boulder, timeZone: zone))
    }

    func testAtThreeInTheAfternoonTonightIsTheComingNight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertNil(underWay(at: date(2026, 10, 18, hour: 15, in: zone), observer: observer(40.0, -105.27), in: zone))
    }

    func testAtNineInTheMorningTheSunHasRisenAndTonightIsTheComingNight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertNil(underWay(at: date(2026, 10, 18, hour: 9, in: zone), observer: observer(40.0, -105.27), in: zone))
    }

    func testTheNightUnderWayEndsAtTheSunriseThatEndsIt() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let boulder = observer(40.0, -105.27)
        let found = try XCTUnwrap(underWay(at: date(2026, 10, 18, hour: 3, in: zone), observer: boulder, in: zone))
        let sunrise = try XCTUnwrap(found.twilight.sunrise)

        XCTAssertNotNil(underWay(at: sunrise.addingTimeInterval(-1), observer: boulder, in: zone))
        XCTAssertNil(underWay(at: sunrise, observer: boulder, in: zone))
        XCTAssertNil(underWay(at: sunrise.addingTimeInterval(1), observer: boulder, in: zone))
    }

    func testTheLookupIsAskedOnceAndForTheDayBefore() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let boulder = observer(40.0, -105.27)
        let calendar = gregorian(zone)
        var asked: [Date] = []
        let found = TwilightCalculator.nightUnderWay(at: date(2026, 10, 18, hour: 3, in: zone), calendar: calendar) { day in
            asked.append(day)
            return TwilightCalculator.night(startingOn: day, observer: boulder, timeZone: zone)
        }
        XCTAssertNotNil(found)
        XCTAssertEqual(asked.map { calendar.startOfDay(for: $0) }, [date(2026, 10, 17, in: zone)])
    }

    // MARK: Daylight-saving changes

    func testAfterTheClocksGoBackThreeInTheMorningIsStillTheNightThatBeganTheDayBefore() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let found = try XCTUnwrap(underWay(at: date(2026, 11, 1, hour: 3, in: zone), observer: observer(40.0, -105.27),
                                           in: zone))
        XCTAssertEqual(found.twilight.interval.start, date(2026, 10, 31, hour: 12, in: zone))
        XCTAssertEqual(found.twilight.interval.duration, 25 * 3_600)
    }

    func testAfterTheClocksGoForwardThreeInTheMorningIsStillTheNightThatBeganTheDayBefore() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let found = try XCTUnwrap(underWay(at: date(2026, 3, 8, hour: 3, in: zone), observer: observer(40.0, -105.27),
                                           in: zone))
        XCTAssertEqual(found.twilight.interval.start, date(2026, 3, 7, hour: 12, in: zone))
        XCTAssertEqual(found.twilight.interval.duration, 23 * 3_600)
    }

    // MARK: Where the Sun does not rise

    func testInTheMidnightSunTheNightUnderWayLastsUntilNoon() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let tromso = observer(69.65, 18.96)
        let found = try XCTUnwrap(underWay(at: date(2026, 6, 22, hour: 3, in: zone), observer: tromso, in: zone))
        XCTAssertNil(found.twilight.sunrise)
        XCTAssertNotNil(underWay(at: date(2026, 6, 22, hour: 11, minute: 59, in: zone), observer: tromso, in: zone))
        XCTAssertNil(underWay(at: date(2026, 6, 22, hour: 12, in: zone), observer: tromso, in: zone))
    }

    func testInThePolarWinterTheNightUnderWayLastsUntilNoon() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let tromso = observer(69.65, 18.96)
        let found = try XCTUnwrap(underWay(at: date(2026, 12, 22, hour: 3, in: zone), observer: tromso, in: zone))
        XCTAssertNil(found.twilight.sunrise)
        XCTAssertNotNil(underWay(at: date(2026, 12, 22, hour: 11, minute: 59, in: zone), observer: tromso, in: zone))
        XCTAssertNil(underWay(at: date(2026, 12, 22, hour: 12, in: zone), observer: tromso, in: zone))
    }
}

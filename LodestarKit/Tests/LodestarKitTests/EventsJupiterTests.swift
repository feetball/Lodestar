import XCTest
@testable import LodestarKit

/// Planet stations, and the Great Red Spot and moon events in the calendar.
///
/// References:
/// - Skyfield 1.55 with JPL DE440s: apparent geocentric ecliptic longitude of date of the planet, the instant of its
///   extremum found on a 4001-point grid over the two days around the 6-hourly sign change of the rate and refined by a
///   parabola through 101 points. Mars retrograde begins 2024-12-06 23:33:09 UT (126.171°) and direct motion resumes
///   2025-02-24 01:59:50 UT (107.015°), Mars again 2027-01-10 12:59:11 UT; Mercury retrograde begins 2026-02-26
///   06:48:10 UT and direct motion resumes 2026-03-20 19:32:50 UT; Jupiter retrograde begins 2026-12-13 00:56:36 UT.
final class EventsJupiterTests: XCTestCase {
    private typealias Support = EventsTestSupport

    // MARK: Stations

    func testMarsStationsAgainstDE440s() throws {
        let found = PlanetStations.find(planet: .mars, from: Support.utc("2024-10-01T00:00:00Z"),
                                        to: Support.utc("2025-04-01T00:00:00Z"))
        XCTAssertEqual(found.count, 2)
        guard found.count == 2, case let .planetStation(first) = found[0].details,
              case let .planetStation(second) = found[1].details else { return }
        XCTAssertEqual(first.kind, .retrogradeBegins)
        XCTAssertEqual(second.kind, .directMotionResumes)
        XCTAssertEqual(first.planet, .mars)
        Support.assertInstant("2024-12-06T23:33:09Z", found[0].date, tolerance: 3 * 3600, "Mars retrograde")
        Support.assertInstant("2025-02-24T01:59:50Z", found[1].date, tolerance: 3 * 3600, "Mars direct")
        Support.assertNear(126.171, first.longitude, tolerance: 0.05, "Mars longitude")
        Support.assertNear(107.015, second.longitude, tolerance: 0.05, "Mars longitude")
        XCTAssertTrue(found.allSatisfy { $0.visibility == nil && $0.kind == .planetStation })
    }

    func testMercuryAndJupiterStationsAgainstDE440s() {
        let mercury = PlanetStations.find(planet: .mercury, from: Support.utc("2026-01-01T00:00:00Z"),
                                          to: Support.utc("2026-04-30T00:00:00Z"))
        XCTAssertEqual(mercury.count, 2)
        guard mercury.count == 2 else { return }
        Support.assertInstant("2026-02-26T06:48:10Z", mercury[0].date, tolerance: 3 * 3600, "Mercury retrograde")
        Support.assertInstant("2026-03-20T19:32:50Z", mercury[1].date, tolerance: 3 * 3600, "Mercury direct")
        let jupiter = PlanetStations.find(planet: .jupiter, from: Support.utc("2026-11-01T00:00:00Z"),
                                          to: Support.utc("2027-01-31T00:00:00Z"))
        XCTAssertEqual(jupiter.count, 1)
        guard let station = jupiter.first else { return }
        Support.assertInstant("2026-12-13T00:56:36Z", station.date, tolerance: 12 * 3600, "Jupiter retrograde")
    }

    func testStationSearchLimits() {
        let from = Support.utc("2024-10-01T00:00:00Z")
        XCTAssertTrue(PlanetStations.find(planet: .moon, from: from, to: Support.utc("2025-04-01T00:00:00Z")).isEmpty)
        XCTAssertTrue(PlanetStations.find(planet: .sun, from: from, to: Support.utc("2025-04-01T00:00:00Z")).isEmpty)
        XCTAssertTrue(PlanetStations.find(planet: .mars, from: Support.utc("2025-04-01T00:00:00Z"), to: from).isEmpty)
        // Every planet from Mercury to Neptune has stations in a few years, alternating retrograde and direct.
        for planet in [SolarSystemBody.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune] {
            let stations = PlanetStations.find(planet: planet, from: Support.utc("2025-01-01T00:00:00Z"),
                                               to: Support.utc("2028-01-01T00:00:00Z"))
            XCTAssertTrue(stations.count >= 2, "\(planet): \(stations.count)")
            let kinds: [PlanetStationKind] = stations.compactMap {
                if case let .planetStation(station) = $0.details { return station.kind }
                return nil
            }
            for (previous, next) in zip(kinds, kinds.dropFirst()) { XCTAssertTrue(previous != next, "\(planet) alternates") }
        }
        let year = PlanetStations.events(from: Support.utc("2026-01-01T00:00:00Z"), to: Support.utc("2026-12-31T23:59:59Z"))
        XCTAssertEqual(year.count, 16)
        XCTAssertEqual(year.sorted { $0.date < $1.date }, year)
        let marsEvents = PlanetStations.find(planet: .mars, from: from, to: Support.utc("2025-04-01T00:00:00Z"))
        guard let event = marsEvents.first else { return XCTFail("no Mars station") }
        XCTAssertEqual(event.title, "Mars stationary: retrograde motion begins")
        XCTAssertEqual(event.aimTargets, [.body(.mars)])
    }

    // MARK: Calendar

    func testCalendarListsGreatRedSpotAndMoonEventsForTheFirstDays() {
        let from = Support.utc("2026-11-19T00:00:00Z")
        let to = Support.utc("2026-12-19T00:00:00Z")
        let options = EventOptions(kinds: [.greatRedSpotTransit, .jupiterMoonEvent])
        let events = EventCalculator.events(from: from, to: to, observer: nil, options: options)
        XCTAssertFalse(events.isEmpty)
        let limit = from.addingTimeInterval(2 * 86_400)
        XCTAssertTrue(events.allSatisfy { $0.date <= limit }, "only the first two days")
        let transits = events.filter { $0.kind == .greatRedSpotTransit }
        XCTAssertTrue((4...6).contains(transits.count), "transits: \(transits.count)")
        XCTAssertTrue(events.contains { $0.kind == .jupiterMoonEvent })
        XCTAssertTrue(transits.allSatisfy { $0.title == "Great Red Spot transit" && $0.aimTargets == [.body(.jupiter)] })
        XCTAssertEqual(events.sorted { $0.date < $1.date }, events)
        // The window of the days can be changed, or switched off.
        let none = EventCalculator.events(from: from, to: to, observer: nil,
                                          options: EventOptions(kinds: options.kinds, jupiterEventDays: 0))
        XCTAssertTrue(none.isEmpty)
        let week = EventCalculator.events(from: from, to: to, observer: nil,
                                          options: EventOptions(kinds: options.kinds, jupiterEventDays: 7))
        XCTAssertTrue(week.count > events.count * 3)
        XCTAssertEqual(EventOptions(jupiterEventDays: .nan).jupiterEventDays, 2.0)
        XCTAssertEqual(EventOptions(jupiterEventDays: 100).jupiterEventDays, 30.0)
    }

    func testCalendarUsesTheGreatRedSpotOfTheOptions() throws {
        let from = Support.utc("2026-11-19T00:00:00Z")
        let to = Support.utc("2026-11-20T00:00:00Z")
        let shifted = try XCTUnwrap(GreatRedSpot(longitude: GreatRedSpot.reference.systemIILongitude(at: from) + 30,
                                                 epoch: from, driftPer30Days: 0))
        let kinds: Set<EventKind> = [.greatRedSpotTransit]
        let reference = EventCalculator.events(from: from, to: to, observer: nil, options: EventOptions(kinds: kinds))
        let other = EventCalculator.events(from: from, to: to, observer: nil,
                                           options: EventOptions(kinds: kinds, greatRedSpot: shifted))
        XCTAssertTrue(reference.count >= 2 && other.count >= 2)
        XCTAssertTrue(reference[0].date != other[0].date)
    }

    func testJupiterEventsAreObservableOnlyWhileJupiterIsUpInTheDark() throws {
        let from = Support.utc("2026-12-01T00:00:00Z")
        let to = Support.utc("2026-12-03T00:00:00Z")
        let kinds: Set<EventKind> = [.greatRedSpotTransit, .jupiterMoonEvent]
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let options = EventOptions(kinds: kinds, timeZone: chicago)
        let events = EventCalculator.events(from: from, to: to, observer: Support.dallas.observer, options: options)
        XCTAssertTrue(events.count > 10)
        let visible = events.filter { $0.visibility?.isObservable == true }
        XCTAssertTrue(!visible.isEmpty && visible.count < events.count,
                      "some are, some are not: \(visible.count) of \(events.count)")
        for event in events {
            let visibility = try XCTUnwrap(event.visibility)
            if let window = visibility.bestWindow {
                XCTAssertTrue(window.start.timeIntervalSince(event.date) <= 3 * 3600)
                XCTAssertNotNil(visibility.bestTime)
            }
            if visibility.isObservable {
                XCTAssertTrue(visibility.altitude > 5, "\(event.title): altitude \(visibility.altitude)")
                XCTAssertTrue(visibility.sunAltitude < -3, "\(event.title): Sun at \(visibility.sunAltitude)")
            }
        }
        let onlyVisible = EventCalculator.events(from: from, to: to, observer: Support.dallas.observer,
                                                 options: EventOptions(kinds: kinds, timeZone: chicago, visibleOnly: true))
        XCTAssertEqual(visible.count, onlyVisible.count)
    }

    func testStationsInTheCalendarCarryVisibility() {
        let options = EventOptions(kinds: [.planetStation])
        let events = EventCalculator.events(from: Support.utc("2026-06-01T00:00:00Z"), to: Support.utc("2026-12-31T00:00:00Z"),
                                            observer: Support.dallas.observer, options: options)
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.visibility != nil && $0.kind == .planetStation })
        XCTAssertEqual(EventKind(rawValue: "planetStation"), .planetStation)
        XCTAssertEqual(EventKind(rawValue: "greatRedSpotTransit"), .greatRedSpotTransit)
        XCTAssertEqual(EventKind(rawValue: "jupiterMoonEvent"), .jupiterMoonEvent)
        XCTAssertTrue(EventKind.calendarKinds.isSuperset(of: [.planetStation, .jupiterMoonEvent, .greatRedSpotTransit]))
        XCTAssertTrue(EventKind.defaultKinds.isDisjoint(with: [.planetStation, .jupiterMoonEvent, .greatRedSpotTransit]))
    }
}

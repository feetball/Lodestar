import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Contexts and instants for the tests of `EventsModel`. The real calculator runs behind it (about a year of events
/// takes seconds in a debug build), so the tests keep the number of runs small.
private enum EventsModelFixtures {
    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: .nan)
    }

    static func context(latitude: Double, longitude: Double, zone identifier: String) -> ObserverContext {
        ObserverContext(
            observer: Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: 700)),
            timeZone: TimeZone(identifier: identifier) ?? TimeZone.gmt, name: "Test site", source: .device)
    }

    /// Burgos in Spain, in Madrid's zone: in the path of the total solar eclipse of 2026-08-12.
    static let burgos = context(latitude: 42.3439, longitude: -3.6969, zone: "Europe/Madrid")

    /// A place north of Burgos, at half of the distance the events may be reused over (a degree of latitude is 111.195 km).
    static let nearBurgos = context(latitude: 42.3439 + 0.5 * EventsKey.placeToleranceKilometers / 111.195,
                                    longitude: -3.6969, zone: "Europe/Madrid")

    /// Burgos's place with another zone: the same day starts at another instant.
    static let burgosInLisbon = context(latitude: 42.3439, longitude: -3.6969, zone: "Europe/Lisbon")

    /// Sydney, on the other side of the world.
    static let sydney = context(latitude: -33.87, longitude: 151.21, zone: "Australia/Sydney")

    /// 12:00 in Madrid on 2026-08-01.
    static let now = date("2026-08-01T10:00:00Z")
}

@MainActor
final class EventsModelTests: XCTestCase {
    private typealias F = EventsModelFixtures

    /// Waits until the model has events, up to `timeout` seconds of real time.
    private func waitForEntries(of model: EventsModel, timeout: TimeInterval = 240) async throws -> [EventsEntry] {
        let deadline = Date().addingTimeInterval(timeout)
        while model.entries == nil {
            if Date() > deadline {
                XCTFail("The events were not ready after \(timeout) s")
                return []
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return model.entries ?? []
    }

    // MARK: Before the first run

    func testAFreshModelHasNoEvents() {
        let model = EventsModel()
        XCTAssertNil(model.entries)
        XCTAssertTrue(model.upcoming(after: Date(timeIntervalSince1970: 0)).isEmpty)
    }

    // MARK: A run

    func testARunWorksOutTheEventsOfTheNextYearInTimeOrder() async throws {
        let model = EventsModel()
        model.refresh(context: F.burgos, now: F.now)
        // The run is asynchronous: nothing has been assigned yet, and a second call with the same key changes nothing.
        XCTAssertNil(model.entries)
        model.refresh(context: F.burgos, now: F.now)
        XCTAssertNil(model.entries)
        XCTAssertTrue(model.upcoming(after: Date(timeIntervalSince1970: 0)).isEmpty)

        let entries = try await waitForEntries(of: model)
        let key = EventsKey(context: F.burgos, now: F.now)
        let first = try XCTUnwrap(entries.first)
        let last = try XCTUnwrap(entries.last)
        XCTAssertGreaterThanOrEqual(first.event.date, key.dayStart)
        XCTAssertLessThanOrEqual(last.event.date, key.end)
        for index in entries.indices.dropFirst() {
            XCTAssertLessThanOrEqual(entries[index - 1].event.date, entries[index].event.date)
        }

        // Every row of a list needs its own identifier.
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        // The Earth's apsides are not asked for.
        XCTAssertFalse(entries.contains { $0.event.kind == .earthApsis })
        // Only meteor showers carry the Moon's effect.
        XCTAssertTrue(entries.contains { $0.event.kind == .meteorShower })
        XCTAssertTrue(entries.allSatisfy { ($0.moonInterference != nil) == ($0.event.kind == .meteorShower) })
        // The observer is known, so what is seen in the sky has a visibility, and the seasons do not.
        XCTAssertTrue(entries.contains { $0.event.kind == .lunarEclipse })
        XCTAssertTrue(entries.filter { $0.event.kind == .lunarEclipse }.allSatisfy { $0.event.visibility != nil })
        XCTAssertTrue(entries.contains { $0.event.kind == .season })
        XCTAssertTrue(entries.filter { $0.event.kind == .season }.allSatisfy { $0.event.visibility == nil })

        // The total solar eclipse of 2026-08-12 is total at Burgos.
        let greatest = F.date("2026-08-12T17:45:51Z")
        let eclipse = try XCTUnwrap(entries.first { entry in
            entry.event.kind == .solarEclipse && abs(entry.event.date.timeIntervalSince(greatest)) < 120
        })
        XCTAssertEqual(eclipse.isVisibleFromHere, true)
        guard case .solarEclipse(let details) = eclipse.event.details else {
            return XCTFail("The event is not a solar eclipse")
        }
        XCTAssertEqual(details.local?.kind, .total)
        let summary = EventsFormat.summary(of: eclipse, isSouthernHemisphere: false, timeZone: F.burgos.timeZone)
        XCTAssertTrue(summary.hasPrefix("Total here: "), summary)

        // The upcoming events are those from now on, a moment in time included.
        let middle = entries[entries.count / 2].event.date
        let later = model.upcoming(after: middle)
        XCTAssertEqual(later.first?.event.date, middle)
        XCTAssertEqual(later.count, entries.filter { $0.event.date >= middle }.count)
        XCTAssertLessThan(later.count, entries.count)
        XCTAssertEqual(model.upcoming(after: Date(timeIntervalSince1970: 0)), entries)
        XCTAssertTrue(model.upcoming(after: Date.distantFuture).isEmpty)
    }

    // MARK: Keeping and replacing the events

    func testTheEventsFollowTheObserver() async throws {
        let model = EventsModel()
        model.refresh(context: F.burgos, now: F.now)
        let first = try await waitForEntries(of: model)

        // A place within the tolerance on the same day is covered: the events stay.
        model.refresh(context: F.nearBurgos, now: F.now)
        XCTAssertEqual(model.entries, first)
        // So is the same place later on the same local day.
        model.refresh(context: F.burgos, now: F.now.addingTimeInterval(3 * 3_600))
        XCTAssertEqual(model.entries, first)

        // The next day is a little out of date, but the events stay until new ones are there.
        model.refresh(context: F.burgos, now: F.now.addingTimeInterval(86_400))
        XCTAssertEqual(model.entries, first)

        // The same place in another time zone drops the events at once: the days are counted in the zone.
        model.refresh(context: F.burgosInLisbon, now: F.now)
        XCTAssertNil(model.entries)

        // A place on the other side of the world would show the wrong visibility. Only the newest run may deliver:
        // the two runs started before it are stale, and their results are discarded.
        model.refresh(context: F.sydney, now: F.now)
        XCTAssertNil(model.entries)
        let sydney = try await waitForEntries(of: model)
        XCTAssertEqual(sydney, EventsCalculator.entries(for: EventsKey(context: F.sydney, now: F.now)))
        XCTAssertNotEqual(sydney, first)
    }
}

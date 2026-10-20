import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The events of one place are reused only for a place within GPS jitter of it (10 km): the local circumstances of an
/// eclipse are worked out for one place, and a totality path is only a few hundred kilometres wide. The distances here are
/// written out in kilometres (a degree of latitude is 111.195 km), not derived from `placeToleranceKilometers`, so that they
/// pin its value.
final class FixOnlineEventsTests: XCTestCase {
    private let kilometresPerDegree = 111.195
    /// Burgos in Spain, in the path of the total solar eclipse of 2026-08-12.
    private let burgosLatitude = 42.3439
    private let burgosLongitude = -3.6969

    private func key(northKilometres: Double = 0, zone: String = "Europe/Madrid",
                     now: String = "2026-08-01T10:00:00Z") -> EventsKey {
        let context = ObserverContext(
            observer: Observer(location: GeographicLocation(latitude: burgosLatitude + northKilometres / kilometresPerDegree,
                                                            longitude: burgosLongitude, elevation: 700)),
            timeZone: TimeZone(identifier: zone) ?? TimeZone.gmt, name: "Test site", source: .device)
        return EventsKey(context: context, now: ISO8601DateFormatter().date(from: now) ?? Date(timeIntervalSince1970: .nan))
    }

    func testTheToleranceIsTenKilometres() {
        XCTAssertEqual(EventsKey.placeToleranceKilometers, 10)
    }

    func testAPlaceFiftyKilometresAwayIsNotCovered() {
        // The old tolerance of 100 km reused the eclipse circumstances of Burgos 50 km away, where the totality may not reach.
        let here = key()
        let away = key(northKilometres: 50)
        XCTAssertFalse(here.covers(away))
        XCTAssertFalse(here.isNear(away))
        XCTAssertFalse(away.covers(here))
    }

    func testAPlaceJustOverTenKilometresAwayIsNotCovered() {
        XCTAssertFalse(key().covers(key(northKilometres: 10.5)))
        XCTAssertFalse(key().covers(key(northKilometres: -10.5)))
    }

    func testAPlaceWithinGPSJitterIsStillCovered() {
        XCTAssertTrue(key().covers(key(northKilometres: 0.05)))
        XCTAssertTrue(key().covers(key(northKilometres: 5)))
        XCTAssertTrue(key().covers(key(northKilometres: 9.5)))
        XCTAssertTrue(key().covers(key(northKilometres: -9.5)))
    }

    func testTheSamePlaceLaterTheSameDayIsStillCovered() {
        XCTAssertTrue(key().covers(key(now: "2026-08-01T14:00:00Z")))
    }

    func testAPlaceThatIsNotNearIsNotNearOnAnotherDayEither() {
        XCTAssertFalse(key().isNear(key(northKilometres: 50, now: "2026-08-03T10:00:00Z")))
        XCTAssertTrue(key().isNear(key(northKilometres: 5, now: "2026-08-03T10:00:00Z")))
    }
}

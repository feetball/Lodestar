import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `ObserverContext`: the location it exposes and the calendar in the observer's time zone.
final class SettingsObserverContextTests: XCTestCase {
    private let boulder = GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650)

    private func makeContext(zone: TimeZone = TimeZone(identifier: "America/Denver")!, name: String = "Home",
                         source: LocationSource = .device, horizon: HorizonProfile? = nil) -> ObserverContext {
        ObserverContext(observer: Observer(location: boulder), timeZone: zone, name: name, source: source,
                        horizontalAccuracy: nil, timestamp: nil, horizon: horizon)
    }

    func testTheLocationIsTheObserversLocation() {
        let context = makeContext()
        XCTAssertEqual(context.location, boulder)
        XCTAssertEqual(context.location, context.observer.location)
    }

    func testTheCalendarIsGregorianInTheObserversTimeZone() {
        let zone = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!
        let calendar = makeContext(zone: zone).calendar
        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.timeZone, zone)
    }

    func testTheCalendarReadsLocalTimeInTheObserversZone() {
        // 1970-01-01 00:00 UTC is 05:30 on the same day at UTC+5:30, and 19:00 on 31 December 1969 at UTC-5.
        let epoch = Date(timeIntervalSince1970: 0)
        let india = makeContext(zone: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!).calendar
            .dateComponents([.year, .month, .day, .hour, .minute], from: epoch)
        XCTAssertEqual(india.year, 1970)
        XCTAssertEqual(india.month, 1)
        XCTAssertEqual(india.day, 1)
        XCTAssertEqual(india.hour, 5)
        XCTAssertEqual(india.minute, 30)

        let west = makeContext(zone: TimeZone(secondsFromGMT: -5 * 3600)!).calendar
            .dateComponents([.year, .month, .day, .hour, .minute], from: epoch)
        XCTAssertEqual(west.year, 1969)
        XCTAssertEqual(west.month, 12)
        XCTAssertEqual(west.day, 31)
        XCTAssertEqual(west.hour, 19)
        XCTAssertEqual(west.minute, 0)
    }

    func testTheCalendarFollowsADaylightSavingZone() {
        let denver = TimeZone(identifier: "America/Denver")!
        let calendar = makeContext(zone: denver).calendar
        // 2024-07-01 12:00 UTC is 06:00 MDT; 2024-01-15 12:00 UTC is 05:00 MST.
        XCTAssertEqual(calendar.component(.hour, from: Date(timeIntervalSince1970: 1_719_835_200)), 6)
        XCTAssertEqual(calendar.component(.hour, from: Date(timeIntervalSince1970: 1_705_320_000)), 5)
    }

    func testTheGPSDetailsAreOptional() {
        var context = makeContext()
        XCTAssertNil(context.horizontalAccuracy)
        XCTAssertNil(context.timestamp)
        context.horizontalAccuracy = 12.5
        context.timestamp = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(context.horizontalAccuracy, 12.5)
        XCTAssertEqual(context.timestamp, Date(timeIntervalSince1970: 100))
    }

    func testContextsAreEqualWhenEveryPartIsEqual() {
        XCTAssertEqual(makeContext(), makeContext())
        XCTAssertNotEqual(makeContext(), makeContext(name: "Cabin"))
        XCTAssertNotEqual(makeContext(), makeContext(zone: TimeZone(identifier: "Europe/Zurich")!))
        XCTAssertNotEqual(makeContext(), makeContext(source: .site(UUID())))
        XCTAssertNotEqual(makeContext(), makeContext(horizon: HorizonProfile.constant(10)))
        XCTAssertEqual(makeContext(horizon: HorizonProfile.constant(10)), makeContext(horizon: HorizonProfile.constant(10)))
    }

    func testTheSourceNamesTheSite() {
        let id = UUID()
        XCTAssertEqual(makeContext(source: .site(id)).source, .site(id))
        XCTAssertEqual(makeContext().source, .device)
    }
}

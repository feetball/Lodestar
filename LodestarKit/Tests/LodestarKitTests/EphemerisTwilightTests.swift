import XCTest
@testable import LodestarKit

final class EphemerisTwilightTests: XCTestCase {
    private func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in timeZone: TimeZone) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour)
        return gregorian(timeZone).date(from: components) ?? .distantPast
    }

    /// The night that starts on a local calendar day, from any instant `hour` o'clock that day.
    private func nightStarting(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, observer: Observer,
                               in zone: TimeZone) -> NightTwilight {
        TwilightCalculator.night(startingOn: date(year, month, day, hour: hour, in: zone), observer: observer, timeZone: zone)
    }

    private func observer(_ latitude: Double, _ longitude: Double) -> Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude))
    }

    /// The Sun's geometric altitude, from a fresh `SkyFrame`.
    private func sunAltitude(at date: Date, observer: Observer) -> Double {
        SkyFrame(date: date, observer: observer).horizontal(of: .sun, refraction: false).altitude
    }

    private func orderedEvents(_ night: NightTwilight) -> [Date?] {
        [night.sunset, night.civilDusk, night.nauticalDusk, night.astronomicalDusk,
         night.astronomicalDawn, night.nauticalDawn, night.civilDawn, night.sunrise]
    }

    // MARK: Ordinary nights

    func testNightAtMidLatitudesHasTheTwilightsInOrder() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let boulder = observer(40.0, -105.27)
        let night = nightStarting(2026, 10, 17, hour: 9, observer: boulder, in: zone)
        let events = try orderedEvents(night).map { try XCTUnwrap($0) }

        for (earlier, later) in zip(events, events.dropFirst()) { XCTAssertLessThan(earlier, later) }
        XCTAssertTrue(night.interval.contains(events.first ?? .distantPast))
        XCTAssertTrue(night.interval.contains(events.last ?? .distantFuture))
        XCTAssertEqual(night.interval.start, date(2026, 10, 17, hour: 12, in: zone))
        XCTAssertEqual(night.interval.end, date(2026, 10, 18, hour: 12, in: zone))

        // At each event the Sun is at the corresponding altitude (to the resolution of the search).
        let thresholds = [-0.8333, -6, -12, -18, -18, -12, -6, -0.8333]
        for (event, threshold) in zip(events, thresholds) {
            XCTAssertEqual(sunAltitude(at: event, observer: boulder), threshold, accuracy: 0.002)
        }
        // Boulder, 17 October: sunset 18:18 and sunrise 07:15 MDT (Skyfield, DE440s).
        let calendar = gregorian(zone)
        let sunsetHour = calendar.component(.hour, from: try XCTUnwrap(night.sunset))
        let sunriseHour = calendar.component(.hour, from: try XCTUnwrap(night.sunrise))
        XCTAssertEqual(sunsetHour, 18)
        XCTAssertEqual(sunriseHour, 7)
        let astronomicalNight = try XCTUnwrap(night.astronomicalNight)
        XCTAssertEqual(astronomicalNight.start, night.astronomicalDusk)
        XCTAssertEqual(astronomicalNight.end, night.astronomicalDawn)
        // The Sun takes 90 minutes to go from sunset to −18° at this latitude and season.
        XCTAssertEqual(astronomicalNight.start.timeIntervalSince(try XCTUnwrap(night.sunset)) / 60, 90, accuracy: 3)
    }

    func testSolarMidnightIsTheLowestPointOfTheSun() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let berlin = observer(52.52, 13.4)
        let night = nightStarting(2026, 3, 20, observer: berlin, in: zone)
        XCTAssertTrue(night.interval.contains(night.solarMidnight))
        XCTAssertEqual(night.sunAltitudeAtMidnight, sunAltitude(at: night.solarMidnight, observer: berlin), accuracy: 1e-3)
        for offset in [-3600.0, -600, 600, 3600] {
            XCTAssertGreaterThan(sunAltitude(at: night.solarMidnight.addingTimeInterval(offset), observer: berlin),
                                 night.sunAltitudeAtMidnight)
        }
        // At the equinox the Sun reaches −(90° − 52.52°) = −37.5° at midnight (−37.3° with the
        // declination of that night, +0.1°).
        XCTAssertEqual(night.sunAltitudeAtMidnight, -37.35, accuracy: 0.15)
        // Solar midnight in Berlin (13.4° E, equation of time −7 min) is at 00:14 CET.
        let components = gregorian(zone).dateComponents([.hour, .minute], from: night.solarMidnight)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(Double(components.minute ?? 0), 14, accuracy: 4)
    }

    func testSouthernHemisphereAndLargeOffsets() throws {
        let cases: [(String, Double, Double)] = [
            ("Australia/Sydney", -33.87, 151.21), ("Pacific/Auckland", -36.85, 174.76),
            ("Pacific/Kiritimati", 1.87, -157.4), ("America/Anchorage", 61.2, -149.9), ("Asia/Kolkata", 28.6, 77.2),
            ("Asia/Kathmandu", 27.7, 85.3),
        ]
        for (identifier, latitude, longitude) in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            let night = TwilightCalculator.night(startingOn: date(2026, 1, 15, hour: 12, in: zone),
                                                 observer: observer(latitude, longitude), timeZone: zone)
            let events = try orderedEvents(night).map { try XCTUnwrap($0, identifier) }
            for (earlier, later) in zip(events, events.dropFirst()) { XCTAssertLessThan(earlier, later, identifier) }
            XCTAssertEqual(night.interval.duration, 86_400, accuracy: 1, identifier)
            XCTAssertTrue(night.interval.contains(night.solarMidnight), identifier)
        }
    }

    // MARK: Local dates and daylight saving

    func testIntervalRunsFromLocalNoonToLocalNoonAcrossDaylightSavingChanges() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let calendar = gregorian(zone)
        let newYork = observer(40.71, -74.0)

        // Clocks go forward at 02:00 on 2026-03-08 and back at 02:00 on 2026-11-01.
        let springNight = nightStarting(2026, 3, 7, hour: 20, observer: newYork, in: zone)
        XCTAssertEqual(springNight.interval.duration, 23 * 3600, accuracy: 0.001)
        let autumnNight = nightStarting(2026, 10, 31, hour: 20, observer: newYork, in: zone)
        XCTAssertEqual(autumnNight.interval.duration, 25 * 3600, accuracy: 0.001)
        let ordinary = nightStarting(2026, 5, 5, hour: 3, observer: newYork, in: zone)
        XCTAssertEqual(ordinary.interval.duration, 24 * 3600, accuracy: 0.001)

        for night in [springNight, autumnNight, ordinary] {
            for boundary in [night.interval.start, night.interval.end] {
                let components = calendar.dateComponents([.hour, .minute, .second], from: boundary)
                XCTAssertEqual(components.hour, 12)
                XCTAssertEqual(components.minute, 0)
                XCTAssertEqual(components.second, 0)
            }
            for event in orderedEvents(night) {
                XCTAssertTrue(night.interval.contains(try XCTUnwrap(event)))
            }
        }
        // The events follow the Sun, not the clock: the wall-clock gap across the change is an hour
        // different in the two directions but the physical times are continuous (about 4 minutes a day).
        let before = nightStarting(2026, 3, 6, hour: 12, observer: newYork, in: zone)
        let shift = try XCTUnwrap(springNight.sunset).timeIntervalSince(try XCTUnwrap(before.sunset)) - 86_400
        XCTAssertEqual(shift, 90, accuracy: 60)
    }

    func testAnyInstantOfTheLocalDayGivesTheSameNight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let tokyo = observer(35.68, 139.69)
        let firstSecond = date(2026, 6, 10, hour: 0, in: zone).addingTimeInterval(1)
        let lastSecond = date(2026, 6, 10, hour: 23, in: zone).addingTimeInterval(3599)
        let morning = TwilightCalculator.night(startingOn: firstSecond, observer: tokyo, timeZone: zone)
        let evening = TwilightCalculator.night(startingOn: lastSecond, observer: tokyo, timeZone: zone)
        XCTAssertEqual(morning, evening)
        // The following local day is a different night.
        let next = nightStarting(2026, 6, 11, hour: 1, observer: tokyo, in: zone)
        XCTAssertEqual(next.interval.start, morning.interval.end)
    }

    func testTheSameInstantIsADifferentNightInDifferentTimeZones() throws {
        // 2026-10-17 03:00 UTC is already the 17th in Sydney but still the 16th in Denver.
        let instant = Date(timeIntervalSince1970: 1_792_206_000)
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let sydney = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        let inDenver = TwilightCalculator.night(startingOn: instant, observer: observer(40, -105.27), timeZone: denver)
        let inSydney = TwilightCalculator.night(startingOn: instant, observer: observer(-33.87, 151.21), timeZone: sydney)
        XCTAssertEqual(gregorian(denver).component(.day, from: inDenver.interval.start), 16)
        XCTAssertEqual(gregorian(sydney).component(.day, from: inSydney.interval.start), 17)
    }

    /// A clock that is ten hours ahead of the Sun puts local noon at 02:00 solar time, so the window holds
    /// a morning sunrise, the evening sunset, solar midnight, and ends before the next sunrise.
    func testEventsBeforeSolarMidnightAreDuskAndAfterAreDawn() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 10 * 3600))
        let night = nightStarting(2026, 3, 20, hour: 6, observer: observer(0, 0), in: zone)
        let sunset = try XCTUnwrap(night.sunset)
        XCTAssertNil(night.sunrise)
        XCTAssertNil(night.civilDawn)
        XCTAssertLessThan(sunset, night.solarMidnight)
        // At the equator on the equinox the Sun sets at 18:07 solar time (18:00 plus semi-diameter and refraction).
        let solarTime = sunset.timeIntervalSince(night.interval.start) / 3600 + 2.0
        XCTAssertEqual(solarTime, 18.1, accuracy: 0.1)
        // The morning sunrise at about 06:00 solar time is before solar midnight and is not a dawn.
        let crossings = RiseSetCalculator.crossings(of: .sun, observer: observer(0, 0), within: night.interval)
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting])
        XCTAssertEqual(night.astronomicalNight, night.astronomicalDusk.map { DateInterval(start: $0, end: night.interval.end) })
    }

    // MARK: Polar regions

    func testMidnightSunAtTromsoHasNoSunsetOrTwilight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let night = nightStarting(2026, 6, 21, observer: observer(69.65, 18.96), in: zone)
        for event in orderedEvents(night) { XCTAssertNil(event) }
        XCTAssertNil(night.astronomicalNight)
        // The Sun is 3° above the horizon at its lowest, around local solar midnight.
        XCTAssertEqual(night.sunAltitudeAtMidnight, 3.08, accuracy: 0.05)
    }

    func testPolarWinterAtTromsoHasTwilightsButNoSunrise() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let tromso = observer(69.65, 18.96)
        let night = nightStarting(2026, 12, 21, observer: tromso, in: zone)
        XCTAssertNil(night.sunset)
        XCTAssertNil(night.sunrise)
        // The Sun peaks at −3.1° at noon: it crosses −6°, −12° and −18° on its way down and up again.
        let twilights = [night.civilDusk, night.nauticalDusk, night.astronomicalDusk,
                         night.astronomicalDawn, night.nauticalDawn, night.civilDawn]
        let events = try twilights.map { try XCTUnwrap($0) }
        for (earlier, later) in zip(events, events.dropFirst()) { XCTAssertLessThan(earlier, later) }
        XCTAssertNotNil(night.astronomicalNight)
    }

    func testPolarWinterAtTheNorthPoleKeepsTheSunBelowEverything() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let pole = observer(89.9, 0)
        let night = nightStarting(2026, 12, 21, observer: pole, in: zone)
        for event in orderedEvents(night) { XCTAssertNil(event) }
        // Below −18° for the whole interval: the entire interval is astronomical night.
        XCTAssertEqual(night.sunAltitudeAtMidnight, -23.54, accuracy: 0.1)
        XCTAssertEqual(night.astronomicalNight, night.interval)
    }

    func testWhiteNightsLeaveCivilTwilightOnly() throws {
        // Helsinki at midsummer: the Sun dips to −6.4°, so only civil twilight is crossed.
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Helsinki"))
        let night = nightStarting(2026, 6, 21, observer: observer(60.17, 24.94), in: zone)
        XCTAssertNotNil(night.sunset)
        XCTAssertNotNil(night.civilDusk)
        XCTAssertNil(night.nauticalDusk)
        XCTAssertNil(night.astronomicalDusk)
        XCTAssertNil(night.astronomicalDawn)
        XCTAssertNil(night.nauticalDawn)
        XCTAssertNotNil(night.civilDawn)
        XCTAssertNotNil(night.sunrise)
        XCTAssertNil(night.astronomicalNight)
        XCTAssertEqual(night.sunAltitudeAtMidnight, -6.395, accuracy: 0.05)
    }

    // MARK: astronomicalNight

    func testAstronomicalNightFollowsTheDuskAndDawnItHas() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let interval = DateInterval(start: start, duration: 86_400)
        let dusk = start.addingTimeInterval(40_000), dawn = start.addingTimeInterval(60_000)
        func night(dusk: Date?, dawn: Date?, midnightAltitude: Double) -> NightTwilight {
            NightTwilight(sunset: nil, civilDusk: nil, nauticalDusk: nil, astronomicalDusk: dusk,
                          astronomicalDawn: dawn, nauticalDawn: nil, civilDawn: nil, sunrise: nil,
                          interval: interval, solarMidnight: start.addingTimeInterval(50_000),
                          sunAltitudeAtMidnight: midnightAltitude)
        }
        let bothEvents = night(dusk: dusk, dawn: dawn, midnightAltitude: -30)
        XCTAssertEqual(bothEvents.astronomicalNight, DateInterval(start: dusk, end: dawn))
        let duskOnly = night(dusk: dusk, dawn: nil, midnightAltitude: -30)
        XCTAssertEqual(duskOnly.astronomicalNight, DateInterval(start: dusk, end: interval.end))
        let dawnOnly = night(dusk: nil, dawn: dawn, midnightAltitude: -30)
        XCTAssertEqual(dawnOnly.astronomicalNight, DateInterval(start: start, end: dawn))
        XCTAssertEqual(night(dusk: nil, dawn: nil, midnightAltitude: -30).astronomicalNight, interval)
        XCTAssertNil(night(dusk: nil, dawn: nil, midnightAltitude: -10).astronomicalNight)
    }

    // MARK: Reference fixture

    private struct FixtureCrossing: Decodable {
        let kind: String
        let unix: Double
    }

    private struct FixtureHorizon: Decodable {
        let crossings: [FixtureCrossing]
    }

    private struct FixtureSun: Decodable {
        let horizon: FixtureHorizon
        let civil: FixtureHorizon
        let nautical: FixtureHorizon
        let astronomical: FixtureHorizon
    }

    private struct FixtureObjects: Decodable {
        let sun: FixtureSun
    }

    private struct FixtureDay: Decodable {
        let site: String
        let lat: Double
        let lon: Double
        let elevationM: Double
        let date: String
        let windowStartUtc: String
        let windowEndUtc: String
        let objects: FixtureObjects
    }

    private struct FixtureFile: Decodable {
        let cases: [FixtureDay]
    }

    /// `riseset.json` windows run from local solar noon to the next; `TimeZone(secondsFromGMT:)` with the
    /// site's longitude in time gives the same local noon, so `night(startingOn:)` must reproduce the
    /// fixture's Sun events: dusk is a set, dawn a rise.
    func testNightsMatchSkyfieldForEverySiteAndDate() throws {
        let days = try EphemerisFixtureStore.load(FixtureFile.self, from: "riseset.json").cases
        XCTAssertEqual(days.count, 30)
        let formatter = ISO8601DateFormatter()
        for day in days {
            let label = "\(day.site) \(day.date)"
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: Int((day.lon * 240).rounded())))
            let start = try XCTUnwrap(formatter.date(from: day.windowStartUtc))
            let end = try XCTUnwrap(formatter.date(from: day.windowEndUtc))
            let night = TwilightCalculator.night(startingOn: start, observer: observer(day.lat, day.lon), timeZone: zone)
            XCTAssertEqual(night.interval.start.timeIntervalSince(start), 0, accuracy: 0.5, label)
            XCTAssertEqual(night.interval.end.timeIntervalSince(end), 0, accuracy: 0.5, label)

            let lists: [(String, FixtureHorizon, Date?, Date?)] = [
                ("horizon", day.objects.sun.horizon, night.sunset, night.sunrise),
                ("civil", day.objects.sun.civil, night.civilDusk, night.civilDawn),
                ("nautical", day.objects.sun.nautical, night.nauticalDusk, night.nauticalDawn),
                ("astronomical", day.objects.sun.astronomical, night.astronomicalDusk, night.astronomicalDawn),
            ]
            for (name, list, dusk, dawn) in lists {
                let expectedDusk = list.crossings.first { $0.kind == "set" }
                let expectedDawn = list.crossings.first { $0.kind == "rise" }
                XCTAssertEqual(dusk == nil, expectedDusk == nil, "\(label) \(name) dusk present")
                XCTAssertEqual(dawn == nil, expectedDawn == nil, "\(label) \(name) dawn present")
                if let found = dusk, let reference = expectedDusk {
                    XCTAssertEqual(found.timeIntervalSince1970, reference.unix, accuracy: 1.5, "\(label) \(name) dusk")
                }
                if let found = dawn, let reference = expectedDawn {
                    XCTAssertEqual(found.timeIntervalSince1970, reference.unix, accuracy: 1.5, "\(label) \(name) dawn")
                }
            }
        }
    }

    // MARK: Consistency with the rise/set search

    func testNightAgreesWithTheGenericCrossingSearch() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let greenwich = observer(51.48, 0)
        let night = nightStarting(2026, 9, 22, observer: greenwich, in: zone)
        let horizon = RiseSetCalculator.crossings(of: .sun, observer: greenwich, within: night.interval)
        XCTAssertEqual(horizon.map(\.kind), [.setting, .rising])
        XCTAssertEqual(night.sunset, horizon[0].time)
        XCTAssertEqual(night.sunrise, horizon[1].time)
        // Twilight 18° below the horizon: the Sun is 18° down 1.5–2 hours after sunset at this latitude and date.
        let darkness = try XCTUnwrap(night.astronomicalDusk).timeIntervalSince(try XCTUnwrap(night.sunset)) / 3600
        XCTAssertTrue((1.5...2.2).contains(darkness), "dusk after \(darkness) h")
    }
}

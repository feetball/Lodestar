import XCTest
@testable import LodestarKit

/// Observing sites and calendar helpers shared by the Planning tests.
enum PlanningTestSupport {
    struct Site {
        let name: String
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let timeZoneIdentifier: String

        init(name: String, latitude: Double, longitude: Double, elevation: Double = 0,
             timeZoneIdentifier: String = "UTC") {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.elevation = elevation
            self.timeZoneIdentifier = timeZoneIdentifier
        }

        var observer: Observer {
            Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation))
        }

        func timeZone() throws -> TimeZone {
            try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier), timeZoneIdentifier)
        }
    }

    static let boulder = Site(name: "Boulder", latitude: 40.0, longitude: -105.27, elevation: 1650,
                              timeZoneIdentifier: "America/Denver")
    static let sydney = Site(name: "Sydney", latitude: -33.87, longitude: 151.21, elevation: 0,
                             timeZoneIdentifier: "Australia/Sydney")
    static let tromso = Site(name: "Tromsø", latitude: 69.65, longitude: 18.96, elevation: 0,
                             timeZoneIdentifier: "Europe/Oslo")
    static let london = Site(name: "London", latitude: 51.48, longitude: 0, elevation: 0,
                             timeZoneIdentifier: "Europe/London")
    static let quito = Site(name: "Quito", latitude: 0, longitude: -78.5, elevation: 2800,
                            timeZoneIdentifier: "America/Guayaquil")
    static let paranal = Site(name: "Paranal", latitude: -24.63, longitude: -70.40, elevation: 2635,
                              timeZoneIdentifier: "America/Santiago")

    /// Noon on a local calendar day.
    static func localNoon(_ year: Int, _ month: Int, _ day: Int, in zone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// The local calendar day whose noon-to-noon night contains `instant`, as that day's noon.
    static func startOfNight(containing instant: Date, in zone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: instant))
        return instant >= noon ? noon : try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: noon))
    }

    /// The summary of the night starting on a local calendar day.
    static func summary(_ site: Site, _ year: Int, _ month: Int, _ day: Int) throws -> NightSummary {
        let zone = try site.timeZone()
        return NightPlanner.summary(nightStartingOn: try localNoon(year, month, day, in: zone),
                                    observer: site.observer, timeZone: zone)
    }

    static func contains(_ intervals: [DateInterval], _ date: Date) -> Bool {
        intervals.contains { $0.start <= date && date < $0.end }
    }

    /// The parts of `window` in which `altitude` (degrees) is at or above `threshold`, found with
    /// `RiseSetCalculator`'s root finder: an independent route to what the planner derives from sampled sines.
    static func intervals(above threshold: Double, within window: DateInterval,
                          altitude: (Date) -> Double) -> [DateInterval] {
        var start: Date? = altitude(window.start) >= threshold ? window.start : nil
        var result = [DateInterval]()
        for crossing in RiseSetCalculator.crossings(of: altitude, threshold: threshold, within: window) {
            switch crossing.kind {
            case .rising:
                start = crossing.time
            case .setting:
                if let opened = start { result.append(DateInterval(start: opened, end: crossing.time)) }
                start = nil
            }
        }
        if let opened = start { result.append(DateInterval(start: opened, end: window.end)) }
        return result
    }

    /// Fails unless both lists hold the same number of intervals whose ends agree to `accuracy` seconds.
    static func assertIntervals(_ actual: [DateInterval], _ expected: [DateInterval], accuracy: TimeInterval,
                                _ message: @autoclosure () -> String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(message()): \(actual) against \(expected)", file: file, line: line)
        for (found, wanted) in zip(actual, expected) {
            XCTAssertEqual(found.start.timeIntervalSince(wanted.start), 0, accuracy: accuracy, "\(message()): start",
                           file: file, line: line)
            XCTAssertEqual(found.end.timeIntervalSince(wanted.end), 0, accuracy: accuracy, "\(message()): end",
                           file: file, line: line)
        }
    }

    /// The Sun's geometric altitude, from a frame built for the instant.
    static func sunAltitude(_ date: Date, _ observer: Observer) -> Double {
        SkyFrame(date: date, observer: observer).horizontal(of: .sun, refraction: false).altitude
    }

    /// A reproducible source of random numbers (SplitMix64).
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

final class PlanningNightSummaryTests: XCTestCase {
    private typealias Support = PlanningTestSupport
    private typealias Sets = NightPlanner.IntervalSet

    private let boulder = Support.boulder

    // MARK: Structure

    func testSummaryCarriesTheTwilightOfTheNight() throws {
        let zone = try boulder.timeZone()
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let twilight = TwilightCalculator.night(startingOn: try Support.localNoon(2026, 10, 25, in: zone),
                                                observer: boulder.observer, timeZone: zone)
        XCTAssertEqual(summary.twilight, twilight)
        XCTAssertEqual(summary.night, twilight.interval)
        XCTAssertEqual(summary.observer, boulder.observer)
        XCTAssertEqual(summary.night.duration, 24 * 3_600, accuracy: 0.001)
        XCTAssertEqual(summary.astronomicalDarknessIntervals, [try XCTUnwrap(twilight.astronomicalNight)])
        XCTAssertEqual(summary.referenceDate, twilight.astronomicalDusk)
        XCTAssertTrue(summary.hasAstronomicalDarkness)
        // Boulder, 25 October: dusk 19:38 and dawn 05:53 MDT, a little over ten hours of darkness.
        XCTAssertEqual(summary.astronomicalDarkHours, 10.25, accuracy: 0.05)
    }

    func testSummaryIsDeterministic() throws {
        XCTAssertEqual(try Support.summary(boulder, 2026, 6, 21), try Support.summary(boulder, 2026, 6, 21))
    }

    func testNightLengthFollowsDaylightSavingChanges() throws {
        let newYork = Support.Site(name: "New York", latitude: 40.71, longitude: -74.0,
                                   timeZoneIdentifier: "America/New_York")
        let zone = try newYork.timeZone()
        for (month, day, hours) in [(3, 7, 23.0), (10, 31, 25.0), (5, 5, 24.0)] {
            let summary = NightPlanner.summary(nightStartingOn: try Support.localNoon(2026, month, day, in: zone),
                                               observer: newYork.observer, timeZone: zone)
            XCTAssertEqual(summary.night.duration / 3_600, hours, accuracy: 1e-6, "2026-\(month)-\(day)")
        }
    }

    // MARK: Darkness

    func testFullMoonNightHasNoMoonFreeDarkness() throws {
        // Full moon at 04:11 UTC on 26 October 2026: the Moon rises at 17:35 and sets at 08:06 the next
        // morning, covering the whole of the astronomical night (19:38 to 05:53).
        let summary = try Support.summary(boulder, 2026, 10, 25)
        XCTAssertEqual(summary.moon.phase.name, .fullMoon)
        XCTAssertGreaterThan(summary.moon.illuminatedFraction, 0.99)
        XCTAssertEqual(summary.moon.upIntervals.count, 1)
        XCTAssertTrue(summary.darknessIntervals.isEmpty)
        XCTAssertEqual(summary.moonFreeDarkHours, 0)
        let astronomical = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let moonUp = try XCTUnwrap(summary.moon.upIntervals.first)
        XCTAssertLessThanOrEqual(moonUp.start, astronomical.start)
        XCTAssertGreaterThanOrEqual(moonUp.end, astronomical.end)
        XCTAssertEqual(summary.moon.riseTransitSet.rise, moonUp.start)
        XCTAssertEqual(summary.moon.riseTransitSet.set, moonUp.end)
    }

    func testNewMoonNightIsAsDarkAsTheAstronomicalNight() throws {
        // New moon at 15:50 UTC on 10 October 2026: the Moon sets with the Sun and is gone all night.
        let summary = try Support.summary(boulder, 2026, 10, 10)
        XCTAssertEqual(summary.moon.phase.name, .newMoon)
        XCTAssertLessThan(summary.moon.illuminatedFraction, 0.02)
        XCTAssertEqual(summary.darknessIntervals, summary.astronomicalDarknessIntervals)
        XCTAssertEqual(summary.moonFreeDarkHours, summary.astronomicalDarkHours, accuracy: 1e-9)
        XCTAssertGreaterThan(summary.moonFreeDarkHours, 9.5)
        // The Moon is above the horizon only before dusk and after dawn.
        let dusk = try XCTUnwrap(summary.twilight.astronomicalDusk)
        let dawn = try XCTUnwrap(summary.twilight.astronomicalDawn)
        for interval in summary.moon.upIntervals {
            XCTAssertTrue(interval.end <= dusk || interval.start >= dawn, "\(interval)")
        }
    }

    func testMoonSetBeginsTheMoonFreeHoursAndDawnEndsThem() throws {
        // 21 June 2026, a day after first quarter: the Moon sets at 00:58 MDT, 2.5 hours before dawn.
        let summary = try Support.summary(boulder, 2026, 6, 21)
        let dawn = try XCTUnwrap(summary.twilight.astronomicalDawn)
        XCTAssertEqual(summary.darknessIntervals.count, 1)
        let dark = try XCTUnwrap(summary.darknessIntervals.first)
        XCTAssertEqual(dark.start, summary.moon.riseTransitSet.set)
        XCTAssertEqual(dark.end, dawn)
        XCTAssertEqual(summary.moonFreeDarkHours, 2.52, accuracy: 0.02)
        XCTAssertEqual(summary.astronomicalDarkHours, 4.87, accuracy: 0.02)
        XCTAssertEqual(summary.moon.phase.name, .firstQuarter)
        XCTAssertEqual(summary.moon.illuminatedFraction, 0.53, accuracy: 0.03)
    }

    func testMoonRiseEndsTheMoonFreeHours() throws {
        // 7 July 2026, last quarter: the Moon rises after midnight, so the evening hours are dark.
        let summary = try Support.summary(boulder, 2026, 7, 7)
        let dusk = try XCTUnwrap(summary.twilight.astronomicalDusk)
        let dark = try XCTUnwrap(summary.darknessIntervals.first)
        XCTAssertEqual(summary.darknessIntervals.count, 1)
        XCTAssertEqual(dark.start, dusk)
        XCTAssertEqual(dark.end, summary.moon.riseTransitSet.rise)
        XCTAssertGreaterThan(summary.moonFreeDarkHours, 1)
        XCTAssertLessThan(summary.moonFreeDarkHours, summary.astronomicalDarkHours)
    }

    /// Darkness is exactly "Sun below −18° and Moon's upper limb below the horizon", checked at random
    /// instants against fresh `SkyFrame` calculations.
    func testDarknessMatchesDirectSunAndMoonAltitudes() throws {
        let cases: [(Support.Site, Int, Int, Int)] = [
            (boulder, 2026, 10, 25), (boulder, 2026, 6, 21), (boulder, 2026, 7, 7), (Support.sydney, 2026, 6, 21),
            (Support.sydney, 2026, 12, 21), (Support.london, 2026, 9, 1), (Support.quito, 2026, 3, 20),
            (Support.paranal, 2026, 8, 12), (Support.tromso, 2026, 12, 21),
        ]
        var generator = Support.SeededGenerator(seed: 20_261_017)
        for (site, year, month, day) in cases {
            let summary = try Support.summary(site, year, month, day)
            let boundaries = (summary.astronomicalDarknessIntervals + summary.moon.upIntervals + summary.darknessIntervals)
                .flatMap { [$0.start, $0.end] }
            var checked = 0
            while checked < 150 {
                let date = summary.night.start.addingTimeInterval(.random(in: 0..<summary.night.duration, using: &generator))
                guard boundaries.allSatisfy({ abs($0.timeIntervalSince(date)) > 30 }) else { continue }
                checked += 1
                let frame = SkyFrame(date: date, observer: site.observer)
                let sunDark = frame.horizontal(of: .sun, refraction: false).altitude < TwilightCalculator.astronomicalAltitude
                let moon = frame.state(of: .moon)
                let semiDiameter = AstroMath.asinDeg(SolarSystemBody.moon.meanRadiusKilometers / moon.distanceKilometers)
                let moonUp = frame.horizontal(of: .moon, refraction: false).altitude + semiDiameter
                    > RiseSetCalculator.standardHorizonAltitude
                let label = "\(site.name) \(year)-\(month)-\(day) at \(date)"
                XCTAssertEqual(Support.contains(summary.astronomicalDarknessIntervals, date), sunDark, label)
                XCTAssertEqual(Support.contains(summary.moon.upIntervals, date), moonUp, label)
                XCTAssertEqual(Support.contains(summary.darknessIntervals, date), sunDark && !moonUp, label)
            }
        }
    }

    func testDarknessNestsInsideAstronomicalNightForEverySiteAndSeason() throws {
        let sites = [boulder, Support.sydney, Support.london, Support.quito, Support.paranal, Support.tromso]
        for site in sites {
            for (month, day) in [(1, 15), (3, 20), (6, 21), (9, 22), (12, 21)] {
                let summary = try Support.summary(site, 2026, month, day)
                let label = "\(site.name) 2026-\(month)-\(day)"
                let astronomical = summary.twilight.astronomicalNight.map { [$0] } ?? []
                XCTAssertEqual(summary.astronomicalDarknessIntervals, astronomical, label)
                XCTAssertEqual(Sets.intersection(summary.darknessIntervals, astronomical), summary.darknessIntervals, label)
                XCTAssertTrue(Sets.intersection(summary.darknessIntervals, summary.moon.upIntervals).isEmpty, label)
                // Dark time plus moonlit astronomical night is the whole astronomical night.
                let moonlit = Sets.intersection(astronomical, summary.moon.upIntervals)
                XCTAssertEqual(Sets.totalDuration(of: summary.darknessIntervals) + Sets.totalDuration(of: moonlit),
                               Sets.totalDuration(of: astronomical), accuracy: 1e-6, label)
                XCTAssertLessThanOrEqual(summary.moonFreeDarkHours, summary.astronomicalDarkHours + 1e-9, label)
                XCTAssertEqual(summary.hasAstronomicalDarkness, !astronomical.isEmpty, label)
                XCTAssertEqual(summary.darkness(.astronomical), summary.astronomicalDarknessIntervals)
                XCTAssertEqual(summary.darkness(.moonFree), summary.darknessIntervals)
            }
        }
    }

    // MARK: High latitudes

    func testPolarSummerHasNoAstronomicalDarkness() throws {
        // Tromsø (69.65° N) on 21 June: the Sun never sets, let alone reaches −18°.
        let summary = try Support.summary(Support.tromso, 2026, 6, 21)
        XCTAssertFalse(summary.hasAstronomicalDarkness)
        XCTAssertTrue(summary.astronomicalDarknessIntervals.isEmpty)
        XCTAssertTrue(summary.darknessIntervals.isEmpty)
        XCTAssertEqual(summary.astronomicalDarkHours, 0)
        XCTAssertEqual(summary.moonFreeDarkHours, 0)
        XCTAssertNil(summary.twilight.sunset)
        XCTAssertEqual(summary.referenceDate, summary.twilight.solarMidnight)
        // Everything that depends on darkness is empty, while the events still come out.
        let core = summary.milkyWayCore
        XCTAssertTrue(core.visibleIntervals.isEmpty)
        XCTAssertTrue(core.moonFreeVisibleIntervals.isEmpty)
        XCTAssertNil(core.bestTime)
        XCTAssertNil(core.maxAltitude)
        XCTAssertNil(core.bestAzimuth)
        XCTAssertEqual(core.riseTransitSet.circumstance, .alwaysDown, "Sagittarius A* never rises at 69.65° N")
        XCTAssertEqual(summary.planets.count, 7)
        for planet in summary.planets {
            XCTAssertNil(planet.maxAltitudeDuringDarkness, planet.body.displayName)
            XCTAssertFalse(planet.visibleDuringDarkness, planet.body.displayName)
            XCTAssertNotNil(planet.magnitude, planet.body.displayName)
        }
        XCTAssertNotNil(summary.moon.riseTransitSet.transit)
    }

    func testPolarWinterNightsAreDarkButMoonlitWhenTheMoonStaysUp() throws {
        // Tromsø on 21 December 2026 (a day before full moon): astronomical darkness from 16:56 to 06:29
        // and a Moon that never sets.
        let summary = try Support.summary(Support.tromso, 2026, 12, 21)
        XCTAssertTrue(summary.hasAstronomicalDarkness)
        XCTAssertEqual(summary.astronomicalDarkHours, 13.55, accuracy: 0.05)
        XCTAssertEqual(summary.moon.riseTransitSet.circumstance, .alwaysUp)
        XCTAssertEqual(summary.moon.upIntervals, [summary.night])
        XCTAssertTrue(summary.darknessIntervals.isEmpty)
        XCTAssertEqual(summary.moonFreeDarkHours, 0)
    }

    func testPolarNightFillsTheWholeWindowWithDarkness() throws {
        let pole = Support.Site(name: "Pole", latitude: 89.9, longitude: 0)
        let zone = try pole.timeZone()
        let summary = NightPlanner.summary(nightStartingOn: try Support.localNoon(2026, 12, 21, in: zone),
                                           observer: pole.observer, timeZone: zone)
        XCTAssertEqual(summary.astronomicalDarknessIntervals, [summary.night])
        XCTAssertEqual(summary.astronomicalDarkHours, 24, accuracy: 1e-6)
        XCTAssertEqual(summary.referenceDate, summary.twilight.solarMidnight)
        XCTAssertTrue(summary.planets.contains { $0.maxAltitudeDuringDarkness != nil })
    }

    // MARK: Twilight

    func testTwilightEventsRunInOrderAtTheSunsAltitudes() throws {
        let sites = [boulder, Support.sydney, Support.quito, Support.paranal]
        for site in sites {
            for (month, day) in [(1, 15), (3, 20), (6, 21), (9, 22), (12, 21)] {
                let label = "\(site.name) 2026-\(month)-\(day)"
                let summary = try Support.summary(site, 2026, month, day)
                let twilight = summary.twilight
                let events = [twilight.sunset, twilight.civilDusk, twilight.nauticalDusk, twilight.astronomicalDusk,
                              twilight.astronomicalDawn, twilight.nauticalDawn, twilight.civilDawn, twilight.sunrise]
                let dates = try events.map { try XCTUnwrap($0, label) }
                XCTAssertEqual(dates, dates.sorted(), label)
                XCTAssertTrue(dates.allSatisfy { summary.night.contains($0) }, label)
                for (date, altitude) in zip(dates, [-0.8333, -6, -12, -18, -18, -12, -6, -0.8333]) {
                    XCTAssertEqual(Support.sunAltitude(date, site.observer), altitude, accuracy: 0.01, label)
                }
                XCTAssertEqual(summary.astronomicalDarknessIntervals,
                               [DateInterval(start: dates[3], end: dates[4])], label)
                // Between the edges the Sun is below −18°, outside them above it.
                let middle = dates[3].addingTimeInterval(dates[3].distance(to: dates[4]) / 2)
                XCTAssertLessThan(Support.sunAltitude(middle, site.observer), -18, label)
                XCTAssertGreaterThan(Support.sunAltitude(summary.night.start, site.observer), -18, label)
                XCTAssertGreaterThan(Support.sunAltitude(summary.night.end, site.observer), -18, label)
            }
        }
    }

    func testLondonInMidsummerHasNauticalButNoAstronomicalDarkness() throws {
        let summary = try Support.summary(Support.london, 2026, 6, 21)
        XCTAssertFalse(summary.hasAstronomicalDarkness)
        XCTAssertNil(summary.twilight.astronomicalDusk)
        XCTAssertNil(summary.twilight.astronomicalDawn)
        XCTAssertNotNil(summary.twilight.nauticalDusk, "the Sun reaches −15° at midnight, past the nautical −12°")
        XCTAssertTrue(summary.darknessIntervals.isEmpty)
        XCTAssertEqual(summary.referenceDate, summary.twilight.solarMidnight)
        XCTAssertEqual(summary.moon.phase.date, summary.twilight.solarMidnight)
        XCTAssertEqual(summary.astronomicalDarkHours, 0)
    }

    // MARK: The Moon

    func testMoonSummaryIsWhatTheMoonCalculatorsSayForTheNight() throws {
        for (site, month, day) in [(boulder, 6, 21), (Support.sydney, 12, 21), (Support.tromso, 12, 21)] {
            let summary = try Support.summary(site, 2026, month, day)
            let label = "\(site.name) 2026-\(month)-\(day)"
            XCTAssertEqual(summary.moon.phase, MoonPhaseCalculator.info(at: summary.referenceDate), label)
            XCTAssertEqual(summary.moon.phase.date, summary.referenceDate, label)
            XCTAssertEqual(summary.moon.illuminatedFraction, summary.moon.phase.illuminatedFraction, label)
            XCTAssertEqual(summary.moon.riseTransitSet,
                           RiseSetCalculator.riseTransitSet(for: .moon, observer: site.observer, within: summary.night), label)
            // The Moon is above the horizon exactly between its rises and sets.
            let crossings = RiseSetCalculator.crossings(of: .moon, observer: site.observer, within: summary.night)
            for interval in summary.moon.upIntervals {
                XCTAssertTrue(interval.start == summary.night.start
                              || crossings.contains { $0.time == interval.start && $0.kind == .rising }, label)
                XCTAssertTrue(interval.end == summary.night.end
                              || crossings.contains { $0.time == interval.end && $0.kind == .setting }, label)
            }
        }
    }

    /// At every New and Full Moon of 2026 the night that contains it is either all moonlit or all moon-free,
    /// as seen from places where the sky gets dark every night of the year.
    func testEveryNewAndFullMoonOf2026() throws {
        let start = Date(timeIntervalSince1970: 1_767_225_600)          // 2026-01-01T00:00:00Z
        let end = Date(timeIntervalSince1970: 1_798_761_600)            // 2027-01-01T00:00:00Z
        let syzygies = MoonPhaseCalculator.nextPhases(after: start, count: 60)
            .filter { $0.date < end && ($0.kind == .newMoon || $0.kind == .fullMoon) }
        XCTAssertEqual(syzygies.filter { $0.kind == .newMoon }.count, 12)
        XCTAssertEqual(syzygies.filter { $0.kind == .fullMoon }.count, 13, "2026 has Full Moons on 1 and 31 May")
        for site in [boulder, Support.sydney] {
            let zone = try site.timeZone()
            for (kind, date) in syzygies {
                let summary = NightPlanner.summary(nightStartingOn: try Support.startOfNight(containing: date, in: zone),
                                                   observer: site.observer, timeZone: zone)
                let label = "\(site.name) \(kind) \(date)"
                XCTAssertTrue(summary.night.contains(date), label)
                XCTAssertTrue(summary.hasAstronomicalDarkness, label)
                if kind == .fullMoon {
                    XCTAssertEqual(summary.moon.phase.name, .fullMoon, label)
                    XCTAssertGreaterThan(summary.moon.illuminatedFraction, 0.99, label)
                    XCTAssertTrue(summary.darknessIntervals.isEmpty, label)
                    XCTAssertEqual(summary.moonFreeDarkHours, 0, label)
                } else {
                    XCTAssertEqual(summary.moon.phase.name, .newMoon, label)
                    XCTAssertLessThan(summary.moon.illuminatedFraction, 0.01, label)
                    XCTAssertEqual(summary.darknessIntervals, summary.astronomicalDarknessIntervals, label)
                    XCTAssertEqual(summary.moonFreeDarkHours, summary.astronomicalDarkHours, accuracy: 1e-9, label)
                }
            }
        }
    }

    // MARK: Reference data

    /// Sun and Moon events for Boulder from the U.S. Naval Observatory's Astronomical Applications API
    /// (`rstt/oneday` for 2026-10-17, 40.00° N 105.27° W, UT), which gives times to the minute. The service
    /// shares no code or data with LodestarKit.
    func testSunAndMoonEventsAgreeWithTheNavalObservatory() throws {
        let midnightUT = Date(timeIntervalSince1970: 1_792_195_200)          // 2026-10-17T00:00:00Z
        func universal(_ hour: Int, _ minute: Int) -> Date { midnightUT.addingTimeInterval(Double(hour * 3_600 + minute * 60)) }

        // The night starting on 16 October holds the evening of the 16th (17 October in UT) and the morning after.
        let evening = try Support.summary(boulder, 2026, 10, 16)
        let twilight = evening.twilight
        XCTAssertEqual(try XCTUnwrap(twilight.sunset).timeIntervalSince(universal(0, 20)), 0, accuracy: 60)
        XCTAssertEqual(try XCTUnwrap(twilight.civilDusk).timeIntervalSince(universal(0, 47)), 0, accuracy: 60)
        XCTAssertEqual(try XCTUnwrap(twilight.civilDawn).timeIntervalSince(universal(12, 47)), 0, accuracy: 60)
        XCTAssertEqual(try XCTUnwrap(twilight.sunrise).timeIntervalSince(universal(13, 14)), 0, accuracy: 60)
        XCTAssertEqual(try XCTUnwrap(evening.moon.riseTransitSet.set).timeIntervalSince(universal(4, 9)), 0, accuracy: 60)
        XCTAssertEqual(evening.moon.phase.name, .waxingCrescent, "USNO: Waxing Crescent, First Quarter on the 18th at 16:12 UT")

        // The Moon rises at 20:01 UT, in the afternoon of the 17th, so in the night starting on that date.
        let following = try Support.summary(boulder, 2026, 10, 17)
        XCTAssertEqual(try XCTUnwrap(following.moon.riseTransitSet.rise).timeIntervalSince(universal(20, 1)), 0, accuracy: 60)
    }

    // MARK: Public initializers

    func testPublicInitializersKeepTheirValues() throws {
        let summary = try Support.summary(boulder, 2026, 12, 14)
        let moon = MoonSummary(phase: summary.moon.phase, riseTransitSet: summary.moon.riseTransitSet,
                               upIntervals: summary.moon.upIntervals)
        let core = summary.milkyWayCore
        let rebuiltCore = MilkyWayCoreVisibility(
            riseTransitSet: core.riseTransitSet, visibleIntervals: core.visibleIntervals,
            moonFreeVisibleIntervals: core.moonFreeVisibleIntervals, bestTime: core.bestTime,
            maxAltitude: core.maxAltitude, bestAzimuth: core.bestAzimuth)
        let planets = summary.planets.map {
            PlanetVisibility(body: $0.body, riseTransitSet: $0.riseTransitSet, visibleIntervals: $0.visibleIntervals,
                             maxAltitudeDuringDarkness: $0.maxAltitudeDuringDarkness, magnitude: $0.magnitude)
        }
        let rebuilt = NightSummary(
            observer: summary.observer, night: summary.night, twilight: summary.twilight,
            referenceDate: summary.referenceDate, moon: moon,
            astronomicalDarknessIntervals: summary.astronomicalDarknessIntervals,
            darknessIntervals: summary.darknessIntervals, milkyWayCore: rebuiltCore, planets: planets)
        XCTAssertEqual(rebuilt, summary)
        XCTAssertEqual(moon.illuminatedFraction, summary.moon.phase.illuminatedFraction)
        XCTAssertEqual(planets.map(\.visibleDuringDarkness), summary.planets.map(\.visibleDuringDarkness))

        let visibility = NightPlanner.visibility(of: .saturn, during: summary)
        let rebuiltVisibility = TargetVisibility(
            riseTransitSet: visibility.riseTransitSet, minimumAltitude: visibility.minimumAltitude,
            maxAltitudeDuringDarkness: visibility.maxAltitudeDuringDarkness, bestTime: visibility.bestTime,
            intervalsAboveMinimum: visibility.intervalsAboveMinimum)
        XCTAssertEqual(rebuiltVisibility, visibility)

        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let sample = AltitudeSample(date: instant, altitude: 12.5, azimuth: 270)
        XCTAssertEqual(sample.date, instant)
        XCTAssertEqual(sample.altitude, 12.5)
        XCTAssertEqual(sample.azimuth, 270)
        XCTAssertEqual(sample, AltitudeSample(date: instant, altitude: 12.5, azimuth: 270))
        XCTAssertNotEqual(sample, AltitudeSample(date: instant, altitude: 12.5, azimuth: 271))
    }

    // MARK: Odd input

    func testAnyInstantOfTheLocalDayGivesTheSameNight() throws {
        let zone = try boulder.timeZone()
        let noon = try Support.localNoon(2026, 10, 25, in: zone)
        let reference = NightPlanner.summary(nightStartingOn: noon, observer: boulder.observer, timeZone: zone)
        for hours in [-11.5, -6.0, 0.0, 6.0, 11.5] {
            let summary = NightPlanner.summary(nightStartingOn: noon.addingTimeInterval(hours * 3_600),
                                               observer: boulder.observer, timeZone: zone)
            XCTAssertEqual(summary, reference, "\(hours) h from noon")
        }
    }

    func testTheTimeZoneDecidesWhichNightIsMeant() throws {
        let instant = try Support.localNoon(2026, 10, 25, in: try XCTUnwrap(TimeZone(identifier: "UTC")))
        let utc = NightPlanner.summary(nightStartingOn: instant, observer: boulder.observer,
                                       timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
        let denver = NightPlanner.summary(nightStartingOn: instant, observer: boulder.observer, timeZone: try boulder.timeZone())
        XCTAssertEqual(utc.night.start, instant)
        XCTAssertNotEqual(utc.night, denver.night)
        XCTAssertEqual(denver.night.duration, 24 * 3_600, accuracy: 1e-6)
    }

    func testPlacesOnThePolesAndNonFiniteDatesStillGetASummary() throws {
        for latitude in [90.0, -90.0] {
            let pole = Support.Site(name: "pole \(latitude)", latitude: latitude, longitude: 0)
            let summary = try Support.summary(pole, 2026, 12, 21)
            XCTAssertEqual(summary.night.duration, 24 * 3_600, accuracy: 1e-6)
            XCTAssertEqual(summary.planets.count, 7)
            XCTAssertTrue(summary.astronomicalDarkHours == 0 || summary.astronomicalDarkHours == 24, "all or nothing at a pole")
            XCTAssertEqual(summary.hasAstronomicalDarkness, latitude > 0)
            XCTAssertTrue(summary.milkyWayCore.visibleIntervals.isEmpty || latitude < 0)
        }
        let broken = NightPlanner.summary(nightStartingOn: Date(timeIntervalSinceReferenceDate: .nan),
                                          observer: boulder.observer, timeZone: try boulder.timeZone())
        XCTAssertEqual(broken.night.duration, 24 * 3_600, accuracy: 3_601)
        let far = NightPlanner.summary(nightStartingOn: .distantFuture, observer: boulder.observer, timeZone: try boulder.timeZone())
        XCTAssertEqual(far.night.duration, 24 * 3_600, accuracy: 3_601)
    }

    // MARK: Moon intervals from horizon crossings

    func testUpIntervalsFollowTheHorizonCrossings() {
        let window = DateInterval(start: Date(timeIntervalSinceReferenceDate: 0), duration: 24 * 3_600)
        func at(_ hours: Double) -> Date { window.start.addingTimeInterval(hours * 3_600) }
        func span(_ from: Double, _ to: Double) -> DateInterval { DateInterval(start: at(from), end: at(to)) }
        func rise(_ hours: Double) -> AltitudeCrossing { AltitudeCrossing(time: at(hours), kind: .rising) }
        func set(_ hours: Double) -> AltitudeCrossing { AltitudeCrossing(time: at(hours), kind: .setting) }
        let up = NightPlanner.upIntervals

        XCTAssertEqual(up([], .alwaysUp, window), [window])
        XCTAssertEqual(up([], .alwaysDown, window), [])
        XCTAssertEqual(up([rise(5), set(9)], .normal, window), [span(5, 9)])
        XCTAssertEqual(up([set(3), rise(10), set(20)], .normal, window), [span(0, 3), span(10, 20)])
        XCTAssertEqual(up([rise(15)], .normal, window), [span(15, 24)])
        XCTAssertEqual(up([set(7)], .normal, window), [span(0, 7)])
        XCTAssertEqual(up([rise(2), set(4), rise(10), set(12)], .normal, window), [span(2, 4), span(10, 12)])
    }
}

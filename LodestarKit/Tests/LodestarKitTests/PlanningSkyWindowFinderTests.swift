import XCTest
@testable import LodestarKit

/// "When does the Milky Way core, the Moon or a star stand over that ridge?": the sky-window search against fresh
/// sky frames, a brute-force scan, the root finder and published geometry.
final class PlanningSkyWindowFinderTests: XCTestCase {
    private typealias Support = PlanningTestSupport

    private let boulder = Support.boulder
    private let tromso = Support.tromso

    /// 47° N in the Alps, where the Milky Way core never gets above 14°.
    private let innsbruck = Support.Site(name: "Innsbruck", latitude: 47.0, longitude: 11.4, elevation: 600,
                                         timeZoneIdentifier: "Europe/Vienna")

    private let coreTarget = SkyWindowTarget.milkyWayCore

    /// Seconds allowed for a year of searching: the documented few hundred milliseconds for a release build; an
    /// unoptimised debug build is an order of magnitude slower, so its bound only catches a calculation that has
    /// gone badly wrong.
    private static let yearLimit: Double = {
        #if DEBUG
        return 120
        #else
        return 10
        #endif
    }()

    private func window(_ azimuth: Double, _ tolerance: Double, _ minimum: Double, _ maximum: Double,
                        line: UInt = #line) throws -> SkyWindow {
        try XCTUnwrap(SkyWindow.around(azimuth: azimuth, tolerance: tolerance, minimumAltitude: minimum,
                                       maximumAltitude: maximum), line: line)
    }

    private func noon(_ site: Support.Site, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try Support.localNoon(year, month, day, in: try site.timeZone())
    }

    private func matches(_ site: Support.Site, _ target: SkyWindowTarget, _ window: SkyWindow, from: Date, to: Date,
                         horizon: HorizonProfile? = nil, darkness: SkyWindowDarkness = .astronomical,
                         moon: SkyWindowMoonRule = .unrestricted) throws -> [SkyWindowMatch] {
        try SkyWindowFinder.matches(target: target, window: window, observer: site.observer, horizon: horizon,
                                    from: from, to: to, darkness: darkness, moon: moon, timeZone: try site.timeZone())
    }

    private func apparent(_ frame: SkyFrame, _ place: EquatorialCoordinate) -> HorizontalCoordinate {
        frame.horizontal(j2000: place, properMotion: nil, refraction: true)
    }

    private func sunAltitude(_ date: Date, _ observer: Observer) -> Double { Support.sunAltitude(date, observer) }

    // MARK: Windows

    func testAWindowNeedsFiniteOrderedAltitudes() throws {
        let range = AzimuthRange(start: 170, length: 20)
        let window = try XCTUnwrap(SkyWindow(azimuth: range, minimumAltitude: 5, maximumAltitude: 25))
        XCTAssertEqual(window.azimuth, range)
        XCTAssertEqual(window.minimumAltitude, 5)
        XCTAssertEqual(window.maximumAltitude, 25)
        XCTAssertNotNil(SkyWindow(azimuth: range, minimumAltitude: -90, maximumAltitude: 90))
        XCTAssertNotNil(SkyWindow(azimuth: range, minimumAltitude: 12, maximumAltitude: 12))
        XCTAssertNil(SkyWindow(azimuth: range, minimumAltitude: 25, maximumAltitude: 5))
        XCTAssertNil(SkyWindow(azimuth: range, minimumAltitude: -90.5, maximumAltitude: 5))
        XCTAssertNil(SkyWindow(azimuth: range, minimumAltitude: 5, maximumAltitude: 90.5))
        XCTAssertNil(SkyWindow(azimuth: range, minimumAltitude: .nan, maximumAltitude: 5))
        XCTAssertNil(SkyWindow(azimuth: range, minimumAltitude: 5, maximumAltitude: .infinity))
    }

    func testAWindowAroundAnAzimuthRunsThroughNorth() throws {
        let window = try window(359, 3, 0, 10)
        XCTAssertEqual(window.azimuth.start, 356, accuracy: 1e-9)
        XCTAssertEqual(window.azimuth.length, 6, accuracy: 1e-9)
        XCTAssertTrue(window.azimuth.contains(0))
        XCTAssertTrue(window.azimuth.contains(2))
        XCTAssertFalse(window.azimuth.contains(3.5))
        XCTAssertEqual(try self.window(10, 180, 0, 10).azimuth.length, 360)
        XCTAssertNil(SkyWindow.around(azimuth: 10, tolerance: -1, minimumAltitude: 0, maximumAltitude: 10))
        XCTAssertNil(SkyWindow.around(azimuth: 10, tolerance: 181, minimumAltitude: 0, maximumAltitude: 10))
        XCTAssertNil(SkyWindow.around(azimuth: .nan, tolerance: 3, minimumAltitude: 0, maximumAltitude: 10))
        XCTAssertNil(SkyWindow.around(azimuth: 10, tolerance: .nan, minimumAltitude: 0, maximumAltitude: 10))
    }

    func testASkylinePointWindowSitsJustAboveTheSkyline() throws {
        let skyline = HorizonTestSupport.truthProfile
        let ridge = try XCTUnwrap(SkyWindow.skylinePoint(azimuth: 90, horizon: skyline))
        XCTAssertEqual(ridge.azimuth.start, 87, accuracy: 1e-9)
        XCTAssertEqual(ridge.azimuth.length, 6, accuracy: 1e-9)
        XCTAssertEqual(ridge.minimumAltitude, 30, accuracy: 1e-9)
        XCTAssertEqual(ridge.maximumAltitude, 40, accuracy: 1e-9)

        let building = try XCTUnwrap(SkyWindow.skylinePoint(azimuth: 190, horizon: skyline, azimuthTolerance: 5,
                                                            altitudeAbove: 2...6))
        XCTAssertEqual(building.azimuth.start, 185, accuracy: 1e-9)
        XCTAssertEqual(building.azimuth.length, 10, accuracy: 1e-9)
        XCTAssertEqual(building.minimumAltitude, skyline.altitude(at: 190) + 2, accuracy: 1e-9)
        XCTAssertEqual(building.maximumAltitude, skyline.altitude(at: 190) + 6, accuracy: 1e-9)

        let flat = try XCTUnwrap(SkyWindow.skylinePoint(azimuth: 45, horizon: .flat))
        XCTAssertEqual(flat.minimumAltitude, 0)
        XCTAssertEqual(flat.maximumAltitude, 10)
        let high = try XCTUnwrap(SkyWindow.skylinePoint(azimuth: 45, horizon: .constant(60), azimuthTolerance: 3,
                                                        altitudeAbove: 0...40))
        XCTAssertEqual(high.minimumAltitude, 60, accuracy: 1e-9)
        XCTAssertEqual(high.maximumAltitude, 90, accuracy: 1e-9)

        XCTAssertNil(SkyWindow.skylinePoint(azimuth: .nan, horizon: skyline))
        XCTAssertNil(SkyWindow.skylinePoint(azimuth: 90, horizon: skyline, azimuthTolerance: .nan))
        XCTAssertNil(SkyWindow.skylinePoint(azimuth: 90, horizon: skyline, azimuthTolerance: 181))
        XCTAssertNil(SkyWindow.skylinePoint(azimuth: 90, horizon: skyline, azimuthTolerance: 3, altitudeAbove: 0...100))
        XCTAssertNil(SkyWindow.skylinePoint(azimuth: 90, horizon: skyline, azimuthTolerance: 3, altitudeAbove: -100...10))
    }

    func testDarknessKindsNameTheSunAltitudeTheyNeed() {
        XCTAssertEqual(SkyWindowDarkness.astronomical.sunAltitudeLimit, -18)
        XCTAssertEqual(SkyWindowDarkness.nautical.sunAltitudeLimit, -12)
        XCTAssertEqual(SkyWindowDarkness.civil.sunAltitudeLimit, -6)
        XCTAssertNil(SkyWindowDarkness.anyTime.sunAltitudeLimit)
        for kind in SkyWindowDarkness.allCases { XCTAssertEqual(SkyWindowDarkness(rawValue: kind.rawValue), kind) }
        XCTAssertNil(SkyWindowDarkness(rawValue: "twilight"))
    }

    // MARK: A fixed star

    func testAFixedStarCrossesTheSouthWindowOnlyAtTransit() throws {
        // A star whose right ascension is the local sidereal time at midnight transits at midnight, in the middle of
        // each night. Declination +10° at 40° N: transit altitude 60°, azimuth rate there 29.6°/h, so a window of
        // 180° ± 2° is crossed in 4° / 29.6°/h = 8.1 minutes.
        let first = try noon(boulder, 2026, 1, 10)
        let midnight = first.addingTimeInterval(12 * 3600)
        let star = EquatorialCoordinate(
            rightAscension: SkyFrame(date: midnight, observer: boulder.observer).localApparentSiderealTime,
            declination: 10)
        let found = try matches(boulder, .fixed(star), window(180, 2, 5, 90), from: first,
                                to: try noon(boulder, 2026, 1, 20), darkness: .anyTime)
        XCTAssertEqual(found.count, 10)
        for (index, match) in found.enumerated() {
            let night = RiseSetCalculator.riseTransitSet(
                forJ2000: star, observer: boulder.observer,
                within: DateInterval(start: try noon(boulder, 2026, 1, 10 + index), duration: 86_400))
            let transit = try XCTUnwrap(night.transit)
            XCTAssertEqual(match.night.start, try noon(boulder, 2026, 1, 10 + index))
            XCTAssertTrue(match.interval.start <= transit && transit <= match.interval.end)
            XCTAssertEqual(match.midpoint.timeIntervalSince(transit), 0, accuracy: 15, "night \(index)")
            XCTAssertEqual(match.azimuth, 180, accuracy: 0.05)
            XCTAssertEqual(match.altitude, 60, accuracy: 0.3)
            XCTAssertTrue(match.isAboveSkyline)

            // The root finder gives the moments the star is at 178° and 182°; the match is inside them, within the
            // 10 s of the bisection.
            let around = DateInterval(start: transit.addingTimeInterval(-1800), end: transit.addingTimeInterval(1800))
            let azimuth = { (date: Date) in
                SkyFrame(date: date, observer: self.boulder.observer)
                    .horizontal(j2000: star, properMotion: nil, refraction: true).azimuth
            }
            let entry = try XCTUnwrap(RiseSetCalculator.crossings(of: azimuth, threshold: 178, within: around).first).time
            let exit = try XCTUnwrap(RiseSetCalculator.crossings(of: azimuth, threshold: 182, within: around).first).time
            XCTAssertEqual(exit.timeIntervalSince(entry), 486, accuracy: 10, "the window takes 8.1 minutes to cross")
            XCTAssertEqual(match.interval.start.timeIntervalSince(entry), 5, accuracy: 5, "night \(index)")
            XCTAssertEqual(exit.timeIntervalSince(match.interval.end), 5, accuracy: 5, "night \(index)")
        }
    }

    func testTheNightsOfASearchFollowTheTimeZone() throws {
        // Spring forward in Denver on 8 March 2026 makes the night that starts on the 7th 23 hours long.
        let first = try noon(boulder, 2026, 3, 7)
        let star = EquatorialCoordinate(
            rightAscension: SkyFrame(date: first.addingTimeInterval(11.5 * 3600), observer: boulder.observer)
                .localApparentSiderealTime,
            declination: 10)
        let found = try matches(boulder, .fixed(star), window(180, 2, 5, 90), from: first,
                                to: try noon(boulder, 2026, 3, 9), darkness: .anyTime)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].night.duration, 23 * 3600, accuracy: 1)
        XCTAssertEqual(found[1].night.duration, 24 * 3600, accuracy: 1)
        XCTAssertEqual(found[1].night.start, try noon(boulder, 2026, 3, 8))
    }

    func testAMatchAgreesWithABruteForceScan() throws {
        let first = try noon(boulder, 2026, 1, 10)
        let star = EquatorialCoordinate(
            rightAscension: SkyFrame(date: first.addingTimeInterval(12 * 3600), observer: boulder.observer)
                .localApparentSiderealTime + 40,
            declination: -10)
        let box = try window(150, 30, 10, 40)
        let found = try matches(boulder, .fixed(star), box, from: first, to: try noon(boulder, 2026, 1, 13),
                                darkness: .nautical)
        var expected = [DateInterval]()
        for night in 0..<3 {
            var start: Date?
            var last: Date?
            var time = try noon(boulder, 2026, 1, 10 + night)
            let end = try noon(boulder, 2026, 1, 11 + night)
            while time < end {
                let frame = SkyFrame(date: time, observer: boulder.observer)
                let place = apparent(frame, star)
                let inside = frame.horizontal(of: .sun, refraction: false).altitude < -12
                    && box.azimuth.contains(place.azimuth)
                    && place.altitude >= box.minimumAltitude && place.altitude <= box.maximumAltitude
                if inside {
                    if start == nil { start = time }
                    last = time
                } else if let opened = start, let closed = last {
                    expected.append(DateInterval(start: opened, end: closed))
                    start = nil
                }
                time = time.addingTimeInterval(30)
            }
            if let opened = start, let closed = last { expected.append(DateInterval(start: opened, end: closed)) }
        }
        XCTAssertFalse(expected.isEmpty)
        Support.assertIntervals(found.map(\.interval), expected, accuracy: 45, "against a 30 s scan")
    }

    // MARK: The Milky Way core

    func testTheCoreStandsInASouthWestWindowOnSummerNightsAtFortySevenNorth() throws {
        // At 47° N the core (declination −29°) culminates at 14° and sets at azimuth 225° (cos A = sin δ / cos φ).
        // Its setting runs through 210…240° below 10° from about mid-July, when it is still dark enough, to autumn.
        let box = try window(225, 15, 3, 10)
        let found = try matches(innsbruck, coreTarget, box, from: try noon(innsbruck, 2026, 7, 1),
                                to: try noon(innsbruck, 2026, 10, 1))
        XCTAssertTrue((50...93).contains(found.count), "found \(found.count)")
        let core = MilkyWayCoreVisibility.galacticCentre
        for match in found {
            let frame = SkyFrame(date: match.midpoint, observer: innsbruck.observer)
            let place = apparent(frame, core)
            XCTAssertEqual(match.azimuth, place.azimuth, accuracy: 0.02)
            XCTAssertEqual(match.altitude, place.altitude, accuracy: 0.02)
            XCTAssertTrue((210.0...240.0).contains(match.azimuth) && (3.0...10.0).contains(match.altitude))
            XCTAssertTrue(match.isAboveSkyline)
            XCTAssertTrue(match.night.start <= match.interval.start && match.interval.end <= match.night.end)
            for date in [match.interval.start, match.midpoint, match.interval.end] {
                XCTAssertLessThan(sunAltitude(date, innsbruck.observer), -17.99, "dark at \(date)")
            }
        }
        // Even at the solstice the Sun sinks 19.6° at 47° N, so there are dark hours at the start of the range, with
        // the core setting at the end of them.
        XCTAssertGreaterThan(try XCTUnwrap(found.first).interval.start, try noon(innsbruck, 2026, 7, 1))
        XCTAssertTrue(zip(found, found.dropFirst()).allSatisfy { $0.interval.end <= $1.interval.start }, "in time order")
        // The core sets about 4 minutes earlier each night, so the window is crossed every night in August.
        let august = found.filter {
            $0.night.start >= (try? noon(innsbruck, 2026, 8, 1)) ?? .distantFuture
                && $0.night.start < (try? noon(innsbruck, 2026, 9, 1)) ?? .distantPast
        }
        XCTAssertEqual(Set(august.map(\.night.start)).count, 31)
    }

    func testTheCoreWindowMatchesTheNightPlannerWhenItIsAskedForHigherUp() throws {
        // Altitudes of 10° and more in the dark are what the planner calls the core visible. The planner's 10° is
        // geometric; the window's altitudes are apparent, so its lower edge is where refraction lifts 10° to.
        let summary = try Support.summary(boulder, 2026, 7, 10)
        let visible = summary.milkyWayCore.visibleIntervals
        XCTAssertFalse(visible.isEmpty)
        let found = try matches(boulder, coreTarget, window(180, 180, Refraction.apparentAltitude(trueAltitude: 10), 90),
                                from: summary.night.start, to: summary.night.end)
        Support.assertIntervals(found.map(\.interval), visible, accuracy: 25, "the planner's visible intervals")
        let best = try XCTUnwrap(summary.milkyWayCore.bestTime)
        XCTAssertTrue(found.contains { $0.interval.contains(best) })
    }

    // MARK: Darkness

    func testDarknessKindsKeepTheStretchOfTheSunBelowTheirLimit() throws {
        // A circumpolar star is in the window all night, so the matches are exactly the dark stretches.
        let star = SkyWindowTarget.fixed(EquatorialCoordinate(rightAscension: 0, declination: 80))
        let box = try window(180, 180, 5, 90)
        let from = try noon(innsbruck, 2026, 8, 20)
        let twilight = TwilightCalculator.night(startingOn: from, observer: innsbruck.observer,
                                                timeZone: try innsbruck.timeZone())
        func hours(_ kind: SkyWindowDarkness) throws -> Double {
            let found = try matches(innsbruck, star, box, from: from, to: from.addingTimeInterval(86_400), darkness: kind)
            XCTAssertEqual(found.count, 1, kind.rawValue)
            return found.reduce(0) { $0 + $1.interval.duration } / 3600
        }
        func expected(_ dusk: Date?, _ dawn: Date?) throws -> Double {
            try XCTUnwrap(dawn).timeIntervalSince(try XCTUnwrap(dusk)) / 3600
        }
        XCTAssertEqual(try hours(.astronomical), try expected(twilight.astronomicalDusk, twilight.astronomicalDawn),
                       accuracy: 0.012)
        XCTAssertEqual(try hours(.nautical), try expected(twilight.nauticalDusk, twilight.nauticalDawn),
                       accuracy: 0.012)
        XCTAssertEqual(try hours(.civil), try expected(twilight.civilDusk, twilight.civilDawn), accuracy: 0.012)
        XCTAssertEqual(try hours(.anyTime), 24, accuracy: 1e-6)
        XCTAssertTrue(try hours(.anyTime) > hours(.civil) + 1 && hours(.civil) > hours(.nautical) + 0.5
                      && hours(.nautical) > hours(.astronomical) + 0.5)
    }

    func testThereIsNoAstronomicalDarknessInAPolarSummer() throws {
        let box = try window(180, 180, 0, 90)
        let from = try noon(tromso, 2026, 6, 20)
        let to = try noon(tromso, 2026, 6, 24)
        let star = SkyWindowTarget.fixed(EquatorialCoordinate(rightAscension: 80, declination: 30))
        for kind in [SkyWindowDarkness.astronomical, .nautical, .civil] {
            XCTAssertTrue(try matches(tromso, star, box, from: from, to: to, darkness: kind).isEmpty, kind.rawValue)
        }
        let anyTime = try matches(tromso, .body(.sun), box, from: from, to: to, darkness: .anyTime)
        XCTAssertFalse(anyTime.isEmpty, "the midnight sun stands in the window")
    }

    // MARK: The Moon

    private func julyFrom() throws -> Date { try noon(boulder, 2026, 7, 1) }
    private func julyTo() throws -> Date { try noon(boulder, 2026, 8, 1) }
    private func wholeSouth() throws -> SkyWindow { try window(180, 90, 5, 90) }

    private func nights(_ found: [SkyWindowMatch]) -> Set<Date> { Set(found.map(\.night.start)) }

    func testTheMoonBelowTheHorizonRuleRemovesNights() throws {
        let all = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo())
        let moonFree = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo(),
                                   moon: .belowHorizon)
        XCTAssertGreaterThanOrEqual(nights(all).count, 29, "the core is up in the dark every night of July")
        XCTAssertLessThanOrEqual(nights(moonFree).count, nights(all).count - 4,
                                 "\(nights(moonFree).count) of \(nights(all).count)")
        XCTAssertFalse(nights(moonFree).isEmpty)
        XCTAssertTrue(nights(moonFree).isSubset(of: nights(all)))
        for match in moonFree {
            XCTAssertFalse(match.moon.isUp)
            for date in [match.interval.start, match.midpoint, match.interval.end] {
                let altitude = SkyFrame(date: date, observer: boulder.observer).horizontal(of: .moon, refraction: false)
                    .altitude
                XCTAssertLessThan(altitude, -0.75, "the Moon is down at \(date): \(altitude)")
            }
        }
        let removed = nights(all).subtracting(nights(moonFree))
        for match in all where removed.contains(match.night.start) {
            XCTAssertTrue(match.moon.isUp, "a removed night has the Moon up whenever the core is in the window")
        }
        let total = all.reduce(0) { $0 + $1.interval.duration }
        XCTAssertLessThan(moonFree.reduce(0) { $0 + $1.interval.duration }, total - 4 * 3600)
    }

    func testTheIlluminationRuleKeepsTheDimMoonNights() throws {
        let all = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo())
        let dim = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo(),
                              moon: .illuminatedAtMost(0.25))
        XCTAssertTrue((6...16).contains(nights(dim).count), "\(nights(dim).count)")
        XCTAssertTrue(nights(dim).isSubset(of: nights(all)))
        for match in dim {
            for date in [match.interval.start, match.midpoint, match.interval.end] {
                XCTAssertLessThanOrEqual(MoonPhaseCalculator.info(at: date).illuminatedFraction, 0.252, "\(date)")
            }
        }
        // New Moon on 14 July 2026, Full Moon on 29 July.
        XCTAssertTrue(nights(dim).contains(try noon(boulder, 2026, 7, 14)))
        XCTAssertFalse(nights(dim).contains(try noon(boulder, 2026, 7, 29)))
        let none = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo(),
                               moon: .illuminatedAtMost(0))
        XCTAssertTrue(none.isEmpty)
        let every = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo(),
                                moon: .illuminatedAtMost(1))
        XCTAssertEqual(all, every)
    }

    func testTheMoonStateDescribesTheMoonAtTheMidpoint() throws {
        let all = try matches(boulder, coreTarget, wholeSouth(), from: julyFrom(), to: julyTo())
        XCTAssertTrue(all.contains { $0.moon.isUp } && all.contains { !$0.moon.isUp })
        for match in all {
            let frame = SkyFrame(date: match.midpoint, observer: boulder.observer)
            XCTAssertEqual(match.moon.altitude, frame.horizontal(of: .moon, refraction: true).altitude, accuracy: 0.02)
            XCTAssertEqual(match.moon.illuminatedFraction,
                           MoonPhaseCalculator.info(at: match.midpoint).illuminatedFraction, accuracy: 1e-9)
            if match.moon.altitude > 1 { XCTAssertTrue(match.moon.isUp) }
            if match.moon.altitude < -2 { XCTAssertFalse(match.moon.isUp) }
        }
        // The Moon itself: a rule that it be down can never hold for it.
        let moonWindow = try window(180, 180, 0, 90)
        let from = try julyFrom()
        let moonSelf = try matches(boulder, .body(.moon), moonWindow, from: from,
                                   to: from.addingTimeInterval(5 * 86_400), darkness: .anyTime)
        XCTAssertFalse(moonSelf.isEmpty)
        XCTAssertTrue(moonSelf.allSatisfy { $0.moon.isUp })
        XCTAssertTrue(try matches(boulder, .body(.moon), moonWindow, from: from,
                                  to: from.addingTimeInterval(5 * 86_400), darkness: .anyTime, moon: .belowHorizon)
            .allSatisfy { $0.altitude < 0.5 })
    }

    // MARK: Objects and the skyline

    func testEveryKindOfTargetFollowsTheSameSky() throws {
        let from = try noon(boulder, 2026, 9, 1)
        let to = try noon(boulder, 2026, 9, 3)
        let everywhere = try window(180, 180, 0, 90)
        let catalog = try CatalogSmallBodyFixture.catalog()
        func check(_ target: SkyWindowTarget, _ expected: (SkyFrame) -> HorizontalCoordinate) throws {
            let found = try matches(boulder, target, everywhere, from: from, to: to, darkness: .anyTime)
            XCTAssertFalse(found.isEmpty, "\(target)")
            for match in found {
                let horizontal = expected(SkyFrame(date: match.midpoint, observer: boulder.observer))
                XCTAssertEqual(match.azimuth, horizontal.azimuth, accuracy: 0.02, "\(target)")
                XCTAssertEqual(match.altitude, horizontal.altitude, accuracy: 0.02, "\(target)")
            }
        }
        try check(.body(.jupiter)) { $0.horizontal(of: .jupiter, refraction: true) }
        try check(.body(.moon)) { $0.horizontal(of: .moon, refraction: true) }
        let place = EquatorialCoordinate(rightAscension: 279.2347, declination: 38.7837)
        let motion = ProperMotion(raMilliarcsecondsPerYear: 200.94, decMilliarcsecondsPerYear: 286.23)
        try check(.fixed(place, properMotion: motion)) {
            $0.horizontal(j2000: place, properMotion: motion, refraction: true)
        }
        try check(.milkyWayCore) {
            $0.horizontal(j2000: MilkyWayCoreVisibility.galacticCentre, properMotion: nil, refraction: true)
        }
        for id in ["planet.saturn", "dso.M31", "special.galacticCenter", "special.ncp", "asteroid.4", "comet.12P"] {
            let object = try XCTUnwrap(catalog.object(id: id), id)
            try check(.catalogObject(object)) { $0.horizontal(of: object, refraction: true) }
        }
        let custom = CelestialObject.custom(name: "Test", j2000: EquatorialCoordinate(rightAscension: 10, declination: -20))
        try check(.catalogObject(custom)) { $0.horizontal(of: custom, refraction: true) }
    }

    func testTheSkylineDecidesWhetherAMatchIsAboveIt() throws {
        let star = SkyWindowTarget.fixed(EquatorialCoordinate(rightAscension: 30, declination: 0))
        let from = try noon(boulder, 2026, 11, 1)
        let to = try noon(boulder, 2026, 11, 4)
        let wall = HorizonProfile.constant(25)
        let low = try window(180, 180, 5, 15)
        let high = try window(180, 180, 30, 40)
        let hidden = try matches(boulder, star, low, from: from, to: to, horizon: wall, darkness: .anyTime)
        XCTAssertTrue(!hidden.isEmpty && hidden.allSatisfy { !$0.isAboveSkyline })
        let visible = try matches(boulder, star, high, from: from, to: to, horizon: wall, darkness: .anyTime)
        XCTAssertTrue(!visible.isEmpty && visible.allSatisfy(\.isAboveSkyline))
        let flat = try matches(boulder, star, low, from: from, to: to, darkness: .anyTime)
        XCTAssertEqual(hidden.map(\.interval), flat.map(\.interval))
        XCTAssertTrue(flat.allSatisfy(\.isAboveSkyline))
        // A window cut from the skyline itself is by construction above it.
        let gap = try XCTUnwrap(SkyWindow.skylinePoint(azimuth: 110, horizon: HorizonTestSupport.truthProfile,
                                                       azimuthTolerance: 5, altitudeAbove: 1...12))
        let over = try matches(boulder, star, gap, from: from, to: to, horizon: HorizonTestSupport.truthProfile,
                               darkness: .anyTime)
        XCTAssertTrue(over.allSatisfy(\.isAboveSkyline))
    }

    // MARK: Ranges, limits and errors

    func testMatchesStayInsideTheRangeAndTheirNights() throws {
        // 03:00 on the 11th: inside the night of the 10th, with a star on the meridian at that moment.
        let from = try noon(boulder, 2026, 1, 10).addingTimeInterval(15 * 3600)
        let to = try noon(boulder, 2026, 1, 14).addingTimeInterval(3 * 3600)
        let star = SkyWindowTarget.fixed(EquatorialCoordinate(
            rightAscension: SkyFrame(date: from, observer: boulder.observer).localApparentSiderealTime, declination: 10))
        let box = try window(180, 180, 0, 90)
        let found = try matches(boulder, star, box, from: from, to: to, darkness: .anyTime)
        XCTAssertFalse(found.isEmpty)
        XCTAssertEqual(try XCTUnwrap(found.first).interval.start, from, "the star is up at the start of the range")
        XCTAssertEqual(try XCTUnwrap(found.first).night.start, try noon(boulder, 2026, 1, 10))
        XCTAssertTrue(found.allSatisfy { $0.interval.start >= from && $0.interval.end <= to })
        XCTAssertTrue(found.allSatisfy { $0.night.start <= $0.interval.start && $0.interval.end <= $0.night.end })
        XCTAssertTrue(zip(found, found.dropFirst()).allSatisfy { $0.interval.end <= $1.interval.start })
        XCTAssertTrue(try matches(boulder, star, box, from: from, to: from, darkness: .anyTime).isEmpty)
    }

    func testTheSearchRefusesWhatItCannotRun() throws {
        let box = try window(180, 10, 0, 90)
        let from = try noon(boulder, 2026, 1, 1)
        XCTAssertThrowsError(try matches(boulder, coreTarget, box, from: from.addingTimeInterval(1), to: from)) {
            guard case SkyWindowError.invalidRange = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try matches(boulder, coreTarget, box, from: from,
                                         to: from.addingTimeInterval(401 * 86_400))) {
            XCTAssertEqual($0 as? SkyWindowError, .rangeTooLong(limit: 400))
        }
        XCTAssertThrowsError(try matches(boulder, .fixed(EquatorialCoordinate(rightAscension: .nan, declination: 10)),
                                         box, from: from, to: from.addingTimeInterval(86_400))) {
            XCTAssertEqual($0 as? SkyWindowError, .invalidTarget)
        }
        XCTAssertThrowsError(try matches(boulder, coreTarget, box, from: from, to: from.addingTimeInterval(86_400),
                                         moon: .illuminatedAtMost(1.5))) {
            XCTAssertEqual($0 as? SkyWindowError, .invalidMoonRule(fraction: 1.5))
        }
        XCTAssertThrowsError(try matches(boulder, coreTarget, box, from: from, to: from.addingTimeInterval(86_400),
                                         moon: .illuminatedAtMost(.nan))) {
            guard case SkyWindowError.invalidMoonRule = $0 else { return XCTFail("\($0)") }
        }
    }

    func testTheMatchLimitCutsALongResultShort() throws {
        // The Sun is in an all-sky window whenever you look: one match per night, cut at the limit.
        let full = try XCTUnwrap(SkyWindow(azimuth: .full, minimumAltitude: -90, maximumAltitude: 90))
        let from = try noon(boulder, 2026, 1, 1)
        let found = try matches(boulder, .body(.sun), full, from: from, to: from.addingTimeInterval(300 * 86_400),
                                darkness: .anyTime)
        XCTAssertEqual(found.count, SkyWindowFinder.maximumMatchCount)
        XCTAssertEqual(SkyWindowFinder.maximumMatchCount, 200)
        XCTAssertEqual(try XCTUnwrap(found.first).interval.start, from)
        XCTAssertEqual(try XCTUnwrap(found.last).night.start, try noon(boulder, 2026, 1, 200), "the 200th night, across the change to daylight time")
    }

    func testTheNightLimitHoldsForAYearAndAHalf() throws {
        XCTAssertEqual(SkyWindowFinder.maximumNightCount, 400)
        let box = try window(180, 5, 0, 90)
        let from = try noon(boulder, 2026, 1, 1)
        // 400 nights are fine (this one has no match: the Sun is never below −18° while it stands due south); 401 are not.
        XCTAssertTrue(try matches(boulder, .body(.sun), box, from: from, to: from.addingTimeInterval(400 * 86_400),
                                  darkness: .astronomical).isEmpty)
        XCTAssertThrowsError(try matches(boulder, coreTarget, box, from: from,
                                         to: from.addingTimeInterval(401 * 86_400 + 3600))) {
            XCTAssertEqual($0 as? SkyWindowError, .rangeTooLong(limit: 400))
        }
    }

    func testAYearOfSearchingIsFast() throws {
        let box = try window(200, 20, 0, 40)
        let from = try noon(boulder, 2026, 1, 1)
        let to = try noon(boulder, 2027, 1, 1)
        var found = [SkyWindowMatch]()
        let clock = ContinuousClock()
        let elapsed = try clock.measure { found = try matches(boulder, coreTarget, box, from: from, to: to) }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        XCTAssertTrue((100...200).contains(found.count), "found \(found.count)")
        XCTAssertLessThan(seconds, Self.yearLimit, "took \(seconds) s")
        let withMoon = try clock.measure { _ = try matches(boulder, coreTarget, box, from: from, to: to, moon: .belowHorizon) }
        let secondsWithMoon = Double(withMoon.components.seconds) + Double(withMoon.components.attoseconds) / 1e18
        XCTAssertLessThan(secondsWithMoon, Self.yearLimit, "took \(secondsWithMoon) s with the Moon")
    }
}

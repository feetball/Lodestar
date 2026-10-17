import XCTest
@testable import LodestarKit

/// How high and for how long targets get in the dark: one target at a time, in batches, and for the Sun,
/// Moon and planets, checked against brute-force scans and the rise/set root finder.
final class PlanningVisibilityTests: XCTestCase {
    private typealias Support = PlanningTestSupport
    private typealias Sets = NightPlanner.IntervalSet

    private let boulder = Support.boulder

    // MARK: Targets

    private let andromedaGalaxy = EquatorialCoordinate(rightAscensionHours: 0 + 42.0 / 60 + 44.3 / 3_600,
                                                       declination: 41 + 16.0 / 60 + 9.0 / 3_600)
    private let orionNebula = EquatorialCoordinate(rightAscensionHours: 5 + 35.0 / 60 + 17.3 / 3_600,
                                                   declination: -(5 + 23.0 / 60 + 28.0 / 3_600))
    private let lagoonNebula = EquatorialCoordinate(rightAscensionHours: 18 + 3.0 / 60 + 37.0 / 3_600,
                                                    declination: -(24 + 23.0 / 60 + 12.0 / 3_600))
    private let polaris = EquatorialCoordinate(rightAscension: 37.954_515, declination: 89.264_110)
    private let alphaCentauri = EquatorialCoordinate(rightAscensionHours: 14 + 39.0 / 60 + 36.5 / 3_600,
                                                     declination: -(60 + 50.0 / 60 + 2.0 / 3_600))
    /// Barnard's Star, with the largest proper motion of any star: 10.3″ a year, almost due north.
    private let barnardsStar = EquatorialCoordinate(rightAscension: 269.452_075, declination: 4.693_391)
    private let barnardsMotion = ProperMotion(raMilliarcsecondsPerYear: -798.58, decMilliarcsecondsPerYear: 10_328.12)

    private func geometric(_ target: EquatorialCoordinate, _ motion: ProperMotion? = nil) -> (SkyFrame) -> HorizontalCoordinate {
        { $0.horizontal(j2000: target, properMotion: motion, refraction: false) }
    }

    /// A reproducible spread of targets over the whole sky.
    private func scatteredTargets(_ count: Int, seed: UInt64) -> [EquatorialCoordinate] {
        var generator = Support.SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            EquatorialCoordinate(rightAscension: .random(in: 0..<360, using: &generator),
                                 declination: AstroMath.asinDeg(.random(in: -1...1, using: &generator)))
        }
    }

    // MARK: Brute force

    /// Geometric altitudes of a target every `step` seconds through the dark intervals, ends included.
    private func scan(_ darkness: [DateInterval], step: TimeInterval = 30,
                      altitude: (Date) -> Double) -> [(date: Date, altitude: Double)] {
        darkness.flatMap { interval -> [(date: Date, altitude: Double)] in
            var dates = Array(stride(from: interval.start, to: interval.end, by: step))
            dates.append(interval.end)
            return dates.map { ($0, altitude($0)) }
        }
    }

    private func directAltitude(of target: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                                at date: Date, _ observer: Observer) -> Double {
        SkyFrame(date: date, observer: observer)
            .horizontal(j2000: target, properMotion: properMotion, refraction: false).altitude
    }

    // MARK: One target

    func testDefaultMinimumAltitudeIsTwentyDegrees() {
        XCTAssertEqual(NightPlanner.defaultMinimumAltitude, 20)
    }

    func testSingleTargetAgreesWithABruteForceScan() throws {
        for (site, month, day) in [(boulder, 10, 25), (Support.sydney, 6, 21)] {
            let summary = try Support.summary(site, 2026, month, day)
            let observer = site.observer
            for target in [andromedaGalaxy, orionNebula, lagoonNebula] {
                let label = "\(site.name) \(target)"
                let result = NightPlanner.visibility(of: geometric(target), during: summary)
                let samples = scan(summary.astronomicalDarknessIntervals) { directAltitude(of: target, at: $0, observer) }
                let highest = try XCTUnwrap(samples.max { $0.altitude < $1.altitude })

                XCTAssertEqual(result.minimumAltitude, 20, label)
                XCTAssertEqual(try XCTUnwrap(result.maxAltitudeDuringDarkness), highest.altitude, accuracy: 2e-3, label)
                let best = try XCTUnwrap(result.bestTime)
                XCTAssertEqual(best.timeIntervalSince(highest.date), 0, accuracy: 60, label)
                XCTAssertEqual(directAltitude(of: target, at: best, observer),
                               try XCTUnwrap(result.maxAltitudeDuringDarkness), accuracy: 2e-3, label)

                let secondsAbove = Double(samples.filter { $0.altitude >= 20 }.count) * 30
                XCTAssertEqual(result.hoursAboveMinimum * 3_600, secondsAbove, accuracy: 90, label)
                XCTAssertEqual(Sets.intersection(result.intervalsAboveMinimum, summary.astronomicalDarknessIntervals),
                               result.intervalsAboveMinimum, label)

                let events = RiseSetCalculator.riseTransitSet(forJ2000: target, observer: observer, within: summary.night)
                XCTAssertEqual(result.riseTransitSet.circumstance, events.circumstance, label)
                for (found, wanted) in [(result.riseTransitSet.rise, events.rise), (result.riseTransitSet.transit, events.transit),
                                        (result.riseTransitSet.set, events.set)] {
                    XCTAssertEqual(found == nil, wanted == nil, label)
                    if let found, let wanted { XCTAssertEqual(found.timeIntervalSince(wanted), 0, accuracy: 1, label) }
                }
            }
        }
    }

    func testIntervalsAboveTheMinimumAreBoundedByTheMinimumAltitude() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let observer = boulder.observer
        let result = NightPlanner.visibility(of: geometric(andromedaGalaxy), during: summary, minimumAltitude: 45)
        XCTAssertEqual(result.minimumAltitude, 45)
        XCTAssertFalse(result.intervalsAboveMinimum.isEmpty)
        let darkEdges = summary.astronomicalDarknessIntervals.flatMap { [$0.start, $0.end] }
        for interval in result.intervalsAboveMinimum {
            let middle = interval.start.addingTimeInterval(interval.duration / 2)
            XCTAssertGreaterThanOrEqual(directAltitude(of: andromedaGalaxy, at: middle, observer), 45)
            for edge in [interval.start, interval.end] where darkEdges.allSatisfy({ abs($0.timeIntervalSince(edge)) > 1 }) {
                XCTAssertEqual(directAltitude(of: andromedaGalaxy, at: edge, observer), 45, accuracy: 0.01)
            }
        }
        XCTAssertEqual(result.hoursAboveMinimum, result.intervalsAboveMinimum.reduce(0) { $0 + $1.duration } / 3_600,
                       accuracy: 1e-9)
    }

    func testHoursAboveShrinkAsTheMinimumAltitudeRises() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        var previous = Double.infinity
        for minimum in [-90.0, 0, 10, 20, 30, 40, 50, 60, 89, 90] {
            let hours = NightPlanner.visibility(of: geometric(andromedaGalaxy), during: summary,
                                                minimumAltitude: minimum).hoursAboveMinimum
            XCTAssertLessThanOrEqual(hours, previous, "minimum \(minimum)")
            previous = hours
        }
        let everything = NightPlanner.visibility(of: geometric(andromedaGalaxy), during: summary, minimumAltitude: -90)
        XCTAssertEqual(everything.hoursAboveMinimum, summary.astronomicalDarkHours, accuracy: 1e-6)
        XCTAssertEqual(previous, 0, "no target is 90° high for long")
    }

    func testInvalidMinimumAltitudesAreReplacedOrClamped() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let position = geometric(andromedaGalaxy)
        XCTAssertEqual(NightPlanner.visibility(of: position, during: summary, minimumAltitude: .nan).minimumAltitude, 20)
        XCTAssertEqual(NightPlanner.visibility(of: position, during: summary, minimumAltitude: .infinity).minimumAltitude, 20)
        XCTAssertEqual(NightPlanner.visibility(of: position, during: summary, minimumAltitude: 500).minimumAltitude, 90)
        XCTAssertEqual(NightPlanner.visibility(of: position, during: summary, minimumAltitude: -500).minimumAltitude, -90)
    }

    func testCircumpolarTargetStaysUpAllNight() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let result = NightPlanner.visibility(of: geometric(polaris), during: summary)
        XCTAssertEqual(result.riseTransitSet.circumstance, .alwaysUp)
        XCTAssertNil(result.riseTransitSet.rise)
        XCTAssertNil(result.riseTransitSet.set)
        XCTAssertEqual(try XCTUnwrap(result.maxAltitudeDuringDarkness), 40.6, accuracy: 0.1, "latitude plus 0.6°")
        XCTAssertEqual(result.hoursAboveMinimum, summary.astronomicalDarkHours, accuracy: 1e-6)
        XCTAssertEqual(result.intervalsAboveMinimum, summary.astronomicalDarknessIntervals)
    }

    func testTargetThatNeverRisesHasNoUsableTime() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let result = NightPlanner.visibility(of: geometric(alphaCentauri), during: summary)
        XCTAssertEqual(result.riseTransitSet.circumstance, .alwaysDown)
        XCTAssertLessThan(try XCTUnwrap(result.maxAltitudeDuringDarkness), -10)
        XCTAssertEqual(result.hoursAboveMinimum, 0)
        XCTAssertTrue(result.intervalsAboveMinimum.isEmpty)
        XCTAssertNotNil(result.bestTime, "the best time is the least bad moment, still reported")
    }

    func testTargetCrossingNearTheZenithReachesItsCulminationAltitude() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        // Precession has carried this J2000 place about 0.13° north by 2026, so it passes 0.01° from the zenith.
        let nearZenith = EquatorialCoordinate(rightAscension: 330, declination: 39.87)
        let apparent = SkyFrame(date: summary.referenceDate, observer: summary.observer).apparentPlace(j2000: nearZenith)
        let expected = 90 - abs(40 - apparent.declination)
        XCTAssertGreaterThan(expected, 89.9, "the target does pass almost through the zenith")
        let result = NightPlanner.visibility(of: geometric(nearZenith), during: summary)
        let transit = try XCTUnwrap(result.riseTransitSet.transit)
        XCTAssertEqual(try XCTUnwrap(result.maxAltitudeDuringDarkness), expected, accuracy: 0.03,
                       "the sampled sines are least precise right at the zenith")
        XCTAssertEqual(try XCTUnwrap(result.bestTime).timeIntervalSince(transit), 0, accuracy: 20)
    }

    // MARK: Darkness

    func testNoAstronomicalDarknessLeavesNoAltitudeButKeepsTheEvents() throws {
        let summary = try Support.summary(Support.tromso, 2026, 6, 21)
        XCTAssertFalse(summary.hasAstronomicalDarkness)
        let single = NightPlanner.visibility(of: geometric(andromedaGalaxy), during: summary)
        let batch = NightPlanner.visibility(ofFixed: [andromedaGalaxy, orionNebula], during: summary)
        let body = NightPlanner.visibility(of: .saturn, during: summary)
        for result in [single, batch[0], batch[1], body] {
            XCTAssertNil(result.maxAltitudeDuringDarkness)
            XCTAssertNil(result.bestTime)
            XCTAssertTrue(result.intervalsAboveMinimum.isEmpty)
            XCTAssertEqual(result.hoursAboveMinimum, 0)
        }
        XCTAssertEqual(single.riseTransitSet.circumstance, .alwaysUp, "the galaxy is circumpolar at 69.65° N")
        XCTAssertEqual(batch[1].riseTransitSet.circumstance, .normal)
    }

    func testMoonFreeDarknessCountsOnlyTheHoursWithoutMoonlight() throws {
        // 21 June 2026: the Moon sets at 00:57 MDT, 2.5 hours before dawn, and the Pole Star region stays up.
        let summary = try Support.summary(boulder, 2026, 6, 21)
        let moonSet = try XCTUnwrap(summary.moon.riseTransitSet.set)
        let all = NightPlanner.visibility(of: geometric(polaris), during: summary, darkness: .astronomical)
        let free = NightPlanner.visibility(of: geometric(polaris), during: summary, darkness: .moonFree)
        XCTAssertEqual(all.hoursAboveMinimum, summary.astronomicalDarkHours, accuracy: 1e-6)
        XCTAssertEqual(free.hoursAboveMinimum, summary.moonFreeDarkHours, accuracy: 1e-6)
        XCTAssertEqual(free.intervalsAboveMinimum, summary.darknessIntervals)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(free.bestTime), moonSet)

        // Around Full Moon there is no moon-free darkness at all.
        let full = try Support.summary(boulder, 2026, 10, 25)
        let result = NightPlanner.visibility(of: geometric(andromedaGalaxy), during: full, darkness: .moonFree)
        XCTAssertNil(result.maxAltitudeDuringDarkness)
        XCTAssertNil(result.bestTime)
        XCTAssertEqual(result.hoursAboveMinimum, 0)
        XCTAssertNotNil(NightPlanner.visibility(of: geometric(andromedaGalaxy), during: full).maxAltitudeDuringDarkness)
    }

    func testDarknessKindRoundTripsThroughCodable() throws {
        for kind in DarknessKind.allCases {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(DarknessKind.self, from: data), kind)
        }
        XCTAssertEqual(DarknessKind.allCases, [.astronomical, .moonFree])
    }

    // MARK: Batches

    func testBatchMatchesTheSingleTargetPath() throws {
        for (site, month, day) in [(boulder, 10, 25), (Support.sydney, 6, 21), (Support.london, 3, 20)] {
            let summary = try Support.summary(site, 2026, month, day)
            let observer = site.observer
            let targets = scatteredTargets(80, seed: UInt64(month * 100 + day))
            let batch = NightPlanner.visibility(ofFixed: targets, during: summary)
            XCTAssertEqual(batch.count, targets.count)
            for (target, found) in zip(targets, batch) {
                let label = "\(site.name) \(target)"
                let single = NightPlanner.visibility(of: geometric(target), during: summary)
                XCTAssertEqual(AstroMath.sinDeg(try XCTUnwrap(found.maxAltitudeDuringDarkness)),
                               AstroMath.sinDeg(try XCTUnwrap(single.maxAltitudeDuringDarkness)), accuracy: 5e-7, label)
                XCTAssertEqual(found.hoursAboveMinimum, single.hoursAboveMinimum, accuracy: 0.005, label)
                XCTAssertEqual(found.intervalsAboveMinimum.count, single.intervalsAboveMinimum.count, label)
                Support.assertIntervals(found.intervalsAboveMinimum, single.intervalsAboveMinimum, accuracy: 2, label)
                XCTAssertEqual(found.riseTransitSet.circumstance, single.riseTransitSet.circumstance, label)
                XCTAssertEqual(found.riseTransitSet.rise == nil, single.riseTransitSet.rise == nil, label)
                XCTAssertEqual(found.riseTransitSet.set == nil, single.riseTransitSet.set == nil, label)
                XCTAssertEqual(found.riseTransitSet.transit == nil, single.riseTransitSet.transit == nil, label)
                for (batchTime, singleTime) in [(found.riseTransitSet.rise, single.riseTransitSet.rise),
                                                (found.riseTransitSet.transit, single.riseTransitSet.transit),
                                                (found.riseTransitSet.set, single.riseTransitSet.set)] {
                    if let batchTime, let singleTime { XCTAssertEqual(batchTime.timeIntervalSince(singleTime), 0, accuracy: 1, label) }
                }
                if let best = found.bestTime, let maximum = found.maxAltitudeDuringDarkness {
                    XCTAssertEqual(AstroMath.sinDeg(directAltitude(of: target, at: best, observer)),
                                   AstroMath.sinDeg(maximum), accuracy: 5e-7, label)
                }
            }
        }
    }

    func testBatchResultsFollowTheOrderOfTheTargets() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let targets = [alphaCentauri, polaris, andromedaGalaxy, orionNebula]
        let results = NightPlanner.visibility(ofFixed: targets, during: summary)
        XCTAssertEqual(results.map(\.riseTransitSet.circumstance), [.alwaysDown, .alwaysUp, .normal, .normal])
        XCTAssertEqual(NightPlanner.visibility(ofFixed: targets.reversed(), during: summary).map(\.riseTransitSet.circumstance),
                       [.normal, .normal, .alwaysUp, .alwaysDown])
        XCTAssertTrue(NightPlanner.visibility(ofFixed: [], during: summary).isEmpty)
    }

    func testProperMotionMovesTheTargetByTheAmountItImplies() throws {
        // 14 June 2026: Barnard's Star crosses the meridian at about 00:20 solar time, in the dark. At the
        // meridian a shift north raises it by exactly that shift: 10.328″ a year for 26.5 years.
        let summary = try Support.summary(boulder, 2026, 6, 14)
        let years = SkyFrame(date: summary.night.start.addingTimeInterval(summary.night.duration / 2),
                             observer: boulder.observer).yearsSinceJ2000
        let shift = 10.328_12 * years / 3_600
        let without = try XCTUnwrap(NightPlanner.visibility(ofFixed: [barnardsStar], during: summary)[0].maxAltitudeDuringDarkness)
        let with = try XCTUnwrap(NightPlanner.visibility(ofFixed: [barnardsStar], properMotions: [barnardsMotion],
                                                         during: summary)[0].maxAltitudeDuringDarkness)
        XCTAssertEqual(with - without, shift, accuracy: 0.002)
        XCTAssertGreaterThan(shift, 0.07)
        let direct = try XCTUnwrap(NightPlanner.visibility(of: geometric(barnardsStar, barnardsMotion), during: summary)
            .maxAltitudeDuringDarkness)
        XCTAssertEqual(with, direct, accuracy: 1e-4, "the same as moving the star in every frame")
    }

    func testProperMotionsApplyByPositionAndMissingEntriesMeanNone() throws {
        let summary = try Support.summary(boulder, 2026, 6, 14)
        let targets = [barnardsStar, barnardsStar, barnardsStar]
        let altitudes = NightPlanner.visibility(ofFixed: targets, properMotions: [nil, barnardsMotion], during: summary)
            .map { $0.maxAltitudeDuringDarkness ?? .nan }
        XCTAssertEqual(altitudes[0], altitudes[2], accuracy: 1e-9, "a nil entry and a missing entry both mean no motion")
        XCTAssertGreaterThan(altitudes[1] - altitudes[0], 0.07)
        let longer = NightPlanner.visibility(ofFixed: [barnardsStar], properMotions: [barnardsMotion, barnardsMotion, nil],
                                             during: summary)
        XCTAssertEqual(longer.count, 1, "extra motions are ignored")
        XCTAssertEqual(longer[0].maxAltitudeDuringDarkness ?? .nan, altitudes[1], accuracy: 1e-9)
    }

    func testTargetsWithoutFiniteCoordinatesNeverRise() throws {
        let summary = try Support.summary(boulder, 2026, 10, 25)
        let broken = [EquatorialCoordinate(rightAscension: .nan, declination: 10),
                      EquatorialCoordinate(rightAscension: 10, declination: .nan),
                      EquatorialCoordinate(rightAscension: .infinity, declination: -.infinity)]
        let results = NightPlanner.visibility(ofFixed: broken + [andromedaGalaxy], during: summary)
        XCTAssertEqual(results.count, 4)
        for result in results.prefix(3) {
            XCTAssertEqual(result.riseTransitSet.circumstance, .alwaysDown)
            XCTAssertNil(result.riseTransitSet.rise)
            XCTAssertNil(result.riseTransitSet.transit)
            XCTAssertNil(result.riseTransitSet.set)
            XCTAssertNil(result.maxAltitudeDuringDarkness)
            XCTAssertNil(result.bestTime)
            XCTAssertEqual(result.hoursAboveMinimum, 0)
        }
        XCTAssertNotNil(results[3].maxAltitudeDuringDarkness, "the others are unaffected")
    }

    func testBatchOverAnIntervalUsesTheIntervalForEverything() throws {
        let observer = boulder.observer
        let start = try Support.localNoon(2026, 10, 25, in: try boulder.timeZone()).addingTimeInterval(11 * 3_600)
        let window = DateInterval(start: start, duration: 4 * 3_600)           // 23:00 to 03:00 MDT
        let targets = [andromedaGalaxy, orionNebula, polaris]
        let results = NightPlanner.visibility(ofFixed: targets, observer: observer, during: window)
        for (target, result) in zip(targets, results) {
            let samples = scan([window]) { directAltitude(of: target, at: $0, observer) }
            let highest = try XCTUnwrap(samples.max { $0.altitude < $1.altitude })
            XCTAssertEqual(try XCTUnwrap(result.maxAltitudeDuringDarkness), highest.altitude, accuracy: 2e-3)
            XCTAssertEqual(result.hoursAboveMinimum * 3_600, Double(samples.filter { $0.altitude >= 20 }.count) * 30, accuracy: 90)
            XCTAssertTrue(result.intervalsAboveMinimum.allSatisfy { window.start <= $0.start && $0.end <= window.end })
            XCTAssertEqual(result.riseTransitSet,
                           RiseSetCalculator.riseTransitSet(forJ2000: target, observer: observer, within: window))
        }
        let single = NightPlanner.visibility(of: geometric(andromedaGalaxy), observer: observer, during: window)
        XCTAssertEqual(single.maxAltitudeDuringDarkness ?? .nan, results[0].maxAltitudeDuringDarkness ?? .infinity, accuracy: 2e-5)
    }

    func testUnusableIntervalsGiveNoDarknessInsteadOfFailing() throws {
        let observer = boulder.observer
        let undefined = DateInterval(start: Date(timeIntervalSinceReferenceDate: .nan), duration: 3_600)
        let empty = DateInterval(start: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 0)
        for window in [undefined, empty] {
            let single = NightPlanner.visibility(of: geometric(andromedaGalaxy), observer: observer, during: window)
            let batch = NightPlanner.visibility(ofFixed: [andromedaGalaxy, polaris], observer: observer, during: window)
            let body = NightPlanner.visibility(of: .mars, observer: observer, during: window)
            XCTAssertEqual(batch.count, 2)
            for result in [single, batch[0], batch[1], body] {
                XCTAssertNil(result.maxAltitudeDuringDarkness)
                XCTAssertNil(result.bestTime)
                XCTAssertEqual(result.hoursAboveMinimum, 0)
            }
        }
    }

    func testWindowsOfManyWeeksAreSampledMoreCoarselyButStayAccurate() throws {
        // Over 100 days the dark time is sampled every 864 s instead of every 600 s (10 000 frames at most).
        // Polaris stays above 20° throughout. The Andromeda Galaxy, at declination +41°, is above 20° for
        // the fraction acos((sin 20° − sin 40° sin 41.3°) / (cos 40° cos 41.3°)) / 180° = 0.5456 of every
        // sidereal day, give or take the part-day at the ends of the window; the root finder gives the exact total.
        let observer = boulder.observer
        let window = DateInterval(start: Date(timeIntervalSince1970: 1_792_195_200), duration: 100 * 86_400)
        let results = NightPlanner.visibility(ofFixed: [polaris, andromedaGalaxy], observer: observer, during: window)
        XCTAssertEqual(results[0].hoursAboveMinimum * 3_600, window.duration, accuracy: 1)

        let declination = SkyFrame(date: window.start.addingTimeInterval(window.duration / 2), observer: observer)
            .apparentPlace(j2000: andromedaGalaxy).declination
        let fraction = AstroMath.acosDeg((AstroMath.sinDeg(20) - AstroMath.sinDeg(40) * AstroMath.sinDeg(declination))
                                         / (AstroMath.cosDeg(40) * AstroMath.cosDeg(declination))) / 180
        let exact = Sets.totalDuration(of: Support.intervals(above: 20, within: window) {
            self.directAltitude(of: self.andromedaGalaxy, at: $0, observer)
        }) / 3_600
        XCTAssertEqual(exact, fraction * 100 * 24, accuracy: 5)
        XCTAssertEqual(results[1].hoursAboveMinimum, exact, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(results[1].maxAltitudeDuringDarkness), 90 - abs(40 - declination), accuracy: 0.05)
    }

    // MARK: Solar-system bodies

    func testBodyVisibilityMatchesTheSummary() throws {
        for (site, month, day) in [(boulder, 12, 14), (Support.sydney, 6, 21)] {
            let summary = try Support.summary(site, 2026, month, day)
            for planet in summary.planets {
                let label = "\(site.name) \(planet.body.displayName)"
                let result = NightPlanner.visibility(of: planet.body, during: summary, minimumAltitude: 10)
                XCTAssertEqual(result.riseTransitSet, planet.riseTransitSet, label)
                XCTAssertEqual(result.maxAltitudeDuringDarkness ?? .nan, planet.maxAltitudeDuringDarkness ?? .infinity,
                               accuracy: 1e-9, label)
                XCTAssertEqual(result.intervalsAboveMinimum, planet.visibleIntervals, label)
            }
            let moon = NightPlanner.visibility(of: .moon, during: summary)
            XCTAssertEqual(moon.riseTransitSet, summary.moon.riseTransitSet)
            XCTAssertNotNil(moon.maxAltitudeDuringDarkness)
            let sun = NightPlanner.visibility(of: .sun, during: summary)
            XCTAssertLessThanOrEqual(try XCTUnwrap(sun.maxAltitudeDuringDarkness), -17.99,
                                     "the Sun is at −18° at the ends of astronomical darkness and lower between")
            XCTAssertEqual(sun.hoursAboveMinimum, 0)
        }
    }

    func testMoonVisibilityUsesTheUpperLimbForItsEvents() throws {
        let summary = try Support.summary(boulder, 2026, 6, 21)
        let viaBody = NightPlanner.visibility(of: .moon, during: summary)
        let viaPosition = NightPlanner.visibility(of: { $0.horizontal(of: .moon, refraction: false) }, during: summary)
        let set = try XCTUnwrap(viaBody.riseTransitSet.set)
        let centreSet = try XCTUnwrap(viaPosition.riseTransitSet.set)
        // The Moon's centre reaches the standard horizon about a minute before its upper limb leaves it.
        XCTAssertGreaterThan(set.timeIntervalSince(centreSet), 30)
        XCTAssertLessThan(set.timeIntervalSince(centreSet), 180)
        XCTAssertEqual(viaBody.maxAltitudeDuringDarkness ?? .nan, viaPosition.maxAltitudeDuringDarkness ?? .infinity, accuracy: 1e-6)
    }

    func testBodyOverAnIntervalMatchesTheNightSummaryOfThatInterval() throws {
        let summary = try Support.summary(boulder, 2026, 12, 14)
        let dark = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let result = NightPlanner.visibility(of: .jupiter, observer: boulder.observer, during: dark)
        let planet = try XCTUnwrap(summary.planets.first { $0.body == .jupiter })
        XCTAssertEqual(result.maxAltitudeDuringDarkness ?? .nan, planet.maxAltitudeDuringDarkness ?? .infinity, accuracy: 1e-9)
        XCTAssertEqual(result.riseTransitSet,
                       RiseSetCalculator.riseTransitSet(for: .jupiter, observer: boulder.observer, within: dark))
    }
}

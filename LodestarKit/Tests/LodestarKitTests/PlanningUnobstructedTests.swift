import XCTest
@testable import LodestarKit

/// Hours above the skyline: `TargetVisibility.unobstructed*`, the `horizon` argument of `NightPlanner.visibility`
/// and the catalog-sized `NightPlanner.unobstructedVisibility`.
final class PlanningUnobstructedTests: XCTestCase {
    private typealias Support = HorizonTestSupport
    private typealias Planning = PlanningTestSupport
    private typealias Sets = NightPlanner.IntervalSet

    private func december() throws -> NightSummary { try Planning.summary(Planning.boulder, 2026, 12, 21) }
    private func october() throws -> NightSummary { try Planning.summary(Planning.boulder, 2026, 10, 25) }

    private let andromeda = EquatorialCoordinate(rightAscensionHours: 0 + 42.0 / 60 + 44.3 / 3_600,
                                                 declination: 41 + 16.0 / 60 + 9.0 / 3_600)
    private let orion = EquatorialCoordinate(rightAscensionHours: 5 + 35.0 / 60 + 17.3 / 3_600,
                                             declination: -(5 + 23.0 / 60 + 28.0 / 3_600))
    private let lagoon = EquatorialCoordinate(rightAscensionHours: 18 + 3.0 / 60 + 37.0 / 3_600,
                                              declination: -(24 + 23.0 / 60 + 12.0 / 3_600))
    private let polaris = EquatorialCoordinate(rightAscension: 37.954_515, declination: 89.264_110)

    private func targets(_ count: Int, seed: UInt64) -> [EquatorialCoordinate] {
        let generator = Support.SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            let rightAscension = 360 * generator.nextDouble()
            let declination = AstroMath.asinDeg(2 * generator.nextDouble() - 1)
            return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        }
    }

    // MARK: Without a skyline nothing changes

    func testWithoutASkylineThePlannerGivesTheNumbersItAlwaysGave() throws {
        // Recorded from the planner before it had a `horizon` argument.
        let expected: [(summary: NightSummary, hours: [Double], peaks: [Double])] = [
            (try october(), [10.245325372583336, 5.437605496843656, 0.0],
             [88.58000253152916, 44.6290463409263, 14.489015202981845]),
            (try december(), [6.96989415390624, 7.735069659385417, 0.0],
             [88.5780985114627, 44.62649021789657, -17.74847228007255]),
        ]
        for (summary, hours, peaks) in expected {
            let list = [andromeda, orion, lagoon]
            let results = NightPlanner.visibility(ofFixed: list, during: summary)
            XCTAssertEqual(results, NightPlanner.visibility(ofFixed: list, during: summary, horizon: nil))
            for index in results.indices {
                XCTAssertEqual(results[index].hoursAboveMinimum, hours[index], accuracy: 1e-9, "hours \(index)")
                XCTAssertEqual(try XCTUnwrap(results[index].maxAltitudeDuringDarkness), peaks[index], accuracy: 1e-9,
                               "peak \(index)")
            }
        }
    }

    func testWithoutASkylineUnobstructedIsAboveTheMinimumAltitude() throws {
        let list = targets(60, seed: 21)
        for result in NightPlanner.visibility(ofFixed: list, during: try december()) {
            XCTAssertEqual(result.unobstructedIntervals, result.intervalsAboveMinimum)
            XCTAssertEqual(result.unobstructedHours, result.hoursAboveMinimum)
            XCTAssertFalse(result.isBehindSkyline)
        }
    }

    func testEveryFormTakesANilSkylineAndGivesTheSameAsLeavingItOut() throws {
        let summary = try december()
        let observer = summary.observer
        let place = EquatorialCoordinate(rightAscensionHours: 5.5883, declination: -5.39)
        let position: (SkyFrame) -> HorizontalCoordinate = { $0.horizontal(j2000: place, refraction: false) }
        let span = DateInterval(start: summary.night.start.addingTimeInterval(8 * 3_600), duration: 12 * 3_600)
        XCTAssertEqual(NightPlanner.visibility(of: position, during: summary),
                       NightPlanner.visibility(of: position, during: summary, horizon: nil))
        XCTAssertEqual(NightPlanner.visibility(of: position, observer: observer, during: span),
                       NightPlanner.visibility(of: position, observer: observer, during: span, horizon: nil))
        XCTAssertEqual(NightPlanner.visibility(of: .jupiter, during: summary),
                       NightPlanner.visibility(of: .jupiter, during: summary, horizon: nil))
        XCTAssertEqual(NightPlanner.visibility(of: .moon, observer: observer, during: span),
                       NightPlanner.visibility(of: .moon, observer: observer, during: span, horizon: nil))
        XCTAssertEqual(NightPlanner.visibility(ofFixed: [place], observer: observer, during: span),
                       NightPlanner.visibility(ofFixed: [place], observer: observer, during: span, horizon: nil))
    }

    // MARK: A skyline hides things

    func testATargetRisingBehindABumpGetsFewerUnobstructedHours() throws {
        // Orion's Sword rises in the east; a 25° bump across the east hides it until it is 25° high, 20° above the
        // 5° minimum, which takes about two hours.
        let summary = try december()
        let observer = summary.observer
        let bump = HorizonProfile.flat.setting(to: 25, in: AzimuthRange(from: 50, to: 130))
        let open = NightPlanner.visibility(ofFixed: [orion], during: summary, minimumAltitude: 5)[0]
        let hidden = NightPlanner.visibility(ofFixed: [orion], during: summary, minimumAltitude: 5, horizon: bump)[0]
        XCTAssertEqual(hidden.unobstructedIntervals.count, 1)
        XCTAssertEqual(open.unobstructedIntervals.count, 1)
        XCTAssertLessThan(hidden.unobstructedHours, open.unobstructedHours - 1,
                          "\(hidden.unobstructedHours) against \(open.unobstructedHours)")
        XCTAssertGreaterThan(hidden.unobstructedHours, open.unobstructedHours - 3)
        XCTAssertEqual(hidden.unobstructedHours, hidden.hoursAboveMinimum)
        XCTAssertFalse(hidden.isBehindSkyline)

        // It clears the bump later and leaves the sky at the same moment as without it.
        let openWindow = open.unobstructedIntervals[0]
        let clearWindow = hidden.unobstructedIntervals[0]
        XCTAssertGreaterThan(clearWindow.start.timeIntervalSince(openWindow.start), 3_600)
        XCTAssertEqual(clearWindow.end.timeIntervalSince(openWindow.end), 0, accuracy: 2)

        // An independent count: the frames of the night every minute, above the minimum and above the bump.
        let dark = try XCTUnwrap(summary.darkness(.astronomical).first)
        var counted = 0
        var time = dark.start.addingTimeInterval(30)
        while time < dark.end {
            let horizontal = SkyFrame(date: time, observer: observer).horizontal(j2000: orion, refraction: false)
            if horizontal.altitude >= 5,
               horizontal.altitude >= HorizonVisibility.thresholdAltitude(
                   skylineAltitude: bump.altitude(at: horizontal.azimuth)) {
                counted += 1
            }
            time = time.addingTimeInterval(60)
        }
        XCTAssertEqual(hidden.unobstructedHours, Double(counted) / 60, accuracy: 0.05)
    }

    func testUnobstructedTimeNeverLeavesTheDarkOrTheOpenSky() throws {
        let wall = HorizonProfile.flat.setting(to: 40, in: AzimuthRange(from: 100, to: 260))
        let list = targets(120, seed: 22)
        let summary = try Planning.summary(Planning.boulder, 2026, 6, 20)
        for kind in DarknessKind.allCases {
            let dark = summary.darkness(kind)
            let open = NightPlanner.visibility(ofFixed: list, during: summary, darkness: kind)
            let hidden = NightPlanner.visibility(ofFixed: list, during: summary, darkness: kind, horizon: wall)
            for index in list.indices {
                let intervals = hidden[index].unobstructedIntervals
                XCTAssertEqual(intervals, Sets.intersection(intervals, dark), "\(kind) target \(index) stays in the dark")
                XCTAssertLessThanOrEqual(hidden[index].unobstructedHours, open[index].unobstructedHours + 0.002,
                                         "\(kind) target \(index)")
            }
            XCTAssertGreaterThan(hidden.indices.filter { hidden[$0].unobstructedHours < open[$0].unobstructedHours - 0.05 }.count,
                                 10)
        }
    }

    func testUnobstructedTimeOfTheSunMoonAndPlanetsAndOfAPositionFunctionFollowsTheSkyline() throws {
        let summary = try december()
        let wall = HorizonProfile.constant(35)
        let place = EquatorialCoordinate(rightAscensionHours: 5.5883, declination: -5.39)
        let position: (SkyFrame) -> HorizontalCoordinate = { $0.horizontal(j2000: place, refraction: false) }
        let open = NightPlanner.visibility(of: position, during: summary)
        let hidden = NightPlanner.visibility(of: position, during: summary, horizon: wall)
        XCTAssertGreaterThan(open.unobstructedHours, 5)
        XCTAssertLessThan(hidden.unobstructedHours, open.unobstructedHours - 1)
        let june = try Planning.summary(Planning.boulder, 2026, 6, 20)
        for body in [SolarSystemBody.moon, .jupiter, .saturn] {
            let free = NightPlanner.visibility(of: body, during: june, minimumAltitude: 0)
            let behind = NightPlanner.visibility(of: body, during: june, minimumAltitude: 0, horizon: wall)
            XCTAssertLessThanOrEqual(behind.unobstructedHours, free.unobstructedHours + 0.002, "\(body)")
        }
    }

    func testATargetThatIsUpButNeverClearIsBehindTheSkyline() throws {
        let summary = try december()
        let ring = HorizonProfile.constant(45)
        let behind = NightPlanner.visibility(ofFixed: [polaris], during: summary, horizon: ring)[0]
        XCTAssertTrue(behind.unobstructedIntervals.isEmpty)
        XCTAssertEqual(behind.unobstructedHours, 0)
        XCTAssertTrue(behind.isBehindSkyline, "Polaris is 40° up but the skyline is at 45°")
        XCTAssertFalse(NightPlanner.visibility(ofFixed: [polaris], during: summary)[0].isBehindSkyline)

        // Alpha Centauri never gets above the horizon at 40°N: nothing hides it, so it is not behind anything.
        let alphaCentauri = EquatorialCoordinate(rightAscensionHours: 14 + 39.0 / 60 + 36.5 / 3_600,
                                                 declination: -(60 + 50.0 / 60 + 2.0 / 3_600))
        let down = NightPlanner.visibility(ofFixed: [alphaCentauri], during: summary, horizon: ring)[0]
        XCTAssertTrue(down.unobstructedIntervals.isEmpty)
        XCTAssertFalse(down.isBehindSkyline)

        // A low skyline lets Polaris through.
        XCTAssertFalse(NightPlanner.visibility(ofFixed: [polaris], during: summary,
                                               horizon: HorizonProfile.constant(10))[0].isBehindSkyline)
    }

    // MARK: Many targets

    func testTheCheapBatchFindsTheSameStretchesAsTheFullPlanner() throws {
        let summary = try december()
        let list = targets(80, seed: 23)
        let wall = HorizonProfile.flat.setting(to: 30, in: AzimuthRange(from: 100, to: 260))
        let skylines: [HorizonProfile?] = [nil, wall, Support.truthProfile]
        for horizon in skylines {
            let full = NightPlanner.visibility(ofFixed: list, during: summary, horizon: horizon)
            let cheap = NightPlanner.unobstructedVisibility(ofFixed: list, during: summary, horizon: horizon)
            XCTAssertEqual(cheap.count, list.count)
            for index in list.indices {
                let message = "target \(index) over \(String(describing: horizon?.maximumAltitude))"
                Planning.assertIntervals(cheap[index].intervals, full[index].unobstructedIntervals, accuracy: 2, message)
                XCTAssertEqual(cheap[index].hours, full[index].unobstructedHours, accuracy: 0.002, message)
                XCTAssertEqual(cheap[index].isBehindSkyline, full[index].isBehindSkyline, message)
            }
            if horizon == wall { XCTAssertGreaterThan(cheap.filter(\.isBehindSkyline).count, 3) }
            if horizon == nil { XCTAssertTrue(cheap.allSatisfy { !$0.isBehindSkyline }) }
        }
    }

    func testTheCheapBatchHonoursDarknessMinimumAltitudeAndProperMotion() throws {
        let june = try Planning.summary(Planning.boulder, 2026, 6, 20)
        let barnard = EquatorialCoordinate(rightAscension: 269.452_075, declination: 4.693_391)
        let motion = ProperMotion(raMilliarcsecondsPerYear: -798.58, decMilliarcsecondsPerYear: 10_328.12)
        let list = targets(30, seed: 24) + [barnard]
        let motions: [ProperMotion?] = [ProperMotion?](repeating: nil, count: list.count - 1) + [motion]
        let ridge = HorizonProfile.constant(12)
        for kind in DarknessKind.allCases {
            for minimum in [0.0, 35.0, Double.nan] {
                let full = NightPlanner.visibility(ofFixed: list, properMotions: motions, during: june, darkness: kind,
                                                   minimumAltitude: minimum, horizon: ridge)
                let cheap = NightPlanner.unobstructedVisibility(ofFixed: list, properMotions: motions, during: june,
                                                                darkness: kind, minimumAltitude: minimum,
                                                                horizon: ridge)
                for index in list.indices {
                    Planning.assertIntervals(cheap[index].intervals, full[index].unobstructedIntervals, accuracy: 2,
                                             "\(kind) \(minimum) \(index)")
                }
            }
        }
    }

    func testTheCheapBatchInASpanAgreesWithTheFullPlannerInTheSpan() throws {
        let summary = try december()
        let observer = summary.observer
        let span = DateInterval(start: summary.night.start.addingTimeInterval(8 * 3_600), duration: 12 * 3_600)
        let list = targets(40, seed: 25)
        let wall = HorizonProfile.flat.setting(to: 30, in: AzimuthRange(from: 60, to: 140))
        let full = NightPlanner.visibility(ofFixed: list, observer: observer, during: span, horizon: wall)
        let cheap = NightPlanner.unobstructedVisibility(ofFixed: list, observer: observer, during: span, horizon: wall)
        for index in list.indices {
            Planning.assertIntervals(cheap[index].intervals, full[index].unobstructedIntervals, accuracy: 2,
                                     "target \(index)")
        }
    }

    func testTargetsWithoutAUsablePositionAreNeverClear() throws {
        let summary = try december()
        let bad = EquatorialCoordinate(rightAscension: .nan, declination: .nan)
        let good = EquatorialCoordinate(rightAscensionHours: 5.9, declination: 7.4)
        let skylines: [HorizonProfile?] = [nil, HorizonProfile.constant(5)]
        for horizon in skylines {
            let results = NightPlanner.unobstructedVisibility(ofFixed: [bad, good], during: summary, horizon: horizon)
            XCTAssertTrue(results[0].intervals.isEmpty)
            XCTAssertEqual(results[0].hours, 0)
            XCTAssertFalse(results[0].isBehindSkyline)
            XCTAssertGreaterThan(results[1].hours, 3)
            XCTAssertTrue(NightPlanner.unobstructedVisibility(ofFixed: [], during: summary, horizon: horizon).isEmpty)
        }
    }

    func testWithoutDarknessNothingIsClear() throws {
        let white = try Planning.summary(Planning.tromso, 2026, 6, 21)
        let results = NightPlanner.unobstructedVisibility(
            ofFixed: [EquatorialCoordinate(rightAscensionHours: 18.6, declination: 38.8)], during: white,
            horizon: Support.truthProfile)
        XCTAssertTrue(results[0].intervals.isEmpty)
        XCTAssertFalse(results[0].isBehindSkyline)
    }

    func testAThousandTargetsThroughTheCheapBatchAreFast() throws {
        let summary = try december()
        let list = targets(1_000, seed: 26)
        var results = [UnobstructedVisibility]()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            results = NightPlanner.unobstructedVisibility(ofFixed: list, during: summary, horizon: Support.truthProfile)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        XCTAssertEqual(results.count, 1_000)
        // About 0.05 s in a release build; an unoptimised debug build is an order of magnitude slower, so the bound
        // only catches a computation that has gone badly wrong.
        XCTAssertLessThan(seconds, 20, "took \(seconds) s")
        XCTAssertGreaterThan(results.filter { $0.hours > 0 }.count, 200)
    }
}

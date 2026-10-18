import XCTest
@testable import LodestarKit

/// The Tonight planner's calls with a `horizon`, against the calls without one.
final class HorizonPlannerTests: XCTestCase {
    private typealias Support = HorizonTestSupport
    private typealias Planning = PlanningTestSupport

    private let flat = HorizonProfile.flat

    private func summary() throws -> NightSummary {
        try Planning.summary(Planning.boulder, 2026, 12, 21)
    }

    private func targets(_ count: Int, seed: UInt64) -> [EquatorialCoordinate] {
        let generator = Support.SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            let rightAscension = 360 * generator.nextDouble()
            let declination = AstroMath.asinDeg(2 * generator.nextDouble() - 1)
            return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        }
    }

    private func assertSameVisibility(_ expected: TargetVisibility, _ actual: TargetVisibility, _ message: String,
                                      line: UInt = #line) {
        XCTAssertEqual(actual.minimumAltitude, expected.minimumAltitude, message, line: line)
        XCTAssertEqual(actual.riseTransitSet.circumstance, expected.riseTransitSet.circumstance, message, line: line)
        let pairs: [(String, Date?, Date?)] = [
            ("rise", expected.riseTransitSet.rise, actual.riseTransitSet.rise),
            ("transit", expected.riseTransitSet.transit, actual.riseTransitSet.transit),
            ("set", expected.riseTransitSet.set, actual.riseTransitSet.set)]
        for (name, wanted, found) in pairs {
            if let wanted {
                if let found {
                    XCTAssertEqual(found.timeIntervalSince(wanted), 0, accuracy: 1, "\(message) \(name)", line: line)
                } else {
                    XCTFail("\(message) \(name) is missing", line: line)
                }
            } else {
                XCTAssertNil(found, "\(message) \(name)", line: line)
            }
        }
        XCTAssertEqual(actual.intervalsAboveMinimum.count, expected.intervalsAboveMinimum.count,
                       "\(message) \(actual)", line: line)
        for (wanted, found) in zip(expected.intervalsAboveMinimum, actual.intervalsAboveMinimum) {
            XCTAssertEqual(found.start.timeIntervalSince(wanted.start), 0, accuracy: 2, "\(message) start", line: line)
            XCTAssertEqual(found.end.timeIntervalSince(wanted.end), 0, accuracy: 2, "\(message) end", line: line)
        }
        XCTAssertEqual(actual.hoursAboveMinimum, expected.hoursAboveMinimum, accuracy: 0.002, message, line: line)
        if let wantedPeak = expected.maxAltitudeDuringDarkness {
            XCTAssertEqual(actual.maxAltitudeDuringDarkness ?? .nan, wantedPeak, accuracy: 0.01, message, line: line)
            XCTAssertNotNil(actual.bestTime, message, line: line)
        } else {
            XCTAssertNil(actual.maxAltitudeDuringDarkness, message, line: line)
            XCTAssertNil(actual.bestTime, message, line: line)
        }
    }

    // MARK: A flat horizon changes nothing

    func testFlatHorizonGivesWhatThePlainPlannerGivesForManyTargets() throws {
        let summary = try summary()
        let list = targets(60, seed: 11)
        let plain = NightPlanner.visibility(ofFixed: list, during: summary)
        let withHorizon = NightPlanner.visibility(ofFixed: list, during: summary, horizon: flat)
        XCTAssertEqual(withHorizon.count, list.count)
        for index in list.indices { assertSameVisibility(plain[index], withHorizon[index], "target \(index)") }
        XCTAssertGreaterThan(withHorizon.filter { $0.hoursAboveMinimum > 0 }.count, 30)
        XCTAssertGreaterThan(withHorizon.filter { $0.hoursAboveMinimum == 0 }.count, 5)
    }

    func testFlatHorizonGivesWhatThePlainPlannerGivesForMoonFreeTimeAndMinimumAltitudes() throws {
        let june = try Planning.summary(Planning.boulder, 2026, 6, 20)
        let list = targets(40, seed: 12)
        for kind in DarknessKind.allCases {
            for minimum in [0.0, 35.0] {
                let plain = NightPlanner.visibility(ofFixed: list, during: june, darkness: kind, minimumAltitude: minimum)
                let withHorizon = NightPlanner.visibility(ofFixed: list, during: june, darkness: kind,
                                                          minimumAltitude: minimum, horizon: flat)
                for index in list.indices {
                    assertSameVisibility(plain[index], withHorizon[index], "\(kind) \(minimum) target \(index)")
                }
            }
        }
    }

    func testFlatHorizonGivesWhatThePlainPlannerGivesForBodies() throws {
        for day in [[2026, 12, 21], [2026, 6, 20], [2026, 1, 3]] {
            let night = try Planning.summary(Planning.boulder, day[0], day[1], day[2])
            for body in SolarSystemBody.allCases {
                let plain = NightPlanner.visibility(of: body, during: night, darkness: .astronomical, minimumAltitude: 10)
                let withHorizon = NightPlanner.visibility(of: body, during: night, darkness: .astronomical,
                                                          minimumAltitude: 10, horizon: flat)
                assertSameVisibility(plain, withHorizon, "\(body) on \(day)")
            }
        }
    }

    func testFlatHorizonGivesWhatThePlainPlannerGivesForAPositionFunctionAndASpan() throws {
        let summary = try summary()
        let observer = summary.observer
        let place = EquatorialCoordinate(rightAscensionHours: 5.5883, declination: -5.39)
        let position: (SkyFrame) -> HorizontalCoordinate = { $0.horizontal(j2000: place, refraction: false) }
        assertSameVisibility(NightPlanner.visibility(of: position, during: summary),
                             NightPlanner.visibility(of: position, during: summary, horizon: flat), "function")
        let span = DateInterval(start: summary.night.start.addingTimeInterval(8 * 3_600), duration: 12 * 3_600)
        assertSameVisibility(NightPlanner.visibility(of: position, observer: observer, during: span),
                             NightPlanner.visibility(of: position, observer: observer, during: span, horizon: flat),
                             "function in a span")
        assertSameVisibility(NightPlanner.visibility(of: .jupiter, observer: observer, during: span),
                             NightPlanner.visibility(of: .jupiter, observer: observer, during: span, horizon: flat),
                             "body in a span")
        let list = [place]
        assertSameVisibility(NightPlanner.visibility(ofFixed: list, observer: observer, during: span)[0],
                             NightPlanner.visibility(ofFixed: list, observer: observer, during: span, horizon: flat)[0],
                             "batch in a span")
    }

    // MARK: A skyline hides things

    func testSkylineRemovesWhatItHidesAndNothingElse() throws {
        let summary = try summary()
        let observer = summary.observer
        let wall = flat.setting(to: 45, in: AzimuthRange(from: 100, to: 260)) // all of the south and part of the east and west
        let list = targets(120, seed: 13)
        let plain = NightPlanner.visibility(ofFixed: list, during: summary)
        let hidden = NightPlanner.visibility(ofFixed: list, during: summary, horizon: wall)
        var shortened = 0
        for index in list.indices {
            XCTAssertLessThanOrEqual(hidden[index].hoursAboveMinimum, plain[index].hoursAboveMinimum + 0.002, "target \(index)")
            for window in hidden[index].intervalsAboveMinimum {
                XCTAssertTrue(plain[index].intervalsAboveMinimum.contains {
                    $0.start.timeIntervalSince(window.start) <= 2 && window.end.timeIntervalSince($0.end) <= 2
                }, "target \(index)")
            }
            if hidden[index].hoursAboveMinimum < plain[index].hoursAboveMinimum - 0.05 { shortened += 1 }
            // The windows are exactly the times above both the planner's minimum and the skyline, found by scanning frames.
            let darkness = summary.darkness(.astronomical)
            for step in 0..<90 {
                let time = darkness[0].start.addingTimeInterval(Double(step) * 420 + 11)
                guard darkness.contains(where: { $0.start <= time && time < $0.end }) else { continue }
                let horizontal = SkyFrame(date: time, observer: observer).horizontal(j2000: list[index], refraction: false)
                let expected = horizontal.altitude >= 20
                    && horizontal.altitude >= HorizonVisibility.thresholdAltitude(
                        skylineAltitude: wall.altitude(at: horizontal.azimuth))
                let found = hidden[index].intervalsAboveMinimum.contains { $0.start <= time && time < $0.end }
                if expected != found {
                    let distance = hidden[index].intervalsAboveMinimum.flatMap { [$0.start, $0.end] }
                        .map { abs($0.timeIntervalSince(time)) }.min() ?? .greatestFiniteMagnitude
                    XCTAssertLessThan(distance, 30, "target \(index) step \(step)")
                }
            }
        }
        XCTAssertGreaterThan(shortened, 10, "\(shortened) targets lose time")
    }

    func testBestTimeIsTheHighestPointWhileTheTargetCanBeSeen() throws {
        let summary = try summary()
        let observer = summary.observer
        // A star on the celestial equator climbs to 50° in the south. Behind a 55° wall from azimuth 120° to 240° it is only
        // seen while it rises in the east below 31° and while it sinks in the west: two windows, separated by its transit.
        let wall = flat.setting(to: 55, in: AzimuthRange(from: 120, to: 240))
        let target = EquatorialCoordinate(rightAscensionHours: 5, declination: 0)
        let plain = NightPlanner.visibility(ofFixed: [target], during: summary)[0]
        let hidden = NightPlanner.visibility(ofFixed: [target], during: summary, horizon: wall)[0]
        XCTAssertLessThan(hidden.hoursAboveMinimum, plain.hoursAboveMinimum)
        XCTAssertGreaterThan(hidden.hoursAboveMinimum, 1)
        XCTAssertEqual(hidden.intervalsAboveMinimum.count, 2, "split by the wall: \(hidden.intervalsAboveMinimum)")
        let best = try XCTUnwrap(hidden.bestTime)
        XCTAssertTrue(hidden.intervalsAboveMinimum.contains { $0.start <= best && best <= $0.end })
        let atBest = SkyFrame(date: best, observer: observer).horizontal(j2000: target, refraction: false)
        XCTAssertEqual(atBest.altitude, try XCTUnwrap(hidden.maxAltitudeDuringDarkness), accuracy: 0.01)
        XCTAssertLessThan(try XCTUnwrap(hidden.maxAltitudeDuringDarkness), try XCTUnwrap(plain.maxAltitudeDuringDarkness) - 3)
        // It is the higher of the two ends of the gap the wall leaves, about 31° high.
        XCTAssertEqual(atBest.altitude, 31, accuracy: 1)
        let ends = hidden.intervalsAboveMinimum.flatMap { [$0.start, $0.end] }
        let altitudes = ends.map { SkyFrame(date: $0, observer: observer).horizontal(j2000: target, refraction: false).altitude }
        XCTAssertEqual(atBest.altitude, altitudes.max() ?? .nan, accuracy: 0.05)
    }

    func testATargetThatIsNeverClearKeepsItsPeakInTheDarkButHasNoWindow() throws {
        let summary = try summary()
        let everywhere = HorizonProfile.constant(45)
        let polaris = EquatorialCoordinate(rightAscension: 37.954_515, declination: 89.264_110)
        let plain = NightPlanner.visibility(ofFixed: [polaris], during: summary)[0]
        let hidden = NightPlanner.visibility(ofFixed: [polaris], during: summary, horizon: everywhere)[0]
        XCTAssertTrue(hidden.intervalsAboveMinimum.isEmpty)
        XCTAssertEqual(hidden.hoursAboveMinimum, 0)
        XCTAssertEqual(hidden.riseTransitSet.circumstance, .alwaysDown)
        XCTAssertNil(hidden.riseTransitSet.rise)
        XCTAssertNil(hidden.riseTransitSet.set)
        // The values describe the highest point in the dark, as without the skyline.
        XCTAssertEqual(try XCTUnwrap(hidden.maxAltitudeDuringDarkness), try XCTUnwrap(plain.maxAltitudeDuringDarkness), accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(hidden.maxAltitudeDuringDarkness), 39)
        XCTAssertNotNil(hidden.bestTime)
    }

    func testSkylineOverridesTheMinimumAltitudeOnlyWhereItIsHigher() throws {
        let summary = try summary()
        // A 30° wall in the south with a 20° minimum: a target in the south needs 30°, one in the north 20°.
        let wall = flat.setting(to: 30, in: AzimuthRange(from: 135, to: 225))
        let list = targets(80, seed: 14)
        let low = NightPlanner.visibility(ofFixed: list, during: summary, horizon: wall)
        let high = NightPlanner.visibility(ofFixed: list, during: summary, minimumAltitude: 30, horizon: wall)
        for index in list.indices {
            XCTAssertLessThanOrEqual(high[index].hoursAboveMinimum, low[index].hoursAboveMinimum + 0.002, "\(index)")
            XCTAssertEqual(high[index].minimumAltitude, 30)
        }
    }

    func testMoonRisingBehindARidgeIsLaterAndTheBodyWindowsFollow() throws {
        let night = try Planning.summary(Planning.boulder, 2026, 6, 24)
        let ridge = HorizonProfile.constant(8)
        let plain = NightPlanner.visibility(of: .moon, during: night, minimumAltitude: 0)
        let behind = NightPlanner.visibility(of: .moon, during: night, minimumAltitude: 0, horizon: ridge)
        let flatRise = try XCTUnwrap(plain.riseTransitSet.rise)
        let clear = try XCTUnwrap(behind.riseTransitSet.rise)
        XCTAssertGreaterThan(clear.timeIntervalSince(flatRise), 20 * 60)
        XCTAssertLessThanOrEqual(behind.hoursAboveMinimum, plain.hoursAboveMinimum)
        // The same call from the visibility object.
        let direct = HorizonVisibility(profile: ridge).riseTransitSet(for: .moon, observer: night.observer, within: night.night)
        XCTAssertEqual(try XCTUnwrap(direct.rise).timeIntervalSince(clear), 0, accuracy: 0.01)
    }

    // MARK: Edge cases

    func testNoDarknessGivesNoPeakButStillTheEvents() throws {
        let white = try Planning.summary(Planning.tromso, 2026, 6, 21)
        XCTAssertFalse(white.hasAstronomicalDarkness)
        let target = EquatorialCoordinate(rightAscensionHours: 18.6, declination: 38.8)
        let result = NightPlanner.visibility(ofFixed: [target], during: white, horizon: Support.truthProfile)[0]
        XCTAssertNil(result.maxAltitudeDuringDarkness)
        XCTAssertNil(result.bestTime)
        XCTAssertTrue(result.intervalsAboveMinimum.isEmpty)
        let plain = NightPlanner.visibility(ofFixed: [target], during: white)[0]
        XCTAssertEqual(result.riseTransitSet.circumstance, plain.riseTransitSet.circumstance)
    }

    func testTargetsWithoutAUsablePositionNeverRise() throws {
        let summary = try summary()
        let bad = EquatorialCoordinate(rightAscension: .nan, declination: .nan)
        let good = EquatorialCoordinate(rightAscensionHours: 5.9, declination: 7.4)
        let results = NightPlanner.visibility(ofFixed: [bad, good], during: summary, horizon: Support.truthProfile)
        XCTAssertEqual(results[0].riseTransitSet.circumstance, .alwaysDown)
        XCTAssertNil(results[0].maxAltitudeDuringDarkness)
        XCTAssertNil(results[0].bestTime)
        XCTAssertTrue(results[0].intervalsAboveMinimum.isEmpty)
        XCTAssertEqual(results[0].minimumAltitude, NightPlanner.defaultMinimumAltitude)
        XCTAssertGreaterThan(results[1].hoursAboveMinimum, 0)
        XCTAssertEqual(NightPlanner.visibility(ofFixed: [bad], during: summary, minimumAltitude: 30, horizon: flat)[0].minimumAltitude, 30)
        XCTAssertEqual(NightPlanner.visibility(ofFixed: [good], during: summary, minimumAltitude: .nan, horizon: flat)[0].minimumAltitude, 20)
        XCTAssertTrue(NightPlanner.visibility(ofFixed: [], during: summary, horizon: flat).isEmpty)
    }

    func testProperMotionsAreUsed() throws {
        let summary = try summary()
        let barnard = EquatorialCoordinate(rightAscension: 269.452_075, declination: 4.693_391)
        let motion = ProperMotion(raMilliarcsecondsPerYear: -798.58, decMilliarcsecondsPerYear: 10_328.12)
        let with = NightPlanner.visibility(ofFixed: [barnard], properMotions: [motion], during: summary, horizon: flat)[0]
        let without = NightPlanner.visibility(ofFixed: [barnard], during: summary, horizon: flat)[0]
        // 26 years of 10″ per year is 4.5′ towards the north: at 40°N the rise of a star at +4.7° moves by 17 s.
        let shift = abs(try XCTUnwrap(with.riseTransitSet.rise).timeIntervalSince(try XCTUnwrap(without.riseTransitSet.rise)))
        XCTAssertTrue(shift > 10 && shift < 30, "\(shift) s")
        let plain = NightPlanner.visibility(ofFixed: [barnard], properMotions: [motion], during: summary)[0]
        XCTAssertEqual(try XCTUnwrap(with.riseTransitSet.rise).timeIntervalSince(try XCTUnwrap(plain.riseTransitSet.rise)),
                       0, accuracy: 1)
    }

    /// Seconds allowed for 700 targets through the Tonight planner. A release build needs about a third of a second
    /// (the requirement is three); an unoptimised debug build is an order of magnitude slower, so its bound only
    /// catches a calculation that has gone badly wrong.
    private static let sevenHundredTargetsLimit: Double = {
        #if DEBUG
        return 60
        #else
        return 3
        #endif
    }()

    func testSeveralHundredTargetsThroughTheTonightPlannerAreFast() throws {
        let summary = try summary()
        let list = targets(700, seed: 700)
        let skyline = Support.truthProfile
        let clock = ContinuousClock()
        var results = [TargetVisibility]()
        let elapsed = clock.measure {
            results = NightPlanner.visibility(ofFixed: list, during: summary, horizon: skyline)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        XCTAssertEqual(results.count, 700)
        // About 1 ms per target; the plain planner needs a few hundredths of a second for a thousand.
        XCTAssertLessThan(seconds, Self.sevenHundredTargetsLimit, "took \(seconds) s")
    }
}

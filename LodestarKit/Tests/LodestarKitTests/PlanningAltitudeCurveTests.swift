import XCTest
@testable import LodestarKit

/// `NightPlanner.altitudeCurve`: the sample grid and the altitudes and azimuths it reports.
final class PlanningAltitudeCurveTests: XCTestCase {
    private typealias Support = PlanningTestSupport

    private let boulder = Support.boulder
    private let orionNebula = EquatorialCoordinate(rightAscension: 83.822_083, declination: -5.391_111)

    private func night(_ year: Int, _ month: Int, _ day: Int) throws -> DateInterval {
        let zone = try boulder.timeZone()
        return DateInterval(start: try Support.localNoon(year, month, day, in: zone),
                            end: try Support.localNoon(year, month, day + 1, in: zone))
    }

    // MARK: The grid

    func testSamplesAreEvenlySpacedFromTheStartToTheEnd() throws {
        let interval = try night(2026, 10, 25)
        let curve = NightPlanner.altitudeCurve(observer: boulder.observer, interval: interval) { _ in
            HorizontalCoordinate(azimuth: 10, altitude: 20)
        }
        XCTAssertEqual(curve.count, 145)
        XCTAssertEqual(curve.first?.date, interval.start)
        XCTAssertEqual(curve.last?.date, interval.end)
        for (earlier, later) in zip(curve, curve.dropFirst()) {
            XCTAssertEqual(later.date.timeIntervalSince(earlier.date), 600, accuracy: 1e-6)
        }
    }

    func testTheSpacingShrinksSoNoGapExceedsTheStep() throws {
        let interval = try night(2026, 10, 25)
        // 24 h with at most 7 h between samples: four gaps of 6 h.
        let curve = NightPlanner.altitudeCurve(observer: boulder.observer, interval: interval, step: 7 * 3_600) { _ in
            HorizontalCoordinate(azimuth: 0, altitude: 0)
        }
        XCTAssertEqual(curve.count, 5)
        XCTAssertEqual(curve[1].date.timeIntervalSince(curve[0].date), 6 * 3_600, accuracy: 1e-6)
        XCTAssertEqual(curve.last?.date, interval.end)

        let coarse = NightPlanner.altitudeCurve(observer: boulder.observer, interval: interval, step: 1e9) { _ in
            HorizontalCoordinate(azimuth: 0, altitude: 0)
        }
        XCTAssertEqual(coarse.map(\.date), [interval.start, interval.end])
    }

    func testUnusableStepsAreReplaced() throws {
        let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 6_000)
        func count(_ step: TimeInterval) -> Int {
            NightPlanner.altitudeCurve(observer: boulder.observer, interval: interval, step: step) { _ in
                HorizontalCoordinate(azimuth: 0, altitude: 0)
            }.count
        }
        XCTAssertEqual(count(600), 11)
        XCTAssertEqual(count(0), 11, "not positive: 10 minutes")
        XCTAssertEqual(count(-30), 11)
        XCTAssertEqual(count(.nan), 11)
        XCTAssertEqual(count(.infinity), 11)
        XCTAssertEqual(count(0.2), 6_001, "below a second: one second")
        XCTAssertEqual(count(1), 6_001)
    }

    func testAnEmptyIntervalGivesOneSample() {
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let curve = NightPlanner.altitudeCurve(observer: boulder.observer, interval: DateInterval(start: instant, duration: 0)) {
            $0.horizontal(of: .sun, refraction: false)
        }
        XCTAssertEqual(curve.map(\.date), [instant])
    }

    func testTheNumberOfSamplesIsCapped() {
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 86_400, step: 600), 144)
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 86_400, step: 1), 86_400)
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 0, step: 600), 0)
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 1e12, step: 1), NightPlanner.maximumCurveSampleCount - 1)
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 365 * 86_400, step: 0.001), NightPlanner.maximumCurveSampleCount - 1)
        XCTAssertEqual(NightPlanner.curveGapCount(duration: 1e300, step: 600), NightPlanner.maximumCurveSampleCount - 1)
    }

    func testAHugeRequestStillReturnsOnlyTheCappedNumberOfSamples() throws {
        let month = DateInterval(start: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 30 * 86_400)
        let curve = NightPlanner.altitudeCurve(observer: boulder.observer, interval: month, step: 1) { _ in
            HorizontalCoordinate(azimuth: 0, altitude: 0)
        }
        XCTAssertEqual(curve.count, NightPlanner.maximumCurveSampleCount)
        XCTAssertEqual(curve.first?.date, month.start)
        XCTAssertEqual(curve.last?.date, month.end)
        XCTAssertEqual(curve[1].date.timeIntervalSince(curve[0].date), month.duration / 99_999, accuracy: 1e-6)
    }

    // MARK: The values

    func testThePositionFunctionSeesAFrameForEachSampleInstant() throws {
        let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: 800_000_000), duration: 3_600)
        var seen = [Date]()
        let curve = NightPlanner.altitudeCurve(observer: boulder.observer, interval: interval, step: 900) { frame in
            seen.append(frame.date)
            XCTAssertEqual(frame.observer, self.boulder.observer)
            return HorizontalCoordinate(azimuth: 370, altitude: Double(seen.count))
        }
        XCTAssertEqual(seen.count, 5)
        for (sample, frameDate) in zip(curve, seen) {
            XCTAssertEqual(frameDate.timeIntervalSince(sample.date), 0, accuracy: 1e-3)
        }
        XCTAssertEqual(curve.map(\.date), (0...4).map { interval.start.addingTimeInterval(Double($0) * 900) })
        XCTAssertEqual(curve.map(\.altitude), [1, 2, 3, 4, 5])
        XCTAssertEqual(curve.map(\.azimuth), Array(repeating: 10, count: 5), "azimuths come out in [0, 360)")
    }

    func testFixedObjectCurveMatchesDirectFrames() throws {
        let interval = try night(2026, 10, 25)
        let motion = ProperMotion(raMilliarcsecondsPerYear: 1_000, decMilliarcsecondsPerYear: -2_000)
        for properMotion in [nil, motion] {
            let curve = NightPlanner.altitudeCurve(ofJ2000: orionNebula, properMotion: properMotion,
                                                   observer: boulder.observer, interval: interval)
            XCTAssertEqual(curve.count, 145)
            for sample in curve {
                let expected = SkyFrame(date: sample.date, observer: boulder.observer)
                    .horizontal(j2000: orionNebula, properMotion: properMotion, refraction: false)
                XCTAssertEqual(sample.altitude, expected.altitude, accuracy: 1e-9)
                XCTAssertEqual(sample.azimuth, expected.azimuth, accuracy: 1e-9)
            }
        }
        // Proper motion of two arcseconds a year moves the target by about a minute of arc by 2026.
        let still = NightPlanner.altitudeCurve(ofJ2000: orionNebula, observer: boulder.observer, interval: interval)
        let moving = NightPlanner.altitudeCurve(ofJ2000: orionNebula, properMotion: motion, observer: boulder.observer,
                                                interval: interval)
        XCTAssertGreaterThan(zip(still, moving).map { abs($0.altitude - $1.altitude) }.max() ?? 0, 0.01)
    }

    func testBodyCurveMatchesDirectFramesAndIsGeometric() throws {
        let interval = try night(2026, 10, 25)
        for body in [SolarSystemBody.sun, .moon, .saturn] {
            let curve = NightPlanner.altitudeCurve(of: body, observer: boulder.observer, interval: interval, step: 1_800)
            XCTAssertEqual(curve.count, 49)
            for sample in curve {
                let expected = SkyFrame(date: sample.date, observer: boulder.observer).horizontal(of: body, refraction: false)
                XCTAssertEqual(sample.altitude, expected.altitude, accuracy: 1e-9, body.displayName)
                XCTAssertEqual(sample.azimuth, expected.azimuth, accuracy: 1e-9, body.displayName)
            }
        }
    }

    func testSunCurveShowsTheNightTheTwilightCalculatorFinds() throws {
        let zone = try boulder.timeZone()
        let noon = try Support.localNoon(2026, 10, 25, in: zone)
        let twilight = TwilightCalculator.night(startingOn: noon, observer: boulder.observer, timeZone: zone)
        let curve = NightPlanner.altitudeCurve(of: .sun, observer: boulder.observer, interval: twilight.interval)
        let lowest = try XCTUnwrap(curve.min { $0.altitude < $1.altitude })
        XCTAssertEqual(lowest.date.timeIntervalSince(twilight.solarMidnight), 0, accuracy: 600)
        XCTAssertEqual(lowest.altitude, twilight.sunAltitudeAtMidnight, accuracy: 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(curve.first).altitude, 20, "the curve starts at local noon")
        // The curve is above −18° at every sample outside the astronomical night and below inside it.
        let dark = try XCTUnwrap(twilight.astronomicalNight)
        for sample in curve where abs(sample.date.timeIntervalSince(dark.start)) > 600
            && abs(sample.date.timeIntervalSince(dark.end)) > 600 {
            XCTAssertEqual(sample.altitude < TwilightCalculator.astronomicalAltitude, dark.contains(sample.date))
        }
        XCTAssertTrue(curve.allSatisfy { (0..<360).contains($0.azimuth) && (-90...90).contains($0.altitude) })
    }

    func testMoonCurveCrossesTheHorizonWhenTheSummarySaysItRisesAndSets() throws {
        let summary = try Support.summary(boulder, 2026, 6, 21)
        let curve = NightPlanner.altitudeCurve(of: .moon, observer: boulder.observer, interval: summary.night, step: 60)
        let moonSet = try XCTUnwrap(summary.moon.riseTransitSet.set)
        let before = try XCTUnwrap(curve.last { $0.date < moonSet.addingTimeInterval(-120) })
        let after = try XCTUnwrap(curve.first { $0.date > moonSet.addingTimeInterval(120) })
        XCTAssertGreaterThan(before.altitude, -0.5)
        XCTAssertLessThan(after.altitude, -0.5)
    }
}

import XCTest
@testable import LodestarKit

final class RiseSetCalculatorTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func date(_ seconds: Double) -> Date { origin.addingTimeInterval(seconds) }

    /// 40 sin(2π t/day) + 10 degrees, a smooth day-long curve with known crossings.
    private func sinusoid() -> (Date) -> Double {
        { time in 40 * sin(2 * .pi * time.timeIntervalSince(self.origin) / 86_400) + 10 }
    }

    // MARK: Generic crossings

    func testCrossingsOfASinusoidAreFoundExactly() {
        let threshold = RiseSetCalculator.standardHorizonAltitude
        let interval = DateInterval(start: origin, duration: 2 * 86_400)
        let crossings = RiseSetCalculator.crossings(of: sinusoid(), threshold: threshold, within: interval, tolerance: 0.001)

        // sin θ = (h₀ − 10)/40. The curve starts at 10°, above the threshold, so it sets first (at
        // θ = π − θ₁) and rises again (at 2π + θ₁), twice in two days.
        let theta = asin((threshold - 10) / 40)
        let setting = (Double.pi - theta) / (2 * .pi) * 86_400
        let rising = (2 * Double.pi + theta) / (2 * .pi) * 86_400
        XCTAssertEqual(crossings.map(\.kind), [.setting, .rising, .setting, .rising])
        let times = crossings.map { $0.time.timeIntervalSince(origin) }
        XCTAssertEqual(times[0], setting, accuracy: 0.01)
        XCTAssertEqual(times[1], rising, accuracy: 0.01)
        XCTAssertEqual(times[2], setting + 86_400, accuracy: 0.01)
        XCTAssertEqual(times[3], rising + 86_400, accuracy: 0.01)
    }

    func testCrossingsDependOnTheThresholdAndReportTheirKind() {
        let interval = DateInterval(start: origin, duration: 86_400)
        let curve = sinusoid()
        // Above the maximum (50°) or below the minimum (−30°) nothing crosses.
        XCTAssertTrue(RiseSetCalculator.crossings(of: curve, threshold: 51, within: interval).isEmpty)
        XCTAssertTrue(RiseSetCalculator.crossings(of: curve, threshold: -31, within: interval).isEmpty)
        // The curve starts at 10° and rises first: a threshold of 30° is crossed up then down.
        let crossings = RiseSetCalculator.crossings(of: curve, threshold: 30, within: interval, tolerance: 0.001)
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting])
        let theta = asin(0.5)
        XCTAssertEqual(crossings[0].time.timeIntervalSince(origin), theta / (2 * .pi) * 86_400, accuracy: 0.01)
        XCTAssertEqual(crossings[1].time.timeIntervalSince(origin), (Double.pi - theta) / (2 * .pi) * 86_400, accuracy: 0.01)
    }

    func testCulminationsAreTheLocalMaxima() {
        let interval = DateInterval(start: origin, duration: 3 * 86_400)
        let culminations = RiseSetCalculator.upperCulminations(of: sinusoid(), within: interval, tolerance: 0.001)
        XCTAssertEqual(culminations.count, 3)
        for (index, culmination) in culminations.enumerated() {
            XCTAssertEqual(culmination.time.timeIntervalSince(origin), 21_600 + Double(index) * 86_400, accuracy: 0.05)
            XCTAssertEqual(culmination.altitude, 50, accuracy: 1e-9)
        }
    }

    func testCulminationNearTheEndOfTheIntervalIsFound() {
        // The maximum lies 2 minutes before the end, between the last two samples; a window that
        // ends just after the peak, or starts just before it, must still report it.
        let peakTime = 21_600.0
        let curve = sinusoid()
        let endsJustAfter = DateInterval(start: date(peakTime - 4 * 3600), end: date(peakTime + 120))
        XCTAssertEqual(RiseSetCalculator.upperCulminations(of: curve, within: endsJustAfter).count, 1)
        let startsJustBefore = DateInterval(start: date(peakTime - 120), end: date(peakTime + 4 * 3600))
        XCTAssertEqual(RiseSetCalculator.upperCulminations(of: curve, within: startsJustBefore).count, 1)
        // A window that holds only the rising or only the falling part has no maximum inside.
        let rising = DateInterval(start: origin, end: date(peakTime - 60))
        XCTAssertTrue(RiseSetCalculator.upperCulminations(of: curve, within: rising).isEmpty)
        let falling = DateInterval(start: date(peakTime + 60), end: date(70_000))
        XCTAssertTrue(RiseSetCalculator.upperCulminations(of: curve, within: falling).isEmpty)
    }

    func testBriefExcursionBetweenSamplesIsStillFound() {
        // The curve peaks 0.02° above the threshold for about 8.6 minutes, centred between two samples
        // 10 minutes apart that both lie below it.
        let center = 1_800.0
        let bump: (Date) -> Double = { current in
            let offset = current.timeIntervalSince(self.origin) - center
            return 0.02 - 3e-7 * offset * offset
        }
        let interval = DateInterval(start: origin, duration: 3 * 3600)
        let found = RiseSetCalculator.crossings(of: bump, threshold: 0, within: interval, tolerance: 0.001)
        let halfWidth = (0.02 / 3e-7).squareRoot()
        XCTAssertEqual(found.map(\.kind), [.rising, .setting])
        XCTAssertEqual(found[0].time.timeIntervalSince(origin), center - halfWidth, accuracy: 0.05)
        XCTAssertEqual(found[1].time.timeIntervalSince(origin), center + halfWidth, accuracy: 0.05)

        // The mirror image: a dip of 0.02° below the threshold between samples that both lie above it.
        let dipFound = RiseSetCalculator.crossings(of: { -bump($0) }, threshold: 0, within: interval, tolerance: 0.001)
        XCTAssertEqual(dipFound.map(\.kind), [.setting, .rising])
        XCTAssertEqual(dipFound[0].time.timeIntervalSince(origin), center - halfWidth, accuracy: 0.05)
        XCTAssertEqual(dipFound[1].time.timeIntervalSince(origin), center + halfWidth, accuracy: 0.05)

        // A bump that stays 0.02° short of the threshold produces nothing.
        XCTAssertTrue(RiseSetCalculator.crossings(of: { bump($0) - 0.04 }, threshold: 0, within: interval).isEmpty)
    }

    // MARK: Generic rise/transit/set

    func testRiseTransitSetOfASinusoid() throws {
        let threshold = 0.0
        let interval = DateInterval(start: origin, duration: 86_400)
        let result = RiseSetCalculator.riseTransitSet(of: sinusoid(), threshold: threshold, within: interval)
        XCTAssertEqual(result.circumstance, .normal)
        let theta = asin((threshold - 10) / 40)
        // The curve starts above the threshold, so it sets first and rises later in the window.
        let setting = (Double.pi - theta) / (2 * .pi) * 86_400
        let rising = (2 * Double.pi + theta) / (2 * .pi) * 86_400
        XCTAssertEqual(try XCTUnwrap(result.set).timeIntervalSince(origin), setting, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(result.rise).timeIntervalSince(origin), rising, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(result.transit).timeIntervalSince(origin), 21_600, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(result.transitAltitude), 50, accuracy: 1e-6)
    }

    func testAlwaysUpAndAlwaysDown() throws {
        let interval = DateInterval(start: origin, duration: 86_400)
        let up = RiseSetCalculator.riseTransitSet(of: sinusoid(), threshold: -35, within: interval)
        XCTAssertEqual(up.circumstance, .alwaysUp)
        XCTAssertNil(up.rise)
        XCTAssertNil(up.set)
        XCTAssertEqual(try XCTUnwrap(up.transitAltitude), 50, accuracy: 1e-6)
        let down = RiseSetCalculator.riseTransitSet(of: sinusoid(), threshold: 60, within: interval)
        XCTAssertEqual(down.circumstance, .alwaysDown)
        XCTAssertNil(down.rise)
        XCTAssertNil(down.set)
        // The culmination is reported even though the target never clears the horizon.
        XCTAssertEqual(try XCTUnwrap(down.transitAltitude), 50, accuracy: 1e-6)
    }

    func testOnlyTheFirstOfRepeatedEventsIsReported() throws {
        let interval = DateInterval(start: origin, duration: 3 * 86_400)
        let result = RiseSetCalculator.riseTransitSet(of: sinusoid(), threshold: 0, within: interval)
        let all = RiseSetCalculator.crossings(of: sinusoid(), threshold: 0, within: interval)
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(result.set, all.first { $0.kind == .setting }?.time)
        XCTAssertEqual(result.rise, all.first { $0.kind == .rising }?.time)
        XCTAssertEqual(try XCTUnwrap(result.transit).timeIntervalSince(origin), 21_600, accuracy: 0.5)
    }

    // MARK: Degenerate input

    func testDegenerateIntervalsAndFunctions() {
        let curve = sinusoid()
        let empty = DateInterval(start: origin, duration: 0)
        XCTAssertTrue(RiseSetCalculator.crossings(of: curve, threshold: 0, within: empty).isEmpty)
        XCTAssertTrue(RiseSetCalculator.upperCulminations(of: curve, within: empty).isEmpty)
        let point = RiseSetCalculator.riseTransitSet(of: curve, threshold: 0, within: empty)
        XCTAssertEqual(point.circumstance, .alwaysUp)
        XCTAssertNil(point.transit)

        // Values that are not finite are skipped rather than trapping or producing crossings.
        let broken: (Date) -> Double = { _ in .nan }
        let interval = DateInterval(start: origin, duration: 86_400)
        XCTAssertTrue(RiseSetCalculator.crossings(of: broken, threshold: 0, within: interval).isEmpty)
        XCTAssertTrue(RiseSetCalculator.upperCulminations(of: broken, within: interval).isEmpty)
        let partlyBroken: (Date) -> Double = { current in
            current.timeIntervalSince(self.origin) < 3_000 ? .nan : curve(current)
        }
        let crossings = RiseSetCalculator.crossings(of: partlyBroken, threshold: 30, within: interval)
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting])
    }

    func testSampleIntervalAndToleranceAreClamped() {
        let interval = DateInterval(start: origin, duration: 3 * 3600)
        // Period 6000 s: rising at 192 s and 6192 s, setting at 2808 s and 8808 s.
        let curve: (Date) -> Double = { current in 25 * sin(2 * .pi * current.timeIntervalSince(self.origin) / 6_000) }
        let reference = RiseSetCalculator.crossings(of: curve, threshold: 5, within: interval, tolerance: 0.001)
        XCTAssertEqual(reference.map(\.kind), [.rising, .setting, .rising, .setting])
        // Absurd arguments fall back to sensible values instead of failing.
        for step in [-5.0, 0, .nan, .infinity, 1e12] {
            let result = RiseSetCalculator.crossings(of: curve, threshold: 5, within: interval, sampleInterval: step,
                                                     tolerance: 0.001)
            XCTAssertEqual(result.map(\.kind), reference.map(\.kind), "step \(step)")
        }
        let loose = RiseSetCalculator.crossings(of: curve, threshold: 5, within: interval, tolerance: .nan)
        XCTAssertEqual(loose.count, 4)
        XCTAssertEqual(loose[0].time.timeIntervalSince(origin), reference[0].time.timeIntervalSince(origin), accuracy: 0.5)
    }

    func testVeryLongIntervalsAreSampledCoarsely() {
        // At most 100 000 samples whatever the interval: a thousand years completes quickly.
        let interval = DateInterval(start: origin, duration: 1_000 * 365.25 * 86_400)
        let curve: (Date) -> Double = { current in sin(current.timeIntervalSince(self.origin) / 3e9) }
        let crossings = RiseSetCalculator.crossings(of: curve, threshold: 0, within: interval)
        XCTAssertEqual(crossings.map(\.kind), [.setting, .rising, .setting])
        XCTAssertEqual(crossings[0].time.timeIntervalSince(origin), Double.pi * 3e9, accuracy: 1_000)
    }

    func testAbsurdDatesAreHandledWithoutTrapping() {
        let observer = Observer(location: GeographicLocation(latitude: 45, longitude: 10))
        for seconds in [1e300, -1e300, 1e18, -1e18, 1e14] {
            let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: seconds), duration: 86_400)
            XCTAssertTrue(RiseSetCalculator.crossings(of: .sun, observer: observer, within: interval).isEmpty)
            XCTAssertTrue(RiseSetCalculator.upperCulminations(of: .moon, observer: observer, within: interval).isEmpty)
            let star = EquatorialCoordinate(rightAscension: 10, declination: 20)
            XCTAssertTrue(RiseSetCalculator.crossings(ofJ2000: star, observer: observer, within: interval).isEmpty)
            let summary = RiseSetCalculator.riseTransitSet(for: .jupiter, observer: observer, within: interval)
            XCTAssertNil(summary.rise)
            XCTAssertNil(summary.transit)
        }
        let night = TwilightCalculator.night(startingOn: Date(timeIntervalSinceReferenceDate: 1e300), observer: observer,
                                             timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        XCTAssertEqual(night.interval.duration, 86_400, accuracy: 1)
        let nan = TwilightCalculator.night(startingOn: Date(timeIntervalSinceReferenceDate: .nan), observer: observer,
                                           timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        XCTAssertEqual(nan.interval.duration, 86_400, accuracy: 1)
    }

    // MARK: Meeus example 15.a

    /// Venus at Boston (φ = +42°20′, λ = 71°05′ W) on 1988 March 20: the book finds
    /// rising 12h25m26s, transit 19h40m31s and setting 2h54m40s UT; DE440s gives 12:25:26,
    /// 19:40:39 and 02:54:39, and a transit altitude of 66.424°.
    func testVenusRiseTransitSetMeeusExample15a() throws {
        let boston = Observer(location: GeographicLocation(latitude: 42.3333, longitude: -71.0833))
        let midnight = JulianDate(ut: JulianDate.julianDay(year: 1988, month: 3, day: 20))
        let start = midnight.date
        let day = DateInterval(start: start, duration: 86_400)
        let result = RiseSetCalculator.riseTransitSet(for: .venus, observer: boston, within: day)
        XCTAssertEqual(result.circumstance, .normal)
        let hours = { (date: Date?) throws -> Double in try XCTUnwrap(date).timeIntervalSince(start) / 3600 }
        XCTAssertEqual(try hours(result.rise), 12 + 25.43 / 60, accuracy: 10.0 / 3600)
        XCTAssertEqual(try hours(result.transit), 19 + 40.65 / 60, accuracy: 15.0 / 3600)
        XCTAssertEqual(try hours(result.set), 2 + 54.66 / 60, accuracy: 10.0 / 3600)
        XCTAssertEqual(try XCTUnwrap(result.transitAltitude), 66.424, accuracy: 0.01)
    }

    // MARK: Fixed objects

    func testStarRisingTwiceInOneWindow() throws {
        // A star returns to the same place in a sidereal day, 3 min 56 s short of 24 hours, so a
        // window that starts just before it rises holds two risings.
        let observer = Observer(location: GeographicLocation(latitude: 0, longitude: 0))
        let star = EquatorialCoordinate(rightAscension: 101.28715539, declination: -16.71611582)
        let probe = DateInterval(start: origin, duration: 86_400)
        let firstRise = try XCTUnwrap(RiseSetCalculator.riseTransitSet(forJ2000: star, observer: observer, within: probe).rise)
        let window = DateInterval(start: firstRise.addingTimeInterval(-60), duration: 86_400)
        let crossings = RiseSetCalculator.crossings(ofJ2000: star, observer: observer, within: window)
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting, .rising])
        let siderealDay = 86_164.0905
        XCTAssertEqual(crossings[2].time.timeIntervalSince(crossings[0].time), siderealDay, accuracy: 1.0)
        let culminations = RiseSetCalculator.upperCulminations(ofJ2000: star, observer: observer, within: window)
        XCTAssertEqual(culminations.count, 1)
        let first = RiseSetCalculator.riseTransitSet(forJ2000: star, observer: observer, within: window)
        XCTAssertEqual(first.rise, crossings[0].time)
        XCTAssertEqual(first.set, crossings[1].time)
        XCTAssertEqual(first.circumstance, .normal)
        // At the equator a star of declination −16.7° culminates at altitude 90° − 16.7°.
        XCTAssertEqual(try XCTUnwrap(first.transitAltitude), 90 - 16.716, accuracy: 0.06)
    }

    func testCircumpolarAndNeverRisingStars() throws {
        let observer = Observer(location: GeographicLocation(latitude: 50, longitude: 8))
        let window = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 86_400)
        let polaris = EquatorialCoordinate(rightAscension: 37.95451535, declination: 89.26410951)
        let circumpolar = RiseSetCalculator.riseTransitSet(forJ2000: polaris, observer: observer, within: window)
        XCTAssertEqual(circumpolar.circumstance, .alwaysUp)
        XCTAssertNil(circumpolar.rise)
        XCTAssertNil(circumpolar.set)
        // Its upper culmination is 90° − |φ − δ| above the horizon, with δ the apparent declination.
        let frame = SkyFrame(date: window.start, observer: observer)
        let apparent = frame.apparentPlace(j2000: polaris, properMotion: nil)
        XCTAssertEqual(try XCTUnwrap(circumpolar.transitAltitude), 90 - (apparent.declination - 50), accuracy: 0.005)

        let acrux = EquatorialCoordinate(rightAscension: 186.64956584, declination: -63.09909166)
        let invisible = RiseSetCalculator.riseTransitSet(forJ2000: acrux, observer: observer, within: window)
        XCTAssertEqual(invisible.circumstance, .alwaysDown)
        XCTAssertNil(invisible.rise)
        XCTAssertNil(invisible.set)
        XCTAssertNotNil(invisible.transit)
    }

    func testProperMotionMovesTheEventTimes() throws {
        let observer = Observer(location: GeographicLocation(latitude: 45, longitude: 0))
        let star = EquatorialCoordinate(rightAscension: 213.9153, declination: 19.1824)
        let window = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 86_400)
        let still = try XCTUnwrap(RiseSetCalculator.riseTransitSet(forJ2000: star, observer: observer, within: window).transit)
        // 100 arcseconds per year in right ascension over 26.7 years: 2670″ = 178 s of time.
        let motion = ProperMotion(raMilliarcsecondsPerYear: 100_000 * AstroMath.cosDeg(19.1824), decMilliarcsecondsPerYear: 0)
        let movingStar = RiseSetCalculator.riseTransitSet(forJ2000: star, properMotion: motion, observer: observer, within: window)
        let moving = try XCTUnwrap(movingStar.transit)
        XCTAssertGreaterThan(moving.timeIntervalSince(still), 170)
        XCTAssertLessThan(moving.timeIntervalSince(still), 186)
    }

    // MARK: Solar-system bodies

    func testPolarDayAndNightForTheSun() throws {
        let tromso = Observer(location: GeographicLocation(latitude: 69.65, longitude: 18.96))
        let midsummer = DateInterval(start: Date(timeIntervalSince1970: 1_782_000_000), duration: 86_400)   // 2026-06-21
        let sunUp = RiseSetCalculator.riseTransitSet(for: .sun, observer: tromso, within: midsummer)
        XCTAssertEqual(sunUp.circumstance, .alwaysUp)
        XCTAssertNil(sunUp.rise)
        XCTAssertNil(sunUp.set)
        // Culmination at 90° − (69.65° − 23.44°) = 43.8°; the lowest point is 3.0° above the horizon.
        XCTAssertEqual(try XCTUnwrap(sunUp.transitAltitude), 43.8, accuracy: 0.2)

        let midwinter = DateInterval(start: Date(timeIntervalSince1970: 1_797_000_000), duration: 86_400)   // 2026-12-14
        let sunDown = RiseSetCalculator.riseTransitSet(for: .sun, observer: tromso, within: midwinter)
        XCTAssertEqual(sunDown.circumstance, .alwaysDown)
        XCTAssertLessThan(try XCTUnwrap(sunDown.transitAltitude), -0.8333)
    }

    func testMoonRisesBetweenTheTwoDefinitionsOfItsHorizon() throws {
        // The event is the upper limb at the horizon (centre at −0.5667° − semi-diameter, seen from the
        // surface). Meeus' threshold 0.7275π − 0.5667° applies to the geocentric altitude of the
        // centre and gives the same instants to within seconds.
        let observer = Observer(location: GeographicLocation(latitude: 48.2, longitude: 16.4, elevation: 200))
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 2 * 86_400)
        let events = RiseSetCalculator.crossings(of: .moon, observer: observer, within: interval)
        XCTAssertGreaterThanOrEqual(events.count, 3)

        let geocentricMargin: (Date) -> Double = { date in
            let frame = SkyFrame(date: date, observer: observer)
            let state = frame.state(of: .moon)
            let direction = frame.equatorialOfDateToHorizontal * (frame.precessionNutationMatrix * state.geocentricJ2000)
            let parallax = AstroMath.asinDeg(SkyFrame.earthEquatorialRadiusKilometers / state.distanceKilometers)
            return HorizontalCoordinate(vector: direction).altitude - (0.7275 * parallax - 0.5667)
        }
        let meeus = RiseSetCalculator.crossings(of: geocentricMargin, threshold: 0, within: interval)
        XCTAssertEqual(meeus.map(\.kind), events.map(\.kind))
        for (mine, theirs) in zip(events, meeus) {
            XCTAssertEqual(mine.time.timeIntervalSince(theirs.time), 0, accuracy: 15)
        }
    }

    func testBodyEvaluatorMatchesADirectSkyFrameComputation() {
        // The searches use cached frames and interpolated ephemerides; they agree with a fresh
        // SkyFrame to a few hundredths of an arcsecond.
        let observer = Observer(location: GeographicLocation(latitude: -33.9, longitude: 151.2, elevation: 30))
        let start = Date(timeIntervalSince1970: 1_790_000_000).timeIntervalSinceReferenceDate
        for body in SolarSystemBody.allCases {
            let sampler = RiseSetCalculator.Sampler(target: .body(body), observer: observer)
            for step in 0..<60 {
                let time = start + Double(step) * 1_777.7
                let direct = SkyFrame(date: Date(timeIntervalSinceReferenceDate: time), observer: observer)
                    .horizontal(of: body, refraction: false).altitude
                XCTAssertEqual(sampler.sample(at: time).centreAltitude, direct, accuracy: 2e-5, "\(body) at step \(step)")
            }
        }
        let star = EquatorialCoordinate(rightAscension: 88.79293860, declination: 7.40706274)
        let sampler = RiseSetCalculator.Sampler(target: .fixed(star, nil), observer: observer)
        for step in 0..<60 {
            let time = start + Double(step) * 1_777.7
            let direct = SkyFrame(date: Date(timeIntervalSinceReferenceDate: time), observer: observer)
                .horizontal(j2000: star, refraction: false).altitude
            XCTAssertEqual(sampler.sample(at: time).centreAltitude, direct, accuracy: 2e-5, "star at step \(step)")
        }
        XCTAssertTrue(sampler.sample(at: .nan).centreAltitude.isNaN)
    }

    func testMoonLimbAllowanceIsItsApparentSemiDiameter() {
        let observer = Observer(location: GeographicLocation(latitude: 10, longitude: 20))
        let time = Date(timeIntervalSince1970: 1_790_000_000).timeIntervalSinceReferenceDate
        let sample = RiseSetCalculator.Sampler(target: .body(.moon), observer: observer).sample(at: time)
        // The Moon's semi-diameter is between 14.7′ and 16.7′ for any distance and viewpoint.
        XCTAssertTrue((0.24...0.28).contains(sample.limbAllowance), "semi-diameter \(sample.limbAllowance)°")
        XCTAssertEqual(sample.limbAltitude, sample.centreAltitude + sample.limbAllowance, accuracy: 1e-12)
        let sun = RiseSetCalculator.Sampler(target: .body(.sun), observer: observer).sample(at: time)
        XCTAssertEqual(sun.limbAllowance, 0)
    }
}

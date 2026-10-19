import XCTest
@testable import LodestarKit

/// The visibility searches against the flat-horizon `RiseSetCalculator`, against closed-form geometry (a star at
/// the equator rises along a line of constant azimuth) and against a brute-force scan with full `SkyFrame`s.
final class HorizonVisibilityTests: XCTestCase {
    private typealias Support = HorizonTestSupport

    private let flat = HorizonVisibility(profile: .flat)

    /// Degrees per hour at which the Earth turns relative to the stars.
    private let siderealRate = 360.985_647_366_29 / 24.0

    private let stars: [(name: String, position: EquatorialCoordinate)] = [
        ("Betelgeuse", EquatorialCoordinate(rightAscensionHours: 5.9195, declination: 7.407)),
        ("Sirius", EquatorialCoordinate(rightAscensionHours: 6.7525, declination: -16.716)),
        ("Polaris", EquatorialCoordinate(rightAscensionHours: 2.5303, declination: 89.264)),
        ("Vega", EquatorialCoordinate(rightAscensionHours: 18.6156, declination: 38.784)),
        ("Sagittarius A*", EquatorialCoordinate(rightAscensionHours: 17.7611, declination: -29.0078)),
        ("Alpha Centauri", EquatorialCoordinate(rightAscensionHours: 14.6600, declination: -60.835)),
    ]

    private let day = DateInterval(start: HorizonTestSupport.date("2026-06-20T00:00:00Z"), duration: 86_400)

    private func assertSameEvents(_ expected: RiseTransitSet, _ actual: RiseTransitSet, accuracy: Double,
                                  _ message: String, line: UInt = #line) {
        XCTAssertEqual(actual.circumstance, expected.circumstance, message, line: line)
        let pairs: [(String, Date?, Date?)] = [("rise", expected.rise, actual.rise),
                                               ("transit", expected.transit, actual.transit),
                                               ("set", expected.set, actual.set)]
        for (name, wanted, found) in pairs {
            if let wanted {
                guard let found else {
                    XCTFail("\(message) \(name) is missing", line: line)
                    continue
                }
                XCTAssertEqual(found.timeIntervalSince(wanted), 0, accuracy: accuracy, "\(message) \(name)", line: line)
            } else {
                XCTAssertNil(found, "\(message) \(name)", line: line)
            }
        }
        if let wanted = expected.transitAltitude {
            XCTAssertEqual(actual.transitAltitude ?? .nan, wanted, accuracy: 1e-6, message, line: line)
        } else {
            XCTAssertNil(actual.transitAltitude, line: line)
        }
    }

    // MARK: A flat profile is the flat horizon

    func testFlatProfileMatchesTheRiseSetCalculatorForStars() {
        for observer in [Support.boulder, Support.equator, Support.sydney, Support.tromso] {
            for (name, position) in stars {
                let expected = RiseSetCalculator.riseTransitSet(forJ2000: position, observer: observer, within: day)
                let actual = flat.riseTransitSet(forJ2000: position, observer: observer, within: day)
                assertSameEvents(expected, actual, accuracy: 0.5, "\(name) at \(observer.location)")
                let wantedCrossings = RiseSetCalculator.crossings(ofJ2000: position, observer: observer, within: day)
                let foundCrossings = flat.crossings(ofJ2000: position, observer: observer, within: day)
                XCTAssertEqual(foundCrossings.map(\.kind), wantedCrossings.map(\.kind), name)
                for (wanted, found) in zip(wantedCrossings, foundCrossings) {
                    XCTAssertEqual(found.time.timeIntervalSince(wanted.time), 0, accuracy: 0.5, name)
                }
            }
        }
    }

    func testFlatProfileMatchesTheRiseSetCalculatorForTheSunMoonAndPlanets() {
        let dates = ["2026-03-20T00:00:00Z", "2026-06-20T00:00:00Z", "2026-12-21T00:00:00Z"]
        for observer in [Support.boulder, Support.tromso, Support.sydney] {
            for date in dates {
                let interval = DateInterval(start: Support.date(date), duration: 86_400)
                for body in SolarSystemBody.allCases {
                    let message = "\(body) at \(observer.location.latitude) on \(date)"
                    assertSameEvents(RiseSetCalculator.riseTransitSet(for: body, observer: observer, within: interval),
                                     flat.riseTransitSet(for: body, observer: observer, within: interval),
                                     accuracy: 0.5, message)
                    let wanted = RiseSetCalculator.crossings(of: body, observer: observer, within: interval)
                    let found = flat.crossings(of: body, observer: observer, within: interval)
                    XCTAssertEqual(found.map(\.kind), wanted.map(\.kind), message)
                    for (expected, actual) in zip(wanted, found) {
                        XCTAssertEqual(actual.time.timeIntervalSince(expected.time), 0, accuracy: 0.5, message)
                    }
                }
            }
        }
    }

    func testFlatProfileWindowsAreTheTimeAboveTheHorizon() throws {
        let observer = Support.boulder
        let position = stars[0].position
        let windows = flat.visibleWindows(ofJ2000: position, observer: observer, within: day)
        let crossings = RiseSetCalculator.crossings(ofJ2000: position, observer: observer, within: day)
        // Betelgeuse at 40°N, 20 June: up at the start of the UTC day (evening in Boulder), sets, rises again.
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].start, day.start)
        XCTAssertEqual(windows[0].end.timeIntervalSince(crossings[0].time), 0, accuracy: 0.5)
        XCTAssertEqual(windows[1].start.timeIntervalSince(crossings[1].time), 0, accuracy: 0.5)
        XCTAssertEqual(windows[1].end, day.end)
        // A star that never sets is one window, a star that never rises none.
        let polaris = stars[2].position
        XCTAssertEqual(flat.visibleWindows(ofJ2000: polaris, observer: observer, within: day), [day])
        XCTAssertTrue(flat.visibleWindows(ofJ2000: polaris, observer: Support.sydney, within: day).isEmpty)
    }

    func testMinimumAltitudeRaisesTheEdgesOfTheWindows() {
        let observer = Support.boulder
        let position = stars[3].position
        let altitude: (Date) -> Double = { SkyFrame(date: $0, observer: observer).horizontal(j2000: position, refraction: false).altitude }
        let expected = RiseSetCalculator.crossings(of: altitude, threshold: 20, within: day, tolerance: 0.01)
        let windows = flat.visibleWindows(ofJ2000: position, observer: observer, within: day, minimumAltitude: 20)
        var starts = expected.filter { $0.kind == .rising }.map(\.time)
        var ends = expected.filter { $0.kind == .setting }.map(\.time)
        if altitude(day.start) >= 20 { starts.insert(day.start, at: 0) }
        if altitude(day.end) >= 20 { ends.append(day.end) }
        XCTAssertEqual(windows.count, starts.count)
        XCTAssertEqual(windows.count, ends.count)
        for index in windows.indices where index < starts.count && index < ends.count {
            XCTAssertEqual(windows[index].start.timeIntervalSince(starts[index]), 0, accuracy: 0.5)
            XCTAssertEqual(windows[index].end.timeIntervalSince(ends[index]), 0, accuracy: 0.5)
        }
        // The window under a higher minimum is inside the window under the horizon.
        let lower = flat.visibleWindows(ofJ2000: position, observer: observer, within: day)
        for window in windows { XCTAssertTrue(lower.contains { $0.start <= window.start && $0.end >= window.end }) }
        // Under the horizon-only search the window is longer.
        XCTAssertGreaterThan(lower.reduce(0) { $0 + $1.duration }, windows.reduce(0) { $0 + $1.duration } + 3_600)
    }

    func testFlatProfileIsVisibleExactlyWhileAboveTheStandardHorizon() {
        let observer = Support.boulder
        let position = stars[1].position
        for step in 0..<48 {
            let time = day.start.addingTimeInterval(Double(step) * 1_800 + 77)
            let geometric = SkyFrame(date: time, observer: observer).horizontal(j2000: position, refraction: false).altitude
            XCTAssertEqual(flat.isVisible(ofJ2000: position, observer: observer, at: time),
                           geometric >= RiseSetCalculator.standardHorizonAltitude, "\(step)")
        }
        XCTAssertTrue(flat.isVisible(altitude: 0, azimuth: 123))
        XCTAssertTrue(flat.isVisible(altitude: -0.5667, azimuth: 10))
        XCTAssertFalse(flat.isVisible(altitude: -0.5668, azimuth: 10))
        XCTAssertTrue(flat.isVisible(altitude: 0, azimuth: 0, refracted: true))
        XCTAssertFalse(flat.isVisible(altitude: -0.1, azimuth: 0, refracted: true))
    }

    // MARK: Mountains

    /// The star of the closed-form tests: on the celestial equator at 6 h, which at the equator rises due east.
    private let equatorStar = EquatorialCoordinate(rightAscensionHours: 6, declination: 0)

    func testAMountainToTheEastDelaysAStarsRiseByTheExpectedAmount() throws {
        let observer = Support.equator
        let mountain = HorizonVisibility(profile: Support.wall(10, from: 45, to: 135))
        let flatRise = try XCTUnwrap(RiseSetCalculator.riseTransitSet(forJ2000: equatorStar, observer: observer, within: day).rise)
        let events = mountain.riseTransitSet(forJ2000: equatorStar, observer: observer, within: day)
        let cleared = try XCTUnwrap(events.rise)

        // At the equator a star of declination 0 climbs along its azimuth, 90°, at 15.041° per hour: altitude = 90° − |H|.
        // It must climb from the horizon (−0.5667°) to the geometric altitude at which refraction lifts it to 10°.
        let threshold = Refraction.trueAltitude(apparentAltitude: 10)
        XCTAssertEqual(threshold, HorizonVisibility.thresholdAltitude(skylineAltitude: 10), accuracy: 0.005) // the same 10° skyline through the library's refraction
        let expected = (HorizonVisibility.thresholdAltitude(skylineAltitude: 10) - RiseSetCalculator.standardHorizonAltitude)
            / siderealRate * 3_600
        XCTAssertEqual(expected, 2_508, accuracy: 1)
        XCTAssertEqual(cleared.timeIntervalSince(flatRise), expected, accuracy: 2)

        // Independent checks with full frames: at that moment the star's refracted altitude is the skyline's, at 90°.
        let frame = SkyFrame(date: cleared, observer: observer)
        let apparent = frame.horizontal(j2000: equatorStar, refraction: true)
        XCTAssertEqual(apparent.altitude, 10, accuracy: 0.01)
        XCTAssertEqual(apparent.azimuth, 90, accuracy: 0.1)
        let before = SkyFrame(date: cleared.addingTimeInterval(-5), observer: observer).horizontal(j2000: equatorStar, refraction: true)
        XCTAssertLessThan(before.altitude, 10)
        XCTAssertFalse(mountain.isVisible(ofJ2000: equatorStar, observer: observer, at: cleared.addingTimeInterval(-5)))
        XCTAssertTrue(mountain.isVisible(ofJ2000: equatorStar, observer: observer, at: cleared.addingTimeInterval(5)))

        // It sets in the west, where the skyline is flat: the set is the flat set, and the circumstance normal.
        let flatEvents = RiseSetCalculator.riseTransitSet(forJ2000: equatorStar, observer: observer, within: day)
        XCTAssertEqual(mountain.crossings(ofJ2000: equatorStar, observer: observer, within: day).first?.kind, .rising)
        XCTAssertEqual(try XCTUnwrap(events.set).timeIntervalSince(try XCTUnwrap(flatEvents.set)), 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(events.transit).timeIntervalSince(try XCTUnwrap(flatEvents.transit)), 0, accuracy: 0.5)
        XCTAssertEqual(events.circumstance, .normal)
    }

    func testAMountainToTheWestMakesAStarSinkBehindItEarlier() throws {
        let observer = Support.equator
        let mountain = HorizonVisibility(profile: Support.wall(15, from: 225, to: 315))
        let flatEvents = RiseSetCalculator.riseTransitSet(forJ2000: equatorStar, observer: observer, within: day)
        let events = mountain.riseTransitSet(forJ2000: equatorStar, observer: observer, within: day)
        let lead = (HorizonVisibility.thresholdAltitude(skylineAltitude: 15) - RiseSetCalculator.standardHorizonAltitude)
            / siderealRate * 3_600
        XCTAssertEqual(try XCTUnwrap(flatEvents.set).timeIntervalSince(try XCTUnwrap(events.set)), lead, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(events.rise).timeIntervalSince(try XCTUnwrap(flatEvents.rise)), 0, accuracy: 0.5)
        // The windows are the time between.
        let windows = mountain.visibleWindows(ofJ2000: equatorStar, observer: observer, within: day)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start.timeIntervalSince(try XCTUnwrap(events.rise)), 0, accuracy: 0.5)
        XCTAssertEqual(windows[0].end.timeIntervalSince(try XCTUnwrap(events.set)), 0, accuracy: 0.5)
    }

    func testADelayForAStarThatRisesNorthOfEast() throws {
        let observer = Support.equator
        // Declination +20° at the equator: it rises at azimuth 70° and keeps going to the north-east.
        let star = EquatorialCoordinate(rightAscensionHours: 6, declination: 20)
        let mountain = HorizonVisibility(profile: Support.wall(10, from: 40, to: 100))
        let flatRise = try XCTUnwrap(RiseSetCalculator.riseTransitSet(forJ2000: star, observer: observer, within: day).rise)
        let cleared = try XCTUnwrap(mountain.riseTransitSet(forJ2000: star, observer: observer, within: day).rise)
        // sin(altitude) = cos(declination) · cos(hour angle) at the equator.
        func hourAngleBefore(_ altitude: Double) -> Double {
            AstroMath.acosDeg(AstroMath.sinDeg(altitude) / AstroMath.cosDeg(20))
        }
        let expected = (hourAngleBefore(RiseSetCalculator.standardHorizonAltitude)
            - hourAngleBefore(HorizonVisibility.thresholdAltitude(skylineAltitude: 10))) / siderealRate * 3_600
        XCTAssertEqual(cleared.timeIntervalSince(flatRise), expected, accuracy: 3)
        let apparent = SkyFrame(date: cleared, observer: observer).horizontal(j2000: star, refraction: true)
        XCTAssertEqual(apparent.altitude, 10, accuracy: 0.01)
        XCTAssertEqual(apparent.azimuth, 69.7, accuracy: 0.3)
    }

    func testAMountainOffTheStarsPathChangesNothing() {
        let observer = Support.equator
        let star = EquatorialCoordinate(rightAscensionHours: 6, declination: 20)
        let mountain = HorizonVisibility(profile: Support.wall(40, from: 100, to: 140))
        assertSameEvents(RiseSetCalculator.riseTransitSet(forJ2000: star, observer: observer, within: day),
                         mountain.riseTransitSet(forJ2000: star, observer: observer, within: day),
                         accuracy: 0.5, "behind the mountain's side")
    }

    func testTheSunRisesLaterBehindATenDegreeSkyline() throws {
        let observer = Support.boulder
        let morning = DateInterval(start: Support.date("2026-03-20T08:00:00Z"), duration: 8 * 3_600)
        let flatEvents = RiseSetCalculator.riseTransitSet(for: .sun, observer: observer, within: morning)
        let flatRise = try XCTUnwrap(flatEvents.rise)
        let ridge = HorizonVisibility(profile: Support.wall(10, from: 60, to: 120))
        let events = ridge.riseTransitSet(for: .sun, observer: observer, within: morning)
        let cleared = try XCTUnwrap(events.rise)

        // Near the equinox the Sun's declination is 0 and sin(altitude) = cos(latitude) · cos(hour angle), at 15° per hour.
        // The upper limb must reach 10° apparent, i.e. the centre 0.2666° lower than a star would have to be.
        let sunThreshold = HorizonVisibility.thresholdAltitude(skylineAltitude: 10)
            + (RiseSetCalculator.sunHorizonAltitude - RiseSetCalculator.standardHorizonAltitude)
        func hourAngleBefore(_ altitude: Double) -> Double {
            AstroMath.acosDeg(AstroMath.sinDeg(altitude) / AstroMath.cosDeg(40))
        }
        let expected = (hourAngleBefore(RiseSetCalculator.sunHorizonAltitude) - hourAngleBefore(sunThreshold)) / 15 * 3_600
        XCTAssertEqual(expected, 54.9 * 60, accuracy: 30)
        XCTAssertEqual(cleared.timeIntervalSince(flatRise), expected, accuracy: 60)

        // A scan with full frames: the first second at which the refracted upper limb stands at 10° (the Sun is at 90° azimuth).
        var scan = flatRise
        let limb = { (time: Date) -> Double in
            let state = Ephemeris.state(of: .sun, at: JulianDate(date: time))
            return SkyFrame(date: time, observer: observer).horizontal(of: .sun, refraction: true).altitude
                + state.angularDiameterArcseconds / 7_200
        }
        while limb(scan) < 10 { scan = scan.addingTimeInterval(1) }
        XCTAssertEqual(cleared.timeIntervalSince(scan), 0, accuracy: 3)
        // Climbing from due east it has turned 8° towards the south by then, still in front of the skyline.
        XCTAssertEqual(SkyFrame(date: cleared, observer: observer).horizontal(of: .sun, refraction: true).azimuth, 98.2, accuracy: 0.5)

        // The skyline is flat in the west: the Sun sets when it does without it.
        let evening = DateInterval(start: Support.date("2026-03-21T00:00:00Z"), duration: 8 * 3_600)
        let flatSet = try XCTUnwrap(RiseSetCalculator.riseTransitSet(for: .sun, observer: observer, within: evening).set)
        XCTAssertEqual(try XCTUnwrap(ridge.riseTransitSet(for: .sun, observer: observer, within: evening).set).timeIntervalSince(flatSet),
                       0, accuracy: 0.5)
        // The day's window runs from the clearing to the sunset.
        let dayWindows = ridge.visibleWindows(of: .sun, observer: observer,
                                              within: DateInterval(start: morning.start, duration: 20 * 3_600))
        XCTAssertEqual(dayWindows.count, 1)
        XCTAssertEqual(dayWindows[0].start.timeIntervalSince(cleared), 0, accuracy: 0.5)
        XCTAssertEqual(dayWindows[0].end.timeIntervalSince(flatSet), 0, accuracy: 0.5)
    }

    func testTheMoonRisesBehindARidgeLaterThanOverTheFlatHorizon() throws {
        let observer = Support.boulder
        let night = DateInterval(start: Support.date("2026-06-24T12:00:00Z"), duration: 24 * 3_600)
        let flatRise = try XCTUnwrap(RiseSetCalculator.riseTransitSet(for: .moon, observer: observer, within: night).rise)
        let ridge = HorizonVisibility(profile: .constant(8))
        let events = ridge.riseTransitSet(for: .moon, observer: observer, within: night)
        let cleared = try XCTUnwrap(events.rise)
        XCTAssertGreaterThan(cleared.timeIntervalSince(flatRise), 20 * 60, "the Moon needs more than 20 minutes to climb 8°")

        // The first second at which the refracted upper limb is at the skyline.
        var scan = flatRise
        let limb = { (time: Date) -> Double in
            let frame = SkyFrame(date: time, observer: observer)
            return frame.horizontal(of: .moon, refraction: true).altitude
                + Ephemeris.state(of: .moon, at: frame.julianDate).angularDiameterArcseconds / 7_200
        }
        while limb(scan) < 8 { scan = scan.addingTimeInterval(1) }
        XCTAssertEqual(cleared.timeIntervalSince(scan), 0, accuracy: 10)
        XCTAssertEqual(ridge.crossings(of: .moon, observer: observer, within: night).first?.kind, .rising)
        XCTAssertFalse(ridge.isVisible(of: .moon, observer: observer, at: cleared.addingTimeInterval(-60)))
        XCTAssertTrue(ridge.isVisible(of: .moon, observer: observer, at: cleared.addingTimeInterval(60)))
    }

    func testCircumstancesFollowTheSkylineNotTheHorizon() throws {
        let polaris = stars[2].position
        // Polaris is 40° high at 40°N: above any skyline lower than that, below a 45° wall all round.
        let low = HorizonVisibility(profile: .constant(30))
        XCTAssertEqual(low.riseTransitSet(forJ2000: polaris, observer: Support.boulder, within: day).circumstance, .alwaysUp)
        XCTAssertTrue(low.crossings(ofJ2000: polaris, observer: Support.boulder, within: day).isEmpty)
        let high = HorizonVisibility(profile: .constant(45))
        let hidden = high.riseTransitSet(forJ2000: polaris, observer: Support.boulder, within: day)
        XCTAssertEqual(hidden.circumstance, .alwaysDown)
        XCTAssertNil(hidden.rise)
        XCTAssertNil(hidden.set)
        XCTAssertTrue(high.visibleWindows(ofJ2000: polaris, observer: Support.boulder, within: day).isEmpty)
        XCTAssertNotNil(hidden.transit) // the culmination is reported whether or not it is hidden
        XCTAssertEqual(flat.riseTransitSet(forJ2000: polaris, observer: Support.boulder, within: day).circumstance, .alwaysUp)
    }

    func testTheMinimumAltitudeAndTheSkylineBothApply() {
        let observer = Support.equator
        let mountain = HorizonVisibility(profile: Support.wall(40, from: 45, to: 135))
        // The star climbs through the 40° wall at azimuth 90°, so a 20° minimum changes nothing there; it sets over the
        // flat west, where the minimum ends the window when the star falls to 20° instead of at the horizon.
        let withoutMinimum = mountain.visibleWindows(ofJ2000: equatorStar, observer: observer, within: day)
        let withLowMinimum = mountain.visibleWindows(ofJ2000: equatorStar, observer: observer, within: day, minimumAltitude: 20)
        XCTAssertEqual(withoutMinimum.count, 1)
        XCTAssertEqual(withLowMinimum.count, 1)
        XCTAssertEqual(withLowMinimum[0].start.timeIntervalSince(withoutMinimum[0].start), 0, accuracy: 0.01)
        let earlier = (20 - RiseSetCalculator.standardHorizonAltitude) / siderealRate * 3_600
        XCTAssertEqual(withoutMinimum[0].end.timeIntervalSince(withLowMinimum[0].end), earlier, accuracy: 1)
        // A 60° minimum is higher than the wall: it decides, and the star is up 30° of hour angle either side of transit.
        let high = mountain.visibleWindows(ofJ2000: equatorStar, observer: observer, within: day, minimumAltitude: 60)
        XCTAssertEqual(high.count, 1)
        XCTAssertEqual(high[0].duration, 60 / siderealRate * 3_600, accuracy: 5)
        XCTAssertLessThan(withoutMinimum[0].start, high[0].start)
    }

    // MARK: Generic position functions

    private let dayLength = 86_400.0
    private let origin = HorizonTestSupport.date("2026-06-20T18:00:00Z")

    /// 40 sin(2π t / day) + 10 degrees at azimuth 90°: a smooth curve with known crossings.
    private var sinusoid: (Date) -> HorizontalCoordinate {
        { [origin, dayLength] time in
            HorizontalCoordinate(azimuth: 90, altitude: 40 * sin(2 * .pi * time.timeIntervalSince(origin) / dayLength) + 10)
        }
    }

    func testCrossingsOfAFunctionAreFoundExactly() throws {
        let skyline = HorizonVisibility(profile: Support.wall(20, from: 80, to: 100))
        let interval = DateInterval(start: origin, duration: 2 * dayLength)
        // Refracted altitudes are compared with the skyline as it is: 40 sin θ + 10 = 20.
        let crossings = skyline.crossings(of: sinusoid, within: interval, refracted: true, tolerance: 0.001)
        let theta = asin(0.25)
        let rising = theta / (2 * .pi) * dayLength
        let setting = (.pi - theta) / (2 * .pi) * dayLength
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting, .rising, .setting])
        let times = crossings.map { $0.time.timeIntervalSince(origin) }
        XCTAssertEqual(times[0], rising, accuracy: 0.01)
        XCTAssertEqual(times[1], setting, accuracy: 0.01)
        XCTAssertEqual(times[2], rising + dayLength, accuracy: 0.01)
        XCTAssertEqual(times[3], setting + dayLength, accuracy: 0.01)

        // Geometric altitudes must reach the threshold above the skyline instead.
        let threshold = HorizonVisibility.thresholdAltitude(skylineAltitude: 20)
        let geometric = skyline.crossings(of: sinusoid, within: interval, tolerance: 0.001)
        XCTAssertEqual(geometric[0].time.timeIntervalSince(origin), asin((threshold - 10) / 40) / (2 * .pi) * dayLength, accuracy: 0.01)
        XCTAssertTrue(threshold < 20 && threshold > 19.9)

        let events = skyline.riseTransitSet(of: sinusoid, within: interval, refracted: true)
        XCTAssertEqual(try XCTUnwrap(events.rise).timeIntervalSince(origin), rising, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(events.set).timeIntervalSince(origin), setting, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(events.transit).timeIntervalSince(origin), dayLength / 4, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(events.transitAltitude), 50, accuracy: 1e-6)
        let windows = skyline.visibleWindows(of: sinusoid, within: interval, refracted: true, tolerance: 0.001)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].start.timeIntervalSince(origin), rising, accuracy: 0.01)
        XCTAssertEqual(windows[0].end.timeIntervalSince(origin), setting, accuracy: 0.01)
    }

    func testIsVisibleForAFunctionFollowsTheMargin() {
        let skyline = HorizonVisibility(profile: Support.wall(20, from: 80, to: 100))
        for step in 0..<96 {
            let time = origin.addingTimeInterval(Double(step) * 900 + 13)
            let altitude = sinusoid(time).altitude
            XCTAssertEqual(skyline.isVisible(of: sinusoid, at: time, refracted: true), altitude >= 20, "\(step)")
            XCTAssertEqual(skyline.isVisible(of: sinusoid, at: time),
                           altitude >= HorizonVisibility.thresholdAltitude(skylineAltitude: 20), "\(step)")
        }
        XCTAssertEqual(skyline.margin(altitude: 30, azimuth: 90, refracted: true), 10, accuracy: 1e-12)
        XCTAssertEqual(skyline.margin(altitude: 30, azimuth: 90), 30 - HorizonVisibility.thresholdAltitude(skylineAltitude: 20),
                       accuracy: 1e-12)
        XCTAssertEqual(skyline.margin(altitude: 30, azimuth: 180, refracted: true), 30, accuracy: 1e-12) // flat there
        XCTAssertTrue(skyline.margin(altitude: .nan, azimuth: 90).isNaN)
    }

    func testATargetThatOnlyGrazesTheSkylineIsStillFound() {
        let skyline = HorizonVisibility(profile: .constant(10))
        // 10.01° at the top of a parabola that is 40 s wide at the skyline: narrower than a sample step (120 s), with the
        // nearest sample 30 s from the top, 0.0125° short of the skyline.
        let peak = origin.addingTimeInterval(1_050)
        let graze: (Date) -> HorizontalCoordinate = { time in
            let offset = time.timeIntervalSince(peak) / 20
            return HorizontalCoordinate(azimuth: 45, altitude: 10.01 - 0.01 * offset * offset)
        }
        let interval = DateInterval(start: origin, duration: 3_600)
        let windows = skyline.visibleWindows(of: graze, within: interval, refracted: true, tolerance: 0.001)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.duration ?? 0, 40, accuracy: 0.05)
        XCTAssertEqual(windows.first?.start.timeIntervalSince(peak.addingTimeInterval(-20)) ?? 99, 0, accuracy: 0.02)
        let crossings = skyline.crossings(of: graze, within: interval, refracted: true, tolerance: 0.001)
        XCTAssertEqual(crossings.map(\.kind), [.rising, .setting])
        // A target that peaks just below the skyline never shows.
        let below: (Date) -> HorizontalCoordinate = { time in
            let offset = time.timeIntervalSince(peak) / 20
            return HorizontalCoordinate(azimuth: 45, altitude: 9.99 - 0.01 * offset * offset)
        }
        XCTAssertTrue(skyline.visibleWindows(of: below, within: interval, refracted: true).isEmpty)
    }

    func testATargetCrossingANarrowSpireDisappearsBehindItAndReturns() throws {
        // A spire 20° high at azimuth 90° (a triangle over ±1°) in front of a target 10° high that moves east at 0.25° per minute.
        let spire = HorizonVisibility(profile: HorizonProfile.flat.setting(to: 20, in: AzimuthRange(start: 90, length: 0)))
        let moving: (Date) -> HorizontalCoordinate = { [origin] time in
            HorizontalCoordinate(azimuth: 80 + time.timeIntervalSince(origin) * 0.25 / 60, altitude: 10)
        }
        let interval = DateInterval(start: origin, duration: 5_000)
        let windows = spire.visibleWindows(of: moving, within: interval, refracted: true, tolerance: 0.001)
        // Hidden while 20 (1 − |d|) ≥ 10, i.e. for |azimuth − 90| < 0.5°: 240 s centred on 2400 s.
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].start.timeIntervalSince(origin), 0, accuracy: 1e-9)
        XCTAssertEqual(windows[0].end.timeIntervalSince(origin), 2_280, accuracy: 0.05)
        XCTAssertEqual(windows[1].start.timeIntervalSince(origin), 2_520, accuracy: 0.05)
        XCTAssertEqual(windows[1].end.timeIntervalSince(origin), 5_000, accuracy: 1e-9)
        let events = spire.riseTransitSet(of: moving, within: interval, refracted: true)
        XCTAssertEqual(try XCTUnwrap(events.rise).timeIntervalSince(origin), 2_520, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(events.set).timeIntervalSince(origin), 2_280, accuracy: 0.05)
    }

    func testEmptyAndDegenerateIntervals() {
        let ridge = HorizonVisibility(profile: .constant(10))
        let position = equatorStar
        let empty = DateInterval(start: day.start, duration: 0)
        XCTAssertTrue(ridge.crossings(ofJ2000: position, observer: Support.equator, within: empty).isEmpty)
        XCTAssertTrue(ridge.visibleWindows(ofJ2000: position, observer: Support.equator, within: empty).isEmpty)
        XCTAssertTrue(ridge.visibleWindows(ofJ2000: position, observer: Support.equator, during: []).isEmpty)
        XCTAssertEqual(ridge.riseTransitSet(forJ2000: position, observer: Support.equator, within: empty).circumstance, .alwaysDown)
        // Overlapping and touching intervals are merged; the windows come back sorted without overlap.
        let first = DateInterval(start: day.start, duration: 6 * 3_600)
        let second = DateInterval(start: day.start.addingTimeInterval(5 * 3_600), duration: 6 * 3_600)
        let merged = ridge.visibleWindows(ofJ2000: position, observer: Support.equator, during: [second, first])
        let whole = ridge.visibleWindows(ofJ2000: position, observer: Support.equator,
                                         within: DateInterval(start: day.start, duration: 11 * 3_600))
        XCTAssertEqual(merged.count, whole.count)
        for (a, b) in zip(merged, whole) {
            XCTAssertEqual(a.start.timeIntervalSince(b.start), 0, accuracy: 0.01)
            XCTAssertEqual(a.end.timeIntervalSince(b.end), 0, accuracy: 0.01)
        }
    }

    // MARK: The threshold

    func testThresholdAltitudeScalesTheHorizonRefractionWithTheSkylineAltitude() {
        XCTAssertEqual(HorizonVisibility.thresholdAltitude(skylineAltitude: 0), RiseSetCalculator.standardHorizonAltitude)
        // Bennett's refraction at the horizon and at 10°, 30° and 60° (arcminutes): 1 / tan(h + 7.31 / (h + 4.4)).
        func bennett(_ h: Double) -> Double { 1 / AstroMath.tanDeg(h + 7.31 / (h + 4.4)) }
        for h in [1.0, 5, 10, 20, 30, 45, 60] {
            let expected = h + RiseSetCalculator.standardHorizonAltitude * bennett(h) / bennett(0)
            XCTAssertEqual(HorizonVisibility.thresholdAltitude(skylineAltitude: h), expected, accuracy: 1e-9, "\(h)")
        }
        XCTAssertEqual(HorizonVisibility.thresholdAltitude(skylineAltitude: 10), 9.9114, accuracy: 1e-4)
        // Rising with the skyline, and never below the skyline itself minus the horizon allowance.
        var previous = HorizonVisibility.thresholdAltitude(skylineAltitude: -10)
        for tenth in -99...600 {
            let h = Double(tenth) / 10
            let value = HorizonVisibility.thresholdAltitude(skylineAltitude: h)
            XCTAssertGreaterThan(value, previous, "\(tenth)")
            XCTAssertTrue(value <= h + 1e-12 && value >= h - 0.5667 - 1e-12, "\(tenth)")
            previous = value
        }
        // A skyline below the horizon keeps the full allowance.
        XCTAssertEqual(HorizonVisibility.thresholdAltitude(skylineAltitude: -5), -5.5667, accuracy: 1e-12)
        XCTAssertTrue(HorizonVisibility.thresholdAltitude(skylineAltitude: .nan).isNaN)
        // The independent route: the refraction model of the library puts the star at the skyline.
        for h in [2.0, 10, 25] {
            let apparent = Refraction.apparentAltitude(trueAltitude: HorizonVisibility.thresholdAltitude(skylineAltitude: h))
            XCTAssertEqual(apparent, h, accuracy: 0.01, "\(h)")
        }
    }

    // MARK: Batches

    func testBatchOfFixedObjectsGivesTheSameWindowsAsSingleCalls() {
        let generator = Support.SeededGenerator(seed: 31)
        let positions = (0..<40).map { _ -> EquatorialCoordinate in
            let rightAscension = 360 * generator.nextDouble()
            let declination = AstroMath.asinDeg(2 * generator.nextDouble() - 1)
            return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        }
        let motions: [ProperMotion?] = positions.indices.map {
            $0 % 3 == 0 ? ProperMotion(raMilliarcsecondsPerYear: 40, decMilliarcsecondsPerYear: -25) : nil
        }
        let skyline = HorizonVisibility(profile: Support.truthProfile)
        let night = [DateInterval(start: Support.date("2026-12-21T01:00:00Z"), duration: 5 * 3_600),
                     DateInterval(start: Support.date("2026-12-21T08:00:00Z"), duration: 3 * 3_600)]
        let batch = skyline.visibleWindows(ofFixed: positions, properMotions: motions, observer: Support.boulder,
                                           during: night, minimumAltitude: 15)
        XCTAssertEqual(batch.count, positions.count)
        for index in positions.indices {
            XCTAssertEqual(skyline.visibleWindows(ofJ2000: positions[index], properMotion: motions[index],
                                                  observer: Support.boulder, during: night, minimumAltitude: 15),
                           batch[index], "\(index)")
        }
        XCTAssertTrue((10...35).contains(batch.filter { !$0.isEmpty }.count))
        // Windows lie inside the given intervals, in order, and without overlap.
        for windows in batch {
            for window in windows { XCTAssertTrue(night.contains { $0.start <= window.start && $0.end >= window.end }) }
            for (a, b) in zip(windows, windows.dropFirst()) { XCTAssertLessThan(a.end, b.start) }
        }
    }

    func testWindowsAgreeWithAScanOfFullFramesForARoughSkyline() {
        let generator = Support.SeededGenerator(seed: 77)
        let skyline = HorizonVisibility(profile: Support.truthProfile)
        let night = DateInterval(start: Support.date("2026-12-21T01:00:00Z"), duration: 10 * 3_600)
        let observer = Support.boulder
        for index in 0..<12 {
            let rightAscension = 360 * generator.nextDouble()
            let declination = AstroMath.asinDeg(2 * generator.nextDouble() - 1)
            let position = EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
            let windows = skyline.visibleWindows(ofJ2000: position, observer: observer, within: night, minimumAltitude: 5)
            var disagreements = 0
            for step in 0..<600 {
                let time = night.start.addingTimeInterval(Double(step) * 60 + 17)
                let geometric = SkyFrame(date: time, observer: observer).horizontal(j2000: position, refraction: false)
                let expected = geometric.altitude >= 5
                    && geometric.altitude >= HorizonVisibility.thresholdAltitude(
                        skylineAltitude: Support.truthProfile.altitude(at: geometric.azimuth))
                let found = windows.contains { $0.start <= time && time < $0.end }
                if expected != found {
                    // Only samples within a few seconds of an edge may differ.
                    let distance = windows.flatMap { [$0.start, $0.end] }.map { abs($0.timeIntervalSince(time)) }.min()
                        ?? .greatestFiniteMagnitude
                    XCTAssertLessThan(distance, 30, "object \(index) at step \(step): expected \(expected)")
                    disagreements += 1
                }
            }
            XCTAssertLessThanOrEqual(disagreements, 3, "\(disagreements) disagreements for object \(index)")
        }
    }

    // MARK: Speed

    /// Seconds allowed for the windows of 700 objects. A release build needs a tenth of a second (the requirement
    /// is one second); an unoptimised debug build is an order of magnitude slower, so its bound only catches a
    /// calculation that has gone badly wrong.
    private static let sevenHundredObjectsLimit: Double = {
        #if DEBUG
        return 20
        #else
        return 1
        #endif
    }()

    func testWindowsForSevenHundredObjectsThroughANightTakeUnderASecond() throws {
        let summary = try PlanningTestSupport.summary(PlanningTestSupport.boulder, 2026, 12, 21)
        let generator = Support.SeededGenerator(seed: 700)
        let positions = (0..<700).map { _ -> EquatorialCoordinate in
            let rightAscension = 360 * generator.nextDouble()
            let declination = AstroMath.asinDeg(2 * generator.nextDouble() - 1)
            return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
        }
        let skyline = HorizonVisibility(profile: Support.truthProfile)
        let dark = summary.astronomicalDarknessIntervals
        XCTAssertGreaterThan(dark.reduce(0) { $0 + $1.duration }, 10 * 3_600)
        let clock = ContinuousClock()
        var windows = [[DateInterval]]()
        let elapsed = clock.measure {
            windows = skyline.visibleWindows(ofFixed: positions, observer: summary.observer, during: dark,
                                             minimumAltitude: 10)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        XCTAssertEqual(windows.count, 700)
        XCTAssertLessThan(seconds, Self.sevenHundredObjectsLimit, "took \(seconds) s")
        XCTAssertGreaterThan(windows.filter { !$0.isEmpty }.count, 200)
        XCTAssertGreaterThan(windows.filter { $0.isEmpty }.count, 100)
    }
}

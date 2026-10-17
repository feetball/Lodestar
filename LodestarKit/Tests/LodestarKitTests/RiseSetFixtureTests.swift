import XCTest
@testable import LodestarKit

/// Compares the rise, transit, set and twilight searches with `riseset.json`: for 5 sites and 6 dates
/// (windows from local solar noon to the next, including midnight Sun and polar night at Tromsø) the
/// instants at which Skyfield and JPL DE440s put the Sun, Moon, Venus, Jupiter, Sirius and Vega
/// through their horizons, and their upper culminations.
final class RiseSetFixtureTests: XCTestCase {
    private struct Crossing: Decodable {
        let kind: String
        let unix: Double
    }

    private struct Horizon: Decodable {
        let crossings: [Crossing]
        let alwaysUp: Bool
        let alwaysDown: Bool
    }

    private struct Transit: Decodable {
        let unix: Double
        let altitudeDeg: Double
    }

    private struct ObjectRecord: Decodable {
        let horizon: Horizon?
        let horizonUpperLimb: Horizon?
        let civil: Horizon?
        let nautical: Horizon?
        let astronomical: Horizon?
        let transits: [Transit]
    }

    private struct DayCase: Decodable {
        let site: String
        let lat: Double
        let lon: Double
        let elevationM: Double
        let date: String
        let windowStartUtc: String
        let windowEndUtc: String
        let objects: [String: ObjectRecord]

        var observer: Observer {
            Observer(location: GeographicLocation(latitude: lat, longitude: lon, elevation: elevationM))
        }

        var interval: DateInterval {
            let formatter = ISO8601DateFormatter()
            return DateInterval(start: formatter.date(from: windowStartUtc) ?? .distantPast,
                                end: formatter.date(from: windowEndUtc) ?? .distantPast)
        }
    }

    private struct File: Decodable {
        let cases: [DayCase]
    }

    /// Sirius and Vega as in the fixture generator (Hipparcos, ICRS J2000.0).
    private static let stars: [String: (EquatorialCoordinate, ProperMotion)] = [
        "sirius": (EquatorialCoordinate(rightAscension: 101.28715539, declination: -16.71611582),
                   ProperMotion(raMilliarcsecondsPerYear: -546.01, decMilliarcsecondsPerYear: -1223.08)),
        "vega": (EquatorialCoordinate(rightAscension: 279.23473511, declination: 38.78369180),
                 ProperMotion(raMilliarcsecondsPerYear: 201.02, decMilliarcsecondsPerYear: 287.46)),
    ]

    /// Seconds by which event times may differ. Observed maxima over the fixture: Sun 0.08 s, stars
    /// 0.04 s, Venus and Jupiter 0.4 s, Moon 0.6 s (a 8″ error in the lunar theory is half a second of time).
    private func timeTolerance(for object: String) -> Double {
        switch object {
        case "sun", "sirius", "vega": 1.5
        case "moon": 3
        default: 2
        }
    }

    private func fixture() throws -> [DayCase] {
        let cases = try EphemerisFixtureStore.load(File.self, from: "riseset.json").cases
        XCTAssertEqual(cases.count, 30, "5 sites x 6 dates")
        return cases
    }

    private func assertCrossings(_ found: [AltitudeCrossing], match expected: Horizon, tolerance: Double,
                                 _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(found.count, expected.crossings.count, "\(label): number of crossings",
                       file: file, line: line)
        guard found.count == expected.crossings.count else { return }
        for (mine, reference) in zip(found, expected.crossings) {
            XCTAssertEqual(mine.kind == .rising ? "rise" : "set", reference.kind, "\(label): kind", file: file, line: line)
            XCTAssertEqual(mine.time.timeIntervalSince1970, reference.unix, accuracy: tolerance, "\(label): time",
                           file: file, line: line)
        }
    }

    private func assertSummary(_ result: RiseTransitSet, crossings expected: Horizon, transits: [Transit],
                               tolerance: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let rise = expected.crossings.first { $0.kind == "rise" }
        let set = expected.crossings.first { $0.kind == "set" }
        XCTAssertEqual(result.rise?.timeIntervalSince1970 == nil, rise == nil, "\(label): rise present", file: file, line: line)
        XCTAssertEqual(result.set?.timeIntervalSince1970 == nil, set == nil, "\(label): set present", file: file, line: line)
        if let found = result.rise?.timeIntervalSince1970, let reference = rise?.unix {
            XCTAssertEqual(found, reference, accuracy: tolerance, "\(label): rise", file: file, line: line)
        }
        if let found = result.set?.timeIntervalSince1970, let reference = set?.unix {
            XCTAssertEqual(found, reference, accuracy: tolerance, "\(label): set", file: file, line: line)
        }
        XCTAssertEqual(result.circumstance == .alwaysUp, expected.alwaysUp, "\(label): always up", file: file, line: line)
        XCTAssertEqual(result.circumstance == .alwaysDown, expected.alwaysDown, "\(label): always down", file: file, line: line)
        XCTAssertEqual(result.circumstance == .normal, !expected.alwaysUp && !expected.alwaysDown,
                       "\(label): circumstance", file: file, line: line)
        if let first = transits.first {
            XCTAssertEqual(result.transit?.timeIntervalSince1970 ?? .nan, first.unix, accuracy: 2 * tolerance,
                           "\(label): transit", file: file, line: line)
            XCTAssertEqual(result.transitAltitude ?? .nan, first.altitudeDeg, accuracy: 0.002,
                           "\(label): transit altitude", file: file, line: line)
        } else {
            XCTAssertNil(result.transit, "\(label): transit", file: file, line: line)
        }
    }

    private func assertCulminations(_ found: [AltitudeCulmination], match expected: [Transit], tolerance: Double,
                                    _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(found.count, expected.count, "\(label): number of culminations", file: file, line: line)
        guard found.count == expected.count else { return }
        for (mine, reference) in zip(found, expected) {
            XCTAssertEqual(mine.time.timeIntervalSince1970, reference.unix, accuracy: 2 * tolerance, "\(label): time",
                           file: file, line: line)
            XCTAssertEqual(mine.altitude, reference.altitudeDeg, accuracy: 0.002, "\(label): altitude",
                           file: file, line: line)
        }
    }

    // MARK: Tests

    func testSunSetsAndRisesAndTwilightsMatch() throws {
        for day in try fixture() {
            let label = "\(day.site) \(day.date) sun"
            let record = try XCTUnwrap(day.objects["sun"])
            let tolerance = timeTolerance(for: "sun")
            let observer = day.observer

            let horizon = try XCTUnwrap(record.horizon)
            assertCrossings(RiseSetCalculator.crossings(of: .sun, observer: observer, within: day.interval),
                            match: horizon, tolerance: tolerance, label + " horizon")
            assertSummary(RiseSetCalculator.riseTransitSet(for: .sun, observer: observer, within: day.interval),
                          crossings: horizon, transits: record.transits, tolerance: tolerance, label + " summary")

            // The twilights go through the generic search with a caller-supplied altitude function.
            let altitude: (Date) -> Double = {
                SkyFrame(date: $0, observer: observer).horizontal(of: .sun, refraction: false).altitude
            }
            for (name, threshold, expected) in [("civil", TwilightCalculator.civilAltitude, record.civil),
                                                ("nautical", TwilightCalculator.nauticalAltitude, record.nautical),
                                                ("astronomical", TwilightCalculator.astronomicalAltitude, record.astronomical)] {
                assertCrossings(RiseSetCalculator.crossings(of: altitude, threshold: threshold, within: day.interval),
                                match: try XCTUnwrap(expected), tolerance: tolerance, "\(label) \(name)")
            }
            assertCulminations(RiseSetCalculator.upperCulminations(of: .sun, observer: observer, within: day.interval),
                               match: record.transits, tolerance: tolerance, label + " culmination")
        }
    }

    func testMoonUpperLimbRiseSetAndTransitMatch() throws {
        for day in try fixture() {
            let label = "\(day.site) \(day.date) moon"
            let record = try XCTUnwrap(day.objects["moon"])
            let tolerance = timeTolerance(for: "moon")
            let limb = try XCTUnwrap(record.horizonUpperLimb)
            assertCrossings(RiseSetCalculator.crossings(of: .moon, observer: day.observer, within: day.interval),
                            match: limb, tolerance: tolerance, label + " upper limb")
            assertSummary(RiseSetCalculator.riseTransitSet(for: .moon, observer: day.observer, within: day.interval),
                          crossings: limb, transits: record.transits, tolerance: tolerance, label + " summary")
            assertCulminations(RiseSetCalculator.upperCulminations(of: .moon, observer: day.observer, within: day.interval),
                               match: record.transits, tolerance: tolerance, label + " culmination")
        }
    }

    /// The fixture also tabulates the DESIGN.md recipe taken literally: the topocentric altitude against
    /// `0.7275·π − 0.5667°`, which is Meeus' threshold for the geocentric altitude. The generic search
    /// reproduces that list, and shows that it puts every event about π too high: rises come 4 to 16
    /// minutes late and sets as early (the fixture README measures 255 s at the equator to 949 s at
    /// Tromsø), which is why `RiseSetCalculator` uses the upper limb instead.
    func testLiteralDesignThresholdOnTopocentricAltitudeIsMinutesOff() throws {
        var compared = 0
        for day in try fixture() {
            let record = try XCTUnwrap(day.objects["moon"])
            let literal = try XCTUnwrap(record.horizon)
            let limb = try XCTUnwrap(record.horizonUpperLimb)
            let observer = day.observer
            let margin: (Date) -> Double = { date in
                let frame = SkyFrame(date: date, observer: observer)
                let distance = frame.state(of: .moon).distanceKilometers
                let parallax = AstroMath.asinDeg(SkyFrame.earthEquatorialRadiusKilometers / distance)
                return frame.horizontal(of: .moon, refraction: false).altitude - (0.7275 * parallax - 0.5667)
            }
            let found = RiseSetCalculator.crossings(of: margin, threshold: 0, within: day.interval)
            assertCrossings(found, match: literal, tolerance: 3, "\(day.site) \(day.date) literal recipe")

            let correct = RiseSetCalculator.crossings(of: .moon, observer: observer, within: day.interval)
            guard found.count == correct.count else { continue }
            for (wrong, right) in zip(found, correct) {
                let delay = wrong.time.timeIntervalSince(right.time)
                XCTAssertGreaterThan(abs(delay), 150, "\(day.site) \(day.date)")
                XCTAssertLessThan(abs(delay), 1_100, "\(day.site) \(day.date)")
                XCTAssertEqual(delay > 0, right.kind == .rising, "\(day.site) \(day.date)")
                compared += 1
            }
            XCTAssertEqual(limb.crossings.count, correct.count)
        }
        XCTAssertGreaterThan(compared, 40)
    }

    func testPlanetsAndStarsMatch() throws {
        for day in try fixture() {
            for key in ["venus", "jupiter", "sirius", "vega"] {
                let label = "\(day.site) \(day.date) \(key)"
                let record = try XCTUnwrap(day.objects[key])
                let horizon = try XCTUnwrap(record.horizon)
                let tolerance = timeTolerance(for: key)
                let found: [AltitudeCrossing]
                let summary: RiseTransitSet
                let culminations: [AltitudeCulmination]
                if let body = SolarSystemBody(rawValue: key) {
                    found = RiseSetCalculator.crossings(of: body, observer: day.observer, within: day.interval)
                    summary = RiseSetCalculator.riseTransitSet(for: body, observer: day.observer, within: day.interval)
                    culminations = RiseSetCalculator.upperCulminations(of: body, observer: day.observer, within: day.interval)
                } else {
                    let (position, motion) = try XCTUnwrap(Self.stars[key])
                    found = RiseSetCalculator.crossings(ofJ2000: position, properMotion: motion,
                                                        observer: day.observer, within: day.interval)
                    summary = RiseSetCalculator.riseTransitSet(forJ2000: position, properMotion: motion,
                                                               observer: day.observer, within: day.interval)
                    culminations = RiseSetCalculator.upperCulminations(ofJ2000: position, properMotion: motion,
                                                                       observer: day.observer, within: day.interval)
                }
                assertCrossings(found, match: horizon, tolerance: tolerance, label + " horizon")
                assertSummary(summary, crossings: horizon, transits: record.transits, tolerance: tolerance, label + " summary")
                assertCulminations(culminations, match: record.transits, tolerance: tolerance, label + " culmination")
            }
        }
    }

    func testFixtureCoversPolarDayNightAndSingleEvents() throws {
        // Guards the fixture itself: the cases this suite is meant to exercise are present.
        var alwaysUp = 0, alwaysDown = 0, singleCrossing = 0
        for day in try fixture() {
            for record in day.objects.values {
                for horizon in [record.horizon, record.horizonUpperLimb, record.civil, record.nautical, record.astronomical] {
                    guard let horizon else { continue }
                    if horizon.alwaysUp { alwaysUp += 1 }
                    if horizon.alwaysDown { alwaysDown += 1 }
                    if horizon.crossings.count == 1 { singleCrossing += 1 }
                }
            }
        }
        XCTAssertGreaterThan(alwaysUp, 10)
        XCTAssertGreaterThan(alwaysDown, 3)
        XCTAssertGreaterThan(singleCrossing, 5)
    }
}

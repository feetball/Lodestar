import XCTest
@testable import LodestarKit

/// The planets in a night summary: which ones are up in the dark, how high they get and how bright they are.
final class PlanningPlanetTests: XCTestCase {
    private typealias Support = PlanningTestSupport
    private typealias Sets = NightPlanner.IntervalSet

    private let boulder = Support.boulder

    private func altitude(of body: SolarSystemBody, at date: Date, _ observer: Observer) -> Double {
        SkyFrame(date: date, observer: observer).horizontal(of: body, refraction: false).altitude
    }

    // MARK: Contents

    func testPlanetsRunFromMercuryToNeptune() throws {
        let summary = try Support.summary(boulder, 2026, 12, 14)
        XCTAssertEqual(summary.planets.map(\.body),
                       [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune])
        XCTAssertEqual(PlanetVisibility.minimumAltitude, 10)
    }

    func testEachPlanetCarriesTheCalculatorsEventsAndTheEphemerisMagnitude() throws {
        for site in [boulder, Support.sydney] {
            let summary = try Support.summary(site, 2026, 12, 14)
            let reference = JulianDate(date: summary.referenceDate)
            for planet in summary.planets {
                let label = "\(site.name) \(planet.body.displayName)"
                XCTAssertEqual(planet.riseTransitSet,
                               RiseSetCalculator.riseTransitSet(for: planet.body, observer: site.observer,
                                                                within: summary.night), label)
                XCTAssertEqual(planet.magnitude, Ephemeris.state(of: planet.body, at: reference).apparentMagnitude, label)
                XCTAssertNotNil(planet.magnitude, label)
            }
        }
    }

    func testMagnitudesAreInThePhysicalRanges() throws {
        let summary = try Support.summary(boulder, 2026, 12, 14)
        let limits: [SolarSystemBody: ClosedRange<Double>] = [
            .mercury: (-2.7)...6, .venus: (-4.95)...(-3.3), .mars: (-3)...2, .jupiter: (-3)...(-1.5),
            .saturn: (-0.6)...1.6, .uranus: 5.3...6.1, .neptune: 7.7...8.0,
        ]
        for planet in summary.planets {
            let magnitude = try XCTUnwrap(planet.magnitude, planet.body.displayName)
            XCTAssertTrue(try XCTUnwrap(limits[planet.body]).contains(magnitude), "\(planet.body.displayName) \(magnitude)")
        }
    }

    // MARK: A night with planets

    func testDecemberEveningSkyHoldsTheOuterPlanets() throws {
        // Boulder, 14 December 2026: Saturn, Uranus and Neptune are up in the evening; Mars and Jupiter climb
        // from the east before midnight; Venus is a morning object; Mercury is lost in the dawn.
        let summary = try Support.summary(boulder, 2026, 12, 14)
        let visible = Dictionary(uniqueKeysWithValues: summary.planets.map { ($0.body, $0.visibleDuringDarkness) })
        XCTAssertEqual(visible, [.mercury: false, .venus: true, .mars: true, .jupiter: true, .saturn: true,
                                 .uranus: true, .neptune: true])
        let night = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        let saturn = try XCTUnwrap(summary.planets.first { $0.body == .saturn })
        XCTAssertEqual(try XCTUnwrap(saturn.visibleIntervals.first).start, night.start, "up already at dusk")
        XCTAssertLessThan(try XCTUnwrap(saturn.visibleIntervals.last).end, night.end, "sets before dawn")
        let jupiter = try XCTUnwrap(summary.planets.first { $0.body == .jupiter })
        XCTAssertGreaterThan(try XCTUnwrap(jupiter.visibleIntervals.first).start, night.start, "rises after dusk")
        XCTAssertEqual(try XCTUnwrap(jupiter.visibleIntervals.last).end, night.end, "still up at dawn")
    }

    func testMercuryAndVenusStayOutOfTheDarkWhenTheyAreNearTheSun() throws {
        // Boulder, 14 June 2026: Mercury sets before astronomical dusk and Venus half an hour after it, too
        // low to count; the planner still reports when they go down.
        let summary = try Support.summary(boulder, 2026, 6, 14)
        let dusk = try XCTUnwrap(summary.twilight.astronomicalDusk)
        for body in [SolarSystemBody.mercury, .venus] {
            let planet = try XCTUnwrap(summary.planets.first { $0.body == body })
            XCTAssertFalse(planet.visibleDuringDarkness, body.displayName)
            XCTAssertTrue(planet.visibleIntervals.isEmpty, body.displayName)
            XCTAssertLessThan(try XCTUnwrap(planet.maxAltitudeDuringDarkness), PlanetVisibility.minimumAltitude, body.displayName)
            XCTAssertNotNil(planet.riseTransitSet.set, body.displayName)
            XCTAssertLessThan(try XCTUnwrap(planet.riseTransitSet.set), dusk.addingTimeInterval(3 * 3_600), body.displayName)
        }
    }

    func testPolarNightJudgesTheWholeWindow() throws {
        // Ten kilometres from the North Pole on 21 December the Sun stays near −23°: the whole 24 hours are
        // astronomically dark, and a planet's altitude hardly changes with the hour, so each one's highest
        // point of the window counts. Planets north of the celestial equator are up all night.
        let pole = Support.Site(name: "North Pole", latitude: 89.9, longitude: 0)
        let summary = try Support.summary(pole, 2026, 12, 21)
        XCTAssertEqual(summary.astronomicalDarknessIntervals, [summary.night])
        let observer = summary.observer
        for planet in summary.planets {
            let culminations = RiseSetCalculator.upperCulminations(of: planet.body, observer: observer,
                                                                   within: summary.night)
            let expected = ([altitude(of: planet.body, at: summary.night.start, observer),
                             altitude(of: planet.body, at: summary.night.end, observer)] + culminations.map(\.altitude)).max()
            XCTAssertEqual(try XCTUnwrap(planet.maxAltitudeDuringDarkness), try XCTUnwrap(expected), accuracy: 0.002,
                           planet.body.displayName)
            // At the pole the altitude is the declination, give or take the 0.1° of latitude.
            let middle = summary.night.start.addingTimeInterval(summary.night.duration / 2)
            let declination = SkyFrame(date: middle, observer: observer).topocentricEquatorial(of: planet.body).declination
            if declination > 10.5 {
                Support.assertIntervals(planet.visibleIntervals, [summary.night], accuracy: 1, planet.body.displayName)
            } else if declination < 9.5 {
                XCTAssertTrue(planet.visibleIntervals.isEmpty, planet.body.displayName)
            }
        }
        XCTAssertTrue(summary.planets.contains { $0.visibleDuringDarkness })
        XCTAssertTrue(summary.planets.contains { !$0.visibleDuringDarkness })
    }

    // MARK: Agreement with independent calculations

    /// The sine-sampled answers against direct altitudes: the visible stretches are bounded by the dark
    /// time and the 10° line, and the maximum is a culmination or an end of the dark time.
    func testPlanetAnswersAreConsistentWithDirectAltitudes() throws {
        let cases: [(Support.Site, Int, Int)] = [
            (boulder, 3, 20), (boulder, 9, 22), (boulder, 12, 21), (Support.sydney, 6, 21), (Support.sydney, 12, 21),
            (Support.quito, 3, 20), (Support.paranal, 9, 22), (Support.london, 12, 21),
        ]
        var visibleRecords = 0, hiddenRecords = 0
        for (site, month, day) in cases {
            let summary = try Support.summary(site, 2026, month, day)
            let observer = site.observer
            let darkness = summary.astronomicalDarknessIntervals
            let darkEdges = darkness.flatMap { [$0.start, $0.end] }
            for planet in summary.planets {
                let label = "\(site.name) 2026-\(month)-\(day) \(planet.body.displayName)"
                let body = planet.body
                if planet.visibleIntervals.isEmpty { hiddenRecords += 1 } else { visibleRecords += 1 }

                XCTAssertEqual(Sets.intersection(planet.visibleIntervals, darkness), planet.visibleIntervals, label)
                for interval in planet.visibleIntervals {
                    let middle = interval.start.addingTimeInterval(interval.duration / 2)
                    XCTAssertGreaterThanOrEqual(altitude(of: body, at: middle, observer), 10, label)
                    for edge in [interval.start, interval.end] where darkEdges.allSatisfy({ abs($0.timeIntervalSince(edge)) > 1 }) {
                        XCTAssertEqual(altitude(of: body, at: edge, observer), 10, accuracy: 0.01, "\(label): an edge at 10°")
                    }
                }
                for gap in Sets.subtracting(planet.visibleIntervals, from: darkness) {
                    let middle = gap.start.addingTimeInterval(gap.duration / 2)
                    XCTAssertLessThan(altitude(of: body, at: middle, observer), 10, label)
                }

                guard let maximum = planet.maxAltitudeDuringDarkness else {
                    XCTAssertTrue(darkness.isEmpty, label)
                    continue
                }
                let inDark = RiseSetCalculator.upperCulminations(of: body, observer: observer, within: summary.night)
                    .filter { culmination in darkness.contains { $0.contains(culmination.time) } }
                    .map(\.altitude)
                let ends = darkEdges.map { altitude(of: body, at: $0, observer) }
                XCTAssertEqual(maximum, try XCTUnwrap((inDark + ends).max()), accuracy: 0.002, label)
                if maximum > 10.01 { XCTAssertTrue(planet.visibleDuringDarkness, label) }
                if maximum < 9.99 { XCTAssertFalse(planet.visibleDuringDarkness, label) }
            }
        }
        XCTAssertGreaterThan(visibleRecords, 20)
        XCTAssertGreaterThan(hiddenRecords, 10)
    }

    func testVisibleStretchesMatchTheRootFinder() throws {
        // The root finder works on the same altitude function with a different method (bisection on the
        // true altitude instead of cubic interpolation of sines), so agreement to a second means the
        // interpolation is as good as claimed.
        for (site, month, day) in [(boulder, 12, 14), (Support.sydney, 12, 21)] {
            let summary = try Support.summary(site, 2026, month, day)
            for planet in summary.planets {
                let expected = Sets.intersection(
                    Support.intervals(above: 10, within: summary.night,
                                      altitude: { self.altitude(of: planet.body, at: $0, summary.observer) }),
                    summary.astronomicalDarknessIntervals)
                Support.assertIntervals(planet.visibleIntervals, expected, accuracy: 1,
                                        "\(site.name) \(planet.body.displayName)")
            }
        }
    }
}

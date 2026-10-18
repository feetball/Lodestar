import XCTest
@testable import LodestarKit

/// Conjunctions and close approaches.
///
/// References (JPL Horizons API, DE441, queried 2026-10-18; geocentric astrometric or apparent RA/Dec at 1–5 minute steps,
/// the minimum of the angular separation read off the table; Hipparcos places moved by their proper motion for the stars):
/// - Venus–Jupiter 2025-08-12 06:38 UT 0.8605°, 2026-06-09 19:48:45 UT 1.6081°.
/// - Moon–Venus 2026-06-17 20:30 UT 0.2697°, Moon–Jupiter 2026-10-06 10:24 UT 0.1582°, Moon–Mars 2026-11-02 13:40 UT 0.9661°,
///   Moon–Mercury 2026-02-18 23:10 UT 0.1194°, Venus–Saturn 2026-03-08 13:15 UT 0.9114°, Mars–Jupiter 2026-11-16 02:15 UT 1.1935°.
/// - Moon–Regulus 2026-05-23 07:18 UT 0.0696°, Moon–Spica 2026-01-10 23:10 UT 1.5033°, Moon–Antares 2026-01-14 20:02 UT 0.5520°,
///   Moon–Pleiades 2026-01-27 21:20 UT 1.0485°.
/// - Topocentric Moon–Venus on 2026-06-17 (SITE_COORD, apparent RA/Dec at 1 minute): Dallas 19:56 UT 0.1583°,
///   Sydney 19:32 UT 0.7328°.
final class EventsConjunctionTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private func conjunctions(_ from: String, _ to: String, options: EventOptions = EventOptions(),
                              observer: Observer? = nil) -> [(AstronomicalEvent, Conjunction)] {
        Support.conjunctions(ConjunctionFinder.events(from: Support.utc(from), to: Support.utc(to), observer: observer,
                                                      options: options))
    }

    private func find(_ found: [(AstronomicalEvent, Conjunction)], _ first: ConjunctionTarget, _ second: ConjunctionTarget,
                      near: String, file: StaticString = #filePath, line: UInt = #line) -> (AstronomicalEvent, Conjunction)? {
        let moment = Support.utc(near)
        let match = found.filter { $0.1.first == first && $0.1.second == second }
            .min { abs(Support.seconds($0.0.date, moment)) < abs(Support.seconds($1.0.date, moment)) }
        XCTAssertNotNil(match, "\(first) \(second) near \(near)", file: file, line: line)
        return match
    }

    private func body(_ body: SolarSystemBody) -> ConjunctionTarget { .body(body) }

    private func star(_ star: ReferenceStar) -> ConjunctionTarget { .star(star) }

    func testJupiterVenusConjunctionsOf2025And2026() throws {
        // The brief: Jupiter–Venus 2025-08-12 and 2026-06-09. Venus comes first in the planet order only after Mercury.
        let found = conjunctions("2025-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        let august = try XCTUnwrap(find(found, body(.venus), body(.jupiter), near: "2025-08-12T06:38:00Z"))
        Support.assertInstant("2025-08-12T06:38:40Z", august.0.date, tolerance: 240, "2025")
        Support.assertNear(0.8605, august.1.separation, tolerance: 0.002, "2025 separation")
        XCTAssertTrue(august.1.solarElongation > 30 && august.1.solarElongation < 40)
        XCTAssertTrue(!august.1.involvesMoon && !august.1.occultationPossible)
        let june = try XCTUnwrap(find(found, body(.venus), body(.jupiter), near: "2026-06-09T19:48:45Z"))
        Support.assertInstant("2026-06-09T19:48:45Z", june.0.date, tolerance: 240, "2026")
        Support.assertNear(1.6081, june.1.separation, tolerance: 0.002, "2026 separation")
        // Both are within the default planet threshold of 3°; they are the only Venus–Jupiter conjunctions of the two years.
        XCTAssertEqual(found.filter { $0.1.first == body(.venus) && $0.1.second == body(.jupiter) }.count, 2)
    }

    func testMoonAndPlanetConjunctionsAgainstHorizons() throws {
        let found = conjunctions("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        let moon = body(.moon)
        let references: [(SolarSystemBody, String, Double)] = [
            (.venus, "2026-06-17T20:30:00Z", 0.2697),
            (.jupiter, "2026-10-06T10:24:00Z", 0.1582),
            (.mars, "2026-11-02T13:40:00Z", 0.9661),
            (.mercury, "2026-02-18T23:10:00Z", 0.1194),
        ]
        for (planet, time, separation) in references {
            let event = try XCTUnwrap(find(found, moon, body(planet), near: time))
            Support.assertInstant(time, event.0.date, tolerance: 180, "Moon–\(planet)")
            Support.assertNear(separation, event.1.separation, tolerance: 0.003, "Moon–\(planet) separation")
            XCTAssertTrue(event.1.involvesMoon)
        }
    }

    func testPlanetPairsAgainstHorizons() throws {
        let found = conjunctions("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        let saturn = try XCTUnwrap(find(found, body(.venus), body(.saturn), near: "2026-03-08T13:15:00Z"))
        Support.assertInstant("2026-03-08T13:15:00Z", saturn.0.date, tolerance: 300, "Venus–Saturn")
        Support.assertNear(0.9114, saturn.1.separation, tolerance: 0.003, "Venus–Saturn separation")
        // Mars and Jupiter 1.19° apart in November (they move slowly relative to each other: ten minutes is nothing).
        let jupiter = try XCTUnwrap(find(found, body(.mars), body(.jupiter), near: "2026-11-16T02:15:00Z"))
        Support.assertInstant("2026-11-16T02:15:00Z", jupiter.0.date, tolerance: 1_200, "Mars–Jupiter")
        Support.assertNear(1.1935, jupiter.1.separation, tolerance: 0.003, "Mars–Jupiter separation")
    }

    func testMoonWithBrightStarsAndThePleiades() throws {
        let found = conjunctions("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        let moon = body(.moon)
        let references: [(ReferenceStar, String, Double)] = [
            (.regulus, "2026-05-23T07:18:00Z", 0.0696),
            (.spica, "2026-01-10T23:10:00Z", 1.5033),
            (.antares, "2026-01-14T20:02:00Z", 0.5520),
            (.pleiades, "2026-01-27T21:20:00Z", 1.0485),
        ]
        for (reference, time, separation) in references {
            let event = try XCTUnwrap(find(found, moon, star(reference), near: time))
            Support.assertInstant(time, event.0.date, tolerance: 180, "Moon–\(reference.displayName)")
            Support.assertNear(separation, event.1.separation, tolerance: 0.003, "Moon–\(reference.displayName) separation")
        }
        // The Moon passes Regulus, Spica and Antares every month (the Moon is within 5° of the ecliptic and these stars
        // are within 2.1° of it), the Pleiades whenever the Moon is far enough north, and Aldebaran (5.5° south of the
        // ecliptic) not at all in 2026, when the ascending node is near the equinox.
        for reference in [ReferenceStar.regulus, .spica, .antares] {
            XCTAssertTrue(found.filter { $0.1.second == star(reference) }.count >= 12, reference.displayName)
        }
        XCTAssertEqual(found.filter { $0.1.second == star(.aldebaran) }.count, 0)
    }

    func testOccultationPossibleFlag() throws {
        let found = conjunctions("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")
        let regulus = try XCTUnwrap(find(found, body(.moon), star(.regulus), near: "2026-05-23T07:18:00Z"))
        XCTAssertTrue(regulus.1.occultationPossible, "0.07° apart: the Moon's disc covers Regulus from somewhere")
        let spica = try XCTUnwrap(find(found, body(.moon), star(.spica), near: "2026-01-10T23:10:00Z"))
        XCTAssertTrue(!spica.1.occultationPossible, "1.5° apart is beyond the Moon's radius and parallax")
        for (_, conjunction) in found where !conjunction.involvesMoon {
            XCTAssertTrue(!conjunction.occultationPossible)
        }
    }

    func testTopocentricApproachAgainstHorizons() throws {
        // 2026-06-17: the Moon's parallax moves it by up to a degree against Venus: Dallas sees them 0.158° apart at
        // 19:56 UT, Sydney 0.733° at 19:32 UT (Horizons), against 0.270° from the Earth's centre at 20:30 UT.
        let dallas = conjunctions("2026-06-15T00:00:00Z", "2026-06-19T00:00:00Z", observer: Support.dallas.observer)
        let venusFromDallas = try XCTUnwrap(find(dallas, body(.moon), body(.venus), near: "2026-06-17T20:30:00Z"))
        let topocentricDallas = try XCTUnwrap(venusFromDallas.1.topocentric)
        Support.assertInstant("2026-06-17T19:56:00Z", topocentricDallas.time, tolerance: 180, "Dallas time")
        Support.assertNear(0.1583, topocentricDallas.separation, tolerance: 0.005, "Dallas separation")
        XCTAssertTrue(!topocentricDallas.isOccultation || topocentricDallas.separation < 0.4)
        let sydney = conjunctions("2026-06-15T00:00:00Z", "2026-06-19T00:00:00Z", observer: Support.sydney.observer)
        let venusFromSydney = try XCTUnwrap(find(sydney, body(.moon), body(.venus), near: "2026-06-17T20:30:00Z"))
        let topocentricSydney = try XCTUnwrap(venusFromSydney.1.topocentric)
        Support.assertInstant("2026-06-17T19:32:00Z", topocentricSydney.time, tolerance: 180, "Sydney time")
        Support.assertNear(0.7328, topocentricSydney.separation, tolerance: 0.005, "Sydney separation")
        XCTAssertTrue(!topocentricSydney.isOccultation)
        Support.assertNear(0.2697, venusFromDallas.1.separation, tolerance: 0.003, "geocentric separation")
        // Without an observer there is no topocentric note, and planet pairs never have one.
        let geocentric = conjunctions("2026-06-15T00:00:00Z", "2026-06-19T00:00:00Z")
        XCTAssertTrue(geocentric.allSatisfy { $0.1.topocentric == nil })
        XCTAssertTrue(dallas.filter { !$0.1.involvesMoon }.allSatisfy { $0.1.topocentric == nil })
    }

    func testTopocentricOccultationOfRegulusInTheSouthPacific() throws {
        // Scanning the Earth on a 4° grid, the Moon's disc covers Regulus on 2026-05-23 along a band through the South
        // Pacific (e.g. 36S 128W, 0.08° at closest). A site in the band reports an occultation, Dallas does not.
        let band = Observer(location: GeographicLocation(latitude: -36, longitude: -128, elevation: 0))
        let found = conjunctions("2026-05-22T00:00:00Z", "2026-05-24T00:00:00Z", observer: band)
        let regulus = try XCTUnwrap(find(found, body(.moon), star(.regulus), near: "2026-05-23T07:18:00Z"))
        let approach = try XCTUnwrap(regulus.1.topocentric)
        XCTAssertTrue(approach.separation < 0.15, "separation \(approach.separation)")
        XCTAssertTrue(approach.isOccultation)
        let dallas = conjunctions("2026-05-22T00:00:00Z", "2026-05-24T00:00:00Z", observer: Support.dallas.observer)
        let dallasRegulus = try XCTUnwrap(find(dallas, body(.moon), star(.regulus), near: "2026-05-23T07:18:00Z"))
        let approachDallas = try XCTUnwrap(dallasRegulus.1.topocentric)
        XCTAssertTrue(!approachDallas.isOccultation && approachDallas.separation > 0.3)
    }

    func testThresholdsAndElongationFilterSelectConjunctions() {
        let from = "2026-01-01T00:00:00Z"
        let to = "2026-12-31T23:59:59Z"
        let defaults = conjunctions(from, to)
        for (event, conjunction) in defaults {
            let limit = conjunction.involvesMoon ? 5.0 : 3.0
            XCTAssertTrue(conjunction.separation <= limit, "\(event.date) \(conjunction.separation)")
            XCTAssertTrue(conjunction.solarElongation >= 10.0, "\(event.date) elongation \(conjunction.solarElongation)")
        }
        // Tighter thresholds keep a subset; nothing farther apart than the threshold survives.
        let tight = conjunctions(from, to, options: EventOptions(planetConjunctionThreshold: 1, moonConjunctionThreshold: 1))
        XCTAssertTrue(tight.count < defaults.count)
        XCTAssertTrue(tight.allSatisfy { $0.1.separation <= 1.0 })
        let defaultTimes = Set(defaults.map { $0.0.date })
        XCTAssertTrue(tight.allSatisfy { defaultTimes.contains($0.0.date) })
        // Looser thresholds and no elongation limit find more, including conjunctions in the Sun's glare.
        let loose = conjunctions(from, to, options: EventOptions(planetConjunctionThreshold: 5, moonConjunctionThreshold: 8,
                                                                  minimumSolarElongation: 0))
        XCTAssertTrue(loose.count > defaults.count)
        XCTAssertTrue(loose.contains { $0.1.solarElongation < 10 })
        // The Moon passes close to something about every other day.
        XCTAssertTrue((90...125).contains(defaults.filter { $0.1.involvesMoon }.count))
    }

    func testConjunctionsAreSortedAndOrdered() {
        let found = ConjunctionFinder.events(from: Support.utc("2026-01-01T00:00:00Z"), to: Support.utc("2026-12-31T23:59:59Z"))
        for index in 1..<found.count { XCTAssertTrue(found[index].date >= found[index - 1].date) }
        for (_, conjunction) in Support.conjunctions(found) {
            if conjunction.involvesMoon {
                XCTAssertTrue(conjunction.second != body(.moon))
            } else if case let .body(first) = conjunction.first, case let .body(second) = conjunction.second {
                XCTAssertTrue((SolarSystemBody.allCases.firstIndex(of: first) ?? 0) < (SolarSystemBody.allCases.firstIndex(of: second) ?? 0))
            } else {
                XCTFail("a planet pair has two bodies")
            }
        }
    }

    func testConjunctionIsALocalMinimumOfTheSeparation() {
        for (event, conjunction) in conjunctions("2026-03-01T00:00:00Z", "2026-06-30T00:00:00Z") {
            func separation(_ offsetDays: Double) -> Double {
                let jd = JulianDate(date: event.date).addingDays(offsetDays)
                func vector(_ target: ConjunctionTarget) -> Vector3 {
                    switch target {
                    case let .body(body): Ephemeris.geocentricJ2000(of: body, at: jd)
                    case let .star(star): star.position.unitVector
                    }
                }
                return vector(conjunction.first).angle(to: vector(conjunction.second))
            }
            let step = conjunction.involvesMoon ? 0.1 : 1.0
            XCTAssertTrue(separation(0) <= separation(-step) + 1e-6 && separation(0) <= separation(step) + 1e-6, "\(event.date)")
            Support.assertNear(conjunction.separation, separation(0), tolerance: 0.01, "\(event.date) separation")
        }
    }

    func testTargetsDescribeWhatToAimAt() {
        let venus = body(.venus)
        XCTAssertEqual(venus.displayName, "Venus")
        XCTAssertEqual(venus.aimTarget, .body(.venus))
        let antares = star(.antares)
        XCTAssertEqual(antares.displayName, "Antares")
        XCTAssertEqual(antares.aimTarget, .fixed(ReferenceStar.antares.position, ReferenceStar.antares.properMotion))
        XCTAssertEqual(ReferenceStar.allCases.count, 5)
        XCTAssertEqual(ReferenceStar(rawValue: "pleiades"), .pleiades)
        XCTAssertNil(ReferenceStar(rawValue: "sirius"))
        // The kit's catalog gives the same J2000 places to the milliarcsecond.
        Support.assertNear(152.092967, ReferenceStar.regulus.position.rightAscension, tolerance: 1e-6, "Regulus RA")
        Support.assertNear(-26.432002, ReferenceStar.antares.position.declination, tolerance: 1e-6, "Antares Dec")
    }

    func testEmptyRangesAndTheEdgesOfARange() {
        let moment = Support.utc("2026-06-09T19:48:45Z")
        XCTAssertTrue(ConjunctionFinder.events(from: moment, to: moment.addingTimeInterval(-1)).isEmpty)
        // A range that ends just before the Venus–Jupiter conjunction does not contain it; one that starts just after neither.
        func venusJupiter(_ found: [(AstronomicalEvent, Conjunction)]) -> Int {
            found.filter { $0.1.first == body(.venus) && $0.1.second == body(.jupiter) }.count
        }
        XCTAssertEqual(venusJupiter(conjunctions("2026-06-09T00:00:00Z", "2026-06-09T19:00:00Z")), 0)
        XCTAssertEqual(venusJupiter(conjunctions("2026-06-09T20:30:00Z", "2026-06-10T12:00:00Z")), 0)
        XCTAssertEqual(venusJupiter(conjunctions("2026-06-09T19:00:00Z", "2026-06-09T20:30:00Z")), 1)
    }
}

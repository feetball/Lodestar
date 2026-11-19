import XCTest
@testable import LodestarKit

/// Jupiter's physical ephemeris, the Galilean moons and the Great Red Spot.
///
/// References:
/// - Meeus, *Astronomical Algorithms* (2nd ed.), Example 43.a (physical ephemeris of Jupiter, 1992 December 16, 0h TD,
///   JDE 2448972.50068): ω1 = 268.06°, ω2 = 72.74°, DE = −2.48°, DS = −2.20°, P = 24.80°; Example 43.b (the low-accuracy
///   formulae of the same chapter): DS = −2.19°, DE = −2.50°.
/// - Meeus, Example 44.a (satellites of Jupiter, the same instant): X, Y of Io −3.44 +0.21, Europa +7.44 +0.25,
///   Ganymede +1.24 +0.65, Callisto +7.08 +1.10, and the exercise of 1988 November 23 (Callisto and Ganymede at
///   conjunction with Jupiter's centre).
/// - Flandrau Science Center (Tucson), *Skywatcher's Guide: April and May 2026*, Great Red Spot meridian transits
///   from Sky & Telescope's tool for 2026 (91° on June 1, 1.75° a month), local times MST (UTC−7).
final class EphemerisJupiterTests: XCTestCase {
    private func utc(_ text: String) -> Date { EventsTestSupport.utc(text) }

    private func assertNear(_ expected: Double, _ actual: Double, _ tolerance: Double, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(expected - actual) <= tolerance, "\(label): \(actual) differs from \(expected) by more than \(tolerance)",
                      file: file, line: line)
    }

    private let example = JulianDate(tt: 2_448_972.50068)

    // MARK: Physical ephemeris

    func testJupiterPhysicalMatchesMeeusExample43a() {
        let state = JupiterPhysical.state(at: example)
        assertNear(268.06, state.systemILongitude, 0.03, "ω1")
        assertNear(72.74, state.systemIILongitude, 0.03, "ω2")
        assertNear(-2.48, state.earthDeclination, 0.01, "DE")
        assertNear(-2.20, state.sunDeclination, 0.01, "DS")
        assertNear(24.80, state.positionAngle, 0.03, "P")
        assertNear(5.6, state.distanceAU, 0.5, "Δ")
    }

    func testCentralMeridiansAdvanceAtTheRotationRates() {
        let first = JupiterPhysical.state(at: JulianDate(ut: 2_461_000.0))
        let second = JupiterPhysical.state(at: JulianDate(ut: 2_461_000.0 + 1.0 / 24))
        // System I turns 877.9° a day and System II 870.27°: 36.58° and 36.26° an hour (the light-time wiggle is tiny).
        assertNear(36.58, AstroMath.normalizeDegrees(second.systemILongitude - first.systemILongitude), 0.02, "I per hour")
        assertNear(36.26, AstroMath.normalizeDegrees(second.systemIILongitude - first.systemIILongitude), 0.02, "II per hour")
        for state in [first, second] {
            XCTAssertTrue((0.0...360.0).contains(state.systemILongitude) && (0.0...360.0).contains(state.systemIILongitude))
            XCTAssertTrue(abs(state.earthDeclination) < 4 && abs(state.sunDeclination) < 4)
            XCTAssertTrue((0.0...360.0).contains(state.positionAngle))
        }
    }

    // MARK: Galilean moons

    func testGalileanMoonsMatchMeeusExample44a() {
        let state = GalileanMoons.positions(at: example)
        XCTAssertEqual(state.moons.map(\.moon), [.io, .europa, .ganymede, .callisto])
        let expected = [(-3.44, 0.21), (7.44, 0.25), (1.24, 0.65), (7.08, 1.10)]
        for (index, moon) in state.moons.enumerated() {
            assertNear(expected[index].0, moon.x, 0.006, "\(moon.moon) X")
            assertNear(expected[index].1, moon.y, 0.006, "\(moon.moon) Y")
        }
        assertNear(-2.50, state.earthDeclination, 0.01, "DE of example 43.b")
        assertNear(-2.19, state.sunDeclination, 0.01, "DS of example 43.b")
    }

    func testGalileanMoonsConjunctionExerciseOfMeeus() {
        // Meeus's exercise (1988 November 23, times in UT): Ganymede (III) crosses X = 0 at 7h28m with Y = -0.84 and
        // Callisto (IV) at 5h15m with X = +0.06, Y = +1.48.
        let ganymede = GalileanMoons.positions(at: JulianDate(date: utc("1988-11-23T07:28:00Z"))).moons[2]
        assertNear(0.0, ganymede.x, 0.02, "Ganymede X")
        assertNear(-0.84, ganymede.y, 0.02, "Ganymede Y")
        let callisto = GalileanMoons.positions(at: JulianDate(date: utc("1988-11-23T05:15:00Z"))).moons[3]
        assertNear(0.06, callisto.x, 0.02, "Callisto X")
        assertNear(1.48, callisto.y, 0.02, "Callisto Y")
    }

    func testGalileanMoonsAgreeWithJplHorizons() {
        // JPL Horizons vector tables (jup365 satellites, DE441 Jupiter, Sun and Earth; queried 2026-11-19) turned into
        // Jupiter's axes (X west along the equator of the IAU 2015 pole, Y north) as seen from the geocentre: the four
        // moons 2615 s of light-time before 2026-11-19 00:42:15.8 UTC, in Jupiter radii (equatorial 71 492 km).
        let truth = [(0.889, 0.027), (-2.349, -0.111), (4.544, 0.062), (-20.011, -0.028)]
        let state = GalileanMoons.positions(at: JulianDate(date: utc("2026-11-19T00:42:15.8Z")))
        for (index, moon) in state.moons.enumerated() {
            assertNear(truth[index].0, moon.x, 0.12, "\(moon.moon) X")
            assertNear(truth[index].1, moon.y, 0.15, "\(moon.moon) Y")
        }
    }

    func testGalileanMoonEventsAgreeWithJplHorizons() {
        // The same Horizons vectors give the contacts of the phenomena (transit: the centre inside the disc in front;
        // shadow transit: the centre of the shadow on the visible hemisphere; occultation and eclipse likewise), found
        // on a 2-minute grid and quoted at the middle of the step, observer time. The low-accuracy method agrees to
        // about 2 minutes for Io and Europa and 6 for Callisto (139 events in three six-day windows from 2026-11-19 to
        // 2027-02-16: rms 1.8 minutes, worst 6 minutes), the basis of `GalileanMoons.accuracyMinutes`.
        let truth: [(GalileanMoon, GalileanPhenomenon, GalileanEdge, String)] = [
            (.io, .transit, .end, "2026-11-19T00:49:15Z"),
            (.io, .eclipse, .start, "2026-11-19T18:27:10Z"),
            (.io, .occultation, .start, "2026-11-19T19:43:09Z"),
            (.europa, .shadowTransit, .start, "2026-11-20T11:45:04Z"),
            (.europa, .transit, .start, "2026-11-20T14:19:03Z"),
            (.io, .shadowTransit, .start, "2026-11-20T15:47:03Z"),
            (.io, .transit, .start, "2026-11-20T17:01:03Z"),
            (.ganymede, .eclipse, .start, "2026-11-21T23:12:53Z"),
        ]
        let events = GalileanMoons.events(from: utc("2026-11-19T00:00:00Z"), to: utc("2026-11-23T00:00:00Z"))
        for (moon, phenomenon, edge, expected) in truth {
            let nearest = events.filter { $0.moon == moon && $0.phenomenon == phenomenon && $0.edge == edge }
                .map { abs($0.date.timeIntervalSince(utc(expected))) }.min()
            XCTAssertTrue((nearest ?? .infinity) <= 6.5 * 60, "\(moon) \(phenomenon) \(edge): \(nearest ?? -1) s from \(expected)")
        }
    }

    func testMoonOffsetsStayOnTheirOrbits() {
        let radii = [5.9057, 9.3966, 14.9883, 26.3627]
        for day in 0..<40 {
            let state = GalileanMoons.positions(at: JulianDate(ut: 2_461_000.5 + Double(day) * 0.9))
            for (index, moon) in state.moons.enumerated() {
                let distance = (moon.x * moon.x + moon.y * moon.y + moon.z * moon.z).squareRoot()
                assertNear(radii[index], distance, 0.2, "\(moon.moon) distance")
                XCTAssertEqual(moon.isInTransit, moon.x * moon.x + moon.y * moon.y < 1 && moon.z > 0)
                XCTAssertFalse(moon.isInTransit && moon.isBehindDisc)
            }
        }
    }

    func testMoonPhenomenaStartBeforeTheyEnd() {
        let from = utc("2026-11-19T00:00:00Z")
        let events = GalileanMoons.events(from: from, to: utc("2026-11-29T00:00:00Z"))
        XCTAssertTrue(events.count > 40, "events: \(events.count)")
        XCTAssertEqual(events.sorted { $0.date < $1.date }, events)
        XCTAssertTrue(events.allSatisfy { $0.date >= from && $0.date <= utc("2026-11-29T00:00:00Z") })
        for moon in GalileanMoon.allCases {
            for phenomenon in GalileanPhenomenon.allCases {
                let series = events.filter { $0.moon == moon && $0.phenomenon == phenomenon }
                // Edges alternate, and a phenomenon that is under way at the start of the search begins with an end.
                for (previous, next) in zip(series, series.dropFirst()) {
                    XCTAssertTrue(previous.edge != next.edge, "\(moon) \(phenomenon) alternates")
                }
                for start in series where start.edge == .start {
                    guard let end = series.first(where: { $0.edge == .end && $0.date > start.date }) else { continue }
                    let minutes = end.date.timeIntervalSince(start.date) / 60
                    XCTAssertTrue((20.0...800.0).contains(minutes), "\(moon) \(phenomenon) lasts \(minutes) min")
                }
            }
        }
    }

    func testIoTransitsRepeatEveryOrbit() {
        let starts = GalileanMoons.events(from: utc("2026-11-19T00:00:00Z"), to: utc("2026-12-19T00:00:00Z"))
            .filter { $0.moon == .io && $0.phenomenon == .transit && $0.edge == .start }
        XCTAssertTrue((16...18).contains(starts.count), "Io transits: \(starts.count)")
        for (previous, next) in zip(starts, starts.dropFirst()) {
            let days = next.date.timeIntervalSince(previous.date) / 86_400
            // Io's synodic period is 1.7699 days.
            assertNear(1.7699, days, 0.08, "Io transit spacing")
        }
    }

    func testShadowTransitAndTransitAreSeparatedByTheGeometry() {
        // Io's shadow enters the disc before Io itself leads or trails it by a fraction of its orbit, never by more than
        // a quarter: the shadow lies within about a 12° phase angle of the moon's own line of sight.
        let events = GalileanMoons.events(from: utc("2026-11-19T00:00:00Z"), to: utc("2026-11-29T00:00:00Z"))
        let transits = events.filter { $0.moon == .io && $0.phenomenon == .transit && $0.edge == .start }
        let shadows = events.filter { $0.moon == .io && $0.phenomenon == .shadowTransit && $0.edge == .start }
        XCTAssertTrue(!transits.isEmpty && !shadows.isEmpty)
        for shadow in shadows {
            let nearest = transits.map { abs($0.date.timeIntervalSince(shadow.date)) }.min() ?? .infinity
            XCTAssertTrue(nearest < 0.25 * 1.77 * 86_400, "shadow is \(nearest) s from the nearest transit")
        }
    }

    func testMoonEventsEdgeCases() throws {
        let from = utc("2026-11-19T00:00:00Z")
        XCTAssertTrue(GalileanMoons.events(from: utc("2026-11-20T00:00:00Z"), to: from).isEmpty)
        XCTAssertTrue(GalileanMoons.events(from: from, to: from).isEmpty)
        // Longer intervals are cut at the limit.
        let cut = GalileanMoons.events(from: from, to: utc("2027-11-19T00:00:00Z"))
        XCTAssertTrue(try XCTUnwrap(cut.last).date <= from.addingTimeInterval(GalileanMoons.maximumSpanDays * 86_400))
        let event = GalileanMoonEvent(moon: .io, phenomenon: .shadowTransit, edge: .start, date: from)
        XCTAssertEqual(event.title, "Io's shadow enters the disc")
        XCTAssertEqual(GalileanMoonEvent(moon: .europa, phenomenon: .occultation, edge: .end, date: from).title,
                       "Europa reappears from behind Jupiter")
        XCTAssertEqual(GalileanMoonEvent(moon: .callisto, phenomenon: .eclipse, edge: .start, date: from).title,
                       "Callisto enters Jupiter's shadow")
        XCTAssertEqual(GalileanMoonEvent(moon: .ganymede, phenomenon: .transit, edge: .end, date: from).title,
                       "Ganymede leaves the disc")
        XCTAssertEqual(GalileanMoon.allCases.map(\.initial), ["I", "E", "G", "C"])
        for moon in GalileanMoon.allCases {
            XCTAssertEqual(GalileanMoon(rawValue: moon.rawValue), moon)
            XCTAssertEqual(String(decoding: try JSONEncoder().encode(moon), as: UTF8.self), "\"\(moon.rawValue)\"")
        }
        XCTAssertNil(GalileanMoon(rawValue: "titan"))
        XCTAssertEqual(GalileanPhenomenon(rawValue: "eclipse"), .eclipse)
        XCTAssertEqual(GalileanEdge(rawValue: "end"), .end)
    }

    // MARK: Great Red Spot

    func testGreatRedSpotTransitsAreAboutTenHoursApart() {
        let transits = GreatRedSpot.reference.transits(from: utc("2026-11-19T00:00:00Z"), to: utc("2026-11-22T00:00:00Z"))
        XCTAssertTrue((7...8).contains(transits.count), "transits: \(transits.count)")
        for (previous, next) in zip(transits, transits.dropFirst()) {
            let minutes = next.date.timeIntervalSince(previous.date) / 60
            // System II turns once in 9 h 55.7 min (360° at 870.27° a day, a little longer as the spot drifts east).
            assertNear(9 * 60 + 55.7, minutes, 0.5, "spacing")
        }
        for transit in transits {
            let jupiter = JupiterPhysical.state(at: JulianDate(date: transit.date))
            assertNear(transit.longitude, jupiter.systemIILongitude, 0.001, "CM II at the transit")
            XCTAssertEqual(transit.wellPlaced.duration, 100.0 * 60, accuracy: 1e-6)
            XCTAssertEqual(transit.date, transit.wellPlaced.start.addingTimeInterval(50 * 60.0))
        }
    }

    func testCentralMeridianAgreesWithPublishedGreatRedSpotTransitTimes() {
        // Flandrau Science Center, Tucson (MST = UTC-7): meridian transit 2026-04-05 20:18, 04-07 21:57, 04-10 19:28
        // and 05-30 21:03 local time (to the minute). The table's own longitude for the spot is not stated (it is not
        // Sky & Telescope's 91° on June 1: that would put the transits 5 to 10 minutes later), so the check is that the
        // System II central meridian stands at one longitude, drifting slowly, at the four instants: 84.4°, 84.4°, 84.7°
        // and 85.0° (the spot's drift of about 0.4° a month in their table).
        let published = [("2026-04-06T03:18:00Z", 84.4), ("2026-04-08T04:57:00Z", 84.4), ("2026-04-11T02:28:00Z", 84.7),
                         ("2026-05-31T04:03:00Z", 85.0)]
        for (text, longitude) in published {
            let meridian = JupiterPhysical.state(at: JulianDate(date: utc(text))).systemIILongitude
            assertNear(longitude, meridian, 0.3, text)
        }
    }

    func testGreatRedSpotLongitudeDriftsFromTheEpoch() throws {
        let spot = GreatRedSpot.reference
        assertNear(91.0, spot.systemIILongitude(at: GreatRedSpot.referenceEpoch), 1e-9, "epoch")
        assertNear(91.0 + 1.75, spot.systemIILongitude(at: GreatRedSpot.referenceEpoch.addingTimeInterval(30 * 86_400)), 1e-9, "30 days")
        assertNear(91.0 - 1.75 / 30 * 61, spot.systemIILongitude(at: utc("2026-04-01T00:00:00Z")), 1e-9, "before")
        let wrapped = try XCTUnwrap(GreatRedSpot(longitude: -10, epoch: utc("2026-06-01T00:00:00Z"), driftPer30Days: 0))
        assertNear(350.0, wrapped.longitude, 1e-9, "normalized")
        assertNear(350.0, wrapped.systemIILongitude(at: utc("2030-01-01T00:00:00Z")), 1e-9, "no drift")
    }

    func testGreatRedSpotTransitMovesWithTheLongitude() throws {
        // 1° of longitude is 1.65 minutes of transit time.
        let day = utc("2026-11-19T00:00:00Z")
        let epoch = utc("2026-11-19T00:00:00Z")
        let first = try XCTUnwrap(GreatRedSpot(longitude: 100, epoch: epoch, driftPer30Days: 0))
            .transits(from: day, to: day.addingTimeInterval(86_400))
        let second = try XCTUnwrap(GreatRedSpot(longitude: 110, epoch: epoch, driftPer30Days: 0))
            .transits(from: day, to: day.addingTimeInterval(86_400))
        let shift = second[0].date.timeIntervalSince(first[0].date) / 60
        // Ten degrees later in longitude means the planet has to turn 10° further: 16.5 minutes later (or a period earlier).
        let period = 9.0 * 60 + 55.7
        var wrapped = shift.truncatingRemainder(dividingBy: period)
        wrapped = (wrapped + period).truncatingRemainder(dividingBy: period)
        assertNear(16.5, wrapped, 0.4, "shift")
    }

    func testGreatRedSpotValidationAndLimits() {
        let epoch = utc("2026-06-01T00:00:00Z")
        XCTAssertNil(GreatRedSpot(longitude: .nan, epoch: epoch))
        XCTAssertNil(GreatRedSpot(longitude: 100, epoch: epoch, driftPer30Days: .infinity))
        XCTAssertNil(GreatRedSpot(longitude: 100, epoch: epoch, driftPer30Days: 31))
        XCTAssertNil(GreatRedSpot(longitude: 100, epoch: .distantFuture.addingTimeInterval(1)))
        XCTAssertNotNil(GreatRedSpot(longitude: 100, epoch: epoch, driftPer30Days: -30))
        let spot = GreatRedSpot.reference
        let from = utc("2026-11-19T00:00:00Z")
        XCTAssertTrue(spot.transits(from: utc("2026-11-20T00:00:00Z"), to: from).isEmpty)
        let year = spot.transits(from: from, to: utc("2030-01-01T00:00:00Z"))
        XCTAssertTrue((880...890).contains(year.count), "a capped year: \(year.count)")
        XCTAssertTrue(year.last.map { $0.date <= from.addingTimeInterval(GreatRedSpot.maximumSpanDays * 86_400) } ?? false)
        XCTAssertEqual(GreatRedSpot.wellPlacedMinutes, 50.0)
    }
}

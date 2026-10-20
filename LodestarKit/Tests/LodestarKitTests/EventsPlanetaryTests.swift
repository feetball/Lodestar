import XCTest
@testable import LodestarKit

/// Oppositions, greatest elongations, equinoxes and solstices, and the Earth's apsides.
///
/// References:
/// - JPL Horizons API (https://ssd.jpl.nasa.gov/api/horizons.api, DE441), geocentric observer tables at 1 h steps queried
///   2026-10-18: apparent ecliptic longitudes (quantity 31) of the planet and of the Sun, whose difference passes 180° at
///   an opposition; and the Sun–observer–target angle (quantity 23), whose maximum is the greatest elongation (found as
///   the zero of its central difference over 24 h).
/// - U.S. Naval Observatory, *Earth's Seasons* (https://aa.usno.navy.mil/api/seasons?year=2026): equinoxes, solstices,
///   perihelion and aphelion to the minute, UT.
final class EventsPlanetaryTests: XCTestCase {
    private typealias Support = EventsTestSupport

    private func events(_ finder: (Date, Date) -> [AstronomicalEvent], _ from: String, _ to: String) -> [AstronomicalEvent] {
        finder(Support.utc(from), Support.utc(to))
    }

    // MARK: Oppositions

    func testMarsOppositionsAgainstHorizons() {
        // Horizons: Mars opposition 2025-01-16 02:38:35 UT (Sun at 296.23°), 2027-02-19 15:50:55 UT.
        let found = Support.oppositions(events({ OppositionFinder.events(from: $0, to: $1) }, "2025-01-01T00:00:00Z", "2027-12-31T23:59:59Z"))
        let mars = found.filter { $0.1.planet == .mars }
        XCTAssertEqual(mars.count, 2)
        guard mars.count == 2 else { return }
        Support.assertInstant("2025-01-16T02:38:35Z", mars[0].0.date, tolerance: 180, "Mars 2025")
        Support.assertInstant("2027-02-19T15:50:55Z", mars[1].0.date, tolerance: 180, "Mars 2027")
        // Distance 0.6437 AU (closest approach 2025-01-12 0.6422 AU), magnitude -1.4, disc 14.5″.
        Support.assertNear(0.6437, mars[0].1.distanceAU, tolerance: 0.001, "Mars 2025 distance")
        Support.assertNear(-1.44, mars[0].1.apparentMagnitude ?? 99, tolerance: 0.05, "Mars 2025 magnitude")
        Support.assertNear(14.5, mars[0].1.angularDiameterArcseconds, tolerance: 0.1, "Mars 2025 diameter")
        Support.assertNear(0.678, mars[1].1.distanceAU, tolerance: 0.001, "Mars 2027 distance")
    }

    func testOuterPlanetOppositionsAgainstHorizons() throws {
        // Horizons: Jupiter 2026-01-10 08:42:10, Saturn 2025-09-21 05:45:39 and 2026-10-04 12:29:12,
        // Uranus 2025-11-21 12:25:25, Neptune 2025-09-23 12:53:35 UT.
        let found = Support.oppositions(events({ OppositionFinder.events(from: $0, to: $1) }, "2025-01-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        func date(_ planet: SolarSystemBody, _ year: Int) throws -> Date {
            try XCTUnwrap(found.first { $0.1.planet == planet && Support.text($0.0.date).hasPrefix(String(year)) }).0.date
        }
        Support.assertInstant("2026-01-10T08:42:10Z", try date(.jupiter, 2026), tolerance: 240, "Jupiter")
        Support.assertInstant("2025-09-21T05:45:39Z", try date(.saturn, 2025), tolerance: 240, "Saturn 2025")
        Support.assertInstant("2026-10-04T12:29:12Z", try date(.saturn, 2026), tolerance: 240, "Saturn 2026")
        Support.assertInstant("2025-11-21T12:25:25Z", try date(.uranus, 2025), tolerance: 240, "Uranus")
        Support.assertInstant("2025-09-23T12:53:35Z", try date(.neptune, 2025), tolerance: 240, "Neptune")
    }

    func testOppositionPutsThePlanetOppositeTheSun() {
        for (event, opposition) in Support.oppositions(events({ OppositionFinder.events(from: $0, to: $1) }, "2026-01-01T00:00:00Z", "2027-12-31T23:59:59Z")) {
            let jd = JulianDate(date: event.date)
            let planet = Ephemeris.state(of: opposition.planet, at: jd)
            let sun = Ephemeris.state(of: .sun, at: jd)
            let difference = AstroMath.normalizeSignedDegrees(planet.eclipticLongitudeOfDate - sun.eclipticLongitudeOfDate)
            XCTAssertTrue(abs(abs(difference) - 180) < 1e-4, "\(opposition.planet): \(difference)")
            Support.assertNear(180, planet.elongation ?? 0, tolerance: 5, "\(opposition.planet) elongation")
        }
        // Mars, Jupiter, Saturn, Uranus and Neptune: one opposition per synodic period, 13 in 2025-2027.
        XCTAssertEqual(events({ OppositionFinder.events(from: $0, to: $1) }, "2025-01-01T00:00:00Z", "2027-12-31T23:59:59Z").count, 13)
    }

    // MARK: Greatest elongations

    func testVenusGreatestElongationsOf2025And2026() {
        // Horizons: Venus 2025-01-10 05:00 UT east 47.169°; 2025-06-01 03:30 west 45.883°; 2026-08-15 06:30 east 45.892°.
        let found = Support.elongations(events({ GreatestElongationFinder.events(from: $0, to: $1) }, "2025-01-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        let venus = found.filter { $0.1.planet == .venus }
        XCTAssertEqual(venus.count, 3)
        guard venus.count == 3 else { return }
        Support.assertInstant("2025-01-10T05:00:00Z", venus[0].0.date, tolerance: 600, "Venus 2025-01")
        XCTAssertEqual(venus[0].1.direction, .east)
        Support.assertNear(47.169, venus[0].1.angle, tolerance: 0.01, "Venus 2025-01 angle")
        Support.assertInstant("2025-06-01T03:30:00Z", venus[1].0.date, tolerance: 600, "Venus 2025-06")
        XCTAssertEqual(venus[1].1.direction, .west)
        Support.assertNear(45.883, venus[1].1.angle, tolerance: 0.01, "Venus 2025-06 angle")
        Support.assertInstant("2026-08-15T06:30:00Z", venus[2].0.date, tolerance: 600, "Venus 2026-08")
        XCTAssertEqual(venus[2].1.direction, .east)
        Support.assertNear(45.892, venus[2].1.angle, tolerance: 0.01, "Venus 2026-08 angle")
    }

    func testMercuryGreatestElongationsAlternateEastAndWest() {
        // Horizons: Mercury 2025-03-08 06:06 UT east 18.248°. Mercury has three evening and three morning elongations
        // a year (here 2025: Mar 8 E, Apr 21 W, Jul 4 E, Aug 19 W, Oct 29 E, Dec 7 W; angles 18.2, 27.4, 25.9, 18.6, 23.9, 20.7).
        let found = Support.elongations(events({ GreatestElongationFinder.events(from: $0, to: $1) }, "2025-01-01T00:00:00Z", "2025-12-31T23:59:59Z"))
        let mercury = found.filter { $0.1.planet == .mercury }
        XCTAssertEqual(mercury.count, 6)
        guard mercury.count == 6 else { return }
        Support.assertInstant("2025-03-08T06:06:00Z", mercury[0].0.date, tolerance: 600, "Mercury 2025-03")
        Support.assertNear(18.248, mercury[0].1.angle, tolerance: 0.01, "Mercury 2025-03 angle")
        XCTAssertEqual(mercury.map { $0.1.direction }, [.east, .west, .east, .west, .east, .west])
        let angles = [18.2, 27.4, 25.9, 18.6, 23.9, 20.7]
        for index in angles.indices {
            Support.assertNear(angles[index], mercury[index].1.angle, tolerance: 0.1, "Mercury elongation \(index)")
        }
    }

    func testElongationIsAMaximumOfTheSeparation() {
        for (event, elongation) in Support.elongations(events({ GreatestElongationFinder.events(from: $0, to: $1) }, "2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")) {
            func angle(_ offsetDays: Double) -> Double {
                let jd = JulianDate(date: event.date).addingDays(offsetDays)
                return Ephemeris.geocentricJ2000(of: elongation.planet, at: jd).angle(to: Ephemeris.geocentricJ2000(of: .sun, at: jd))
            }
            XCTAssertTrue(angle(0) >= angle(-2) && angle(0) >= angle(2), "\(elongation.planet) \(event.date)")
            Support.assertNear(angle(0), elongation.angle, tolerance: 1e-3, "\(event.date) angle")
        }
    }

    // MARK: Equinoxes, solstices, apsides

    func testEquinoxesAndSolsticesOf2026AgainstUsno() {
        // USNO 2026 (UT): March equinox 20 Mar 14:46, June solstice 21 Jun 08:24, September equinox 23 Sep 00:05,
        // December solstice 21 Dec 20:50. The times are rounded to the minute: allow a minute and a half.
        let found = Support.seasons(events({ SeasonFinder.events(from: $0, to: $1) }, "2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        XCTAssertEqual(found.map { $0.1.kind }, [.marchEquinox, .juneSolstice, .septemberEquinox, .decemberSolstice])
        guard found.count == 4 else { return }
        Support.assertInstant("2026-03-20T14:46:00Z", found[0].0.date, tolerance: 90, "March equinox")
        Support.assertInstant("2026-06-21T08:24:00Z", found[1].0.date, tolerance: 90, "June solstice")
        Support.assertInstant("2026-09-23T00:05:00Z", found[2].0.date, tolerance: 90, "September equinox")
        Support.assertInstant("2026-12-21T20:50:00Z", found[3].0.date, tolerance: 90, "December solstice")
    }

    func testSeasonsPutTheSunAtTheRightLongitude() {
        for (event, season) in Support.seasons(events({ SeasonFinder.events(from: $0, to: $1) }, "2026-06-01T00:00:00Z", "2030-06-01T00:00:00Z")) {
            let longitude = Ephemeris.state(of: .sun, at: JulianDate(date: event.date)).eclipticLongitudeOfDate
            XCTAssertTrue(abs(AstroMath.normalizeSignedDegrees(longitude - season.kind.solarLongitude)) < 1e-4, "\(event.date)")
        }
        XCTAssertEqual(events({ SeasonFinder.events(from: $0, to: $1) }, "2026-06-01T00:00:00Z", "2030-06-01T00:00:00Z").count, 16)
    }

    func testPerihelionAndAphelionOf2026AgainstUsno() {
        // USNO 2026: perihelion 3 Jan 17:15 UT, aphelion 6 Jul 17:30 UT. The distance is flat there: the aphelion is
        // only good to a quarter of an hour.
        let found = Support.apsides(events({ EarthApsisFinder.events(from: $0, to: $1) }, "2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        XCTAssertEqual(found.map { $0.1.kind }, [.perihelion, .aphelion])
        guard found.count == 2 else { return }
        Support.assertInstant("2026-01-03T17:15:00Z", found[0].0.date, tolerance: 240, "perihelion")
        Support.assertInstant("2026-07-06T17:30:00Z", found[1].0.date, tolerance: 1_500, "aphelion")
        Support.assertNear(0.98330, found[0].1.distanceAU, tolerance: 1e-4, "perihelion distance")
        Support.assertNear(1.01664, found[1].1.distanceAU, tolerance: 1e-4, "aphelion distance")
    }

    func testApsidesAreFoundFarFromThePresent() {
        // The apsides drift through the calendar by about 1.75 days a century: around 1500 the perihelion is in late
        // December, around 2500 it is on 11 January, outside a fixed window around 3 January. Meeus (ch. 38) gives the
        // mean instants (JDE = 2451547.507 + 365.2596358 k, whole k perihelion, k + 0.5 aphelion); the planets and the
        // Moon move the true ones by up to about two days, so allow three.
        let cases: [(Double, EarthApsisKind)] = [(0, .perihelion), (0.5, .aphelion)]
        for k in [-500.0, 500.0] {
            for (offset, kind) in cases {
                let estimate = JulianDate(tt: 2_451_547.507 + 365.259_635_8 * (k + offset)).date
                let label = "\(kind) k \(k + offset)"
                let found = Support.apsides(EarthApsisFinder.events(from: estimate.addingTimeInterval(-20 * 86_400),
                                                                    to: estimate.addingTimeInterval(20 * 86_400)))
                XCTAssertEqual(found.map { $0.1.kind }, [kind], label)
                guard let apsis = found.first else { continue }
                XCTAssertTrue(abs(Support.seconds(apsis.0.date, estimate)) < 3 * 86_400, "\(label): \(apsis.0.date)")
                // The distance is the extreme of its kind around the event.
                let jd = JulianDate(date: apsis.0.date)
                func distance(_ days: Double) -> Double { Ephemeris.geocentricJ2000(of: .sun, at: jd.addingDays(days)).length }
                let sign = kind == .perihelion ? 1.0 : -1.0
                XCTAssertTrue(sign * (distance(-5) - distance(0)) > 0 && sign * (distance(5) - distance(0)) > 0, label)
                Support.assertNear(kind == .perihelion ? 0.9833 : 1.0167, apsis.1.distanceAU, tolerance: 1e-3, "\(label) distance")
            }
        }
    }

    func testApsidesOfWholeYearsFarFromThePresent() {
        // 2500: perihelion about 11 January, aphelion about 13 July. 1500: aphelion about 26 June, perihelion about
        // 26 December (the one before it, in 1499, is also in late December and outside the year).
        let year2500 = Support.apsides(events({ EarthApsisFinder.events(from: $0, to: $1) }, "2500-01-01T00:00:00Z", "2500-12-31T23:59:59Z"))
        XCTAssertEqual(year2500.map { $0.1.kind }, [.perihelion, .aphelion])
        let year1500 = Support.apsides(events({ EarthApsisFinder.events(from: $0, to: $1) }, "1500-01-01T00:00:00Z", "1500-12-31T23:59:59Z"))
        XCTAssertEqual(year1500.map { $0.1.kind }, [.aphelion, .perihelion])
        // The calculator reaches them too.
        let calculated = EventCalculator.events(from: Support.utc("2500-01-01T00:00:00Z"), to: Support.utc("2501-01-01T00:00:00Z"),
                                                observer: nil, options: EventOptions(kinds: [.earthApsis]))
        XCTAssertEqual(calculated.count, 2)
    }

    func testApsidesAreOptionalByDefault() {
        XCTAssertTrue(!EventOptions().kinds.contains(.earthApsis))
        XCTAssertTrue(EventKind.allCases.contains(.earthApsis))
        let events = EventCalculator.events(from: Support.utc("2026-01-01T00:00:00Z"), to: Support.utc("2026-12-31T23:59:59Z"))
        XCTAssertTrue(events.allSatisfy { $0.kind != .earthApsis })
        let withApsides = EventCalculator.events(from: Support.utc("2026-01-01T00:00:00Z"), to: Support.utc("2026-12-31T23:59:59Z"),
                                                 observer: nil, options: EventOptions(kinds: [.earthApsis]))
        XCTAssertEqual(withApsides.count, 2)
    }

    func testEmptyAndReversedRangesGiveNoEvents() {
        let moment = Support.utc("2026-03-20T14:46:00Z")
        let before = moment.addingTimeInterval(-1)
        XCTAssertTrue(SeasonFinder.events(from: moment, to: before).isEmpty)
        XCTAssertTrue(OppositionFinder.events(from: moment, to: before).isEmpty)
        XCTAssertTrue(GreatestElongationFinder.events(from: moment, to: before).isEmpty)
        XCTAssertTrue(EarthApsisFinder.events(from: moment, to: before).isEmpty)
    }
}

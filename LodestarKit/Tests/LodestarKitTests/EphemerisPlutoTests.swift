import XCTest
@testable import LodestarKit

/// Pluto: the series of Meeus, chapter 37, against the book's example and JPL DE440s, the magnitude against JPL
/// Horizons, and the sanity of its distances over the span in which the series is valid (1885–2099).
final class EphemerisPlutoTests: XCTestCase {
    private typealias Theory = Ephemeris.PlutoTheory

    // MARK: The series

    /// Example 37.a: Pluto on 1992 October 13.0 TT (JDE 2448908.5), heliocentric, referred to the mean equinox and
    /// ecliptic of J2000.0. The book gives l = 232.74071°, b = +14.58782°, r = 29.711111 AU (the 43 rows give
    /// 232.740711423°, 14.587817302°, 29.711110981 AU).
    func testMeeusExample37a() {
        let centuries = (2_448_908.5 - JulianDate.j2000) / JulianDate.daysPerJulianCentury
        let pluto = Theory.heliocentricEcliptic(centuries: centuries)
        XCTAssertEqual(pluto.longitude, 232.74071, accuracy: 1e-5)
        XCTAssertEqual(pluto.latitude, 14.58782, accuracy: 1e-5)
        XCTAssertEqual(pluto.radius, 29.711111, accuracy: 1e-6)
        XCTAssertEqual(Theory.termCount, 43)
    }

    func testHeliocentricJ2000IsTheEclipticPlaceRotatedToTheMeanEquator() {
        for jde in [2_448_908.5, 2_451_545.0, 2_460_000.5, 2_415_020.5] {
            let centuries = (jde - JulianDate.j2000) / JulianDate.daysPerJulianCentury
            let ecliptic = Theory.heliocentricEcliptic(centuries: centuries)
            let direction = EclipticCoordinate(longitude: ecliptic.longitude, latitude: ecliptic.latitude).unitVector
            let expected = Matrix3.rotationX(AstroMath.radians(Obliquity.j2000)) * (direction * ecliptic.radius)
            let vector = Theory.heliocentricJ2000(julianDayTT: jde)
            XCTAssertEqual((vector - expected).length, 0, accuracy: 1e-9, "JDE \(jde)")
            XCTAssertEqual(vector.length, ecliptic.radius, accuracy: 1e-9, "JDE \(jde)")
        }
    }

    /// The series is a sum of sines: whatever the date, r = 40.7241346 ± Σ√(A²+B²) = 29.648...51.800 AU,
    /// b is between −25.354° and +17.538°, and l is normalised.
    func testSeriesStaysBoundedForAnyDate() {
        for step in -300...300 {
            let centuries = Double(step) * 0.2137
            let pluto = Theory.heliocentricEcliptic(centuries: centuries)
            XCTAssertTrue((29.6...51.9).contains(pluto.radius), "T = \(centuries)")
            XCTAssertTrue((-25.4...17.6).contains(pluto.latitude), "T = \(centuries)")
            XCTAssertTrue((0..<360).contains(pluto.longitude), "T = \(centuries)")
        }
    }

    // MARK: Apparent place

    /// DE440s on 1992 October 13.0 TT: apparent α = 232.927709°, δ = −4.456119° (J2000 axes), Δ = 30.528738 AU,
    /// Sun–Pluto distance 29.711092 AU at the time the light left, elongation 34.4155°, phase angle 1.0874°. (The
    /// book's astrometric place, 15h 31m 43.7s, −4° 27′ 29″, is the same without aberration.)
    func testApparentPlaceOnTheDayOfMeeusExample37a() throws {
        let state = Ephemeris.state(of: .pluto, at: JulianDate(tt: 2_448_908.5))
        let place = EquatorialCoordinate(vector: state.geocentricJ2000)
        XCTAssertEqual(place.rightAscension, 232.927709, accuracy: 0.001)
        XCTAssertEqual(place.declination, -4.456119, accuracy: 0.001)
        XCTAssertEqual(state.distanceAU, 30.528738, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(state.heliocentricDistanceAU), 29.711092, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(state.elongation), 34.4155, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(state.phaseAngle), 1.0874, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(state.illuminatedFraction), 0.99991, accuracy: 0.0005)
        XCTAssertNil(state.isWaxing)
        // 2 · 1188.3 km seen from 30.5287 AU.
        XCTAssertEqual(state.angularDiameterArcseconds, 0.1073, accuracy: 0.001)
        XCTAssertEqual(state.geocentricJ2000, Ephemeris.geocentricJ2000(of: .pluto, at: state.julianDate))
        XCTAssertNotNil(state.apparentMagnitude)
    }

    // MARK: Magnitude

    func testPhotometryFormula() {
        typealias P = Ephemeris.Photometry
        // V(1, 0) = −1.00 and 0.041 mag per degree of phase angle.
        XCTAssertEqual(P.pluto(sunDistance: 1, earthDistance: 1, phaseAngle: 0), -1.00, accuracy: 1e-12)
        XCTAssertEqual(P.pluto(sunDistance: 1, earthDistance: 1, phaseAngle: 2), -1.00 + 0.082, accuracy: 1e-12)
        XCTAssertEqual(P.pluto(sunDistance: 33, earthDistance: 32, phaseAngle: 1),
                       5 * log10(33.0 * 32.0) - 1.00 + 0.041, accuracy: 1e-12)
        XCTAssertEqual(P.pluto(sunDistance: 30, earthDistance: 31, phaseAngle: 0), 5 * log10(30.0 * 31.0) - 1.00,
                       accuracy: 1e-12)
    }

    /// JPL Horizons' observer table for Pluto (command 999, centre 500@399, times in TT): the apparent visual
    /// magnitude APmag, which is printed to 0.001 and includes Charon. The instants are the largest phase angle
    /// seen from the Earth (1.96°, 1988), Meeus' example 37.a, J2000, the smallest phase angle (opposition, 2018)
    /// and four instants of the next years.
    private static let horizonsMagnitudes: [(jdTT: Double, magnitude: Double)] = [
        (2_447_374.5, 13.800), (2_448_908.5, 13.833), (2_451_545.0, 13.902), (2_458_311.5, 14.197),
        (2_460_000.5, 14.494), (2_461_041.5, 14.572), (2_462_000.5, 14.536), (2_466_000.5, 14.865),
    ]

    /// The formula against the Horizons table: the largest difference over these instants is 0.0004 mag (series and
    /// DE440s Earth), so 0.005 is ten times that and half the 0.010 by which V(1, 0) = −1.01 would be off.
    func testMagnitudeMatchesHorizons() throws {
        XCTAssertGreaterThanOrEqual(Self.horizonsMagnitudes.count, 8)
        for (jd, expected) in Self.horizonsMagnitudes {
            let state = Ephemeris.state(of: .pluto, at: JulianDate(tt: jd))
            XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), expected, accuracy: 0.005, "JD \(jd)")
        }
    }

    // MARK: Distances over the valid span

    /// 1885-01-01 to 2099-12-31 every 53 days (1,482 instants). DE440s (and the series): r 29.66...48.93 AU,
    /// Δ 28.69...49.85 AU, |β| up to 17.72°, phase angle up to 1.96°, so the disc is 0.066″ to 0.114″ across.
    func testGeocentricDistanceRangeOverTheValidSpan() throws {
        let last = JulianDate.julianDay(year: 2099, month: 12, day: 31)
        var jd = JulianDate.julianDay(year: 1885, month: 1, day: 1)
        while jd <= last {
            let state = Ephemeris.state(of: .pluto, at: JulianDate(ut: jd))
            let message = "JD \(jd)"
            XCTAssertTrue((28.5...50.1).contains(state.distanceAU), message)
            XCTAssertTrue((29.5...49.2).contains(try XCTUnwrap(state.heliocentricDistanceAU)), message)
            XCTAssertLessThan(abs(state.eclipticLatitudeOfDate), 17.9, message)
            XCTAssertLessThan(try XCTUnwrap(state.phaseAngle), 2.1, message)
            XCTAssertTrue((0.064...0.116).contains(state.angularDiameterArcseconds), message)
            jd += 53
        }
    }

    // MARK: Cross-twin check

    /// The state at JD(UT) 2460000.5 with ΔT 69.2 s, with the digits the Kotlin twin computes (its
    /// `EphemerisGoldenTests` pins the same row): the two implementations of the series, the light-time loop and the
    /// magnitude must agree to the last few digits. DE440s is 1.2×10⁻⁴ AU from this place (3×10⁻⁶ of the
    /// distance); `testApparentPlaceOnTheDayOfMeeusExample37a` is the check against DE440s itself.
    func testStateAtTheGoldenInstant() throws {
        let state = Ephemeris.state(of: .pluto, at: JulianDate(ut: 2_460_000.5, deltaT: 69.2))
        XCTAssertEqual(state.geocentricJ2000.x, 17.233150638279188, accuracy: 1e-9)
        XCTAssertEqual(state.geocentricJ2000.y, -27.870347727564585, accuracy: 1e-9)
        XCTAssertEqual(state.geocentricJ2000.z, -13.661324765442227, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), 14.493880860819205, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(state.elongation), 36.78370544834634, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(state.phaseAngle), 0.9782224377925626, accuracy: 1e-9)
        XCTAssertEqual(state.eclipticLongitudeOfDate, 299.3872492780666, accuracy: 1e-9)
        XCTAssertEqual(state.eclipticLatitudeOfDate, -2.339787769333409, accuracy: 1e-9)
    }

    // MARK: The body

    func testPlutoIsADwarfPlanetListedWithThePlanets() throws {
        XCTAssertEqual(SolarSystemBody(rawValue: "pluto"), .pluto)
        XCTAssertEqual(SolarSystemBody.pluto.displayName, "Pluto")
        XCTAssertTrue(SolarSystemBody.pluto.isPlanet)
        XCTAssertEqual(SolarSystemBody.allCases.last, .pluto)
        XCTAssertEqual(SolarSystemBody.pluto.meanRadiusKilometers, 1_188.3, accuracy: 0.05)
        let data = try JSONEncoder().encode(SolarSystemBody.pluto)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"pluto\"")
        XCTAssertEqual(try JSONDecoder().decode(SolarSystemBody.self, from: data), .pluto)
    }
}

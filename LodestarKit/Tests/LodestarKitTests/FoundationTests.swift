import XCTest
@testable import LodestarKit

/// Foundation layer checks against worked examples in Meeus, *Astronomical Algorithms* (2nd ed.).
final class FoundationTests: XCTestCase {
    private func dms(_ d: Double, _ m: Double, _ s: Double) -> Double {
        let sign: Double = (d < 0 || (d == 0 && (m < 0 || s < 0))) ? -1 : 1
        return sign * (abs(d) + abs(m) / 60 + abs(s) / 3600)
    }

    private func hms(_ h: Double, _ m: Double, _ s: Double) -> Double {
        (h + m / 60 + s / 3600) * 15
    }

    // MARK: Math

    func testAngleNormalisation() {
        XCTAssertEqual(AstroMath.normalizeDegrees(-30), 330, accuracy: 1e-12)
        XCTAssertEqual(AstroMath.normalizeDegrees(720.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(AstroMath.normalizeDegrees(-1e-15), 0)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(190), -170, accuracy: 1e-12)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(-180), 180, accuracy: 1e-12)
        XCTAssertTrue(AstroMath.normalizeDegrees(.nan).isNaN)
        XCTAssertEqual(AstroMath.asinDeg(1.0000000001), 90, accuracy: 1e-12)
        XCTAssertEqual(AstroMath.polynomial(2, [1, 2, 3]), 17, accuracy: 1e-12)
    }

    func testVectorBasics() {
        let a = Vector3(1, 0, 0), b = Vector3(0, 1, 0)
        XCTAssertEqual(a.cross(b), Vector3(0, 0, 1))
        XCTAssertEqual(a.angle(to: b), 90, accuracy: 1e-12)
        XCTAssertEqual(Vector3.zero.normalized, .zero)
        XCTAssertEqual(Vector3(3, 4, 0).length, 5, accuracy: 1e-12)
        XCTAssertEqual(Vector3(1, 0, 0).angle(to: Vector3(1, 1e-9, 0)), AstroMath.degrees(1e-9), accuracy: 1e-15)
    }

    func testActiveAndFrameRotations() {
        let quarter = Double.pi / 2
        assertVector(Matrix3.rotationZ(quarter) * Vector3(1, 0, 0), Vector3(0, 1, 0))
        assertVector(Matrix3.rotationX(quarter) * Vector3(0, 1, 0), Vector3(0, 0, 1))
        assertVector(Matrix3.rotationY(quarter) * Vector3(0, 0, 1), Vector3(1, 0, 0))
        assertVector(Matrix3.frameRotationZ(quarter) * Vector3(1, 0, 0), Vector3(0, -1, 0))
        let axis = Vector3(1, 2, 3)
        let r = Matrix3.rotation(axis: axis, angleRadians: 0.7)
        XCTAssertEqual(r.determinant, 1, accuracy: 1e-12)
        assertVector(r * axis, axis)
        assertMatrix(r * r.transposed, .identity)
        let product = Matrix3.rotationX(0.3) * Matrix3.rotationY(-1.1)
        assertVector(product * Vector3(0.2, -0.5, 0.9), Matrix3.rotationX(0.3) * (Matrix3.rotationY(-1.1) * Vector3(0.2, -0.5, 0.9)))
        let noisy = Matrix3(rows: Vector3(1.01, 0.02, 0), Vector3(0, 0.98, 0.01), Vector3(0, 0, 1.02))
        let cleaned = noisy.orthonormalized()
        assertMatrix(cleaned * cleaned.transposed, .identity)
        XCTAssertEqual(cleaned.determinant, 1, accuracy: 1e-12)
    }

    // MARK: Time

    func testJulianDayFromCalendar() {
        // Meeus examples 7.a and the table in ch. 7.
        XCTAssertEqual(JulianDate.julianDay(year: 1957, month: 10, day: 4, hour: 19, minute: 26, second: 24), 2_436_116.31, accuracy: 1e-6)
        XCTAssertEqual(JulianDate.julianDay(year: 2000, month: 1, day: 1, hour: 12), 2_451_545.0)
        XCTAssertEqual(JulianDate.julianDay(year: 1987, month: 6, day: 19, hour: 12), 2_446_966.0)
        XCTAssertEqual(JulianDate.julianDay(year: 1988, month: 1, day: 27), 2_447_187.5)
        XCTAssertEqual(JulianDate.julianDay(year: 1600, month: 1, day: 1), 2_305_447.5)
        XCTAssertEqual(JulianDate.julianDay(year: 1900, month: 1, day: 1), 2_415_020.5)
    }

    func testDateRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_791_331_200) // 2026-10-07T00:00:00Z
        let jd = JulianDate(date: date)
        XCTAssertEqual(jd.ut, JulianDate.julianDay(year: 2026, month: 10, day: 7), accuracy: 1e-9)
        XCTAssertEqual(jd.date.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1e-4)
        XCTAssertEqual(JulianDate(tt: jd.tt).ut, jd.ut, accuracy: 1e-9)
    }

    func testDeltaT() {
        XCTAssertEqual(JulianDate.deltaT(decimalYear: 2000), 63.86, accuracy: 0.01)
        XCTAssertEqual(JulianDate.deltaT(decimalYear: 2020), 69.36, accuracy: 0.01)
        XCTAssertEqual(JulianDate.deltaT(decimalYear: 1950), 29.07, accuracy: 0.01)
        // No jumps at the segment boundaries.
        for boundary in [1860.0, 1900, 1920, 1941, 1961, 1986, 2005, 2026, 2050, 2150] {
            let before = JulianDate.deltaT(decimalYear: boundary - 1e-6)
            let after = JulianDate.deltaT(decimalYear: boundary + 1e-6)
            XCTAssertEqual(before, after, accuracy: 1.5, "ΔT discontinuity at \(boundary)")
        }
        XCTAssertEqual(JulianDate.deltaT(decimalYear: .nan), 69.2)
    }

    func testSiderealTime() {
        // Meeus 12.a: 1987 April 10, 0h UT → GMST 13h10m46.3668s.
        let a = JulianDate(ut: 2_446_895.5)
        XCTAssertEqual(SiderealTime.greenwichMean(a), hms(13, 10, 46.3668), accuracy: 0.0005 / 240)
        // Apparent: 13h10m46.1351s with Δψ = −3.788″, ε = 23°26′36.85″.
        let nutation = Nutation(longitude: -3.788 / 3600, obliquity: 9.443 / 3600)
        XCTAssertEqual(SiderealTime.greenwichApparent(a, nutation: nutation, trueObliquity: dms(23, 26, 36.85)),
                       hms(13, 10, 46.1351), accuracy: 0.001 / 240)
        // Meeus 12.b: 1987 April 10, 19h21m00s UT → 8h34m57.0896s.
        let b = JulianDate(ut: 2_446_896.30625)
        XCTAssertEqual(SiderealTime.greenwichMean(b), hms(8, 34, 57.0896), accuracy: 0.001 / 240)
    }

    // MARK: Earth orientation

    func testNutationAndObliquity() {
        // Meeus 22.a: 1987 April 10, 0h TD.
        let jd = JulianDate(tt: 2_446_895.5)
        let nutation = Nutation(julianDate: jd)
        XCTAssertEqual(nutation.longitude * 3600, -3.788, accuracy: 0.002)
        XCTAssertEqual(nutation.obliquity * 3600, 9.443, accuracy: 0.002)
        XCTAssertEqual(Obliquity.mean(jd), dms(23, 26, 27.407), accuracy: 0.001 / 3600)
        XCTAssertEqual(Obliquity.mean(jd) + nutation.obliquity, dms(23, 26, 36.850), accuracy: 0.003 / 3600)
    }

    func testPrecessionWithProperMotion() {
        // Meeus 21.b: θ Persei, J2000 → 2028 Nov 13.19 TD (mean place of date incl. proper motion).
        let jd = JulianDate(tt: 2_462_088.69)
        let j2000 = EquatorialCoordinate(rightAscension: hms(2, 44, 11.986), declination: dms(49, 13, 42.48))
        let years = (jd.tt - JulianDate.j2000) / 365.25
        // Meeus gives μα = +0.03425 s/yr (not μα*) and μδ = −0.0895″/yr.
        let pm = ProperMotion(raMilliarcsecondsPerYear: 0.03425 * 15 * 1000 * AstroMath.cosDeg(j2000.declination),
                              decMilliarcsecondsPerYear: -89.5)
        let moved = pm.apply(to: j2000, years: years)
        let ofDate = EquatorialCoordinate(vector: Precession.matrixFromJ2000(to: jd) * moved.unitVector)
        XCTAssertEqual(ofDate.rightAscension, 41.547214, accuracy: 0.00001)
        XCTAssertEqual(ofDate.declination, 49.348483, accuracy: 0.00001)
    }

    func testApparentPlace() {
        // Meeus 23.a: θ Persei apparent place for 2028 Nov 13.19 TD:
        // α = 2h46m14.390s, δ = +49°21′07.45″.
        let jd = JulianDate(tt: 2_462_088.69)
        let frame = SkyFrame(julianDate: jd, observer: Observer(location: GeographicLocation(latitude: 0, longitude: 0)))
        let j2000 = EquatorialCoordinate(rightAscension: hms(2, 44, 11.986), declination: dms(49, 13, 42.48))
        let pm = ProperMotion(raMilliarcsecondsPerYear: 0.03425 * 15 * 1000 * AstroMath.cosDeg(j2000.declination),
                              decMilliarcsecondsPerYear: -89.5)
        let apparent = frame.apparentPlace(j2000: j2000, properMotion: pm)
        XCTAssertEqual(apparent.rightAscension, hms(2, 46, 14.390), accuracy: 0.05 / 3600)
        XCTAssertEqual(apparent.declination, dms(49, 21, 7.45), accuracy: 0.05 / 3600)
    }

    func testAberrationMagnitude() {
        let beta = Aberration.earthVelocity(JulianDate(ut: 2_460_000.5))
        XCTAssertEqual(beta.length * AstroMath.arcsecondsPerRadian, 20.5, accuracy: 0.4)
        let jd = JulianDate(ut: 2_460_000.5)
        let sunDirection = EquatorialCoordinate(vector:
            Matrix3.rotationX(AstroMath.radians(Obliquity.mean(jd)))
                * EclipticCoordinate(longitude: SolarCoordinates.geometricLongitude(jd), latitude: 0).unitVector)
        // The Earth moves perpendicular to the Sun direction (to within the eccentricity terms).
        XCTAssertEqual(beta.normalized.angle(to: sunDirection.unitVector), 90, accuracy: 1.5)
    }

    // MARK: Coordinates

    func testEquatorialToHorizontal() {
        // Meeus 13.b: Venus from USNO; H = 64.352133°, δ = −6.719892°, φ = 38.921389°
        // → A = 68.0337° from the south, h = 15.1249°.
        let horizontal = CoordinateTransforms.equatorialToHorizontal(hourAngle: 64.352133, declination: -6.719892,
                                                                    latitude: 38.921389)
        XCTAssertEqual(horizontal.azimuth, 68.0337 + 180, accuracy: 0.0002)
        XCTAssertEqual(horizontal.altitude, 15.1249, accuracy: 0.0002)
        let back = CoordinateTransforms.horizontalToEquatorial(horizontal, latitude: 38.921389)
        XCTAssertEqual(back.hourAngle, 64.352133, accuracy: 1e-9)
        XCTAssertEqual(back.declination, -6.719892, accuracy: 1e-9)
    }

    func testEclipticEquatorialRoundTrip() {
        // Meeus 13.a: Pollux, α = 116.328942°, δ = 28.026183°, ε = 23.4392911° → λ = 113.215630°, β = 6.684170°.
        let pollux = EquatorialCoordinate(rightAscension: 116.328942, declination: 28.026183)
        let ecliptic = CoordinateTransforms.equatorialToEcliptic(pollux, obliquity: 23.4392911)
        XCTAssertEqual(ecliptic.longitude, 113.215630, accuracy: 1e-6)
        XCTAssertEqual(ecliptic.latitude, 6.684170, accuracy: 1e-6)
        let back = CoordinateTransforms.eclipticToEquatorial(ecliptic, obliquity: 23.4392911)
        XCTAssertEqual(back.rightAscension, pollux.rightAscension, accuracy: 1e-9)
        XCTAssertEqual(back.declination, pollux.declination, accuracy: 1e-9)
    }

    func testGalacticFrame() {
        let centre = CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: 0, latitude: 0))
        XCTAssertEqual(centre.rightAscension, 266.40499, accuracy: 0.001)
        XCTAssertEqual(centre.declination, -28.93617, accuracy: 0.001)
        let pole = CoordinateTransforms.galacticToEquatorialJ2000(GalacticCoordinate(longitude: 0, latitude: 90))
        XCTAssertEqual(pole.rightAscension, 192.85948, accuracy: 0.001)
        XCTAssertEqual(pole.declination, 27.12825, accuracy: 0.001)
        let sgrA = EquatorialCoordinate(rightAscension: hms(17, 45, 40.04), declination: dms(-29, 0, 28.1))
        let galactic = CoordinateTransforms.equatorialJ2000ToGalactic(sgrA)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(galactic.longitude), -0.0558, accuracy: 0.001)
        XCTAssertEqual(galactic.latitude, -0.0462, accuracy: 0.001)
    }

    func testHorizontalVectorRoundTrip() {
        for (az, alt) in [(0.0, 0.0), (90, 45), (215.5, -12), (359.9, 89.5), (10, -89)] {
            let h = HorizontalCoordinate(azimuth: az, altitude: alt)
            let back = HorizontalCoordinate(vector: h.unitVector * 3.7)
            XCTAssertEqual(back.altitude, alt, accuracy: 1e-9)
            XCTAssertEqual(AstroMath.normalizeSignedDegrees(back.azimuth - az), 0, accuracy: 1e-7)
        }
        let zenith = HorizontalCoordinate(vector: Vector3(0, 0, 1))
        XCTAssertEqual(zenith.altitude, 90)
        XCTAssertEqual(zenith.azimuth, 0)
        // East is azimuth 90°.
        XCTAssertEqual(HorizontalCoordinate(vector: Vector3(1, 0, 0)).azimuth, 90, accuracy: 1e-12)
    }

    func testGeographicLocationValidation() {
        XCTAssertNil(GeographicLocation.validated(latitude: 91, longitude: 0))
        XCTAssertNil(GeographicLocation.validated(latitude: .nan, longitude: 0))
        XCTAssertNil(GeographicLocation.validated(latitude: 10, longitude: .infinity))
        XCTAssertNil(GeographicLocation.validated(latitude: 10, longitude: 10, elevation: 50_000))
        XCTAssertEqual(GeographicLocation.validated(latitude: 10, longitude: 350)?.longitude ?? 0, -10, accuracy: 1e-12)
        let clamped = GeographicLocation(latitude: 120, longitude: 540, elevation: .nan)
        XCTAssertEqual(clamped.latitude, 90)
        XCTAssertEqual(clamped.longitude, 180)
        XCTAssertEqual(clamped.elevation, 0)
    }

    // MARK: Refraction

    func testRefraction() {
        // Meeus 16.a uses Bennett's formula: apparent altitude 0.5° → R ≈ 28.75′.
        XCTAssertEqual(Refraction.refractionForApparentAltitude(0.5) * 60, 28.75, accuracy: 0.05)
        // Sæmundsson at the horizon ≈ 29′, and ≈ 1′ at 45°.
        XCTAssertEqual(Refraction.refractionForTrueAltitude(0) * 60, 28.9, accuracy: 0.3)
        XCTAssertEqual(Refraction.refractionForTrueAltitude(45) * 60, 1.0, accuracy: 0.05)
        XCTAssertEqual(Refraction.refractionForTrueAltitude(90), 0)
        XCTAssertEqual(Refraction.refractionForTrueAltitude(-6), 0)
        // Exact inverse, monotonic mapping.
        var previous = -Double.infinity
        for tenth in stride(from: -60, through: 900, by: 3) {
            let h = Double(tenth) / 10
            let apparent = Refraction.apparentAltitude(trueAltitude: h)
            XCTAssertGreaterThan(apparent, previous)
            previous = apparent
            XCTAssertEqual(Refraction.trueAltitude(apparentAltitude: apparent), h, accuracy: 1e-7)
        }
        // Thin, warm air refracts less.
        let thin = Atmosphere(pressureMillibars: 700, temperatureCelsius: 25)
        XCTAssertLessThan(Refraction.refractionForTrueAltitude(5, atmosphere: thin), Refraction.refractionForTrueAltitude(5))
        XCTAssertEqual(Atmosphere(pressureMillibars: .nan, temperatureCelsius: 10).refractionScale, 1)
    }

    // MARK: SkyFrame

    func testCelestialPoleAltitudeEqualsLatitude() {
        for latitude in [-60.0, -10, 0.5, 40, 78] {
            let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_790_000_000),
                                 observer: Observer(location: GeographicLocation(latitude: latitude, longitude: 12)))
            let north = frame.horizontalOfCelestialPole(north: true, refraction: false)
            XCTAssertEqual(north.altitude, latitude, accuracy: 1e-9)
            if latitude != 90 { XCTAssertEqual(AstroMath.normalizeSignedDegrees(north.azimuth), 0, accuracy: 1e-6) }
            let south = frame.horizontalOfCelestialPole(north: false, refraction: false)
            XCTAssertEqual(south.altitude, -latitude, accuracy: 1e-9)
        }
    }

    func testObjectOnMeridianAtZenith() {
        // A star whose apparent RA equals the local sidereal time and whose apparent declination
        // equals the latitude must be at the zenith.
        let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_800_000_000),
                             observer: Observer(location: GeographicLocation(latitude: 35, longitude: -100)))
        let apparent = EquatorialCoordinate(rightAscension: frame.localApparentSiderealTime, declination: 35)
        let horizontal = HorizontalCoordinate(vector: frame.equatorialOfDateToHorizontal * apparent.unitVector)
        XCTAssertEqual(horizontal.altitude, 90, accuracy: 1e-9)
        XCTAssertEqual(frame.hourAngle(apparentRightAscension: apparent.rightAscension), 0, accuracy: 1e-9)
    }

    func testHorizontalJ2000RoundTrip() {
        let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_760_000_000),
                             observer: Observer(location: GeographicLocation(latitude: -33.87, longitude: 151.21, elevation: 50)))
        let vega = EquatorialCoordinate(rightAscension: 279.23473, declination: 38.78369)
        for refraction in [false, true] {
            let horizontal = frame.horizontal(j2000: vega, refraction: refraction)
            let back = frame.j2000(fromHorizontal: horizontal, refracted: refraction)
            XCTAssertEqual(back.angularSeparation(to: vega) * 3600, 0, accuracy: 0.05)
        }
        let fast = HorizontalCoordinate(vector: frame.horizontalVector(j2000UnitVector: vega.unitVector))
        let full = frame.horizontal(j2000: vega, refraction: false)
        XCTAssertEqual(fast.angularSeparation(to: full) * 3600, 0, accuracy: 1e-6)
    }

    func testTopocentricParallaxOfNearbyBody() {
        // A body 60 Earth radii away on the observer's horizon is displaced downward by ≈ its
        // horizontal parallax (~57′); at the zenith there is no displacement.
        let observer = Observer(location: GeographicLocation(latitude: 0, longitude: 0))
        let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_770_000_000), observer: observer)
        let distance = 60 * SkyFrame.earthEquatorialRadiusKilometers / SkyFrame.kilometersPerAU
        let zenithOfDate = frame.equatorialOfDateToHorizontal.transposed * Vector3(0, 0, 1)
        let zenithJ2000 = frame.precessionNutationMatrix.transposed * zenithOfDate
        let atZenith = frame.horizontal(geocentricJ2000: zenithJ2000 * distance, refraction: false)
        XCTAssertEqual(atZenith.altitude, 90, accuracy: 1e-6)
        let eastOfDate = frame.equatorialOfDateToHorizontal.transposed * Vector3(1, 0, 0)
        let eastJ2000 = frame.precessionNutationMatrix.transposed * eastOfDate
        let atHorizon = frame.horizontal(geocentricJ2000: eastJ2000 * distance, refraction: false)
        XCTAssertEqual(atHorizon.altitude, -AstroMath.degrees(asin(1.0 / 60)), accuracy: 0.01)
    }

    // MARK: Helpers

    private func assertVector(_ a: Vector3, _ b: Vector3, accuracy: Double = 1e-12,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
    }

    private func assertMatrix(_ a: Matrix3, _ b: Matrix3, accuracy: Double = 1e-12,
                              file: StaticString = #filePath, line: UInt = #line) {
        assertVector(a.r0, b.r0, accuracy: accuracy, file: file, line: line)
        assertVector(a.r1, b.r1, accuracy: accuracy, file: file, line: line)
        assertVector(a.r2, b.r2, accuracy: accuracy, file: file, line: line)
    }
}

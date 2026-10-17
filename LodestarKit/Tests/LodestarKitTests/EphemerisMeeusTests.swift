import XCTest
@testable import LodestarKit

/// `Ephemeris` against the worked examples of Meeus, *Astronomical Algorithms* (2nd ed.), values
/// computed with JPL DE440s, and structural invariants of `BodyState`.
final class EphemerisMeeusTests: XCTestCase {
    private let greenwich = Observer(location: GeographicLocation(latitude: 0, longitude: 0))

    // MARK: Moon

    /// Example 47.a: the Moon on 1992 April 12 at 0h TD (JDE 2448724.5).
    func testLunarSeriesReproducesMeeusExample47a() {
        let centuries = (2_448_724.5 - JulianDate.j2000) / JulianDate.daysPerJulianCentury
        let moon = Ephemeris.LunarTheory.geocentricEcliptic(centuries: centuries)
        XCTAssertEqual(moon.longitude, 133.162655, accuracy: 1e-5)
        XCTAssertEqual(moon.latitude, -3.229126, accuracy: 1e-5)
        XCTAssertEqual(moon.distanceKilometers, 368_409.7, accuracy: 0.05)
    }

    func testMoonApparentPlaceMeeusExample47a() {
        // The book gives α = 134.688470°, δ = +13.768368° without light-time (0.7″ in longitude);
        // DE440s gives α = 134.687915°, δ = +13.768449°, the truncated series' own error.
        let jd = JulianDate(tt: 2_448_724.5)
        let frame = SkyFrame(julianDate: jd, observer: greenwich)
        let apparent = frame.geocentricApparentEquatorial(of: .moon)
        XCTAssertEqual(apparent.rightAscension, 134.688470, accuracy: 0.0004)
        XCTAssertEqual(apparent.declination, 13.768368, accuracy: 0.0004)
        let state = frame.state(of: .moon)
        XCTAssertEqual(state.distanceKilometers, 368_409.7, accuracy: 0.5)
        // Apparent longitude: λ + Δψ (+0.004610°) minus the Moon's motion during the light-time (0.7″).
        XCTAssertEqual(state.eclipticLongitudeOfDate, 133.162655 + 0.004610, accuracy: 0.0004)
        XCTAssertEqual(state.eclipticLatitudeOfDate, -3.229126, accuracy: 0.0004)
    }

    /// Example 48.a: the same instant; the book finds i = 69.0756° and k = 0.6786 (with its own
    /// low-accuracy Sun). DE440s gives i = 69.0840°, k = 0.67850.
    func testMoonPhaseMeeusExample48a() throws {
        let state = Ephemeris.state(of: .moon, at: JulianDate(tt: 2_448_724.5))
        XCTAssertEqual(try XCTUnwrap(state.illuminatedFraction), 0.6786, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(state.phaseAngle), 69.0756, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(state.elongation), 110.7929, accuracy: 0.002)
        XCTAssertEqual(state.isWaxing, true)
        // 368 410 km: the disc is 2 · 1737.4 km across, 32.4′.
        XCTAssertEqual(state.angularDiameterArcseconds, 1945.5, accuracy: 0.5)
    }

    /// The Moon is not corrected for annual aberration: that, 20.5″ at its largest, cancels against
    /// the Earth's motion during the light-time, leaving only the Moon's own motion (0.7″).
    func testMoonDirectionHasNoAnnualAberration() {
        let jd = JulianDate(tt: 2_459_000.25)
        let geometric = Ephemeris.LunarTheory.geocentricEcliptic(centuries: jd.centuriesTT)
        let geometricJ2000 = Matrix3.rotationX(AstroMath.radians(Obliquity.mean(jd)))
            * EclipticCoordinate(longitude: geometric.longitude, latitude: geometric.latitude).unitVector
        let ofDate = Precession.matrixFromJ2000(to: jd).transposed * geometricJ2000
        let apparent = Ephemeris.geocentricJ2000(of: .moon, at: jd)
        XCTAssertLessThan(ofDate.angle(to: apparent) * 3600, 1.5)
    }

    // MARK: Sun

    /// Example 25.a (low accuracy, 0.01°): the Sun on 1992 October 13 at 0h TD.
    func testSunMeeusExample25a() {
        let jd = JulianDate(tt: 2_448_908.5)
        let frame = SkyFrame(julianDate: jd, observer: greenwich)
        let apparent = frame.geocentricApparentEquatorial(of: .sun)
        XCTAssertEqual(apparent.rightAscension, 198.38083, accuracy: 0.01)
        XCTAssertEqual(apparent.declination, -7.78507, accuracy: 0.01)
        XCTAssertEqual(frame.state(of: .sun).distanceAU, 0.99766, accuracy: 0.0001)
    }

    /// Example 25.b (VSOP87, about 1″), cross-checked against DE440s, which gives α = 198.378134°,
    /// δ = −7.783811° and R = 0.99760852 AU.
    func testSunMeeusExample25b() {
        let jd = JulianDate(tt: 2_448_908.5)
        let frame = SkyFrame(julianDate: jd, observer: greenwich)
        let apparent = frame.geocentricApparentEquatorial(of: .sun)
        XCTAssertEqual(apparent.rightAscension, 198.378178, accuracy: 0.0003)
        XCTAssertEqual(apparent.declination, -7.783871, accuracy: 0.0003)
        XCTAssertEqual(apparent.angularSeparation(to: EquatorialCoordinate(rightAscension: 198.378134,
                                                                          declination: -7.783811)) * 3600, 0, accuracy: 1)
        let state = frame.state(of: .sun)
        XCTAssertEqual(state.distanceAU, 0.99760852, accuracy: 0.00001)
        // Apparent ecliptic longitude (nutation and aberration included): 199.905998° from the DE440s place
        // and the true obliquity of date, 199.90606° in the book. The Sun's latitude is 0.0002°.
        XCTAssertEqual(state.eclipticLongitudeOfDate, 199.906, accuracy: 0.0003)
        XCTAssertEqual(state.eclipticLatitudeOfDate, 0.0002, accuracy: 0.0004)
    }

    func testSunPhysicalAppearance() throws {
        let state = Ephemeris.state(of: .sun, at: JulianDate(ut: 2_460_000.5))
        XCTAssertEqual(state.angularDiameterArcseconds / 60, 32, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), -26.74, accuracy: 0.1)
        XCTAssertNil(state.heliocentricDistanceAU)
        XCTAssertNil(state.elongation)
        XCTAssertNil(state.phaseAngle)
        XCTAssertNil(state.illuminatedFraction)
        XCTAssertNil(state.isWaxing)
        // Brighter at perihelion than at aphelion.
        let january = Ephemeris.state(of: .sun, at: JulianDate(ut: JulianDate.julianDay(year: 2026, month: 1, day: 4)))
        let july = Ephemeris.state(of: .sun, at: JulianDate(ut: JulianDate.julianDay(year: 2026, month: 7, day: 6)))
        XCTAssertLessThan(january.distanceAU, 0.984)
        XCTAssertGreaterThan(july.distanceAU, 1.016)
        XCTAssertGreaterThan(january.angularDiameterArcseconds, july.angularDiameterArcseconds)
    }

    // MARK: Planets

    /// Distance ranges over 1900–2100 from DE440s, widened by a little.
    func testPlanetDistancesStayWithinTheirOrbits() throws {
        let heliocentricRange: [SolarSystemBody: ClosedRange<Double>] = [
            .mercury: 0.30...0.47, .venus: 0.71...0.73, .mars: 1.37...1.67, .jupiter: 4.94...5.47,
            .saturn: 9.0...10.1, .uranus: 18.2...20.15, .neptune: 29.7...30.4,
        ]
        let geocentricRange: [SolarSystemBody: ClosedRange<Double>] = [
            .mercury: 0.54...1.46, .venus: 0.26...1.74, .mars: 0.37...2.68, .jupiter: 3.9...6.5,
            .saturn: 7.9...11.1, .uranus: 17.2...21.1, .neptune: 28.7...31.4,
        ]
        for (body, helio) in heliocentricRange {
            for step in 0..<120 {
                let jd = JulianDate(ut: 2_451_545 + Double(step) * 197.3)
                let state = Ephemeris.state(of: body, at: jd)
                XCTAssertTrue(helio.contains(try XCTUnwrap(state.heliocentricDistanceAU)), "\(body) r at step \(step)")
                XCTAssertTrue(try XCTUnwrap(geocentricRange[body]).contains(state.distanceAU), "\(body) Δ at step \(step)")
            }
        }
    }

    /// DE440s: Mars at opposition on 2020 October 13, 23h UT, 0.4192 AU away, magnitude −2.69.
    func testMarsOppositionOfOctober2020() throws {
        let jd = JulianDate(ut: JulianDate.julianDay(year: 2020, month: 10, day: 13, hour: 23))
        let state = Ephemeris.state(of: .mars, at: jd)
        XCTAssertEqual(state.distanceAU, 0.4192, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(state.elongation), 177.0, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), -2.69, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(state.illuminatedFraction), 0.9997, accuracy: 0.0005)
        XCTAssertEqual(state.angularDiameterArcseconds, 22.3, accuracy: 0.1)
    }

    /// DE440s: Venus at inferior conjunction on 2020 June 3 (0.2886 AU, a 58″ crescent) and at greatest
    /// western elongation on 2020 August 13 (45.8°, half lit, magnitude −4.43).
    func testVenusAtInferiorConjunctionAndGreatestElongation() throws {
        let conjunctionDate = JulianDate.julianDay(year: 2020, month: 6, day: 3, hour: 12)
        let conjunction = Ephemeris.state(of: .venus, at: JulianDate(ut: conjunctionDate))
        XCTAssertEqual(try XCTUnwrap(conjunction.elongation), 0.66, accuracy: 0.02)
        XCTAssertEqual(conjunction.distanceAU, 0.2886, accuracy: 0.0005)
        XCTAssertEqual(conjunction.angularDiameterArcseconds, 57.8, accuracy: 0.3)
        XCTAssertLessThan(try XCTUnwrap(conjunction.illuminatedFraction), 0.0005)
        XCTAssertGreaterThan(try XCTUnwrap(conjunction.phaseAngle), 178)
        XCTAssertEqual(try XCTUnwrap(conjunction.apparentMagnitude), -3.2, accuracy: 0.1)

        let elongation = Ephemeris.state(of: .venus, at: JulianDate(ut: JulianDate.julianDay(year: 2020, month: 8, day: 13)))
        XCTAssertEqual(try XCTUnwrap(elongation.elongation), 45.79, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(elongation.illuminatedFraction), 0.5007, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(elongation.apparentMagnitude), -4.43, accuracy: 0.03)
    }

    /// Saturn's rings were wide open at the 2017 opposition (magnitude −0.06) and edge-on in March 2025
    /// (1.14, DE440s with Mallama & Hilton): the tilt alone dims the planet by 1.2 magnitudes.
    func testSaturnRingTiltChangesTheMagnitude() throws {
        let open = Ephemeris.state(of: .saturn, at: JulianDate(ut: JulianDate.julianDay(year: 2017, month: 6, day: 15)))
        let edgeOn = Ephemeris.state(of: .saturn, at: JulianDate(ut: JulianDate.julianDay(year: 2025, month: 3, day: 23)))
        XCTAssertEqual(try XCTUnwrap(open.apparentMagnitude), -0.06, accuracy: 0.03)
        XCTAssertEqual(try XCTUnwrap(edgeOn.apparentMagnitude), 1.14, accuracy: 0.05)
    }

    // MARK: Mallama & Hilton equations (reference values from Skyfield's magnitudelib)

    func testPhotometryReproducesSkyfieldReferenceValues() {
        typealias P = Ephemeris.Photometry
        let tolerance = 1e-9
        XCTAssertEqual(P.mercury(sunDistance: 0.387, earthDistance: 0.8, phaseAngle: 60), -1.2447218703, accuracy: tolerance)
        XCTAssertEqual(P.mercury(sunDistance: 0.45, earthDistance: 1.3, phaseAngle: 120), 2.3549732248, accuracy: tolerance)
        XCTAssertEqual(P.mercury(sunDistance: 0.31, earthDistance: 0.72, phaseAngle: 145), 2.1457947204, accuracy: tolerance)
        XCTAssertEqual(P.venus(sunDistance: 0.723, earthDistance: 0.5, phaseAngle: 100), -4.9310584918, accuracy: tolerance)
        XCTAssertEqual(P.venus(sunDistance: 0.725, earthDistance: 1.5, phaseAngle: 30), -3.9700818919, accuracy: tolerance)
        XCTAssertEqual(P.venus(sunDistance: 0.72, earthDistance: 0.3, phaseAngle: 170), -4.0424252442, accuracy: tolerance)
        XCTAssertEqual(P.mars(sunDistance: 1.5, earthDistance: 0.6, phaseAngle: 20), -1.4284674528, accuracy: tolerance)
        XCTAssertEqual(P.mars(sunDistance: 1.6, earthDistance: 2.0, phaseAngle: 45), 1.6812448916, accuracy: tolerance)
        XCTAssertEqual(P.mars(sunDistance: 1.4, earthDistance: 2.5, phaseAngle: 60), 2.0497402218, accuracy: tolerance)
        XCTAssertEqual(P.jupiter(sunDistance: 5.2, earthDistance: 4.2, phaseAngle: 5), -2.6851868298, accuracy: tolerance)
        XCTAssertEqual(P.jupiter(sunDistance: 5.4, earthDistance: 6.2, phaseAngle: 11), -1.7006067534, accuracy: tolerance)
        XCTAssertEqual(P.saturn(sunDistance: 9.5, earthDistance: 8.5, phaseAngle: 3, sunLatitude: 10, earthLatitude: 12),
                       0.3528264210, accuracy: tolerance)
        XCTAssertEqual(P.saturn(sunDistance: 9.5, earthDistance: 10, phaseAngle: 5.5, sunLatitude: -20, earthLatitude: -5),
                       0.8007098250, accuracy: tolerance)
        // Opposite sides of the ring plane: the rings do not contribute.
        XCTAssertEqual(P.saturn(sunDistance: 9.6, earthDistance: 9, phaseAngle: 4, sunLatitude: 10, earthLatitude: -5),
                       0.8725687124, accuracy: tolerance)
        XCTAssertEqual(P.uranus(sunDistance: 19.2, earthDistance: 18.2, sunLatitude: 60, earthLatitude: 50),
                       5.5606630834, accuracy: tolerance)
        XCTAssertEqual(P.uranus(sunDistance: 19, earthDistance: 20, sunLatitude: -10, earthLatitude: 30),
                       5.7721179831, accuracy: tolerance)
        XCTAssertEqual(P.neptune(sunDistance: 30.1, earthDistance: 29.1, year: 2026.8), 7.7122974229, accuracy: tolerance)
        XCTAssertEqual(P.neptune(sunDistance: 30, earthDistance: 31, year: 1990.5), 7.8957147428, accuracy: tolerance)
        XCTAssertEqual(P.neptune(sunDistance: 29.9, earthDistance: 29, year: 1970), 7.8003459312, accuracy: tolerance)
    }

    func testSunAndMoonMagnitudes() {
        typealias P = Ephemeris.Photometry
        XCTAssertEqual(P.sun(distanceAU: 1), -26.74, accuracy: 1e-12)
        XCTAssertEqual(P.sun(distanceAU: 100), -16.74, accuracy: 1e-12)
        let meanDistance = 384_400 / SkyFrame.kilometersPerAU
        // Full moon at the mean distance, and a quarter moon (Allen: −12.73 + 0.026·90 + 4e-9·90⁴).
        XCTAssertEqual(P.moon(sunDistance: 1, earthDistance: meanDistance, phaseAngle: 0), -12.73, accuracy: 1e-9)
        XCTAssertEqual(P.moon(sunDistance: 1, earthDistance: meanDistance, phaseAngle: 90), -10.128, accuracy: 0.001)
        // A body 10 % closer is 0.2 magnitudes brighter.
        XCTAssertEqual(P.moon(sunDistance: 1, earthDistance: meanDistance * 0.9, phaseAngle: 0), -12.73 + 5 * log10(0.9),
                       accuracy: 1e-9)
    }

    // MARK: BodyState invariants

    func testBodyStateInvariantsAcrossBodiesAndTime() throws {
        for body in SolarSystemBody.allCases {
            for step in 0..<400 {
                let jd = JulianDate(ut: 2_415_020.5 + Double(step) * 197.37)
                let state = Ephemeris.state(of: body, at: jd)
                let message = "\(body) at JD \(jd.ut)"
                XCTAssertEqual(state.body, body)
                XCTAssertEqual(state.julianDate, jd)
                XCTAssertTrue(state.geocentricJ2000.isFinite, message)
                XCTAssertGreaterThan(state.distanceAU, 0, message)
                XCTAssertEqual(state.distanceAU, state.geocentricJ2000.length, accuracy: 1e-12, message)
                XCTAssertGreaterThan(state.angularDiameterArcseconds, 0, message)
                XCTAssertTrue((0..<360).contains(state.eclipticLongitudeOfDate), message)
                XCTAssertTrue((-90...90).contains(state.eclipticLatitudeOfDate), message)
                // Largest geocentric ecliptic latitudes: the Moon 5.3°, Venus 8.9°, the other planets less.
                let latitudeLimit = body == .sun ? 0.001 : (body == .moon ? 5.4 : 9.5)
                XCTAssertLessThan(abs(state.eclipticLatitudeOfDate), latitudeLimit, message)

                XCTAssertEqual(state.heliocentricDistanceAU == nil, body == .sun, message)
                XCTAssertEqual(state.elongation == nil, body == .sun, message)
                XCTAssertEqual(state.phaseAngle == nil, body == .sun, message)
                XCTAssertEqual(state.illuminatedFraction == nil, body == .sun, message)
                XCTAssertNotNil(state.apparentMagnitude, message)
                XCTAssertEqual(state.isWaxing == nil, body != .moon, message)
                if body != .sun {
                    let elongation = try XCTUnwrap(state.elongation)
                    let phaseAngle = try XCTUnwrap(state.phaseAngle)
                    let fraction = try XCTUnwrap(state.illuminatedFraction)
                    XCTAssertTrue((0...180).contains(elongation), message)
                    XCTAssertTrue((0...180).contains(phaseAngle), message)
                    XCTAssertTrue((0...1).contains(fraction), message)
                    XCTAssertEqual(fraction, (1 + cos(AstroMath.radians(phaseAngle))) / 2, accuracy: 1e-12, message)
                    XCTAssertTrue(try XCTUnwrap(state.heliocentricDistanceAU) > 0, message)
                }
                if body == .moon {
                    XCTAssertTrue((356_000...407_000).contains(state.distanceKilometers), message)
                    // 1737.4 km seen from 356 700–406 500 km: 29.4′ to 33.5′ across.
                    XCTAssertTrue((29.3...33.5).contains(state.angularDiameterArcseconds / 60), message)
                    // Waxing means east of the Sun: elongation measured eastwards below 180°.
                    let sun = Ephemeris.state(of: .sun, at: jd)
                    let separation = state.eclipticLongitudeOfDate - sun.eclipticLongitudeOfDate
                    let eastOfSun = AstroMath.normalizeDegrees(separation) < 180
                    XCTAssertEqual(state.isWaxing, eastOfSun, message)
                    // Inner and outer limits of the Moon's phase angle follow from its elongation:
                    // phase angle + elongation ≈ 180° (the Sun is far away).
                    XCTAssertEqual(try XCTUnwrap(state.phaseAngle) + XCTUnwrap(state.elongation), 180, accuracy: 0.35, message)
                }
                if body == .mercury || body == .venus {
                    XCTAssertLessThan(try XCTUnwrap(state.elongation), body == .mercury ? 28.5 : 47.5, message)
                }
            }
        }
    }

    func testStateIsSendableHashableAndStable() {
        let jd = JulianDate(ut: 2_460_000.5)
        let state = Ephemeris.state(of: .jupiter, at: jd)
        let again = Ephemeris.state(of: .jupiter, at: jd)
        XCTAssertEqual(state, again)
        XCTAssertEqual(Set([state, again]).count, 1)
        XCTAssertNotEqual(state, Ephemeris.state(of: .jupiter, at: jd.addingDays(1)))
        let sendable: any Sendable = state
        XCTAssertNotNil(sendable)
    }

    func testStateForTimesFarFromToday() {
        // The series are trigonometric, so they stay finite and sensible for thousands of years.
        for year in [-2000, -1000, 0, 1000, 1800, 2200, 3000, 4000] {
            let jd = JulianDate(ut: JulianDate.julianDay(year: year, month: 6, day: 1))
            for body in SolarSystemBody.allCases {
                let state = Ephemeris.state(of: body, at: jd)
                XCTAssertTrue(state.geocentricJ2000.isFinite, "\(body) in \(year)")
                XCTAssertTrue(state.distanceAU > 0.002 && state.distanceAU < 35, "\(body) distance in \(year)")
            }
        }
    }

    func testNonFiniteTimesDoNotTrap() {
        for body in SolarSystemBody.allCases {
            let state = Ephemeris.state(of: body, at: JulianDate(ut: .nan, deltaT: 69))
            XCTAssertFalse(state.geocentricJ2000.isFinite)
        }
    }

    // MARK: SkyFrame conveniences

    func testSkyFrameConveniencesAgreeWithTheLowLevelPipeline() {
        let observer = Observer(location: GeographicLocation(latitude: 47.6, longitude: -122.3, elevation: 60))
        let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_790_000_000), observer: observer)
        for body in SolarSystemBody.allCases {
            let state = frame.state(of: body)
            XCTAssertEqual(state.julianDate, frame.julianDate)
            let vector = state.geocentricJ2000
            XCTAssertEqual(frame.horizontal(of: body), frame.horizontal(geocentricJ2000: vector, refraction: true))
            XCTAssertEqual(frame.horizontal(of: body, refraction: false),
                           frame.horizontal(geocentricJ2000: vector, refraction: false))
            XCTAssertEqual(frame.topocentricEquatorial(of: body), frame.topocentricEquatorial(geocentricJ2000: vector))
            XCTAssertEqual(frame.geocentricApparentEquatorial(of: body),
                           EquatorialCoordinate(vector: frame.precessionNutationMatrix * vector))
        }
    }

    func testMoonParallaxReachesAboutOneDegreeAtTheHorizon() {
        // Seen from the surface the Moon is displaced downwards by up to its horizontal parallax,
        // nearly 1°, relative to the geocentre; the Sun's parallax is only 8.8″.
        let observer = Observer(location: GeographicLocation(latitude: 20, longitude: 10))
        var largest = 0.0
        for halfHour in 0..<48 {
            let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_790_000_000 + Double(halfHour) * 1800), observer: observer)
            let geocentric = frame.geocentricApparentEquatorial(of: .moon)
            let topocentric = frame.topocentricEquatorial(of: .moon)
            largest = max(largest, geocentric.angularSeparation(to: topocentric))
            let sunShift = frame.geocentricApparentEquatorial(of: .sun)
                .angularSeparation(to: frame.topocentricEquatorial(of: .sun)) * 3600
            XCTAssertLessThan(sunShift, 9.0)
        }
        XCTAssertTrue((0.88...1.03).contains(largest), "largest displacement \(largest)°")
    }

    // MARK: Bodies

    func testSolarSystemBodyProperties() throws {
        XCTAssertEqual(SolarSystemBody.allCases.map(\.rawValue),
                       ["sun", "moon", "mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune"])
        XCTAssertEqual(SolarSystemBody.allCases.map(\.displayName),
                       ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"])
        XCTAssertEqual(SolarSystemBody.allCases.filter(\.isPlanet).count, 7)
        XCTAssertFalse(SolarSystemBody.sun.isPlanet)
        XCTAssertFalse(SolarSystemBody.moon.isPlanet)
        XCTAssertEqual(SolarSystemBody.moon.meanRadiusKilometers, 1737.4, accuracy: 0.05)
        XCTAssertEqual(SolarSystemBody.sun.meanRadiusKilometers, 695_700, accuracy: 1)
        XCTAssertEqual(SolarSystemBody.jupiter.meanRadiusKilometers, 69_911, accuracy: 1)
        for body in SolarSystemBody.allCases {
            XCTAssertGreaterThan(body.meanRadiusKilometers, 0)
            let data = try JSONEncoder().encode(body)
            XCTAssertEqual(try JSONDecoder().decode(SolarSystemBody.self, from: data), body)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(body.rawValue)\"")
        }
    }
}

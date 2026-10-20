import XCTest
@testable import LodestarKit

/// Orbital elements and two-body propagation of comets and asteroids.
final class CometsOrbitTests: XCTestCase {
    private func elements(q: Double = 1.0, e: Double = 0.5, i: Double = 0.0, w: Double = 0.0, node: Double = 0.0,
                          t: Double = 2_460_000.0, epoch: Double? = nil) throws -> SmallBodyElements {
        try XCTUnwrap(SmallBodyElements(perihelionDistanceAU: q, eccentricity: e, inclination: i, argumentOfPerihelion: w,
                                      longitudeOfAscendingNode: node, perihelionJulianDayTT: t, epochJulianDayTT: epoch))
    }

    private func create(_ q: Double, _ e: Double, _ i: Double, _ w: Double, _ node: Double, _ t: Double, _ epoch: Double? = nil) -> SmallBodyElements? {
        SmallBodyElements(perihelionDistanceAU: q, eccentricity: e, inclination: i, argumentOfPerihelion: w,
                        longitudeOfAscendingNode: node, perihelionJulianDayTT: t, epochJulianDayTT: epoch)
    }

    // MARK: Elements

    func testValidElementsKeepTheirValues() throws {
        let orbit = try elements(q: 0.5, e: 0.9, i: 30.0, w: 120.0, node: 250.0, t: 2_460_100.5, epoch: 2_460_000.5)
        XCTAssertEqual(orbit.perihelionDistanceAU, 0.5)
        XCTAssertEqual(orbit.eccentricity, 0.9)
        XCTAssertEqual(orbit.inclination, 30.0)
        XCTAssertEqual(orbit.argumentOfPerihelion, 120.0)
        XCTAssertEqual(orbit.longitudeOfAscendingNode, 250.0)
        XCTAssertEqual(orbit.perihelionJulianDayTT, 2_460_100.5)
        XCTAssertEqual(orbit.epochJulianDayTT, 2_460_000.5)
    }

    func testEpochDefaultsToThePerihelionTime() throws {
        XCTAssertEqual(try elements().epochJulianDayTT, 2_460_000.0)
    }

    func testAnglesAreReducedToTheirRange() throws {
        let orbit = try elements(w: -30.0, node: 725.0)
        XCTAssertEqual(orbit.argumentOfPerihelion, 330.0, accuracy: 1e-12)
        XCTAssertEqual(orbit.longitudeOfAscendingNode, 5.0, accuracy: 1e-12)
    }

    func testInvalidElementsAreRejected() {
        XCTAssertNil(create(0.0, 0.5, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(-1.0, 0.5, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(0.000_001, 0.5, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1_000.1, 0.5, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, -0.1, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 100.1, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, 180.1, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, -0.1, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, 0.0, Double.nan, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, Double.infinity, 2_460_000.0))
        XCTAssertNil(create(Double.nan, 0.5, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, Double.nan, 0.0, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, Double.nan, 0.0, 0.0, 2_460_000.0))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, 0.0, -1.0))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, 0.0, 6_000_001.0))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, 0.0, Double.nan))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, 0.0, 2_460_000.0, Double.nan))
        XCTAssertNil(create(1.0, 0.5, 0.0, 0.0, 0.0, 2_460_000.0, 7_000_000.0))
    }

    func testBoundaryValuesAreAccepted() {
        XCTAssertNotNil(create(0.00001, 0.0, 0.0, 0.0, 0.0, 0.0))
        XCTAssertNotNil(create(1000.0, 100.0, 180.0, 360.0, 360.0, 6_000_000.0))
    }

    func testShapeFollowsTheEccentricity() throws {
        XCTAssertEqual(try elements(e: 0.999_999_9).shape, .elliptic)
        XCTAssertEqual(try elements(e: 1.0).shape, .parabolic)
        XCTAssertEqual(try elements(e: 1.000_000_1).shape, .hyperbolic)
        XCTAssertEqual(try elements(e: 0.0).shape, .elliptic)
    }

    func testDerivedQuantitiesOfAnEllipse() throws {
        // Ceres (JPL SBDB): a = 2.765552595 AU, e = 0.07969229515 -> q = 2.545159361, Q = 2.985945829, P = 1679.853 d.
        let orbit = try elements(q: 2.545_159_361_382_861, e: 0.079_692_295_148_165_86)
        XCTAssertEqual(try XCTUnwrap(orbit.semiMajorAxisAU), 2.765_552_595_034_094, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(orbit.aphelionDistanceAU), 2.985_945_828_685_327, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(orbit.periodDays), 1_679.853_119_758_983, accuracy: 2e-3)
        XCTAssertEqual(try XCTUnwrap(orbit.periodYears), 1_679.853_119_758_983 / 365.25, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(orbit.meanMotion), 0.214_304_450_648_43, accuracy: 1e-8)
    }

    func testUnboundOrbitsHaveNoPeriod() throws {
        for e in [1.0, 1.5, 6.1] {
            let orbit = try elements(e: e)
            XCTAssertNil(orbit.semiMajorAxisAU)
            XCTAssertNil(orbit.aphelionDistanceAU)
            XCTAssertNil(orbit.meanMotion)
            XCTAssertNil(orbit.periodDays)
            XCTAssertNil(orbit.periodYears)
            XCTAssertNil(orbit.meanAnomaly(at: 2_460_010.0))
        }
    }

    func testMeanAnomalyGrowsFromPerihelion() throws {
        let orbit = try elements(q: 1.0, e: 0.0, t: 2_460_000.0)
        // A circular orbit of radius 1 AU has the Gaussian mean motion, 0.9856076686 degrees per day.
        XCTAssertEqual(try XCTUnwrap(orbit.meanMotion), 0.985_607_668_6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(orbit.meanAnomaly(at: 2_460_000.0)), 0.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(orbit.meanAnomaly(at: 2_460_100.0)), 98.560_766_86, accuracy: 1e-7)
        XCTAssertEqual(try XCTUnwrap(orbit.meanAnomaly(at: 2_459_900.0)), 360.0 - 98.560_766_86, accuracy: 1e-7)
    }

    func testMeanAnomalyConstructorRecoversTheAnomalyAtTheEpoch() throws {
        // Vesta (MPC): epoch 2026 June 9, M = 81.19019 degrees, a = 2.3613660 AU, e = 0.0902037.
        let orbit = try XCTUnwrap(SmallBodyElements.fromMeanAnomaly(
            semiMajorAxisAU: 2.361_366, eccentricity: 0.090_203_7, inclination: 7.143_93, argumentOfPerihelion: 151.468_56,
            longitudeOfAscendingNode: 103.701_35, meanAnomaly: 81.190_19, epochJulianDayTT: 2_461_200.5))
        XCTAssertEqual(try XCTUnwrap(orbit.meanAnomaly(at: 2_461_200.5)), 81.190_19, accuracy: 1e-9)
        XCTAssertEqual(orbit.perihelionDistanceAU, 2.361_366 * (1 - 0.090_203_7), accuracy: 1e-12)
        XCTAssertEqual(orbit.epochJulianDayTT, 2_461_200.5)
        // JPL's time of perihelion for the same orbit: 2460901.5874.
        XCTAssertEqual(orbit.perihelionJulianDayTT, 2_460_901.587_4, accuracy: 2e-3)
    }

    func testMeanAnomalyConstructorReducesTheAnomaly() throws {
        func make(_ anomaly: Double) throws -> SmallBodyElements {
            try XCTUnwrap(SmallBodyElements.fromMeanAnomaly(
                semiMajorAxisAU: 2.0, eccentricity: 0.1, inclination: 5.0, argumentOfPerihelion: 10.0,
                longitudeOfAscendingNode: 20.0, meanAnomaly: anomaly, epochJulianDayTT: 2_460_000.5))
        }
        let a = try make(40.0)
        let b = try make(400.0)
        let c = try make(-320.0)
        XCTAssertEqual(a.perihelionJulianDayTT, b.perihelionJulianDayTT, accuracy: 1e-9)
        XCTAssertEqual(a.perihelionJulianDayTT, c.perihelionJulianDayTT, accuracy: 1e-9)
    }

    func testMeanAnomalyConstructorRejectsInvalidInput() {
        func make(_ a: Double, _ e: Double, _ i: Double, _ m: Double, _ epoch: Double) -> SmallBodyElements? {
            SmallBodyElements.fromMeanAnomaly(semiMajorAxisAU: a, eccentricity: e, inclination: i, argumentOfPerihelion: 10.0,
                                            longitudeOfAscendingNode: 20.0, meanAnomaly: m, epochJulianDayTT: epoch)
        }
        XCTAssertNil(make(2.0, 1.0, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(2.0, 1.5, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(2.0, -0.1, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(0.0, 0.1, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(-2.0, 0.1, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(Double.nan, 0.1, 5.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(2.0, 0.1, 5.0, Double.nan, 2_460_000.5))
        XCTAssertNil(make(2.0, 0.1, 200.0, 40.0, 2_460_000.5))
        XCTAssertNil(make(2.0, 0.1, 5.0, 40.0, -5.0))
    }

    // MARK: Stumpff functions

    func testStumpffFunctionsAtZero() {
        XCTAssertEqual(OrbitPropagator.stumpffC(0.0), 0.5, accuracy: 1e-15)
        XCTAssertEqual(OrbitPropagator.stumpffS(0.0), 1.0 / 6.0, accuracy: 1e-15)
    }

    func testStumpffFunctionsSatisfyTheirDefiningIdentities() {
        // 1 - z C(z) = cos(sqrt z) and 1 - z S(z) = sin(sqrt z) / sqrt z, with cosh and sinh for z < 0.
        for z in [-400.0, -50.0, -4.0, -1.5, -1.0, -0.999, -0.3, -1e-6, 1e-9, 0.2, 0.999, 1.0, 1.001, 2.5, 4.0, 9.8696, 30.0, 400.0] {
            let c = OrbitPropagator.stumpffC(z)
            let s = OrbitPropagator.stumpffS(z)
            let cosine = z >= 0 ? cos(z.squareRoot()) : cosh((-z).squareRoot())
            let sinc = z > 0 ? sin(z.squareRoot()) / z.squareRoot() : (z < 0 ? sinh((-z).squareRoot()) / (-z).squareRoot() : 1.0)
            let scale = max(1.0, abs(cosine))
            XCTAssertEqual(1 - z * c, cosine, accuracy: 1e-12 * scale, "cos identity at z = \(z)")
            XCTAssertEqual(1 - z * s, sinc, accuracy: 1e-12 * max(1.0, abs(sinc)), "sin identity at z = \(z)")
        }
    }

    func testStumpffFunctionsAreContinuousAcrossTheSeriesBoundary() {
        for z in [1.0, -1.0] {
            XCTAssertEqual(OrbitPropagator.stumpffC(z - 1e-9), OrbitPropagator.stumpffC(z + 1e-9), accuracy: 1e-8)
            XCTAssertEqual(OrbitPropagator.stumpffS(z - 1e-9), OrbitPropagator.stumpffS(z + 1e-9), accuracy: 1e-8)
        }
        // Known values: C(4) = (1 - cos 2) / 4 and S(4) = (2 - sin 2) / 8.
        XCTAssertEqual(OrbitPropagator.stumpffC(4.0), (1 - cos(2.0)) / 4, accuracy: 1e-15)
        XCTAssertEqual(OrbitPropagator.stumpffS(4.0), (2 - sin(2.0)) / 8, accuracy: 1e-15)
        XCTAssertEqual(OrbitPropagator.stumpffC(-4.0), (cosh(2.0) - 1) / 4, accuracy: 1e-15)
        XCTAssertEqual(OrbitPropagator.stumpffS(-4.0), (sinh(2.0) - 2) / 8, accuracy: 1e-15)
    }

    // MARK: Kepler's equation against an independent solver

    func testUniversalSolverMatchesClassicalAnomaliesForEveryEccentricity() throws {
        var worst = 0.0
        for c in CometsKeplerData.cases {
            let position = try XCTUnwrap(OrbitPropagator.perifocal(q: c.q, e: c.e, days: c.days), "e = \(c.e), dt = \(c.days)")
            let error = max(abs(position.x - c.x), abs(position.y - c.y))
            let tolerance = 1e-10 * max(1.0, c.r)
            XCTAssertTrue(error <= tolerance, "e = \(c.e), q = \(c.q), dt = \(c.days): error \(error) AU")
            XCTAssertEqual(position.r, c.r, accuracy: tolerance, "distance e = \(c.e), dt = \(c.days)")
            worst = max(worst, error / max(1.0, c.r))
        }
        XCTAssertTrue(worst < 1e-10, "worst relative error \(worst)")
    }

    func testMeeusExampleForKeplersEquation() throws {
        // Meeus, Astronomical Algorithms, Example 30.a: e = 0.1, M = 5 degrees gives E = 5.554589 degrees.
        // For a = 1 AU the mean motion is k radians per day, so M = 5 degrees takes 5 / 0.9856076686 days.
        let q = 0.9
        let days = 5.0 / AstroMath.degrees(OrbitPropagator.gaussianGravitationalConstant)
        let position = try XCTUnwrap(OrbitPropagator.perifocal(q: q, e: 0.1, days: days))
        let eccentricAnomaly = AstroMath.radians(5.554_589)
        XCTAssertEqual(position.x, cos(eccentricAnomaly) - 0.1, accuracy: 2e-8)
        XCTAssertEqual(position.y, (1 - 0.01).squareRoot() * sin(eccentricAnomaly), accuracy: 2e-8)
    }

    func testParabolicOrbitFollowsBarkersEquation() throws {
        // Meeus ch. 34: for e = 1, r = q (1 + s^2) with s = tan(nu / 2) and s + s^3 / 3 = k dt / sqrt(2 q^3).
        let q = 0.921
        let days = 52.5
        let position = try XCTUnwrap(OrbitPropagator.perifocal(q: q, e: 1.0, days: days))
        let w = OrbitPropagator.gaussianGravitationalConstant * days / (2 * q * q * q).squareRoot()
        var s = w
        for _ in 0..<60 { s -= (s + s * s * s / 3 - w) / (1 + s * s) }
        XCTAssertEqual(position.x, q * (1 - s * s), accuracy: 1e-12)
        XCTAssertEqual(position.y, 2 * q * s, accuracy: 1e-12)
        XCTAssertEqual(position.r, q * (1 + s * s), accuracy: 1e-12)
    }

    // MARK: Invariants

    func testPositionIsContinuousThroughEccentricityOne() throws {
        for days in [-120.0, 3.0, 60.0, 900.0] {
            let below = try XCTUnwrap(OrbitPropagator.perifocal(q: 0.8, e: 0.999_999_9, days: days))
            let parabola = try XCTUnwrap(OrbitPropagator.perifocal(q: 0.8, e: 1.0, days: days))
            let above = try XCTUnwrap(OrbitPropagator.perifocal(q: 0.8, e: 1.000_000_1, days: days))
            XCTAssertEqual(below.x, parabola.x, accuracy: 1e-5)
            XCTAssertEqual(below.y, parabola.y, accuracy: 1e-5)
            XCTAssertEqual(above.x, parabola.x, accuracy: 1e-5)
            XCTAssertEqual(above.y, parabola.y, accuracy: 1e-5)
        }
    }

    func testEllipseRepeatsAfterOnePeriod() throws {
        let orbit = try elements(q: 0.587, e: 0.967, i: 162.0, w: 112.0, node: 59.0, t: 2_446_470.0)
        let period = try XCTUnwrap(orbit.periodDays)
        for offset in [-3000.0, 0.0, 40.0, 4000.0] {
            let first = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: 2_446_470.0 + offset))
            for cycles in [1.0, 7.0, -4.0] {
                let later = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: 2_446_470.0 + offset + cycles * period))
                XCTAssertTrue((first - later).length < 2e-9 * max(1.0, first.length), "offset \(offset), cycles \(cycles)")
            }
        }
    }

    func testVisVivaAndAngularMomentumHoldAlongTheOrbit() throws {
        let mu = OrbitPropagator.gaussianGravitationalConstant * OrbitPropagator.gaussianGravitationalConstant
        for e in [0.3, 0.97, 1.0, 1.0004, 2.2] {
            let orbit = try elements(q: 0.6, e: e, i: 35.0, w: 80.0, node: 200.0, t: 2_460_000.0)
            let expectedMomentum = (mu * 0.6 * (1 + e)).squareRoot()
            for days in [-300.0, -20.0, 0.5, 45.0, 700.0] {
                let step = 0.01
                let before = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: 2_460_000.0 + days - step))
                let here = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: 2_460_000.0 + days))
                let after = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: 2_460_000.0 + days + step))
                let velocity = (after - before) / (2 * step)
                let momentum = here.cross(velocity).length
                XCTAssertEqual(momentum, expectedMomentum, accuracy: 2e-7 * expectedMomentum, "e = \(e), dt = \(days)")
                let inverseAxis = (1 - e) / 0.6
                let expectedSpeedSquared = mu * (2 / here.length - inverseAxis)
                XCTAssertEqual(velocity.dot(velocity), expectedSpeedSquared, accuracy: 1e-6 * expectedSpeedSquared, "e = \(e), dt = \(days)")
            }
        }
    }

    func testPerihelionIsTheClosestPoint() throws {
        for e in [0.2, 1.0, 3.0] {
            let orbit = try elements(q: 0.75, e: e, t: 2_460_000.0)
            let atPerihelion = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_460_000.0))
            XCTAssertEqual(atPerihelion, 0.75, accuracy: 1e-12)
            for days in [-30.0, -1.0, 1.0, 30.0] {
                XCTAssertTrue(try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_460_000.0 + days)) > 0.75)
            }
        }
    }

    // MARK: Orientation

    func testOrientationAnglesRotateThePlane() throws {
        let t = 2_460_000.0
        // Zero angles: perihelion on the +x axis of the ecliptic, motion towards +y.
        let flat = try elements(q: 1.0, e: 0.5, t: t)
        let flatPerihelion = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: flat, at: t))
        XCTAssertEqual(flatPerihelion.x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(flatPerihelion.y, 0.0, accuracy: 1e-12)
        XCTAssertEqual(flatPerihelion.z, 0.0, accuracy: 1e-12)
        XCTAssertTrue(try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: flat, at: t + 5)).y > 0)
        // The argument of perihelion turns the perihelion within the plane.
        let turned = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: try elements(q: 1.0, e: 0.5, w: 90.0, t: t), at: t))
        XCTAssertEqual(turned.x, 0.0, accuracy: 1e-12)
        XCTAssertEqual(turned.y, 1.0, accuracy: 1e-12)
        // The node turns the whole orbit about the pole.
        let node = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: try elements(q: 1.0, e: 0.5, node: 90.0, t: t), at: t))
        XCTAssertEqual(node.x, 0.0, accuracy: 1e-12)
        XCTAssertEqual(node.y, 1.0, accuracy: 1e-12)
        // With the perihelion at the ascending node (w = 0) and i = 90 degrees the orbit climbs towards +z.
        let polar = try elements(q: 1.0, e: 0.5, i: 90.0, t: t)
        let climbing = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: polar, at: t + 20))
        XCTAssertTrue(climbing.z > 0.1)
        XCTAssertEqual(climbing.y, 0.0, accuracy: 1e-12)
        // A retrograde orbit (i = 180) runs towards -y.
        XCTAssertTrue(try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: try elements(i: 180.0, t: t), at: t + 5)).y < 0)
    }

    func testEquatorialFrameIsTheEclipticTiltedByTheObliquityOfJ2000() throws {
        let t = 2_460_000.0
        let orbit = try elements(q: 1.0, e: 0.0, w: 90.0, t: t)
        let ecliptic = try XCTUnwrap(OrbitPropagator.heliocentricEcliptic(of: orbit, at: t))
        let equatorial = try XCTUnwrap(OrbitPropagator.heliocentricJ2000(of: orbit, at: t))
        let obliquity = AstroMath.radians(Obliquity.j2000)
        XCTAssertEqual(equatorial.x, ecliptic.x, accuracy: 1e-14)
        XCTAssertEqual(equatorial.y, ecliptic.y * cos(obliquity) - ecliptic.z * sin(obliquity), accuracy: 1e-14)
        XCTAssertEqual(equatorial.z, ecliptic.y * sin(obliquity) + ecliptic.z * cos(obliquity), accuracy: 1e-14)
        XCTAssertEqual(equatorial.length, ecliptic.length, accuracy: 1e-14)
        // The +y ecliptic axis points to RA 90 degrees, dec 23.44 degrees.
        XCTAssertEqual(EquatorialCoordinate(vector: equatorial).declination, Obliquity.j2000, accuracy: 1e-9)
    }

    // MARK: Domain

    func testUnboundOrbitsAreLimitedToTheSpanAroundPerihelion() throws {
        let orbit = try elements(q: 0.4, e: 1.0002, t: 2_460_000.0)
        XCTAssertNotNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: 2_460_000.0 + 49_999.0))
        XCTAssertNotNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: 2_460_000.0 - 49_999.0))
        XCTAssertNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: 2_460_000.0 + 50_001.0))
        XCTAssertNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: 2_460_000.0 - 50_001.0))
        XCTAssertNil(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_460_000.0 + 1e9))
        XCTAssertEqual(OrbitPropagator.maximumUnboundSpanDays, 50_000.0)
    }

    func testEllipsesWorkForAnyDate() throws {
        let orbit = try elements(q: 2.0, e: 0.1, t: 2_460_000.0)
        for jd in [0.0, 1e5, 5e6, 5.9e6] {
            XCTAssertNotNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: jd))
        }
    }

    func testNonFiniteDatesGiveNothing() throws {
        let orbit = try elements()
        XCTAssertNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: Double.nan))
        XCTAssertNil(OrbitPropagator.heliocentricJ2000(of: orbit, at: Double.infinity))
        XCTAssertNil(OrbitPropagator.heliocentricEcliptic(of: orbit, at: -Double.infinity))
        XCTAssertNil(OrbitPropagator.heliocentricDistance(of: orbit, at: Double.nan))
    }

    func testNearParabolicEllipseWithAHugePeriodStillSolves() throws {
        // e = 1 - 1e-12 has an enormous semi-major axis; the position stays finite and close to the parabola.
        let orbit = try elements(q: 1.0, e: 1.0 - 1e-12, t: 2_460_000.0)
        let position = try XCTUnwrap(OrbitPropagator.perifocal(q: 1.0, e: 1.0 - 1e-12, days: 100.0))
        let parabola = try XCTUnwrap(OrbitPropagator.perifocal(q: 1.0, e: 1.0, days: 100.0))
        XCTAssertEqual(position.x, parabola.x, accuracy: 1e-9)
        XCTAssertEqual(position.y, parabola.y, accuracy: 1e-9)
        XCTAssertNotNil(orbit.periodDays)
    }

    func testFarHyperbolasConvergeToTheClassicalSolution() throws {
        // Barker's parabola, the start of the iteration, is far too high when (e - 1) / q is large (for q = 0.01 and
        // e = 10 it puts sqrt(-z) at 240 where the root is at 15), and plain Newton steps then only lower it by about 1.
        // That used to run out of iterations with r around 1e58 AU. The reference solves e sinh H - H = M by bisection.
        let cases: [(q: Double, e: Double, days: Double)] = [
            (0.01, 10.0, 50_000.0), (0.01, 10.0, -50_000.0), (0.01, 5.0, 20_000.0),
            (1e-5, 100.0, 50_000.0), (0.01, 100.0, -50_000.0)
        ]
        for c in cases {
            let a = c.q / (c.e - 1)
            let meanAnomaly = OrbitPropagator.gaussianGravitationalConstant * abs(c.days) / (a * a.squareRoot())
            var low = 0.0
            var high = 100.0
            for _ in 0..<200 {
                let middle = 0.5 * (low + high)
                if c.e * sinh(middle) - middle > meanAnomaly { high = middle } else { low = middle }
            }
            let anomaly = 0.5 * (low + high)
            let r = a * (c.e * cosh(anomaly) - 1)
            let x = a * (c.e - cosh(anomaly))
            let y = (c.days < 0 ? -1.0 : 1.0) * a * (c.e * c.e - 1).squareRoot() * sinh(anomaly)
            let position = try XCTUnwrap(OrbitPropagator.perifocal(q: c.q, e: c.e, days: c.days), "q = \(c.q), e = \(c.e), dt = \(c.days)")
            XCTAssertEqual(position.r, r, accuracy: 1e-9 * r, "distance q = \(c.q), e = \(c.e), dt = \(c.days)")
            XCTAssertEqual(position.x, x, accuracy: 1e-9 * r, "x q = \(c.q), e = \(c.e), dt = \(c.days)")
            XCTAssertEqual(position.y, y, accuracy: 1e-9 * r, "y q = \(c.q), e = \(c.e), dt = \(c.days)")
        }
        let orbit = try elements(q: 0.01, e: 10.0, t: 2_460_000.0)
        let distance = try XCTUnwrap(OrbitPropagator.heliocentricDistance(of: orbit, at: 2_460_000.0 + 50_000.0))
        XCTAssertTrue(distance > 25_000.0 && distance < 26_000.0, "distance \(distance) AU")
    }

    func testInvalidInputsToTheSolverGiveNothing() {
        // The semi-major axis overflows, so the period is not a number.
        XCTAssertNil(OrbitPropagator.perifocal(q: 1e300, e: 1.0 - 1e-16, days: 1.0))
        XCTAssertNil(OrbitPropagator.perifocal(q: -1.0, e: 0.5, days: 1.0))
        XCTAssertNil(OrbitPropagator.perifocal(q: 0.0, e: 0.5, days: 1.0))
        XCTAssertNil(OrbitPropagator.perifocal(q: 1.0, e: -0.5, days: 1.0))
        XCTAssertNil(OrbitPropagator.perifocal(q: Double.nan, e: 0.5, days: 1.0))
        XCTAssertNil(OrbitPropagator.perifocal(q: 1.0, e: Double.nan, days: 1.0))
    }

    func testSolverIsFast() throws {
        var checksum = 0.0
        let started = Date()
        for index in 0..<200_000 {
            let e: Double
            switch index % 4 {
            case 0: e = 0.1
            case 1: e = 0.97
            case 2: e = 1.0
            default: e = 1.5
            }
            let position = try XCTUnwrap(OrbitPropagator.perifocal(q: 0.8, e: e, days: Double((index % 997) - 400)))
            checksum += position.r
        }
        let seconds = Date().timeIntervalSince(started)
        XCTAssertTrue(checksum > 0)
        XCTAssertTrue(seconds < 30.0, "200 000 solutions took \(seconds) s")
        XCTAssertFalse(checksum.isNaN)
    }
}

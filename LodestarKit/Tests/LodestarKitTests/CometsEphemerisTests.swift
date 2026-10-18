import XCTest
@testable import LodestarKit

/// Positions, distances, magnitudes and tails of comets and asteroids against JPL Horizons (https://ssd.jpl.nasa.gov/api/horizons.api,
/// queried 2026-10-18). Each case takes the osculating elements Horizons itself reports at an epoch (so only planetary
/// perturbations separate the two-body motion from Horizons' N-body integration) and compares the observer table at
/// and around that epoch: C/2023 A3 (Tsuchinshan-ATLAS) in October 2024, 12P/Pons-Brooks in April 2024, 1P/Halley in
/// 1986, and the asteroids (4) Vesta and (1) Ceres in 2026.
///
/// Expected two-body error (measured, see the tolerances below): below 1 arcsecond at the epoch and within 1.2 arcseconds
/// after 15 days for a comet 0.5 AU from the Earth; 0.6 arcseconds after 60 days for Halley; 4 arcseconds after 120 days
/// for the main-belt asteroids. Elements that are months old are still good to an arcminute (see `staleElements`),
/// elements that are decades old are not.
final class CometsEphemerisTests: XCTestCase {
    private func body(_ item: CometsHorizonsData.Case) throws -> SmallBody {
        let orbit = try XCTUnwrap(OrbitalElements(
            perihelionDistanceAU: item.perihelionDistance, eccentricity: item.eccentricity, inclination: item.inclination,
            argumentOfPerihelion: item.argumentOfPerihelion, longitudeOfAscendingNode: item.ascendingNode,
            perihelionJulianDayTT: item.perihelionTimeTDB, epochJulianDayTT: item.epochTDB))
        let isAsteroid = item.title.hasPrefix("(")
        let photometry: SmallBodyPhotometry
        if isAsteroid {
            photometry = .asteroid(try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: item.absoluteMagnitude, slopeParameter: item.slope)))
        } else {
            photometry = .comet(try XCTUnwrap(CometMagnitudes(
                totalMagnitude: item.absoluteMagnitude, totalSlope: item.slope, nuclearMagnitude: item.nuclearMagnitude,
                nuclearSlope: item.nuclearSlope, nuclearPhaseCoefficient: item.nuclearPhaseCoefficient)))
        }
        return try XCTUnwrap(SmallBody(designation: item.title, kind: isAsteroid ? .asteroid : .comet, orbit: orbit,
                                       photometry: photometry))
    }

    private func arcseconds(_ a: Vector3, _ b: Vector3) -> Double { a.angle(to: b) * 3600 }

    private func direction(_ ra: Double, _ dec: Double) -> Vector3 {
        EquatorialCoordinate(rightAscension: ra, declination: dec).unitVector
    }

    /// Allowed two-body error in arcseconds at `offset` days from the epoch.
    private func allowedArcseconds(_ offset: Double) -> Double { 2.0 + 0.1 * abs(offset) }

    private func state(_ small: SmallBody, _ item: CometsHorizonsData.Case, _ offset: Double) throws -> SmallBodyState {
        try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: item.epochTDB + offset)))
    }

    // MARK: Horizons

    func testAstrometricPositionsAgreeWithHorizons() throws {
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let state = try state(small, item, row.offsetDays)
                let error = arcseconds(state.astrometricJ2000, direction(row.raAstrometric, row.decAstrometric))
                XCTAssertTrue(error <= allowedArcseconds(row.offsetDays), "\(item.title) at \(row.offsetDays) d: \(error) arcsec")
            }
        }
    }

    func testApparentPositionsAgreeWithHorizons() throws {
        // Horizons' "a-app" is the geocentric apparent place: true equator and equinox of date, light-time, deflection, aberration.
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let julianDate = JulianDate(ut: item.epochTDB + row.offsetDays)
                let frame = SkyFrame(julianDate: julianDate, observer: Observer(location: GeographicLocation(latitude: 0.0, longitude: 0.0, elevation: 0.0)))
                let apparent = try XCTUnwrap(frame.geocentricApparentEquatorial(of: small))
                let error = apparent.angularSeparation(to: EquatorialCoordinate(rightAscension: row.raApparent, declination: row.decApparent)) * 3600
                XCTAssertTrue(error <= allowedArcseconds(row.offsetDays) + 0.5, "\(item.title) at \(row.offsetDays) d: \(error) arcsec")
            }
        }
    }

    func testAberrationDisplacesTheApparentPositionByTheConstantOfAberration() throws {
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let state = try state(small, item, row.offsetDays)
                let shift = arcseconds(state.astrometricJ2000, state.geocentricJ2000)
                XCTAssertTrue(shift > 0.5 && shift < 21.0, "\(item.title): \(shift) arcsec")
                XCTAssertEqual(state.geocentricJ2000.length, state.astrometricJ2000.length, accuracy: 1e-12)
            }
        }
    }

    func testDistancesElongationAndPhaseAgreeWithHorizons() throws {
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let state = try state(small, item, row.offsetDays)
                XCTAssertEqual(state.heliocentricDistanceAU, row.sunDistance, accuracy: 5e-5, "\(item.title) r at \(row.offsetDays)")
                XCTAssertEqual(state.distanceAU, row.earthDistance, accuracy: 5e-5, "\(item.title) delta at \(row.offsetDays)")
                XCTAssertEqual(state.elongation, row.elongation, accuracy: 0.01, "\(item.title) elongation at \(row.offsetDays)")
                XCTAssertEqual(state.phaseAngle, row.phaseAngle, accuracy: 0.03, "\(item.title) phase at \(row.offsetDays)")
                XCTAssertEqual(state.distanceKilometers, state.distanceAU * SkyFrame.kilometersPerAU, accuracy: 1e-3)
                XCTAssertEqual(state.heliocentricDistanceAU, state.heliocentricJ2000.length, accuracy: 1e-15)
            }
        }
    }

    func testMagnitudesAgreeWithHorizons() throws {
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let state = try state(small, item, row.offsetDays)
                let magnitude = try XCTUnwrap(state.apparentMagnitude)
                if row.magnitude == 6.0 && item.title.hasPrefix("C/2023 A3") {
                    // Horizons lists nothing brighter than 6.0 for this record (the formula gives 5.83 and 5.87).
                    XCTAssertTrue(magnitude <= 6.0 && magnitude >= 5.8, "\(item.title): \(magnitude)")
                } else {
                    XCTAssertEqual(magnitude, row.magnitude, accuracy: 0.01, "\(item.title) at \(row.offsetDays)")
                }
                if let nuclear = row.nuclearMagnitude {
                    XCTAssertEqual(try XCTUnwrap(state.nuclearMagnitude), nuclear, accuracy: 0.01, "\(item.title) nuclear at \(row.offsetDays)")
                } else {
                    XCTAssertNil(state.nuclearMagnitude)
                }
            }
        }
    }

    func testMagnitudesFollowTheCatalogFormulas() {
        // Independent evaluation of the formulas with Horizons' own r and delta.
        for item in CometsHorizonsData.cases where !item.title.hasPrefix("(") {
            for row in item.rows where row.magnitude != 6.0 {
                let total = item.absoluteMagnitude + 5 * log10(row.earthDistance) + item.slope * log10(row.sunDistance)
                XCTAssertEqual(total, row.magnitude, accuracy: 0.0006, "\(item.title) total at \(row.offsetDays)")
                if let nuclearMagnitude = item.nuclearMagnitude, let nuclearSlope = item.nuclearSlope, let nuclear = row.nuclearMagnitude {
                    let expected = nuclearMagnitude + 5 * log10(row.earthDistance) + nuclearSlope * log10(row.sunDistance)
                        + item.nuclearPhaseCoefficient * row.phaseAngle
                    XCTAssertEqual(expected, nuclear, accuracy: 0.0006, "\(item.title) nuclear at \(row.offsetDays)")
                }
            }
        }
    }

    func testAsteroidMagnitudeFollowsTheIAUHGSystem() throws {
        // (4) Vesta, H = 3.25, G = 0.32; Horizons APmag 8.018 for r = 2.347784276612, delta = 2.53640919646355, alpha = 23.5847 degrees.
        let vesta = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 3.25, slopeParameter: 0.32))
        XCTAssertEqual(try XCTUnwrap(vesta.apparent(sunDistanceAU: 2.347_784_276_612, earthDistanceAU: 2.536_409_196_463_55, phaseAngle: 23.5847)), 8.018, accuracy: 0.0006)
        // (1) Ceres, H = 3.34, G = 0.12: 8.855 at alpha = 5.0813 degrees.
        let ceres = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 3.34, slopeParameter: 0.12))
        XCTAssertEqual(try XCTUnwrap(ceres.apparent(sunDistanceAU: 2.766_134_002_962, earthDistanceAU: 3.740_251_165_185_17, phaseAngle: 5.0813)), 8.855, accuracy: 0.0006)
        // At zero phase the magnitude is H + 5 log10(r delta).
        XCTAssertEqual(try XCTUnwrap(vesta.apparent(sunDistanceAU: 2.0, earthDistanceAU: 1.5, phaseAngle: 0.0)), 3.25 + 5 * log10(2.0 * 1.5), accuracy: 1e-12)
        // Fainter with growing phase angle, for any G.
        for g in [0.0, 0.15, 0.5, 1.0] {
            let magnitudes = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 10.0, slopeParameter: g))
            var previous = -100.0
            for phase in [0.0, 10.0, 30.0, 60.0, 90.0, 120.0] {
                let value = try XCTUnwrap(magnitudes.apparent(sunDistanceAU: 1.5, earthDistanceAU: 1.0, phaseAngle: phase))
                XCTAssertTrue(value > previous, "G = \(g), alpha = \(phase)")
                previous = value
            }
        }
        // G = 1 uses only the second basis function, G = 0 only the first.
        let phase = 40.0
        let t = tan(phase * Double.pi / 180 / 2)
        let first = exp(-3.33 * pow(t, 0.63))
        let second = exp(-1.87 * pow(t, 1.22))
        let onlyFirst = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 0.0, slopeParameter: 0.0))
        let onlySecond = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 0.0, slopeParameter: 1.0))
        XCTAssertEqual(try XCTUnwrap(onlyFirst.apparent(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: phase)), -2.5 * log10(first), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(onlySecond.apparent(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: phase)), -2.5 * log10(second), accuracy: 1e-12)
    }

    func testCometMagnitudeFormulas() throws {
        // 12P/Pons-Brooks on 2024 April 21: M1 = 5, K1 = 15, M2 = 11, K2 = 10 -> T-mag 4.416, N-mag 10.953 (Horizons).
        let magnitudes = try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 15.0, nuclearMagnitude: 11.0, nuclearSlope: 10.0))
        XCTAssertEqual(try XCTUnwrap(magnitudes.total(sunDistanceAU: 0.780_792_203_878, earthDistanceAU: 1.605_357_418_629_92)), 4.416, accuracy: 0.0006)
        XCTAssertEqual(try XCTUnwrap(magnitudes.nuclear(sunDistanceAU: 0.780_792_203_878, earthDistanceAU: 1.605_357_418_629_92, phaseAngle: 29.7253)), 10.953, accuracy: 0.0006)
        // 1P/Halley on 1986 Feb 9 with the phase coefficient PC = 0.03: N-mag 13.786.
        let halley = try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.5, totalSlope: 8.0, nuclearMagnitude: 13.6, nuclearSlope: 5.0, nuclearPhaseCoefficient: 0.03))
        XCTAssertEqual(try XCTUnwrap(halley.total(sunDistanceAU: 0.587_194_099_879, earthDistanceAU: 1.549_715_750_555_96)), 4.602, accuracy: 0.0006)
        XCTAssertEqual(try XCTUnwrap(halley.nuclear(sunDistanceAU: 0.587_194_099_879, earthDistanceAU: 1.549_715_750_555_96, phaseAngle: 13.0346)), 13.786, accuracy: 0.0006)
        // At r = delta = 1 AU the magnitude is M1.
        XCTAssertEqual(try XCTUnwrap(magnitudes.total(sunDistanceAU: 1.0, earthDistanceAU: 1.0)), 5.0, accuracy: 1e-12)
        // The MPC slope parameter k gives K1 = 2.5 k.
        let mpc = try XCTUnwrap(CometMagnitudes.fromMPC(absoluteMagnitude: 6.5, slopeParameter: 3.2))
        XCTAssertEqual(mpc.totalSlope, 8.0, accuracy: 1e-12)
        XCTAssertEqual(mpc.totalMagnitude, 6.5)
        XCTAssertNil(mpc.nuclearMagnitude)
        XCTAssertNil(mpc.nuclear(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: 0.0))
        // Invalid distances give nothing.
        XCTAssertNil(magnitudes.total(sunDistanceAU: 0.0, earthDistanceAU: 1.0))
        XCTAssertNil(magnitudes.total(sunDistanceAU: 1.0, earthDistanceAU: -1.0))
        XCTAssertNil(magnitudes.total(sunDistanceAU: Double.nan, earthDistanceAU: 1.0))
        XCTAssertNil(magnitudes.nuclear(sunDistanceAU: 1.0, earthDistanceAU: 0.0, phaseAngle: 0.0))
        let asteroid = try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 3.0, slopeParameter: 0.15))
        XCTAssertNil(asteroid.apparent(sunDistanceAU: 0.0, earthDistanceAU: 1.0, phaseAngle: 10.0))
        XCTAssertNil(asteroid.apparent(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: 180.0))
        XCTAssertNil(asteroid.apparent(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: -1.0))
        XCTAssertNil(asteroid.apparent(sunDistanceAU: 1.0, earthDistanceAU: 1.0, phaseAngle: Double.nan))
    }

    func testPhotometryValuesAreValidated() throws {
        XCTAssertNil(CometMagnitudes(totalMagnitude: -21.0, totalSlope: 10.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 41.0, totalSlope: 10.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: Double.nan, totalSlope: 10.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 61.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: -6.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0, nuclearMagnitude: 11.0, nuclearSlope: 70.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0, nuclearMagnitude: 45.0, nuclearSlope: 10.0))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0, nuclearMagnitude: 11.0, nuclearSlope: 10.0, nuclearPhaseCoefficient: 0.6))
        XCTAssertNil(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0, nuclearPhaseCoefficient: Double.nan))
        // Nuclear parameters are used only when both are given.
        let onlyMagnitude = try XCTUnwrap(CometMagnitudes(totalMagnitude: 5.0, totalSlope: 10.0, nuclearMagnitude: 11.0, nuclearSlope: nil, nuclearPhaseCoefficient: 0.03))
        XCTAssertNil(onlyMagnitude.nuclearMagnitude)
        XCTAssertNil(onlyMagnitude.nuclearSlope)
        XCTAssertEqual(onlyMagnitude.nuclearPhaseCoefficient, 0.0)
        XCTAssertNil(CometMagnitudes.fromMPC(absoluteMagnitude: 5.0, slopeParameter: Double.nan))
        XCTAssertNil(AsteroidMagnitudes(absoluteMagnitude: -6.0))
        XCTAssertNil(AsteroidMagnitudes(absoluteMagnitude: 41.0))
        XCTAssertNil(AsteroidMagnitudes(absoluteMagnitude: 10.0, slopeParameter: -0.3))
        XCTAssertNil(AsteroidMagnitudes(absoluteMagnitude: 10.0, slopeParameter: 1.1))
        XCTAssertNil(AsteroidMagnitudes(absoluteMagnitude: Double.nan))
        XCTAssertEqual(try XCTUnwrap(AsteroidMagnitudes(absoluteMagnitude: 10.0)).slopeParameter, 0.15)
        XCTAssertEqual(CometMagnitudes.defaultTotalSlope, 10.0)
        XCTAssertEqual(AsteroidMagnitudes.defaultSlopeParameter, 0.15)
    }

    func testTailPositionAngleAgreesWithHorizons() throws {
        // Horizons' PsAng is the position angle of the extended Sun -> target radius vector, north through east.
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let state = try state(small, item, row.offsetDays)
                let angle = try XCTUnwrap(state.tailPositionAngle)
                let difference = abs(AstroMath.normalizeSignedDegrees(angle - row.tailPositionAngle))
                XCTAssertTrue(difference < 0.02, "\(item.title) at \(row.offsetDays): \(angle) vs \(row.tailPositionAngle)")
            }
        }
    }

    func testTailPositionAngleGeometry() throws {
        // A comet due north of the Earth's line of sight with the Sun below it: the tail points north.
        let line = Vector3(1.0, 0.0, 0.0)
        XCTAssertEqual(try XCTUnwrap(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(1.0, 0.0, 1.0))), 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(1.0, 1.0, 0.0))), 90.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(1.0, 0.0, -1.0))), 180.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(1.0, -1.0, 0.0))), 270.0, accuracy: 1e-9)
        // Along the line of sight or at a celestial pole there is no direction.
        XCTAssertNil(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(5.0, 0.0, 0.0)))
        XCTAssertNil(SmallBodyEphemeris.antiSolarPositionAngle(toward: line, away: Vector3(-2.0, 0.0, 0.0)))
        XCTAssertNil(SmallBodyEphemeris.antiSolarPositionAngle(toward: Vector3(0.0, 0.0, 1.0), away: Vector3(1.0, 0.0, 1.0)))
    }

    // MARK: Topocentric

    private func caseKey(_ item: CometsHorizonsData.Case) -> String {
        if item.title.hasPrefix("C/2023 A3") { return "c2023a3" }
        if item.title.hasPrefix("12P") { return "p12" }
        if item.title.hasPrefix("1P") { return "halley1986" }
        if item.title.hasPrefix("(4)") { return "vesta" }
        return "ceres"
    }

    func testTopocentricPositionsAgreeWithHorizons() throws {
        // Sites: Los Angeles (C/2023 A3, 0.47 AU away), Sydney (Halley) and Mauna Kea (12P). Horizons' airless azimuth/elevation
        // use the observed UT1 and polar motion, which the kit neglects: allow 25 arcseconds.
        for row in CometsHorizonsData.topocentricRows {
            let item = try XCTUnwrap(CometsHorizonsData.cases.first { caseKey($0) == row.caseKey })
            let small = try body(item)
            let observer = Observer(location: GeographicLocation(latitude: row.latitude, longitude: row.longitude, elevation: row.elevationMeters))
            let frame = SkyFrame(julianDate: JulianDate(ut: row.julianDayUT), observer: observer)
            let equatorial = try XCTUnwrap(frame.topocentricEquatorial(of: small))
            let error = equatorial.angularSeparation(to: EquatorialCoordinate(rightAscension: row.raApparent, declination: row.decApparent)) * 3600
            XCTAssertTrue(error < 25.0, "\(item.title): apparent place off by \(error) arcsec")
            let horizontal = try XCTUnwrap(frame.horizontal(of: small, refraction: false))
            let reference = HorizontalCoordinate(azimuth: row.azimuth, altitude: row.elevation)
            let horizontalError = horizontal.angularSeparation(to: reference) * 3600
            XCTAssertTrue(horizontalError < 25.0, "\(item.title): azimuth/elevation off by \(horizontalError) arcsec")
        }
    }

    func testParallaxMattersForNearbyComets() throws {
        // C/2023 A3 at 0.47 AU: the topocentric place differs from the geocentric one by up to 18 arcseconds.
        let small = try body(CometsHorizonsData.c2023a3)
        let row = try XCTUnwrap(CometsHorizonsData.topocentricRows.first { $0.caseKey == "c2023a3" })
        let frame = SkyFrame(julianDate: JulianDate(ut: row.julianDayUT),
                             observer: Observer(location: GeographicLocation(latitude: row.latitude, longitude: row.longitude, elevation: row.elevationMeters)))
        let geocentric = try XCTUnwrap(frame.geocentricApparentEquatorial(of: small))
        let topocentric = try XCTUnwrap(frame.topocentricEquatorial(of: small))
        let shift = geocentric.angularSeparation(to: topocentric) * 3600
        XCTAssertTrue(shift > 5.0 && shift < 20.0, "parallax \(shift) arcsec")
    }

    func testSkyFrameExtensionsAgree() throws {
        let item = CometsHorizonsData.p12
        let small = try body(item)
        let julianDate = JulianDate(ut: item.epochTDB + 11)
        let frame = SkyFrame(julianDate: julianDate, observer: Observer(location: GeographicLocation(latitude: 48.0, longitude: 11.0, elevation: 500.0)))
        let state = try XCTUnwrap(frame.state(of: small))
        XCTAssertEqual(state.julianDate, julianDate)
        XCTAssertEqual(state, SmallBodyEphemeris.state(of: small, at: julianDate))
        XCTAssertEqual(state.geocentricJ2000, try XCTUnwrap(SmallBodyEphemeris.geocentricJ2000(of: small, at: julianDate)))
        XCTAssertEqual(frame.horizontal(of: small, refraction: true), frame.horizontal(geocentricJ2000: state.geocentricJ2000, refraction: true))
        XCTAssertEqual(frame.horizontal(of: small, refraction: false), frame.horizontal(geocentricJ2000: state.geocentricJ2000, refraction: false))
        XCTAssertEqual(frame.topocentricEquatorial(of: small), frame.topocentricEquatorial(geocentricJ2000: state.geocentricJ2000))
        XCTAssertEqual(frame.geocentricApparentEquatorial(of: small),
                       EquatorialCoordinate(vector: frame.precessionNutationMatrix * state.geocentricJ2000))
        // Refraction raises the altitude and leaves the azimuth.
        let airless = try XCTUnwrap(frame.horizontal(of: small, refraction: false))
        let refracted = try XCTUnwrap(frame.horizontal(of: small, refraction: true))
        XCTAssertEqual(refracted.azimuth, airless.azimuth, accuracy: 1e-9)
        XCTAssertTrue(refracted.altitude >= airless.altitude)
    }

    func testOutOfRangeDatesGiveNoState() throws {
        let hyperbolic = try body(CometsHorizonsData.c2023a3)
        let far = JulianDate(ut: CometsHorizonsData.c2023a3.perihelionTimeTDB + 60_000.0)
        XCTAssertNil(SmallBodyEphemeris.state(of: hyperbolic, at: far))
        XCTAssertNil(SmallBodyEphemeris.geocentricJ2000(of: hyperbolic, at: far))
        let observer = Observer(location: GeographicLocation(latitude: 0.0, longitude: 0.0, elevation: 0.0))
        let frame = SkyFrame(julianDate: far, observer: observer)
        XCTAssertNil(frame.state(of: hyperbolic))
        XCTAssertNil(frame.horizontal(of: hyperbolic))
        XCTAssertNil(frame.topocentricEquatorial(of: hyperbolic))
        XCTAssertNil(frame.geocentricApparentEquatorial(of: hyperbolic))
        let altitude = SmallBodyEphemeris.altitude(of: hyperbolic, observer: observer)
        XCTAssertTrue(altitude(far.date).isNaN)
    }

    // MARK: Elements of other origins

    func testStaleElementsDegradeGracefullyForCometsWithinMonths() throws {
        // The Small-Body Database elements of 12P are osculating at 2023 September 24; the table starts 179 days later.
        let pons = try SmallBodyJSONParser.parse(CometsTestData.jsonPonsBrooks)
        let item = CometsHorizonsData.p12
        var worst = 0.0
        for row in item.rows {
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: pons, at: JulianDate(ut: item.epochTDB + row.offsetDays)))
            worst = max(worst, arcseconds(state.astrometricJ2000, direction(row.raAstrometric, row.decAstrometric)))
        }
        XCTAssertTrue(worst < 36.0, "12P from elements 200 days old: \(worst) arcsec") // measured 27"
        XCTAssertTrue(worst > 5.0)
        // C/2023 A3: osculating at 2024 May 18, the table is 3 weeks to 5 months later.
        let atlas = try SmallBodyJSONParser.parse(CometsTestData.jsonTsuchinshanAtlas)
        var worstAtlas = 0.0
        for row in CometsHorizonsData.c2023a3.rows {
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: atlas, at: JulianDate(ut: CometsHorizonsData.c2023a3.epochTDB + row.offsetDays)))
            worstAtlas = max(worstAtlas, arcseconds(state.astrometricJ2000, direction(row.raAstrometric, row.decAstrometric)))
        }
        XCTAssertTrue(worstAtlas < 30.0, "C/2023 A3 from elements 4 months old: \(worstAtlas) arcsec") // measured 20"
    }

    func testStaleElementsOfDecadesAreUseless() throws {
        // The Small-Body Database elements of Halley are osculating at 1968; two-body motion to 1986 is hopeless.
        let halley = try SmallBodyJSONParser.parse(CometsTestData.jsonHalley)
        let item = CometsHorizonsData.halley1986
        for row in item.rows {
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: halley, at: JulianDate(ut: item.epochTDB + row.offsetDays)))
            let error = state.astrometricJ2000.angle(to: direction(row.raAstrometric, row.decAstrometric))
            XCTAssertTrue(error > 0.3 && error < 8.0, "Halley from 1968 elements at \(row.offsetDays) d: \(error) degrees")
        }
    }

    func testSmallBodyDatabaseAsteroidsAgreeWithHorizons() throws {
        for (json, item) in [(CometsTestData.jsonVesta, CometsHorizonsData.vesta), (CometsTestData.jsonCeres, CometsHorizonsData.ceres)] {
            let small = try SmallBodyJSONParser.parse(json)
            for row in item.rows {
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: item.epochTDB + row.offsetDays)))
                let error = arcseconds(state.astrometricJ2000, direction(row.raAstrometric, row.decAstrometric))
                XCTAssertTrue(error <= allowedArcseconds(row.offsetDays), "\(item.title) at \(row.offsetDays) d: \(error) arcsec")
                XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), row.magnitude, accuracy: 0.01)
            }
        }
    }

    func testMpcMinorPlanetLinesAgreeWithHorizons() throws {
        // The MPC elements are osculating at 2026 June 9, like JPL's. Horizons uses G = 0.32 for Vesta and the MPC G = 0.15, so
        // the magnitudes differ by 0.2.
        for (line, item) in [(CometsTestData.asteroidVesta, CometsHorizonsData.vesta), (CometsTestData.asteroidCeres, CometsHorizonsData.ceres)] {
            let small = try MinorPlanetElementsParser.parseLine(line)
            for row in item.rows {
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: item.epochTDB + row.offsetDays)))
                let error = arcseconds(state.astrometricJ2000, direction(row.raAstrometric, row.decAstrometric))
                XCTAssertTrue(error <= 8.0 + 0.1 * abs(row.offsetDays), "\(item.title) at \(row.offsetDays) d: \(error) arcsec")
            }
        }
        let vesta = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidVesta)
        let row = CometsHorizonsData.vesta.rows[2]
        let state = try XCTUnwrap(SmallBodyEphemeris.state(of: vesta, at: JulianDate(ut: CometsHorizonsData.vesta.epochTDB + row.offsetDays)))
        XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), row.magnitude, accuracy: 0.3)
    }

    func testMpcCometLinesAgreeWithHorizons() throws {
        // Elements osculating at 2026-10-17 from the MPC file against Horizons' own solutions on 2026-10-18 and 2026-11-17.
        let lines: [(String, [CometsTestData.MpcRow], Double)] = [
            (CometsTestData.cometHartleyIras, CometsTestData.horizonsHartleyIras, 5.0),
            (CometsTestData.cometGehrels, CometsTestData.horizonsGehrels, 5.0),
            (CometsTestData.cometSchwassmannWachmann, CometsTestData.horizonsSchwassmannWachmann, 5.0),
            (CometsTestData.cometBernardinelliBernstein, CometsTestData.horizonsBernardinelliBernstein, 5.0),
            (CometsTestData.cometLeonard, CometsTestData.horizonsLeonard, 5.0),
            (CometsTestData.cometWierzchos, CometsTestData.horizonsWierzchos, 60.0),
        ]
        for (line, rows, allowed) in lines {
            let small = try CometElementsParser.parseLine(line)
            for row in rows {
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: 2_461_331.5 + row.dayOffset)), small.title)
                let error = arcseconds(state.astrometricJ2000, direction(row.ra, row.dec))
                XCTAssertTrue(error <= allowed, "\(small.title) at \(row.dayOffset) d: \(error) arcsec")
                XCTAssertEqual(state.heliocentricDistanceAU, row.sunDistance, accuracy: 5e-4 * row.sunDistance, small.title)
                XCTAssertEqual(state.distanceAU, row.earthDistance, accuracy: 5e-4 * row.earthDistance, small.title)
                XCTAssertEqual(state.elongation, row.elongation, accuracy: 0.05, small.title)
                // The MPC magnitude parameters (visual estimates) differ from JPL's; check against the MPC formula instead.
                guard case .comet(let magnitudes)? = small.photometry else { return XCTFail("expected comet photometry") }
                let expected = magnitudes.totalMagnitude + 5 * log10(row.earthDistance) + magnitudes.totalSlope * log10(row.sunDistance)
                XCTAssertEqual(try XCTUnwrap(state.apparentMagnitude), expected, accuracy: 0.01, small.title)
            }
        }
    }

    func testMpcTailAnglesAgreeWithHorizons() throws {
        let small = try CometElementsParser.parseLine(CometsTestData.cometHartleyIras)
        for row in CometsTestData.horizonsHartleyIras {
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: 2_461_331.5 + row.dayOffset)))
            let difference = abs(AstroMath.normalizeSignedDegrees(try XCTUnwrap(state.tailPositionAngle) - row.tailPositionAngle))
            XCTAssertTrue(difference < 0.2, "\(small.title): \(difference) degrees")
        }
    }

    // MARK: Consistency

    func testGeocentricShortcutMatchesTheState() throws {
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let julianDate = JulianDate(ut: item.epochTDB + row.offsetDays)
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: julianDate))
                XCTAssertEqual(state.geocentricJ2000, try XCTUnwrap(SmallBodyEphemeris.geocentricJ2000(of: small, at: julianDate)))
            }
        }
    }

    func testElongationAndPhaseSatisfyTheTriangle() throws {
        // Sun, Earth and body form a triangle with sides R (Sun-Earth), r (Sun-body), delta (Earth-body):
        // with the law of sines r / sin(elongation) = R / sin(phase).
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                let julianDate = JulianDate(ut: item.epochTDB + row.offsetDays)
                let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: julianDate))
                let earth = Ephemeris.PlanetaryTheory.heliocentricJ2000(.earth, julianDayTT: julianDate.tt)
                let ratio = state.heliocentricDistanceAU / earth.length
                let sines = AstroMath.sinDeg(state.elongation) / AstroMath.sinDeg(state.phaseAngle)
                XCTAssertEqual(sines, ratio, accuracy: 2e-3 * ratio, "\(item.title) at \(row.offsetDays)")
                XCTAssertTrue(state.elongation >= 0 && state.elongation <= 180)
                XCTAssertTrue(state.phaseAngle >= 0 && state.phaseAngle <= 180)
            }
        }
    }

    func testPhotographableNeedsBrightnessAndElongation() throws {
        let item = CometsHorizonsData.c2023a3
        let atlas = try body(item)
        func stateAt(_ offset: Double) throws -> SmallBodyState { try state(atlas, item, offset) }
        // Oct 5 and Oct 12: magnitude 5.9 and 5.8 but only 15 and 12 degrees from the Sun.
        XCTAssertFalse(try stateAt(-7.0).isPhotographable())
        XCTAssertFalse(try stateAt(0.0).isPhotographable())
        XCTAssertTrue(try stateAt(0.0).isPhotographable(magnitudeLimit: 10.0, minimumElongation: 10.0))
        // Oct 20 (magnitude 6.9, 43 degrees) and Oct 27 (8.0, 54 degrees).
        XCTAssertTrue(try stateAt(8.0).isPhotographable())
        XCTAssertTrue(try stateAt(15.0).isPhotographable())
        XCTAssertFalse(try stateAt(15.0).isPhotographable(magnitudeLimit: 7.5))
        XCTAssertTrue(try stateAt(8.0).isPhotographable(magnitudeLimit: 7.5))
        XCTAssertFalse(try stateAt(8.0).isPhotographable(minimumElongation: 60.0))
        XCTAssertEqual(SmallBodyEphemeris.defaultMagnitudeLimit, 10.0)
        XCTAssertEqual(SmallBodyEphemeris.defaultMinimumElongation, 25.0)
        // A body without photometry is never photographable.
        let orbit = try XCTUnwrap(OrbitalElements(perihelionDistanceAU: 1.0, eccentricity: 0.5, inclination: 10.0,
                                                  argumentOfPerihelion: 20.0, longitudeOfAscendingNode: 30.0,
                                                  perihelionJulianDayTT: item.perihelionTimeTDB))
        let bare = try XCTUnwrap(SmallBody(designation: "X", kind: .comet, orbit: orbit))
        let bareState = try XCTUnwrap(SmallBodyEphemeris.state(of: bare, at: JulianDate(ut: item.epochTDB + 8)))
        XCTAssertNil(bareState.apparentMagnitude)
        XCTAssertNil(bareState.nuclearMagnitude)
        XCTAssertFalse(bareState.isPhotographable(magnitudeLimit: 99.0, minimumElongation: 0.0))
    }

    // MARK: Tail framing

    func testTailAngleFromVerticalMatchesAnIndependentConstruction() throws {
        // Move 0.02 degrees from the comet along the position angle of the tail and compare the displacement in the
        // horizontal frame: right = increasing azimuth, up = increasing altitude.
        let observers = [
            Observer(location: GeographicLocation(latitude: 34.0522, longitude: -118.2437, elevation: 90.0)),
            Observer(location: GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 50.0)),
            Observer(location: GeographicLocation(latitude: 64.0, longitude: 20.0, elevation: 10.0)),
        ]
        var checked = 0
        for item in CometsHorizonsData.cases {
            let small = try body(item)
            for row in item.rows {
                for observer in observers {
                    for hours in [0.0, 0.25, 0.5, 0.75] {
                        let julianDate = JulianDate(ut: item.epochTDB + row.offsetDays + hours)
                        let frame = SkyFrame(julianDate: julianDate, observer: observer)
                        let state = try XCTUnwrap(frame.state(of: small))
                        guard let angle = SmallBodyEphemeris.tailAngleFromVertical(of: state, in: frame) else { continue }
                        let position = EquatorialCoordinate(vector: state.astrometricJ2000)
                        let tail = try XCTUnwrap(state.tailPositionAngle)
                        let step = 0.02
                        let moved = EquatorialCoordinate(
                            rightAscension: position.rightAscension + step * AstroMath.sinDeg(tail) / AstroMath.cosDeg(position.declination),
                            declination: position.declination + step * AstroMath.cosDeg(tail))
                        let here = frame.horizontal(j2000: position, refraction: false)
                        let there = frame.horizontal(j2000: moved, refraction: false)
                        if here.altitude > 85.0 { continue }
                        let towardsRight = AstroMath.normalizeSignedDegrees(there.azimuth - here.azimuth) * AstroMath.cosDeg(here.altitude)
                        let towardsUp = there.altitude - here.altitude
                        let expected = AstroMath.atan2Deg(towardsRight, towardsUp)
                        XCTAssertEqual(abs(AstroMath.normalizeSignedDegrees(angle - expected)), 0.0, accuracy: 0.35, "\(item.title) \(row.offsetDays) d")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertTrue(checked > 100, "only \(checked) cases were checked")
    }

    /// A synthetic state 1e6 AU away in the horizontal direction `h` (ENU), whose tail points along `tail` (ENU) for `frame`.
    private func syntheticState(_ frame: SkyFrame, _ h: Vector3, _ tail: Vector3) throws -> SmallBodyState {
        let toJ2000 = frame.j2000ToHorizontal.transposed
        let orbit = try XCTUnwrap(OrbitalElements(perihelionDistanceAU: 1.0, eccentricity: 0.5, inclination: 10.0,
                                                  argumentOfPerihelion: 20.0, longitudeOfAscendingNode: 30.0,
                                                  perihelionJulianDayTT: 2_460_000.0))
        let body = try XCTUnwrap(SmallBody(designation: "S", kind: .comet, orbit: orbit))
        let apparent = toJ2000 * h.normalized * 1e6
        return SmallBodyState(body: body, julianDate: frame.julianDate, astrometric: apparent, apparent: apparent,
                              heliocentric: toJ2000 * tail.normalized * 3.0, elongation: 90.0, phaseAngle: 30.0,
                              apparentMagnitude: 5.0, nuclearMagnitude: nil, tailPositionAngle: nil)
    }

    func testTailAngleFromVerticalForConstructedGeometry() throws {
        // A body 30 degrees up in the south; "up" along the sky is the direction towards the zenith.
        let frame = SkyFrame(julianDate: JulianDate(ut: 2_461_000.5), observer: Observer(location: GeographicLocation(latitude: 40.0, longitude: -100.0, elevation: 0.0)))
        let h = Vector3(0.0, -cos(30.0 * Double.pi / 180), sin(30.0 * Double.pi / 180))
        let up = Vector3(0.0, 0.5, 3.0.squareRoot() / 2)
        let right = Vector3(-1.0, 0.0, 0.0) // facing south, the right hand is west
        func angle(_ tail: Vector3) throws -> Double {
            try XCTUnwrap(SmallBodyEphemeris.tailAngleFromVertical(of: try syntheticState(frame, h, tail), in: frame))
        }
        XCTAssertEqual(try angle(h + up * 0.2), 0.0, accuracy: 1e-5)
        XCTAssertEqual(try angle(h + right * 0.2), 90.0, accuracy: 1e-5)
        XCTAssertEqual(abs(try angle(h - up * 0.2)), 180.0, accuracy: 1e-5)
        XCTAssertEqual(try angle(h - right * 0.2), -90.0, accuracy: 1e-5)
        XCTAssertEqual(try angle(h + up * 0.2 + right * 0.2), 45.0, accuracy: 1e-5)
        XCTAssertEqual(try angle(h - up * 0.2 - right * 0.2), -135.0, accuracy: 1e-5)
        // The tail along the line of sight has no direction on the sky.
        XCTAssertNil(SmallBodyEphemeris.tailAngleFromVertical(of: try syntheticState(frame, h, h), in: frame))
        XCTAssertNil(SmallBodyEphemeris.tailAngleFromVertical(of: try syntheticState(frame, h, h * -1.0), in: frame))
        // At the zenith "up" is undefined.
        XCTAssertNil(SmallBodyEphemeris.tailAngleFromVertical(of: try syntheticState(frame, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 1.0)), in: frame))
    }

    // MARK: Rise, transit and set

    func testRiseTransitSetOfAnAsteroidAgreesWithAFixedPosition() throws {
        // Vesta moves 0.25 degrees per day: its rise, transit and set differ from those of a fixed point at its position at
        // noon by about a minute.
        let item = CometsHorizonsData.vesta
        let small = try body(item)
        let observer = Observer(location: GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 1600.0))
        let start = JulianDate(ut: item.epochTDB + 120).date // 2026-10-07 UT
        let interval = DateInterval(start: start, duration: 86_400.0)
        let result = SmallBodyEphemeris.riseTransitSet(of: small, observer: observer, within: interval)
        XCTAssertEqual(result.circumstance, .normal)
        let middle = JulianDate(date: start.addingTimeInterval(43_200.0))
        let place = EquatorialCoordinate(vector: try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: middle)).astrometricJ2000)
        let fixed = RiseSetCalculator.riseTransitSet(forJ2000: place, properMotion: nil, observer: observer, within: interval)
        XCTAssertEqual(try XCTUnwrap(result.rise).timeIntervalSince1970, try XCTUnwrap(fixed.rise).timeIntervalSince1970, accuracy: 240.0)
        XCTAssertEqual(try XCTUnwrap(result.set).timeIntervalSince1970, try XCTUnwrap(fixed.set).timeIntervalSince1970, accuracy: 240.0)
        XCTAssertEqual(try XCTUnwrap(result.transit).timeIntervalSince1970, try XCTUnwrap(fixed.transit).timeIntervalSince1970, accuracy: 240.0)
        XCTAssertEqual(try XCTUnwrap(result.transitAltitude), try XCTUnwrap(fixed.transitAltitude), accuracy: 0.5)
    }

    func testRiseTransitSetEventsAreConsistentWithTheAltitude() throws {
        let item = CometsHorizonsData.halley1986
        let small = try body(item)
        let observer = Observer(location: GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 50.0))
        let start = JulianDate(ut: item.epochTDB + 60).date
        let interval = DateInterval(start: start, duration: 86_400.0)
        let altitude = SmallBodyEphemeris.altitude(of: small, observer: observer)
        let result = SmallBodyEphemeris.riseTransitSet(of: small, observer: observer, within: interval)
        let rise = try XCTUnwrap(result.rise)
        let set = try XCTUnwrap(result.set)
        let transit = try XCTUnwrap(result.transit)
        XCTAssertEqual(altitude(rise), RiseSetCalculator.standardHorizonAltitude, accuracy: 0.01)
        XCTAssertEqual(altitude(set), RiseSetCalculator.standardHorizonAltitude, accuracy: 0.01)
        XCTAssertTrue(altitude(rise.addingTimeInterval(120.0)) > altitude(rise.addingTimeInterval(-120.0)))
        XCTAssertTrue(altitude(set.addingTimeInterval(120.0)) < altitude(set.addingTimeInterval(-120.0)))
        XCTAssertTrue(altitude(transit) >= altitude(transit.addingTimeInterval(600.0)))
        XCTAssertTrue(altitude(transit) >= altitude(transit.addingTimeInterval(-600.0)))
        XCTAssertEqual(altitude(transit), try XCTUnwrap(result.transitAltitude), accuracy: 0.05)
        let crossings = SmallBodyEphemeris.crossings(of: small, observer: observer, within: interval)
        XCTAssertEqual(Set(crossings.map(\.kind)), [.rising, .setting])
        XCTAssertEqual(rise, crossings.first { $0.kind == .rising }?.time)
        let culminations = SmallBodyEphemeris.upperCulminations(of: small, observer: observer, within: interval)
        XCTAssertEqual(transit, culminations.first?.time)
    }

    func testRiseTransitSetOfACometThatNeverRises() throws {
        // Halley in April 1986 from Alaska: dec -47 never rises above the horizon at latitude 70 N.
        let item = CometsHorizonsData.halley1986
        let small = try body(item)
        let observer = Observer(location: GeographicLocation(latitude: 70.0, longitude: -150.0, elevation: 0.0))
        let interval = DateInterval(start: JulianDate(ut: item.epochTDB + 60).date, duration: 86_400.0)
        let result = SmallBodyEphemeris.riseTransitSet(of: small, observer: observer, within: interval)
        XCTAssertEqual(result.circumstance, .alwaysDown)
        XCTAssertNil(result.rise)
        XCTAssertNil(result.set)
    }

    func testAltitudeFunctionAllocatesNoStateAcrossCalls() throws {
        let item = CometsHorizonsData.vesta
        let small = try body(item)
        let observer = Observer(location: GeographicLocation(latitude: 10.0, longitude: 20.0, elevation: 0.0))
        let altitude = SmallBodyEphemeris.altitude(of: small, observer: observer)
        let instant = JulianDate(ut: item.epochTDB + 3).date
        XCTAssertEqual(altitude(instant), altitude(instant))
        let frame = SkyFrame(date: instant, observer: observer)
        XCTAssertEqual(try XCTUnwrap(frame.horizontal(of: small, refraction: false)).altitude, altitude(instant), accuracy: 1e-12)
    }

    // MARK: Cost

    func testStateIsCheap() throws {
        let small = try body(CometsHorizonsData.p12)
        let started = Date()
        var checksum = 0.0
        for index in 0..<20_000 {
            let state = try XCTUnwrap(SmallBodyEphemeris.state(of: small, at: JulianDate(ut: 2_460_400.0 + Double(index) * 0.01)))
            checksum += state.distanceAU
        }
        let seconds = Date().timeIntervalSince(started)
        XCTAssertTrue(checksum > 0)
        XCTAssertTrue(seconds < 5.0, "20 000 states took \(seconds) s")
        XCTAssertNotNil(SmallBodyEphemeris.state(of: small, at: JulianDate(date: Date(timeIntervalSince1970: 1_713_657_600))))
    }
}

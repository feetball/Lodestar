import XCTest
@testable import LodestarKit

/// Tests of the mount geometry (`SkyWatcherPointingModel`) and of the sky conversions. The geometry is checked against the
/// foundation's hour angle / horizontal transforms (home position: counterweight down and telescope at the pole; level and north) and
/// against hand-derived axis angles.
final class SkyWatcherModelTests: XCTestCase {
    private func assertVector(_ expected: Vector3, _ actual: Vector3, accuracy: Double = 1e-9, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) x \(actual)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) y \(actual)", file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, "\(message) z \(actual)", file: file, line: line)
    }

    private let north = SkyWatcherPointingModel.nominal(mode: .equatorial, isSouthernHemisphere: false)
    private let south = SkyWatcherPointingModel.nominal(mode: .equatorial, isSouthernHemisphere: true)
    private let altAz = SkyWatcherPointingModel.nominal(mode: .altAzimuth, isSouthernHemisphere: false)

    // MARK: Equatorial geometry

    func testEquatorialNamedPositions() {
        // Home: counterweight down, telescope at the pole.
        assertVector(Vector3(0.0, 0.0, 1.0), north.direction(axis1Degrees: 0.0, axis2Degrees: 0.0))
        // Declination axis turned 90°: the telescope swings out to the horizon, west for a positive angle (the T position).
        assertVector(Vector3(0.0, -1.0, 0.0), north.direction(axis1Degrees: 0.0, axis2Degrees: 90.0))
        assertVector(Vector3(0.0, 1.0, 0.0), north.direction(axis1Degrees: 0.0, axis2Degrees: -90.0))
        // Right ascension axis turned a quarter: the telescope on the meridian at the equator (counterweight horizontal).
        assertVector(Vector3(1.0, 0.0, 0.0), north.direction(axis1Degrees: -90.0, axis2Degrees: 90.0))
        assertVector(Vector3(1.0, 0.0, 0.0), north.direction(axis1Degrees: 90.0, axis2Degrees: -90.0))
        assertVector(Vector3(-1.0, 0.0, 0.0), north.direction(axis1Degrees: 90.0, axis2Degrees: 90.0))
        // Declination axis turned half way round: towards the opposite pole.
        assertVector(Vector3(0.0, 0.0, -1.0), north.direction(axis1Degrees: 33.0, axis2Degrees: 180.0))
        assertVector(Vector3(0.0, 0.0, -1.0), north.direction(axis1Degrees: -33.0, axis2Degrees: -180.0))
    }

    func testEquatorialAnglesMatchHourAngleAndDeclination() {
        // Pier side east (declination axis angle 0° to 180°): hour angle = axis1 + 90°, declination = 90° - axis2.
        for axis1 in [-85.0, -30.0, 0.0, 45.0, 80.0] {
            for axis2 in [10.0, 60.0, 90.0, 150.0] {
                let expected = CoordinateTransforms.localEquatorialVector(hourAngle: axis1 + 90.0, declination: 90.0 - axis2)
                assertVector(expected, north.direction(axis1Degrees: axis1, axis2Degrees: axis2), "east \(axis1) \(axis2)")
            }
        }
        // Pier side west (angle -180° to 0°): hour angle = axis1 - 90°, declination = 90° + axis2.
        for axis1 in [-80.0, -45.0, 0.0, 30.0, 85.0] {
            for axis2 in [-10.0, -60.0, -90.0, -150.0] {
                let expected = CoordinateTransforms.localEquatorialVector(hourAngle: axis1 - 90.0, declination: 90.0 + axis2)
                assertVector(expected, north.direction(axis1Degrees: axis1, axis2Degrees: axis2), "west \(axis1) \(axis2)")
            }
        }
    }

    func testEquatorialCounterweightIsDownBetweenTheMeridianLimits() throws {
        // For a target west of the meridian the east side keeps the counterweight down (|axis1| < 90°); east of the meridian the west side.
        let west = CoordinateTransforms.localEquatorialVector(hourAngle: 60.0, declination: 20.0)
        let byWest = north.solutions(west)
        let normal = try XCTUnwrap(byWest.first { $0.pierSide == .east })
        let through = try XCTUnwrap(byWest.first { $0.pierSide == .west })
        XCTAssertEqual(normal.axis1, -30.0, accuracy: 1e-9)
        XCTAssertEqual(normal.axis2, 70.0, accuracy: 1e-9)
        XCTAssertEqual(through.axis1, 150.0, accuracy: 1e-9)
        XCTAssertEqual(through.axis2, -70.0, accuracy: 1e-9)
        let east = CoordinateTransforms.localEquatorialVector(hourAngle: -60.0, declination: 20.0)
        let byEast = north.solutions(east)
        let eastNormal = try XCTUnwrap(byEast.first { $0.pierSide == .east })
        let eastThrough = try XCTUnwrap(byEast.first { $0.pierSide == .west })
        XCTAssertEqual(eastNormal.axis1, -150.0, accuracy: 1e-9)
        XCTAssertEqual(eastNormal.axis2, 70.0, accuracy: 1e-9)
        XCTAssertEqual(eastThrough.axis1, 30.0, accuracy: 1e-9)
        XCTAssertEqual(eastThrough.axis2, -70.0, accuracy: 1e-9)
        // The counterweight hangs below the horizontal exactly when the angle of axis 1 is within 90° of home.
        XCTAssertTrue(abs(normal.axis1) < 90 && abs(through.axis1) > 90)
        XCTAssertTrue(abs(eastThrough.axis1) < 90 && abs(eastNormal.axis1) > 90)
    }

    func testSouthernHemisphereIsTheMirrorImage() throws {
        // Home in the south: the telescope points at the south celestial pole.
        assertVector(Vector3(0.0, 0.0, -1.0), south.direction(axis1Degrees: 0.0, axis2Degrees: 0.0))
        for axis1 in [-70.0, 0.0, 55.0] {
            for axis2 in [-120.0, -30.0, 20.0, 100.0] {
                let mirrored = north.direction(axis1Degrees: axis1, axis2Degrees: axis2)
                assertVector(Vector3(mirrored.x, -mirrored.y, -mirrored.z), south.direction(axis1Degrees: axis1, axis2Degrees: axis2), "\(axis1) \(axis2)")
            }
        }
        // The counterweight rule is the same: a target at hour angle +60° and declination -20° needs the normal side.
        let target = CoordinateTransforms.localEquatorialVector(hourAngle: 60.0, declination: -20.0)
        let solutions = south.solutions(target)
        for solution in solutions { assertVector(target, south.direction(axis1Degrees: solution.axis1, axis2Degrees: solution.axis2), "south") }
        // In the mirrored mount the hour angle of the sky runs the other way: hour angle +60° looks like -60° (declination +20°).
        let normal = try XCTUnwrap(solutions.first { $0.pierSide == .east })
        let expected = try XCTUnwrap(north.solutions(CoordinateTransforms.localEquatorialVector(hourAngle: -60.0, declination: 20.0)).first { $0.pierSide == .east })
        XCTAssertEqual(normal.axis1, expected.axis1, accuracy: 1e-9)
        XCTAssertEqual(normal.axis2, expected.axis2, accuracy: 1e-9)
    }

    // MARK: Alt-azimuth geometry

    func testAltAzimuthNamedPositions() {
        assertVector(Vector3(0.0, 1.0, 0.0), altAz.direction(axis1Degrees: 0.0, axis2Degrees: 0.0))
        assertVector(Vector3(1.0, 0.0, 0.0), altAz.direction(axis1Degrees: 90.0, axis2Degrees: 0.0))
        assertVector(Vector3(0.0, -1.0, 0.0), altAz.direction(axis1Degrees: 180.0, axis2Degrees: 0.0))
        assertVector(Vector3(-1.0, 0.0, 0.0), altAz.direction(axis1Degrees: -90.0, axis2Degrees: 0.0))
        assertVector(Vector3(0.0, 0.0, 1.0), altAz.direction(axis1Degrees: 123.0, axis2Degrees: 90.0))
        for azimuth in [0.0, 33.0, 120.0, 200.0, 359.0] {
            for altitude in [-10.0, 0.0, 25.0, 60.0, 89.0] {
                assertVector(HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector,
                             altAz.direction(axis1Degrees: azimuth, axis2Degrees: altitude), "\(azimuth) \(altitude)")
            }
        }
    }

    func testAltAzimuthSolutionsAreNormalAndOverTheTop() throws {
        let target = HorizontalCoordinate(azimuth: 120.0, altitude: 30.0).unitVector
        let solutions = altAz.solutions(target)
        let normal = try XCTUnwrap(solutions.first { $0.pierSide == .east })
        let over = try XCTUnwrap(solutions.first { $0.pierSide == .west })
        XCTAssertEqual(normal.axis1, 120.0, accuracy: 1e-9)
        XCTAssertEqual(normal.axis2, 30.0, accuracy: 1e-9)
        XCTAssertEqual(over.axis1, -60.0, accuracy: 1e-9)
        XCTAssertEqual(over.axis2, 150.0, accuracy: 1e-9)
    }

    // MARK: Errors

    func testErrorsAreAppliedAsDocumented() throws {
        // An index error shifts the encoder angles.
        let shifted = SkyWatcherPointingModel(mode: .altAzimuth, isSouthernHemisphere: false,
                                              errors: SkyWatcherPointingErrors(axis1Index: 3.0, axis2Index: -2.0))
        assertVector(altAz.direction(axis1Degrees: 33.0, axis2Degrees: 28.0), shifted.direction(axis1Degrees: 30.0, axis2Degrees: 30.0))
        // The solutions undo it.
        let target = HorizontalCoordinate(azimuth: 120.0, altitude: 30.0).unitVector
        let solution = try XCTUnwrap(shifted.solutions(target).first { $0.pierSide == .east })
        XCTAssertEqual(solution.axis1, 117.0, accuracy: 1e-9)
        XCTAssertEqual(solution.axis2, 32.0, accuracy: 1e-9)
        // Cone error: the optical axis leaves the plane perpendicular to the altitude axis.
        let cone = SkyWatcherPointingModel(mode: .altAzimuth, isSouthernHemisphere: false, errors: SkyWatcherPointingErrors(cone: 0.5))
        assertVector(Vector3(AstroMath.sinDeg(0.5), AstroMath.cosDeg(0.5), 0.0), cone.direction(axis1Degrees: 0.0, axis2Degrees: 0.0))
        // Orthogonality error: the altitude axis is not horizontal, so pointing at the zenith side tilts towards x.
        let skew = SkyWatcherPointingModel(mode: .altAzimuth, isSouthernHemisphere: false, errors: SkyWatcherPointingErrors(orthogonality: 0.5))
        assertVector(Vector3(AstroMath.sinDeg(0.5), 0.0, AstroMath.cosDeg(0.5)), skew.direction(axis1Degrees: 0.0, axis2Degrees: 90.0))
        // Base tilt about y raises the east side: pointing east now has an altitude.
        let tilted = SkyWatcherPointingModel(mode: .altAzimuth, isSouthernHemisphere: false, errors: SkyWatcherPointingErrors(baseTiltY: 1.0))
        XCTAssertEqual(AstroMath.asinDeg(tilted.direction(axis1Degrees: 90.0, axis2Degrees: 0.0).z), -1.0, accuracy: 1e-9)
        XCTAssertEqual(AstroMath.asinDeg(tilted.direction(axis1Degrees: 0.0, axis2Degrees: 0.0).z), 0.0, accuracy: 1e-9)
        // Base tilt about x lifts the north side.
        let lifted = SkyWatcherPointingModel(mode: .altAzimuth, isSouthernHemisphere: false, errors: SkyWatcherPointingErrors(baseTiltX: 1.0))
        XCTAssertEqual(AstroMath.asinDeg(lifted.direction(axis1Degrees: 0.0, axis2Degrees: 0.0).z), 1.0, accuracy: 1e-9)
        XCTAssertEqual(AstroMath.asinDeg(lifted.direction(axis1Degrees: 90.0, axis2Degrees: 0.0).z), 0.0, accuracy: 1e-9)
    }

    func testPolarAxisErrorsOfAnEquatorialMount() {
        let latitude = 40.0
        let sinLatitude = AstroMath.sinDeg(latitude)
        let cosLatitude = AstroMath.cosDeg(latitude)
        // The polar axis is the direction the telescope points at when axis 2 is 0 (whatever axis 1 says).
        func poleAltitude(_ errors: SkyWatcherPointingErrors) -> Double {
            let axis = SkyWatcherPointingModel(mode: .equatorial, isSouthernHemisphere: false, errors: errors)
                .direction(axis1Degrees: 37.0, axis2Degrees: 0.0)
            return AstroMath.asinDeg(axis.x * cosLatitude + axis.z * sinLatitude)
        }
        func poleAzimuth(_ errors: SkyWatcherPointingErrors) -> Double {
            let axis = SkyWatcherPointingModel(mode: .equatorial, isSouthernHemisphere: false, errors: errors)
                .direction(axis1Degrees: 37.0, axis2Degrees: 0.0)
            let northComponent = -axis.x * sinLatitude + axis.z * cosLatitude
            return AstroMath.atan2Deg(axis.y, northComponent)
        }
        let high = SkyWatcherPointingErrors(baseTiltY: 0.5)
        XCTAssertEqual(poleAltitude(high), latitude + 0.5, accuracy: 1e-3)
        XCTAssertEqual(high.polarAxisAltitudeError, 0.5, accuracy: 0.0)
        let west = SkyWatcherPointingErrors(baseTiltX: 0.4)
        XCTAssertEqual(poleAzimuth(west), -0.4 / AstroMath.cosDeg(latitude), accuracy: 2e-3)
        XCTAssertEqual(west.polarAxisAzimuthError(latitude: latitude), -0.4 / AstroMath.cosDeg(latitude), accuracy: 1e-12)
        XCTAssertEqual(west.polarAxisAzimuthError(latitude: 90.0), 0.0, accuracy: 0.0)
        XCTAssertEqual(poleAltitude(SkyWatcherPointingErrors()), latitude, accuracy: 1e-9)
    }

    func testSolutionsRoundTripWithRandomErrors() {
        let random = SkyWatcherSimulatedRandom(seed: 2026)
        for index in 0 ..< 600 {
            let mode: SkyWatcherMountMode = index % 2 == 0 ? .equatorial : .altAzimuth
            let southern = (index / 2) % 2 == 1
            let errors = SkyWatcherPointingErrors(
                axis1Index: (random.next() - 0.5) * 20, axis2Index: (random.next() - 0.5) * 20, baseTiltX: (random.next() - 0.5) * 4,
                baseTiltY: (random.next() - 0.5) * 4, orthogonality: (random.next() - 0.5) * 2, cone: (random.next() - 0.5) * 2)
            let model = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: southern, errors: errors)
            let longitude = random.next() * 360
            let latitude = AstroMath.asinDeg(random.next() * 2 - 1)
            let target = EquatorialCoordinate(rightAscension: longitude, declination: latitude).unitVector
            let solutions = model.solutions(target, preferredAxis1Degrees: 0.0)
            XCTAssertEqual(solutions.count, 2)
            for solution in solutions {
                let pointed = model.direction(axis1Degrees: solution.axis1, axis2Degrees: solution.axis2)
                XCTAssertTrue(pointed.angle(to: target) < 1e-7, "\(index) \(mode) \(southern) \(pointed.angle(to: target))")
                XCTAssertTrue(abs(solution.axis1) <= 180.0 && abs(solution.axis2) <= 180.0)
            }
        }
    }

    func testPolesOfThePrimaryAxis() throws {
        // At the pole axis 1 is undefined: both solutions use the preferred angle.
        let solutions = north.solutions(Vector3(0.0, 0.0, 1.0), preferredAxis1Degrees: 25.0)
        for solution in solutions {
            XCTAssertEqual(solution.axis1, 25.0, accuracy: 1e-6)
            XCTAssertEqual(solution.axis2, 0.0, accuracy: 1e-6)
        }
        let zenith = altAz.solutions(Vector3(0.0, 0.0, 1.0), preferredAxis1Degrees: -40.0)
        let normal = try XCTUnwrap(zenith.first { $0.pierSide == .east })
        XCTAssertEqual(normal.axis1, -40.0, accuracy: 1e-6)
        XCTAssertEqual(normal.axis2, 90.0, accuracy: 1e-6)
    }

    func testPierSideFollowsTheModelAngle() {
        XCTAssertEqual(north.pierSide(axis2Degrees: 3.0), .east)
        XCTAssertEqual(north.pierSide(axis2Degrees: 0.0), .east)
        XCTAssertEqual(north.pierSide(axis2Degrees: -0.001), .west)
        let shifted = SkyWatcherPointingModel(mode: .equatorial, isSouthernHemisphere: false,
                                              errors: SkyWatcherPointingErrors(axis1Index: 4.0, axis2Index: -5.0))
        XCTAssertEqual(shifted.pierSide(axis2Degrees: 3.0), .west)
        XCTAssertEqual(shifted.pierSide(axis2Degrees: 6.0), .east)
        XCTAssertEqual(shifted.modelAxis1(90.0), 94.0, accuracy: 1e-12)
        XCTAssertEqual(shifted.modelAxis1(180.0), -176.0, accuracy: 1e-12)
        XCTAssertEqual(altAz.pierSide(axis2Degrees: 89.0), .east)
        XCTAssertEqual(altAz.pierSide(axis2Degrees: 91.0), .west)
        XCTAssertEqual(altAz.pierSide(axis2Degrees: -120.0), .west)
    }

    // MARK: Sky conversions

    func testSkyConversionsFollowTheHourAngle() {
        let sidereal = 123.0
        // On the meridian: hour angle 0.
        assertVector(Vector3(AstroMath.cosDeg(30.0), 0.0, AstroMath.sinDeg(30.0)),
                     SkyWatcherSky.localDirection(EquatorialCoordinate(rightAscension: sidereal, declination: 30.0), localSiderealTime: sidereal,
                                                  latitude: 40.0, mode: .equatorial))
        // West of the meridian (hour angle +90°, right ascension 90° less than the sidereal time): y = -1.
        assertVector(Vector3(0.0, -1.0, 0.0),
                     SkyWatcherSky.localDirection(EquatorialCoordinate(rightAscension: sidereal - 90.0, declination: 0.0), localSiderealTime: sidereal,
                                                  latitude: 40.0, mode: .equatorial))
        // The same place in the horizon frame.
        let place = EquatorialCoordinate(rightAscension: 200.0, declination: 25.0)
        let expected = CoordinateTransforms.equatorialToHorizontal(hourAngle: AstroMath.normalizeSignedDegrees(sidereal - 200.0), declination: 25.0, latitude: 40.0)
        assertVector(expected.unitVector, SkyWatcherSky.localDirection(place, localSiderealTime: sidereal, latitude: 40.0, mode: .altAzimuth))
        XCTAssertEqual(SkyWatcherSky.altitude(place, localSiderealTime: sidereal, latitude: 40.0), expected.altitude, accuracy: 1e-12)
        XCTAssertEqual(SkyWatcherSky.siderealDegreesPerSecond, 0.0041780746, accuracy: 1e-9)
    }

    func testSkyConversionsRoundTrip() {
        let random = SkyWatcherSimulatedRandom(seed: 7)
        for index in 0 ..< 400 {
            let mode: SkyWatcherMountMode = index % 2 == 0 ? .equatorial : .altAzimuth
            let latitude = (random.next() - 0.5) * 170
            let sidereal = random.next() * 360
            let place = EquatorialCoordinate(rightAscension: random.next() * 360, declination: AstroMath.asinDeg(random.next() * 1.96 - 0.98))
            let direction = SkyWatcherSky.localDirection(place, localSiderealTime: sidereal, latitude: latitude, mode: mode)
            XCTAssertEqual(direction.length, 1.0, accuracy: 1e-12)
            let back = SkyWatcherSky.apparentPlace(direction, localSiderealTime: sidereal, latitude: latitude, mode: mode)
            XCTAssertTrue(back.angularSeparation(to: place) < 1e-9, "\(index) \(back.angularSeparation(to: place))")
        }
    }

    // MARK: Alignment

    private struct Star {
        let first: Double
        let second: Double
    }

    private func directionOf(_ star: Star, _ mode: SkyWatcherMountMode) -> Vector3 {
        if mode == .equatorial { return CoordinateTransforms.localEquatorialVector(hourAngle: star.first, declination: star.second) }
        return HorizontalCoordinate(azimuth: star.first, altitude: star.second).unitVector
    }

    /// What the encoders read when the real mount (the model `truth`) points at `direction`, on the side that keeps the counterweight down.
    private func observe(_ truth: SkyWatcherPointingModel, _ direction: Vector3) -> SkyWatcherAlignmentPoint {
        let solutions = truth.solutions(direction, preferredAxis1Degrees: 0.0)
        let usable: SkyWatcherAxisSolution?
        if truth.mode == .equatorial {
            usable = solutions.filter { abs(truth.modelAxis1($0.axis1)) <= 95.0 }.min { abs(truth.modelAxis1($0.axis1)) < abs(truth.modelAxis1($1.axis1)) }
        } else {
            usable = solutions.first { $0.pierSide == .east }
        }
        let solution = usable ?? solutions[0]
        return SkyWatcherAlignmentPoint(axis1Degrees: solution.axis1, axis2Degrees: solution.axis2, direction: direction,
                                        timestamp: SkyWatcherTestSupport.start)
    }

    private let equatorialStars = [Star(first: 60.0, second: 40.0), Star(first: -70.0, second: 50.0), Star(first: 15.0, second: 10.0),
                                   Star(first: -20.0, second: -10.0), Star(first: -100.0, second: 20.0)]
    private let altAzimuthStars = [Star(first: 290.0, second: 43.0), Star(first: 54.0, second: 41.0), Star(first: 208.0, second: 57.0),
                                   Star(first: 120.0, second: 30.0), Star(first: 10.0, second: 65.0)]

    private func stars(_ mode: SkyWatcherMountMode) -> [Star] { mode == .equatorial ? equatorialStars : altAzimuthStars }

    func testPredictedErrorShrinksWithMoreStars() throws {
        for mode in SkyWatcherMountMode.allCases {
            let errors = mode == .equatorial ? SkyWatcherTestSupport.equatorialErrors : SkyWatcherTestSupport.altAzimuthErrors
            let truth = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: false, errors: errors)
            var predicted: [Double] = []
            for count in 1 ... 4 {
                let points = stars(mode).prefix(count).map { observe(truth, directionOf($0, mode)) }
                predicted.append(try SkyWatcherAlignmentSolver.solve(Array(points), mode: mode, isSouthernHemisphere: false).predictedErrorDegrees)
            }
            // One star leaves about a degree (the priors), more stars bring it down.
            XCTAssertTrue(predicted[0] > 0.3 && predicted[0] < 3.0, "\(mode) \(predicted)")
            XCTAssertTrue(predicted[1] < predicted[0], "\(mode) \(predicted)")
            XCTAssertTrue(predicted[2] < predicted[1], "\(mode) \(predicted)")
            XCTAssertTrue(predicted[3] < predicted[2], "\(mode) \(predicted)")
            XCTAssertTrue(predicted[3] < 0.3, "\(mode) \(predicted)")
        }
        XCTAssertEqual(SkyWatcherAlignmentSolver.maximumPoints, 8)
        XCTAssertEqual(SkyWatcherAlignmentPriors.standard.measurementSigmaDegrees, 0.1, accuracy: 0.0)
    }

    func testOneStarFindsTheIndexOffsetsExactly() throws {
        for mode in SkyWatcherMountMode.allCases {
            for southern in [false, true] {
                if mode == .altAzimuth && southern { continue }
                let truth = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: southern,
                                                    errors: SkyWatcherPointingErrors(axis1Index: 3.7, axis2Index: -2.4))
                for star in stars(mode) {
                    let point = observe(truth, directionOf(star, mode))
                    let fit = try SkyWatcherAlignmentSolver.solve([point], mode: mode, isSouthernHemisphere: southern)
                    XCTAssertEqual(fit.model.errors.axis1Index, 3.7, accuracy: 1e-5, "\(mode) \(southern) \(star)")
                    XCTAssertEqual(fit.model.errors.axis2Index, -2.4, accuracy: 1e-5, "\(mode) \(southern) \(star)")
                    XCTAssertEqual(fit.model.errors.baseTiltX, 0.0, accuracy: 1e-6)
                    XCTAssertEqual(fit.model.errors.baseTiltY, 0.0, accuracy: 1e-6)
                    XCTAssertEqual(fit.model.errors.orthogonality, 0.0, accuracy: 1e-6)
                    XCTAssertEqual(fit.model.errors.cone, 0.0, accuracy: 1e-6)
                    XCTAssertTrue(fit.maximumResidualDegrees < 1e-6)
                    XCTAssertEqual(fit.residualsDegrees.count, 1)
                }
            }
        }
    }

    func testTwoStarsFindTheBaseTilt() throws {
        for mode in SkyWatcherMountMode.allCases {
            let truth = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: false,
                                                errors: SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: 1.1, baseTiltX: 0.5, baseTiltY: -0.4))
            let points = [0, 1].map { observe(truth, directionOf(stars(mode)[$0], mode)) }
            let fit = try SkyWatcherAlignmentSolver.solve(points, mode: mode, isSouthernHemisphere: false)
            XCTAssertEqual(fit.model.errors.axis1Index, 2.0, accuracy: 0.5, "\(mode)")
            XCTAssertEqual(fit.model.errors.axis2Index, 1.1, accuracy: 0.5, "\(mode)")
            XCTAssertEqual(fit.model.errors.baseTiltX, 0.5, accuracy: 0.5, "\(mode)")
            XCTAssertEqual(fit.model.errors.baseTiltY, -0.4, accuracy: 0.5, "\(mode)")
            XCTAssertTrue(fit.maximumResidualDegrees < 0.1, "\(mode) \(fit.residualsDegrees)")
            // Two stars cannot pin the tilt down completely (the prior shrinks it), but the model predicts the other stars far better
            // than the index offsets of one star alone.
            let oneStar = try SkyWatcherAlignmentSolver.solve(Array(points.prefix(1)), mode: mode, isSouthernHemisphere: false)
            var worstTwo = 0.0
            var worstOne = 0.0
            for other in stars(mode).dropFirst(2) {
                let direction = directionOf(other, mode)
                let real = observe(truth, direction)
                worstTwo = max(worstTwo, fit.model.direction(axis1Degrees: real.axis1Degrees, axis2Degrees: real.axis2Degrees).angle(to: direction))
                worstOne = max(worstOne, oneStar.model.direction(axis1Degrees: real.axis1Degrees, axis2Degrees: real.axis2Degrees).angle(to: direction))
            }
            XCTAssertTrue(worstTwo < 0.6, "\(mode) \(worstTwo)")
            XCTAssertTrue(worstTwo < worstOne, "\(mode) two stars \(worstTwo), one star \(worstOne)")
        }
    }

    func testThreeStarsRecoverAllSixErrors() throws {
        for mode in SkyWatcherMountMode.allCases {
            let errors = mode == .equatorial ? SkyWatcherTestSupport.equatorialErrors : SkyWatcherTestSupport.altAzimuthErrors
            let truth = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: false, errors: errors)
            let points = stars(mode).prefix(3).map { observe(truth, directionOf($0, mode)) }
            let fit = try SkyWatcherAlignmentSolver.solve(Array(points), mode: mode, isSouthernHemisphere: false)
            // Index offsets and tilts are well determined; orthogonality and cone only weakly (the prior shrinks them).
            XCTAssertEqual(fit.model.errors.axis1Index, errors.axis1Index, accuracy: 0.1, "\(mode)")
            XCTAssertEqual(fit.model.errors.axis2Index, errors.axis2Index, accuracy: 0.1, "\(mode)")
            XCTAssertEqual(fit.model.errors.baseTiltX, errors.baseTiltX, accuracy: 0.1, "\(mode)")
            XCTAssertEqual(fit.model.errors.baseTiltY, errors.baseTiltY, accuracy: 0.1, "\(mode)")
            XCTAssertEqual(fit.model.errors.orthogonality, errors.orthogonality, accuracy: 0.15, "\(mode)")
            XCTAssertEqual(fit.model.errors.cone, errors.cone, accuracy: 0.15, "\(mode)")
            XCTAssertTrue(fit.isPlausible)
            XCTAssertTrue(fit.maximumResidualDegrees < 0.05, "\(mode) \(fit.residualsDegrees)")
            XCTAssertTrue(fit.rmsDegrees <= fit.maximumResidualDegrees)
            // The fitted model points at the two stars that were not used to within a fifth of a degree, although both are outside the
            // region the three stars span (extrapolation is the weak spot).
            for other in stars(mode).dropFirst(3) {
                let direction = directionOf(other, mode)
                let real = observe(truth, direction)
                let predicted = fit.model.direction(axis1Degrees: real.axis1Degrees, axis2Degrees: real.axis2Degrees)
                XCTAssertTrue(predicted.angle(to: direction) < 0.2, "\(mode) \(other) \(predicted.angle(to: direction))")
            }
        }
    }

    func testSouthernHemisphereAlignment() throws {
        let truth = SkyWatcherPointingModel(mode: .equatorial, isSouthernHemisphere: true, errors: SkyWatcherTestSupport.equatorialErrors)
        let points = equatorialStars.prefix(3).map { observe(truth, directionOf($0, .equatorial)) }
        let fit = try SkyWatcherAlignmentSolver.solve(Array(points), mode: .equatorial, isSouthernHemisphere: true)
        XCTAssertEqual(fit.model.errors.axis1Index, SkyWatcherTestSupport.equatorialErrors.axis1Index, accuracy: 0.1)
        XCTAssertEqual(fit.model.errors.baseTiltY, SkyWatcherTestSupport.equatorialErrors.baseTiltY, accuracy: 0.15)
        XCTAssertTrue(fit.maximumResidualDegrees < 0.05)
        XCTAssertTrue(fit.model.isSouthernHemisphere)
    }

    func testResidualsExposeAWrongStar() throws {
        for mode in SkyWatcherMountMode.allCases {
            let truth = SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: false,
                                                errors: SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: 1.0))
            let good = stars(mode).prefix(2).map { observe(truth, directionOf($0, mode)) }
            // The user centred another star than the one the app says: 20° off.
            let third = stars(mode)[2]
            let wrongDirection = directionOf(Star(first: third.first + 20.0, second: third.second - 8.0), mode)
            let real = observe(truth, directionOf(third, mode))
            let wrong = SkyWatcherAlignmentPoint(axis1Degrees: real.axis1Degrees, axis2Degrees: real.axis2Degrees, direction: wrongDirection,
                                                 timestamp: real.timestamp)
            // Free errors can explain a lot, but not without becoming larger than a hand-made set-up can have.
            let fit = try SkyWatcherAlignmentSolver.solve(good + [wrong], mode: mode, isSouthernHemisphere: false)
            XCTAssertTrue(fit.maximumResidualDegrees > 0.5 || !fit.isPlausible, "\(mode) \(fit.residualsDegrees) \(fit.model.errors)")
            let twoStars = try SkyWatcherAlignmentSolver.solve([good[0], wrong], mode: mode, isSouthernHemisphere: false)
            XCTAssertTrue(twoStars.maximumResidualDegrees > 0.5 || !twoStars.isPlausible, "\(mode) \(twoStars.residualsDegrees) \(twoStars.model.errors)")
        }
    }

    func testAlignmentInputsAreValidated() throws {
        let point = SkyWatcherAlignmentPoint(axis1Degrees: 10.0, axis2Degrees: 20.0, direction: Vector3(0.0, 1.0, 0.0), timestamp: SkyWatcherTestSupport.start)
        func with(axis1Degrees: Double? = nil, axis2Degrees: Double? = nil, direction: Vector3? = nil) -> SkyWatcherAlignmentPoint {
            SkyWatcherAlignmentPoint(axis1Degrees: axis1Degrees ?? point.axis1Degrees, axis2Degrees: axis2Degrees ?? point.axis2Degrees,
                                     direction: direction ?? point.direction, timestamp: point.timestamp)
        }
        let bad: [[SkyWatcherAlignmentPoint]] = [
            [],
            [with(axis1Degrees: Double.nan)],
            [with(axis2Degrees: Double.infinity)],
            [with(direction: Vector3(Double.nan, 0.0, 0.0))],
            [with(direction: Vector3(0.0, 0.0, 0.0))],
            [SkyWatcherAlignmentPoint](repeating: point, count: 9),
        ]
        for points in bad {
            XCTAssertTrue(skyWatcherThrown { try SkyWatcherAlignmentSolver.solve(points, mode: .altAzimuth, isSouthernHemisphere: false) }?.isInvalidInput == true)
        }
        // A direction that is not a unit vector is normalised.
        let fit = try SkyWatcherAlignmentSolver.solve([with(direction: Vector3(0.0, 5.0, 0.0))], mode: .altAzimuth, isSouthernHemisphere: false)
        XCTAssertTrue(fit.maximumResidualDegrees < 1e-6)
    }
}

import XCTest
@testable import LodestarKit

final class StreakRiskTests: XCTestCase {
    private typealias Support = SatelliteTestSupport

    // MARK: Camera frame

    private func assertVector(_ expected: Vector3, _ actual: Vector3, accuracy: Double = 1e-12, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, file: file, line: line)
    }

    private func frame(_ azimuth: Double, _ altitude: Double, _ width: Double, _ height: Double, roll: Double = 0.0) throws -> CameraFrame {
        try XCTUnwrap(CameraFrame(boresight: HorizontalCoordinate(azimuth: azimuth, altitude: altitude), widthDegrees: width, heightDegrees: height, rollDegrees: roll))
    }

    func testALevelFrameLooksAlongTheBoresightWithTheTopUp() throws {
        let north = try frame(0.0, 0.0, 60.0, 40.0)
        assertVector(Vector3(0.0, 1.0, 0.0), north.boresight)
        assertVector(Vector3(0.0, 0.0, 1.0), north.up)
        assertVector(Vector3(1.0, 0.0, 0.0), north.right)
        let east = try frame(90.0, 0.0, 60.0, 40.0)
        assertVector(Vector3(1.0, 0.0, 0.0), east.boresight)
        assertVector(Vector3(0.0, -1.0, 0.0), east.right)  // looking east, the right-hand side is south
        let raised = try frame(0.0, 45.0, 60.0, 40.0)
        assertVector(Vector3(0.0, 0.5.squareRoot(), 0.5.squareRoot()), raised.boresight)
        assertVector(Vector3(0.0, -0.5.squareRoot(), 0.5.squareRoot()), raised.up)
        assertVector(Vector3(1.0, 0.0, 0.0), raised.right)
        XCTAssertEqual(raised.boresightCoordinate.altitude, HorizontalCoordinate(azimuth: 0.0, altitude: 45.0).altitude, accuracy: 1e-9)
    }

    func testPositiveRollTurnsTheCameraClockwise() throws {
        // Turned 90 degrees clockwise (as the photographer sees it) the picture's top points to the right of the
        // level up, to the east when looking north; the picture's right side then points down.
        let frame90 = try frame(0.0, 0.0, 60.0, 40.0, roll: 90.0)
        assertVector(Vector3(1.0, 0.0, 0.0), frame90.up)
        assertVector(Vector3(0.0, 0.0, -1.0), frame90.right)
        let tilted = try frame(0.0, 0.0, 60.0, 40.0, roll: 30.0)
        XCTAssertEqual(AstroMath.degrees(atan2(tilted.up.x, tilted.up.z)), 30.0, accuracy: 1e-9)
        XCTAssertEqual(AstroMath.degrees(atan2(tilted.right.z, tilted.right.x)), -30.0, accuracy: 1e-9)
        let reversed = try frame(0.0, 0.0, 60.0, 40.0, roll: -30.0)
        assertVector(Vector3(-tilted.up.x, 0.0, tilted.up.z), reversed.up)
        // Axes stay orthonormal.
        for candidate in [frame90, tilted, reversed] {
            XCTAssertEqual(candidate.boresight.dot(candidate.up), 0.0, accuracy: 1e-12)
            XCTAssertEqual(candidate.boresight.dot(candidate.right), 0.0, accuracy: 1e-12)
            XCTAssertEqual(candidate.up.dot(candidate.right), 0.0, accuracy: 1e-12)
            XCTAssertEqual(candidate.up.length, 1.0, accuracy: 1e-12)
            assertVector(candidate.right, candidate.boresight.cross(candidate.up))
        }
    }

    func testLookingAtTheZenithTheTopIsNorth() throws {
        let zenith = try frame(123.0, 90.0, 60.0, 40.0)
        assertVector(Vector3(0.0, 0.0, 1.0), zenith.boresight)
        assertVector(Vector3(0.0, 1.0, 0.0), zenith.up)
        assertVector(Vector3(-1.0, 0.0, 0.0), zenith.right)  // looking up with north at the top, west is on the right
        let nadir = try frame(0.0, -90.0, 60.0, 40.0)
        assertVector(Vector3(0.0, 1.0, 0.0), nadir.up)
        assertVector(Vector3(1.0, 0.0, 0.0), nadir.right)  // looking down like at a map, east is on the right
    }

    func testContainsUsesTheTangentPlane() throws {
        let camera = try frame(90.0, 0.0, 60.0, 40.0)  // looking east
        func direction(_ rightDegrees: Double, _ upDegrees: Double) -> Vector3 {
            // Gnomonic coordinates tan(right), tan(up) relative to the boresight.
            camera.boresight + camera.right * tan(rightDegrees * Double.pi / 180) + camera.up * tan(upDegrees * Double.pi / 180)
        }
        XCTAssertTrue(camera.contains(camera.boresight))
        XCTAssertTrue(camera.contains(direction(29.9, 19.9)))
        XCTAssertFalse(camera.contains(direction(30.1, 0.0)))
        XCTAssertFalse(camera.contains(direction(0.0, 20.1)))
        XCTAssertFalse(camera.contains(direction(-30.1, 0.0)))
        XCTAssertFalse(camera.contains(direction(0.0, -20.1)))
        XCTAssertFalse(camera.contains(camera.boresight * -1.0))
        XCTAssertFalse(camera.contains(camera.right))  // 90 degrees away
        let position = try XCTUnwrap(camera.position(of: direction(15.0, -10.0)))
        XCTAssertEqual(position.x, tan(15 * Double.pi / 180) / tan(30 * Double.pi / 180), accuracy: 1e-12)
        XCTAssertEqual(position.y, -tan(10 * Double.pi / 180) / tan(20 * Double.pi / 180), accuracy: 1e-12)
        XCTAssertNil(camera.position(of: camera.right))
        let horizontal = tan(30 * Double.pi / 180)
        let vertical = tan(20 * Double.pi / 180)
        XCTAssertEqual(camera.cornerAngle, AstroMath.degrees(atan((horizontal * horizontal + vertical * vertical).squareRoot())), accuracy: 1e-9)
    }

    func testInvalidFramesAreRefused() {
        let look = HorizontalCoordinate(azimuth: 0.0, altitude: 0.0)
        let sizes: [(Double, Double)] = [(0.0, 10.0), (10.0, 0.0), (-5.0, 10.0), (171.0, 10.0), (10.0, 180.0), (.nan, 10.0), (10.0, .infinity)]
        for (width, height) in sizes {
            XCTAssertNil(CameraFrame(boresight: look, widthDegrees: width, heightDegrees: height), "\(width) x \(height)")
        }
        XCTAssertNil(CameraFrame(boresight: look, widthDegrees: 10.0, heightDegrees: 10.0, rollDegrees: .nan))
        XCTAssertNotNil(CameraFrame(boresight: look, widthDegrees: 170.0, heightDegrees: 170.0))
        XCTAssertNotNil(CameraFrame(boresight: look, widthDegrees: 0.01, heightDegrees: 0.01))
    }

    func testAFrameFromAMeasuredPointing() throws {
        // A phone held upright facing north: the camera looks north along the horizon with its top up.
        let matrix = Matrix3(columns: Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
        let attitude = try XCTUnwrap(DeviceAttitude(matrix: matrix, referenceAzimuth: 0.0, timestamp: 0.0))
        let solution = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
        let camera = try XCTUnwrap(CameraFrame(solution: solution, widthDegrees: 40.0, heightDegrees: 30.0))
        assertVector(Vector3(0.0, 1.0, 0.0), camera.boresight, accuracy: 1e-9)
        assertVector(Vector3(0.0, 0.0, 1.0), camera.up, accuracy: 1e-9)
        assertVector(Vector3(1.0, 0.0, 0.0), camera.right, accuracy: 1e-9)
        XCTAssertNil(CameraFrame(solution: solution, widthDegrees: 0.0, heightDegrees: 30.0))
    }

    // MARK: Geometry helpers

    func testClippingASegmentAgainstTheFrame() {
        var clipper = SegmentClipper()
        XCTAssertTrue(clipper.clip(-2.0, 0.0, 2.0, 0.0))
        XCTAssertEqual(clipper.low, 0.25, accuracy: 1e-12)
        XCTAssertEqual(clipper.high, 0.75, accuracy: 1e-12)
        XCTAssertTrue(clipper.clip(0.5, 0.5, -0.5, -0.5))
        XCTAssertEqual(clipper.low, 0.0, accuracy: 1e-12)
        XCTAssertEqual(clipper.high, 1.0, accuracy: 1e-12)
        XCTAssertFalse(clipper.clip(-2.0, 2.0, 2.0, 1.5))  // passes above
        XCTAssertFalse(clipper.clip(2.0, -3.0, 3.0, 3.0))  // passes to the right
        XCTAssertTrue(clipper.clip(-1.5, 0.5, 0.5, 2.5))  // clips the upper left corner region
        XCTAssertTrue(clipper.low > 0.0 && clipper.high < 1.0)
        XCTAssertFalse(clipper.clip(-1.5, 0.9, 0.9, 2.5))  // grazes beyond the corner
        XCTAssertTrue(clipper.clip(0.0, 0.0, 0.0, 0.0))  // a point inside
        XCTAssertFalse(clipper.clip(3.0, 0.0, 3.0, 0.0))  // a point outside
        XCTAssertTrue(clipper.clip(1.0, -3.0, 1.0, 3.0))  // along the right edge
        XCTAssertEqual(clipper.low, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(clipper.high, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertTrue(clipper.clip(-1.0, -1.0, 1.0, 1.0))  // diagonal corner to corner
    }

    func testRestrictingALinearQuantity() {
        var restriction = LinearRestriction()
        XCTAssertTrue(restriction.restrict(from: 5.0, to: 6.0, limit: 4.0))
        XCTAssertEqual(restriction.low, 0.0, accuracy: 0.0)
        XCTAssertEqual(restriction.high, 1.0, accuracy: 0.0)
        XCTAssertFalse(restriction.restrict(from: 1.0, to: 2.0, limit: 4.0))
        XCTAssertTrue(restriction.restrict(from: 1.0, to: 5.0, limit: 3.0))  // rises through the limit half way
        XCTAssertEqual(restriction.low, 0.5, accuracy: 1e-12)
        XCTAssertEqual(restriction.high, 1.0, accuracy: 0.0)
        XCTAssertTrue(restriction.restrict(from: 5.0, to: 1.0, limit: 4.0))  // falls through it a quarter of the way
        XCTAssertEqual(restriction.low, 0.0, accuracy: 0.0)
        XCTAssertEqual(restriction.high, 0.25, accuracy: 1e-12)
    }

    // MARK: Assessments

    private let epoch = SatelliteTestSupport.iso("2026-10-18T00:00:00Z")
    private let equator = SatelliteTestSupport.observer(0.0, 30.0)

    /// A geostationary satellite 30 degrees east of Greenwich as seen from (0, 30): at the zenith.
    private func geostationarySatellite(intrinsic: Double? = nil) throws -> Satellite {
        Satellite(elements: try Support.geostationary(longitude: 30.0, epoch: epoch), intrinsicMagnitude: intrinsic)
    }

    private func exposure(_ seconds: Double) -> DateInterval { DateInterval(start: epoch.addingTimeInterval(7200.0), duration: seconds) }

    func testASatelliteThatSitsInTheFrameStreaksTheWholeExposure() throws {
        let satellite = try geostationarySatellite()
        let time = epoch.addingTimeInterval(7200.0)
        let look = try XCTUnwrap(satellite.look(at: time, observer: equator))
        XCTAssertTrue(look.isSunlit, "the test needs a lit satellite")
        let camera = try XCTUnwrap(CameraFrame(boresight: look.horizontal, widthDegrees: 4.0, heightDegrees: 3.0))
        let assessment = StreakRisk.assess([satellite], observer: equator, frame: camera, exposure: exposure(30.0))
        XCTAssertEqual(assessment.crossings.count, 1)
        let crossing = try XCTUnwrap(assessment.crossings.first)
        XCTAssertTrue(crossing.startsBeforeExposure && crossing.endsAfterExposure)
        XCTAssertEqual(crossing.entry.date, time)
        XCTAssertEqual(crossing.duration, 30.0, accuracy: 1e-6)
        let position = try XCTUnwrap(crossing.entry.position)
        XCTAssertTrue(abs(position.x) < 0.05 && abs(position.y) < 0.05, "centre of the frame, got \(position)")
        XCTAssertEqual(assessment.evaluatedCount, 1)
        XCTAssertEqual(assessment.aboveHorizonCount, 1)
        XCTAssertEqual(assessment.sunlitAboveSummaryAltitudeCount, 1)
        XCTAssertEqual(assessment.crossingsPerMinute * assessment.rateWindow / 60.0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(assessment.crossingsPerMinute, 0.5, accuracy: 1e-12)  // one crossing in the default window of 120 s
        XCTAssertNil(crossing.magnitude)
    }

    func testAFrameThatMissesTheSatelliteSeesNothing() throws {
        let satellite = try geostationarySatellite()
        let look = try XCTUnwrap(satellite.look(at: epoch.addingTimeInterval(7200.0), observer: equator))
        let away = HorizontalCoordinate(azimuth: look.azimuth + 90.0, altitude: look.altitude - 15.0)
        let camera = try XCTUnwrap(CameraFrame(boresight: away, widthDegrees: 4.0, heightDegrees: 3.0))
        let assessment = StreakRisk.assess([satellite], observer: equator, frame: camera, exposure: exposure(30.0))
        XCTAssertTrue(assessment.crossings.isEmpty)
        XCTAssertEqual(assessment.crossingsPerMinute, 0.0, accuracy: 0.0)
        XCTAssertEqual(assessment.sunlitAboveSummaryAltitudeCount, 1)
        // A frame that just fits the satellite.
        let tight = try XCTUnwrap(CameraFrame(boresight: look.horizontal, widthDegrees: 0.02, heightDegrees: 0.02))
        XCTAssertEqual(StreakRisk.assess([satellite], observer: equator, frame: tight, exposure: exposure(30.0)).crossings.count, 1)
    }

    func testTheHorizonAndTheMagnitudeLimitFilterCrossings() throws {
        let bright = try geostationarySatellite(intrinsic: -1.8)
        let look = try XCTUnwrap(bright.look(at: epoch.addingTimeInterval(7200.0), observer: equator))
        let camera = try XCTUnwrap(CameraFrame(boresight: look.horizontal, widthDegrees: 4.0, heightDegrees: 3.0))
        func crossings(_ satellite: Satellite, _ options: StreakOptions = StreakOptions()) -> StreakAssessment {
            StreakRisk.assess([satellite], observer: equator, frame: camera, exposure: exposure(30.0), options: options)
        }
        let unfiltered = crossings(bright)
        let magnitude = try XCTUnwrap(unfiltered.crossings.first?.magnitude)
        XCTAssertTrue((4.5...6.5).contains(magnitude), "a geostationary satellite 36 000 km away is faint, magnitude \(magnitude)")
        // Dropped by a limiting magnitude brighter than it; kept by a fainter one; satellites without a known
        // magnitude are never dropped.
        XCTAssertTrue(crossings(bright, StreakOptions(limitingMagnitude: 3.0)).crossings.isEmpty)
        XCTAssertEqual(crossings(bright, StreakOptions(limitingMagnitude: 20.0)).crossings.count, 1)
        XCTAssertEqual(crossings(try geostationarySatellite(), StreakOptions(limitingMagnitude: 3.0)).crossings.count, 1)
        // Streaks only count above the minimum altitude (the satellite stands at the zenith).
        XCTAssertEqual(crossings(bright, StreakOptions(minimumAltitude: 89.0)).crossings.count, 1)
        XCTAssertTrue(crossings(bright, StreakOptions(minimumAltitude: 89.99)).crossings.isEmpty)
        XCTAssertEqual(crossings(bright, StreakOptions(summaryAltitude: 85.0)).sunlitAboveSummaryAltitudeCount, 1)
        XCTAssertEqual(crossings(bright, StreakOptions(summaryAltitude: 89.99)).sunlitAboveSummaryAltitudeCount, 0)
    }

    func testAnEmptyListAndAnUnpropagatableSatellite() throws {
        let camera = try frame(0.0, 45.0, 60.0, 40.0)
        let empty = StreakRisk.assess([], observer: equator, frame: camera, exposure: exposure(30.0))
        XCTAssertTrue(empty.crossings.isEmpty)
        XCTAssertEqual(empty.evaluatedCount, 0)
        XCTAssertEqual(empty.crossingsPerMinute, 0.0, accuracy: 0.0)
        // The ISS element set cannot be propagated 40 years later.
        let iss = try XCTUnwrap(Support.referenceSatellites()["iss"])
        let far = DateInterval(start: Support.iso("2070-01-01T00:00:00Z"), duration: 30.0)
        let result = StreakRisk.assess([iss], observer: equator, frame: camera, exposure: far)
        XCTAssertEqual(result.evaluatedCount, 0)
        XCTAssertTrue(result.crossings.isEmpty)
    }

    func testStreakProbabilityFollowsAPoissonProcess() {
        let assessment = StreakAssessment(
            crossings: [], evaluatedCount: 100, aboveHorizonCount: 20, sunlitAboveSummaryAltitudeCount: 5,
            crossingsPerMinute: 2.0, rateWindow: 120.0
        )
        XCTAssertEqual(assessment.probabilityOfStreak(exposureSeconds: 60.0), 1.0 - exp(-2.0), accuracy: 1e-12)
        XCTAssertEqual(assessment.probabilityOfStreak(exposureSeconds: 30.0), 1.0 - exp(-1.0), accuracy: 1e-12)
        XCTAssertEqual(assessment.probabilityOfStreak(exposureSeconds: 0.0), 0.0, accuracy: 0.0)
        XCTAssertEqual(assessment.probabilityOfStreak(exposureSeconds: .nan), 0.0, accuracy: 0.0)
        XCTAssertEqual(assessment.probabilityOfStreak(exposureSeconds: -5.0), 0.0, accuracy: 0.0)
    }

    func testAssessmentLimits() throws {
        let camera = try frame(0.0, 45.0, 60.0, 40.0)
        let satellite = try geostationarySatellite()
        // A negative or NaN duration is an exposure of zero seconds; the rate window is clamped.
        let zero = StreakRisk.assess(
            [satellite], observer: equator, frame: camera,
            exposure: DateInterval(start: epoch.addingTimeInterval(7200.0), duration: 0.0), options: StreakOptions(rateWindow: .nan)
        )
        XCTAssertEqual(zero.rateWindow, 120.0, accuracy: 0.0)
        let long = StreakRisk.assess([satellite], observer: equator, frame: camera, exposure: exposure(10_000.0), options: StreakOptions(rateWindow: 0.0))
        XCTAssertEqual(long.rateWindow, 1.0, accuracy: 0.0)
        XCTAssertEqual(long.evaluatedCount, 1)
    }
}

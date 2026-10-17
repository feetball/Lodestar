import XCTest
@testable import LodestarKit

final class PointingSmootherTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let axis = Vector3(0.3, -0.5, 0.8)
    private let base = Matrix3.rotation(axis: Vector3(1, 2, 3), angleRadians: 0.9)

    /// The base orientation turned by `degrees` about a fixed axis, so the angle between two such
    /// attitudes is the difference of their parameters.
    private func attitude(_ degrees: Double, at time: TimeInterval, referenceAzimuth: Double = 0) throws -> DeviceAttitude {
        try XCTUnwrap(DeviceAttitude(matrix: Matrix3.rotation(axis: axis, angleRadians: AstroMath.radians(degrees)) * base,
                                     referenceAzimuth: referenceAzimuth, timestamp: time))
    }

    /// Rotation angle in degrees between two attitudes, from the trace of AᵀB.
    private func angle(_ a: DeviceAttitude, _ b: DeviceAttitude) -> Double {
        let product = a.matrix.transposed * b.matrix
        let trace = product[0, 0] + product[1, 1] + product[2, 2]
        return AstroMath.acosDeg((trace - 1) / 2)
    }

    // MARK: Quaternions

    func testQuaternionMatrixRoundTrip() {
        var random = PointingTestRandom(seed: 401)
        var samples = (0..<2000).map { _ in random.rotation() }
        // Half turns about each axis and about the diagonals exercise every branch of the conversion.
        for axis in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(-1, 2, 1)] {
            for angle in [Double.pi, Double.pi - 1e-6, 3.0, 0.0] {
                samples.append(Matrix3.rotation(axis: axis, angleRadians: angle))
            }
        }
        samples.append(.identity)
        for matrix in samples {
            let q = AttitudeQuaternion(matrix)
            XCTAssertEqual(q.dot(q), 1, accuracy: 1e-12)
            Support.assertMatrix(q.matrix, matrix, accuracy: 1e-12)
            Support.assertRotation(q.matrix, accuracy: 1e-12)
        }
    }

    func testQuaternionAngleMatchesTheRotationAngle() {
        var random = PointingTestRandom(seed: 402)
        for _ in 0..<200 {
            let a = random.rotation()
            let degrees = random.uniform(0, 180)
            let b = Matrix3.rotation(axis: random.unitVector(), angleRadians: AstroMath.radians(degrees)) * a
            XCTAssertEqual(AttitudeQuaternion(a).angle(to: AttitudeQuaternion(b)), degrees, accuracy: 1e-6)
        }
    }

    func testSlerpFollowsTheShortestArc() {
        var random = PointingTestRandom(seed: 403)
        for _ in 0..<200 {
            let a = random.rotation()
            let degrees = random.uniform(0, 179)
            let rotation = random.unitVector()
            let b = Matrix3.rotation(axis: rotation, angleRadians: AstroMath.radians(degrees)) * a
            let qa = AttitudeQuaternion(a), qb = AttitudeQuaternion(b)
            Support.assertMatrix(qa.slerp(to: qb, 0).matrix, a, accuracy: 1e-9)
            Support.assertMatrix(qa.slerp(to: qb, 1).matrix, b, accuracy: 1e-9)
            let t = random.uniform(0.05, 0.95)
            let expected = Matrix3.rotation(axis: rotation, angleRadians: AstroMath.radians(degrees * t)) * a
            Support.assertMatrix(qa.slerp(to: qb, t).matrix, expected, accuracy: 1e-9)
        }
    }

    func testSlerpTakesTheShortSideOfADoubleCover() {
        // q and −q are the same rotation: interpolating towards −q must not go the long way round.
        let a = AttitudeQuaternion(Matrix3.rotationZ(0.2))
        var b = AttitudeQuaternion(Matrix3.rotationZ(0.4))
        b.w = -b.w; b.x = -b.x; b.y = -b.y; b.z = -b.z
        Support.assertMatrix(a.slerp(to: b, 0.5).matrix, Matrix3.rotationZ(0.3), accuracy: 1e-12)
    }

    func testSlerpIsStableForNearlyEqualQuaternions() {
        let a = AttitudeQuaternion(base)
        for tiny in [0.0, 1e-12, 1e-9, 1e-6, 1e-4] {
            let b = AttitudeQuaternion(Matrix3.rotation(axis: Vector3(0, 0, 1), angleRadians: tiny) * base)
            let middle = a.slerp(to: b, 0.5)
            XCTAssertEqual(middle.dot(middle), 1, accuracy: 1e-12)
            Support.assertMatrix(middle.matrix, Matrix3.rotation(axis: Vector3(0, 0, 1), angleRadians: tiny / 2) * base, accuracy: 1e-12)
        }
    }

    // MARK: Filtering

    func testFirstSampleIsPassedThrough() throws {
        var smoother = AttitudeSmoother()
        let first = try attitude(12, at: 100, referenceAzimuth: 33)
        XCTAssertEqual(smoother.update(with: first), first)
    }

    func testAConstantInputStaysConstant() throws {
        var smoother = AttitudeSmoother()
        for k in 0..<120 {
            let input = try attitude(7, at: 100 + Double(k) / 60)
            Support.assertMatrix(smoother.update(with: input).matrix, input.matrix, accuracy: 1e-12)
        }
    }

    func testOutputKeepsTheTimestampAndReferenceAzimuthOfTheSample() throws {
        var smoother = AttitudeSmoother()
        _ = smoother.update(with: try attitude(0, at: 10, referenceAzimuth: 25))
        let output = smoother.update(with: try attitude(0.4, at: 10.02, referenceAzimuth: 25))
        XCTAssertEqual(output.timestamp, 10.02)
        XCTAssertEqual(output.referenceAzimuth, 25, accuracy: 1e-12)
        Support.assertRotation(output.matrix, accuracy: 1e-12)
    }

    func testAtRestTheTimeConstantIsExponential() throws {
        // With the lag limit out of the way the filter is a plain exponential smoother.
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 0))
        let target = 10.0
        var output = try attitude(0, at: 0)
        for k in 1...30 {
            output = smoother.update(with: try attitude(target, at: Double(k) / 60))
            let expectedFraction = 1 - exp(-(Double(k) / 60) / 0.12)
            XCTAssertEqual(angle(output, try attitude(0, at: 0)) / target, expectedFraction, accuracy: 1e-9, "sample \(k)")
        }
    }

    func testNoiseIsAveragedOutWhileStill() throws {
        var random = PointingTestRandom(seed: 411)
        var smoother = AttitudeSmoother()
        let truth = try attitude(0, at: 0)
        var rawSquares = 0.0, filteredSquares = 0.0
        let count = 600
        for k in 0..<count {
            let noisy = try XCTUnwrap(DeviceAttitude(matrix: random.smallRotation(sigmaDegrees: 0.01) * truth.matrix,
                                                     timestamp: Double(k) / 60))
            let filtered = smoother.update(with: noisy)
            if k >= 60 {
                rawSquares += pow(angle(noisy, truth), 2)
                filteredSquares += pow(angle(filtered, truth), 2)
            }
        }
        XCTAssertLessThan((filteredSquares / rawSquares).squareRoot(), 0.5)
    }

    func testLagStaysBelowTheLimitWhileTurning() throws {
        for speed in [2.0, 10, 30, 90, 240] {
            var smoother = AttitudeSmoother()
            var lag = 0.0
            for k in 0..<240 {
                let time = Double(k) / 60
                let raw = try attitude(speed * time, at: time)
                let filtered = smoother.update(with: raw)
                if k > 120 { lag = max(lag, angle(filtered, raw)) }
            }
            XCTAssertLessThan(lag, 0.5, "speed \(speed)°/s")
            XCTAssertGreaterThan(lag, 0.0, "speed \(speed)°/s")
        }
    }

    func testTheFilteredAttitudeNeverGetsAheadOfTheTrueOne() throws {
        var smoother = AttitudeSmoother()
        let start = try attitude(0, at: 0)
        for k in 0..<180 {
            let time = Double(k) / 60
            let filtered = smoother.update(with: try attitude(45 * time, at: time))
            XCTAssertLessThanOrEqual(angle(start, filtered), 45 * time + 1e-9)
        }
    }

    func testAFastStepIsNotSmoothedAway() throws {
        // A jump of a few degrees in one frame is real motion: the output must follow at once.
        var smoother = AttitudeSmoother()
        for k in 0..<30 { _ = smoother.update(with: try attitude(0, at: Double(k) / 60)) }
        let stepped = try attitude(5, at: 0.5)
        XCTAssertLessThan(angle(smoother.update(with: stepped), stepped), 0.05)
    }

    func testStepResponseNeverOvershoots() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1)
        for k in 0..<30 { _ = smoother.update(with: try attitude(0, at: Double(k) / 60)) }
        var previousDistance = Double.infinity
        for k in 30..<400 {
            let target = try attitude(3, at: Double(k) / 60)
            let output = smoother.update(with: target)
            let distance = angle(output, target)
            XCTAssertLessThanOrEqual(distance, previousDistance + 1e-9)
            previousDistance = distance
        }
        XCTAssertLessThan(previousDistance, 1e-3)
    }

    // MARK: Resets

    func testALargeJumpRestartsTheFilter() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 0))
        // 15° is smoothed (the lag limit is disabled), 25° exceeds the 20° jump threshold.
        let moderate = try attitude(15, at: 1.0 / 60)
        XCTAssertGreaterThan(angle(smoother.update(with: moderate), moderate), 10)
        let jump = try attitude(25, at: 2.0 / 60)
        let output = smoother.update(with: jump)
        XCTAssertLessThan(angle(output, jump), 1e-9)
        // And the filter carries on smoothly from the new place.
        let next = try attitude(26, at: 3.0 / 60)
        XCTAssertGreaterThan(angle(smoother.update(with: next), next), 0.5)
    }

    func testALongPauseRestartsTheFilter() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 0))
        let soon = try attitude(3, at: 0.4)
        XCTAssertGreaterThan(angle(smoother.update(with: soon), soon), 1e-3) // 0.4 s is still filtered
        let late = try attitude(6, at: 1.0)
        XCTAssertLessThan(angle(smoother.update(with: late), late), 1e-9) // 0.6 s gap restarts
    }

    func testAChangeOfReferenceAzimuthRestartsTheFilter() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 0, referenceAzimuth: 0))
        let sameFrame = try attitude(2, at: 1.0 / 60, referenceAzimuth: 0)
        XCTAssertGreaterThan(angle(smoother.update(with: sameFrame), sameFrame), 1)
        let newFrame = try attitude(3, at: 2.0 / 60, referenceAzimuth: 40)
        let output = smoother.update(with: newFrame)
        XCTAssertLessThan(angle(output, newFrame), 1e-9)
        XCTAssertEqual(output.referenceAzimuth, 40, accuracy: 1e-12)
    }

    func testRepeatedTimestampsRestartTheFilter() throws {
        // Samples without usable timestamps (all 0 by default) are passed through, never frozen.
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        let first = try attitude(0, at: 0)
        XCTAssertEqual(smoother.update(with: first), first)
        for degrees in [2.0, 4, 6] {
            let sample = try attitude(degrees, at: 0)
            XCTAssertEqual(smoother.update(with: sample), sample)
        }
    }

    func testTimeGoingBackwardsRestartsTheFilter() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 5))
        let earlier = try attitude(2, at: 4.99)
        XCTAssertLessThan(angle(smoother.update(with: earlier), earlier), 1e-9)
    }

    func testResetPassesTheNextSampleThrough() throws {
        var smoother = AttitudeSmoother(timeConstant: 0.12, maximumLag: 1e12)
        _ = smoother.update(with: try attitude(0, at: 0))
        smoother.reset()
        let sample = try attitude(5, at: 1.0 / 60)
        XCTAssertEqual(smoother.update(with: sample), sample)
    }

    func testInvalidParametersFallBackToDefaults() {
        let smoother = AttitudeSmoother(timeConstant: -1, maximumLag: .nan, jumpThreshold: 0, maximumTimeGap: .infinity)
        XCTAssertEqual(smoother.timeConstant, 0.12)
        XCTAssertEqual(smoother.maximumLag, 0.5)
        XCTAssertEqual(smoother.jumpThreshold, 20)
        XCTAssertEqual(smoother.maximumTimeGap, 0.5)
        let custom = AttitudeSmoother(timeConstant: 0.3, maximumLag: 2, jumpThreshold: 10, maximumTimeGap: 1)
        XCTAssertEqual(custom.timeConstant, 0.3)
        XCTAssertEqual(custom.jumpThreshold, 10)
    }

    func testSmoothedPointingStaysConsistentWithThePhoneGeometry() throws {
        // End to end: pan a level camera at 20°/s and compare the boresight from the smoothed
        // attitude with the true one. The azimuth lags by less than the limit, the altitude is untouched.
        var smoother = AttitudeSmoother()
        for k in 0..<300 {
            let time = Double(k) / 60
            let azimuth = 100 + 20 * time
            let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: azimuth, altitude: 30), rollDegrees: 0)
            let raw = try Support.attitude(mount: .backCameraPortrait, frame: frame, referenceAzimuth: 15, timestamp: time)
            let smoothed = smoother.update(with: raw)
            let boresight = PointingSolution.solve(attitude: smoothed, mount: .backCameraPortrait).boresight
            if k > 120 {
                let lag = Support.azimuthDifference(azimuth, boresight.azimuth) * cos(AstroMath.radians(30))
                XCTAssertGreaterThan(lag, 0)
                XCTAssertLessThan(lag, 0.5)
                XCTAssertEqual(boresight.altitude, 30, accuracy: 0.01)
            }
        }
    }
}

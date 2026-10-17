import XCTest
@testable import LodestarKit

/// Shared scenario generation for the alignment tests: a "truth" (compass error and mount
/// misalignment) from which phone attitudes are synthesised for known targets.
struct AlignmentTestScenario {
    /// The compass error in degrees (corrected azimuth = measured + heading).
    var headingOffset: Double
    /// The true device-frame rotation of the camera axes relative to the mount's nominal axes
    /// (a rotation vector in degrees).
    var correction: Vector3
    var mount: MountProfile

    /// The point recorded when the camera is centred on `target` with the given roll and the phone
    /// reporting through a reference frame of azimuth `referenceAzimuth`. `noiseDegrees` turns the
    /// reported attitude by a random rotation of that size.
    func point(target: HorizontalCoordinate, roll: Double, referenceAzimuth: Double = 0, noiseDegrees: Double = 0,
               random: inout PointingTestRandom, index: Int = 0, name: String? = nil) throws -> AlignmentPoint {
        // corrected = Rz(−heading) · raw, hence raw = Rz(+heading) · corrected.
        let raw = Matrix3.rotationZ(AstroMath.radians(headingOffset)) * target.unitVector
        let frame = PointingTestSupport.cameraFrame(boresight: HorizontalCoordinate(vector: raw), rollDegrees: roll)
        let exact = try PointingTestSupport.attitude(mount: mount, correction: correction, frame: frame,
                                                     referenceAzimuth: referenceAzimuth)
        var reported = exact
        if noiseDegrees > 0 {
            reported = try XCTUnwrap(DeviceAttitude(matrix: random.smallRotation(sigmaDegrees: noiseDegrees) * exact.matrix,
                                                    referenceAzimuth: referenceAzimuth))
        }
        return AlignmentPoint(attitude: reported, target: target,
                              timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), name: name)
    }

    /// The pointing the true system has for a phone attitude: what the DSLR really looks at.
    func trueBoresight(of attitude: DeviceAttitude) -> HorizontalCoordinate {
        let turn = Matrix3.rotation(axis: correction, angleRadians: AstroMath.radians(correction.length))
        let raw = attitude.deviceToWorld * (turn * mount.cameraAxis)
        return HorizontalCoordinate(vector: Matrix3.rotationZ(-AstroMath.radians(headingOffset)) * raw)
    }
}

final class AlignmentSolverTests: XCTestCase {
    private typealias Support = PointingTestSupport

    /// Pointing error in degrees of `model` for a phone attitude, against the truth.
    private func error(of model: AlignmentModel, scenario: AlignmentTestScenario, attitude: DeviceAttitude) -> Double {
        let predicted = PointingSolution.solve(attitude: attitude, mount: scenario.mount, alignment: model).boresight
        return predicted.angularSeparation(to: scenario.trueBoresight(of: attitude))
    }

    /// Phone attitudes (from random targets and rolls) at which a model is judged.
    private func validationAttitudes(_ scenario: AlignmentTestScenario, count: Int,
                                     random: inout PointingTestRandom) throws -> [DeviceAttitude] {
        try (0..<count).map { _ in
            try scenario.point(target: random.horizontal(altitude: 5...75), roll: random.uniform(-40, 40), random: &random).attitude
        }
    }

    // MARK: One point

    func testOnePointIsExactAtThePointForEveryMountAndRoll() throws {
        var random = PointingTestRandom(seed: 501)
        for mount in MountProfile.presets {
            for _ in 0..<60 {
                let scenario = AlignmentTestScenario(
                    headingOffset: random.uniform(-40, 40),
                    correction: random.unitVector() * random.uniform(0, 4),
                    mount: mount)
                let target = random.horizontal(altitude: -50...75)
                let point = try scenario.point(target: target, roll: random.uniform(-180, 180),
                                               referenceAzimuth: random.uniform(-180, 180), random: &random)
                let model = try AlignmentModel.solve(points: [point], mount: mount)
                XCTAssertEqual(model.points.count, 1)
                XCTAssertEqual(model.residuals.count, 1)
                XCTAssertEqual(model.residuals[0], 0, accuracy: 1e-7, mount.id)
                XCTAssertEqual(model.rmsResidual, 0, accuracy: 1e-7)
                // The public pointing code agrees with the solver: the boresight is the target.
                let solved = PointingSolution.solve(attitude: point.attitude, mount: mount, alignment: model).boresight
                XCTAssertEqual(solved.angularSeparation(to: target), 0, accuracy: 1e-7, mount.id)
                // The correction never turns the picture about the optical axis.
                XCTAssertEqual(model.deviceCorrection.dot(mount.cameraAxis), 0, accuracy: 1e-9)
            }
        }
    }

    func testOnePointWithOnlyACompassErrorRecoversTheOffset() throws {
        var random = PointingTestRandom(seed: 502)
        for mount in MountProfile.presets {
            let scenario = AlignmentTestScenario(headingOffset: 12, correction: .zero, mount: mount)
            let point = try scenario.point(target: HorizontalCoordinate(azimuth: 215, altitude: 33),
                                           roll: random.uniform(-90, 90), random: &random)
            let model = try AlignmentModel.solve(points: [point], mount: mount)
            XCTAssertEqual(model.headingOffset, 12, accuracy: 1e-9, mount.id)
            XCTAssertEqual(model.deviceCorrection.length, 0, accuracy: 1e-9, mount.id)
        }
    }

    func testOnePointWithOnlyAMountTiltRecoversTheTilt() throws {
        // A level camera whose lens sits 2° above the phone's nominal axis: the phone reports an
        // altitude 2° too low, and the correction is the rotation about the camera's right axis.
        let mount = MountProfile.backCameraPortrait
        var random = PointingTestRandom(seed: 503)
        let scenario = AlignmentTestScenario(headingOffset: 0, correction: Vector3(2, 0, 0), mount: mount)
        let point = try scenario.point(target: HorizontalCoordinate(azimuth: 0, altitude: 30), roll: 0, random: &random)
        let model = try AlignmentModel.solve(points: [point], mount: mount)
        XCTAssertEqual(model.headingOffset, 0, accuracy: 1e-9)
        Support.assertVector(model.deviceCorrection, Vector3(2, 0, 0), accuracy: 1e-9)
    }

    func testOnePointBlamesTheAltitudeOnTheMountAndTheAzimuthOnTheCompass() throws {
        // The phone reports (az 90°, alt 20°); the camera really looks at (az 100°, alt 25°).
        let mount = MountProfile.backCameraPortrait
        let reported = HorizontalCoordinate(azimuth: 90, altitude: 20)
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: reported, rollDegrees: 0))
        let point = AlignmentPoint(attitude: attitude, target: HorizontalCoordinate(azimuth: 100, altitude: 25),
                                   timestamp: Date(timeIntervalSince1970: 0))
        let model = try AlignmentModel.solve(points: [point], mount: mount)
        XCTAssertEqual(model.headingOffset, 10, accuracy: 1e-9)
        XCTAssertEqual(model.deviceCorrection.length, 5, accuracy: 1e-9)
        // Raising the lens by 5° about the camera's right axis (device +x): positive rotation about x.
        Support.assertVector(model.deviceCorrection, Vector3(5, 0, 0), accuracy: 1e-9)
    }

    func testOnePointErrorElsewhereIsBounded() throws {
        // Truth: 12° compass error plus a 2° mount misalignment in a random direction. After aligning
        // on one object, the camera is wrong by no more than a few degrees anywhere else.
        var random = PointingTestRandom(seed: 504)
        var worst = 0.0
        for mount in MountProfile.presets {
            for _ in 0..<40 {
                let scenario = AlignmentTestScenario(headingOffset: 12, correction: random.unitVector() * 2, mount: mount)
                let point = try scenario.point(target: random.horizontal(altitude: 10...65),
                                               roll: random.uniform(-30, 30), random: &random)
                let model = try AlignmentModel.solve(points: [point], mount: mount)
                for attitude in try validationAttitudes(scenario, count: 10, random: &random) {
                    worst = max(worst, error(of: model, scenario: scenario, attitude: attitude))
                }
            }
        }
        XCTAssertLessThan(worst, 5)
    }

    /// A compass error: the canonical 12° most of the time, anywhere on the circle otherwise.
    private func compassError(_ random: inout PointingTestRandom) -> Double {
        random.nextBits() % 3 == 0 ? 12 : random.uniform(-180, 180)
    }

    // MARK: Several points

    func testTwoToFivePointsRecoverTheTruthWithoutNoise() throws {
        var random = PointingTestRandom(seed: 505)
        for mount in MountProfile.presets {
            for count in 2...5 {
                for _ in 0..<12 {
                    let scenario = AlignmentTestScenario(headingOffset: compassError(&random), correction: random.unitVector() * 2, mount: mount)
                    let points = try (0..<count).map { index -> AlignmentPoint in
                        // Spread in altitude and azimuth, and some roll, so the effects can be told apart.
                        let altitude = 15 + 55 * Double(index) / Double(max(count - 1, 1)) + random.uniform(-5, 5)
                        return try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: altitude),
                                                  roll: random.uniform(-45, 45), random: &random, index: index)
                    }
                    let model = try AlignmentModel.solve(points: points, mount: mount)
                    XCTAssertEqual(model.points.count, count)
                    XCTAssertLessThan(model.rmsResidual, 0.01, "\(mount.id) \(count) points")
                    for attitude in try validationAttitudes(scenario, count: 8, random: &random) {
                        XCTAssertLessThan(error(of: model, scenario: scenario, attitude: attitude), 0.05,
                                          "\(mount.id) \(count) points")
                    }
                }
            }
        }
    }

    func testCompassOffsetAndPureTiltAreSeparatedByTwoPoints() throws {
        // Truth without twist so that the parameters themselves can be compared.
        let mount = MountProfile.backCameraPortrait
        var random = PointingTestRandom(seed: 506)
        let truth = Vector3(1.5, -1.0, 0)
        let scenario = AlignmentTestScenario(headingOffset: -17, correction: truth, mount: mount)
        let points = [
            try scenario.point(target: HorizontalCoordinate(azimuth: 40, altitude: 20), roll: 0, random: &random, index: 0),
            try scenario.point(target: HorizontalCoordinate(azimuth: 250, altitude: 62), roll: 25, random: &random, index: 1),
        ]
        let model = try AlignmentModel.solve(points: points, mount: mount)
        XCTAssertEqual(model.headingOffset, -17, accuracy: 0.05)
        Support.assertVector(model.deviceCorrection, truth, accuracy: 0.05)
    }

    func testPointsInAMixOfReferenceFramesAreSolvedTogether() throws {
        // The compass-referenced points and the points taken after switching to a gyro frame (a
        // different reference azimuth) describe the same camera and share one answer.
        let mount = MountProfile.backCameraLandscapeLeft
        var random = PointingTestRandom(seed: 507)
        let scenario = AlignmentTestScenario(headingOffset: 9, correction: Vector3(1, 2, 0), mount: mount)
        var points = [AlignmentPoint]()
        for (index, psi) in [0.0, 0, 133, 133, -75].enumerated() {
            points.append(try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: 15 + 12 * Double(index)),
                                             roll: random.uniform(-30, 30), referenceAzimuth: psi, random: &random, index: index))
        }
        let model = try AlignmentModel.solve(points: points, mount: mount)
        XCTAssertLessThan(model.rmsResidual, 0.01)
        XCTAssertEqual(model.headingOffset, 9, accuracy: 0.05)
    }

    func testNoisyPointsDegradeGracefully() throws {
        var random = PointingTestRandom(seed: 508)
        var errors = [Double]()
        var worstResidual = 0.0
        for mount in MountProfile.presets {
            for _ in 0..<15 {
                let scenario = AlignmentTestScenario(headingOffset: 12, correction: random.unitVector() * 2, mount: mount)
                let points = try (0..<5).map { index in
                    try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: 15 + 14 * Double(index)),
                                       roll: random.uniform(-45, 45), noiseDegrees: 0.2, random: &random, index: index)
                }
                let model = try AlignmentModel.solve(points: points, mount: mount)
                worstResidual = max(worstResidual, model.rmsResidual)
                for attitude in try validationAttitudes(scenario, count: 6, random: &random) {
                    errors.append(error(of: model, scenario: scenario, attitude: attitude))
                }
            }
        }
        // Per-axis noise of 0.2° puts the input pointing about 0.3° off; the fit does at least as well.
        XCTAssertLessThan(errors.reduce(0, +) / Double(errors.count), 0.4)
        XCTAssertLessThan(errors.max() ?? .infinity, 1.5)
        XCTAssertLessThan(worstResidual, 0.8)
    }

    func testResidualsAreTheDistancesFromTheTargets() throws {
        var random = PointingTestRandom(seed: 509)
        let mount = MountProfile.flatOnTopTopEdgeForward
        let scenario = AlignmentTestScenario(headingOffset: 5, correction: Vector3(0, 1.5, 0), mount: mount)
        let points = try (0..<4).map { index in
            try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: 20 + 12 * Double(index)),
                               roll: random.uniform(-30, 30), noiseDegrees: 0.3, random: &random, index: index)
        }
        let model = try AlignmentModel.solve(points: points, mount: mount)
        XCTAssertEqual(model.residuals.count, 4)
        for (point, residual) in zip(model.points, model.residuals) {
            let solved = PointingSolution.solve(attitude: point.attitude, mount: mount, alignment: model).boresight
            XCTAssertEqual(residual, solved.angularSeparation(to: point.target), accuracy: 1e-7)
        }
        let expectedRMS = (model.residuals.map { $0 * $0 }.reduce(0, +) / 4).squareRoot()
        XCTAssertEqual(model.rmsResidual, expectedRMS, accuracy: 1e-12)
        XCTAssertGreaterThan(model.rmsResidual, 0.01)
    }

    func testTheFitIsNoWorseThanAnyOtherParameters() throws {
        // The solution is a minimum of the (prior-regularised) squared error: nudging either
        // parameter does not reduce the sum of squared residuals.
        var random = PointingTestRandom(seed: 510)
        let mount = MountProfile.backCameraPortrait
        let scenario = AlignmentTestScenario(headingOffset: 20, correction: Vector3(2, -1, 0), mount: mount)
        let points = try (0..<4).map { index in
            try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: 20 + 14 * Double(index)),
                               roll: random.uniform(-30, 30), noiseDegrees: 0.3, random: &random, index: index)
        }
        let model = try AlignmentModel.solve(points: points, mount: mount)
        func cost(heading: Double, correction: Vector3) -> Double {
            let trial = AlignmentModel(headingOffset: heading, deviceCorrection: correction, points: [], residuals: [],
                                       pointingUncertainty: nil, calibratedMount: mount)
            let sumOfSquares = points.reduce(0.0) { total, point in
                let boresight = PointingSolution.solve(attitude: point.attitude, mount: mount, alignment: trial).boresight
                return total + pow(boresight.angularSeparation(to: point.target) / 0.25, 2)
            }
            return sumOfSquares + pow(correction.length / 10, 2)
        }
        let best = cost(heading: model.headingOffset, correction: model.deviceCorrection)
        for delta in [Vector3(0.05, 0, 0), Vector3(0, 0.05, 0), Vector3(-0.05, 0, 0), Vector3(0, -0.05, 0)] {
            XCTAssertGreaterThanOrEqual(cost(heading: model.headingOffset, correction: model.deviceCorrection + delta), best - 1e-9)
        }
        for delta in [0.05, -0.05] {
            XCTAssertGreaterThanOrEqual(cost(heading: model.headingOffset + delta, correction: model.deviceCorrection), best - 1e-9)
        }
    }

    // MARK: Uncertainty

    func testUncertaintyShrinksAsWellSpreadPointsAreAdded() throws {
        var random = PointingTestRandom(seed: 520)
        let mount = MountProfile.backCameraPortrait
        let scenario = AlignmentTestScenario(headingOffset: 12, correction: Vector3(1.5, -1, 0), mount: mount)
        // (azimuth, altitude, roll) of five objects spread over the sky.
        let spread: [(Double, Double, Double)] = [(40, 15, 0), (250, 62, 30), (130, 38, -40), (320, 72, 10), (200, 25, 60)]
        var model = AlignmentModel.identity
        XCTAssertNil(model.pointingUncertainty)
        var previous = Double.infinity
        var values = [Double]()
        for (index, item) in spread.enumerated() {
            let point = try scenario.point(target: HorizontalCoordinate(azimuth: item.0, altitude: item.1), roll: item.2,
                                           random: &random, index: index)
            model = try model.adding(point, mount: mount)
            let uncertainty = try XCTUnwrap(model.pointingUncertainty)
            XCTAssertLessThan(uncertainty, previous)
            previous = uncertainty
            values.append(uncertainty)
        }
        XCTAssertGreaterThan(values[0], 10) // one point says nothing about the rest of the sky
        XCTAssertLessThan(values[1], 1.0)
        XCTAssertLessThan(values[2], 0.6)
        XCTAssertLessThan(values[4], 0.35)
    }

    func testUncertaintyFlagsPointsThatCannotSeparateCompassFromMount() throws {
        // All at one altitude with the camera level: a compass error and a pan error of the mount look
        // alike, however many points there are.
        var random = PointingTestRandom(seed: 521)
        let mount = MountProfile.backCameraPortrait
        let scenario = AlignmentTestScenario(headingOffset: 12, correction: Vector3(1.5, -1, 0), mount: mount)
        var model = AlignmentModel.identity
        for index in 0..<4 {
            let point = try scenario.point(target: HorizontalCoordinate(azimuth: Double(index) * 90, altitude: 30), roll: 0,
                                           random: &random, index: index)
            model = try model.adding(point, mount: mount)
            XCTAssertGreaterThan(try XCTUnwrap(model.pointingUncertainty), 10)
        }
        // The fit itself is perfect on those points: only the uncertainty tells them apart.
        XCTAssertLessThan(model.rmsResidual, 0.05)
        // Two points that differ in altitude, or in roll, are enough to tell the effects apart.
        let differentAltitudes = try AlignmentModel.solve(points: [
            try scenario.point(target: HorizontalCoordinate(azimuth: 30, altitude: 20), roll: 0, random: &random, index: 0),
            try scenario.point(target: HorizontalCoordinate(azimuth: 200, altitude: 65), roll: 0, random: &random, index: 1),
        ], mount: mount)
        XCTAssertLessThan(try XCTUnwrap(differentAltitudes.pointingUncertainty), 1.5)
        let differentRolls = try AlignmentModel.solve(points: [
            try scenario.point(target: HorizontalCoordinate(azimuth: 30, altitude: 40), roll: 0, random: &random, index: 0),
            try scenario.point(target: HorizontalCoordinate(azimuth: 200, altitude: 45), roll: 90, random: &random, index: 1),
        ], mount: mount)
        XCTAssertLessThan(try XCTUnwrap(differentRolls.pointingUncertainty), 1.5)
    }

    func testUncertaintyPredictsTheErrorAcrossTheSky() throws {
        // With points centred to within 0.25° (the assumed accuracy), the predicted figure matches the
        // actual root-mean-square error over directions spread evenly over the sky and random rolls.
        var random = PointingTestRandom(seed: 522)
        var predictedSum = 0.0, actualSquares = 0.0
        let scenarios = 400
        for _ in 0..<scenarios {
            let mount = MountProfile.presets[Int(random.nextBits() % UInt64(MountProfile.presets.count))]
            let tilt = random.unitVector() * random.uniform(0, 3)
            let correction = tilt - mount.cameraAxis * mount.cameraAxis.dot(tilt)
            let scenario = AlignmentTestScenario(headingOffset: random.uniform(-30, 30), correction: correction, mount: mount)
            let count = 3 + Int(random.nextBits() % 4)
            let points = try (0..<count).map { index in
                try scenario.point(target: random.horizontal(altitude: 8...72), roll: random.uniform(-45, 45),
                                   noiseDegrees: 0.25, random: &random, index: index)
            }
            let model = try AlignmentModel.solve(points: points, mount: mount)
            predictedSum += try XCTUnwrap(model.pointingUncertainty)
            var squares = 0.0
            for _ in 0..<10 {
                let altitude = AstroMath.degrees(asin(random.uniform(0.05, 0.97))) // evenly spread over the sky
                let probe = try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: altitude),
                                               roll: random.uniform(-180, 180), random: &random).attitude
                let error = error(of: model, scenario: scenario, attitude: probe)
                squares += error * error
            }
            actualSquares += squares / 10
        }
        let predicted = predictedSum / Double(scenarios)
        let actual = (actualSquares / Double(scenarios)).squareRoot()
        XCTAssertEqual(actual / predicted, 1, accuracy: 0.25, "predicted \(predicted)°, actual \(actual)°")
    }

    // MARK: Degenerate input

    func testDegenerateConfigurationsStayFinite() throws {
        var random = PointingTestRandom(seed: 511)
        let mount = MountProfile.backCameraPortrait
        let scenario = AlignmentTestScenario(headingOffset: 30, correction: Vector3(1, 1, 0), mount: mount)
        let target = HorizontalCoordinate(azimuth: 120, altitude: 40)
        let single = try scenario.point(target: target, roll: 0, random: &random)

        // The same point five times.
        let repeated = try AlignmentModel.solve(points: Array(repeating: single, count: 5), mount: mount)
        XCTAssertEqual(repeated.residuals.count, 5)
        XCTAssertLessThan(repeated.rmsResidual, 1e-3) // the weak prior pulls the correction a hair towards zero

        // Contradictory points: one phone attitude, two different targets.
        let contradiction = AlignmentPoint(attitude: single.attitude, target: HorizontalCoordinate(azimuth: 130, altitude: 45),
                                           timestamp: single.timestamp)
        let model = try AlignmentModel.solve(points: [single, contradiction], mount: mount)
        XCTAssertTrue(model.headingOffset.isFinite)
        XCTAssertTrue(model.deviceCorrection.isFinite)
        XCTAssertTrue(model.residuals.allSatisfy { $0.isFinite })
        XCTAssertLessThan(model.deviceCorrection.length, AlignmentModel.maximumDeviceCorrection)

        // Same altitude and roll everywhere: the compass and the pan error cannot be told apart, but the
        // result must still reproduce the points.
        let flat = try (0..<4).map { index in
            try scenario.point(target: HorizontalCoordinate(azimuth: Double(index) * 80, altitude: 30), roll: 0, random: &random, index: index)
        }
        let flatModel = try AlignmentModel.solve(points: flat, mount: mount)
        XCTAssertLessThan(flatModel.rmsResidual, 0.05)
        XCTAssertTrue(flatModel.deviceCorrection.isFinite)
    }

    func testRandomScenariosAlwaysGiveConsistentFiniteModels() throws {
        var random = PointingTestRandom(seed: 512)
        for _ in 0..<300 {
            let mount = MountProfile.presets[Int(random.nextBits() % UInt64(MountProfile.presets.count))]
            let scenario = AlignmentTestScenario(headingOffset: random.uniform(-180, 180),
                                                 correction: random.unitVector() * random.uniform(0, 6), mount: mount)
            let count = Int(random.nextBits() % 6) + 1
            let points = try (0..<count).map { index in
                try scenario.point(target: random.horizontal(altitude: -60...70), roll: random.uniform(-180, 180),
                                   referenceAzimuth: random.uniform(-180, 180), noiseDegrees: random.uniform(0, 0.5),
                                   random: &random, index: index)
            }
            let model = try AlignmentModel.solve(points: points, mount: mount)
            XCTAssertTrue(model.headingOffset.isFinite)
            XCTAssertTrue(abs(model.headingOffset) <= 180)
            XCTAssertTrue(model.deviceCorrection.isFinite)
            XCTAssertEqual(model.residuals.count, count)
            // The reported residuals are what the public pointing code produces.
            for (point, residual) in zip(model.points, model.residuals) {
                let solved = PointingSolution.solve(attitude: point.attitude, mount: mount, alignment: model).boresight
                XCTAssertEqual(residual, solved.angularSeparation(to: point.target), accuracy: 1e-6)
            }
            // One point is always matched exactly.
            if count == 1 { XCTAssertLessThan(model.rmsResidual, 1e-6) }
        }
    }
}

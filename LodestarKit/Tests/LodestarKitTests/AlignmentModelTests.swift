import XCTest
@testable import LodestarKit

final class AlignmentModelTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let mount = MountProfile.backCameraPortrait

    /// A point for a camera that points exactly where the phone says (no errors at all), unless
    /// `reportedAltitudeError` shifts the phone's idea of the altitude.
    private func point(azimuth: Double, altitude: Double, reportedAltitudeError: Double = 0, index: Int = 0,
                       name: String? = nil, mount: MountProfile? = nil) throws -> AlignmentPoint {
        let mount = mount ?? self.mount
        let reported = HorizontalCoordinate(azimuth: azimuth, altitude: altitude + reportedAltitudeError)
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: reported, rollDegrees: 0))
        return AlignmentPoint(attitude: attitude, target: HorizontalCoordinate(azimuth: azimuth, altitude: altitude),
                              timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), name: name)
    }

    // MARK: Identity

    func testIdentityModelDoesNothing() throws {
        let identity = AlignmentModel.identity
        XCTAssertEqual(identity.headingOffset, 0)
        XCTAssertEqual(identity.deviceCorrection, .zero)
        XCTAssertTrue(identity.points.isEmpty)
        XCTAssertFalse(identity.isAligned)
        XCTAssertEqual(identity.rmsResidual, 0)
        XCTAssertEqual(try AlignmentModel.solve(points: [], mount: mount), identity)
        for preset in MountProfile.presets { XCTAssertTrue(identity.isApplicable(to: preset)) }
        Support.assertMatrix(identity.deviceCorrectionMatrix, .identity, accuracy: 1e-15)
    }

    func testModelRecordsTheMountItWasSolvedFor() throws {
        let model = try AlignmentModel.solve(points: [try point(azimuth: 10, altitude: 30)], mount: mount)
        XCTAssertTrue(model.isAligned)
        XCTAssertEqual(model.calibratedMount?.id, mount.id)
        XCTAssertTrue(model.isApplicable(to: mount))
        XCTAssertFalse(model.isApplicable(to: .backCameraLandscapeLeft))
        XCTAssertFalse(model.isApplicable(to: .flatOnTopTopEdgeForward))
        // The same geometry under another name or id is the same mount.
        let sameGeometry = try XCTUnwrap(MountProfile.custom(name: "Mine", cameraAxis: Vector3(0, 0, -1), cameraUp: Vector3(0, 2, 0)))
        XCTAssertTrue(model.isApplicable(to: sameGeometry))
        let tilted = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 0.05, -1), cameraUp: Vector3(0, 1, 0)))
        XCTAssertFalse(model.isApplicable(to: tilted))
    }

    // MARK: Rejection

    func testPointsNearTheZenithOrNadirAreRejected() throws {
        // Target too high (the camera follows it, so the boresight is too).
        XCTAssertThrowsError(try AlignmentModel.solve(points: [try point(azimuth: 0, altitude: 82)], mount: mount)) { error in
            guard case AlignmentError.targetTooHigh(let altitude)? = error as? AlignmentError else { return XCTFail("\(error)") }
            XCTAssertEqual(altitude, 82, accuracy: 1e-9)
        }
        XCTAssertThrowsError(try AlignmentModel.solve(points: [try point(azimuth: 0, altitude: -80.5)], mount: mount)) { error in
            guard case AlignmentError.targetTooHigh? = error as? AlignmentError else { return XCTFail("\(error)") }
        }
        // Target fine, but the phone says the camera looks at 85°.
        let nearZenith = try point(azimuth: 0, altitude: 60, reportedAltitudeError: 25)
        XCTAssertThrowsError(try AlignmentModel.solve(points: [nearZenith], mount: mount)) { error in
            guard case AlignmentError.boresightTooHigh(let altitude)? = error as? AlignmentError else { return XCTFail("\(error)") }
            XCTAssertEqual(altitude, 85, accuracy: 1e-9)
        }
        let nearNadir = try point(azimuth: 0, altitude: -60, reportedAltitudeError: -25)
        XCTAssertThrowsError(try AlignmentModel.solve(points: [nearNadir], mount: mount)) { error in
            guard case AlignmentError.boresightTooHigh? = error as? AlignmentError else { return XCTFail("\(error)") }
        }
        // Just inside the limit.
        XCTAssertNoThrow(try AlignmentModel.solve(points: [try point(azimuth: 0, altitude: 79.9)], mount: mount))
        XCTAssertNoThrow(try AlignmentModel.solve(points: [try point(azimuth: 0, altitude: -79.9)], mount: mount))
        // One bad point spoils the whole set.
        let fine = try point(azimuth: 0, altitude: 30)
        XCTAssertThrowsError(try AlignmentModel.solve(points: [fine, try point(azimuth: 0, altitude: 83)], mount: mount))
    }

    func testNonFiniteTargetsAreRejected() throws {
        let good = try point(azimuth: 10, altitude: 30)
        let bad = AlignmentPoint(attitude: good.attitude, target: HorizontalCoordinate(azimuth: .nan, altitude: 30), timestamp: good.timestamp)
        XCTAssertThrowsError(try AlignmentModel.solve(points: [bad], mount: mount)) { error in
            XCTAssertEqual(error as? AlignmentError, .nonFiniteInput)
        }
        XCTAssertThrowsError(try AlignmentModel.solve(points: [good, bad], mount: mount))
        XCTAssertThrowsError(try AlignmentModel.identity.adding(bad, mount: mount))
    }

    func testImplausibleCorrectionsAreRejected() throws {
        // The phone says 10° altitude, the object is at 70°: a 60° "mount error" means a wrong object
        // was centred or the wrong mount is selected.
        let wrong = try point(azimuth: 0, altitude: 70, reportedAltitudeError: -60)
        XCTAssertThrowsError(try AlignmentModel.solve(points: [wrong], mount: mount)) { error in
            guard case AlignmentError.implausibleCorrection(let degrees)? = error as? AlignmentError else { return XCTFail("\(error)") }
            XCTAssertEqual(degrees, 60, accuracy: 1e-6)
        }
        // 30° is large but possible.
        XCTAssertNoThrow(try AlignmentModel.solve(points: [try point(azimuth: 0, altitude: 60, reportedAltitudeError: -30)], mount: mount))
    }

    func testPointNamesAreLengthCapped() throws {
        let long = try point(azimuth: 0, altitude: 30, name: String(repeating: "N", count: 1000))
        XCTAssertEqual(long.name?.count, 120)
        XCTAssertNil(try point(azimuth: 0, altitude: 30).name)
    }

    // MARK: Managing points

    func testAddingRefitsAndKeepsOnlyTheNewestTwelve() throws {
        var model = AlignmentModel.identity
        for index in 0..<15 {
            let azimuth = Double(index) * 23
            let altitude = 20 + Double(index % 5) * 10
            model = try model.adding(try point(azimuth: azimuth, altitude: altitude, reportedAltitudeError: 1, index: index,
                                               name: "p\(index)"), mount: mount)
            XCTAssertLessThanOrEqual(model.points.count, AlignmentModel.maximumPointCount)
            XCTAssertEqual(model.residuals.count, model.points.count)
        }
        XCTAssertEqual(model.points.count, 12)
        XCTAssertEqual(model.points.first?.name, "p3")
        XCTAssertEqual(model.points.last?.name, "p14")
        // `solve` keeps the newest points of a long list in the same way.
        let all = try (0..<15).map { index in
            try point(azimuth: Double(index) * 23, altitude: 20 + Double(index % 5) * 10, reportedAltitudeError: 1,
                      index: index, name: "p\(index)")
        }
        let direct = try AlignmentModel.solve(points: all, mount: mount)
        XCTAssertEqual(direct.points.map { $0.name }, model.points.map { $0.name })
        XCTAssertEqual(AlignmentModel.maximumPointCount, 12)
    }

    func testAddingAPointForAnotherMountStartsOver() throws {
        let first = try AlignmentModel.solve(points: [try point(azimuth: 10, altitude: 30, index: 0, name: "old")], mount: mount)
        let landscape = MountProfile.backCameraLandscapeLeft
        let added = try first.adding(try point(azimuth: 200, altitude: 40, index: 1, name: "new", mount: landscape), mount: landscape)
        XCTAssertEqual(added.points.map { $0.name }, ["new"])
        XCTAssertEqual(added.calibratedMount?.id, landscape.id)
    }

    func testRemovingAPointRefitsTheRest() throws {
        let good1 = try point(azimuth: 20, altitude: 25, index: 0, name: "a")
        let good2 = try point(azimuth: 140, altitude: 55, index: 1, name: "b")
        // A mistaken point: the camera was not on this object.
        let outlier = try point(azimuth: 260, altitude: 40, reportedAltitudeError: 6, index: 2, name: "oops")
        let model = try AlignmentModel.solve(points: [good1, good2, outlier], mount: mount)
        XCTAssertGreaterThan(model.rmsResidual, 0.5)
        let cleaned = try model.removingPoint(at: 2, mount: mount)
        XCTAssertEqual(cleaned.points.map { $0.name }, ["a", "b"])
        XCTAssertLessThan(cleaned.rmsResidual, 1e-3)
        XCTAssertLessThan(cleaned.deviceCorrection.length, 1e-3)
        XCTAssertEqual(cleaned.headingOffset, 0, accuracy: 1e-3)
        // Out-of-range indices change nothing; removing the last point gives the identity.
        XCTAssertEqual(try model.removingPoint(at: 3, mount: mount), model)
        XCTAssertEqual(try model.removingPoint(at: -1, mount: mount), model)
        let single = try AlignmentModel.solve(points: [good1], mount: mount)
        XCTAssertEqual(try single.removingPoint(at: 0, mount: mount), .identity)
    }

    func testAlignmentBringsTheArrowToZero() throws {
        // The phone reads 10° too far west and 3° too low. Before aligning, guidance to the object is
        // off; after aligning on it, the camera is on target there and guidance is right nearby.
        let target = HorizontalCoordinate(azimuth: 150, altitude: 40)
        let reported = HorizontalCoordinate(azimuth: 140, altitude: 37)
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: reported, rollDegrees: 0))
        var tracker = GuidanceTracker(onTargetThreshold: 0.5)
        let before = try XCTUnwrap(tracker.update(solution: PointingSolution.solve(attitude: attitude, mount: mount), target: target))
        XCTAssertGreaterThan(before.separation, 8)
        let model = try AlignmentModel.identity.adding(
            AlignmentPoint(attitude: attitude, target: target, timestamp: Date(timeIntervalSince1970: 0)), mount: mount)
        tracker.reset()
        let aligned = PointingSolution.solve(attitude: attitude, mount: mount, alignment: model)
        let after = try XCTUnwrap(tracker.update(solution: aligned, target: target))
        XCTAssertLessThan(after.separation, 1e-6)
        XCTAssertEqual(after.state, .onTarget)
    }

    // MARK: Persistence

    func testCodableRoundTripIsExact() throws {
        var random = PointingTestRandom(seed: 601)
        let scenario = AlignmentTestScenario(headingOffset: -23, correction: Vector3(1.2, -0.7, 0), mount: .backCameraLandscapeRight)
        let points = try (0..<4).map { index in
            try scenario.point(target: HorizontalCoordinate(azimuth: random.uniform(0, 360), altitude: 20 + 12 * Double(index)),
                               roll: random.uniform(-30, 30), noiseDegrees: 0.1, random: &random, index: index, name: "Star \(index)")
        }
        let model = try AlignmentModel.solve(points: points, mount: .backCameraLandscapeRight)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AlignmentModel.self, from: data)
        XCTAssertEqual(decoded, model)
        let identity = try JSONDecoder().decode(AlignmentModel.self, from: try JSONEncoder().encode(AlignmentModel.identity))
        XCTAssertEqual(identity, .identity)
    }

    func testDecodingRejectsInconsistentModels() throws {
        let model = try AlignmentModel.solve(points: [try point(azimuth: 10, altitude: 30, reportedAltitudeError: 2),
                                                      try point(azimuth: 120, altitude: 50, reportedAltitudeError: 2, index: 1)], mount: mount)
        let data = try JSONEncoder().encode(model)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        func decode(_ changes: (inout [String: Any]) -> Void) throws -> AlignmentModel {
            var copy = object
            changes(&copy)
            return try JSONDecoder().decode(AlignmentModel.self, from: JSONSerialization.data(withJSONObject: copy))
        }
        XCTAssertNoThrow(try decode { _ in })
        XCTAssertThrowsError(try decode { $0["headingOffset"] = 400.0 })
        XCTAssertThrowsError(try decode { $0["residuals"] = [0.1] })
        XCTAssertThrowsError(try decode { $0["residuals"] = [0.1, -0.2] })
        XCTAssertThrowsError(try decode { $0["pointingUncertainty"] = -1.0 })
        XCTAssertThrowsError(try decode { $0["pointingUncertainty"] = nil }) // an aligned model must say how good it is
        XCTAssertThrowsError(try decode { $0["deviceCorrection"] = ["x": 60.0, "y": 0.0, "z": 0.0] })
        let point = try XCTUnwrap((object["points"] as? [[String: Any]])?.first)
        XCTAssertThrowsError(try decode {
            var bad = point
            bad["target"] = ["azimuth": 400.0, "altitude": 10.0]
            $0["points"] = [bad, bad]
        })
        XCTAssertThrowsError(try decode {
            var bad = point
            bad["target"] = ["azimuth": 40.0, "altitude": 95.0]
            $0["points"] = [bad, bad]
        })
        XCTAssertThrowsError(try decode {
            $0["points"] = Array(repeating: point, count: 13)
            $0["residuals"] = Array(repeating: 0.1, count: 13)
        })
        XCTAssertThrowsError(try decode {
            var bad = point
            bad["attitude"] = ["matrix": ["r0": ["x": 3.0, "y": 0.0, "z": 0.0], "r1": ["x": 0.0, "y": 1.0, "z": 0.0],
                                          "r2": ["x": 0.0, "y": 0.0, "z": 1.0]], "referenceAzimuth": 0.0, "timestamp": 0.0]
            $0["points"] = [bad, bad]
        })
    }
}

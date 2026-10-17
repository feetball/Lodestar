import XCTest
@testable import LodestarKit

final class PointingSolutionTests: XCTestCase {
    private typealias Support = PointingTestSupport

    func testBoresightAndCameraAxesMatchThePhysicalCameraForEveryMount() throws {
        var random = PointingTestRandom(seed: 101)
        for expected in Support.expectedMounts {
            for _ in 0..<200 {
                let boresight = random.horizontal(altitude: -85...85)
                let roll = random.uniform(-180, 180)
                let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
                let psi = random.uniform(-180, 180)
                let attitude = try Support.attitude(mount: expected.mount, frame: frame, referenceAzimuth: psi)
                let solution = PointingSolution.solve(attitude: attitude, mount: expected.mount)

                Support.assertVector(solution.boresightVector, frame.forward, accuracy: 1e-9, expected.mount.id)
                Support.assertVector(solution.cameraUpVector, frame.up, accuracy: 1e-9, expected.mount.id)
                Support.assertVector(solution.cameraRightVector, frame.right, accuracy: 1e-9, expected.mount.id)
                XCTAssertEqual(Support.azimuthDifference(solution.boresight.azimuth, boresight.azimuth), 0, accuracy: 1e-7)
                XCTAssertEqual(solution.boresight.altitude, boresight.altitude, accuracy: 1e-7)
                XCTAssertEqual(Support.azimuthDifference(solution.roll, roll), 0, accuracy: 1e-6, expected.mount.id)

                // The screen's right and up expressed in the world, from the hand-derived table.
                let screenRight = frame.right * expected.screenRight.x + frame.up * expected.screenUp.x
                let screenUp = frame.right * expected.screenRight.y + frame.up * expected.screenUp.y
                Support.assertVector(solution.screenRightVector, screenRight, accuracy: 1e-9, expected.mount.id)
                Support.assertVector(solution.screenUpVector, screenUp, accuracy: 1e-9, expected.mount.id)
            }
        }
    }

    func testSolutionVectorsAreOrthonormalAndRightHanded() throws {
        var random = PointingTestRandom(seed: 102)
        for mount in MountProfile.presets {
            for _ in 0..<100 {
                let attitude = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: random.uniform(-180, 180)))
                let s = PointingSolution.solve(attitude: attitude, mount: mount)
                for vector in [s.boresightVector, s.cameraUpVector, s.cameraRightVector, s.screenRightVector, s.screenUpVector] {
                    XCTAssertEqual(vector.length, 1, accuracy: 1e-12)
                }
                XCTAssertEqual(s.boresightVector.dot(s.cameraUpVector), 0, accuracy: 1e-12)
                XCTAssertEqual(s.boresightVector.dot(s.cameraRightVector), 0, accuracy: 1e-12)
                XCTAssertEqual(s.boresightVector.dot(s.screenRightVector), 0, accuracy: 1e-12)
                XCTAssertEqual(s.boresightVector.dot(s.screenUpVector), 0, accuracy: 1e-12)
                // The photographer looks along the boresight, so right × up points back at them.
                Support.assertVector(s.cameraRightVector.cross(s.cameraUpVector), s.boresightVector * -1, accuracy: 1e-12)
                Support.assertVector(s.screenRightVector.cross(s.screenUpVector), s.boresightVector * -1, accuracy: 1e-12)
                Support.assertVector(s.boresightVector, HorizontalCoordinate(vector: s.boresightVector).unitVector, accuracy: 1e-12)
            }
        }
    }

    func testRollIsPositiveWhenTheRightSideIsLower() throws {
        let boresight = HorizontalCoordinate(azimuth: 120, altitude: 25)
        for roll in [-90.0, -10, 0, 10, 45, 90, 170] {
            let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
            // The helper itself must obey the physical statement: clockwise means the right side dips.
            if roll > 0 { XCTAssertLessThan(frame.right.z, 0) }
            if roll < 0 { XCTAssertGreaterThan(frame.right.z, 0) }
            let attitude = try Support.attitude(mount: .backCameraPortrait, frame: frame)
            XCTAssertEqual(PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait).roll, roll, accuracy: 1e-8)
        }
        // Level: the camera's right side is horizontal; turned 20° clockwise it dips below the horizon.
        let level = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 0, altitude: 0), rollDegrees: 0)
        Support.assertVector(level.right, Vector3(1, 0, 0), accuracy: 1e-15)
        Support.assertVector(level.up, Vector3(0, 0, 1), accuracy: 1e-15)
        let rolled = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 0, altitude: 0), rollDegrees: 20)
        XCTAssertLessThan(rolled.right.z, 0)
        XCTAssertGreaterThan(rolled.up.x, 0)
    }

    func testRollIsZeroAtTheZenithAndNadir() throws {
        for altitude in [90.0, -90, 89.99999, -89.99999] {
            let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 33, altitude: altitude), rollDegrees: 0)
            let attitude = try Support.attitude(mount: .backCameraPortrait, frame: frame)
            let solution = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
            XCTAssertEqual(solution.roll, 0, accuracy: 1e-12, "altitude \(altitude)")
            XCTAssertTrue(solution.cameraUpVector.isFinite)
        }
    }

    func testHeadingOffsetTurnsTheWorldAboutTheVertical() throws {
        var random = PointingTestRandom(seed: 103)
        for _ in 0..<100 {
            let frame = Support.cameraFrame(boresight: random.horizontal(altitude: -80...80), rollDegrees: random.uniform(-90, 90))
            let attitude = try Support.attitude(mount: .backCameraLandscapeLeft, frame: frame, referenceAzimuth: random.uniform(-180, 180))
            let offset = random.uniform(-180, 180)
            let alignment = AlignmentModel(headingOffset: offset, deviceCorrection: .zero, points: [], residuals: [],
                                           pointingUncertainty: nil, calibratedMount: nil)
            let plain = PointingSolution.solve(attitude: attitude, mount: .backCameraLandscapeLeft)
            let corrected = PointingSolution.solve(attitude: attitude, mount: .backCameraLandscapeLeft, alignment: alignment)
            XCTAssertEqual(Support.azimuthDifference(corrected.boresight.azimuth, plain.boresight.azimuth + offset), 0, accuracy: 1e-9)
            XCTAssertEqual(corrected.boresight.altitude, plain.boresight.altitude, accuracy: 1e-9)
            XCTAssertEqual(corrected.roll, plain.roll, accuracy: 1e-7)
            Support.assertVector(corrected.cameraUpVector, PointingMath.yawed(plain.cameraUpVector, byAzimuth: offset), accuracy: 1e-9)
            Support.assertVector(corrected.cameraRightVector, PointingMath.yawed(plain.cameraRightVector, byAzimuth: offset), accuracy: 1e-9)
        }
    }

    func testDeviceCorrectionTurnsTheCameraAxisInTheDeviceFrame() throws {
        // Upright portrait phone facing north.
        let attitude = try Support.attitude(deviceX: Vector3(1, 0, 0), deviceY: Vector3(0, 0, 1), deviceZ: Vector3(0, -1, 0))
        let mount = MountProfile.backCameraPortrait
        func solution(_ correction: Vector3) -> PointingSolution {
            let alignment = AlignmentModel(headingOffset: 0, deviceCorrection: correction, points: [], residuals: [],
                                           pointingUncertainty: nil, calibratedMount: nil)
            return PointingSolution.solve(attitude: attitude, mount: mount, alignment: alignment)
        }
        // About the camera's right axis (device x): the lens tilts up.
        let tilt = solution(Vector3(2, 0, 0))
        XCTAssertEqual(tilt.boresight.altitude, 2, accuracy: 1e-9)
        XCTAssertEqual(Support.azimuthDifference(tilt.boresight.azimuth, 0), 0, accuracy: 1e-9)
        // About the camera's up axis (device y): the lens turns to the left.
        let pan = solution(Vector3(0, 2, 0))
        XCTAssertEqual(Support.azimuthDifference(pan.boresight.azimuth, -2), 0, accuracy: 1e-9)
        XCTAssertEqual(pan.boresight.altitude, 0, accuracy: 1e-9)
        // About the optical axis (device z): the picture turns, the lens does not move. Positive
        // rotation about +z is counter-clockwise for the photographer, i.e. negative roll.
        let twist = solution(Vector3(0, 0, 2))
        XCTAssertEqual(twist.boresight.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(Support.azimuthDifference(twist.boresight.azimuth, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(twist.roll, -2, accuracy: 1e-9)
    }

    func testAlignmentSolvedForAnotherMountIsIgnored() throws {
        let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 200, altitude: 35), rollDegrees: 0)
        let attitude = try Support.attitude(mount: .backCameraPortrait, frame: frame)
        let alignment = AlignmentModel(headingOffset: 25, deviceCorrection: Vector3(3, 0, 0), points: [], residuals: [],
                                       pointingUncertainty: nil, calibratedMount: .backCameraLandscapeLeft)
        XCTAssertFalse(alignment.isApplicable(to: .backCameraPortrait))
        XCTAssertTrue(alignment.isApplicable(to: .backCameraLandscapeLeft))
        let ignored = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait, alignment: alignment)
        let plain = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
        XCTAssertEqual(ignored, plain)
        // The identity applies to every mount.
        XCTAssertTrue(AlignmentModel.identity.isApplicable(to: .flatOnTopTopEdgeBack))
    }

    func testSolutionFollowsThePhoneWhenItIsRotatedOnTheTripod() throws {
        // Pan a level camera through a full turn: azimuth follows, altitude and roll stay put.
        for step in 0..<36 {
            let azimuth = Double(step) * 10
            let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: azimuth, altitude: 15), rollDegrees: 0)
            let attitude = try Support.attitude(mount: .flatOnTopTopEdgeForward, frame: frame, referenceAzimuth: 40)
            let solution = PointingSolution.solve(attitude: attitude, mount: .flatOnTopTopEdgeForward)
            XCTAssertEqual(Support.azimuthDifference(solution.boresight.azimuth, azimuth), 0, accuracy: 1e-9)
            XCTAssertEqual(solution.boresight.altitude, 15, accuracy: 1e-9)
            XCTAssertEqual(solution.roll, 0, accuracy: 1e-8)
        }
    }
}

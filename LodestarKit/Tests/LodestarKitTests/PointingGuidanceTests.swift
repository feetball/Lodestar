import XCTest
@testable import LodestarKit

final class PointingGuidanceTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private func solution(_ mount: MountProfile, boresight: HorizontalCoordinate, roll: Double = 0,
                          referenceAzimuth: Double = 0) throws -> PointingSolution {
        let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
        let attitude = try Support.attitude(mount: mount, frame: frame, referenceAzimuth: referenceAzimuth)
        return PointingSolution.solve(attitude: attitude, mount: mount)
    }

    private func guidance(_ solution: PointingSolution, to target: HorizontalCoordinate, threshold: Double = 0.5) throws -> Guidance {
        var tracker = GuidanceTracker(onTargetThreshold: threshold)
        return try XCTUnwrap(tracker.update(solution: solution, target: target))
    }

    /// The angle of `a` relative to `b`, wrapped to (−π, π].
    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        AstroMath.radians(AstroMath.normalizeSignedDegrees(AstroMath.degrees(a - b)))
    }

    // MARK: On target

    func testPointingExactlyAtTheTargetIsOnTarget() throws {
        var random = PointingTestRandom(seed: 201)
        for mount in MountProfile.presets {
            for _ in 0..<100 {
                let target = random.horizontal(altitude: -60...80)
                let s = try solution(mount, boresight: target, roll: random.uniform(-180, 180), referenceAzimuth: random.uniform(-180, 180))
                let g = try guidance(s, to: target)
                XCTAssertEqual(g.separation, 0, accuracy: 1e-6)
                XCTAssertEqual(g.panDelta, 0, accuracy: 1e-6)
                XCTAssertEqual(g.tiltDelta, 0, accuracy: 1e-6)
                XCTAssertEqual(g.state, .onTarget)
                XCTAssertTrue(g.isTargetInFront)
            }
        }
    }

    func testSeparationIsTheGreatCircleDistance() throws {
        var random = PointingTestRandom(seed: 202)
        for _ in 0..<200 {
            let boresight = random.horizontal(altitude: -80...80)
            let target = random.horizontal()
            let s = try solution(.backCameraPortrait, boresight: boresight, roll: random.uniform(-90, 90))
            XCTAssertEqual(try guidance(s, to: target).separation, boresight.angularSeparation(to: target), accuracy: 1e-6)
        }
    }

    // MARK: Pan, tilt and the arrow for a level camera

    func testTargetFiveDegreesEastAtTwentyDegreesAltitude() throws {
        let boresight = HorizontalCoordinate(azimuth: 100, altitude: 20)
        for mount in [MountProfile.backCameraPortrait, .flatOnTopTopEdgeForward] {
            let s = try solution(mount, boresight: boresight)
            let g = try guidance(s, to: HorizontalCoordinate(azimuth: 105, altitude: 20))
            XCTAssertEqual(g.panDelta, 5, accuracy: 1e-9)
            XCTAssertEqual(g.tiltDelta, 0, accuracy: 1e-9)
            // Two points at equal altitude: the great circle between them bulges slightly upwards.
            XCTAssertEqual(g.arrowAngle, 0, accuracy: 0.03, mount.id)
            XCTAssertGreaterThan(g.arrowAngle, 0)
            XCTAssertEqual(g.separation, 5 * cos(AstroMath.radians(20)), accuracy: 0.02)
        }
    }

    func testTargetThreeDegreesHigherPointsTheArrowUp() throws {
        let boresight = HorizontalCoordinate(azimuth: 250, altitude: 30)
        for mount in [MountProfile.backCameraPortrait, .flatOnTopTopEdgeForward] {
            let s = try solution(mount, boresight: boresight)
            let g = try guidance(s, to: HorizontalCoordinate(azimuth: 250, altitude: 33))
            XCTAssertEqual(g.tiltDelta, 3, accuracy: 1e-9)
            XCTAssertEqual(g.panDelta, 0, accuracy: 1e-9)
            XCTAssertEqual(g.arrowAngle, Double.pi / 2, accuracy: 1e-9, mount.id)
            XCTAssertEqual(g.separation, 3, accuracy: 1e-9)
        }
    }

    func testArrowExamplesForEveryMount() throws {
        // A level camera facing north (roll 0). Arrow angles in the phone's screen axes (0 = right edge,
        // π/2 = top edge), written out by hand from how each mount sits on the camera:
        //  - portrait:           the camera's right is the right edge, its up the top edge;
        //  - upside down:        both reversed;
        //  - landscape (top edge left): the camera's up is the right edge, its right the bottom edge;
        //  - landscape (top edge right): the camera's up is the left edge, its right the top edge;
        //  - flat on top:        the camera's right is the right edge and tilting up is drawn towards the top edge.
        let half = Double.pi / 2
        let expectations: [(MountProfile, east: Double, up: Double)] = [
            (.backCameraPortrait, 0, half),
            (.backCameraPortraitUpsideDown, Double.pi, -half),
            (.backCameraLandscapeLeft, -half, 0),
            (.backCameraLandscapeRight, half, Double.pi),
            (.flatOnTopTopEdgeForward, 0, half),
            (.flatOnTopTopEdgeBack, Double.pi, -half),
        ]
        let boresight = HorizontalCoordinate(azimuth: 0, altitude: 0)
        for (mount, east, up) in expectations {
            let s = try solution(mount, boresight: boresight)
            let towardsEast = try guidance(s, to: HorizontalCoordinate(azimuth: 4, altitude: 0))
            XCTAssertEqual(angleDifference(towardsEast.arrowAngle, east), 0, accuracy: 1e-9, "\(mount.id) east")
            XCTAssertEqual(towardsEast.panDelta, 4, accuracy: 1e-9)
            let towardsUp = try guidance(s, to: HorizontalCoordinate(azimuth: 0, altitude: 4))
            XCTAssertEqual(angleDifference(towardsUp.arrowAngle, up), 0, accuracy: 1e-9, "\(mount.id) up")
            XCTAssertEqual(towardsUp.tiltDelta, 4, accuracy: 1e-9)
        }
    }

    func testArrowPointsLeftAndDownForTargetsToTheLeftAndBelow() throws {
        let boresight = HorizontalCoordinate(azimuth: 10, altitude: 0)
        let s = try solution(.backCameraPortrait, boresight: boresight)
        let left = try guidance(s, to: HorizontalCoordinate(azimuth: 5, altitude: 0))
        XCTAssertEqual(left.panDelta, -5, accuracy: 1e-9)
        XCTAssertEqual(abs(left.arrowAngle), Double.pi, accuracy: 1e-9)
        let below = try guidance(s, to: HorizontalCoordinate(azimuth: 10, altitude: -4))
        XCTAssertEqual(below.tiltDelta, -4, accuracy: 1e-9)
        XCTAssertEqual(below.arrowAngle, -Double.pi / 2, accuracy: 1e-9)
        let right = try guidance(s, to: HorizontalCoordinate(azimuth: 14, altitude: 0))
        XCTAssertEqual(right.arrowAngle, 0, accuracy: 1e-9)
    }

    func testSmallOffsetsGivePanTiltAndArrowThatAgree() throws {
        var random = PointingTestRandom(seed: 203)
        for mount in [MountProfile.backCameraPortrait, .flatOnTopTopEdgeForward] {
            for _ in 0..<200 {
                let boresight = random.horizontal(altitude: -50...60)
                let s = try solution(mount, boresight: boresight)
                let target = HorizontalCoordinate(azimuth: boresight.azimuth + random.uniform(-2, 2),
                                                  altitude: boresight.altitude + random.uniform(-2, 2))
                let g = try guidance(s, to: target)
                let eastward = g.panDelta * cos(AstroMath.radians(boresight.altitude))
                // Level camera: screen right is east-ish, screen up is up.
                let expected = atan2(g.tiltDelta, eastward)
                if hypot(eastward, g.tiltDelta) > 0.3 {
                    XCTAssertEqual(angleDifference(g.arrowAngle, expected), 0, accuracy: 0.05)
                }
                // Panning right always means a rightward arrow (the east component of the tangent has
                // the sign of the azimuth difference).
                XCTAssertGreaterThan(g.panDelta * cos(g.arrowAngle), -1e-9)
            }
        }
    }

    // MARK: Every mount, every roll

    func testArrowFollowsTheMountMappingForAnyRollAndDirection() throws {
        var random = PointingTestRandom(seed: 204)
        for expected in Support.expectedMounts {
            for _ in 0..<300 {
                let boresight = random.horizontal(altitude: -70...80)
                let roll = random.uniform(-180, 180)
                let s = try solution(expected.mount, boresight: boresight, roll: roll, referenceAzimuth: random.uniform(-180, 180))
                // A target at angle `distance` along the direction `phi` of the picture (0 = camera right,
                // 90° = camera up), written in the camera's own axes.
                let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
                let phi = random.uniform(-180, 180)
                let distance = random.uniform(0.01, 170)
                let direction = frame.right * cos(AstroMath.radians(phi)) + frame.up * sin(AstroMath.radians(phi))
                let targetVector = frame.forward * cos(AstroMath.radians(distance)) + direction * sin(AstroMath.radians(distance))
                let g = try guidance(s, to: HorizontalCoordinate(vector: targetVector))
                // The mapping table says where the camera's right/up are drawn on the screen.
                let onScreen = expected.screenRight * cos(AstroMath.radians(phi)) + expected.screenUp * sin(AstroMath.radians(phi))
                XCTAssertEqual(angleDifference(g.arrowAngle, atan2(onScreen.y, onScreen.x)), 0, accuracy: 1e-6,
                               "\(expected.mount.id) roll \(roll) φ \(phi)")
                XCTAssertEqual(g.separation, distance, accuracy: 1e-6)
            }
        }
    }

    func testArrowOfABackCameraMountIsTheDirectionToMoveTheCameraOnTheScreen() throws {
        // Rotate the phone slightly about the in-plane device axis that moves the back camera towards the
        // arrow's direction on the screen: the separation must shrink by the size of the rotation.
        var random = PointingTestRandom(seed: 205)
        let backCameraMounts: [MountProfile] = [.backCameraPortrait, .backCameraPortraitUpsideDown,
                                                .backCameraLandscapeLeft, .backCameraLandscapeRight]
        let step = 0.05
        for mount in backCameraMounts {
            for _ in 0..<200 {
                let boresight = random.horizontal(altitude: -60...70)
                let roll = random.uniform(-180, 180)
                let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
                let attitude = try Support.attitude(mount: mount, frame: frame, referenceAzimuth: random.uniform(-180, 180))
                let target = random.horizontal(altitude: -60...80)
                let before = PointingSolution.solve(attitude: attitude, mount: mount)
                let separation = boresight.angularSeparation(to: target)
                guard separation > 3 && separation < 150 else { continue }
                let g = try guidance(before, to: target)

                let arrow = Vector3(cos(g.arrowAngle), sin(g.arrowAngle), 0)
                // Turning the device by +step about n = (sy, −sx, 0) moves its back camera (−z) along (sx, sy, 0).
                let axis = Vector3(arrow.y, -arrow.x, 0)
                let turn = Matrix3.rotation(axis: axis, angleRadians: AstroMath.radians(step))
                let moved = try XCTUnwrap(DeviceAttitude(matrix: turn.transposed * attitude.matrix,
                                                         referenceAzimuth: attitude.referenceAzimuth))
                let after = PointingSolution.solve(attitude: moved, mount: mount)
                let improvement = separation - after.boresight.angularSeparation(to: target)
                XCTAssertEqual(improvement, step, accuracy: 0.05 * step, "\(mount.id) roll \(roll)")
            }
        }
    }

    func testPanAndTiltNumbersMoveATripodHeadOntoTheTarget() throws {
        // Physical meaning of the numbers: panning the head clockwise (seen from above) by `panDelta`
        // and then raising the lens about the horizontal axis across the view by `tiltDelta` puts the
        // camera on the target, whatever the mount and however the camera is rolled.
        var random = PointingTestRandom(seed: 207)
        for mount in MountProfile.presets {
            for _ in 0..<100 {
                let start = random.horizontal(altitude: -50...75)
                let target = random.horizontal(altitude: -50...75)
                let psi = random.uniform(-180, 180)
                let attitude = try Support.attitude(
                    mount: mount, frame: Support.cameraFrame(boresight: start, rollDegrees: random.uniform(-180, 180)),
                    referenceAzimuth: psi)
                let g = try guidance(PointingSolution.solve(attitude: attitude, mount: mount), to: target)

                // The head turns the whole camera: clockwise from above is a negative turn about "up".
                let pan = Matrix3.rotationZ(-AstroMath.radians(g.panDelta))
                let panned = pan * (attitude.deviceToWorld * mount.cameraAxis)
                let level = panned.cross(Vector3(0, 0, 1)).normalized // horizontal, across the view
                let tilt = Matrix3.rotation(axis: level, angleRadians: AstroMath.radians(g.tiltDelta))
                let turn = tilt * pan
                let result = HorizontalCoordinate(vector: turn * (attitude.deviceToWorld * mount.cameraAxis))
                XCTAssertEqual(result.angularSeparation(to: target), 0, accuracy: 1e-7, mount.id)
            }
        }
    }

    func testFollowingTheArrowAlwaysLeadsToTheTarget() throws {
        // A closed loop: at each step the phone is turned by 1° about the device axis that moves its back
        // camera along the arrow on the screen. The separation must fall steadily until the state
        // says "on target" — over the zenith and behind the camera included.
        var random = PointingTestRandom(seed: 206)
        let backCameraMounts: [MountProfile] = [.backCameraPortrait, .backCameraPortraitUpsideDown,
                                                .backCameraLandscapeLeft, .backCameraLandscapeRight]
        for mount in backCameraMounts {
            for _ in 0..<40 {
                let start = random.horizontal(altitude: -30...85)
                let target = random.horizontal(altitude: 0...88)
                var attitude = try Support.attitude(
                    mount: mount, frame: Support.cameraFrame(boresight: start, rollDegrees: random.uniform(-180, 180)),
                    referenceAzimuth: random.uniform(-180, 180))
                var tracker = GuidanceTracker(onTargetThreshold: 0.6)
                let initial = start.angularSeparation(to: target)
                var previous = initial
                var steps = 0
                while true {
                    let g = try XCTUnwrap(tracker.update(solution: PointingSolution.solve(attitude: attitude, mount: mount), target: target))
                    if g.state == .onTarget { break }
                    // One degree per step, plus a little for the last, overshooting step.
                    guard steps <= Int(initial.rounded(.up)) + 2 else {
                        XCTFail("no convergence for \(mount.id) from \(start) to \(target)")
                        break
                    }
                    let axis = Vector3(sin(g.arrowAngle), -cos(g.arrowAngle), 0)
                    let turn = Matrix3.rotation(axis: axis, angleRadians: AstroMath.radians(1))
                    attitude = try XCTUnwrap(DeviceAttitude(matrix: turn.transposed * attitude.matrix,
                                                            referenceAzimuth: attitude.referenceAzimuth))
                    XCTAssertLessThan(g.separation, previous + 1e-9)
                    previous = g.separation
                    steps += 1
                }
            }
        }
    }

    func testArrowAngleIsContinuousAroundTheBoresight() throws {
        for mount in MountProfile.presets {
            let boresight = HorizontalCoordinate(azimuth: 300, altitude: 40)
            let roll = 37.0
            let s = try solution(mount, boresight: boresight, roll: roll)
            let frame = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
            var previous: Double?
            for step in 0...72 {
                let phi = AstroMath.radians(Double(step) * 5)
                let direction = frame.right * cos(phi) + frame.up * sin(phi)
                let radius = AstroMath.radians(4)
                let target = HorizontalCoordinate(vector: frame.forward * cos(radius) + direction * sin(radius))
                let angle = try guidance(s, to: target).arrowAngle
                if let previous {
                    // Moving the target counter-clockwise around the picture turns the arrow the same
                    // way by the same amount (the screen mapping is a proper rotation).
                    XCTAssertEqual(angleDifference(angle, previous), AstroMath.radians(5), accuracy: 1e-6, mount.id)
                }
                previous = angle
            }
        }
    }

    // MARK: Flags

    func testPanDeltaWrapsAcrossNorth() throws {
        let s1 = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 359, altitude: 10))
        XCTAssertEqual(try guidance(s1, to: HorizontalCoordinate(azimuth: 2, altitude: 10)).panDelta, 3, accuracy: 1e-9)
        let s2 = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 2, altitude: 10))
        XCTAssertEqual(try guidance(s2, to: HorizontalCoordinate(azimuth: 359, altitude: 10)).panDelta, -3, accuracy: 1e-9)
        XCTAssertEqual(try guidance(s2, to: HorizontalCoordinate(azimuth: 182, altitude: 10)).panDelta, 180, accuracy: 1e-9)
    }

    func testNearZenithFlag() throws {
        let high = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 88))
        XCTAssertTrue(try guidance(high, to: HorizontalCoordinate(azimuth: 90, altitude: 60)).isNearZenith)
        let low = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 60))
        XCTAssertTrue(try guidance(low, to: HorizontalCoordinate(azimuth: 90, altitude: 86)).isNearZenith)
        XCTAssertFalse(try guidance(low, to: HorizontalCoordinate(azimuth: 90, altitude: 85)).isNearZenith)
        let nadir = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: -87))
        XCTAssertTrue(try guidance(nadir, to: HorizontalCoordinate(azimuth: 0, altitude: 10)).isNearZenith)
        XCTAssertFalse(try guidance(low, to: HorizontalCoordinate(azimuth: 10, altitude: 70)).isNearZenith)
    }

    func testArrowStaysCorrectNearTheZenith() throws {
        // Boresight 2° from the zenith; the target is 3° further along the same meridian (over the
        // zenith). Pan/tilt are unreliable here, the arrow is not: it must still point along the
        // great circle, i.e. up on the screen for a camera whose top points that way.
        let boresight = HorizontalCoordinate(azimuth: 0, altitude: 88)
        let s = try solution(.backCameraPortrait, boresight: boresight, roll: 0)
        let target = HorizontalCoordinate(azimuth: 180, altitude: 89)
        let g = try guidance(s, to: target)
        XCTAssertTrue(g.isNearZenith)
        XCTAssertEqual(g.separation, 3, accuracy: 1e-9)
        XCTAssertEqual(g.arrowAngle, Double.pi / 2, accuracy: 1e-9)
    }

    func testTargetBelowTheHorizon() throws {
        let s = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 5))
        XCTAssertTrue(try guidance(s, to: HorizontalCoordinate(azimuth: 0, altitude: -0.1)).targetBelowHorizon)
        XCTAssertFalse(try guidance(s, to: HorizontalCoordinate(azimuth: 0, altitude: 0)).targetBelowHorizon)
        XCTAssertFalse(try guidance(s, to: HorizontalCoordinate(azimuth: 0, altitude: 30)).targetBelowHorizon)
    }

    func testTargetsBehindTheCamera() throws {
        let boresight = HorizontalCoordinate(azimuth: 40, altitude: 10)
        let s = try solution(.backCameraPortrait, boresight: boresight)
        XCTAssertTrue(try guidance(s, to: HorizontalCoordinate(azimuth: 40 + 89, altitude: 0)).isTargetInFront)
        XCTAssertFalse(try guidance(s, to: HorizontalCoordinate(azimuth: 40 + 100, altitude: 0)).isTargetInFront)
        // Exactly behind: there is no unique way round; the result must still be finite.
        let behind = try guidance(s, to: HorizontalCoordinate(vector: boresight.unitVector * -1))
        XCTAssertFalse(behind.isTargetInFront)
        XCTAssertEqual(behind.separation, 180, accuracy: 1e-6)
        XCTAssertTrue(behind.arrowAngle.isFinite)
        XCTAssertEqual(behind.state, .far)
    }

    // MARK: Tracker

    func testDefaultThresholdIsAQuarterOfTheShortSide() {
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: 54.4, verticalFieldOfView: 37.8), 9.45, accuracy: 1e-12)
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: 20, verticalFieldOfView: 30), 5, accuracy: 1e-12)
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: 3.4, verticalFieldOfView: 2.3), 0.575, accuracy: 1e-12)
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: 2.5, verticalFieldOfView: 1.7), 0.5)
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: .nan, verticalFieldOfView: 30), 0.5)
        XCTAssertEqual(GuidanceTracker.defaultOnTargetThreshold(horizontalFieldOfView: -4, verticalFieldOfView: .infinity), 0.5)
    }

    func testOnTargetHasHysteresis() throws {
        // The target lies on the horizon east of a horizontal camera, so the separation equals Δaz.
        let s = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 0))
        var tracker = GuidanceTracker(onTargetThreshold: 1)
        func state(_ separation: Double) throws -> GuidanceState {
            try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: separation, altitude: 0))).state
        }
        XCTAssertEqual(try state(3), .close)
        XCTAssertEqual(try state(1.2), .close) // inside the hysteresis band but not yet on target
        XCTAssertEqual(try state(0.9), .onTarget)
        XCTAssertEqual(try state(1.2), .onTarget) // stays on target inside the band
        XCTAssertEqual(try state(1.49), .onTarget)
        XCTAssertEqual(try state(1.51), .close) // leaves beyond 1.5 × threshold
        XCTAssertEqual(try state(1.2), .close) // and must get below the threshold again to re-enter
        XCTAssertEqual(try state(0.99), .onTarget)
        XCTAssertEqual(try state(7), .far)
        XCTAssertEqual(try state(0.5), .onTarget)
    }

    func testResetForgetsTheOnTargetState() throws {
        let s = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 0))
        var tracker = GuidanceTracker(onTargetThreshold: 1)
        XCTAssertEqual(try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: 0.5, altitude: 0))).state, .onTarget)
        XCTAssertEqual(try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: 1.2, altitude: 0))).state, .onTarget)
        tracker.reset()
        XCTAssertEqual(try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: 1.2, altitude: 0))).state, .close)
    }

    func testCloseAndFarThresholds() throws {
        let s = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 0))
        func state(_ tracker: inout GuidanceTracker, _ separation: Double) throws -> GuidanceState {
            try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: separation, altitude: 0))).state
        }
        // Default: three times the on-target threshold, at least 5°.
        var small = GuidanceTracker(onTargetThreshold: 1)
        XCTAssertEqual(small.closeThreshold, 5)
        XCTAssertEqual(try state(&small, 4.9), .close)
        XCTAssertEqual(try state(&small, 5.1), .far)
        var wide = GuidanceTracker(onTargetThreshold: 9)
        XCTAssertEqual(wide.closeThreshold, 27)
        XCTAssertEqual(try state(&wide, 26), .close)
        XCTAssertEqual(try state(&wide, 28), .far)
        var custom = GuidanceTracker(onTargetThreshold: 1, closeThreshold: 12)
        XCTAssertEqual(try state(&custom, 11), .close)
        XCTAssertEqual(try state(&custom, 13), .far)
        // A close threshold below the on-target threshold is raised to it.
        XCTAssertEqual(GuidanceTracker(onTargetThreshold: 2, closeThreshold: 1).closeThreshold, 2)
    }

    func testInvalidThresholdsFallBack() {
        for bad in [0.0, -1, .nan, .infinity] {
            XCTAssertEqual(GuidanceTracker(onTargetThreshold: bad).onTargetThreshold, 0.5)
        }
        XCTAssertEqual(GuidanceTracker(onTargetThreshold: 1, closeThreshold: .nan).closeThreshold, 5)
    }

    func testNonFiniteTargetsGiveNoGuidance() throws {
        let s = try solution(.backCameraPortrait, boresight: HorizontalCoordinate(azimuth: 0, altitude: 0))
        var tracker = GuidanceTracker(onTargetThreshold: 1)
        XCTAssertNil(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: .nan, altitude: 10)))
        XCTAssertNil(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: .infinity, altitude: 10)))
        // And the tracker is not disturbed by them.
        XCTAssertEqual(try XCTUnwrap(tracker.update(solution: s, target: HorizontalCoordinate(azimuth: 0.5, altitude: 0))).state, .onTarget)
    }

    func testGuidanceStateRawValuesAreStable() throws {
        XCTAssertEqual(GuidanceState.onTarget.rawValue, "onTarget")
        let data = try JSONEncoder().encode([GuidanceState.onTarget, .close, .far])
        XCTAssertEqual(try JSONDecoder().decode([GuidanceState].self, from: data), [.onTarget, .close, .far])
    }
}

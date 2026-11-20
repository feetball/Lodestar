import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The gyro-lock transfer in `MotionProcessor`: waiting for a steady compass sample, switching to the gyro-only frame,
/// computing that frame's heading from the first steady gyro sample, and the rules that refuse the transfer.
///
/// Geometry (CoreMotion conventions): the matrix `M` satisfies `v_device = M · v_reference`, so its rows are the device
/// axes written in the reference frame (x axis at true azimuth ψ, y 90 degrees counter-clockwise of it, z up). A phone
/// that is upright and looks at true azimuth `a` has, in a frame with x axis at azimuth ψ, the matrix `upright(a - ψ)`.
/// So two frames describe one physical orientation when `ψ₁ + r₁ = ψ₂ + r₂`: the compass frame (known ψ₁) with
/// `upright(r₁)` and the gyro frame with `upright(r₂)` give the gyro frame the heading `ψ₂ = ψ₁ + r₁ - r₂`.
///
/// Timeline used by most tests: samples every 1/16 s (step n is at 1000 + n/16 s). The compass stream is settled and
/// steady for the first time at step 16 (a full second after its first sample); the first gyro-frame sample is step 17
/// and the gyro frame is steady (a quarter second without motion, counted from its first still sample) at step 21.
final class MotionGyroLockTests: XCTestCase {
    // MARK: Fixtures

    private let bothFrames = MotionFrameAvailability(magneticNorth: true, trueNorth: true)
    private let trueNorthOnly = MotionFrameAvailability(magneticNorth: false, trueNorth: true)

    private func stamp(_ step: Int) -> TimeInterval { 1000.0 + Double(step) / 16.0 }

    /// Upright in portrait, back camera `azimuth` degrees clockwise from the reference frame's x axis (rows: right =
    /// (-sin a, -cos a, 0), top = up, screen normal = (-cos a, sin a, 0); gravity in device coordinates is (0, -1, 0)).
    private func upright(_ azimuth: Double) -> Matrix3 {
        let s = sin(azimuth * Double.pi / 180), c = cos(azimuth * Double.pi / 180)
        return Matrix3(rows: Vector3(-s, -c, 0), Vector3(0, 0, 1), Vector3(-c, s, 0))
    }

    /// Lying face up with its top `azimuth` degrees clockwise from the reference frame's x axis (rows: right =
    /// (-sin a, -cos a, 0), top = (cos a, -sin a, 0), screen normal = up; gravity is (0, 0, -1)).
    private func flat(_ azimuth: Double) -> Matrix3 {
        let s = sin(azimuth * Double.pi / 180), c = cos(azimuth * Double.pi / 180)
        return Matrix3(rows: Vector3(-s, -c, 0), Vector3(c, -s, 0), Vector3(0, 0, 1))
    }

    private func makeInput(_ matrix: Matrix3, at timestamp: TimeInterval, speed: Double = 0, yaw: Double = 0,
                           field: Double = 50, accuracy: CompassQuality = .high, gravity: Vector3? = nil) -> MotionInput {
        MotionInput(matrix: matrix, gravity: gravity ?? matrix * Vector3(0, 0, -1), angularSpeed: speed, yawRate: yaw,
                    fieldMicrotesla: field, fieldAccuracy: accuracy, timestamp: timestamp)
    }

    private func cameraAzimuth(_ attitude: DeviceAttitude) -> Double {
        let direction = attitude.deviceToWorld * DeviceAttitude.backCameraAxis
        return AstroMath.atan2Deg(direction.x, direction.y)
    }

    private func azimuthDifference(_ a: Double, _ b: Double) -> Double { AstroMath.normalizeSignedDegrees(a - b) }

    private func reference(_ declination: Double, field: Double = 50) -> MagneticReference {
        MagneticReference(declination: declination, expectedFieldMicrotesla: field)
    }

    /// A processor with gyro lock wanted, running on `availability`, and the request for its compass stream.
    private func armed(_ availability: MotionFrameAvailability, declination: Double? = nil)
        -> (processor: MotionProcessor, request: MotionStreamStart) {
        var p = MotionProcessor()
        if let declination { p.setMagneticReference(reference(declination)) }
        _ = p.setSource(.gyroLock, availability: availability)
        let request = p.start(availability: availability)
        return (p, request)
    }

    /// Feeds still samples of `matrix` on the compass stream at steps `first ... first + 16`. The steady sample is
    /// taken at the last one, the first to follow a full second of the stream's life; nothing is asked before it.
    private func capture(_ p: inout MotionProcessor, request: MotionStreamStart, matrix: Matrix3, from first: Int = 0,
                         field: Double = 50) {
        for step in first..<(first + 16) {
            let early = p.process(makeInput(matrix, at: stamp(step), field: field), streamID: request.id)
            XCTAssertNil(early, "step \(step)")
        }
        let event = p.process(makeInput(matrix, at: stamp(first + 16), field: field), streamID: request.id)
        XCTAssertEqual(event, MotionEvent.compassSteady(stream: request.id))
        XCTAssertEqual(p.snapshot.phase, .compassCaptured)
    }

    /// Captures `compass` at steps 0...16 and switches to the gyro frame; returns the gyro stream's request.
    private func captureAndSwitch(_ p: inout MotionProcessor, request: MotionStreamStart, compass: Matrix3) throws
        -> MotionStreamStart {
        capture(&p, request: request, matrix: compass)
        let gyro = try XCTUnwrap(p.switchToGyroFrame())
        XCTAssertEqual(gyro, MotionStreamStart(stream: .arbitrary, id: request.id + 1))
        XCTAssertEqual(p.snapshot.phase, .awaitingGyro)
        return gyro
    }

    /// Feeds gyro-frame samples at `steps`; they never return an event.
    private func feedGyro(_ p: inout MotionProcessor, id: Int, _ matrix: Matrix3, steps: ClosedRange<Int>,
                          speed: Double = 0, yaw: Double = 0, gravity: Vector3? = nil, field: Double = 50) {
        for step in steps {
            let event = p.process(makeInput(matrix, at: stamp(step), speed: speed, yaw: yaw, field: field, gravity: gravity),
                                  streamID: id)
            XCTAssertNil(event)
        }
    }

    /// Feeds one compass-stream sample per entry of `speeds` (entry n is step `first + n`) and returns the steps at
    /// which a `compassSteady` event came back.
    private func steadySteps(_ p: inout MotionProcessor, id: Int, speeds: [Double], matrix: Matrix3, from first: Int = 0,
                             field: Double = 50, accuracy: CompassQuality = .high) -> [Int] {
        var steps: [Int] = []
        for (offset, speed) in speeds.enumerated() {
            let input = makeInput(matrix, at: stamp(first + offset), speed: speed, field: field, accuracy: accuracy)
            if p.process(input, streamID: id) != nil { steps.append(first + offset) }
        }
        return steps
    }

    // MARK: Waiting for a steady compass sample

    func testTheCompassSampleIsCapturedAfterASettledSecondOfStandingStill() {
        let rig = armed(bothFrames)
        var p = rig.processor
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        let steps = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 40), matrix: upright(40))
        XCTAssertEqual(steps, [16], "one event, at the first sample a full second after the stream began")
        XCTAssertEqual(p.snapshot.phase, .compassCaptured)
    }

    func testNothingIsCapturedBeforeTheStreamHasSettled() {
        let rig = armed(bothFrames)
        var p = rig.processor
        // Steady since the very first sample, yet the first 16 samples (up to 0.9375 s) are too early.
        let steps = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 16), matrix: upright(40))
        XCTAssertEqual(steps, [])
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
    }

    func testMovementBeforeStandingStillDelaysTheCaptureByAQuarterSecond() {
        let rig = armed(bothFrames)
        var p = rig.processor
        let speeds = Array(repeating: 5.0, count: 16) + Array(repeating: 0.0, count: 24)
        let steps = steadySteps(&p, id: rig.request.id, speeds: speeds, matrix: upright(40))
        XCTAssertEqual(steps, [20], "still since step 16, steady (0.25 s) at step 20")
    }

    func testAMovementDuringTheWaitRestartsTheSteadyTimer() {
        let rig = armed(bothFrames)
        var p = rig.processor
        // Would be captured at step 16, but the phone moves at that step; still again from 17, steady at 21.
        let speeds = Array(repeating: 0.0, count: 16) + [5.0] + Array(repeating: 0.0, count: 23)
        let steps = steadySteps(&p, id: rig.request.id, speeds: speeds, matrix: upright(40))
        XCTAssertEqual(steps, [21])
    }

    func testARotationOfExactlyTwoDegreesPerSecondCountsAsMoving() {
        let rig = armed(bothFrames)
        var p = rig.processor
        let speeds = Array(repeating: 2.0, count: 40) + Array(repeating: 1.99, count: 10)
        let steps = steadySteps(&p, id: rig.request.id, speeds: speeds, matrix: upright(40))
        XCTAssertEqual(steps, [44], "2.0 deg/s is not still; 1.99 deg/s is, steady a quarter second later")
    }

    func testAnUncalibratedCompassIsNotCaptured() {
        let rig = armed(bothFrames)
        var p = rig.processor
        let uncalibrated = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 31),
                                       matrix: upright(40), accuracy: .uncalibrated)
        XCTAssertEqual(uncalibrated, [])
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        // The moment the accuracy reaches low, the (long steady, long settled) sample is taken.
        let low = steadySteps(&p, id: rig.request.id, speeds: [0.0], matrix: upright(40), from: 31, accuracy: .low)
        XCTAssertEqual(low, [31])
    }

    func testAPendingCalibrationRequestHoldsBackTheCaptureUntilMediumAccuracy() {
        let rig = armed(bothFrames)
        var p = rig.processor
        p.noteCalibrationRequested(streamID: rig.request.id)
        let held = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 30), matrix: upright(40),
                               accuracy: .low)
        XCTAssertEqual(held, [])
        XCTAssertEqual(p.snapshot.compassQuality, .uncalibrated)
        let cleared = steadySteps(&p, id: rig.request.id, speeds: [0.0], matrix: upright(40), from: 30, accuracy: .medium)
        XCTAssertEqual(cleared, [30])
    }

    func testAFrameWithoutAFieldCanStillBeCaptured() {
        let rig = armed(bothFrames)
        var p = rig.processor
        let steps = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 20), matrix: upright(40),
                                field: 0)
        XCTAssertEqual(steps, [16])
    }

    func testTheCompassSourceNeverAsksForTheTransfer() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        let steps = steadySteps(&p, id: request.id, speeds: Array(repeating: 0.0, count: 40), matrix: upright(40))
        XCTAssertEqual(steps, [])
        XCTAssertEqual(p.snapshot.phase, .inactive)
    }

    func testCapturingWorksOnTheTrueNorthFrameToo() {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let steps = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 20), matrix: upright(40))
        XCTAssertEqual(steps, [16])
    }

    // MARK: The switch

    func testTheSwitchNeedsACapturedSample() {
        var fresh = MotionProcessor()
        XCTAssertNil(fresh.switchToGyroFrame())

        let rig = armed(bothFrames)
        var waiting = rig.processor
        XCTAssertNil(waiting.switchToGyroFrame(), "waiting for the compass")
        feed(&waiting, id: rig.request.id, steps: 0...10)
        XCTAssertNil(waiting.switchToGyroFrame(), "not steady yet")

        var compassOnly = MotionProcessor()
        _ = compassOnly.start(availability: bothFrames)
        XCTAssertNil(compassOnly.switchToGyroFrame())
    }

    private func feed(_ p: inout MotionProcessor, id: Int, steps: ClosedRange<Int>) {
        for step in steps {
            _ = p.process(makeInput(upright(40), at: stamp(step)), streamID: id)
        }
    }

    func testTheSwitchStartsTheGyroOnlyStreamAndRetiresTheCompassStream() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        XCTAssertEqual(p.stream, .arbitrary)
        XCTAssertTrue(p.isCurrent(streamID: gyro.id))
        XCTAssertFalse(p.isCurrent(streamID: rig.request.id))
        XCTAssertNil(p.switchToGyroFrame(), "a second event for the same capture is stale")

        // A compass sample still queued from before the switch is dropped.
        let count = p.sampleCount
        let late = p.process(makeInput(upright(40), at: stamp(17)), streamID: rig.request.id)
        XCTAssertNil(late)
        XCTAssertEqual(p.sampleCount, count)
    }

    func testARestartBetweenTheCaptureAndTheSwitchMakesTheSwitchStale() {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        let restart = p.start(availability: bothFrames)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertNil(p.switchToGyroFrame())
        XCTAssertEqual(p.stream, .magneticNorth)
        XCTAssertTrue(p.isCurrent(streamID: restart.id))
    }

    func testLeavingGyroLockAfterTheCaptureCancelsTheSwitch() {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        XCTAssertNil(p.setSource(.compass, availability: bothFrames))
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertNil(p.switchToGyroFrame())
        XCTAssertEqual(p.stream, .magneticNorth)
    }

    func testTurningMoreThanADegreeBeforeTheSwitchMakesTheCapturedSampleStale() {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        // 8 degrees per second for 1/16 s is half a degree per sample.
        for step in 17...18 {
            _ = p.process(makeInput(upright(40), at: stamp(step), speed: 8, yaw: 8), streamID: rig.request.id)
        }
        XCTAssertEqual(p.snapshot.phase, .compassCaptured, "exactly one degree is still allowed")
        _ = p.process(makeInput(upright(40), at: stamp(19), speed: 8, yaw: 8), streamID: rig.request.id)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass, "1.5 degrees")
        XCTAssertNil(p.switchToGyroFrame())
        // The phone stands still again from step 20: a new sample is captured a quarter second later.
        let steps = steadySteps(&p, id: rig.request.id, speeds: Array(repeating: 0.0, count: 21), matrix: upright(40),
                                from: 20)
        XCTAssertEqual(steps, [24])
    }

    func testTurningTheOtherWayAlsoMakesTheCapturedSampleStale() {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        _ = p.process(makeInput(upright(40), at: stamp(17), speed: 20, yaw: -20), streamID: rig.request.id)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass, "-1.25 degrees")
        XCTAssertNil(p.switchToGyroFrame())
    }

    func testALongGapBetweenCompassSamplesCountsAtTheRateOfTheSampleThatEndsIt() {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        // 9.5 deg/s after a gap of half a second counts for 0.1 s, i.e. 0.95 degrees (not 4.75).
        _ = p.process(makeInput(upright(40), at: stamp(16) + 0.5, speed: 9.5, yaw: 9.5), streamID: rig.request.id)
        XCTAssertEqual(p.snapshot.phase, .compassCaptured)
        _ = p.process(makeInput(upright(40), at: stamp(16) + 1.0, speed: 9.5, yaw: 9.5), streamID: rig.request.id)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass, "0.95 + 0.95 degrees")
    }

    // MARK: A successful transfer

    func testTheGyroFrameContinuesWhereTheCompassFrameWas() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // The gyro frame's x axis points at true azimuth 25: the phone, still looking at 40, is 15 degrees clockwise of it.
        for step in 17...20 {
            _ = p.process(makeInput(upright(15), at: stamp(step)), streamID: gyro.id)
            XCTAssertEqual(p.snapshot.phase, .awaitingGyro, "step \(step): less than a quarter second of standing still")
        }
        _ = p.process(makeInput(upright(15), at: stamp(21)), streamID: gyro.id)
        XCTAssertEqual(p.snapshot.phase, .referenced)

        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.timestamp, stamp(21))
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.attitude), 40), 0, accuracy: 1e-9)
        XCTAssertEqual(sample.attitude, sample.rawAttitude, "the smoother restarts at the transfer")
        XCTAssertEqual(p.snapshot.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.source, .gyroLock)
        XCTAssertEqual(p.snapshot.frameEpoch, 0, "alignments made in the compass frame stay valid")
    }

    func testTheGyroFrameKeepsTheHeadingAsThePhoneTurnsAfterTheTransfer() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        // The phone is panned 60 degrees clockwise: the gyro frame's azimuth stays 25, the camera looks at 100.
        feedGyro(&p, id: gyro.id, upright(75), steps: 40...40, speed: 30)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 100), 0, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.phase, .referenced)
    }

    func testNothingNewIsPublishedWhileTheTransferIsPending() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...20)
        XCTAssertEqual(p.sampleCount, 21)
        // The last compass sample stays published: the phone stood still, so it is still right.
        let latest = try XCTUnwrap(p.latest)
        XCTAssertEqual(latest.timestamp, stamp(16))
        XCTAssertEqual(latest.attitude.referenceAzimuth, 0, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(latest.attitude), 40), 0, accuracy: 1e-9)
        XCTAssertEqual(p.sample(at: stamp(17))?.timestamp, stamp(16))
    }

    func testAFlatPhoneTransfersToo() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        // Top towards azimuth 350 in the true-north frame; the gyro frame's x axis at azimuth 200 sees it at 150.
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: flat(350))
        feedGyro(&p, id: gyro.id, flat(150), steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        let sample = try XCTUnwrap(p.latest)
        // 200 degrees is reported as -160, within (-180, 180].
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, -160, accuracy: 1e-9)
    }

    func testTheHeadingIsFoundAtAnyPhoneAzimuth() throws {
        for (compassAzimuth, gyroHeading) in [(0.0, 90.0), (90.0, -90.0), (270.0, 135.0), (-30.0, -170.0)] {
            let rig = armed(trueNorthOnly)
            var p = rig.processor
            let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(compassAzimuth))
            feedGyro(&p, id: gyro.id, upright(compassAzimuth - gyroHeading), steps: 17...21)
            XCTAssertEqual(p.snapshot.phase, .referenced)
            let sample = try XCTUnwrap(p.latest)
            XCTAssertEqual(azimuthDifference(sample.rawAttitude.referenceAzimuth, gyroHeading), 0, accuracy: 1e-9,
                           "compass \(compassAzimuth), gyro frame \(gyroHeading)")
            XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), compassAzimuth), 0, accuracy: 1e-9)
        }
    }

    func testTheGyroFrameHasNoCompassData() throws {
        let rig = armed(bothFrames, declination: 0)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40), field: 55)
        XCTAssertEqual(p.snapshot.compassQuality, .high)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)
        let gyro = try XCTUnwrap(p.switchToGyroFrame())
        feedGyro(&p, id: gyro.id, upright(40), steps: 17...21, field: 55)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        XCTAssertEqual(p.snapshot.compassQuality, .unavailable)
        XCTAssertNil(p.snapshot.magneticDisturbance)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertNil(sample.magneticFieldMicrotesla)
        XCTAssertEqual(sample.compassQuality, .unavailable)
    }

    // MARK: Transfers and the declination

    func testAKnownDeclinationIsPartOfTheCompassFramesAzimuth() throws {
        let rig = armed(bothFrames, declination: 10)
        var p = rig.processor
        // The phone looks at true azimuth 40 = 30 east of magnetic north + 10 declination.
        capture(&p, request: rig.request, matrix: upright(30))
        let compassSample = try XCTUnwrap(p.latest)
        XCTAssertEqual(compassSample.attitude.referenceAzimuth, 10, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(compassSample.attitude), 40), 0, accuracy: 1e-9)

        let gyro = try XCTUnwrap(p.switchToGyroFrame())
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9, "not 35: the declination counts once")
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 40), 0, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testAChangeOfDeclinationAfterAKnownOneWasUsedDoesNotMoveTheGyroHeading() throws {
        let rig = armed(bothFrames, declination: 10)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(30))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)

        p.setMagneticReference(reference(12))
        feedGyro(&p, id: gyro.id, upright(15), steps: 22...22)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        XCTAssertTrue(p.isCurrent(streamID: gyro.id))
    }

    func testTheTrueNorthFrameNeverAddsADeclination() throws {
        let rig = armed(trueNorthOnly, declination: 10)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)

        p.setMagneticReference(reference(12))
        feedGyro(&p, id: gyro.id, upright(15), steps: 22...22)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testADeclinationThatArrivesAfterTheTransferIsAddedToTheGyroHeading() throws {
        let rig = armed(bothFrames) // declination not known yet
        var p = rig.processor
        // The magnetic frame is taken as true north for now: the phone looks at "30", its truth being 40.
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(30))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        var sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 15, accuracy: 1e-9)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 30), 0, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)

        p.setMagneticReference(reference(10))
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "the heading moves by the declination: alignments are void")
        XCTAssertTrue(p.isCurrent(streamID: gyro.id), "no restart")
        feedGyro(&p, id: gyro.id, upright(15), steps: 22...22)
        sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 40), 0, accuracy: 1e-9)
        XCTAssertEqual(sample.attitude, sample.rawAttitude, "the smoother restarts with the new heading")

        // It is added once only.
        p.setMagneticReference(reference(12))
        feedGyro(&p, id: gyro.id, upright(15), steps: 23...23)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testADeclinationThatArrivesWhileTheGyroHeadingIsPendingIsAddedWhenItIsFound() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(30))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17)
        p.setMagneticReference(reference(10))
        XCTAssertEqual(p.snapshot.frameEpoch, 0, "no heading was transferred yet that could be wrong")
        feedGyro(&p, id: gyro.id, upright(15), steps: 18...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)

        p.setMagneticReference(reference(12))
        feedGyro(&p, id: gyro.id, upright(15), steps: 22...22)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9, "added once only")
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testADeclinationThatArrivesBetweenTheCaptureAndTheSwitchIsAddedWhenItIsFound() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(30))
        p.setMagneticReference(reference(10))
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "the running magnetic frame's reference azimuth steps from 0 to 10")
        let gyro = try XCTUnwrap(p.switchToGyroFrame())
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    // MARK: Refused transfers

    func testATiltOfLessThanThreeDegreesIsTolerated() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // Tipped 2.9 degrees about the device's x axis (a horizontal axis): gravity moves by 2.9 degrees, the heading
        // found from the two frames does not change.
        let tilted = Matrix3.rotationX(AstroMath.radians(2.9)) * upright(15)
        feedGyro(&p, id: gyro.id, tilted, steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-6)
    }

    func testATiltOfMoreThanThreeDegreesRefusesTheTransfer() throws {
        for tilt in [3.1, -3.1] {
            let rig = armed(trueNorthOnly)
            var p = rig.processor
            let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
            let tilted = Matrix3.rotationX(AstroMath.radians(tilt)) * upright(15)
            feedGyro(&p, id: gyro.id, tilted, steps: 17...20)
            XCTAssertEqual(p.snapshot.phase, .awaitingGyro, "tilt \(tilt): not steady yet")
            feedGyro(&p, id: gyro.id, tilted, steps: 21...21)
            XCTAssertEqual(p.snapshot.phase, .unreferenced, "tilt \(tilt)")
            XCTAssertEqual(p.snapshot.frameEpoch, 1, "tilt \(tilt)")
        }
    }

    func testMatricesThatDisagreeAboutTheVerticalByMoreThanTenDegreesRefuseTheTransfer() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // The gravity vectors agree, but the matrix is 15 degrees off: the two attitudes cannot be one orientation.
        let tilted = Matrix3.rotationX(AstroMath.radians(15)) * upright(15)
        feedGyro(&p, id: gyro.id, tilted, steps: 17...21, gravity: Vector3(0, -1, 0))
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testAPhoneThatKeepsMovingForMoreThanTwoSecondsIsRefused() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // The clock starts with the first gyro sample (step 17); step 49 is exactly two seconds later.
        for step in 17...49 {
            feedGyro(&p, id: gyro.id, upright(15), steps: step...step, speed: 10)
            XCTAssertEqual(p.snapshot.phase, .awaitingGyro, "step \(step)")
        }
        feedGyro(&p, id: gyro.id, upright(15), steps: 50...50, speed: 10)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        // The gyro frame carries on without a heading, starting at the sample that gave up.
        let latest = try XCTUnwrap(p.latest)
        XCTAssertEqual(latest.timestamp, stamp(50))
        XCTAssertEqual(latest.attitude.referenceAzimuth, 0, accuracy: 1e-12)
    }

    func testAPhoneThatSettlesWithinTwoSecondsIsAccepted() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...40, speed: 10)
        feedGyro(&p, id: gyro.id, upright(15), steps: 41...44)
        XCTAssertEqual(p.snapshot.phase, .awaitingGyro)
        feedGyro(&p, id: gyro.id, upright(15), steps: 45...45)
        XCTAssertEqual(p.snapshot.phase, .referenced, "steady for a quarter second, 1.75 s after the first gyro sample")
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
    }

    func testAPhoneThatSettlesTooLateIsRefused() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...47, speed: 10)
        feedGyro(&p, id: gyro.id, upright(15), steps: 48...49)
        XCTAssertEqual(p.snapshot.phase, .awaitingGyro)
        // Step 50 is 2.0625 s after the first gyro sample; the phone has stood still for only 0.125 s.
        feedGyro(&p, id: gyro.id, upright(15), steps: 50...50)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
    }

    func testTurningMoreThanADegreeAboutTheVerticalRefusesTheTransfer() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // 20 degrees per second for 1/16 s: 1.25 degrees.
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17, speed: 20, yaw: 20)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testTurningTheOtherWayAboutTheVerticalRefusesTheTransfer() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17, speed: 20, yaw: -20)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
    }

    func testTurningExactlyOneDegreeIsStillAccepted() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        // 16 degrees per second for 1/16 s: exactly one degree; then still from step 18, steady at step 22.
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17, speed: 16, yaw: 16)
        feedGyro(&p, id: gyro.id, upright(15), steps: 18...21)
        XCTAssertEqual(p.snapshot.phase, .awaitingGyro)
        feedGyro(&p, id: gyro.id, upright(15), steps: 22...22)
        XCTAssertEqual(p.snapshot.phase, .referenced)
    }

    func testTheTurnSinceTheCaptureCountsAgainstTheTransfer() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        capture(&p, request: rig.request, matrix: upright(40))
        // 0.75 degrees on the compass stream after the capture, before the switch...
        _ = p.process(makeInput(upright(40), at: stamp(17), speed: 12, yaw: 12), streamID: rig.request.id)
        XCTAssertEqual(p.snapshot.phase, .compassCaptured)
        let gyro = try XCTUnwrap(p.switchToGyroFrame())
        // ...and another 0.75 on the gyro stream make 1.5.
        feedGyro(&p, id: gyro.id, upright(15), steps: 18...18, speed: 12, yaw: 12)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testALongGapWhileTheFramesSwitchCountsAtTheRateOfTheSampleThatEndsIt() throws {
        // The first gyro sample comes half a second after the capture (step 24): 12 deg/s counts for 0.1 s = 1.2 degrees.
        let refused = armed(trueNorthOnly)
        var p = refused.processor
        let refusedGyro = try captureAndSwitch(&p, request: refused.request, compass: upright(40))
        feedGyro(&p, id: refusedGyro.id, upright(15), steps: 24...24, speed: 12, yaw: 12)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)

        // 9 deg/s counts for 0.9 degrees (not 4.5): accepted once the phone has been still for a quarter second.
        let accepted = armed(trueNorthOnly)
        var q = accepted.processor
        let acceptedGyro = try captureAndSwitch(&q, request: accepted.request, compass: upright(40))
        feedGyro(&q, id: acceptedGyro.id, upright(15), steps: 24...24, speed: 9, yaw: 9)
        XCTAssertEqual(q.snapshot.phase, .awaitingGyro)
        feedGyro(&q, id: acceptedGyro.id, upright(15), steps: 25...29)
        XCTAssertEqual(q.snapshot.phase, .referenced)
        XCTAssertEqual(try XCTUnwrap(q.latest).rawAttitude.referenceAzimuth, 25, accuracy: 1e-9)
    }

    func testAFailedTransferLeavesTheGyroFrameRunningWithoutAHeading() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(30))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17, speed: 20, yaw: 20)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)

        // There is no retry: the frame carries on at azimuth 0, whatever the phone does.
        feedGyro(&p, id: gyro.id, upright(15), steps: 18...120)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        let latest = try XCTUnwrap(p.latest)
        XCTAssertEqual(latest.timestamp, stamp(120))
        XCTAssertEqual(latest.attitude.referenceAzimuth, 0, accuracy: 1e-12)

        // A declination that arrives now has no heading to correct.
        p.setMagneticReference(reference(10))
        feedGyro(&p, id: gyro.id, upright(15), steps: 121...121)
        XCTAssertEqual(try XCTUnwrap(p.latest).attitude.referenceAzimuth, 0, accuracy: 1e-12)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
    }

    // MARK: Leaving gyro lock and restarting

    func testLeavingGyroLockReturnsToTheCompassFrameAndDropsTheHeading() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)

        let back = try XCTUnwrap(p.setSource(.compass, availability: bothFrames))
        XCTAssertEqual(back, MotionStreamStart(stream: .magneticNorth, id: gyro.id + 1))
        XCTAssertEqual(p.source, .compass)
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "the gyro heading, and the alignments made in it, are gone")
        XCTAssertFalse(p.isCurrent(streamID: gyro.id))
        let late = p.process(makeInput(upright(15), at: stamp(22)), streamID: gyro.id)
        XCTAssertNil(late)
        // The compass frame publishes at its own reference azimuth again.
        _ = p.process(makeInput(upright(40), at: stamp(30)), streamID: back.id)
        XCTAssertEqual(try XCTUnwrap(p.latest).attitude.referenceAzimuth, 0, accuracy: 1e-12)
    }

    func testLeavingGyroLockOnATrueNorthDeviceReturnsToTheTrueNorthFrame() throws {
        let rig = armed(trueNorthOnly)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        let back = p.setSource(.compass, availability: trueNorthOnly)
        XCTAssertEqual(back, MotionStreamStart(stream: .trueNorth, id: gyro.id + 1))
    }

    func testALaterTransferStartsCleanAfterLeavingGyroLock() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(30))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21) // declination unknown: the heading lacks it
        XCTAssertEqual(p.snapshot.phase, .referenced)

        let back = try XCTUnwrap(p.setSource(.compass, availability: bothFrames))
        p.setMagneticReference(reference(10))
        XCTAssertNil(p.setSource(.gyroLock, availability: bothFrames))
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        let epochBeforeTransfer = p.snapshot.frameEpoch

        // The phone now looks at true azimuth 100 = 90 east of magnetic north + 10 declination; the new gyro frame's
        // x axis points at azimuth -50, so the phone is 150 degrees clockwise of it.
        capture(&p, request: back, matrix: upright(90), from: 40)
        let second = try XCTUnwrap(p.switchToGyroFrame())
        feedGyro(&p, id: second.id, upright(150), steps: 57...61)
        XCTAssertEqual(p.snapshot.phase, .referenced)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, -50, accuracy: 1e-9)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 100), 0, accuracy: 1e-9)
        XCTAssertEqual(p.snapshot.frameEpoch, epochBeforeTransfer)

        // The declination is part of that heading; a new value does not move it.
        p.setMagneticReference(reference(12))
        feedGyro(&p, id: second.id, upright(150), steps: 62...62)
        XCTAssertEqual(try XCTUnwrap(p.latest).rawAttitude.referenceAzimuth, -50, accuracy: 1e-9)
    }

    func testRestartingWhileTheGyroFrameCarriesAHeadingStartsANewEpoch() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        let restart = p.start(availability: bothFrames)
        XCTAssertEqual(restart.stream, .magneticNorth)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass, "gyro lock begins again from the compass frame")
        XCTAssertNil(p.switchToGyroFrame())
    }

    func testRestartingAfterAFailedTransferStartsAnotherEpoch() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...17, speed: 20, yaw: 20)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        _ = p.start(availability: bothFrames)
        XCTAssertEqual(p.snapshot.frameEpoch, 2)
    }

    func testStoppingWhileTheGyroFrameCarriesAHeadingStartsANewEpoch() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...21)
        p.stop()
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertNil(p.stream)
        XCTAssertEqual(p.snapshot.source, .gyroLock)
    }

    func testStoppingWhileTheHeadingIsStillPendingKeepsTheEpoch() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...19)
        p.stop()
        XCTAssertEqual(p.snapshot.frameEpoch, 0, "no heading was transferred, so no alignment can be lost")
        XCTAssertEqual(p.snapshot.sampleCount, 0)
    }

    func testRestartingWhileTheHeadingIsStillPendingKeepsTheEpoch() throws {
        let rig = armed(bothFrames)
        var p = rig.processor
        let gyro = try captureAndSwitch(&p, request: rig.request, compass: upright(40))
        feedGyro(&p, id: gyro.id, upright(15), steps: 17...19)
        _ = p.start(availability: bothFrames)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
    }
}

import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `MotionProcessor` configuration and lifecycle: frame choice, start/stop, stream ids, smoothing, the magnetic
/// declination and the heading source. (The gyro-lock transfer itself is in `MotionGyroLockTests`.)
///
/// Geometry (CoreMotion conventions): the matrix `M` satisfies `v_device = M · v_reference`, so its rows are the device
/// axes written in the reference frame (x north, y west, z up). The back camera looks along the device's -z axis.
final class MotionProcessorConfigurationTests: XCTestCase {
    // MARK: Fixtures

    private let bothFrames = MotionFrameAvailability(magneticNorth: true, trueNorth: true)
    private let magneticOnly = MotionFrameAvailability(magneticNorth: true, trueNorth: false)
    private let trueNorthOnly = MotionFrameAvailability(magneticNorth: false, trueNorth: true)
    private let noFrames = MotionFrameAvailability(magneticNorth: false, trueNorth: false)

    /// Sample times: step n is at 1000 + n/16 seconds. 1/16 is exact in binary, so every sum and difference is exact.
    private func stamp(_ step: Int) -> TimeInterval { 1000.0 + Double(step) / 16.0 }

    /// The phone upright in portrait with its back camera looking `azimuth` degrees clockwise from the reference
    /// frame's x axis (rows: right = (-sin a, -cos a, 0), top = up, screen normal = (-cos a, sin a, 0)).
    private func upright(_ azimuth: Double) -> Matrix3 {
        let s = sin(azimuth * Double.pi / 180), c = cos(azimuth * Double.pi / 180)
        return Matrix3(rows: Vector3(-s, -c, 0), Vector3(0, 0, 1), Vector3(-c, s, 0))
    }

    private func makeInput(_ matrix: Matrix3, at timestamp: TimeInterval, speed: Double = 0, yaw: Double = 0,
                           field: Double = 50, accuracy: CompassQuality = .high) -> MotionInput {
        MotionInput(matrix: matrix, gravity: matrix * Vector3(0, 0, -1), angularSpeed: speed, yawRate: yaw,
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

    @discardableResult
    private func feed(_ p: inout MotionProcessor, id: Int, _ matrix: Matrix3, steps: ClosedRange<Int>, speed: Double = 0,
                      field: Double = 50) -> [MotionEvent] {
        var events: [MotionEvent] = []
        for step in steps {
            if let event = p.process(makeInput(matrix, at: stamp(step), speed: speed, field: field), streamID: id) {
                events.append(event)
            }
        }
        return events
    }

    // MARK: Frame choice

    func testTheMagneticFrameIsPreferredWhenBothFramesExist() {
        XCTAssertEqual(MotionProcessor.compassStream(for: bothFrames), .magneticNorth)
    }

    func testTheMagneticFrameIsUsedWhenItIsTheOnlyOne() {
        XCTAssertEqual(MotionProcessor.compassStream(for: magneticOnly), .magneticNorth)
    }

    func testTheTrueNorthFrameIsUsedWhenItIsTheOnlyOne() {
        XCTAssertEqual(MotionProcessor.compassStream(for: trueNorthOnly), .trueNorth)
    }

    func testNoCompassFrameMeansNoCompassStream() {
        XCTAssertNil(MotionProcessor.compassStream(for: noFrames))
    }

    // MARK: Plain value types

    func testStreamRequestsEventsAndAvailabilityCompareByValue() {
        XCTAssertEqual(MotionStreamStart(stream: .arbitrary, id: 3), MotionStreamStart(stream: .arbitrary, id: 3))
        XCTAssertNotEqual(MotionStreamStart(stream: .arbitrary, id: 3), MotionStreamStart(stream: .arbitrary, id: 4))
        XCTAssertNotEqual(MotionStreamStart(stream: .arbitrary, id: 3), MotionStreamStart(stream: .trueNorth, id: 3))
        XCTAssertEqual(MotionEvent.failed(stream: 1, code: 2), MotionEvent.failed(stream: 1, code: 2))
        XCTAssertNotEqual(MotionEvent.failed(stream: 1, code: 2), MotionEvent.failed(stream: 1, code: 3))
        XCTAssertNotEqual(MotionEvent.compassSteady(stream: 1), MotionEvent.trueNorthUnavailable(stream: 1))
        XCTAssertNotEqual(MotionEvent.compassSteady(stream: 1), MotionEvent.compassSteady(stream: 2))
        XCTAssertEqual(bothFrames, MotionFrameAvailability(magneticNorth: true, trueNorth: true))
        XCTAssertNotEqual(bothFrames, magneticOnly)
    }

    // MARK: Initial state and start

    func testAFreshProcessorIsStoppedAndEmpty() {
        let p = MotionProcessor()
        XCTAssertEqual(p.snapshot, MotionSnapshot(stream: nil, phase: .inactive, source: .compass,
                                                  compassQuality: .unavailable, magneticDisturbance: nil, frameEpoch: 0,
                                                  sampleCount: 0, isDeclinationKnown: false))
        XCTAssertEqual(p.source, .compass)
        XCTAssertNil(p.stream)
        XCTAssertNil(p.latest)
        XCTAssertNil(p.sample(at: 0))
        XCTAssertFalse(p.isCurrent(streamID: 0))
        XCTAssertFalse(p.isCurrent(streamID: 1))
    }

    func testStartingWithBothFramesRunsTheMagneticFrame() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        XCTAssertEqual(request, MotionStreamStart(stream: .magneticNorth, id: 1))
        XCTAssertEqual(p.stream, .magneticNorth)
        XCTAssertEqual(p.snapshot.stream, .magneticNorth)
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        XCTAssertTrue(p.isCurrent(streamID: 1))
        XCTAssertFalse(p.isCurrent(streamID: 0))
        XCTAssertFalse(p.isCurrent(streamID: 2))
    }

    func testStartingWithOnlyTheTrueNorthFrameRunsIt() {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        XCTAssertEqual(request, MotionStreamStart(stream: .trueNorth, id: 1))
        XCTAssertEqual(p.stream, .trueNorth)
        XCTAssertEqual(p.snapshot.phase, .inactive)
    }

    func testStartingWithoutACompassRunsTheGyroFrameWithoutAHeading() {
        var p = MotionProcessor()
        let request = p.start(availability: noFrames)
        XCTAssertEqual(request, MotionStreamStart(stream: .arbitrary, id: 1))
        XCTAssertEqual(p.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testStartingWithGyroLockBeginsInTheCompassFrameAndWaits() {
        var p = MotionProcessor()
        XCTAssertNil(p.setSource(.gyroLock, availability: bothFrames))
        let request = p.start(availability: bothFrames)
        XCTAssertEqual(request.stream, .magneticNorth)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertEqual(p.snapshot.source, .gyroLock)
    }

    func testStartingGyroLockWithoutACompassIsGyroOnlyAndUnreferenced() {
        var p = MotionProcessor()
        _ = p.setSource(.gyroLock, availability: noFrames)
        let request = p.start(availability: noFrames)
        XCTAssertEqual(request.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
    }

    func testEachStartIssuesANewStreamIdAndRetiresTheOldOne() {
        var p = MotionProcessor()
        let first = p.start(availability: bothFrames)
        let second = p.start(availability: bothFrames)
        XCTAssertEqual(first.id, 1)
        XCTAssertEqual(second.id, 2)
        XCTAssertFalse(p.isCurrent(streamID: first.id))
        XCTAssertTrue(p.isCurrent(streamID: second.id))
        // A sample still queued from the first stream is dropped.
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: first.id)
        XCTAssertEqual(p.sampleCount, 0)
        _ = p.process(makeInput(upright(0), at: stamp(1)), streamID: second.id)
        XCTAssertEqual(p.sampleCount, 1)
    }

    func testRestartingTheSameCompassFrameKeepsTheEpoch() {
        var p = MotionProcessor()
        _ = p.start(availability: bothFrames)
        _ = p.start(availability: bothFrames)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testRestartingGyroLockGoesBackToWaitingInTheCompassFrame() {
        var p = MotionProcessor()
        _ = p.setSource(.gyroLock, availability: bothFrames)
        let first = p.start(availability: bothFrames)
        feed(&p, id: first.id, upright(0), steps: 0...5)
        let second = p.start(availability: bothFrames)
        XCTAssertEqual(second.stream, .magneticNorth)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertNil(p.switchToGyroFrame())
    }

    // MARK: Stop

    func testStopForgetsTheSamplesButKeepsTheConfiguration() {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        _ = p.setSource(.gyroLock, availability: bothFrames)
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...3, field: 55)
        XCTAssertEqual(p.sampleCount, 4)
        XCTAssertNotNil(p.latest)
        XCTAssertNotNil(p.snapshot.magneticDisturbance)

        p.stop()

        XCTAssertEqual(p.snapshot, MotionSnapshot(stream: nil, phase: .inactive, source: .gyroLock,
                                                  compassQuality: .unavailable, magneticDisturbance: nil, frameEpoch: 0,
                                                  sampleCount: 0, isDeclinationKnown: true))
        XCTAssertNil(p.latest)
        XCTAssertNil(p.sample(at: stamp(3)))
    }

    func testSamplesOfAStoppedStreamAreDropped() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        p.stop()
        XCTAssertFalse(p.isCurrent(streamID: request.id))
        // Stopping also moves the id counter on (to 2); with no stream running, even that id is not current.
        XCTAssertFalse(p.isCurrent(streamID: request.id + 1))
        for id in [request.id, request.id + 1] {
            let event = p.process(makeInput(upright(0), at: stamp(0)), streamID: id)
            XCTAssertNil(event)
        }
        XCTAssertEqual(p.sampleCount, 0)
        XCTAssertNil(p.latest)
    }

    func testStoppingACompassFrameKeepsTheEpoch() {
        var p = MotionProcessor()
        _ = p.start(availability: bothFrames)
        p.stop()
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testStoppingTheGyroOnlyFrameStartsANewEpoch() {
        var p = MotionProcessor()
        _ = p.start(availability: noFrames)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
        p.stop()
        XCTAssertEqual(p.snapshot.frameEpoch, 2)
    }

    func testStopClearsAPendingCalibrationRequest() {
        var p = MotionProcessor()
        let first = p.start(availability: bothFrames)
        p.noteCalibrationRequested(streamID: first.id)
        p.stop()
        let second = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), accuracy: .low), streamID: second.id)
        XCTAssertEqual(p.snapshot.compassQuality, .low)
    }

    func testARestartAfterStopStartsCountingAgain() {
        var p = MotionProcessor()
        let first = p.start(availability: bothFrames)
        feed(&p, id: first.id, upright(0), steps: 0...2)
        p.stop()
        let second = p.start(availability: bothFrames)
        XCTAssertEqual(second.id, 3, "start 1, stop moves the counter to 2, the next start takes 3")
        feed(&p, id: second.id, upright(0), steps: 10...10)
        XCTAssertEqual(p.sampleCount, 1)
        XCTAssertEqual(p.latest?.timestamp, stamp(10))
    }

    // MARK: Smoothing

    /// After the raw camera azimuth moved from 20 to 20.1 degrees one sample (1/16 s) later: how far, in degrees, the
    /// published (smoothed) azimuth has moved. `settings` are passed to `setSmoothing`, in order, before the first sample.
    private func smoothedShift(settings: [Double]) throws -> Double {
        var p = MotionProcessor()
        for value in settings { p.setSmoothing(value) }
        let request = p.start(availability: trueNorthOnly)
        _ = p.process(makeInput(upright(20), at: stamp(0)), streamID: request.id)
        _ = p.process(makeInput(upright(20.1), at: stamp(1)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 20), 0.1, accuracy: 1e-9)
        return azimuthDifference(cameraAzimuth(sample.attitude), 20)
    }

    func testSmoothingIsOnByDefaultAndLagsBehindTheRawAttitude() throws {
        let shift = try smoothedShift(settings: [])
        XCTAssertGreaterThan(shift, 0.01)
        XCTAssertLessThan(shift, 0.09)
    }

    func testAZeroTimeConstantTurnsSmoothingOff() throws {
        let shift = try smoothedShift(settings: [0])
        XCTAssertEqual(shift, 0.1, accuracy: 1e-9)
    }

    func testNegativeAndTinyTimeConstantsTurnSmoothingOff() throws {
        for value in [-1.0, 0.005, 0.0099] {
            let shift = try smoothedShift(settings: [value])
            XCTAssertEqual(shift, 0.1, accuracy: 1e-9, "time constant \(value)")
        }
    }

    func testTheSmallestSmoothingTimeConstantStillSmooths() throws {
        let shift = try smoothedShift(settings: [0.01])
        XCTAssertGreaterThan(shift, 0.09)
        XCTAssertLessThan(shift, 0.1 - 1e-5)
    }

    func testANonFiniteTimeConstantFallsBackToTheDefault() throws {
        let defaultShift = try smoothedShift(settings: [])
        for settings in [[Double.nan], [0.0, Double.nan], [0.0, Double.infinity], [0.0, -Double.infinity]] {
            let shift = try smoothedShift(settings: settings)
            XCTAssertEqual(shift, defaultShift, accuracy: 1e-12, "settings \(settings)")
        }
    }

    func testATimeConstantAboveTwoSecondsIsClampedToTwo() throws {
        let clamped = try smoothedShift(settings: [100])
        let two = try smoothedShift(settings: [2])
        let defaultShift = try smoothedShift(settings: [])
        XCTAssertEqual(clamped, two, accuracy: 1e-12)
        XCTAssertGreaterThan(two, 0)
        XCTAssertLessThan(two, defaultShift, "a longer time constant lags more")
    }

    /// Feeds 20, 20.1 degrees, applies `value` and feeds 20.2 degrees; returns how far the published azimuth is from 20.
    private func thirdSampleShift(afterSetting value: Double) throws -> Double {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        _ = p.process(makeInput(upright(20), at: stamp(0)), streamID: request.id)
        _ = p.process(makeInput(upright(20.1), at: stamp(1)), streamID: request.id)
        p.setSmoothing(value)
        _ = p.process(makeInput(upright(20.2), at: stamp(2)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 20), 0.2, accuracy: 1e-9)
        return azimuthDifference(cameraAzimuth(sample.attitude), 20)
    }

    func testSettingTheSameTimeConstantAgainKeepsTheFilterState() throws {
        let shift = try thirdSampleShift(afterSetting: 0.12)
        // Still lagging: the filter carries on from the smoothed second sample (about 0.05 degrees).
        XCTAssertGreaterThan(shift, 0.06)
        XCTAssertLessThan(shift, 0.19)
    }

    func testChangingTheTimeConstantRestartsTheFilterFromTheNextRawSample() throws {
        let shift = try thirdSampleShift(afterSetting: 0.5)
        XCTAssertEqual(shift, 0.2, accuracy: 1e-9)
    }

    // MARK: Magnetic reference

    func testTheDeclinationIsKnownOnceAFiniteOneIsSet() {
        var p = MotionProcessor()
        XCTAssertFalse(p.snapshot.isDeclinationKnown)
        p.setMagneticReference(reference(10))
        XCTAssertTrue(p.snapshot.isDeclinationKnown)
        p.setMagneticReference(nil)
        XCTAssertFalse(p.snapshot.isDeclinationKnown)
        p.setMagneticReference(reference(-12.5))
        XCTAssertTrue(p.snapshot.isDeclinationKnown)
    }

    func testANonFiniteDeclinationCountsAsUnknown() {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            var p = MotionProcessor()
            p.setMagneticReference(reference(bad))
            XCTAssertFalse(p.snapshot.isDeclinationKnown, "declination \(bad)")
            p.setMagneticReference(reference(10))
            XCTAssertTrue(p.snapshot.isDeclinationKnown)
            p.setMagneticReference(reference(bad))
            XCTAssertFalse(p.snapshot.isDeclinationKnown, "after a known one, declination \(bad)")
        }
    }

    func testTheMagneticFrameWithoutADeclinationIsTakenAsTrueNorth() throws {
        var p = MotionProcessor()
        let request = p.start(availability: magneticOnly)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.attitude.referenceAzimuth, 0, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.attitude), 0), 0, accuracy: 1e-9)
    }

    func testAnEastDeclinationIsTheReferenceAzimuthOfTheMagneticFrame() throws {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        let request = p.start(availability: magneticOnly)
        // The phone is upright and looks along the frame's x axis, i.e. at magnetic north, which lies 10 degrees east of
        // true north.
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.attitude.referenceAzimuth, 10, accuracy: 1e-12)
        XCTAssertEqual(sample.rawAttitude.referenceAzimuth, 10, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 10), 0, accuracy: 1e-9)
    }

    func testAWestDeclinationTurnsTheReferenceTheOtherWay() throws {
        var p = MotionProcessor()
        p.setMagneticReference(reference(-12.5))
        let request = p.start(availability: magneticOnly)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.attitude.referenceAzimuth, -12.5, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), -12.5), 0, accuracy: 1e-9)
    }

    func testTheDeclinationShiftsTheTrueAzimuthByExactlyItsValue() throws {
        for declination in [10.0, -12.5, 23.4] {
            var trueNorth = MotionProcessor()
            let trueRequest = trueNorth.start(availability: trueNorthOnly)
            var magnetic = MotionProcessor()
            magnetic.setMagneticReference(reference(declination))
            let magneticRequest = magnetic.start(availability: magneticOnly)
            let matrix = upright(37)
            _ = trueNorth.process(makeInput(matrix, at: stamp(0)), streamID: trueRequest.id)
            _ = magnetic.process(makeInput(matrix, at: stamp(0)), streamID: magneticRequest.id)
            let trueSample = try XCTUnwrap(trueNorth.latest)
            let magneticSample = try XCTUnwrap(magnetic.latest)
            XCTAssertEqual(trueSample.attitude.referenceAzimuth, 0, accuracy: 1e-12)
            XCTAssertEqual(azimuthDifference(cameraAzimuth(trueSample.attitude), 37), 0, accuracy: 1e-9)
            XCTAssertEqual(azimuthDifference(cameraAzimuth(magneticSample.attitude), 37 + declination), 0,
                           accuracy: 1e-9, "declination \(declination)")
        }
    }

    func testANewDeclinationTakesEffectOnTheRunningStreamWithoutARestart() throws {
        var p = MotionProcessor()
        let request = p.start(availability: magneticOnly)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let before = try XCTUnwrap(p.latest)
        XCTAssertEqual(before.attitude.referenceAzimuth, 0, accuracy: 1e-12)

        p.setMagneticReference(reference(10))
        XCTAssertTrue(p.isCurrent(streamID: request.id), "no restart")
        _ = p.process(makeInput(upright(0), at: stamp(1)), streamID: request.id)
        let after = try XCTUnwrap(p.latest)
        XCTAssertEqual(after.attitude.referenceAzimuth, 10, accuracy: 1e-12)
        XCTAssertEqual(after.rawAttitude.referenceAzimuth, 10, accuracy: 1e-12)
    }

    func testTheTrueNorthFrameIgnoresTheDeclination() throws {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        p.setMagneticReference(reference(10))
        XCTAssertTrue(p.snapshot.isDeclinationKnown)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.attitude.referenceAzimuth, 0, accuracy: 1e-12)
    }

    func testADeclinationSetBeforeStartingDoesNotStartANewEpoch() {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        _ = p.start(availability: magneticOnly)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testOnlyAReferenceStepBeyondHalfADegreeStartsANewEpoch() {
        var p = MotionProcessor()
        let request = p.start(availability: magneticOnly) // reference azimuth 0: the declination is not known yet
        p.setMagneticReference(reference(0.4))
        XCTAssertEqual(p.snapshot.frameEpoch, 0, "0.4 degrees from the reference the alignments were made for")
        p.setMagneticReference(reference(0.8))
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "0.8 degrees from it: the steps add up against the recorded reference")
        p.setMagneticReference(reference(1.2))
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "0.4 from the new reference (0.8)")
        p.setMagneticReference(reference(1.31))
        XCTAssertEqual(p.snapshot.frameEpoch, 2, "0.51 from the reference (0.8)")
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testASmallDeclinationStepIsAppliedWithoutANewEpoch() throws {
        var p = MotionProcessor()
        let request = p.start(availability: magneticOnly)
        p.setMagneticReference(reference(0.4))
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.attitude.referenceAzimuth, 0.4, accuracy: 1e-12)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
    }

    func testDeclinationChangesUnderAHundredthOfADegreeAreIgnoredButTheExpectedFieldIsKept() throws {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10, field: 50))
        let request = p.start(availability: magneticOnly)
        p.setMagneticReference(reference(10.005, field: 40))
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 44), streamID: request.id)
        let first = try XCTUnwrap(p.latest)
        XCTAssertEqual(first.attitude.referenceAzimuth, 10, accuracy: 1e-12, "10.005 is within 0.01 of 10")
        // The expected field of the ignored reference is in use: 4 µT off 40, not 6 µT off 50.
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)

        p.setMagneticReference(reference(10.02, field: 40))
        _ = p.process(makeInput(upright(0), at: stamp(1), field: 44), streamID: request.id)
        let second = try XCTUnwrap(p.latest)
        XCTAssertEqual(second.attitude.referenceAzimuth, 10.02, accuracy: 1e-12)
    }

    func testClearingTheDeclinationOnTheMagneticFrameStartsANewEpoch() throws {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        let request = p.start(availability: magneticOnly)
        p.setMagneticReference(nil)
        XCTAssertFalse(p.snapshot.isDeclinationKnown)
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "the reference azimuth steps from 10 back to 0")
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.latest).attitude.referenceAzimuth, 0, accuracy: 1e-12)
    }

    func testADeclinationThatChangedWhileStoppedStartsANewEpochAtTheNextStart() {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        _ = p.start(availability: magneticOnly)
        p.stop()
        p.setMagneticReference(reference(20))
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        _ = p.start(availability: magneticOnly)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testTheGyroOnlyFrameIgnoresDeclinationChanges() {
        var p = MotionProcessor()
        _ = p.start(availability: noFrames)
        let epoch = p.snapshot.frameEpoch
        p.setMagneticReference(reference(10))
        XCTAssertTrue(p.snapshot.isDeclinationKnown)
        XCTAssertEqual(p.snapshot.frameEpoch, epoch)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
    }

    // MARK: Heading source

    func testSettingTheSameSourceChangesNothing() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        XCTAssertNil(p.setSource(.compass, availability: bothFrames))
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testSettingASourceWhileStoppedOnlyRemembersIt() {
        var p = MotionProcessor()
        XCTAssertNil(p.setSource(.gyroLock, availability: bothFrames))
        XCTAssertEqual(p.source, .gyroLock)
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertNil(p.stream)
        XCTAssertNil(p.setSource(.compass, availability: bothFrames))
        XCTAssertEqual(p.source, .compass)
    }

    func testGyroLockOnARunningCompassFrameWaitsThereForASteadyPhone() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        XCTAssertNil(p.setSource(.gyroLock, availability: bothFrames), "no restart is needed")
        XCTAssertEqual(p.source, .gyroLock)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertEqual(p.stream, .magneticNorth)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testGyroLockOnATrueNorthFrameWaitsThereToo() {
        var p = MotionProcessor()
        _ = p.start(availability: trueNorthOnly)
        XCTAssertNil(p.setSource(.gyroLock, availability: trueNorthOnly))
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertEqual(p.stream, .trueNorth)
    }

    func testGyroLockOnAGyroOnlyDeviceChangesNothing() {
        var p = MotionProcessor()
        let request = p.start(availability: noFrames)
        XCTAssertNil(p.setSource(.gyroLock, availability: noFrames))
        XCTAssertEqual(p.source, .gyroLock)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.stream, .arbitrary)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testGyroLockIsNotArmedWhenTheDeviceReportsNoCompassFrame() {
        var p = MotionProcessor()
        _ = p.start(availability: bothFrames)
        XCTAssertNil(p.setSource(.gyroLock, availability: noFrames))
        XCTAssertEqual(p.source, .gyroLock)
        XCTAssertEqual(p.snapshot.phase, .inactive)
    }

    func testBackToCompassWhileWaitingForTheTransferDisarmsIt() {
        var p = MotionProcessor()
        _ = p.setSource(.gyroLock, availability: bothFrames)
        let request = p.start(availability: bothFrames)
        XCTAssertEqual(p.snapshot.phase, .awaitingCompass)
        XCTAssertNil(p.setSource(.compass, availability: bothFrames))
        XCTAssertEqual(p.source, .compass)
        XCTAssertEqual(p.snapshot.phase, .inactive)
        XCTAssertTrue(p.isCurrent(streamID: request.id), "the compass frame keeps running")
        // Steady samples no longer ask for the transfer.
        let events = feed(&p, id: request.id, upright(0), steps: 0...40)
        XCTAssertEqual(events, [])
    }

    func testBackToCompassOnAGyroOnlyDeviceChangesNothing() {
        var p = MotionProcessor()
        _ = p.setSource(.gyroLock, availability: noFrames)
        let request = p.start(availability: noFrames)
        let epoch = p.snapshot.frameEpoch
        XCTAssertNil(p.setSource(.compass, availability: noFrames))
        XCTAssertEqual(p.source, .compass)
        XCTAssertEqual(p.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, epoch)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    // MARK: True-north failure

    func testTrueNorthFailureFallsBackToTheMagneticFrame() {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        let next = p.recoverFromTrueNorthFailure(streamID: request.id, availability: bothFrames)
        XCTAssertEqual(next, MotionStreamStart(stream: .magneticNorth, id: 2))
        XCTAssertEqual(p.stream, .magneticNorth)
        XCTAssertFalse(p.isCurrent(streamID: request.id))
        XCTAssertTrue(p.isCurrent(streamID: 2))
        XCTAssertEqual(p.snapshot.frameEpoch, 0, "without a declination the reference azimuth stays 0")
    }

    func testTrueNorthFailureWithoutAMagneticFrameFallsBackToGyroOnly() {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        let next = p.recoverFromTrueNorthFailure(streamID: request.id, availability: trueNorthOnly)
        XCTAssertEqual(next, MotionStreamStart(stream: .arbitrary, id: 2))
        XCTAssertEqual(p.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.phase, .unreferenced)
        XCTAssertEqual(p.snapshot.frameEpoch, 1)
    }

    func testFallingBackToTheMagneticFrameWithAKnownDeclinationStartsANewEpoch() {
        var p = MotionProcessor()
        p.setMagneticReference(reference(10))
        let request = p.start(availability: trueNorthOnly)
        XCTAssertEqual(p.snapshot.frameEpoch, 0)
        _ = p.recoverFromTrueNorthFailure(streamID: request.id, availability: bothFrames)
        XCTAssertEqual(p.snapshot.frameEpoch, 1, "the reference azimuth steps from 0 (true north) to 10")
    }

    func testTrueNorthFailureOfAStaleStreamIsIgnored() {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        XCTAssertNil(p.recoverFromTrueNorthFailure(streamID: request.id + 5, availability: bothFrames))
        XCTAssertNil(p.recoverFromTrueNorthFailure(streamID: request.id - 1, availability: bothFrames))
        XCTAssertEqual(p.stream, .trueNorth)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testTrueNorthFailureWhileAnotherFrameRunsIsIgnored() {
        var p = MotionProcessor()
        let request = p.start(availability: magneticOnly)
        XCTAssertNil(p.recoverFromTrueNorthFailure(streamID: request.id, availability: bothFrames))
        XCTAssertEqual(p.stream, .magneticNorth)
        XCTAssertTrue(p.isCurrent(streamID: request.id))
    }

    func testTrueNorthFailureAfterStopIsIgnored() {
        var p = MotionProcessor()
        let request = p.start(availability: trueNorthOnly)
        p.stop()
        XCTAssertNil(p.recoverFromTrueNorthFailure(streamID: request.id, availability: bothFrames))
        XCTAssertNil(p.stream)
    }
}

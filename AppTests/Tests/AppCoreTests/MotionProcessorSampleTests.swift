import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `MotionProcessor.process` and what it publishes: which inputs count, what a published sample carries, the compass
/// quality and magnetic disturbance, and the short history behind `sample(at:)`.
///
/// Geometry used throughout (CoreMotion conventions): the matrix `M` satisfies `v_device = M · v_reference`, so its rows
/// are the device axes written in the reference frame (x north, y west, z up). The device frame has x to the right of the
/// phone, y to its top and z out of the screen; the back camera looks along -z.
final class MotionProcessorSampleTests: XCTestCase {
    // MARK: Fixtures

    private let bothFrames = MotionFrameAvailability(magneticNorth: true, trueNorth: true)
    private let noFrames = MotionFrameAvailability(magneticNorth: false, trueNorth: false)

    /// Sample times: step n is at 1000 + n/16 seconds. 1/16 is exact in binary, so every sum, difference and boundary
    /// below is exact.
    private func stamp(_ step: Int) -> TimeInterval { 1000.0 + Double(step) / 16.0 }

    /// The phone held upright in portrait with its back camera looking `azimuth` degrees clockwise from the reference
    /// frame's x axis. Written from the device axes: top = up, camera direction (cos a, -sin a, 0) in the north-west-up
    /// frame (clockwise from north means towards -y, which is east), screen normal = opposite of the camera direction,
    /// right = top × normal. Gravity in device coordinates is (0, -1, 0).
    private func upright(_ azimuth: Double) -> Matrix3 {
        let s = sin(azimuth * Double.pi / 180), c = cos(azimuth * Double.pi / 180)
        return Matrix3(rows: Vector3(-s, -c, 0), Vector3(0, 0, 1), Vector3(-c, s, 0))
    }

    private func makeInput(_ matrix: Matrix3, at timestamp: TimeInterval, speed: Double = 0, yaw: Double = 0,
                           field: Double = 50, accuracy: CompassQuality = .high, gravity: Vector3? = nil) -> MotionInput {
        MotionInput(matrix: matrix, gravity: gravity ?? matrix * Vector3(0, 0, -1), angularSpeed: speed, yawRate: yaw,
                    fieldMicrotesla: field, fieldAccuracy: accuracy, timestamp: timestamp)
    }

    /// True azimuth the back camera looks at, from the attitude's own world transform.
    private func cameraAzimuth(_ attitude: DeviceAttitude) -> Double {
        let direction = attitude.deviceToWorld * DeviceAttitude.backCameraAxis
        return AstroMath.atan2Deg(direction.x, direction.y)
    }

    private func azimuthDifference(_ a: Double, _ b: Double) -> Double { AstroMath.normalizeSignedDegrees(a - b) }

    private func assertMatrix(_ a: Matrix3, _ b: Matrix3, accuracy: Double = 1e-12,
                              file: StaticString = #filePath, line: UInt = #line) {
        for row in 0..<3 {
            for column in 0..<3 {
                XCTAssertEqual(a[row, column], b[row, column], accuracy: accuracy, file: file, line: line)
            }
        }
    }

    @discardableResult
    private func feed(_ p: inout MotionProcessor, id: Int, _ matrix: Matrix3, steps: ClosedRange<Int>, speed: Double = 0,
                      field: Double = 50, accuracy: CompassQuality = .high) -> [MotionEvent] {
        var events: [MotionEvent] = []
        for step in steps {
            let input = makeInput(matrix, at: stamp(step), speed: speed, field: field, accuracy: accuracy)
            if let event = p.process(input, streamID: id) { events.append(event) }
        }
        return events
    }

    private func unusableInputs() -> [MotionInput] {
        let good = makeInput(upright(0), at: stamp(0))
        var badMatrix = good
        badMatrix.matrix.r1.y = .nan
        var badGravity = good
        badGravity.gravity = Vector3(0, .infinity, 0)
        var badSpeed = good
        badSpeed.angularSpeed = .nan
        var badYaw = good
        badYaw.yawRate = -.infinity
        var badTime = good
        badTime.timestamp = .nan
        return [badMatrix, badGravity, badSpeed, badYaw, badTime]
    }

    // MARK: Which inputs count

    func testAnInputIsUsableOnlyWhenTheCoreNumbersAreFinite() {
        XCTAssertTrue(makeInput(upright(0), at: stamp(0)).isUsable)
        for bad in unusableInputs() {
            XCTAssertFalse(bad.isUsable)
        }
    }

    func testANonFiniteFieldDoesNotMakeAnInputUnusable() {
        var input = makeInput(upright(0), at: stamp(0))
        input.fieldMicrotesla = .nan
        XCTAssertTrue(input.isUsable)
    }

    func testASampleBeforeAnyStreamStartedIsIgnored() {
        var p = MotionProcessor()
        let event = p.process(makeInput(upright(0), at: stamp(0)), streamID: 0)
        XCTAssertNil(event)
        XCTAssertEqual(p.sampleCount, 0)
        XCTAssertNil(p.latest)
    }

    func testASampleOfAnotherStreamIsIgnored() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id + 1)
        _ = p.process(makeInput(upright(0), at: stamp(1)), streamID: request.id - 1)
        XCTAssertEqual(p.sampleCount, 0)
        XCTAssertNil(p.latest)
        _ = p.process(makeInput(upright(0), at: stamp(2)), streamID: request.id)
        XCTAssertEqual(p.sampleCount, 1)
        XCTAssertEqual(p.latest?.timestamp, stamp(2))
    }

    func testUnusableInputsAreDroppedBeforeAnythingIsCounted() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        for bad in unusableInputs() {
            let event = p.process(bad, streamID: request.id)
            XCTAssertNil(event)
        }
        XCTAssertEqual(p.sampleCount, 0)
        XCTAssertNil(p.latest)
        XCTAssertEqual(p.snapshot.compassQuality, .unavailable)
    }

    func testAMatrixThatIsNotARotationIsCountedButNotPublished() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        let scaled = Matrix3(rows: Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2))
        let mirrored = Matrix3(rows: Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
        _ = p.process(makeInput(scaled, at: stamp(0)), streamID: request.id)
        _ = p.process(makeInput(mirrored, at: stamp(1)), streamID: request.id)
        XCTAssertEqual(p.sampleCount, 2)
        XCTAssertNil(p.latest)
        XCTAssertNil(p.sample(at: stamp(0)))
        XCTAssertNil(p.sample(at: stamp(1)))
        // A proper rotation afterwards is published normally.
        _ = p.process(makeInput(upright(0), at: stamp(2)), streamID: request.id)
        XCTAssertEqual(p.sampleCount, 3)
        XCTAssertEqual(p.latest?.timestamp, stamp(2))
    }

    func testAMatrixSlightlyOffARotationIsCleanedUp() throws {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        var matrix = upright(30)
        matrix.r0 = matrix.r0 * 1.01 // row length 1.01: within the tolerance for sensor noise
        _ = p.process(makeInput(matrix, at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.rawAttitude.matrix.r0.length, 1, accuracy: 1e-12)
        XCTAssertEqual(sample.rawAttitude.matrix.determinant, 1, accuracy: 1e-12)
        XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), 30), 0, accuracy: 1e-9)
    }

    // MARK: What a sample carries

    func testThePublishedSampleCarriesTheInputValues() throws {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        let matrix = upright(30)
        let gravity = Vector3(0.01, -0.99, -0.02)
        _ = p.process(makeInput(matrix, at: stamp(7), speed: 1.5, field: 47.5, accuracy: .medium, gravity: gravity),
                      streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(sample.gravity, gravity)
        XCTAssertEqual(sample.angularSpeed, 1.5)
        XCTAssertEqual(sample.magneticFieldMicrotesla, 47.5)
        XCTAssertEqual(sample.compassQuality, .medium)
        XCTAssertEqual(sample.timestamp, stamp(7))
        XCTAssertEqual(sample.rawAttitude.timestamp, stamp(7))
        XCTAssertEqual(sample.attitude.timestamp, stamp(7))
        assertMatrix(sample.rawAttitude.matrix, matrix)
        // Nothing to smooth against yet: the first sample passes through unchanged.
        XCTAssertEqual(sample.attitude, sample.rawAttitude)
    }

    func testTheCountAndTheLatestSampleFollowTheNewestSample() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...4)
        XCTAssertEqual(p.sampleCount, 5)
        XCTAssertEqual(p.snapshot.sampleCount, 5)
        XCTAssertEqual(p.latest?.timestamp, stamp(4))
    }

    func testAnUprightPhoneFacingEachCardinalDirectionLooksThereInTheTrueNorthFrame() throws {
        var p = MotionProcessor()
        let request = p.start(availability: MotionFrameAvailability(magneticNorth: false, trueNorth: true))
        // Facing north, east, south and west; the matrices come from the device axes, not from the helper's formula.
        let north = Matrix3(rows: Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
        let east = Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
        let south = Matrix3(rows: Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
        let west = Matrix3(rows: Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
        let expected: [(Matrix3, Double)] = [(north, 0), (east, 90), (south, 180), (west, 270)]
        for (step, item) in expected.enumerated() {
            _ = p.process(makeInput(item.0, at: stamp(step * 100)), streamID: request.id)
            let sample = try XCTUnwrap(p.latest)
            XCTAssertEqual(azimuthDifference(cameraAzimuth(sample.rawAttitude), item.1), 0, accuracy: 1e-9,
                           "facing \(item.1) degrees")
            let direction = sample.rawAttitude.deviceToWorld * DeviceAttitude.backCameraAxis
            XCTAssertEqual(direction.z, 0, accuracy: 1e-12, "the camera of an upright phone looks at the horizon")
        }
    }

    func testAFlatPhoneLooksStraightDown() throws {
        var p = MotionProcessor()
        let request = p.start(availability: MotionFrameAvailability(magneticNorth: false, trueNorth: true))
        // Lying face up with its top towards north: device x east, y north, z up; in the north-west-up frame x = -y_ref.
        let flat = Matrix3(rows: Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
        _ = p.process(makeInput(flat, at: stamp(0)), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        let direction = sample.rawAttitude.deviceToWorld * DeviceAttitude.backCameraAxis
        XCTAssertEqual(direction.x, 0, accuracy: 1e-12)
        XCTAssertEqual(direction.y, 0, accuracy: 1e-12)
        XCTAssertEqual(direction.z, -1, accuracy: 1e-12)
        XCTAssertEqual(sample.gravity, Vector3(0, 0, -1))
    }

    // MARK: Compass quality

    func testTheCompassQualityFollowsTheReportedAccuracy() throws {
        for accuracy in [CompassQuality.uncalibrated, .low, .medium, .high] {
            var p = MotionProcessor()
            let request = p.start(availability: bothFrames)
            _ = p.process(makeInput(upright(0), at: stamp(0), accuracy: accuracy), streamID: request.id)
            XCTAssertEqual(p.snapshot.compassQuality, accuracy)
            let sample = try XCTUnwrap(p.latest)
            XCTAssertEqual(sample.compassQuality, accuracy)
        }
    }

    func testWithoutAFieldTheCompassIsUnavailable() throws {
        for field in [0.0, -5.0, Double.nan, Double.infinity, -Double.infinity] {
            var p = MotionProcessor()
            p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
            let request = p.start(availability: bothFrames)
            _ = p.process(makeInput(upright(0), at: stamp(0), field: field), streamID: request.id)
            XCTAssertEqual(p.sampleCount, 1, "field \(field)")
            XCTAssertEqual(p.snapshot.compassQuality, .unavailable, "field \(field)")
            XCTAssertNil(p.snapshot.magneticDisturbance, "field \(field)")
            let sample = try XCTUnwrap(p.latest)
            XCTAssertNil(sample.magneticFieldMicrotesla, "field \(field)")
            XCTAssertEqual(sample.compassQuality, .unavailable, "field \(field)")
        }
    }

    func testACalibrationRequestKeepsTheQualityUncalibratedUntilMediumAccuracy() throws {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), accuracy: .low), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .low)

        p.noteCalibrationRequested(streamID: request.id)
        _ = p.process(makeInput(upright(0), at: stamp(1), accuracy: .low), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .uncalibrated)
        XCTAssertEqual(try XCTUnwrap(p.latest).compassQuality, .uncalibrated)

        // Even a better accuracy below medium does not lift the request.
        _ = p.process(makeInput(upright(0), at: stamp(2), accuracy: .uncalibrated), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .uncalibrated)

        // Medium accuracy clears the request for good.
        _ = p.process(makeInput(upright(0), at: stamp(3), accuracy: .medium), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .medium)
        _ = p.process(makeInput(upright(0), at: stamp(4), accuracy: .low), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .low)
    }

    func testACalibrationRequestForAnotherStreamIsIgnored() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        p.noteCalibrationRequested(streamID: request.id + 1)
        _ = p.process(makeInput(upright(0), at: stamp(0), accuracy: .low), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .low)
    }

    func testACalibrationRequestWithoutAFieldWaitsForTheNextFieldSample() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        p.noteCalibrationRequested(streamID: request.id)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 0), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .unavailable)
        _ = p.process(makeInput(upright(0), at: stamp(1), accuracy: .low), streamID: request.id)
        XCTAssertEqual(p.snapshot.compassQuality, .uncalibrated)
    }

    func testAGyroOnlyDeviceHasNoCompassData() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 10, expectedFieldMicrotesla: 50))
        let request = p.start(availability: noFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
        let sample = try XCTUnwrap(p.latest)
        XCTAssertEqual(p.snapshot.stream, .arbitrary)
        XCTAssertEqual(p.snapshot.compassQuality, .unavailable)
        XCTAssertNil(p.snapshot.magneticDisturbance)
        XCTAssertNil(sample.magneticFieldMicrotesla)
        XCTAssertEqual(sample.compassQuality, .unavailable)
        // The heading is unknown until the user aligns on a star: the declination must not be applied to it.
        XCTAssertEqual(sample.attitude.referenceAzimuth, 0, accuracy: 1e-12)
    }

    // MARK: Magnetic disturbance

    func testTheFirstFieldSampleSetsTheDisturbanceRelativeToTheExpectedField() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)
    }

    func testTheDisturbanceIsTheAbsoluteRelativeDeviation() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 40), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.2, accuracy: 1e-12)
    }

    func testAFieldAtTheExpectedStrengthShowsNoDisturbance() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 50), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0, accuracy: 1e-12)
    }

    func testTheDisturbanceUsesAnExponentialAverageOfTheField() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: 1000, field: 55), streamID: request.id)
        // One second later (the averaging time constant) the average has covered 1 - 1/e = 63.2 percent of the way
        // from 55 to 45: 48.6788 µT, which is 2.6424 percent below the expected 50 µT.
        _ = p.process(makeInput(upright(0), at: 1001, field: 45), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.0264241118, accuracy: 1e-9)
    }

    func testASampleThatIsNotLaterThanItsPredecessorRestartsTheAverage() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 45), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)
    }

    func testAMissingFieldDropsTheAverage() throws {
        var p = MotionProcessor()
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
        _ = p.process(makeInput(upright(0), at: stamp(1), field: 0), streamID: request.id)
        XCTAssertNil(p.snapshot.magneticDisturbance)
        // The next field starts a new average: 45 µT is 10 percent away from 50, not something mixed with the old 55.
        _ = p.process(makeInput(upright(0), at: stamp(2), field: 45), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)
    }

    func testNoDisturbanceBelowLowAccuracy() throws {
        let expectations: [(CompassQuality, Bool)] = [(.uncalibrated, false), (.low, true), (.medium, true), (.high, true)]
        for (accuracy, hasDisturbance) in expectations {
            var p = MotionProcessor()
            p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
            let request = p.start(availability: bothFrames)
            _ = p.process(makeInput(upright(0), at: stamp(0), field: 55, accuracy: accuracy), streamID: request.id)
            if hasDisturbance {
                XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12, "\(accuracy)")
            } else {
                XCTAssertNil(p.snapshot.magneticDisturbance, "\(accuracy)")
            }
        }
    }

    func testNoDisturbanceWithoutAUsableExpectedField() {
        let references: [MagneticReference?] = [
            nil,
            MagneticReference(declination: 5, expectedFieldMicrotesla: 0),
            MagneticReference(declination: 5, expectedFieldMicrotesla: -50),
            MagneticReference(declination: 5, expectedFieldMicrotesla: .nan),
            MagneticReference(declination: 5, expectedFieldMicrotesla: .infinity),
        ]
        for reference in references {
            var p = MotionProcessor()
            p.setMagneticReference(reference)
            let request = p.start(availability: bothFrames)
            _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
            XCTAssertNil(p.snapshot.magneticDisturbance, "\(String(describing: reference))")
            XCTAssertEqual(p.snapshot.compassQuality, .high)
        }
    }

    func testTheExpectedFieldCanArriveAfterTheFirstSamplesAndBeWithdrawn() throws {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0), field: 55), streamID: request.id)
        XCTAssertNil(p.snapshot.magneticDisturbance)
        p.setMagneticReference(MagneticReference(declination: 0, expectedFieldMicrotesla: 50))
        _ = p.process(makeInput(upright(0), at: stamp(1), field: 55), streamID: request.id)
        XCTAssertEqual(try XCTUnwrap(p.snapshot.magneticDisturbance), 0.1, accuracy: 1e-12)
        p.setMagneticReference(nil)
        _ = p.process(makeInput(upright(0), at: stamp(2), field: 55), streamID: request.id)
        XCTAssertNil(p.snapshot.magneticDisturbance)
    }

    // MARK: Sample lookup by time

    func testLookupReturnsTheSampleAtTheTimeExactly() throws {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        for step in 0...3 {
            _ = p.process(makeInput(upright(Double(step) * 10), at: stamp(step)), streamID: request.id)
        }
        for step in 0...3 {
            let found = try XCTUnwrap(p.sample(at: stamp(step)), "step \(step)")
            XCTAssertEqual(found.timestamp, stamp(step))
            XCTAssertEqual(azimuthDifference(cameraAzimuth(found.rawAttitude), Double(step) * 10), 0, accuracy: 1e-9)
        }
    }

    func testLookupReturnsTheNearestSample() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...1)
        // The samples are at 1000.0 and 1000.0625.
        XCTAssertEqual(p.sample(at: 1000.02)?.timestamp, stamp(0))
        XCTAssertEqual(p.sample(at: 1000.04)?.timestamp, stamp(1))
    }

    func testLookupBetweenTwoEquallyNearSamplesTakesTheLaterOne() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...1)
        XCTAssertEqual(p.sample(at: 1000.03125)?.timestamp, stamp(1))
    }

    func testLookupGivesNothingFartherThanTheReachFromAnySample() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...1)
        // Ahead of the newest sample (a stalled sensor) and before the oldest one: 0.09 s is reachable, 0.11 s is not.
        XCTAssertEqual(p.sample(at: stamp(1) + 0.09)?.timestamp, stamp(1))
        XCTAssertNil(p.sample(at: stamp(1) + 0.11))
        XCTAssertEqual(p.sample(at: stamp(0) - 0.09)?.timestamp, stamp(0))
        XCTAssertNil(p.sample(at: stamp(0) - 0.11))
    }

    func testLookupIsNilWithoutSamplesAndForANonFiniteTime() {
        var p = MotionProcessor()
        XCTAssertNil(p.sample(at: stamp(0)))
        let request = p.start(availability: bothFrames)
        XCTAssertNil(p.sample(at: stamp(0)))
        feed(&p, id: request.id, upright(0), steps: 0...1)
        XCTAssertNil(p.sample(at: .nan))
        XCTAssertNil(p.sample(at: .infinity))
        XCTAssertNil(p.sample(at: -.infinity))
    }

    func testTheHistoryKeepsTheLastHalfSecond() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        // Nine samples span exactly half a second: all are kept, the oldest sits exactly on the cut-off.
        feed(&p, id: request.id, upright(0), steps: 0...8)
        XCTAssertEqual(p.sample(at: stamp(0))?.timestamp, stamp(0))
        // The tenth sample moves the cut-off past the oldest one, which a lookup at its time then no longer finds.
        feed(&p, id: request.id, upright(0), steps: 9...9)
        XCTAssertEqual(p.sample(at: stamp(0))?.timestamp, stamp(1))
        for step in 1...9 {
            XCTAssertEqual(p.sample(at: stamp(step))?.timestamp, stamp(step), "step \(step)")
        }
    }

    func testTheHistoryStaysBoundedOverALongRun() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...63)
        XCTAssertEqual(p.sampleCount, 64)
        // Newest is step 63; the cut-off is step 55. A lookup before that lands on step 55 if it is within reach
        // (one step, 0.0625 s) and finds nothing otherwise (two steps, 0.125 s, is beyond the 0.1 s reach).
        XCTAssertEqual(p.sample(at: stamp(55))?.timestamp, stamp(55))
        XCTAssertEqual(p.sample(at: stamp(54))?.timestamp, stamp(55))
        XCTAssertNil(p.sample(at: stamp(53)))
        XCTAssertNil(p.sample(at: stamp(40)))
        XCTAssertNil(p.sample(at: stamp(0)))
        XCTAssertEqual(p.latest?.timestamp, stamp(63))
    }

    func testAGapInTheSamplesLeavesOnlyTheNewSampleInTheHistory() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        feed(&p, id: request.id, upright(0), steps: 0...3)
        _ = p.process(makeInput(upright(0), at: stamp(3) + 5), streamID: request.id)
        XCTAssertNil(p.sample(at: stamp(3)))
        XCTAssertNil(p.sample(at: stamp(0)))
        XCTAssertEqual(p.sample(at: stamp(3) + 5)?.timestamp, stamp(3) + 5)
    }

    func testSamplesThatWereNotPublishedAreNotInTheHistory() {
        var p = MotionProcessor()
        let request = p.start(availability: bothFrames)
        _ = p.process(makeInput(upright(0), at: stamp(0)), streamID: request.id)
        let scaled = Matrix3(rows: Vector3(2, 0, 0), Vector3(0, 2, 0), Vector3(0, 0, 2))
        _ = p.process(makeInput(scaled, at: stamp(1)), streamID: request.id)
        XCTAssertEqual(p.sampleCount, 2)
        XCTAssertEqual(p.latest?.timestamp, stamp(0))
        XCTAssertEqual(p.sample(at: stamp(1))?.timestamp, stamp(0))
    }
}

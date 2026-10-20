import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// A stand-in for `MotionService` that hands out scripted samples, the way the Aim frame engine's tests do.
private struct MotionScriptedSource: MotionSampleSource {
    let samples: [MotionSample]

    func latestSample() -> MotionSample? { samples.last }

    func sample(at time: TimeInterval) -> MotionSample? {
        samples.first { abs($0.timestamp - time) <= 0.05 }
    }
}

final class MotionTypesTests: XCTestCase {
    private let ascending: [CompassQuality] = [.unavailable, .uncalibrated, .low, .medium, .high]

    private func makeSample(timestamp: TimeInterval, azimuth: Double = 0) throws -> MotionSample {
        let attitude = try XCTUnwrap(DeviceAttitude(matrix: .identity, referenceAzimuth: azimuth, timestamp: timestamp))
        return MotionSample(attitude: attitude, rawAttitude: attitude, gravity: Vector3(0, 0, -1), angularSpeed: 0.5,
                            magneticFieldMicrotesla: 48.5, compassQuality: .medium, timestamp: timestamp)
    }

    // MARK: CompassQuality

    func testCompassQualityIsOrderedFromUnavailableToHigh() {
        for (i, a) in ascending.enumerated() {
            for (j, b) in ascending.enumerated() {
                XCTAssertEqual(a < b, i < j, "\(a) < \(b)")
                XCTAssertEqual(a <= b, i <= j, "\(a) <= \(b)")
                XCTAssertEqual(a > b, i > j, "\(a) > \(b)")
                XCTAssertEqual(a >= b, i >= j, "\(a) >= \(b)")
            }
        }
    }

    func testCompassQualitiesSortAndHaveExtremes() {
        let shuffled: [CompassQuality] = [.medium, .high, .unavailable, .low, .uncalibrated]
        XCTAssertEqual(shuffled.sorted(), ascending)
        XCTAssertEqual(shuffled.max(), .high)
        XCTAssertEqual(shuffled.min(), .unavailable)
    }

    func testCalibrationThresholdsSitBetweenTheRightLevels() {
        // The processor shows a field disturbance from `.low` up and clears a calibration request from `.medium` up.
        XCTAssertFalse(CompassQuality.uncalibrated >= .low)
        XCTAssertTrue(CompassQuality.low >= .low)
        XCTAssertFalse(CompassQuality.low >= .medium)
        XCTAssertTrue(CompassQuality.medium >= .medium)
        XCTAssertTrue(CompassQuality.high >= .medium)
        XCTAssertFalse(CompassQuality.unavailable >= .uncalibrated)
    }

    func testCompassQualityRawValuesAreTheCaseNames() {
        XCTAssertEqual(ascending.map(\.rawValue), ["unavailable", "uncalibrated", "low", "medium", "high"])
        XCTAssertEqual(CompassQuality(rawValue: "medium"), .medium)
        XCTAssertNil(CompassQuality(rawValue: "excellent"))
    }

    // MARK: MotionStatus and MagneticReference

    func testMotionStatusCasesAreDistinct() {
        let all: [MotionStatus] = [.idle, .starting, .running, .unavailable, .failed("x")]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() {
                XCTAssertEqual(a == b, i == j, "\(a) == \(b)")
            }
        }
    }

    func testAFailedStatusComparesByItsMessage() {
        XCTAssertEqual(MotionStatus.failed("Motion data stopped arriving."), .failed("Motion data stopped arriving."))
        XCTAssertNotEqual(MotionStatus.failed("a"), .failed("b"))
    }

    func testMagneticReferencesCompareByBothValues() {
        let reference = MagneticReference(declination: 10, expectedFieldMicrotesla: 50)
        XCTAssertEqual(reference, MagneticReference(declination: 10, expectedFieldMicrotesla: 50))
        XCTAssertNotEqual(reference, MagneticReference(declination: 10.5, expectedFieldMicrotesla: 50))
        XCTAssertNotEqual(reference, MagneticReference(declination: 10, expectedFieldMicrotesla: 49))
    }

    // MARK: MotionSample and MotionSampleSource

    func testASampleKeepsTheValuesItWasBuiltWith() throws {
        let sample = try makeSample(timestamp: 12.5, azimuth: 33)
        XCTAssertEqual(sample.attitude.referenceAzimuth, 33, accuracy: 1e-12)
        XCTAssertEqual(sample.rawAttitude.timestamp, 12.5)
        XCTAssertEqual(sample.gravity, Vector3(0, 0, -1))
        XCTAssertEqual(sample.angularSpeed, 0.5)
        XCTAssertEqual(sample.magneticFieldMicrotesla, 48.5)
        XCTAssertEqual(sample.compassQuality, .medium)
        XCTAssertEqual(sample.timestamp, 12.5)
    }

    func testASampleIsAValueAndAnEditedCopyLeavesTheOriginalAlone() throws {
        let original = try makeSample(timestamp: 1)
        var copy = original
        copy.timestamp = 2
        copy.magneticFieldMicrotesla = nil
        copy.compassQuality = .low
        XCTAssertEqual(original.timestamp, 1)
        XCTAssertEqual(original.magneticFieldMicrotesla, 48.5)
        XCTAssertEqual(original.compassQuality, .medium)
        XCTAssertEqual(copy.timestamp, 2)
        XCTAssertNil(copy.magneticFieldMicrotesla)
    }

    func testASourceWithoutSamplesHasNoLatestSample() {
        let source: any MotionSampleSource = MotionScriptedSource(samples: [])
        XCTAssertNil(source.latestSample())
        XCTAssertNil(source.sample(at: 0))
    }

    func testAScriptedSourceServesLatestAndNearestSamples() throws {
        let first = try makeSample(timestamp: 10, azimuth: 1)
        let second = try makeSample(timestamp: 10.0625, azimuth: 2)
        let source: any MotionSampleSource = MotionScriptedSource(samples: [first, second])
        XCTAssertEqual(source.latestSample()?.timestamp, 10.0625)
        XCTAssertEqual(source.sample(at: 10.01)?.timestamp, 10)
        XCTAssertEqual(source.sample(at: 10.06)?.timestamp, 10.0625)
        XCTAssertNil(source.sample(at: 11))
    }
}

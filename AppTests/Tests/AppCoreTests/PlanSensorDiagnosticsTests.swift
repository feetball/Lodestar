import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// What the sensor diagnostics screen shows for one motion sample, and the World Magnetic Model's values it compares with.
///
/// Conventions (CoreMotion): the attitude matrix `M` satisfies `v_device = M . v_reference` with the reference axes
/// x = north, y = west, z = up, and the device axes x = right edge, y = top edge, z = out of the screen. The rows of `M`
/// are the device axes written in the reference frame. Gravity is the device-frame vector pointing down, in g.
final class PlanSensorDiagnosticsTests: XCTestCase {
    private let tolerance = 1e-9

    // MARK: Poses

    /// Lying flat on a table, screen up, top edge towards north: right = east = -y_ref, top = north, out = up.
    private func flatNorthMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
    }

    /// Lying flat, screen up, top edge towards east (so the right edge is towards south).
    private func flatEastMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
    }

    /// Lying flat, screen up, top edge towards south (so the right edge is towards west).
    private func flatSouthMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
    }

    /// Lying flat, screen up, top edge towards west (so the right edge is towards north).
    private func flatWestMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
    }

    /// Held upright in portrait with the back camera looking at the north horizon:
    /// right = east, top = up, out of the screen = south.
    private func uprightNorthMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
    }

    /// Held upright, camera looking at the east horizon: right = south, top = up, out of the screen = west.
    private func uprightEastMatrix() -> Matrix3 {
        Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
    }

    /// Upright but tipped back, so that the camera looks north at 45 degrees of altitude.
    private func raisedNorthMatrix() -> Matrix3 {
        let s = 0.5.squareRoot()
        return Matrix3(rows: Vector3(0, -1, 0), Vector3(-s, 0, s), Vector3(-s, 0, -s))
    }

    private let gravityFlat = Vector3(0, 0, -1)
    private let gravityUpright = Vector3(0, -1, 0)
    /// Gravity in the device frame for `raisedNorthMatrix()`: (0, -sqrt(1/2), sqrt(1/2)).
    private let gravityRaised = Vector3(0, -(0.5.squareRoot()), 0.5.squareRoot())

    private func makeSample(matrix: Matrix3, azimuth: Double = 0, gravity: Vector3, angularSpeed: Double = 0,
                            magneticField: Double? = nil, smoothedMatrix: Matrix3? = nil) throws -> MotionSample {
        let raw = try XCTUnwrap(DeviceAttitude(matrix: matrix, referenceAzimuth: azimuth, timestamp: 1))
        let smoothed = try XCTUnwrap(DeviceAttitude(matrix: smoothedMatrix ?? matrix, referenceAzimuth: azimuth, timestamp: 1))
        return MotionSample(attitude: smoothed, rawAttitude: raw, gravity: gravity, angularSpeed: angularSpeed,
                            magneticFieldMicrotesla: magneticField, compassQuality: .high, timestamp: 1)
    }

    private func snapshot(matrix: Matrix3, azimuth: Double = 0, gravity: Vector3, angularSpeed: Double = 0,
                          magneticField: Double? = nil, smoothedMatrix: Matrix3? = nil) throws -> SensorDiagnosticsSnapshot {
        SensorDiagnosticsSnapshot(sample: try makeSample(matrix: matrix, azimuth: azimuth, gravity: gravity,
                                                         angularSpeed: angularSpeed, magneticField: magneticField,
                                                         smoothedMatrix: smoothedMatrix))
    }

    // MARK: Thresholds

    func testTheTolerancesAreTheDocumentedOnes() {
        XCTAssertEqual(SensorDiagnosticsSnapshot.gravityTolerance, 0.05)
        XCTAssertEqual(SensorDiagnosticsSnapshot.poseDiscrimination, 0.1)
        XCTAssertEqual(SensorDiagnosticsSnapshot.flatTolerance, 10)
        XCTAssertEqual(SensorDiagnosticsSnapshot.boresightTolerance, 0.1)
    }

    // MARK: Values copied from the sample

    func testTheSnapshotCarriesTheSamplesRawValues() throws {
        let result = try snapshot(matrix: flatNorthMatrix(), azimuth: 12.5, gravity: gravityFlat, angularSpeed: 3.5,
                                  magneticField: 48.25)
        XCTAssertEqual(result.matrix, flatNorthMatrix())
        XCTAssertEqual(result.referenceAzimuth, 12.5, accuracy: tolerance)
        XCTAssertEqual(result.gravity, gravityFlat)
        XCTAssertEqual(result.angularSpeed, 3.5)
        XCTAssertEqual(result.magneticFieldMicrotesla, 48.25)
    }

    func testAMissingMagneticFieldStaysMissing() throws {
        let result = try snapshot(matrix: flatNorthMatrix(), gravity: gravityFlat)
        XCTAssertNil(result.magneticFieldMicrotesla)
    }

    func testTheSnapshotUsesTheUnsmoothedAttitude() throws {
        // The smoothed attitude looks east, the raw one north: the boresight must follow the raw one.
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: gravityUpright,
                                  smoothedMatrix: uprightEastMatrix())
        XCTAssertEqual(result.boresightInFrame.azimuth, 0, accuracy: 1e-6)
        XCTAssertEqual(result.matrix, uprightNorthMatrix())
    }

    // MARK: Boresight

    func testUprightTowardsNorthLooksAtTheNorthHorizon() throws {
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: gravityUpright)
        XCTAssertEqual(result.boresightInFrame.azimuth, 0, accuracy: 1e-6)
        XCTAssertEqual(result.boresightInFrame.altitude, 0, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.azimuth, 0, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.altitude, 0, accuracy: 1e-6)
    }

    func testUprightTowardsEastLooksAtTheEastHorizon() throws {
        let result = try snapshot(matrix: uprightEastMatrix(), gravity: gravityUpright)
        XCTAssertEqual(result.boresightInFrame.azimuth, 90, accuracy: 1e-6)
        XCTAssertEqual(result.boresightInFrame.altitude, 0, accuracy: 1e-6)
    }

    func testTheReferenceAzimuthIsAddedToTheBoresightAzimuth() throws {
        let result = try snapshot(matrix: uprightEastMatrix(), azimuth: 20, gravity: gravityUpright)
        XCTAssertEqual(result.boresightInFrame.azimuth, 90, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.azimuth, 110, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.altitude, 0, accuracy: 1e-6)
    }

    func testTheBoresightAzimuthWrapsIntoZeroToThreeSixty() throws {
        // 0 degrees in the frame plus a reference azimuth of -30 is 330 degrees, not -30.
        let result = try snapshot(matrix: uprightNorthMatrix(), azimuth: -30, gravity: gravityUpright)
        XCTAssertEqual(result.boresightInFrame.azimuth, 0, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.azimuth, 330, accuracy: 1e-6)
        XCTAssertTrue(result.boresightsAgree)
    }

    func testTippingTheCameraBackRaisesTheBoresight() throws {
        let result = try snapshot(matrix: raisedNorthMatrix(), gravity: gravityRaised)
        XCTAssertEqual(result.boresightInFrame.altitude, 45, accuracy: 1e-6)
        XCTAssertEqual(result.boresightInFrame.azimuth, 0, accuracy: 1e-6)
    }

    func testTheMatrixBoresightAgreesWithLodestarKit() throws {
        for azimuth in [0.0, 7.5, 20.0, -35.0, 179.0] {
            let upright = try snapshot(matrix: uprightEastMatrix(), azimuth: azimuth, gravity: gravityUpright)
            XCTAssertEqual(upright.boresightDisagreement, 0, accuracy: 1e-6, "azimuth \(azimuth)")
            XCTAssertTrue(upright.boresightsAgree)
            let raised = try snapshot(matrix: raisedNorthMatrix(), azimuth: azimuth,
                                      gravity: gravityRaised)
            XCTAssertEqual(raised.boresightDisagreement, 0, accuracy: 1e-6, "azimuth \(azimuth)")
            XCTAssertTrue(raised.boresightsAgree)
        }
    }

    func testTheRaisedBoresightAlsoAgreesWithLodestarKitOnItsAzimuth() throws {
        let result = try snapshot(matrix: raisedNorthMatrix(), azimuth: 20,
                                  gravity: gravityRaised)
        XCTAssertEqual(result.boresight.azimuth, 20, accuracy: 1e-6)
        XCTAssertEqual(result.boresight.altitude, 45, accuracy: 1e-6)
    }

    // MARK: Gravity verdict

    func testGravityThatMatchesTheAssumedMappingPasses() throws {
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: gravityUpright)
        XCTAssertEqual(result.gravityVerdict, .pass)
        XCTAssertEqual(result.referenceToDeviceResidual, 0, accuracy: tolerance)
        // The other hypothesis predicts (1, 0, 0), which is 2^(1/2) g away from (0, -1, 0).
        XCTAssertEqual(result.deviceToReferenceResidual, 2.0.squareRoot(), accuracy: tolerance)
    }

    func testGravityThatMatchesTheTransposedMappingFails() throws {
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: Vector3(1, 0, 0))
        XCTAssertEqual(result.gravityVerdict, .fail)
        XCTAssertEqual(result.deviceToReferenceResidual, 0, accuracy: tolerance)
        XCTAssertEqual(result.referenceToDeviceResidual, 2.0.squareRoot(), accuracy: tolerance)
    }

    func testGravityPointingTheWrongWayFails() throws {
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: Vector3(0, 1, 0))
        XCTAssertEqual(result.gravityVerdict, .fail)
        XCTAssertEqual(result.referenceToDeviceResidual, 2, accuracy: tolerance)
    }

    func testTheGravityToleranceIsFiveHundredthsOfAG() throws {
        let within = try snapshot(matrix: uprightNorthMatrix(), gravity: Vector3(0, -1, 0.04))
        XCTAssertEqual(within.gravityVerdict, .pass)
        XCTAssertEqual(within.referenceToDeviceResidual, 0.04, accuracy: tolerance)
        let beyond = try snapshot(matrix: uprightNorthMatrix(), gravity: Vector3(0, -1, 0.06))
        XCTAssertEqual(beyond.gravityVerdict, .fail)
        XCTAssertEqual(beyond.referenceToDeviceResidual, 0.06, accuracy: tolerance)
    }

    func testTheRaisedPoseIsRecognisedAsPassing() throws {
        let s = 0.5.squareRoot()
        let result = try snapshot(matrix: raisedNorthMatrix(), gravity: Vector3(0, -s, s))
        XCTAssertEqual(result.gravityVerdict, .pass)
        XCTAssertEqual(result.referenceToDeviceResidual, 0, accuracy: 1e-9)
        // The transposed mapping would predict (s, 0, s): the distance to (0, -s, s) is 1.
        XCTAssertEqual(result.deviceToReferenceResidual, 1, accuracy: 1e-9)
    }

    func testAFlatPoseCannotTellTheMappingsApart() throws {
        let result = try snapshot(matrix: flatNorthMatrix(), gravity: gravityFlat)
        XCTAssertEqual(result.gravityVerdict, .inconclusive)
        XCTAssertEqual(result.referenceToDeviceResidual, 0, accuracy: tolerance)
        XCTAssertEqual(result.deviceToReferenceResidual, 0, accuracy: tolerance)
    }

    func testAFlatPoseIsInconclusiveEvenWithWrongGravity() throws {
        // The verdict depends on the matrix alone being ambiguous, not on the measurement.
        let result = try snapshot(matrix: flatNorthMatrix(), gravity: Vector3(0, 0, 1))
        XCTAssertEqual(result.gravityVerdict, .inconclusive)
        XCTAssertEqual(result.referenceToDeviceResidual, 2, accuracy: tolerance)
    }

    // MARK: Tilt and top-edge heading

    func testALevelPhoneIsFlat() throws {
        let result = try snapshot(matrix: flatNorthMatrix(), gravity: gravityFlat)
        XCTAssertEqual(result.tiltFromFlat, 0, accuracy: 1e-6)
        XCTAssertTrue(result.isFlat)
    }

    func testAnUprightPhoneIsNinetyDegreesFromFlat() throws {
        let result = try snapshot(matrix: uprightNorthMatrix(), gravity: gravityUpright)
        XCTAssertEqual(result.tiltFromFlat, 90, accuracy: 1e-6)
        XCTAssertFalse(result.isFlat)
    }

    func testAPhoneFaceDownIsOneHundredEightyDegreesFromFlat() throws {
        let result = try snapshot(matrix: flatNorthMatrix(), gravity: Vector3(0, 0, 1))
        XCTAssertEqual(result.tiltFromFlat, 180, accuracy: 1e-6)
        XCTAssertFalse(result.isFlat)
    }

    func testTheFlatLimitIsTenDegreesOfTilt() throws {
        func gravity(tiltDegrees: Double) -> Vector3 {
            Vector3(0, -sin(tiltDegrees * .pi / 180), -cos(tiltDegrees * .pi / 180))
        }
        let nearlyFlat = try snapshot(matrix: flatNorthMatrix(), gravity: gravity(tiltDegrees: 9))
        XCTAssertEqual(nearlyFlat.tiltFromFlat, 9, accuracy: 1e-6)
        XCTAssertTrue(nearlyFlat.isFlat)
        let tilted = try snapshot(matrix: flatNorthMatrix(), gravity: gravity(tiltDegrees: 11))
        XCTAssertEqual(tilted.tiltFromFlat, 11, accuracy: 1e-6)
        XCTAssertFalse(tilted.isFlat)
    }

    func testTheTopEdgeHeadingOfAFlatPhoneFollowsWhereTheTopEdgePoints() throws {
        let cases: [(Matrix3, Double)] = [
            (flatNorthMatrix(), 0), (flatEastMatrix(), 90), (flatSouthMatrix(), 180), (flatWestMatrix(), 270),
        ]
        for (matrix, expected) in cases {
            let result = try snapshot(matrix: matrix, gravity: gravityFlat)
            XCTAssertEqual(result.topEdgeHeadingInFrame, expected, accuracy: 1e-6, "expected \(expected)")
            XCTAssertEqual(result.topEdgeHeading, expected, accuracy: 1e-6, "expected \(expected)")
        }
    }

    func testTheReferenceAzimuthIsAddedToTheTopEdgeHeading() throws {
        let east = try snapshot(matrix: flatEastMatrix(), azimuth: 30, gravity: gravityFlat)
        XCTAssertEqual(east.topEdgeHeadingInFrame, 90, accuracy: 1e-6)
        XCTAssertEqual(east.topEdgeHeading, 120, accuracy: 1e-6)
        let north = try snapshot(matrix: flatNorthMatrix(), azimuth: -20, gravity: gravityFlat)
        XCTAssertEqual(north.topEdgeHeadingInFrame, 0, accuracy: 1e-6)
        XCTAssertEqual(north.topEdgeHeading, 340, accuracy: 1e-6)
        let west = try snapshot(matrix: flatWestMatrix(), azimuth: 150, gravity: gravityFlat)
        XCTAssertEqual(west.topEdgeHeading, 60, accuracy: 1e-6)
    }

    // MARK: MotionTypes

    func testCompassQualityIsOrderedFromUnavailableToHigh() {
        let ordered: [CompassQuality] = [.unavailable, .uncalibrated, .low, .medium, .high]
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(lower, higher)
            XCTAssertGreaterThan(higher, lower)
            XCTAssertFalse(higher < lower)
        }
        XCTAssertLessThanOrEqual(CompassQuality.medium, .medium)
        XCTAssertEqual(ordered.reversed().sorted(), ordered)
        XCTAssertEqual(ordered.max(), .high)
        XCTAssertEqual(ordered.min(), .unavailable)
    }

    func testCompassQualityRawValues() {
        XCTAssertEqual(CompassQuality.unavailable.rawValue, "unavailable")
        XCTAssertEqual(CompassQuality.uncalibrated.rawValue, "uncalibrated")
        XCTAssertEqual(CompassQuality.high.rawValue, "high")
        XCTAssertEqual(CompassQuality(rawValue: "medium"), .medium)
        XCTAssertNil(CompassQuality(rawValue: "excellent"))
    }

    func testMotionStatusesCompareByCaseAndMessage() {
        XCTAssertEqual(MotionStatus.idle, .idle)
        XCTAssertEqual(MotionStatus.failed("no sensor"), .failed("no sensor"))
        XCTAssertNotEqual(MotionStatus.failed("no sensor"), .failed("denied"))
        XCTAssertNotEqual(MotionStatus.idle, .starting)
        XCTAssertNotEqual(MotionStatus.running, .unavailable)
        XCTAssertNotEqual(MotionStatus.failed("idle"), .idle)
    }

    func testMagneticReferencesCompareByBothValues() {
        let reference = MagneticReference(declination: 7.5, expectedFieldMicrotesla: 52)
        XCTAssertEqual(reference, MagneticReference(declination: 7.5, expectedFieldMicrotesla: 52))
        XCTAssertNotEqual(reference, MagneticReference(declination: -7.5, expectedFieldMicrotesla: 52))
        XCTAssertNotEqual(reference, MagneticReference(declination: 7.5, expectedFieldMicrotesla: 50))
    }

    // MARK: The magnetic model at the observer

    /// Midday UTC on 2 July 2025, which is exactly decimal year 2025.5.
    private let midValidity = Date(timeIntervalSince1970: 1_751_457_600)
    private let denver = GeographicLocation(latitude: 39.7, longitude: -105.0, elevation: 1600)

    func testTheModelGivesTheFieldAtTheObserver() throws {
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: midValidity))
        XCTAssertTrue(model.isCurrent)
        XCTAssertEqual(model.reliability, .reliable)
        // Denver: about 52 microtesla in total, 21 horizontal, dipping 66 degrees, declination 7 to 8 degrees east.
        XCTAssertGreaterThan(model.expectedFieldMicrotesla, 48)
        XCTAssertLessThan(model.expectedFieldMicrotesla, 57)
        XCTAssertGreaterThan(model.horizontalFieldMicrotesla, 17)
        XCTAssertLessThan(model.horizontalFieldMicrotesla, 25)
        XCTAssertGreaterThan(model.inclination, 60)
        XCTAssertLessThan(model.inclination, 72)
        XCTAssertGreaterThan(model.declination, 3)
        XCTAssertLessThan(model.declination, 12)
    }

    func testTheHorizontalFieldIsTheTotalFieldTimesTheCosineOfTheInclination() throws {
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: midValidity))
        XCTAssertEqual(model.horizontalFieldMicrotesla,
                       model.expectedFieldMicrotesla * cos(model.inclination * .pi / 180), accuracy: 1e-6)
    }

    func testTheFieldPointsUpInTheSouthernHemisphere() throws {
        let sydney = GeographicLocation(latitude: -33.9, longitude: 151.2, elevation: 20)
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: sydney, date: midValidity))
        XCTAssertLessThan(model.inclination, 0)
        XCTAssertEqual(model.reliability, .reliable)
        XCTAssertTrue(model.isCurrent)
    }

    func testTheModelIsCurrentUpToTheLastSecondOf2029() throws {
        // 2030-01-01 00:00:00 UTC is 1_893_456_000 seconds after the epoch.
        let lastSecond = Date(timeIntervalSince1970: 1_893_455_999)
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: lastSecond))
        XCTAssertTrue(model.isCurrent)
    }

    func testTheModelExpiresOnTheFirstOfJanuary2030() throws {
        let expiry = Date(timeIntervalSince1970: 1_893_456_000)
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: expiry))
        XCTAssertFalse(model.isCurrent)
        // The field is still extrapolated and valid, just flagged as out of date.
        XCTAssertGreaterThan(model.expectedFieldMicrotesla, 40)
    }

    func testTheModelIsNotCurrentInTheMiddleOf2031() throws {
        let later = Date(timeIntervalSince1970: 1_924_992_000 + 181 * 86_400)
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: later))
        XCTAssertFalse(model.isCurrent)
        XCTAssertEqual(model.reliability, .reliable)
    }

    func testTheModelIsNotCurrentBeforeItsFirstYear() throws {
        // 2024-06-01 00:00:00 UTC.
        let earlier = Date(timeIntervalSince1970: 1_717_200_000)
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: earlier))
        XCTAssertFalse(model.isCurrent)
    }

    func testAnExpiredModelStillReportsTheLocalField() throws {
        let current = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: midValidity))
        let expired = try XCTUnwrap(SensorDiagnosticsMagneticModel(
            location: denver, date: Date(timeIntervalSince1970: 1_924_992_000 + 181 * 86_400)))
        // Six years of secular variation move the field by a few percent at most.
        XCTAssertEqual(expired.expectedFieldMicrotesla, current.expectedFieldMicrotesla, accuracy: 3)
        XCTAssertEqual(expired.declination, current.declination, accuracy: 3)
    }

    func testNoModelWhenTheDateHasNoYear() {
        XCTAssertNil(SensorDiagnosticsMagneticModel(location: denver, date: Date(timeIntervalSince1970: .nan)))
        XCTAssertNil(SensorDiagnosticsMagneticModel(location: denver, date: Date(timeIntervalSince1970: .infinity)))
        XCTAssertNil(SensorDiagnosticsMagneticModel(location: denver, date: Date(timeIntervalSince1970: -.infinity)))
        // Beyond about 300,000 years from 1970 the year cannot be worked out.
        XCTAssertNil(SensorDiagnosticsMagneticModel(location: denver, date: Date(timeIntervalSince1970: 1e14)))
    }

    // MARK: Deviation of a measured field

    func testDeviationIsTheRelativeDistanceFromTheExpectedField() throws {
        let model = try XCTUnwrap(SensorDiagnosticsMagneticModel(location: denver, date: midValidity))
        let expected = model.expectedFieldMicrotesla
        XCTAssertEqual(model.deviation(ofMeasured: expected), 0, accuracy: tolerance)
        XCTAssertEqual(model.deviation(ofMeasured: expected * 1.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(model.deviation(ofMeasured: expected * 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(model.deviation(ofMeasured: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(model.deviation(ofMeasured: expected * 3), 2, accuracy: 1e-9)
    }
}

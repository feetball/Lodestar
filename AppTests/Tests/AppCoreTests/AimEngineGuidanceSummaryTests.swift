import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `AimGuidanceSummary`: what the guidance asks of the photographer, in words and numbers.
///
/// The guidance values come from a real `GuidanceTracker` and `PointingSolution`: a phone held upright aims the back
/// camera at the place the test chooses, and the target is another place. The on-target threshold is 1.5 degrees.
final class AimEngineGuidanceSummaryTests: XCTestCase {
    // MARK: Helpers

    private func makeAttitude(azimuth: Double, altitude: Double) throws -> DeviceAttitude {
        let az = AstroMath.radians(azimuth), alt = AstroMath.radians(altitude)
        let forward = Vector3(cos(alt) * sin(az), cos(alt) * cos(az), sin(alt))
        let right = Vector3(cos(az), -sin(az), 0)
        let up = Vector3(-sin(alt) * sin(az), -sin(alt) * cos(az), cos(alt))
        // The rows of the CoreMotion matrix are the device axes in the north-west-up frame.
        func row(_ axis: Vector3) -> Vector3 { Vector3(axis.y, -axis.x, axis.z) }
        return try XCTUnwrap(DeviceAttitude(matrix: Matrix3(rows: row(right), row(up), row(forward * -1)),
                                            referenceAzimuth: 0, timestamp: 0))
    }

    /// The guidance for a camera aimed at `look` (azimuth, altitude) and a target at `target`.
    private func makeGuidance(looking look: (Double, Double), at target: (Double, Double)) throws -> Guidance {
        let solution = PointingSolution.solve(attitude: try makeAttitude(azimuth: look.0, altitude: look.1),
                                              mount: .backCameraPortrait)
        var tracker = GuidanceTracker(onTargetThreshold: 1.5)
        return try XCTUnwrap(tracker.update(solution: solution,
                                            target: HorizontalCoordinate(azimuth: target.0, altitude: target.1)))
    }

    private func makeSummary(looking look: (Double, Double), at target: (Double, Double)) throws -> AimGuidanceSummary {
        AimGuidanceSummary(try makeGuidance(looking: look, at: target))
    }

    // MARK: The movements

    func testATargetToTheRightAndAboveAsksForAPanRightAndATiltUp() throws {
        let summary = try makeSummary(looking: (90, 0), at: (113, 12))
        XCTAssertEqual(summary.pan.verb, "Pan right")
        XCTAssertEqual(summary.pan.systemImage, "arrow.right")
        XCTAssertEqual(summary.pan.degrees, 23, accuracy: 1e-6)
        XCTAssertEqual(summary.tilt.verb, "Tilt up")
        XCTAssertEqual(summary.tilt.systemImage, "arrow.up")
        XCTAssertEqual(summary.tilt.degrees, 12, accuracy: 1e-6)
    }

    func testATargetToTheLeftAndBelowAsksForAPanLeftAndATiltDown() throws {
        let summary = try makeSummary(looking: (200, 40), at: (170, 25))
        XCTAssertEqual(summary.pan.verb, "Pan left")
        XCTAssertEqual(summary.pan.systemImage, "arrow.left")
        XCTAssertEqual(summary.pan.degrees, 30, accuracy: 1e-6)
        XCTAssertEqual(summary.tilt.verb, "Tilt down")
        XCTAssertEqual(summary.tilt.systemImage, "arrow.down")
        XCTAssertEqual(summary.tilt.degrees, 15, accuracy: 1e-6)
    }

    func testTheMovementsMixDirections() throws {
        let rightAndDown = try makeSummary(looking: (90, 40), at: (100, 30))
        XCTAssertEqual(rightAndDown.pan.verb, "Pan right")
        XCTAssertEqual(rightAndDown.tilt.verb, "Tilt down")
        let leftAndUp = try makeSummary(looking: (90, 40), at: (80, 50))
        XCTAssertEqual(leftAndUp.pan.verb, "Pan left")
        XCTAssertEqual(leftAndUp.tilt.verb, "Tilt up")
    }

    func testThePanTakesTheShortWayRoundTheCompass() throws {
        // From azimuth 350 to azimuth 10 is 20 degrees to the right, not 340 to the left.
        let across = try makeSummary(looking: (350, 30), at: (10, 30))
        XCTAssertEqual(across.pan.verb, "Pan right")
        XCTAssertEqual(across.pan.degrees, 20, accuracy: 1e-6)
        let back = try makeSummary(looking: (10, 30), at: (350, 30))
        XCTAssertEqual(back.pan.verb, "Pan left")
        XCTAssertEqual(back.pan.degrees, 20, accuracy: 1e-6)
    }

    func testTheSeparationIsTheAngleBetweenWhereTheCameraPointsAndTheTarget() throws {
        let summary = try makeSummary(looking: (90, 0), at: (113, 12))
        // cos(separation) = cos 12 degrees * cos 23 degrees.
        XCTAssertEqual(summary.separation, 25.79, accuracy: 0.01)
        let straightUp = try makeSummary(looking: (90, 30), at: (90, 86))
        XCTAssertEqual(straightUp.separation, 56, accuracy: 1e-6)
    }

    func testTheSummaryTakesItsNumbersFromTheGuidance() throws {
        let guidance = try makeGuidance(looking: (200, 40), at: (170, 25))
        let summary = AimGuidanceSummary(guidance)
        XCTAssertEqual(summary.pan.degrees, abs(guidance.panDelta))
        XCTAssertEqual(summary.tilt.degrees, abs(guidance.tiltDelta))
        XCTAssertEqual(summary.separation, guidance.separation)
        XCTAssertEqual(summary.isNearZenith, guidance.isNearZenith)
        XCTAssertEqual(summary.isBelowHorizon, guidance.targetBelowHorizon)
        XCTAssertEqual(summary.isOnTarget, guidance.state == .onTarget)
    }

    // MARK: On target

    func testWithinTheThresholdTheCameraIsOnTarget() throws {
        let summary = try makeSummary(looking: (90, 20), at: (90.5, 20.2))
        XCTAssertTrue(summary.isOnTarget)
        XCTAssertEqual(summary.separation, 0.51, accuracy: 0.01)
        XCTAssertEqual(summary.spokenText, "On target")
    }

    func testBeyondTheThresholdTheCameraIsNotOnTargetEvenWhenClose() throws {
        // About 3.5 degrees away: close, but not on target.
        let summary = try makeSummary(looking: (90, 20), at: (92, 23))
        XCTAssertFalse(summary.isOnTarget)
        XCTAssertEqual(summary.separation, 3.53, accuracy: 0.01)
        XCTAssertEqual(summary.spokenText, "Pan right 2 degrees, tilt up 3 degrees, 4 degrees away")
    }

    func testOnTargetBeatsEverythingElseInTheSpokenText() throws {
        // Near the zenith, a few arcminutes off: still just "On target".
        let summary = try makeSummary(looking: (0, 88), at: (0.5, 88))
        XCTAssertTrue(summary.isNearZenith)
        XCTAssertTrue(summary.isOnTarget)
        XCTAssertEqual(summary.spokenText, "On target")
    }

    // MARK: Spoken text

    func testTheSpokenTextNamesBothMovementsAndTheDistance() throws {
        XCTAssertEqual(try makeSummary(looking: (90, 0), at: (113, 12)).spokenText,
                       "Pan right 23 degrees, tilt up 12 degrees, 26 degrees away")
        XCTAssertEqual(try makeSummary(looking: (200, 40), at: (170, 25)).spokenText,
                       "Pan left 30 degrees, tilt down 15 degrees, 29 degrees away")
    }

    func testTheSpokenTextSaysOneDegreeAndUnderOneDegree() throws {
        XCTAssertEqual(try makeSummary(looking: (90, 20), at: (91.2, 24)).spokenText,
                       "Pan right 1 degree, tilt up 4 degrees, 4 degrees away")
        XCTAssertEqual(try makeSummary(looking: (90, 20), at: (90.3, 24)).spokenText,
                       "Pan right under one degree, tilt up 4 degrees, 4 degrees away")
    }

    // MARK: Near the zenith

    func testNearTheZenithOnlyTheArrowAndTheSeparationAreSpoken() throws {
        let summary = try makeSummary(looking: (0, 88), at: (90, 88))
        XCTAssertTrue(summary.isNearZenith)
        XCTAssertFalse(summary.isOnTarget)
        XCTAssertEqual(summary.separation, 2.83, accuracy: 0.01)
        XCTAssertEqual(summary.spokenText, "Near the zenith, follow the arrow, 3 degrees away")
    }

    func testATargetNearTheZenithAlsoMakesItNearTheZenith() throws {
        let summary = try makeSummary(looking: (90, 30), at: (90, 86))
        XCTAssertTrue(summary.isNearZenith)
        XCTAssertEqual(summary.spokenText, "Near the zenith, follow the arrow, 56 degrees away")
    }

    func testTheZenithLimitIsEightyFiveDegreesOfAltitude() throws {
        XCTAssertFalse(try makeSummary(looking: (90, 30), at: (95, 85)).isNearZenith)
        XCTAssertTrue(try makeSummary(looking: (90, 30), at: (95, 85.1)).isNearZenith)
        XCTAssertFalse(try makeSummary(looking: (90, 84.9), at: (95, 30)).isNearZenith)
        XCTAssertTrue(try makeSummary(looking: (90, 85.1), at: (95, 30)).isNearZenith)
        // Below the limit the movements are spoken as usual.
        XCTAssertEqual(try makeSummary(looking: (90, 30), at: (95, 85)).spokenText,
                       "Pan right 5 degrees, tilt up 55 degrees, 55 degrees away")
    }

    func testTheNadirCountsAsNearTheZenithToo() throws {
        XCTAssertTrue(try makeSummary(looking: (90, -86), at: (95, 30)).isNearZenith)
        XCTAssertTrue(try makeSummary(looking: (90, 30), at: (95, -86)).isNearZenith)
    }

    // MARK: Below the horizon

    func testATargetBelowTheHorizonIsFlagged() throws {
        let summary = try makeSummary(looking: (90, 0), at: (100, -5))
        XCTAssertTrue(summary.isBelowHorizon)
        XCTAssertEqual(summary.tilt.verb, "Tilt down")
        XCTAssertEqual(summary.spokenText, "Pan right 10 degrees, tilt down 5 degrees, 11 degrees away")
    }

    func testATargetOnTheHorizonOrAboveIsNotBelowIt() throws {
        let onHorizon = try makeSummary(looking: (90, 10), at: (100, 0))
        XCTAssertFalse(onHorizon.isBelowHorizon)
        XCTAssertEqual(onHorizon.spokenText, "Pan right 10 degrees, tilt down 10 degrees, 14 degrees away")
        XCTAssertFalse(try makeSummary(looking: (90, 10), at: (100, 40)).isBelowHorizon)
        XCTAssertTrue(try makeSummary(looking: (90, 10), at: (100, -0.5)).isBelowHorizon)
    }

    func testThePhoneCanLookBelowTheHorizonAtATargetAboveIt() throws {
        let summary = try makeSummary(looking: (90, -20), at: (90.4, 20))
        XCTAssertFalse(summary.isBelowHorizon)
        XCTAssertEqual(summary.tilt.verb, "Tilt up")
        XCTAssertEqual(summary.tilt.degrees, 40, accuracy: 1e-6)
    }
}

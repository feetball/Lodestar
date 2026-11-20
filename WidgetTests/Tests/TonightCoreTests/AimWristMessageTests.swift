import XCTest
@testable import TonightCore

final class AimWristMessageTests: XCTestCase {
    /// A message as the iPhone app builds it (`WatchAimLink.message`).
    private func message(pan: Double = 12, tilt: Double = 3, separation: Double = 12.4, state: String = "far",
                         below: Bool = false, zenith: Bool = false, night: Bool = false,
                         target: String = "Orion Nebula") -> [String: Any] {
        ["aim": 1, "sent": 1_700_000_000.5, "pan": pan, "tilt": tilt, "sep": separation, "state": state,
         "below": below, "zenith": zenith, "night": night, "target": target]
    }

    private func decoded(_ message: [String: Any]) throws -> AimWristMessage {
        try XCTUnwrap(AimWristMessage.decode(message))
    }

    // MARK: Decoding

    func testAWellFormedMessageIsDecoded() throws {
        let m = try decoded(message(night: true))
        XCTAssertEqual(m.sent, 1_700_000_000.5)
        XCTAssertEqual(m.pan, 12)
        XCTAssertEqual(m.tilt, 3)
        XCTAssertEqual(m.separation, 12.4)
        XCTAssertEqual(m.state, .far)
        XCTAssertFalse(m.isBelowHorizon)
        XCTAssertFalse(m.isNearZenith)
        XCTAssertTrue(m.isNight)
        XCTAssertEqual(m.targetName, "Orion Nebula")
    }

    func testMissingOptionalFlagsFallBack() throws {
        var raw = message()
        for key in ["below", "zenith", "night", "target"] { raw[key] = nil }
        let m = try decoded(raw)
        XCTAssertFalse(m.isBelowHorizon || m.isNearZenith || m.isNight)
        XCTAssertEqual(m.targetName, "")
    }

    func testMessagesThatAreNotAimMessagesAreDropped() {
        XCTAssertNil(AimWristMessage.decode([:]))
        XCTAssertNil(AimWristMessage.decode(["lat": 36.0, "lon": -112.0]))
        var other = message()
        other["aim"] = 2
        XCTAssertNil(AimWristMessage.decode(other))
        other["aim"] = nil
        XCTAssertNil(AimWristMessage.decode(other))
    }

    func testValuesOutOfRangeOrNotFiniteAreDropped() {
        XCTAssertNil(AimWristMessage.decode(message(pan: .nan)))
        XCTAssertNil(AimWristMessage.decode(message(tilt: .infinity)))
        XCTAssertNil(AimWristMessage.decode(message(pan: 181)))
        XCTAssertNil(AimWristMessage.decode(message(tilt: -180.5)))
        XCTAssertNil(AimWristMessage.decode(message(separation: -1)))
        XCTAssertNil(AimWristMessage.decode(message(separation: 181)))
        XCTAssertNil(AimWristMessage.decode(message(state: "far away")))
        var wrongType = message()
        wrongType["pan"] = "12"
        XCTAssertNil(AimWristMessage.decode(wrongType))
        wrongType = message()
        wrongType["sent"] = Double.nan
        XCTAssertNil(AimWristMessage.decode(wrongType))
    }

    func testALongTargetNameIsCut() throws {
        let m = try decoded(message(target: String(repeating: "x", count: 500)))
        XCTAssertEqual(m.targetName.count, AimWristMessage.maximumNameLength)
    }

    // MARK: The arrow

    func testTheArrowPointsAlongThePanAndTiltAxes() throws {
        XCTAssertEqual(try decoded(message(pan: 10, tilt: 0)).arrowAngle, 0, accuracy: 1e-12)
        XCTAssertEqual(try decoded(message(pan: 0, tilt: 10)).arrowAngle, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try decoded(message(pan: -10, tilt: 0)).arrowAngle, .pi, accuracy: 1e-12)
        XCTAssertEqual(try decoded(message(pan: 0, tilt: -10)).arrowAngle, -.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try decoded(message(pan: 10, tilt: 10)).arrowAngle, .pi / 4, accuracy: 1e-12)
    }

    func testNearTheZenithTheArrowFollowsTheTiltOnly() throws {
        XCTAssertEqual(try decoded(message(pan: 90, tilt: 3, zenith: true)).arrowAngle, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try decoded(message(pan: 90, tilt: -3, zenith: true)).arrowAngle, -.pi / 2, accuracy: 1e-12)
        // With no tilt to make, the pan is all there is.
        XCTAssertEqual(try decoded(message(pan: 90, tilt: 0.2, zenith: true)).arrowAngle, atan2(0.2, 90), accuracy: 1e-12)
    }

    // MARK: Words

    func testTheMovesAreInWholeDegrees() throws {
        XCTAssertEqual(try decoded(message(pan: 12.4, tilt: 2.6)).moves, ["Pan right 12\u{00B0}", "Tilt up 3\u{00B0}"])
        XCTAssertEqual(try decoded(message(pan: -12.5, tilt: -2.5)).moves, ["Pan left 13\u{00B0}", "Tilt down 3\u{00B0}"])
        XCTAssertEqual(try decoded(message(pan: 12.2, tilt: 0.4)).moves, ["Pan right 12\u{00B0}"])
        XCTAssertEqual(try decoded(message(pan: 0.3, tilt: 6)).moves, ["Tilt up 6\u{00B0}"])
    }

    func testNearTheZenithOnlyTheTiltIsListed() throws {
        XCTAssertEqual(try decoded(message(pan: 30, tilt: -3, zenith: true)).moves, ["Tilt down 3\u{00B0}"])
        XCTAssertEqual(try decoded(message(pan: 80, tilt: 0.2, separation: 2.5, zenith: true)).moves,
                       ["Pan right 80\u{00B0}"])
    }

    func testCloseToTheTargetItIsAlmostThere() throws {
        XCTAssertEqual(try decoded(message(pan: 1, tilt: 0.5, separation: 1.1, state: "close")).moves, ["Almost there"])
        XCTAssertEqual(try decoded(message(pan: 0.2, tilt: 0.1, separation: 2.5, state: "close")).moves, ["Almost there"])
    }

    func testTheDistanceHasADecimalOnlyBelowTenDegrees() throws {
        XCTAssertEqual(try decoded(message(separation: 26.4)).distanceText, "26\u{00B0} away")
        XCTAssertEqual(try decoded(message(separation: 9.96)).distanceText, "10.0\u{00B0} away")
        XCTAssertEqual(try decoded(message(separation: 3.2)).distanceText, "3.2\u{00B0} away")
    }

    func testOnTargetIsNotClaimedBelowTheHorizon() throws {
        let on = try decoded(message(pan: 0, tilt: 0, separation: 0.1, state: "onTarget"))
        XCTAssertTrue(on.isOnTarget)
        XCTAssertEqual(on.spokenSummary, "On target, Orion Nebula")
        let below = try decoded(message(pan: 0, tilt: 0, separation: 0.1, state: "onTarget", below: true))
        XCTAssertFalse(below.isOnTarget)
        XCTAssertEqual(below.spokenSummary, "Target is below the horizon")
    }

    func testTheSpokenSummaryNamesMovesDistanceAndTarget() throws {
        XCTAssertEqual(try decoded(message()).spokenSummary,
                       "Pan right 12\u{00B0}, Tilt up 3\u{00B0}, 12\u{00B0} away, Orion Nebula")
        XCTAssertEqual(try decoded(message(target: "")).spokenSummary, "Pan right 12\u{00B0}, Tilt up 3\u{00B0}, 12\u{00B0} away")
    }
}

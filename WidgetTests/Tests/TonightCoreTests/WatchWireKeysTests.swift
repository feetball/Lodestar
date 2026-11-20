import XCTest
import LodestarKit
@testable import TonightCore

/// What the iPhone app sends the watch and what the watch reads, held together by the keys they share. The phone side's
/// own code (`WatchAimLink`, `WatchObserverLink`) cannot be built here; it only calls what these tests cover.
final class WatchWireKeysTests: XCTestCase {
    private func aim(state: AimWristMessage.State = .close, target: String = "Orion Nebula") -> AimWristMessage {
        AimWristMessage(sent: 1_700_000_000.5, pan: -12.5, tilt: 3.25, separation: 12.75, state: state,
                        isBelowHorizon: true, isNearZenith: true, isNight: true, targetName: target)
    }

    // MARK: Aim

    func testAnAimMessageIsDecodedAsItWasSent() throws {
        for state in [AimWristMessage.State.onTarget, .close, .far] {
            let sent = aim(state: state)
            XCTAssertEqual(AimWristMessage.decode(sent.wireMessage), sent)
        }
    }

    func testTheAimMessageKeepsTheKeysAndTypesTheWatchHasAlwaysRead() throws {
        let wire = aim().wireMessage
        XCTAssertEqual(Set(wire.keys),
                       ["aim", "sent", "pan", "tilt", "sep", "state", "below", "zenith", "night", "target"])
        XCTAssertEqual(wire["aim"] as? Int, 1)
        XCTAssertEqual(wire["sent"] as? Double, 1_700_000_000.5)
        XCTAssertEqual(wire["pan"] as? Double, -12.5)
        XCTAssertEqual(wire["tilt"] as? Double, 3.25)
        XCTAssertEqual(wire["sep"] as? Double, 12.75)
        XCTAssertEqual(wire["state"] as? String, "close")
        XCTAssertEqual(wire["below"] as? Bool, true)
        XCTAssertEqual(wire["zenith"] as? Bool, true)
        XCTAssertEqual(wire["night"] as? Bool, true)
        XCTAssertEqual(wire["target"] as? String, "Orion Nebula")
    }

    func testTheEnginesGuidanceStatesAreSentUnderTheirOwnNames() {
        for guidance in [GuidanceState.onTarget, .close, .far] {
            XCTAssertEqual(AimWristMessage.State(guidance).rawValue, guidance.rawValue)
        }
    }

    func testALongTargetNameIsCutBeforeItIsSent() throws {
        let wire = aim(target: String(repeating: "x", count: 500)).wireMessage
        XCTAssertEqual((wire["target"] as? String)?.count, AimWristMessage.maximumNameLength)
        XCTAssertEqual(try XCTUnwrap(AimWristMessage.decode(wire)).targetName.count, AimWristMessage.maximumNameLength)
    }

    // MARK: Observer

    func testTheObserverKeysAreThoseTheWatchHasAlwaysRead() {
        XCTAssertEqual(TonightPhoneContext.latitudeKey, "lat")
        XCTAssertEqual(TonightPhoneContext.longitudeKey, "lon")
        XCTAssertEqual(TonightPhoneContext.elevationKey, "elevation")
        XCTAssertEqual(TonightPhoneContext.timeZoneKey, "timeZone")
    }

    func testAnObserverContextBuiltFromTheSharedKeysIsReadAsAPlace() throws {
        let context: [String: Any] = [
            TonightPhoneContext.latitudeKey: 40.0, TonightPhoneContext.longitudeKey: -105.27,
            TonightPhoneContext.elevationKey: 1_650.0, TonightPhoneContext.timeZoneKey: "America/Denver",
        ]
        let place = try XCTUnwrap(TonightPhoneContext.place(from: context))
        XCTAssertEqual(place, TonightPlace(latitude: 40, longitude: -105.27, elevation: 1_650,
                                           timeZoneIdentifier: "America/Denver"))
    }
}

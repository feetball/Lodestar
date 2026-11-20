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
        XCTAssertEqual(TonightPhoneContext.kindKey, "kind")
        XCTAssertEqual(TonightPhoneContext.sentAtKey, "sentAt")
    }

    func testAnObserverContextTheIPhoneBuildsIsReadAsAPlace() throws {
        let place = try XCTUnwrap(TonightPlace(latitude: 40, longitude: -105.27, elevation: 1_650,
                                               timeZoneIdentifier: "America/Denver"))
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
        let phonePlace = TonightPhonePlace(place: place, kind: .savedSite, sentAt: sentAt)
        let context = TonightPhoneContext.context(for: phonePlace)
        XCTAssertEqual(Set(context.keys), ["lat", "lon", "elevation", "timeZone", "kind", "sentAt"])
        // The place has validated its coordinates, which may move the last digit of a longitude.
        XCTAssertEqual(context["lat"] as? Double, place.latitude)
        XCTAssertEqual(context["lon"] as? Double, place.longitude)
        XCTAssertEqual(context["elevation"] as? Double, 1_650)
        XCTAssertEqual(context["timeZone"] as? String, "America/Denver")
        XCTAssertEqual(context["kind"] as? String, "savedSite")
        XCTAssertEqual(context["sentAt"] as? Double, 1_800_000_000)
        XCTAssertEqual(TonightPhoneContext.place(from: context), place)
        XCTAssertEqual(TonightPhoneContext.phonePlace(from: context), phonePlace)
    }

    func testAnObserverContextWithoutASendTimeLeavesTheKeyOut() throws {
        let place = try XCTUnwrap(TonightPlace(latitude: -33.87, longitude: 151.21, elevation: 20,
                                               timeZoneIdentifier: "Australia/Sydney"))
        let context = TonightPhoneContext.context(for: TonightPhonePlace(place: place, kind: .device, sentAt: nil))
        XCTAssertEqual(Set(context.keys), ["lat", "lon", "elevation", "timeZone", "kind"])
        XCTAssertEqual(context["kind"] as? String, "device")
        XCTAssertEqual(TonightPhoneContext.place(from: context), place)
    }
}

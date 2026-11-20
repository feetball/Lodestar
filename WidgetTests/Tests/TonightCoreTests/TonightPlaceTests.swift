import XCTest
@testable import TonightCore

final class TonightPlaceTests: XCTestCase {
    func testAPlaceNeedsFiniteCoordinatesInRange() {
        XCTAssertNotNil(TonightPlace(latitude: 40, longitude: -105, elevation: 1650, timeZoneIdentifier: "America/Denver"))
        XCTAssertNil(TonightPlace(latitude: 91, longitude: 0, elevation: 0, timeZoneIdentifier: "UTC"))
        XCTAssertNil(TonightPlace(latitude: -91, longitude: 0, elevation: 0, timeZoneIdentifier: "UTC"))
        XCTAssertNil(TonightPlace(latitude: 0, longitude: 361, elevation: 0, timeZoneIdentifier: "UTC"))
        XCTAssertNil(TonightPlace(latitude: .nan, longitude: 0, elevation: 0, timeZoneIdentifier: "UTC"))
        XCTAssertNil(TonightPlace(latitude: 0, longitude: .infinity, elevation: 0, timeZoneIdentifier: "UTC"))
        XCTAssertNil(TonightPlace(latitude: 0, longitude: 0, elevation: .nan, timeZoneIdentifier: "UTC"))
    }

    func testElevationIsClampedAndAnUnknownTimeZoneBecomesTheDevices() throws {
        let place = try XCTUnwrap(TonightPlace(latitude: 10, longitude: 20, elevation: 50_000,
                                               timeZoneIdentifier: "Not/AZone"))
        XCTAssertEqual(place.elevation, 12_000)
        XCTAssertEqual(place.timeZoneIdentifier, TimeZone.current.identifier)
        let low = try XCTUnwrap(TonightPlace(latitude: 10, longitude: 20, elevation: -5_000, timeZoneIdentifier: "UTC"))
        XCTAssertEqual(low.elevation, -1_000)
    }

    func testThePreviewPlaceIsValidAndFollowsTheDevicesTimeZone() {
        let place = TonightPlace.preview()
        XCTAssertEqual(place.latitude, 40)
        XCTAssertEqual(place.timeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(place.longitude, Double(TimeZone.current.secondsFromGMT()) / 240, accuracy: 1e-9)
    }

    func testAPlaceSurvivesJSONAndTheStore() throws {
        let place = TonightTestSupport.boulder
        let decoded = try JSONDecoder().decode(TonightPlace.self, from: JSONEncoder().encode(place))
        XCTAssertEqual(decoded, place)

        TonightPlaceStore.save(place, as: .phone)
        XCTAssertEqual(TonightPlaceStore.load(.phone), place)
        let other = TonightTestSupport.sydney
        TonightPlaceStore.save(other, as: .phone)
        XCTAssertEqual(TonightPlaceStore.load(.phone), other)
        TonightPlaceStore.save(place, as: .phone)
    }

    func testThePhoneContextIsDecodedAndValidated() throws {
        let context: [String: Any] = ["lat": 40.0, "lon": -105.27, "elevation": 1650.0, "timeZone": "America/Denver"]
        let place = try XCTUnwrap(TonightPhoneContext.place(from: context))
        XCTAssertEqual(place, TonightTestSupport.boulder)

        // The elevation and the time zone are optional.
        let bare = try XCTUnwrap(TonightPhoneContext.place(from: ["lat": 10.0, "lon": 20.0]))
        XCTAssertEqual(bare.elevation, 0)
        XCTAssertEqual(bare.timeZoneIdentifier, TimeZone.current.identifier)

        XCTAssertNil(TonightPhoneContext.place(from: [:]))
        XCTAssertNil(TonightPhoneContext.place(from: ["lat": 40.0]))
        XCTAssertNil(TonightPhoneContext.place(from: ["lat": "40", "lon": "-105"]))
        XCTAssertNil(TonightPhoneContext.place(from: ["lat": 140.0, "lon": 0.0]))
    }

    // MARK: The iPhone's place

    private let sent = Date(timeIntervalSince1970: 1_800_000_000)

    func testAPlaceTheIPhoneSendsKeepsItsKindAndSendTime() throws {
        for kind in [TonightPhonePlace.Kind.device, .savedSite] {
            let phonePlace = TonightPhonePlace(place: TonightTestSupport.boulder, kind: kind, sentAt: sent)
            let context = TonightPhoneContext.context(for: phonePlace)
            XCTAssertEqual(context[TonightPhoneContext.latitudeKey] as? Double, 40)
            XCTAssertEqual(context[TonightPhoneContext.kindKey] as? String, kind.rawValue)
            XCTAssertEqual(context[TonightPhoneContext.sentAtKey] as? Double, 1_800_000_000)
            XCTAssertEqual(TonightPhoneContext.phonePlace(from: context), phonePlace)
        }
    }

    func testAContextFromAnOlderIPhoneAppIsTheDevicesPlaceOfUnknownAge() throws {
        let old: [String: Any] = ["lat": 40.0, "lon": -105.27, "elevation": 1650.0, "timeZone": "America/Denver"]
        let phonePlace = try XCTUnwrap(TonightPhoneContext.phonePlace(from: old))
        XCTAssertEqual(phonePlace.place, TonightTestSupport.boulder)
        XCTAssertEqual(phonePlace.kind, .device)
        XCTAssertNil(phonePlace.sentAt)
        XCTAssertFalse(phonePlace.isFresh(at: sent))
    }

    func testAContextWithoutAValidPlaceOrWithOddExtrasIsHandledSafely() throws {
        XCTAssertNil(TonightPhoneContext.phonePlace(from: ["kind": "device", "sentAt": 1_800_000_000.0]))
        XCTAssertNil(TonightPhoneContext.phonePlace(from: ["lat": 140.0, "lon": 0.0, "sentAt": 1_800_000_000.0]))
        let odd = try XCTUnwrap(TonightPhoneContext.phonePlace(
            from: ["lat": 10.0, "lon": 20.0, "kind": "orbit", "sentAt": Double.nan]))
        XCTAssertEqual(odd.kind, .device)
        XCTAssertNil(odd.sentAt)
        let text = try XCTUnwrap(TonightPhoneContext.phonePlace(from: ["lat": 10.0, "lon": 20.0, "sentAt": "now"]))
        XCTAssertNil(text.sentAt)
    }

    func testTheIPhonesOwnLocationIsTrustedForAWhileAndThenNot() {
        let phonePlace = TonightPhonePlace(place: TonightTestSupport.boulder, kind: .device, sentAt: sent)
        let limit = TonightPhonePlace.deviceFreshness
        XCTAssertTrue(phonePlace.isFresh(at: sent))
        XCTAssertTrue(phonePlace.isFresh(at: sent.addingTimeInterval(limit)))
        XCTAssertFalse(phonePlace.isFresh(at: sent.addingTimeInterval(limit + 1)))
        XCTAssertFalse(phonePlace.isFresh(at: sent.addingTimeInterval(24 * 3_600)))
    }

    func testASendTimeFarAheadOfTheClockIsNotBelieved() {
        let phonePlace = TonightPhonePlace(place: TonightTestSupport.boulder, kind: .device, sentAt: sent)
        let slack = TonightPhonePlace.clockTolerance
        XCTAssertTrue(phonePlace.isFresh(at: sent.addingTimeInterval(-slack)))
        XCTAssertFalse(phonePlace.isFresh(at: sent.addingTimeInterval(-slack - 1)))
    }

    func testASiteTheUserChoseHoldsUntilTheUserChoosesAnother() {
        let site = TonightPhonePlace(place: TonightTestSupport.sydney, kind: .savedSite, sentAt: sent)
        XCTAssertTrue(site.isFresh(at: sent.addingTimeInterval(30 * 24 * 3_600)))
        let unstamped = TonightPhonePlace(place: TonightTestSupport.sydney, kind: .savedSite, sentAt: nil)
        XCTAssertTrue(unstamped.isFresh(at: sent))
    }

    func testTheIPhonesPlaceSurvivesTheStore() throws {
        let phonePlace = TonightPhonePlace(place: TonightTestSupport.sydney, kind: .savedSite, sentAt: sent)
        TonightPlaceStore.savePhonePlace(phonePlace)
        XCTAssertEqual(TonightPlaceStore.loadPhonePlace(), phonePlace)
    }
}

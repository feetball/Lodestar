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
}

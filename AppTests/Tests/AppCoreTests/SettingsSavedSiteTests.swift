import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `SavedSite`: validation and normalizing in the initializer, and the re-validating decoder.
final class SettingsSavedSiteTests: XCTestCase {
    private func decodeSite(_ json: String) throws -> SavedSite {
        try JSONDecoder().decode(SavedSite.self, from: Data(json.utf8))
    }

    private func valid(name: String = "Site", latitude: Double = 40, longitude: Double = -105,
                      elevation: Double = 0) -> SavedSite? {
        SavedSite(name: name, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    // MARK: Initializer

    func testAValidSiteKeepsItsValues() throws {
        let id = UUID()
        let site = try XCTUnwrap(SavedSite(id: id, name: "Dark Site", latitude: 40.015, longitude: -105.27, elevation: 1650))
        XCTAssertEqual(site.id, id)
        XCTAssertEqual(site.name, "Dark Site")
        XCTAssertEqual(site.latitude, 40.015)
        XCTAssertEqual(site.longitude, -105.27, accuracy: 1e-9)
        XCTAssertEqual(site.elevation, 1650)
        XCTAssertNil(site.timeZoneIdentifier)
        XCTAssertNil(site.horizon)
        XCTAssertNil(site.timeZone)
    }

    func testEachSiteGetsItsOwnIdentifierByDefault() throws {
        let first = try XCTUnwrap(valid())
        let second = try XCTUnwrap(valid())
        XCTAssertNotEqual(first.id, second.id)
    }

    func testTheElevationDefaultsToZero() throws {
        let site = try XCTUnwrap(SavedSite(name: "Sea level", latitude: 1, longitude: 2))
        XCTAssertEqual(site.elevation, 0)
    }

    func testTheLocationPropertyCarriesTheCoordinates() throws {
        let site = try XCTUnwrap(valid(latitude: -33.8688, longitude: 151.2093, elevation: 58))
        XCTAssertEqual(site.location, GeographicLocation(latitude: -33.8688, longitude: 151.2093, elevation: 58))
    }

    func testLatitudeMustBeInsideMinusNinetyToNinety() {
        XCTAssertNotNil(valid(latitude: 90))
        XCTAssertNotNil(valid(latitude: -90))
        XCTAssertNil(valid(latitude: 90.0001))
        XCTAssertNil(valid(latitude: -90.0001))
        XCTAssertNil(valid(latitude: .nan))
        XCTAssertNil(valid(latitude: .infinity))
    }

    func testLongitudeMustBeInsideMinus180To360() {
        XCTAssertNotNil(valid(longitude: -180))
        XCTAssertNotNil(valid(longitude: 360))
        XCTAssertNil(valid(longitude: -180.1))
        XCTAssertNil(valid(longitude: 360.1))
        XCTAssertNil(valid(longitude: .nan))
        XCTAssertNil(valid(longitude: -.infinity))
    }

    func testElevationMustBeInsideMinus1000To12000Metres() {
        XCTAssertNotNil(valid(elevation: -1000))
        XCTAssertNotNil(valid(elevation: 12000))
        XCTAssertNil(valid(elevation: -1000.1))
        XCTAssertNil(valid(elevation: 12000.1))
        XCTAssertNil(valid(elevation: .nan))
        XCTAssertNil(valid(elevation: .infinity))
    }

    func testEastLongitudesAreWrappedIntoMinus180To180() throws {
        XCTAssertEqual(try XCTUnwrap(valid(longitude: 190)).longitude, -170, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(valid(longitude: 270)).longitude, -90, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(valid(longitude: 360)).longitude, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(valid(longitude: 180)).longitude, 180, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(valid(longitude: -180)).longitude, 180, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(valid(longitude: -105.5)).longitude, -105.5, accuracy: 1e-9)
    }

    // MARK: Name

    func testTheNameIsTrimmed() throws {
        XCTAssertEqual(try XCTUnwrap(valid(name: "  Dark Sky \n")).name, "Dark Sky")
    }

    func testAnEmptyOrBlankNameBecomesUnnamedSite() throws {
        XCTAssertEqual(try XCTUnwrap(valid(name: "")).name, "Unnamed site")
        XCTAssertEqual(try XCTUnwrap(valid(name: " \t\n ")).name, "Unnamed site")
    }

    func testTheNameIsCutToSixtyCharacters() throws {
        XCTAssertEqual(SavedSite.maximumNameLength, 60)
        XCTAssertEqual(try XCTUnwrap(valid(name: String(repeating: "a", count: 60))).name.count, 60)
        XCTAssertEqual(try XCTUnwrap(valid(name: String(repeating: "a", count: 61))).name, String(repeating: "a", count: 60))
        // The name is trimmed first, then cut.
        let padded = "   " + String(repeating: "b", count: 70)
        XCTAssertEqual(try XCTUnwrap(valid(name: padded)).name, String(repeating: "b", count: 60))
    }

    func testTheNameIsCutByCharactersNotByBytes() throws {
        let name = try XCTUnwrap(valid(name: String(repeating: "\u{1F31F}", count: 65))).name
        XCTAssertEqual(name.count, 60)
        XCTAssertEqual(name, String(repeating: "\u{1F31F}", count: 60))
    }

    // MARK: Time zone and horizon

    func testAKnownTimeZoneIdentifierIsKept() throws {
        let site = try XCTUnwrap(SavedSite(name: "Denver", latitude: 39.7, longitude: -105, timeZoneIdentifier: "America/Denver"))
        XCTAssertEqual(site.timeZoneIdentifier, "America/Denver")
        XCTAssertEqual(site.timeZone, TimeZone(identifier: "America/Denver"))
    }

    func testAnUnknownTimeZoneIdentifierIsDropped() throws {
        let unknown = try XCTUnwrap(SavedSite(name: "Mars", latitude: 1, longitude: 2, timeZoneIdentifier: "Mars/Olympus_Mons"))
        XCTAssertNil(unknown.timeZoneIdentifier)
        XCTAssertNil(unknown.timeZone)
    }

    func testAFlatHorizonIsStoredAsNoHorizon() throws {
        let site = try XCTUnwrap(SavedSite(name: "Open", latitude: 1, longitude: 2, horizon: HorizonProfile.flat))
        XCTAssertNil(site.horizon)
    }

    func testARealSkylineIsKept() throws {
        let skyline = HorizonProfile.constant(15)
        let site = try XCTUnwrap(SavedSite(name: "Valley", latitude: 1, longitude: 2, horizon: skyline))
        XCTAssertEqual(site.horizon, skyline)
    }

    // MARK: Decoding

    func testASiteRoundTripsThroughJSON() throws {
        let skyline = HorizonProfile.constant(12.5)
        let original = try XCTUnwrap(SavedSite(id: UUID(), name: "Ridge", latitude: 46.5, longitude: 8.25, elevation: 2400,
                                               timeZoneIdentifier: "Europe/Zurich", horizon: skyline))
        let decoded = try JSONDecoder().decode(SavedSite.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.horizon, skyline)
        XCTAssertEqual(decoded.timeZoneIdentifier, "Europe/Zurich")
    }

    func testADecodedSiteWithoutElevationHasZeroElevation() throws {
        let site = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20}"#)
        XCTAssertEqual(site.elevation, 0)
        XCTAssertNil(site.horizon)
        XCTAssertNil(site.timeZoneIdentifier)
    }

    func testADecodedSiteWithInvalidCoordinatesThrows() {
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":91,"longitude":20}"#)) { error in
            XCTAssertTrue(error is DecodingError)
        }
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":-181}"#))
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"elevation":50000}"#))
    }

    func testADecodedSiteMissingARequiredKeyThrows() {
        XCTAssertThrowsError(try decodeSite(#"{"name":"A","latitude":10,"longitude":20}"#))
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","latitude":10,"longitude":20}"#))
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","longitude":20}"#))
        XCTAssertThrowsError(try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10}"#))
        XCTAssertThrowsError(try decodeSite(#"{"id":"not-a-uuid","name":"A","latitude":10,"longitude":20}"#))
    }

    func testADecodedSiteIsNormalizedLikeAnewOne() throws {
        let long = String(repeating: "x", count: 80)
        let json = #"{"id":"\#(UUID().uuidString)","name":"  \#(long)  ","latitude":10,"longitude":190,"timeZoneIdentifier":"Mars/Olympus_Mons"}"#
        let site = try decodeSite(json)
        XCTAssertEqual(site.name, String(repeating: "x", count: 60))
        XCTAssertEqual(site.longitude, -170, accuracy: 1e-9)
        XCTAssertNil(site.timeZoneIdentifier)
        let blank = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"   ","latitude":10,"longitude":20}"#)
        XCTAssertEqual(blank.name, "Unnamed site")
    }

    func testADamagedSkylineIsDroppedButTheSiteIsKept() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"horizon":{"version":9,"altitudeTenths":[]}}"#
        let site = try decodeSite(json)
        XCTAssertEqual(site.name, "A")
        XCTAssertNil(site.horizon)
    }

    func testASkylineOfTheWrongShapeIsDroppedButTheSiteIsKept() throws {
        let site = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"horizon":"flat"}"#)
        XCTAssertNil(site.horizon)
    }

    func testAStoredFlatSkylineBecomesNoSkyline() throws {
        let flat = String(decoding: try JSONEncoder().encode(HorizonProfile.flat), as: UTF8.self)
        let site = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"horizon":\#(flat)}"#)
        XCTAssertNil(site.horizon)
    }

    func testAStoredValidSkylineIsRestored() throws {
        let skyline = HorizonProfile.constant(7)
        let encoded = String(decoding: try JSONEncoder().encode(skyline), as: UTF8.self)
        let site = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"horizon":\#(encoded)}"#)
        XCTAssertEqual(site.horizon, skyline)
    }

    func testAKnownStoredTimeZoneIsKept() throws {
        let known = try decodeSite(#"{"id":"\#(UUID().uuidString)","name":"A","latitude":10,"longitude":20,"timeZoneIdentifier":"Asia/Tokyo"}"#)
        XCTAssertEqual(known.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(known.timeZone?.identifier, "Asia/Tokyo")
    }

    func testSitesWithTheSameValuesAreEqualAndDifferentIdsAreNot() throws {
        let id = UUID()
        let a = try XCTUnwrap(SavedSite(id: id, name: "A", latitude: 1, longitude: 2))
        let b = try XCTUnwrap(SavedSite(id: id, name: "A", latitude: 1, longitude: 2))
        let c = try XCTUnwrap(SavedSite(id: UUID(), name: "A", latitude: 1, longitude: 2))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}

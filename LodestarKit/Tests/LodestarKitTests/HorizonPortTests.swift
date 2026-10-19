import XCTest
@testable import LodestarKit

/// Tests of the places where the Swift and Kotlin forms differ in how they are used: the JSON of a stored
/// observing site and the value semantics of the visibility object.
final class HorizonPortTests: XCTestCase {
    private typealias Support = HorizonTestSupport

    /// What an app stores for an observing site: the skyline is optional and absent for a flat horizon.
    private struct StoredSite: Codable, Equatable {
        var name: String
        var horizon: HorizonProfile?
    }

    func testAProfileInsideAStoredSiteRoundTripsAndAFlatOneIsLeftOut() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let site = StoredSite(name: "Dark ridge", horizon: Support.truthProfile)
        let data = try encoder.encode(site)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"horizon\":{\"altitudeTenths\":[20,"), String(text.prefix(80)))
        XCTAssertEqual(try JSONDecoder().decode(StoredSite.self, from: data), site)
        // Nothing is stored for a site without a skyline, and a site stored before the feature existed still loads.
        let plain = StoredSite(name: "Backyard", horizon: nil)
        XCTAssertEqual(String(decoding: try encoder.encode(plain), as: UTF8.self), "{\"name\":\"Backyard\"}")
        XCTAssertEqual(try JSONDecoder().decode(StoredSite.self, from: Data("{\"name\":\"Backyard\"}".utf8)), plain)
        XCTAssertNil(try JSONDecoder().decode(StoredSite.self, from: Data("{\"name\":\"Backyard\",\"horizon\":null}".utf8)).horizon)
        // A corrupt skyline fails the decode of the site, so the app can drop or repair it.
        let corrupt = "{\"name\":\"x\",\"horizon\":{\"version\":1,\"altitudeTenths\":[1,2,3]}}"
        XCTAssertThrowsError(try JSONDecoder().decode(StoredSite.self, from: Data(corrupt.utf8)))
    }

    func testVisibilityObjectsAreValuesThatCompareByProfile() {
        XCTAssertEqual(HorizonVisibility(profile: Support.truthProfile), HorizonVisibility(profile: Support.truthProfile))
        XCTAssertEqual(HorizonVisibility(profile: Support.truthProfile).hashValue,
                       HorizonVisibility(profile: Support.truthProfile).hashValue)
        XCTAssertNotEqual(HorizonVisibility(profile: Support.truthProfile), HorizonVisibility(profile: .flat))
    }

    func testTheRecorderIsAValueWhoseCopiesAreIndependent() {
        var recorder = HorizonRecorder()
        recorder.add(azimuth: 10, altitude: 5, timestamp: 0)
        var copy = recorder
        copy.reset()
        XCTAssertEqual(recorder.recordedBinCount, 1)
        XCTAssertEqual(copy.recordedBinCount, 0)
    }
}

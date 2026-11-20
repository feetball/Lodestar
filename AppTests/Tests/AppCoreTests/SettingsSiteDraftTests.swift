import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `SiteDraft` and `SiteTimeZoneStatus`: the editable text of an observing site and what it means.
final class SettingsSiteDraftTests: XCTestCase {
    private func fix(latitude: Double = 40.015, longitude: Double = -105.2705, altitude: Double = 1650,
                     verticalAccuracy: Double = 5) -> LocationFix {
        LocationFix(latitude: latitude, longitude: longitude, altitude: altitude, horizontalAccuracy: 10,
                    verticalAccuracy: verticalAccuracy, timestamp: Date(timeIntervalSince1970: 1_000))
    }

    private func makeDraft(latitude: String, longitude: String, elevation: Double = 0) -> SiteDraft {
        var draft = SiteDraft(name: "Test")
        draft.latitudeText = latitude
        draft.longitudeText = longitude
        draft.elevation = elevation
        return draft
    }

    // MARK: A draft without a position

    func testANewDraftHasAnEmptyPosition() {
        let draft = SiteDraft(name: "New site")
        XCTAssertEqual(draft.name, "New site")
        XCTAssertEqual(draft.latitudeText, "")
        XCTAssertEqual(draft.longitudeText, "")
        XCTAssertEqual(draft.elevation, 0)
        XCTAssertNil(draft.location)
        XCTAssertFalse(draft.isLatitudeValid)
        XCTAssertFalse(draft.isLongitudeValid)
    }

    // MARK: A draft from a fix

    func testADraftFromAFixWritesTheCoordinatesToSixDecimals() {
        let draft = SiteDraft(name: "Here", fix: fix())
        XCTAssertEqual(draft.name, "Here")
        XCTAssertEqual(draft.latitudeText, "40.015000\u{00B0} N")
        XCTAssertEqual(draft.longitudeText, "105.270500\u{00B0} W")
        XCTAssertTrue(draft.isLatitudeValid)
        XCTAssertTrue(draft.isLongitudeValid)
    }

    func testADraftFromAFixTakesTheAltitudeWhenTheFixSaysItIsValid() {
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: 1650, verticalAccuracy: 5)).elevation, 1650)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: -30, verticalAccuracy: 0.5)).elevation, -30)
    }

    func testADraftFromAFixIgnoresAnAltitudeThatIsNotValid() {
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: 1650, verticalAccuracy: 0)).elevation, 0)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: 1650, verticalAccuracy: -1)).elevation, 0)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: .nan, verticalAccuracy: 5)).elevation, 0)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: .infinity, verticalAccuracy: 5)).elevation, 0)
    }

    func testADraftFromAFixClampsTheAltitudeIntoTheSupportedRange() {
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: 20_000)).elevation, 12_000)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: -2_000)).elevation, -1_000)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: 12_000)).elevation, 12_000)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(altitude: -1_000)).elevation, -1_000)
    }

    func testADraftFromAFixWithoutAValidPositionLeavesTheTextEmpty() {
        let draft = SiteDraft(name: "A", fix: fix(latitude: 95, longitude: 10))
        XCTAssertEqual(draft.latitudeText, "")
        XCTAssertEqual(draft.longitudeText, "")
        XCTAssertNil(draft.location)
        // The altitude is still taken from the fix.
        XCTAssertEqual(draft.elevation, 1650)
        XCTAssertEqual(SiteDraft(name: "A", fix: fix(latitude: .nan)).latitudeText, "")
    }

    func testADraftFromAFixInTheSouthernAndEasternHemispheres() {
        let draft = SiteDraft(name: "Sydney", fix: fix(latitude: -33.8688, longitude: 151.2093, altitude: 58))
        XCTAssertEqual(draft.latitudeText, "33.868800\u{00B0} S")
        XCTAssertEqual(draft.longitudeText, "151.209300\u{00B0} E")
        XCTAssertEqual(draft.elevation, 58)
    }

    func testADraftFromAFixWrapsAnEastLongitudeAbove180() {
        let draft = SiteDraft(name: "A", fix: fix(longitude: 190))
        XCTAssertEqual(draft.longitudeText, "170.000000\u{00B0} W")
    }

    // MARK: A draft from a saved site

    func testADraftFromASavedSiteCopiesItsNameElevationAndPosition() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 40.015, longitude: -105.2705, elevation: 1650))
        let draft = SiteDraft(site: site)
        XCTAssertEqual(draft.name, "Ridge")
        XCTAssertEqual(draft.elevation, 1650)
        XCTAssertEqual(draft.latitudeText, "40.015000\u{00B0} N")
        XCTAssertEqual(draft.longitudeText, "105.270500\u{00B0} W")
    }

    func testEditingOnlyTheNameLeavesThePositionOfASavedSiteAsItWas() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 40.015, longitude: -105.2705, elevation: 1650))
        var draft = SiteDraft(site: site)
        draft.name = "Renamed"
        let location = try XCTUnwrap(draft.location)
        XCTAssertEqual(location.latitude, site.latitude, accuracy: 1e-6)
        XCTAssertEqual(location.longitude, site.longitude, accuracy: 1e-6)
        XCTAssertEqual(location.elevation, 1650, accuracy: 1e-9)
    }

    // MARK: The position the text describes

    func testTypedDecimalDegreesGiveALocation() throws {
        let location = try XCTUnwrap(makeDraft(latitude: "40.015", longitude: "-105.2705", elevation: 1650).location)
        XCTAssertEqual(location.latitude, 40.015, accuracy: 1e-9)
        XCTAssertEqual(location.longitude, -105.2705, accuracy: 1e-9)
        XCTAssertEqual(location.elevation, 1650)
    }

    func testHemisphereLettersAreUnderstood() throws {
        let location = try XCTUnwrap(makeDraft(latitude: "S 33.5", longitude: "105.25 W").location)
        XCTAssertEqual(location.latitude, -33.5, accuracy: 1e-9)
        XCTAssertEqual(location.longitude, -105.25, accuracy: 1e-9)
    }

    func testSexagesimalDegreesAreUnderstood() throws {
        let location = try XCTUnwrap(makeDraft(latitude: "40\u{00B0} 30\u{2032} 00\u{2033} N", longitude: "105\u{00B0} 15\u{2032} 00\u{2033} W").location)
        XCTAssertEqual(location.latitude, 40.5, accuracy: 1e-9)
        XCTAssertEqual(location.longitude, -105.25, accuracy: 1e-9)
    }

    func testALongitudeAbove180IsAnEastLongitude() throws {
        let location = try XCTUnwrap(makeDraft(latitude: "10", longitude: "200").location)
        XCTAssertEqual(location.longitude, -160, accuracy: 1e-9)
    }

    func testThePolesAndTheAntimeridianAreAccepted() throws {
        XCTAssertNotNil(makeDraft(latitude: "90", longitude: "180").location)
        XCTAssertNotNil(makeDraft(latitude: "-90", longitude: "-180").location)
    }

    func testThereIsNoLocationWhileEitherCoordinateIsIncompleteOrOutOfRange() {
        XCTAssertNil(makeDraft(latitude: "", longitude: "-105").location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "").location)
        XCTAssertNil(makeDraft(latitude: "91", longitude: "-105").location)
        XCTAssertNil(makeDraft(latitude: "-90.5", longitude: "-105").location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "-181").location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "361").location)
        XCTAssertNil(makeDraft(latitude: "forty", longitude: "-105").location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "-").location)
    }

    func testThereIsNoLocationWhenTheElevationIsOutOfRange() {
        XCTAssertNotNil(makeDraft(latitude: "40", longitude: "20", elevation: 12_000).location)
        XCTAssertNotNil(makeDraft(latitude: "40", longitude: "20", elevation: -1_000).location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "20", elevation: 12_001).location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "20", elevation: -1_001).location)
        XCTAssertNil(makeDraft(latitude: "40", longitude: "20", elevation: .nan).location)
    }

    func testEachCoordinateIsValidatedOnItsOwn() {
        XCTAssertTrue(makeDraft(latitude: "40.5", longitude: "x").isLatitudeValid)
        XCTAssertFalse(makeDraft(latitude: "40.5", longitude: "x").isLongitudeValid)
        XCTAssertFalse(makeDraft(latitude: "91", longitude: "10").isLatitudeValid)
        XCTAssertTrue(makeDraft(latitude: "91", longitude: "10").isLongitudeValid)
        XCTAssertTrue(makeDraft(latitude: "90", longitude: "180").isLatitudeValid)
        XCTAssertFalse(makeDraft(latitude: "", longitude: "").isLatitudeValid)
        XCTAssertFalse(makeDraft(latitude: "", longitude: "").isLongitudeValid)
    }

    func testLongitudeValidityRunsFromMinus180To360() {
        XCTAssertTrue(makeDraft(latitude: "0", longitude: "-180").isLongitudeValid)
        XCTAssertTrue(makeDraft(latitude: "0", longitude: "360").isLongitudeValid)
        XCTAssertFalse(makeDraft(latitude: "0", longitude: "-181").isLongitudeValid)
        XCTAssertFalse(makeDraft(latitude: "0", longitude: "361").isLongitudeValid)
    }

    // MARK: Setting the position

    func testSettingThePositionWritesTheTextAndLeavesTheRestAlone() {
        var draft = SiteDraft(name: "Keep me")
        draft.elevation = 500
        draft.setPosition(GeographicLocation(latitude: -33.8688, longitude: 151.2093))
        XCTAssertEqual(draft.latitudeText, "33.868800\u{00B0} S")
        XCTAssertEqual(draft.longitudeText, "151.209300\u{00B0} E")
        XCTAssertEqual(draft.elevation, 500)
        XCTAssertEqual(draft.name, "Keep me")
    }

    func testSettingThePositionReplacesWhatWasTyped() throws {
        var draft = makeDraft(latitude: "1", longitude: "2")
        draft.setPosition(GeographicLocation(latitude: 40.5, longitude: 20.25))
        let location = try XCTUnwrap(draft.location)
        XCTAssertEqual(location.latitude, 40.5, accuracy: 1e-9)
        XCTAssertEqual(location.longitude, 20.25, accuracy: 1e-9)
    }

    func testDraftsWithTheSameValuesAreEqual() {
        XCTAssertEqual(SiteDraft(name: "A"), SiteDraft(name: "A"))
        XCTAssertNotEqual(SiteDraft(name: "A"), SiteDraft(name: "B"))
        var changed = SiteDraft(name: "A")
        changed.elevation = 1
        XCTAssertNotEqual(changed, SiteDraft(name: "A"))
        changed = SiteDraft(name: "A")
        changed.latitudeText = "1"
        XCTAssertNotEqual(changed, SiteDraft(name: "A"))
    }

    // MARK: The time zone lookup

    func testTheTimeZoneStatusHasAZoneOnlyOnceOneIsFoundOrEstimated() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertNil(SiteTimeZoneStatus.waitingForCoordinates.timeZone)
        XCTAssertNil(SiteTimeZoneStatus.resolving.timeZone)
        XCTAssertEqual(SiteTimeZoneStatus.resolved(zone).timeZone, zone)
        XCTAssertEqual(SiteTimeZoneStatus.approximate(zone).timeZone, zone)
    }

    func testTheTimeZoneStatusesCompareByCaseAndZone() throws {
        let denver = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        let zurich = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        XCTAssertEqual(SiteTimeZoneStatus.resolving, SiteTimeZoneStatus.resolving)
        XCTAssertEqual(SiteTimeZoneStatus.resolved(denver), SiteTimeZoneStatus.resolved(denver))
        XCTAssertNotEqual(SiteTimeZoneStatus.resolved(denver), SiteTimeZoneStatus.resolved(zurich))
        XCTAssertNotEqual(SiteTimeZoneStatus.resolved(denver), SiteTimeZoneStatus.approximate(denver))
        XCTAssertNotEqual(SiteTimeZoneStatus.waitingForCoordinates, SiteTimeZoneStatus.resolving)
    }
}

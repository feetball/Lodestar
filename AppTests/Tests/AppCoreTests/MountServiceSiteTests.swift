import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The site a connected mount follows (`MountService.site`, `pendingSite`, `usePendingSite`), and the refusals that depend on
/// where the mount points.
extension MountServiceTests {
    /// The context of a saved site at `place`, as the app resolves it for a person who chose that site.
    static func siteContext(_ place: Observer, name: String = "Dark Site") -> ObserverContext {
        ObserverContext(observer: place, timeZone: TimeZone(secondsFromGMT: 0)!, name: name, source: .site(UUID()))
    }

    private var farAway: Observer {
        Observer(location: GeographicLocation(latitude: observer.location.latitude + 5.0, longitude: observer.location.longitude,
                                              elevation: 100.0))
    }

    // MARK: - The site

    func testTheSiteOfAConnectionIsTheOneItWasConnectedWith() async {
        await connectFake()
        XCTAssertEqual(service.site?.name, "Current Location")
        XCTAssertEqual(service.site?.observer, observer)
        XCTAssertNil(service.pendingSite)
    }

    func testWithoutAConnectionTheSiteFollowsTheApp() {
        let place = Self.siteContext(farAway)
        service.updateObserver(place)
        XCTAssertEqual(service.site, place)
        XCTAssertNil(service.pendingSite)
    }

    func testAnotherSiteFarAwayWaitsForTheDecisionOfAConnectedMount() async {
        let fake = await connectFake()
        await settle()
        let sentAtConnection = fake.siteLocations
        let place = Self.siteContext(farAway)
        service.updateObserver(place)
        XCTAssertEqual(service.pendingSite, place)
        XCTAssertEqual(service.site?.name, "Current Location", "the mount keeps the site it was connected with")
        await settle()
        XCTAssertEqual(fake.siteLocations, sentAtConnection, "the mount was not given the new place")
    }

    func testAGoToAndASyncWaitWhileASiteIsPending() async {
        await connectFake()
        service.updateObserver(Self.siteContext(farAway))
        let expected = "The site changed to Dark Site. Use it for the mount first, or choose Current Location again."
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), expected)
        XCTAssertEqual(service.syncUnavailableReason(for: highTarget()), expected)
        XCTAssertNil(service.errorText)
    }

    func testChoosingTheMountsSiteAgainEndsTheWait() async {
        await connectFake()
        service.updateObserver(Self.siteContext(farAway))
        XCTAssertNotNil(service.pendingSite)
        service.updateObserver(Self.context(observer))
        XCTAssertNil(service.pendingSite)
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
    }

    func testUsingThePendingSiteHandsItToTheMount() async {
        await connectFake()
        let place = Self.siteContext(farAway)
        service.updateObserver(place)
        service.usePendingSite()
        XCTAssertEqual(service.site, place)
        XCTAssertNil(service.pendingSite)
        await settle()
        XCTAssertNil(service.errorText)
    }

    func testThereIsNothingToUseWithoutAPendingSite() async {
        await connectFake()
        service.usePendingSite()
        XCTAssertEqual(service.site?.name, "Current Location")
        XCTAssertNil(service.pendingSite)
    }

    func testAnotherSiteCloseByIsHandedOverAtOnce() async {
        await connectFake()
        let nearby = Observer(location: GeographicLocation(latitude: observer.location.latitude + 0.005,
                                                           longitude: observer.location.longitude, elevation: 100.0))
        let place = Self.siteContext(nearby, name: "Next door")
        service.updateObserver(place)
        XCTAssertNil(service.pendingSite)
        XCTAssertEqual(service.site, place)
    }

    func testAnotherSourceAtTheSamePlaceIsAChangeToo() async {
        await connectFake()
        let place = Self.siteContext(observer, name: "Same place")
        service.updateObserver(place)
        XCTAssertEqual(service.site, place, "a saved site at the place of the phone is a site of its own")
        XCTAssertNil(service.pendingSite)
    }

    func testAConnectionWithoutAPlaceIsRefused() {
        service.connectDemo(Self.option(for: Fake()), context: nil)
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertEqual(service.errorText, "Lodestar needs to know where you are to check targets against your altitude limit. "
            + "Allow location access or choose an observing site first.")
    }

    // MARK: - Near the Sun

    func testANudgeRefusedNearTheSunSaysWhyInItsOwnWords() async {
        let fake = await connectFake()
        fake.configure { $0.nudgeError = .nearSun(separationDegrees: 9.0, limitDegrees: 15.0) }
        service.nudgeOnce(.north)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount points \(AppFormat.separation(9.0)) from the Sun, closer than the "
            + "\(AppFormat.separation(15.0)) safety limit, so Lodestar won't move it with the arrows. "
            + "Move it away from the Sun first, with Go to or by hand.")
    }

    func testAnotherRefusalOfANudgeKeepsItsOwnWords() async {
        let fake = await connectFake()
        fake.configure { $0.nudgeError = .parked }
        service.nudgeOnce(.south)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount is parked. Unpark it first.")
    }

    func testTrackingThatStopsNearTheSunStaysOnScreenUntilTrackingIsBack() async throws {
        let sun = try XCTUnwrap(Self.sun)
        let day = Self.placeOnEarth(sunUp: true)
        let onTheSun = MountTargets.resolve(sun, observer: day, date: Date()).j2000
        let fake = await connectFake(seenFrom: day) { $0.configure { $0.position = onTheSun } }
        let expected = "Tracking stopped: the mount was within \(AppFormat.separation(15.0)) of the Sun. "
            + "Point it away before tracking again."
        await mountServiceExpect("the notice about the Sun") { self.service.noticeText == expected }
        XCTAssertEqual(fake.trackingCalls, [false], "the engine switched tracking off")
        // The person switches tracking on again (the mount points away from the Sun first): the notice goes.
        fake.configure { $0.position = EquatorialCoordinate(rightAscension: onTheSun.rightAscension + 180.0,
                                                            declination: -onTheSun.declination) }
        service.setTracking(true)
        await mountServiceExpect("the notice to go") { self.service.noticeText != expected }
    }
}

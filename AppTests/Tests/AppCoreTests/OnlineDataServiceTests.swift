import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Waits (a few milliseconds at a time) until `condition` holds; `false` when it still does not after `timeout` seconds.
/// The service works through a queue of tasks, so this is the only way to see the end of a job.
@MainActor
private func onlineServiceWaitUntil(timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return true
}

/// A temporary cache directory, a private defaults suite and the collaborators of one service.
///
/// Every request of every resource of the feeds a test uses is made impossible by `block`: the last attempt is "now",
/// and no resource may be requested again for at least ten minutes. So no test here reaches the network. The service
/// is only held weakly: a test lets go of it and calls `settle()`, which waits until the job that may still be running
/// has ended (a running job holds the service) and the queued ones have lapsed (they hold it weakly). Only then are
/// the suite and the directory removed, because without them every resource would be allowed again.
@MainActor
private final class OnlineDataServiceTestsBox {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: OnlineStore
    let cache: OnlineCache
    let refresher: OnlineRefresher
    let catalog = CatalogService()
    /// The time of the last request of every blocked resource: now, to the second.
    let attempt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
    private weak var probe: OnlineDataService?

    init() {
        let id = UUID().uuidString
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnlineDataServiceTests-\(id)", isDirectory: true)
        suiteName = "AppCoreTests.OnlineDataService.\(id)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = OnlineStore(defaults: defaults)
        cache = OnlineCache(directory: directory)
        refresher = OnlineRefresher(cache: cache, downloader: OnlineDownloader(userAgent: "Lodestar/test"), store: store)
    }

    func makeService() -> OnlineDataService {
        let service = OnlineDataService(catalog: catalog, store: store, refresher: refresher)
        probe = service
        return service
    }

    /// Records a request of every file of `feed` as just made.
    func block(_ feed: OnlineFeed) {
        for resource in feed.resources { store.setLastAttempt(resource, attempt) }
    }

    /// Puts `bytes` in the cache as `resource` with the given metadata.
    func save(_ resource: OnlineResource, _ bytes: Data, savedAt: Date, expires: Date? = nil, key: String? = nil) throws {
        try cache.write(resource.key, bytes: bytes, meta: OnlineCacheMeta(savedAt: savedAt, expires: expires, key: key))
    }

    /// Waits until the service made by `makeService` is gone, which it is once no job holds it.
    func settle() async {
        let gone = await onlineServiceWaitUntil { self.probe == nil }
        XCTAssertTrue(gone, "a job of the service is still running")
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// `OnlineDataService`: enabling and disabling feeds, what is loaded and requested when, and the state it publishes.
/// The downloader cannot be replaced, so every feed that is switched on has its requests blocked by a recent attempt (see
/// `OnlineDataServiceTestsBox`), and the cases that would reach the network (a download, a 304, a failed request) are not
/// covered.
final class OnlineDataServiceTests: XCTestCase {
    /// Saved times, a long time ago (whole seconds).
    private let savedEarly = Date(timeIntervalSince1970: 1_750_000_000)
    private let savedLate = Date(timeIntervalSince1970: 1_750_003_600)
    private let place = "32.8,-96.8"

    // MARK: Fixtures

    /// A CelesTrak OMM record for `number`, with an epoch far in the past so that it is accepted whatever the clock says.
    private func omm(_ number: Int) -> String {
        let fields = [
            "\"OBJECT_NAME\":\"TEST SAT \(number)\"", "\"OBJECT_ID\":\"2020-001A\"", "\"EPOCH\":\"2025-03-04T05:06:07\"",
            "\"MEAN_MOTION\":15.5", "\"ECCENTRICITY\":0.001", "\"INCLINATION\":51.6", "\"RA_OF_ASC_NODE\":10",
            "\"ARG_OF_PERICENTER\":20", "\"MEAN_ANOMALY\":30", "\"EPHEMERIS_TYPE\":0", "\"CLASSIFICATION_TYPE\":\"U\"",
            "\"NORAD_CAT_ID\":\(number)", "\"ELEMENT_SET_NO\":7", "\"REV_AT_EPOCH\":99", "\"BSTAR\":0.0001",
            "\"MEAN_MOTION_DOT\":0.00001", "\"MEAN_MOTION_DDOT\":0",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func list(_ numbers: [Int]) -> Data { Data(("[" + numbers.map { omm($0) }.joined(separator: ",") + "]").utf8) }

    private var forecastJSON: Data {
        let entries = (0..<8).map { hour in
            "{\"time\":\"2026-10-18T0\(hour):00:00Z\",\"data\":{\"instant\":{\"details\":{\"cloud_area_fraction\":\(hour * 10)}}}}"
        }
        return Data(("{\"geometry\":{\"coordinates\":[-96.8,32.8,150]},\"properties\":{\"meta\":{\"updated_at\":\"2026-10-18T00:30:00Z\"},"
            + "\"timeseries\":[\(entries.joined(separator: ","))]}}").utf8)
    }

    private let haleBopp = "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091"
    private let halley = "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592"

    private func dallas() -> GeographicLocation { GeographicLocation(latitude: 32.8473, longitude: -96.7712, elevation: 150) }

    private func assertDate(_ date: Date?, equals expected: Date, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(date?.timeIntervalSince1970 ?? .nan, expected.timeIntervalSince1970, accuracy: 0.001, message, line: line)
    }

    // MARK: Start

    @MainActor
    func testTheSwitchesComeFromTheStore() {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        box.store.setEnabled(.comets, true)
        box.store.setEnabled(.clouds, true)
        let service = box.makeService()
        XCTAssertTrue(service.isEnabled(.comets))
        XCTAssertTrue(service.isEnabled(.clouds))
        XCTAssertFalse(service.isEnabled(.satellites))
        XCTAssertFalse(service.isEnabled(.starlink))
        XCTAssertEqual(service.statuses.count, 4)
        XCTAssertEqual(service.status(.comets), OnlineFeedStatus(isEnabled: true))
        XCTAssertEqual(service.status(.satellites), OnlineFeedStatus())
    }

    @MainActor
    func testANewServiceHasNoDataAndHasNotExplained() {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        let service = box.makeService()
        XCTAssertFalse(service.hasExplained)
        XCTAssertNil(service.forecast)
        XCTAssertNil(service.satellites.stations)
        XCTAssertNil(service.satellites.visual)
        XCTAssertNil(service.satellites.starlink)
        XCTAssertFalse(service.satellites.hasPassData)
        for feed in OnlineFeed.allCases {
            XCTAssertEqual(service.status(feed), OnlineFeedStatus(), "\(feed)")
        }
    }

    @MainActor
    func testTheDefaultStatusHasNothingToShow() {
        let status = OnlineFeedStatus()
        XCTAssertFalse(status.isEnabled)
        XCTAssertNil(status.lastUpdate)
        XCTAssertFalse(status.isUpdating)
        XCTAssertNil(status.error)
        XCTAssertNil(status.nextRequest)
    }

    @MainActor
    func testTheExplanationIsRememberedAcrossServices() {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        let service = box.makeService()
        service.markExplained()
        XCTAssertTrue(service.hasExplained)
        XCTAssertTrue(box.store.hasExplained)
        XCTAssertTrue(box.makeService().hasExplained)
    }

    // MARK: Switching on

    @MainActor
    func testSwitchingOnIsRememberedAndShownAtOnce() async {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.satellites, true)
        // Before the queue has run anything:
        XCTAssertTrue(service.isEnabled(.satellites))
        XCTAssertTrue(box.store.isEnabled(.satellites))
        XCTAssertEqual(service.status(.satellites), OnlineFeedStatus(isEnabled: true))
        XCTAssertFalse(service.isEnabled(.starlink))
        XCTAssertFalse(box.store.isEnabled(.starlink))
        // Nothing is saved, and the requests are blocked, so the status ends with just the next possible time.
        let ready = await onlineServiceWaitUntil { service.status(.satellites).nextRequest != nil }
        XCTAssertTrue(ready)
        let status = service.status(.satellites)
        service = nil
        await box.settle()
        assertDate(status.nextRequest, equals: box.attempt.addingTimeInterval(7200))
        XCTAssertNil(status.lastUpdate)
        XCTAssertNil(status.error)
        XCTAssertFalse(status.isUpdating)
        XCTAssertTrue(status.isEnabled)
    }

    @MainActor
    func testSwitchingOnAFeedThatIsAlreadyOnChangesNothing() {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        box.store.setEnabled(.comets, true)
        let service = box.makeService()
        service.setEnabled(.comets, true)
        service.setEnabled(.starlink, false)
        XCTAssertEqual(service.status(.comets), OnlineFeedStatus(isEnabled: true))
        XCTAssertEqual(service.status(.starlink), OnlineFeedStatus())
    }

    @MainActor
    func testSwitchingOnLoadsTheSavedSatellitesAndShowsWhenTheyWereSaved() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.stations, list([25544]), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedLate)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.satellites, true)
        let ready = await onlineServiceWaitUntil { service.status(.satellites).lastUpdate != nil }
        XCTAssertTrue(ready)
        let library = service.satellites
        let status = service.status(.satellites)
        service = nil
        await box.settle()
        XCTAssertEqual(library.stations?.satellites.map(\.catalogNumber), [25544])
        XCTAssertEqual(library.visual?.satellites.map(\.catalogNumber), [12345])
        XCTAssertNil(library.starlink)
        XCTAssertTrue(library.hasPassData)
        XCTAssertEqual(library.passSatellites.map { $0.satellite.catalogNumber }, [25544, 12345])
        // The oldest of the feed's files decides.
        XCTAssertEqual(status.lastUpdate, savedEarly)
        assertDate(status.nextRequest, equals: box.attempt.addingTimeInterval(7200))
        XCTAssertNil(status.error)
        XCTAssertFalse(status.isUpdating)
    }

    @MainActor
    func testStatusTimesCoverOnlyTheFilesThatExist() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.visual, list([12345]), savedAt: savedLate)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.satellites, true)
        let ready = await onlineServiceWaitUntil { service.status(.satellites).lastUpdate != nil }
        XCTAssertTrue(ready)
        let library = service.satellites
        let status = service.status(.satellites)
        service = nil
        await box.settle()
        XCTAssertNil(library.stations)
        XCTAssertEqual(library.visual?.satellites.count, 1)
        XCTAssertEqual(status.lastUpdate, savedLate)
    }

    @MainActor
    func testSavedDataThatCannotBeReadIsDeletedAndTheRestIsKept() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.stations, Data("garbage".utf8), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedLate)
        box.store.setEnabled(.satellites, true)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.onForeground()
        let ready = await onlineServiceWaitUntil { service.status(.satellites).lastUpdate != nil }
        XCTAssertTrue(ready)
        let library = service.satellites
        let status = service.status(.satellites)
        service = nil
        await box.settle()
        XCTAssertNil(library.stations)
        XCTAssertEqual(library.visual?.satellites.count, 1)
        XCTAssertNil(box.cache.read(OnlineResource.stations.key))
        XCTAssertNotNil(box.cache.read(OnlineResource.visual.key))
        XCTAssertEqual(status.lastUpdate, savedLate)
    }

    // MARK: Switching off

    @MainActor
    func testSwitchingOffDeletesWhatWasDownloadedAtOnce() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.stations, list([25544]), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedLate)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.satellites, true)
        let ready = await onlineServiceWaitUntil { service.satellites.visual != nil && service.status(.satellites).lastUpdate != nil }
        XCTAssertTrue(ready)
        service.setEnabled(.satellites, false)
        // Everything happens before the queue runs again.
        XCTAssertFalse(service.isEnabled(.satellites))
        XCTAssertFalse(box.store.isEnabled(.satellites))
        XCTAssertNil(service.satellites.stations)
        XCTAssertNil(service.satellites.visual)
        XCTAssertFalse(service.satellites.hasPassData)
        XCTAssertNil(box.cache.read(OnlineResource.stations.key))
        XCTAssertNil(box.cache.read(OnlineResource.visual.key))
        XCTAssertEqual(service.status(.satellites), OnlineFeedStatus(isEnabled: false))
        service = nil
        await box.settle()
        XCTAssertNil(box.cache.read(OnlineResource.stations.key))
    }

    @MainActor
    func testSwitchingOffTheSatellitesKeepsStarlink() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.stations, list([25544]), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedEarly)
        try box.save(.starlink, list([7001, 7002]), savedAt: savedLate)
        box.store.setEnabled(.satellites, true)
        box.store.setEnabled(.starlink, true)
        box.block(.satellites)
        box.block(.starlink)
        var service: OnlineDataService! = box.makeService()
        service.onForeground()
        let ready = await onlineServiceWaitUntil {
            service.satellites.starlink != nil && service.satellites.visual != nil && service.status(.starlink).lastUpdate != nil
        }
        XCTAssertTrue(ready)
        service.setEnabled(.satellites, false)
        XCTAssertNil(service.satellites.stations)
        XCTAssertNil(service.satellites.visual)
        XCTAssertEqual(service.satellites.starlink?.satellites.map(\.catalogNumber), [7001, 7002])
        XCTAssertTrue(service.isEnabled(.starlink))
        XCTAssertNotNil(box.cache.read(OnlineResource.starlink.key))
        XCTAssertNil(box.cache.read(OnlineResource.stations.key))
        XCTAssertNil(box.cache.read(OnlineResource.visual.key))
        service = nil
        await box.settle()
    }

    @MainActor
    func testSwitchingOffTheCloudForecastClearsTheForecastAndItsFile() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.forecast, forecastJSON, savedAt: savedEarly, key: place)
        box.block(.clouds)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.setEnabled(.clouds, true)
        let ready = await onlineServiceWaitUntil { service.forecast != nil && service.status(.clouds).lastUpdate != nil }
        XCTAssertTrue(ready)
        service.setEnabled(.clouds, false)
        XCTAssertNil(service.forecast)
        XCTAssertNil(box.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(service.status(.clouds), OnlineFeedStatus(isEnabled: false))
        XCTAssertFalse(box.store.isEnabled(.clouds))
        service = nil
        await box.settle()
    }

    @MainActor
    func testSwitchingOffAFeedThatIsOffChangesNothing() {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        let service = box.makeService()
        service.setEnabled(.comets, false)
        XCTAssertEqual(service.status(.comets), OnlineFeedStatus())
        XCTAssertFalse(box.store.isEnabled(.comets))
    }

    @MainActor
    func testTheLastRequestSurvivesSwitchingOff() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        box.store.setEnabled(.satellites, true)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.satellites, false)
        service = nil
        await box.settle()
        // Toggling cannot get around the request interval.
        for resource in OnlineFeed.satellites.resources {
            assertDate(box.store.lastAttempt(resource), equals: box.attempt, "\(resource)")
        }
    }

    // MARK: Foreground

    @MainActor
    func testTheForegroundLoadsTheFeedsThatAreOnAndLeavesTheOthers() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.stations, list([25544]), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedEarly)
        try box.save(.starlink, list([7001]), savedAt: savedEarly)
        try box.save(.forecast, forecastJSON, savedAt: savedLate, key: place)
        box.store.setEnabled(.satellites, true)
        box.store.setEnabled(.clouds, true)
        box.block(.satellites)
        box.block(.clouds)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.onForeground()
        // The clouds are the last job of the foreground: when they are in, the others are done.
        let ready = await onlineServiceWaitUntil { service.forecast != nil && service.status(.clouds).lastUpdate != nil }
        XCTAssertTrue(ready)
        let library = service.satellites
        let forecast = service.forecast
        let starlink = service.status(.starlink)
        let comets = service.status(.comets)
        let satellites = service.status(.satellites)
        service = nil
        await box.settle()
        XCTAssertEqual(library.stations?.satellites.count, 1)
        XCTAssertEqual(library.visual?.satellites.count, 1)
        XCTAssertNil(library.starlink)
        XCTAssertEqual(forecast?.hours.count, 8)
        XCTAssertEqual(starlink, OnlineFeedStatus())
        XCTAssertEqual(comets, OnlineFeedStatus())
        XCTAssertEqual(satellites.lastUpdate, savedEarly)
    }

    // MARK: Calls for feeds that are off

    @MainActor
    func testRequestsForFeedsThatAreOffAreIgnored() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.forecast, forecastJSON, savedAt: savedEarly, key: place)
        try box.save(.comets, Data("x".utf8), savedAt: savedEarly)
        try box.save(.stations, list([25544]), savedAt: savedEarly)
        try box.save(.visual, list([12345]), savedAt: savedEarly)
        box.store.setEnabled(.satellites, true)
        box.block(.satellites)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.refreshForecast()
        service.updateNow(.comets)
        service.updateNow(.starlink)
        // The satellites are on: this job runs after any job the calls above would have queued.
        service.updateNow(.satellites)
        let ready = await onlineServiceWaitUntil { service.satellites.visual != nil && service.status(.satellites).lastUpdate != nil }
        XCTAssertTrue(ready)
        let forecast = service.forecast
        let comets = service.status(.comets)
        let clouds = service.status(.clouds)
        let starlink = service.status(.starlink)
        service = nil
        await box.settle()
        XCTAssertNil(forecast)
        XCTAssertEqual(comets, OnlineFeedStatus())
        XCTAssertEqual(clouds, OnlineFeedStatus())
        XCTAssertEqual(starlink, OnlineFeedStatus())
        // Nothing of the files of the feeds that are off was touched.
        XCTAssertNotNil(box.cache.read(OnlineResource.forecast.key))
        XCTAssertNotNil(box.cache.read(OnlineResource.comets.key))
    }

    @MainActor
    func testUpdateNowLoadsTheSavedDataOfAFeedThatIsOnButStillObeysTheRequestInterval() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.starlink, list([7001]), savedAt: savedEarly)
        box.store.setEnabled(.starlink, true)
        box.block(.starlink)
        var service: OnlineDataService! = box.makeService()
        service.updateNow(.starlink)
        let ready = await onlineServiceWaitUntil { service.satellites.starlink != nil && service.status(.starlink).nextRequest != nil }
        XCTAssertTrue(ready)
        let status = service.status(.starlink)
        service = nil
        await box.settle()
        // "Update now" follows the same rule as the automatic refresh: no request, no error, the time to wait is shown.
        XCTAssertNil(status.error)
        XCTAssertFalse(status.isUpdating)
        assertDate(status.nextRequest, equals: box.attempt.addingTimeInterval(7200))
    }

    // MARK: The cloud forecast

    @MainActor
    func testTheForecastNeedsAnObservingLocation() async {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        box.store.setEnabled(.clouds, true)
        var service: OnlineDataService! = box.makeService()
        service.refreshForecast()
        let ready = await onlineServiceWaitUntil { service.status(.clouds).error != nil }
        XCTAssertTrue(ready)
        let status = service.status(.clouds)
        let forecast = service.forecast
        service = nil
        await box.settle()
        XCTAssertEqual(status.error, "Choose an observing location to get a cloud forecast.")
        XCTAssertFalse(status.isUpdating)
        XCTAssertNil(forecast)
        // Nothing was requested, so nothing was recorded.
        XCTAssertNil(box.store.lastAttempt(.forecast))
    }

    @MainActor
    func testTheSavedForecastIsPublishedAndTheNextRequestFollowsTheMinimumInterval() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.forecast, forecastJSON, savedAt: savedEarly, key: place)
        box.block(.clouds)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.setEnabled(.clouds, true)
        let ready = await onlineServiceWaitUntil { service.forecast != nil && service.status(.clouds).lastUpdate != nil }
        XCTAssertTrue(ready)
        let forecast = service.forecast
        let status = service.status(.clouds)
        service = nil
        await box.settle()
        XCTAssertEqual(forecast?.hours.count, 8)
        XCTAssertEqual(forecast?.key, place)
        XCTAssertEqual(status.lastUpdate, savedEarly)
        XCTAssertNil(status.error)
        assertDate(status.nextRequest, equals: box.attempt.addingTimeInterval(600))
    }

    @MainActor
    func testTheNextRequestWaitsForTheServersExpiresAndAJitterUnderFiveMinutes() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        let expires = box.attempt.addingTimeInterval(3600)
        try box.save(.forecast, forecastJSON, savedAt: savedEarly, expires: expires, key: place)
        box.block(.clouds)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.setEnabled(.clouds, true)
        let ready = await onlineServiceWaitUntil { service.forecast != nil && service.status(.clouds).nextRequest != nil }
        XCTAssertTrue(ready)
        let status = service.status(.clouds)
        service = nil
        await box.settle()
        let next = status.nextRequest?.timeIntervalSince1970 ?? .nan
        XCTAssertGreaterThanOrEqual(next, expires.timeIntervalSince1970 - 0.001)
        XCTAssertLessThan(next, expires.timeIntervalSince1970 + 300)
    }

    @MainActor
    func testTheExpiresOfAnotherPlaceDoesNotDelayTheNextRequest() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        try box.save(.forecast, forecastJSON, savedAt: savedEarly, expires: box.attempt.addingTimeInterval(3600), key: "10.0,20.0")
        box.block(.clouds)
        var service: OnlineDataService! = box.makeService()
        service.locationProvider = { self.dallas() }
        service.setEnabled(.clouds, true)
        let ready = await onlineServiceWaitUntil { service.status(.clouds).lastUpdate != nil }
        XCTAssertTrue(ready)
        let status = service.status(.clouds)
        service = nil
        await box.settle()
        assertDate(status.nextRequest, equals: box.attempt.addingTimeInterval(600))
    }

    // MARK: Comets

    @MainActor
    func testSavedCometsJoinTheCatalogAndLeaveItWhenTheFeedIsSwitchedOff() async throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        await box.catalog.load()
        try XCTSkipUnless(box.catalog.loadState == .loaded, "The bundled sky catalog did not load")
        try box.save(.comets, Data([haleBopp, halley].joined(separator: "\n").utf8), savedAt: savedEarly)
        box.block(.comets)
        var changes = 0
        box.catalog.onSmallBodiesChange = { changes += 1 }
        var service: OnlineDataService! = box.makeService()
        service.setEnabled(.comets, true)
        let ready = await onlineServiceWaitUntil {
            box.catalog.object(id: "comet.C/1995 O1") != nil && service.status(.comets).lastUpdate != nil
        }
        XCTAssertTrue(ready)
        XCTAssertNotNil(box.catalog.object(id: "comet.1P"))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(service.status(.comets).lastUpdate, savedEarly)
        service.setEnabled(.comets, false)
        XCTAssertNil(box.catalog.object(id: "comet.C/1995 O1"))
        XCTAssertNil(box.catalog.object(id: "comet.1P"))
        XCTAssertEqual(changes, 2)
        XCTAssertNil(box.cache.read(OnlineResource.comets.key))
        service = nil
        await box.settle()
    }

    // MARK: Review data

    #if DEBUG
    @MainActor
    func testReviewDataShowsEveryFeedAsUpdatedAndSavesNothing() throws {
        let box = OnlineDataServiceTestsBox()
        defer { box.remove() }
        let service = box.makeService()
        let parsed = try OnlineParsing.parse(.stations, data: list([25544]), now: Date(timeIntervalSince1970: 1_750_100_000))
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        let forecast = try ForecastParser.parseForecast(forecastJSON)
        let reference = Date(timeIntervalSince1970: 1_792_300_000)
        service.installReviewData(satellites: [group], forecast: forecast, now: reference)
        for feed in OnlineFeed.allCases {
            XCTAssertTrue(service.isEnabled(feed), "\(feed)")
            XCTAssertEqual(service.status(feed).lastUpdate, reference.addingTimeInterval(-3 * 3600), "\(feed)")
            XCTAssertNil(service.status(feed).error, "\(feed)")
            XCTAssertFalse(box.store.isEnabled(feed), "\(feed)")
        }
        XCTAssertTrue(service.hasExplained)
        XCTAssertFalse(box.store.hasExplained)
        XCTAssertEqual(service.satellites.stations?.satellites.map(\.catalogNumber), [25544])
        XCTAssertEqual(service.forecast, forecast)
    }
    #endif
}

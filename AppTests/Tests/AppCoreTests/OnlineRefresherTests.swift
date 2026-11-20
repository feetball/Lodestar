import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// A temporary cache directory and a private defaults suite for one test.
private final class OnlineRefresherTestsBox {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: OnlineStore
    let cache: OnlineCache
    let refresher: OnlineRefresher

    init() {
        let id = UUID().uuidString
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnlineRefresherTests-\(id)", isDirectory: true)
        suiteName = "AppCoreTests.OnlineRefresher.\(id)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = OnlineStore(defaults: defaults)
        cache = OnlineCache(directory: directory)
        refresher = OnlineRefresher(cache: cache, downloader: OnlineDownloader(userAgent: "Lodestar/test"), store: store)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// `OnlineRefresher` without a network: the state it reports, installing and loading cached data, and the one request
/// that fails before anything is sent (an address that is not HTTPS). The downloader is a struct that makes its own
/// `URLSession`, so the outcomes of a real answer (updated, not modified, storage failure) cannot be reached here.
final class OnlineRefresherTests: XCTestCase {
    /// 2026-10-18T04:28:15Z.
    private let now = Date(timeIntervalSince1970: 1_792_297_695)
    private let place = "32.8,-96.8"

    private func omm(_ number: Int, epoch: String = "2026-10-18T03:28:15") -> String {
        let fields = [
            "\"OBJECT_NAME\":\"TEST SAT \(number)\"", "\"OBJECT_ID\":\"2020-001A\"", "\"EPOCH\":\"\(epoch)\"",
            "\"MEAN_MOTION\":15.5", "\"ECCENTRICITY\":0.001", "\"INCLINATION\":51.6", "\"RA_OF_ASC_NODE\":10",
            "\"ARG_OF_PERICENTER\":20", "\"MEAN_ANOMALY\":30", "\"EPHEMERIS_TYPE\":0", "\"CLASSIFICATION_TYPE\":\"U\"",
            "\"NORAD_CAT_ID\":\(number)", "\"ELEMENT_SET_NO\":7", "\"REV_AT_EPOCH\":99", "\"BSTAR\":0.0001",
            "\"MEAN_MOTION_DOT\":0.00001", "\"MEAN_MOTION_DDOT\":0",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    private var satellites: Data { satellitesData(epoch: "2026-10-18T03:28:15") }

    private func satellitesData(epoch: String) -> Data {
        Data(("[" + omm(25544, epoch: epoch) + "," + omm(48274, epoch: epoch) + "]").utf8)
    }

    private var forecast: Data {
        let entries = (0..<8).map { hour in
            "{\"time\":\"2026-10-18T0\(hour):00:00Z\",\"data\":{\"instant\":{\"details\":{\"cloud_area_fraction\":\(hour * 10)}}}}"
        }
        return Data(("{\"geometry\":{\"coordinates\":[-96.8,32.8,150]},\"properties\":{\"meta\":{\"updated_at\":\"2026-10-18T00:30:00Z\"},"
            + "\"timeseries\":[\(entries.joined(separator: ","))]}}").utf8)
    }

    // MARK: State

    func testAnUntouchedResourceHasAnEmptyState() async {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let state = await box.refresher.state(.comets)
        XCTAssertNil(state.lastAttempt)
        XCTAssertFalse(state.lastAttemptFailed)
        XCTAssertNil(state.retryWait)
        XCTAssertNil(state.meta)
    }

    func testTheStateCombinesTheStoreAndTheCache() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        box.store.setLastAttempt(.forecast, now)
        box.store.setLastAttemptFailed(.forecast, true)
        box.store.setRetryWait(.forecast, 900)
        let installed = await box.refresher.install(.forecast, bytes: forecast, key: place, now: now)
        XCTAssertNotNil(installed)
        let state = await box.refresher.state(.forecast)
        XCTAssertEqual(state.lastAttempt, now)
        XCTAssertTrue(state.lastAttemptFailed)
        XCTAssertEqual(state.retryWait, 900)
        XCTAssertEqual(state.meta?.savedAt, now)
        XCTAssertEqual(state.meta?.key, place)
    }

    func testTheStateOfOneResourceIsNotThatOfAnother() async {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        box.store.setLastAttempt(.stations, now)
        let visual = await box.refresher.state(.visual)
        XCTAssertNil(visual.lastAttempt)
    }

    // MARK: Install

    func testInstallingAForecastCachesItAndReturnsIt() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let loaded = await box.refresher.install(.forecast, bytes: forecast, key: place, now: now)
        guard case .forecast(let value)? = loaded else { return XCTFail("expected a forecast") }
        XCTAssertEqual(value.hours.count, 8)
        let entry = try XCTUnwrap(box.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.savedAt, now)
        XCTAssertEqual(entry.meta.key, place)
        XCTAssertNil(entry.meta.etag)
        XCTAssertNil(entry.meta.lastModified)
        XCTAssertNil(entry.meta.expires)
        XCTAssertNil(entry.meta.dataEpoch)
    }

    func testInstallingSatellitesRecordsTheNewestEpoch() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let loaded = await box.refresher.install(.stations, bytes: satellites, key: nil, now: now)
        guard case .satellites(let group)? = loaded else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [25544, 48274])
        let meta = try XCTUnwrap(box.cache.readMeta(OnlineResource.stations.key))
        XCTAssertEqual(meta.dataEpoch?.timeIntervalSince1970 ?? 0, 1_792_294_095, accuracy: 0.001)
        XCTAssertNil(meta.key)
    }

    func testInstallingBytesThatDoNotParseChangesNothing() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let before = await box.refresher.install(.forecast, bytes: forecast, key: place, now: now)
        XCTAssertNotNil(before)
        let rejected = await box.refresher.install(.forecast, bytes: Data("not json".utf8), key: "1.0,2.0", now: now.addingTimeInterval(60))
        XCTAssertNil(rejected)
        let entry = try XCTUnwrap(box.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.key, place)
        XCTAssertEqual(entry.meta.savedAt, now)
    }

    func testInstallingReturnsNilWhenTheDiskRefuses() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        // The cache directory would have to be made inside a plain file.
        try Data([0]).write(to: box.directory)
        let blocked = OnlineCache(directory: box.directory.appendingPathComponent("inside", isDirectory: true))
        let refresher = OnlineRefresher(cache: blocked, downloader: OnlineDownloader(userAgent: "Lodestar/test"), store: box.store)
        let loaded = await refresher.install(.forecast, bytes: forecast, key: place, now: now)
        XCTAssertNil(loaded)
    }

    // MARK: Load cached

    func testNothingCachedLoadsNothing() async {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let loaded = await box.refresher.loadCached(.comets)
        XCTAssertNil(loaded)
    }

    func testCachedDataIsParsedAgainWithItsMeta() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        _ = await box.refresher.install(.forecast, bytes: forecast, key: place, now: now)
        let loaded = await box.refresher.loadCached(.forecast)
        let result = try XCTUnwrap(loaded)
        guard case .forecast(let value) = result.0 else { return XCTFail("expected a forecast") }
        XCTAssertEqual(value.hours.count, 8)
        XCTAssertEqual(result.1, box.cache.readMeta(OnlineResource.forecast.key))
        XCTAssertEqual(result.1.key, place)
    }

    func testCachedSatellitesAreRebuilt() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        // An old epoch, because loadCached parses against the real clock.
        _ = await box.refresher.install(.visual, bytes: satellitesData(epoch: "2025-03-04T05:06:07"), key: nil, now: now)
        let loaded = await box.refresher.loadCached(.visual)
        let result = try XCTUnwrap(loaded)
        guard case .satellites(let group) = result.0 else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.group, .visual)
        XCTAssertEqual(group.satellites.count, 2)
    }

    func testCachedDataThatNoLongerParsesIsRemoved() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        try box.cache.write(OnlineResource.forecast.key, bytes: Data("garbage".utf8), meta: OnlineCacheMeta(savedAt: now))
        XCTAssertNotNil(box.cache.read(OnlineResource.forecast.key))
        let loaded = await box.refresher.loadCached(.forecast)
        XCTAssertNil(loaded)
        XCTAssertNil(box.cache.read(OnlineResource.forecast.key))
        XCTAssertNil(box.cache.readMeta(OnlineResource.forecast.key))
    }

    func testCachedSatellitesFromTheFarFutureAreRemoved() async throws {
        // loadCached parses with the real clock; an epoch decades ahead leaves nothing usable, so the file goes.
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        try box.cache.write(OnlineResource.visual.key, bytes: satellitesData(epoch: "2098-01-01T00:00:00"),
                            meta: OnlineCacheMeta(savedAt: now))
        let loaded = await box.refresher.loadCached(.visual)
        XCTAssertNil(loaded)
        XCTAssertNil(box.cache.read(OnlineResource.visual.key))
    }

    // MARK: Refresh that sends nothing

    func testARefreshOfAnInsecureAddressFailsWithoutBeingCounted() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let url = try XCTUnwrap(URL(string: "http://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"))
        let outcome = await box.refresher.refresh(.comets, url: url, key: nil, now: now)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertEqual(message, "The address is not secure.")
        // Nothing was sent, so the request interval is not used up: the store is as it was.
        XCTAssertNil(box.store.lastAttempt(.comets))
        XCTAssertFalse(box.store.lastAttemptFailed(.comets))
        XCTAssertNil(box.store.retryWait(.comets))
    }

    func testTheEarlierAttemptIsRestoredAfterARefusedRequest() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        let earlier = now.addingTimeInterval(-5000)
        box.store.setLastAttempt(.comets, earlier)
        box.store.setLastAttemptFailed(.comets, true)
        box.store.setRetryWait(.comets, 1800)
        let url = try XCTUnwrap(URL(string: "http://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"))
        let outcome = await box.refresher.refresh(.comets, url: url, key: nil, now: now)
        guard case .failed(let failure, _) = outcome else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertEqual(box.store.lastAttempt(.comets), earlier)
        XCTAssertTrue(box.store.lastAttemptFailed(.comets))
        XCTAssertEqual(box.store.retryWait(.comets), 1800)
    }

    func testARefusedRefreshLeavesTheCachedDataAlone() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        _ = await box.refresher.install(.forecast, bytes: forecast, key: place, now: now)
        let url = try XCTUnwrap(URL(string: "http://api.met.no/weatherapi/locationforecast/2.0/complete?lat=32.8&lon=-96.8"))
        let outcome = await box.refresher.refresh(.forecast, url: url, key: place, now: now.addingTimeInterval(3600))
        guard case .failed = outcome else { return XCTFail("expected a failure") }
        let entry = try XCTUnwrap(box.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.savedAt, now)
    }

    func testARefusedRefreshOfOneResourceDoesNotTouchAnother() async throws {
        let box = OnlineRefresherTestsBox()
        defer { box.remove() }
        box.store.setLastAttempt(.stations, now)
        let url = try XCTUnwrap(URL(string: "http://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=json"))
        _ = await box.refresher.refresh(.visual, url: url, key: nil, now: now)
        XCTAssertEqual(box.store.lastAttempt(.stations), now)
        XCTAssertNil(box.store.lastAttempt(.visual))
    }
}

import Foundation
import XCTest
@testable import AppCore

// A redirect to an address that is not HTTPS is a request that was made: the provider answered with the 3xx. The tests run
// the downloader and the refresher against a scripted network, a small copy of the one in OnlineNetFetchTests: the protocol
// is put in front of the network of one fetch, so no request leaves the machine.

/// The script (address -> address it redirects to) and the record of the requests that reached the protocol.
private final class FixOnlineScript: @unchecked Sendable {
    static let shared = FixOnlineScript()

    private let lock = NSLock()
    private var redirects: [String: String] = [:]
    private var seen: [String] = []

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        redirects = [:]
        seen = []
    }

    func redirect(_ address: String, to target: String) {
        lock.lock()
        defer { lock.unlock() }
        redirects[address.lowercased()] = target
    }

    func target(of address: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return redirects[address.lowercased()]
    }

    func record(_ address: String) {
        lock.lock()
        defer { lock.unlock() }
        seen.append(address)
    }

    var requested: [String] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

/// Answers every request with a 302 to the address the script names.
private final class FixOnlineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let script = FixOnlineScript.shared
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        script.record(url.absoluteString)
        guard let address = script.target(of: url.absoluteString), let target = URL(string: address),
              let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                             headerFields: ["Location": address]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
    }

    override func stopLoading() {}
}

/// Hands one value to the first of two callers: the work, or the clock that gives up on it.
private final class FixOnlineGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    func arm(_ continuation: CheckedContinuation<Value?, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ value: Value?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}

/// The result of `work`, or `nil` when it has not finished after `seconds`, so that a fetch that hangs fails its test instead
/// of stopping the run. (A free function: an async method of a test class cannot take a non-escaping closure.)
private func fixOnlineBounded<Value: Sendable>(seconds: TimeInterval = 30,
                                               _ work: @escaping @Sendable () async -> Value) async -> Value? {
    let gate = FixOnlineGate<Value>()
    return await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
        gate.arm(continuation)
        Task { gate.finish(await work()) }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { gate.finish(nil) }
    }
}

/// A downloader whose network is the scripted protocol.
private func fixOnlineDownloader() -> OnlineDownloader {
    var downloader = OnlineDownloader(userAgent: "Lodestar/test")
    downloader.protocolClasses = [FixOnlineProtocol.self]
    return downloader
}

final class FixOnlineRedirectTests: XCTestCase {
    private let script = FixOnlineScript.shared
    private let start = "https://example.test/fix-start"
    private let insecure = "http://example.test/fix-insecure"
    /// 2026-10-18T04:28:15Z.
    private let now = Date(timeIntervalSince1970: 1_792_297_695)
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        script.reset()
        script.redirect(start, to: insecure)
        let id = UUID().uuidString
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FixOnlineRedirectTests-\(id)", isDirectory: true)
        suiteName = "AppCoreTests.FixOnlineRedirect.\(id)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        script.reset()
        super.tearDown()
    }

    private func makeRefresher(store: OnlineStore) -> OnlineRefresher {
        OnlineRefresher(cache: OnlineCache(directory: directory), downloader: fixOnlineDownloader(), store: store)
    }

    // MARK: The downloader

    func testARedirectToHTTPFailsAsInsecureWithTheStatusOfTheRedirect() async throws {
        let url = try XCTUnwrap(URL(string: start))
        let downloader = fixOnlineDownloader()
        let bounded = await fixOnlineBounded { await downloader.fetch(OnlineRequest(url: url, maximumBytes: 10_000)) }
        let result = try XCTUnwrap(bounded, "the fetch did not end")
        guard case .failed(let failure, let status, let retryAfter) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure, .insecure)
        // The provider answered with the 302: the failure carries it, and that is how a request that was made is told from one
        // that never left the phone.
        XCTAssertEqual(status, 302)
        XCTAssertNil(retryAfter)
        // The text of the error line does not change.
        XCTAssertEqual(failure.message(statusCode: status), "The address is not secure.")
        XCTAssertEqual(failure.message(), "The address is not secure.")
        // The insecure target was never requested.
        XCTAssertEqual(script.requested, [start])
    }

    func testOnlyAFailureWithoutAStatusCanBeARequestThatWasNeverSent() {
        XCTAssertTrue(OnlineFailure.insecure.neverSent(statusCode: nil))
        XCTAssertTrue(OnlineFailure.offline.neverSent(statusCode: nil))
        XCTAssertTrue(OnlineFailure.waitingForUnmetered.neverSent(statusCode: nil))
        // An insecure redirect came after an answer.
        XCTAssertFalse(OnlineFailure.insecure.neverSent(statusCode: 302))
        // A failure that was sent anyway stays sent.
        XCTAssertFalse(OnlineFailure.forbidden.neverSent(statusCode: nil))
        XCTAssertFalse(OnlineFailure.httpError.neverSent(statusCode: 500))
        XCTAssertFalse(OnlineFailure.timeout.neverSent(statusCode: nil))
    }

    // MARK: The refresher

    func testARedirectToHTTPIsRecordedAsARequest() async throws {
        let store = OnlineStore(defaults: defaults)
        let earlier = now.addingTimeInterval(-5000)
        store.setLastAttempt(.stations, earlier)
        store.setLastAttemptFailed(.stations, false)
        let url = try XCTUnwrap(URL(string: start))
        let refresher = makeRefresher(store: store)
        let time = now
        let bounded = await fixOnlineBounded { await refresher.refresh(.stations, url: url, key: nil, now: time) }
        let outcome = try XCTUnwrap(bounded, "the refresh did not end")
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertEqual(message, "The address is not secure.")
        // The provider was asked, so the attempt is this one, it failed, and the resource's retry interval applies.
        XCTAssertEqual(store.lastAttempt(.stations), now)
        XCTAssertTrue(store.lastAttemptFailed(.stations))
        XCTAssertEqual(store.retryWait(.stations), 7200)
    }

    func testARedirectToHTTPKeepsTheTwoHourRuleOfCelesTrak() async throws {
        let store = OnlineStore(defaults: defaults)
        let url = try XCTUnwrap(URL(string: start))
        let refresher = makeRefresher(store: store)
        let time = now
        _ = await fixOnlineBounded { await refresher.refresh(.stations, url: url, key: nil, now: time) }
        let state = await refresher.state(.stations)
        XCTAssertEqual(state.lastAttempt, now)
        // Not again within two hours (the provider has seen the request) ...
        XCTAssertFalse(OnlineSchedule.mayRequest(.stations, state: state, now: now.addingTimeInterval(60)))
        XCTAssertFalse(OnlineSchedule.mayRequest(.stations, state: state, now: now.addingTimeInterval(7199)))
        // ... and again after them.
        XCTAssertTrue(OnlineSchedule.mayRequest(.stations, state: state, now: now.addingTimeInterval(7200)))
    }
}

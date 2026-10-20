import Foundation
import LodestarKit
import XCTest
@testable import AppCore

// The downloader and the refresher against a scripted network.
//
// `OnlineDownloader.protocolClasses` puts `OnlineNetProtocol` in front of the network of the ephemeral session of one fetch
// (nothing is ever registered globally), so no request leaves the machine: the protocol answers from a script that a test
// writes per address (all addresses are on the reserved `.test` domain). Everything the protocol answers, fails or redirects
// with is a script entry; every request that reaches it is recorded, so the tests can read the headers that were sent.

// MARK: - The scripted network

/// What the protocol does for one address.
private struct OnlineNetReply {
    var status = 200
    var headers: [String: String] = [:]
    var chunks: [Data] = []
    /// When set, the answer is a redirect (`status`) to this address and has no body.
    var redirectTo: String?
    /// The error the connection fails with before anything is answered.
    var errorBeforeAnswer: Error?
    /// The error the connection fails with after the answer and its chunks.
    var errorAfterBody: Error?
    /// When set, the answer is a plain `URLResponse` (not an HTTP one).
    var plainResponse = false
    /// Seconds the protocol waits before it answers.
    var delay: TimeInterval = 0
    /// Called when the request reaches the protocol.
    var onRequest: (@Sendable () -> Void)?

    /// A complete answer with `text` as its body (no body when empty).
    static func answer(_ status: Int = 200, headers: [String: String] = [:], text: String = "") -> OnlineNetReply {
        var reply = OnlineNetReply()
        reply.status = status
        reply.headers = headers
        reply.chunks = text.isEmpty ? [] : [Data(text.utf8)]
        return reply
    }

    /// An answer whose body arrives in `chunks`; the connection breaks with `error` after them when there is one.
    static func stream(_ chunks: [Data], status: Int = 200, headers: [String: String] = [:], endingWith error: Error? = nil) -> OnlineNetReply {
        var reply = OnlineNetReply()
        reply.status = status
        reply.headers = headers
        reply.chunks = chunks
        reply.errorAfterBody = error
        return reply
    }

    /// A redirect response (`status`) to `address`.
    static func redirect(to address: String, status: Int = 302) -> OnlineNetReply {
        var reply = OnlineNetReply()
        reply.status = status
        reply.redirectTo = address
        return reply
    }

    /// A connection that fails with `error` before any answer.
    static func fail(_ error: Error) -> OnlineNetReply {
        var reply = OnlineNetReply()
        reply.errorBeforeAnswer = error
        return reply
    }

    /// An answer that is a plain `URLResponse` with `text` as its body.
    static func plain(text: String) -> OnlineNetReply {
        var reply = OnlineNetReply()
        reply.plainResponse = true
        reply.chunks = [Data(text.utf8)]
        return reply
    }

    func delayed(_ seconds: TimeInterval) -> OnlineNetReply {
        var copy = self
        copy.delay = seconds
        return copy
    }

    func calling(_ hook: @escaping @Sendable () -> Void) -> OnlineNetReply {
        var copy = self
        copy.onRequest = hook
        return copy
    }
}

/// The script and the record of the requests. The protocol runs on the queues of `URLSession`, so every access takes the lock.
private final class OnlineNetServer: @unchecked Sendable {
    static let shared = OnlineNetServer()

    private let lock = NSLock()
    private var replies: [String: OnlineNetReply] = [:]
    private var seen: [URLRequest] = []

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        replies = [:]
        seen = []
    }

    func serve(_ address: String, _ reply: OnlineNetReply) {
        lock.lock()
        defer { lock.unlock() }
        replies[address.lowercased()] = reply
    }

    func reply(for url: URL) -> OnlineNetReply? {
        lock.lock()
        defer { lock.unlock() }
        return replies[url.absoluteString.lowercased()]
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        seen.append(request)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    var requestedAddresses: [String] {
        requests.compactMap { $0.url?.absoluteString }
    }
}

/// Answers every request from `OnlineNetServer`, so no request reaches the network.
private final class OnlineNetProtocol: URLProtocol {
    private let stateLock = NSLock()
    private var stopped = false

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let server = OnlineNetServer.shared
        server.record(request)
        guard let url = request.url, let reply = server.reply(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        reply.onRequest?()
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { self.deliver(reply, url: url) }
        } else {
            deliver(reply, url: url)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private func deliver(_ reply: OnlineNetReply, url: URL) {
        if isStopped { return }
        if let error = reply.errorBeforeAnswer {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let address = reply.redirectTo {
            guard let target = URL(string: address),
                  let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Location": address]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            var next = URLRequest(url: target)
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        let response: URLResponse
        if reply.plainResponse {
            response = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: -1, textEncodingName: nil)
        } else if let http = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: reply.headers) {
            response = http
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks {
            if isStopped { return }
            client?.urlProtocol(self, didLoad: chunk)
        }
        if isStopped { return }
        if let error = reply.errorAfterBody {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

/// Hands one value to the first of two callers: the work, or the clock that gives up on it.
private final class OnlineNetGate<Value: Sendable>: @unchecked Sendable {
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

/// The result of `work`, or `nil` when it has not finished after `seconds`. A fetch that hangs then fails its test instead
/// of stopping the run. (A free function: an async method of a test class cannot take a non-escaping closure.)
private func onlineNetBounded<Value: Sendable>(seconds: TimeInterval = 30,
                                               _ work: @escaping @Sendable () async -> Value) async -> Value? {
    let gate = OnlineNetGate<Value>()
    return await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
        gate.arm(continuation)
        Task { gate.finish(await work()) }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { gate.finish(nil) }
    }
}

/// Waits (a few milliseconds at a time) until `count` requests have reached the protocol; `false` after `timeout` seconds.
private func onlineNetWaitForRequests(_ count: Int, timeout: TimeInterval = 20) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while OnlineNetServer.shared.requests.count < count {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return true
}

/// An HTTP date ("Sun, 06 Nov 1994 08:49:37 GMT").
private func onlineNetHTTPDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
}

/// A downloader whose network is the scripted protocol.
private func onlineNetDownloader(userAgent: String? = "Lodestar/test", idleTimeout: TimeInterval? = nil) -> OnlineDownloader {
    var downloader = userAgent.map { OnlineDownloader(userAgent: $0) } ?? OnlineDownloader()
    downloader.protocolClasses = [OnlineNetProtocol.self]
    if let idleTimeout { downloader.idleTimeout = idleTimeout }
    return downloader
}

/// One fetch against the scripted network. A fetch that does not end fails the test and answers `.timeout`.
private func onlineNetFetch(_ address: String, maximumBytes: Int = 10_000, etag: String? = nil, lastModified: String? = nil,
                            expensive: Bool = true, userAgent: String? = "Lodestar/test",
                            idleTimeout: TimeInterval? = nil) async -> OnlineResult {
    guard let url = URL(string: address) else {
        XCTFail("not an address: \(address)")
        return .failed(.unreadable, statusCode: nil)
    }
    let downloader = onlineNetDownloader(userAgent: userAgent, idleTimeout: idleTimeout)
    let request = OnlineRequest(url: url, maximumBytes: maximumBytes, etag: etag, lastModified: lastModified,
                                allowsExpensiveNetwork: expensive)
    let bounded = await onlineNetBounded { await downloader.fetch(request) }
    guard let result = bounded else {
        XCTFail("the fetch of \(address) did not end")
        return .failed(.timeout, statusCode: nil)
    }
    return result
}

// MARK: - OnlineDownloader

/// `OnlineDownloader.fetch`: every branch of the answer, the redirect rules, the size limit, the errors and the request that
/// goes out.
final class OnlineNetDownloaderTests: XCTestCase {
    private let server = OnlineNetServer.shared
    private let host = "https://example.test"

    override func setUp() {
        super.setUp()
        server.reset()
    }

    override func tearDown() {
        server.reset()
        super.tearDown()
    }

    @discardableResult
    private func serve(_ path: String, _ reply: OnlineNetReply) -> String {
        let address = host + path
        server.serve(address, reply)
        return address
    }

    private func expectFailure(_ result: OnlineResult, _ expected: OnlineFailure, status: Int? = nil, retryAfter: TimeInterval? = nil,
                               _ context: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard case .failed(let failure, let statusCode, let wait) = result else {
            return XCTFail("expected \(expected), got \(result) \(context)", file: file, line: line)
        }
        XCTAssertEqual(failure, expected, context, file: file, line: line)
        XCTAssertEqual(statusCode, status, context, file: file, line: line)
        XCTAssertEqual(wait, retryAfter, context, file: file, line: line)
    }

    /// Addresses `/chain-<name>-0` … `-<hops>`: each redirects to the next, the last one answers "end".
    private func serveChain(_ name: String, hops: Int) -> [String] {
        var addresses: [String] = []
        for index in 0...hops { addresses.append(host + "/chain-\(name)-\(index)") }
        for index in 0..<hops { server.serve(addresses[index], .redirect(to: addresses[index + 1])) }
        server.serve(addresses[hops], .answer(text: "end"))
        return addresses
    }

    // MARK: Answers

    func testAnAnswerIsDeliveredWithTheServersValidators() async {
        let address = serve("/data", .answer(headers: [
            "ETag": "\"v7\"", "Last-Modified": "Sun, 18 Oct 2026 03:00:00 GMT", "Expires": "Sun, 18 Oct 2026 19:50:18 GMT",
        ], text: "hello"))
        let result = await onlineNetFetch(address)
        guard case .downloaded(let bytes, let etag, let lastModified, let expires) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes, Data("hello".utf8))
        XCTAssertEqual(etag, "\"v7\"")
        XCTAssertEqual(lastModified, "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertEqual(expires, Date(timeIntervalSince1970: 1_792_353_018))
    }

    func testHeaderNamesAreMatchedWithoutRegardToCase() async {
        let address = serve("/lower", .answer(headers: [
            "etag": "\"low\"", "last-modified": "Sun, 18 Oct 2026 03:00:00 GMT", "EXPIRES": "Sun, 18 Oct 2026 19:50:18 GMT",
        ], text: "x"))
        let result = await onlineNetFetch(address)
        guard case .downloaded(_, let etag, let lastModified, let expires) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(etag, "\"low\"")
        XCTAssertEqual(lastModified, "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertEqual(expires, Date(timeIntervalSince1970: 1_792_353_018))
    }

    func testAnAnswerWithoutValidatorsHasNone() async {
        let address = serve("/bare", .answer(text: "bare"))
        let result = await onlineNetFetch(address)
        guard case .downloaded(let bytes, let etag, let lastModified, let expires) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes, Data("bare".utf8))
        XCTAssertNil(etag)
        XCTAssertNil(lastModified)
        XCTAssertNil(expires)
    }

    func testAnExpiresThatIsNotAnHTTPDateCountsAsNone() async {
        let values = ["0", "soon", "2026-10-18T19:50:18Z", "-1", ""]
        for (index, value) in values.enumerated() {
            let address = serve("/expires-\(index)", .answer(headers: ["Expires": value, "ETag": "\"kept\""], text: "x"))
            let result = await onlineNetFetch(address)
            guard case .downloaded(_, let etag, _, let expires) = result else { XCTFail("\(result) for '\(value)'"); continue }
            XCTAssertNil(expires, "'\(value)'")
            // The other validators are not affected by an Expires that cannot be read.
            XCTAssertEqual(etag, "\"kept\"", "'\(value)'")
        }
    }

    func testTheBodyOfSeveralChunksIsJoinedInOrder() async {
        let address = serve("/chunks", .stream([Data("alpha ".utf8), Data("beta ".utf8), Data("gamma".utf8)]))
        let result = await onlineNetFetch(address)
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "alpha beta gamma")
    }

    func testEveryAnswerOf2xxWithABodyIsADownload() async {
        for status in [200, 201, 202, 203, 299] {
            let address = serve("/ok-\(status)", .answer(status, text: "body \(status)"))
            let result = await onlineNetFetch(address)
            guard case .downloaded(let bytes, _, _, _) = result else { XCTFail("\(result) for \(status)"); continue }
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "body \(status)")
        }
    }

    func testAnAnswerWithoutABodyIsEmpty() async {
        let plain = serve("/empty", .answer())
        expectFailure(await onlineNetFetch(plain), .empty)
        let announced = serve("/empty-length", .answer(headers: ["Content-Length": "0"]))
        expectFailure(await onlineNetFetch(announced), .empty)
        let noContent = serve("/no-content", .answer(204))
        expectFailure(await onlineNetFetch(noContent), .empty)
    }

    // MARK: Size limit

    func testABodyOfExactlyTheLimitIsAccepted() async {
        let address = serve("/exact", .stream([Data(repeating: 0x61, count: 100)]))
        let result = await onlineNetFetch(address, maximumBytes: 100)
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes.count, 100)
    }

    func testABodyOneByteOverTheLimitIsTooLarge() async {
        let address = serve("/over", .stream([Data(repeating: 0x61, count: 101)]))
        expectFailure(await onlineNetFetch(address, maximumBytes: 100), .tooLarge)
    }

    func testChunksThatTogetherPassTheLimitAreTooLarge() async {
        let chunks = [Data(repeating: 0x61, count: 60), Data(repeating: 0x62, count: 30), Data(repeating: 0x63, count: 30)]
        let address = serve("/chunks-over", .stream(chunks))
        expectFailure(await onlineNetFetch(address, maximumBytes: 100), .tooLarge)
    }

    func testChunksThatTogetherReachTheLimitExactlyAreAccepted() async {
        let chunks = [Data(repeating: 0x61, count: 60), Data(repeating: 0x62, count: 40)]
        let address = serve("/chunks-exact", .stream(chunks))
        let result = await onlineNetFetch(address, maximumBytes: 100)
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes, chunks[0] + chunks[1])
    }

    func testAnAnnouncedLengthOverTheLimitIsTooLargeWhateverTheBodyIs() async {
        let address = serve("/announced", .stream([Data("tiny".utf8)], headers: ["Content-Length": "101"]))
        expectFailure(await onlineNetFetch(address, maximumBytes: 100), .tooLarge)
    }

    func testAnAnnouncedLengthAtTheLimitIsAccepted() async {
        let address = serve("/announced-exact", .stream([Data(repeating: 0x61, count: 100)], headers: ["Content-Length": "100"]))
        let result = await onlineNetFetch(address, maximumBytes: 100)
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes.count, 100)
    }

    func testTheLengthIsOnlyCheckedForASuccessfulAnswer() async {
        // A 404 that announces a huge page is an HTTP error, not a download that is too large.
        let address = serve("/huge-404", .answer(404, headers: ["Content-Length": "999999"]))
        expectFailure(await onlineNetFetch(address, maximumBytes: 100), .httpError, status: 404)
    }

    // MARK: Not modified

    func testNotModifiedCarriesTheServersExpires() async {
        let address = serve("/not-modified", .answer(304, headers: ["Expires": "Mon, 19 Oct 2026 06:00:00 GMT"]))
        let result = await onlineNetFetch(address, etag: "\"v1\"")
        guard case .notModified(let expires) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(expires, Date(timeIntervalSince1970: 1_792_389_600))
    }

    func testNotModifiedWithoutAUsableExpiresHasNone() async {
        let missing = serve("/not-modified-bare", .answer(304))
        guard case .notModified(let bare) = await onlineNetFetch(missing, etag: "\"v1\"") else { return XCTFail("expected 304") }
        XCTAssertNil(bare)
        let invalid = serve("/not-modified-zero", .answer(304, headers: ["Expires": "0"]))
        guard case .notModified(let zero) = await onlineNetFetch(invalid, etag: "\"v1\"") else { return XCTFail("expected 304") }
        XCTAssertNil(zero)
    }

    // MARK: HTTP errors

    func testForbiddenIsReportedWithItsStatus() async {
        let address = serve("/forbidden", .answer(403))
        expectFailure(await onlineNetFetch(address), .forbidden, status: 403)
    }

    func testForbiddenCarriesTheSecondsOfRetryAfter() async {
        let address = serve("/forbidden-wait", .answer(403, headers: ["Retry-After": "120"]))
        expectFailure(await onlineNetFetch(address), .forbidden, status: 403, retryAfter: 120)
    }

    func testRateLimitedCarriesTheSecondsOfRetryAfter() async {
        let address = serve("/limited", .answer(429, headers: ["Retry-After": "30"]))
        expectFailure(await onlineNetFetch(address), .rateLimited, status: 429, retryAfter: 30)
    }

    func testRateLimitedWithoutRetryAfterHasNoWait() async {
        let address = serve("/limited-bare", .answer(429))
        expectFailure(await onlineNetFetch(address), .rateLimited, status: 429)
    }

    func testRetryAfterMayBeAnHTTPDateInTheFuture() async throws {
        let address = serve("/limited-date", .answer(429, headers: ["Retry-After": onlineNetHTTPDate(Date().addingTimeInterval(600))]))
        let result = await onlineNetFetch(address)
        guard case .failed(let failure, let status, let retryAfter) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(failure, .rateLimited)
        XCTAssertEqual(status, 429)
        // The date has whole seconds and the clock moves on: allow half a minute either way.
        XCTAssertEqual(try XCTUnwrap(retryAfter), 600, accuracy: 30)
    }

    func testRetryAfterThatIsPastZeroNegativeOrNotANumberIsIgnored() async {
        let values = ["Sun, 06 Nov 1994 08:49:37 GMT", "0", "-5", "soon", "", "inf", "nan"]
        for (index, value) in values.enumerated() {
            let address = serve("/ignored-\(index)", .answer(429, headers: ["Retry-After": value]))
            expectFailure(await onlineNetFetch(address), .rateLimited, status: 429, "Retry-After '\(value)'")
        }
    }

    func testRetryAfterAroundItsNumberIsTrimmed() async {
        let address = serve("/limited-spaces", .answer(429, headers: ["Retry-After": " 45 "]))
        expectFailure(await onlineNetFetch(address), .rateLimited, status: 429, retryAfter: 45)
    }

    func testTheDownloaderDoesNotCapRetryAfter() async {
        // The longest wait is applied where the wait is decided (OnlineSchedule), not here.
        let address = serve("/limited-long", .answer(429, headers: ["Retry-After": "1000000"]))
        expectFailure(await onlineNetFetch(address), .rateLimited, status: 429, retryAfter: 1_000_000)
    }

    func testOtherStatusesAreHTTPErrorsWithTheirCode() async {
        for status in [300, 400, 404, 410, 500, 502, 503] {
            let address = serve("/status-\(status)", .answer(status, text: "an error page"))
            expectFailure(await onlineNetFetch(address), .httpError, status: status, "status \(status)")
        }
    }

    func testAnAnswerThatIsNotHTTPIsAnHTTPErrorWithoutAStatus() async {
        let address = serve("/not-http", .plain(text: "hello"))
        expectFailure(await onlineNetFetch(address), .httpError)
    }

    func testAServerErrorKeepsItsRetryAfter() async {
        let address = serve("/unavailable", .answer(503, headers: ["Retry-After": "60"]))
        expectFailure(await onlineNetFetch(address), .httpError, status: 503, retryAfter: 60)
    }

    // MARK: Redirects

    func testARedirectToAnotherHTTPSAddressIsFollowed() async {
        for status in [301, 302, 307, 308] {
            let target = serve("/final-\(status)", .answer(text: "arrived \(status)"))
            let start = serve("/start-\(status)", .redirect(to: target, status: status))
            let result = await onlineNetFetch(start)
            guard case .downloaded(let bytes, _, _, _) = result else { XCTFail("\(result) for \(status)"); continue }
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "arrived \(status)")
            XCTAssertEqual(Array(server.requestedAddresses.suffix(2)), [start, target], "status \(status)")
        }
    }

    func testFourRedirectsInARowAreFollowedToTheEnd() async {
        let addresses = serveChain("four", hops: 4)
        let result = await onlineNetFetch(addresses[0])
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "end")
        XCTAssertEqual(server.requestedAddresses, addresses)
    }

    func testTheFifthRedirectFailsAsAnHTTPErrorWithTheRedirectsStatus() async {
        let addresses = serveChain("five", hops: 5)
        let result = await onlineNetFetch(addresses[0])
        expectFailure(result, .httpError, status: 302)
        // The fifth redirect is refused before its target is requested.
        XCTAssertEqual(server.requestedAddresses, Array(addresses[0...4]))
    }

    func testARedirectChainThatNeverEndsStopsAfterFiveRequests() async {
        let addresses = serveChain("endless", hops: 12)
        expectFailure(await onlineNetFetch(addresses[0]), .httpError, status: 302)
        XCTAssertEqual(server.requestedAddresses, Array(addresses[0...4]))
    }

    func testARedirectToHTTPIsInsecureAndTheTargetIsNeverRequested() async {
        let start = serve("/to-http", .redirect(to: "http://example.test/insecure"))
        serve("/insecure", .answer(text: "plain text"))
        expectFailure(await onlineNetFetch(start), .insecure)
        XCTAssertEqual(server.requestedAddresses, [start])
    }

    func testTheSchemeOfARedirectIsCheckedBeforeTheCount() async {
        let addresses = serveChain("late-http", hops: 5)
        // The fifth redirect would be one too many, but it also leaves HTTPS: that is the failure that is reported.
        server.serve(addresses[4], .redirect(to: "http://example.test/insecure"))
        expectFailure(await onlineNetFetch(addresses[0]), .insecure)
    }

    func testARedirectTargetMayHaveAnUpperCaseScheme() async {
        serve("/upper-final", .answer(text: "arrived"))
        let start = serve("/to-upper", .redirect(to: "HTTPS://example.test/upper-final"))
        let result = await onlineNetFetch(start)
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "arrived")
    }

    // MARK: Errors of the connection

    func testNoAnswerInTimeIsATimeout() async {
        let address = serve("/timeout", .fail(URLError(.timedOut)))
        expectFailure(await onlineNetFetch(address), .timeout)
    }

    func testConnectionProblemsAreNetworkFailures() async {
        let codes: [URLError.Code] = [.cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed]
        for (index, code) in codes.enumerated() {
            let address = serve("/network-\(index)", .fail(URLError(code)))
            expectFailure(await onlineNetFetch(address), .network, "code \(code.rawValue)")
        }
    }

    func testAnErrorThatIsNotAURLErrorIsANetworkFailure() async {
        let address = serve("/foreign", .fail(NSError(domain: "OnlineNetTests", code: 42)))
        expectFailure(await onlineNetFetch(address), .network)
    }

    func testBeingOfflineIsReportedAsOffline() async {
        let codes: [URLError.Code] = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive]
        for (index, code) in codes.enumerated() {
            let address = serve("/offline-\(index)", .fail(URLError(code)))
            expectFailure(await onlineNetFetch(address), .offline, "code \(code.rawValue)")
        }
    }

    func testTheAppTransportSecurityRefusalIsInsecure() async {
        let address = serve("/ats", .fail(URLError(.appTransportSecurityRequiresSecureConnection)))
        expectFailure(await onlineNetFetch(address), .insecure)
    }

    func testAnExpensiveOrConstrainedNetworkMeansWaitingForAnUnmeteredOne() async {
        // The reason travels in the error's user info under the key of `URLError.networkUnavailableReason`; both spellings of the
        // key are given so that the test does not depend on which one the system reads.
        for reason in [URLError.NetworkUnavailableReason.expensive, URLError.NetworkUnavailableReason.constrained] {
            let info: [String: Any] = [
                "NSURLErrorNetworkUnavailableReasonKey": reason.rawValue,
                "_NSURLErrorNetworkUnavailableReasonKey": reason.rawValue,
            ]
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: info)
            let address = serve("/unmetered-\(reason.rawValue)", .fail(error))
            expectFailure(await onlineNetFetch(address), .waitingForUnmetered, "reason \(reason.rawValue)")
        }
    }

    func testABrokenConnectionAfterTheAnswerIsInterrupted() async {
        let chunks = [Data("part of ".utf8)]
        let address = serve("/broken", .stream(chunks, endingWith: URLError(.networkConnectionLost)))
        expectFailure(await onlineNetFetch(address), .interrupted)
    }

    func testATimeoutAfterTheAnswerIsInterrupted() async {
        let address = serve("/stalled", .stream([Data("part of ".utf8)], endingWith: URLError(.timedOut)))
        expectFailure(await onlineNetFetch(address), .interrupted)
    }

    func testAnErrorBeforeAnyBodyAfterTheHeadersIsInterruptedToo() async {
        let address = serve("/broken-early", .stream([], endingWith: URLError(.networkConnectionLost)))
        expectFailure(await onlineNetFetch(address), .interrupted)
    }

    func testAnErrorAfterAnErrorStatusKeepsTheStatusFailure() async {
        let address = serve("/forbidden-broken", .stream([Data("x".utf8)], status: 403, endingWith: URLError(.networkConnectionLost)))
        expectFailure(await onlineNetFetch(address), .forbidden, status: 403)
    }

    func testAnErrorAfterNotModifiedStillMeansNotModified() async {
        let address = serve("/not-modified-broken", .stream([], status: 304, endingWith: URLError(.networkConnectionLost)))
        guard case .notModified(let expires) = await onlineNetFetch(address, etag: "\"v1\"") else { return XCTFail("expected 304") }
        XCTAssertNil(expires)
    }

    // MARK: Cancellation

    func testCancellingTheTaskEndsAFetchThatIsWaitingForTheServer() async {
        let address = serve("/slow", OnlineNetReply.answer(text: "late").delayed(20))
        guard let url = URL(string: address) else { return XCTFail("address") }
        let downloader = onlineNetDownloader()
        let request = OnlineRequest(url: url, maximumBytes: 1000)
        let fetching = Task { await downloader.fetch(request) }
        let reached = await onlineNetWaitForRequests(1)
        XCTAssertTrue(reached, "the request never reached the protocol")
        fetching.cancel()
        let bounded = await onlineNetBounded(seconds: 10) { await fetching.value }
        guard let result = bounded else { return XCTFail("the fetch did not end after its task was cancelled") }
        guard case .failed = result else { return XCTFail("expected a failure, got \(result)") }
    }

    func testATaskThatIsCancelledBeforeTheFetchStillEnds() async {
        let address = serve("/slow-early", OnlineNetReply.answer(text: "late").delayed(20))
        guard let url = URL(string: address) else { return XCTFail("address") }
        let downloader = onlineNetDownloader()
        let request = OnlineRequest(url: url, maximumBytes: 1000)
        let fetching = Task { () -> OnlineResult in
            while !Task.isCancelled { await Task.yield() }
            return await downloader.fetch(request)
        }
        fetching.cancel()
        let bounded = await onlineNetBounded(seconds: 10) { await fetching.value }
        guard let result = bounded else { return XCTFail("the fetch did not end although its task was cancelled") }
        guard case .failed = result else { return XCTFail("expected a failure, got \(result)") }
    }

    // MARK: The request that goes out

    func testTheRequestIsAPlainGETWithTheUserAgentAndNothingConditional() async {
        let address = serve("/plain", .answer(text: "x"))
        _ = await onlineNetFetch(address, userAgent: "Lodestar/9.9 (test)")
        guard let request = server.requests.first else { return XCTFail("no request reached the protocol") }
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, address)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Lodestar/9.9 (test)")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testTheDefaultUserAgentIsTheOneOfThisBuild() async {
        let address = serve("/default-agent", .answer(text: "x"))
        _ = await onlineNetFetch(address, userAgent: nil)
        XCTAssertEqual(server.requests.first?.value(forHTTPHeaderField: "User-Agent"), OnlineUserAgent.current)
    }

    func testTheEntityTagIsSentAsIfNoneMatch() async {
        let address = serve("/etag", .answer(304))
        _ = await onlineNetFetch(address, etag: "\"abc123\"")
        let request = server.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-None-Match"), "\"abc123\"")
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-Modified-Since"))
    }

    func testTheLastModifiedTextIsSentAsIfModifiedSince() async {
        let address = serve("/modified", .answer(304))
        _ = await onlineNetFetch(address, lastModified: "Sun, 18 Oct 2026 03:00:00 GMT")
        let request = server.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-Modified-Since"), "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testBothValidatorsAreSentTogether() async {
        let address = serve("/both", .answer(304))
        _ = await onlineNetFetch(address, etag: "W/\"weak\"", lastModified: "Sat, 17 Oct 2026 12:00:00 GMT")
        let request = server.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-None-Match"), "W/\"weak\"")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-Modified-Since"), "Sat, 17 Oct 2026 12:00:00 GMT")
    }

    func testTheRequestTimeoutIsTheIdleTimeout() async {
        let custom = serve("/idle-custom", .answer(text: "x"))
        _ = await onlineNetFetch(custom, idleTimeout: 17)
        XCTAssertEqual(server.requests.first?.timeoutInterval, 17)
        let standard = serve("/idle-default", .answer(text: "x"))
        _ = await onlineNetFetch(standard)
        XCTAssertEqual(server.requests.last?.timeoutInterval, 30)
    }

    func testNoCookieIsSentAndNoneIsKept() async {
        let address = serve("/cookie", .answer(headers: ["Set-Cookie": "session=abc; Path=/"], text: "x"))
        _ = await onlineNetFetch(address)
        _ = await onlineNetFetch(address)
        let requests = server.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }

    func testTheNetworkSettingDoesNotChangeWhatIsAskedFor() async {
        for expensive in [true, false] {
            let address = serve("/expensive-\(expensive)", .answer(headers: ["ETag": "\"e\""], text: "x"))
            let result = await onlineNetFetch(address, expensive: expensive)
            guard case .downloaded(let bytes, let etag, _, _) = result else { XCTFail("\(result)"); continue }
            XCTAssertEqual(bytes, Data("x".utf8))
            XCTAssertEqual(etag, "\"e\"")
        }
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests[0].value(forHTTPHeaderField: "User-Agent"), "Lodestar/test")
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "User-Agent"), "Lodestar/test")
    }

    func testAnAddressThatIsNotHTTPSNeverReachesTheProtocol() async {
        serve("/plain-text", .answer(text: "x"))
        expectFailure(await onlineNetFetch("http://example.test/plain-text"), .insecure)
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testTheSchemeOfTheAddressMayBeUpperCase() async {
        serve("/shouting", .answer(text: "loud"))
        let result = await onlineNetFetch("HTTPS://example.test/shouting")
        guard case .downloaded(let bytes, _, _, _) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(bytes, Data("loud".utf8))
    }

    func testFetchesRunAtTheSameTimeDoNotShareAnything() async {
        let first = serve("/first", .answer(headers: ["ETag": "\"first\""], text: "one"))
        let second = serve("/second", .answer(403))
        async let one = onlineNetFetch(first)
        async let two = onlineNetFetch(second)
        let results = await (one, two)
        guard case .downloaded(let bytes, let etag, _, _) = results.0 else { return XCTFail("\(results.0)") }
        XCTAssertEqual(bytes, Data("one".utf8))
        XCTAssertEqual(etag, "\"first\"")
        expectFailure(results.1, .forbidden, status: 403)
    }
}

// MARK: - OnlineRefresher

/// A temporary cache directory and a private defaults suite for one test.
private final class OnlineNetBench {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: OnlineStore
    let cache: OnlineCache
    let downloader: OnlineDownloader
    let refresher: OnlineRefresher
    /// 2026-10-18T04:28:15Z.
    let now = Date(timeIntervalSince1970: 1_792_297_695)

    init() {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnlineNetTests-\(id)", isDirectory: true)
        let suiteName = "AppCoreTests.OnlineNet.\(id)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = OnlineStore(defaults: defaults)
        let cache = OnlineCache(directory: directory)
        let downloader = onlineNetDownloader()
        self.directory = directory
        self.suiteName = suiteName
        self.defaults = defaults
        self.store = store
        self.cache = cache
        self.downloader = downloader
        self.refresher = OnlineRefresher(cache: cache, downloader: downloader, store: store)
    }

    func remove() {
        // A test may have taken the write permission of the directory away.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// What the store held at the moment a request reached the protocol.
private final class OnlineNetObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var attempt: Date?
    private var failed = false
    private var wait: TimeInterval?

    func record(_ store: OnlineStore, _ resource: OnlineResource) {
        let lastAttempt = store.lastAttempt(resource)
        let lastFailed = store.lastAttemptFailed(resource)
        let retryWait = store.retryWait(resource)
        lock.lock()
        calls += 1
        attempt = lastAttempt
        failed = lastFailed
        wait = retryWait
        lock.unlock()
    }

    var snapshot: (calls: Int, attempt: Date?, failed: Bool, wait: TimeInterval?) {
        lock.lock()
        defer { lock.unlock() }
        return (calls, attempt, failed, wait)
    }
}

/// `OnlineRefresher.refresh` with a downloader whose network is the scripted protocol: the outcomes, what reaches the cache and
/// the store, the validators that are sent and the waits that follow a failure.
///
/// The waits are written out from the rules: a resource's retry interval is 10 minutes for the forecast, 2 hours for the
/// CelesTrak groups and 1 hour for the comets; a time-out or no route waits at most 10 minutes; a 403 or 429 at least an hour;
/// a `Retry-After` adds its seconds up to a day.
final class OnlineNetRefresherTests: XCTestCase {
    private let server = OnlineNetServer.shared
    private let host = "https://example.test"
    private let place = "32.8,-96.8"
    private let oldSaved = Date(timeIntervalSince1970: 1_792_290_000)
    private var bench: OnlineNetBench!

    override func setUp() {
        super.setUp()
        server.reset()
        bench = OnlineNetBench()
    }

    override func tearDown() {
        bench.remove()
        bench = nil
        server.reset()
        super.tearDown()
    }

    // MARK: Fixtures

    private func omm(_ number: Int, epoch: String) -> String {
        let fields = [
            "\"OBJECT_NAME\":\"TEST SAT \(number)\"", "\"OBJECT_ID\":\"2020-001A\"", "\"EPOCH\":\"\(epoch)\"",
            "\"MEAN_MOTION\":15.5", "\"ECCENTRICITY\":0.001", "\"INCLINATION\":51.6", "\"RA_OF_ASC_NODE\":10",
            "\"ARG_OF_PERICENTER\":20", "\"MEAN_ANOMALY\":30", "\"EPHEMERIS_TYPE\":0", "\"CLASSIFICATION_TYPE\":\"U\"",
            "\"NORAD_CAT_ID\":\(number)", "\"ELEMENT_SET_NO\":7", "\"REV_AT_EPOCH\":99", "\"BSTAR\":0.0001",
            "\"MEAN_MOTION_DOT\":0.00001", "\"MEAN_MOTION_DDOT\":0",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// Two satellites with an element set of 2025-03-04T05:06:07Z (an old epoch, because a refresh parses with the real clock).
    private var satellites: Data {
        Data(("[" + omm(25544, epoch: "2025-03-04T05:06:07") + "," + omm(48274, epoch: "2025-03-04T05:06:07") + "]").utf8)
    }

    private var forecast: Data {
        let entries = (0..<8).map { hour in
            "{\"time\":\"2026-10-18T0\(hour):00:00Z\",\"data\":{\"instant\":{\"details\":{\"cloud_area_fraction\":\(hour * 10)}}}}"
        }
        return Data(("{\"geometry\":{\"coordinates\":[-96.8,32.8,150]},\"properties\":{\"meta\":{\"updated_at\":\"2026-10-18T00:30:00Z\"},"
            + "\"timeseries\":[\(entries.joined(separator: ","))]}}").utf8)
    }

    // Real lines of the Minor Planet Center's comet file.
    private let haleBopp = "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091"
    private let halley = "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592"

    private var comets: Data { Data([haleBopp, halley].joined(separator: "\n").utf8) }

    // MARK: Helpers

    @discardableResult
    private func serve(_ path: String, _ reply: OnlineNetReply) -> String {
        let address = host + path
        server.serve(address, reply)
        return address
    }

    private func refresh(_ resource: OnlineResource, _ address: String, key: String? = nil,
                         using custom: OnlineRefresher? = nil) async -> OnlineRefreshOutcome {
        guard let url = URL(string: address) else {
            XCTFail("not an address: \(address)")
            return .failed(.unreadable, message: "")
        }
        let refresher = custom ?? bench.refresher
        let now = bench.now
        let bounded = await onlineNetBounded { await refresher.refresh(resource, url: url, key: key, now: now) }
        guard let outcome = bounded else {
            XCTFail("the refresh of \(address) did not end")
            return .failed(.timeout, message: "")
        }
        return outcome
    }

    /// Puts `bytes` in the cache of `resource` as saved long before the tests' `now`.
    private func cacheCopy(_ resource: OnlineResource, bytes: Data, etag: String? = nil, lastModified: String? = nil,
                           expires: Date? = nil, key: String? = nil) throws -> OnlineCacheMeta {
        let meta = OnlineCacheMeta(savedAt: oldSaved, etag: etag, lastModified: lastModified, expires: expires,
                                   dataEpoch: Date(timeIntervalSince1970: 1_792_280_000), key: key)
        try bench.cache.write(resource.key, bytes: bytes, meta: meta)
        return meta
    }

    /// What a failed refresh must have recorded: the attempt is `now`, it failed and `wait` seconds are to pass.
    private func expectRecorded(_ resource: OnlineResource, wait: TimeInterval?, _ context: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(bench.store.lastAttempt(resource), bench.now, context, file: file, line: line)
        XCTAssertTrue(bench.store.lastAttemptFailed(resource), context, file: file, line: line)
        XCTAssertEqual(bench.store.retryWait(resource), wait, context, file: file, line: line)
    }

    // MARK: Updated

    func testADownloadedForecastIsParsedCachedAndRecorded() async throws {
        let address = serve("/forecast", .stream([forecast], headers: [
            "ETag": "\"f1\"", "Last-Modified": "Sun, 18 Oct 2026 03:00:00 GMT", "Expires": "Sun, 18 Oct 2026 19:50:18 GMT",
        ]))
        let before = Date()
        let outcome = await refresh(.forecast, address, key: place)
        let after = Date()
        guard case .updated(let loaded, let meta) = outcome else { return XCTFail("\(outcome)") }
        guard case .forecast(let value) = loaded else { return XCTFail("expected a forecast") }
        XCTAssertEqual(value.hours.count, 8)
        XCTAssertEqual(meta.etag, "\"f1\"")
        XCTAssertEqual(meta.lastModified, "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertEqual(meta.expires, Date(timeIntervalSince1970: 1_792_353_018))
        XCTAssertEqual(meta.key, place)
        XCTAssertNil(meta.dataEpoch)
        XCTAssertGreaterThanOrEqual(meta.savedAt, before)
        XCTAssertLessThanOrEqual(meta.savedAt, after)
        // The cache holds the bytes and the same metadata.
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.etag, "\"f1\"")
        XCTAssertEqual(entry.meta.lastModified, "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertEqual(entry.meta.expires, Date(timeIntervalSince1970: 1_792_353_018))
        XCTAssertEqual(entry.meta.key, place)
        XCTAssertEqual(entry.meta.savedAt.timeIntervalSince1970, meta.savedAt.timeIntervalSince1970, accuracy: 0.001)
        // The request is recorded as made and as having worked.
        XCTAssertEqual(bench.store.lastAttempt(.forecast), bench.now)
        XCTAssertFalse(bench.store.lastAttemptFailed(.forecast))
        XCTAssertNil(bench.store.retryWait(.forecast))
    }

    func testDownloadedSatellitesRecordTheirNewestEpoch() async throws {
        let address = serve("/stations", .stream([satellites]))
        let outcome = await refresh(.stations, address)
        guard case .updated(let loaded, let meta) = outcome else { return XCTFail("\(outcome)") }
        guard case .satellites(let group) = loaded else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.group, .stations)
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [25544, 48274])
        XCTAssertEqual(meta.dataEpoch?.timeIntervalSince1970 ?? 0, 1_741_064_767, accuracy: 0.001)
        XCTAssertNil(meta.key)
        XCTAssertNil(meta.etag)
        XCTAssertNil(meta.lastModified)
        XCTAssertNil(meta.expires)
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.stations.key))
        XCTAssertEqual(entry.bytes, satellites)
        XCTAssertEqual(entry.meta.dataEpoch?.timeIntervalSince1970 ?? 0, 1_741_064_767, accuracy: 0.001)
    }

    func testDownloadedCometsJoinTheCacheWithoutAnEpoch() async throws {
        let address = serve("/comets", .stream([comets], headers: ["ETag": "\"c1\""]))
        let outcome = await refresh(.comets, address)
        guard case .updated(let loaded, let meta) = outcome else { return XCTFail("\(outcome)") }
        guard case .comets(let bodies) = loaded else { return XCTFail("expected comets") }
        XCTAssertEqual(bodies.map(\.id), ["comet.C/1995 O1", "comet.1P"])
        XCTAssertEqual(meta.etag, "\"c1\"")
        XCTAssertNil(meta.dataEpoch)
        XCTAssertEqual(try XCTUnwrap(bench.cache.read(OnlineResource.comets.key)).bytes, comets)
    }

    func testTheValidatorsOfTheNewCopyAreTheServersNotTheOldOnes() async throws {
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"old\"", lastModified: "Sat, 17 Oct 2026 12:00:00 GMT",
                          expires: Date(timeIntervalSince1970: 1_792_291_000), key: place)
        let address = serve("/forecast-new", .stream([forecast]))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .updated(_, let meta) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(meta.etag)
        XCTAssertNil(meta.lastModified)
        XCTAssertNil(meta.expires)
        let stored = try XCTUnwrap(bench.cache.readMeta(OnlineResource.forecast.key))
        XCTAssertNil(stored.etag)
        XCTAssertNil(stored.lastModified)
        XCTAssertNil(stored.expires)
    }

    func testASuccessClearsTheFailureAndTheWaitOfTheEarlierAttempt() async {
        bench.store.setLastAttempt(.forecast, bench.now.addingTimeInterval(-5000))
        bench.store.setLastAttemptFailed(.forecast, true)
        bench.store.setRetryWait(.forecast, 1800)
        let address = serve("/forecast-ok", .stream([forecast]))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .updated = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(bench.store.lastAttempt(.forecast), bench.now)
        XCTAssertFalse(bench.store.lastAttemptFailed(.forecast))
        XCTAssertNil(bench.store.retryWait(.forecast))
    }

    func testTheRequestIsRecordedBeforeItIsMade() async {
        let observation = OnlineNetObservation()
        let store = bench.store
        store.setLastAttempt(.forecast, bench.now.addingTimeInterval(-5000))
        store.setLastAttemptFailed(.forecast, false)
        store.setRetryWait(.forecast, 1800)
        let address = serve("/forecast-watched", OnlineNetReply.stream([forecast]).calling { observation.record(store, .forecast) })
        _ = await refresh(.forecast, address, key: place)
        let seen = observation.snapshot
        XCTAssertEqual(seen.calls, 1)
        // While the request was under way the store already said "attempted now, failed, no wait recorded".
        XCTAssertEqual(seen.attempt, bench.now)
        XCTAssertTrue(seen.failed)
        XCTAssertNil(seen.wait)
    }

    func testTheStateAfterARefreshShowsTheStoreAndTheCache() async {
        let address = serve("/forecast-state", .stream([forecast]))
        _ = await refresh(.forecast, address, key: place)
        let state = await bench.refresher.state(.forecast)
        XCTAssertEqual(state.lastAttempt, bench.now)
        XCTAssertFalse(state.lastAttemptFailed)
        XCTAssertNil(state.retryWait)
        XCTAssertEqual(state.meta?.key, place)
    }

    func testTheRequestGoesToTheAddressWithTheUserAgentOfTheDownloader() async {
        let address = serve("/forecast-agent", .stream([forecast]))
        _ = await refresh(.forecast, address, key: place)
        XCTAssertEqual(server.requestedAddresses, [address])
        XCTAssertEqual(server.requests.first?.value(forHTTPHeaderField: "User-Agent"), "Lodestar/test")
        XCTAssertEqual(server.requests.first?.httpMethod, "GET")
    }

    // MARK: Conditional requests

    func testTheValidatorsOfTheCachedCopyAreSent() async throws {
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"abc\"", lastModified: "Sun, 18 Oct 2026 03:00:00 GMT", key: place)
        let address = serve("/forecast-conditional", .answer(304))
        _ = await refresh(.forecast, address, key: place)
        let request = server.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "If-Modified-Since"), "Sun, 18 Oct 2026 03:00:00 GMT")
    }

    func testNoValidatorsAreSentWithoutACachedCopy() async {
        let address = serve("/forecast-first", .stream([forecast]))
        _ = await refresh(.forecast, address, key: place)
        let request = server.requests.first
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-Modified-Since"))
    }

    func testTheValidatorsOfAnotherPlaceAreNotSent() async throws {
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"abc\"", lastModified: "Sun, 18 Oct 2026 03:00:00 GMT", key: "1.0,2.0")
        let address = serve("/forecast-elsewhere", .stream([forecast]))
        let outcome = await refresh(.forecast, address, key: place)
        let request = server.requests.first
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "If-Modified-Since"))
        // The download is for the new place, so it replaces the copy of the other one.
        guard case .updated(_, let meta) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(meta.key, place)
        XCTAssertEqual(bench.cache.readMeta(OnlineResource.forecast.key)?.key, place)
    }

    func testACopyWithoutAKeyIsOnlyTheCopyOfARequestWithoutOne() async throws {
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"abc\"", key: nil)
        let keyed = serve("/forecast-keyed", .answer(304))
        _ = await refresh(.forecast, keyed, key: place)
        XCTAssertNil(server.requests.last?.value(forHTTPHeaderField: "If-None-Match"))
        let unkeyed = serve("/forecast-unkeyed", .answer(304))
        _ = await refresh(.forecast, unkeyed, key: nil)
        XCTAssertEqual(server.requests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
    }

    func testTheValidatorsFromOneDownloadAreSentWithTheNextRequest() async {
        let first = serve("/forecast-round-1", .stream([forecast], headers: [
            "ETag": "\"r1\"", "Last-Modified": "Sun, 18 Oct 2026 03:00:00 GMT",
        ]))
        guard case .updated = await refresh(.forecast, first, key: place) else { return XCTFail("expected an update") }
        let second = serve("/forecast-round-2", .answer(304, headers: ["Expires": "Mon, 19 Oct 2026 06:00:00 GMT"]))
        let outcome = await refresh(.forecast, second, key: place)
        guard case .notModified(let meta) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "If-None-Match"), "\"r1\"")
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "If-Modified-Since"), "Sun, 18 Oct 2026 03:00:00 GMT")
        XCTAssertEqual(meta.etag, "\"r1\"")
        XCTAssertEqual(meta.expires, Date(timeIntervalSince1970: 1_792_389_600))
    }

    // MARK: Not modified

    func testNotModifiedRefreshesTheCopyAndKeepsItsBytesAndValidators() async throws {
        let old = try cacheCopy(.forecast, bytes: forecast, etag: "\"e1\"", lastModified: "Sun, 18 Oct 2026 03:00:00 GMT",
                                expires: Date(timeIntervalSince1970: 1_792_291_000), key: place)
        let address = serve("/forecast-304", .answer(304, headers: ["Expires": "Mon, 19 Oct 2026 06:00:00 GMT"]))
        bench.store.setRetryWait(.forecast, 1800)
        let before = Date()
        let outcome = await refresh(.forecast, address, key: place)
        let after = Date()
        guard case .notModified(let meta) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(meta.etag, old.etag)
        XCTAssertEqual(meta.lastModified, old.lastModified)
        XCTAssertEqual(meta.key, place)
        XCTAssertEqual(meta.dataEpoch, old.dataEpoch)
        XCTAssertEqual(meta.expires, Date(timeIntervalSince1970: 1_792_389_600))
        XCTAssertGreaterThanOrEqual(meta.savedAt, before)
        XCTAssertLessThanOrEqual(meta.savedAt, after)
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.expires, Date(timeIntervalSince1970: 1_792_389_600))
        XCTAssertEqual(entry.meta.etag, "\"e1\"")
        XCTAssertGreaterThan(entry.meta.savedAt, oldSaved)
        XCTAssertEqual(bench.store.lastAttempt(.forecast), bench.now)
        XCTAssertFalse(bench.store.lastAttemptFailed(.forecast))
        XCTAssertNil(bench.store.retryWait(.forecast))
    }

    func testNotModifiedWithoutAnExpiresKeepsTheOldOne() async throws {
        let oldExpires = Date(timeIntervalSince1970: 1_792_291_000)
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"e1\"", expires: oldExpires, key: place)
        let address = serve("/forecast-304-bare", .answer(304))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .notModified(let meta) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(meta.expires, oldExpires)
        XCTAssertEqual(bench.cache.readMeta(OnlineResource.forecast.key)?.expires, oldExpires)
    }

    func testNotModifiedForACopyOfAnotherPlaceIsAnEmptyAnswer() async throws {
        let old = try cacheCopy(.forecast, bytes: forecast, etag: "\"e1\"", key: "1.0,2.0")
        let address = serve("/forecast-304-elsewhere", .answer(304))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .empty)
        XCTAssertEqual(message, "The provider sent no data.")
        // The copy of the other place is left as it was.
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.key, old.key)
        XCTAssertEqual(entry.meta.savedAt, oldSaved)
        expectRecorded(.forecast, wait: nil)
    }

    func testNotModifiedWithNothingCachedIsAnEmptyAnswer() async {
        let address = serve("/forecast-304-nothing", .answer(304))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .empty)
        XCTAssertEqual(message, "The provider sent no data.")
        XCTAssertNil(bench.cache.read(OnlineResource.forecast.key))
        expectRecorded(.forecast, wait: nil)
    }

    func testNotModifiedForACopyWhoseBytesAreDamagedIsAnEmptyAnswer() async throws {
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"e1\"", key: place)
        // Cut the last byte off the file: the header still reads, the length no longer matches.
        let file = bench.directory.appendingPathComponent("\(OnlineResource.forecast.key).cache")
        let whole = try Data(contentsOf: file)
        try whole.dropLast().write(to: file)
        XCTAssertNotNil(bench.cache.readMeta(OnlineResource.forecast.key))
        XCTAssertNil(bench.cache.read(OnlineResource.forecast.key))
        let address = serve("/forecast-304-damaged", .answer(304))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .failed(let failure, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .empty)
        // The validators were still sent: the metadata was readable.
        XCTAssertEqual(server.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "\"e1\"")
        expectRecorded(.forecast, wait: nil)
    }

    func testNotModifiedThatCannotBeSavedIsAStorageFailure() async throws {
        try XCTSkipIf(geteuid() == 0, "the root user ignores the permissions of a directory")
        _ = try cacheCopy(.forecast, bytes: forecast, etag: "\"e1\"", key: place)
        // The copy can be read, but nothing can be written next to it.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bench.directory.path)
        let address = serve("/forecast-304-locked", .answer(304))
        let outcome = await refresh(.forecast, address, key: place)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bench.directory.path)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .storage)
        XCTAssertEqual(message, "The data could not be saved on this phone.")
        XCTAssertEqual(try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key)).meta.savedAt, oldSaved)
        expectRecorded(.forecast, wait: nil)
    }

    // MARK: Answers that cannot be used

    func testDataThatDoesNotParseNeverReplacesTheCache() async throws {
        let old = try cacheCopy(.forecast, bytes: forecast, etag: "\"keep\"", key: place)
        let address = serve("/forecast-garbage", .stream([Data("not json".utf8)], headers: ["ETag": "\"new\""]))
        let outcome = await refresh(.forecast, address, key: place)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .unreadable)
        XCTAssertEqual(message, "The downloaded data could not be read.")
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.etag, old.etag)
        XCTAssertEqual(entry.meta.key, place)
        XCTAssertEqual(entry.meta.savedAt, oldSaved)
        // The request counted: it is recorded as failed, and the resource's own retry interval applies.
        expectRecorded(.forecast, wait: nil)
    }

    func testDataThatDoesNotParseCreatesNoCache() async {
        let address = serve("/forecast-garbage-first", .stream([Data("not json".utf8)]))
        _ = await refresh(.forecast, address, key: place)
        XCTAssertNil(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertNil(bench.cache.readMeta(OnlineResource.forecast.key))
    }

    func testEveryResourceRefusesDataItCannotParse() async {
        let cases: [(OnlineResource, Data)] = [
            (.stations, Data("[]".utf8)),
            (.visual, Data("not json".utf8)),
            (.comets, Data("<html>Service unavailable</html>".utf8)),
            (.forecast, Data("not json".utf8)),
        ]
        for (resource, bytes) in cases {
            let address = serve("/unreadable-\(resource.rawValue)", .stream([bytes]))
            let outcome = await refresh(resource, address)
            guard case .failed(let failure, _) = outcome else { XCTFail("\(outcome) for \(resource)"); continue }
            XCTAssertEqual(failure, .unreadable, "\(resource)")
            XCTAssertNil(bench.cache.read(resource.key), "\(resource)")
            expectRecorded(resource, wait: nil, "\(resource)")
        }
    }

    func testDownloadedDataThatCannotBeSavedIsAStorageFailure() async throws {
        // The cache directory would have to be made inside a plain file.
        try Data([0]).write(to: bench.directory)
        let blocked = OnlineCache(directory: bench.directory.appendingPathComponent("inside", isDirectory: true))
        let refresher = OnlineRefresher(cache: blocked, downloader: bench.downloader, store: bench.store)
        let address = serve("/forecast-unsaveable", .stream([forecast]))
        let outcome = await refresh(.forecast, address, key: place, using: refresher)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .storage)
        XCTAssertEqual(message, "The data could not be saved on this phone.")
        XCTAssertNil(blocked.read(OnlineResource.forecast.key))
        expectRecorded(.forecast, wait: nil)
    }

    func testTheSizeLimitOfTheResourceIsTheOneThatIsEnforced() async throws {
        // The stations' limit is 512 KiB: an announced length one byte over is refused, one at the limit gets as far as the parser.
        let over = serve("/stations-over", .stream([Data("tiny".utf8)], headers: ["Content-Length": "524289"]))
        let refused = await refresh(.stations, over)
        guard case .failed(let tooLarge, let message) = refused else { return XCTFail("\(refused)") }
        XCTAssertEqual(tooLarge, .tooLarge)
        XCTAssertEqual(message, "The download was larger than expected.")
        expectRecorded(.stations, wait: 7200)
        let exact = serve("/stations-exact", .stream([Data(repeating: 0x78, count: 524_288)], headers: ["Content-Length": "524288"]))
        let parsed = await refresh(.stations, exact)
        guard case .failed(let unreadable, _) = parsed else { return XCTFail("\(parsed)") }
        XCTAssertEqual(unreadable, .unreadable)
        XCTAssertNil(bench.cache.read(OnlineResource.stations.key))
    }

    // MARK: Failures that waited for an answer

    func testAForbiddenAnswerWaitsAtLeastAnHour() async {
        let cases: [(OnlineResource, TimeInterval)] = [(.forecast, 3600), (.stations, 7200), (.comets, 3600)]
        for (resource, wait) in cases {
            let address = serve("/forbidden-\(resource.rawValue)", .answer(403))
            let outcome = await refresh(resource, address)
            guard case .failed(let failure, let message) = outcome else { XCTFail("\(outcome)"); continue }
            XCTAssertEqual(failure, .forbidden, "\(resource)")
            XCTAssertEqual(message, "The provider declined the request (HTTP 403).")
            expectRecorded(resource, wait: wait, "\(resource)")
        }
    }

    func testARateLimitedAnswerWaitsAtLeastAnHour() async {
        let address = serve("/limited", .answer(429))
        let outcome = await refresh(.forecast, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .rateLimited)
        XCTAssertEqual(message, "The provider asked for fewer requests (HTTP 429).")
        expectRecorded(.forecast, wait: 3600)
    }

    func testRetryAfterLongerThanTheMinimumIsWaitedOut() async {
        let address = serve("/limited-long", .answer(429, headers: ["Retry-After": "7200"]))
        _ = await refresh(.forecast, address)
        expectRecorded(.forecast, wait: 7200)
    }

    func testRetryAfterShorterThanTheMinimumDoesNotShortenIt() async {
        let address = serve("/limited-short", .answer(429, headers: ["Retry-After": "60"]))
        _ = await refresh(.forecast, address)
        expectRecorded(.forecast, wait: 3600)
    }

    func testRetryAfterIsCappedAtADay() async {
        let forbidden = serve("/forbidden-huge", .answer(403, headers: ["Retry-After": "1000000"]))
        _ = await refresh(.forecast, forbidden)
        expectRecorded(.forecast, wait: 86_400)
        let unavailable = serve("/unavailable-huge", .answer(503, headers: ["Retry-After": "1000000"]))
        _ = await refresh(.stations, unavailable)
        expectRecorded(.stations, wait: 86_400)
    }

    func testRetryAfterAsAnHTTPDateIsWaitedOutFromNow() async throws {
        let address = serve("/limited-date", .answer(429, headers: ["Retry-After": onlineNetHTTPDate(Date().addingTimeInterval(5400))]))
        _ = await refresh(.forecast, address)
        let wait = try XCTUnwrap(bench.store.retryWait(.forecast))
        // An hour and a half, give or take the seconds that have passed and the whole seconds of the date.
        XCTAssertEqual(wait, 5400, accuracy: 120)
        XCTAssertTrue(bench.store.lastAttemptFailed(.forecast))
    }

    func testAServerErrorWaitsTheRetryIntervalOfTheResource() async {
        let cases: [(OnlineResource, TimeInterval)] = [(.forecast, 600), (.stations, 7200), (.visual, 7200), (.starlink, 7200), (.comets, 3600)]
        for (resource, wait) in cases {
            let address = serve("/error-\(resource.rawValue)", .answer(500))
            let outcome = await refresh(resource, address)
            guard case .failed(let failure, let message) = outcome else { XCTFail("\(outcome)"); continue }
            XCTAssertEqual(failure, .httpError, "\(resource)")
            XCTAssertEqual(message, "The provider answered with an error (HTTP 500).")
            expectRecorded(resource, wait: wait, "\(resource)")
        }
    }

    func testTheStatusOfAnHTTPErrorIsInItsMessage() async {
        let address = serve("/missing", .answer(404))
        let outcome = await refresh(.comets, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .httpError)
        XCTAssertEqual(message, "The provider answered with an error (HTTP 404).")
        expectRecorded(.comets, wait: 3600)
    }

    func testRetryAfterOfAServerErrorLongerThanTheIntervalIsWaitedOut() async {
        let address = serve("/unavailable", .answer(503, headers: ["Retry-After": "1800"]))
        _ = await refresh(.forecast, address)
        expectRecorded(.forecast, wait: 1800)
    }

    func testRetryAfterOfAServerErrorShorterThanTheIntervalChangesNothing() async {
        let address = serve("/unavailable-short", .answer(503, headers: ["Retry-After": "30"]))
        _ = await refresh(.forecast, address)
        expectRecorded(.forecast, wait: 600)
    }

    func testAnEmptyAnswerWaitsTheRetryIntervalOfTheResource() async {
        let address = serve("/nothing", .answer())
        let outcome = await refresh(.comets, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .empty)
        XCTAssertEqual(message, "The provider sent no data.")
        expectRecorded(.comets, wait: 3600)
    }

    func testAnAnswerThatBreaksOffWaitsTheRetryIntervalOfTheResource() async {
        let address = serve("/broken", .stream([Data("[{".utf8)], endingWith: URLError(.networkConnectionLost)))
        let outcome = await refresh(.stations, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .interrupted)
        XCTAssertEqual(message, "The connection broke while the data was arriving.")
        expectRecorded(.stations, wait: 7200)
    }

    func testTooManyRedirectsWaitTheRetryIntervalOfTheResource() async {
        // Seven redirects in a row: the fifth is refused.
        let addresses = (0...7).map { host + "/hop-\($0)" }
        for index in 0..<7 { server.serve(addresses[index], .redirect(to: addresses[index + 1])) }
        server.serve(addresses[7], .answer(text: "end"))
        let outcome = await refresh(.forecast, addresses[0])
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .httpError)
        XCTAssertEqual(message, "The provider answered with an error (HTTP 302).")
        expectRecorded(.forecast, wait: 600)
    }

    func testAFailureOverwritesTheEarlierAttemptAndItsWait() async {
        bench.store.setLastAttempt(.forecast, bench.now.addingTimeInterval(-5000))
        bench.store.setLastAttemptFailed(.forecast, false)
        bench.store.setRetryWait(.forecast, 99)
        let address = serve("/error-again", .answer(500))
        _ = await refresh(.forecast, address)
        expectRecorded(.forecast, wait: 600)
    }

    func testAFailureLeavesTheCachedCopyAsItWas() async throws {
        let old = try cacheCopy(.forecast, bytes: forecast, etag: "\"keep\"", expires: Date(timeIntervalSince1970: 1_792_291_000), key: place)
        let address = serve("/error-cached", .answer(500, text: "<html>oops</html>"))
        _ = await refresh(.forecast, address, key: place)
        let entry = try XCTUnwrap(bench.cache.read(OnlineResource.forecast.key))
        XCTAssertEqual(entry.bytes, forecast)
        XCTAssertEqual(entry.meta.etag, old.etag)
        XCTAssertEqual(entry.meta.expires, old.expires)
        XCTAssertEqual(entry.meta.savedAt, oldSaved)
    }

    func testAFailureOfOneResourceDoesNotTouchTheStoreOfAnother() async {
        bench.store.setLastAttempt(.stations, bench.now.addingTimeInterval(-100))
        let address = serve("/error-other", .answer(500))
        _ = await refresh(.visual, address)
        XCTAssertEqual(bench.store.lastAttempt(.stations), bench.now.addingTimeInterval(-100))
        XCTAssertFalse(bench.store.lastAttemptFailed(.stations))
        XCTAssertNil(bench.store.retryWait(.stations))
    }

    func testTheStateAfterAFailureShowsTheWait() async {
        let address = serve("/forbidden-state", .answer(403))
        _ = await refresh(.forecast, address, key: place)
        let state = await bench.refresher.state(.forecast)
        XCTAssertEqual(state.lastAttempt, bench.now)
        XCTAssertTrue(state.lastAttemptFailed)
        XCTAssertEqual(state.retryWait, 3600)
        XCTAssertNil(state.meta)
    }

    // MARK: Failures without an answer

    func testATimeoutWaitsAtMostTenMinutes() async {
        let cases: [(OnlineResource, TimeInterval)] = [(.forecast, 600), (.stations, 600), (.comets, 600)]
        for (resource, wait) in cases {
            let address = serve("/timeout-\(resource.rawValue)", .fail(URLError(.timedOut)))
            let outcome = await refresh(resource, address)
            guard case .failed(let failure, let message) = outcome else { XCTFail("\(outcome)"); continue }
            XCTAssertEqual(failure, .timeout, "\(resource)")
            XCTAssertEqual(message, "The provider did not answer in time.")
            expectRecorded(resource, wait: wait, "\(resource)")
        }
    }

    func testNoRouteWaitsAtMostTenMinutes() async {
        let address = serve("/no-route", .fail(URLError(.cannotConnectToHost)))
        let outcome = await refresh(.stations, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .network)
        XCTAssertEqual(message, "No connection to the provider.")
        expectRecorded(.stations, wait: 600)
    }

    func testNoRouteWaitsTenMinutesEvenWhereTheResourcesOwnIntervalIsAnHour() async {
        let address = serve("/no-route-comets", .fail(URLError(.dnsLookupFailed)))
        _ = await refresh(.comets, address)
        expectRecorded(.comets, wait: 600)
    }

    func testBeingOfflineRestoresTheEarlierAttempt() async {
        let earlier = bench.now.addingTimeInterval(-5000)
        bench.store.setLastAttempt(.stations, earlier)
        bench.store.setLastAttemptFailed(.stations, true)
        bench.store.setRetryWait(.stations, 1800)
        let address = serve("/offline", .fail(URLError(.notConnectedToInternet)))
        let outcome = await refresh(.stations, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .offline)
        XCTAssertEqual(message, "No network connection.")
        // Nothing reached the provider: the store is as it was.
        XCTAssertEqual(bench.store.lastAttempt(.stations), earlier)
        XCTAssertTrue(bench.store.lastAttemptFailed(.stations))
        XCTAssertEqual(bench.store.retryWait(.stations), 1800)
    }

    func testBeingOfflineWithoutAnEarlierAttemptLeavesTheStoreEmpty() async {
        let address = serve("/offline-first", .fail(URLError(.dataNotAllowed)))
        _ = await refresh(.forecast, address, key: place)
        XCTAssertNil(bench.store.lastAttempt(.forecast))
        XCTAssertFalse(bench.store.lastAttemptFailed(.forecast))
        XCTAssertNil(bench.store.retryWait(.forecast))
    }

    func testTheAppTransportSecurityRefusalRestoresTheEarlierAttempt() async {
        let earlier = bench.now.addingTimeInterval(-3000)
        bench.store.setLastAttempt(.comets, earlier)
        bench.store.setLastAttemptFailed(.comets, false)
        let address = serve("/ats", .fail(URLError(.appTransportSecurityRequiresSecureConnection)))
        let outcome = await refresh(.comets, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertEqual(message, "The address is not secure.")
        XCTAssertEqual(bench.store.lastAttempt(.comets), earlier)
        XCTAssertFalse(bench.store.lastAttemptFailed(.comets))
        XCTAssertNil(bench.store.retryWait(.comets))
    }

    func testWaitingForAnUnmeteredNetworkRestoresTheEarlierAttempt() async {
        let earlier = bench.now.addingTimeInterval(-4000)
        bench.store.setLastAttempt(.starlink, earlier)
        bench.store.setLastAttemptFailed(.starlink, true)
        bench.store.setRetryWait(.starlink, 900)
        let reason = URLError.NetworkUnavailableReason.constrained.rawValue
        let info: [String: Any] = ["NSURLErrorNetworkUnavailableReasonKey": reason, "_NSURLErrorNetworkUnavailableReasonKey": reason]
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: info)
        let address = serve("/constrained", .fail(error))
        let outcome = await refresh(.starlink, address)
        guard case .failed(let failure, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .waitingForUnmetered)
        XCTAssertEqual(message, "Waiting for an unmetered network such as Wi-Fi: this download is too large for mobile data.")
        XCTAssertEqual(bench.store.lastAttempt(.starlink), earlier)
        XCTAssertTrue(bench.store.lastAttemptFailed(.starlink))
        XCTAssertEqual(bench.store.retryWait(.starlink), 900)
    }

    func testAnInsecureFirstAddressRestoresTheEarlierAttemptToo() async {
        let earlier = bench.now.addingTimeInterval(-3000)
        bench.store.setLastAttempt(.forecast, earlier)
        let outcome = await refresh(.forecast, "http://example.test/plain", key: place)
        guard case .failed(let failure, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertEqual(bench.store.lastAttempt(.forecast), earlier)
        XCTAssertTrue(server.requests.isEmpty)
    }
}

import Foundation
import XCTest
@testable import AppCore

/// The parts of the downloader that need no network: the failure texts, `sentNothing`, the request value and the
/// refusal of an address that is not HTTPS (which returns before any session is made). The `URLSession` is created
/// inside `fetch`, so status codes, redirects, the size limit and 304 cannot be reached without a network.
final class OnlineDownloaderTests: XCTestCase {
    private let everyFailure: [OnlineFailure] = [
        .insecure, .forbidden, .rateLimited, .httpError, .tooLarge, .timeout, .network, .interrupted, .offline,
        .waitingForUnmetered, .empty, .unreadable, .storage,
    ]

    // MARK: Messages

    func testEveryFailureHasItsSentence() {
        XCTAssertEqual(OnlineFailure.insecure.message(), "The address is not secure.")
        XCTAssertEqual(OnlineFailure.forbidden.message(), "The provider declined the request (HTTP 403).")
        XCTAssertEqual(OnlineFailure.rateLimited.message(), "The provider asked for fewer requests (HTTP 429).")
        XCTAssertEqual(OnlineFailure.httpError.message(), "The provider answered with an error.")
        XCTAssertEqual(OnlineFailure.tooLarge.message(), "The download was larger than expected.")
        XCTAssertEqual(OnlineFailure.timeout.message(), "The provider did not answer in time.")
        XCTAssertEqual(OnlineFailure.network.message(), "No connection to the provider.")
        XCTAssertEqual(OnlineFailure.interrupted.message(), "The connection broke while the data was arriving.")
        XCTAssertEqual(OnlineFailure.offline.message(), "No network connection.")
        XCTAssertEqual(OnlineFailure.waitingForUnmetered.message(),
                       "Waiting for an unmetered network such as Wi-Fi: this download is too large for mobile data.")
        XCTAssertEqual(OnlineFailure.empty.message(), "The provider sent no data.")
        XCTAssertEqual(OnlineFailure.unreadable.message(), "The downloaded data could not be read.")
        XCTAssertEqual(OnlineFailure.storage.message(), "The data could not be saved on this phone.")
    }

    func testTheStatusCodeAppearsOnlyInTheGenericHTTPError() {
        XCTAssertEqual(OnlineFailure.httpError.message(statusCode: 503), "The provider answered with an error (HTTP 503).")
        XCTAssertEqual(OnlineFailure.httpError.message(statusCode: 404), "The provider answered with an error (HTTP 404).")
        for failure in everyFailure where failure != .httpError {
            XCTAssertEqual(failure.message(statusCode: 500), failure.message(), "\(failure)")
        }
    }

    func testEveryMessageIsADistinctNonEmptySentence() {
        let messages = everyFailure.map { $0.message() }
        XCTAssertEqual(Set(messages).count, everyFailure.count)
        for message in messages {
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.hasSuffix("."), message)
        }
    }

    // MARK: Sent nothing

    func testOnlyOfflineUnmeteredAndInsecureCountAsNothingSent() {
        let sentNothing: [OnlineFailure] = [.offline, .waitingForUnmetered, .insecure]
        for failure in everyFailure {
            XCTAssertEqual(failure.sentNothing, sentNothing.contains(failure), "\(failure)")
        }
        XCTAssertTrue(OnlineFailure.offline.sentNothing)
        XCTAssertTrue(OnlineFailure.waitingForUnmetered.sentNothing)
        XCTAssertTrue(OnlineFailure.insecure.sentNothing)
        XCTAssertFalse(OnlineFailure.forbidden.sentNothing)
        XCTAssertFalse(OnlineFailure.rateLimited.sentNothing)
        XCTAssertFalse(OnlineFailure.timeout.sentNothing)
        XCTAssertFalse(OnlineFailure.network.sentNothing)
        XCTAssertFalse(OnlineFailure.interrupted.sentNothing)
    }

    // MARK: Request and downloader values

    func testARequestDefaultsToNoValidatorsAndAnyNetwork() throws {
        let url = try XCTUnwrap(URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=json"))
        let request = OnlineRequest(url: url, maximumBytes: 1000)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.maximumBytes, 1000)
        XCTAssertNil(request.etag)
        XCTAssertNil(request.lastModified)
        XCTAssertTrue(request.allowsExpensiveNetwork)
    }

    func testTheDownloaderKeepsItsUserAgentAndHasTheDocumentedTimeouts() {
        let downloader = OnlineDownloader(userAgent: "Lodestar/9.9 (test)")
        XCTAssertEqual(downloader.userAgent, "Lodestar/9.9 (test)")
        XCTAssertEqual(downloader.idleTimeout, 30)
        XCTAssertEqual(downloader.totalTimeout, 120)
    }

    func testTheDefaultUserAgentIsTheOneOfThisBuild() {
        XCTAssertEqual(OnlineDownloader().userAgent, OnlineUserAgent.current)
    }

    // MARK: Addresses that are not HTTPS

    private func fetchResult(_ address: String) async throws -> OnlineResult {
        let url = try XCTUnwrap(URL(string: address), address)
        return await OnlineDownloader(userAgent: "Lodestar/test").fetch(OnlineRequest(url: url, maximumBytes: 1000))
    }

    func testAnHTTPAddressIsRefusedBeforeAnythingIsSent() async throws {
        let result = try await fetchResult("http://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=json")
        guard case .failed(let failure, let status, let retryAfter) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure, .insecure)
        XCTAssertNil(status)
        XCTAssertNil(retryAfter)
    }

    func testTheSchemeIsComparedWithoutRegardToCase() async throws {
        let result = try await fetchResult("HTTP://celestrak.org/")
        guard case .failed(let failure, _, _) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure, .insecure)
    }

    func testOtherSchemesAreRefused() async throws {
        for address in ["ftp://celestrak.org/file", "file:///etc/hosts", "data:text/plain,hello", "celestrak.org/no-scheme"] {
            let result = try await fetchResult(address)
            guard case .failed(let failure, let status, _) = result else { return XCTFail("expected a failure for \(address)") }
            XCTAssertEqual(failure, .insecure, address)
            XCTAssertNil(status, address)
        }
    }
}

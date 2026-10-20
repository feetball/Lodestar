import Foundation

/// One request: the address (HTTPS only), the size limit and the validators of the copy we already have.
struct OnlineRequest: Sendable {
    let url: URL
    let maximumBytes: Int
    var etag: String?
    var lastModified: String?
    /// Whether the request may use an expensive network (cellular, a personal hotspot) or Low Data Mode.
    var allowsExpensiveNetwork = true
}

/// Why a download did not deliver data.
enum OnlineFailure: Sendable, Equatable {
    /// The address (or a redirect) is not HTTPS.
    case insecure
    /// HTTP 403: CelesTrak answers a repeated request for unchanged data this way.
    case forbidden
    /// HTTP 429.
    case rateLimited
    /// Any other HTTP error status.
    case httpError
    /// More bytes than the feed's limit.
    case tooLarge
    /// The connection or the server did not answer in time.
    case timeout
    /// No route, DNS failure, reset connection.
    case network
    /// The provider answered, then the connection broke or stalled while the data was arriving.
    case interrupted
    /// The phone is offline; nothing was sent.
    case offline
    /// The feed needs a network that is not expensive or constrained; nothing was sent.
    case waitingForUnmetered
    /// The answer had no content.
    case empty
    /// The bytes could not be read as the expected data.
    case unreadable
    /// The phone could not store the data.
    case storage

    /// The sentence for the error line.
    func message(statusCode: Int? = nil) -> String {
        switch self {
        case .insecure: return "The address is not secure."
        case .forbidden: return "The provider declined the request (HTTP 403)."
        case .rateLimited: return "The provider asked for fewer requests (HTTP 429)."
        case .httpError:
            if let statusCode { return "The provider answered with an error (HTTP \(statusCode))." }
            return "The provider answered with an error."
        case .tooLarge: return "The download was larger than expected."
        case .timeout: return "The provider did not answer in time."
        case .network: return "No connection to the provider."
        case .interrupted: return "The connection broke while the data was arriving."
        case .offline: return "No network connection."
        case .waitingForUnmetered:
            return "Waiting for an unmetered network such as Wi-Fi: this download is too large for mobile data."
        case .empty: return "The provider sent no data."
        case .unreadable: return "The downloaded data could not be read."
        case .storage: return "The data could not be saved on this phone."
        }
    }

    /// Whether the request never reached the provider, so it does not count against the request interval.
    var sentNothing: Bool { self == .offline || self == .waitingForUnmetered || self == .insecure }
}

/// The outcome of `OnlineDownloader.fetch`.
enum OnlineResult: Sendable {
    /// A complete answer. The validators are the server's, for the next conditional request.
    case downloaded(bytes: Data, etag: String?, lastModified: String?, expires: Date?)
    /// HTTP 304: the copy we have is current.
    case notModified(expires: Date?)
    /// Nothing arrived. `statusCode` is the HTTP status when there was one; `retryAfter` is the seconds the server asked
    /// us to wait (`Retry-After`), when it did.
    case failed(OnlineFailure, statusCode: Int?, retryAfter: TimeInterval? = nil)
}

/// Downloads one file over HTTPS with `URLSession`: time-outs, a size limit, conditional requests (`ETag`,
/// `Last-Modified`) and a descriptive User-Agent. It follows at most four redirects, each to another HTTPS address, sends
/// no cookies and keeps nothing in the URL cache. Each request has a session of its own, so nothing is shared between
/// feeds.
struct OnlineDownloader: Sendable {
    let userAgent: String
    /// Seconds without any data before the request fails.
    var idleTimeout: TimeInterval = 30
    /// Seconds for the whole request.
    var totalTimeout: TimeInterval = 120
    /// `URLProtocol` classes that answer the request instead of the network (tests only; `nil` in the app).
    var protocolClasses: [AnyClass]?

    init(userAgent: String = OnlineUserAgent.current) {
        self.userAgent = userAgent
    }

    func fetch(_ request: OnlineRequest) async -> OnlineResult {
        guard request.url.scheme?.lowercased() == "https" else { return .failed(.insecure, statusCode: nil) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = totalTimeout
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = request.allowsExpensiveNetwork
        configuration.allowsConstrainedNetworkAccess = request.allowsExpensiveNetwork
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        if let protocolClasses { configuration.protocolClasses = protocolClasses }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = idleTimeout
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag = request.etag { urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = request.lastModified { urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let delegate = OnlineDownloadDelegate(maximumBytes: request.maximumBytes)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)
        let result: OnlineResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        session.finishTasksAndInvalidate()
        return result
    }
}

/// Collects one response, enforcing the size limit and the HTTPS-only redirect rule as the bytes arrive.
private final class OnlineDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let maximumRedirects = 4

    private let lock = NSLock()
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<OnlineResult, Never>?
    private var body = Data()
    private var response: HTTPURLResponse?
    /// Set when this delegate cancelled the task itself; it explains the cancellation error.
    private var abort: OnlineFailure?
    private var abortStatus: Int?
    private var abortRetryAfter: TimeInterval?
    private var redirects = 0
    /// The result of a task that finished (was cancelled) before `start` was called.
    private var earlyResult: OnlineResult?

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func start(_ continuation: CheckedContinuation<OnlineResult, Never>) {
        lock.lock()
        let early = earlyResult
        earlyResult = nil
        if early == nil { self.continuation = continuation }
        lock.unlock()
        if let early { continuation.resume(returning: early) }
    }

    private func setAbort(_ failure: OnlineFailure, status: Int? = nil, retryAfter: TimeInterval? = nil) {
        lock.lock()
        if abort == nil {
            abort = failure
            abortStatus = status
            abortRetryAfter = retryAfter
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        redirects += 1
        let count = redirects
        lock.unlock()
        guard request.url?.scheme?.lowercased() == "https" else {
            setAbort(.insecure)
            completionHandler(nil)
            task.cancel()
            return
        }
        guard count <= Self.maximumRedirects else {
            setAbort(.httpError, status: response.statusCode)
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            setAbort(.httpError)
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = http
        lock.unlock()
        switch http.statusCode {
        case 304:
            completionHandler(.allow)
        case 403:
            setAbort(.forbidden, status: 403, retryAfter: Self.retryAfter(http))
            completionHandler(.cancel)
        case 429:
            setAbort(.rateLimited, status: 429, retryAfter: Self.retryAfter(http))
            completionHandler(.cancel)
        case 200...299:
            if http.expectedContentLength > Int64(maximumBytes) {
                setAbort(.tooLarge)
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        default:
            setAbort(.httpError, status: http.statusCode, retryAfter: Self.retryAfter(http))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let tooMuch = body.count + data.count > maximumBytes
        if !tooMuch { body.append(data) }
        lock.unlock()
        if tooMuch {
            setAbort(.tooLarge)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let response = self.response
        let abort = self.abort
        let abortStatus = self.abortStatus
        let abortRetryAfter = self.abortRetryAfter
        let body = self.body
        let result = Self.result(response: response, body: body, error: error, abort: abort, abortStatus: abortStatus,
                                 abortRetryAfter: abortRetryAfter)
        if continuation == nil { earlyResult = result }
        lock.unlock()
        continuation?.resume(returning: result)
    }

    private static func result(response: HTTPURLResponse?, body: Data, error: Error?, abort: OnlineFailure?,
                               abortStatus: Int?, abortRetryAfter: TimeInterval?) -> OnlineResult {
        if let response, response.statusCode == 304 {
            return .notModified(expires: date(response, "Expires"))
        }
        if let abort { return .failed(abort, statusCode: abortStatus, retryAfter: abortRetryAfter) }
        if let error {
            let kind = failure(for: error)
            // Once the provider has answered, a broken connection is not "no connection": it may have counted the request.
            if response != nil && (kind == .network || kind == .timeout) { return .failed(.interrupted, statusCode: nil) }
            return .failed(kind, statusCode: nil)
        }
        guard let response, (200...299).contains(response.statusCode) else { return .failed(.httpError, statusCode: response?.statusCode) }
        guard !body.isEmpty else { return .failed(.empty, statusCode: nil) }
        return .downloaded(bytes: body, etag: response.value(forHTTPHeaderField: "ETag"),
                           lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                           expires: date(response, "Expires"))
    }

    private static func failure(for error: Error) -> OnlineFailure {
        guard let error = error as? URLError else { return .network }
        if error.networkUnavailableReason == .expensive || error.networkUnavailableReason == .constrained {
            return .waitingForUnmetered
        }
        switch error.code {
        case .timedOut: return .timeout
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive: return .offline
        case .appTransportSecurityRequiresSecureConnection: return .insecure
        default: return .network
        }
    }

    /// An HTTP date header ("Sun, 18 Oct 2026 19:50:18 GMT"), or `nil`; `Expires: 0` and other invalid values count as none.
    private static func date(_ response: HTTPURLResponse, _ name: String) -> Date? {
        guard let text = response.value(forHTTPHeaderField: name) else { return nil }
        return httpDate(text)
    }

    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    /// The `Retry-After` header as seconds from now: it holds a number of seconds or an HTTP date. `nil` when it is
    /// missing, invalid or not in the future.
    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let text = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        let seconds = TimeInterval(text) ?? httpDate(text)?.timeIntervalSinceNow
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}

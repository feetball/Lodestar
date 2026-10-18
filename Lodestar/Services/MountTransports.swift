import Foundation
import Network
import LodestarKit

// The links to a mount, as the engine wants them: blocking calls with a timeout, used from the mount worker thread.
//
// Local network: iOS asks for permission the first time Lodestar talks to a device on the local network
// (`NSLocalNetworkUsageDescription` in Config/Info.plist). Until the person answers, a connection waits; if they
// refuse, connections fail and the connection screen points them to iOS Settings. The mount is reached by its IP
// address, so no Bonjour service has to be declared (`NSBonjourServices` is only needed to browse Bonjour).

/// What the mount's driver talks through: a byte stream, an HTTP client, or nothing for the simulated mount.
enum MountChannel: Sendable {
    case stream(MountSocketTransport)
    case http(MountHTTPTransport)
    /// The demonstration mount, which lives in memory.
    case simulated

    /// Opens the connection (a TCP handshake); instant for the other kinds.
    func open(timeoutSeconds: Double) throws {
        switch self {
        case .stream(let transport): try transport.open(timeoutSeconds: timeoutSeconds)
        case .http, .simulated: break
        }
    }

    /// Ends whatever exchange is waiting right now, so a Stop or a Cancel does not sit out a timeout.
    func interrupt() {
        switch self {
        case .stream(let transport): transport.interrupt()
        case .http(let transport): transport.interrupt()
        case .simulated: break
        }
    }

    func close() {
        switch self {
        case .stream(let transport): transport.close()
        case .http(let transport): transport.close()
        case .simulated: break
        }
    }
}

// MARK: - TCP and UDP

/// A TCP connection, or a UDP socket connected to the mount, behind the engine's blocking `MountTransport`.
///
/// Network.framework delivers input through callbacks on its own queue. A receive loop that re-arms itself appends what
/// arrives to a buffer; `receive` waits on a condition for the buffer to fill, so it returns as soon as any bytes are
/// there and gives up at its deadline. `discardPendingInput` empties the buffer. All of it is safe from any thread.
final class MountSocketTransport: MountTransport, @unchecked Sendable {
    enum Kind: String, Codable, Sendable {
        case tcp, udp
    }

    private enum LinkState: Equatable {
        case preparing
        case ready
        case failed(String)
        case closed
    }

    /// The most unread input kept; older bytes are dropped.
    private static let maximumBuffered = 65_536
    private static let sendTimeoutSeconds = 3.0

    let kind: Kind
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "net.kuecker.lodestar.mount.socket")
    private let condition = NSCondition()
    private var linkState = LinkState.preparing
    private var buffer: [UInt8] = []
    private var interruptions = 0
    private var waitingDetail: String?
    private var hasStarted = false

    /// - Returns: `nil` if the port is not 1 to 65535 or the host is empty.
    init?(host: String, port: Int, kind: Kind) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, (1...65_535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return nil
        }
        let parameters: NWParameters
        switch kind {
        case .tcp:
            let options = NWProtocolTCP.Options()
            options.noDelay = true
            options.enableKeepalive = true
            parameters = NWParameters(tls: nil, tcp: options)
        case .udp:
            parameters = NWParameters.udp
        }
        // A mount is on the local network; never try the mobile network for it.
        parameters.prohibitedInterfaceTypes = [.cellular]
        self.kind = kind
        connection = NWConnection(host: NWEndpoint.Host(trimmed), port: nwPort, using: parameters)
    }

    deinit {
        connection.cancel()
    }

    // MARK: Opening and closing

    /// Starts the connection and waits until it is ready.
    ///
    /// - Throws: `MountError.timeout` if it is not ready in time (also while iOS waits for an answer to the local network
    ///   question), `MountError.transport` if it fails or is cancelled.
    func open(timeoutSeconds: Double) throws {
        condition.lock()
        let isFirstOpen = !hasStarted
        hasStarted = true
        let startInterruptions = interruptions
        condition.unlock()

        if isFirstOpen {
            connection.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            connection.start(queue: queue)
        }

        let deadline = Date(timeIntervalSinceNow: max(timeoutSeconds, 0.1))
        condition.lock()
        defer { condition.unlock() }
        while true {
            switch linkState {
            case .ready:
                return
            case .failed(let detail):
                throw MountError.transport(detail: detail)
            case .closed:
                throw MountError.transport(detail: "the connection was closed")
            case .preparing:
                break
            }
            if interruptions != startInterruptions {
                throw MountError.transport(detail: "connecting was cancelled")
            }
            if !condition.wait(until: deadline) {
                let detail = waitingDetail.map { "connecting: \($0)" } ?? "connecting"
                throw MountError.timeout(operation: detail)
            }
        }
    }

    /// Wakes up whatever is waiting in `open` or `receive` right now. Later calls are not affected.
    func interrupt() {
        condition.lock()
        interruptions += 1
        condition.broadcast()
        condition.unlock()
    }

    func close() {
        condition.lock()
        linkState = .closed
        buffer.removeAll()
        condition.broadcast()
        condition.unlock()
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    // MARK: MountTransport

    func send(_ bytes: [UInt8]) throws {
        condition.lock()
        let state = linkState
        condition.unlock()
        try requireReady(state)
        let outcome = MountSendOutcome()
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            outcome.finish(error)
        })
        guard outcome.wait(timeoutSeconds: Self.sendTimeoutSeconds) else {
            throw MountError.timeout(operation: "sending a command")
        }
        if let error = outcome.error {
            throw MountError.transport(detail: Self.describe(error))
        }
    }

    func receive(maxCount: Int, timeoutSeconds: Double) throws -> [UInt8] {
        let deadline = Date(timeIntervalSinceNow: max(timeoutSeconds, 0))
        condition.lock()
        defer { condition.unlock() }
        let startInterruptions = interruptions
        while buffer.isEmpty {
            try requireReady(linkState)
            if interruptions != startInterruptions {
                throw MountError.timeout(operation: "stopped waiting")
            }
            if !condition.wait(until: deadline) {
                throw MountError.timeout(operation: "waiting for a reply")
            }
        }
        let count = min(max(maxCount, 1), buffer.count)
        let bytes = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return bytes
    }

    func discardPendingInput() throws {
        condition.lock()
        buffer.removeAll()
        condition.unlock()
    }

    // MARK: Network.framework callbacks

    private func requireReady(_ state: LinkState) throws {
        switch state {
        case .ready, .preparing:
            return
        case .failed(let detail):
            throw MountError.transport(detail: detail)
        case .closed:
            throw MountError.transport(detail: "the connection was closed")
        }
    }

    private func handle(_ state: NWConnection.State) {
        var becameReady = false
        condition.lock()
        switch state {
        case .ready:
            if linkState == .preparing {
                linkState = .ready
                becameReady = true
            }
        case .waiting(let error):
            waitingDetail = Self.describe(error)
        case .failed(let error):
            if linkState != .closed { linkState = .failed(Self.describe(error)) }
        case .cancelled:
            linkState = .closed
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
        condition.broadcast()
        condition.unlock()
        if becameReady { armReceive() }
    }

    /// Asks for the next input; the completion stores it and asks again.
    private func armReceive() {
        switch kind {
        case .tcp:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
                self?.received(data, isStreamEnd: isComplete, error: error)
            }
        case .udp:
            connection.receiveMessage { [weak self] data, _, _, error in
                self?.received(data, isStreamEnd: false, error: error)
            }
        }
    }

    private func received(_ data: Data?, isStreamEnd: Bool, error: NWError?) {
        var rearm = false
        condition.lock()
        if let data, !data.isEmpty {
            buffer.append(contentsOf: data)
            if buffer.count > Self.maximumBuffered {
                buffer.removeFirst(buffer.count - Self.maximumBuffered)
            }
        }
        if linkState == .ready {
            if let error {
                linkState = .failed(Self.describe(error))
            } else if isStreamEnd {
                linkState = .failed("the mount closed the connection")
            } else {
                rearm = true
            }
        }
        condition.broadcast()
        condition.unlock()
        if rearm { armReceive() }
    }

    /// Short words for what went wrong, to follow "Could not talk to the mount: ".
    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "the mount refused the connection (wrong port?)"
            case .ETIMEDOUT: return "the connection timed out"
            case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN: return "the mount cannot be reached on this network"
            case .ECONNRESET, .EPIPE: return "the connection was reset"
            case .ENOTCONN: return "the connection was closed"
            case .EPERM, .EACCES: return "network access was refused (is Local Network allowed for Lodestar?)"
            default: return "network error \(code.rawValue)"
            }
        case .dns(let code):
            // kDNSServiceErr_PolicyDenied: the person said no to the local network question.
            return code == -65_570 ? "Local Network access is off for Lodestar" : "the address was not found"
        default:
            return "a network error"
        }
    }
}

/// Carries the result of one asynchronous send back to the thread that waits for it.
private final class MountSendOutcome: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var failure: NWError?

    var error: NWError? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    func finish(_ error: NWError?) {
        lock.lock()
        failure = error
        lock.unlock()
        semaphore.signal()
    }

    /// `false` if the send was not reported within `timeoutSeconds`.
    func wait(timeoutSeconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + timeoutSeconds) == .success
    }
}

// MARK: - HTTP for Alpaca

/// One Alpaca server over plain HTTP (a LAN address; App Transport Security allows it through `NSAllowsLocalNetworking`),
/// behind the engine's blocking `AlpacaTransport`.
final class MountHTTPTransport: AlpacaTransport, @unchecked Sendable {
    /// Larger answers are refused; Alpaca replies are a few hundred bytes.
    private static let maximumResponseBytes = 262_144

    let endpoint: AlpacaEndpoint
    private let session: URLSession
    private let lock = NSLock()
    private var currentTask: URLSessionDataTask?
    private var isClosed = false

    init(endpoint: AlpacaEndpoint) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
        self.endpoint = endpoint
    }

    func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse {
        guard let url = URL(string: endpoint.baseURL + request.target) else {
            throw MountError.invalidInput(detail: "the address is not valid")
        }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                    timeoutInterval: max(timeoutSeconds, 1))
        urlRequest.httpMethod = request.method.rawValue
        if request.method == .put {
            urlRequest.httpBody = Data(request.body.utf8)
            if let contentType = request.contentType {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        let outcome = MountHTTPOutcome()
        lock.lock()
        // A session that has been invalidated must not be given new tasks.
        guard !isClosed else {
            lock.unlock()
            throw MountError.transport(detail: "the connection was closed")
        }
        let task = session.dataTask(with: urlRequest) { data, response, error in
            outcome.finish(data: data, response: response, error: error)
        }
        currentTask = task
        lock.unlock()
        task.resume()
        let finished = outcome.wait(timeoutSeconds: max(timeoutSeconds, 1) + 2)
        lock.lock()
        currentTask = nil
        lock.unlock()
        guard finished else {
            task.cancel()
            throw MountError.timeout(operation: "waiting for the Alpaca server")
        }
        if let error = outcome.error {
            let code = (error as? URLError)?.code
            if code == .cancelled { throw MountError.timeout(operation: "stopped waiting") }
            if code == .timedOut { throw MountError.timeout(operation: "waiting for the Alpaca server") }
            throw MountError.transport(detail: Self.describe(error))
        }
        guard let http = outcome.response as? HTTPURLResponse else {
            throw MountError.malformedReply(detail: "not an HTTP answer")
        }
        let data = outcome.data ?? Data()
        guard data.count <= Self.maximumResponseBytes else {
            throw MountError.malformedReply(detail: "the answer is too long")
        }
        return AlpacaHTTPResponse(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
    }

    /// Cancels the request that is running right now.
    func interrupt() {
        lock.lock()
        let task = currentTask
        lock.unlock()
        task?.cancel()
    }

    func close() {
        lock.lock()
        isClosed = true
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
        session.invalidateAndCancel()
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "a network error" }
        switch urlError.code {
        case .cannotConnectToHost: return "the server refused the connection (wrong port?)"
        case .cannotFindHost, .dnsLookupFailed: return "the server address was not found"
        case .notConnectedToInternet, .networkConnectionLost:
            return "no network connection to the server (is Local Network allowed for Lodestar?)"
        default: return "network error \(urlError.errorCode)"
        }
    }
}

/// Carries the answer of one URLSession task back to the thread that waits for it.
private final class MountHTTPOutcome: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedData: Data?
    private var storedResponse: URLResponse?
    private var storedError: Error?

    var data: Data? { read { storedData } }
    var response: URLResponse? { read { storedResponse } }
    var error: Error? { read { storedError } }

    func finish(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        storedData = data
        storedResponse = response
        storedError = error
        lock.unlock()
        semaphore.signal()
    }

    /// `false` if the task did not finish within `timeoutSeconds`.
    func wait(timeoutSeconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + timeoutSeconds) == .success
    }

    private func read<Value>(_ value: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value()
    }
}

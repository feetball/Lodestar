import Darwin
import Foundation
import LodestarKit
import XCTest
@testable import AppCore

// Tests of the mount links in Services/MountTransports.swift and of the parts of Services/MountDiscovery.swift that talk to
// a server. Every server here is started by the test on 127.0.0.1 with an ephemeral port (BSD sockets); nothing leaves the
// machine. Every socket is closed in tearDown.

// MARK: - Loopback helpers

private enum MountNetFailure: Error {
    case socket
    case bind
}

private func mountNetLoopbackAddress(port: UInt16) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
    return address
}

private func mountNetBind(_ descriptor: Int32, port: UInt16) -> Bool {
    var address = mountNetLoopbackAddress(port: port)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
            Darwin.bind(descriptor, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}

private func mountNetBoundPort(_ descriptor: Int32) -> Int? {
    var address = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
            getsockname(descriptor, generic, &length)
        }
    }
    guard result == 0 else { return nil }
    return Int(UInt16(bigEndian: address.sin_port))
}

/// A TCP port on which nobody listens: bound once, then closed again before anything listened.
private func mountNetUnusedPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw MountNetFailure.socket }
    defer { Darwin.close(descriptor) }
    guard mountNetBind(descriptor, port: 0), let port = mountNetBoundPort(descriptor) else { throw MountNetFailure.bind }
    return port
}

private func mountNetPoll(_ descriptor: Int32, events: Int32, milliseconds: Int32) -> Bool {
    var item = pollfd(fd: descriptor, events: Int16(events), revents: 0)
    return poll(&item, 1, milliseconds) > 0
}

private func mountNetWriteAll(_ descriptor: Int32, _ bytes: [UInt8], timeout: Double = 20) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    var offset = 0
    while offset < bytes.count {
        guard Date() < deadline else { return false }
        guard mountNetPoll(descriptor, events: POLLOUT, milliseconds: 100) else { continue }
        let written = bytes.withUnsafeBufferPointer { buffer in
            Darwin.write(descriptor, buffer.baseAddress! + offset, bytes.count - offset)
        }
        if written > 0 {
            offset += written
        } else if written < 0 && errno != EAGAIN && errno != EINTR {
            return false
        }
    }
    return true
}

private func mountNetReadAvailable(_ descriptor: Int32, count: Int, timeout: Double) -> [UInt8] {
    let deadline = Date(timeIntervalSinceNow: timeout)
    var result: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while result.count < count && Date() < deadline {
        guard mountNetPoll(descriptor, events: POLLIN, milliseconds: 50) else { continue }
        let wanted = min(chunk.count, count - result.count)
        let got = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, wanted) }
        if got <= 0 { break }
        result.append(contentsOf: chunk[0..<got])
    }
    return result
}

private func mountNetSendDatagram(_ descriptor: Int32, _ bytes: [UInt8], to address: sockaddr_in) -> Bool {
    var destination = address
    let length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let sent = withUnsafePointer(to: &destination) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
            Darwin.sendto(descriptor, bytes, bytes.count, 0, generic, length)
        }
    }
    return sent == bytes.count
}

/// A TCP server that accepts connections and lets the test write to them, read from them and close them.
private final class MountNetTCPServer: @unchecked Sendable {
    let port: Int
    private let listener: Int32
    private let condition = NSCondition()
    private var clients: [Int32] = []
    private var stopRequested = false
    private var isStopped = false
    private let loopEnded = DispatchSemaphore(value: 0)

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MountNetFailure.socket }
        guard mountNetBind(descriptor, port: 0), Darwin.listen(descriptor, 8) == 0,
              let bound = mountNetBoundPort(descriptor) else {
            Darwin.close(descriptor)
            throw MountNetFailure.bind
        }
        listener = descriptor
        port = bound
        Thread.detachNewThread { [self] in self.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            condition.lock()
            let done = stopRequested
            condition.unlock()
            if done { break }
            guard mountNetPoll(listener, events: POLLIN, milliseconds: 50) else { continue }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { continue }
            var quiet: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
            condition.lock()
            clients.append(client)
            condition.broadcast()
            condition.unlock()
        }
        loopEnded.signal()
    }

    /// The descriptor of the `index`-th accepted connection, waiting for it to arrive.
    func clientDescriptor(_ index: Int = 0, timeout: Double = 10) -> Int32? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while clients.count <= index {
            if !condition.wait(until: deadline) { return nil }
        }
        let descriptor = clients[index]
        return descriptor >= 0 ? descriptor : nil
    }

    @discardableResult
    func sendToClient(_ bytes: [UInt8], client index: Int = 0) -> Bool {
        guard let descriptor = clientDescriptor(index) else { return false }
        return mountNetWriteAll(descriptor, bytes)
    }

    func readFromClient(count: Int, client index: Int = 0, timeout: Double = 10) -> [UInt8] {
        guard let descriptor = clientDescriptor(index) else { return [] }
        return mountNetReadAvailable(descriptor, count: count, timeout: timeout)
    }

    /// Closes the server's end of a connection, which the client sees as the end of the stream.
    func closeClient(_ index: Int = 0) {
        guard let descriptor = clientDescriptor(index) else { return }
        condition.lock()
        clients[index] = -1
        condition.unlock()
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    func stop() {
        condition.lock()
        if isStopped {
            condition.unlock()
            return
        }
        isStopped = true
        stopRequested = true
        condition.unlock()
        _ = loopEnded.wait(timeout: .now() + 3)
        Darwin.close(listener)
        condition.lock()
        for descriptor in clients where descriptor >= 0 { Darwin.close(descriptor) }
        clients.removeAll()
        condition.unlock()
    }
}

/// A UDP socket on 127.0.0.1 that records the datagrams it gets and answers the sender on request, or by itself.
private final class MountNetUDPServer: @unchecked Sendable {
    let port: Int
    private let descriptor: Int32
    private let condition = NSCondition()
    private var received: [[UInt8]] = []
    private var lastSender: sockaddr_in?
    private var automaticReply: [UInt8]?
    private var stopRequested = false
    private var isStopped = false
    private let loopEnded = DispatchSemaphore(value: 0)

    init() throws {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketDescriptor >= 0 else { throw MountNetFailure.socket }
        guard mountNetBind(socketDescriptor, port: 0), let bound = mountNetBoundPort(socketDescriptor) else {
            Darwin.close(socketDescriptor)
            throw MountNetFailure.bind
        }
        descriptor = socketDescriptor
        port = bound
        Thread.detachNewThread { [self] in self.receiveLoop() }
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            condition.lock()
            let done = stopRequested
            condition.unlock()
            if done { break }
            guard mountNetPoll(descriptor, events: POLLIN, milliseconds: 50) else { continue }
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &sender) { senderPointer in
                    senderPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        Darwin.recvfrom(descriptor, raw.baseAddress, raw.count, 0, generic, &senderLength)
                    }
                }
            }
            guard count >= 0 else { continue }
            condition.lock()
            received.append(Array(buffer.prefix(count)))
            lastSender = sender
            let reply = automaticReply
            condition.broadcast()
            condition.unlock()
            if let reply { _ = mountNetSendDatagram(descriptor, reply, to: sender) }
        }
        loopEnded.signal()
    }

    /// Answers every datagram that arrives from now on with `bytes`.
    func setAutomaticReply(_ bytes: [UInt8]?) {
        condition.lock()
        automaticReply = bytes
        condition.unlock()
    }

    /// The oldest datagram not yet taken, waiting for it to arrive.
    func nextDatagram(timeout: Double = 10) -> [UInt8]? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while received.isEmpty {
            if !condition.wait(until: deadline) { return nil }
        }
        return received.removeFirst()
    }

    var pendingDatagrams: Int {
        condition.lock()
        defer { condition.unlock() }
        return received.count
    }

    /// Sends one datagram to whoever sent the last one.
    @discardableResult
    func reply(_ bytes: [UInt8]) -> Bool {
        condition.lock()
        let sender = lastSender
        condition.unlock()
        guard let sender else { return false }
        return mountNetSendDatagram(descriptor, bytes, to: sender)
    }

    func stop() {
        condition.lock()
        if isStopped {
            condition.unlock()
            return
        }
        isStopped = true
        stopRequested = true
        condition.unlock()
        _ = loopEnded.wait(timeout: .now() + 3)
        Darwin.close(descriptor)
    }
}

private struct MountNetHTTPRequest {
    var method = ""
    var target = ""
    /// Header names in lower case.
    var headers: [String: String] = [:]
    var body = ""
}

/// An HTTP/1.1 server for one reply per connection. The handler returns the complete reply (head and body) to send, an empty
/// array to close the connection without a word, or nil to never answer.
private final class MountNetHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (MountNetHTTPRequest) -> [UInt8]?

    let port: Int
    private let listener: Int32
    private let handler: Handler
    private let condition = NSCondition()
    private var requests: [MountNetHTTPRequest] = []
    private var stopRequested = false
    private var isStopped = false
    private let loopEnded = DispatchSemaphore(value: 0)
    private let connectionThreads = DispatchGroup()

    init(handler: @escaping Handler) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MountNetFailure.socket }
        guard mountNetBind(descriptor, port: 0), Darwin.listen(descriptor, 16) == 0,
              let bound = mountNetBoundPort(descriptor) else {
            Darwin.close(descriptor)
            throw MountNetFailure.bind
        }
        listener = descriptor
        port = bound
        self.handler = handler
        Thread.detachNewThread { [self] in self.acceptLoop() }
    }

    private var isStopping: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopRequested
    }

    private func acceptLoop() {
        while !isStopping {
            guard mountNetPoll(listener, events: POLLIN, milliseconds: 50) else { continue }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { continue }
            var quiet: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
            connectionThreads.enter()
            Thread.detachNewThread { [self] in self.serve(client) }
        }
        loopEnded.signal()
    }

    private static func headerEnd(in data: [UInt8]) -> Int? {
        guard data.count >= 4 else { return nil }
        for index in 0...(data.count - 4)
        where data[index] == 13 && data[index + 1] == 10 && data[index + 2] == 13 && data[index + 3] == 10 {
            return index + 4
        }
        return nil
    }

    private static func parse(head: String) -> MountNetHTTPRequest {
        var request = MountNetHTTPRequest()
        let lines = head.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
        if first.count >= 2 {
            request.method = String(first[0])
            request.target = String(first[1])
        }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            request.headers[name] = value
        }
        return request
    }

    private func serve(_ client: Int32) {
        defer {
            Darwin.close(client)
            connectionThreads.leave()
        }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4_096)
        var headEnd: Int?
        var head = ""
        var expected = 0
        while true {
            if let end = headEnd, data.count - end >= expected { break }
            if isStopping { return }
            guard mountNetPoll(client, events: POLLIN, milliseconds: 50) else { continue }
            let got = chunk.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress, $0.count) }
            if got <= 0 { return }
            data.append(contentsOf: chunk[0..<got])
            if headEnd == nil, let end = Self.headerEnd(in: data) {
                headEnd = end
                head = String(decoding: data[0..<(end - 4)], as: UTF8.self)
                let lengthLine = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                expected = lengthLine.flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
            }
        }
        guard let end = headEnd else { return }
        var request = Self.parse(head: head)
        request.body = String(decoding: data[end..<min(data.count, end + expected)], as: UTF8.self)
        condition.lock()
        requests.append(request)
        condition.broadcast()
        condition.unlock()
        guard let response = handler(request) else {
            // Never answer: keep the connection until the client goes away or the server stops.
            while !isStopping {
                guard mountNetPoll(client, events: POLLIN, milliseconds: 50) else { continue }
                let got = chunk.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress, $0.count) }
                if got <= 0 { return }
            }
            return
        }
        _ = mountNetWriteAll(client, response)
    }

    var recorded: [MountNetHTTPRequest] {
        condition.lock()
        defer { condition.unlock() }
        return requests
    }

    /// Waits until `count` requests have been received.
    func waitForRequests(_ count: Int, timeout: Double = 10) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while requests.count < count {
            if !condition.wait(until: deadline) { return false }
        }
        return true
    }

    func stop() {
        condition.lock()
        if isStopped {
            condition.unlock()
            return
        }
        isStopped = true
        stopRequested = true
        condition.unlock()
        _ = loopEnded.wait(timeout: .now() + 3)
        _ = connectionThreads.wait(timeout: .now() + 3)
        Darwin.close(listener)
    }
}

private func mountNetHTTPResponse(status: Int = 200, body: [UInt8], contentType: String = "application/json") -> [UInt8] {
    let head = "HTTP/1.1 \(status) Reply\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    return Array(head.utf8) + body
}

private func mountNetHTTPResponse(status: Int = 200, body: String, contentType: String = "application/json") -> [UInt8] {
    mountNetHTTPResponse(status: status, body: Array(body.utf8), contentType: contentType)
}

/// Runs blocking work on a background queue so that the test thread can act while it waits.
private final class MountNetBackground<Value>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    init(_ work: @escaping () throws -> Value) {
        DispatchQueue.global().async {
            let outcome = Result { try work() }
            self.lock.lock()
            self.result = outcome
            self.lock.unlock()
            self.semaphore.signal()
        }
    }

    /// The outcome, or nil if the work did not end within `timeout` seconds.
    func wait(timeout: Double) -> Result<Value, Error>? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private func mountNetError<Value>(_ result: Result<Value, Error>?) -> MountError? {
    guard case .failure(let error)? = result else { return nil }
    return error as? MountError
}

/// The `MountError` thrown by `body`; nil (after a test failure) if it did not throw one.
private func mountNetThrown<Value>(_ body: () throws -> Value, file: StaticString = #filePath, line: UInt = #line) -> MountError? {
    do {
        _ = try body()
        XCTFail("expected a MountError", file: file, line: line)
        return nil
    } catch let error as MountError {
        return error
    } catch {
        XCTFail("unexpected error \(error)", file: file, line: line)
        return nil
    }
}

/// Reads exactly `count` bytes, however the input is split up.
private func mountNetReadAll(_ transport: MountSocketTransport, count: Int, timeout: Double = 10) throws -> [UInt8] {
    let deadline = Date(timeIntervalSinceNow: timeout)
    var result: [UInt8] = []
    while result.count < count {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw MountError.timeout(operation: "the test deadline") }
        let part = try transport.receive(maxCount: count - result.count, timeoutSeconds: remaining)
        result.append(contentsOf: part)
    }
    return result
}

// MARK: - TCP and UDP

final class MountNetSocketTransportTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups.removeAll()
        super.tearDown()
    }

    private func startTCPServer() throws -> MountNetTCPServer {
        let server = try MountNetTCPServer()
        cleanups.append { server.stop() }
        return server
    }

    private func startUDPServer() throws -> MountNetUDPServer {
        let server = try MountNetUDPServer()
        cleanups.append { server.stop() }
        return server
    }

    private func makeTransport(port: Int, kind: MountSocketTransport.Kind = .tcp) throws -> MountSocketTransport {
        let transport = try XCTUnwrap(MountSocketTransport(host: "127.0.0.1", port: port, kind: kind))
        cleanups.append { transport.close() }
        return transport
    }

    private func connectedTCP() throws -> (server: MountNetTCPServer, transport: MountSocketTransport) {
        let server = try startTCPServer()
        let transport = try makeTransport(port: server.port)
        try transport.open(timeoutSeconds: 10)
        return (server, transport)
    }

    private func connectedUDP() throws -> (server: MountNetUDPServer, transport: MountSocketTransport) {
        let server = try startUDPServer()
        let transport = try makeTransport(port: server.port, kind: .udp)
        try transport.open(timeoutSeconds: 10)
        return (server, transport)
    }

    // MARK: Creating

    func testPortsOutsideOneToSixtyFiveThousandAreRefused() {
        for kind in [MountSocketTransport.Kind.tcp, .udp] {
            XCTAssertNil(MountSocketTransport(host: "127.0.0.1", port: 0, kind: kind))
            XCTAssertNil(MountSocketTransport(host: "127.0.0.1", port: -1, kind: kind))
            XCTAssertNil(MountSocketTransport(host: "127.0.0.1", port: 65_536, kind: kind))
            XCTAssertNil(MountSocketTransport(host: "127.0.0.1", port: Int.max, kind: kind))
        }
    }

    func testTheFirstAndLastPortAreAccepted() {
        XCTAssertNotNil(MountSocketTransport(host: "127.0.0.1", port: 1, kind: .tcp))
        XCTAssertNotNil(MountSocketTransport(host: "127.0.0.1", port: 65_535, kind: .udp))
    }

    func testEmptyAndBlankHostsAreRefused() {
        XCTAssertNil(MountSocketTransport(host: "", port: 9999, kind: .tcp))
        XCTAssertNil(MountSocketTransport(host: "   ", port: 9999, kind: .tcp))
        XCTAssertNil(MountSocketTransport(host: " \t ", port: 9999, kind: .udp))
    }

    func testBlanksAroundAHostAreIgnored() {
        XCTAssertNotNil(MountSocketTransport(host: "  192.168.0.1 ", port: 9999, kind: .tcp))
    }

    func testTheTransportRemembersItsKind() throws {
        XCTAssertEqual(try XCTUnwrap(MountSocketTransport(host: "127.0.0.1", port: 80, kind: .tcp)).kind, .tcp)
        XCTAssertEqual(try XCTUnwrap(MountSocketTransport(host: "127.0.0.1", port: 80, kind: .udp)).kind, .udp)
    }

    func testTheKindIsStoredAsItsName() throws {
        let data = try JSONEncoder().encode([MountSocketTransport.Kind.tcp, .udp])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"tcp\",\"udp\"]")
        let decoded = try JSONDecoder().decode([MountSocketTransport.Kind].self, from: Data("[\"udp\"]".utf8))
        XCTAssertEqual(decoded, [.udp])
        XCTAssertThrowsError(try JSONDecoder().decode([MountSocketTransport.Kind].self, from: Data("[\"sctp\"]".utf8)))
    }

    // MARK: Opening

    func testOpeningConnectsToAListeningServer() throws {
        let (server, _) = try connectedTCP()
        XCTAssertNotNil(server.clientDescriptor(0))
    }

    func testOpeningTwiceIsHarmless() throws {
        let (server, transport) = try connectedTCP()
        try transport.open(timeoutSeconds: 10)
        XCTAssertNotNil(server.clientDescriptor(0))
        XCTAssertNil(server.clientDescriptor(1, timeout: 0.3), "a second open must not start a second connection")
    }

    func testOpeningAPortNobodyListensOnFails() throws {
        let transport = try makeTransport(port: try mountNetUnusedPort())
        let started = Date()
        let error = mountNetThrown { try transport.open(timeoutSeconds: 1.0) }
        switch error {
        case .timeout(let operation)?:
            // Network.framework keeps a refused connection in its waiting state, which `open` reports as a timeout.
            XCTAssertTrue(operation.hasPrefix("connecting"), operation)
        case .transport(let detail)?:
            XCTAssertFalse(detail.isEmpty)
        default:
            XCTFail("unexpected \(String(describing: error))")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 15.0)
    }

    func testOpeningAnInterruptedJobFailsAtOnce() throws {
        let transport = try makeTransport(port: try mountNetUnusedPort())
        transport.interrupt()
        let started = Date()
        let error = mountNetThrown { try transport.open(timeoutSeconds: 30) }
        guard case .transport? = error else {
            XCTFail("expected a transport error, got \(String(describing: error))")
            return
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 15.0)
    }

    func testInterruptingWakesAnOpenThatIsWaiting() throws {
        let transport = try makeTransport(port: try mountNetUnusedPort())
        let pending = MountNetBackground { try transport.open(timeoutSeconds: 60) }
        Thread.sleep(forTimeInterval: 0.2)
        transport.interrupt()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "the open was not woken")
        guard case .transport? = mountNetError(result) else {
            XCTFail("expected a transport error, got \(String(describing: result))")
            return
        }
    }

    func testClosingWakesAnOpenThatIsWaiting() throws {
        let transport = try makeTransport(port: try mountNetUnusedPort())
        let pending = MountNetBackground { try transport.open(timeoutSeconds: 60) }
        Thread.sleep(forTimeInterval: 0.2)
        transport.close()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "the open was not woken")
        guard case .transport? = mountNetError(result) else {
            XCTFail("expected a transport error, got \(String(describing: result))")
            return
        }
    }

    // MARK: Sending

    func testSendDeliversTheBytesToTheServer() throws {
        let (server, transport) = try connectedTCP()
        try transport.send([0x3A, 0x47, 0x52, 0x23])
        XCTAssertEqual(server.readFromClient(count: 4), [0x3A, 0x47, 0x52, 0x23])
    }

    func testSendsArriveInOrder() throws {
        let (server, transport) = try connectedTCP()
        for value in 0..<20 { try transport.send([UInt8(value)]) }
        XCTAssertEqual(server.readFromClient(count: 20), (0..<20).map { UInt8($0) })
    }

    func testAnInterruptedSendFailsBeforeTouchingTheLink() throws {
        let transport = try makeTransport(port: 9)
        transport.interrupt()
        XCTAssertEqual(mountNetThrown { try transport.send([1, 2, 3]) }, MountError.transport(detail: "the command was stopped"))
    }

    func testSendAfterCloseFails() throws {
        let (_, transport) = try connectedTCP()
        transport.close()
        XCTAssertEqual(mountNetThrown { try transport.send([1]) }, MountError.transport(detail: "the connection was closed"))
    }

    func testInterruptionComesBeforeTheClosedCheckInSend() throws {
        let (_, transport) = try connectedTCP()
        transport.close()
        transport.interrupt()
        XCTAssertEqual(mountNetThrown { try transport.send([1]) }, MountError.transport(detail: "the command was stopped"))
    }

    // MARK: Receiving

    func testReceiveReturnsWhatTheServerSent() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([0x31, 0x0D]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 2), [0x31, 0x0D])
    }

    func testReceiveReturnsAsSoonAsBytesArrive() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertNotNil(server.clientDescriptor(0))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { _ = server.sendToClient([0x42]) }
        let started = Date()
        let bytes = try transport.receive(maxCount: 10, timeoutSeconds: 10)
        XCTAssertEqual(bytes, [0x42])
        XCTAssertLessThan(Date().timeIntervalSince(started), 9.0, "receive sat out its timeout")
    }

    func testAStreamHasNoMessageBoundaries() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([1, 2]))
        XCTAssertTrue(server.sendToClient([3]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 3), [1, 2, 3])
    }

    func testReceiveNeverReturnsMoreThanMaxCount() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([1, 2, 3, 4, 5]))
        let first = try transport.receive(maxCount: 2, timeoutSeconds: 10)
        XCTAssertGreaterThanOrEqual(first.count, 1)
        XCTAssertLessThanOrEqual(first.count, 2)
        let firstTwo: [UInt8] = [1, 2]
        XCTAssertEqual(first, Array(firstTwo.prefix(first.count)))
        let rest = try mountNetReadAll(transport, count: 5 - first.count)
        XCTAssertEqual(first + rest, [1, 2, 3, 4, 5])
    }

    func testAMaxCountBelowOneStillReturnsOneByte() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([7, 8, 9]))
        XCTAssertEqual(try transport.receive(maxCount: 0, timeoutSeconds: 10), [7])
        XCTAssertEqual(try transport.receive(maxCount: -4, timeoutSeconds: 10), [8])
    }

    func testReceiveTimesOutWhenNothingArrives() throws {
        let (_, transport) = try connectedTCP()
        let started = Date()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 16, timeoutSeconds: 0.3) },
                       MountError.timeout(operation: "waiting for a reply"))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 0.25)
        XCTAssertLessThan(elapsed, 10.0)
    }

    func testAZeroOrNegativeTimeoutFailsAtOnceWhenTheBufferIsEmpty() throws {
        let (_, transport) = try connectedTCP()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0) },
                       MountError.timeout(operation: "waiting for a reply"))
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: -5) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testReceiveOnALinkThatWasNeverOpenedTimesOut() throws {
        let transport = try makeTransport(port: 9)
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testDiscardPendingInputDropsWhatWasNotRead() throws {
        let (server, transport) = try connectedTCP()
        // One write is one segment on the loopback, so the three bytes arrive together; the first read proves they have.
        XCTAssertTrue(server.sendToClient([1, 2, 3]))
        XCTAssertEqual(try transport.receive(maxCount: 1, timeoutSeconds: 10), [1])
        try transport.discardPendingInput()
        XCTAssertTrue(server.sendToClient([9]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 1), [9])
    }

    func testDiscardPendingInputWithNothingPendingDoesNothing() throws {
        let transport = try makeTransport(port: 9)
        XCTAssertNoThrow(try transport.discardPendingInput())
        XCTAssertNoThrow(try transport.discardPendingInput())
    }

    // MARK: The buffer

    func testTheBufferKeepsAtMostSixtyFiveThousandBytesAndDropsTheOldestFirst() throws {
        let (server, transport) = try connectedTCP()
        // 4 MB of a pattern that never contains 0xFF, then one 0xFF as the end marker. Nobody reads until the server has
        // written it all, which cannot happen unless the link took most of it in and threw the old bytes away.
        let sent = 4_000_000
        let pattern = (0..<sent).map { UInt8($0 % 250) }
        XCTAssertTrue(server.sendToClient(pattern + [0xFF]))

        var total = 0
        var largest = 0
        var continuous = true
        var sawMarker = false
        let deadline = Date(timeIntervalSinceNow: 60)
        while !sawMarker && Date() < deadline {
            let chunk = try transport.receive(maxCount: 1_000_000, timeoutSeconds: 10)
            total += chunk.count
            largest = max(largest, chunk.count)
            // Whatever is kept is a gap-free piece of the stream: the oldest bytes are cut off the front.
            for (previous, next) in zip(chunk, chunk.dropFirst()) where next != 0xFF && Int(next) != (Int(previous) + 1) % 250 {
                continuous = false
            }
            sawMarker = chunk.last == 0xFF
        }
        XCTAssertTrue(sawMarker, "the end of the stream never arrived")
        XCTAssertTrue(continuous, "the buffer reordered or corrupted bytes")
        XCTAssertLessThanOrEqual(largest, 65_536, "one read returned more than the buffer may hold")
        XCTAssertLessThan(total, sent + 1, "no byte was dropped")
    }

    // MARK: When the server goes away

    func testBytesThatArrivedBeforeTheServerClosedCanStillBeRead() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([5, 6]))
        server.closeClient()
        XCTAssertEqual(try mountNetReadAll(transport, count: 2), [5, 6])
    }

    func testTheServerClosingEndsTheLink() throws {
        let (server, transport) = try connectedTCP()
        server.closeClient()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 10) },
                       MountError.transport(detail: "the mount closed the connection"))
        // The link stays failed: later calls name the same cause.
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the mount closed the connection"))
        XCTAssertEqual(mountNetThrown { try transport.send([1]) },
                       MountError.transport(detail: "the mount closed the connection"))
        XCTAssertEqual(mountNetThrown { try transport.open(timeoutSeconds: 1) },
                       MountError.transport(detail: "the mount closed the connection"))
    }

    // MARK: Closing

    func testCloseWakesAWaitingReceive() throws {
        let (_, transport) = try connectedTCP()
        let pending = MountNetBackground { try transport.receive(maxCount: 1, timeoutSeconds: 60) }
        Thread.sleep(forTimeInterval: 0.2)
        transport.close()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "the receive was not woken")
        XCTAssertEqual(mountNetError(result), MountError.transport(detail: "the connection was closed"))
    }

    func testAfterCloseEveryCallFails() throws {
        let (_, transport) = try connectedTCP()
        transport.close()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the connection was closed"))
        XCTAssertEqual(mountNetThrown { try transport.send([1]) }, MountError.transport(detail: "the connection was closed"))
        XCTAssertEqual(mountNetThrown { try transport.open(timeoutSeconds: 1) },
                       MountError.transport(detail: "the connection was closed"))
    }

    func testCloseDropsTheBufferedInput() throws {
        let (server, transport) = try connectedTCP()
        XCTAssertTrue(server.sendToClient([1, 2, 3]))
        XCTAssertEqual(try transport.receive(maxCount: 1, timeoutSeconds: 10), [1])
        transport.close()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 10, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the connection was closed"))
    }

    func testClosingTwiceAndClosingAnUnopenedLinkAreHarmless() throws {
        let (_, transport) = try connectedTCP()
        transport.close()
        transport.close()
        let unopened = try makeTransport(port: 9)
        unopened.close()
        XCTAssertEqual(mountNetThrown { try unopened.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the connection was closed"))
    }

    // MARK: Interrupting

    func testAnInterruptionFailsTheNextReceive() throws {
        let (_, transport) = try connectedTCP()
        transport.interrupt()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 10) },
                       MountError.transport(detail: "the command was stopped"))
    }

    func testAnInterruptionHoldsUntilTheNextJobBegins() throws {
        let (_, transport) = try connectedTCP()
        transport.interrupt()
        for _ in 0..<2 {
            XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 10) },
                           MountError.transport(detail: "the command was stopped"))
            XCTAssertEqual(mountNetThrown { try transport.send([1]) }, MountError.transport(detail: "the command was stopped"))
        }
        transport.beginJob()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testAJobThatBeginsAfterTheInterruptionIsNotAffected() throws {
        let (server, transport) = try connectedTCP()
        transport.interrupt()
        transport.beginJob()
        try transport.send([0x21])
        XCTAssertEqual(server.readFromClient(count: 1), [0x21])
    }

    func testTwoInterruptionsAreForgivenByOneBeginJob() throws {
        let (_, transport) = try connectedTCP()
        transport.interrupt()
        transport.interrupt()
        transport.beginJob()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testInterruptingWakesAReceiveThatIsWaiting() throws {
        let (_, transport) = try connectedTCP()
        let pending = MountNetBackground { try transport.receive(maxCount: 1, timeoutSeconds: 60) }
        Thread.sleep(forTimeInterval: 0.2)
        transport.interrupt()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "the receive was not woken")
        XCTAssertEqual(mountNetError(result), MountError.transport(detail: "the command was stopped"))
    }

    // MARK: UDP

    func testAUDPSocketIsReadyAtOnce() throws {
        let (_, transport) = try connectedUDP()
        XCTAssertEqual(transport.kind, .udp)
    }

    func testAUDPSendIsOneDatagram() throws {
        let (server, transport) = try connectedUDP()
        try transport.send([0x3A, 0x65, 0x31, 0x0D])
        try transport.send([0x3A, 0x65, 0x32, 0x0D])
        XCTAssertEqual(server.nextDatagram(), [0x3A, 0x65, 0x31, 0x0D])
        XCTAssertEqual(server.nextDatagram(), [0x3A, 0x65, 0x32, 0x0D])
    }

    func testAUDPReplyIsReadBack() throws {
        let (server, transport) = try connectedUDP()
        try transport.send([1])
        XCTAssertNotNil(server.nextDatagram())
        XCTAssertTrue(server.reply([0x3D, 0x32, 0x30, 0x0D]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 4), [0x3D, 0x32, 0x30, 0x0D])
    }

    func testRepliesInSeparateDatagramsFollowEachOtherInTheBuffer() throws {
        let (server, transport) = try connectedUDP()
        try transport.send([1])
        XCTAssertNotNil(server.nextDatagram())
        XCTAssertTrue(server.reply([1, 2]))
        XCTAssertTrue(server.reply([3, 4, 5]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 5), [1, 2, 3, 4, 5])
    }

    func testAUDPReceiveTimesOut() throws {
        let (_, transport) = try connectedUDP()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 8, timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testDiscardingDropsAUDPReplyThatCameLate() throws {
        let (server, transport) = try connectedUDP()
        try transport.send([1])
        XCTAssertNotNil(server.nextDatagram())
        XCTAssertTrue(server.reply([1, 2, 3]))
        XCTAssertEqual(try transport.receive(maxCount: 1, timeoutSeconds: 10), [1])
        try transport.discardPendingInput()
        XCTAssertTrue(server.reply([9]))
        XCTAssertEqual(try mountNetReadAll(transport, count: 1), [9])
    }
}

// MARK: - The channel

final class MountNetChannelTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups.removeAll()
        super.tearDown()
    }

    private func socketTransport(port: Int) throws -> MountSocketTransport {
        let transport = try XCTUnwrap(MountSocketTransport(host: "127.0.0.1", port: port, kind: .tcp))
        cleanups.append { transport.close() }
        return transport
    }

    private func httpTransport(port: Int) -> MountHTTPTransport {
        let transport = MountHTTPTransport(endpoint: AlpacaEndpoint(host: "127.0.0.1", port: port))
        cleanups.append { transport.close() }
        return transport
    }

    func testTheSimulatedChannelDoesNothingAndFailsNothing() throws {
        let channel = MountChannel.simulated
        XCTAssertNoThrow(try channel.open(timeoutSeconds: 0.1))
        channel.interrupt()
        channel.beginJob()
        channel.close()
    }

    func testAnHTTPChannelOpensWithoutTouchingTheNetwork() throws {
        let channel = MountChannel.http(httpTransport(port: 9))
        XCTAssertNoThrow(try channel.open(timeoutSeconds: 0.1))
    }

    func testAStreamChannelOpensTheSocket() throws {
        let server = try MountNetTCPServer()
        cleanups.append { server.stop() }
        let transport = try socketTransport(port: server.port)
        try MountChannel.stream(transport).open(timeoutSeconds: 10)
        XCTAssertNotNil(server.clientDescriptor(0))
    }

    func testAStreamChannelPassesInterruptsAndNewJobsOn() throws {
        let transport = try socketTransport(port: 9)
        let channel = MountChannel.stream(transport)
        channel.interrupt()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the command was stopped"))
        channel.beginJob()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for a reply"))
    }

    func testAStreamChannelPassesCloseOn() throws {
        let transport = try socketTransport(port: 9)
        MountChannel.stream(transport).close()
        XCTAssertEqual(mountNetThrown { try transport.receive(maxCount: 1, timeoutSeconds: 0.2) },
                       MountError.transport(detail: "the connection was closed"))
    }

    func testAnHTTPChannelPassesInterruptsAndNewJobsOn() throws {
        let server = try MountNetHTTPServer { _ in mountNetHTTPResponse(body: "{}") }
        cleanups.append { server.stop() }
        let transport = httpTransport(port: server.port)
        let channel = MountChannel.http(transport)
        let request = AlpacaHTTPRequest(method: .get, path: "/ping", query: [], form: [], clientTransactionID: 1)
        channel.interrupt()
        XCTAssertEqual(mountNetThrown { try transport.send(request, timeoutSeconds: 5) },
                       MountError.transport(detail: "the command was stopped"))
        XCTAssertTrue(server.recorded.isEmpty)
        channel.beginJob()
        XCTAssertEqual(try transport.send(request, timeoutSeconds: 10), AlpacaHTTPResponse(statusCode: 200, body: "{}"))
    }

    func testAnHTTPChannelPassesCloseOn() throws {
        let transport = httpTransport(port: 9)
        MountChannel.http(transport).close()
        let request = AlpacaHTTPRequest(method: .get, path: "/ping", query: [], form: [], clientTransactionID: 1)
        XCTAssertEqual(mountNetThrown { try transport.send(request, timeoutSeconds: 1) },
                       MountError.transport(detail: "the connection was closed"))
    }
}

// MARK: - HTTP

final class MountNetHTTPTransportTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups.removeAll()
        super.tearDown()
    }

    private func startServer(_ handler: @escaping MountNetHTTPServer.Handler) throws -> MountNetHTTPServer {
        let server = try MountNetHTTPServer(handler: handler)
        cleanups.append { server.stop() }
        return server
    }

    private func transport(port: Int) -> MountHTTPTransport {
        let transport = MountHTTPTransport(endpoint: AlpacaEndpoint(host: "127.0.0.1", port: port))
        cleanups.append { transport.close() }
        return transport
    }

    private func getRequest(_ id: Int = 1, path: String = "/api/v1/telescope/0/tracking") -> AlpacaHTTPRequest {
        AlpacaHTTPRequest(method: .get, path: path,
                          query: [AlpacaField(name: "ClientID", value: "1"),
                                  AlpacaField(name: "ClientTransactionID", value: String(id))],
                          form: [], clientTransactionID: id)
    }

    private func putRequest(_ id: Int = 2) -> AlpacaHTTPRequest {
        AlpacaHTTPRequest(method: .put, path: "/api/v1/telescope/0/tracking", query: [],
                          form: [AlpacaField(name: "Tracking", value: "True"), AlpacaField(name: "ClientID", value: "1"),
                                 AlpacaField(name: "ClientTransactionID", value: String(id))],
                          clientTransactionID: id)
    }

    // MARK: Requests

    func testTheEndpointIsKept() {
        let endpoint = AlpacaEndpoint(host: "192.168.1.20", port: 11111)
        let transport = MountHTTPTransport(endpoint: endpoint)
        cleanups.append { transport.close() }
        XCTAssertEqual(transport.endpoint, endpoint)
    }

    func testAGetSendsTheQueryInTheTarget() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{\"Value\":true}") }
        let response = try transport(port: server.port).send(getRequest(5), timeoutSeconds: 10)
        XCTAssertEqual(response, AlpacaHTTPResponse(statusCode: 200, body: "{\"Value\":true}"))
        let seen = try XCTUnwrap(server.recorded.first)
        XCTAssertEqual(seen.method, "GET")
        XCTAssertEqual(seen.target, "/api/v1/telescope/0/tracking?ClientID=1&ClientTransactionID=5")
        XCTAssertEqual(seen.body, "")
    }

    func testAPutSendsTheFormAsTheBody() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{}") }
        _ = try transport(port: server.port).send(putRequest(2), timeoutSeconds: 10)
        let seen = try XCTUnwrap(server.recorded.first)
        XCTAssertEqual(seen.method, "PUT")
        XCTAssertEqual(seen.target, "/api/v1/telescope/0/tracking")
        XCTAssertEqual(seen.body, "Tracking=True&ClientID=1&ClientTransactionID=2")
        XCTAssertEqual(seen.headers["content-type"], "application/x-www-form-urlencoded")
        XCTAssertEqual(seen.headers["content-length"], "46")
    }

    func testTwoRequestsInARowBothGetTheirAnswers() throws {
        let server = try startServer { request in mountNetHTTPResponse(body: "{\"target\":\"\(request.target)\"}") }
        let link = transport(port: server.port)
        let first = try link.send(getRequest(1, path: "/one"), timeoutSeconds: 10)
        let second = try link.send(getRequest(2, path: "/two"), timeoutSeconds: 10)
        XCTAssertEqual(first.body, "{\"target\":\"/one?ClientID=1&ClientTransactionID=1\"}")
        XCTAssertEqual(second.body, "{\"target\":\"/two?ClientID=1&ClientTransactionID=2\"}")
        XCTAssertEqual(server.recorded.count, 2)
    }

    // MARK: Answers

    func testAStatusOtherThan200IsAnAnswerNotAnError() throws {
        let server = try startServer { _ in mountNetHTTPResponse(status: 404, body: "Not found", contentType: "text/plain") }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 10)
        XCTAssertEqual(response, AlpacaHTTPResponse(statusCode: 404, body: "Not found"))
    }

    func testAServerErrorIsAnAnswerToo() throws {
        let server = try startServer { _ in mountNetHTTPResponse(status: 500, body: "boom", contentType: "text/plain") }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 10)
        XCTAssertEqual(response.statusCode, 500)
        XCTAssertEqual(response.body, "boom")
    }

    func testTheBodyIsDecodedAsUTF8() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "Gr\u{FC}\u{DF}e \u{1F30C}", contentType: "text/plain; charset=utf-8") }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 10)
        XCTAssertEqual(response.body, "Gr\u{FC}\u{DF}e \u{1F30C}")
    }

    func testBytesThatAreNotUTF8BecomeReplacementCharacters() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: [0x61, 0xFF, 0x62], contentType: "application/octet-stream") }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 10)
        XCTAssertEqual(response.body, "a\u{FFFD}b")
    }

    func testAnEmptyBodyIsAnEmptyString() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "") }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 10)
        XCTAssertEqual(response, AlpacaHTTPResponse(statusCode: 200, body: ""))
    }

    func testAnAnswerOfExactlyTheLargestSizeIsAccepted() throws {
        let body = String(repeating: "x", count: 262_144)
        let server = try startServer { _ in mountNetHTTPResponse(body: body) }
        let response = try transport(port: server.port).send(getRequest(), timeoutSeconds: 30)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body.utf8.count, 262_144)
    }

    func testAnAnswerOneByteOverTheLimitIsRefused() throws {
        let body = String(repeating: "x", count: 262_145)
        let server = try startServer { _ in mountNetHTTPResponse(body: body) }
        XCTAssertEqual(mountNetThrown { try transport(port: server.port).send(getRequest(), timeoutSeconds: 30) },
                       MountError.malformedReply(detail: "the answer is too long"))
    }

    // MARK: Failures

    func testAServerThatClosesWithoutAnswerIsATransportError() throws {
        let server = try startServer { _ in [] }
        let error = mountNetThrown { try transport(port: server.port).send(getRequest(), timeoutSeconds: 10) }
        guard case .transport(let detail)? = error else {
            XCTFail("expected a transport error, got \(String(describing: error))")
            return
        }
        XCTAssertFalse(detail.isEmpty)
    }

    func testARefusedConnectionNamesTheWrongPort() throws {
        let port = try mountNetUnusedPort()
        XCTAssertEqual(mountNetThrown { try transport(port: port).send(getRequest(), timeoutSeconds: 10) },
                       MountError.transport(detail: "the server refused the connection (wrong port?)"))
    }

    func testASilentServerTimesOutAfterAtLeastOneSecond() throws {
        let server = try startServer { _ in nil }
        let started = Date()
        // A timeout below one second is raised to one second.
        XCTAssertEqual(mountNetThrown { try transport(port: server.port).send(getRequest(), timeoutSeconds: 0.2) },
                       MountError.timeout(operation: "waiting for the Alpaca server"))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 0.9)
        XCTAssertLessThan(elapsed, 15.0)
    }

    // MARK: Interrupting and closing

    func testAnInterruptedJobSendsNothing() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{}") }
        let link = transport(port: server.port)
        link.interrupt()
        XCTAssertEqual(mountNetThrown { try link.send(getRequest(), timeoutSeconds: 5) },
                       MountError.transport(detail: "the command was stopped"))
        XCTAssertEqual(mountNetThrown { try link.send(getRequest(), timeoutSeconds: 5) },
                       MountError.transport(detail: "the command was stopped"))
        XCTAssertTrue(server.recorded.isEmpty)
    }

    func testANewJobIsNotAffectedByAnEarlierInterruption() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{}") }
        let link = transport(port: server.port)
        link.interrupt()
        link.beginJob()
        XCTAssertEqual(try link.send(getRequest(), timeoutSeconds: 10).statusCode, 200)
    }

    func testTwoInterruptionsAreForgivenByOneBeginJob() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{}") }
        let link = transport(port: server.port)
        link.interrupt()
        link.interrupt()
        link.beginJob()
        XCTAssertEqual(try link.send(getRequest(), timeoutSeconds: 10).statusCode, 200)
    }

    func testInterruptingCancelsTheRequestThatIsWaiting() throws {
        let server = try startServer { request in
            request.target.hasPrefix("/hang") ? nil : mountNetHTTPResponse(body: "{}")
        }
        let link = transport(port: server.port)
        let hanging = getRequest(1, path: "/hang")
        let pending = MountNetBackground { try link.send(hanging, timeoutSeconds: 60) }
        XCTAssertTrue(server.waitForRequests(1), "the request never reached the server")
        link.interrupt()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "the interrupt did not end the wait")
        XCTAssertEqual(mountNetError(result), MountError.timeout(operation: "stopped waiting"))
        // The rest of the job sends nothing; the next job does.
        XCTAssertEqual(mountNetThrown { try link.send(getRequest(2), timeoutSeconds: 5) },
                       MountError.transport(detail: "the command was stopped"))
        link.beginJob()
        XCTAssertEqual(try link.send(getRequest(3), timeoutSeconds: 10).statusCode, 200)
    }

    func testClosingCancelsTheRequestThatIsWaiting() throws {
        let server = try startServer { _ in nil }
        let link = transport(port: server.port)
        let request = getRequest()
        let pending = MountNetBackground { try link.send(request, timeoutSeconds: 60) }
        XCTAssertTrue(server.waitForRequests(1), "the request never reached the server")
        link.close()
        let result = pending.wait(timeout: 20)
        XCTAssertNotNil(result, "closing did not end the wait")
        XCTAssertEqual(mountNetError(result), MountError.timeout(operation: "stopped waiting"))
    }

    func testAfterCloseNothingIsSent() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "{}") }
        let link = transport(port: server.port)
        link.close()
        link.close()
        XCTAssertEqual(mountNetThrown { try link.send(getRequest(), timeoutSeconds: 5) },
                       MountError.transport(detail: "the connection was closed"))
        XCTAssertTrue(server.recorded.isEmpty)
    }

    func testTheClosedCheckComesBeforeTheInterruptionCheck() throws {
        let link = transport(port: 9)
        link.close()
        link.interrupt()
        XCTAssertEqual(mountNetThrown { try link.send(getRequest(), timeoutSeconds: 5) },
                       MountError.transport(detail: "the connection was closed"))
    }
}

// MARK: - Discovery over loopback

final class MountNetDiscoveryNetworkTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups.removeAll()
        super.tearDown()
    }

    private func startServer(_ handler: @escaping MountNetHTTPServer.Handler) throws -> MountNetHTTPServer {
        let server = try MountNetHTTPServer(handler: handler)
        cleanups.append { server.stop() }
        return server
    }

    private static let devicesJSON = """
        {"Value":[{"DeviceName":"Test Mount","DeviceType":"Telescope","DeviceNumber":0,"UniqueID":"A"},\
        {"DeviceName":"Imager","DeviceType":"Camera","DeviceNumber":1,"UniqueID":"B"},\
        {"DeviceName":"Second Mount","DeviceType":"telescope","DeviceNumber":2,"UniqueID":"C"}],\
        "ClientTransactionID":1,"ServerTransactionID":9,"ErrorNumber":0,"ErrorMessage":""}
        """

    // MARK: Telescopes of a server

    func testOnlyTheTelescopesOfTheServerAreListed() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: MountNetDiscoveryNetworkTests.devicesJSON) }
        let found = try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port)
        XCTAssertEqual(found, [
            MountFoundDevice(host: "127.0.0.1", port: server.port, deviceNumber: 0, name: "Test Mount"),
            MountFoundDevice(host: "127.0.0.1", port: server.port, deviceNumber: 2, name: "Second Mount"),
        ])
    }

    func testTheServerIsAskedForItsConfiguredDevices() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: MountNetDiscoveryNetworkTests.devicesJSON) }
        _ = try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port)
        let seen = try XCTUnwrap(server.recorded.first)
        XCTAssertEqual(seen.method, "GET")
        XCTAssertTrue(seen.target.hasPrefix("/management/v1/configureddevices"), seen.target)
    }

    func testAServerWithoutTelescopesGivesAnEmptyList() throws {
        let json = """
            {"Value":[{"DeviceName":"Imager","DeviceType":"Camera","DeviceNumber":0,"UniqueID":"B"}],"ClientTransactionID":1,\
            "ServerTransactionID":1,"ErrorNumber":0,"ErrorMessage":""}
            """
        let server = try startServer { _ in mountNetHTTPResponse(body: json) }
        XCTAssertEqual(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port), [])
    }

    func testAnEmptyDeviceListGivesAnEmptyList() throws {
        let json = "{\"Value\":[],\"ClientTransactionID\":1,\"ServerTransactionID\":1,\"ErrorNumber\":0,\"ErrorMessage\":\"\"}"
        let server = try startServer { _ in mountNetHTTPResponse(body: json) }
        XCTAssertEqual(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port), [])
    }

    func testAnHTTPErrorFromTheServerIsReported() throws {
        let server = try startServer { _ in mountNetHTTPResponse(status: 500, body: "oops", contentType: "text/plain") }
        XCTAssertThrowsError(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port)) { error in
            XCTAssertEqual(error as? MountError, MountError.remote(code: 500, detail: "oops"))
        }
    }

    func testADeviceListThatIsNotAnArrayIsRefused() throws {
        let json = "{\"Value\":\"nothing\",\"ClientTransactionID\":1,\"ServerTransactionID\":1,\"ErrorNumber\":0,\"ErrorMessage\":\"\"}"
        let server = try startServer { _ in mountNetHTTPResponse(body: json) }
        XCTAssertThrowsError(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port)) { error in
            XCTAssertEqual(error as? MountError, MountError.malformedReply(detail: "the device list is not an array"))
        }
    }

    func testAnAnswerThatIsNotJSONIsRefused() throws {
        let server = try startServer { _ in mountNetHTTPResponse(body: "<html>hello</html>", contentType: "text/html") }
        XCTAssertThrowsError(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: server.port)) { error in
            guard case .malformedReply? = error as? MountError else {
                XCTFail("expected a malformed reply, got \(error)")
                return
            }
        }
    }

    func testAnAddressThatCannotBeUsedIsRefusedWithoutAnyTraffic() {
        for (host, port) in [("", 11111), ("127.0.0.1", 0), ("127.0.0.1", 70_000), ("bad host", 11111), ("a/b", 11111)] {
            XCTAssertThrowsError(try MountAlpacaDiscovery.telescopes(host: host, port: port), "\(host):\(port)") { error in
                XCTAssertEqual(error as? MountError, MountError.invalidInput(detail: "the address is not valid"))
            }
        }
    }

    func testAServerThatIsNotThereIsATransportError() throws {
        let port = try mountNetUnusedPort()
        XCTAssertThrowsError(try MountAlpacaDiscovery.telescopes(host: "127.0.0.1", port: port)) { error in
            XCTAssertEqual(error as? MountError, MountError.transport(detail: "the server refused the connection (wrong port?)"))
        }
    }

    // MARK: The subnet probe over loopback

    func testTheProbeCollectsOneReplyPerSender() throws {
        try XCTSkipIf(MountSubnetProbe.localNetworks().isEmpty, "no Wi-Fi or Ethernet interface is up on this machine")
        let server = try MountNetUDPServer()
        cleanups.append { server.stop() }
        server.setAutomaticReply([7, 8, 9])
        // The only address asked is this machine's own loopback address; the subnet is not swept.
        let replies = MountSubnetProbe.run(payload: [1, 2, 3], port: server.port, listenSeconds: 1.5, cancel: MountCancelFlag()) { _ in
            MountSubnetProbe.Plan(addresses: [0x7F00_0001], sweepsSubnet: false)
        }
        XCTAssertEqual(replies.count, 1, "one sender, however many networks asked")
        XCTAssertEqual(replies.first?.host, "127.0.0.1")
        XCTAssertEqual(replies.first?.bytes, [7, 8, 9])
        XCTAssertEqual(server.nextDatagram(timeout: 1), [1, 2, 3])
    }

    func testTheProbeReturnsNothingWhenNobodyAnswers() throws {
        let server = try MountNetUDPServer()
        cleanups.append { server.stop() }
        let replies = MountSubnetProbe.run(payload: [1], port: server.port, listenSeconds: 0.3, cancel: MountCancelFlag()) { _ in
            MountSubnetProbe.Plan(addresses: [0x7F00_0001], sweepsSubnet: false)
        }
        XCTAssertEqual(replies.count, 0)
    }

    func testTheProbeStopsListeningWhenItIsCancelledBeforehand() {
        let flag = MountCancelFlag()
        flag.cancel()
        let started = Date()
        let replies = MountSubnetProbe.run(payload: [1], port: 9, listenSeconds: 60, cancel: flag) { _ in
            MountSubnetProbe.Plan(addresses: [], sweepsSubnet: false)
        }
        XCTAssertEqual(replies.count, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10.0)
    }

    func testTheProbeStopsListeningWhenItIsCancelledWhileItWaits() {
        let flag = MountCancelFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { flag.cancel() }
        let started = Date()
        let replies = MountSubnetProbe.run(payload: [1], port: 9, listenSeconds: 60, cancel: flag) { _ in
            MountSubnetProbe.Plan(addresses: [], sweepsSubnet: false)
        }
        XCTAssertEqual(replies.count, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20.0)
    }
}

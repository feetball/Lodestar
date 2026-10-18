import Foundation

/// Deadline-based framing on top of a `MountTransport`: one exchange is "discard stale input, send, read the reply".
/// Replies may arrive in pieces; bytes that arrive beyond what a read asked for are kept for the next read of the
/// same exchange. Every read has a deadline and a bounded number of receive calls, so nothing here can loop forever.
final class MountLink {
    /// The most receive calls one read may use (a transport that dribbles single bytes still finishes).
    static let maximumReceives = 512

    private let transport: MountTransport
    private let clock: MountClock
    private var buffer: [UInt8] = []

    init(transport: MountTransport, clock: MountClock) {
        self.transport = transport
        self.clock = clock
    }

    private static func wrap(_ error: Error) -> MountError {
        if let mountError = error as? MountError { return mountError }
        return MountError.transport(detail: MountText.sanitized(error.localizedDescription, limit: 120))
    }

    /// Starts an exchange: forgets buffered bytes and drops late input from earlier exchanges.
    func beginExchange() throws {
        buffer = []
        do {
            try transport.discardPendingInput()
        } catch {
            throw MountLink.wrap(error)
        }
    }

    func send(_ bytes: [UInt8]) throws {
        do {
            try transport.send(bytes)
        } catch {
            throw MountLink.wrap(error)
        }
    }

    /// Reads exactly `count` bytes within `timeoutSeconds`.
    func readExactly(_ count: Int, timeoutSeconds: Double, operation: String) throws -> [UInt8] {
        let start = clock.now()
        var receives = 0
        while buffer.count < count {
            receives += 1
            if receives > MountLink.maximumReceives { throw MountError.timeout(operation: operation) }
            try fill(wanted: count - buffer.count, start: start, timeoutSeconds: timeoutSeconds, operation: operation)
        }
        let result = Array(buffer[0 ..< count])
        buffer = Array(buffer[count...])
        return result
    }

    /// Reads up to the next `terminator` within `timeoutSeconds` and returns the bytes before it. Fails with
    /// `MountError.malformedReply` when more than `maximumLength` bytes arrive without a terminator.
    func readUntil(_ terminator: UInt8, maximumLength: Int, timeoutSeconds: Double, operation: String) throws -> [UInt8] {
        let start = clock.now()
        var receives = 0
        while true {
            if let position = buffer.firstIndex(of: terminator) {
                if position > maximumLength { throw MountError.malformedReply(detail: "reply too long") }
                let result = Array(buffer[0 ..< position])
                buffer = Array(buffer[(position + 1)...])
                return result
            }
            if buffer.count > maximumLength { throw MountError.malformedReply(detail: "reply too long") }
            receives += 1
            if receives > MountLink.maximumReceives { throw MountError.timeout(operation: operation) }
            try fill(wanted: maximumLength + 1 - buffer.count, start: start, timeoutSeconds: timeoutSeconds, operation: operation)
        }
    }

    private func fill(wanted: Int, start: Date, timeoutSeconds: Double, operation: String) throws {
        let remaining = timeoutSeconds - clock.now().timeIntervalSince(start)
        if !(remaining > 0) { throw MountError.timeout(operation: operation) }
        let request = max(wanted, 1)
        let chunk: [UInt8]
        do {
            chunk = try transport.receive(maxCount: request, timeoutSeconds: remaining)
        } catch {
            throw MountLink.wrap(error)
        }
        if chunk.isEmpty { throw MountError.transport(detail: "the connection returned no data") }
        if chunk.count > request { throw MountError.transport(detail: "the connection returned more data than requested") }
        buffer += chunk
    }
}

import Foundation

/// A defect the simulators can be told to produce in the next reply to a command (see `MountSimulatedStreamTransport.inject`).
public enum MountSimulatedFault: Hashable, Sendable {
    /// The mount does not answer at all.
    case silence
    /// The reply is replaced by `text` (one character per byte), for garbled or wrong answers.
    case replace(text: String)
    /// Only the first `keep` bytes of the reply arrive.
    case truncate(keep: Int)
    /// The connection drops: the next send or receive fails with `MountError.transport`.
    case disconnect
}

/// The common part of the byte-stream simulators: collects what the client sends, lets the subclass answer complete
/// commands, delivers replies (optionally in small chunks, as a TCP stream may) and charges simulated time for every
/// reply (`latencySeconds`) and for every timeout (the full timeout), so deadlines behave as on a real link.
open class MountSimulatedStreamTransport: MountTransport {
    /// The clock shared with the controller.
    public let clock: ManualMountClock
    /// Simulated round-trip time added to the clock for every reply.
    public let latencySeconds: Double
    /// Deliver replies in pieces of this many bytes per receive call; 0 delivers each reply at once.
    public let chunkSize: Int

    private var inbox: [UInt8] = []
    private var outbox: [UInt8] = []
    private var broken = false
    private var faults: [(String, MountSimulatedFault)] = []
    private var log: [String] = []

    public init(clock: ManualMountClock, latencySeconds: Double = 0.05, chunkSize: Int = 0) {
        self.clock = clock
        self.latencySeconds = latencySeconds
        self.chunkSize = chunkSize
    }

    /// The labels of the commands received so far, oldest first.
    public var commandLog: [String] { log }

    /// Arranges for the next `times` replies to commands whose label starts with `commandPrefix` to suffer `fault`.
    public func inject(_ commandPrefix: String, _ fault: MountSimulatedFault, times: Int = 1) {
        for _ in 0 ..< max(times, 0) { faults.append((commandPrefix, fault)) }
    }

    /// Forgets the recorded command labels.
    public func clearLog() {
        log.removeAll()
    }

    /// Consumes complete commands from the front of `pending` and answers them with `reply`; returns the number of bytes
    /// used (0 if the first command is not complete yet). The base class swallows everything and never answers.
    open func consume(_ pending: [UInt8]) -> Int { pending.count }

    /// Sends the reply `bytes` to the command called `label`, after applying any injected fault.
    public final func reply(_ label: String, _ bytes: [UInt8]) {
        log.append(label)
        var delivered = bytes
        if let index = faults.firstIndex(where: { label.hasPrefix($0.0) }) {
            let fault = faults.remove(at: index).1
            switch fault {
            case .silence:
                return
            case let .replace(text):
                delivered = MountText.latin1Bytes(text)
            case let .truncate(keep):
                delivered = Array(bytes[0 ..< min(max(keep, 0), bytes.count)])
            case .disconnect:
                broken = true
                return
            }
        }
        outbox += delivered
        clock.advance(seconds: latencySeconds)
    }

    /// Records that a command with `label` arrived and needs no reply.
    public final func noReply(_ label: String) {
        log.append(label)
        if let index = faults.firstIndex(where: { label.hasPrefix($0.0) && $0.1 == .disconnect }) {
            faults.remove(at: index)
            broken = true
        }
    }

    public func send(_ bytes: [UInt8]) throws {
        if broken { throw MountError.transport(detail: "connection reset by the simulated mount") }
        inbox += bytes
        while !inbox.isEmpty {
            let used = consume(inbox)
            if used <= 0 { break }
            inbox = Array(inbox[used...])
        }
    }

    public func receive(maxCount: Int, timeoutSeconds: Double) throws -> [UInt8] {
        if broken { throw MountError.transport(detail: "connection reset by the simulated mount") }
        if outbox.isEmpty {
            clock.advance(seconds: timeoutSeconds)
            throw MountError.timeout(operation: "simulated")
        }
        let available = chunkSize > 0 ? min(chunkSize, outbox.count) : outbox.count
        let count = min(maxCount, available)
        let result = Array(outbox[0 ..< count])
        outbox = Array(outbox[count...])
        return result
    }

    public func discardPendingInput() throws {
        outbox = []
    }
}

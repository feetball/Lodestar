import Foundation

/// One command and its reply over a `MountTransport` that may lose or damage datagrams (the mounts' UDP port 11880 answers every
/// command in one datagram, and UDP gives no delivery guarantee). An attempt discards stale input, sends the command and waits for the
/// reply; a missing, truncated or garbled reply, and the errors that a damaged request can cause, make the exchange send the command
/// again, up to `attempts` times. Replies that parse but carry the wrong number of digits count as garbled. A reply that arrives after
/// its attempt timed out is dropped by the next attempt's flush, so a late answer is not taken for the next command's.
final class SkyWatcherLink {
    /// A reply is at most `=` and six digits; anything longer than this without a terminator is garbage.
    private static let maximumReplyBytes = 12

    private let link: MountLink
    private let clock: MountClock
    private let attempts: Int
    private let timeoutSeconds: Double

    /// The datagrams sent so far (retries included).
    private(set) var datagramsSent = 0

    /// How many of them were repetitions of a command that got no usable reply.
    private(set) var retries = 0

    init(transport: MountTransport, clock: MountClock, attempts: Int, timeoutSeconds: Double) {
        link = MountLink(transport: transport, clock: clock)
        self.clock = clock
        self.attempts = attempts
        self.timeoutSeconds = timeoutSeconds
    }

    /// Sends the command and returns the data digits of the reply.
    ///
    /// - Parameter maximumAttempts: how many times the command may be sent; use 1 for commands that must not be repeated blindly
    ///   (nil: the configured number of attempts).
    /// - Throws: `MountError.timeout` if no usable reply arrived, the mapped error for a `!` reply (see `SkyWatcherCodec.error`).
    @discardableResult
    func exchange(_ command: SkyWatcherCommand, axis: SkyWatcherAxis, data: String, operation: String,
                  maximumAttempts: Int? = nil) throws -> String {
        let request = try SkyWatcherCodec.request(command, axis: axis, data: data)
        var last: MountError = MountError.timeout(operation: operation)
        let limit = max(1, min(maximumAttempts ?? attempts, attempts))
        for attempt in 1 ... limit {
            if attempt > 1 { retries += 1 }
            try link.beginExchange()
            try link.send(request)
            datagramsSent += 1
            do {
                let line = try link.readUntil(UInt8(SkyWatcherCodec.terminator), maximumLength: SkyWatcherLink.maximumReplyBytes,
                                              timeoutSeconds: timeoutSeconds, operation: operation)
                switch try SkyWatcherCodec.parseReply(line) {
                case let .success(payload):
                    if command.replyDigits >= 0 && payload.unicodeScalars.count != command.replyDigits {
                        last = MountError.malformedReply(detail: "\(operation): wrong reply length")
                    } else {
                        return payload
                    }
                case let .failure(code):
                    if !SkyWatcherCodec.isPossiblyCausedByDamagedRequest(code) { throw SkyWatcherCodec.error(code) }
                    last = SkyWatcherCodec.error(code)
                }
            } catch let error as MountError {
                switch error {
                case .timeout, .malformedReply: last = error
                default: throw error
                }
            }
        }
        throw last
    }

    /// Pauses for `seconds`.
    func pause(_ seconds: Double) {
        clock.sleep(seconds: seconds)
    }
}

import Foundation

/// The engine's source of time. Timeouts, slew watching and sky calculations all use it, so tests can drive a
/// `ManualMountClock` instead of waiting.
public protocol MountClock: AnyObject {
    /// The current time.
    func now() -> Date
    /// Blocks the calling thread for `seconds` (a manual clock advances instead).
    func sleep(seconds: Double)
}

/// The real clock: `Date()` and `Thread.sleep`.
public final class SystemMountClock: MountClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(seconds: Double) {
        guard seconds > 0 else { return }
        Thread.sleep(forTimeInterval: min(seconds, 3600))
    }
}

/// A clock that only moves when told to: `sleep` and `advance` add time. Used by the simulators and tests.
public final class ManualMountClock: MountClock {
    private var seconds: Double

    public init(start: Date) { seconds = start.timeIntervalSince1970 }

    public func now() -> Date { Date(timeIntervalSince1970: seconds) }

    public func sleep(seconds: Double) { advance(seconds: seconds) }

    /// Moves the clock forward by `seconds`; negative, NaN and infinite values are ignored.
    public func advance(seconds: Double) {
        if seconds.isFinite && seconds > 0 { self.seconds += seconds }
    }

    /// The clock's reading as seconds since 1970 (without the rounding of `now`).
    public var secondsSince1970: Double { seconds }
}

/// A byte-stream link to a mount: a TCP socket, a UDP socket "connected" to the mount, or a serial port. The apps
/// implement it; the engine only calls these three methods, one exchange at a time from one thread.
///
/// Implementations throw `MountError.timeout` when nothing arrives in time and `MountError.transport` for I/O errors.
public protocol MountTransport: AnyObject {
    /// Sends all of `bytes` (one datagram for UDP).
    func send(_ bytes: [UInt8]) throws

    /// Waits up to `timeoutSeconds` for input and returns what has arrived, at least one and at most `maxCount` bytes.
    ///
    /// - Throws: `MountError.timeout` if nothing arrived.
    func receive(maxCount: Int, timeoutSeconds: Double) throws -> [UInt8]

    /// Drops any input that has arrived but was not read (late replies of earlier commands).
    func discardPendingInput() throws
}

/// An HTTP client for one Alpaca server, as the apps implement it: it sends `AlpacaHTTPRequest.method` to
/// `AlpacaEndpoint.baseURL` + `AlpacaHTTPRequest.target` with `AlpacaHTTPRequest.body` and
/// `AlpacaHTTPRequest.contentType`, and returns the status code and the body decoded as UTF-8.
///
/// Implementations throw `MountError.timeout` when the server does not answer within the timeout and
/// `MountError.transport` for connection failures. A non-200 status is a normal return value, not an error.
public protocol AlpacaTransport: AnyObject {
    /// Performs one request/response exchange, waiting at most `timeoutSeconds`.
    func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse
}

import Foundation

/// One protocol session with a mount, as the `MountController` uses it. Coordinates are in the driver's own
/// `epoch`; the controller converts from and to J2000. Drivers perform one blocking exchange per call, validate every
/// reply and throw `MountError`; they never retry on their own (the controller decides) except for the protocol's own
/// "busy, send again" convention.
///
/// Not thread safe: use one driver, its transport and its controller from one thread (or one queue) at a time.
public protocol MountDriver: AnyObject {
    /// The protocol this driver speaks.
    var kind: MountProtocol { get }

    /// The frame of the coordinates passed to and returned by the other methods. Final after `connect`.
    var epoch: MountEpoch { get }

    /// Performs the handshake (version, capabilities, first position) and returns what the mount can do.
    func connect() throws -> MountCapabilities

    /// Ends the session; no exchange failures are reported.
    func disconnect()

    /// The place the mount points at.
    func readPosition() throws -> EquatorialCoordinate

    /// Whether the mount is executing a slew.
    func readSlewing() throws -> Bool

    /// Whether the mount is tracking; nil if the protocol cannot tell.
    func readTracking() throws -> Bool?

    /// Whether the mount is aligned (a star alignment is complete); nil if the protocol cannot tell.
    func readAligned() throws -> Bool?

    /// Starts a slew to `target`; returns once the mount has accepted it.
    func slew(to target: EquatorialCoordinate) throws

    /// Tells the mount that it points at `target` now.
    func sync(to target: EquatorialCoordinate) throws

    /// Stops a slew (and any nudge).
    func abort() throws

    /// Switches tracking on or off.
    func setTracking(_ enabled: Bool) throws

    /// Starts moving in `direction` at `rate`. The mount keeps moving until `stopNudge`, except where the protocol
    /// has timed pulses, which end by themselves after `durationSeconds`.
    func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws

    /// Stops the nudge in `direction`.
    func stopNudge(direction: MountNudgeDirection) throws

    /// Sets the mount's site and clock; the clock is set to UTC with no zone offset.
    func setSiteAndTime(location: GeographicLocation, date: Date) throws
}

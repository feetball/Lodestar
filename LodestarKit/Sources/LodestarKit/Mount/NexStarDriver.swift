import Foundation

/// Settings of a `NexStarDriver`.
///
/// Values are clamped to their ranges when the configuration is created.
public struct NexStarConfiguration: Hashable, Sendable {
    /// The frame of the coordinates on the wire. Nil (the default) picks it from the controller family at connect time:
    /// Sky-Watcher SynScan firmware 3.37 / 4.37.03 or later documents J2000 for GOTO, sync and position replies
    /// ("SynScan Serial Communication Protocol" 3.3), Celestron hand controls take the current epoch ("JNow", mean of
    /// date). Set it to override, for example `MountEpoch.meanOfDate` for a SynScan hand control with old firmware.
    public let epoch: MountEpoch?
    /// How long one command may take (1 to 30 s). Celestron documents up to 3.5 s, SynScan up to 5 s, in the worst case.
    public let exchangeTimeoutSeconds: Double
    /// Use the 32-bit position commands; nil decides from the firmware version (Celestron 1.6 and later, always for SynScan).
    public let usesPrecisePositions: Bool?
    /// The mode `T` sets when tracking is switched on and the mount has not reported a running mode. Nil (the default)
    /// picks it from the model number the mount reports (`NexStarCodec.isEquatorialModel`): equatorial for the mounts known
    /// to be German equatorial, alt-azimuth for every other model, including those the list does not know. Set it to
    /// override, for example `.eqNorth` for a fork mount on a wedge. `.off` is not a mode to switch on and counts as `.altAz`.
    public let preferredTrackingMode: NexStarTrackingMode?
    /// Swap the sense of east and west nudges (the sign of the right ascension / azimuth axis is not documented per mount).
    public let invertsEastWest: Bool

    /// Automatic epoch, 5.5 s timeout, tracking mode from the mount's model, INDI's axis signs.
    public static let standard = NexStarConfiguration()

    /// Creates a configuration; out-of-range values are clamped.
    public init(epoch: MountEpoch? = nil, exchangeTimeoutSeconds: Double = 5.5, usesPrecisePositions: Bool? = nil,
                preferredTrackingMode: NexStarTrackingMode? = nil, invertsEastWest: Bool = false) {
        self.epoch = epoch
        self.exchangeTimeoutSeconds = exchangeTimeoutSeconds.isNaN ? 5.5 : min(max(exchangeTimeoutSeconds, 1.0), 30.0)
        self.usesPrecisePositions = usesPrecisePositions
        self.preferredTrackingMode = preferredTrackingMode.map { $0 == .off ? .altAz : $0 }
        self.invertsEastWest = invertsEastWest
    }
}

/// Drives a Celestron NexStar or Sky-Watcher SynScan hand control over a byte-stream `MountTransport` (serial bridge,
/// or the SynScan Wi-Fi adapter's UDP/TCP relay). See `NexStarCodec` for the command reference.
///
/// GOTO and sync only work once the hand control is aligned ("J" answers 1); the driver refuses to slew otherwise.
/// Manual nudges use the variable-rate pass-through slews; as the protocol notes recommend, tracking is switched off for
/// the duration of a nudge and restored afterwards.
public final class NexStarDriver: MountDriver {
    private let link: MountLink

    /// The settings in use.
    public let configuration: NexStarConfiguration

    private var resolvedEpoch: MountEpoch
    private var precise: Bool
    /// The last mode the mount reported while it was tracking; nil until it has reported one.
    private var rememberedTrackingMode: NexStarTrackingMode?
    /// True if the model number read by `connect` is that of a German equatorial mount.
    private var isEquatorialModel = false
    /// The latitude last sent to the mount by `setSiteAndTime`; nil until then.
    private var siteLatitude: Double?
    private var trackingToRestore: NexStarTrackingMode?
    private var activeNudges: [MountNudgeDirection] = []
    private var canReadTracking = true
    private var canSetTime = true

    /// The firmware version found by `connect`; nil before.
    public private(set) var version: NexStarVersion?

    public var kind: MountProtocol { .nexstar }

    public var epoch: MountEpoch { resolvedEpoch }

    public init(transport: MountTransport, clock: MountClock, configuration: NexStarConfiguration = .standard) {
        link = MountLink(transport: transport, clock: clock)
        self.configuration = configuration
        resolvedEpoch = configuration.epoch ?? .meanOfDate
        precise = configuration.usesPrecisePositions ?? true
    }

    public func connect() throws -> MountCapabilities {
        let found = try readVersion()
        version = found
        resolvedEpoch = configuration.epoch ?? (found.flavor == .synscan ? .j2000 : .meanOfDate)
        let isSynScan = found.flavor == .synscan
        precise = configuration.usesPrecisePositions ?? (isSynScan || found.isAtLeast(1, 6))
        canReadTracking = isSynScan || found.isAtLeast(2, 3)
        canSetTime = isSynScan || found.isAtLeast(2, 3)

        var name = isSynScan ? "Sky-Watcher SynScan" : "Celestron NexStar"
        isEquatorialModel = false
        do {
            let model = try transact(NexStarCodec.getModel, payloadLength: 1, operation: "read model")
            name = NexStarCodec.modelName(Int(model[0]), flavor: found.flavor)
            isEquatorialModel = NexStarCodec.isEquatorialModel(Int(model[0]), flavor: found.flavor)
        } catch MountError.timeout {
            // The model command is optional on old firmware.
        } catch MountError.malformedReply {
            // Keep the generic name.
        }
        var aligned: Bool?
        do {
            aligned = try readAlignmentFlag()
        } catch MountError.timeout {
            aligned = nil
        }
        if canReadTracking {
            let mode = try readTrackingMode()
            if mode != .off { rememberedTrackingMode = mode }
        }
        do {
            _ = try readPosition()
        } catch MountError.malformedReply(let detail) {
            // Before an alignment the position values are not meaningful and may not even be valid coordinates.
            if aligned != false { throw MountError.malformedReply(detail: detail) }
        }

        let canSync: Bool
        if isSynScan {
            canSync = found.major == 3 ? found.isAtLeast(3, 37) : found.isAtLeast(4, 37, 3)
        } else {
            canSync = found.isAtLeast(4, 10)
        }
        let canPassThrough: Bool
        if isSynScan {
            canPassThrough = found.major == 3 ? found.isAtLeast(3, 3) : found.isAtLeast(4, 1, 1)
        } else {
            canPassThrough = found.isAtLeast(1, 6)
        }
        return MountCapabilities(
            kind: .nexstar, name: "\(name) \(found.description)", firmware: found.description, canSlew: true, canSync: canSync,
            canAbort: true, canSetTracking: isSynScan || found.isAtLeast(1, 6), canNudge: canPassThrough,
            canSetSiteAndTime: canSetTime, gotoNeedsAlignment: true, isAligned: aligned)
    }

    public func disconnect() {
        activeNudges.removeAll()
    }

    public func readPosition() throws -> EquatorialCoordinate {
        let payload = try transact(NexStarCodec.getPosition(precise: precise), payloadLength: precise ? 17 : 9,
                                   operation: "read position")
        return try NexStarCodec.decodePosition(MountText.latin1(payload))
    }

    public func readSlewing() throws -> Bool {
        let reply = try transact(NexStarCodec.getGotoInProgress, payloadLength: 1, operation: "read slew state")
        switch reply[0] {
        case UInt8(ascii: "1"): return true
        case UInt8(ascii: "0"): return false
        default: throw MountError.malformedReply(detail: "slew state")
        }
    }

    public func readTracking() throws -> Bool? {
        if !canReadTracking { return nil }
        return try readTrackingMode() != .off
    }

    public func readAligned() throws -> Bool? {
        try readAlignmentFlag()
    }

    public func slew(to target: EquatorialCoordinate) throws {
        try requireFinite(target)
        if !(try readAlignmentFlag()) { throw MountError.notAligned }
        try expectAcknowledge(NexStarCodec.goto(target, precise: precise), operation: "start slew")
    }

    public func sync(to target: EquatorialCoordinate) throws {
        try requireFinite(target)
        try expectAcknowledge(NexStarCodec.sync(target, precise: precise), operation: "sync")
    }

    public func abort() throws {
        try expectAcknowledge(NexStarCodec.cancelGoto, operation: "stop slew")
    }

    public func setTracking(_ enabled: Bool) throws {
        let mode = enabled ? trackingModeToSwitchOn() : NexStarTrackingMode.off
        try expectAcknowledge(NexStarCodec.setTrackingMode(mode), operation: "set tracking")
        if enabled { trackingToRestore = nil }
    }

    public func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
        if activeNudges.isEmpty && canReadTracking {
            let mode = try readTrackingMode()
            if mode != .off {
                trackingToRestore = mode
                try expectAcknowledge(NexStarCodec.setTrackingMode(.off), operation: "pause tracking")
            }
        }
        let command = try NexStarCodec.variableRateSlew(axis: axis(direction), positive: isPositive(direction),
                                                        arcsecondsPerSecond: rate.degreesPerSecond * 3600.0)
        try expectPassthroughAcknowledge(command, operation: "start move")
        if !activeNudges.contains(direction) { activeNudges.append(direction) }
    }

    public func stopNudge(direction: MountNudgeDirection) throws {
        try expectPassthroughAcknowledge(
            NexStarCodec.fixedRateSlew(axis: axis(direction), positive: isPositive(direction), rate: 0), operation: "stop move")
        activeNudges.removeAll { $0 == direction }
        if activeNudges.isEmpty, let restore = trackingToRestore {
            try expectAcknowledge(NexStarCodec.setTrackingMode(restore), operation: "resume tracking")
            trackingToRestore = nil
        }
    }

    public func setSiteAndTime(location: GeographicLocation, date: Date) throws {
        if !canSetTime { throw MountError.notSupported(feature: .siteAndTime) }
        guard let fields = MountCalendar.fields(for: date) else {
            throw MountError.invalidInput(detail: "the date is outside 1970 to 9999")
        }
        try expectAcknowledge(NexStarCodec.setLocation(location), operation: "set location")
        siteLatitude = location.latitude
        try expectAcknowledge(NexStarCodec.setTime(fields, zoneOffsetHours: 0, daylightSaving: false), operation: "set time")
    }

    // MARK: Exchanges

    /// The mode `T` sets when tracking is switched on. In order: the mode the mount was seen tracking in, the configured
    /// mode, then the mode that fits the mount's model. A German equatorial mount gets the equatorial mode and every other
    /// mount, or one whose model is unknown, gets alt-azimuth tracking.
    ///
    /// SynScan has one equatorial mode (`T` 2; 3 is sidereal with PEC), so it is used in both hemispheres. A Celestron
    /// mount has an equatorial mode for each hemisphere: south when the latitude sent by `setSiteAndTime` is negative. Until
    /// a site has been sent the hemisphere is not known and north is assumed.
    private func trackingModeToSwitchOn() -> NexStarTrackingMode {
        if let remembered = rememberedTrackingMode { return remembered }
        if let configured = configuration.preferredTrackingMode { return configured }
        guard isEquatorialModel else { return .altAz }
        if version?.flavor == .synscan { return .eqNorth }
        return (siteLatitude ?? 0.0) < 0.0 ? .eqSouth : .eqNorth
    }

    private func requireFinite(_ target: EquatorialCoordinate) throws {
        if !target.rightAscension.isFinite || !target.declination.isFinite {
            throw MountError.invalidInput(detail: "the target coordinates are not numbers")
        }
    }

    private func axis(_ direction: MountNudgeDirection) -> NexStarAxis {
        switch direction {
        case .north, .south: .altitudeDeclination
        case .east, .west: .azimuthRightAscension
        }
    }

    /// North and west are the positive directions of the declination and right ascension axes (as in INDI's Celestron driver).
    private func isPositive(_ direction: MountNudgeDirection) -> Bool {
        switch direction {
        case .north: true
        case .south: false
        case .west: !configuration.invertsEastWest
        case .east: configuration.invertsEastWest
        }
    }

    /// Sends `command` and reads `payloadLength` bytes plus the `#`; returns the payload.
    private func transact(_ command: [UInt8], payloadLength: Int, operation: String) throws -> [UInt8] {
        try link.beginExchange()
        try link.send(command)
        let reply = try link.readExactly(payloadLength + 1, timeoutSeconds: configuration.exchangeTimeoutSeconds, operation: operation)
        if Int(reply[payloadLength]) != NexStarCodec.terminator {
            throw MountError.malformedReply(detail: "\(operation): reply not terminated")
        }
        return Array(reply[0 ..< payloadLength])
    }

    /// A command whose whole reply is `#`.
    private func expectAcknowledge(_ command: [UInt8], operation: String) throws {
        try link.beginExchange()
        try link.send(command)
        let reply = try link.readExactly(1, timeoutSeconds: configuration.exchangeTimeoutSeconds, operation: operation)
        if Int(reply[0]) != NexStarCodec.terminator { throw MountError.malformedReply(detail: "\(operation): no acknowledgement") }
    }

    /// A pass-through command whose answer is `#`; a different first byte means the motor controller did not take part
    /// (the hand control then sends one extra byte before the `#`).
    private func expectPassthroughAcknowledge(_ command: [UInt8], operation: String) throws {
        try link.beginExchange()
        try link.send(command)
        let reply = try link.readExactly(1, timeoutSeconds: configuration.exchangeTimeoutSeconds, operation: operation)
        if Int(reply[0]) != NexStarCodec.terminator {
            throw MountError.rejected(detail: "the motor controller did not answer (\(operation))")
        }
    }

    private func readVersion() throws -> NexStarVersion {
        try link.beginExchange()
        try link.send(NexStarCodec.getVersion)
        let timeout = configuration.exchangeTimeoutSeconds
        let head = try link.readExactly(3, timeoutSeconds: timeout, operation: "read version")
        if Int(head[2]) == NexStarCodec.terminator { return try NexStarCodec.decodeVersion(Array(head[0 ..< 2])) }
        let tail = try link.readExactly(4, timeoutSeconds: timeout, operation: "read version")
        let whole = head + tail
        if Int(whole[6]) != NexStarCodec.terminator { throw MountError.malformedReply(detail: "version: reply not terminated") }
        return try NexStarCodec.decodeVersion(Array(whole[0 ..< 6]))
    }

    private func readAlignmentFlag() throws -> Bool {
        let reply = try transact(NexStarCodec.getAlignmentComplete, payloadLength: 1, operation: "read alignment")
        switch reply[0] {
        case 1: return true
        case 0: return false
        default: throw MountError.malformedReply(detail: "alignment")
        }
    }

    private func readTrackingMode() throws -> NexStarTrackingMode {
        let reply = try transact(NexStarCodec.getTrackingMode, payloadLength: 1, operation: "read tracking")
        guard let mode = NexStarTrackingMode.fromCode(Int(reply[0])) else { throw MountError.malformedReply(detail: "tracking mode") }
        return mode
    }
}

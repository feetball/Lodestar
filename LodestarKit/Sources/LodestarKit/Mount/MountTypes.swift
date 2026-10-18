import Foundation

/// The control protocols the engine speaks.
public enum MountProtocol: String, CaseIterable, Codable, Hashable, Sendable {
    /// Meade LX200 serial command protocol (also OnStep and many Wi-Fi bridges), usually over a TCP socket.
    case lx200
    /// Celestron NexStar / Sky-Watcher SynScan hand-controller protocol, over a TCP or UDP socket.
    case nexstar
    /// ASCOM Alpaca Telescope interface, REST over HTTP.
    case alpaca
    /// Sky-Watcher motor controller protocol over UDP, as spoken by the built-in Wi-Fi of the AZ-GTi, the Star Adventurer GTi and
    /// the Wi-Fi dongles of EQ mounts (see `SkyWatcherDriver`); "Sky-Watcher Wi-Fi (AZ-GTi, Star Adventurer GTi)" in menus.
    case skywatcher
}

/// Something a mount may not be able to do, named in `MountError.notSupported`.
public enum MountFeature: String, CaseIterable, Codable, Hashable, Sendable {
    /// Slewing to coordinates.
    case slew
    /// Telling the mount where it is pointing.
    case sync
    /// Stopping a slew.
    case abort
    /// Switching tracking on and off.
    case tracking
    /// Short manual moves.
    case nudge
    /// Setting the mount's site and clock.
    case siteAndTime
    /// The mount's coordinate system.
    case coordinateSystem
    /// An operation the protocol layer could not attribute to a feature.
    case other

    /// Words that finish the sentence "This mount doesn't support …".
    public var displayName: String {
        switch self {
        case .slew: "slewing to coordinates"
        case .sync: "syncing to a position"
        case .abort: "stopping a slew"
        case .tracking: "switching tracking on and off"
        case .nudge: "manual moves"
        case .siteAndTime: "setting the site and time"
        case .coordinateSystem: "this coordinate system"
        case .other: "this operation"
        }
    }
}

/// Why a mount operation failed. Every case has a message a photographer can read (`userMessage`, also the
/// `errorDescription`); the engine throws these and never traps.
public enum MountError: Error, Hashable, Sendable, LocalizedError {
    /// There is no open session with the mount.
    case notConnected
    /// The mount cannot accept the command right now.
    case busy
    /// A slew is already running; abort it before starting another.
    case slewInProgress
    /// Lodestar's own safety check: the target is below the configured altitude limit.
    case belowHorizonLimit(altitude: Double, limit: Double)
    /// The mount refused the target because it is below the mount's own horizon limit.
    case mountHorizonLimit
    /// The mount refused the target because it is above the mount's overhead limit.
    case mountOverheadLimit
    /// The mount refused the target because it is outside its movement limits (meridian, declination, axis).
    case outsideMountLimits
    /// The mount needs a star alignment before it can slew.
    case notAligned
    /// The mount is parked.
    case parked
    /// The mount's controller is in standby.
    case standby
    /// Tracking is off and the operation needs it on.
    case notTracking
    /// The mount or its protocol does not offer `feature`.
    case notSupported(feature: MountFeature)
    /// The mount reported a hardware fault.
    case hardwareFault(detail: String)
    /// The mount rejected a value or command.
    case rejected(detail: String)
    /// The mount did not answer within the timeout.
    case timeout(operation: String)
    /// A slew did not finish within `seconds` and was stopped.
    case slewTimeout(seconds: Double)
    /// The mount stopped `remainingDegrees` short of the target without being told to.
    case slewStopped(remainingDegrees: Double)
    /// A sync would move the mount's idea of its position by `offsetDegrees`, more than the allowed `limitDegrees`.
    case syncOffsetTooLarge(offsetDegrees: Double, limitDegrees: Double)
    /// Repeated failures ended the session.
    case connectionLost
    /// The transport reported an I/O failure.
    case transport(detail: String)
    /// The mount's reply failed validation (wrong length, bad characters, out of range, wrong transaction).
    case malformedReply(detail: String)
    /// The mount reported error `code` with `detail` that has no more specific case.
    case remote(code: Int, detail: String)
    /// The target or another input is not a usable value.
    case invalidInput(detail: String)
    /// The mount reports a coordinate system the engine cannot convert to (code from the protocol).
    case unsupportedCoordinateSystem(code: Int)

    /// The text to show the user.
    public var userMessage: String {
        switch self {
        case .notConnected: "The mount is not connected."
        case .busy: "The mount is busy. Try again in a moment."
        case .slewInProgress: "The mount is already slewing. Stop it before starting another move."
        case let .belowHorizonLimit(altitude, limit):
            "The target is at \(String(format: "%.1f", altitude))°, below your altitude limit of "
                + "\(String(format: "%.1f", limit))°. Lodestar won't slew there."
        case .mountHorizonLimit: "The target is below the mount's horizon limit."
        case .mountOverheadLimit: "The target is above the mount's overhead limit."
        case .outsideMountLimits: "The target is outside the mount's movement limits."
        case .notAligned: "The mount is not aligned. Do a star alignment on the mount first, then try again."
        case .parked: "The mount is parked. Unpark it first."
        case .standby: "The mount is in standby. Wake it up first."
        case .notTracking: "Tracking is off. Turn tracking on first."
        case let .notSupported(feature): "This mount doesn't support \(feature.displayName)."
        case let .hardwareFault(detail):
            detail.isEmpty ? "The mount reported a hardware fault." : "The mount reported a hardware fault: \(detail)."
        case let .rejected(detail):
            detail.isEmpty ? "The mount rejected the command." : "The mount rejected the command: \(detail)."
        case let .timeout(operation): "The mount didn't answer in time (\(operation))."
        case let .slewTimeout(seconds):
            "The slew did not finish within \(String(format: "%.0f", seconds)) s, so it was stopped."
        case let .slewStopped(remainingDegrees):
            "The mount stopped \(String(format: "%.1f", remainingDegrees))° short of the target."
        case let .syncOffsetTooLarge(offsetDegrees, limitDegrees):
            "The mount points \(String(format: "%.1f", offsetDegrees))° away from that star, more than the allowed "
                + "\(String(format: "%.0f", limitDegrees))°. Check that you centred the right star."
        case .connectionLost: "The connection to the mount was lost."
        case let .transport(detail): "Could not talk to the mount: \(detail)."
        case let .malformedReply(detail): "The mount sent an unexpected reply (\(detail))."
        case let .remote(code, detail):
            detail.isEmpty ? "The mount reported error \(code)." : "The mount reported error \(code): \(detail)."
        case let .invalidInput(detail): "That value can't be used: \(detail)."
        case let .unsupportedCoordinateSystem(code):
            "The mount uses a coordinate system Lodestar can't convert to (code \(code))."
        }
    }

    public var errorDescription: String? { userMessage }

    /// True for failures of the link rather than refusals by the mount: timeouts, I/O errors, garbled replies.
    public var isCommunicationFailure: Bool {
        switch self {
        case .timeout, .transport, .malformedReply, .connectionLost: true
        default: false
        }
    }
}

/// What the connected mount can do, found out by the connection handshake.
public struct MountCapabilities: Hashable, Sendable {
    /// The protocol in use.
    public let kind: MountProtocol
    /// A display name: product name and firmware as the mount reports it; length-capped.
    public let name: String
    /// The firmware version text, if the mount reports one.
    public let firmware: String?
    /// Slewing to coordinates is available.
    public let canSlew: Bool
    /// Sync is available.
    public let canSync: Bool
    /// A slew can be stopped.
    public let canAbort: Bool
    /// Tracking can be switched on and off.
    public let canSetTracking: Bool
    /// Manual nudges are available.
    public let canNudge: Bool
    /// The site and clock can be set.
    public let canSetSiteAndTime: Bool
    /// A slew is refused (or silently ignored) by the mount until it is star-aligned.
    public let gotoNeedsAlignment: Bool
    /// Whether the mount reports being aligned; nil if it cannot tell.
    public let isAligned: Bool?

    public init(kind: MountProtocol, name: String, firmware: String?, canSlew: Bool, canSync: Bool, canAbort: Bool,
                canSetTracking: Bool, canNudge: Bool, canSetSiteAndTime: Bool, gotoNeedsAlignment: Bool, isAligned: Bool?) {
        self.kind = kind
        self.name = name
        self.firmware = firmware
        self.canSlew = canSlew
        self.canSync = canSync
        self.canAbort = canAbort
        self.canSetTracking = canSetTracking
        self.canNudge = canNudge
        self.canSetSiteAndTime = canSetSiteAndTime
        self.gotoNeedsAlignment = gotoNeedsAlignment
        self.isAligned = isAligned
    }
}

/// A direction on the sky in which a nudge moves the mount (north = +declination or up, east = +right ascension).
public enum MountNudgeDirection: String, CaseIterable, Codable, Hashable, Sendable {
    /// Towards increasing declination (up on an alt-azimuth mount).
    case north
    /// Towards decreasing declination (down).
    case south
    /// Towards increasing right ascension (right when facing south in the northern hemisphere).
    case east
    /// Towards decreasing right ascension.
    case west
}

/// How fast a nudge moves, as a multiple of the sidereal rate.
public enum MountNudgeRate: String, CaseIterable, Codable, Hashable, Sendable {
    /// The mount's guide rate: for the finest corrections.
    case guide
    /// The centring rate: fine framing adjustments.
    case center
    /// The find rate: moving across a field.
    case find
    /// A fast rate for larger moves.
    case slew

    /// The rate as a multiple of the sidereal rate (15.041 arcseconds per second).
    public var siderealMultiple: Double {
        switch self {
        case .guide: 1.0
        case .center: 8.0
        case .find: 32.0
        case .slew: 128.0
        }
    }

    /// The sidereal rate in degrees per second (360.98564736629 degrees per mean solar day).
    public static let siderealDegreesPerSecond: Double = 360.98564736629 / 86_400.0

    /// The rate in degrees per second.
    public var degreesPerSecond: Double { siderealMultiple * MountNudgeRate.siderealDegreesPerSecond }
}

/// What the controller is doing.
public enum MountPhase: String, CaseIterable, Codable, Hashable, Sendable {
    /// No session.
    case disconnected
    /// Connected and not moving under the controller's command.
    case idle
    /// A slew is in progress.
    case slewing
    /// A manual nudge is in progress.
    case nudging
}

/// How the last slew ended.
public enum MountSlewOutcome: Hashable, Sendable {
    /// The mount stopped within the tolerance of the target, `separation` degrees away.
    case arrived(separation: Double)
    /// The user aborted the slew.
    case aborted
    /// The slew failed; `error` says why.
    case failed(error: MountError)
}

/// A snapshot of the controller for the UI.
public struct MountStatus: Hashable, Sendable {
    /// What the controller is doing.
    public let phase: MountPhase
    /// Where the mount points, as a J2000 place; nil until the first reading.
    public let position: EquatorialCoordinate?
    /// The J2000 target of the current or last slew.
    public let target: EquatorialCoordinate?
    /// Degrees between `position` and `target`; nil when either is unknown.
    public let separation: Double?
    /// Whether the mount is tracking; nil if the protocol cannot tell.
    public let isTracking: Bool?
    /// Whether the mount reports being aligned; nil if it cannot tell. Refreshed by `MountController.poll` until it is
    /// true, so a screen can ask the user to align the mount and notice when it is done.
    public let isAligned: Bool?
    /// The mount's own "slewing" flag at the last reading; nil before the first reading.
    public let isMoving: Bool?
    /// Seconds since the current slew started; nil when not slewing.
    public let slewElapsedSeconds: Double?
    /// How the last finished slew ended; cleared when a new slew starts.
    public let outcome: MountSlewOutcome?
    /// The last communication error, cleared by the next successful poll.
    public let lastError: MountError?
    /// When the status was last refreshed.
    public let updated: Date?

    public init(phase: MountPhase, position: EquatorialCoordinate?, target: EquatorialCoordinate?, separation: Double?,
                isTracking: Bool?, isAligned: Bool?, isMoving: Bool?, slewElapsedSeconds: Double?,
                outcome: MountSlewOutcome?, lastError: MountError?, updated: Date?) {
        self.phase = phase
        self.position = position
        self.target = target
        self.separation = separation
        self.isTracking = isTracking
        self.isAligned = isAligned
        self.isMoving = isMoving
        self.slewElapsedSeconds = slewElapsedSeconds
        self.outcome = outcome
        self.lastError = lastError
        self.updated = updated
    }

    /// The status of a controller that has no session.
    public static let disconnected = MountStatus(
        phase: .disconnected, position: nil, target: nil, separation: nil, isTracking: nil, isAligned: nil, isMoving: nil,
        slewElapsedSeconds: nil, outcome: nil, lastError: nil, updated: nil)
}

/// The result of a successful sync.
public struct MountSyncResult: Hashable, Sendable {
    /// Degrees between where the mount believed it pointed and the synced position.
    public let offsetDegrees: Double

    public init(offsetDegrees: Double) { self.offsetDegrees = offsetDegrees }
}

/// Limits and timings of the controller. Out-of-range or non-finite values are replaced by the nearest allowed value
/// (the default for NaN), so the controller never runs with an unbounded wait.
public struct MountSettings: Hashable, Sendable {
    /// Targets lower than this altitude (degrees, geometric, no refraction) are refused.
    public let altitudeLimit: Double
    /// The target must also stay above the limit this many seconds from now (the slew takes time).
    public let horizonLookaheadSeconds: Double
    /// A slew that has not finished after this many seconds is stopped.
    public let maximumSlewSeconds: Double
    /// After a slew command the mount may report "not slewing" for this long before the slew counts as not started.
    public let slewStartGraceSeconds: Double
    /// The mount counts as arrived when it stops within this many degrees of the target.
    public let arrivalToleranceDegrees: Double
    /// The time between polls used by `MountController.awaitSettled`.
    public let pollIntervalSeconds: Double
    /// This many failed polls in a row end the session.
    public let maximumConsecutiveFailures: Int
    /// The longest nudge.
    public let maximumNudgeSeconds: Double
    /// A sync that would move the mount by more than this many degrees is refused (180 allows everything).
    public let maximumSyncOffsetDegrees: Double

    /// The default settings.
    public static let standard = MountSettings()

    /// Creates settings; values are clamped to their allowed ranges (see the documentation of each property).
    public init(altitudeLimit: Double = 0, horizonLookaheadSeconds: Double = 60, maximumSlewSeconds: Double = 300,
                slewStartGraceSeconds: Double = 5, arrivalToleranceDegrees: Double = 0.25, pollIntervalSeconds: Double = 1,
                maximumConsecutiveFailures: Int = 3, maximumNudgeSeconds: Double = 10, maximumSyncOffsetDegrees: Double = 180) {
        self.altitudeLimit = MountSettings.sane(altitudeLimit, 0, -10, 60)
        self.horizonLookaheadSeconds = MountSettings.sane(horizonLookaheadSeconds, 60, 0, 1800)
        self.maximumSlewSeconds = MountSettings.sane(maximumSlewSeconds, 300, 10, 3600)
        self.slewStartGraceSeconds = MountSettings.sane(slewStartGraceSeconds, 5, 0, 60)
        self.arrivalToleranceDegrees = MountSettings.sane(arrivalToleranceDegrees, 0.25, 0.01, 5)
        self.pollIntervalSeconds = MountSettings.sane(pollIntervalSeconds, 1, 0.1, 30)
        self.maximumConsecutiveFailures = min(max(maximumConsecutiveFailures, 1), 10)
        self.maximumNudgeSeconds = MountSettings.sane(maximumNudgeSeconds, 10, 0.1, 30)
        self.maximumSyncOffsetDegrees = MountSettings.sane(maximumSyncOffsetDegrees, 180, 0.1, 180)
    }

    private static func sane(_ value: Double, _ defaultValue: Double, _ lower: Double, _ upper: Double) -> Double {
        value.isNaN ? defaultValue : min(max(value, lower), upper)
    }
}

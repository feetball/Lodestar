import Foundation

/// The two motor channels of a Sky-Watcher motor controller (`*1` / `*2` in the command set).
public enum SkyWatcherAxis: String, CaseIterable, Codable, Hashable, Sendable {
    /// Channel "1": right ascension (equatorial mounts) or azimuth (alt-azimuth mounts).
    case axis1
    /// Channel "2": declination (equatorial mounts) or altitude (alt-azimuth mounts).
    case axis2

    /// The channel character sent on the wire.
    public var channel: Character { self == .axis1 ? "1" : "2" }

    /// 0 for `axis1`, 1 for `axis2`.
    public var index: Int { self == .axis1 ? 0 : 1 }
}

/// How the two axes are arranged: which kind of pointing model applies.
public enum SkyWatcherMountMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// Hour-angle / declination axes on a polar axis (Star Adventurer GTi, EQ mounts, an AZ-GTi on a wedge).
    case equatorial
    /// Azimuth / altitude axes on a level base (AZ-GTi, AZ-GTe and other alt-azimuth mounts).
    case altAzimuth
}

/// Which side of the mount the telescope is on, named as ASCOM names the pier sides. On an equatorial mount `east` is the
/// normal pointing state (counterweight down, telescope looking west, declination axis angle 0° to 180°) and `west` the
/// state "through the pole" (looking east, declination axis angle -180° to 0°). On an alt-azimuth mount `east` is the
/// normal state (altitude axis -90° to 90°) and `west` means over the top (beyond the zenith).
public enum SkyWatcherPierSide: String, CaseIterable, Codable, Hashable, Sendable {
    /// Normal pointing state.
    case east
    /// Through-the-pole (equatorial) or over-the-top (alt-azimuth) state.
    case west
}

/// How the driver keeps the telescope on the sky while tracking.
public enum SkyWatcherTrackingStrategy: String, CaseIterable, Codable, Hashable, Sendable {
    /// The right ascension axis runs at the sidereal rate on its own; the declination axis stands still (equatorial mounts).
    case sidereal
    /// Both axes get new rates computed from the target's motion about once a second (alt-azimuth mounts, which have no
    /// tracking of their own); the app must keep polling.
    case servo
}

/// The arrangements a mount model supports.
public enum SkyWatcherMountClass: String, CaseIterable, Codable, Hashable, Sendable {
    /// Equatorial mounts.
    case equatorialOnly
    /// Alt-azimuth mounts.
    case altAzimuthOnly
    /// Mounts that can be used either way (AZ-GTi on a wedge, Star Adventurer GTi, AZ-EQ and Wave mounts).
    case either
}

/// The motion modes of the `G` command (first data digit): what the next `J` (start) does.
public enum SkyWatcherMotionMode: Character, CaseIterable, Codable, Hashable, Sendable {
    /// High-speed GOTO: moves by the goto increment with acceleration and a brake point.
    case gotoFast = "0"
    /// Speed ("tracking") mode at low speed: runs at the step period until stopped.
    case trackSlow = "1"
    /// Low-speed GOTO: moves by the goto increment at a constant slow speed.
    case gotoSlow = "2"
    /// Speed mode at high speed: the step period is multiplied by the controller's high-speed ratio.
    case trackFast = "3"

    /// The character sent on the wire.
    public var code: Character { rawValue }

    /// True for the two GOTO modes.
    public var isGoto: Bool { self == .gotoFast || self == .gotoSlow }

    /// True for the two high-speed modes.
    public var isFast: Bool { self == .gotoFast || self == .trackFast }

    /// The mode sent as `code`, or nil if there is none.
    public static func fromCode(_ code: Character) -> SkyWatcherMotionMode? { SkyWatcherMotionMode(rawValue: code) }
}

/// The direction digit of the `G` command (second data digit).
public enum SkyWatcherDirection: Character, CaseIterable, Codable, Hashable, Sendable {
    /// The position count increases.
    case increasing = "0"
    /// The position count decreases.
    case decreasing = "1"

    /// The character sent on the wire.
    public var code: Character { rawValue }

    /// The direction sent as `code`, or nil if there is none.
    public static func fromCode(_ code: Character) -> SkyWatcherDirection? { SkyWatcherDirection(rawValue: code) }
}

/// What the `f` command reports for one axis.
public struct SkyWatcherAxisStatus: Hashable, Sendable {
    /// True in speed ("tracking") mode, false in GOTO mode.
    public let isSpeedMode: Bool
    /// True when the axis turns counter-clockwise (the position count decreases).
    public let isDecreasing: Bool
    /// True in the high-speed variant of the mode.
    public let isFast: Bool
    /// True while the axis moves.
    public let isRunning: Bool
    /// True when the controller reports the axis as blocked.
    public let isBlocked: Bool
    /// True once the `F` command (initialization done) has been accepted.
    public let isInitialized: Bool
    /// True while the level (home) switch is on.
    public let isLevelSwitchOn: Bool

    public init(isSpeedMode: Bool, isDecreasing: Bool, isFast: Bool, isRunning: Bool, isBlocked: Bool, isInitialized: Bool,
                isLevelSwitchOn: Bool) {
        self.isSpeedMode = isSpeedMode
        self.isDecreasing = isDecreasing
        self.isFast = isFast
        self.isRunning = isRunning
        self.isBlocked = isBlocked
        self.isInitialized = isInitialized
        self.isLevelSwitchOn = isLevelSwitchOn
    }

    /// True while the axis executes a GOTO.
    public var isGoto: Bool { isRunning && !isSpeedMode }
}

/// The error codes of a `!` reply.
public enum SkyWatcherErrorCode: CaseIterable, Hashable, Sendable {
    /// Code 0.
    case unknownCommand
    /// Code 1.
    case commandLength
    /// Code 2: the command needs a stopped motor.
    case motorNotStopped
    /// Code 3.
    case invalidCharacter
    /// Code 4: the `F` command has not been sent since power-up.
    case notInitialized
    /// Code 5.
    case driverSleeping
    /// Code 7.
    case pecTrainingRunning
    /// Code 8.
    case noValidPECData

    /// The code sent after the `!`.
    public var code: Int {
        switch self {
        case .unknownCommand: 0
        case .commandLength: 1
        case .motorNotStopped: 2
        case .invalidCharacter: 3
        case .notInitialized: 4
        case .driverSleeping: 5
        case .pecTrainingRunning: 7
        case .noValidPECData: 8
        }
    }

    /// The documented name.
    public var title: String {
        switch self {
        case .unknownCommand: "unknown command"
        case .commandLength: "command length error"
        case .motorNotStopped: "motor not stopped"
        case .invalidCharacter: "invalid character"
        case .notInitialized: "not initialized"
        case .driverSleeping: "driver sleeping"
        case .pecTrainingRunning: "PEC training is running"
        case .noValidPECData: "no valid PEC data"
        }
    }

    /// The error with the given code, or nil if the code is not documented (6 and 9 to 15).
    public static func fromCode(_ code: Int) -> SkyWatcherErrorCode? { allCases.first { $0.code == code } }
}

/// The reply to `:e` (motor board version): firmware version and mount model code.
///
/// The six hex digits `AABBCC` are read as firmware `AA.BB` and mount code `CC` (INDI's `skywatcherAPI` reads the board
/// version the same way); the mount codes come from INDI's mount-type table.
public struct SkyWatcherVersion: Hashable, Sendable {
    /// The first byte of the version reply.
    public let major: Int
    /// The second byte of the version reply.
    public let minor: Int
    /// The mount model code (last byte of the reply).
    public let mountCode: Int

    public init(major: Int, minor: Int, mountCode: Int) {
        self.major = major
        self.minor = minor
        self.mountCode = mountCode
    }

    /// The firmware as text: the major byte in decimal, the minor byte as two hex digits ("3.22").
    public var description: String { "\(major).\(SkyWatcherMountCatalog.hex2(minor))" }

    /// The mount model's name.
    public var mountName: String { SkyWatcherMountCatalog.name(mountCode) }

    /// The arrangements this model supports.
    public var mountClass: SkyWatcherMountClass { SkyWatcherMountCatalog.mountClass(mountCode) }
}

/// Mount model codes of the motor controller (from INDI's `skywatcherAPI.h` and `skywatcher.cpp` mount-type tables).
public enum SkyWatcherMountCatalog {
    /// The model name for a code ("Sky-Watcher motor controller" for codes that are not listed).
    public static func name(_ code: Int) -> String {
        switch code {
        case 0x00: "EQ6"
        case 0x01: "HEQ5"
        case 0x02: "EQ5"
        case 0x03: "EQ3"
        case 0x04: "EQ8"
        case 0x05: "AZ-EQ6"
        case 0x06: "AZ-EQ5"
        case 0x0A: "Star Adventurer"
        case 0x0C: "Star Adventurer GTi"
        case 0x20: "EQ8-R Pro"
        case 0x22: "AZ-EQ6 Pro"
        case 0x23: "EQ6-R Pro"
        case 0x24: "EQ6 Pro"
        case 0x25: "CQ350 Pro"
        case 0x31: "EQ5 Pro"
        case 0x44: "Wave 100i"
        case 0x45: "Wave 150i"
        case 0x80: "GT"
        case 0x81: "MF"
        case 0x82: "114GT"
        case 0x90: "Dob"
        case 0xA2: "AZ-GTe"
        case 0xA5: "AZ-GTi"
        default: "Sky-Watcher motor controller"
        }
    }

    /// Which arrangements the model with this code supports (unknown codes: either).
    public static func mountClass(_ code: Int) -> SkyWatcherMountClass {
        switch code {
        case 0x00, 0x01, 0x02, 0x03, 0x04, 0x0A, 0x20, 0x23, 0x24, 0x25, 0x31: .equatorialOnly
        case 0x80, 0x81, 0x82, 0x90: .altAzimuthOnly
        default: .either
        }
    }

    /// The arrangement to assume for the model with this code: alt-azimuth for the AZ-GTi family and GT/MF/Dob mounts, equatorial otherwise.
    public static func defaultMode(_ code: Int) -> SkyWatcherMountMode {
        switch code {
        case 0x80, 0x81, 0x82, 0x90, 0xA2, 0xA5: .altAzimuth
        default: .equatorial
        }
    }

    static func hex2(_ value: Int) -> String {
        let digits = Array("0123456789ABCDEF")
        let byte = value & 0xFF
        return String([digits[byte >> 4], digits[byte & 15]])
    }
}

/// Limits of what the driver lets the mount do. Values are clamped to their ranges when the limits are created.
public struct SkyWatcherLimits: Hashable, Sendable {
    /// Targets lower than this geometric altitude are refused (`MountError.mountHorizonLimit`); -20 to 60, default -10 so the controller's own altitude limit decides.
    public let minimumAltitudeDegrees: Double
    /// Alt-azimuth only: targets higher than this are refused (`MountError.mountOverheadLimit`), and tracking stops above it; 60 to 90, default 88.
    public let maximumAltitudeDegrees: Double
    /// Alt-azimuth only: the lowest azimuth axis angle (from the home position), the cable-wrap limit; -330 to 0, default -270.
    public let azimuthMinimumDegrees: Double
    /// Alt-azimuth only: the highest azimuth axis angle; 0 to 330, default 270.
    public let azimuthMaximumDegrees: Double
    /// Equatorial only: how far past the meridian (counterweight horizontal) the right ascension axis may turn; 0 to 30, default 5.
    public let meridianOverlapDegrees: Double
    /// Equatorial only: slews may dip this far below the minimum altitude on the way (tripod clearance); 0 to 30, default 5.
    public let pathMarginDegrees: Double
    /// The fastest an axis may be asked to turn while tracking or nudging; 0.1 to 4, default 3.
    public let maximumAxisRateDegreesPerSecond: Double

    /// The default limits.
    public static let standard = SkyWatcherLimits()

    /// Creates limits; values are clamped to their ranges (NaN becomes the default).
    public init(minimumAltitudeDegrees: Double = -10, maximumAltitudeDegrees: Double = 88, azimuthMinimumDegrees: Double = -270,
                azimuthMaximumDegrees: Double = 270, meridianOverlapDegrees: Double = 5, pathMarginDegrees: Double = 5,
                maximumAxisRateDegreesPerSecond: Double = 3) {
        self.minimumAltitudeDegrees = SkyWatcherLimits.sane(minimumAltitudeDegrees, -10, -20, 60)
        self.maximumAltitudeDegrees = SkyWatcherLimits.sane(maximumAltitudeDegrees, 88, 60, 90)
        self.azimuthMinimumDegrees = SkyWatcherLimits.sane(azimuthMinimumDegrees, -270, -330, 0)
        self.azimuthMaximumDegrees = SkyWatcherLimits.sane(azimuthMaximumDegrees, 270, 0, 330)
        self.meridianOverlapDegrees = SkyWatcherLimits.sane(meridianOverlapDegrees, 5, 0, 30)
        self.pathMarginDegrees = SkyWatcherLimits.sane(pathMarginDegrees, 5, 0, 30)
        self.maximumAxisRateDegreesPerSecond = SkyWatcherLimits.sane(maximumAxisRateDegreesPerSecond, 3, 0.1, 4)
    }

    private static func sane(_ value: Double, _ defaultValue: Double, _ lower: Double, _ upper: Double) -> Double {
        value.isNaN ? defaultValue : min(max(value, lower), upper)
    }
}

/// Settings of a `SkyWatcherDriver`. Values are clamped to their ranges when the configuration is created.
public struct SkyWatcherConfiguration: Hashable, Sendable {
    /// Where the mount stands; the pointing model needs the latitude and the sidereal time. `MountController.setSiteAndTime` replaces it.
    public let location: GeographicLocation
    /// The mount's arrangement; nil (the default) picks it from the mount model found at connect time.
    public let mode: SkyWatcherMountMode?
    /// Set when the position count of axis 1 decreases while the axis turns in the positive direction (clockwise seen from above / towards the west).
    public let invertsAxis1: Bool
    /// Set when the position count of axis 2 decreases while the axis turns in the positive direction (up / towards a smaller declination).
    public let invertsAxis2: Bool
    /// How long one attempt waits for the mount's reply (0.2 to 5 s, default 0.6).
    public let exchangeTimeoutSeconds: Double
    /// How often a command is sent before the exchange fails (1 to 6, default 3); UDP loses datagrams.
    public let attempts: Int
    /// Axis, altitude and cable-wrap limits.
    public let limits: SkyWatcherLimits
    /// How tracking is kept; nil (the default) uses `.sidereal` for equatorial and `.servo` for alt-azimuth mounts.
    public let trackingStrategy: SkyWatcherTrackingStrategy?
    /// The least time between two rate updates of a servo tracker or a nudge (0.25 to 30 s, default 1).
    public let trackingUpdateIntervalSeconds: Double
    /// Allow slews before any alignment star was synced (the model then assumes a perfect home position); default false.
    public let allowsGotoWithoutAlignment: Bool
    /// Send GOTO targets as absolute positions (`S`) instead of increments (`H`); default false (what INDI does).
    public let usesAbsoluteGotoTarget: Bool
    /// The slew speed the planner assumes when it predicts where a moving target will be on arrival (0.1 to 10 degrees per second, default 2.5).
    public let assumedSlewDegreesPerSecond: Double
    /// A slew is repeated with a short correction while the mount stops more than this far from the target (0.002 to 0.5 degrees, default 0.02).
    public let refinementToleranceDegrees: Double
    /// A sync that would leave a residual larger than this on any alignment star is refused (0.1 to 10 degrees, default 1).
    public let maximumAlignmentResidualDegrees: Double

    /// Creates a configuration; out-of-range values are clamped (NaN becomes the default).
    public init(location: GeographicLocation, mode: SkyWatcherMountMode? = nil, invertsAxis1: Bool = false, invertsAxis2: Bool = false,
                exchangeTimeoutSeconds: Double = 0.6, attempts: Int = 3, limits: SkyWatcherLimits = .standard,
                trackingStrategy: SkyWatcherTrackingStrategy? = nil, trackingUpdateIntervalSeconds: Double = 1,
                allowsGotoWithoutAlignment: Bool = false, usesAbsoluteGotoTarget: Bool = false,
                assumedSlewDegreesPerSecond: Double = 2.5, refinementToleranceDegrees: Double = 0.02,
                maximumAlignmentResidualDegrees: Double = 1) {
        self.location = location
        self.mode = mode
        self.invertsAxis1 = invertsAxis1
        self.invertsAxis2 = invertsAxis2
        self.exchangeTimeoutSeconds = SkyWatcherConfiguration.sane(exchangeTimeoutSeconds, 0.6, 0.2, 5)
        self.attempts = min(max(attempts, 1), 6)
        self.limits = limits
        self.trackingStrategy = trackingStrategy
        self.trackingUpdateIntervalSeconds = SkyWatcherConfiguration.sane(trackingUpdateIntervalSeconds, 1, 0.25, 30)
        self.allowsGotoWithoutAlignment = allowsGotoWithoutAlignment
        self.usesAbsoluteGotoTarget = usesAbsoluteGotoTarget
        self.assumedSlewDegreesPerSecond = SkyWatcherConfiguration.sane(assumedSlewDegreesPerSecond, 2.5, 0.1, 10)
        self.refinementToleranceDegrees = SkyWatcherConfiguration.sane(refinementToleranceDegrees, 0.02, 0.002, 0.5)
        self.maximumAlignmentResidualDegrees = SkyWatcherConfiguration.sane(maximumAlignmentResidualDegrees, 1, 0.1, 10)
    }

    private static func sane(_ value: Double, _ defaultValue: Double, _ lower: Double, _ upper: Double) -> Double {
        value.isNaN ? defaultValue : min(max(value, lower), upper)
    }
}

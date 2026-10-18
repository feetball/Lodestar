import Foundation

/// A mount that moves: the physics shared by the protocol simulators. It slews towards a target at a finite rate
/// (right ascension and declination move at the same speed, right ascension the short way round), reports "slewing"
/// until it arrives, accepts syncs, and moves continuously while a nudge is on. Time comes from the `ManualMountClock`,
/// so results are deterministic. Coordinates are in whatever frame the protocol simulator is used with.
public final class MountSimulatorModel {
    private let clock: ManualMountClock
    private var rightAscension: Double
    private var declination: Double
    private var lastUpdate: Double
    private var goalRightAscension: Double
    private var goalDeclination: Double
    private var slewing = false
    private var slewBegan = 0.0
    private var rightAscensionRate = 0.0
    private var declinationRate = 0.0

    /// Slew speed in degrees per second.
    public let slewRateDegreesPerSecond: Double
    /// Seconds between the slew command and the first movement; the mount reports "slewing" meanwhile.
    public let startDelaySeconds: Double

    /// Whether the mount tracks the sky (it never drifts in the simulation; the flag is only reported).
    public var isTracking = true
    /// Whether the mount has been star-aligned.
    public var isAligned = true
    /// Whether the mount is parked.
    public var isParked = false
    /// The number of slews started so far.
    public private(set) var slewsStarted = 0
    /// The number of syncs performed so far.
    public private(set) var syncsPerformed = 0
    /// The number of times the mount was told to stop.
    public private(set) var stopsReceived = 0

    public init(clock: ManualMountClock, start: EquatorialCoordinate, slewRateDegreesPerSecond: Double = 4.0,
                startDelaySeconds: Double = 0.4) {
        self.clock = clock
        self.slewRateDegreesPerSecond = slewRateDegreesPerSecond
        self.startDelaySeconds = startDelaySeconds
        rightAscension = start.rightAscension
        declination = start.declination
        lastUpdate = clock.secondsSince1970
        goalRightAscension = start.rightAscension
        goalDeclination = start.declination
    }

    /// Where the mount points now.
    public var position: EquatorialCoordinate {
        advance()
        return EquatorialCoordinate(rightAscension: rightAscension, declination: declination)
    }

    /// Whether the mount is slewing (a nudge does not count).
    public var isSlewing: Bool {
        advance()
        return slewing
    }

    /// Whether a nudge is moving the mount.
    public var isNudging: Bool {
        advance()
        return rightAscensionRate != 0.0 || declinationRate != 0.0
    }

    /// Starts a slew to `target`.
    public func beginSlew(to target: EquatorialCoordinate) {
        advance()
        goalRightAscension = target.rightAscension
        goalDeclination = target.declination
        slewing = true
        slewBegan = clock.secondsSince1970
        slewsStarted += 1
    }

    /// Stops a slew and all nudges.
    public func stop() {
        advance()
        slewing = false
        rightAscensionRate = 0.0
        declinationRate = 0.0
        stopsReceived += 1
    }

    /// Declares the mount to point at `target` now.
    public func sync(to target: EquatorialCoordinate) {
        advance()
        rightAscension = target.rightAscension
        declination = target.declination
        syncsPerformed += 1
    }

    /// Moves continuously: `rightAscensionDegreesPerSecond` and `declinationDegreesPerSecond` (signed; 0 leaves an axis still).
    public func setNudgeRates(rightAscensionDegreesPerSecond: Double, declinationDegreesPerSecond: Double) {
        advance()
        rightAscensionRate = rightAscensionDegreesPerSecond
        declinationRate = declinationDegreesPerSecond
    }

    /// Moves the position by `rightAscensionDegrees` and `declinationDegrees` at once (a guide pulse).
    public func displace(rightAscensionDegrees: Double, declinationDegrees: Double) {
        advance()
        rightAscension = AstroMath.normalizeDegrees(rightAscension + rightAscensionDegrees)
        declination = min(max(declination + declinationDegrees, -90.0), 90.0)
    }

    private func advance() {
        let now = clock.secondsSince1970
        let previous = lastUpdate
        lastUpdate = now
        let elapsed = now - previous
        if elapsed <= 0 { return }
        if slewing {
            let movingSince = max(previous, slewBegan + startDelaySeconds)
            let movingTime = now - movingSince
            if movingTime > 0 {
                let step = slewRateDegreesPerSecond * movingTime
                let raDelta = AstroMath.normalizeSignedDegrees(goalRightAscension - rightAscension)
                let decDelta = goalDeclination - declination
                if abs(raDelta) <= step {
                    rightAscension = goalRightAscension
                } else {
                    rightAscension = AstroMath.normalizeDegrees(rightAscension + (raDelta > 0 ? step : -step))
                }
                if abs(decDelta) <= step {
                    declination = goalDeclination
                } else {
                    declination += decDelta > 0 ? step : -step
                }
                if rightAscension == goalRightAscension && declination == goalDeclination { slewing = false }
            }
        }
        if rightAscensionRate != 0.0 || declinationRate != 0.0 {
            rightAscension = AstroMath.normalizeDegrees(rightAscension + rightAscensionRate * elapsed)
            declination = min(max(declination + declinationRate * elapsed, -90.0), 90.0)
        }
    }
}

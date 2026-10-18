import Foundation

/// The encoder angles of both axes in degrees, as read from the mount.
public struct SkyWatcherAxisAngles: Hashable, Sendable {
    /// The encoder angle of axis 1.
    public let axis1Degrees: Double
    /// The encoder angle of axis 2.
    public let axis2Degrees: Double

    public init(axis1Degrees: Double, axis2Degrees: Double) {
        self.axis1Degrees = axis1Degrees
        self.axis2Degrees = axis2Degrees
    }
}

/// Drives a Sky-Watcher Wi-Fi mount (AZ-GTi, AZ-GTe, Star Adventurer GTi, EQ mounts with the Wi-Fi dongle) through the motor
/// controller protocol on UDP port 11880 (see `SkyWatcherCodec`) with the `MountController`. The motor controller only knows
/// encoder counts and step periods, so the driver supplies what the hand controls normally do:
///
/// - **Pointing model.** The documented home position (equatorial: counterweight down, telescope at the pole; alt-azimuth:
///   level, pointing north) is the mount's zero. The user powers the mount up at home, connects, and syncs on 1 to 3 stars: one
///   star finds the home position error, two add the polar axis (equatorial) or level (alt-azimuth) error, three add orthogonality
///   and cone errors (see `SkyWatcherAlignmentSolver`; the residuals are in `alignmentFit`). `sync` adds an alignment point; goto is
///   refused until the first one (`MountError.notAligned`) unless `SkyWatcherConfiguration.allowsGotoWithoutAlignment`.
/// - **GoTo.** The target (apparent place of date, `epoch`) is turned into axis angles through the model, for the position the sky
///   will have when the slew ends; limits and the pier side are chosen first: equatorial mounts take the side that keeps the
///   counterweight down (the side changes at the meridian, within `SkyWatcherLimits.meridianOverlapDegrees` the current side
///   stays), alt-azimuth mounts unwrap the azimuth within the cable-wrap limits. Slews whose straight path would dip below the
///   horizon are split into two legs. When the mount stops, the remaining error is corrected with short slews.
/// - **Tracking.** Equatorial mounts track at the sidereal rate on axis 1 alone. Alt-azimuth mounts have no tracking of their own:
///   about every `SkyWatcherConfiguration.trackingUpdateIntervalSeconds` the driver computes new rates of both axes from the target's motion and
///   its distance from the target. **This happens inside `readSlewing`: the app must keep polling** (the controller does that once
///   per call of `poll`; poll at least once a second). When a limit is reached, tracking stops and `trackingStopReason` says why.
///
/// Coordinates are in `epoch` = `MountEpoch.apparentOfDate`. Refraction is not modelled. Not thread safe.
public final class SkyWatcherDriver: MountDriver {
    /// The name of this connection type for menus.
    public static let menuTitle = "Sky-Watcher Wi-Fi (AZ-GTi, Star Adventurer GTi)"

    private static let duplicateSeparationDegrees = 0.5
    private static let siteChangeDegrees = 0.25
    private static let minimumCosine = 0.05
    private static let maximumDeclination = 89.5
    private static let nudgeGraceSeconds = 2.0
    private static let nudgeLeadSeconds = 0.5
    private static let nudgeUpdateSeconds = 0.5
    private static let trackingLeadExtraSeconds = 0.5
    private static let trackingRateSlack = 1.5
    private static let limitSlackDegrees = 0.25
    private static let slewOverheadSeconds = 1.5
    private static let refinementLeadSeconds = 1.5
    private static let settleSeconds = 1.0
    private static let maximumRefinements = 3
    private static let predictionPasses = 3
    private static let pathSamples = 24
    private static let completedCounts = 3
    private static let stopPolls = 40
    private static let stopPollSeconds = 0.1
    private static let maximumCount = 0x7FFFF0
    private static let highSpeedBrakeCounts = 3200
    private static let lowSpeedBrakeCounts = 200
    private static let siderealSecondsPerRevolution = 86164.09065

    private let link: SkyWatcherLink
    private let clock: MountClock

    /// The settings in use (the `location` may be replaced by `setSiteAndTime`).
    public let configuration: SkyWatcherConfiguration

    /// The site of the mount.
    public private(set) var location: GeographicLocation

    /// The motor board version found by `connect`; nil before.
    public private(set) var version: SkyWatcherVersion?

    /// The arrangement in use (from the configuration or the mount model); nil before `connect`.
    public private(set) var mountMode: SkyWatcherMountMode?

    /// The tracking strategy in use; nil before `connect`.
    public private(set) var trackingStrategy: SkyWatcherTrackingStrategy?

    /// The encoder angles at `connect`; far from 0 when the mount was not at its home position (or was moved before).
    public private(set) var startupAxisAngles: SkyWatcherAxisAngles?

    /// Why tracking stopped by itself (a limit was reached); cleared when tracking is switched on.
    public private(set) var trackingStopReason: MountError?

    /// The alignment points in use, oldest first.
    public private(set) var alignmentPoints: [SkyWatcherAlignmentPoint] = []

    /// The fit of the model to `alignmentPoints`; nil before the first sync.
    public private(set) var alignmentFit: SkyWatcherAlignmentFit?

    /// The datagrams sent so far, retries included (link statistics).
    public var datagramsSent: Int { link.datagramsSent }

    /// How many datagrams were repetitions because no usable reply arrived (link statistics).
    public var retries: Int { link.retries }

    public var kind: MountProtocol { .skywatcher }

    public var epoch: MountEpoch { .apparentOfDate }

    // MARK: Private state

    private enum Motion { case stopped, tracking, slewing, nudging }

    private struct Leg {
        let axis1: Double?
        let axis2: Double?
    }

    private final class Slew {
        let goal: EquatorialCoordinate
        var legs: [Leg]
        var refinements: Int
        var lastCommand: Date

        init(goal: EquatorialCoordinate, legs: [Leg], refinements: Int, lastCommand: Date) {
            self.goal = goal
            self.legs = legs
            self.refinements = refinements
            self.lastCommand = lastCommand
        }
    }

    private struct Nudge {
        let origin: EquatorialCoordinate
        let start: Date
        let rightAscensionRate: Double
        let declinationRate: Double
        let deadline: Date
    }

    private struct Reading {
        let axis1: Double
        let axis2: Double
        let counts1: Int
        let counts2: Int
        let time: Date
    }

    private struct Choice {
        let axis1: Double
        let axis2: Double
        let side: SkyWatcherPierSide
    }

    private var resolvedMode: SkyWatcherMountMode
    private var resolvedStrategy: SkyWatcherTrackingStrategy = .servo
    private var model: SkyWatcherPointingModel
    private var countsPerRevolution = [0, 0]
    private var highSpeedRatio = [0, 0]
    private var timerFrequency = 0
    private var statuses: [SkyWatcherAxisStatus?] = [nil, nil]
    private var motion = Motion.stopped
    private var trackingEnabled = false
    private var anchor: EquatorialCoordinate?
    private var slew: Slew?
    private var nudge: Nudge?
    private var lastReading: Reading?
    private var lastServo: Date?
    private var pendingStop = false
    private var connected = false

    private var isSouthern: Bool { location.latitude < 0 }

    /// The side of the mount at the last position reading (equatorial: counterweight side; alt-azimuth: over the top or not); nil before the first reading.
    public var pierSide: SkyWatcherPierSide? {
        guard let reading = lastReading else { return nil }
        return model.pierSide(axis2Degrees: reading.axis2)
    }

    /// The pointing model in use (the nominal model before the first sync); nil before `connect`.
    public var pointingModel: SkyWatcherPointingModel? { connected ? model : nil }

    public init(transport: MountTransport, clock: MountClock, configuration: SkyWatcherConfiguration) {
        link = SkyWatcherLink(transport: transport, clock: clock, attempts: configuration.attempts,
                              timeoutSeconds: configuration.exchangeTimeoutSeconds)
        self.clock = clock
        self.configuration = configuration
        location = configuration.location
        let mode = configuration.mode ?? .altAzimuth
        resolvedMode = mode
        model = SkyWatcherPointingModel.nominal(mode: mode, isSouthernHemisphere: configuration.location.latitude < 0)
    }

    // MARK: Session

    public func connect() throws -> MountCapabilities {
        connected = false
        let found = try SkyWatcherCodec.decodeVersion(try link.exchange(.inquireVersion, axis: .axis1, data: "", operation: "read version"))
        for axis in SkyWatcherAxis.allCases {
            let cpr = try SkyWatcherCodec.decode24(try link.exchange(.inquireCountsPerRevolution, axis: axis, data: "",
                                                                      operation: "read counts per revolution"))
            if cpr < 1000 { throw MountError.malformedReply(detail: "counts per revolution") }
            countsPerRevolution[axis.index] = cpr
        }
        let frequency = try SkyWatcherCodec.decode24(try link.exchange(.inquireTimerFrequency, axis: .axis1, data: "",
                                                                        operation: "read timer frequency"))
        if frequency <= 0 { throw MountError.malformedReply(detail: "timer frequency") }
        timerFrequency = frequency
        for axis in SkyWatcherAxis.allCases {
            highSpeedRatio[axis.index] = try SkyWatcherCodec.decodeHighSpeedRatio(
                try link.exchange(.inquireHighSpeedRatio, axis: axis, data: "", operation: "read high-speed ratio"))
        }
        try refreshStatuses()
        if statuses.contains(where: { $0?.isInitialized != true }) {
            for axis in SkyWatcherAxis.allCases { try link.exchange(.initializationDone, axis: axis, data: "", operation: "initialize") }
            try refreshStatuses()
            if statuses.contains(where: { $0?.isInitialized != true }) {
                throw MountError.rejected(detail: "the motor controller did not initialize")
            }
        }
        if statuses.contains(where: { $0?.isRunning == true }) {
            try stopAxes()
            try waitUntilStopped()
        }

        version = found
        resolvedMode = configuration.mode ?? SkyWatcherMountCatalog.defaultMode(found.mountCode)
        mountMode = resolvedMode
        if resolvedMode == .altAzimuth {
            resolvedStrategy = .servo
        } else {
            resolvedStrategy = configuration.trackingStrategy ?? .sidereal
        }
        trackingStrategy = resolvedStrategy
        alignmentPoints = []
        alignmentFit = nil
        model = SkyWatcherPointingModel.nominal(mode: resolvedMode, isSouthernHemisphere: isSouthern)
        motion = .stopped
        trackingEnabled = false
        trackingStopReason = nil
        anchor = nil
        slew = nil
        nudge = nil
        lastServo = nil
        pendingStop = false
        connected = true
        let start = try readAxes()
        startupAxisAngles = SkyWatcherAxisAngles(axis1Degrees: start.axis1, axis2Degrees: start.axis2)
        return MountCapabilities(
            kind: .skywatcher, name: "Sky-Watcher \(found.mountName) \(found.description)", firmware: found.description,
            canSlew: true, canSync: true, canAbort: true, canSetTracking: true, canNudge: true, canSetSiteAndTime: true,
            gotoNeedsAlignment: !configuration.allowsGotoWithoutAlignment, isAligned: false)
    }

    /// Ends the session. Servo tracking (alt-azimuth mounts) is stopped, because the mount would otherwise keep turning at the last
    /// rate; a sidereal tracking equatorial mount keeps tracking, and a running slew is left to finish.
    public func disconnect() {
        if !connected { return }
        connected = false
        if motion == .tracking && resolvedStrategy == .servo {
            do {
                try stopAxes()
            } catch {
                // Best effort: the link is probably gone.
            }
        }
        motion = .stopped
    }

    // MARK: Reading

    public func readPosition() throws -> EquatorialCoordinate {
        try requireConnected()
        let reading = try readAxes()
        checkSiderealLimits(reading)
        return pointing(reading)
    }

    public func readSlewing() throws -> Bool {
        try requireConnected()
        try refreshStatuses()
        try serviceMotion()
        if motion == .slewing { return true }
        return statuses.contains(where: { $0?.isGoto == true })
    }

    public func readTracking() throws -> Bool? {
        try requireConnected()
        return trackingEnabled
    }

    public func readAligned() throws -> Bool? { !alignmentPoints.isEmpty }

    // MARK: Slew, sync, abort

    public func slew(to target: EquatorialCoordinate) throws {
        try requireConnected()
        try requireFinite(target)
        if !configuration.allowsGotoWithoutAlignment && alignmentPoints.isEmpty { throw MountError.notAligned }
        if motion == .nudging { try endNudge() }
        let start = try readAxes()
        let legs = try planSlew(target, start)
        trackingEnabled = true
        trackingStopReason = nil
        try stopAxes()
        try waitUntilStopped()
        motion = .slewing
        anchor = target
        let state = Slew(goal: target, legs: legs, refinements: 0, lastCommand: clock.now())
        slew = state
        do {
            let first = state.legs.removeFirst()
            _ = try startLeg(first)
            state.lastCommand = clock.now()
        } catch {
            slew = nil
            motion = .stopped
            throw error
        }
    }

    public func sync(to target: EquatorialCoordinate) throws {
        try requireConnected()
        try requireFinite(target)
        let reading = try readAxes()
        let direction = SkyWatcherSky.localDirection(target, localSiderealTime: lst(reading.time), latitude: location.latitude,
                                                     mode: resolvedMode)
        let point = SkyWatcherAlignmentPoint(axis1Degrees: reading.axis1, axis2Degrees: reading.axis2, direction: direction,
                                             timestamp: reading.time)
        var updated: [SkyWatcherAlignmentPoint] = []
        for existing in alignmentPoints {
            // Syncing the same star again replaces its earlier point (the local direction of a star changes with the time of the sync).
            let earlier = SkyWatcherSky.apparentPlace(existing.direction, localSiderealTime: lst(existing.timestamp),
                                                      latitude: location.latitude, mode: resolvedMode)
            if earlier.angularSeparation(to: target) >= SkyWatcherDriver.duplicateSeparationDegrees { updated.append(existing) }
        }
        updated.append(point)
        while updated.count > SkyWatcherAlignmentSolver.maximumPoints { updated.removeFirst() }
        let fit = try SkyWatcherAlignmentSolver.solve(updated, mode: resolvedMode, isSouthernHemisphere: isSouthern)
        if fit.maximumResidualDegrees > configuration.maximumAlignmentResidualDegrees {
            throw MountError.rejected(
                detail: "the alignment would leave \(formatDegrees(fit.maximumResidualDegrees)) of error on a star; check that you centred the right star")
        }
        if !fit.isPlausible {
            throw MountError.rejected(
                detail: "the alignment would need larger corrections than a mount set up by hand can have; check that you centred the right star and that the mount started at its home position")
        }
        alignmentPoints = updated
        alignmentFit = fit
        model = fit.model
        if motion == .tracking { anchor = target }
    }

    public func abort() throws {
        try requireConnected()
        try stopAxes()
        slew = nil
        nudge = nil
        motion = .stopped
        pendingStop = false
    }

    // MARK: Tracking and nudges

    public func setTracking(_ enabled: Bool) throws {
        try requireConnected()
        if enabled {
            trackingEnabled = true
            trackingStopReason = nil
            if motion == .stopped {
                try refreshStatuses()
                if let refused = try startTracking() { throw refused }
            }
        } else {
            try stopAxes()
            trackingEnabled = false
            if motion == .tracking { motion = .stopped }
        }
    }

    public func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
        try requireConnected()
        if motion == .slewing { throw MountError.slewInProgress }
        if !(durationSeconds > 0) || !durationSeconds.isFinite { throw MountError.invalidInput(detail: "the nudge duration") }
        try refreshStatuses()
        let reading = try readAxes()
        let origin = pointing(reading)
        let speed = rate.degreesPerSecond
        var rightAscensionRate = 0.0
        var declinationRate = 0.0
        switch direction {
        case .north: declinationRate = speed
        case .south: declinationRate = -speed
        case .east: rightAscensionRate = speed / max(AstroMath.cosDeg(origin.declination), SkyWatcherDriver.minimumCosine)
        case .west: rightAscensionRate = -speed / max(AstroMath.cosDeg(origin.declination), SkyWatcherDriver.minimumCosine)
        }
        nudge = Nudge(origin: origin, start: reading.time, rightAscensionRate: rightAscensionRate, declinationRate: declinationRate,
                      deadline: reading.time.addingTimeInterval(durationSeconds + SkyWatcherDriver.nudgeGraceSeconds))
        motion = .nudging
        try servoStep(reading, lead: SkyWatcherDriver.nudgeLeadSeconds) { at in self.nudgeAnchor(at) }
        lastServo = clock.now()
    }

    public func stopNudge(direction: MountNudgeDirection) throws {
        try requireConnected()
        if motion == .nudging { try endNudge() }
    }

    public func setSiteAndTime(location: GeographicLocation, date: Date) throws {
        try requireConnected()
        let previous = self.location
        self.location = location
        let moved = abs(location.latitude - previous.latitude) > SkyWatcherDriver.siteChangeDegrees
            || abs(AstroMath.normalizeSignedDegrees(location.longitude - previous.longitude)) > SkyWatcherDriver.siteChangeDegrees
        if (previous.latitude < 0) != (location.latitude < 0) || moved {
            clearAlignment()
        } else {
            model = SkyWatcherPointingModel(mode: resolvedMode, isSouthernHemisphere: isSouthern, errors: model.errors)
        }
    }

    /// Declares that the mount stands at its home position now (counterweight down and pointing at the pole, or level and pointing
    /// north): stops the axes, sets both position counts to zero (`E`), forgets the alignment and the tracking. For a mount that was not
    /// at home when the session began (`startupAxisAngles` far from zero) and was then brought home with the nudge pad, without
    /// switching the power off.
    public func declareHomePosition() throws {
        try requireConnected()
        try stopAxes()
        try waitUntilStopped()
        for axis in SkyWatcherAxis.allCases {
            try link.exchange(.setPosition, axis: axis, data: SkyWatcherCodec.encodePosition(0), operation: "set position")
        }
        slew = nil
        nudge = nil
        anchor = nil
        motion = .stopped
        trackingEnabled = false
        trackingStopReason = nil
        pendingStop = false
        lastServo = nil
        clearAlignment()
        let reading = try readAxes()
        startupAxisAngles = SkyWatcherAxisAngles(axis1Degrees: reading.axis1, axis2Degrees: reading.axis2)
    }

    // MARK: Alignment

    /// Forgets all alignment points; the model returns to the ideal geometry (home position assumed).
    public func clearAlignment() {
        alignmentPoints = []
        alignmentFit = nil
        model = SkyWatcherPointingModel.nominal(mode: resolvedMode, isSouthernHemisphere: isSouthern)
    }

    /// Removes the alignment point at `index` and fits the model to the rest.
    public func removeAlignmentPoint(_ index: Int) throws {
        if index < 0 || index >= alignmentPoints.count { throw MountError.invalidInput(detail: "there is no alignment point \(index)") }
        var rest = alignmentPoints
        rest.remove(at: index)
        if rest.isEmpty {
            clearAlignment()
            return
        }
        let fit = try SkyWatcherAlignmentSolver.solve(rest, mode: resolvedMode, isSouthernHemisphere: isSouthern)
        alignmentPoints = rest
        alignmentFit = fit
        model = fit.model
    }

    /// Replaces the alignment with `points` (for an app that kept them from an earlier session with the mount powered on all the
    /// time: the points refer to the encoder counts since power-up).
    public func restoreAlignment(_ points: [SkyWatcherAlignmentPoint]) throws {
        let fit = try SkyWatcherAlignmentSolver.solve(points, mode: resolvedMode, isSouthernHemisphere: isSouthern)
        alignmentPoints = points
        alignmentFit = fit
        model = fit.model
    }

    // MARK: Axis helpers

    private func requireConnected() throws {
        if !connected { throw MountError.notConnected }
    }

    private func requireFinite(_ target: EquatorialCoordinate) throws {
        if !target.rightAscension.isFinite || !target.declination.isFinite {
            throw MountError.invalidInput(detail: "the target coordinates are not numbers")
        }
    }

    private func sense(_ axis: SkyWatcherAxis) -> Double {
        let inverted = axis == .axis1 ? configuration.invertsAxis1 : configuration.invertsAxis2
        return inverted ? -1.0 : 1.0
    }

    private func degrees(_ axis: SkyWatcherAxis, _ counts: Int) -> Double {
        sense(axis) * Double(counts) * 360.0 / Double(countsPerRevolution[axis.index])
    }

    private func counts(_ axis: SkyWatcherAxis, _ degrees: Double) -> Int {
        let value = sense(axis) * degrees * Double(countsPerRevolution[axis.index]) / 360.0
        if !value.isFinite { return 0 }
        return Int(min(max(value, -2e9), 2e9).rounded())
    }

    private func readCounts(_ axis: SkyWatcherAxis) throws -> Int {
        try SkyWatcherCodec.decodePosition(try link.exchange(.inquirePosition, axis: axis, data: "", operation: "read position"))
    }

    private func readAxes() throws -> Reading {
        let before = clock.now()
        let counts1 = try readCounts(.axis1)
        let counts2 = try readCounts(.axis2)
        let after = clock.now()
        let time = before.addingTimeInterval(after.timeIntervalSince(before) / 2)
        let reading = Reading(axis1: degrees(.axis1, counts1), axis2: degrees(.axis2, counts2), counts1: counts1, counts2: counts2, time: time)
        lastReading = reading
        return reading
    }

    @discardableResult
    private func readStatus(_ axis: SkyWatcherAxis) throws -> SkyWatcherAxisStatus {
        let status = try SkyWatcherCodec.decodeStatus(try link.exchange(.inquireStatus, axis: axis, data: "", operation: "read status"))
        statuses[axis.index] = status
        return status
    }

    private func refreshStatuses() throws {
        try readStatus(.axis1)
        try readStatus(.axis2)
    }

    private func stopAxes() throws {
        for axis in SkyWatcherAxis.allCases { try link.exchange(.stopMotion, axis: axis, data: "", operation: "stop") }
    }

    private func waitUntilStopped() throws {
        for _ in 0 ..< SkyWatcherDriver.stopPolls {
            try refreshStatuses()
            if !statuses.contains(where: { $0?.isRunning == true }) { return }
            link.pause(SkyWatcherDriver.stopPollSeconds)
        }
        throw MountError.busy
    }

    private func stopAxis(_ axis: SkyWatcherAxis) throws {
        try link.exchange(.stopMotion, axis: axis, data: "", operation: "stop")
        for _ in 0 ..< SkyWatcherDriver.stopPolls {
            if try !readStatus(axis).isRunning { return }
            link.pause(SkyWatcherDriver.stopPollSeconds)
        }
        throw MountError.busy
    }

    /// Starts the motion set up for `axis`. The command is not repeated blindly: if its reply is lost, the axis' status says whether
    /// the start happened. For a GOTO to `gotoTarget` counts the position is checked as well, because a short GOTO may already be
    /// over (the axis is then back in speed mode, and starting it again would send it off at the speed of its last step period).
    private func startAxis(_ axis: SkyWatcherAxis, gotoTarget: Int? = nil) throws {
        var last: MountError?
        for _ in 0 ..< 3 {
            do {
                try link.exchange(.startMotion, axis: axis, data: "", operation: "start motion", maximumAttempts: 1)
                return
            } catch let error as MountError {
                switch error {
                case .timeout, .malformedReply: last = error
                default: throw error
                }
            }
            // The start may have been executed although its reply was lost: look at the axis before sending it again.
            if try readStatus(axis).isRunning { return }
            if let target = gotoTarget {
                let position = try readCounts(axis)
                if abs(position - target) <= SkyWatcherDriver.completedCounts { return }
            }
        }
        throw last ?? MountError.timeout(operation: "start motion")
    }

    // MARK: Sky helpers

    private func lst(_ at: Date) -> Double {
        SkyFrame(date: at, observer: Observer(location: location)).localApparentSiderealTime
    }

    private func pointing(_ reading: Reading) -> EquatorialCoordinate {
        SkyWatcherSky.apparentPlace(model.direction(axis1Degrees: reading.axis1, axis2Degrees: reading.axis2),
                                    localSiderealTime: lst(reading.time), latitude: location.latitude, mode: resolvedMode)
    }

    private func formatDegrees(_ value: Double) -> String { String(format: "%.2f°", value) }

    // MARK: Choosing axis angles

    /// The axis angles for `place` at `at`, within the limits; throws the mount's limit errors.
    private func choose(_ place: EquatorialCoordinate, _ at: Date, _ near: Reading, keepSide: Bool) throws -> Choice {
        let limits = configuration.limits
        let sidereal = lst(at)
        let altitude = SkyWatcherSky.altitude(place, localSiderealTime: sidereal, latitude: location.latitude)
        if altitude < limits.minimumAltitudeDegrees { throw MountError.mountHorizonLimit }
        if resolvedMode == .altAzimuth && altitude > limits.maximumAltitudeDegrees { throw MountError.mountOverheadLimit }
        let direction = SkyWatcherSky.localDirection(place, localSiderealTime: sidereal, latitude: location.latitude, mode: resolvedMode)
        let solutions = model.solutions(direction, preferredAxis1Degrees: near.axis1)
        if resolvedMode == .altAzimuth {
            guard let normal = solutions.first(where: { $0.pierSide == .east }) else { throw MountError.outsideMountLimits }
            var best: Double?
            for turns in -2 ... 2 {
                let candidate = normal.axis1 + 360.0 * Double(turns)
                if candidate < limits.azimuthMinimumDegrees || candidate > limits.azimuthMaximumDegrees { continue }
                if let current = best {
                    if abs(candidate - near.axis1) < abs(current - near.axis1) { best = candidate }
                } else {
                    best = candidate
                }
            }
            guard let chosen = best else { throw MountError.outsideMountLimits }
            return Choice(axis1: chosen, axis2: normal.axis2, side: .east)
        }
        let currentSide = model.pierSide(axis2Degrees: near.axis2)
        let limit = 90.0 + limits.meridianOverlapDegrees
        var valid: [SkyWatcherAxisSolution] = []
        for solution in solutions {
            if abs(model.modelAxis1(solution.axis1)) > limit { continue }
            if keepSide && solution.pierSide != currentSide { continue }
            valid.append(solution)
        }
        if valid.isEmpty { throw MountError.outsideMountLimits }
        var pick = valid[0]
        if valid.count > 1 {
            if let same = valid.first(where: { $0.pierSide == currentSide }) {
                pick = same
            } else if abs(model.modelAxis1(valid[1].axis1)) < abs(model.modelAxis1(valid[0].axis1)) {
                pick = valid[1]
            }
        }
        return Choice(axis1: pick.axis1, axis2: pick.axis2, side: pick.pierSide)
    }

    private func estimatedSeconds(_ distanceDegrees: Double) -> Double {
        distanceDegrees / configuration.assumedSlewDegreesPerSecond + SkyWatcherDriver.slewOverheadSeconds
    }

    /// True if pointing along the straight path of both axes at equal speed stays above the tripod clearance (equatorial mounts).
    private func pathClears(_ from1: Double, _ from2: Double, _ to1: Double, _ to2: Double) -> Bool {
        if resolvedMode != .equatorial { return true }
        let delta1 = to1 - from1
        let delta2 = to2 - from2
        let total = max(abs(delta1), abs(delta2))
        if total < 1.0 { return true }
        let floor = configuration.limits.minimumAltitudeDegrees - configuration.limits.pathMarginDegrees
        let sinLatitude = AstroMath.sinDeg(location.latitude)
        let cosLatitude = AstroMath.cosDeg(location.latitude)
        for index in 0 ... SkyWatcherDriver.pathSamples {
            let travelled = total * Double(index) / Double(SkyWatcherDriver.pathSamples)
            let position1 = from1 + (delta1 >= 0 ? 1.0 : -1.0) * min(travelled, abs(delta1))
            let position2 = from2 + (delta2 >= 0 ? 1.0 : -1.0) * min(travelled, abs(delta2))
            let direction = model.direction(axis1Degrees: position1, axis2Degrees: position2)
            let altitude = AstroMath.asinDeg(direction.x * cosLatitude + direction.z * sinLatitude)
            if altitude < floor { return false }
        }
        return true
    }

    private func planSlew(_ goal: EquatorialCoordinate, _ start: Reading) throws -> [Leg] {
        var arrival = start.time
        var choice: Choice?
        for _ in 0 ..< SkyWatcherDriver.predictionPasses {
            let chosen = try choose(goal, arrival, start, keepSide: false)
            choice = chosen
            let distance = max(abs(chosen.axis1 - start.axis1), abs(chosen.axis2 - start.axis2))
            arrival = start.time.addingTimeInterval(estimatedSeconds(distance))
        }
        guard let final = choice else { throw MountError.outsideMountLimits }
        if pathClears(start.axis1, start.axis2, final.axis1, final.axis2) { return [Leg(axis1: final.axis1, axis2: final.axis2)] }
        if pathClears(start.axis1, start.axis2, start.axis1, final.axis2) && pathClears(start.axis1, final.axis2, final.axis1, final.axis2) {
            return [Leg(axis1: nil, axis2: final.axis2), Leg(axis1: final.axis1, axis2: nil)]
        }
        if pathClears(start.axis1, start.axis2, final.axis1, start.axis2) && pathClears(final.axis1, start.axis2, final.axis1, final.axis2) {
            return [Leg(axis1: final.axis1, axis2: nil), Leg(axis1: nil, axis2: final.axis2)]
        }
        throw MountError.outsideMountLimits
    }

    // MARK: Motion

    private func lowSpeedGotoMargin(_ axis: SkyWatcherAxis) -> Int {
        let value = 640.0 * Double(countsPerRevolution[axis.index]) / SkyWatcherDriver.siderealSecondsPerRevolution
        return Int(min(max(value, 0), 2e9))
    }

    /// Starts the goto of the axes named in `leg`; both axes must be stopped.
    private func startLeg(_ leg: Leg) throws -> Int {
        var started = 0
        let targets = [leg.axis1, leg.axis2]
        for axis in SkyWatcherAxis.allCases {
            guard let target = targets[axis.index] else { continue }
            if try startAxisGoto(axis, target) { started += 1 }
        }
        return started
    }

    private func startAxisGoto(_ axis: SkyWatcherAxis, _ targetDegrees: Double) throws -> Bool {
        let current = try readCounts(axis)
        let targetCounts = counts(axis, targetDegrees)
        if targetCounts < -SkyWatcherDriver.maximumCount || targetCounts > SkyWatcherDriver.maximumCount { throw MountError.outsideMountLimits }
        let delta = targetCounts - current
        if abs(delta) <= SkyWatcherDriver.completedCounts { return false }
        let magnitude = abs(delta)
        let direction: SkyWatcherDirection = delta > 0 ? .increasing : .decreasing
        let fast = magnitude > lowSpeedGotoMargin(axis)
        let mode: SkyWatcherMotionMode = fast ? .gotoFast : .gotoSlow
        try link.exchange(.setMotionMode, axis: axis, data: String(mode.code) + String(direction.code), operation: "set motion mode")
        if configuration.usesAbsoluteGotoTarget {
            try link.exchange(.setGotoTarget, axis: axis, data: SkyWatcherCodec.encodePosition(targetCounts), operation: "set target")
        } else {
            try link.exchange(.setGotoTargetIncrement, axis: axis, data: SkyWatcherCodec.encode24(magnitude), operation: "set target")
            let brake = min(magnitude, fast ? SkyWatcherDriver.highSpeedBrakeCounts : SkyWatcherDriver.lowSpeedBrakeCounts)
            try link.exchange(.setBrakePointIncrement, axis: axis, data: SkyWatcherCodec.encode24(brake), operation: "set brake point")
        }
        try startAxis(axis, gotoTarget: targetCounts)
        return true
    }

    /// Runs `axis` in speed mode at `degreesPerSecond` (signed, in the direction of increasing encoder angle); stops it if that is too slow to represent.
    private func setAxisRate(_ axis: SkyWatcherAxis, _ degreesPerSecond: Double) throws {
        let index = axis.index
        let countRate = degreesPerSecond * sense(axis)
        guard let speed = SkyWatcherCodec.speed(degreesPerSecond: countRate, countsPerRevolution: countsPerRevolution[index],
                                                timerFrequency: timerFrequency, highSpeedRatio: highSpeedRatio[index]) else {
            if statuses[index]?.isRunning != false { try stopAxis(axis) }
            return
        }
        let direction: SkyWatcherDirection = countRate > 0 ? .increasing : .decreasing
        let status = statuses[index]
        var reusable = false
        if let known = status {
            reusable = known.isRunning && known.isSpeedMode && !known.isFast && !speed.isHighSpeed
                && known.isDecreasing == (direction == .decreasing)
        }
        if reusable {
            try link.exchange(.setStepPeriod, axis: axis, data: SkyWatcherCodec.encode24(speed.period), operation: "set speed")
            return
        }
        if status == nil || status?.isRunning == true { try stopAxis(axis) }
        let mode: SkyWatcherMotionMode = speed.isHighSpeed ? .trackFast : .trackSlow
        try link.exchange(.setMotionMode, axis: axis, data: String(mode.code) + String(direction.code), operation: "set motion mode")
        try link.exchange(.setStepPeriod, axis: axis, data: SkyWatcherCodec.encode24(speed.period), operation: "set speed")
        try startAxis(axis)
        statuses[index] = SkyWatcherAxisStatus(isSpeedMode: true, isDecreasing: direction == .decreasing, isFast: speed.isHighSpeed,
                                               isRunning: true, isBlocked: false, isInitialized: true, isLevelSwitchOn: false)
    }

    private func siderealAxis1Rate() -> Double {
        (isSouthern ? -1.0 : 1.0) * SkyWatcherSky.siderealDegreesPerSecond
    }

    /// Starts tracking from the position the mount has now (both axes stopped or running in speed mode).
    private func startTracking() throws -> MountError? {
        let reading = try readAxes()
        anchor = pointing(reading)
        motion = .tracking
        lastServo = nil
        return try applyTracking(reading)
    }

    /// Sets the axes to track. Returns the limit error that makes tracking impossible here (tracking is then switched off and
    /// `trackingStopReason` says why); communication errors are thrown.
    private func applyTracking(_ reading: Reading) throws -> MountError? {
        do {
            if resolvedStrategy == .sidereal {
                try setAxisRate(.axis1, siderealAxis1Rate())
                if statuses[1]?.isRunning != false { try stopAxis(.axis2) }
            } else {
                let place = anchor ?? pointing(reading)
                try servoStep(reading, lead: trackingLead()) { _ in place }
                lastServo = clock.now()
            }
            return nil
        } catch let error as MountError {
            if error.isCommunicationFailure { throw error }
            stopTracking(error)
            return error
        }
    }

    private func trackingLead() -> Double { configuration.trackingUpdateIntervalSeconds + SkyWatcherDriver.trackingLeadExtraSeconds }

    private func nudgeAnchor(_ at: Date) -> EquatorialCoordinate {
        guard let state = nudge else { return anchor ?? EquatorialCoordinate(rightAscension: 0, declination: 0) }
        let elapsed = at.timeIntervalSince(state.start)
        return EquatorialCoordinate(
            rightAscension: state.origin.rightAscension + state.rightAscensionRate * elapsed,
            declination: AstroMath.clamp(state.origin.declination + state.declinationRate * elapsed,
                                         -SkyWatcherDriver.maximumDeclination, SkyWatcherDriver.maximumDeclination))
    }

    /// Sets the speeds of both axes so that the mount reaches the place `anchorAt` gives for the time `lead` seconds after `reading`.
    /// Closed loop: the rate includes the correction of the distance to where the anchor is now.
    private func servoStep(_ reading: Reading, lead: Double, anchorAt: (Date) -> EquatorialCoordinate) throws {
        let at = reading.time.addingTimeInterval(lead)
        let wanted = try choose(anchorAt(at), at, reading, keepSide: true)
        let limit = configuration.limits.maximumAxisRateDegreesPerSecond
        var rate1 = (wanted.axis1 - reading.axis1) / lead
        var rate2 = (wanted.axis2 - reading.axis2) / lead
        if abs(rate1) > limit * SkyWatcherDriver.trackingRateSlack || abs(rate2) > limit * SkyWatcherDriver.trackingRateSlack {
            if motion == .tracking { throw MountError.outsideMountLimits }
        }
        rate1 = AstroMath.clamp(rate1, -limit, limit)
        rate2 = AstroMath.clamp(rate2, -limit, limit)
        try setAxisRate(.axis1, rate1)
        try setAxisRate(.axis2, rate2)
    }

    private func endNudge() throws {
        nudge = nil
        try refreshStatuses()
        let reading = try readAxes()
        anchor = pointing(reading)
        if trackingEnabled {
            motion = .tracking
            lastServo = nil
            _ = try applyTracking(reading)
        } else {
            motion = .stopped
            try stopAxes()
            try waitUntilStopped()
        }
    }

    private func stopTracking(_ reason: MountError) {
        trackingEnabled = false
        trackingStopReason = reason
        motion = .stopped
        pendingStop = true
    }

    /// Equatorial sidereal tracking: stops it when the counterweight would rise above the limit.
    private func checkSiderealLimits(_ reading: Reading) {
        if motion != .tracking || resolvedMode != .equatorial { return }
        if abs(model.modelAxis1(reading.axis1)) > 90.0 + configuration.limits.meridianOverlapDegrees + SkyWatcherDriver.limitSlackDegrees {
            stopTracking(MountError.outsideMountLimits)
        }
    }

    // MARK: Service (called by readSlewing, once per poll)

    private func serviceMotion() throws {
        if pendingStop {
            try stopAxes()
            pendingStop = false
        }
        let now = clock.now()
        switch motion {
        case .stopped:
            if trackingEnabled { _ = try startTracking() }
        case .slewing: try serviceSlew(now)
        case .tracking: try serviceTracking(now)
        case .nudging: try serviceNudge(now)
        }
    }

    private func serviceSlew(_ now: Date) throws {
        guard let state = slew else {
            motion = .stopped
            return
        }
        if statuses.contains(where: { $0?.isGoto == true }) { return }
        if statuses.contains(where: { $0?.isRunning == true }) {
            // An axis runs in speed mode in the middle of a slew (a start that was repeated after a short GOTO had ended): stop it.
            try stopAxes()
            return
        }
        if now.timeIntervalSince(state.lastCommand) < SkyWatcherDriver.settleSeconds { return }
        if !state.legs.isEmpty {
            let next = state.legs.removeFirst()
            let started = try startLeg(next)
            state.lastCommand = started > 0 ? clock.now() : now.addingTimeInterval(-SkyWatcherDriver.settleSeconds)
            return
        }
        let reading = try readAxes()
        let error = pointing(reading).angularSeparation(to: state.goal)
        if error > configuration.refinementToleranceDegrees && state.refinements < SkyWatcherDriver.maximumRefinements {
            state.refinements += 1
            do {
                let at = reading.time.addingTimeInterval(SkyWatcherDriver.refinementLeadSeconds)
                let wanted = try choose(state.goal, at, reading, keepSide: true)
                let started = try startLeg(Leg(axis1: wanted.axis1, axis2: wanted.axis2))
                state.lastCommand = started > 0 ? clock.now() : now.addingTimeInterval(-SkyWatcherDriver.settleSeconds)
                return
            } catch let limit as MountError {
                if limit.isCommunicationFailure { throw limit }
            }
        }
        slew = nil
        anchor = state.goal
        if trackingEnabled {
            motion = .tracking
            lastServo = nil
            _ = try applyTracking(reading)
        } else {
            motion = .stopped
        }
    }

    private func serviceTracking(_ now: Date) throws {
        if resolvedStrategy == .sidereal {
            let status1 = statuses[0]
            let expectedDecreasing = (siderealAxis1Rate() * sense(.axis1)) < 0
            var healthy = false
            if let known = status1 { healthy = known.isRunning && known.isSpeedMode && known.isDecreasing == expectedDecreasing }
            if !healthy || statuses[1]?.isRunning == true { _ = try applyTracking(try readAxes()) }
            return
        }
        if let last = lastServo, now.timeIntervalSince(last) < configuration.trackingUpdateIntervalSeconds { return }
        let reading = try readAxes()
        let place = anchor ?? pointing(reading)
        do {
            try servoStep(reading, lead: trackingLead()) { _ in place }
            lastServo = clock.now()
        } catch let limit as MountError {
            if limit.isCommunicationFailure { throw limit }
            stopTracking(limit)
            try stopAxes()
            pendingStop = false
        }
    }

    private func serviceNudge(_ now: Date) throws {
        guard let state = nudge else {
            motion = .stopped
            return
        }
        if now >= state.deadline {
            try endNudge()
            return
        }
        if let last = lastServo, now.timeIntervalSince(last) < SkyWatcherDriver.nudgeUpdateSeconds { return }
        let reading = try readAxes()
        do {
            try servoStep(reading, lead: SkyWatcherDriver.nudgeLeadSeconds) { at in self.nudgeAnchor(at) }
            lastServo = clock.now()
        } catch let limit as MountError {
            if limit.isCommunicationFailure { throw limit }
            // The nudge has reached a limit of the mount: end it here and go on tracking from where the mount is.
            try endNudge()
        }
    }
}

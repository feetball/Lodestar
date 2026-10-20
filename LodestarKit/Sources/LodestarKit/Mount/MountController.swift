import Foundation

/// The GoTo state machine: connects to a mount through a `MountDriver`, keeps its position up to date, slews to J2000
/// targets, syncs, aborts, nudges and switches tracking, and watches every slew until the mount has arrived, stopped
/// short, failed or timed out.
///
/// ```
/// disconnected --connect--> idle --goto--> slewing --poll: arrived / failed / timeout--> idle
///                            |  \--nudge--> nudging --duration over (poll) / stopNudge--> idle
///                            \--abort (any phase)--> idle            3 failed polls in a row --> disconnected
/// ```
///
/// Safety rules enforced here: a target below `MountSettings.altitudeLimit` (now, and
/// `MountSettings.horizonLookaheadSeconds` from now) is never sent, and neither is a target within
/// `MountSettings.sunExclusionDegrees` of the Sun while the Sun is up; a goto while a slew or nudge runs is refused
/// (`MountError.slewInProgress`, `MountError.busy`) until `abort` has been called, and so is a goto or sync while
/// the mount's own "slewing" flag is set (a move started on the hand controller); a slew that exceeds
/// `MountSettings.maximumSlewSeconds` is aborted; a nudge ends by itself after its duration (the next `poll` sends the
/// stop, so poll at least once a second while nudging); every driver exchange has a timeout and no loop is unbounded.
///
/// Not thread safe. Call every method from one thread or queue, typically a background worker that calls `poll`
/// about once a second while the Aim screen shows the mount and `abort` on the user's request.
public final class MountController {
    private static let stopAttempts = 3

    /// The Sun's geometric altitude (degrees) above which it counts as up for the exclusion zone.
    private static let sunUpAltitude = -1.0

    private let driver: MountDriver
    private let clock: MountClock

    /// The observer used for the altitude limit and the epoch conversions; may be replaced when the user moves.
    public var observer: Observer

    /// The limits and timings in use.
    public let settings: MountSettings

    /// What the mount can do; nil before `connect` succeeded.
    public private(set) var capabilities: MountCapabilities?

    private var phase: MountPhase = .disconnected
    private var position: EquatorialCoordinate?
    private var mountPosition: EquatorialCoordinate?
    private var target: EquatorialCoordinate?
    private var sentTarget: EquatorialCoordinate?
    private var separation: Double?
    private var tracking: Bool?
    private var aligned: Bool?
    private var moving: Bool?
    private var slewStarted: Date?
    private var slewElapsed: Double?
    private var sawSlewing = false
    private var outcome: MountSlewOutcome?
    private var lastError: MountError?
    private var updated: Date?
    private var failures = 0
    private var nudgeDirection: MountNudgeDirection?
    private var nudgeEnds: Date?

    public init(driver: MountDriver, observer: Observer, settings: MountSettings = .standard,
                clock: MountClock = SystemMountClock()) {
        self.driver = driver
        self.observer = observer
        self.settings = settings
        self.clock = clock
    }

    /// The state as of the last call; cheap, never talks to the mount.
    public var status: MountStatus {
        MountStatus(phase: phase, position: position, target: target, separation: separation, isTracking: tracking,
                    isAligned: aligned, isMoving: moving, slewElapsedSeconds: slewElapsed, outcome: outcome,
                    lastError: lastError, updated: updated)
    }

    /// True while a session is open.
    public var isConnected: Bool { phase != .disconnected }

    // MARK: Session

    /// Opens the session: runs the driver's handshake and reads the first position. Does nothing but return the
    /// capabilities if the session is already open.
    @discardableResult
    public func connect() throws -> MountCapabilities {
        if let existing = capabilities, phase != .disconnected { return existing }
        do {
            let found = try driver.connect()
            let now = clock.now()
            aligned = found.isAligned
            try readPosition(now: now, alignment: found.isAligned)
            tracking = try driver.readTracking()
            moving = try driver.readSlewing()
            capabilities = found
            phase = .idle
            failures = 0
            lastError = nil
            outcome = nil
            target = nil
            sentTarget = nil
            separation = nil
            slewStarted = nil
            slewElapsed = nil
            nudgeDirection = nil
            nudgeEnds = nil
            updated = now
            return found
        } catch let error as MountError {
            lastError = error
            driver.disconnect()
            throw error
        }
    }

    /// Ends the session. A running nudge is stopped (best effort); a running slew is left to finish.
    public func disconnect() {
        if phase != .disconnected, let direction = nudgeDirection {
            do {
                try driver.stopNudge(direction: direction)
            } catch let error as MountError {
                lastError = error
            } catch {
                lastError = MountError.transport(detail: "stop failed")
            }
        }
        if phase != .disconnected { driver.disconnect() }
        phase = .disconnected
        nudgeDirection = nil
        nudgeEnds = nil
        slewStarted = nil
        slewElapsed = nil
    }

    // MARK: Polling

    /// One refresh cycle: reads the mount's position (and slewing/tracking flags), advances a running slew or nudge and
    /// returns the new `status`. Never throws: failures are recorded in `MountStatus.lastError`; after
    /// `MountSettings.maximumConsecutiveFailures` failed polls in a row the session ends
    /// (`MountError.connectionLost`). Costs two to four driver exchanges (about 30 to 200 ms on a Wi-Fi mount).
    @discardableResult
    public func poll() -> MountStatus {
        if phase == .disconnected { return status }
        let now = clock.now()
        do {
            switch phase {
            case .slewing: try pollSlewing(now: now)
            case .nudging: try pollNudging(now: now)
            default: try readState(now: now)
            }
            failures = 0
            lastError = nil
        } catch let error as MountError {
            recordFailure(error)
        } catch {
            recordFailure(MountError.transport(detail: "unexpected failure"))
        }
        updated = clock.now()
        return status
    }

    /// Polls every `MountSettings.pollIntervalSeconds` until the slew has ended and returns the final status. The loop is
    /// bounded by the maximum slew time, so it returns after at most about that long.
    @discardableResult
    public func awaitSettled() -> MountStatus {
        let limit = Int((settings.maximumSlewSeconds / settings.pollIntervalSeconds).rounded(.up)) + 10
        var iterations = 0
        while phase == .slewing && iterations < limit {
            poll()
            if phase != .slewing { break }
            clock.sleep(seconds: settings.pollIntervalSeconds)
            iterations += 1
        }
        return status
    }

    // MARK: Commands

    /// Starts a slew to the J2000 place `target` (with its `properMotion`, if it has one) and returns as soon as the mount has
    /// accepted it; watch it with `poll` or `awaitSettled`.
    ///
    /// - Throws: `MountError.notConnected`, `slewInProgress` (call `abort` first), `busy` (nudging), `invalidInput`,
    ///   `notSupported`, `belowHorizonLimit` (checked with the observer's sky now and
    ///   `MountSettings.horizonLookaheadSeconds` from now), `nearSun` (the Sun is up and the target is within
    ///   `MountSettings.sunExclusionDegrees` of it, now or `horizonLookaheadSeconds` from now), and whatever the mount
    ///   answers (`notAligned`, `mountHorizonLimit`, `parked`, …).
    public func goto(_ target: EquatorialCoordinate, properMotion: ProperMotion? = nil) throws {
        let found = try requireConnected()
        try requireFinite(target)
        switch phase {
        case .slewing: throw MountError.slewInProgress
        case .nudging: throw MountError.busy
        default: break
        }
        if moving == true { throw MountError.slewInProgress }
        if !found.canSlew { throw MountError.notSupported(feature: .slew) }
        let now = clock.now()
        try checkAltitude(target, properMotion, now)
        try checkSun(target, properMotion, now)
        let sent = driver.epoch.fromJ2000(target, frame: SkyFrame(date: now, observer: observer), properMotion: properMotion)
        do {
            try driver.slew(to: sent)
        } catch let error as MountError {
            lastError = error
            if error.isCommunicationFailure { stopQuietly() }
            throw error
        }
        phase = .slewing
        self.target = target
        sentTarget = sent
        separation = mountPosition?.angularSeparation(to: sent)
        slewStarted = now
        slewElapsed = 0.0
        sawSlewing = false
        outcome = nil
        lastError = nil
        updated = now
    }

    /// Tells the mount that it points at the J2000 place `target` now (after the user centred that star), and returns by
    /// how much the mount's idea of its position changed.
    ///
    /// - Throws: `MountError.syncOffsetTooLarge` if the change exceeds `MountSettings.maximumSyncOffsetDegrees`, plus
    ///   the errors listed at `goto` that apply (not connected, busy, not supported, the mount's refusals).
    @discardableResult
    public func sync(_ target: EquatorialCoordinate, properMotion: ProperMotion? = nil) throws -> MountSyncResult {
        let found = try requireConnected()
        try requireFinite(target)
        switch phase {
        case .slewing: throw MountError.slewInProgress
        case .nudging: throw MountError.busy
        default: break
        }
        if moving == true { throw MountError.slewInProgress }
        if !found.canSync { throw MountError.notSupported(feature: .sync) }
        let now = clock.now()
        let sent = driver.epoch.fromJ2000(target, frame: SkyFrame(date: now, observer: observer), properMotion: properMotion)
        let before = try driver.readPosition()
        let offset = before.angularSeparation(to: sent)
        if offset > settings.maximumSyncOffsetDegrees {
            throw MountError.syncOffsetTooLarge(offsetDegrees: offset, limitDegrees: settings.maximumSyncOffsetDegrees)
        }
        do {
            try driver.sync(to: sent)
        } catch let error as MountError {
            lastError = error
            throw error
        }
        storePosition(sent, now: now)
        lastError = nil
        updated = now
        return MountSyncResult(offsetDegrees: offset)
    }

    /// Stops the mount: halts a slew or nudge (each stop is attempted up to three times on communication failures) and
    /// returns to `MountPhase.idle`. Allowed in every connected phase.
    ///
    /// - Throws: `MountError` if the mount could not be stopped; the phase is then unchanged and the call can be repeated.
    public func abort() throws {
        _ = try requireConnected()
        let direction = nudgeDirection
        var failure = repeatUntilDone { try driver.abort() }
        // The abort of some protocols (NexStar, Alpaca) cancels only a GoTo, so a running nudge is stopped on its own,
        // whatever became of the abort. The first failure is the one reported.
        if let toStop = direction {
            let stopFailure = repeatUntilDone { try driver.stopNudge(direction: toStop) }
            if failure == nil { failure = stopFailure }
        }
        if let failure {
            lastError = failure
            throw failure
        }
        if phase == .slewing { finishSlew(.aborted) }
        phase = .idle
        nudgeDirection = nil
        nudgeEnds = nil
        moving = false
        lastError = nil
    }

    /// Moves the mount in `direction` at `rate` for `durationSeconds` (at most `MountSettings.maximumNudgeSeconds`). The
    /// nudge ends at the first `poll` after the duration, or at `stopNudge`. A nudge in another direction replaces a
    /// running one.
    public func nudge(_ direction: MountNudgeDirection, rate: MountNudgeRate = .center, durationSeconds: Double = 0.5) throws {
        let found = try requireConnected()
        if !(durationSeconds > 0) || durationSeconds > settings.maximumNudgeSeconds {
            throw MountError.invalidInput(detail: "the nudge must last more than 0 and at most \(settings.maximumNudgeSeconds) seconds")
        }
        if phase == .slewing { throw MountError.slewInProgress }
        if !found.canNudge { throw MountError.notSupported(feature: .nudge) }
        if let previous = nudgeDirection, previous != direction {
            try driver.stopNudge(direction: previous)
            nudgeDirection = nil
            nudgeEnds = nil
        }
        let now = clock.now()
        do {
            try driver.startNudge(direction: direction, rate: rate, durationSeconds: durationSeconds)
        } catch let error as MountError {
            lastError = error
            var stopped = true
            do {
                try driver.stopNudge(direction: direction)
            } catch {
                // Already failing; the error above is what the caller needs to see.
                stopped = false
            }
            if stopped {
                // What ran before is stopped (the previous direction above, this one just now): the controller is idle and
                // not left in a nudge that has no direction.
                if phase == .nudging { phase = .idle }
                nudgeDirection = nil
                nudgeEnds = nil
            } else {
                // The move may be running although the stop could not be confirmed: it stays on the books, so that
                // `stopNudge`, `abort` and the end of its duration still send the stop.
                phase = .nudging
                nudgeDirection = direction
                nudgeEnds = now.addingTimeInterval(durationSeconds)
            }
            throw error
        }
        phase = .nudging
        nudgeDirection = direction
        nudgeEnds = now.addingTimeInterval(durationSeconds)
        lastError = nil
    }

    /// Ends a running nudge now. Does nothing when no nudge is running.
    public func stopNudge() throws {
        _ = try requireConnected()
        guard let direction = nudgeDirection else { return }
        if let failure = repeatUntilDone({ try driver.stopNudge(direction: direction) }) {
            lastError = failure
            throw failure
        }
        if phase == .nudging { phase = .idle }
        nudgeDirection = nil
        nudgeEnds = nil
        moving = nil
    }

    /// Switches the mount's tracking on or off (refused while a slew runs).
    public func setTracking(_ enabled: Bool) throws {
        let found = try requireConnected()
        if phase == .slewing { throw MountError.slewInProgress }
        if !found.canSetTracking { throw MountError.notSupported(feature: .tracking) }
        do {
            try driver.setTracking(enabled)
        } catch let error as MountError {
            lastError = error
            throw error
        }
        tracking = enabled
        lastError = nil
    }

    /// Sets the mount's site and clock (UTC, no zone offset) from `location` and `date` (default: the clock's now).
    /// Needed by mounts that compute their own sky (OnStep, SynScan, NexStar hand controls).
    public func setSiteAndTime(location: GeographicLocation, date: Date? = nil) throws {
        let found = try requireConnected()
        if phase == .slewing { throw MountError.slewInProgress }
        if !found.canSetSiteAndTime { throw MountError.notSupported(feature: .siteAndTime) }
        do {
            try driver.setSiteAndTime(location: location, date: date ?? clock.now())
        } catch let error as MountError {
            lastError = error
            throw error
        }
        lastError = nil
    }

    // MARK: Polling steps

    private func pollSlewing(now: Date) throws {
        let started = slewStarted ?? now
        let elapsed = now.timeIntervalSince(started)
        slewElapsed = elapsed
        if elapsed > settings.maximumSlewSeconds {
            try driver.abort()
            moving = false
            finishSlew(.failed(error: MountError.slewTimeout(seconds: settings.maximumSlewSeconds)))
            return
        }
        let isMoving = try driver.readSlewing()
        moving = isMoving
        let reading = try driver.readPosition()
        storePosition(reading, now: now)
        if isMoving {
            sawSlewing = true
            return
        }
        guard let goal = sentTarget else { return }
        let remaining = reading.angularSeparation(to: goal)
        if remaining <= settings.arrivalToleranceDegrees {
            finishSlew(.arrived(separation: remaining))
        } else if !sawSlewing && elapsed < settings.slewStartGraceSeconds {
            return
        } else {
            finishSlew(.failed(error: MountError.slewStopped(remainingDegrees: remaining)))
        }
    }

    private func pollNudging(now: Date) throws {
        if let ends = nudgeEnds, let direction = nudgeDirection, now >= ends {
            try driver.stopNudge(direction: direction)
            phase = .idle
            nudgeDirection = nil
            nudgeEnds = nil
            moving = nil
        }
        try readState(now: now)
    }

    private func readState(now: Date) throws {
        if aligned != true { aligned = try driver.readAligned() ?? aligned }
        try readPosition(now: now, alignment: aligned)
        moving = try driver.readSlewing()
        tracking = try driver.readTracking()
    }

    /// Reads and stores the position; before an alignment the mount's coordinates may be meaningless, which is not an error.
    private func readPosition(now: Date, alignment: Bool?) throws {
        do {
            storePosition(try driver.readPosition(), now: now)
        } catch MountError.malformedReply(let detail) {
            if alignment != false { throw MountError.malformedReply(detail: detail) }
        }
    }

    private func recordFailure(_ error: MountError) {
        failures += 1
        lastError = error
        if failures < settings.maximumConsecutiveFailures { return }
        // A nudge keeps an axis turning until the mount is told to stop, and the poll that would have ended it will not
        // come again. The link may be gone, so this is one best-effort attempt that never throws.
        if phase == .nudging, let direction = nudgeDirection { stopNudgeQuietly(direction) }
        if phase == .slewing {
            stopQuietly()
            outcome = .failed(error: MountError.connectionLost)
        }
        phase = .disconnected
        lastError = MountError.connectionLost
        nudgeDirection = nil
        nudgeEnds = nil
        slewStarted = nil
        slewElapsed = nil
        driver.disconnect()
    }

    // MARK: Helpers

    @discardableResult
    private func requireConnected() throws -> MountCapabilities {
        guard let found = capabilities, phase != .disconnected else { throw MountError.notConnected }
        return found
    }

    private func requireFinite(_ target: EquatorialCoordinate) throws {
        if !target.rightAscension.isFinite || !target.declination.isFinite {
            throw MountError.invalidInput(detail: "the target coordinates are not numbers")
        }
    }

    private func checkAltitude(_ target: EquatorialCoordinate, _ properMotion: ProperMotion?, _ now: Date) throws {
        let limit = settings.altitudeLimit
        let offsets = settings.horizonLookaheadSeconds > 0 ? [0.0, settings.horizonLookaheadSeconds] : [0.0]
        for offset in offsets {
            let frame = SkyFrame(date: now.addingTimeInterval(offset), observer: observer)
            let altitude = frame.horizontal(j2000: target, properMotion: properMotion, refraction: false).altitude
            if altitude < limit { throw MountError.belowHorizonLimit(altitude: altitude, limit: limit) }
        }
    }

    /// Refuses a target that is closer to the Sun than `MountSettings.sunExclusionDegrees` while the Sun is up. The check
    /// looks at the sky now and `MountSettings.horizonLookaheadSeconds` from now (the Sun may rise during the slew), and
    /// compares positions, not identities: Venus near inferior conjunction, the Moon at new moon or a comet in the glare
    /// are as dangerous as the Sun itself. Both places are geometric, topocentric and in the horizontal frame, so no
    /// frame conversion can put them out of step. The Sun counts as up from -1 degrees, which covers its disc and the
    /// refraction at the horizon.
    private func checkSun(_ target: EquatorialCoordinate, _ properMotion: ProperMotion?, _ now: Date) throws {
        let limit = settings.sunExclusionDegrees
        let offsets = settings.horizonLookaheadSeconds > 0 ? [0.0, settings.horizonLookaheadSeconds] : [0.0]
        for offset in offsets {
            let frame = SkyFrame(date: now.addingTimeInterval(offset), observer: observer)
            let sun = frame.horizontal(of: .sun, refraction: false)
            if sun.altitude <= MountController.sunUpAltitude { continue }
            let place = frame.horizontal(j2000: target, properMotion: properMotion, refraction: false)
            let distance = place.angularSeparation(to: sun)
            if distance < limit { throw MountError.nearSun(separationDegrees: distance, limitDegrees: limit) }
        }
    }

    private func storePosition(_ reading: EquatorialCoordinate, now: Date) {
        mountPosition = reading
        position = driver.epoch.toJ2000(reading, frame: SkyFrame(date: now, observer: observer))
        if let goal = sentTarget {
            separation = reading.angularSeparation(to: goal)
        } else {
            separation = nil
        }
    }

    private func finishSlew(_ result: MountSlewOutcome) {
        outcome = result
        phase = .idle
        slewStarted = nil
        slewElapsed = nil
    }

    /// Tells the mount to stop after an exchange failed so badly that a slew may or may not have started.
    private func stopQuietly() {
        do {
            try driver.abort()
        } catch {
            // Nothing more can be done; the caller reports the original failure.
        }
    }

    /// Tells the mount to end the nudge in `direction` when the session is being given up; a failure changes nothing.
    private func stopNudgeQuietly(_ direction: MountNudgeDirection) {
        do {
            try driver.stopNudge(direction: direction)
        } catch {
            // The link is probably gone; the session ends with `connectionLost` either way.
        }
    }

    /// Runs `action` up to three times while it fails with communication errors; returns the last error, or nil on success.
    private func repeatUntilDone(_ action: () throws -> Void) -> MountError? {
        var last: MountError?
        for _ in 1 ... MountController.stopAttempts {
            do {
                try action()
                return nil
            } catch let error as MountError {
                last = error
                if !error.isCommunicationFailure { return error }
            } catch {
                return MountError.transport(detail: "unexpected failure")
            }
        }
        return last
    }
}

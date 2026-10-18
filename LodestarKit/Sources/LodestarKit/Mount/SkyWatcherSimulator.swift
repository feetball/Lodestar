import Foundation

/// A deterministic xorshift64* generator, identical in Swift and Kotlin, for the random faults of the simulators.
public final class SkyWatcherSimulatedRandom {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x2545F4914F6CDD1D : seed
    }

    /// The next value in [0, 1).
    public func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let mixed = state &* 0x2545F4914F6CDD1D
        return Double(mixed >> 11) / 9007199254740992.0
    }
}

/// A Sky-Watcher motor controller behind a `MountTransport`, for tests, UI previews and the demo mode: two axes with encoders that
/// turn at finite speeds, the controller's commands and error replies, and a mount whose real geometry has the `errors` that an alignment
/// has to find. It answers every command of `SkyWatcherCodec` like the firmware (`=` data, `!` code), requires `F` before motion
/// commands, accepts speed mode (step period, optionally high speed), GOTO by increment or by absolute target with acceleration and braking,
/// stops with `K` (deceleration) and `L` (instant), and returns an axis to speed mode when it stops.
///
/// Faults: the base class's `inject` drops or damages the reply to a command (the label is the letter and channel, e.g. `j1`);
/// `requestLossProbability`, `replyLossProbability` and `garbleProbability` add random datagram loss and damage from a seeded
/// generator. Time is the shared `ManualMountClock`; every reply costs the latency, a missing reply costs the caller's timeout.
///
/// The true pointing of the simulated mount is `truePointing()` (a direction in the local frame of `SkyWatcherPointingModel`) and
/// `truePlace()` (an apparent place of date): what the camera really sees, as opposed to what the driver believes.
public final class SkyWatcherSimulator: MountSimulatedStreamTransport {
    private enum Phase { case stopped, speed, goto, braking }

    private final class SimulatedAxis {
        var position = 0.0
        var velocity = 0.0
        var phase = Phase.stopped
        var modeCode: Character = "1"
        var directionCode: Character = "0"
        var period = 0
        var increment = 0
        var brake = 0
        var target = 0.0
        var absoluteTarget: Int?
        var gotoFast = false
        var initialized = false
        var lastFast = false
    }

    /// The simulator's default start time, for demos: 2026-10-18 04:00 UTC.
    public static let defaultStart = Date(timeIntervalSince1970: 1_792_296_000)

    /// Where the simulated mount stands.
    public let location: GeographicLocation
    /// How the axes are arranged.
    public let mode: SkyWatcherMountMode
    /// The real errors of the mount (home position error, base tilt, orthogonality, cone).
    public let errors: SkyWatcherPointingErrors
    /// The motor board version it reports.
    public let version: SkyWatcherVersion
    /// Counts per revolution of both axes.
    public let countsPerRevolution: Int
    /// The step timer frequency.
    public let timerFrequency: Int
    /// The high-speed ratio.
    public let highSpeedRatio: Int
    /// The fastest the axes turn.
    public let maximumSlewDegreesPerSecond: Double
    /// How fast the axes accelerate and brake.
    public let accelerationDegreesPerSecondSquared: Double
    /// The constant speed of low-speed GOTOs.
    public let lowSpeedGotoDegreesPerSecond: Double
    /// True if the position count of axis 1 decreases when the axis turns in the positive direction.
    public let axis1Inverted: Bool
    /// True if the position count of axis 2 decreases when the axis turns in the positive direction.
    public let axis2Inverted: Bool

    private let axes = [SimulatedAxis(), SimulatedAxis()]

    // The counts that the encoders lack compared to the physical position, after the position was set with `E`.
    private var encoderShift = [0.0, 0.0]
    private var lastTime: Double
    private let random: SkyWatcherSimulatedRandom
    private var sleeping = false

    /// The chance that a command is lost before the controller sees it (0 to 1).
    public var requestLossProbability = 0.0

    /// The chance that the reply to a command is lost (0 to 1).
    public var replyLossProbability = 0.0

    /// The chance that a reply is damaged: a bad character, cut short, a stray byte in front, or sent twice (0 to 1).
    public var garbleProbability = 0.0

    /// The number of GOTOs started.
    public private(set) var gotosStarted = 0

    /// The number of speed-mode starts.
    public private(set) var speedStarts = 0

    /// The highest speed any axis reached, in degrees per second.
    public private(set) var peakSpeedDegreesPerSecond = 0.0

    public init(clock: ManualMountClock, location: GeographicLocation, mode: SkyWatcherMountMode = .altAzimuth,
                errors: SkyWatcherPointingErrors = SkyWatcherPointingErrors(),
                version: SkyWatcherVersion = SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5),
                countsPerRevolution: Int = 9_216_000, timerFrequency: Int = 1_500_000, highSpeedRatio: Int = 32,
                maximumSlewDegreesPerSecond: Double = 3.0, accelerationDegreesPerSecondSquared: Double = 6.0,
                lowSpeedGotoDegreesPerSecond: Double = 0.5, axis1Inverted: Bool = false, axis2Inverted: Bool = false,
                latencySeconds: Double = 0.05, chunkSize: Int = 0, seed: UInt64 = 1) {
        self.location = location
        self.mode = mode
        self.errors = errors
        self.version = version
        self.countsPerRevolution = countsPerRevolution
        self.timerFrequency = timerFrequency
        self.highSpeedRatio = highSpeedRatio
        self.maximumSlewDegreesPerSecond = maximumSlewDegreesPerSecond
        self.accelerationDegreesPerSecondSquared = accelerationDegreesPerSecondSquared
        self.lowSpeedGotoDegreesPerSecond = lowSpeedGotoDegreesPerSecond
        self.axis1Inverted = axis1Inverted
        self.axis2Inverted = axis2Inverted
        lastTime = clock.secondsSince1970
        random = SkyWatcherSimulatedRandom(seed: seed)
        super.init(clock: clock, latencySeconds: latencySeconds, chunkSize: chunkSize)
    }

    /// True once the axes were told that initialization is done (`F`).
    public var isInitialized: Bool { axes[0].initialized && axes[1].initialized }

    /// True while at least one axis moves.
    public var isMoving: Bool {
        advance()
        return axes[0].phase != .stopped || axes[1].phase != .stopped
    }

    // MARK: Test access

    /// The encoder angle of axis 1 in degrees.
    public var axis1Degrees: Double { axisDegrees(0) }

    /// The encoder angle of axis 2 in degrees.
    public var axis2Degrees: Double { axisDegrees(1) }

    private func axisDegrees(_ index: Int) -> Double {
        advance()
        let inverted = index == 0 ? axis1Inverted : axis2Inverted
        return (inverted ? -1.0 : 1.0) * axes[index].position * 360.0 / Double(countsPerRevolution)
    }

    private func shiftDegrees(_ index: Int) -> Double {
        let inverted = index == 0 ? axis1Inverted : axis2Inverted
        return (inverted ? -1.0 : 1.0) * encoderShift[index] * 360.0 / Double(countsPerRevolution)
    }

    /// The physical angle of the axis: the encoder angle plus the shift that `E` (set position) caused.
    private func physicalDegrees(_ index: Int) -> Double { axisDegrees(index) + shiftDegrees(index) }

    /// The errors as they are now: `errors` with the home position error changed by what `E` (set position) did to the encoder
    /// zero. A pointing model with these errors turns encoder angles into the real pointing.
    public var effectiveErrors: SkyWatcherPointingErrors {
        SkyWatcherPointingErrors(axis1Index: errors.axis1Index + shiftDegrees(0), axis2Index: errors.axis2Index + shiftDegrees(1),
                                 baseTiltX: errors.baseTiltX, baseTiltY: errors.baseTiltY, orthogonality: errors.orthogonality,
                                 cone: errors.cone)
    }

    /// Moves the axes to the given encoder angles at once and stops them (as if the user turned the mount by hand before connecting).
    public func placeAxes(axis1Degrees: Double, axis2Degrees: Double) {
        advance()
        for index in 0 ..< 2 {
            let inverted = index == 0 ? axis1Inverted : axis2Inverted
            let degrees = index == 0 ? axis1Degrees : axis2Degrees
            let axis = axes[index]
            axis.position = (inverted ? -1.0 : 1.0) * degrees * Double(countsPerRevolution) / 360.0
            axis.velocity = 0.0
            axis.phase = .stopped
            axis.modeCode = "1"
        }
    }

    /// The direction the telescope really points at, in the local frame of `SkyWatcherPointingModel` (true geometry with `errors`).
    public func truePointing() -> Vector3 {
        let theta = AstroMath.radians(physicalDegrees(0) + errors.axis1Index)
        let secondary = AstroMath.radians(physicalDegrees(1) + errors.axis2Index)
        let phi = mode == .equatorial ? secondary + Double.pi / 2 : secondary
        let cone = AstroMath.radians(errors.cone)
        var vector = Vector3(sin(cone), cos(cone) * cos(phi), cos(cone) * sin(phi))
        vector = Matrix3.rotationY(AstroMath.radians(errors.orthogonality)) * vector
        vector = Matrix3.rotationZ(-theta) * vector
        vector = Matrix3.rotationX(AstroMath.radians(errors.baseTiltX)) * vector
        vector = Matrix3.rotationY(AstroMath.radians(errors.baseTiltY)) * vector
        if mode == .equatorial && location.latitude < 0 { vector = Vector3(vector.x, -vector.y, -vector.z) }
        return vector
    }

    /// The apparent place of date the telescope really points at now.
    public func truePlace() -> EquatorialCoordinate {
        let frame = SkyFrame(date: clock.now(), observer: Observer(location: location))
        return SkyWatcherSky.apparentPlace(truePointing(), localSiderealTime: frame.localApparentSiderealTime, latitude: location.latitude,
                                           mode: mode)
    }

    // MARK: Protocol

    public override func consume(_ pending: [UInt8]) -> Int {
        var end = -1
        for index in pending.indices where Int(pending[index]) == SkyWatcherCodec.terminator {
            end = index
            break
        }
        if end < 0 { return 0 }
        var start = -1
        var index = end - 1
        while index >= 0 {
            if Int(pending[index]) == SkyWatcherCodec.leadingByte {
                start = index
                break
            }
            index -= 1
        }
        if start >= 0 { handle(Array(pending[start ..< end])) }
        return end + 1
    }

    private func handle(_ line: [UInt8]) {
        let text = MountText.latin1(line)
        let scalars = Array(text.unicodeScalars)
        let label = scalars.count >= 3 ? String(String.UnicodeScalarView(scalars[1 ..< 3])) : text
        if random.next() < requestLossProbability {
            noReply(label)
            return
        }
        advance()
        let answer = execute(scalars)
        let bytes = MountText.latin1Bytes(answer)
        if random.next() < replyLossProbability {
            noReply(label)
            return
        }
        reply(label, random.next() < garbleProbability ? garbled(bytes) : bytes)
    }

    private func garbled(_ bytes: [UInt8]) -> [UInt8] {
        let kind = Int(random.next() * 4)
        switch kind {
        case 0:
            var copy = bytes
            let index = 1 + Int(random.next() * Double(max(copy.count - 2, 1)))
            copy[min(index, copy.count - 1)] = UInt8(ascii: "G")
            return copy
        case 1:
            return Array(bytes[0 ..< max(0, bytes.count - 2)])
        case 2:
            return [UInt8(ascii: "\n")] + bytes
        default:
            return bytes + bytes
        }
    }

    private static let digits = Array("0123456789ABCDEF")

    private func failure(_ code: Int) -> String { "!\(SkyWatcherSimulator.digits[code & 15])\r" }

    private func success(_ payload: String) -> String { "=\(payload)\r" }

    private func hex24(_ value: Int) -> String { (try? SkyWatcherCodec.encode24(value)) ?? "000000" }

    private func position24(_ counts: Int) -> String { (try? SkyWatcherCodec.encodePosition(counts)) ?? "000080" }

    private func expectedDataLength(_ command: SkyWatcherCommand) -> Int {
        switch command {
        case .setMotionMode: 2
        case .setPosition, .setGotoTargetIncrement, .setBrakePointIncrement, .setGotoTarget, .setStepPeriod, .setLongGotoStepPeriod,
             .setBrakeSteps, .extendedSetting, .extendedInquire: 6
        case .setSleep, .setAuxSwitch, .setAutoguideSpeed, .inquireIncrement: 1
        default: 0
        }
    }

    private func execute(_ text: [Unicode.Scalar]) -> String {
        if text.count < 3 { return failure(1) }
        guard let command = SkyWatcherCommand.fromLetter(Character(text[1])) else { return failure(0) }
        let dataScalars = Array(text[3...])
        if dataScalars.count != expectedDataLength(command) { return failure(1) }
        for scalar in dataScalars where !((scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 70)) {
            return failure(3)
        }
        let data = String(String.UnicodeScalarView(dataScalars))
        let targets: [Int]
        switch text[2] {
        case "1": targets = [0]
        case "2": targets = [1]
        case "3":
            if command == .initializationDone || command == .startMotion || command == .stopMotion || command == .instantStop {
                targets = [0, 1]
            } else {
                return failure(3)
            }
        default: return failure(3)
        }
        var result = success("")
        for index in targets {
            result = run(command, index, data)
            if result.hasPrefix("!") { return result }
        }
        return result
    }

    private func requireReady(_ axis: SimulatedAxis) -> String? {
        if sleeping { return failure(5) }
        if !axis.initialized { return failure(4) }
        return nil
    }

    private func run(_ command: SkyWatcherCommand, _ index: Int, _ data: String) -> String {
        let axis = axes[index]
        switch command {
        case .inquireVersion: return success(SkyWatcherCodec.encodeVersion(version))
        case .inquireCountsPerRevolution: return success(hex24(countsPerRevolution))
        case .inquireTimerFrequency: return success(hex24(timerFrequency))
        case .inquireHighSpeedRatio: return success((try? SkyWatcherCodec.encode8(highSpeedRatio)) ?? "01")
        case .inquireStatus:
            return success(SkyWatcherCodec.encodeStatus(SkyWatcherAxisStatus(
                isSpeedMode: axis.modeCode == "1" || axis.modeCode == "3", isDecreasing: axis.directionCode == "1",
                isFast: axis.modeCode == "0" || axis.modeCode == "3", isRunning: axis.phase != .stopped, isBlocked: false,
                isInitialized: axis.initialized, isLevelSwitchOn: false)))
        case .inquirePosition, .inquireAxisPosition:
            return success(position24(roundedCount(axis.position)))
        case .inquireGotoTarget: return success(position24(roundedCount(axis.target)))
        case .inquireStepPeriod: return success(hex24(axis.period))
        case .inquireIncrement: return success(hex24(axis.increment))
        case .inquireBrakePoint, .inquireBrakeSteps: return success(hex24(axis.brake))
        case .inquireTrackingPeriod:
            let speed = SkyWatcherCodec.speed(degreesPerSecond: SkyWatcherSky.siderealDegreesPerSecond, countsPerRevolution: countsPerRevolution,
                                              timerFrequency: timerFrequency, highSpeedRatio: highSpeedRatio)
            return success(hex24(speed?.period ?? 0))
        case .inquirePECPeriod: return success(hex24(countsPerRevolution / 40))
        case .extendedInquire: return success(hex24(0x8000))
        case .extendedSetting, .setAuxSwitch, .setAutoguideSpeed: return success("")
        case .setSleep:
            sleeping = data == "1"
            return success("")
        case .initializationDone:
            axis.initialized = true
            return success("")
        case .setPosition:
            if axis.phase != .stopped { return failure(2) }
            let newPosition = Double((try? SkyWatcherCodec.decodePosition(data)) ?? 0)
            encoderShift[index] += axis.position - newPosition
            axis.position = newPosition
            return success("")
        case .stopMotion:
            if axis.phase == .speed || axis.phase == .goto { axis.phase = .braking }
            return success("")
        case .instantStop:
            halt(axis)
            return success("")
        default: break
        }
        if let refusal = requireReady(axis) { return refusal }
        switch command {
        case .setMotionMode:
            if axis.phase != .stopped { return failure(2) }
            let scalars = Array(data.unicodeScalars)
            let modeCharacter = Character(scalars[0])
            let directionCharacter = Character(scalars[1])
            if !("0" ... "3").contains(modeCharacter) || (directionCharacter != "0" && directionCharacter != "1") { return failure(3) }
            axis.modeCode = modeCharacter
            axis.directionCode = directionCharacter
        case .setGotoTargetIncrement:
            axis.increment = (try? SkyWatcherCodec.decode24(data)) ?? 0
            axis.absoluteTarget = nil
        case .setBrakePointIncrement, .setBrakeSteps:
            axis.brake = (try? SkyWatcherCodec.decode24(data)) ?? 0
        case .setLongGotoStepPeriod:
            break
        case .setGotoTarget:
            axis.absoluteTarget = (try? SkyWatcherCodec.decodePosition(data)) ?? 0
        case .setStepPeriod:
            if axis.phase == .speed && axis.lastFast { return failure(2) }
            let period = (try? SkyWatcherCodec.decode24(data)) ?? 0
            if period < 1 { return failure(3) }
            axis.period = period
            if axis.phase == .speed { axis.velocity = speedVelocity(axis) }
        case .startMotion:
            return start(axis)
        default:
            break
        }
        return success("")
    }

    private func roundedCount(_ value: Double) -> Int {
        if !value.isFinite { return 0 }
        return min(max(Int(min(max(value, -2e9), 2e9).rounded()), -0x7FFFFF), 0x7FFFFF)
    }

    private func halt(_ axis: SimulatedAxis) {
        axis.phase = .stopped
        axis.velocity = 0.0
        axis.modeCode = "1"
    }

    private func countsPerSecond(_ degreesPerSecond: Double) -> Double { degreesPerSecond * Double(countsPerRevolution) / 360.0 }

    private func speedVelocity(_ axis: SimulatedAxis) -> Double {
        let factor = axis.modeCode == "3" ? Double(highSpeedRatio) : 1.0
        let magnitude = min(factor * Double(timerFrequency) / Double(max(axis.period, 1)), countsPerSecond(maximumSlewDegreesPerSecond))
        return axis.directionCode == "1" ? -magnitude : magnitude
    }

    private func start(_ axis: SimulatedAxis) -> String {
        if axis.phase != .stopped { return failure(2) }
        switch axis.modeCode {
        case "1", "3":
            if axis.period < 1 { return failure(3) }
            axis.lastFast = axis.modeCode == "3"
            axis.velocity = speedVelocity(axis)
            axis.phase = .speed
            speedStarts += 1
        default:
            let signed = axis.directionCode == "1" ? -axis.increment : axis.increment
            if let absolute = axis.absoluteTarget {
                axis.target = Double(absolute)
            } else {
                axis.target = axis.position + Double(signed)
            }
            axis.gotoFast = axis.modeCode == "0"
            axis.lastFast = axis.gotoFast
            axis.phase = .goto
            axis.velocity = 0.0
            gotosStarted += 1
        }
        return success("")
    }

    // MARK: Physics

    private func advance() {
        let now = clock.secondsSince1970
        var remaining = now - lastTime
        lastTime = now
        if !(remaining > 0) { return }
        let step = max(0.02, remaining / 20000.0)
        while remaining > 1e-12 {
            let dt = min(remaining, step)
            for axis in axes { move(axis, dt) }
            remaining -= dt
        }
        for axis in axes {
            let speed = abs(axis.velocity) * 360.0 / Double(countsPerRevolution)
            if speed > peakSpeedDegreesPerSecond { peakSpeedDegreesPerSecond = speed }
        }
    }

    private func move(_ axis: SimulatedAxis, _ dt: Double) {
        let acceleration = countsPerSecond(accelerationDegreesPerSecondSquared)
        switch axis.phase {
        case .stopped:
            break
        case .speed:
            axis.position += axis.velocity * dt
        case .braking:
            let speed = abs(axis.velocity)
            let reduced = speed - acceleration * dt
            let sign = axis.velocity >= 0 ? 1.0 : -1.0
            if reduced <= 0 {
                axis.position += sign * speed * dt / 2
                halt(axis)
            } else {
                axis.position += sign * (speed + reduced) / 2 * dt
                axis.velocity = sign * reduced
            }
        case .goto:
            let distance = axis.target - axis.position
            let remainingDistance = abs(distance)
            if remainingDistance <= 0.5 {
                axis.position = axis.target
                halt(axis)
                return
            }
            let sign = distance >= 0 ? 1.0 : -1.0
            let limit = countsPerSecond(axis.gotoFast ? maximumSlewDegreesPerSecond : lowSpeedGotoDegreesPerSecond)
            let desired = axis.gotoFast ? min(limit, (2 * acceleration * remainingDistance).squareRoot()) : limit
            var speed = abs(axis.velocity)
            speed = desired > speed ? min(desired, speed + acceleration * dt) : max(desired, speed - acceleration * dt)
            speed = max(speed, countsPerSecond(0.01))
            let travel = speed * dt
            if travel >= remainingDistance {
                axis.position = axis.target
                halt(axis)
            } else {
                axis.position += sign * travel
                axis.velocity = sign * speed
            }
        }
    }
}

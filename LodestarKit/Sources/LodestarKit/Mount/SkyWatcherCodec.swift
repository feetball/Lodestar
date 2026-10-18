import Foundation

/// The commands of the Sky-Watcher motor controller protocol that the engine uses (letter and the length of the data in
/// a normal reply). Reference: Sky-Watcher, "Motor Controller Command Set" (`skywatcher_motor_controller_command_set.pdf`,
/// sha256 `a4c583bdf617b45ea64b3c742e8b8ab7009a953a2d42c97fdaacd67455d7f73a`, 25 Aug 2021); the commands `H`, `M`, `T`
/// and `U` are listed there greyed out, their use follows INDI's `skywatcherAPI.cpp` (GPL, read for facts only). The
/// bootloader, EEPROM, register and debug commands are deliberately not offered.
public enum SkyWatcherCommand: CaseIterable, Hashable, Sendable {
    /// `E`: set the position count (motor must be stopped).
    case setPosition
    /// `F`: initialization done; motion commands are refused until it was sent after power-up.
    case initializationDone
    /// `G`: set the motion mode and direction for the next start (motor must be stopped).
    case setMotionMode
    /// `H`: set the GOTO target as an increment from the current position.
    case setGotoTargetIncrement
    /// `M`: set the brake point (where the deceleration of a GOTO starts) as an increment.
    case setBrakePointIncrement
    /// `S`: set the GOTO target as an absolute position.
    case setGotoTarget
    /// `I`: set the step period (the timer preset value, which sets the speed).
    case setStepPeriod
    /// `T`: set the long GOTO step period.
    case setLongGotoStepPeriod
    /// `U`: set the brake steps (deceleration ramp length in speed mode).
    case setBrakeSteps
    /// `J`: start the motion.
    case startMotion
    /// `K`: stop with deceleration (the axis returns to speed mode).
    case stopMotion
    /// `L`: stop instantly.
    case instantStop
    /// `B`: wake up or put the driver to sleep.
    case setSleep
    /// `O`: auxiliary switch (camera snap port) on or off.
    case setAuxSwitch
    /// `P`: set the autoguide speed.
    case setAutoguideSpeed
    /// `a`: counts per revolution of the axis.
    case inquireCountsPerRevolution
    /// `b`: frequency of the step timer (channel 1 answers for both).
    case inquireTimerFrequency
    /// `c`: brake steps.
    case inquireBrakeSteps
    /// `h`: the GOTO target position.
    case inquireGotoTarget
    /// `i`: the step period.
    case inquireStepPeriod
    /// `j`: the position count (offset by 0x800000).
    case inquirePosition
    /// `k`: the GOTO increment.
    case inquireIncrement
    /// `m`: the brake point.
    case inquireBrakePoint
    /// `f`: the axis status (three hex digits).
    case inquireStatus
    /// `g`: the high-speed ratio (two hex digits).
    case inquireHighSpeedRatio
    /// `D`: the step period of 1x sidereal tracking.
    case inquireTrackingPeriod
    /// `d`: the position of the telescope axis (auxiliary encoder).
    case inquireAxisPosition
    /// `e`: the motor board version.
    case inquireVersion
    /// `s`: the PEC period (counts per worm revolution).
    case inquirePECPeriod
    /// `W`: extended setting.
    case extendedSetting
    /// `q`: extended inquire (features).
    case extendedInquire

    /// The command letter.
    public var letter: Character {
        switch self {
        case .setPosition: "E"
        case .initializationDone: "F"
        case .setMotionMode: "G"
        case .setGotoTargetIncrement: "H"
        case .setBrakePointIncrement: "M"
        case .setGotoTarget: "S"
        case .setStepPeriod: "I"
        case .setLongGotoStepPeriod: "T"
        case .setBrakeSteps: "U"
        case .startMotion: "J"
        case .stopMotion: "K"
        case .instantStop: "L"
        case .setSleep: "B"
        case .setAuxSwitch: "O"
        case .setAutoguideSpeed: "P"
        case .inquireCountsPerRevolution: "a"
        case .inquireTimerFrequency: "b"
        case .inquireBrakeSteps: "c"
        case .inquireGotoTarget: "h"
        case .inquireStepPeriod: "i"
        case .inquirePosition: "j"
        case .inquireIncrement: "k"
        case .inquireBrakePoint: "m"
        case .inquireStatus: "f"
        case .inquireHighSpeedRatio: "g"
        case .inquireTrackingPeriod: "D"
        case .inquireAxisPosition: "d"
        case .inquireVersion: "e"
        case .inquirePECPeriod: "s"
        case .extendedSetting: "W"
        case .extendedInquire: "q"
        }
    }

    /// The number of hex digits in the data of a normal reply; -1 if it is not fixed.
    public var replyDigits: Int {
        switch self {
        case .inquireStatus: 3
        case .inquireHighSpeedRatio: 2
        case .inquireCountsPerRevolution, .inquireTimerFrequency, .inquireBrakeSteps, .inquireGotoTarget, .inquireStepPeriod,
             .inquirePosition, .inquireIncrement, .inquireBrakePoint, .inquireTrackingPeriod, .inquireAxisPosition,
             .inquireVersion, .inquirePECPeriod, .extendedInquire: 6
        case .extendedSetting: -1
        default: 0
        }
    }

    /// True for the commands that ask for a value.
    public var isInquiry: Bool { replyDigits > 0 }

    /// The command with the given letter, or nil if there is none.
    public static func fromLetter(_ letter: Character) -> SkyWatcherCommand? { allCases.first { $0.letter == letter } }
}

/// A decoded reply of the motor controller.
public enum SkyWatcherReply: Hashable, Sendable {
    /// `=` followed by `payload` (0 to 6 uppercase hex digits).
    case success(payload: String)
    /// `!` followed by an error `code`.
    case failure(code: Int)
}

/// The step period and speed class that give a wanted speed (see `SkyWatcherCodec.speed`).
public struct SkyWatcherSpeed: Hashable, Sendable {
    /// The timer preset value for the `I` command.
    public let period: Int
    /// True if the axis must be started in the high-speed mode (`3`).
    public let isHighSpeed: Bool

    public init(period: Int, isHighSpeed: Bool) {
        self.period = period
        self.isHighSpeed = isHighSpeed
    }
}

/// Encoding and decoding of the Sky-Watcher motor controller protocol (the same command set on the serial line and on the
/// Wi-Fi mounts' UDP port 11880): commands `:` letter channel data CR, replies `=` data CR or `!` code CR, numbers as
/// little-endian hex bytes (0x123456 is sent as "563412"), positions offset by 0x800000. Pure functions; every decoder
/// validates characters and lengths and throws `MountError.malformedReply`.
public enum SkyWatcherCodec {
    /// The first byte of a command, `:`.
    public static let leadingByte = 0x3A
    /// The last byte of a command and of a reply, carriage return.
    public static let terminator = 0x0D
    /// Position counts are sent as `count + 0x800000`.
    public static let positionOffset = 0x800000
    /// The most data digits a command or reply carries.
    public static let maximumDigits = 6
    /// The smallest step period the engine asks for (INDI's `minperiods`, 6 timer ticks).
    public static let minimumPeriod = 6
    /// The largest step period (24 bits).
    public static let maximumPeriod = 0xFFFFFF
    /// The speed above which an axis must run in the high-speed mode: 128 times the sidereal rate (INDI's `LOW_SPEED_MARGIN`).
    public static let lowSpeedLimitSiderealMultiple = 128.0

    // MARK: Numbers

    private static let hexDigits = Array("0123456789ABCDEF")

    private static func hexValue(_ scalar: Unicode.Scalar) -> Int {
        let value = Int(scalar.value)
        if value >= 48 && value <= 57 { return value - 48 }
        if value >= 65 && value <= 70 { return value - 65 + 10 }
        return -1
    }

    private static func encodeBytes(_ value: Int, byteCount: Int) -> String {
        var result: [Character] = []
        for index in 0 ..< byteCount {
            let byte = (value >> (8 * index)) & 0xFF
            result.append(hexDigits[byte >> 4])
            result.append(hexDigits[byte & 15])
        }
        return String(result)
    }

    private static func decodeBytes(_ text: String, byteCount: Int) throws -> Int {
        let scalars = Array(text.unicodeScalars)
        if scalars.count != byteCount * 2 {
            throw MountError.malformedReply(detail: "expected \(byteCount * 2) hex digits, got \(scalars.count)")
        }
        var value = 0
        for index in 0 ..< byteCount {
            let high = hexValue(scalars[2 * index])
            let low = hexValue(scalars[2 * index + 1])
            if high < 0 || low < 0 { throw MountError.malformedReply(detail: "not a hex number") }
            value |= ((high << 4) | low) << (8 * index)
        }
        return value
    }

    /// Six hex digits, low byte first: 0x123456 becomes "563412". The value must be 0 to 0xFFFFFF.
    public static func encode24(_ value: Int) throws -> String {
        if value < 0 || value > 0xFFFFFF { throw MountError.invalidInput(detail: "\(value) does not fit in 24 bits") }
        return encodeBytes(value, byteCount: 3)
    }

    /// Four hex digits, low byte first: 0x1234 becomes "3412".
    public static func encode16(_ value: Int) throws -> String {
        if value < 0 || value > 0xFFFF { throw MountError.invalidInput(detail: "\(value) does not fit in 16 bits") }
        return encodeBytes(value, byteCount: 2)
    }

    /// Two hex digits: 0x12 becomes "12".
    public static func encode8(_ value: Int) throws -> String {
        if value < 0 || value > 0xFF { throw MountError.invalidInput(detail: "\(value) does not fit in 8 bits") }
        return encodeBytes(value, byteCount: 1)
    }

    /// The inverse of `encode24`: exactly six uppercase hex digits.
    public static func decode24(_ text: String) throws -> Int { try decodeBytes(text, byteCount: 3) }

    /// The inverse of `encode16`.
    public static func decode16(_ text: String) throws -> Int { try decodeBytes(text, byteCount: 2) }

    /// The inverse of `encode8`.
    public static func decode8(_ text: String) throws -> Int { try decodeBytes(text, byteCount: 1) }

    /// A position count relative to the power-up position (-0x800000 to 0x7FFFFF) as the six digits the controller expects.
    public static func encodePosition(_ counts: Int) throws -> String {
        if counts < -positionOffset || counts >= positionOffset { throw MountError.invalidInput(detail: "position \(counts) is out of range") }
        return try encode24(counts + positionOffset)
    }

    /// The position count relative to the power-up position in a six-digit reply.
    public static func decodePosition(_ text: String) throws -> Int { try decode24(text) - positionOffset }

    // MARK: Requests

    /// One command as a datagram or serial line: `:`, the command letter, the channel digit, `data` (at most six
    /// uppercase hex digits) and a carriage return.
    public static func request(_ command: SkyWatcherCommand, axis: SkyWatcherAxis, data: String = "") throws -> [UInt8] {
        let scalars = Array(data.unicodeScalars)
        if scalars.count > maximumDigits { throw MountError.invalidInput(detail: "a command carries at most \(maximumDigits) data digits") }
        for scalar in scalars where hexValue(scalar) < 0 {
            throw MountError.invalidInput(detail: "command data must be uppercase hex digits")
        }
        var bytes: [UInt8] = [UInt8(ascii: ":")]
        bytes.append(command.letter.asciiValue ?? 63)
        bytes.append(axis.channel.asciiValue ?? 63)
        for scalar in scalars { bytes.append(UInt8(truncatingIfNeeded: scalar.value)) }
        bytes.append(UInt8(terminator))
        return bytes
    }

    /// An inquiry (`a b c h i j k m f g D d e s q` letters) for `axis`.
    public static func inquire(_ command: SkyWatcherCommand, axis: SkyWatcherAxis) throws -> [UInt8] {
        if !command.isInquiry { throw MountError.invalidInput(detail: "\(command.letter) is not an inquiry") }
        let data = command == .extendedInquire ? try encode24(1) : ""
        return try request(command, axis: axis, data: data)
    }

    /// `G`: `mode` and `direction` for the next start.
    public static func setMotionMode(axis: SkyWatcherAxis, mode: SkyWatcherMotionMode, direction: SkyWatcherDirection) throws -> [UInt8] {
        try request(.setMotionMode, axis: axis, data: String(mode.code) + String(direction.code))
    }

    /// `H`: the GOTO distance in counts (0 to 0xFFFFFF; the direction is the `G` direction).
    public static func setGotoTargetIncrement(axis: SkyWatcherAxis, counts: Int) throws -> [UInt8] {
        try request(.setGotoTargetIncrement, axis: axis, data: encode24(counts))
    }

    /// `M`: the distance before the target where the GOTO starts to brake, in counts.
    public static func setBrakePointIncrement(axis: SkyWatcherAxis, counts: Int) throws -> [UInt8] {
        try request(.setBrakePointIncrement, axis: axis, data: encode24(counts))
    }

    /// `S`: the absolute GOTO target as a position count relative to the power-up position.
    public static func setGotoTarget(axis: SkyWatcherAxis, position: Int) throws -> [UInt8] {
        try request(.setGotoTarget, axis: axis, data: encodePosition(position))
    }

    /// `I`: the step period (timer preset value).
    public static func setStepPeriod(axis: SkyWatcherAxis, period: Int) throws -> [UInt8] {
        try request(.setStepPeriod, axis: axis, data: encode24(period))
    }

    /// `J`: start the motion.
    public static func start(axis: SkyWatcherAxis) throws -> [UInt8] { try request(.startMotion, axis: axis) }

    /// `K` (decelerate) or `L` (instant): stop the motion.
    public static func stop(axis: SkyWatcherAxis, instant: Bool = false) throws -> [UInt8] {
        try request(instant ? .instantStop : .stopMotion, axis: axis)
    }

    /// `E`: declare the position count (relative to the power-up position) of a stopped axis.
    public static func setPosition(axis: SkyWatcherAxis, counts: Int) throws -> [UInt8] {
        try request(.setPosition, axis: axis, data: encodePosition(counts))
    }

    /// `F`: initialization done.
    public static func initializationDone(axis: SkyWatcherAxis) throws -> [UInt8] { try request(.initializationDone, axis: axis) }

    // MARK: Replies

    /// Decodes one reply without its carriage return. Bytes before the first `=` or `!` are skipped (an echoed command, a
    /// stray line feed); after it come at most six uppercase hex digits (`=`) or one or two hex digits (`!`).
    ///
    /// - Throws: `MountError.malformedReply` for anything else.
    public static func parseReply(_ line: [UInt8]) throws -> SkyWatcherReply {
        var start = -1
        for index in line.indices where line[index] == UInt8(ascii: "=") || line[index] == UInt8(ascii: "!") {
            start = index
            break
        }
        if start < 0 { throw MountError.malformedReply(detail: "no reply marker") }
        let marker = line[start]
        var rest: [Unicode.Scalar] = []
        if start + 1 < line.count {
            for index in (start + 1) ..< line.count {
                let scalar = Unicode.Scalar(line[index])
                if hexValue(scalar) < 0 { throw MountError.malformedReply(detail: "unexpected character in the reply") }
                rest.append(scalar)
            }
        }
        if marker == UInt8(ascii: "=") {
            if rest.count > maximumDigits { throw MountError.malformedReply(detail: "reply too long") }
            var payload = String.UnicodeScalarView()
            payload.append(contentsOf: rest)
            return .success(payload: String(payload))
        }
        if rest.isEmpty || rest.count > 2 { throw MountError.malformedReply(detail: "malformed error code") }
        var code = 0
        for scalar in rest { code = code * 16 + hexValue(scalar) }
        return .failure(code: code)
    }

    /// Decodes a whole datagram: the reply up to the first carriage return, which must be present.
    public static func parseDatagram(_ bytes: [UInt8]) throws -> SkyWatcherReply {
        var end = -1
        for index in bytes.indices where Int(bytes[index]) == terminator {
            end = index
            break
        }
        if end < 0 { throw MountError.malformedReply(detail: "the reply is incomplete") }
        return try parseReply(Array(bytes[0 ..< end]))
    }

    /// The error to throw for the reply `!code`.
    public static func error(_ code: Int) -> MountError {
        switch code {
        case SkyWatcherErrorCode.unknownCommand.code: .notSupported(feature: .other)
        case SkyWatcherErrorCode.commandLength.code: .rejected(detail: "command length error")
        case SkyWatcherErrorCode.motorNotStopped.code: .busy
        case SkyWatcherErrorCode.invalidCharacter.code: .rejected(detail: "invalid character")
        case SkyWatcherErrorCode.notInitialized.code: .rejected(detail: "the motor controller is not initialized")
        case SkyWatcherErrorCode.driverSleeping.code: .standby
        case SkyWatcherErrorCode.pecTrainingRunning.code: .busy
        case SkyWatcherErrorCode.noValidPECData.code: .rejected(detail: "no valid PEC data")
        default: .remote(code: code, detail: "undocumented motor controller error")
        }
    }

    /// True for the errors that a damaged request can cause (unknown command, length, invalid character): the driver
    /// sends the command again before it believes them. The other codes describe the controller's state.
    public static func isPossiblyCausedByDamagedRequest(_ code: Int) -> Bool {
        code == SkyWatcherErrorCode.unknownCommand.code || code == SkyWatcherErrorCode.commandLength.code
            || code == SkyWatcherErrorCode.invalidCharacter.code
    }

    /// The axis status in a three-digit `f` reply.
    public static func decodeStatus(_ payload: String) throws -> SkyWatcherAxisStatus {
        let scalars = Array(payload.unicodeScalars)
        if scalars.count != 3 { throw MountError.malformedReply(detail: "status needs 3 digits") }
        let first = hexValue(scalars[0])
        let second = hexValue(scalars[1])
        let third = hexValue(scalars[2])
        if first < 0 || second < 0 || third < 0 { throw MountError.malformedReply(detail: "status is not hex") }
        return SkyWatcherAxisStatus(isSpeedMode: (first & 1) != 0, isDecreasing: (first & 2) != 0, isFast: (first & 4) != 0,
                                    isRunning: (second & 1) != 0, isBlocked: (second & 2) != 0, isInitialized: (third & 1) != 0,
                                    isLevelSwitchOn: (third & 2) != 0)
    }

    /// Encodes a status as the three digits of an `f` reply (for simulators and tests).
    public static func encodeStatus(_ status: SkyWatcherAxisStatus) -> String {
        let first = (status.isSpeedMode ? 1 : 0) | (status.isDecreasing ? 2 : 0) | (status.isFast ? 4 : 0)
        let second = (status.isRunning ? 1 : 0) | (status.isBlocked ? 2 : 0)
        let third = (status.isInitialized ? 1 : 0) | (status.isLevelSwitchOn ? 2 : 0)
        return String([hexDigits[first], hexDigits[second], hexDigits[third]])
    }

    /// The motor board version in a six-digit `e` reply: the digits `AABBCC` are firmware `AA.BB` and mount code `CC`.
    public static func decodeVersion(_ payload: String) throws -> SkyWatcherVersion {
        let scalars = Array(payload.unicodeScalars)
        if scalars.count != 6 { throw MountError.malformedReply(detail: "version needs 6 digits") }
        var values = [Int](repeating: 0, count: 6)
        for index in 0 ..< 6 {
            values[index] = hexValue(scalars[index])
            if values[index] < 0 { throw MountError.malformedReply(detail: "version is not hex") }
        }
        return SkyWatcherVersion(major: values[0] * 16 + values[1], minor: values[2] * 16 + values[3], mountCode: values[4] * 16 + values[5])
    }

    /// Encodes a version as the six digits of an `e` reply (for simulators and tests).
    public static func encodeVersion(_ version: SkyWatcherVersion) -> String {
        SkyWatcherMountCatalog.hex2(version.major) + SkyWatcherMountCatalog.hex2(version.minor) + SkyWatcherMountCatalog.hex2(version.mountCode)
    }

    /// The high-speed ratio in a two-digit `g` reply (1 to 255).
    public static func decodeHighSpeedRatio(_ payload: String) throws -> Int {
        let value = try decode8(payload)
        if value == 0 { throw MountError.malformedReply(detail: "the high-speed ratio is zero") }
        return value
    }

    // MARK: Speeds

    /// The fastest speed of the low-speed mode in degrees per second (128 times sidereal).
    public static var lowSpeedLimitDegreesPerSecond: Double { lowSpeedLimitSiderealMultiple * MountNudgeRate.siderealDegreesPerSecond }

    /// The step period for turning an axis at `degreesPerSecond` (the sign is ignored), following the command set's formula
    /// `T1 = TMR_Freq · 360 / speed / CPR`, multiplied by the high-speed ratio above 128 times sidereal. Periods below
    /// `minimumPeriod` are raised to it (the axis then runs at the controller's maximum). Returns nil if the speed is not a
    /// positive number or so slow that the period would not fit in 24 bits.
    public static func speed(degreesPerSecond: Double, countsPerRevolution: Int, timerFrequency: Int, highSpeedRatio: Int) -> SkyWatcherSpeed? {
        let rate = abs(degreesPerSecond)
        if !rate.isFinite || !(rate > 0) || countsPerRevolution <= 0 || timerFrequency <= 0 || highSpeedRatio <= 0 { return nil }
        let isHigh = rate > lowSpeedLimitDegreesPerSecond
        let factor = isHigh ? Double(highSpeedRatio) : 1.0
        let period = factor * Double(timerFrequency) * 360.0 / (rate * Double(countsPerRevolution))
        if !(period < Double(maximumPeriod) + 0.5) { return nil }
        let rounded = Int(period.rounded())
        return SkyWatcherSpeed(period: max(rounded, minimumPeriod), isHighSpeed: isHigh)
    }

    /// The speed in degrees per second that the step period `period` gives (the inverse of `speed`).
    public static func degreesPerSecond(period: Int, isHighSpeed: Bool, countsPerRevolution: Int, timerFrequency: Int,
                                        highSpeedRatio: Int) -> Double {
        if period <= 0 || countsPerRevolution <= 0 || timerFrequency <= 0 { return 0 }
        let factor = isHighSpeed ? Double(highSpeedRatio) : 1.0
        return factor * Double(timerFrequency) * 360.0 / (Double(period) * Double(countsPerRevolution))
    }
}

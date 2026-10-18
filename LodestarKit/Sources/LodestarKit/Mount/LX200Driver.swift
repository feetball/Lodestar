import Foundation

/// Settings of an `LX200Driver`.
///
/// Values are clamped to their ranges when the configuration is created.
public struct LX200Configuration: Hashable, Sendable {
    /// The frame the mount expects; LX200 mounts expect "JNow", so the default is `MountEpoch.meanOfDate`.
    public let epoch: MountEpoch
    /// How long one command may take to answer (0.5 to 30 s).
    public let exchangeTimeoutSeconds: Double
    /// How long the optional identification commands may take (0.2 to 10 s).
    public let identifyTimeoutSeconds: Double
    /// How long to wait for the optional text after a `0`/`1` answer (0.05 to 2 s).
    public let tailTimeoutSeconds: Double
    /// The dialect to assume; nil detects it from the product name.
    public let dialect: LX200Dialect?
    /// Switch the mount to the high precision position format at connect time when it is in the low one.
    public let prefersHighPrecision: Bool
    /// How often a command is repeated when the controller answers "busy" (0 to 10).
    public let busyRetries: Int

    /// The defaults: JNow (mean of date), 3 s timeout, automatic dialect, high precision.
    public static let standard = LX200Configuration()

    /// Creates a configuration; out-of-range values are clamped.
    public init(epoch: MountEpoch = .meanOfDate, exchangeTimeoutSeconds: Double = 3.0, identifyTimeoutSeconds: Double = 1.0,
                tailTimeoutSeconds: Double = 0.4, dialect: LX200Dialect? = nil, prefersHighPrecision: Bool = true,
                busyRetries: Int = 3) {
        self.epoch = epoch
        self.exchangeTimeoutSeconds = LX200Configuration.sane(exchangeTimeoutSeconds, 3.0, 0.5, 30.0)
        self.identifyTimeoutSeconds = LX200Configuration.sane(identifyTimeoutSeconds, 1.0, 0.2, 10.0)
        self.tailTimeoutSeconds = LX200Configuration.sane(tailTimeoutSeconds, 0.4, 0.05, 2.0)
        self.dialect = dialect
        self.prefersHighPrecision = prefersHighPrecision
        self.busyRetries = min(max(busyRetries, 0), 10)
    }

    private static func sane(_ value: Double, _ defaultValue: Double, _ lower: Double, _ upper: Double) -> Double {
        value.isNaN ? defaultValue : min(max(value, lower), upper)
    }
}

/// Drives an LX200-compatible mount (Meade LX200/Autostar, OnStep, SkyFi and other Wi-Fi bridges) over a byte-stream
/// `MountTransport`. See `LX200Codec` for the command reference.
///
/// Position format: the driver reads `:GR#`/`:GD#` in whatever precision the mount uses and sends targets in the
/// same precision; at connect time it switches a low-precision mount to high precision with `:U#` (a toggle, sent
/// only after a low-precision reply was seen).
///
/// Coordinates are in `LX200Configuration.epoch`; the Meade command set sends JNow, which the controller derives from
/// J2000 with the engine's precession (`MountEpoch.meanOfDate`).
public final class LX200Driver: MountDriver {
    private static let maximumReplyLength = 63
    private static let busyDelaySeconds = 0.1

    private let link: MountLink
    private let clock: MountClock

    /// The settings in use.
    public let configuration: LX200Configuration

    /// The dialect in use: configured, or detected at `connect`.
    public private(set) var dialect: LX200Dialect

    /// The position format last seen from the mount (used for the next `:Sr`/`:Sd`).
    public private(set) var precision: LX200Precision = .high

    public var kind: MountProtocol { .lx200 }

    public var epoch: MountEpoch { configuration.epoch }

    public init(transport: MountTransport, clock: MountClock, configuration: LX200Configuration = .standard) {
        self.clock = clock
        self.configuration = configuration
        link = MountLink(transport: transport, clock: clock)
        dialect = configuration.dialect ?? .meade
    }

    public func connect() throws -> MountCapabilities {
        var name = ""
        var firmware: String?
        do {
            name = MountText.sanitized(
                try query(LX200Codec.getProductName, operation: "identify", timeoutSeconds: configuration.identifyTimeoutSeconds), limit: 40)
            if !name.isEmpty {
                let number = MountText.sanitized(
                    try query(LX200Codec.getFirmwareNumber, operation: "identify", timeoutSeconds: configuration.identifyTimeoutSeconds),
                    limit: 20)
                if !number.isEmpty { firmware = number }
            }
        } catch MountError.timeout {
            // Not every controller knows the identification commands; the position read below decides.
        } catch MountError.malformedReply {
            name = ""
            firmware = nil
        }
        dialect = configuration.dialect ?? LX200Codec.dialect(productName: name)

        var reading = try LX200Codec.decodeRightAscension(try query(LX200Codec.getRightAscension, operation: "read right ascension"))
        if reading.precision == .low && configuration.prefersHighPrecision {
            try sendOnly(LX200Codec.togglePrecision)
            reading = try LX200Codec.decodeRightAscension(try query(LX200Codec.getRightAscension, operation: "read right ascension"))
        }
        precision = reading.precision
        _ = try LX200Codec.decodeDeclination(try query(LX200Codec.getDeclination, operation: "read declination"))

        var aligned: Bool?
        if dialect == .onstep {
            _ = try LX200Codec.decodeStatus(try query(LX200Codec.getStatus, operation: "read status"))
            do {
                aligned = try LX200Codec.decodeAlignmentStatus(
                    try query(LX200Codec.getAlignmentStatus, operation: "read alignment")).alignedStars > 0
            } catch MountError.timeout {
                aligned = nil
            } catch MountError.malformedReply {
                aligned = nil
            }
        }
        return MountCapabilities(
            kind: .lx200, name: name.isEmpty ? "LX200-compatible mount" : name, firmware: firmware, canSlew: true, canSync: true,
            canAbort: true, canSetTracking: dialect == .onstep, canNudge: true, canSetSiteAndTime: true,
            gotoNeedsAlignment: false, isAligned: aligned)
    }

    public func disconnect() {
        // The protocol has no session; nothing to close.
    }

    public func readPosition() throws -> EquatorialCoordinate {
        let ra = try LX200Codec.decodeRightAscension(try query(LX200Codec.getRightAscension, operation: "read right ascension"))
        let dec = try LX200Codec.decodeDeclination(try query(LX200Codec.getDeclination, operation: "read declination"))
        precision = ra.precision
        return EquatorialCoordinate(rightAscensionHours: ra.value, declination: dec.value)
    }

    public func readSlewing() throws -> Bool {
        LX200Codec.isSlewing(distanceBars: try query(LX200Codec.getSlewDistance, operation: "read slew state"))
    }

    public func readTracking() throws -> Bool? {
        if dialect != .onstep { return nil }
        return try readStatus().isTracking
    }

    public func readAligned() throws -> Bool? {
        if dialect != .onstep { return nil }
        return try LX200Codec.decodeAlignmentStatus(try query(LX200Codec.getAlignmentStatus, operation: "read alignment")).alignedStars > 0
    }

    public func slew(to target: EquatorialCoordinate) throws {
        try setTarget(target)
        try exchange(LX200Codec.slewToTarget, operation: "start slew") { first in
            guard let scalar = Unicode.Scalar(UInt32(first)) else { throw MountError.malformedReply(detail: "slew reply") }
            let code = Character(scalar)
            if let refusal = try LX200Codec.slewRefusal(code) {
                if code == "1" || code == "2" { try drainTail(segments: 1) }
                throw refusal
            }
        }
    }

    public func sync(to target: EquatorialCoordinate) throws {
        if dialect == .onstep {
            let status = try readStatus()
            if status.isParked { throw MountError.parked }
            if status.isGotoActive { throw MountError.slewInProgress }
        }
        try setTarget(target)
        let reply = try query(LX200Codec.syncToTarget, operation: "sync")
        let chars = Array(reply.unicodeScalars)
        if chars.count == 2 && chars[0] == "E" && chars[1].value >= 0x31 && chars[1].value <= 0x39 {
            throw try LX200Codec.slewRefusal(Character(chars[1])) ?? MountError.rejected(detail: "sync")
        }
        if reply.isEmpty { throw MountError.rejected(detail: "the mount ignored the sync") }
    }

    public func abort() throws {
        try sendOnly(LX200Codec.halt)
    }

    public func setTracking(_ enabled: Bool) throws {
        if dialect != .onstep { throw MountError.notSupported(feature: .tracking) }
        if try flag(enabled ? LX200Codec.trackingOn : LX200Codec.trackingOff, operation: "set tracking") { return }
        let status = try readStatus()
        if status.isParked { throw MountError.parked }
        if status.isGotoActive { throw MountError.slewInProgress }
        throw MountError.rejected(detail: "tracking could not be changed")
    }

    public func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
        try sendOnly(LX200Codec.setRate(rate))
        try sendOnly(LX200Codec.move(direction))
    }

    public func stopNudge(direction: MountNudgeDirection) throws {
        try sendOnly(LX200Codec.halt(direction))
    }

    public func setSiteAndTime(location: GeographicLocation, date: Date) throws {
        guard let fields = MountCalendar.fields(for: date) else {
            throw MountError.invalidInput(detail: "the date is outside 1970 to 9999")
        }
        try requireAccepted(try flag(LX200Codec.setLatitude(location.latitude), operation: "set latitude"), "latitude")
        try requireAccepted(try flag(LX200Codec.setLongitude(location.longitude), operation: "set longitude"), "longitude")
        try requireAccepted(
            try flag(LX200Codec.setUTCOffset(eastOffsetHours: 0.0, dialect: dialect), operation: "set UTC offset"), "UTC offset")
        let dateAccepted = try exchange(LX200Codec.setDate(fields), operation: "set date") { first in
            let accepted = try flagValue(first)
            if accepted && dialect == .meade { try drainTail(segments: 2) }
            return accepted
        }
        try requireAccepted(dateAccepted, "date")
        try requireAccepted(try flag(LX200Codec.setTime(fields), operation: "set time"), "time")
    }

    // MARK: Exchanges

    private func requireAccepted(_ accepted: Bool, _ what: String) throws {
        if !accepted { throw MountError.rejected(detail: "the \(what) was not accepted") }
    }

    private func readStatus() throws -> LX200StatusFlags {
        try LX200Codec.decodeStatus(try query(LX200Codec.getStatus, operation: "read status"))
    }

    private func setTarget(_ target: EquatorialCoordinate) throws {
        if !target.rightAscension.isFinite || !target.declination.isFinite {
            throw MountError.invalidInput(detail: "the target coordinates are not numbers")
        }
        try requireAccepted(
            try flag(LX200Codec.setTargetRightAscension(hours: target.rightAscension / 15.0, precision: precision),
                     operation: "set target right ascension"),
            "target right ascension")
        try requireAccepted(
            try flag(LX200Codec.setTargetDeclination(degrees: target.declination, precision: precision),
                     operation: "set target declination"),
            "target declination")
    }

    /// Sends a command that has no reply.
    private func sendOnly(_ command: String) throws {
        try link.beginExchange()
        try link.send(MountText.ascii(command))
    }

    /// Sends `command`, waits for the first reply byte and hands it to `reply`; repeats the command on a busy NAK.
    @discardableResult
    private func exchange<T>(_ command: String, operation: String, timeoutSeconds: Double? = nil,
                             reply: (Int) throws -> T) throws -> T {
        let timeout = timeoutSeconds ?? configuration.exchangeTimeoutSeconds
        for _ in 0 ... configuration.busyRetries {
            try link.beginExchange()
            try link.send(MountText.ascii(command))
            let first = Int(try link.readExactly(1, timeoutSeconds: timeout, operation: operation)[0])
            if first == LX200Codec.busyByte {
                clock.sleep(seconds: LX200Driver.busyDelaySeconds)
                continue
            }
            return try reply(first)
        }
        throw MountError.busy
    }

    /// A `#`-terminated text reply (a lone `#` is the empty text).
    private func query(_ command: String, operation: String, timeoutSeconds: Double? = nil) throws -> String {
        let timeout = timeoutSeconds ?? configuration.exchangeTimeoutSeconds
        return try exchange(command, operation: operation, timeoutSeconds: timeout) { first in
            if first == 0x23 { return "" }
            let rest = try link.readUntil(0x23, maximumLength: LX200Driver.maximumReplyLength, timeoutSeconds: timeout,
                                          operation: operation)
            return MountText.latin1([UInt8(first)] + rest)
        }
    }

    /// A `0`/`1` flag reply.
    private func flag(_ command: String, operation: String) throws -> Bool {
        try exchange(command, operation: operation) { first in try flagValue(first) }
    }

    private func flagValue(_ first: Int) throws -> Bool {
        switch first {
        case 0x31: return true
        case 0x30: return false
        default: throw MountError.malformedReply(detail: "flag reply 0x\(String(first, radix: 16))")
        }
    }

    /// Reads and drops up to `segments` `#`-terminated texts that follow a short answer; silence is fine.
    private func drainTail(segments: Int) throws {
        for _ in 0 ..< segments {
            do {
                _ = try link.readUntil(0x23, maximumLength: LX200Driver.maximumReplyLength,
                                       timeoutSeconds: configuration.tailTimeoutSeconds, operation: "reply text")
            } catch MountError.timeout {
                return
            }
        }
    }
}

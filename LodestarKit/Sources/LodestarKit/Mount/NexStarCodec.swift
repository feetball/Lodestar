import Foundation

/// Which hand controller family answered the version command.
public enum NexStarFlavor: String, CaseIterable, Codable, Hashable, Sendable {
    /// Celestron NexStar hand control: the version is two binary bytes.
    case celestron
    /// Sky-Watcher SynScan hand control: the version is six hexadecimal digits in ASCII.
    case synscan
}

/// The hand controller's firmware version.
public struct NexStarVersion: Hashable, Sendable {
    /// The family that reported the version.
    public let flavor: NexStarFlavor
    /// Major version.
    public let major: Int
    /// Minor version.
    public let minor: Int
    /// Patch level; 0 for Celestron controllers, which report two numbers.
    public let patch: Int

    public init(flavor: NexStarFlavor, major: Int, minor: Int, patch: Int) {
        self.flavor = flavor
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// True if this version is `major`.`minor`.`patch` or later.
    public func isAtLeast(_ major: Int, _ minor: Int, _ patch: Int = 0) -> Bool {
        if self.major != major { return self.major > major }
        if self.minor != minor { return self.minor > minor }
        return self.patch >= patch
    }

    /// `4.37.07` for SynScan, `5.28` for Celestron.
    public var description: String {
        switch flavor {
        case .celestron: "\(major).\(MountCalendar.twoDigits(minor))"
        case .synscan: "\(major).\(MountCalendar.twoDigits(minor)).\(MountCalendar.twoDigits(patch))"
        }
    }
}

/// The two motor axes the hand control exposes to pass-through commands.
public enum NexStarAxis: Int, CaseIterable, Hashable, Sendable {
    /// Azimuth on an alt-azimuth mount, right ascension on an equatorial mount (device 16).
    case azimuthRightAscension = 16
    /// Altitude on an alt-azimuth mount, declination on an equatorial mount (device 17).
    case altitudeDeclination = 17

    /// The device number used in pass-through commands.
    public var device: Int { rawValue }
}

/// The tracking modes of the `T` and `t` commands.
public enum NexStarTrackingMode: Int, CaseIterable, Hashable, Sendable {
    /// Tracking off.
    case off = 0
    /// Alt-azimuth tracking.
    case altAz = 1
    /// Equatorial tracking (Celestron: equatorial north; SynScan: equatorial).
    case eqNorth = 2
    /// Celestron: equatorial south; SynScan: sidereal with PEC.
    case eqSouth = 3

    /// The byte sent and received.
    public var code: Int { rawValue }

    /// The mode with the given code, or nil if there is none.
    public static func fromCode(_ code: Int) -> NexStarTrackingMode? { NexStarTrackingMode(rawValue: code) }
}

/// Encoding and decoding of the Celestron NexStar hand-control serial protocol ("NexStar Communication Protocol",
/// Celestron) and its Sky-Watcher SynScan twin ("SynScan Serial Communication Protocol", version 3.3).
///
/// Commands are single ASCII letters followed by fixed-length arguments; replies end in `#`. Positions are
/// hexadecimal fractions of a revolution: 16 bits (`E`, `R`, `S`: about 20″ per unit) or 32 bits whose lowest 8 bits are
/// unused (`e`, `r`, `s`: about 0.08″ per unit). Pass-through (`P`) commands talk to the motor controllers.
public enum NexStarCodec {
    /// The byte that ends every reply.
    public static let terminator = 0x23

    /// Declination replies may overshoot ±90° by this much (rounding of the last unit) before they count as garbled.
    public static let declinationSlackDegrees = 0.01

    // MARK: Simple commands

    /// `V`: get the version.
    public static let getVersion: [UInt8] = [UInt8(ascii: "V")]
    /// `m`: get the model.
    public static let getModel: [UInt8] = [UInt8(ascii: "m")]
    /// `J`: is the alignment complete?
    public static let getAlignmentComplete: [UInt8] = [UInt8(ascii: "J")]
    /// `L`: is a GOTO in progress?
    public static let getGotoInProgress: [UInt8] = [UInt8(ascii: "L")]
    /// `M`: cancel the GOTO.
    public static let cancelGoto: [UInt8] = [UInt8(ascii: "M")]
    /// `t`: get the tracking mode.
    public static let getTrackingMode: [UInt8] = [UInt8(ascii: "t")]

    /// `T` and the mode byte: set the tracking mode.
    public static func setTrackingMode(_ mode: NexStarTrackingMode) -> [UInt8] { [UInt8(ascii: "T"), UInt8(mode.code)] }

    /// `e` or `E`: get the position as right ascension and declination.
    public static func getPosition(precise: Bool) -> [UInt8] { [UInt8(ascii: precise ? "e" : "E")] }

    /// `r…` or `R…`: GOTO the J2000 or JNow place `target` (whichever frame the mount expects).
    public static func goto(_ target: EquatorialCoordinate, precise: Bool) -> [UInt8] {
        MountText.ascii(positionCommand(precise ? "r" : "R", target, precise))
    }

    /// `s…` or `S…`: sync to `target`.
    public static func sync(_ target: EquatorialCoordinate, precise: Bool) -> [UInt8] {
        MountText.ascii(positionCommand(precise ? "s" : "S", target, precise))
    }

    private static func positionCommand(_ letter: String, _ target: EquatorialCoordinate, _ precise: Bool) -> String {
        "\(letter)\(encodeAngle(target.rightAscension, precise: precise)),\(encodeAngle(target.declination, precise: precise))"
    }

    // MARK: Angles

    /// The hexadecimal fraction of a revolution for `degrees` (wrapped into one turn; negative angles such as a
    /// southern declination become 360° minus their size): 4 digits, or 8 digits with the lowest byte 00.
    public static func encodeAngle(_ degrees: Double, precise: Bool) -> String {
        let fraction = AstroMath.normalizeDegrees(degrees.isFinite ? degrees : 0.0) / 360.0
        if precise {
            var units = Int((fraction * 16_777_216.0).rounded())
            if units >= 16_777_216 { units -= 16_777_216 }
            return hex(units * 256, 8)
        }
        var units = Int((fraction * 65_536.0).rounded())
        if units >= 65_536 { units -= 65_536 }
        return hex(units, 4)
    }

    /// The angle in [0°, 360°) of a 4 or 8 digit hexadecimal fraction of a revolution (the lowest byte of 8 digits is unused).
    public static func decodeAngle(_ hexText: String) throws -> Double {
        let chars = Array(hexText.unicodeScalars)
        if chars.count != 4 && chars.count != 8 { throw malformed("angle", hexText) }
        var value = 0
        for ch in chars {
            let digit = hexDigit(ch)
            if digit < 0 { throw malformed("angle", hexText) }
            value = value * 16 + digit
        }
        if chars.count == 4 { return Double(value) / 65_536.0 * 360.0 }
        return Double(value / 256) / 16_777_216.0 * 360.0
    }

    /// Decodes the payload `RRRR,DDDD` or `RRRRRRRR,DDDDDDDD` of `E` / `e` (without the `#`) into a place.
    public static func decodePosition(_ payload: String) throws -> EquatorialCoordinate {
        let parts = payload.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count != 2 || parts[0].unicodeScalars.count != parts[1].unicodeScalars.count {
            throw malformed("position", payload)
        }
        let rightAscension = try decodeAngle(String(parts[0]))
        var declination = try decodeAngle(String(parts[1]))
        if declination > 180.0 { declination -= 360.0 }
        if abs(declination) > 90.0 + declinationSlackDegrees { throw malformed("position", payload) }
        return EquatorialCoordinate(rightAscension: rightAscension, declination: min(max(declination, -90.0), 90.0))
    }

    // MARK: Pass-through

    /// `P` and seven bytes: a pass-through command to `device` with command `commandID`, three data bytes and the
    /// number of reply bytes expected (`responseLength`).
    public static func passthrough(payloadLength: Int, device: Int, commandID: Int, data1: Int, data2: Int, data3: Int,
                                   responseLength: Int) -> [UInt8] {
        [UInt8(ascii: "P"), UInt8(truncatingIfNeeded: payloadLength), UInt8(truncatingIfNeeded: device),
         UInt8(truncatingIfNeeded: commandID), UInt8(truncatingIfNeeded: data1), UInt8(truncatingIfNeeded: data2),
         UInt8(truncatingIfNeeded: data3), UInt8(truncatingIfNeeded: responseLength)]
    }

    /// Variable-rate slew of `axis` at `arcsecondsPerSecond` (0 to 16 383.75, resolution ¼″/s) in the positive or negative
    /// direction: `P`, 3, device, 6 or 7, rate×4 high byte, low byte, 0, 0.
    public static func variableRateSlew(axis: NexStarAxis, positive: Bool, arcsecondsPerSecond: Double) throws -> [UInt8] {
        if !(arcsecondsPerSecond >= 0) || arcsecondsPerSecond > 16_383.75 {
            throw MountError.invalidInput(detail: "the rate is outside 0 to 16383.75 arcseconds per second")
        }
        let quarters = Int((arcsecondsPerSecond * 4).rounded())
        return passthrough(payloadLength: 3, device: axis.device, commandID: positive ? 6 : 7, data1: quarters / 256,
                           data2: quarters % 256, data3: 0, responseLength: 0)
    }

    /// Fixed-rate slew of `axis` at hand-control rate `rate` (1 to 9; 0 stops): `P`, 2, device, 36 or 37, rate, 0, 0, 0.
    public static func fixedRateSlew(axis: NexStarAxis, positive: Bool, rate: Int) throws -> [UInt8] {
        if rate < 0 || rate > 9 { throw MountError.invalidInput(detail: "the fixed rate must be 0 to 9") }
        return passthrough(payloadLength: 2, device: axis.device, commandID: positive ? 36 : 37, data1: rate, data2: 0,
                           data3: 0, responseLength: 0)
    }

    /// `P`, 1, device, 254, 0, 0, 0, 2: get the firmware version of a motor controller.
    public static func getDeviceVersion(axis: NexStarAxis) -> [UInt8] {
        passthrough(payloadLength: 1, device: axis.device, commandID: 254, data1: 0, data2: 0, data3: 0, responseLength: 2)
    }

    // MARK: Time and location

    /// `W` and eight bytes: set the site. Latitude and longitude are rounded to the arcsecond; the flags are 0 for north
    /// and east, 1 for south and west.
    public static func setLocation(_ location: GeographicLocation) throws -> [UInt8] {
        if !location.latitude.isFinite || !location.longitude.isFinite {
            throw MountError.invalidInput(detail: "the location is not a number")
        }
        let latitude = abs(min(max(location.latitude, -90), 90))
        let longitude = abs(min(max(location.longitude, -180), 180))
        let latSeconds = Int((latitude * 3600).rounded())
        let lonSeconds = Int((longitude * 3600).rounded())
        return [
            UInt8(ascii: "W"),
            UInt8(latSeconds / 3600), UInt8(latSeconds % 3600 / 60), UInt8(latSeconds % 60),
            location.latitude < 0 ? 1 : 0,
            UInt8(lonSeconds / 3600), UInt8(lonSeconds % 3600 / 60), UInt8(lonSeconds % 60),
            location.longitude < 0 ? 1 : 0,
        ]
    }

    /// `H` and eight bytes: set the clock to hour, minute, second, month, day, year−2000, the zone offset
    /// (256 − hours for zones west of Greenwich) and the daylight-saving flag. `dateTime` must be in 2000…2099.
    public static func setTime(_ dateTime: MountDateTime, zoneOffsetHours: Int, daylightSaving: Bool) throws -> [UInt8] {
        if dateTime.year < 2000 || dateTime.year > 2099 {
            throw MountError.invalidInput(detail: "the hand control accepts the years 2000 to 2099")
        }
        if zoneOffsetHours < -12 || zoneOffsetHours > 14 {
            throw MountError.invalidInput(detail: "the zone offset must be −12 to +14 hours")
        }
        return [
            UInt8(ascii: "H"),
            UInt8(dateTime.hour), UInt8(dateTime.minute), UInt8(dateTime.second),
            UInt8(dateTime.month), UInt8(dateTime.day), UInt8(dateTime.year - 2000),
            UInt8(zoneOffsetHours < 0 ? 256 + zoneOffsetHours : zoneOffsetHours),
            daylightSaving ? 1 : 0,
        ]
    }

    // MARK: Replies

    /// Decodes a version reply without its `#`: two bytes (Celestron, major and minor) or six hexadecimal digits
    /// (SynScan: `042507` is 4.37.07).
    public static func decodeVersion(_ payload: [UInt8]) throws -> NexStarVersion {
        if payload.count == 2 {
            return NexStarVersion(flavor: .celestron, major: Int(payload[0]), minor: Int(payload[1]), patch: 0)
        }
        if payload.count == 6 {
            var digits = [Int](repeating: 0, count: 6)
            for index in 0 ..< 6 {
                digits[index] = hexDigit(Unicode.Scalar(payload[index]))
                if digits[index] < 0 { throw MountError.malformedReply(detail: "version") }
            }
            return NexStarVersion(flavor: .synscan, major: digits[0] * 16 + digits[1], minor: digits[2] * 16 + digits[3],
                                  patch: digits[4] * 16 + digits[5])
        }
        throw MountError.malformedReply(detail: "version")
    }

    /// The display name of a model number from the `m` command for the controller family.
    public static func modelName(_ model: Int, flavor: NexStarFlavor) -> String {
        switch flavor {
        case .celestron:
            switch model {
            case 1: return "Celestron NexStar GPS"
            case 3: return "Celestron NexStar i-Series"
            case 4: return "Celestron NexStar i-Series SE"
            case 5: return "Celestron CGE"
            case 6: return "Celestron Advanced GT"
            case 7: return "Celestron SLT"
            case 9: return "Celestron CPC"
            case 10: return "Celestron GT"
            case 11: return "Celestron NexStar 4/5 SE"
            case 12: return "Celestron NexStar 6/8 SE"
            default: return "Celestron NexStar"
            }
        case .synscan:
            switch model {
            case 0: return "Sky-Watcher EQ6 GOTO"
            case 1: return "Sky-Watcher HEQ5 GOTO"
            case 2: return "Sky-Watcher EQ5 GOTO"
            case 3: return "Sky-Watcher EQ3 GOTO"
            case 4: return "Sky-Watcher EQ8 GOTO"
            case 5: return "Sky-Watcher AZ-EQ6 GOTO"
            case 6: return "Sky-Watcher AZ-EQ5 GOTO"
            case 128 ... 143: return "Sky-Watcher AZ GOTO"
            case 144 ... 159: return "Sky-Watcher Dobsonian GOTO"
            case 160: return "Sky-Watcher AllView GOTO"
            default: return "Sky-Watcher SynScan"
            }
        }
    }

    // MARK: Helpers

    private static func malformed(_ what: String, _ text: String) -> MountError {
        MountError.malformedReply(detail: "\(what) \"\(MountText.sanitized(text, limit: 24))\"")
    }

    private static func hex(_ value: Int, _ digits: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }

    private static func hexDigit(_ ch: Unicode.Scalar) -> Int {
        switch ch.value {
        case 0x30 ... 0x39: Int(ch.value) - 0x30
        case 0x41 ... 0x46: Int(ch.value) - 0x41 + 10
        case 0x61 ... 0x66: Int(ch.value) - 0x61 + 10
        default: -1
        }
    }
}

import Foundation

/// Which of the two position formats the mount uses: `HH:MM.T` / `sDD*MM` or `HH:MM:SS` / `sDD*MM:SS`.
public enum LX200Precision: String, CaseIterable, Codable, Hashable, Sendable {
    /// Tenths of a minute of right ascension, whole arcminutes of declination.
    case low
    /// Whole seconds of right ascension, whole arcseconds of declination.
    case high
}

/// Which family of LX200 firmware is talking; it decides the extensions the driver may use.
public enum LX200Dialect: String, CaseIterable, Codable, Hashable, Sendable {
    /// Meade LX200, Autostar, and the many compatible controllers that implement only the Meade command set.
    case meade
    /// OnStep, which adds `:GU#` status, `:Te#`/`:Td#` tracking and single-digit `:MS#` replies.
    case onstep
}

/// A decoded right ascension (hours) or declination (degrees) and the format it arrived in.
public struct LX200Reading: Hashable, Sendable {
    /// Hours for a right ascension, degrees for a declination.
    public let value: Double
    /// The format of the reply.
    public let precision: LX200Precision

    public init(value: Double, precision: LX200Precision) {
        self.value = value
        self.precision = precision
    }
}

/// The flags of OnStep's `:GU#` status string that the controller uses.
public struct LX200StatusFlags: Hashable, Sendable {
    /// `n` is absent: sidereal tracking is on (or a goto started from tracking is running).
    public let isTracking: Bool
    /// `N` is absent: a goto is in progress.
    public let isGotoActive: Bool
    /// `P`: the mount is parked.
    public let isParked: Bool
    /// `I`: parking is in progress.
    public let isParking: Bool
    /// `F`: parking failed.
    public let parkFailed: Bool
    /// `H`: the mount is at its home position.
    public let isAtHome: Bool

    public init(isTracking: Bool, isGotoActive: Bool, isParked: Bool, isParking: Bool, parkFailed: Bool, isAtHome: Bool) {
        self.isTracking = isTracking
        self.isGotoActive = isGotoActive
        self.isParked = isParked
        self.isParking = isParking
        self.parkFailed = parkFailed
        self.isAtHome = isAtHome
    }
}

/// The result of `:GW#` (LX200GPS and OnStep): mount type, tracking and the number of alignment stars.
public struct LX200AlignmentStatus: Hashable, Sendable {
    /// `A` alt-azimuth, `P` polar/fork, `L` land, `G` German equatorial.
    public let mountType: Character
    /// The `T` / `N` flag.
    public let isTracking: Bool
    /// 0 when the mount needs an alignment, up to 9 for 9 or more stars.
    public let alignedStars: Int

    public init(mountType: Character, isTracking: Bool, alignedStars: Int) {
        self.mountType = mountType
        self.isTracking = isTracking
        self.alignedStars = alignedStars
    }
}

/// Encoding and decoding of the Meade LX200 command set (Meade Telescope Serial Command Protocol, revision 2007.10,
/// and OnStep's extensions, the OnStep 4.24 `Command.ino`).
///
/// Commands are ASCII strings `:XX…#`. Replies are `#`-terminated except single-character answers (`0`/`1` flags,
/// the `:MS#` digit). The functions here take a reply without its terminator (as text with one character per byte,
/// so the degree sign 0xDF some Meade scopes send arrives as `ß`) and throw `MountError.malformedReply` for anything
/// that is not exactly a valid value.
public enum LX200Codec {
    /// The byte that ends a command and most replies.
    public static let terminator: Character = "#"
    /// Sent by LX200GPS and Autostar II instead of a reply when the controller is busy; retry the command.
    public static let busyByte = 0x15

    // MARK: Fixed commands

    /// Get the telescope's right ascension.
    public static let getRightAscension = ":GR#"
    /// Get the telescope's declination.
    public static let getDeclination = ":GD#"
    /// Get the product name.
    public static let getProductName = ":GVP#"
    /// Get the firmware number.
    public static let getFirmwareNumber = ":GVN#"
    /// OnStep: get the status string.
    public static let getStatus = ":GU#"
    /// LX200GPS and OnStep: get mount type, tracking and alignment.
    public static let getAlignmentStatus = ":GW#"
    /// Get the distance bars: a non-empty answer means the mount is slewing.
    public static let getSlewDistance = ":D#"
    /// Slew to the target set with `:Sr` and `:Sd`.
    public static let slewToTarget = ":MS#"
    /// Sync the mount to the target set with `:Sr` and `:Sd`.
    public static let syncToTarget = ":CM#"
    /// Halt all slewing.
    public static let halt = ":Q#"
    /// Toggle between the low and high precision position formats. It is a toggle: never send it blind.
    public static let togglePrecision = ":U#"
    /// OnStep: enable tracking.
    public static let trackingOn = ":Te#"
    /// OnStep: disable tracking.
    public static let trackingOff = ":Td#"

    // MARK: Parameterised commands

    /// `:Sr…#`: set the target right ascension from `hours`.
    public static func setTargetRightAscension(hours: Double, precision: LX200Precision) -> String {
        ":Sr\(formatRightAscension(hours: hours, precision: precision))#"
    }

    /// `:Sd…#`: set the target declination from `degrees`.
    public static func setTargetDeclination(degrees: Double, precision: LX200Precision) -> String {
        ":Sd\(formatDeclination(degrees: degrees, precision: precision))#"
    }

    /// `:M?#`: start moving in `direction` at the current rate.
    public static func move(_ direction: MountNudgeDirection) -> String { ":M\(directionLetter(direction))#" }

    /// `:Q?#`: stop moving in `direction`.
    public static func halt(_ direction: MountNudgeDirection) -> String { ":Q\(directionLetter(direction))#" }

    /// `:R?#`: select the slew rate (`G` guide, `C` centre, `M` find, `S` max).
    public static func setRate(_ rate: MountNudgeRate) -> String { ":R\(rateLetter(rate))#" }

    /// `:St…#`: set the site latitude (north positive), rounded to the arcminute.
    public static func setLatitude(_ latitude: Double) -> String {
        let safe = finiteOrZero(latitude)
        let minutes = Int((abs(min(max(safe, -90), 90)) * 60).rounded())
        let sign = safe < 0 && minutes > 0 ? "-" : "+"
        return ":St\(sign)\(MountCalendar.twoDigits(minutes / 60))*\(MountCalendar.twoDigits(minutes % 60))#"
    }

    /// `:Sg…#`: set the site longitude from `eastLongitude` (east positive). The protocol counts longitude westwards
    /// from 0 to 360°, so 10° E is sent as 350.
    public static func setLongitude(_ eastLongitude: Double) -> String {
        var west = (-finiteOrZero(eastLongitude)).truncatingRemainder(dividingBy: 360.0)
        if west < 0 { west += 360.0 }
        var minutes = Int((west * 60).rounded())
        if minutes >= 360 * 60 { minutes -= 360 * 60 }
        return ":Sg\(MountCalendar.threeDigits(minutes / 60))*\(MountCalendar.twoDigits(minutes % 60))#"
    }

    /// `:SG…#`: set the hours that are added to local time to get UTC (west of Greenwich positive, so −`eastOffsetHours`).
    /// Meade writes `sHH.H`; OnStep writes `sHH` or `sHH:MM` with MM of 30 or 45.
    public static func setUTCOffset(eastOffsetHours: Double, dialect: LX200Dialect) -> String {
        let added = -min(max(finiteOrZero(eastOffsetHours), -14), 14)
        switch dialect {
        case .meade:
            let tenths = Int((abs(added) * 10).rounded())
            let sign = added < 0 && tenths > 0 ? "-" : "+"
            return ":SG\(sign)\(MountCalendar.twoDigits(tenths / 10)).\(tenths % 10)#"
        case .onstep:
            let quarters = Int((abs(added) * 4).rounded())
            let minutes = quarters * 15
            let sign = added < 0 && minutes > 0 ? "-" : "+"
            let hours = MountCalendar.twoDigits(minutes / 60)
            let rest = minutes % 60
            return rest == 0 ? ":SG\(sign)\(hours)#" : ":SG\(sign)\(hours):\(MountCalendar.twoDigits(rest))#"
        }
    }

    /// `:SC…#`: set the date to `MM/DD/YY` (the year modulo 100).
    public static func setDate(_ dateTime: MountDateTime) -> String {
        ":SC\(MountCalendar.twoDigits(dateTime.month))/\(MountCalendar.twoDigits(dateTime.day))/"
            + "\(MountCalendar.twoDigits(dateTime.year % 100))#"
    }

    /// `:SL…#`: set the local time to `HH:MM:SS`.
    public static func setTime(_ dateTime: MountDateTime) -> String {
        ":SL\(MountCalendar.twoDigits(dateTime.hour)):\(MountCalendar.twoDigits(dateTime.minute)):"
            + "\(MountCalendar.twoDigits(dateTime.second))#"
    }

    // MARK: Formatting of positions

    /// `HH:MM:SS` or `HH:MM.T` for `hours`, wrapped into [0, 24) and rounded to the format's resolution.
    public static func formatRightAscension(hours: Double, precision: LX200Precision) -> String {
        var wrapped = finiteOrZero(hours).truncatingRemainder(dividingBy: 24.0)
        if wrapped < 0 { wrapped += 24.0 }
        switch precision {
        case .high:
            var seconds = Int((wrapped * 3600).rounded())
            if seconds >= 86_400 { seconds -= 86_400 }
            return "\(MountCalendar.twoDigits(seconds / 3600)):\(MountCalendar.twoDigits(seconds % 3600 / 60)):"
                + MountCalendar.twoDigits(seconds % 60)
        case .low:
            var tenths = Int((wrapped * 600).rounded())
            if tenths >= 14_400 { tenths -= 14_400 }
            return "\(MountCalendar.twoDigits(tenths / 600)):\(MountCalendar.twoDigits(tenths % 600 / 10)).\(tenths % 10)"
        }
    }

    /// `sDD*MM:SS` or `sDD*MM` for `degrees`, clamped to ±90 and rounded to the format's resolution.
    public static func formatDeclination(degrees: Double, precision: LX200Precision) -> String {
        let clamped = min(max(finiteOrZero(degrees), -90), 90)
        switch precision {
        case .high:
            let seconds = Int((abs(clamped) * 3600).rounded())
            let sign = clamped < 0 && seconds > 0 ? "-" : "+"
            return "\(sign)\(MountCalendar.twoDigits(seconds / 3600))*\(MountCalendar.twoDigits(seconds % 3600 / 60)):"
                + MountCalendar.twoDigits(seconds % 60)
        case .low:
            let minutes = Int((abs(clamped) * 60).rounded())
            let sign = clamped < 0 && minutes > 0 ? "-" : "+"
            return "\(sign)\(MountCalendar.twoDigits(minutes / 60))*\(MountCalendar.twoDigits(minutes % 60))"
        }
    }

    // MARK: Decoding of replies

    /// Decodes `HH:MM:SS` (also with fractional seconds, as OnStep's high-precision reply) or `HH:MM.T` into hours.
    /// Hours are 0 to 23 (24:00:00 reads as 0), minutes and seconds 0 to 59.
    public static func decodeRightAscension(_ text: String) throws -> LX200Reading {
        let chars = Array(text.unicodeScalars)
        guard let hours = twoDigits(chars, 0) else { throw malformed("right ascension", text) }
        if chars.count < 7 || chars[2] != ":" { throw malformed("right ascension", text) }
        guard let minutes = twoDigits(chars, 3) else { throw malformed("right ascension", text) }
        if hours > 24 || minutes > 59 { throw malformed("right ascension", text) }
        let value: Double
        let precision: LX200Precision
        switch chars[5] {
        case ":":
            guard let seconds = twoDigits(chars, 6) else { throw malformed("right ascension", text) }
            if seconds > 59 { throw malformed("right ascension", text) }
            var fraction = 0.0
            if chars.count != 8 {
                guard let parsed = decimalFraction(chars, 8, 4) else { throw malformed("right ascension", text) }
                fraction = parsed
            }
            value = Double(hours) + Double(minutes) / 60.0 + (Double(seconds) + fraction) / 3600.0
            precision = .high
        case ".":
            guard let fraction = decimalFraction(chars, 5, 3) else { throw malformed("right ascension", text) }
            value = Double(hours) + (Double(minutes) + fraction) / 60.0
            precision = .low
        default:
            throw malformed("right ascension", text)
        }
        if value > 24.0 { throw malformed("right ascension", text) }
        return LX200Reading(value: value >= 24.0 ? 0.0 : value, precision: precision)
    }

    /// Decodes `sDD*MM:SS` or `sDD*MM` (degree separator `*`, `:`, `°` or the byte 0xDF; seconds separator `:` or `'`,
    /// fractional seconds allowed) into degrees. The sign is optional; the magnitude is at most 90°.
    public static func decodeDeclination(_ text: String) throws -> LX200Reading {
        let chars = Array(text.unicodeScalars)
        var index = 0
        var negative = false
        if let first = chars.first, first == "+" || first == "-" {
            negative = first == "-"
            index = 1
        }
        guard let degrees = twoDigits(chars, index) else { throw malformed("declination", text) }
        if chars.count < index + 5 { throw malformed("declination", text) }
        let separator = chars[index + 2]
        if separator != "*" && separator != ":" && separator != "\u{00B0}" && separator != "\u{00DF}" {
            throw malformed("declination", text)
        }
        guard let minutes = twoDigits(chars, index + 3) else { throw malformed("declination", text) }
        if degrees > 90 || minutes > 59 { throw malformed("declination", text) }
        var magnitude = Double(degrees) + Double(minutes) / 60.0
        var precision = LX200Precision.low
        if chars.count > index + 5 {
            let secondsSeparator = chars[index + 5]
            if secondsSeparator != ":" && secondsSeparator != "'" { throw malformed("declination", text) }
            guard let seconds = twoDigits(chars, index + 6) else { throw malformed("declination", text) }
            if seconds > 59 { throw malformed("declination", text) }
            var fraction = 0.0
            if chars.count != index + 8 {
                guard let parsed = decimalFraction(chars, index + 8, 4) else { throw malformed("declination", text) }
                fraction = parsed
            }
            magnitude += (Double(seconds) + fraction) / 3600.0
            precision = .high
        }
        if magnitude > 90.0 { throw malformed("declination", text) }
        return LX200Reading(value: negative ? -magnitude : magnitude, precision: precision)
    }

    /// Maps the digit that answers `:MS#` (and follows `E` in OnStep's `:CM#` failure `En#`) to the reason the mount
    /// refused: `0` is success (nil). Meade defines 1 (below horizon) and 2 (above the higher limit); OnStep 1 to 9.
    public static func slewRefusal(_ code: Character) throws -> MountError? {
        switch code {
        case "0": nil
        case "1": MountError.mountHorizonLimit
        case "2": MountError.mountOverheadLimit
        case "3": MountError.standby
        case "4": MountError.parked
        case "5": MountError.slewInProgress
        case "6": MountError.outsideMountLimits
        case "7": MountError.hardwareFault(detail: "")
        case "8": MountError.busy
        case "9": MountError.rejected(detail: "the mount refused the move for an unspecified reason")
        default: throw malformed("slew reply", String(code))
        }
    }

    /// Decodes the answer of `:D#` (text between the bars and the terminator): non-empty means the mount is slewing.
    public static func isSlewing(distanceBars: String) -> Bool { !distanceBars.isEmpty }

    /// Decodes OnStep's `:GU#` status string.
    public static func decodeStatus(_ text: String) throws -> LX200StatusFlags {
        let chars = Array(text.unicodeScalars)
        if chars.isEmpty || chars.count > 40 { throw malformed("status", text) }
        var parkMarkers = 0
        for ch in chars {
            if ch.value < 0x21 || ch.value > 0x7E { throw malformed("status", text) }
            if ch == "p" || ch == "I" || ch == "P" || ch == "F" { parkMarkers += 1 }
        }
        if parkMarkers != 1 { throw malformed("status", text) }
        return LX200StatusFlags(
            isTracking: !chars.contains("n"),
            isGotoActive: !chars.contains("N"),
            isParked: chars.contains("P"),
            isParking: chars.contains("I"),
            parkFailed: chars.contains("F"),
            isAtHome: chars.contains("H"))
    }

    /// Decodes `:GW#`: mount type `A`/`P`/`L`/`G`, tracking `T`/`N`, alignment digit.
    public static func decodeAlignmentStatus(_ text: String) throws -> LX200AlignmentStatus {
        let chars = Array(text.unicodeScalars)
        if chars.count != 3 { throw malformed("alignment status", text) }
        let mount = chars[0]
        let tracking = chars[1]
        let stars = chars[2]
        if mount != "A" && mount != "P" && mount != "L" && mount != "G" { throw malformed("alignment status", text) }
        if tracking != "T" && tracking != "N" { throw malformed("alignment status", text) }
        if stars.value < 0x30 || stars.value > 0x39 { throw malformed("alignment status", text) }
        return LX200AlignmentStatus(mountType: Character(mount), isTracking: tracking == "T", alignedStars: Int(stars.value) - 0x30)
    }

    /// The dialect a product name (`:GVP#`) belongs to: OnStep calls itself "On-Step".
    public static func dialect(productName: String) -> LX200Dialect {
        let lowered = MountText.asciiLowercased(productName)
        return lowered.contains("on-step") || lowered.contains("onstep") ? .onstep : .meade
    }

    // MARK: Helpers

    /// Non-finite numbers are sent as 0 so that no formatting can fail; callers validate their input first.
    private static func finiteOrZero(_ value: Double) -> Double { value.isFinite ? value : 0.0 }

    private static func directionLetter(_ direction: MountNudgeDirection) -> Character {
        switch direction {
        case .north: "n"
        case .south: "s"
        case .east: "e"
        case .west: "w"
        }
    }

    private static func rateLetter(_ rate: MountNudgeRate) -> Character {
        switch rate {
        case .guide: "G"
        case .center: "C"
        case .find: "M"
        case .slew: "S"
        }
    }

    private static func malformed(_ what: String, _ text: String) -> MountError {
        MountError.malformedReply(detail: "\(what) \"\(MountText.sanitized(text, limit: 24))\"")
    }

    private static func twoDigits(_ chars: [Unicode.Scalar], _ at: Int) -> Int? {
        if at < 0 || chars.count < at + 2 { return nil }
        let tens = chars[at].value
        let ones = chars[at + 1].value
        if tens < 0x30 || tens > 0x39 || ones < 0x30 || ones > 0x39 { return nil }
        return Int(tens - 0x30) * 10 + Int(ones - 0x30)
    }

    /// The value of `.d…` (a dot and 1 to `maximumDigits` digits that end the text) starting at `at`, or nil.
    private static func decimalFraction(_ chars: [Unicode.Scalar], _ at: Int, _ maximumDigits: Int) -> Double? {
        if chars.count < at + 2 || chars[at] != "." { return nil }
        let digits = chars.count - at - 1
        if digits > maximumDigits { return nil }
        var value = 0.0
        var scale = 1.0
        for offset in 1 ... digits {
            let code = chars[at + offset].value
            if code < 0x30 || code > 0x39 { return nil }
            scale /= 10.0
            value += Double(code - 0x30) * scale
        }
        return value
    }
}

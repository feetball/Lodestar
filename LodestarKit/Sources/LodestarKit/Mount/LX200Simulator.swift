import Foundation

/// An in-memory LX200 mount behind a `MountTransport`, for tests and UI previews. It parses `:…#` commands like a Meade
/// or OnStep controller, answers with the documented reply formats (including the single-digit `:MS#` answers of OnStep and
/// the `1<text>#` answers of Meade), and drives a `MountSimulatorModel`. Defects are injected with `inject` or the public
/// properties: busy NAKs (`busyReplies`), refused slews (`refusalCode`), a low-precision mount (`highPrecision`).
public final class LX200Simulator: MountSimulatedStreamTransport {
    /// The moving mount behind the protocol.
    public let mount: MountSimulatorModel
    /// The firmware family: it decides which commands exist and how errors are reported.
    public let dialect: LX200Dialect
    /// The position format currently selected on the mount (`:U#` toggles it).
    public var highPrecision: Bool
    /// The answer to `:GVP#`.
    public let productName: String
    /// Answer this many commands with the busy byte (NAK) before behaving normally.
    public var busyReplies = 0
    /// If set (`"1"` … `"9"`), `:MS#` and `:CM#` refuse with this code (see `LX200Codec.slewRefusal`).
    public var refusalCode: Character?
    /// The number of alignment stars `:GW#` reports.
    public var alignedStars = 2

    private var siteLog: [String] = []
    private var targetRightAscension: Double?
    private var targetDeclination: Double?
    private var selectedRate: MountNudgeRate = .guide
    private var rightAscensionRate = 0.0
    private var declinationRate = 0.0

    public init(clock: ManualMountClock, mount: MountSimulatorModel, dialect: LX200Dialect = .onstep, highPrecision: Bool = true,
                productName: String? = nil, latencySeconds: Double = 0.05, chunkSize: Int = 0) {
        self.mount = mount
        self.dialect = dialect
        self.highPrecision = highPrecision
        self.productName = productName ?? (dialect == .onstep ? "On-Step" : "LX200 Classic")
        super.init(clock: clock, latencySeconds: latencySeconds, chunkSize: chunkSize)
    }

    /// The site and clock commands received (`St+40*00`, `Sg104*00`, `SG+00`, `SC10/18/26`, `SL04:00:00`), in order.
    public var siteCommands: [String] { siteLog }

    private var precision: LX200Precision { highPrecision ? .high : .low }

    public override func consume(_ pending: [UInt8]) -> Int {
        guard let colon = pending.firstIndex(of: UInt8(ascii: ":")) else { return pending.count }
        guard let hash = pending[colon...].firstIndex(of: UInt8(ascii: "#")) else { return 0 }
        handle(MountText.latin1(Array(pending[(colon + 1) ..< hash])))
        return hash + 1
    }

    private func text(_ label: String, _ answer: String) { reply(label, MountText.latin1Bytes(answer)) }

    private func handle(_ frame: String) {
        if busyReplies > 0 {
            busyReplies -= 1
            reply(frame, [UInt8(LX200Codec.busyByte)])
            return
        }
        let onStep = dialect == .onstep
        if frame == "GR" {
            text(frame, LX200Codec.formatRightAscension(hours: mount.position.rightAscension / 15.0, precision: precision) + "#")
        } else if frame == "GD" {
            text(frame, LX200Codec.formatDeclination(degrees: mount.position.declination, precision: precision) + "#")
        } else if frame == "GVP" {
            text(frame, "\(productName)#")
        } else if frame == "GVN" {
            text(frame, "4.24#")
        } else if frame == "GU" && onStep {
            text(frame, statusText() + "#")
        } else if frame == "GW" && onStep {
            text(frame, "G\(mount.isTracking ? "T" : "N")\(min(max(alignedStars, 0), 9))#")
        } else if frame == "D" {
            text(frame, mount.isSlewing ? "\u{7F}#" : "#")
        } else if frame.hasPrefix("Sr") {
            setTarget(frame, isRightAscension: true)
        } else if frame.hasPrefix("Sd") {
            setTarget(frame, isRightAscension: false)
        } else if frame == "MS" {
            slewToTarget(frame)
        } else if frame == "CM" {
            syncToTarget(frame)
        } else if frame == "Q" {
            rightAscensionRate = 0.0
            declinationRate = 0.0
            mount.stop()
            noReply(frame)
        } else if frame.unicodeScalars.count == 2 && frame.hasPrefix("Q") {
            move(frame, start: false)
        } else if frame.unicodeScalars.count == 2 && frame.hasPrefix("M") {
            move(frame, start: true)
        } else if frame.unicodeScalars.count == 2 && frame.hasPrefix("R") {
            selectRate(frame)
        } else if frame == "U" {
            highPrecision.toggle()
            noReply(frame)
        } else if frame == "Te" && onStep {
            setTracking(frame, true)
        } else if frame == "Td" && onStep {
            setTracking(frame, false)
        } else if frame.hasPrefix("SC") {
            siteLog.append(frame)
            text(frame, dialect == .meade ? "1Updating Planetary Data#\(String(repeating: " ", count: 30))#" : "1")
        } else if frame.hasPrefix("St") || frame.hasPrefix("Sg") || frame.hasPrefix("SG") || frame.hasPrefix("SL") {
            siteLog.append(frame)
            text(frame, "1")
        } else {
            noReply(frame)
        }
    }

    private func statusText() -> String {
        var builder = ""
        if !mount.isTracking { builder += "n" }
        if !mount.isSlewing { builder += "N" }
        builder += mount.isParked ? "P" : "p"
        builder += "Eo000"
        return builder
    }

    private func setTarget(_ frame: String, isRightAscension: Bool) {
        let argument = String(frame.unicodeScalars.dropFirst(2))
        do {
            if isRightAscension {
                let reading = try LX200Codec.decodeRightAscension(argument)
                if dialect == .meade && reading.precision != precision { throw MountError.rejected(detail: "precision") }
                targetRightAscension = reading.value * 15.0
            } else {
                let reading = try LX200Codec.decodeDeclination(argument)
                if dialect == .meade && reading.precision != precision { throw MountError.rejected(detail: "precision") }
                targetDeclination = reading.value
            }
            text(frame, "1")
        } catch {
            text(frame, "0")
        }
    }

    private func slewToTarget(_ frame: String) {
        let ra = targetRightAscension
        let dec = targetDeclination
        var refusal: Character? = refusalCode
        if refusal == nil {
            if mount.isParked {
                refusal = "4"
            } else if mount.isSlewing {
                refusal = "5"
            } else if ra == nil || dec == nil {
                refusal = "9"
            }
        }
        guard refusal == nil, let ra, let dec else {
            answerRefusal(frame, refusal ?? "9")
            return
        }
        mount.beginSlew(to: EquatorialCoordinate(rightAscension: ra, declination: dec))
        text(frame, "0")
    }

    private func answerRefusal(_ frame: String, _ digit: Character) {
        if dialect == .onstep {
            text(frame, String(digit))
        } else {
            text(frame, "\(digit)\(digit == "1" ? "Object below horizon" : "Object below higher")#")
        }
    }

    private func syncToTarget(_ frame: String) {
        let ra = targetRightAscension
        let dec = targetDeclination
        if dialect == .onstep {
            if mount.isParked || mount.isSlewing {
                text(frame, "#")
            } else if let code = refusalCode {
                text(frame, "E\(code)#")
            } else if let ra, let dec {
                mount.sync(to: EquatorialCoordinate(rightAscension: ra, declination: dec))
                text(frame, "N/A#")
            } else {
                text(frame, "#")
            }
        } else if let ra, let dec {
            mount.sync(to: EquatorialCoordinate(rightAscension: ra, declination: dec))
            text(frame, "Coordinates matched        #")
        } else {
            text(frame, "#")
        }
    }

    private func setTracking(_ frame: String, _ enabled: Bool) {
        if mount.isParked || mount.isSlewing {
            text(frame, "0")
        } else {
            mount.isTracking = enabled
            text(frame, "1")
        }
    }

    private func selectRate(_ frame: String) {
        switch frame.unicodeScalars.last {
        case "G": selectedRate = .guide
        case "C": selectedRate = .center
        case "M": selectedRate = .find
        case "S": selectedRate = .slew
        default: break
        }
        noReply(frame)
    }

    private func move(_ frame: String, start: Bool) {
        let speed = start ? selectedRate.degreesPerSecond : 0.0
        switch frame.unicodeScalars.last {
        case "n": declinationRate = speed
        case "s": declinationRate = start ? -speed : 0.0
        case "e": rightAscensionRate = speed
        case "w": rightAscensionRate = start ? -speed : 0.0
        default: break
        }
        mount.setNudgeRates(rightAscensionDegreesPerSecond: rightAscensionRate, declinationDegreesPerSecond: declinationRate)
        noReply(frame)
    }
}

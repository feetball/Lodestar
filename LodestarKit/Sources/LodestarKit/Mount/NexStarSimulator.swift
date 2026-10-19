import Foundation

/// An in-memory Celestron NexStar or Sky-Watcher SynScan hand control behind a `MountTransport`, for tests and UI previews.
/// It answers the commands of `NexStarCodec` with the documented replies (binary version for Celestron, six hex digits for
/// SynScan, one extra byte for pass-through commands to an absent device), ignores GOTO and sync while it is not aligned
/// (as the real hand control does) and drives a `MountSimulatorModel`.
public final class NexStarSimulator: MountSimulatedStreamTransport {
    private static let fixedRatesDegreesPerSecond: [Double] = [0.0, 0.0042, 0.0084, 0.0167, 0.0333, 0.0667, 0.1333, 0.5, 1.0, 3.0]

    /// The moving mount behind the protocol.
    public let mount: MountSimulatorModel
    /// Which hand control family to imitate.
    public let flavor: NexStarFlavor
    /// Reported major version.
    public let major: Int
    /// Reported minor version.
    public let minor: Int
    /// Reported patch level (SynScan only).
    public let patch: Int
    /// The answer to `m`.
    public let model: Int
    /// The tracking mode the mount runs in while it tracks (1 alt-az, 2 equatorial).
    public var trackingMode: Int

    /// The eight bytes of the last `W` (set location) command, as unsigned values; empty before one arrived.
    public private(set) var receivedLocation: [Int] = []
    /// The eight bytes of the last `H` (set time) command, as unsigned values; empty before one arrived.
    public private(set) var receivedTime: [Int] = []

    private var rightAscensionRate = 0.0
    private var declinationRate = 0.0

    public init(clock: ManualMountClock, mount: MountSimulatorModel, flavor: NexStarFlavor = .synscan, major: Int = 4, minor: Int = 38,
                patch: Int = 6, model: Int = 128, trackingMode: Int = 1, latencySeconds: Double = 0.05, chunkSize: Int = 0) {
        self.mount = mount
        self.flavor = flavor
        self.major = major
        self.minor = minor
        self.patch = patch
        self.model = model
        self.trackingMode = trackingMode
        super.init(clock: clock, latencySeconds: latencySeconds, chunkSize: chunkSize)
    }

    public override func consume(_ pending: [UInt8]) -> Int {
        let opcode = Character(Unicode.Scalar(pending[0]))
        let needed: Int
        switch opcode {
        case "T", "K": needed = 2
        case "r", "s": needed = 18
        case "R", "S": needed = 10
        case "P": needed = 8
        case "W", "H": needed = 9
        default: needed = 1
        }
        if pending.count < needed { return 0 }
        handle(opcode, Array(pending[0 ..< needed]))
        return needed
    }

    private func answer(_ label: String, _ bytes: [Int] = []) {
        reply(label, bytes.map { UInt8(truncatingIfNeeded: $0) } + [UInt8(ascii: "#")])
    }

    private func handle(_ opcode: Character, _ command: [UInt8]) {
        let label = String(opcode)
        switch opcode {
        case "V":
            if flavor == .celestron {
                answer(label, [major, minor])
            } else {
                let digits = hex2(major) + hex2(minor) + hex2(patch)
                reply(label, MountText.ascii("\(digits)#"))
            }
        case "m": answer(label, [model])
        case "J": answer(label, [mount.isAligned ? 1 : 0])
        case "L": answer(label, [mount.isSlewing ? 0x31 : 0x30])
        case "M":
            mount.stop()
            rightAscensionRate = 0.0
            declinationRate = 0.0
            answer(label)
        case "t": answer(label, [mount.isTracking ? trackingMode : 0])
        case "T":
            let mode = Int(command[1])
            mount.isTracking = mode != 0
            if mode != 0 { trackingMode = mode }
            answer(label)
        case "e", "E":
            let precise = opcode == "e"
            let position = mount.position
            let text = NexStarCodec.encodeAngle(position.rightAscension, precise: precise) + ","
                + NexStarCodec.encodeAngle(position.declination, precise: precise) + "#"
            reply(label, MountText.ascii(text))
        case "r", "R", "s", "S": positionCommand(opcode, command)
        case "P": passthrough(command)
        case "K": answer(label, [Int(command[1])])
        case "W":
            receivedLocation = command.dropFirst().map { Int($0) }
            answer(label)
        case "H":
            receivedTime = command.dropFirst().map { Int($0) }
            answer(label)
        default: noReply(label)
        }
    }

    private func positionCommand(_ opcode: Character, _ command: [UInt8]) {
        let label = String(opcode)
        guard let target = try? NexStarCodec.decodePosition(MountText.latin1(Array(command[1...]))) else {
            noReply(label)
            return
        }
        if mount.isAligned {
            if opcode == "r" || opcode == "R" {
                mount.beginSlew(to: target)
                mount.isTracking = true
            } else {
                mount.sync(to: target)
            }
        }
        answer(label)
    }

    private func passthrough(_ command: [UInt8]) {
        let device = Int(command[2])
        let id = Int(command[3])
        let data1 = Int(command[4])
        let data2 = Int(command[5])
        let responseLength = Int(command[7])
        if device != 16 && device != 17 {
            reply("P", [0, UInt8(ascii: "#")])
            return
        }
        switch id {
        case 6, 7: setAxisRate(device, id == 6, Double(data1 * 256 + data2) / 4.0 / 3600.0)
        case 36, 37: setAxisRate(device, id == 36, NexStarSimulator.fixedRatesDegreesPerSecond[min(max(data1, 0), 9)])
        case 254:
            reply("P", [UInt8(truncatingIfNeeded: major), UInt8(truncatingIfNeeded: minor), UInt8(ascii: "#")])
            return
        default: break
        }
        reply("P", (0 ..< responseLength).map { _ in UInt8(0) } + [UInt8(ascii: "#")])
    }

    /// Positive on the right ascension / azimuth axis moves west, positive on the declination / altitude axis moves north.
    private func setAxisRate(_ device: Int, _ positive: Bool, _ degreesPerSecond: Double) {
        let signed = positive ? degreesPerSecond : -degreesPerSecond
        if device == 16 { rightAscensionRate = -signed } else { declinationRate = signed }
        mount.setNudgeRates(rightAscensionDegreesPerSecond: rightAscensionRate, declinationDegreesPerSecond: declinationRate)
    }

    private func hex2(_ value: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return text.count < 2 ? "0" + text : text
    }
}

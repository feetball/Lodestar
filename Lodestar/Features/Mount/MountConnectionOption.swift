import Foundation
import LodestarKit

/// How Lodestar reaches a mount.
enum MountLinkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tcp, udp, http

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .http: return "HTTP"
        }
    }
}

/// A ready-made address for a well-known adapter, offered under the address fields.
struct MountConnectionPreset: Identifiable, Hashable, Sendable {
    let title: String
    /// `nil` keeps the host that is typed in (SkyFi gets its address from the home router).
    let host: String?
    let port: Int
    let link: MountLinkKind

    var id: String { title }
}

/// The frame of the mount's coordinates, where it can be chosen.
enum MountEpochChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, j2000, meanOfDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .j2000: return "J2000"
        case .meanOfDate: return "Current epoch (JNow)"
        }
    }

    /// `nil` lets the driver decide.
    var epoch: MountEpoch? {
        switch self {
        case .automatic: return nil
        case .j2000: return .j2000
        case .meanOfDate: return .meanOfDate
        }
    }
}

/// What a driver factory is given besides the link.
struct MountDriverOptions: Sendable {
    /// The coordinate frame to use instead of the protocol's own choice, or `nil`.
    var epoch: MountEpoch?
    /// Swap east and west for nudges, for a mount that turns the other way.
    var reversesEastWest = false
    /// Which of the server's telescopes to drive (Alpaca).
    var deviceNumber = 0
    /// Where the demonstration mount points at the start.
    var demoStart: EquatorialCoordinate?
}

/// A driver with the clock it and its controller run on. Made and used on the mount worker thread only.
final class MountDriverBundle {
    let driver: MountDriver
    let clock: MountClock
    /// Run before every job; the demonstration mount moves its clock to real time here.
    let prepare: (() -> Void)?

    init(driver: MountDriver, clock: MountClock, prepare: (() -> Void)? = nil) {
        self.driver = driver
        self.clock = clock
        self.prepare = prepare
    }
}

/// One kind of mount Lodestar can connect to: what the connection screen shows and how its driver is made.
///
/// A new protocol is one more entry in `all`: its texts, its default address and the links it accepts, and a factory
/// that makes the driver from the link. The screens read everything from here and never switch on the protocol.
struct MountConnectionOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let defaultHost: String
    let defaultPort: Int
    /// The links the mount can be reached through; the first is the default.
    let links: [MountLinkKind]
    let presets: [MountConnectionPreset]
    /// Whether "Find devices" works for this kind (Alpaca).
    let supportsDiscovery: Bool
    /// Whether the coordinate frame can be chosen.
    let supportsEpoch: Bool
    /// Whether east and west can be swapped.
    let supportsAxisReversal: Bool
    /// A line under the address fields.
    let addressNote: String
    let makeDriver: @Sendable (MountChannel, MountDriverOptions) throws -> MountDriverBundle

    var defaultLink: MountLinkKind { links.first ?? .tcp }

    static func == (lhs: MountConnectionOption, rhs: MountConnectionOption) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Registry

    /// The kinds of mount, in the order of the picker.
    static let all: [MountConnectionOption] = [.lx200, .nexstar, .alpaca]

    static func option(id: String) -> MountConnectionOption? {
        all.first { $0.id == id } ?? (id == demo.id ? demo : nil)
    }

    static let lx200 = MountConnectionOption(
        id: "lx200",
        title: "LX200 / OnStep",
        summary: "Meade LX200, OnStep, SkyFi and other Wi-Fi telescopes that speak the LX200 commands.",
        defaultHost: "192.168.0.1",
        defaultPort: 9999,
        links: [.tcp],
        presets: [
            MountConnectionPreset(title: "OnStep Wi-Fi", host: "192.168.0.1", port: 9999, link: .tcp),
            MountConnectionPreset(title: "SkyFi", host: nil, port: 4030, link: .tcp),
        ],
        supportsDiscovery: false,
        supportsEpoch: true,
        supportsAxisReversal: false,
        addressNote: """
            OnStep listens on port 9999, SkyFi on 4030. A SkyFi gets its address from your router; \
            look it up in the router or in the SkyFi app.
            """,
        makeDriver: { channel, options in
            guard case .stream(let transport) = channel else {
                throw MountError.invalidInput(detail: "this mount needs a TCP connection")
            }
            let clock = SystemMountClock()
            let configuration = LX200Configuration(epoch: options.epoch ?? .meanOfDate)
            return MountDriverBundle(driver: LX200Driver(transport: transport, clock: clock,
                                                         configuration: configuration), clock: clock)
        })

    static let nexstar = MountConnectionOption(
        id: "nexstar",
        title: "Celestron NexStar / SynScan",
        summary: "Celestron and Sky-Watcher hand controls with a Wi-Fi adapter.",
        defaultHost: "192.168.4.1",
        defaultPort: 11880,
        links: [.udp, .tcp],
        presets: [
            MountConnectionPreset(title: "SynScan Wi-Fi adapter", host: "192.168.4.1", port: 11880, link: .udp),
            MountConnectionPreset(title: "Celestron Wi-Fi", host: "1.2.3.4", port: 2000, link: .tcp),
        ],
        supportsDiscovery: false,
        supportsEpoch: true,
        supportsAxisReversal: true,
        addressNote: """
            The SynScan Wi-Fi adapter usually answers on UDP port 11880, Celestron's Wi-Fi module on TCP port 2000. \
            Check the adapter's manual if unsure. The hand control must be star-aligned before a GoTo.
            """,
        makeDriver: { channel, options in
            guard case .stream(let transport) = channel else {
                throw MountError.invalidInput(detail: "this mount needs a TCP or UDP connection")
            }
            let clock = SystemMountClock()
            let configuration = NexStarConfiguration(epoch: options.epoch, invertsEastWest: options.reversesEastWest)
            return MountDriverBundle(driver: NexStarDriver(transport: transport, clock: clock,
                                                           configuration: configuration), clock: clock)
        })

    static let alpaca = MountConnectionOption(
        id: "alpaca",
        title: "ASCOM Alpaca",
        summary: "Mounts and drivers that offer the ASCOM Alpaca interface on the network.",
        defaultHost: "",
        defaultPort: 11111,
        links: [.http],
        presets: [
            MountConnectionPreset(title: "Default port", host: nil, port: 11111, link: .http),
        ],
        supportsDiscovery: true,
        supportsEpoch: false,
        supportsAxisReversal: true,
        addressNote: """
            Alpaca servers use port 11111 unless set otherwise. If a server has several telescopes, \
            Lodestar drives the first one unless you pick another from the search results.
            """,
        makeDriver: { channel, options in
            guard case .http(let transport) = channel else {
                throw MountError.invalidInput(detail: "this mount needs an HTTP connection")
            }
            let configuration = AlpacaConfiguration(deviceNumber: options.deviceNumber,
                                                    primaryPositiveIsEast: !options.reversesEastWest)
            return MountDriverBundle(driver: AlpacaDriver(transport: transport, configuration: configuration),
                                     clock: SystemMountClock())
        })

    /// A mount that exists only in memory, for trying the screens without hardware. It is not in the picker.
    static let demo = MountConnectionOption(
        id: "demo",
        title: "Demo mount",
        summary: "A simulated mount that slews, syncs and tracks, to try Lodestar without hardware.",
        defaultHost: "",
        defaultPort: 0,
        links: [.tcp],
        presets: [],
        supportsDiscovery: false,
        supportsEpoch: false,
        supportsAxisReversal: false,
        addressNote: "",
        makeDriver: { _, options in
            let start = options.demoStart ?? EquatorialCoordinate(rightAscension: 0, declination: 45)
            let clock = ManualMountClock(start: Date())
            let model = MountSimulatorModel(clock: clock, start: start)
            let transport = LX200Simulator(clock: clock, mount: model, dialect: .onstep, productName: "On-Step demo")
            let driver = LX200Driver(transport: transport, clock: clock)
            // The simulator's clock only moves when told to: bring it up to real time before every job.
            var lastReal = Date()
            let prepare: () -> Void = {
                let now = Date()
                clock.advance(seconds: now.timeIntervalSince(lastReal))
                lastReal = now
            }
            return MountDriverBundle(driver: driver, clock: clock, prepare: prepare)
        })

    // MARK: Links

    /// The link for `form`, or `nil` if the address or port cannot be used.
    func makeChannel(for form: MountConnectionForm) -> MountChannel? {
        if id == Self.demo.id { return .simulated }
        let address = MountAddress(text: form.host, defaultPort: form.port)
        switch form.link {
        case .tcp:
            return MountSocketTransport(host: address.host, port: address.port, kind: .tcp).map(MountChannel.stream)
        case .udp:
            return MountSocketTransport(host: address.host, port: address.port, kind: .udp).map(MountChannel.stream)
        case .http:
            return AlpacaEndpoint.validated(host: address.host, port: address.port)
                .map { MountChannel.http(MountHTTPTransport(endpoint: $0)) }
        }
    }
}

/// What the person typed into the address field: a host, optionally with a port ("192.168.0.1:9999") or a web address
/// ("http://192.168.1.20:11111/"). A port in the text wins over the port field.
struct MountAddress: Equatable {
    let host: String
    let port: Int

    init(text: String, defaultPort: Int) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        var port = defaultPort
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        // A single colon followed by digits is a port; more colons would be an IPv6 address, which stays as typed.
        if parts.count == 2, let typed = Int(parts[1]), !parts[0].isEmpty {
            value = String(parts[0])
            port = typed
        }
        host = value
        self.port = port
    }
}

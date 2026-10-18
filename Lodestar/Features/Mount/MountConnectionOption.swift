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

/// How a Sky-Watcher mount is set up, where the mount model does not say.
enum MountArrangementChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, altAzimuth, equatorial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .altAzimuth: return "Alt-azimuth"
        case .equatorial: return "Equatorial"
        }
    }

    /// `nil` takes it from the mount model.
    var mode: SkyWatcherMountMode? {
        switch self {
        case .automatic: return nil
        case .altAzimuth: return .altAzimuth
        case .equatorial: return .equatorial
        }
    }
}

/// The choices of the "Advanced" section that a kind of mount has.
enum MountAdvancedField: Hashable, Sendable {
    /// The frame of the coordinates (JNow or J2000).
    case epoch
    /// Swap east and west for nudges.
    case swapEastWest
    /// Equatorial or alt-azimuth set-up (Sky-Watcher Wi-Fi).
    case arrangement
    /// The first or second axis counts the other way round (Sky-Watcher Wi-Fi).
    case reverseAxis1, reverseAxis2
}

/// The ways the connection screen can look for mounts on the network, with the words for its button and its results.
enum MountDiscoveryKind: Sendable {
    case alpaca, skyWatcher

    var sectionTitle: String {
        switch self {
        case .alpaca: return "Alpaca Devices"
        case .skyWatcher: return "Mounts Found"
        }
    }

    var buttonTitle: String {
        switch self {
        case .alpaca: return "Find Alpaca devices"
        case .skyWatcher: return "Find mount"
        }
    }

    var footer: String {
        switch self {
        case .alpaca:
            return """
                Lodestar asks every address of the Wi-Fi network it is on. Servers on another network, or behind a \
                firewall, are not found: type their address above.
                """
        case .skyWatcher:
            return """
                Lodestar asks the mount's own address (\(SkyWatcherDiscovery.accessPointAddress)) and every address of \
                the Wi-Fi network it is on. If nothing answers, type the mount's address above.
                """
        }
    }

    /// What to tell after a search: how many were found, or what to check.
    func summary(servers: Int, devices: Int) -> String {
        switch self {
        case .alpaca:
            if devices > 0 {
                return "Found \(devices) telescope\(devices == 1 ? "" : "s"). Tap one to use it."
            }
            if servers > 0 {
                return "Found \(servers) Alpaca server\(servers == 1 ? "" : "s"), but no telescope is set up on "
                    + "\(servers == 1 ? "it" : "them")."
            }
            return """
                No Alpaca server answered. Is the iPhone on the same Wi-Fi network as the server? Is Local Network \
                allowed for Lodestar in the iOS Settings app? You can also type the address by hand.
                """
        case .skyWatcher:
            if devices > 0 {
                return "Found \(devices) mount\(devices == 1 ? "" : "s"). Tap one to use it."
            }
            return """
                No Sky-Watcher mount answered. Check that the mount is switched on and the phone is on its Wi-Fi \
                network, or type its address.
                """
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
    /// Where the phone is; a mount that does its pointing in Lodestar needs it to make its driver.
    var location: GeographicLocation?
    /// How a Sky-Watcher mount is set up; `nil` takes it from the mount model.
    var arrangement: SkyWatcherMountMode?
    /// A Sky-Watcher axis counts the other way round.
    var reversesAxis1 = false
    var reversesAxis2 = false
}

/// A driver with the clock it and its controller run on. Made and used on the mount worker thread only.
final class MountDriverBundle {
    let driver: MountDriver
    let clock: MountClock
    /// Run before every job; the demonstration mount moves its clock to real time here.
    let prepare: (() -> Void)?
    /// What the driver can tell besides the controller's status (alignment, pier side), read after every job.
    let detail: (() -> MountDriverDetail)?
    /// The simulated Sky-Watcher turns its telescope to a place, as if the person had centred it with the nudge arrows.
    let centreSimulated: ((EquatorialCoordinate) -> Void)?

    init(driver: MountDriver, clock: MountClock, prepare: (() -> Void)? = nil, detail: (() -> MountDriverDetail)? = nil,
         centreSimulated: ((EquatorialCoordinate) -> Void)? = nil) {
        self.driver = driver
        self.clock = clock
        self.prepare = prepare
        self.detail = detail
        self.centreSimulated = centreSimulated
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
    /// How the connection screen can search the network for this kind of mount, if it can.
    let discovery: MountDiscoveryKind?
    /// The choices of the "Advanced" section.
    let advancedFields: Set<MountAdvancedField>
    /// The mount knows nothing about the sky: Lodestar does the pointing from the phone's location and clock, needs the
    /// mount's home position, and aligns it on stars before the first GoTo (Sky-Watcher Wi-Fi).
    let usesLodestarAlignment: Bool
    /// A line under the address fields.
    let addressNote: String
    let makeDriver: @Sendable (MountChannel, MountDriverOptions) throws -> MountDriverBundle

    var defaultLink: MountLinkKind { links.first ?? .tcp }
    var supportsDiscovery: Bool { discovery != nil }
    /// The simulated mounts.
    var isDemo: Bool { id.hasPrefix("demo") }

    static func == (lhs: MountConnectionOption, rhs: MountConnectionOption) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Registry

    /// The kinds of mount, in the order of the picker.
    static let all: [MountConnectionOption] = [.lx200, .skyWatcher, .nexstar, .alpaca]

    /// The simulated mounts, which are not in the picker.
    static let demos: [MountConnectionOption] = [.demo, .demoSkyWatcher]

    static func option(id: String) -> MountConnectionOption? {
        (all + demos).first { $0.id == id }
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
        discovery: nil,
        advancedFields: [.epoch],
        usesLodestarAlignment: false,
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

    static let skyWatcher = MountConnectionOption(
        id: MountProtocol.skywatcher.rawValue,
        title: SkyWatcherDriver.menuTitle,
        summary: "Sky-Watcher mounts with built-in Wi-Fi, and EQ mounts with the Sky-Watcher Wi-Fi adapter",
        defaultHost: SkyWatcherDiscovery.accessPointAddress,
        defaultPort: SkyWatcherDiscovery.port,
        links: [.udp],
        presets: [
            MountConnectionPreset(title: "The mount's own Wi-Fi", host: SkyWatcherDiscovery.accessPointAddress,
                                  port: SkyWatcherDiscovery.port, link: .udp),
        ],
        discovery: .skyWatcher,
        advancedFields: [.arrangement, .reverseAxis1, .reverseAxis2],
        usesLodestarAlignment: true,
        addressNote: """
            Works with the Wi-Fi built into the Sky-Watcher AZ-GTi and AZ-GTe (on their tripod, or on a wedge as an \
            equatorial mount), the Star Adventurer GTi, and EQ mounts with the Sky-Watcher Wi-Fi adapter. Join the \
            mount's own Wi-Fi network first. These mounts know nothing about the sky: Lodestar does the pointing from \
            your location and the phone's clock, and sends the mount nothing but motor commands. So switch the mount \
            on at its home position (the pictures show it) and align it on one to three stars before the first Go to.
            """,
        makeDriver: { channel, options in
            guard case .stream(let transport) = channel else {
                throw MountError.invalidInput(detail: "this mount needs a UDP connection")
            }
            guard let location = options.location else {
                throw MountError.invalidInput(detail: "your location is not known yet")
            }
            let clock = SystemMountClock()
            let configuration = SkyWatcherConfiguration(location: location, mode: options.arrangement,
                                                        invertsAxis1: options.reversesAxis1,
                                                        invertsAxis2: options.reversesAxis2)
            let driver = SkyWatcherDriver(transport: transport, clock: clock, configuration: configuration)
            return MountDriverBundle(driver: driver, clock: clock, detail: { MountDriverDetail(skyWatcher: driver) })
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
        discovery: nil,
        advancedFields: [.epoch, .swapEastWest],
        usesLodestarAlignment: false,
        addressNote: """
            Works with Celestron NexStar hand controls behind a Wi-Fi bridge (TCP, usually port 2000) and Sky-Watcher \
            SynScan hand controls with the SynScan Wi-Fi adapter (UDP, usually port 11880). For the Wi-Fi built into \
            Star Adventurer GTi and AZ-GTi mounts choose Sky-Watcher Wi-Fi instead. Do the star alignment on the \
            hand controller first: it refuses to slew before that.
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
        discovery: .alpaca,
        advancedFields: [.swapEastWest],
        usesLodestarAlignment: false,
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
        title: "Simulated OnStep mount",
        summary: "A simulated mount that slews, syncs and tracks, to try Lodestar without hardware.",
        defaultHost: "",
        defaultPort: 0,
        links: [.tcp],
        presets: [],
        discovery: nil,
        advancedFields: [],
        usesLodestarAlignment: false,
        addressNote: "",
        makeDriver: { _, options in
            let start = options.demoStart ?? EquatorialCoordinate(rightAscension: 0, declination: 45)
            let clock = ManualMountClock(start: Date())
            let model = MountSimulatorModel(clock: clock, start: start)
            let transport = LX200Simulator(clock: clock, mount: model, dialect: .onstep, productName: "On-Step demo")
            let driver = LX200Driver(transport: transport, clock: clock)
            return MountDriverBundle(driver: driver, clock: clock, prepare: MountConnectionOption.realTimePreparation(of: clock))
        })

    /// A simulated Sky-Watcher AZ-GTi that was switched on a little off its home position and set up a little crooked, so
    /// the alignment has something to find. It is not in the picker.
    static let demoSkyWatcher = MountConnectionOption(
        id: "demo-skywatcher",
        title: "Simulated Sky-Watcher mount",
        summary: "A simulated Sky-Watcher AZ-GTi: align it on stars, then go to targets.",
        defaultHost: "",
        defaultPort: 0,
        links: [.udp],
        presets: [],
        discovery: nil,
        advancedFields: [],
        usesLodestarAlignment: true,
        addressNote: "",
        makeDriver: { _, options in
            let location = options.location ?? GeographicLocation(latitude: 40, longitude: -105, elevation: 0)
            let mode = options.arrangement ?? .altAzimuth
            let clock = ManualMountClock(start: Date())
            // What a mount set up by hand typically has wrong: a few degrees of home position, a fraction of a degree of tilt.
            let errors = SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: 1.1, baseTiltX: 0.5, baseTiltY: -0.4,
                                                  orthogonality: 0.1, cone: 0.12)
            let version = mode == .altAzimuth ? SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5)
                : SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C)
            let simulator = SkyWatcherSimulator(clock: clock, location: location, mode: mode, errors: errors, version: version)
            let driver = SkyWatcherDriver(transport: simulator, clock: clock,
                                          configuration: SkyWatcherConfiguration(location: location, mode: mode))
            let centre: (EquatorialCoordinate) -> Void = { star in
                centreSimulator(simulator, on: star, at: clock.now())
            }
            return MountDriverBundle(driver: driver, clock: clock, prepare: MountConnectionOption.realTimePreparation(of: clock),
                                     detail: { MountDriverDetail(skyWatcher: driver) }, centreSimulated: centre)
        })

    /// The simulators' clock only moves when told to: this brings it up to real time before every job.
    private static func realTimePreparation(of clock: ManualMountClock) -> () -> Void {
        var lastReal = Date()
        return {
            let now = Date()
            clock.advance(seconds: now.timeIntervalSince(lastReal))
            lastReal = now
        }
    }

    // MARK: Links

    /// The link for `form`, or `nil` if the address or port cannot be used.
    func makeChannel(for form: MountConnectionForm) -> MountChannel? {
        if isDemo { return .simulated }
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

/// Turns the simulated axes so that the telescope, with its real and slightly wrong geometry, points at `star` at `date`.
private func centreSimulator(_ simulator: SkyWatcherSimulator, on star: EquatorialCoordinate, at date: Date) {
    let observer = Observer(location: simulator.location)
    let frame = SkyFrame(date: date, observer: observer)
    let place = MountEpoch.apparentOfDate.fromJ2000(star, frame: frame)
    let direction = SkyWatcherSky.localDirection(place, localSiderealTime: frame.localApparentSiderealTime,
                                                 latitude: simulator.location.latitude, mode: simulator.mode)
    let truth = SkyWatcherPointingModel(mode: simulator.mode, isSouthernHemisphere: simulator.location.latitude < 0,
                                        errors: simulator.effectiveErrors)
    let options = truth.solutions(direction, preferredAxis1Degrees: simulator.axis1Degrees)
    // An equatorial mount keeps the counterweight below the horizontal; an alt-azimuth one stays on its normal side.
    let allowed = options.filter { option in
        simulator.mode == .equatorial ? abs(truth.modelAxis1(option.axis1)) <= 95 : option.pierSide == .east
    }
    let candidates = allowed.isEmpty ? options : allowed
    let best = candidates.min { first, second in
        abs(first.axis1 - simulator.axis1Degrees) + abs(first.axis2 - simulator.axis2Degrees)
            < abs(second.axis1 - simulator.axis1Degrees) + abs(second.axis2 - simulator.axis2Degrees)
    }
    if let best { simulator.placeAxes(axis1Degrees: best.axis1, axis2Degrees: best.axis2) }
}

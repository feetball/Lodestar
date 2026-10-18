import Darwin
import Foundation
import LodestarKit

/// A mount found on the local network, or looked up at an address.
struct MountFoundDevice: Identifiable, Hashable, Sendable {
    let host: String
    let port: Int
    /// Which telescope of an Alpaca server (0 for the other kinds).
    let deviceNumber: Int
    let name: String

    var id: String { "\(host):\(port)#\(deviceNumber)" }
    var addressText: String { "\(host):\(port)" }
}

/// What a search found.
struct MountSearchResult: Sendable {
    var devices: [MountFoundDevice] = []
    /// Servers that answered the search message, with or without a telescope.
    var serverCount = 0
}

/// Sends one small UDP message to the addresses of the local network and collects the answers.
///
/// Multicast and broadcast on iOS: a UDP broadcast or multicast needs Apple's *Multicast Networking* entitlement
/// (`com.apple.developer.networking.multicast`, granted on request), which Lodestar does not have. The search therefore
/// does not depend on it. It sends the message by plain unicast UDP to every address of the local subnet (up to a /22,
/// so at most 1,022 small datagrams, less than a second), which needs no entitlement, and additionally tries the
/// directed broadcast address and any fixed addresses of the caller, which are simply dropped when the entitlement is
/// missing. The answers come back as ordinary unicast datagrams. BSD sockets are used because a connected `NWConnection`
/// only accepts answers from one sender. Servers that the search misses (another subnet, a firewall) are reached by
/// typing their address.
enum MountSubnetProbe {
    /// An IPv4 network this device is on.
    struct LocalNetwork {
        /// This device's address and the network mask, in host byte order.
        let address: UInt32
        let mask: UInt32

        var hostMask: UInt32 { ~mask }
        var prefixLength: Int { mask.nonzeroBitCount }
        var addressText: String { MountSubnetProbe.text(of: address) }
        var broadcast: UInt32 { (address & mask) | hostMask }
    }

    /// Where to send the message for one network.
    struct Plan {
        /// Addresses to try besides the sweep (a broadcast address, the mount's access point address).
        var addresses: [UInt32] = []
        /// Send to every address of the subnet as well.
        var sweepsSubnet = true
    }

    struct Reply {
        let host: String
        let bytes: [UInt8]
    }

    /// The largest host mask the sweep covers (a /22 network has 1,022 hosts).
    private static let maximumSweepHostMask: UInt32 = 1_023

    /// Sends `payload` to port `port` as `plan` says for each network and returns the replies that arrive in
    /// `listenSeconds`, one per sender. Blocks; call it off the main actor.
    static func run(payload: [UInt8], port: Int, listenSeconds: Double, cancel: MountCancelFlag,
                    plan: (LocalNetwork) -> Plan) -> [Reply] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        var enabled: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }

        var sentCount = 0
        for network in localNetworks() {
            let chosen = plan(network)
            for address in chosen.addresses {
                _ = sendDatagram(payload, port: port, from: descriptor, to: address)
            }
            guard chosen.sweepsSubnet else { continue }
            // A network wider than /22 is cut down to the /24 around this device.
            let hostMask = network.hostMask
            let sweepBase: UInt32
            let sweepMask: UInt32
            if hostMask > maximumSweepHostMask {
                sweepBase = network.address & 0xFFFF_FF00
                sweepMask = 0xFF
            } else {
                sweepBase = network.address & network.mask
                sweepMask = hostMask
            }
            guard sweepMask >= 2 else { continue }
            var offset: UInt32 = 1
            while offset < sweepMask {
                let target = sweepBase | offset
                offset += 1
                if target == network.address { continue }
                _ = sendDatagram(payload, port: port, from: descriptor, to: target)
                sentCount += 1
                // Give the socket's buffer time to drain now and then.
                if sentCount % 64 == 0 { usleep(2_000) }
                if cancel.isCancelled { return [] }
            }
        }
        return listen(on: descriptor, listenSeconds: listenSeconds, cancel: cancel)
    }

    /// Reads answers until the listening time is up.
    private static func listen(on descriptor: Int32, listenSeconds: Double, cancel: MountCancelFlag) -> [Reply] {
        var replies: [Reply] = []
        var seen = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 1_500)
        let capacity = buffer.count
        let deadline = Date(timeIntervalSinceNow: listenSeconds)
        while Date() < deadline && !cancel.isCancelled {
            var pending = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&pending, 1, 100) > 0 else { continue }
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { senderPointer in
                senderPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    recvfrom(descriptor, &buffer, capacity, 0, generic, &senderLength)
                }
            }
            guard count > 0 else { continue }
            let host = text(of: UInt32(bigEndian: sender.sin_addr.s_addr))
            if seen.insert(host).inserted { replies.append(Reply(host: host, bytes: Array(buffer.prefix(count)))) }
        }
        return replies
    }

    private static func sendDatagram(_ payload: [UInt8], port: Int, from descriptor: Int32, to address: UInt32) -> Bool {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = in_port_t(port).bigEndian
        target.sin_addr = in_addr(s_addr: address.bigEndian)
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        for attempt in 0..<2 {
            let sent = withUnsafePointer(to: &target) { targetPointer in
                targetPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    sendto(descriptor, payload, payload.count, 0, generic, length)
                }
            }
            if sent >= 0 { return true }
            // A full send buffer clears in a moment; other errors (no route, not permitted) do not.
            guard errno == ENOBUFS || errno == EAGAIN, attempt == 0 else { return false }
            usleep(5_000)
        }
        return false
    }

    /// The IPv4 networks of the Wi-Fi, Ethernet and Personal Hotspot interfaces that are up.
    static func localNetworks() -> [LocalNetwork] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(first) }
        var networks: [LocalNetwork] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            let flags = Int32(bitPattern: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, let mask = entry.pointee.ifa_netmask,
                  address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            networks.append(LocalNetwork(address: ip, mask: netmask))
        }
        return networks
    }

    static func text(of address: UInt32) -> String {
        "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }

    /// The value of a dotted IPv4 address, or `nil`.
    static func address(of text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        return value
    }
}

/// Finds ASCOM Alpaca servers on the Wi-Fi network and lists their telescopes.
///
/// The Alpaca discovery message is the 16 bytes `alpacadiscovery1` sent by UDP to port 32227; every server answers
/// with `{"AlpacaPort": n}` from its own address. See `MountSubnetProbe` for how it reaches them without the multicast
/// entitlement.
enum MountAlpacaDiscovery {
    /// How long the search listens for answers once the messages are out.
    static let listenSeconds = 2.0
    /// Servers asked for their telescopes, at most.
    private static let maximumServers = 8
    private static let lookupTimeoutSeconds = 4.0
    /// All the lookups together take at most about this long.
    private static let maximumLookupSeconds = 10.0

    /// Searches for servers and lists their telescopes. Blocks for a few seconds; call it off the main actor.
    static func search(cancel: MountCancelFlag) -> MountSearchResult {
        let replies = MountSubnetProbe.run(payload: AlpacaDiscovery.requestPayload, port: AlpacaDiscovery.port,
                                           listenSeconds: listenSeconds, cancel: cancel) { network in
            MountSubnetProbe.Plan(addresses: [network.broadcast], sweepsSubnet: true)
        }
        var servers: [(host: String, port: Int)] = []
        for reply in replies {
            if let port = try? AlpacaDiscovery.parseResponse(reply.bytes) { servers.append((reply.host, port)) }
        }
        var result = MountSearchResult()
        result.serverCount = servers.count
        let lookupDeadline = Date(timeIntervalSinceNow: maximumLookupSeconds)
        for server in servers.prefix(maximumServers) where !cancel.isCancelled && Date() < lookupDeadline {
            if let found = try? telescopes(host: server.host, port: server.port) {
                result.devices.append(contentsOf: found)
            }
        }
        return result
    }

    /// The telescopes that the Alpaca server at `host:port` has configured.
    static func telescopes(host: String, port: Int) throws -> [MountFoundDevice] {
        guard let endpoint = AlpacaEndpoint.validated(host: host, port: port) else {
            throw MountError.invalidInput(detail: "the address is not valid")
        }
        let transport = MountHTTPTransport(endpoint: endpoint)
        defer { transport.close() }
        let request = AlpacaRequestBuilder().configuredDevices()
        let response = try transport.send(request, timeoutSeconds: lookupTimeoutSeconds)
        let devices = try AlpacaResponseParser.configuredDevices(response, for: request)
        return devices.filter(\.isTelescope).map {
            MountFoundDevice(host: host, port: port, deviceNumber: $0.deviceNumber, name: $0.deviceName)
        }
    }
}

/// Finds Sky-Watcher Wi-Fi mounts: sends the motor board version probe (`:e1`) to the mount's access point address and, when
/// the phone is on another network, to the subnet's broadcast address and every address of the subnet, and reads the
/// versions that come back. A mount that makes its own network answers at 192.168.4.1; one that joined the home network
/// answers from its own address.
enum MountSkyWatcherProbe {
    static let listenSeconds = 1.5

    /// Blocks for a few seconds; call it off the main actor.
    static func search(cancel: MountCancelFlag) -> MountSearchResult {
        let replies = MountSubnetProbe.run(payload: SkyWatcherDiscovery.probePayload, port: SkyWatcherDiscovery.port,
                                           listenSeconds: listenSeconds, cancel: cancel) { network in
            let targets = SkyWatcherDiscovery.probeTargets(network.addressText, prefixLength: network.prefixLength)
                .compactMap(MountSubnetProbe.address(of:))
            // On the mount's own network the access point address is the only candidate: no need to sweep.
            let onAccessPoint = targets.count == 1
            return MountSubnetProbe.Plan(addresses: targets, sweepsSubnet: !onAccessPoint)
        }
        var result = MountSearchResult()
        for reply in replies {
            guard let version = try? SkyWatcherDiscovery.parseProbeReply(reply.bytes) else { continue }
            result.serverCount += 1
            result.devices.append(MountFoundDevice(host: reply.host, port: SkyWatcherDiscovery.port, deviceNumber: 0,
                                                   name: "Sky-Watcher \(version.mountName) \(version.description)"))
        }
        return result
    }
}

import Darwin
import Foundation
import LodestarKit

/// An Alpaca telescope found on the local network, or looked up at an address.
struct MountAlpacaTelescope: Identifiable, Hashable, Sendable {
    let host: String
    let port: Int
    let deviceNumber: Int
    let name: String

    var id: String { "\(host):\(port)#\(deviceNumber)" }
    var addressText: String { "\(host):\(port)" }
}

/// What a search for Alpaca servers found.
struct MountAlpacaSearchResult: Sendable {
    var telescopes: [MountAlpacaTelescope] = []
    /// Servers that answered the discovery message, with or without a telescope.
    var serverCount = 0
}

/// Finds ASCOM Alpaca servers on the Wi-Fi network and lists their telescopes.
///
/// The Alpaca discovery message is the 16 bytes `alpacadiscovery1` sent by UDP to port 32227; every server answers
/// with `{"AlpacaPort": n}` from its own address.
///
/// Multicast and broadcast on iOS: a UDP broadcast or multicast needs Apple's *Multicast Networking* entitlement
/// (`com.apple.developer.networking.multicast`, granted on request), which Lodestar does not have. The search therefore
/// does not depend on it. It sends the message by plain unicast UDP to every address of the local subnet (up to /22,
/// so at most 1,022 small datagrams, less than a second), which needs no entitlement, and additionally tries the
/// subnet's directed broadcast address, which is simply dropped when the entitlement is missing. The answers come back
/// as ordinary unicast datagrams. BSD sockets are used because a connected `NWConnection` only accepts answers from one
/// sender. Servers that the search misses (another subnet, a firewall) are reached by typing their address.
enum MountAlpacaDiscovery {
    /// How long the search listens for answers once the messages are out.
    static let listenSeconds = 2.0
    /// Servers asked for their telescopes, at most.
    private static let maximumServers = 8
    /// The largest host mask the sweep covers (a /22 network has 1,022 hosts).
    private static let maximumSweepHostMask: UInt32 = 1_023
    private static let lookupTimeoutSeconds = 4.0
    /// All the lookups together take at most about this long.
    private static let maximumLookupSeconds = 10.0

    private struct LocalNetwork {
        /// This device's address and the network mask, in host byte order.
        let address: UInt32
        let mask: UInt32
    }

    /// Searches for servers and lists their telescopes. Blocks for a few seconds; call it off the main actor.
    static func search(cancel: MountCancelFlag) -> MountAlpacaSearchResult {
        let servers = findServers(cancel: cancel)
        var result = MountAlpacaSearchResult()
        result.serverCount = servers.count
        let lookupDeadline = Date(timeIntervalSinceNow: maximumLookupSeconds)
        for server in servers.prefix(maximumServers) where !cancel.isCancelled && Date() < lookupDeadline {
            if let found = try? telescopes(host: server.host, port: server.port) {
                result.telescopes.append(contentsOf: found)
            }
        }
        return result
    }

    /// The telescopes that the Alpaca server at `host:port` has configured.
    static func telescopes(host: String, port: Int) throws -> [MountAlpacaTelescope] {
        guard let endpoint = AlpacaEndpoint.validated(host: host, port: port) else {
            throw MountError.invalidInput(detail: "the address is not valid")
        }
        let transport = MountHTTPTransport(endpoint: endpoint)
        defer { transport.close() }
        let request = AlpacaRequestBuilder().configuredDevices()
        let response = try transport.send(request, timeoutSeconds: lookupTimeoutSeconds)
        let devices = try AlpacaResponseParser.configuredDevices(response, for: request)
        return devices.filter(\.isTelescope).map {
            MountAlpacaTelescope(host: host, port: port, deviceNumber: $0.deviceNumber, name: $0.deviceName)
        }
    }

    // MARK: Discovery datagrams

    private struct Server: Hashable {
        let host: String
        let port: Int
    }

    private static func findServers(cancel: MountCancelFlag) -> [Server] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        var enabled: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }

        let payload = AlpacaDiscovery.requestPayload
        var sentCount = 0
        for network in localNetworks() {
            let hostMask = ~network.mask
            let base = network.address & network.mask
            // A directed broadcast: dropped silently without the multicast entitlement.
            _ = sendDatagram(payload, from: descriptor, to: base | hostMask)
            // The sweep: a network wider than /22 is cut down to the /24 around this device.
            let sweepBase: UInt32
            let sweepMask: UInt32
            if hostMask > maximumSweepHostMask {
                sweepBase = network.address & 0xFFFF_FF00
                sweepMask = 0xFF
            } else {
                sweepBase = base
                sweepMask = hostMask
            }
            guard sweepMask >= 2 else { continue }
            var offset: UInt32 = 1
            while offset < sweepMask {
                let target = sweepBase | offset
                offset += 1
                if target == network.address { continue }
                _ = sendDatagram(payload, from: descriptor, to: target)
                sentCount += 1
                // Give the socket's buffer time to drain now and then.
                if sentCount % 64 == 0 { usleep(2_000) }
                if cancel.isCancelled { return [] }
            }
        }
        return listen(on: descriptor, cancel: cancel)
    }

    /// Reads answers until the listening time is up.
    private static func listen(on descriptor: Int32, cancel: MountCancelFlag) -> [Server] {
        var servers: [Server] = []
        var seen = Set<Server>()
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
            guard count > 0, let port = try? AlpacaDiscovery.parseResponse(Array(buffer.prefix(count))) else { continue }
            let address = UInt32(bigEndian: sender.sin_addr.s_addr)
            let host = "\(address >> 24 & 0xFF).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
            let server = Server(host: host, port: port)
            if seen.insert(server).inserted { servers.append(server) }
        }
        return servers
    }

    private static func sendDatagram(_ payload: [UInt8], from descriptor: Int32, to address: UInt32) -> Bool {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = in_port_t(AlpacaDiscovery.port).bigEndian
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
    private static func localNetworks() -> [LocalNetwork] {
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
}

import Foundation

/// Finding a Sky-Watcher Wi-Fi mount: the access point address of a mount that makes its own network, and a UDP probe for mounts
/// that joined the home network. The engine does no networking: the apps send `probePayload` as a UDP datagram to port `port` of
/// `accessPointAddress` (or of the subnet's broadcast address, see `broadcastAddress`) and hand every reply to `parseProbeReply`.
///
/// Reference: "Motor Controller Command Set", section "Wi-Fi Connection": the module runs a UDP server on port 11880; in access
/// point mode its address is 192.168.4.1; commands and replies each fit in one datagram.
public enum SkyWatcherDiscovery {
    /// The UDP port of the mount's motor controller.
    public static let port = 11880

    /// The mount's address when it runs its own access point.
    public static let accessPointAddress = "192.168.4.1"

    /// The datagram to send: `:e1` and a carriage return (inquire the motor board version of channel 1).
    public static var probePayload: [UInt8] {
        (try? SkyWatcherCodec.inquire(.inquireVersion, axis: .axis1)) ?? [0x3A, 0x65, 0x31, 0x0D]
    }

    /// True if `bytes` is the probe datagram (for simulators that answer it).
    public static func isProbe(_ bytes: [UInt8]) -> Bool { bytes == probePayload }

    /// Decodes a reply datagram to the probe.
    ///
    /// - Throws: `MountError.malformedReply` if it is not a motor board version reply.
    public static func parseProbeReply(_ datagram: [UInt8]) throws -> SkyWatcherVersion {
        switch try SkyWatcherCodec.parseDatagram(datagram) {
        case let .success(payload): return try SkyWatcherCodec.decodeVersion(payload)
        case let .failure(code): throw MountError.malformedReply(detail: "the device answered with error \(code)")
        }
    }

    /// The directed broadcast address of the subnet of `address` (dotted IPv4) with `prefixLength` network bits (8 to 30), or nil.
    public static func broadcastAddress(_ address: String, prefixLength: Int) -> String? {
        guard let octets = parseIPv4(address) else { return nil }
        if prefixLength < 8 || prefixLength > 30 { return nil }
        let value = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
        let hostMask = (1 << (32 - prefixLength)) - 1
        let broadcast = value | hostMask
        return "\((broadcast >> 24) & 255).\((broadcast >> 16) & 255).\((broadcast >> 8) & 255).\(broadcast & 255)"
    }

    /// The addresses to probe, best first: the access point address (when the phone is on the mount's own network, `address` is in
    /// 192.168.4.0/24, only that), otherwise the subnet's broadcast address; empty when `address` is not a valid address.
    public static func probeTargets(_ address: String, prefixLength: Int) -> [String] {
        guard let octets = parseIPv4(address) else { return [] }
        if octets[0] == 192 && octets[1] == 168 && octets[2] == 4 { return [accessPointAddress] }
        guard let broadcast = broadcastAddress(address, prefixLength: prefixLength) else { return [accessPointAddress] }
        return [broadcast, accessPointAddress]
    }

    private static func parseIPv4(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 4 { return nil }
        var result = [Int](repeating: 0, count: 4)
        for index in 0 ..< 4 {
            let part = Array(parts[index].unicodeScalars)
            if part.isEmpty || part.count > 3 { return nil }
            var value = 0
            for scalar in part {
                if scalar.value < 48 || scalar.value > 57 { return nil }
                value = value * 10 + Int(scalar.value) - 48
            }
            if value > 255 { return nil }
            result[index] = value
        }
        return result
    }
}

import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The pure parts of Services/MountDiscovery.swift: the dotted-address arithmetic, the networks of this device and the values the
/// search hands to the screens. Nothing here sends a packet; the parts that need a server are in MountNetTransportTests.swift
/// (loopback only), and the searches that would scan the real network are not tested at all.
final class MountNetDiscoveryTests: XCTestCase {
    // MARK: Addresses as numbers

    func testAnAddressIsWrittenAsFourDecimalNumbers() {
        XCTAssertEqual(MountSubnetProbe.text(of: 0x0000_0000), "0.0.0.0")
        XCTAssertEqual(MountSubnetProbe.text(of: 0xFFFF_FFFF), "255.255.255.255")
        XCTAssertEqual(MountSubnetProbe.text(of: 0xC0A8_0101), "192.168.1.1")
        XCTAssertEqual(MountSubnetProbe.text(of: 0xC0A8_0401), "192.168.4.1")
        XCTAssertEqual(MountSubnetProbe.text(of: 0x7F00_0001), "127.0.0.1")
        XCTAssertEqual(MountSubnetProbe.text(of: 0x0A00_00FE), "10.0.0.254")
        XCTAssertEqual(MountSubnetProbe.text(of: 0x0102_0304), "1.2.3.4")
    }

    func testAnAddressIsReadFromFourDecimalNumbers() {
        XCTAssertEqual(MountSubnetProbe.address(of: "0.0.0.0"), 0)
        XCTAssertEqual(MountSubnetProbe.address(of: "255.255.255.255"), 0xFFFF_FFFF)
        XCTAssertEqual(MountSubnetProbe.address(of: "192.168.4.1"), 0xC0A8_0401)
        XCTAssertEqual(MountSubnetProbe.address(of: "10.0.0.254"), 0x0A00_00FE)
        XCTAssertEqual(MountSubnetProbe.address(of: "1.2.3.4"), 0x0102_0304)
    }

    func testTextAndNumberAreInverse() {
        for value: UInt32 in [0, 1, 255, 256, 0x7F00_0001, 0xC0A8_0164, 0xAC10_FFFE, 0xFFFF_FFFE, 0xFFFF_FFFF] {
            XCTAssertEqual(MountSubnetProbe.address(of: MountSubnetProbe.text(of: value)), value)
        }
        for text in ["0.0.0.0", "8.8.4.4", "172.16.255.254", "192.168.0.1", "255.255.255.0"] {
            XCTAssertEqual(MountSubnetProbe.address(of: text).map(MountSubnetProbe.text(of:)), text)
        }
    }

    func testTextThatIsNotADottedAddressIsRefused() {
        let refused = [
            "", "1", "1.2", "1.2.3", "1.2.3.4.5", "...", "1..3.4", ".2.3.4", "1.2.3.",
            "256.1.1.1", "1.256.1.1", "1.1.256.1", "1.1.1.256", "999.999.999.999", "4294967296",
            "a.b.c.d", "1.2.3.x", "one.two.three.four", "1.2.3.4 ", " 1.2.3.4", "1. 2.3.4",
            "-1.2.3.4", "1.2.3.-4", "1.2.3.4/24", "1.2.3.4:80", "fe80::1", "0x7f.0.0.1", "1,2,3,4",
        ]
        for text in refused {
            XCTAssertNil(MountSubnetProbe.address(of: text), "'\(text)'")
        }
    }

    func testTheLargestOctetIs255() {
        XCTAssertNotNil(MountSubnetProbe.address(of: "255.255.255.255"))
        XCTAssertNil(MountSubnetProbe.address(of: "255.255.255.256"))
        XCTAssertNotNil(MountSubnetProbe.address(of: "0.0.0.0"))
    }

    // MARK: Networks

    func testAClassCNetwork() {
        // 192.168.1.37 with the mask 255.255.255.0
        let network = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0125, mask: 0xFFFF_FF00)
        XCTAssertEqual(network.hostMask, 0x0000_00FF)
        XCTAssertEqual(network.prefixLength, 24)
        XCTAssertEqual(network.addressText, "192.168.1.37")
        XCTAssertEqual(network.broadcast, 0xC0A8_01FF)
        XCTAssertEqual(MountSubnetProbe.text(of: network.broadcast), "192.168.1.255")
    }

    func testANetworkWiderThanAClassC() {
        // 10.1.5.9 with the mask 255.255.252.0 (a /22)
        let network = MountSubnetProbe.LocalNetwork(address: 0x0A01_0509, mask: 0xFFFF_FC00)
        XCTAssertEqual(network.hostMask, 0x0000_03FF)
        XCTAssertEqual(network.prefixLength, 22)
        XCTAssertEqual(network.addressText, "10.1.5.9")
        XCTAssertEqual(MountSubnetProbe.text(of: network.broadcast), "10.1.7.255")
    }

    func testAClassBNetwork() {
        let network = MountSubnetProbe.LocalNetwork(address: 0xAC10_0A0B, mask: 0xFFFF_0000)
        XCTAssertEqual(network.prefixLength, 16)
        XCTAssertEqual(network.hostMask, 0x0000_FFFF)
        XCTAssertEqual(MountSubnetProbe.text(of: network.broadcast), "172.16.255.255")
    }

    func testAPersonalHotspotNetwork() {
        // 172.20.10.2 with 255.255.255.240 (a /28)
        let network = MountSubnetProbe.LocalNetwork(address: 0xAC14_0A02, mask: 0xFFFF_FFF0)
        XCTAssertEqual(network.prefixLength, 28)
        XCTAssertEqual(network.hostMask, 0x0F)
        XCTAssertEqual(MountSubnetProbe.text(of: network.broadcast), "172.20.10.15")
    }

    func testTheBroadcastAddressDoesNotDependOnTheHostPart() {
        let first = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0101, mask: 0xFFFF_FF00)
        let last = MountSubnetProbe.LocalNetwork(address: 0xC0A8_01FE, mask: 0xFFFF_FF00)
        XCTAssertEqual(first.broadcast, last.broadcast)
    }

    func testTheExtremeMasks() {
        let single = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0105, mask: 0xFFFF_FFFF)
        XCTAssertEqual(single.prefixLength, 32)
        XCTAssertEqual(single.hostMask, 0)
        XCTAssertEqual(single.broadcast, 0xC0A8_0105, "a network of one address broadcasts to itself")

        let everything = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0105, mask: 0)
        XCTAssertEqual(everything.prefixLength, 0)
        XCTAssertEqual(everything.hostMask, 0xFFFF_FFFF)
        XCTAssertEqual(everything.broadcast, 0xFFFF_FFFF)
    }

    func testTheBroadcastAgreesWithTheEnginesOwnArithmetic() {
        // LodestarKit works on the text of the address; the app on the numbers. They must name the same address.
        let cases: [(String, UInt32, Int)] = [
            ("192.168.1.37", 0xC0A8_0125, 24), ("10.1.5.9", 0x0A01_0509, 22), ("172.16.10.11", 0xAC10_0A0B, 16),
            ("172.20.10.2", 0xAC14_0A02, 28), ("10.0.0.7", 0x0A00_0007, 8),
        ]
        for (text, address, prefix) in cases {
            let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
            let network = MountSubnetProbe.LocalNetwork(address: address, mask: mask)
            XCTAssertEqual(network.addressText, text)
            XCTAssertEqual(network.prefixLength, prefix)
            XCTAssertEqual(MountSubnetProbe.text(of: network.broadcast),
                           SkyWatcherDiscovery.broadcastAddress(text, prefixLength: prefix), text)
        }
    }

    func testTheProbeTargetsOfANetworkAreNumbers() throws {
        // What the Sky-Watcher search does with the engine's text answers.
        let home = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0125, mask: 0xFFFF_FF00)
        let targets = SkyWatcherDiscovery.probeTargets(home.addressText, prefixLength: home.prefixLength)
            .compactMap(MountSubnetProbe.address(of:))
        XCTAssertEqual(targets, [0xC0A8_01FF, 0xC0A8_0401], "the broadcast address, then the mount's own address")

        let onTheMount = MountSubnetProbe.LocalNetwork(address: 0xC0A8_0402, mask: 0xFFFF_FF00)
        let alone = SkyWatcherDiscovery.probeTargets(onTheMount.addressText, prefixLength: onTheMount.prefixLength)
            .compactMap(MountSubnetProbe.address(of:))
        XCTAssertEqual(alone, [0xC0A8_0401], "on the mount's own network that is the only candidate")
    }

    func testTheNetworksOfThisDeviceAreConsistent() {
        // Whatever the machine has, each network must obey the arithmetic of its own address and mask. Nothing is sent.
        for network in MountSubnetProbe.localNetworks() {
            XCTAssertEqual(network.hostMask, ~network.mask)
            XCTAssertEqual(network.broadcast & network.mask, network.address & network.mask)
            XCTAssertEqual(network.broadcast | network.mask, 0xFFFF_FFFF)
            XCTAssertTrue((0...32).contains(network.prefixLength))
            XCTAssertNotEqual(network.address >> 24, 127, "the loopback interface is not a network to search")
            XCTAssertEqual(MountSubnetProbe.address(of: network.addressText), network.address)
        }
    }

    // MARK: Plans and results

    func testAPlanSweepsTheSubnetUnlessToldNotTo() {
        let plan = MountSubnetProbe.Plan()
        XCTAssertTrue(plan.addresses.isEmpty)
        XCTAssertTrue(plan.sweepsSubnet)
        let special = MountSubnetProbe.Plan(addresses: [0xC0A8_0401], sweepsSubnet: false)
        XCTAssertEqual(special.addresses, [0xC0A8_0401])
        XCTAssertFalse(special.sweepsSubnet)
    }

    func testAnEmptySearchResultFoundNothing() {
        let result = MountSearchResult()
        XCTAssertTrue(result.devices.isEmpty)
        XCTAssertEqual(result.serverCount, 0)
    }

    func testAFoundDeviceIsNamedByItsAddressAndNumber() {
        let device = MountFoundDevice(host: "192.168.1.20", port: 11111, deviceNumber: 2, name: "Dobsonian")
        XCTAssertEqual(device.id, "192.168.1.20:11111#2")
        XCTAssertEqual(device.addressText, "192.168.1.20:11111")
        let skyWatcher = MountFoundDevice(host: "192.168.4.1", port: 11880, deviceNumber: 0, name: "Sky-Watcher AZ-GTi 3.22")
        XCTAssertEqual(skyWatcher.id, "192.168.4.1:11880#0")
        XCTAssertEqual(skyWatcher.addressText, "192.168.4.1:11880")
    }

    func testTwoTelescopesOfOneServerAreTwoDevices() {
        let first = MountFoundDevice(host: "10.0.0.5", port: 11111, deviceNumber: 0, name: "A")
        let second = MountFoundDevice(host: "10.0.0.5", port: 11111, deviceNumber: 1, name: "B")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second, first]).count, 2)
        XCTAssertEqual(first.addressText, second.addressText)
    }

    func testDevicesAreEqualWhenAllTheirFieldsAre() {
        XCTAssertEqual(MountFoundDevice(host: "h", port: 1, deviceNumber: 0, name: "n"),
                       MountFoundDevice(host: "h", port: 1, deviceNumber: 0, name: "n"))
        XCTAssertNotEqual(MountFoundDevice(host: "h", port: 1, deviceNumber: 0, name: "n"),
                          MountFoundDevice(host: "h", port: 1, deviceNumber: 0, name: "other name"))
    }
}

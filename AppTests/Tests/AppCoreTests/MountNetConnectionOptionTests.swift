import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The pure parts of Features/Mount/MountConnectionOption.swift: the kinds of mount and their defaults, the parsing of what is
/// typed into the address field, the links made from a form, and the drivers the factories build (none of them is connected to
/// a real mount; the demonstration mounts are in memory).
final class MountNetConnectionOptionTests: XCTestCase {
    private let location = GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650)

    private func throwsInvalidInput(_ expected: String, file: StaticString = #filePath, line: UInt = #line,
                                    _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? MountError, MountError.invalidInput(detail: expected), file: file, line: line)
        }
    }

    private func streamChannel(kind: MountSocketTransport.Kind) throws -> MountChannel {
        MountChannel.stream(try XCTUnwrap(MountSocketTransport(host: "127.0.0.1", port: 9, kind: kind)))
    }

    private func httpChannel() -> MountChannel {
        MountChannel.http(MountHTTPTransport(endpoint: AlpacaEndpoint(host: "127.0.0.1", port: 9)))
    }

    // MARK: Links, epochs and arrangements

    func testTheLinkKindsAreNamedForTheScreen() {
        XCTAssertEqual(MountLinkKind.allCases, [.tcp, .udp, .http])
        XCTAssertEqual(MountLinkKind.allCases.map(\.title), ["TCP", "UDP", "HTTP"])
        XCTAssertEqual(MountLinkKind.allCases.map(\.id), ["tcp", "udp", "http"])
        XCTAssertEqual(MountLinkKind.allCases.map(\.rawValue), ["tcp", "udp", "http"])
    }

    func testTheEpochChoicesMapToTheEnginesFrames() {
        XCTAssertEqual(MountEpochChoice.allCases, [.automatic, .j2000, .meanOfDate])
        XCTAssertNil(MountEpochChoice.automatic.epoch)
        XCTAssertEqual(MountEpochChoice.j2000.epoch, MountEpoch.j2000)
        XCTAssertEqual(MountEpochChoice.meanOfDate.epoch, MountEpoch.meanOfDate)
        XCTAssertEqual(MountEpochChoice.allCases.map(\.title), ["Automatic", "J2000", "Current epoch (JNow)"])
        XCTAssertEqual(MountEpochChoice.allCases.map(\.id), ["automatic", "j2000", "meanOfDate"])
    }

    func testTheArrangementChoicesMapToTheEnginesModes() {
        XCTAssertEqual(MountArrangementChoice.allCases, [.automatic, .altAzimuth, .equatorial])
        XCTAssertNil(MountArrangementChoice.automatic.mode)
        XCTAssertEqual(MountArrangementChoice.altAzimuth.mode, SkyWatcherMountMode.altAzimuth)
        XCTAssertEqual(MountArrangementChoice.equatorial.mode, SkyWatcherMountMode.equatorial)
        XCTAssertEqual(MountArrangementChoice.allCases.map(\.title), ["Automatic", "Alt-azimuth", "Equatorial"])
        XCTAssertEqual(MountArrangementChoice.allCases.map(\.id), ["automatic", "altAzimuth", "equatorial"])
    }

    func testTheChoicesRoundTripThroughTheirStoredNames() throws {
        for choice in MountEpochChoice.allCases {
            let data = try JSONEncoder().encode([choice])
            XCTAssertEqual(try JSONDecoder().decode([MountEpochChoice].self, from: data), [choice])
        }
        for choice in MountArrangementChoice.allCases {
            let data = try JSONEncoder().encode([choice])
            XCTAssertEqual(try JSONDecoder().decode([MountArrangementChoice].self, from: data), [choice])
        }
        XCTAssertThrowsError(try JSONDecoder().decode([MountEpochChoice].self, from: Data("[\"jnow\"]".utf8)))
    }

    // MARK: Discovery texts

    func testTheDiscoveryKindsHaveTheirOwnTitles() {
        XCTAssertEqual(MountDiscoveryKind.alpaca.sectionTitle, "Alpaca Devices")
        XCTAssertEqual(MountDiscoveryKind.skyWatcher.sectionTitle, "Mounts Found")
        XCTAssertEqual(MountDiscoveryKind.alpaca.buttonTitle, "Find Alpaca devices")
        XCTAssertEqual(MountDiscoveryKind.skyWatcher.buttonTitle, "Find mount")
    }

    func testTheSkyWatcherFooterNamesTheMountsOwnAddress() {
        XCTAssertTrue(MountDiscoveryKind.skyWatcher.footer.contains("(192.168.4.1)"), MountDiscoveryKind.skyWatcher.footer)
        XCTAssertFalse(MountDiscoveryKind.alpaca.footer.contains("192.168.4.1"))
        XCTAssertTrue(MountDiscoveryKind.alpaca.footer.hasPrefix("Lodestar asks every address of the Wi-Fi network it is on."))
    }

    func testTheAlpacaSummaryCountsTelescopes() {
        let kind = MountDiscoveryKind.alpaca
        XCTAssertEqual(kind.summary(servers: 1, devices: 1), "Found 1 telescope. Tap one to use it.")
        XCTAssertEqual(kind.summary(servers: 1, devices: 2), "Found 2 telescopes. Tap one to use it.")
        // Telescopes win over servers.
        XCTAssertEqual(kind.summary(servers: 5, devices: 3), "Found 3 telescopes. Tap one to use it.")
    }

    func testTheAlpacaSummaryExplainsServersWithoutTelescopes() {
        let kind = MountDiscoveryKind.alpaca
        XCTAssertEqual(kind.summary(servers: 1, devices: 0), "Found 1 Alpaca server, but no telescope is set up on it.")
        XCTAssertEqual(kind.summary(servers: 2, devices: 0), "Found 2 Alpaca servers, but no telescope is set up on them.")
    }

    func testTheAlpacaSummaryWhenNothingAnsweredTellsWhatToCheck() {
        let text = MountDiscoveryKind.alpaca.summary(servers: 0, devices: 0)
        XCTAssertTrue(text.hasPrefix("No Alpaca server answered."), text)
        XCTAssertTrue(text.contains("Local Network allowed for Lodestar"), text)
        XCTAssertTrue(text.hasSuffix("You can also type the address by hand."), text)
    }

    func testTheSkyWatcherSummaryCountsMounts() {
        let kind = MountDiscoveryKind.skyWatcher
        XCTAssertEqual(kind.summary(servers: 1, devices: 1), "Found 1 mount. Tap one to use it.")
        XCTAssertEqual(kind.summary(servers: 3, devices: 3), "Found 3 mounts. Tap one to use it.")
    }

    func testTheSkyWatcherSummaryIgnoresTheServerCount() {
        let kind = MountDiscoveryKind.skyWatcher
        let text = kind.summary(servers: 4, devices: 0)
        XCTAssertTrue(text.hasPrefix("No Sky-Watcher mount answered."), text)
        XCTAssertTrue(text.hasSuffix("or type its address."), text)
        XCTAssertEqual(kind.summary(servers: 0, devices: 0), text)
    }

    // MARK: Driver options

    func testDriverOptionsStartWithNothingChanged() {
        let options = MountDriverOptions()
        XCTAssertNil(options.epoch)
        XCTAssertFalse(options.reversesEastWest)
        XCTAssertEqual(options.deviceNumber, 0)
        XCTAssertNil(options.demoStart)
        XCTAssertNil(options.location)
        XCTAssertNil(options.arrangement)
        XCTAssertFalse(options.reversesAxis1)
        XCTAssertFalse(options.reversesAxis2)
    }

    // MARK: The registry

    func testThePickerOffersFourKindsInOrderAndTheDemosAreApart() {
        XCTAssertEqual(MountConnectionOption.all.map(\.id), ["lx200", "skywatcher", "nexstar", "alpaca"])
        XCTAssertEqual(MountConnectionOption.demos.map(\.id), ["demo", "demo-skywatcher"])
    }

    func testEveryOptionCanBeFoundByItsId() {
        for option in MountConnectionOption.all + MountConnectionOption.demos {
            XCTAssertEqual(MountConnectionOption.option(id: option.id)?.id, option.id)
        }
        XCTAssertNil(MountConnectionOption.option(id: "unknown"))
        XCTAssertNil(MountConnectionOption.option(id: ""))
        XCTAssertNil(MountConnectionOption.option(id: "LX200"), "ids are case sensitive")
    }

    func testIdsAreUniqueAndTextsAreFilledIn() {
        let options = MountConnectionOption.all + MountConnectionOption.demos
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        for option in options {
            XCTAssertFalse(option.title.isEmpty, option.id)
            XCTAssertFalse(option.summary.isEmpty, option.id)
        }
        for option in MountConnectionOption.all {
            XCTAssertFalse(option.addressNote.isEmpty, option.id)
        }
    }

    func testOnlyTheDemosAreDemos() {
        XCTAssertEqual(MountConnectionOption.all.map(\.isDemo), [false, false, false, false])
        XCTAssertEqual(MountConnectionOption.demos.map(\.isDemo), [true, true])
    }

    func testTheDefaultsOfEachKind() {
        let lx200 = MountConnectionOption.lx200
        XCTAssertEqual(lx200.title, "LX200 / OnStep")
        XCTAssertEqual(lx200.defaultHost, "192.168.0.1")
        XCTAssertEqual(lx200.defaultPort, 9999)
        XCTAssertEqual(lx200.links, [.tcp])
        XCTAssertEqual(lx200.defaultLink, .tcp)
        XCTAssertFalse(lx200.supportsDiscovery)
        XCTAssertEqual(lx200.advancedFields, [.epoch])
        XCTAssertFalse(lx200.usesLodestarAlignment)

        let skyWatcher = MountConnectionOption.skyWatcher
        XCTAssertEqual(skyWatcher.title, SkyWatcherDriver.menuTitle)
        XCTAssertEqual(skyWatcher.defaultHost, "192.168.4.1")
        XCTAssertEqual(skyWatcher.defaultPort, 11880)
        XCTAssertEqual(skyWatcher.links, [.udp])
        XCTAssertEqual(skyWatcher.defaultLink, .udp)
        XCTAssertEqual(skyWatcher.discovery, MountDiscoveryKind.skyWatcher)
        XCTAssertTrue(skyWatcher.supportsDiscovery)
        XCTAssertEqual(skyWatcher.advancedFields, [.arrangement, .reverseAxis1, .reverseAxis2])
        XCTAssertTrue(skyWatcher.usesLodestarAlignment)

        let nexstar = MountConnectionOption.nexstar
        XCTAssertEqual(nexstar.title, "Celestron NexStar / SynScan")
        XCTAssertEqual(nexstar.defaultHost, "192.168.4.1")
        XCTAssertEqual(nexstar.defaultPort, 11880)
        XCTAssertEqual(nexstar.links, [.udp, .tcp])
        XCTAssertEqual(nexstar.defaultLink, .udp, "the first link is the default")
        XCTAssertFalse(nexstar.supportsDiscovery)
        XCTAssertEqual(nexstar.advancedFields, [.epoch, .swapEastWest])
        XCTAssertFalse(nexstar.usesLodestarAlignment)

        let alpaca = MountConnectionOption.alpaca
        XCTAssertEqual(alpaca.title, "ASCOM Alpaca")
        XCTAssertEqual(alpaca.defaultHost, "")
        XCTAssertEqual(alpaca.defaultPort, 11111)
        XCTAssertEqual(alpaca.links, [.http])
        XCTAssertEqual(alpaca.defaultLink, .http)
        XCTAssertEqual(alpaca.discovery, MountDiscoveryKind.alpaca)
        XCTAssertTrue(alpaca.supportsDiscovery)
        XCTAssertEqual(alpaca.advancedFields, [.swapEastWest])
        XCTAssertFalse(alpaca.usesLodestarAlignment)
    }

    func testTheDemosNeedNoAddress() {
        for demo in MountConnectionOption.demos {
            XCTAssertEqual(demo.defaultHost, "", demo.id)
            XCTAssertEqual(demo.defaultPort, 0, demo.id)
            XCTAssertTrue(demo.presets.isEmpty, demo.id)
            XCTAssertTrue(demo.advancedFields.isEmpty, demo.id)
            XCTAssertFalse(demo.supportsDiscovery, demo.id)
            XCTAssertEqual(demo.addressNote, "", demo.id)
        }
        XCTAssertEqual(MountConnectionOption.demo.defaultLink, .tcp)
        XCTAssertFalse(MountConnectionOption.demo.usesLodestarAlignment)
        XCTAssertEqual(MountConnectionOption.demoSkyWatcher.defaultLink, .udp)
        XCTAssertTrue(MountConnectionOption.demoSkyWatcher.usesLodestarAlignment)
    }

    func testThePresetsOfEachKind() {
        XCTAssertEqual(MountConnectionOption.lx200.presets.map(\.title), ["OnStep Wi-Fi", "SkyFi"])
        let skyFi = MountConnectionOption.lx200.presets[1]
        XCTAssertNil(skyFi.host, "a SkyFi gets its address from the router, so the typed host stays")
        XCTAssertEqual(skyFi.port, 4030)
        XCTAssertEqual(skyFi.link, .tcp)
        let onStep = MountConnectionOption.lx200.presets[0]
        XCTAssertEqual(onStep.host, "192.168.0.1")
        XCTAssertEqual(onStep.port, 9999)

        XCTAssertEqual(MountConnectionOption.nexstar.presets.map(\.title), ["SynScan Wi-Fi adapter", "Celestron Wi-Fi"])
        XCTAssertEqual(MountConnectionOption.nexstar.presets.map(\.link), [.udp, .tcp])
        XCTAssertEqual(MountConnectionOption.nexstar.presets.map(\.port), [11880, 2000])
        XCTAssertEqual(MountConnectionOption.skyWatcher.presets.map(\.host), ["192.168.4.1"])
        XCTAssertEqual(MountConnectionOption.alpaca.presets.map(\.port), [11111])
    }

    func testEveryPresetUsesALinkItsOptionOffers() {
        for option in MountConnectionOption.all {
            for preset in option.presets {
                XCTAssertTrue(option.links.contains(preset.link), "\(option.id): \(preset.title)")
                XCTAssertEqual(preset.id, preset.title)
                XCTAssertTrue((1...65_535).contains(preset.port), "\(option.id): \(preset.title)")
            }
            XCTAssertEqual(Set(option.presets.map(\.id)).count, option.presets.count, option.id)
        }
    }

    func testAnOptionIsIdentifiedByItsIdAlone() {
        let twin = MountConnectionOption(id: "lx200", title: "Another title", summary: "", defaultHost: "10.0.0.1", defaultPort: 1,
                                         links: [], presets: [], discovery: nil, advancedFields: [],
                                         usesLodestarAlignment: false, addressNote: "",
                                         makeDriver: { _, _ in throw MountError.notConnected })
        XCTAssertEqual(twin, MountConnectionOption.lx200)
        XCTAssertNotEqual(twin, MountConnectionOption.alpaca)
        XCTAssertEqual(Set([twin, MountConnectionOption.lx200, MountConnectionOption.alpaca]).count, 2)
        XCTAssertEqual(twin.id, "lx200")
    }

    func testAnOptionWithoutLinksFallsBackToTCP() {
        let bare = MountConnectionOption(id: "demo-bare", title: "", summary: "", defaultHost: "", defaultPort: 0, links: [],
                                         presets: [], discovery: nil, advancedFields: [], usesLodestarAlignment: false,
                                         addressNote: "", makeDriver: { _, _ in throw MountError.notConnected })
        XCTAssertEqual(bare.defaultLink, .tcp)
        XCTAssertTrue(bare.isDemo, "a demonstration mount is recognised by the start of its id")
        XCTAssertFalse(bare.supportsDiscovery)
    }

    // MARK: The address field

    func testAPlainHostKeepsTheDefaultPort() {
        let address = MountAddress(text: "192.168.0.1", defaultPort: 9999)
        XCTAssertEqual(address.host, "192.168.0.1")
        XCTAssertEqual(address.port, 9999)
    }

    func testAPortInTheTextWinsOverTheDefault() {
        let address = MountAddress(text: "192.168.0.1:4030", defaultPort: 9999)
        XCTAssertEqual(address.host, "192.168.0.1")
        XCTAssertEqual(address.port, 4030)
    }

    func testBlanksAndNewlinesAroundTheTextAreIgnored() {
        let address = MountAddress(text: "  \t10.0.0.2:2000 \n", defaultPort: 1)
        XCTAssertEqual(address.host, "10.0.0.2")
        XCTAssertEqual(address.port, 2000)
    }

    func testAWebAddressIsReducedToHostAndPort() {
        let full = MountAddress(text: "http://192.168.1.20:11111/", defaultPort: 80)
        XCTAssertEqual(full.host, "192.168.1.20")
        XCTAssertEqual(full.port, 11111)
        let withPath = MountAddress(text: "http://192.168.1.20/api/v1/telescope/0", defaultPort: 11111)
        XCTAssertEqual(withPath.host, "192.168.1.20")
        XCTAssertEqual(withPath.port, 11111)
        let secure = MountAddress(text: "https://mount.local", defaultPort: 443)
        XCTAssertEqual(secure.host, "mount.local")
        XCTAssertEqual(secure.port, 443)
        let other = MountAddress(text: "ftp://x:21/dir", defaultPort: 1)
        XCTAssertEqual(other.host, "x")
        XCTAssertEqual(other.port, 21)
    }

    func testAnythingAfterTheFirstSlashIsDropped() {
        let address = MountAddress(text: "10.0.0.5:2222/?x=1", defaultPort: 1)
        XCTAssertEqual(address.host, "10.0.0.5")
        XCTAssertEqual(address.port, 2222)
        XCTAssertEqual(MountAddress(text: "10.0.0.5/", defaultPort: 7).host, "10.0.0.5")
    }

    func testAnIPv6AddressStaysAsTyped() {
        let address = MountAddress(text: "fe80::1", defaultPort: 11111)
        XCTAssertEqual(address.host, "fe80::1")
        XCTAssertEqual(address.port, 11111)
        let longer = MountAddress(text: "2001:db8::1:2", defaultPort: 5)
        XCTAssertEqual(longer.host, "2001:db8::1:2")
        XCTAssertEqual(longer.port, 5)
    }

    func testTwoColonsAreNeverReadAsAPort() {
        let address = MountAddress(text: "10.0.0.1:80:90", defaultPort: 1)
        XCTAssertEqual(address.host, "10.0.0.1:80:90")
        XCTAssertEqual(address.port, 1)
    }

    func testATextAfterTheColonThatIsNotANumberStaysInTheHost() {
        let address = MountAddress(text: "mount:abc", defaultPort: 4030)
        XCTAssertEqual(address.host, "mount:abc")
        XCTAssertEqual(address.port, 4030)
    }

    func testAColonWithoutAHostIsNotAPort() {
        let address = MountAddress(text: ":8080", defaultPort: 4030)
        XCTAssertEqual(address.host, ":8080")
        XCTAssertEqual(address.port, 4030)
    }

    func testEmptyTextGivesAnEmptyHost() {
        let address = MountAddress(text: "", defaultPort: 11111)
        XCTAssertEqual(address.host, "")
        XCTAssertEqual(address.port, 11111)
        XCTAssertEqual(MountAddress(text: "   ", defaultPort: 3).host, "")
        XCTAssertEqual(MountAddress(text: "http://", defaultPort: 3).host, "")
    }

    func testThePortInTheTextIsNotRangeChecked() {
        // The check comes later, when the link is made.
        XCTAssertEqual(MountAddress(text: "mount:99999", defaultPort: 1).port, 99_999)
        XCTAssertEqual(MountAddress(text: "mount:0", defaultPort: 1).port, 0)
        XCTAssertEqual(MountAddress(text: "mount:-5", defaultPort: 1).port, -5)
    }

    func testAddressesAreEqualWhenHostAndPortAre() {
        XCTAssertEqual(MountAddress(text: "a:1", defaultPort: 2), MountAddress(text: "a", defaultPort: 1))
        XCTAssertNotEqual(MountAddress(text: "a:1", defaultPort: 2), MountAddress(text: "a", defaultPort: 2))
    }

    // MARK: Links made from a form

    func testTheDemosNeedNoLink() {
        for demo in MountConnectionOption.demos {
            var form = MountConnectionForm(option: demo)
            form.host = "not an address at all"
            form.port = -1
            guard case .simulated? = demo.makeChannel(for: form) else {
                XCTFail("\(demo.id) should use the simulated channel")
                continue
            }
        }
    }

    func testLX200MakesATCPStream() throws {
        let channel = try XCTUnwrap(MountConnectionOption.lx200.makeChannel(for: MountConnectionForm(option: .lx200)))
        defer { channel.close() }
        guard case .stream(let transport) = channel else { return XCTFail("expected a stream") }
        XCTAssertEqual(transport.kind, .tcp)
    }

    func testSkyWatcherMakesAUDPStream() throws {
        let channel = try XCTUnwrap(MountConnectionOption.skyWatcher.makeChannel(for: MountConnectionForm(option: .skyWatcher)))
        defer { channel.close() }
        guard case .stream(let transport) = channel else { return XCTFail("expected a stream") }
        XCTAssertEqual(transport.kind, .udp)
    }

    func testTheLinkOfTheFormDecidesTheKindOfStream() throws {
        var form = MountConnectionForm(option: .nexstar)
        XCTAssertEqual(form.link, .udp)
        let udp = try XCTUnwrap(MountConnectionOption.nexstar.makeChannel(for: form))
        defer { udp.close() }
        guard case .stream(let udpTransport) = udp else { return XCTFail("expected a stream") }
        XCTAssertEqual(udpTransport.kind, .udp)

        form.link = .tcp
        let tcp = try XCTUnwrap(MountConnectionOption.nexstar.makeChannel(for: form))
        defer { tcp.close() }
        guard case .stream(let tcpTransport) = tcp else { return XCTFail("expected a stream") }
        XCTAssertEqual(tcpTransport.kind, .tcp)
    }

    func testAlpacaMakesAnHTTPClientForTheTypedAddress() throws {
        var form = MountConnectionForm(option: .alpaca)
        form.host = "192.168.1.20"
        let channel = try XCTUnwrap(MountConnectionOption.alpaca.makeChannel(for: form))
        defer { channel.close() }
        guard case .http(let transport) = channel else { return XCTFail("expected an HTTP client") }
        XCTAssertEqual(transport.endpoint, AlpacaEndpoint(host: "192.168.1.20", port: 11111))
    }

    func testAPortAndSchemeTypedIntoTheHostFieldAreUsed() throws {
        var form = MountConnectionForm(option: .alpaca)
        form.host = "http://10.0.0.5:2222/"
        let channel = try XCTUnwrap(MountConnectionOption.alpaca.makeChannel(for: form))
        defer { channel.close() }
        guard case .http(let transport) = channel else { return XCTFail("expected an HTTP client") }
        XCTAssertEqual(transport.endpoint, AlpacaEndpoint(host: "10.0.0.5", port: 2222))
    }

    func testAnIPv6HostGoesToTheHTTPClientWhole() throws {
        var form = MountConnectionForm(option: .alpaca)
        form.host = "fe80::1"
        let channel = try XCTUnwrap(MountConnectionOption.alpaca.makeChannel(for: form))
        defer { channel.close() }
        guard case .http(let transport) = channel else { return XCTFail("expected an HTTP client") }
        XCTAssertEqual(transport.endpoint, AlpacaEndpoint(host: "fe80::1", port: 11111))
    }

    func testAlpacaWithoutAnAddressMakesNoLink() {
        // The default host of Alpaca is empty: the person has to type one.
        XCTAssertNil(MountConnectionOption.alpaca.makeChannel(for: MountConnectionForm(option: .alpaca)))
    }

    func testAnAddressTheEngineRefusesMakesNoHTTPClient() {
        var form = MountConnectionForm(option: .alpaca)
        form.host = "bad host"
        XCTAssertNil(MountConnectionOption.alpaca.makeChannel(for: form))
        form.host = "user@host"
        XCTAssertNil(MountConnectionOption.alpaca.makeChannel(for: form))
    }

    func testPortsOutsideTheValidRangeMakeNoLink() {
        for option in [MountConnectionOption.lx200, .skyWatcher, .nexstar] {
            var form = MountConnectionForm(option: option)
            form.host = "10.0.0.1"
            for port in [0, -1, 65_536] {
                form.port = port
                XCTAssertNil(option.makeChannel(for: form), "\(option.id) port \(port)")
            }
            form.port = 1_000
            form.host = "10.0.0.1:70000"
            XCTAssertNil(option.makeChannel(for: form), "\(option.id) port in the text")
        }
        var alpaca = MountConnectionForm(option: .alpaca)
        alpaca.host = "10.0.0.1"
        alpaca.port = 0
        XCTAssertNil(MountConnectionOption.alpaca.makeChannel(for: alpaca))
        alpaca.port = 65_536
        XCTAssertNil(MountConnectionOption.alpaca.makeChannel(for: alpaca))
    }

    func testAnEmptyHostMakesNoStream() {
        for option in [MountConnectionOption.lx200, .skyWatcher, .nexstar] {
            var form = MountConnectionForm(option: option)
            form.host = "  "
            XCTAssertNil(option.makeChannel(for: form), option.id)
        }
    }

    // MARK: The driver factories

    func testTheLX200FactoryAsksForJNowUnlessToldOtherwise() throws {
        let bundle = try MountConnectionOption.lx200.makeDriver(try streamChannel(kind: .tcp), MountDriverOptions())
        let driver = try XCTUnwrap(bundle.driver as? LX200Driver)
        XCTAssertEqual(driver.kind, .lx200)
        XCTAssertEqual(driver.configuration.epoch, .meanOfDate)
        XCTAssertEqual(driver.epoch, .meanOfDate)
        XCTAssertTrue(bundle.clock is SystemMountClock)
        XCTAssertNil(bundle.prepare)
        XCTAssertNil(bundle.detail)
        XCTAssertNil(bundle.centreSimulated)

        var options = MountDriverOptions()
        options.epoch = .j2000
        let chosen = try MountConnectionOption.lx200.makeDriver(try streamChannel(kind: .tcp), options)
        XCTAssertEqual((chosen.driver as? LX200Driver)?.epoch, MountEpoch.j2000)
    }

    func testTheLX200FactoryNeedsAStream() {
        throwsInvalidInput("this mount needs a TCP connection") {
            _ = try MountConnectionOption.lx200.makeDriver(.simulated, MountDriverOptions())
        }
        throwsInvalidInput("this mount needs a TCP connection") {
            _ = try MountConnectionOption.lx200.makeDriver(httpChannel(), MountDriverOptions())
        }
    }

    func testTheNexStarFactoryPassesEpochAndDirectionOn() throws {
        let plain = try MountConnectionOption.nexstar.makeDriver(try streamChannel(kind: .udp), MountDriverOptions())
        let plainDriver = try XCTUnwrap(plain.driver as? NexStarDriver)
        XCTAssertEqual(plainDriver.kind, .nexstar)
        XCTAssertNil(plainDriver.configuration.epoch, "automatic: the driver decides when it has met the controller")
        XCTAssertFalse(plainDriver.configuration.invertsEastWest)
        XCTAssertEqual(plainDriver.epoch, .meanOfDate, "before the handshake the driver assumes JNow")
        XCTAssertNil(plain.detail)

        var options = MountDriverOptions()
        options.epoch = .j2000
        options.reversesEastWest = true
        let tuned = try MountConnectionOption.nexstar.makeDriver(try streamChannel(kind: .tcp), options)
        let tunedDriver = try XCTUnwrap(tuned.driver as? NexStarDriver)
        XCTAssertEqual(tunedDriver.configuration.epoch, MountEpoch.j2000)
        XCTAssertTrue(tunedDriver.configuration.invertsEastWest)
        XCTAssertEqual(tunedDriver.epoch, .j2000)
    }

    func testTheNexStarFactoryNeedsAStream() {
        throwsInvalidInput("this mount needs a TCP or UDP connection") {
            _ = try MountConnectionOption.nexstar.makeDriver(.simulated, MountDriverOptions())
        }
        throwsInvalidInput("this mount needs a TCP or UDP connection") {
            _ = try MountConnectionOption.nexstar.makeDriver(httpChannel(), MountDriverOptions())
        }
    }

    func testTheAlpacaFactoryPassesTheDeviceAndTheDirectionOn() throws {
        let channel = httpChannel()
        defer { channel.close() }
        let plain = try MountConnectionOption.alpaca.makeDriver(channel, MountDriverOptions())
        let plainDriver = try XCTUnwrap(plain.driver as? AlpacaDriver)
        XCTAssertEqual(plainDriver.kind, .alpaca)
        XCTAssertEqual(plainDriver.configuration.deviceNumber, 0)
        XCTAssertTrue(plainDriver.configuration.primaryPositiveIsEast)
        XCTAssertTrue(plain.clock is SystemMountClock)
        XCTAssertNil(plain.prepare)
        XCTAssertNil(plain.detail)

        var options = MountDriverOptions()
        options.deviceNumber = 3
        options.reversesEastWest = true
        let tuned = try MountConnectionOption.alpaca.makeDriver(channel, options)
        let tunedDriver = try XCTUnwrap(tuned.driver as? AlpacaDriver)
        XCTAssertEqual(tunedDriver.configuration.deviceNumber, 3)
        XCTAssertFalse(tunedDriver.configuration.primaryPositiveIsEast)
    }

    func testTheAlpacaFactoryNeedsAnHTTPClient() throws {
        throwsInvalidInput("this mount needs an HTTP connection") {
            _ = try MountConnectionOption.alpaca.makeDriver(.simulated, MountDriverOptions())
        }
        throwsInvalidInput("this mount needs an HTTP connection") {
            _ = try MountConnectionOption.alpaca.makeDriver(try streamChannel(kind: .tcp), MountDriverOptions())
        }
    }

    func testTheSkyWatcherFactoryNeedsTheLocationOfThePhone() throws {
        let channel = try streamChannel(kind: .udp)
        throwsInvalidInput("your location is not known yet") {
            _ = try MountConnectionOption.skyWatcher.makeDriver(channel, MountDriverOptions())
        }
    }

    func testTheSkyWatcherFactoryNeedsAStreamBeforeItLooksAtTheLocation() {
        var options = MountDriverOptions()
        options.location = location
        throwsInvalidInput("this mount needs a UDP connection") {
            _ = try MountConnectionOption.skyWatcher.makeDriver(.simulated, options)
        }
        throwsInvalidInput("this mount needs a UDP connection") {
            _ = try MountConnectionOption.skyWatcher.makeDriver(httpChannel(), MountDriverOptions())
        }
    }

    func testTheSkyWatcherFactoryPassesTheSetUpOn() throws {
        var options = MountDriverOptions()
        options.location = location
        let plain = try MountConnectionOption.skyWatcher.makeDriver(try streamChannel(kind: .udp), options)
        let plainDriver = try XCTUnwrap(plain.driver as? SkyWatcherDriver)
        XCTAssertEqual(plainDriver.kind, .skywatcher)
        XCTAssertEqual(plainDriver.configuration.location, location)
        XCTAssertNil(plainDriver.configuration.mode, "automatic: the mount model decides")
        XCTAssertFalse(plainDriver.configuration.invertsAxis1)
        XCTAssertFalse(plainDriver.configuration.invertsAxis2)
        XCTAssertNotNil(plain.detail, "the Sky-Watcher driver reports its alignment")
        XCTAssertNil(plain.prepare)
        XCTAssertNil(plain.centreSimulated)
        XCTAssertTrue(plain.clock is SystemMountClock)

        options.arrangement = .equatorial
        options.reversesAxis1 = true
        options.reversesAxis2 = true
        let tuned = try MountConnectionOption.skyWatcher.makeDriver(try streamChannel(kind: .udp), options)
        let tunedDriver = try XCTUnwrap(tuned.driver as? SkyWatcherDriver)
        XCTAssertEqual(tunedDriver.configuration.mode, SkyWatcherMountMode.equatorial)
        XCTAssertTrue(tunedDriver.configuration.invertsAxis1)
        XCTAssertTrue(tunedDriver.configuration.invertsAxis2)
    }

    func testTheDemoMountLivesInMemoryAndStartsWhereToldTo() throws {
        let start = EquatorialCoordinate(rightAscension: 90, declination: -20)
        var options = MountDriverOptions()
        options.demoStart = start
        let bundle = try MountConnectionOption.demo.makeDriver(.simulated, options)
        XCTAssertTrue(bundle.clock is ManualMountClock)
        XCTAssertNotNil(bundle.prepare, "the demonstration mount's clock is brought to real time before every job")
        XCTAssertNil(bundle.detail)
        XCTAssertNil(bundle.centreSimulated)
        XCTAssertEqual(bundle.driver.kind, .lx200)
        _ = try bundle.driver.connect()
        let position = try bundle.driver.readPosition()
        XCTAssertEqual(position.angularSeparation(to: start), 0, accuracy: 0.05)
    }

    func testTheDemoMountStartsHighInTheNorthByDefault() throws {
        let bundle = try MountConnectionOption.demo.makeDriver(.simulated, MountDriverOptions())
        _ = try bundle.driver.connect()
        let position = try bundle.driver.readPosition()
        XCTAssertEqual(position.angularSeparation(to: EquatorialCoordinate(rightAscension: 0, declination: 45)), 0, accuracy: 0.05)
    }

    func testTheDemoMountIgnoresTheChannelItIsGiven() throws {
        let bundle = try MountConnectionOption.demo.makeDriver(try streamChannel(kind: .udp), MountDriverOptions())
        XCTAssertEqual(bundle.driver.kind, .lx200)
    }

    func testThePreparationMovesTheDemoClockForwardWithRealTime() throws {
        let bundle = try MountConnectionOption.demo.makeDriver(.simulated, MountDriverOptions())
        let clock = try XCTUnwrap(bundle.clock as? ManualMountClock)
        let prepare = try XCTUnwrap(bundle.prepare)
        let before = clock.secondsSince1970
        // Real time passes between the calls; a few calls are enough for the clock to show it, and it never goes back.
        let deadline = Date(timeIntervalSinceNow: 5)
        var last = before
        while clock.secondsSince1970 == before && Date() < deadline {
            prepare()
            XCTAssertGreaterThanOrEqual(clock.secondsSince1970, last)
            last = clock.secondsSince1970
        }
        XCTAssertGreaterThan(clock.secondsSince1970, before)
        XCTAssertLessThan(clock.secondsSince1970 - before, 5.5, "the clock follows real time, it does not jump")
    }

    func testTheSimulatedSkyWatcherUsesTheLocationAndArrangementItIsGiven() throws {
        var options = MountDriverOptions()
        options.location = location
        options.arrangement = .equatorial
        let bundle = try MountConnectionOption.demoSkyWatcher.makeDriver(.simulated, options)
        let driver = try XCTUnwrap(bundle.driver as? SkyWatcherDriver)
        XCTAssertEqual(driver.kind, .skywatcher)
        XCTAssertEqual(driver.configuration.location, location)
        XCTAssertEqual(driver.configuration.mode, SkyWatcherMountMode.equatorial)
        XCTAssertTrue(bundle.clock is ManualMountClock)
        XCTAssertNotNil(bundle.prepare)
        XCTAssertNotNil(bundle.detail)
        XCTAssertNotNil(bundle.centreSimulated)
    }

    func testTheSimulatedSkyWatcherDefaultsToColoradoAndAnAltAzimuthSetUp() throws {
        let bundle = try MountConnectionOption.demoSkyWatcher.makeDriver(.simulated, MountDriverOptions())
        let driver = try XCTUnwrap(bundle.driver as? SkyWatcherDriver)
        XCTAssertEqual(driver.configuration.location, GeographicLocation(latitude: 40, longitude: -105, elevation: 0))
        XCTAssertEqual(driver.configuration.mode, SkyWatcherMountMode.altAzimuth)
        _ = try driver.connect()
        XCTAssertEqual(driver.mountMode, SkyWatcherMountMode.altAzimuth)
        XCTAssertEqual(driver.version, SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5))
    }

    func testTheSimulatedEquatorialSkyWatcherReportsAnEquatorialMount() throws {
        var options = MountDriverOptions()
        options.arrangement = .equatorial
        let bundle = try MountConnectionOption.demoSkyWatcher.makeDriver(.simulated, options)
        let driver = try XCTUnwrap(bundle.driver as? SkyWatcherDriver)
        _ = try driver.connect()
        XCTAssertEqual(driver.mountMode, SkyWatcherMountMode.equatorial)
        XCTAssertEqual(driver.version, SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C))
    }

    func testTheSimulatedSkyWatcherCanBeCentredOnAStarAndAligned() throws {
        // A star 80 degrees from the celestial pole stands between 30 and 50 degrees high at 40 degrees north at any hour of
        // the year, so the test does not depend on the date.
        let star = EquatorialCoordinate(rightAscensionHours: 5.0, declination: 80.0)
        var options = MountDriverOptions()
        options.location = GeographicLocation(latitude: 40, longitude: -105, elevation: 0)
        let bundle = try MountConnectionOption.demoSkyWatcher.makeDriver(.simulated, options)
        let controller = MountController(driver: bundle.driver, observer: Observer(location: try XCTUnwrap(options.location)),
                                         clock: bundle.clock)
        try controller.connect()
        bundle.prepare?()
        let centre = try XCTUnwrap(bundle.centreSimulated)
        centre(star)
        let result = try controller.sync(star)
        XCTAssertLessThan(result.offsetDegrees, 20, "the simulated mount starts a few degrees off its home position")
        let detail = try XCTUnwrap(bundle.detail?())
        XCTAssertEqual(detail.alignment?.stars.count, 1)
        XCTAssertEqual(detail.arrangement, SkyWatcherMountMode.altAzimuth)
    }
}

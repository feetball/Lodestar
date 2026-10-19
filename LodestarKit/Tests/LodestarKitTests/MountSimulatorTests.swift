import XCTest
@testable import LodestarKit

/// The simulators are test equipment, so they get their own checks: replies are exactly the documented ones.
final class MountSimulatorTests: XCTestCase {
    private typealias Support = MountTestSupport

    private func makeClock() -> ManualMountClock { ManualMountClock(start: Support.start) }

    private func mount(_ clock: ManualMountClock, rate: Double = 4.0, delay: Double = 0.4,
                       at: EquatorialCoordinate = EquatorialCoordinate(rightAscension: 150.0, declination: 10.0)) -> MountSimulatorModel {
        MountSimulatorModel(clock: clock, start: at, slewRateDegreesPerSecond: rate, startDelaySeconds: delay)
    }

    private func drain(_ transport: MountTransport) throws -> String {
        var text = ""
        while true {
            do {
                text += MountText.latin1(try transport.receive(maxCount: 256, timeoutSeconds: 0.0))
            } catch let error as MountError where error.isTimeout {
                return text
            }
        }
    }

    private func ask(_ transport: MountTransport, _ command: String) throws -> String {
        try transport.discardPendingInput()
        try transport.send(MountText.ascii(command))
        return try drain(transport)
    }

    private func askBytes(_ transport: MountTransport, _ command: [Int]) throws -> String {
        try transport.discardPendingInput()
        try transport.send(command.map { UInt8($0) })
        return try drain(transport)
    }

    // MARK: The moving mount

    func testASlewMovesAtTheConfiguredRateAfterTheStartDelay() {
        let clock = makeClock()
        let mount = mount(clock, at: EquatorialCoordinate(rightAscension: 150.0, declination: 0.0))
        mount.beginSlew(to: EquatorialCoordinate(rightAscension: 150.0, declination: 40.0))
        XCTAssertTrue(mount.isSlewing)
        clock.advance(seconds: 0.3)
        XCTAssertEqual(mount.position.declination, 0.0, accuracy: 0.0)
        XCTAssertTrue(mount.isSlewing)
        clock.advance(seconds: 0.1 + 5.0)
        XCTAssertEqual(mount.position.declination, 20.0, accuracy: 1e-6)
        clock.advance(seconds: 4.9)
        XCTAssertTrue(mount.isSlewing)
        XCTAssertEqual(mount.position.declination, 39.6, accuracy: 1e-6)
        clock.advance(seconds: 0.2)
        XCTAssertFalse(mount.isSlewing)
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 150.0, declination: 40.0))
        XCTAssertEqual(mount.slewsStarted, 1)
    }

    func testRightAscensionTakesTheShortWayRound() {
        let clock = makeClock()
        let mount = mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 350.0, declination: 0.0))
        mount.beginSlew(to: EquatorialCoordinate(rightAscension: 10.0, declination: 0.0))
        clock.advance(seconds: 2.5)
        XCTAssertEqual(mount.position.rightAscension, 0.0, accuracy: 1e-9)
        clock.advance(seconds: 2.5)
        XCTAssertEqual(mount.position.rightAscension, 10.0, accuracy: 1e-9)
        XCTAssertFalse(mount.isSlewing)
        let backwards = self.mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 10.0, declination: 0.0))
        backwards.beginSlew(to: EquatorialCoordinate(rightAscension: 350.0, declination: 0.0))
        clock.advance(seconds: 1.0)
        XCTAssertEqual(backwards.position.rightAscension, 6.0, accuracy: 1e-9)
    }

    func testBothAxesMoveTogetherAndFinishTogetherWhenEqual() {
        let clock = makeClock()
        let mount = mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 100.0, declination: 0.0))
        mount.beginSlew(to: EquatorialCoordinate(rightAscension: 120.0, declination: 8.0))
        clock.advance(seconds: 2.0)
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 108.0, declination: 8.0))
        XCTAssertTrue(mount.isSlewing)
        clock.advance(seconds: 3.0)
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 120.0, declination: 8.0))
        XCTAssertFalse(mount.isSlewing)
    }

    func testStopSyncAndNudge() {
        let clock = makeClock()
        let mount = mount(clock, delay: 0.0)
        mount.beginSlew(to: EquatorialCoordinate(rightAscension: 200.0, declination: 50.0))
        clock.advance(seconds: 2.0)
        mount.stop()
        let stopped = mount.position
        XCTAssertFalse(mount.isSlewing)
        clock.advance(seconds: 10.0)
        XCTAssertEqual(mount.position, stopped)
        XCTAssertEqual(mount.stopsReceived, 1)
        mount.sync(to: EquatorialCoordinate(rightAscension: 12.0, declination: -3.0))
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 12.0, declination: -3.0))
        XCTAssertEqual(mount.syncsPerformed, 1)
        mount.setNudgeRates(rightAscensionDegreesPerSecond: 0.5, declinationDegreesPerSecond: -0.25)
        XCTAssertTrue(mount.isNudging)
        XCTAssertFalse(mount.isSlewing)
        clock.advance(seconds: 4.0)
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 14.0, declination: -4.0))
        mount.stop()
        XCTAssertFalse(mount.isNudging)
        mount.displace(rightAscensionDegrees: -20.0, declinationDegrees: 1.0)
        XCTAssertEqual(mount.position, EquatorialCoordinate(rightAscension: 354.0, declination: -3.0))
    }

    func testNudgesStopAtThePole() {
        let clock = makeClock()
        let mount = mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 0.0, declination: 89.0))
        mount.setNudgeRates(rightAscensionDegreesPerSecond: 0.0, declinationDegreesPerSecond: 1.0)
        clock.advance(seconds: 10.0)
        XCTAssertEqual(mount.position.declination, 90.0, accuracy: 0.0)
    }

    // MARK: Stream behaviour

    func testTimeoutsCostTheirFullDurationAndRepliesCostTheLatency() throws {
        let clock = makeClock()
        let simulator = LX200Simulator(clock: clock, mount: mount(clock), latencySeconds: 0.25)
        let before = clock.secondsSince1970
        try simulator.send(MountText.ascii(":GVP#"))
        XCTAssertEqual(clock.secondsSince1970 - before, 0.25, accuracy: 1e-9)
        XCTAssertEqual(MountText.latin1(try simulator.receive(maxCount: 100, timeoutSeconds: 1.0)), "On-Step#")
        let afterReply = clock.secondsSince1970
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try simulator.receive(maxCount: 100, timeoutSeconds: 1.5) }).isTimeout)
        XCTAssertEqual(clock.secondsSince1970 - afterReply, 1.5, accuracy: 1e-9)
    }

    func testRepliesCanArriveInPiecesAndOldInputIsDiscarded() throws {
        let clock = makeClock()
        let simulator = LX200Simulator(clock: clock, mount: mount(clock), chunkSize: 3)
        try simulator.send(MountText.ascii(":GVP#"))
        XCTAssertEqual(MountText.latin1(try simulator.receive(maxCount: 100, timeoutSeconds: 1.0)), "On-")
        XCTAssertEqual(MountText.latin1(try simulator.receive(maxCount: 2, timeoutSeconds: 1.0)), "St")
        XCTAssertEqual(MountText.latin1(try simulator.receive(maxCount: 100, timeoutSeconds: 1.0)), "ep#")
        try simulator.send(MountText.ascii(":GVP#"))
        try simulator.discardPendingInput()
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try simulator.receive(maxCount: 100, timeoutSeconds: 0.1) }).isTimeout)
    }

    func testInjectedFaultsHitOnlyMatchingCommandsOnce() throws {
        let clock = makeClock()
        let simulator = LX200Simulator(clock: clock, mount: mount(clock))
        simulator.inject("GR", .silence)
        simulator.inject("GD", .replace(text: "??#"))
        simulator.inject("GVP", .truncate(keep: 2))
        XCTAssertEqual(try ask(simulator, ":GR#"), "")
        XCTAssertTrue(try ask(simulator, ":GR#").hasSuffix("#"))
        XCTAssertEqual(try ask(simulator, ":GD#"), "??#")
        XCTAssertTrue(try ask(simulator, ":GD#").hasPrefix("+10*"))
        XCTAssertEqual(try ask(simulator, ":GVP#"), "On")
        XCTAssertEqual(try ask(simulator, ":GVP#"), "On-Step#")
        simulator.inject("GR", .disconnect)
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try ask(simulator, ":GR#") }).isTransport)
        XCTAssertTrue(try XCTUnwrap(mountError { try simulator.send(MountText.ascii(":GR#")) }).isTransport)
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try simulator.receive(maxCount: 1, timeoutSeconds: 1.0) }).isTransport)
        XCTAssertEqual(simulator.commandLog, ["GR", "GR", "GD", "GD", "GVP", "GVP", "GR"])
    }

    // MARK: LX200 replies

    func testOnStepRepliesFollowTheReference() throws {
        let clock = makeClock()
        let model = mount(clock, at: EquatorialCoordinate(rightAscension: 187.5, declination: -0.5))
        let simulator = LX200Simulator(clock: clock, mount: model, dialect: .onstep)
        XCTAssertEqual(try ask(simulator, ":GR#"), "12:30:00#")
        XCTAssertEqual(try ask(simulator, ":GD#"), "-00*30:00#")
        XCTAssertEqual(try ask(simulator, ":GVP#"), "On-Step#")
        XCTAssertEqual(try ask(simulator, ":GVN#"), "4.24#")
        XCTAssertEqual(try ask(simulator, ":D#"), "#")
        XCTAssertEqual(try ask(simulator, ":GU#"), "NpEo000#")
        XCTAssertEqual(try ask(simulator, ":GW#"), "GT2#")
        XCTAssertEqual(try ask(simulator, ":Sr13:00:00#"), "1")
        XCTAssertEqual(try ask(simulator, ":Sd+10*00:00#"), "1")
        XCTAssertEqual(try ask(simulator, ":Sr13:00.0#"), "1")
        XCTAssertEqual(try ask(simulator, ":Sr25:00:00#"), "0")
        XCTAssertEqual(try ask(simulator, ":Sd+95*00#"), "0")
        XCTAssertEqual(try ask(simulator, ":Sr13:00:00#"), "1")
        XCTAssertEqual(try ask(simulator, ":MS#"), "0")
        XCTAssertEqual(try ask(simulator, ":D#"), "\u{7F}#")
        XCTAssertEqual(try ask(simulator, ":GU#"), "pEo000#")
        XCTAssertEqual(try ask(simulator, ":MS#"), "5")
        XCTAssertEqual(try ask(simulator, ":CM#"), "#")
        XCTAssertEqual(try ask(simulator, ":Q#"), "")
        XCTAssertEqual(try ask(simulator, ":D#"), "#")
        XCTAssertEqual(try ask(simulator, ":CM#"), "N/A#")
        XCTAssertEqual(try ask(simulator, ":Td#"), "1")
        XCTAssertEqual(try ask(simulator, ":GU#"), "nNpEo000#")
        XCTAssertEqual(try ask(simulator, ":Bogus#"), "")
    }

    func testOnStepRefusalDigits() throws {
        let clock = makeClock()
        let simulator = LX200Simulator(clock: clock, mount: mount(clock), dialect: .onstep)
        XCTAssertEqual(try ask(simulator, ":MS#"), "9")
        _ = try ask(simulator, ":Sr13:00:00#")
        _ = try ask(simulator, ":Sd+10*00:00#")
        simulator.refusalCode = "1"
        XCTAssertEqual(try ask(simulator, ":MS#"), "1")
        XCTAssertEqual(try ask(simulator, ":CM#"), "E1#")
        simulator.refusalCode = nil
        simulator.mount.isParked = true
        XCTAssertEqual(try ask(simulator, ":MS#"), "4")
        XCTAssertEqual(try ask(simulator, ":Te#"), "0")
    }

    func testMeadeRepliesFollowTheReference() throws {
        let clock = makeClock()
        let model = mount(clock, at: EquatorialCoordinate(rightAscension: 187.5, declination: 45.5))
        let simulator = LX200Simulator(clock: clock, mount: model, dialect: .meade, highPrecision: false)
        XCTAssertEqual(try ask(simulator, ":GR#"), "12:30.0#")
        XCTAssertEqual(try ask(simulator, ":GD#"), "+45*30#")
        XCTAssertEqual(try ask(simulator, ":GVP#"), "LX200 Classic#")
        // :U# toggles the format and has no reply.
        XCTAssertEqual(try ask(simulator, ":U#"), "")
        XCTAssertEqual(try ask(simulator, ":GR#"), "12:30:00#")
        XCTAssertEqual(try ask(simulator, ":GD#"), "+45*30:00#")
        // A Meade mount only takes targets in the current format.
        XCTAssertEqual(try ask(simulator, ":Sr12:30.0#"), "0")
        XCTAssertEqual(try ask(simulator, ":Sr12:30:00#"), "1")
        XCTAssertEqual(try ask(simulator, ":Sd+45*30#"), "0")
        XCTAssertEqual(try ask(simulator, ":Sd+45*30:00#"), "1")
        simulator.refusalCode = "1"
        XCTAssertEqual(try ask(simulator, ":MS#"), "1Object below horizon#")
        simulator.refusalCode = "2"
        XCTAssertEqual(try ask(simulator, ":MS#"), "2Object below higher#")
        simulator.refusalCode = nil
        XCTAssertEqual(try ask(simulator, ":MS#"), "0")
        XCTAssertEqual(try ask(simulator, ":CM#"), "Coordinates matched        #")
        // Unknown commands (here an OnStep-only one) get no answer.
        XCTAssertEqual(try ask(simulator, ":GU#"), "")
        XCTAssertEqual(try ask(simulator, ":Te#"), "")
        XCTAssertEqual(try ask(simulator, ":SC10/18/26#"), "1Updating Planetary Data#\(String(repeating: " ", count: 30))#")
    }

    func testBusyControllersAnswerWithNAK() throws {
        let clock = makeClock()
        let simulator = LX200Simulator(clock: clock, mount: mount(clock))
        simulator.busyReplies = 2
        XCTAssertEqual(try ask(simulator, ":GR#"), "\u{15}")
        XCTAssertEqual(try ask(simulator, ":GD#"), "\u{15}")
        XCTAssertTrue(try ask(simulator, ":GR#").hasSuffix("#"))
    }

    func testLX200MovesAndRates() throws {
        let clock = makeClock()
        let model = mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 100.0, declination: 0.0))
        let simulator = LX200Simulator(clock: clock, mount: model)
        _ = try ask(simulator, ":RC#")
        _ = try ask(simulator, ":Mn#")
        _ = try ask(simulator, ":Me#")
        clock.advance(seconds: 10.0)
        let rate = MountNudgeRate.center.degreesPerSecond
        XCTAssertEqual(simulator.mount.position.declination, 10 * rate, accuracy: 1e-6)
        XCTAssertEqual(simulator.mount.position.rightAscension, 100.0 + 10 * rate, accuracy: 1e-6)
        _ = try ask(simulator, ":Qn#")
        clock.advance(seconds: 10.0)
        XCTAssertEqual(simulator.mount.position.declination, 10 * rate, accuracy: 1e-6)
        _ = try ask(simulator, ":Qe#")
        let settled = simulator.mount.position
        clock.advance(seconds: 10.0)
        XCTAssertEqual(simulator.mount.position, settled)
        _ = try ask(simulator, ":Ms#")
        _ = try ask(simulator, ":Mw#")
        XCTAssertTrue(simulator.mount.isNudging)
        _ = try ask(simulator, ":Q#")
        XCTAssertFalse(simulator.mount.isNudging)
    }

    // MARK: NexStar replies

    func testHandControlRepliesFollowTheReference() throws {
        let clock = makeClock()
        let model = mount(clock, at: EquatorialCoordinate(rightAscension: Double(0x34AB05) / 16_777_216.0 * 360.0,
                                                          declination: Double(0x12CE05) / 16_777_216.0 * 360.0))
        let celestron = NexStarSimulator(clock: clock, mount: model, flavor: .celestron, major: 5, minor: 28, patch: 0, model: 12)
        let v = Int(UInt8(ascii: "V")), m = Int(UInt8(ascii: "m")), j = Int(UInt8(ascii: "J")), l = Int(UInt8(ascii: "L"))
        let e = Int(UInt8(ascii: "e")), upperE = Int(UInt8(ascii: "E")), t = Int(UInt8(ascii: "t")), upperT = Int(UInt8(ascii: "T"))
        let k = Int(UInt8(ascii: "K")), a = Int(UInt8(ascii: "A"))
        XCTAssertEqual(try askBytes(celestron, [v]), "\u{05}\u{1C}#")
        XCTAssertEqual(try askBytes(celestron, [m]), "\u{0C}#")
        XCTAssertEqual(try askBytes(celestron, [j]), "\u{01}#")
        XCTAssertEqual(try askBytes(celestron, [l]), "0#")
        XCTAssertEqual(try askBytes(celestron, [e]), "34AB0500,12CE0500#")
        XCTAssertEqual(try askBytes(celestron, [upperE]), "34AB,12CE#")
        XCTAssertEqual(try askBytes(celestron, [t]), "\u{01}#")
        XCTAssertEqual(try askBytes(celestron, [upperT, 0]), "#")
        XCTAssertEqual(try askBytes(celestron, [t]), "\u{00}#")
        XCTAssertEqual(try askBytes(celestron, [k, a]), "A#")
        let synScan = NexStarSimulator(clock: clock, mount: model, flavor: .synscan, major: 4, minor: 38, patch: 6)
        XCTAssertEqual(try askBytes(synScan, [v]), "042606#")
        XCTAssertEqual(try askBytes(synScan, [Int(UInt8(ascii: "x"))]), "")
    }

    func testHandControlGotoSyncAndSlews() throws {
        let clock = makeClock()
        let model = mount(clock, delay: 0.0, at: EquatorialCoordinate(rightAscension: 100.0, declination: 0.0))
        let simulator = NexStarSimulator(clock: clock, mount: model, flavor: .synscan)
        let p = Int(UInt8(ascii: "P")), l = Int(UInt8(ascii: "L")), upperM = Int(UInt8(ascii: "M"))
        // GOTO a reachable target.
        let target = EquatorialCoordinate(rightAscension: Double(0x1D58C6) / 16_777_216.0 * 360.0,
                                          declination: Double(0x1D58C6) / 16_777_216.0 * 360.0 / 2)
        XCTAssertEqual(try ask(simulator, "r" + NexStarCodec.encodeAngle(target.rightAscension, precise: true) + ","
            + NexStarCodec.encodeAngle(target.declination, precise: true)), "#")
        XCTAssertEqual(try askBytes(simulator, [l]), "1#")
        XCTAssertEqual(try askBytes(simulator, [upperM]), "#")
        XCTAssertEqual(try askBytes(simulator, [l]), "0#")
        XCTAssertEqual(try ask(simulator, "s34AB0500,12CE0500"), "#")
        XCTAssertEqual(model.position.rightAscension, Double(0x34AB05) / 16_777_216.0 * 360.0, accuracy: 1e-9)
        XCTAssertEqual(model.syncsPerformed, 1)
        // Variable rate slew, 150 arcseconds per second positive on the declination axis, then stop with a fixed rate of 0.
        XCTAssertEqual(try askBytes(simulator, [p, 3, 17, 6, 2, 88, 0, 0]), "#")
        clock.advance(seconds: 10.0)
        XCTAssertEqual(model.position.declination - Double(0x12CE05) / 16_777_216.0 * 360.0, 10.05 * 150.0 / 3600, accuracy: 1e-6)
        XCTAssertEqual(try askBytes(simulator, [p, 2, 17, 36, 0, 0, 0, 0]), "#")
        XCTAssertFalse(model.isNudging)
        // A device that is not there answers with one extra byte.
        XCTAssertEqual(try askBytes(simulator, [p, 3, 99, 6, 0, 1, 0, 0]), "\u{00}#")
        // Firmware version of a motor controller.
        XCTAssertEqual(try askBytes(simulator, [p, 1, 16, 254, 0, 0, 0, 2]), "\u{04}\u{26}#")
    }

    func testAnUnalignedHandControlAcknowledgesButDoesNotMove() throws {
        let clock = makeClock()
        let model = mount(clock, delay: 0.0)
        model.isAligned = false
        let simulator = NexStarSimulator(clock: clock, mount: model)
        XCTAssertEqual(try askBytes(simulator, [Int(UInt8(ascii: "J"))]), "\u{00}#")
        XCTAssertEqual(try ask(simulator, "r34AB0500,12CE0500"), "#")
        XCTAssertFalse(model.isSlewing)
        XCTAssertEqual(model.slewsStarted, 0)
        XCTAssertEqual(try ask(simulator, "s34AB0500,12CE0500"), "#")
        XCTAssertEqual(model.syncsPerformed, 0)
    }

    func testCommandsMayArriveInPieces() throws {
        let clock = makeClock()
        let model = mount(clock, delay: 0.0)
        let simulator = NexStarSimulator(clock: clock, mount: model)
        try simulator.send(MountText.ascii("r34AB05"))
        XCTAssertEqual(try drain(simulator), "")
        try simulator.send(MountText.ascii("00,12CE0500"))
        XCTAssertEqual(try drain(simulator), "#")
        XCTAssertEqual(model.slewsStarted, 1)
        let lx = LX200Simulator(clock: clock, mount: model)
        try lx.send(MountText.ascii(":G"))
        XCTAssertEqual(try drain(lx), "")
        try lx.send(MountText.ascii("VP#:GVN#"))
        XCTAssertEqual(try drain(lx), "On-Step#4.24#")
        // Characters before the start of a command are skipped.
        try lx.send(MountText.ascii("xx:GVP#"))
        XCTAssertEqual(try drain(lx), "On-Step#")
        XCTAssertEqual(simulator.commandLog + lx.commandLog, ["r", "GVP", "GVN", "GVP"])
    }

    // MARK: Alpaca replies

    func testAlpacaRepliesFollowTheDocumentedShapes() {
        let clock = makeClock()
        let simulator = AlpacaSimulator(clock: clock, mount: mount(clock, at: EquatorialCoordinate(rightAscension: 187.5, declination: 45.5)))
        let builder = AlpacaRequestBuilder()
        func body(_ request: AlpacaHTTPRequest) -> String { (try? simulator.send(request, timeoutSeconds: 5.0))?.body ?? "<failed>" }
        XCTAssertEqual(body(builder.connected()),
                       "{\"Value\":false,\"ClientTransactionID\":1,\"ServerTransactionID\":1,\"ErrorNumber\":0,\"ErrorMessage\":\"\"}")
        XCTAssertEqual(body(builder.abortSlew()),
                       "{\"ClientTransactionID\":2,\"ServerTransactionID\":2,\"ErrorNumber\":1031,\"ErrorMessage\":\"Not connected\"}")
        XCTAssertEqual(body(builder.setConnected(true)),
                       "{\"ClientTransactionID\":3,\"ServerTransactionID\":3,\"ErrorNumber\":0,\"ErrorMessage\":\"\"}")
        XCTAssertTrue(body(builder.rightAscension()).hasPrefix("{\"Value\":12.500000000,"))
        XCTAssertTrue(body(builder.declination()).hasPrefix("{\"Value\":45.500000000,"))
        XCTAssertTrue(body(builder.equatorialSystem()).hasPrefix("{\"Value\":1,"))
        XCTAssertTrue(body(builder.trackingRates()).hasPrefix("{\"Value\":[0,1,2],"))
        XCTAssertTrue(body(builder.canMoveAxis(.primary)).hasPrefix("{\"Value\":true,"))
        XCTAssertTrue(body(builder.canMoveAxis(.tertiary)).hasPrefix("{\"Value\":false,"))
        XCTAssertTrue(body(builder.name()).hasPrefix("{\"Value\":\"Simulated Alpaca Mount\","))
        if let slew = try? builder.slewToCoordinatesAsync(rightAscensionHours: 13.0, declination: 10.0) {
            XCTAssertTrue(body(slew).contains("\"ErrorNumber\":0"))
        } else {
            XCTFail("could not build the slew request")
        }
        XCTAssertTrue(body(builder.slewing()).hasPrefix("{\"Value\":true,"))
    }

    func testAlpacaValidatesPathsMethodsAndParameters() throws {
        let clock = makeClock()
        let simulator = AlpacaSimulator(clock: clock, mount: mount(clock))
        let builder = AlpacaRequestBuilder()
        _ = try simulator.send(builder.setConnected(true), timeoutSeconds: 5.0)
        func status(_ method: AlpacaMethod, _ path: String) throws -> Int {
            try simulator.send(AlpacaHTTPRequest(method: method, path: path, query: [], form: [], clientTransactionID: 1), timeoutSeconds: 5.0).statusCode
        }
        XCTAssertEqual(try status(.get, "/api/v1/telescope/0/bogus"), 400)
        XCTAssertEqual(try status(.get, "/api/v1/telescope/1/slewing"), 400)
        XCTAssertEqual(try status(.get, "/api/v1/camera/0/slewing"), 400)
        XCTAssertEqual(try status(.put, "/api/v1/telescope/0/slewing"), 400)
        XCTAssertEqual(try status(.get, "/api/v1/telescope/0/abortslew"), 400)
        XCTAssertEqual(try status(.get, "/api/v1/telescope/0/canmoveaxis"), 400)
        XCTAssertEqual(try status(.get, "/other"), 400)
        // Out of range values are reported as InvalidValue (0x401), a parked mount as 0x408.
        func put(_ path: String, _ fields: [(String, String)], _ id: Int) throws -> String {
            let form = fields.map { AlpacaField(name: $0.0, value: $0.1) }
            return try simulator.send(AlpacaHTTPRequest(method: .put, path: "/api/v1/telescope/0/\(path)", query: [], form: form,
                                                        clientTransactionID: id), timeoutSeconds: 5.0).body
        }
        XCTAssertTrue(try put("slewtocoordinatesasync", [("RightAscension", "25"), ("Declination", "0")], 5).contains("\"ErrorNumber\":1025"))
        XCTAssertTrue(try put("slewtocoordinatesasync", [("RightAscension", "5")], 6).contains("\"ErrorNumber\":1025"))
        XCTAssertTrue(try put("synctocoordinates", [("RightAscension", "5"), ("Declination", "91")], 7).contains("\"ErrorNumber\":1025"))
        XCTAssertTrue(try put("tracking", [("Tracking", "maybe")], 8).contains("1025"))
        XCTAssertTrue(try put("pulseguide", [("Direction", "7"), ("Duration", "100")], 9).contains("1025"))
        XCTAssertTrue(try put("moveaxis", [("Axis", "2"), ("Rate", "1")], 10).contains("1025"))
        // Parameter names are matched ignoring case.
        XCTAssertTrue(try put("tracking", [("tracking", "false")], 11).contains("\"ErrorNumber\":0"))
        XCTAssertFalse(simulator.mount.isTracking)
    }

    func testAlpacaManagementEndpoints() throws {
        let clock = makeClock()
        let simulator = AlpacaSimulator(clock: clock, mount: mount(clock), deviceNumber: 3)
        let builder = AlpacaRequestBuilder(deviceNumber: 3, clientID: 5)
        let versions = builder.apiVersions()
        XCTAssertEqual(try AlpacaResponseParser.apiVersions(try simulator.send(versions, timeoutSeconds: 5.0), for: versions), [1])
        let description = builder.serverDescription()
        XCTAssertEqual(try AlpacaResponseParser.serverDescription(try simulator.send(description, timeoutSeconds: 5.0), for: description).manufacturer,
                       "Lodestar")
        let devices = builder.configuredDevices()
        let parsed = try AlpacaResponseParser.configuredDevices(try simulator.send(devices, timeoutSeconds: 5.0), for: devices)
        XCTAssertEqual(parsed.map(\.deviceType), ["Telescope", "Camera"])
        XCTAssertEqual(try XCTUnwrap(parsed.first { $0.isTelescope }).deviceNumber, 3)
        XCTAssertEqual(try simulator.send(AlpacaHTTPRequest(method: .get, path: "/management/v1/other", query: [], form: [],
                                                            clientTransactionID: 1), timeoutSeconds: 5.0).statusCode, 400)
        // Discovery: the simulator is what the datagram finds.
        XCTAssertTrue(AlpacaDiscovery.isRequest(AlpacaDiscovery.requestPayload))
    }

    func testAlpacaFaults() throws {
        let clock = makeClock()
        let simulator = AlpacaSimulator(clock: clock, mount: mount(clock))
        let builder = AlpacaRequestBuilder()
        simulator.inject("name", .status(statusCode: 503, body: "Busy"))
        XCTAssertEqual(try simulator.send(builder.name(), timeoutSeconds: 5.0), AlpacaHTTPResponse(statusCode: 503, body: "Busy"))
        simulator.inject("name", .body(text: "not json"))
        XCTAssertEqual(try simulator.send(builder.name(), timeoutSeconds: 5.0), AlpacaHTTPResponse(statusCode: 200, body: "not json"))
        simulator.inject("name", .error(number: 1280, message: "Boom \"quoted\""))
        XCTAssertTrue(try simulator.send(builder.name(), timeoutSeconds: 5.0).body.contains("\"ErrorMessage\":\"Boom \\\"quoted\\\"\""))
        let before = clock.secondsSince1970
        simulator.inject("name", .timeout)
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try simulator.send(builder.name(), timeoutSeconds: 7.0) }).isTimeout)
        XCTAssertGreaterThanOrEqual(clock.secondsSince1970 - before, 7.0)
        simulator.inject("name", .wrongTransactionID)
        let request = builder.name()
        XCTAssertTrue(try simulator.send(request, timeoutSeconds: 5.0).body.contains("\"ClientTransactionID\":\(request.clientTransactionID + 1000)"))
        XCTAssertEqual(simulator.methodLog, ["name", "name", "name", "name", "name"])
    }
}

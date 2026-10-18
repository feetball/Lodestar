import XCTest
@testable import LodestarKit

/// Protocol-specific behaviour of the three drivers, exercised against the simulators without a controller.
final class MountDriverTests: XCTestCase {
    private typealias Support = MountTestSupport

    private struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private final class Fixture<S> {
        let clock: ManualMountClock
        let mount: MountSimulatorModel
        let simulator: S

        init(clock: ManualMountClock, mount: MountSimulatorModel, simulator: S) {
            self.clock = clock
            self.mount = mount
            self.simulator = simulator
        }
    }

    private func lx200(_ dialect: LX200Dialect = .onstep, highPrecision: Bool = true,
                       configure: (LX200Simulator) -> Void = { _ in }) -> Fixture<LX200Simulator> {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        let simulator = LX200Simulator(clock: clock, mount: mount, dialect: dialect, highPrecision: highPrecision)
        configure(simulator)
        return Fixture(clock: clock, mount: mount, simulator: simulator)
    }

    private func nexStar(_ flavor: NexStarFlavor = .synscan, _ major: Int = 4, _ minor: Int = 38, _ patch: Int = 6,
                         trackingMode: Int = 1) -> Fixture<NexStarSimulator> {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        return Fixture(clock: clock, mount: mount,
                       simulator: NexStarSimulator(clock: clock, mount: mount, flavor: flavor, major: major, minor: minor, patch: patch,
                                                   trackingMode: trackingMode))
    }

    // MARK: LX200

    func testALowPrecisionMountIsSwitchedToHighPrecisionOnce() throws {
        let f = lx200(.meade, highPrecision: false)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        XCTAssertTrue(f.simulator.highPrecision)
        XCTAssertEqual(driver.precision, .high)
        XCTAssertEqual(f.simulator.commandLog.filter { $0 == "U" }.count, 1)
        _ = try driver.readPosition()
        XCTAssertEqual(f.simulator.commandLog.filter { $0 == "U" }.count, 1)
    }

    func testAHighPrecisionMountIsLeftAlone() throws {
        let f = lx200(.meade, highPrecision: true)
        _ = try LX200Driver(transport: f.simulator, clock: f.clock).connect()
        XCTAssertEqual(f.simulator.commandLog.filter { $0 == "U" }.count, 0)
        XCTAssertTrue(f.simulator.highPrecision)
    }

    func testLowPrecisionCanBeKeptAndTargetsUseIt() throws {
        let f = lx200(.meade, highPrecision: false)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock, configuration: LX200Configuration(prefersHighPrecision: false))
        _ = try driver.connect()
        XCTAssertEqual(driver.precision, .low)
        XCTAssertEqual(f.simulator.commandLog.filter { $0 == "U" }.count, 0)
        try driver.slew(to: EquatorialCoordinate(rightAscension: 187.5, declination: 45.5))
        XCTAssertTrue(f.simulator.commandLog.contains("Sr12:30.0"), "\(f.simulator.commandLog)")
        XCTAssertTrue(f.simulator.commandLog.contains("Sd+45*30"), "\(f.simulator.commandLog)")
        XCTAssertEqual(f.mount.slewsStarted, 1)
    }

    func testAPrecisionChangeBehindTheDriversBackIsNoticedByTheNextReading() throws {
        let f = lx200(.meade, highPrecision: true)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        // Someone toggles the format on the hand controller; a strict Meade mount now refuses the high precision target.
        f.simulator.highPrecision = false
        let target = EquatorialCoordinate(rightAscension: 187.5, declination: 45.5)
        XCTAssertTrue(try XCTUnwrap(mountError { try driver.slew(to: target) }).isRejected)
        XCTAssertEqual(f.mount.slewsStarted, 0)
        _ = try driver.readPosition()
        XCTAssertEqual(driver.precision, .low)
        try driver.slew(to: target)
        XCTAssertEqual(f.mount.slewsStarted, 1)
    }

    func testIdentificationIsOptional() throws {
        let f = lx200(.meade) { $0.inject("GVP", .silence) }
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        let begin = f.clock.secondsSince1970
        let capabilities = try driver.connect()
        XCTAssertEqual(capabilities.name, "LX200-compatible mount")
        XCTAssertNil(capabilities.firmware)
        XCTAssertEqual(driver.dialect, .meade)
        // Only the short identification timeout was spent waiting.
        XCTAssertLessThan(f.clock.secondsSince1970 - begin, 2.0)
    }

    func testGarbageDuringIdentificationIsIgnored() throws {
        let f = lx200(.meade) { $0.inject("GVP", .replace(text: String(repeating: "x", count: 70) + "#")) }
        let capabilities = try LX200Driver(transport: f.simulator, clock: f.clock).connect()
        XCTAssertEqual(capabilities.name, "LX200-compatible mount")
        XCTAssertNil(capabilities.firmware)
    }

    func testTheDialectCanBeForced() throws {
        let f = lx200(.onstep)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock, configuration: LX200Configuration(dialect: .meade))
        let capabilities = try driver.connect()
        XCTAssertEqual(driver.dialect, .meade)
        XCTAssertFalse(capabilities.canSetTracking)
        XCTAssertFalse(f.simulator.commandLog.contains("GU"))
        XCTAssertNil(try driver.readTracking())
        XCTAssertNil(try driver.readAligned())
        XCTAssertEqual(mountError { try driver.setTracking(false) }, .notSupported(feature: .tracking))
    }

    func testOnStepReportsTrackingAndAlignment() throws {
        let f = lx200(.onstep) { $0.alignedStars = 0 }
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        XCTAssertEqual(try driver.connect().isAligned, false)
        XCTAssertEqual(try driver.readAligned(), false)
        f.simulator.alignedStars = 3
        XCTAssertEqual(try driver.readAligned(), true)
        XCTAssertEqual(try driver.readTracking(), true)
        f.mount.isTracking = false
        XCTAssertEqual(try driver.readTracking(), false)
    }

    func testMeadeDateReplyTextDoesNotDisturbTheNextCommand() throws {
        let f = lx200(.meade)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        try driver.setSiteAndTime(location: GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 0), date: Support.start)
        let position = try driver.readPosition()
        XCTAssertEqual(position.angularSeparation(to: Support.parkPosition), 0.0, accuracy: 0.03)
        XCTAssertEqual(f.simulator.siteCommands, ["St+40*00", "Sg105*00", "SG+00.0", "SC10/18/26", "SL04:00:00"])
    }

    func testAMountThatRefusesTheSiteSaysWhich() throws {
        let f = lx200(.onstep) { $0.inject("Sg", .replace(text: "0")) }
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        let location = GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 0)
        guard case let .rejected(detail)? = mountError({ try driver.setSiteAndTime(location: location, date: Support.start) }) else {
            return XCTFail("expected a rejection")
        }
        XCTAssertTrue(detail.contains("longitude"), detail)
        XCTAssertTrue(try XCTUnwrap(mountError {
            try driver.setSiteAndTime(location: location, date: Date(timeIntervalSince1970: 253_402_300_800))
        }).isInvalidInput)
    }

    func testOnStepSyncLooksAtTheStatusBeforeTouchingTheTarget() throws {
        let f = lx200(.onstep)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        f.simulator.clearLog()
        f.mount.isParked = true
        XCTAssertEqual(mountError { try driver.sync(to: Support.andromeda) }, .parked)
        f.mount.isParked = false
        f.mount.beginSlew(to: Support.andromeda)
        XCTAssertEqual(mountError { try driver.sync(to: Support.andromeda) }, .slewInProgress)
        XCTAssertTrue(f.simulator.commandLog.allSatisfy { !$0.hasPrefix("Sr") && $0 != "CM" }, "\(f.simulator.commandLog)")
    }

    func testGarbageWhereAFlagIsExpectedIsReported() throws {
        let f = lx200(.onstep)
        let driver = LX200Driver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        f.simulator.inject("Sr", .replace(text: "x"))
        XCTAssertTrue(try XCTUnwrap(mountError { try driver.slew(to: Support.andromeda) }).isMalformedReply)
        f.simulator.inject("MS", .replace(text: "z"))
        XCTAssertTrue(try XCTUnwrap(mountError { try driver.slew(to: Support.andromeda) }).isMalformedReply)
    }

    // MARK: NexStar and SynScan

    func testOldCelestronFirmwareGetsFewerFeaturesAndStandardPositions() throws {
        let old = nexStar(.celestron, 1, 5, 0)
        let driver = NexStarDriver(transport: old.simulator, clock: old.clock)
        let capabilities = try driver.connect()
        XCTAssertFalse(capabilities.canSync || capabilities.canSetTracking || capabilities.canNudge || capabilities.canSetSiteAndTime)
        XCTAssertTrue(old.simulator.commandLog.contains("E"))
        XCTAssertFalse(old.simulator.commandLog.contains("e"))
        XCTAssertNil(try driver.readTracking())
        XCTAssertEqual(driver.epoch, .meanOfDate)
        XCTAssertEqual(try driver.readPosition().angularSeparation(to: Support.parkPosition), 0.0, accuracy: 0.01)

        let recent = nexStar(.celestron, 1, 6, 0)
        let recentCapabilities = try NexStarDriver(transport: recent.simulator, clock: recent.clock).connect()
        XCTAssertTrue(recentCapabilities.canSetTracking && recentCapabilities.canNudge)
        XCTAssertFalse(recentCapabilities.canSync || recentCapabilities.canSetSiteAndTime)
        XCTAssertTrue(recent.simulator.commandLog.contains("e"))

        let clockProgram = nexStar(.celestron, 2, 3, 0)
        XCTAssertTrue(try NexStarDriver(transport: clockProgram.simulator, clock: clockProgram.clock).connect().canSetSiteAndTime)
        let syncing = nexStar(.celestron, 4, 10, 0)
        XCTAssertTrue(try NexStarDriver(transport: syncing.simulator, clock: syncing.clock).connect().canSync)
    }

    func testSynScanFirmwareGatesSyncAndPassThroughMoves() throws {
        let cases: [((Int, Int, Int), Bool)] = [
            ((3, 36, 0), false), ((3, 37, 0), true), ((4, 37, 2), false), ((4, 37, 3), true), ((4, 38, 6), true),
        ]
        for (version, expected) in cases {
            let f = nexStar(.synscan, version.0, version.1, version.2)
            let capabilities = try NexStarDriver(transport: f.simulator, clock: f.clock).connect()
            XCTAssertEqual(capabilities.canSync, expected, "\(version)")
            XCTAssertTrue(capabilities.canNudge, "\(version)")
            XCTAssertTrue(capabilities.canSetTracking, "\(version)")
        }
        let tooOld = nexStar(.synscan, 3, 2, 0)
        XCTAssertFalse(try NexStarDriver(transport: tooOld.simulator, clock: tooOld.clock).connect().canNudge)
        let driver = NexStarDriver(transport: tooOld.simulator, clock: tooOld.clock)
        let capabilities = try driver.connect()
        XCTAssertEqual(capabilities.name, "Sky-Watcher AZ GOTO 3.02.00")
        XCTAssertEqual(capabilities.firmware, "3.02.00")
    }

    func testTheEpochDefaultsFollowTheFlavorAndCanBeOverridden() throws {
        let synScan = nexStar(.synscan)
        let automatic = NexStarDriver(transport: synScan.simulator, clock: synScan.clock)
        _ = try automatic.connect()
        XCTAssertEqual(automatic.epoch, .j2000)
        let celestron = nexStar(.celestron, 5, 28, 0)
        let celestronDriver = NexStarDriver(transport: celestron.simulator, clock: celestron.clock)
        _ = try celestronDriver.connect()
        XCTAssertEqual(celestronDriver.epoch, .meanOfDate)
        let legacy = nexStar(.synscan)
        let forced = NexStarDriver(transport: legacy.simulator, clock: legacy.clock, configuration: NexStarConfiguration(epoch: .meanOfDate))
        XCTAssertEqual(forced.epoch, .meanOfDate)
        _ = try forced.connect()
        XCTAssertEqual(forced.epoch, .meanOfDate)
        let celestronAsJ2000 = nexStar(.celestron, 5, 28, 0)
        let override = NexStarDriver(transport: celestronAsJ2000.simulator, clock: celestronAsJ2000.clock,
                                     configuration: NexStarConfiguration(epoch: .j2000))
        _ = try override.connect()
        XCTAssertEqual(override.epoch, .j2000)
    }

    func testTrackingIsSwitchedBackOnInTheModeThatWasRunning() throws {
        let equatorial = nexStar(trackingMode: 2)
        let driver = NexStarDriver(transport: equatorial.simulator, clock: equatorial.clock)
        _ = try driver.connect()
        try driver.setTracking(false)
        XCTAssertEqual(try driver.readTracking(), false)
        try driver.setTracking(true)
        XCTAssertEqual(equatorial.simulator.trackingMode, 2)
        XCTAssertEqual(try driver.readTracking(), true)

        let stopped = nexStar(trackingMode: 1)
        stopped.mount.isTracking = false
        let preferred = NexStarDriver(transport: stopped.simulator, clock: stopped.clock,
                                      configuration: NexStarConfiguration(preferredTrackingMode: .eqNorth))
        _ = try preferred.connect()
        try preferred.setTracking(true)
        XCTAssertEqual(stopped.simulator.trackingMode, 2)
        XCTAssertTrue(stopped.mount.isTracking)
    }

    func testAMotorControllerThatDoesNotAnswerIsReported() throws {
        let f = nexStar()
        let driver = NexStarDriver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        f.simulator.inject("P", .replace(text: "\u{00}#"))
        XCTAssertTrue(try XCTUnwrap(mountError { try driver.startNudge(direction: .north, rate: .center, durationSeconds: 1.0) }).isRejected)
        // Tracking was paused for the move; stopping the failed nudge puts it back.
        XCTAssertFalse(f.mount.isTracking)
        try driver.stopNudge(direction: .north)
        XCTAssertFalse(f.mount.isNudging)
        XCTAssertTrue(f.mount.isTracking)
    }

    func testEastAndWestCanBeSwapped() throws {
        for invert in [false, true] {
            let f = nexStar()
            let driver = NexStarDriver(transport: f.simulator, clock: f.clock, configuration: NexStarConfiguration(invertsEastWest: invert))
            _ = try driver.connect()
            let before = f.mount.position.rightAscension
            try driver.startNudge(direction: .east, rate: .find, durationSeconds: 1.0)
            f.clock.advance(seconds: 1.0)
            try driver.stopNudge(direction: .east)
            let moved = f.mount.position.rightAscension - before
            XCTAssertTrue(invert ? moved < -0.01 : moved > 0.01, "invert=\(invert) moved \(moved)")
        }
    }

    func testUnalignedHandControlsDoNotGetGotoCommands() throws {
        let f = nexStar()
        f.mount.isAligned = false
        let driver = NexStarDriver(transport: f.simulator, clock: f.clock)
        XCTAssertEqual(try driver.connect().isAligned, false)
        XCTAssertEqual(mountError { try driver.slew(to: Support.andromeda) }, .notAligned)
        XCTAssertFalse(f.simulator.commandLog.contains("r"))
        XCTAssertEqual(try driver.readAligned(), false)
        f.mount.isAligned = true
        XCTAssertEqual(try driver.readAligned(), true)
    }

    func testUnalignedPositionsMayBeMeaningless() throws {
        let nonsense = MountSimulatedFault.replace(text: "34AB0500,50000500#")
        let unaligned = nexStar()
        unaligned.mount.isAligned = false
        unaligned.simulator.inject("e", nonsense, times: 3)
        let driver = NexStarDriver(transport: unaligned.simulator, clock: unaligned.clock)
        _ = try driver.connect()
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try driver.readPosition() }).isMalformedReply)

        let aligned = nexStar()
        aligned.simulator.inject("e", nonsense)
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try NexStarDriver(transport: aligned.simulator, clock: aligned.clock).connect() })
            .isMalformedReply)
    }

    func testTheControllerShowsAnUnalignedMountAndNoticesWhenItIsAligned() throws {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        mount.isAligned = false
        let simulator = NexStarSimulator(clock: clock, mount: mount)
        simulator.inject("e", .replace(text: "34AB0500,50000500#"), times: 3)
        let controller = MountController(driver: NexStarDriver(transport: simulator, clock: clock), observer: Support.boulder,
                                         settings: .standard, clock: clock)
        try controller.connect()
        XCTAssertEqual(controller.status.isAligned, false)
        XCTAssertNil(controller.status.position)
        let polled = controller.poll()
        XCTAssertNil(polled.lastError)
        XCTAssertEqual(polled.isAligned, false)
        XCTAssertEqual(mountError { try controller.goto(Support.andromeda) }, .notAligned)
        mount.isAligned = true
        let aligned = controller.poll()
        XCTAssertEqual(aligned.isAligned, true)
        XCTAssertNotNil(aligned.position)
        try controller.goto(Support.andromeda)
        XCTAssertEqual(controller.status.phase, .slewing)
    }

    func testSiteAndTimeAreRefusedByOldHandControls() throws {
        let f = nexStar(.celestron, 2, 2, 0)
        let driver = NexStarDriver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        let location = GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 0)
        XCTAssertEqual(mountError { try driver.setSiteAndTime(location: location, date: Support.start) }, .notSupported(feature: .siteAndTime))
        let recent = nexStar()
        let recentDriver = NexStarDriver(transport: recent.simulator, clock: recent.clock)
        _ = try recentDriver.connect()
        XCTAssertTrue(try XCTUnwrap(mountError {
            try recentDriver.setSiteAndTime(location: location, date: Date(timeIntervalSince1970: 5_680_886_400))
        }).isInvalidInput)
    }

    func testGarbageWhereAnAcknowledgementIsExpected() throws {
        let f = nexStar()
        let driver = NexStarDriver(transport: f.simulator, clock: f.clock)
        _ = try driver.connect()
        f.simulator.inject("r", .replace(text: "?"))
        XCTAssertTrue(try XCTUnwrap(mountError { try driver.slew(to: Support.andromeda) }).isMalformedReply)
        f.simulator.inject("L", .replace(text: "2#"))
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try driver.readSlewing() }).isMalformedReply)
        f.simulator.inject("t", .replace(text: "\u{09}#"))
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try driver.readTracking() }).isMalformedReply)
        f.simulator.inject("J", .replace(text: "\u{07}#"))
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try driver.readAligned() }).isMalformedReply)
        f.simulator.inject("L", .replace(text: "1x"))
        XCTAssertTrue(try XCTUnwrap(mountError { _ = try driver.readSlewing() }).isMalformedReply)
    }

    // MARK: Alpaca

    private final class Recorder: AlpacaTransport {
        private let inner: AlpacaTransport
        private(set) var requests: [AlpacaHTTPRequest] = []

        init(_ inner: AlpacaTransport) { self.inner = inner }

        func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse {
            requests.append(request)
            return try inner.send(request, timeoutSeconds: timeoutSeconds)
        }
    }

    private func alpaca(_ build: (ManualMountClock, MountSimulatorModel) -> AlpacaSimulator)
        -> (ManualMountClock, MountSimulatorModel, AlpacaSimulator) {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        return (clock, mount, build(clock, mount))
    }

    func testOtherCoordinateSystemsAreRefused() {
        for system in [0, 3, 4] {
            let (_, _, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1, equatorialSystem: system) }
            XCTAssertEqual(mountError { _ = try AlpacaDriver(transport: simulator).connect() }, .unsupportedCoordinateSystem(code: system), "\(system)")
        }
    }

    func testNudgesFallBackToWhatTheMountOffers() throws {
        let (_, mountA, onlyPulses) = alpaca { AlpacaSimulator(clock: $0, mount: $1, canMoveAxis: false) }
        let pulseDriver = AlpacaDriver(transport: onlyPulses)
        XCTAssertTrue(try pulseDriver.connect().canNudge)
        try pulseDriver.startNudge(direction: .north, rate: .slew, durationSeconds: 1.0)
        XCTAssertTrue(onlyPulses.methodLog.contains("pulseguide"))
        XCTAssertFalse(onlyPulses.methodLog.contains("moveaxis"))
        XCTAssertGreaterThan(mountA.position.declination, Support.parkPosition.declination)

        let (_, _, onlyAxes) = alpaca { AlpacaSimulator(clock: $0, mount: $1, canPulseGuide: false) }
        let axisDriver = AlpacaDriver(transport: onlyAxes)
        XCTAssertTrue(try axisDriver.connect().canNudge)
        try axisDriver.startNudge(direction: .north, rate: .guide, durationSeconds: 1.0)
        XCTAssertTrue(onlyAxes.methodLog.contains("moveaxis"))
        try axisDriver.stopNudge(direction: .north)
        XCTAssertEqual(onlyAxes.methodLog.filter { $0 == "moveaxis" }.count, 2)

        let (_, _, neither) = alpaca { AlpacaSimulator(clock: $0, mount: $1, canPulseGuide: false, canMoveAxis: false) }
        let bareDriver = AlpacaDriver(transport: neither)
        XCTAssertFalse(try bareDriver.connect().canNudge)
        XCTAssertEqual(mountError { try bareDriver.startNudge(direction: .east, rate: .center, durationSeconds: 1.0) }, .notSupported(feature: .nudge))
    }

    func testRequestsAreNumberedConsecutivelyWithOneClientIdentity() throws {
        let (clock, _, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1) }
        let recorder = Recorder(simulator)
        let controller = MountController(driver: AlpacaDriver(transport: recorder, configuration: AlpacaConfiguration(clientID: 42)),
                                         observer: Support.boulder, settings: .standard, clock: clock)
        try controller.connect()
        try controller.goto(Support.andromeda)
        controller.poll()
        try controller.abort()
        let ids = recorder.requests.map(\.clientTransactionID)
        XCTAssertEqual(ids, Array(1 ... ids.count))
        XCTAssertGreaterThan(ids.count, 15)
        XCTAssertTrue(recorder.requests.allSatisfy { ($0.query + $0.form).contains(AlpacaField(name: "ClientID", value: "42")) })
        XCTAssertTrue(recorder.requests.allSatisfy { $0.path.hasPrefix("/api/v1/telescope/0/") })
    }

    func testTheMoveAxisSignIsConfigurable() throws {
        for eastIsPositive in [true, false] {
            let (clock, _, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1, canPulseGuide: false) }
            let recorder = Recorder(simulator)
            let driver = AlpacaDriver(transport: recorder, configuration: AlpacaConfiguration(
                primaryPositiveIsEast: eastIsPositive, secondaryPositiveIsNorth: !eastIsPositive))
            _ = try driver.connect()
            clock.advance(seconds: 0.0)
            try driver.startNudge(direction: .east, rate: .center, durationSeconds: 1.0)
            try driver.startNudge(direction: .north, rate: .center, durationSeconds: 1.0)
            let rates = recorder.requests.filter { $0.path.hasSuffix("/moveaxis") }.compactMap { request in
                request.form.first { $0.name == "Rate" }.flatMap { Double($0.value) }
            }
            XCTAssertEqual(rates.count, 2)
            XCTAssertEqual(rates[0] > 0, eastIsPositive, "east primary \(eastIsPositive)")
            XCTAssertEqual(rates[1] > 0, !eastIsPositive, "north secondary")
        }
    }

    func testServerAndDeviceErrorsAreRecordedByPolls() throws {
        let (clock, _, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1) }
        let controller = MountController(driver: AlpacaDriver(transport: simulator), observer: Support.boulder, settings: .standard, clock: clock)
        try controller.connect()
        simulator.inject("slewing", .status(statusCode: 500, body: "Internal error\r\n"))
        XCTAssertEqual(controller.poll().lastError, .remote(code: 500, detail: "Internal error"))
        XCTAssertNil(controller.poll().lastError)
        simulator.inject("rightascension", .error(number: 1031, message: "Not connected"))
        XCTAssertEqual(controller.poll().lastError, .notConnected)
        XCTAssertNil(controller.poll().lastError)
        simulator.inject("declination", .wrongTransactionID)
        XCTAssertTrue(try XCTUnwrap(controller.poll().lastError).isMalformedReply)
        XCTAssertNil(controller.poll().lastError)
    }

    func testDisconnectingClosesTheServerSession() throws {
        let (clock, _, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1) }
        let controller = MountController(driver: AlpacaDriver(transport: simulator), observer: Support.boulder, settings: .standard, clock: clock)
        try controller.connect()
        XCTAssertTrue(simulator.isConnected)
        controller.disconnect()
        XCTAssertFalse(simulator.isConnected)
    }

    func testTransportExceptionsBecomeTransportErrors() {
        final class Failing: AlpacaTransport {
            func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse {
                throw TestFailure(message: "socket closed")
            }
        }
        XCTAssertEqual(mountError { _ = try AlpacaDriver(transport: Failing()).connect() }, .transport(detail: "socket closed"))
        final class BrokenStream: MountTransport {
            func send(_ bytes: [UInt8]) throws { throw TestFailure(message: "broken pipe") }
            func receive(maxCount: Int, timeoutSeconds: Double) throws -> [UInt8] { throw TestFailure(message: "reset") }
            func discardPendingInput() throws { throw TestFailure(message: "flush failed") }
        }
        let clock = ManualMountClock(start: Support.start)
        XCTAssertEqual(mountError { _ = try LX200Driver(transport: BrokenStream(), clock: clock).connect() }, .transport(detail: "flush failed"))
        XCTAssertEqual(mountError { _ = try NexStarDriver(transport: BrokenStream(), clock: clock).connect() }, .transport(detail: "flush failed"))
    }

    func testAlpacaSlewIsRefusedBeforeSendingWhenTheMountIsParked() throws {
        let (_, mount, simulator) = alpaca { AlpacaSimulator(clock: $0, mount: $1) }
        let driver = AlpacaDriver(transport: simulator)
        _ = try driver.connect()
        mount.isParked = true
        XCTAssertEqual(mountError { try driver.slew(to: Support.andromeda) }, .parked)
        XCTAssertFalse(simulator.methodLog.contains("slewtocoordinatesasync"))
        XCTAssertEqual(mount.slewsStarted, 0)
    }
}

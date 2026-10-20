import XCTest
@testable import LodestarKit

final class MountControllerCommandTests: XCTestCase {
    private typealias Support = MountTestSupport

    // MARK: Sync

    func testSyncMovesTheMountsIdeaOfItsPosition() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            let sent = rig.epoch.fromJ2000(Support.deneb, frame: rig.frame())
            let expectedOffset = Support.parkPosition.angularSeparation(to: sent)
            let result = try rig.controller.sync(Support.deneb)
            XCTAssertEqual(result.offsetDegrees, expectedOffset, accuracy: 0.03, name)
            XCTAssertEqual(rig.mount.syncsPerformed, 1, name)
            XCTAssertEqual(rig.mount.slewsStarted, 0, name)
            let tolerance = name == "lx200-meade-low" ? 0.03 : 0.004
            XCTAssertEqual(rig.mountJ2000().angularSeparation(to: Support.deneb), 0.0, accuracy: tolerance, name)
            XCTAssertEqual(try XCTUnwrap(rig.controller.status.position, name).angularSeparation(to: Support.deneb), 0.0,
                           accuracy: tolerance, name)
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
        }
    }

    func testSyncIsRefusedWhileMoving() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            XCTAssertEqual(mountError { try rig.controller.sync(Support.deneb) }, .slewInProgress, name)
            try rig.controller.abort()
            try rig.controller.nudge(.north, rate: .find, durationSeconds: 5.0)
            XCTAssertEqual(mountError { try rig.controller.sync(Support.deneb) }, .busy, name)
            XCTAssertEqual(rig.mount.syncsPerformed, 0, name)
        }
    }

    func testSyncOffsetLimitCatchesTheWrongStar() throws {
        let rig = Support.rig("lx200-onstep", settings: MountSettings(maximumSyncOffsetDegrees: 5.0))
        try rig.controller.connect()
        guard case let .syncOffsetTooLarge(offset, limit)? = mountError({ try rig.controller.sync(Support.andromeda) }) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(limit, 5.0, accuracy: 0.0)
        XCTAssertGreaterThan(offset, 20.0)
        XCTAssertTrue(MountError.syncOffsetTooLarge(offsetDegrees: offset, limitDegrees: limit).userMessage
            .contains("Check that you centred the right star"))
        XCTAssertEqual(rig.mount.syncsPerformed, 0)
        // A near star is fine.
        let near = EquatorialCoordinate(rightAscension: Support.parkPosition.rightAscension,
                                        declination: Support.parkPosition.declination + 1.0)
        let neighbour = rig.epoch.toJ2000(near, frame: rig.frame())
        XCTAssertEqual(try rig.controller.sync(neighbour).offsetDegrees, 1.0, accuracy: 0.1)
        XCTAssertEqual(rig.mount.syncsPerformed, 1)
    }

    func testSyncNeedsTheCapability() throws {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        let alpaca = AlpacaSimulator(clock: clock, mount: mount, canSync: false)
        let controller = MountController(driver: AlpacaDriver(transport: alpaca), observer: Support.boulder, settings: .standard, clock: clock)
        XCTAssertFalse(try controller.connect().canSync)
        XCTAssertEqual(mountError { try controller.sync(Support.deneb) }, .notSupported(feature: .sync))
        XCTAssertEqual(mount.syncsPerformed, 0)

        let oldClock = ManualMountClock(start: Support.start)
        let oldMount = MountSimulatorModel(clock: oldClock, start: Support.parkPosition)
        let oldHandControl = NexStarSimulator(clock: oldClock, mount: oldMount, flavor: .celestron, major: 4, minor: 3, patch: 0)
        let oldController = MountController(driver: NexStarDriver(transport: oldHandControl, clock: oldClock),
                                            observer: Support.boulder, settings: .standard, clock: oldClock)
        let capabilities = try oldController.connect()
        XCTAssertFalse(capabilities.canSync)
        XCTAssertTrue(try XCTUnwrap(mountError { try oldController.sync(Support.deneb) }).isNotSupported)
    }

    func testMotionStartedOnTheHandControllerBlocksGotoAndSync() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            rig.mount.beginSlew(to: Support.andromeda)
            let status = rig.controller.poll()
            XCTAssertEqual(status.phase, .idle, name)
            XCTAssertEqual(status.isMoving, true, name)
            XCTAssertEqual(mountError { try rig.controller.goto(Support.deneb) }, .slewInProgress, name)
            XCTAssertEqual(mountError { try rig.controller.sync(Support.deneb) }, .slewInProgress, name)
            XCTAssertEqual(rig.mount.syncsPerformed, 0, name)
            try rig.controller.abort()
            XCTAssertEqual(rig.controller.status.isMoving, false, name)
            try rig.controller.goto(Support.deneb)
            XCTAssertEqual(rig.controller.status.phase, .slewing, name)
        }
    }

    // MARK: Nudges

    func testNudgeMovesTheMountAndEndsAfterItsDuration() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            let before = rig.mount.position
            try rig.controller.nudge(.east, rate: .center, durationSeconds: 1.0)
            XCTAssertEqual(rig.controller.status.phase, .nudging, name)
            XCTAssertTrue(rig.mount.isNudging, name)
            rig.clock.advance(seconds: 1.5)
            let status = rig.controller.poll()
            XCTAssertEqual(status.phase, .idle, name)
            XCTAssertFalse(rig.mount.isNudging, name)
            let moved = rig.mount.position.rightAscension - before.rightAscension
            let rate = MountNudgeRate.center.degreesPerSecond
            XCTAssertTrue(moved >= rate * 1.0 && moved <= rate * 2.5, "\(name) moved \(moved) at rate \(rate)")
            XCTAssertEqual(rig.mount.position.declination, before.declination, accuracy: 1e-9, name)
        }
    }

    func testNudgeDirectionsMoveTheRightWay() throws {
        for name in Support.rigNames {
            for direction in MountNudgeDirection.allCases {
                let rig = Support.rig(name)
                try rig.controller.connect()
                let before = rig.mount.position
                try rig.controller.nudge(direction, rate: .find, durationSeconds: 1.0)
                rig.clock.advance(seconds: 1.0)
                try rig.controller.stopNudge()
                let after = rig.mount.position
                let context = "\(name) \(direction)"
                XCTAssertEqual(rig.controller.status.phase, .idle, context)
                switch direction {
                case .north: XCTAssertGreaterThan(after.declination, before.declination + 0.01, context)
                case .south: XCTAssertLessThan(after.declination, before.declination - 0.01, context)
                case .east: XCTAssertGreaterThan(after.rightAscension, before.rightAscension + 0.01, context)
                case .west: XCTAssertLessThan(after.rightAscension, before.rightAscension - 0.01, context)
                }
            }
        }
    }

    func testGuideRateNudgeUsesTheMountsOwnPulseOnAlpaca() throws {
        let rig = Support.rig("alpaca-topocentric")
        try rig.controller.connect()
        let before = rig.mount.position
        try rig.controller.nudge(.north, rate: .guide, durationSeconds: 2.0)
        let simulator = try XCTUnwrap(rig.alpacaSimulator)
        XCTAssertTrue(simulator.methodLog.contains("pulseguide"))
        XCTAssertFalse(simulator.methodLog.contains("moveaxis"))
        XCTAssertEqual(rig.mount.position.declination - before.declination, MountNudgeRate.guide.degreesPerSecond * 2.0, accuracy: 1e-6)
        rig.clock.advance(seconds: 2.5)
        XCTAssertEqual(rig.controller.poll().phase, .idle)
        XCTAssertFalse(simulator.methodLog.contains("moveaxis"))
    }

    func testFasterNudgeOnAlpacaUsesMoveAxisAndStopsItWithRateZero() throws {
        let rig = Support.rig("alpaca-topocentric")
        try rig.controller.connect()
        try rig.controller.nudge(.west, rate: .find, durationSeconds: 1.0)
        let simulator = try XCTUnwrap(rig.alpacaSimulator)
        XCTAssertEqual(simulator.methodLog.filter { $0 == "moveaxis" }.count, 1)
        rig.clock.advance(seconds: 1.2)
        rig.controller.poll()
        XCTAssertEqual(simulator.methodLog.filter { $0 == "moveaxis" }.count, 2)
        XCTAssertFalse(rig.mount.isNudging)
    }

    func testNudgeIsValidatedAndExcludesSlews() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.nudge(.north, rate: .center, durationSeconds: 0.0) }).isInvalidInput)
        XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.nudge(.north, rate: .center, durationSeconds: Double.nan) }).isInvalidInput)
        XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.nudge(.north, rate: .center, durationSeconds: 11.0) }).isInvalidInput)
        XCTAssertFalse(rig.mount.isNudging)
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .busy)
        try rig.controller.stopNudge()
        try rig.controller.goto(Support.andromeda)
        XCTAssertEqual(mountError { try rig.controller.nudge(.north) }, .slewInProgress)
    }

    func testANewNudgeReplacesTheRunningOne() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0)
        let log = try XCTUnwrap(rig.streamSimulator).commandLog
        let north = try XCTUnwrap(log.firstIndex(of: "Mn"))
        let stopNorth = try XCTUnwrap(log.firstIndex(of: "Qn"))
        let east = try XCTUnwrap(log.firstIndex(of: "Me"))
        XCTAssertGreaterThan(stopNorth, north, "\(log)")
        XCTAssertGreaterThan(east, stopNorth, "\(log)")
        let position = rig.mount.position
        rig.clock.advance(seconds: 1.0)
        XCTAssertEqual(rig.mount.position.declination, position.declination, accuracy: 1e-9)
        XCTAssertGreaterThan(rig.mount.position.rightAscension, position.rightAscension)
    }

    func testAbortAlsoStopsANudge() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.nudge(.south, rate: .slew, durationSeconds: 5.0)
            XCTAssertTrue(rig.mount.isNudging, name)
            try rig.controller.abort()
            XCTAssertFalse(rig.mount.isNudging, name)
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
        }
    }

    func testNexStarNudgePausesTrackingAndResumesIt() throws {
        let rig = Support.rig("nexstar-celestron")
        try rig.controller.connect()
        let simulator = try XCTUnwrap(rig.streamSimulator)
        XCTAssertTrue(rig.mount.isTracking)
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 1.0)
        XCTAssertFalse(rig.mount.isTracking)
        rig.clock.advance(seconds: 1.5)
        rig.controller.poll()
        XCTAssertTrue(rig.mount.isTracking)
        XCTAssertEqual(rig.controller.status.phase, .idle)
        let log = simulator.commandLog
        XCTAssertLessThan(try XCTUnwrap(log.firstIndex(of: "T")), try XCTUnwrap(log.firstIndex(of: "P")), "\(log)")
        XCTAssertGreaterThan(try XCTUnwrap(log.lastIndex(of: "T")), try XCTUnwrap(log.lastIndex(of: "P")) - 1, "\(log)")
    }

    // MARK: Tracking and site

    func testTrackingCanBeSwitched() throws {
        for name in Support.rigNames {
            if name == "lx200-meade-low" { continue }
            let rig = Support.rig(name)
            try rig.controller.connect()
            XCTAssertEqual(rig.controller.status.isTracking, true, name)
            try rig.controller.setTracking(false)
            XCTAssertFalse(rig.mount.isTracking, name)
            XCTAssertEqual(rig.controller.status.isTracking, false, name)
            XCTAssertEqual(rig.controller.poll().isTracking, false, name)
            try rig.controller.setTracking(true)
            XCTAssertTrue(rig.mount.isTracking, name)
            XCTAssertEqual(rig.controller.poll().isTracking, true, name)
        }
    }

    func testMeadeMountsCannotSwitchTracking() throws {
        let rig = Support.rig("lx200-meade-low")
        let capabilities = try rig.controller.connect()
        XCTAssertFalse(capabilities.canSetTracking)
        XCTAssertEqual(mountError { try rig.controller.setTracking(false) }, .notSupported(feature: .tracking))
        XCTAssertNil(rig.controller.status.isTracking)
    }

    func testTrackingCannotBeChangedDuringASlew() throws {
        let rig = Support.rig("nexstar-synscan")
        try rig.controller.connect()
        try rig.controller.goto(Support.andromeda)
        XCTAssertEqual(mountError { try rig.controller.setTracking(false) }, .slewInProgress)
        XCTAssertTrue(rig.mount.isTracking)
    }

    func testSiteAndTimeAreSentAsUTC() throws {
        let location = Support.boulder.location
        let lx = Support.rig("lx200-onstep")
        try lx.controller.connect()
        try lx.controller.setSiteAndTime(location: location, date: Support.start)
        XCTAssertEqual((lx.streamSimulator as? LX200Simulator)?.siteCommands,
                       ["St+40*01", "Sg105*16", "SG+00", "SC10/18/26", "SL04:00:00"])
        let meade = Support.rig("lx200-meade-low")
        try meade.controller.connect()
        try meade.controller.setSiteAndTime(location: location, date: Support.start)
        XCTAssertEqual((meade.streamSimulator as? LX200Simulator)?.siteCommands,
                       ["St+40*01", "Sg105*16", "SG+00.0", "SC10/18/26", "SL04:00:00"])
        let nexstar = Support.rig("nexstar-synscan")
        try nexstar.controller.connect()
        try nexstar.controller.setSiteAndTime(location: location, date: Support.start)
        let handControl = try XCTUnwrap(nexstar.streamSimulator as? NexStarSimulator)
        XCTAssertEqual(handControl.receivedLocation, [40, 0, 54, 0, 105, 16, 12, 1])
        XCTAssertEqual(handControl.receivedTime, [4, 0, 0, 10, 18, 26, 0, 0])
        let alpaca = Support.rig("alpaca-topocentric")
        try alpaca.controller.connect()
        try alpaca.controller.setSiteAndTime(location: location, date: Support.start)
        XCTAssertEqual(alpaca.alpacaSimulator?.siteValues,
                       ["SiteLatitude=40.015", "SiteLongitude=-105.27", "SiteElevation=1650.0", "UTCDate=2026-10-18T04:00:00.000Z"])
    }

    func testAlpacaSiteElevationStaysWithinWhatAscomAccepts() throws {
        let rig = Support.rig("alpaca-topocentric")
        try rig.controller.connect()
        // The Dead Sea shore is inside the engine's range for elevations but below ASCOM's lower limit of -300 m.
        try rig.controller.setSiteAndTime(location: GeographicLocation(latitude: 31.5, longitude: 35.5, elevation: -430.0), date: Support.start)
        let low = try XCTUnwrap(rig.alpacaSimulator?.siteValues)
        XCTAssertTrue(low.contains("SiteElevation=-300.0"), "\(low)")
        XCTAssertTrue(low.contains("UTCDate=2026-10-18T04:00:00.000Z"), "\(low)")
        let high = Support.rig("alpaca-topocentric")
        try high.controller.connect()
        try high.controller.setSiteAndTime(location: GeographicLocation(latitude: 28.0, longitude: 86.9, elevation: 11_000.0), date: Support.start)
        XCTAssertTrue(try XCTUnwrap(high.alpacaSimulator?.siteValues).contains("SiteElevation=10000.0"))
    }

    func testDisconnectStopsANudgeAndClosesTheSession() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        try rig.controller.nudge(.north, rate: .find, durationSeconds: 5.0)
        rig.controller.disconnect()
        XCTAssertFalse(rig.mount.isNudging)
        XCTAssertEqual(rig.controller.status.phase, .disconnected)
        XCTAssertFalse(rig.controller.isConnected)
        XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .notConnected)
        // A new session works.
        try rig.controller.connect()
        XCTAssertEqual(rig.controller.status.phase, .idle)
    }
}

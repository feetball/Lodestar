import XCTest
@testable import LodestarKit

final class MountControllerTests: XCTestCase {
    private typealias Support = MountTestSupport

    // MARK: Connecting

    func testConnectReadsCapabilitiesAndPosition() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            XCTAssertEqual(rig.controller.status.phase, .disconnected, name)
            let capabilities = try rig.controller.connect()
            XCTAssertEqual(capabilities, rig.controller.capabilities, name)
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
            XCTAssertTrue(capabilities.canSlew && capabilities.canAbort && capabilities.canSync, name)
            let position = try XCTUnwrap(rig.controller.status.position, name)
            XCTAssertEqual(position.angularSeparation(to: rig.mountJ2000()), 0.0, accuracy: 0.001, name)
            XCTAssertNil(rig.controller.status.target, name)
            XCTAssertNil(rig.controller.status.outcome, name)
            // Connecting twice is harmless.
            XCTAssertEqual(try rig.controller.connect(), capabilities, name)
        }
    }

    func testCapabilitiesDescribeEachProtocol() throws {
        let onStep = try Support.rig("lx200-onstep").controller.connect()
        XCTAssertEqual(onStep.kind, .lx200)
        XCTAssertEqual(onStep.name, "On-Step")
        XCTAssertEqual(onStep.firmware, "4.24")
        XCTAssertTrue(onStep.canSetTracking)
        XCTAssertEqual(onStep.isAligned, true)
        let meade = try Support.rig("lx200-meade-low").controller.connect()
        XCTAssertEqual(meade.name, "LX200 Classic")
        XCTAssertFalse(meade.canSetTracking)
        XCTAssertNil(meade.isAligned)
        let celestron = try Support.rig("nexstar-celestron").controller.connect()
        XCTAssertEqual(celestron.kind, .nexstar)
        XCTAssertEqual(celestron.name, "Celestron NexStar 6/8 SE 5.28")
        XCTAssertTrue(celestron.gotoNeedsAlignment)
        XCTAssertEqual(celestron.isAligned, true)
        let synScan = try Support.rig("nexstar-synscan").controller.connect()
        XCTAssertEqual(synScan.name, "Sky-Watcher AZ GOTO 4.38.06")
        let alpaca = try Support.rig("alpaca-topocentric").controller.connect()
        XCTAssertEqual(alpaca.kind, .alpaca)
        XCTAssertEqual(alpaca.name, "Simulated Alpaca Mount")
        XCTAssertFalse(alpaca.gotoNeedsAlignment)
    }

    func testEpochFollowsTheProtocol() throws {
        let expected: [String: MountEpoch] = [
            "lx200-onstep": .meanOfDate,
            "lx200-meade-low": .meanOfDate,
            "nexstar-celestron": .meanOfDate,
            "nexstar-synscan": .j2000,
            "alpaca-topocentric": .apparentOfDate,
            "alpaca-j2000": .j2000,
        ]
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            XCTAssertEqual(rig.epoch, expected[name], name)
        }
    }

    func testOperationsNeedAConnection() {
        let rig = Support.rig("lx200-onstep")
        XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .notConnected)
        XCTAssertEqual(mountError { try rig.controller.sync(Support.andromeda) }, .notConnected)
        XCTAssertEqual(mountError { try rig.controller.abort() }, .notConnected)
        XCTAssertEqual(mountError { try rig.controller.nudge(.north) }, .notConnected)
        XCTAssertEqual(mountError { try rig.controller.setTracking(true) }, .notConnected)
        XCTAssertEqual(rig.controller.poll(), MountStatus.disconnected)
    }

    // MARK: Goto

    func testGotoSlewsToTheTargetAndArrives() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            XCTAssertEqual(rig.controller.status.phase, .slewing, name)
            XCTAssertEqual(rig.controller.status.target, Support.andromeda, name)
            XCTAssertNil(rig.controller.status.outcome, name)
            let status = rig.controller.awaitSettled()
            XCTAssertEqual(status.phase, .idle, name)
            guard case .arrived? = status.outcome else {
                XCTFail("\(name): \(String(describing: status.outcome))")
                continue
            }
            XCTAssertEqual(rig.mount.slewsStarted, 1, name)
            // The mount was told the target in its own frame and points there; the controller reports J2000.
            XCTAssertEqual(rig.mountJ2000().angularSeparation(to: Support.andromeda), 0.0, accuracy: 0.002, name)
            XCTAssertEqual(try XCTUnwrap(status.position, name).angularSeparation(to: Support.andromeda), 0.0, accuracy: 0.002, name)
            XCTAssertLessThan(status.separation ?? 1.0, 0.01, name)
            XCTAssertNil(status.slewElapsedSeconds, name)
        }
    }

    func testGotoTakesAsLongAsTheMountNeeds() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        let before = rig.clock.now()
        try rig.controller.goto(Support.deneb)
        rig.controller.awaitSettled()
        let seconds = Int(rig.clock.now().timeIntervalSince1970) - Int(before.timeIntervalSince1970)
        let distance = Support.parkPosition.angularSeparation(to: rig.epoch.fromJ2000(Support.deneb, frame: rig.frame()))
        // Rate 4 degrees per second, 0.4 s start delay, polled once a second; right ascension and declination move together.
        XCTAssertGreaterThanOrEqual(seconds, 1, "took \(seconds) s for \(distance) degrees")
        XCTAssertLessThanOrEqual(Double(seconds), distance / 4.0 + 8.0, "took \(seconds) s for \(distance) degrees")
        guard case .arrived? = rig.controller.status.outcome else { return XCTFail("not arrived") }
    }

    func testGotoSendsTheTargetInTheMountsFrame() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            rig.controller.awaitSettled()
            let sent = rig.epoch.fromJ2000(Support.andromeda, frame: rig.frame())
            // Resolution of the position format: 1 s of right ascension (0.004 degrees) for OnStep, 0.1 min and 1 arcminute
            // (0.025 degrees) for the low precision Meade format; the other protocols are finer.
            let tolerance = name == "lx200-meade-low" ? 0.03 : (name == "lx200-onstep" ? 0.004 : 0.001)
            XCTAssertEqual(rig.mount.position.angularSeparation(to: sent), 0.0, accuracy: tolerance, name)
        }
    }

    func testSecondGotoWhileSlewingIsRefusedUntilAborted() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            XCTAssertEqual(mountError { try rig.controller.goto(Support.deneb) }, .slewInProgress, name)
            XCTAssertEqual(rig.mount.slewsStarted, 1, name)
            try rig.controller.abort()
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
            try rig.controller.goto(Support.deneb)
            XCTAssertEqual(rig.mount.slewsStarted, 2, name)
            rig.controller.awaitSettled()
            XCTAssertEqual(rig.mountJ2000().angularSeparation(to: Support.deneb), 0.0, accuracy: 0.002, name)
        }
    }

    func testAbortStopsTheMountMidSlew() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            rig.clock.advance(seconds: 2.0)
            let moving = rig.controller.poll()
            XCTAssertEqual(moving.phase, .slewing, name)
            XCTAssertEqual(moving.isMoving, true, name)
            XCTAssertGreaterThanOrEqual(moving.slewElapsedSeconds ?? 0.0, 2.0, name)
            try rig.controller.abort()
            let status = rig.controller.status
            XCTAssertEqual(status.phase, .idle, name)
            XCTAssertEqual(status.outcome, .aborted, name)
            XCTAssertFalse(rig.mount.isSlewing, name)
            let stopped = rig.mount.position
            rig.clock.advance(seconds: 5.0)
            XCTAssertEqual(rig.mount.position, stopped, name)
            // It is somewhere between start and target.
            let separation = rig.mountJ2000().angularSeparation(to: Support.andromeda)
            XCTAssertGreaterThan(separation, 1.0, "\(name): \(separation)")
            // Polling afterwards reports the mount at rest and keeps the outcome.
            let after = rig.controller.poll()
            XCTAssertEqual(after.isMoving, false, name)
            XCTAssertEqual(after.outcome, .aborted, name)
        }
    }

    func testGotoBelowTheAltitudeLimitIsRefusedWithoutTouchingTheMount() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            let altitude = Support.altitude(of: Support.orionNebula, clock: rig.clock)
            XCTAssertLessThan(altitude, 0, "Orion should be down: \(altitude)")
            guard case let .belowHorizonLimit(reported, limit)? = mountError({ try rig.controller.goto(Support.orionNebula) }) else {
                XCTFail(name)
                continue
            }
            XCTAssertEqual(reported, altitude, accuracy: 0.5, name)
            XCTAssertEqual(limit, 0.0, accuracy: 0.0, name)
            XCTAssertTrue(MountError.belowHorizonLimit(altitude: reported, limit: limit).userMessage.contains("below your altitude limit"), name)
            XCTAssertEqual(rig.mount.slewsStarted, 0, name)
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
        }
    }

    func testAltitudeLimitIsConfigurableAndChecksTheSlewDuration() throws {
        let probe = Support.rig("lx200-onstep")
        let nowAltitude = Support.altitude(of: Support.altair, clock: probe.clock)
        XCTAssertTrue((30.0 ... 55.0).contains(nowAltitude), "Altair altitude \(nowAltitude)")
        let strict = Support.rig("lx200-onstep", settings: MountSettings(altitudeLimit: nowAltitude + 5.0))
        try strict.controller.connect()
        guard case let .belowHorizonLimit(_, limit)? = mountError({ try strict.controller.goto(Support.altair) }) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(limit, nowAltitude + 5.0, accuracy: 1e-9)
        let relaxed = Support.rig("lx200-onstep", settings: MountSettings(altitudeLimit: nowAltitude - 5.0))
        try relaxed.controller.connect()
        try relaxed.controller.goto(Support.altair)
        XCTAssertEqual(relaxed.controller.status.phase, .slewing)

        // Altair is setting: a limit just under its altitude now is met now, but not ten minutes later.
        let later = Support.altitude(of: Support.altair, clock: ManualMountClock(start: Support.start.addingTimeInterval(600)))
        XCTAssertLessThan(later, nowAltitude - 0.5, "Altair should sink: \(nowAltitude) -> \(later)")
        let lookahead = Support.rig(
            "lx200-onstep", settings: MountSettings(altitudeLimit: nowAltitude - 0.05, horizonLookaheadSeconds: 600.0))
        try lookahead.controller.connect()
        guard case let .belowHorizonLimit(altitude, _)? = mountError({ try lookahead.controller.goto(Support.altair) }) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(altitude, later, accuracy: 0.05)
        let noLookahead = Support.rig(
            "lx200-onstep", settings: MountSettings(altitudeLimit: nowAltitude - 0.05, horizonLookaheadSeconds: 0.0))
        try noLookahead.controller.connect()
        try noLookahead.controller.goto(Support.altair)
        XCTAssertEqual(noLookahead.controller.status.phase, .slewing)
    }

    func testInvalidTargetsAreRefused() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        let broken = EquatorialCoordinate(rightAscension: Double.nan, declination: 10.0)
        XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.goto(broken) }).isInvalidInput)
        XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.sync(broken) }).isInvalidInput)
        XCTAssertEqual(rig.mount.slewsStarted, 0)
    }
}

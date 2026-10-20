import XCTest
@testable import LodestarKit

final class MountControllerFaultTests: XCTestCase {
    private typealias Support = MountTestSupport

    /// Makes the position query of the rig fail by silence (or timeout, for Alpaca).
    private func silence(_ rig: MountRig, times: Int = 1) {
        rig.streamSimulator?.inject(rig.name.hasPrefix("lx200") ? "GR" : "e", .silence, times: times)
        rig.alpacaSimulator?.inject("rightascension", .timeout, times: times)
    }

    // MARK: Timeouts

    func testASilentMountEndsTheSessionAfterThreeFailedPolls() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            silence(rig, times: 100)
            let begin = rig.clock.secondsSince1970
            let first = rig.controller.poll()
            XCTAssertTrue(try XCTUnwrap(first.lastError, name).isTimeout, name)
            XCTAssertEqual(first.phase, .idle, name)
            XCTAssertEqual(rig.controller.poll().phase, .idle, name)
            let third = rig.controller.poll()
            XCTAssertEqual(third.phase, .disconnected, name)
            XCTAssertEqual(third.lastError, .connectionLost, name)
            // Three exchanges each waited for their whole timeout.
            XCTAssertGreaterThanOrEqual(rig.clock.secondsSince1970 - begin, 3 * 2.9, name)
            XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .notConnected, name)
        }
    }

    func testOneFailedPollDoesNotCountAgainstLaterOnes() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            silence(rig, times: 1)
            XCTAssertTrue(try XCTUnwrap(rig.controller.poll().lastError, name).isTimeout, name)
            let recovered = rig.controller.poll()
            XCTAssertNil(recovered.lastError, name)
            XCTAssertEqual(recovered.phase, .idle, name)
            silence(rig, times: 2)
            rig.controller.poll()
            XCTAssertEqual(rig.controller.poll().phase, .idle, name)
            XCTAssertNil(rig.controller.poll().lastError, name)
        }
    }

    func testALinkThatDiesDuringASlewIsReported() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            let stopsBefore = rig.mount.stopsReceived
            silence(rig, times: 100)
            rig.controller.poll()
            rig.controller.poll()
            let status = rig.controller.poll()
            XCTAssertEqual(status.phase, .disconnected, name)
            XCTAssertEqual(status.outcome, .failed(error: .connectionLost), name)
            // Giving up on the mount tells it to stop first.
            XCTAssertGreaterThan(rig.mount.stopsReceived, stopsBefore, name)
        }
    }

    func testALinkThatDiesDuringANudgeStopsTheNudgeBeforeTheSessionEnds() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name, settings: MountSettings(maximumNudgeSeconds: 30.0))
            try rig.controller.connect()
            try rig.controller.nudge(.north, rate: .find, durationSeconds: 30.0)
            XCTAssertTrue(rig.mount.isNudging, name)
            silence(rig, times: 100)
            rig.controller.poll()
            XCTAssertEqual(rig.controller.status.phase, .nudging, name)
            XCTAssertTrue(rig.mount.isNudging, name)
            rig.controller.poll()
            let status = rig.controller.poll()
            XCTAssertEqual(status.phase, .disconnected, name)
            XCTAssertEqual(status.lastError, .connectionLost, name)
            XCTAssertFalse(rig.mount.isNudging, name)
        }
    }

    func testAFailedStopDoesNotStopTheSessionFromEnding() throws {
        let rig = Support.rig("alpaca-topocentric", settings: MountSettings(maximumNudgeSeconds: 30.0))
        try rig.controller.connect()
        try rig.controller.nudge(.north, rate: .find, durationSeconds: 30.0)
        silence(rig, times: 100)
        rig.alpacaSimulator?.inject("moveaxis", .timeout, times: 10)
        rig.controller.poll()
        rig.controller.poll()
        let status = rig.controller.poll()
        XCTAssertEqual(status.phase, .disconnected)
        XCTAssertEqual(status.lastError, .connectionLost)
    }

    func testAnAlpacaMoveWhoseReplyWasLostIsStillStopped() throws {
        let clock = ManualMountClock(start: Support.start)
        let mount = MountSimulatorModel(clock: clock, start: Support.parkPosition)
        let simulator = AlpacaSimulator(clock: clock, mount: mount, canPulseGuide: false)
        let transport = LostReplyTransport(simulator, method: "moveaxis")
        let controller = MountController(driver: AlpacaDriver(transport: transport), observer: Support.boulder, settings: .standard,
                                         clock: clock)
        try controller.connect()
        let error = try XCTUnwrap(mountError { try controller.nudge(.east, rate: .find, durationSeconds: 5.0) })
        XCTAssertTrue(error.isTimeout)
        XCTAssertEqual(transport.lostReplies, 1)
        XCTAssertEqual(controller.status.phase, .idle)
        // The mount did carry out the request. The cleanup that follows the failure must send the stop as well.
        XCTAssertEqual(simulator.methodLog.filter { $0 == "moveaxis" }.count, 2)
        XCTAssertFalse(mount.isNudging)
    }

    func testAnAlpacaMoveTheMountRefusedIsNotStoppedAgain() throws {
        let rig = Support.rig("alpaca-topocentric")
        try rig.controller.connect()
        rig.alpacaSimulator?.inject("moveaxis", .error(number: 1025, message: "bad rate"))
        let error = try XCTUnwrap(mountError { try rig.controller.nudge(.east, rate: .find, durationSeconds: 5.0) })
        XCTAssertTrue(error.isRejected)
        // The mount said no, so nothing moves and there is nothing to stop.
        XCTAssertEqual(rig.alpacaSimulator?.methodLog.filter { $0 == "moveaxis" }.count, 1)
        XCTAssertFalse(rig.mount.isNudging)
    }

    /// An Alpaca link that delivers a request to the server but loses the first reply to the method, as a slow Wi-Fi does.
    private final class LostReplyTransport: AlpacaTransport {
        private let inner: AlpacaTransport
        private let method: String
        private(set) var lostReplies = 0

        init(_ inner: AlpacaTransport, method: String) {
            self.inner = inner
            self.method = method
        }

        func send(_ request: AlpacaHTTPRequest, timeoutSeconds: Double) throws -> AlpacaHTTPResponse {
            let response = try inner.send(request, timeoutSeconds: timeoutSeconds)
            if lostReplies == 0 && request.path.hasSuffix("/" + method) {
                lostReplies += 1
                throw MountError.timeout(operation: "simulated")
            }
            return response
        }
    }

    func testASlewThatTakesTooLongIsAborted() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name, settings: MountSettings(maximumSlewSeconds: 30.0), slewRate: 0.05)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            let status = rig.controller.awaitSettled()
            XCTAssertEqual(status.phase, .idle, name)
            XCTAssertEqual(status.outcome, .failed(error: .slewTimeout(seconds: 30.0)), name)
            XCTAssertFalse(rig.mount.isSlewing, name)
            XCTAssertGreaterThanOrEqual(rig.mount.stopsReceived, 1, name)
            let seconds = rig.clock.secondsSince1970 - Support.start.timeIntervalSince1970
            XCTAssertTrue((30.0 ... 45.0).contains(seconds), "\(name) took \(seconds)")
        }
    }

    func testAMountThatStopsShortIsReportedAsSuch() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            rig.clock.advance(seconds: 1.5)
            XCTAssertEqual(rig.controller.poll().phase, .slewing, name)
            rig.mount.stop()
            let status = rig.controller.poll()
            XCTAssertEqual(status.phase, .idle, name)
            guard case let .failed(error)? = status.outcome, case let .slewStopped(remaining) = error else {
                XCTFail("\(name): \(String(describing: status.outcome))")
                continue
            }
            XCTAssertGreaterThan(remaining, 1.0, name)
            XCTAssertTrue(error.userMessage.contains("short of the target"), name)
        }
    }

    func testAMountThatNeverStartsIsReportedAfterTheGracePeriod() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        try rig.controller.goto(Support.andromeda)
        rig.mount.stop()
        XCTAssertEqual(rig.controller.poll().phase, .slewing)
        rig.clock.advance(seconds: 6.0)
        let status = rig.controller.poll()
        XCTAssertEqual(status.phase, .idle)
        guard case let .failed(error)? = status.outcome else { return XCTFail("expected a failure") }
        XCTAssertTrue(error.isSlewStopped)
    }

    func testGotoToTheCurrentPositionArrivesAtOnce() throws {
        let rig = Support.rig("nexstar-synscan")
        try rig.controller.connect()
        let here = rig.epoch.toJ2000(Support.parkPosition, frame: rig.frame())
        try rig.controller.goto(here)
        rig.mount.stop()
        let status = rig.controller.poll()
        XCTAssertEqual(status.phase, .idle)
        guard case .arrived? = status.outcome else { return XCTFail("expected arrival") }
    }

    // MARK: Refusals

    func testOnStepRefusalsAreExplained() throws {
        let expected: [(Character, MountError)] = [
            ("1", .mountHorizonLimit), ("2", .mountOverheadLimit), ("3", .standby), ("4", .parked), ("5", .slewInProgress),
            ("6", .outsideMountLimits), ("8", .busy),
        ]
        for (code, error) in expected {
            let rig = Support.rig("lx200-onstep")
            try rig.controller.connect()
            (rig.streamSimulator as? LX200Simulator)?.refusalCode = code
            XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, error, "code \(code)")
            XCTAssertEqual(rig.controller.status.phase, .idle, "code \(code)")
            XCTAssertEqual(rig.mount.slewsStarted, 0, "code \(code)")
            XCTAssertEqual(rig.controller.status.lastError, error, "code \(code)")
        }
        let fault = Support.rig("lx200-onstep")
        try fault.controller.connect()
        let faulty = try XCTUnwrap(fault.streamSimulator as? LX200Simulator)
        faulty.refusalCode = "7"
        XCTAssertTrue(try XCTUnwrap(mountError { try fault.controller.goto(Support.andromeda) }).isHardwareFault)
        faulty.refusalCode = "9"
        XCTAssertTrue(try XCTUnwrap(mountError { try fault.controller.goto(Support.andromeda) }).isRejected)
    }

    func testMeadeRefusalsCarryTheirTextAndAreStillTyped() throws {
        let rig = Support.rig("lx200-meade-low")
        try rig.controller.connect()
        let simulator = try XCTUnwrap(rig.streamSimulator as? LX200Simulator)
        simulator.refusalCode = "1"
        XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .mountHorizonLimit)
        simulator.refusalCode = "2"
        XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .mountOverheadLimit)
        // The text after the digit was consumed: the next exchange is clean.
        simulator.refusalCode = nil
        try rig.controller.goto(Support.andromeda)
        XCTAssertEqual(rig.controller.status.phase, .slewing)
    }

    func testOnStepSyncRefusalsAreExplained() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        let simulator = try XCTUnwrap(rig.streamSimulator as? LX200Simulator)
        simulator.refusalCode = "6"
        XCTAssertEqual(mountError { try rig.controller.sync(Support.andromeda) }, .outsideMountLimits)
        simulator.refusalCode = nil
        rig.mount.isParked = true
        XCTAssertEqual(mountError { try rig.controller.sync(Support.andromeda) }, .parked)
        XCTAssertEqual(rig.mount.syncsPerformed, 0)
    }

    func testAnUnalignedHandControlRefusesToSlew() throws {
        for name in ["nexstar-celestron", "nexstar-synscan"] {
            let rig = Support.rig(name)
            rig.mount.isAligned = false
            let capabilities = try rig.controller.connect()
            XCTAssertEqual(capabilities.isAligned, false, name)
            XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, .notAligned, name)
            XCTAssertEqual(rig.mount.slewsStarted, 0, name)
            XCTAssertTrue(rig.controller.status.lastError?.userMessage.contains("star alignment") == true, name)
            // Aligning the mount later is picked up without reconnecting.
            rig.mount.isAligned = true
            try rig.controller.goto(Support.andromeda)
            XCTAssertEqual(rig.controller.status.phase, .slewing, name)
        }
    }

    func testAlpacaErrorNumbersBecomeTypedErrors() throws {
        let cases: [(Int, String, MountError)] = [
            (1035, "Target is below the horizon limit", .mountHorizonLimit),
            (1035, "The telescope is not aligned", .notAligned),
            (1032, "", .parked),
            (1280, "Slewing is in progress", .busy),
            (1281, "Meridian limit reached", .outsideMountLimits),
        ]
        for (number, message, expected) in cases {
            let rig = Support.rig("alpaca-topocentric")
            try rig.controller.connect()
            rig.alpacaSimulator?.inject("slewtocoordinatesasync", .error(number: number, message: message))
            XCTAssertEqual(mountError { try rig.controller.goto(Support.andromeda) }, expected, "\(number) \(message)")
            XCTAssertEqual(rig.mount.slewsStarted, 0)
            XCTAssertEqual(rig.controller.status.phase, .idle)
        }
        let unknown = Support.rig("alpaca-topocentric")
        try unknown.controller.connect()
        unknown.alpacaSimulator?.inject("slewtocoordinatesasync", .error(number: 1290, message: "Axis 2 motor stalled"))
        XCTAssertEqual(mountError { try unknown.controller.goto(Support.andromeda) }, .remote(code: 1290, detail: "Axis 2 motor stalled"))
    }

    func testAlpacaMountsThatAreParkedOrNotTrackingSayWhy() throws {
        let parked = Support.rig("alpaca-j2000")
        try parked.controller.connect()
        parked.mount.isParked = true
        XCTAssertEqual(mountError { try parked.controller.goto(Support.andromeda) }, .parked)
        let notTracking = Support.rig("alpaca-j2000")
        try notTracking.controller.connect()
        try notTracking.controller.setTracking(false)
        XCTAssertEqual(mountError { try notTracking.controller.goto(Support.andromeda) }, .notTracking)
        try notTracking.controller.setTracking(true)
        try notTracking.controller.goto(Support.andromeda)
        XCTAssertEqual(notTracking.controller.status.phase, .slewing)
    }

    // MARK: Garbled and partial replies

    func testAGarbledReplyIsReportedAndTheNextPollRecovers() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            if name.hasPrefix("lx200") {
                rig.streamSimulator?.inject("GR", .replace(text: "12:7x:00#"))
            } else if name.hasPrefix("nexstar") {
                rig.streamSimulator?.inject("e", .replace(text: "34AB0500;12CE0500#"))
            } else {
                rig.alpacaSimulator?.inject("rightascension", .body(text: "{\"Value\": 12.5,"))
            }
            let status = rig.controller.poll()
            XCTAssertTrue(try XCTUnwrap(status.lastError, name).isMalformedReply, name)
            XCTAssertEqual(status.phase, .idle, name)
            XCTAssertNil(rig.controller.poll().lastError, name)
        }
    }

    func testATruncatedReplyTimesOutAndTheNextPollRecovers() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            if name.hasPrefix("lx200") {
                rig.streamSimulator?.inject("GR", .truncate(keep: 4))
            } else if name.hasPrefix("nexstar") {
                rig.streamSimulator?.inject("e", .truncate(keep: 10))
            } else {
                rig.alpacaSimulator?.inject("rightascension", .body(text: "{\"Value\": 12.5, \"ClientTr"))
            }
            let status = rig.controller.poll()
            let error = try XCTUnwrap(status.lastError, name)
            // The stream is cut short and the mount stays silent, so the read runs out of time; the JSON is just invalid.
            XCTAssertTrue(error.isTimeout || error.isMalformedReply, "\(name): \(error)")
            XCTAssertNil(rig.controller.poll().lastError, name)
        }
    }

    func testRepliesInSingleByteChunksStillWork() throws {
        for name in Support.rigNames {
            if !name.hasPrefix("lx200") && !name.hasPrefix("nexstar") { continue }
            let rig = Support.rig(name, chunkSize: 1)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            let status = rig.controller.awaitSettled()
            guard case .arrived? = status.outcome else {
                XCTFail("\(name): \(String(describing: status.outcome))")
                continue
            }
            XCTAssertNil(rig.controller.poll().lastError, name)
        }
    }

    func testALateReplyOfAnEarlierCommandIsDiscarded() throws {
        let rig = Support.rig("lx200-onstep")
        try rig.controller.connect()
        rig.controller.poll()
        // A stray reply that arrived after its command timed out must not be read as the next answer.
        let simulator = try XCTUnwrap(rig.streamSimulator as? LX200Simulator)
        try simulator.send(MountText.ascii(":GVP#"))
        let status = rig.controller.poll()
        XCTAssertNil(status.lastError)
        XCTAssertEqual(try XCTUnwrap(status.position).angularSeparation(to: rig.mountJ2000()), 0.0, accuracy: 0.01)
    }

    func testBusyControllersAreRetriedAndGiveUpEventually() throws {
        let rig = Support.rig("lx200-onstep")
        let simulator = try XCTUnwrap(rig.streamSimulator as? LX200Simulator)
        simulator.busyReplies = 2
        try rig.controller.connect()
        XCTAssertEqual(rig.controller.status.phase, .idle)
        simulator.busyReplies = 4
        let status = rig.controller.poll()
        XCTAssertEqual(status.lastError, .busy)
        XCTAssertNil(rig.controller.poll().lastError)
    }

    func testADroppedConnectionIsReportedAsATransportError() throws {
        for name in Support.rigNames {
            if name.hasPrefix("alpaca") { continue }
            let rig = Support.rig(name)
            try rig.controller.connect()
            rig.streamSimulator?.inject(name.hasPrefix("lx200") ? "GR" : "e", .disconnect)
            let status = rig.controller.poll()
            XCTAssertTrue(try XCTUnwrap(status.lastError, name).isTransport, name)
            rig.controller.poll()
            XCTAssertEqual(rig.controller.poll().phase, .disconnected, name)
        }
    }

    // MARK: Failures around commands

    func testAGotoThatCannotBeConfirmedTriesToStopTheMount() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            try rig.controller.connect()
            if name.hasPrefix("lx200") {
                rig.streamSimulator?.inject("MS", .silence)
            } else if name.hasPrefix("nexstar") {
                rig.streamSimulator?.inject("r", .silence)
            } else {
                rig.alpacaSimulator?.inject("slewtocoordinatesasync", .timeout)
            }
            let error = try XCTUnwrap(mountError { try rig.controller.goto(Support.andromeda) }, name)
            XCTAssertTrue(error.isTimeout, name)
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
            XCTAssertGreaterThanOrEqual(rig.mount.stopsReceived, 1, name)
        }
    }

    func testAbortIsRepeatedWhenTheLinkFails() throws {
        for name in ["nexstar-celestron", "alpaca-topocentric"] {
            let rig = Support.rig(name)
            try rig.controller.connect()
            try rig.controller.goto(Support.andromeda)
            if name.hasPrefix("nexstar") {
                rig.streamSimulator?.inject("M", .silence, times: 2)
            } else {
                rig.alpacaSimulator?.inject("abortslew", .timeout, times: 2)
            }
            try rig.controller.abort()
            XCTAssertEqual(rig.controller.status.phase, .idle, name)
            XCTAssertFalse(rig.mount.isSlewing, name)

            let stubborn = Support.rig(name)
            try stubborn.controller.connect()
            try stubborn.controller.goto(Support.andromeda)
            if name.hasPrefix("nexstar") {
                stubborn.streamSimulator?.inject("M", .silence, times: 3)
            } else {
                stubborn.alpacaSimulator?.inject("abortslew", .timeout, times: 3)
            }
            XCTAssertTrue(try XCTUnwrap(mountError { try stubborn.controller.abort() }, name).isTimeout, name)
            // Still slewing as far as the controller knows; the abort can be repeated.
            XCTAssertEqual(stubborn.controller.status.phase, .slewing, name)
            try stubborn.controller.abort()
            XCTAssertEqual(stubborn.controller.status.phase, .idle, name)
            XCTAssertFalse(stubborn.mount.isSlewing, name)
        }
    }

    func testAConnectionThatFailsLeavesTheControllerDisconnected() throws {
        for name in Support.rigNames {
            let rig = Support.rig(name)
            if name.hasPrefix("lx200") {
                rig.streamSimulator?.inject("GR", .silence, times: 5)
            } else if name.hasPrefix("nexstar") {
                rig.streamSimulator?.inject("V", .silence, times: 5)
            } else {
                rig.alpacaSimulator?.inject("connected", .timeout, times: 5)
            }
            XCTAssertTrue(try XCTUnwrap(mountError { try rig.controller.connect() }, name).isTimeout, name)
            XCTAssertEqual(rig.controller.status.phase, .disconnected, name)
            XCTAssertNil(rig.controller.capabilities, name)
        }
    }
}

import XCTest
@testable import LodestarKit

/// A driver the test scripts and whose calls it records, for situations the simulators cannot produce: a stop that fails for one
/// direction only, a start that is refused after another direction was stopped, an abort that fails while the nudge stop works.
private final class MountSafetyScriptedDriver: MountDriver {
    /// The calls received, oldest first: "start north", "stop north", "abort", "slew".
    var calls: [String] = []
    /// Every `startNudge` fails with this while it is set.
    var startNudgeError: MountError?
    /// Every `abort` fails with this while it is set.
    var abortError: MountError?
    /// Stopping one of these directions fails with `stopNudgeError`.
    var failingStops: Set<MountNudgeDirection> = []
    var stopNudgeError = MountError.busy

    var kind: MountProtocol { .lx200 }
    var epoch: MountEpoch { .j2000 }

    func connect() throws -> MountCapabilities {
        MountCapabilities(kind: .lx200, name: "Scripted", firmware: nil, canSlew: true, canSync: true, canAbort: true,
                          canSetTracking: true, canNudge: true, canSetSiteAndTime: true, gotoNeedsAlignment: false, isAligned: true)
    }

    func disconnect() {}

    func readPosition() throws -> EquatorialCoordinate { EquatorialCoordinate(rightAscension: 100.0, declination: 20.0) }

    func readSlewing() throws -> Bool { false }

    func readTracking() throws -> Bool? { true }

    func readAligned() throws -> Bool? { true }

    func slew(to target: EquatorialCoordinate) throws { calls.append("slew") }

    func sync(to target: EquatorialCoordinate) throws { calls.append("sync") }

    func abort() throws {
        calls.append("abort")
        if let abortError { throw abortError }
    }

    func setTracking(_ enabled: Bool) throws {}

    func startNudge(direction: MountNudgeDirection, rate: MountNudgeRate, durationSeconds: Double) throws {
        calls.append("start \(direction.rawValue)")
        if let startNudgeError { throw startNudgeError }
    }

    func stopNudge(direction: MountNudgeDirection) throws {
        calls.append("stop \(direction.rawValue)")
        if failingStops.contains(direction) { throw stopNudgeError }
    }

    func setSiteAndTime(location: GeographicLocation, date: Date) throws {}
}

private struct MountSafetyScriptedRig {
    let driver: MountSafetyScriptedDriver
    let controller: MountController
    let clock: ManualMountClock
}

/// A connected controller on a scripted driver whose call record is empty.
private func mountSafetyScriptedRig() throws -> MountSafetyScriptedRig {
    let clock = ManualMountClock(start: MountTestSupport.start)
    let driver = MountSafetyScriptedDriver()
    let controller = MountController(driver: driver, observer: MountTestSupport.boulder, settings: .standard, clock: clock)
    try controller.connect()
    driver.calls.removeAll()
    return MountSafetyScriptedRig(driver: driver, controller: controller, clock: clock)
}

/// The stop logic of the controller: a nudge that replaces another one and cannot start, and an abort whose first step fails.
final class MountSafetyControllerTests: XCTestCase {
    private typealias Support = MountTestSupport

    // MARK: A nudge that replaces another one

    /// Old code: the nudge north is stopped and `nudgeDirection` cleared, the start east throws, and `phase` stays `.nudging` with no
    /// direction behind it. The phase check fails, and so would the goto (`.busy`).
    func testAReplacementNudgeThatCannotStartLeavesTheControllerIdle() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        XCTAssertEqual(rig.controller.status.phase, .nudging)
        rig.driver.startNudgeError = .rejected(detail: "refused")
        XCTAssertEqual(mountError { try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0) }, .rejected(detail: "refused"))
        XCTAssertEqual(rig.driver.calls, ["start north", "stop north", "start east", "stop east"])
        XCTAssertEqual(rig.controller.status.phase, .idle)
        XCTAssertEqual(rig.controller.status.lastError, .rejected(detail: "refused"))
        // Nothing runs, so Stop has nothing to do and sends nothing.
        try rig.controller.stopNudge()
        XCTAssertEqual(rig.driver.calls.count, 4)
        // The controller is free again.
        rig.driver.startNudgeError = nil
        try rig.controller.goto(Support.andromeda)
        XCTAssertEqual(rig.controller.status.phase, .slewing)
    }

    /// Pins the part that stays as it was: when the old direction cannot be stopped it still runs as far as anyone knows, so the
    /// controller keeps it and a later Stop sends the stop for it. The new nudge is never started.
    func testAReplacementNudgeWhoseOldDirectionCannotBeStoppedStaysStoppable() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        rig.driver.failingStops = [.north]
        XCTAssertEqual(mountError { try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0) }, .busy)
        XCTAssertEqual(rig.controller.status.phase, .nudging)
        XCTAssertEqual(rig.driver.calls, ["start north", "stop north"])
        rig.driver.failingStops = []
        try rig.controller.stopNudge()
        XCTAssertEqual(rig.driver.calls, ["start north", "stop north", "stop north"])
        XCTAssertEqual(rig.controller.status.phase, .idle)
    }

    /// The new move may be running although neither its start nor its stop was confirmed (a lost reply): it must stay on the books.
    /// Old code: `nudgeDirection` is nil after the failure, so `stopNudge()` returns at once and sends nothing.
    func testAMoveThatCannotBeStartedOrConfirmedStoppedStaysOnTheBooksForStop() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        rig.driver.startNudgeError = .timeout(operation: "move")
        rig.driver.failingStops = [.east]
        rig.driver.stopNudgeError = .timeout(operation: "stop")
        XCTAssertEqual(mountError { try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0) }, .timeout(operation: "move"))
        XCTAssertEqual(rig.controller.status.phase, .nudging)
        rig.driver.calls.removeAll()
        rig.driver.failingStops = []
        try rig.controller.stopNudge()
        XCTAssertEqual(rig.driver.calls, ["stop east"])
        XCTAssertEqual(rig.controller.status.phase, .idle)
    }

    /// The same situation, ended by the poll after the duration instead of by Stop. Old code: the poll needs a direction to end the
    /// nudge, finds none, and the phase stays `.nudging` for good.
    func testTheEndOfTheDurationStopsAMoveThatCouldNotBeConfirmedStopped() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.north, rate: .center, durationSeconds: 5.0)
        rig.driver.startNudgeError = .timeout(operation: "move")
        rig.driver.failingStops = [.east]
        rig.driver.stopNudgeError = .timeout(operation: "stop")
        XCTAssertEqual(mountError { try rig.controller.nudge(.east, rate: .center, durationSeconds: 5.0) }, .timeout(operation: "move"))
        rig.clock.advance(seconds: 6.0)
        rig.driver.calls.removeAll()
        rig.driver.failingStops = []
        let status = rig.controller.poll()
        XCTAssertEqual(rig.driver.calls, ["stop east"])
        XCTAssertEqual(status.phase, .idle)
    }

    /// Alpaca mount: a guide-rate pulse that the mount refuses replaces a running move. Old code: the move is stopped, and the
    /// controller stays in `.nudging` with no direction, so the goto is refused as busy.
    func testARefusedReplacementNudgeOnAlpacaLeavesTheControllerIdle() throws {
        let rig = Support.rig("alpaca-topocentric")
        try rig.controller.connect()
        try rig.controller.nudge(.north, rate: .find, durationSeconds: 5.0)
        XCTAssertTrue(rig.mount.isNudging)
        rig.alpacaSimulator?.inject("pulseguide", .error(number: 1025, message: "bad duration"))
        let error = try XCTUnwrap(mountError { try rig.controller.nudge(.east, rate: .guide, durationSeconds: 5.0) })
        XCTAssertTrue(error.isRejected)
        XCTAssertFalse(rig.mount.isNudging)
        XCTAssertEqual(rig.controller.status.phase, .idle)
        try rig.controller.goto(Support.andromeda)
        XCTAssertEqual(rig.controller.status.phase, .slewing)
    }

    // MARK: Abort

    /// Old code: the nudge is stopped only if the abort succeeded, so the calls end at "abort" and the nudge runs on.
    func testAbortStopsTheNudgeEvenWhenTheAbortFails() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.south, rate: .center, durationSeconds: 5.0)
        rig.driver.abortError = .rejected(detail: "jammed")
        XCTAssertEqual(mountError { try rig.controller.abort() }, .rejected(detail: "jammed"))
        XCTAssertEqual(rig.driver.calls, ["start south", "abort", "stop south"])
        // The failure leaves the phase alone, and the call can be repeated.
        XCTAssertEqual(rig.controller.status.phase, .nudging)
        XCTAssertEqual(rig.controller.status.lastError, .rejected(detail: "jammed"))
        rig.driver.abortError = nil
        try rig.controller.abort()
        XCTAssertEqual(rig.driver.calls, ["start south", "abort", "stop south", "abort", "stop south"])
        XCTAssertEqual(rig.controller.status.phase, .idle)
    }

    /// Both steps keep their three attempts on communication failures, and the failure of the abort (the first) is the one
    /// reported. Old code: only the three aborts are sent.
    func testAbortRepeatsBothStepsAndReportsTheFirstFailure() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.south, rate: .center, durationSeconds: 5.0)
        rig.driver.abortError = .timeout(operation: "abort")
        rig.driver.failingStops = [.south]
        rig.driver.stopNudgeError = .transport(detail: "gone")
        XCTAssertEqual(mountError { try rig.controller.abort() }, .timeout(operation: "abort"))
        XCTAssertEqual(rig.driver.calls, ["start south", "abort", "abort", "abort", "stop south", "stop south", "stop south"])
        XCTAssertEqual(rig.controller.status.phase, .nudging)
    }

    /// Pins the other order: the abort worked and the nudge stop failed, which is reported as before and leaves the phase alone.
    func testAbortReportsTheFailureOfTheNudgeStopWhenTheAbortWorked() throws {
        let rig = try mountSafetyScriptedRig()
        try rig.controller.nudge(.south, rate: .center, durationSeconds: 5.0)
        rig.driver.failingStops = [.south]
        XCTAssertEqual(mountError { try rig.controller.abort() }, .busy)
        XCTAssertEqual(rig.driver.calls, ["start south", "abort", "stop south"])
        XCTAssertEqual(rig.controller.status.phase, .nudging)
        rig.driver.failingStops = []
        try rig.controller.abort()
        XCTAssertEqual(rig.controller.status.phase, .idle)
    }

    /// NexStar and Alpaca: `abort` cancels only a GoTo. With the abort failing on every attempt the nudge is still stopped. The
    /// Alpaca simulator drops the failed `abortslew` before it acts, so its move keeps running on the old code; the NexStar
    /// simulator acts on a command whose reply it then drops, so there the stop that follows the aborts is looked for in the log.
    func testAbortStopsTheNudgeOfMountsWhoseAbortOnlyCancelsAGoTo() throws {
        let alpaca = Support.rig("alpaca-topocentric")
        try alpaca.controller.connect()
        try alpaca.controller.nudge(.south, rate: .slew, durationSeconds: 5.0)
        XCTAssertTrue(alpaca.mount.isNudging)
        alpaca.alpacaSimulator?.inject("abortslew", .timeout, times: 3)
        XCTAssertTrue(try XCTUnwrap(mountError { try alpaca.controller.abort() }).isTimeout)
        XCTAssertFalse(alpaca.mount.isNudging)
        XCTAssertEqual(alpaca.controller.status.phase, .nudging)
        try alpaca.controller.abort()
        XCTAssertEqual(alpaca.controller.status.phase, .idle)

        let nexStar = Support.rig("nexstar-celestron")
        try nexStar.controller.connect()
        try nexStar.controller.nudge(.south, rate: .slew, durationSeconds: 5.0)
        XCTAssertTrue(nexStar.mount.isNudging)
        let simulator = try XCTUnwrap(nexStar.streamSimulator)
        simulator.inject("M", .silence, times: 3)
        XCTAssertTrue(try XCTUnwrap(mountError { try nexStar.controller.abort() }).isTimeout)
        let log = simulator.commandLog
        let lastCancel = try XCTUnwrap(log.lastIndex(of: "M"))
        let lastMove = try XCTUnwrap(log.lastIndex(of: "P"))
        XCTAssertGreaterThan(lastMove, lastCancel, "\(log)")
        XCTAssertFalse(nexStar.mount.isNudging)
        XCTAssertEqual(nexStar.controller.status.phase, .nudging)
        try nexStar.controller.abort()
        XCTAssertEqual(nexStar.controller.status.phase, .idle)
    }
}

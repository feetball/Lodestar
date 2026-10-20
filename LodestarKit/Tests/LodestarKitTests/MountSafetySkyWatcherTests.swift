import XCTest
@testable import LodestarKit

/// The stop logic of the Sky-Watcher driver: a stop that fails on one axis, a disconnect with a stop still pending, and declaring the
/// home position when an axis does not answer. The injected faults replace a reply, not the command: the simulated controller has
/// carried the command out by then, so what the tests look at is what the driver sent (`commandLog`) and what it believes afterwards.
final class MountSafetySkyWatcherTests: XCTestCase {
    private typealias Support = SkyWatcherTestSupport

    private let altAz = SkyWatcherMountMode.altAzimuth
    private let equatorial = SkyWatcherMountMode.equatorial

    // MARK: Stopping both axes

    /// Old code: the stop of axis 1 throws and the loop ends, so the log has "K1" and never "K2".
    func testAStopThatFailsOnAxis1StillReachesAxis2() throws {
        let rig = Support.rig(mode: altAz)
        try rig.controller.connect()
        rig.simulator.inject("K1", .replace(text: "!2\r"))
        rig.simulator.clearLog()
        XCTAssertEqual(skyWatcherThrown { try rig.controller.abort() }, .busy)
        let log = rig.simulator.commandLog
        let first = try XCTUnwrap(log.firstIndex(of: "K1"), "\(log)")
        let second = try XCTUnwrap(log.firstIndex(of: "K2"), "\(log)")
        XCTAssertLessThan(first, second)
    }

    /// When both axes fail, the error of the first one is thrown.
    func testWhenBothStopsFailTheFirstErrorIsThrown() throws {
        let rig = Support.rig(mode: altAz)
        try rig.controller.connect()
        rig.simulator.inject("K1", .replace(text: "!2\r"))
        rig.simulator.inject("K2", .replace(text: "!5\r"))
        rig.simulator.clearLog()
        XCTAssertEqual(skyWatcherThrown { try rig.driver.abort() }, .busy)
        let log = rig.simulator.commandLog
        XCTAssertTrue(log.contains("K1") && log.contains("K2"), "\(log)")
    }

    /// A stop of axis 1 that gets no answer is tried the usual number of times, and axis 2 is stopped afterwards all the same.
    func testAStopOfAxis1ThatTimesOutStillReachesAxis2() throws {
        let rig = Support.rig(mode: altAz)
        try rig.controller.connect()
        rig.simulator.inject("K1", .silence, times: 3)
        rig.simulator.clearLog()
        XCTAssertTrue(skyWatcherThrown { try rig.driver.abort() }?.isTimeout == true)
        let log = rig.simulator.commandLog
        XCTAssertEqual(log.filter { $0 == "K1" }.count, 3, "\(log)")
        XCTAssertEqual(log.filter { $0 == "K2" }.count, 1, "\(log)")
    }

    // MARK: Disconnecting with a stop pending

    /// Sidereal tracking runs into the counterweight limit: tracking is switched off and the stop is left to the next poll. A
    /// disconnect before that poll must send it. Old code: `motion` is `.stopped` by then, so nothing is sent and axis 1 turns on at
    /// the sidereal rate with nobody to watch the limit.
    func testDisconnectStopsAnAxisWhoseStopWasStillPending() throws {
        let rig = Support.rig(mode: equatorial)
        try rig.controller.connect()
        try rig.controller.setTracking(true)
        XCTAssertTrue(rig.simulator.isMoving)
        // Sidereal tracking carries axis 1 past 95 degrees (90 plus the overlap of 5 and a quarter of a degree) in about 6.5 hours.
        rig.clock.advance(seconds: 25_000.0)
        _ = try rig.driver.readPosition()
        XCTAssertEqual(rig.driver.trackingStopReason, .outsideMountLimits)
        XCTAssertTrue(rig.simulator.isMoving, "the stop waits for the next poll")
        rig.controller.disconnect()
        rig.clock.advance(seconds: 2.0)
        XCTAssertFalse(rig.simulator.isMoving)
    }

    /// The other way to a pending stop: the stop that ends a nudge does not get through (the driver keeps it for the next poll).
    /// Old code sends nothing at the disconnect.
    func testDisconnectSendsTheStopOfANudgeThatDidNotGetThrough() throws {
        let rig = Support.rig(mode: altAz, settings: MountSettings(maximumNudgeSeconds: 30.0))
        try rig.controller.connect()
        // Due east and 40 degrees up: well away from every limit and from the pole.
        rig.simulator.placeAxes(axis1Degrees: 90.0, axis2Degrees: 40.0)
        try rig.controller.nudge(.east, rate: .find, durationSeconds: 30.0)
        XCTAssertTrue(rig.simulator.isMoving)
        rig.simulator.inject("K1", .silence, times: 3)
        // The controller repeats the stop; the driver has handed the unfinished stop to the next poll by then, so this returns.
        try rig.controller.stopNudge()
        XCTAssertEqual(rig.controller.status.phase, .idle)
        rig.simulator.clearLog()
        rig.controller.disconnect()
        let log = rig.simulator.commandLog
        XCTAssertTrue(log.contains("K1") && log.contains("K2"), "\(log)")
    }

    // MARK: Declaring the home position

    /// Old code: `E` reaches axis 1 (its zero moves) and axis 2 fails, so the alignment and the tracking are still in place.
    func testDeclaringHomeForgetsTheAlignmentAndTheTrackingEvenWhenAnAxisFails() throws {
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: -40.0, axis2Index: -10.0))
        rig.simulator.placeAxes(axis1Degrees: 40.0, axis2Degrees: 10.0)
        try rig.controller.connect()
        try rig.syncOn(Support.vega)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 1)
        try rig.controller.setTracking(true)
        XCTAssertEqual(try rig.driver.readTracking(), true)
        rig.simulator.inject("E2", .replace(text: "!2\r"))
        XCTAssertEqual(skyWatcherThrown { try rig.driver.declareHomePosition() }, .busy)
        // Axis 1 has its new zero, so the old model no longer fits the encoders.
        XCTAssertEqual(rig.simulator.axis1Degrees, 0.0, accuracy: 1e-3)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 0)
        XCTAssertNil(rig.driver.alignmentFit)
        XCTAssertEqual(try rig.driver.readAligned(), false)
        XCTAssertEqual(try rig.driver.readTracking(), false)
        XCTAssertEqual(skyWatcherThrown { try rig.controller.goto(Support.deneb) }, .notAligned)
        Support.poll(rig, seconds: 3)
        XCTAssertFalse(rig.simulator.isMoving)
    }

    /// Pins the other half: when the axes cannot even be stopped, no `E` is sent, no zero has moved and the alignment stays.
    func testDeclaringHomeKeepsTheAlignmentWhenTheAxesCannotBeStopped() throws {
        let rig = Support.rig(mode: altAz, errors: SkyWatcherPointingErrors(axis1Index: -40.0, axis2Index: -10.0))
        rig.simulator.placeAxes(axis1Degrees: 40.0, axis2Degrees: 10.0)
        try rig.controller.connect()
        try rig.syncOn(Support.vega)
        rig.simulator.inject("K1", .replace(text: "!2\r"))
        rig.simulator.clearLog()
        XCTAssertEqual(skyWatcherThrown { try rig.driver.declareHomePosition() }, .busy)
        XCTAssertEqual(rig.driver.alignmentPoints.count, 1)
        XCTAssertFalse(rig.simulator.commandLog.contains("E1") || rig.simulator.commandLog.contains("E2"))
    }
}

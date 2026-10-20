import LodestarKit
import XCTest
@testable import AppCore

/// Going to the background stops the mount also when the command that starts a move is still on its way: the controller's phase
/// becomes `.slewing` or `.nudging` only when the driver call returns, so at that moment it still says `.idle`.
extension MountServiceTests {
    func testGoingToTheBackgroundWhileACommandIsBeingSetUpStillStopsTheMount() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        let goTo = Task { await self.service.goTo(self.highTarget(), observer: self.observer) }
        await mountServiceExpect("the GoTo to be under way") { service.isWorking }
        XCTAssertEqual(service.status.phase, .idle, "as far as the controller knows nothing moves yet")
        helper.simulateBackground()
        // Give the handler time to call off the queued GoTo and to queue the stop, while the worker is still stuck.
        await settle()
        fake.readGate.open()
        await goTo.value
        await mountServiceExpect("the session to end") { service.connection != .connected }
        XCTAssertEqual(fake.abortCount, 1, "the GoTo may have started, so the mount is stopped anyway")
        XCTAssertTrue(fake.slews.isEmpty, "a GoTo that was still queued does not start after the stop")
        XCTAssertFalse(service.isWorking)
    }

    func testGoingToTheBackgroundWithANudgeHeldStillStopsTheMount() async throws {
        let helper = try lifecycle()
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        service.beginNudge(.north)
        // The first pulse waits behind the stuck poll: nothing has moved as far as the controller knows.
        await settle()
        XCTAssertEqual(service.status.phase, .idle)
        helper.simulateBackground()
        await settle()
        fake.readGate.open()
        await mountServiceExpect("the session to end") { service.connection != .connected }
        XCTAssertGreaterThanOrEqual(fake.abortCount, 1, "the pulse may have started, so the mount is stopped anyway")
        XCTAssertTrue(fake.nudgeStarts.isEmpty, "a pulse that was still queued does not start after the stop")
    }

    func testDisconnectingWithANudgeHeldStillStopsTheMount() async {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        service.beginNudge(.north)
        await settle()
        XCTAssertEqual(service.status.phase, .idle)
        service.disconnect()
        await settle()
        fake.readGate.open()
        await mountServiceExpect("the disconnection") { service.connection == .disconnected }
        XCTAssertGreaterThanOrEqual(fake.abortCount, 1, "the pulse may have started, so the mount is stopped anyway")
        XCTAssertTrue(fake.nudgeStarts.isEmpty, "a pulse that was still queued does not start after the disconnect")
    }
}

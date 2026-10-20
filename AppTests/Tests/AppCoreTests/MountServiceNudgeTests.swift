import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The nudge loop, the observer, the limits and the overlay direction of `MountService`.
/// The fixtures (`Fake`, `connectFake`, ...) are in MountServiceTests.swift.
extension MountServiceTests {
    // MARK: - The nudge loop

    func testHoldingAnArrowRepeatsTheNudge() async {
        let fake = await connectFake()
        service.beginNudge(.north)
        await mountServiceExpect("three pulses") { fake.nudgeStarts.count >= 3 }
        let first = fake.nudgeStarts[0]
        XCTAssertEqual(first.direction, .north)
        XCTAssertEqual(first.rate, .center)
        XCTAssertEqual(first.seconds, 0.5, accuracy: 1e-9)
        XCTAssertTrue(fake.nudgeStarts.allSatisfy { $0.direction == .north })
        XCTAssertNil(service.errorText)
        service.endNudge()
    }

    func testTheNudgeRateComesFromTheSettings() async {
        service.settings.nudgeRate = .find
        let fake = await connectFake()
        service.beginNudge(.west)
        await mountServiceExpect("the first pulse") { !fake.nudgeStarts.isEmpty }
        XCTAssertEqual(fake.nudgeStarts[0].rate, .find)
        XCTAssertEqual(fake.nudgeStarts[0].direction, .west)
        service.endNudge()
    }

    func testANudgeMakesTheMountMoving() async {
        await connectFake()
        service.beginNudge(.east)
        await mountServiceExpect("the mount to nudge") { self.service.status.phase == .nudging }
        XCTAssertTrue(service.isMoving)
        service.endNudge()
    }

    func testLiftingTheFingerStopsTheNudge() async {
        let fake = await connectFake()
        service.beginNudge(.south)
        await mountServiceExpect("the first pulse") { self.service.status.phase == .nudging }
        service.endNudge()
        await mountServiceExpect("the mount to stop") { self.service.status.phase == .idle }
        XCTAssertGreaterThanOrEqual(fake.nudgeStopCount, 1)
        // The pulse that may have been on its way is over; no further one comes.
        await settle(0.3)
        let pulses = fake.nudgeStarts.count
        await settle(1.0)
        XCTAssertEqual(fake.nudgeStarts.count, pulses, "no pulse follows the finger up")
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isMoving)
    }

    func testAPulseThatWaitedInTheQueueWhileTheFingerLiftedDoesNothing() async {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        service.beginNudge(.east)
        // The first pulse is queued behind the stuck poll by now.
        await settle()
        service.endNudge()
        await settle()
        fake.readGate.open()
        // A job queued after the pulse runs after it.
        await service.sendSiteAndTime(location: observer.location, announceSuccess: false)
        XCTAssertTrue(fake.nudgeStarts.isEmpty, "the pulse saw that the finger was up and did not start")
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertNil(service.errorText)
    }

    func testBeginningANewNudgeReplacesTheOldLoop() async {
        let fake = await connectFake()
        service.beginNudge(.north)
        await mountServiceExpect("a pulse to the north") { fake.nudgeStarts.contains { $0.direction == .north } }
        service.beginNudge(.south)
        await mountServiceExpect("two pulses to the south") { fake.nudgeStarts.filter { $0.direction == .south }.count >= 2 }
        await settle(0.3)
        let norths = fake.nudgeStarts.filter { $0.direction == .north }.count
        await settle(1.0)
        XCTAssertEqual(fake.nudgeStarts.filter { $0.direction == .north }.count, norths, "the old loop is gone")
        service.endNudge()
    }

    func testBeginningANudgeClearsTheLastError() async {
        let fake = await connectFake()
        fake.configure { $0.syncError = .rejected(detail: "no") }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertNotNil(service.errorText)
        service.beginNudge(.north)
        XCTAssertNil(service.errorText)
        service.endNudge()
    }

    func testANudgeThatFailsShowsTheErrorAndEndsTheLoop() async {
        let fake = await connectFake()
        fake.configure { $0.nudgeError = .busy }
        service.beginNudge(.north)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount is busy. Try again in a moment.")
        // The engine stops the direction it failed to start, once; a loop that went on would stop it again every 0.4 s.
        let stops = fake.nudgeStopCount
        XCTAssertEqual(stops, 1)
        await settle(1.0)
        XCTAssertEqual(fake.nudgeStopCount, stops)
        XCTAssertTrue(fake.nudgeStarts.isEmpty)
    }

    func testNoNudgeStartsWithoutAConnection() async {
        service.beginNudge(.north)
        await settle(0.1)
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.errorText)
        service.nudgeOnce(.north)
        await settle(0.1)
        XCTAssertNil(service.errorText)
    }

    func testNoNudgeStartsOnAMountThatCannotNudge() async {
        let fake = await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canNudge: false) }
        }
        service.beginNudge(.north)
        service.nudgeOnce(.south)
        await settle()
        XCTAssertTrue(fake.nudgeStarts.isEmpty)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testNoNudgeStartsWhileTheMountSlews() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        service.beginNudge(.north)
        await settle()
        XCTAssertTrue(fake.nudgeStarts.isEmpty)
        XCTAssertEqual(service.status.phase, .slewing)
    }

    func testLiftingTheFingerWithoutANudgeDoesNothing() async {
        let fake = await connectFake()
        service.endNudge()
        await settle()
        XCTAssertEqual(fake.nudgeStopCount, 0)
        XCTAssertEqual(fake.abortCount, 0)
    }

    func testNudgeOnceSendsASinglePulse() async {
        let fake = await connectFake()
        service.nudgeOnce(.west)
        await mountServiceExpect("the pulse") { !fake.nudgeStarts.isEmpty }
        await settle(1.0)
        XCTAssertEqual(fake.nudgeStarts.count, 1)
        XCTAssertEqual(fake.nudgeStarts[0].direction, .west)
        XCTAssertEqual(fake.nudgeStarts[0].rate, .center)
        XCTAssertEqual(fake.nudgeStarts[0].seconds, 0.5, accuracy: 1e-9)
        XCTAssertNil(service.errorText)
    }

    func testNudgeOnceShowsWhatTheMountRefuses() async {
        let fake = await connectFake()
        fake.configure { $0.nudgeError = .parked }
        service.nudgeOnce(.north)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount is parked. Unpark it first.")
    }

    // MARK: - Where the phone is

    func testTheObserverIsIgnoredWhenNothingChanged() async {
        let fake = await connectFake(lodestar: true)
        service.updateObserver(nil)
        service.updateObserver(observer)
        await settle()
        XCTAssertTrue(fake.siteLocations.isEmpty)
    }

    func testUpdatingTheObserverWithoutAConnectionIsHarmless() {
        service.updateObserver(Observer(location: GeographicLocation(latitude: 10.0, longitude: 20.0, elevation: 0.0)))
        XCTAssertEqual(service.connection, .disconnected)
        XCTAssertNil(service.errorText)
    }

    func testAMountThatLodestarAlignsIsHandedTheNewPlaceOnlyWhenThePhoneHasMoved() async {
        let fake = await connectFake(lodestar: true)
        let base = observer.location
        let jitter = Observer(location: GeographicLocation(latitude: base.latitude + 0.005, longitude: base.longitude,
                                                           elevation: base.elevation))
        let moved = Observer(location: GeographicLocation(latitude: base.latitude + 0.02, longitude: base.longitude,
                                                          elevation: base.elevation))
        // 0.005 degrees is a better GPS fix; 0.02 degrees is a move.
        service.updateObserver(jitter)
        service.updateObserver(moved)
        await mountServiceExpect("the new place to be sent") { !fake.siteLocations.isEmpty }
        await settle()
        XCTAssertEqual(fake.siteLocations, [moved.location])
    }

    func testTheDateLineIsNotAMoveForAMountThatLodestarAligns() async {
        let west = Observer(location: GeographicLocation(latitude: 35.0, longitude: 179.998, elevation: 0.0))
        let east = Observer(location: GeographicLocation(latitude: 35.0, longitude: -179.998, elevation: 0.0))
        let fake = await connectFake(lodestar: true, seenFrom: west)
        // 0.004 degrees apart across the date line.
        service.updateObserver(east)
        let moved = Observer(location: GeographicLocation(latitude: 35.0, longitude: -179.9, elevation: 0.0))
        service.updateObserver(moved)
        await mountServiceExpect("the new place to be sent") { !fake.siteLocations.isEmpty }
        await settle()
        XCTAssertEqual(fake.siteLocations, [moved.location])
    }

    func testAMountThatLodestarDoesNotAlignIsNeverHandedTheNewPlace() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        let far = Observer(location: GeographicLocation(latitude: 50.0, longitude: 8.0, elevation: 100.0))
        service.updateObserver(far)
        await settle()
        XCTAssertTrue(fake.siteLocations.isEmpty)
    }

    func testTheControllerChecksTargetsAgainstTheNewPlace() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        let target = highTarget()
        // The other side of the Earth: the target is below its horizon, 60 degrees down.
        let antipode = Observer(location: GeographicLocation(latitude: -observer.location.latitude,
                                                             longitude: observer.location.longitude + 180.0,
                                                             elevation: 0.0))
        service.updateObserver(antipode)
        await settle()
        // The check in the service uses the observer it is given; the engine's check uses the one it was told about.
        await service.goTo(target, observer: observer)
        let message = service.errorText ?? "nil"
        XCTAssertTrue(message.hasPrefix("The target is at -"), message)
        XCTAssertTrue(message.hasSuffix("\u{00B0}, below your altitude limit of 5.0\u{00B0}. Lodestar won't slew there."), message)
        XCTAssertTrue(fake.slews.isEmpty)
    }

    // MARK: - Limits that change

    func testChangingALimitRebuildsTheControllerOnceTheMountIsIdle() async {
        let fake = await connectFake()
        XCTAssertEqual(fake.connectCount, 1)
        service.settings.altitudeLimit = 20.0
        await mountServiceExpect("the controller to be rebuilt") { fake.connectCount == 2 }
        XCTAssertEqual(service.connection, .connected)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testASettingThatIsNotALimitDoesNotRebuildTheController() async {
        let fake = await connectFake()
        service.settings.nudgeRate = .slew
        await settle(1.6)
        XCTAssertEqual(fake.connectCount, 1)
    }

    func testTheControllerIsNotRebuiltWhileTheMountMoves() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        service.settings.altitudeLimit = 20.0
        // The rebuild looks at the mount a second later, then again every second: wait for three polls of the slew.
        let reads = fake.slewingReads
        await mountServiceExpect("three polls") { fake.slewingReads >= reads + 3 }
        XCTAssertEqual(fake.connectCount, 1, "the controller keeps its limits until the mount is idle")
        service.stop()
        await mountServiceExpect("the controller to be rebuilt after the stop") { fake.connectCount == 2 }
        let events = fake.events
        let abortIndex = events.firstIndex(of: .abort)
        let secondConnect = events.lastIndex(of: .connect)
        XCTAssertNotNil(abortIndex)
        XCTAssertNotNil(secondConnect)
        if let abortIndex, let secondConnect { XCTAssertLessThan(abortIndex, secondConnect) }
    }

    func testALimitThatCannotBeSentIsReported() async {
        let fake = await connectFake()
        fake.configure { $0.connectError = .rejected(detail: "no") }
        service.settings.altitudeLimit = 25.0
        await mountServiceExpect("the report") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText,
                       "The new limits could not be sent to the mount's controller. The mount rejected the command: no.")
        XCTAssertEqual(service.connection, .connected, "the session goes on with the old limits")
        XCTAssertEqual(service.status.phase, .idle)
    }

    // MARK: - The overlay

    func testTheOverlayHasNoDirectionWithoutAConnection() {
        XCTAssertNil(service.overlayDirection(observer: observer, at: Date(timeIntervalSince1970: 1_792_296_000.0)))
    }

    func testTheOverlayPointsWhereTheMountPoints() async throws {
        await connectFake()
        let date = Date(timeIntervalSince1970: 1_792_296_000.0)
        let result = try XCTUnwrap(service.overlayDirection(observer: observer, at: date))
        let place = EquatorialCoordinate(rightAscension: 100.0, declination: 20.0)
        let expected = SkyFrame(date: date, observer: observer).horizontal(j2000: place, refraction: true).unitVector
        XCTAssertEqual(result.direction.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(result.direction.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(result.direction.z, expected.z, accuracy: 1e-12)
        XCTAssertFalse(result.isMoving)
    }

    func testTheOverlayDirectionIsWorkedOutOncePerSecondAndObserver() async throws {
        await connectFake()
        let base = Date(timeIntervalSince1970: 1_792_296_000.0)
        let first = try XCTUnwrap(service.overlayDirection(observer: observer, at: base.addingTimeInterval(0.1)))
        let sameSecond = try XCTUnwrap(service.overlayDirection(observer: observer, at: base.addingTimeInterval(0.9)))
        let nextSecond = try XCTUnwrap(service.overlayDirection(observer: observer, at: base.addingTimeInterval(1.1)))
        XCTAssertEqual(first.direction, sameSecond.direction, "the result of the first call is kept for the whole second")
        XCTAssertNotEqual(first.direction, nextSecond.direction)
        let other = Observer(location: GeographicLocation(latitude: -20.0, longitude: 30.0, elevation: 0.0))
        let elsewhere = try XCTUnwrap(service.overlayDirection(observer: other, at: base.addingTimeInterval(1.2)))
        XCTAssertNotEqual(nextSecond.direction, elsewhere.direction)
    }

    func testTheOverlayKnowsWhenTheMountIsMoving() async throws {
        await connectFake()
        await service.goTo(highTarget(), observer: observer)
        let result = try XCTUnwrap(service.overlayDirection(observer: observer, at: Date(timeIntervalSince1970: 1_792_296_000.0)))
        XCTAssertTrue(result.isMoving)
    }
}

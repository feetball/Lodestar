import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The commands of `MountService`: why a GoTo or a sync is not offered, GoTo, sync, Stop, tracking, the site and time.
/// The fixtures (`Fake`, `connectFake`, ...) are in MountServiceTests.swift.
extension MountServiceTests {
    private static let notConnectedText = "The mount is not connected."
    private static let slewingText = "The mount is already slewing. Stop it before starting another move."
    private static let busyText = "The mount is busy. Try again in a moment."

    // MARK: - Why a GoTo is not offered

    func testGoToAndSyncAreUnavailableWithoutAConnection() {
        let target = highTarget()
        XCTAssertEqual(service.goToUnavailableReason(for: target, observer: observer), Self.notConnectedText)
        XCTAssertEqual(service.goToUnavailableReason(for: nil, observer: nil), Self.notConnectedText)
        XCTAssertEqual(service.syncUnavailableReason(for: target), Self.notConnectedText)
        XCTAssertEqual(service.syncUnavailableReason(for: nil), Self.notConnectedText)
    }

    func testGoToIsUnavailableForAMountThatCannotSlew() async {
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSlew: false) }
        }
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer),
                       "This mount doesn't support slewing to coordinates.")
    }

    func testSyncIsUnavailableForAMountThatCannotSync() async {
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSync: false) }
        }
        XCTAssertEqual(service.syncUnavailableReason(for: highTarget()), "This mount doesn't support syncing to a position.")
        // It can still slew.
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
    }

    func testGoToAndSyncNeedATarget() async {
        await connectFake()
        XCTAssertEqual(service.goToUnavailableReason(for: nil, observer: observer), "Choose a target first.")
        XCTAssertEqual(service.syncUnavailableReason(for: nil), "Choose a target first.")
    }

    func testTheSunIsNeverATarget() async throws {
        let sun = try XCTUnwrap(Self.sun)
        await connectFake()
        XCTAssertEqual(service.goToUnavailableReason(for: sun, observer: observer), MountTargets.sunRefusal)
        XCTAssertEqual(service.goToUnavailableReason(for: sun, observer: nil), MountTargets.sunRefusal)
        XCTAssertEqual(service.syncUnavailableReason(for: sun), MountTargets.sunRefusal)
        XCTAssertTrue(MountTargets.sunRefusal.hasPrefix("Lodestar never slews a mount to the Sun."))
    }

    func testAHighTargetIsAvailableForGoToAndSync() async {
        await connectFake()
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
        XCTAssertNil(service.syncUnavailableReason(for: highTarget()))
    }

    func testATargetBelowTheAltitudeLimitIsRefused() async {
        await connectFake()
        let below = service.goToUnavailableReason(for: Self.target(altitude: -30.0, seenFrom: observer), observer: observer)
        XCTAssertEqual(below, "The target is at -30.0\u{00B0}, below your altitude limit of 5.0\u{00B0}. Lodestar won't slew there.")
        // The default limit is 5 degrees: 4 degrees is below it and 6 degrees is above it.
        let low = service.goToUnavailableReason(for: Self.target(altitude: 4.0, seenFrom: observer), observer: observer)
        XCTAssertEqual(low, "The target is at 4.0\u{00B0}, below your altitude limit of 5.0\u{00B0}. Lodestar won't slew there.")
        XCTAssertNil(service.goToUnavailableReason(for: Self.target(altitude: 6.0, seenFrom: observer), observer: observer))
    }

    func testTheAltitudeLimitComesFromTheSettings() async {
        service.settings.altitudeLimit = 45.0
        await connectFake()
        let refused = service.goToUnavailableReason(for: Self.target(altitude: 30.0, seenFrom: observer), observer: observer)
        XCTAssertEqual(refused, "The target is at 30.0\u{00B0}, below your altitude limit of 45.0\u{00B0}. Lodestar won't slew there.")
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
    }

    func testWithoutAnObserverTheAltitudeIsLeftToTheEngine() async {
        await connectFake()
        XCTAssertNil(service.goToUnavailableReason(for: Self.target(altitude: -30.0, seenFrom: observer), observer: nil))
    }

    func testATargetNearTheSunIsRefusedWhileTheSunIsUp() async throws {
        let sun = try XCTUnwrap(Self.sun)
        let day = Self.placeOnEarth(sunUp: true)
        await connectFake()
        let place = MountTargets.resolve(sun, observer: day, date: Date()).j2000
        let onTheSun = CelestialObject.custom(name: "On the Sun", j2000: place)
        let reason = service.goToUnavailableReason(for: onTheSun, observer: day) ?? "nil"
        XCTAssertTrue(reason.hasPrefix("The target is 0."), reason)
        XCTAssertTrue(reason.hasSuffix("\u{00B0} from the Sun, closer than the 15\u{00B0} safety limit. Lodestar won't slew there."),
                      reason)
    }

    func testTheSunExclusionZoneEndsFifteenDegreesFromTheSun() async throws {
        let day = Self.placeOnEarth(sunUp: true)
        await connectFake()
        let sun = SkyFrame(date: Date(), observer: day).horizontal(of: .sun, refraction: false)
        // Straight below the Sun, so that both targets stay above the altitude limit.
        let near = Self.target(altitude: sun.altitude - 14.0, azimuth: sun.azimuth, name: "Near", seenFrom: day)
        let far = Self.target(altitude: sun.altitude - 16.0, azimuth: sun.azimuth, name: "Far", seenFrom: day)
        let refused = service.goToUnavailableReason(for: near, observer: day) ?? "nil"
        XCTAssertTrue(refused.hasPrefix("The target is 14.0\u{00B0} from the Sun, closer than the 15\u{00B0} safety limit."),
                      refused)
        XCTAssertNil(service.goToUnavailableReason(for: far, observer: day))
    }

    func testTheSunZoneDoesNotApplyWhileTheSunIsDown() async throws {
        let sun = try XCTUnwrap(Self.sun)
        await connectFake()
        // The Sun is far below the horizon for this observer: the target on it is refused for its altitude, not for the Sun.
        let place = MountTargets.resolve(sun, observer: observer, date: Date()).j2000
        let onTheSun = CelestialObject.custom(name: "On the Sun", j2000: place)
        let reason = service.goToUnavailableReason(for: onTheSun, observer: observer) ?? "nil"
        XCTAssertTrue(reason.hasPrefix("The target is at -"), reason)
        XCTAssertTrue(reason.contains("below your altitude limit"), reason)
        XCTAssertFalse(reason.contains("Sun"), reason)
    }

    func testGoToWaitsForAMountThatIsNotAligned() async {
        let fake = await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(gotoNeedsAlignment: true, isAligned: false) }
        }
        XCTAssertEqual(service.alignmentWarning, "The mount is not aligned. Align it on the hand controller, then continue.")
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), MountError.notAligned.userMessage)
        XCTAssertEqual(MountError.notAligned.userMessage,
                       "The mount is not aligned. Do a star alignment on the mount first, then try again.")
        // The sync is what aligns it, so it stays available.
        XCTAssertNil(service.syncUnavailableReason(for: highTarget()))
        fake.configure { $0.aligned = true }
        await mountServiceExpect("the next poll to report the alignment") { service.alignmentWarning == nil }
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
    }

    func testAMountThatDoesNotSayWhetherItIsAlignedIsNotHeldBack() async {
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(gotoNeedsAlignment: true, isAligned: nil) }
        }
        XCTAssertNil(service.alignmentWarning)
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
    }

    func testAMountThatNeedsNoAlignmentIsNotHeldBackButStillWarned() async {
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(gotoNeedsAlignment: false, isAligned: false) }
        }
        XCTAssertNil(service.goToUnavailableReason(for: highTarget(), observer: observer))
        XCTAssertNotNil(service.alignmentWarning)
    }

    func testNoMoveIsOfferedWhileTheMountSlews() async {
        await connectFake()
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), Self.slewingText)
        XCTAssertEqual(service.syncUnavailableReason(for: highTarget()), Self.slewingText)
    }

    func testNoMoveIsOfferedWhileTheMountNudges() async {
        await connectFake()
        service.nudgeOnce(.north)
        await mountServiceExpect("the nudge to start") { service.status.phase == .nudging }
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), Self.busyText)
        XCTAssertEqual(service.syncUnavailableReason(for: highTarget()), Self.busyText)
    }

    // MARK: - GoTo

    func testGoToSlewsTheMountToTheTarget() async throws {
        let fake = await connectFake()
        let target = highTarget("Capella")
        let place = try XCTUnwrap(target.j2000)
        let announced = MountLifecycle.announcements.count
        await service.goTo(target, observer: observer)
        XCTAssertEqual(fake.slews, [place])
        XCTAssertEqual(service.slewTargetName, "Capella")
        XCTAssertEqual(service.status.phase, .slewing)
        XCTAssertEqual(service.status.target, place)
        XCTAssertTrue(service.isMoving)
        XCTAssertFalse(service.isWorking)
        XCTAssertNil(service.errorText)
        let expectedStart = EquatorialCoordinate(rightAscension: 100.0, declination: 20.0).angularSeparation(to: place)
        XCTAssertEqual(try XCTUnwrap(service.slewStartSeparation), expectedStart, accuracy: 1e-9)
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing"])
    }

    func testASlewThatArrivesIsAnnounced() async throws {
        let fake = await connectFake()
        let target = highTarget("Capella")
        let place = try XCTUnwrap(target.j2000)
        let announced = MountLifecycle.announcements.count
        await service.goTo(target, observer: observer)
        fake.finishSlew()
        await mountServiceExpect("the next poll to see the arrival") { service.status.phase == .idle }
        if case .arrived(let separation)? = service.status.outcome {
            XCTAssertLessThan(separation, 0.25)
        } else {
            XCTFail("the slew did not arrive: \(String(describing: service.status.outcome))")
        }
        XCTAssertEqual(service.status.position, place)
        XCTAssertFalse(service.isMoving)
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing", "Arrived"])
    }

    func testAMountThatStopsShortOfTheTargetIsAnnounced() async {
        let fake = await connectFake()
        let announced = MountLifecycle.announcements.count
        await service.goTo(highTarget(), observer: observer)
        // Two polls have seen the mount moving; then it stops by itself, far from the target.
        let reads = fake.slewingReads
        await mountServiceExpect("two polls during the slew") { fake.slewingReads >= reads + 2 }
        fake.stopShort()
        await mountServiceExpect("the next poll to see the stop") { service.status.phase == .idle }
        var stoppedShort = false
        if case .failed(let error)? = service.status.outcome, case .slewStopped = error { stoppedShort = true }
        XCTAssertTrue(stoppedShort, "outcome \(String(describing: service.status.outcome))")
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing", "Stopped short of the target"])
    }

    func testGoToReportsWhatTheMountRefuses() async {
        let fake = await connectFake()
        fake.configure { $0.slewError = .mountHorizonLimit }
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "The target is below the mount's horizon limit.")
        XCTAssertNil(service.slewTargetName)
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isWorking)
        XCTAssertTrue(fake.slews.isEmpty)
    }

    func testAnUnalignedMountThatRefusesAGoToIsExplained() async {
        let fake = await connectFake()
        fake.configure { $0.slewError = .notAligned }
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "The mount is not aligned. Do a star alignment on the mount first, then try again.")
    }

    func testGoToChecksTheTargetBeforeTheEngineSeesIt() async {
        let fake = await connectFake()
        await service.goTo(Self.target(altitude: -30.0, seenFrom: observer), observer: observer)
        XCTAssertEqual(service.errorText,
                       "The target is at -30.0\u{00B0}, below your altitude limit of 5.0\u{00B0}. Lodestar won't slew there.")
        XCTAssertTrue(fake.slews.isEmpty)
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isWorking)
    }

    func testGoToRefusesTheSun() async throws {
        let sun = try XCTUnwrap(Self.sun)
        let fake = await connectFake()
        await service.goTo(sun, observer: observer)
        XCTAssertEqual(service.errorText, MountTargets.sunRefusal)
        XCTAssertTrue(fake.slews.isEmpty)
    }

    func testATargetNearTheSunIsNotSlewedTo() async throws {
        let sun = try XCTUnwrap(Self.sun)
        let day = Self.placeOnEarth(sunUp: true)
        let fake = await connectFake(seenFrom: day)
        let place = MountTargets.resolve(sun, observer: day, date: Date()).j2000
        await service.goTo(CelestialObject.custom(name: "On the Sun", j2000: place), observer: day)
        let message = service.errorText ?? "nil"
        XCTAssertTrue(message.hasPrefix("The target is 0."), message)
        XCTAssertTrue(message.contains("from the Sun, closer than the 15"), message)
        XCTAssertTrue(fake.slews.isEmpty)
    }

    func testGoToWithoutAConnectionDoesNothing() async {
        await service.goTo(highTarget(), observer: observer)
        XCTAssertNil(service.errorText, "nothing was asked of a mount that is not there")
        XCTAssertFalse(service.isWorking)
    }

    func testGoToClearsTheMessagesOfEarlierActions() async {
        let fake = await connectFake()
        fake.configure { $0.syncError = .rejected(detail: "no") }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertNotNil(service.errorText)
        await service.goTo(highTarget(), observer: observer)
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
    }

    func testIsWorkingWhileAGoToWaitsForTheMount() async {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        let running = Task { await self.service.goTo(self.highTarget(), observer: self.observer) }
        await mountServiceExpect("the GoTo to be under way") { service.isWorking }
        XCTAssertFalse(service.isMoving, "the mount has not been asked yet")
        fake.readGate.open()
        await running.value
        XCTAssertFalse(service.isWorking)
        XCTAssertTrue(service.isMoving)
        XCTAssertEqual(fake.slews.count, 1)
    }

    func testASecondGoToWhileOneIsUnderWayIsIgnored() async {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        let second = Self.target(altitude: 50.0, azimuth: 150.0, name: "Second", seenFrom: observer)
        let running = Task { await self.service.goTo(self.highTarget("First"), observer: self.observer) }
        await mountServiceExpect("the first GoTo to be under way") { service.isWorking }
        await service.goTo(second, observer: observer)
        fake.readGate.open()
        await running.value
        XCTAssertEqual(fake.slews.count, 1)
        XCTAssertEqual(service.slewTargetName, "First")
        XCTAssertFalse(service.isWorking)
    }

    func testAGoToThatWaitedWhileStopWasTappedDoesNotStartTheSlew() async {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        let running = Task { await self.service.goTo(self.highTarget(), observer: self.observer) }
        await mountServiceExpect("the GoTo to be under way") { service.isWorking }
        service.stop()
        await settle()
        fake.readGate.open()
        await running.value
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertTrue(fake.slews.isEmpty)
        XCTAssertNil(service.slewTargetName)
        XCTAssertNil(service.errorText, "the person knows, so a cancelled GoTo reports nothing")
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isWorking)
    }

    // MARK: - Stop

    func testStopHaltsAnIdleMount() async {
        let fake = await connectFake()
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping && self.service.noticeText != nil }
        XCTAssertEqual(service.noticeText, "Stopped.")
        XCTAssertNil(service.errorText)
        XCTAssertEqual(fake.abortCount, 1)
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertEqual(service.connection, .connected)
    }

    func testStopIsMarkedAtOnce() async {
        await connectFake()
        service.stop()
        XCTAssertTrue(service.isStopping)
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
    }

    func testStopHaltsASlew() async {
        let fake = await connectFake()
        let announced = MountLifecycle.announcements.count
        await service.goTo(highTarget(), observer: observer)
        XCTAssertTrue(service.isMoving)
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertEqual(service.status.outcome, .aborted)
        XCTAssertFalse(service.isMoving)
        XCTAssertEqual(service.noticeText, "Stopped.")
        XCTAssertEqual(fake.abortCount, 1)
        XCTAssertEqual(Array(MountLifecycle.announcements.dropFirst(announced)), ["Slewing", "Stopped"])
    }

    func testStopHaltsANudge() async {
        let fake = await connectFake()
        service.nudgeOnce(.east)
        await mountServiceExpect("the nudge to start") { service.status.phase == .nudging }
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertFalse(service.isMoving)
        XCTAssertEqual(fake.abortCount, 1)
        XCTAssertTrue(fake.events.contains(.nudgeStop(.east)))
    }

    func testStopClearsAnEarlierError() async {
        let fake = await connectFake()
        fake.configure { $0.syncError = .rejected(detail: "no") }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertNotNil(service.errorText)
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.noticeText, "Stopped.")
    }

    func testAStopThatFailsSaysTheMountMayStillBeMoving() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        fake.configure { $0.abortError = .rejected(detail: "jammed") }
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertEqual(service.errorText, "The mount may still be moving. The mount rejected the command: jammed. "
            + "Stop it on its hand controller or switch it off.")
        XCTAssertNil(service.noticeText)
        XCTAssertEqual(service.status.phase, .slewing, "the engine leaves the phase alone, so Stop can be tried again")
        XCTAssertEqual(fake.abortCount, 1)
    }

    func testAStopIsRepeatedWhenTheLinkFails() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        fake.configure { $0.abortError = .timeout(operation: "stop") }
        service.stop()
        await mountServiceExpect("the stop to finish") { !self.service.isStopping }
        XCTAssertEqual(fake.abortCount, 3, "the engine tries three times on communication failures")
        XCTAssertEqual(service.errorText, "The mount may still be moving. The mount didn't answer in time (stop). "
            + "Stop it on its hand controller or switch it off.")
    }

    func testStopGoesBeforeTheCommandsThatAreWaiting() async throws {
        let fake = await connectFake()
        fake.readGate.close()
        await mountServiceExpect("a poll to be stuck") { fake.readGate.isWaiting }
        service.setTracking(true)
        service.stop()
        // Both jobs are queued behind the stuck poll by now.
        await settle()
        fake.readGate.open()
        await mountServiceExpect("both commands to run") { fake.trackingCalls == [true] && !self.service.isStopping }
        let events = fake.events
        let abortIndex = try XCTUnwrap(events.firstIndex(of: .abort))
        let trackingIndex = try XCTUnwrap(events.firstIndex(of: .tracking(true)))
        XCTAssertLessThan(abortIndex, trackingIndex, "Stop is urgent and jumps the queue: \(events)")
    }

    func testStopAfterALostConnectionDoesNothing() async {
        let fake = await connectFake()
        fake.configure { $0.readError = .timeout(operation: "position") }
        await mountServiceExpect("the loss of the connection", timeout: 30.0) { self.service.connection != .connected }
        let lost = service.connection
        service.stop()
        XCTAssertEqual(service.connection, lost)
        XCTAssertFalse(service.isStopping)
    }

    func testNoticesCanBeDismissed() async {
        await connectFake()
        service.stop()
        await mountServiceExpect("the notice") { self.service.noticeText == "Stopped." }
        service.dismissNotice()
        XCTAssertNil(service.noticeText)
    }

    // MARK: - Sync

    func testSyncTellsTheMountItPointsAtTheTarget() async {
        let fake = await connectFake { fake in
            fake.configure { $0.position = EquatorialCoordinate(rightAscension: 10.0, declination: 0.0) }
        }
        let place = EquatorialCoordinate(rightAscension: 10.0, declination: 5.0)
        await service.syncMount(to: CelestialObject.custom(name: "Alpha Test", j2000: place), observer: observer)
        XCTAssertEqual(fake.syncs, [place])
        XCTAssertEqual(service.noticeText, "Synced (was 5.0\u{00B0} off).")
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.status.position, place)
        XCTAssertFalse(service.isWorking)
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testSyncOnAMountThatLodestarDoesNotAlignRemembersNothing() async {
        await connectFake()
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
    }

    func testAnOffsetBeyondTheLimitIsRefused() async {
        service.settings.maximumSyncOffset = 1.0
        let fake = await connectFake { fake in
            fake.configure { $0.position = EquatorialCoordinate(rightAscension: 10.0, declination: 0.0) }
        }
        let far = CelestialObject.custom(name: "Far", j2000: EquatorialCoordinate(rightAscension: 10.0, declination: 5.0))
        await service.syncMount(to: far, observer: observer)
        XCTAssertEqual(service.errorText, "The mount points 5.0\u{00B0} away from that star, more than the allowed 1\u{00B0}. "
            + "Check that you centred the right star.")
        XCTAssertTrue(fake.syncs.isEmpty)
        XCTAssertNil(service.noticeText)
        // A star within the limit goes through.
        let near = CelestialObject.custom(name: "Near", j2000: EquatorialCoordinate(rightAscension: 10.0, declination: 0.5))
        await service.syncMount(to: near, observer: observer)
        XCTAssertEqual(fake.syncs.count, 1)
        XCTAssertEqual(service.noticeText, "Synced (was 30\u{2032} off).")
        XCTAssertNil(service.errorText)
    }

    func testSyncReportsWhatTheMountRefuses() async {
        let fake = await connectFake()
        fake.configure { $0.syncError = .rejected(detail: "not now") }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "The mount rejected the command: not now.")
        XCTAssertNil(service.noticeText)
        XCTAssertFalse(service.isWorking)
    }

    func testSyncIsRefusedWhileTheMountSlews() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, Self.slewingText)
        XCTAssertTrue(fake.syncs.isEmpty)
    }

    func testSyncRefusesTheSun() async throws {
        let sun = try XCTUnwrap(Self.sun)
        let fake = await connectFake()
        await service.syncMount(to: sun, observer: observer)
        XCTAssertEqual(service.errorText, MountTargets.sunRefusal)
        XCTAssertTrue(fake.syncs.isEmpty)
    }

    func testSyncWithoutAConnectionDoesNothing() async {
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
    }

    func testSyncOnAMountThatCannotSyncSaysSo() async {
        let fake = await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSync: false) }
        }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "This mount doesn't support syncing to a position.")
        XCTAssertTrue(fake.syncs.isEmpty)
    }

    // MARK: - Tracking

    func testTrackingCanBeSwitchedOffAndOn() async {
        let fake = await connectFake()
        XCTAssertEqual(service.trackingLine, "Tracking")
        service.setTracking(false)
        await mountServiceExpect("the notice") { self.service.noticeText == "Tracking is off." }
        XCTAssertEqual(fake.trackingCalls, [false])
        XCTAssertEqual(service.trackingLine, "Tracking is off")
        XCTAssertEqual(service.trackingAndPierLine, "Tracking is off")
        service.setTracking(true)
        await mountServiceExpect("the notice") { self.service.noticeText == "Tracking is on." }
        XCTAssertEqual(fake.trackingCalls, [false, true])
        XCTAssertEqual(service.trackingLine, "Tracking")
    }

    func testTrackingLineIsEmptyWhenTheMountDoesNotSay() async {
        await connectFake { fake in
            fake.configure { $0.tracking = nil }
        }
        XCTAssertNil(service.status.isTracking)
        XCTAssertNil(service.trackingLine)
        XCTAssertNil(service.trackingAndPierLine)
    }

    func testTrackingErrorsAreShown() async {
        let fake = await connectFake()
        fake.configure { $0.trackingError = .parked }
        service.setTracking(true)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "The mount is parked. Unpark it first.")
        XCTAssertNil(service.noticeText)
    }

    func testTrackingCannotBeChangedOnAMountThatLacksIt() async {
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSetTracking: false) }
        }
        service.setTracking(false)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, "This mount doesn't support switching tracking on and off.")
    }

    func testTrackingCannotBeChangedDuringASlew() async {
        let fake = await connectFake()
        await service.goTo(highTarget(), observer: observer)
        service.setTracking(false)
        await mountServiceExpect("the error") { self.service.errorText != nil }
        XCTAssertEqual(service.errorText, Self.slewingText)
        XCTAssertTrue(fake.trackingCalls.isEmpty)
    }

    func testSettingTrackingWithoutAConnectionDoesNothing() {
        service.setTracking(true)
        XCTAssertNil(service.noticeText)
        XCTAssertNil(service.errorText)
    }

    // MARK: - Site and time

    func testTheSiteAndTimeCanBeSentOnRequest() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        let place = GeographicLocation(latitude: 47.6, longitude: -122.3, elevation: 50.0)
        await service.sendSiteAndTime(location: place)
        XCTAssertEqual(fake.siteLocations, [place])
        XCTAssertEqual(service.noticeText, "Location and time sent to the mount.")
        XCTAssertNil(service.errorText)
    }

    func testTheSiteAndTimeCanBeSentWithoutAConfirmation() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        let place = GeographicLocation(latitude: 47.6, longitude: -122.3, elevation: 50.0)
        await service.sendSiteAndTime(location: place, announceSuccess: false)
        XCTAssertEqual(fake.siteLocations, [place])
        XCTAssertNil(service.noticeText)
    }

    func testAFailedSendOfTheSiteAndTimeIsExplained() async {
        service.settings.sendsSiteAndTime = false
        let fake = await connectFake()
        fake.configure { $0.siteError = .timeout(operation: "set time") }
        await service.sendSiteAndTime(location: observer.location)
        XCTAssertEqual(service.errorText, "Could not send the location and time. The mount didn't answer in time (set time).")
        XCTAssertNil(service.noticeText)
    }

    func testAMountThatCannotTakeTheSiteAndTimeSaysSo() async {
        service.settings.sendsSiteAndTime = false
        await connectFake { fake in
            fake.configure { $0.capabilities = Fake.makeCapabilities(canSetSiteAndTime: false) }
        }
        await service.sendSiteAndTime(location: observer.location)
        XCTAssertEqual(service.errorText,
                       "Could not send the location and time. This mount doesn't support setting the site and time.")
    }

    func testSendingTheSiteAndTimeWithoutAConnectionDoesNothing() async {
        await service.sendSiteAndTime(location: observer.location)
        XCTAssertNil(service.noticeText)
        XCTAssertNil(service.errorText)
    }

    // MARK: - Centring the simulated mount

    func testTheSimulatedSkyWatcherIsCentredOnATargetBetweenTwoStops() async throws {
        let fake = Fake()
        fakes.append(fake)
        let placed = Recorder()
        let option = Self.option(for: fake, centre: { place in
            placed.add("\(place.rightAscension) \(place.declination)")
        })
        service.connectDemo(option, observer: observer)
        await mountServiceExpect("the connection") { self.service.connection == .connected }
        let target = highTarget("Centred")
        let place = try XCTUnwrap(target.j2000)
        await service.centreSimulatedMount(on: target, observer: observer)
        XCTAssertEqual(placed.all, ["\(place.rightAscension) \(place.declination)"])
        XCTAssertEqual(fake.abortCount, 2, "the axes stop before and after the telescope is turned")
        XCTAssertNil(service.errorText)
        XCTAssertFalse(service.isWorking)
    }

    func testAMountThatCannotBeCentredReportsIt() async {
        await connectFake()
        await service.centreSimulatedMount(on: highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "This mount doesn't support this operation.")
        XCTAssertFalse(service.isWorking)
    }

    func testCentringNeedsAConnection() async {
        await service.centreSimulatedMount(on: highTarget(), observer: observer)
        XCTAssertNil(service.errorText)
    }
}

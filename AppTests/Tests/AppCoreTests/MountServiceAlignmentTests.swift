import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The alignment of a mount that Lodestar aligns itself (Sky-Watcher Wi-Fi): with a scripted driver for what depends only on
/// the service, with the app's own simulated Sky-Watcher (`MountConnectionOption.demoSkyWatcher`) for what needs a real
/// alignment model, and the pure texts of `MountAlignmentText`.
/// The fixtures (`Fake`, `connectFake`, ...) are in MountServiceTests.swift.
extension MountServiceTests {
    private static let homeLine = "Not aligned: centre a star and tap Sync"

    // MARK: - A mount that Lodestar aligns, with a scripted driver

    func testAMountThatLodestarAlignsIsNotOfferedAGoToBeforeTheFirstSync() async {
        await connectFake(lodestar: true)
        XCTAssertTrue(service.usesLodestarAlignment)
        XCTAssertTrue(service.needsFirstSync)
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), MountAlignmentText.notAlignedYet)
        XCTAssertNil(service.syncUnavailableReason(for: highTarget()), "the sync is what aligns it")
    }

    func testAGoToBeforeTheFirstSyncSaysWhatToDoFirst() async {
        let fake = await connectFake(lodestar: true)
        await service.goTo(highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "Not aligned yet. Centre a star with the nudge pad, then tap Sync.")
        XCTAssertTrue(fake.slews.isEmpty)
    }

    func testTheTextsOfAMountThatLodestarAlignsBeforeTheFirstSync() async {
        await connectFake(lodestar: true)
        XCTAssertEqual(service.alignmentLine, Self.homeLine)
        XCTAssertEqual(service.startPositionLine, "The mount started at its home position.")
        XCTAssertFalse(service.startsAwayFromHome)
        XCTAssertNil(service.alignmentWarning, "the alignment line says it for these mounts")
        XCTAssertNil(service.pierSideLine)
        XCTAssertEqual(service.trackingAndPierLine, "Tracking")
        XCTAssertNil(service.trackingStopText)
        XCTAssertTrue(service.alignedStars.isEmpty)
    }

    func testTheAlignmentTextsOfOtherMountsAreEmpty() async {
        await connectFake()
        XCTAssertFalse(service.usesLodestarAlignment)
        XCTAssertFalse(service.needsFirstSync)
        XCTAssertNil(service.alignmentLine)
        XCTAssertNil(service.startPositionLine)
        XCTAssertNil(service.pierSideLine)
        XCTAssertNil(service.trackingStopText)
        XCTAssertFalse(service.startsAwayFromHome)
    }

    func testTheFirstSyncOfAMountThatLodestarAlignsReportsTheHomeError() async throws {
        let fake = await connectFake(lodestar: true) { fake in
            fake.configure { $0.position = EquatorialCoordinate(rightAscension: 10.0, declination: 0.0) }
        }
        let place = EquatorialCoordinate(rightAscension: 10.0, declination: 5.0)
        await service.syncMount(to: CelestialObject.custom(name: "Alpha Test", j2000: place), observer: observer)
        XCTAssertEqual(fake.syncs, [place])
        XCTAssertEqual(service.noticeText, "Synced to Alpha Test. The mount's home position was 5.0\u{00B0} off.")
        XCTAssertEqual(try XCTUnwrap(service.alignmentHomeError), 5.0, accuracy: 1e-6)
        XCTAssertEqual(service.syncedObjects, [MountSyncedObject(name: "Alpha Test", place: place)])
        XCTAssertNil(service.errorText)
    }

    func testTheSyncLimitDoesNotApplyToAMountThatLodestarAligns() async {
        service.settings.maximumSyncOffset = 1.0
        let fake = await connectFake(lodestar: true) { fake in
            fake.configure { $0.position = EquatorialCoordinate(rightAscension: 10.0, declination: 0.0) }
        }
        await service.syncMount(to: CelestialObject.custom(name: "Far", j2000: EquatorialCoordinate(rightAscension: 10.0,
                                                                                                       declination: 5.0)),
                                observer: observer)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(fake.syncs.count, 1, "the first sync is as far off as the home position is")
    }

    func testAMountThatRejectsAStarIsToldWhichStarToCheck() async {
        let fake = await connectFake(lodestar: true)
        fake.configure { $0.syncError = .rejected(detail: "residual too large") }
        await service.syncMount(to: CelestialObject.custom(name: "Wrong Star", j2000: EquatorialCoordinate(rightAscension: 40.0,
                                                                                                             declination: 10.0)),
                                observer: observer)
        XCTAssertEqual(service.errorText, "That does not fit the other stars. Check that you centred Wrong Star.")
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
    }

    func testOtherSyncFailuresOfAMountThatLodestarAlignsAreShownAsTheyAre() async {
        let fake = await connectFake(lodestar: true)
        fake.configure { $0.syncError = .timeout(operation: "sync") }
        await service.syncMount(to: highTarget(), observer: observer)
        XCTAssertEqual(service.errorText, "The mount didn't answer in time (sync).")
    }

    func testOnlyTheLastTwentyFourSyncedObjectsAreRemembered() async {
        let fake = await connectFake(lodestar: true)
        for index in 1...25 {
            let place = EquatorialCoordinate(rightAscension: Double(index) * 10.0, declination: 0.0)
            await service.syncMount(to: CelestialObject.custom(name: "Star \(index)", j2000: place), observer: observer)
        }
        XCTAssertEqual(fake.syncs.count, 25)
        XCTAssertEqual(service.syncedObjects.count, 24)
        XCTAssertEqual(service.syncedObjects.first?.name, "Star 2")
        XCTAssertEqual(service.syncedObjects.last?.name, "Star 25")
    }

    func testTheAlignmentCommandsNeedADriverThatCanDoThem() async {
        let fake = await connectFake(lodestar: true)
        let unsupported = "This mount doesn't support this operation."
        await service.removeAlignedStar(at: 0)
        XCTAssertEqual(service.errorText, unsupported)
        XCTAssertNil(service.noticeText)
        await service.clearAlignment()
        XCTAssertEqual(service.errorText, unsupported)
        service.dismissError()
        XCTAssertEqual(fake.abortCount, 0)
        // "This is home" stops the mount first, then asks the driver.
        await service.declareHomePosition()
        XCTAssertEqual(fake.abortCount, 1)
        XCTAssertEqual(service.errorText, unsupported)
        XCTAssertFalse(service.isWorking)
    }

    func testTheAlignmentCommandsAreIgnoredByOtherMounts() async {
        let fake = await connectFake()
        await service.removeAlignedStar(at: 0)
        await service.clearAlignment()
        await service.declareHomePosition()
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
        XCTAssertEqual(fake.abortCount, 0)
    }

    func testRemovingAndClearingWaitForTheMountToBeIdle() async {
        await connectFake(lodestar: true)
        service.nudgeOnce(.north)
        await expect("the nudge to start") { self.service.status.phase == .nudging }
        await service.removeAlignedStar(at: 0)
        await service.clearAlignment()
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
    }

    func testAlignmentCommandsAreIgnoredWithoutAConnection() async {
        await service.removeAlignedStar(at: 0)
        await service.clearAlignment()
        await service.declareHomePosition()
        XCTAssertNil(service.errorText)
        XCTAssertNil(service.noticeText)
    }

    // MARK: - The simulated Sky-Watcher mount

    private func connectSimulatedSkyWatcher() async {
        service.connectDemo(.demoSkyWatcher, observer: observer)
        await expect("the simulated Sky-Watcher mount") { self.service.connection == .connected }
    }

    /// The simulated telescope is turned to the star, as a person would with the nudge pad, and the mount is synced.
    private func alignOnOneStar(_ name: String = "Alpha Test") async -> CelestialObject {
        let star = Self.target(altitude: 55.0, azimuth: 160.0, name: name, seenFrom: observer)
        await service.centreSimulatedMount(on: star, observer: observer)
        await service.syncMount(to: star, observer: observer)
        return star
    }

    func testTheSimulatedSkyWatcherStartsWithoutAnAlignment() async {
        await connectSimulatedSkyWatcher()
        XCTAssertTrue(service.isDemo)
        XCTAssertTrue(service.usesLodestarAlignment)
        XCTAssertEqual(service.connectedOption?.id, "demo-skywatcher")
        XCTAssertTrue(service.displayName.hasPrefix("Sky-Watcher"), service.displayName)
        XCTAssertTrue(service.displayName.hasSuffix(" (simulated)"), service.displayName)
        XCTAssertNotNil(service.driverDetail)
        XCTAssertEqual(service.driverDetail?.arrangement, .altAzimuth)
        XCTAssertTrue(service.needsFirstSync)
        XCTAssertTrue(service.alignedStars.isEmpty)
        XCTAssertEqual(service.alignmentLine, Self.homeLine)
        XCTAssertEqual(service.startPositionLine, "The mount started at its home position.")
        XCTAssertFalse(service.startsAwayFromHome)
        XCTAssertNil(service.pierSideLine, "only an equatorial set-up has a pier side")
        XCTAssertNil(service.alignmentWarning)
        XCTAssertEqual(service.trackingLine, "Tracking is off")
        XCTAssertEqual(service.goToUnavailableReason(for: highTarget(), observer: observer), MountAlignmentText.notAlignedYet)
        XCTAssertNil(service.errorText)
    }

    func testOneSyncAlignsTheSimulatedSkyWatcherOnOneStar() async throws {
        await connectSimulatedSkyWatcher()
        let star = await alignOnOneStar()
        XCTAssertNil(service.errorText)
        let notice = try XCTUnwrap(service.noticeText)
        XCTAssertTrue(notice.hasPrefix("Synced to Alpha Test. The mount's home position was "), notice)
        XCTAssertTrue(notice.hasSuffix(" off."), notice)
        XCTAssertGreaterThan(try XCTUnwrap(service.alignmentHomeError), 0.3, "the simulated mount starts a little off its home")
        XCTAssertEqual(service.syncedObjects.map { $0.name }, ["Alpha Test"])
        XCTAssertEqual(service.syncedObjects.first?.place, star.j2000)
        XCTAssertEqual(service.driverDetail?.alignment?.stars.count, 1)
        XCTAssertFalse(service.needsFirstSync)
        XCTAssertEqual(service.alignedStars.count, 1)
        XCTAssertEqual(service.alignedStars.first?.name, "Alpha Test")
        XCTAssertEqual(service.alignedStars.first?.index, 0)
        XCTAssertEqual(service.alignedStars.first?.id, 0)
        let line = try XCTUnwrap(service.alignmentLine)
        XCTAssertTrue(line.hasPrefix("Aligned on 1 star"), line)
        XCTAssertNil(service.goToUnavailableReason(for: star, observer: observer))
    }

    func testAnAlignedSimulatedSkyWatcherCanBeSentToAnotherTarget() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        let other = Self.target(altitude: 40.0, azimuth: 160.0, name: "Beta Test", seenFrom: observer)
        XCTAssertNil(service.goToUnavailableReason(for: other, observer: observer))
        await service.goTo(other, observer: observer)
        XCTAssertNil(service.errorText)
        XCTAssertEqual(service.slewTargetName, "Beta Test")
        XCTAssertEqual(service.status.phase, .slewing)
        service.stop()
        await expect("the stop to finish") { !self.service.isStopping }
        XCTAssertEqual(service.status.phase, .idle)
        XCTAssertEqual(service.status.outcome, .aborted)
    }

    func testTwoStarsAreNamedAndOneOfThemCanBeRemoved() async throws {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar("Alpha Test")
        let second = Self.target(altitude: 40.0, azimuth: 220.0, name: "Beta Test", seenFrom: observer)
        await service.centreSimulatedMount(on: second, observer: observer)
        await service.syncMount(to: second, observer: observer)
        XCTAssertNil(service.errorText)
        let notice = try XCTUnwrap(service.noticeText)
        XCTAssertTrue(notice.hasPrefix("Synced to Beta Test. The mount was "), notice)
        XCTAssertEqual(service.driverDetail?.alignment?.stars.count, 2)
        XCTAssertEqual(service.alignedStars.map { $0.name }, ["Alpha Test", "Beta Test"])
        XCTAssertEqual(service.alignedStars.map { $0.index }, [0, 1])
        let line = try XCTUnwrap(service.alignmentLine)
        XCTAssertTrue(line.hasPrefix("Aligned on 2 stars"), line)
        await service.removeAlignedStar(at: 0)
        XCTAssertEqual(service.noticeText, "Removed Alpha Test from the alignment.")
        XCTAssertEqual(service.alignedStars.map { $0.name }, ["Beta Test"])
        XCTAssertEqual(service.syncedObjects.count, 2, "one star is left, so the alignment is not forgotten")
        XCTAssertNotNil(service.alignmentHomeError)
        XCTAssertFalse(service.needsFirstSync)
    }

    func testRemovingTheOnlyStarLeavesTheSimulatedSkyWatcherUnaligned() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        await service.removeAlignedStar(at: 0)
        XCTAssertEqual(service.noticeText, "Removed Alpha Test from the alignment.")
        XCTAssertNil(service.errorText)
        XCTAssertTrue(service.needsFirstSync)
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
        XCTAssertTrue(service.alignedStars.isEmpty)
        XCTAssertEqual(service.alignmentLine, Self.homeLine)
    }

    func testRemovingAStarThatIsNotThereIsReported() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        await service.removeAlignedStar(at: 5)
        XCTAssertEqual(service.errorText, "That value can't be used: there is no alignment point 5.")
        XCTAssertNil(service.noticeText)
        XCTAssertEqual(service.alignedStars.count, 1, "the alignment is untouched")
        XCTAssertFalse(service.isWorking)
    }

    func testClearingTheAlignmentStartsOver() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        await service.clearAlignment()
        XCTAssertEqual(service.noticeText, "The star alignment was cleared.")
        XCTAssertNil(service.errorText)
        XCTAssertTrue(service.needsFirstSync)
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
    }

    func testDeclaringTheHomePositionClearsTheAlignment() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        await service.declareHomePosition()
        XCTAssertEqual(service.noticeText, "This is now the mount's home position. The star alignment was cleared.")
        XCTAssertNil(service.errorText)
        XCTAssertTrue(service.needsFirstSync)
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
        XCTAssertFalse(service.startsAwayFromHome)
        XCTAssertEqual(service.status.phase, .idle)
    }

    func testMovingTheObserverFarClearsTheSimulatedSkyWatchersAlignment() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        let base = observer.location
        let elsewhere = Observer(location: GeographicLocation(latitude: base.latitude + 1.0, longitude: base.longitude,
                                                              elevation: base.elevation))
        service.updateObserver(elsewhere)
        await expect("the alignment to be dropped") { self.service.needsFirstSync }
        await expect("the notice") { self.service.noticeText != nil }
        XCTAssertEqual(service.noticeText, "Your location changed, so the star alignment was cleared. Align on a star again.")
        XCTAssertTrue(service.syncedObjects.isEmpty)
        XCTAssertNil(service.alignmentHomeError)
    }

    func testMovingTheObserverALittleKeepsTheSimulatedSkyWatchersAlignment() async {
        await connectSimulatedSkyWatcher()
        _ = await alignOnOneStar()
        let base = observer.location
        let jitter = Observer(location: GeographicLocation(latitude: base.latitude + 0.005, longitude: base.longitude,
                                                           elevation: base.elevation))
        service.updateObserver(jitter)
        await settle(0.5)
        XCTAssertFalse(service.needsFirstSync)
        XCTAssertEqual(service.alignedStars.count, 1)
        XCTAssertFalse((service.noticeText ?? "").contains("location changed"))
    }

    // MARK: - An equatorial Sky-Watcher mount that started away from home

    /// A simulated equatorial Sky-Watcher mount whose axes stand at the given angles when it is connected, as if it had been
    /// switched on there.
    private func equatorialOption(axis1: Double, axis2: Double) -> MountConnectionOption {
        Self.option(id: "demo-equatorial", lodestarAligned: true) { _, options in
            let location = options.location ?? GeographicLocation(latitude: 40.0, longitude: -105.0, elevation: 0.0)
            let clock = ManualMountClock(start: Date())
            let simulator = SkyWatcherSimulator(clock: clock, location: location, mode: .equatorial,
                                                errors: SkyWatcherPointingErrors(),
                                                version: SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C))
            simulator.placeAxes(axis1Degrees: axis1, axis2Degrees: axis2)
            let driver = SkyWatcherDriver(transport: simulator, clock: clock,
                                          configuration: SkyWatcherConfiguration(location: location, mode: .equatorial))
            return MountDriverBundle(driver: driver, clock: clock, detail: { MountDriverDetail(skyWatcher: driver) })
        }
    }

    func testAMountThatStartedAwayFromHomeSaysSoUntilThePersonDeclaresHome() async {
        service.connectDemo(equatorialOption(axis1: 45.0, axis2: 10.0), observer: observer)
        await expect("the equatorial mount") { self.service.connection == .connected }
        XCTAssertEqual(service.driverDetail?.arrangement, .equatorial)
        XCTAssertTrue(service.startsAwayFromHome)
        XCTAssertEqual(service.startPositionLine, "The mount is not at its home position. Switch it off and on at the home "
            + "position, or move it there with the arrows and tap This is home.")
        XCTAssertEqual(service.pierSideLine, "Telescope east of the pier")
        XCTAssertEqual(service.trackingAndPierLine, "Tracking is off \u{00B7} Telescope east of the pier")
        await service.declareHomePosition()
        XCTAssertEqual(service.noticeText, "This is now the mount's home position. The star alignment was cleared.")
        XCTAssertFalse(service.startsAwayFromHome)
        XCTAssertEqual(service.startPositionLine, "The mount started at its home position.")
    }

    func testTheOtherSideOfThePierIsNamed() async {
        service.connectDemo(equatorialOption(axis1: 45.0, axis2: -10.0), observer: observer)
        await expect("the equatorial mount") { self.service.connection == .connected }
        XCTAssertEqual(service.pierSideLine, "Telescope west of the pier")
        XCTAssertEqual(service.trackingAndPierLine, "Tracking is off \u{00B7} Telescope west of the pier")
    }

    func testTrackingThatStopsAtTheMeridianIsExplained() async {
        service.connectDemo(equatorialOption(axis1: 100.0, axis2: 10.0), observer: observer)
        await expect("the equatorial mount") { self.service.connection == .connected }
        XCTAssertNil(service.trackingStopText, "tracking has not been tried yet")
        service.setTracking(true)
        await expect("the poll to notice that the mount is past the meridian limit") { self.service.trackingStopText != nil }
        XCTAssertEqual(service.driverDetail?.trackingStopReason, .outsideMountLimits)
        XCTAssertEqual(service.trackingStopText, "Tracking stopped at the meridian. Tap Go to to flip the mount")
        XCTAssertEqual(service.trackingLine, "Tracking is off")
    }

    // MARK: - Words of the alignment

    func testTheFixedTextsOfTheAlignment() {
        XCTAssertEqual(MountAlignmentText.notAlignedYet, "Not aligned yet. Centre a star with the nudge pad, then tap Sync.")
        XCTAssertEqual(MountAlignmentText.siteAndTime,
                       "Uses your location and the phone's clock for pointing; nothing is sent to the mount.")
        XCTAssertEqual(MountAlignmentText.rejectedText(name: "Vega"),
                       "That does not fit the other stars. Check that you centred Vega.")
    }

    private func star(_ residual: Double? = nil) -> MountAlignmentStar {
        MountAlignmentStar(place: EquatorialCoordinate(rightAscension: 10.0, declination: 20.0), residualDegrees: residual)
    }

    func testTheAlignmentLineWithoutStarsSaysWhatToDo() {
        XCTAssertEqual(MountAlignmentText.line(nil), Self.homeLine)
        let empty = MountAlignmentDetail(stars: [], predictedErrorDegrees: 0.3, maximumResidualDegrees: 0.1)
        XCTAssertEqual(MountAlignmentText.line(empty), Self.homeLine)
    }

    func testTheAlignmentLineOfOneStar() {
        let bare = MountAlignmentDetail(stars: [star()], predictedErrorDegrees: nil, maximumResidualDegrees: nil)
        XCTAssertEqual(MountAlignmentText.line(bare), "Aligned on 1 star")
        let predicted = MountAlignmentDetail(stars: [star()], predictedErrorDegrees: 0.2, maximumResidualDegrees: 0.05)
        // One star has no residual to report, only the expected accuracy.
        XCTAssertEqual(MountAlignmentText.line(predicted), "Aligned on 1 star, \u{2248}\u{00A0}0.2\u{00B0} accuracy")
    }

    func testTheAlignmentLineOfSeveralStars() {
        let three = MountAlignmentDetail(stars: [star(), star(), star()], predictedErrorDegrees: 0.2,
                                         maximumResidualDegrees: 0.0213)
        XCTAssertEqual(MountAlignmentText.line(three),
                       "Aligned on 3 stars, 0.02\u{00B0} residual, \u{2248}\u{00A0}0.2\u{00B0} accuracy")
        let noResidual = MountAlignmentDetail(stars: [star(), star()], predictedErrorDegrees: nil, maximumResidualDegrees: nil)
        XCTAssertEqual(MountAlignmentText.line(noResidual), "Aligned on 2 stars")
        let noPrediction = MountAlignmentDetail(stars: [star(), star()], predictedErrorDegrees: nil, maximumResidualDegrees: 0.5)
        XCTAssertEqual(MountAlignmentText.line(noPrediction), "Aligned on 2 stars, 0.50\u{00B0} residual")
    }

    func testTheAccuracyKeepsTheDigitsThatMeanSomething() {
        XCTAssertEqual(MountAlignmentText.accuracy(0.0), "0.00\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(0.05), "0.05\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(0.0949), "0.09\u{00B0}")
        // From 0.095 on there is a single decimal.
        XCTAssertEqual(MountAlignmentText.accuracy(0.0951), "0.1\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(0.2), "0.2\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(1.04), "1.0\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(9.4), "9.4\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(9.4999), "9.5\u{00B0}")
        // 9.5 is the first value without decimals.
        XCTAssertEqual(MountAlignmentText.accuracy(9.5), "10\u{00B0}")
        XCTAssertEqual(MountAlignmentText.accuracy(12.3), "12\u{00B0}")
    }

    func testTheSyncNoticeOfTheFirstStarNamesTheHomeError() {
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Vega", offset: 3.2, starCount: 1),
                       "Synced to Vega. The mount's home position was 3.2\u{00B0} off.")
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Vega", offset: 12.4, starCount: 1),
                       "Synced to Vega. The mount's home position was 12\u{00B0} off.")
        // Even a very large offset is not "a lot" for the first star, and no star count is read as the first.
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Vega", offset: 40.0, starCount: 0),
                       "Synced to Vega. The mount's home position was 40\u{00B0} off.")
    }

    func testTheSyncNoticeOfLaterStarsWarnsAboutLargeOffsets() {
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Deneb", offset: 0.3, starCount: 2),
                       "Synced to Deneb. The mount was 18\u{2032} off.")
        // Half a degree is still all right; a little more is a lot.
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Deneb", offset: 0.5, starCount: 2),
                       "Synced to Deneb. The mount was 30\u{2032} off.")
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Deneb", offset: 0.6, starCount: 2),
                       "Synced to Deneb. The mount was 36\u{2032} off, which is a lot: check that you centred the right star "
                       + "and that the mount has not been bumped.")
        XCTAssertEqual(MountAlignmentText.syncNotice(name: "Deneb", offset: 2.0, starCount: 3),
                       "Synced to Deneb. The mount was 2.0\u{00B0} off, which is a lot: check that you centred the right star "
                       + "and that the mount has not been bumped.")
    }

    func testAnAlignedStarKnowsItsIndexAsItsIdentity() {
        let aligned = MountAlignedStar(index: 3, name: "Star 4", residualDegrees: 0.02)
        XCTAssertEqual(aligned.id, 3)
        XCTAssertEqual(aligned, MountAlignedStar(index: 3, name: "Star 4", residualDegrees: 0.02))
        XCTAssertNotEqual(aligned, MountAlignedStar(index: 3, name: "Star 4", residualDegrees: nil))
    }
}

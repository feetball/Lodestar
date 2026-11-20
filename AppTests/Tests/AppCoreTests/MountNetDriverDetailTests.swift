import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Features/Mount/MountDriverDetail.swift: what the screens learn from a Sky-Watcher driver besides the controller's status (the
/// alignment stars and how well they fit, the pier side, where the mount stood at the start). The driver runs against the
/// engine's simulator on a manual clock, so nothing here depends on the date or on time passing.
final class MountNetDriverDetailTests: XCTestCase {
    /// 2026-10-18 04:00 UTC.
    private static let start = Date(timeIntervalSince1970: 1_792_296_000)
    private static let boulder = GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650)
    private static let vega = EquatorialCoordinate(rightAscensionHours: 18.6156, declination: 38.7837)
    private static let mirfak = EquatorialCoordinate(rightAscensionHours: 3.4054, declination: 49.8612)
    private static let altAzimuthErrors = SkyWatcherPointingErrors(axis1Index: 2.0, axis2Index: 1.1, baseTiltX: 0.5, baseTiltY: -0.4,
                                                                   orthogonality: 0.1, cone: 0.12)
    private static let equatorialErrors = SkyWatcherPointingErrors(axis1Index: 1.3, axis2Index: -0.8, baseTiltX: 0.4, baseTiltY: -0.3,
                                                                   orthogonality: 0.15, cone: -0.1)

    private struct Rig {
        let clock: ManualMountClock
        let simulator: SkyWatcherSimulator
        let driver: SkyWatcherDriver
        let controller: MountController
    }

    private func makeRig(mode: SkyWatcherMountMode, errors: SkyWatcherPointingErrors = SkyWatcherPointingErrors(),
                         configure: (SkyWatcherSimulator) -> Void = { _ in }) -> Rig {
        let clock = ManualMountClock(start: Self.start)
        let version = mode == .altAzimuth ? SkyWatcherVersion(major: 3, minor: 0x22, mountCode: 0xA5)
            : SkyWatcherVersion(major: 3, minor: 0x40, mountCode: 0x0C)
        let simulator = SkyWatcherSimulator(clock: clock, location: Self.boulder, mode: mode, errors: errors, version: version)
        configure(simulator)
        let driver = SkyWatcherDriver(transport: simulator, clock: clock,
                                      configuration: SkyWatcherConfiguration(location: Self.boulder, mode: mode))
        let controller = MountController(driver: driver, observer: Observer(location: Self.boulder), clock: clock)
        return Rig(clock: clock, simulator: simulator, driver: driver, controller: controller)
    }

    /// Turns the simulated axes so that the telescope really points at `star`, as a person does with the nudge arrows.
    private func centre(_ rig: Rig, on star: EquatorialCoordinate) {
        let frame = SkyFrame(date: rig.clock.now(), observer: Observer(location: Self.boulder))
        let place = MountEpoch.apparentOfDate.fromJ2000(star, frame: frame)
        let direction = SkyWatcherSky.localDirection(place, localSiderealTime: frame.localApparentSiderealTime,
                                                     latitude: Self.boulder.latitude, mode: rig.simulator.mode)
        let truth = SkyWatcherPointingModel(mode: rig.simulator.mode, isSouthernHemisphere: false, errors: rig.simulator.effectiveErrors)
        let options = truth.solutions(direction, preferredAxis1Degrees: rig.simulator.axis1Degrees)
        let allowed = options.filter { option in
            rig.simulator.mode == .equatorial ? abs(truth.modelAxis1(option.axis1)) <= 95 : option.pierSide == .east
        }
        let candidates = allowed.isEmpty ? options : allowed
        let best = candidates.min { first, second in
            abs(first.axis1 - rig.simulator.axis1Degrees) + abs(first.axis2 - rig.simulator.axis2Degrees)
                < abs(second.axis1 - rig.simulator.axis1Degrees) + abs(second.axis2 - rig.simulator.axis2Degrees)
        }
        if let best { rig.simulator.placeAxes(axis1Degrees: best.axis1, axis2Degrees: best.axis2) }
    }

    private func syncOn(_ rig: Rig, _ star: EquatorialCoordinate) throws {
        centre(rig, on: star)
        try rig.controller.sync(star)
    }

    /// Where the alignment should have recorded `star` for the apparent place of the moment.
    private func apparentPlace(of star: EquatorialCoordinate, _ rig: Rig) -> EquatorialCoordinate {
        MountEpoch.apparentOfDate.fromJ2000(star, frame: SkyFrame(date: rig.clock.now(), observer: Observer(location: Self.boulder)))
    }

    // MARK: Before the handshake

    func testADriverThatHasNotConnectedHasNothingToTell() {
        let rig = makeRig(mode: .altAzimuth)
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(detail.alignment, MountAlignmentDetail(stars: [], predictedErrorDegrees: nil, maximumResidualDegrees: nil))
        XCTAssertNil(detail.arrangement)
        XCTAssertNil(detail.pierSide)
        XCTAssertNil(detail.startAxis1Degrees)
        XCTAssertNil(detail.startAxis2Degrees)
        XCTAssertNil(detail.trackingStopReason)
        XCTAssertFalse(detail.startsAwayFromHome)
    }

    // MARK: After the handshake

    func testAnAltAzimuthMountAtHomeReportsItsArrangementAndNoPierSide() throws {
        let rig = makeRig(mode: .altAzimuth)
        try rig.controller.connect()
        XCTAssertNotNil(rig.driver.pierSide, "the driver itself has a side for every mount")
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(detail.arrangement, SkyWatcherMountMode.altAzimuth)
        XCTAssertNil(detail.pierSide, "only an equatorial set-up shows the side of the pier")
        XCTAssertEqual(try XCTUnwrap(detail.startAxis1Degrees), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(detail.startAxis2Degrees), 0, accuracy: 1e-6)
        XCTAssertFalse(detail.startsAwayFromHome)
        XCTAssertNil(detail.trackingStopReason)
        XCTAssertEqual(detail.alignment?.stars.count, 0)
        XCTAssertNil(detail.alignment?.predictedErrorDegrees)
        XCTAssertNil(detail.alignment?.maximumResidualDegrees)
    }

    func testAnEquatorialMountAtHomeIsOnTheEastSideOfThePier() throws {
        let rig = makeRig(mode: .equatorial)
        try rig.controller.connect()
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(detail.arrangement, SkyWatcherMountMode.equatorial)
        XCTAssertEqual(detail.pierSide, SkyWatcherPierSide.east)
        XCTAssertEqual(detail.pierSide, rig.driver.pierSide)
    }

    func testTheSideOfThePierFollowsTheDeclinationAxis() throws {
        for (axis2, side) in [(30.0, SkyWatcherPierSide.east), (-30.0, SkyWatcherPierSide.west)] {
            let rig = makeRig(mode: .equatorial) { $0.placeAxes(axis1Degrees: 0, axis2Degrees: axis2) }
            try rig.controller.connect()
            XCTAssertEqual(MountDriverDetail(skyWatcher: rig.driver).pierSide, side, "axis 2 at \(axis2)")
        }
    }

    // MARK: The start position

    func testAMountSwitchedOnAwayFromHomeSaysSo() throws {
        let rig = makeRig(mode: .altAzimuth) { $0.placeAxes(axis1Degrees: 40, axis2Degrees: 10) }
        try rig.controller.connect()
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(try XCTUnwrap(detail.startAxis1Degrees), 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(detail.startAxis2Degrees), 10, accuracy: 0.01)
        XCTAssertTrue(detail.startsAwayFromHome)
    }

    func testOneAxisAwayFromHomeIsEnough() throws {
        let first = makeRig(mode: .altAzimuth) { $0.placeAxes(axis1Degrees: 0, axis2Degrees: 25) }
        try first.controller.connect()
        XCTAssertTrue(MountDriverDetail(skyWatcher: first.driver).startsAwayFromHome)
        let second = makeRig(mode: .altAzimuth) { $0.placeAxes(axis1Degrees: -30, axis2Degrees: 0) }
        try second.controller.connect()
        XCTAssertTrue(MountDriverDetail(skyWatcher: second.driver).startsAwayFromHome)
    }

    func testAMountAFewDegreesFromHomeIsStillHome() throws {
        let rig = makeRig(mode: .altAzimuth) { $0.placeAxes(axis1Degrees: 5, axis2Degrees: -5) }
        try rig.controller.connect()
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(try XCTUnwrap(detail.startAxis1Degrees), 5, accuracy: 0.01)
        XCTAssertFalse(detail.startsAwayFromHome)
    }

    func testTheHomeToleranceIsTenDegreesOnEitherSide() throws {
        XCTAssertEqual(MountDriverDetail.homeToleranceDegrees, 10.0)
        let rig = makeRig(mode: .altAzimuth)
        try rig.controller.connect()
        var detail = MountDriverDetail(skyWatcher: rig.driver)

        detail.startAxis1Degrees = 10.0
        detail.startAxis2Degrees = -10.0
        XCTAssertFalse(detail.startsAwayFromHome, "exactly at the tolerance is still home")

        detail.startAxis1Degrees = 10.01
        detail.startAxis2Degrees = 0
        XCTAssertTrue(detail.startsAwayFromHome)

        detail.startAxis1Degrees = 0
        detail.startAxis2Degrees = -10.01
        XCTAssertTrue(detail.startsAwayFromHome)

        detail.startAxis1Degrees = -179
        detail.startAxis2Degrees = 0
        XCTAssertTrue(detail.startsAwayFromHome)
    }

    func testWithoutBothAnglesTheMountIsTakenToBeAtHome() throws {
        let rig = makeRig(mode: .altAzimuth)
        try rig.controller.connect()
        var detail = MountDriverDetail(skyWatcher: rig.driver)
        detail.startAxis1Degrees = 90
        detail.startAxis2Degrees = nil
        XCTAssertFalse(detail.startsAwayFromHome)
        detail.startAxis1Degrees = nil
        detail.startAxis2Degrees = 90
        XCTAssertFalse(detail.startsAwayFromHome)
        detail.startAxis2Degrees = nil
        XCTAssertFalse(detail.startsAwayFromHome)
    }

    // MARK: The alignment

    func testOneAlignedStarIsListedWithItsFit() throws {
        let rig = makeRig(mode: .altAzimuth, errors: Self.altAzimuthErrors)
        try rig.controller.connect()
        try syncOn(rig, Self.vega)
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        let alignment = try XCTUnwrap(detail.alignment)
        XCTAssertEqual(alignment.stars.count, 1)
        let star = try XCTUnwrap(alignment.stars.first)
        XCTAssertLessThan(star.place.angularSeparation(to: apparentPlace(of: Self.vega, rig)), 0.01)
        XCTAssertEqual(try XCTUnwrap(star.residualDegrees), 0, accuracy: 1e-3, "one star is fitted exactly")
        XCTAssertEqual(try XCTUnwrap(alignment.maximumResidualDegrees), 0, accuracy: 1e-3)
        let fit = try XCTUnwrap(rig.driver.alignmentFit)
        XCTAssertEqual(alignment.predictedErrorDegrees, fit.predictedErrorDegrees)
        XCTAssertGreaterThan(try XCTUnwrap(alignment.predictedErrorDegrees), 0, "a single star leaves the rest of the sky uncertain")
        XCTAssertEqual(detail.arrangement, SkyWatcherMountMode.altAzimuth)
        XCTAssertNil(detail.pierSide)
    }

    func testTheStarsAreListedOldestFirstEachWithItsOwnResidual() throws {
        let rig = makeRig(mode: .altAzimuth, errors: Self.altAzimuthErrors)
        try rig.controller.connect()
        try syncOn(rig, Self.vega)
        try syncOn(rig, Self.mirfak)
        let alignment = try XCTUnwrap(MountDriverDetail(skyWatcher: rig.driver).alignment)
        XCTAssertEqual(alignment.stars.count, 2)
        XCTAssertLessThan(alignment.stars[0].place.angularSeparation(to: apparentPlace(of: Self.vega, rig)), 0.01)
        XCTAssertLessThan(alignment.stars[1].place.angularSeparation(to: apparentPlace(of: Self.mirfak, rig)), 0.01)
        let fit = try XCTUnwrap(rig.driver.alignmentFit)
        XCTAssertEqual(fit.residualsDegrees.count, 2)
        XCTAssertEqual(alignment.stars[0].residualDegrees, fit.residualsDegrees[0])
        XCTAssertEqual(alignment.stars[1].residualDegrees, fit.residualsDegrees[1])
        XCTAssertEqual(alignment.maximumResidualDegrees, fit.maximumResidualDegrees)
        XCTAssertEqual(alignment.predictedErrorDegrees, fit.predictedErrorDegrees)
    }

    func testRemovingTheFirstStarLeavesTheSecondOne() throws {
        let rig = makeRig(mode: .altAzimuth, errors: Self.altAzimuthErrors)
        try rig.controller.connect()
        try syncOn(rig, Self.vega)
        try syncOn(rig, Self.mirfak)
        try rig.driver.removeAlignmentPoint(0)
        let alignment = try XCTUnwrap(MountDriverDetail(skyWatcher: rig.driver).alignment)
        XCTAssertEqual(alignment.stars.count, 1)
        XCTAssertLessThan(alignment.stars[0].place.angularSeparation(to: apparentPlace(of: Self.mirfak, rig)), 0.01)
        XCTAssertEqual(try XCTUnwrap(alignment.stars[0].residualDegrees), 0, accuracy: 1e-3)
    }

    func testClearingTheAlignmentEmptiesTheList() throws {
        let rig = makeRig(mode: .altAzimuth, errors: Self.altAzimuthErrors)
        try rig.controller.connect()
        try syncOn(rig, Self.vega)
        XCTAssertEqual(MountDriverDetail(skyWatcher: rig.driver).alignment?.stars.count, 1)
        rig.driver.clearAlignment()
        let alignment = try XCTUnwrap(MountDriverDetail(skyWatcher: rig.driver).alignment)
        XCTAssertTrue(alignment.stars.isEmpty)
        XCTAssertNil(alignment.predictedErrorDegrees)
        XCTAssertNil(alignment.maximumResidualDegrees)
    }

    func testAnEquatorialMountListsItsStarsAndItsSide() throws {
        let rig = makeRig(mode: .equatorial, errors: Self.equatorialErrors)
        try rig.controller.connect()
        try syncOn(rig, Self.vega)
        let detail = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(detail.arrangement, SkyWatcherMountMode.equatorial)
        XCTAssertNotNil(detail.pierSide)
        XCTAssertEqual(detail.pierSide, rig.driver.pierSide)
        let alignment = try XCTUnwrap(detail.alignment)
        XCTAssertEqual(alignment.stars.count, 1)
        XCTAssertLessThan(alignment.stars[0].place.angularSeparation(to: apparentPlace(of: Self.vega, rig)), 0.01)
    }

    func testTheDetailIsASnapshot() throws {
        let rig = makeRig(mode: .altAzimuth, errors: Self.altAzimuthErrors)
        try rig.controller.connect()
        let before = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(before, MountDriverDetail(skyWatcher: rig.driver))
        try syncOn(rig, Self.vega)
        let after = MountDriverDetail(skyWatcher: rig.driver)
        XCTAssertEqual(before.alignment?.stars.count, 0, "an earlier snapshot does not change")
        XCTAssertEqual(after.alignment?.stars.count, 1)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(Set([before, after, after]).count, 2)
    }

    // MARK: The value types

    func testAnAlignmentStarIsEqualWhenPlaceAndResidualAre() {
        let place = EquatorialCoordinate(rightAscension: 100, declination: 20)
        XCTAssertEqual(MountAlignmentStar(place: place, residualDegrees: 0.1), MountAlignmentStar(place: place, residualDegrees: 0.1))
        XCTAssertNotEqual(MountAlignmentStar(place: place, residualDegrees: 0.1), MountAlignmentStar(place: place, residualDegrees: nil))
        XCTAssertNotEqual(MountAlignmentStar(place: place, residualDegrees: 0.1),
                          MountAlignmentStar(place: EquatorialCoordinate(rightAscension: 101, declination: 20), residualDegrees: 0.1))
    }

    func testAnAlignmentDetailKeepsItsStarsInOrder() {
        let first = MountAlignmentStar(place: EquatorialCoordinate(rightAscension: 10, declination: 10), residualDegrees: 0.01)
        let second = MountAlignmentStar(place: EquatorialCoordinate(rightAscension: 20, declination: 20), residualDegrees: 0.02)
        let detail = MountAlignmentDetail(stars: [first, second], predictedErrorDegrees: 0.3, maximumResidualDegrees: 0.02)
        XCTAssertEqual(detail.stars, [first, second])
        XCTAssertNotEqual(detail, MountAlignmentDetail(stars: [second, first], predictedErrorDegrees: 0.3, maximumResidualDegrees: 0.02))
        XCTAssertEqual(detail.predictedErrorDegrees, 0.3)
        XCTAssertEqual(detail.maximumResidualDegrees, 0.02)
    }
}

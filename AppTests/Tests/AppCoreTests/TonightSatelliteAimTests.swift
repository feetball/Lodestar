import Foundation
import LodestarKit
import Observation
import XCTest
@testable import AppCore

/// Where Aim leads guidance for a satellite (`SatelliteAimSource`, `SatelliteAimFix`): the live position of a followed
/// satellite and the fixed point of a pass's peak.
final class TonightSatelliteAimTests: XCTestCase {
    private let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.2705, elevation: 1655))
    /// 2026-10-18T12:00:00Z, about nine hours after the epoch of the element set below.
    private let peakSeconds = 1_792_324_800.0

    private func station() throws -> Satellite {
        let elements = try ElementSetParser.parseTwoLine(
            line1: "1 25544U 98067A   26291.14461894  .00007503  00000+0  14456-3 0  9994",
            line2: "2 25544  51.6328  51.6259 0006780 277.7856  82.2363 15.48918166590814", name: "ISS (ZARYA)")
        return Satellite(elements: elements)
    }

    private func point(_ seconds: Double, azimuth: Double, altitude: Double) -> SatellitePassPoint {
        SatellitePassPoint(date: Date(timeIntervalSince1970: seconds), azimuth: azimuth, altitude: altitude,
                           rangeKilometers: 600, isSunlit: true, magnitude: -3)
    }

    /// A pass of `satellite` that peaks at `peakSeconds` (the hand-made peak point is at azimuth 123, altitude 45).
    private func passItem(_ satellite: Satellite, peakAt peakSeconds: Double) -> SatellitePassItem {
        let peak = point(peakSeconds, azimuth: 123, altitude: 45)
        let pass = SatellitePass(
            rise: point(peakSeconds - 300, azimuth: 200, altitude: 10), culmination: peak,
            set: point(peakSeconds + 300, azimuth: 40, altitude: 10),
            visibleIntervals: [DateInterval(start: Date(timeIntervalSince1970: peakSeconds - 200),
                                            end: Date(timeIntervalSince1970: peakSeconds + 200))],
            brightest: peak, isRiseCut: false, isSetCut: false)
        return SatellitePassItem(satellite: satellite, group: .stations, pass: pass, peak: peak)
    }

    // MARK: Following a satellite

    func testFollowingASatelliteAimsAtItAndRemembersThePass() throws {
        let item = passItem(try station(), peakAt: peakSeconds)
        let source = SatelliteAimSource.follow(item, observer: observer)
        XCTAssertEqual(source.title, "ISS")
        XCTAssertEqual(source.observer, observer)
        XCTAssertFalse(source.isPeak)
        XCTAssertEqual(source.pass?.id, item.id)
        XCTAssertNil(source.peakDate)
    }

    func testAFollowedSatelliteIsFoundWhereTheCameraShouldPoint() throws {
        let satellite = try station()
        let source = SatelliteAimSource.follow(passItem(satellite, peakAt: peakSeconds), observer: observer)
        let date = Date(timeIntervalSince1970: peakSeconds)
        let fix = try XCTUnwrap(source.fix(at: date))
        let look = try XCTUnwrap(satellite.look(at: date, observer: observer))
        XCTAssertEqual(fix.label, "ISS")
        XCTAssertEqual(fix.horizontal, look.apparentHorizontal)
        XCTAssertEqual(fix.look, look)
        XCTAssertNil(fix.secondsToPeak)
        XCTAssertEqual(fix.direction, look.apparentHorizontal.unitVector)
    }

    func testAFollowedSatelliteMovesWithTime() throws {
        let source = SatelliteAimSource.follow(passItem(try station(), peakAt: peakSeconds), observer: observer)
        let early = try XCTUnwrap(source.fix(at: Date(timeIntervalSince1970: peakSeconds)))
        let later = try XCTUnwrap(source.fix(at: Date(timeIntervalSince1970: peakSeconds + 60)))
        XCTAssertNotEqual(early.horizontal, later.horizontal)
        XCTAssertGreaterThan(early.direction.angle(to: later.direction), 0.1)
    }

    func testAFollowedSatelliteWhoseOrbitCannotBeComputedHasNoFix() throws {
        let satellite = try station()
        let farAway = Date(timeIntervalSince1970: 2_840_140_800) // 2060-01-01, 34 years after the epoch
        try XCTSkipUnless(satellite.look(at: farAway, observer: observer) == nil,
                          "SGP4 still propagates this element set 34 years from its epoch")
        let source = SatelliteAimSource.follow(passItem(satellite, peakAt: peakSeconds), observer: observer)
        XCTAssertNil(source.fix(at: farAway))
    }

    // MARK: Waiting at the peak

    func testWaitingAtThePeakAimsAtAFixedPoint() throws {
        let item = passItem(try station(), peakAt: peakSeconds)
        let source = SatelliteAimSource.peak(item, observer: observer)
        XCTAssertEqual(source.title, "ISS")
        XCTAssertTrue(source.isPeak)
        XCTAssertNil(source.pass)
        XCTAssertEqual(source.peakDate, Date(timeIntervalSince1970: peakSeconds))
    }

    func testThePeakPointIsWhereTheSatelliteIsAtThatMomentAsTheCameraSeesIt() throws {
        let satellite = try station()
        let source = SatelliteAimSource.peak(passItem(satellite, peakAt: peakSeconds), observer: observer)
        let peakDate = Date(timeIntervalSince1970: peakSeconds)
        let look = try XCTUnwrap(satellite.look(at: peakDate, observer: observer))
        // Any moment gives the same point: the camera waits there.
        for offset in [-600.0, -120.0, 0.0, 45.0, 900.0] {
            let fix = try XCTUnwrap(source.fix(at: peakDate.addingTimeInterval(offset)))
            XCTAssertEqual(fix.horizontal, look.apparentHorizontal, "offset \(offset)")
            XCTAssertNil(fix.look)
            XCTAssertEqual(fix.label, "ISS peak")
        }
    }

    func testTheCountdownToThePeakIsPositiveBeforeItAndNegativeAfterIt() throws {
        let source = SatelliteAimSource.peak(passItem(try station(), peakAt: peakSeconds), observer: observer)
        let peakDate = Date(timeIntervalSince1970: peakSeconds)
        XCTAssertEqual(try XCTUnwrap(source.fix(at: peakDate.addingTimeInterval(-120))).secondsToPeak, 120)
        XCTAssertEqual(try XCTUnwrap(source.fix(at: peakDate)).secondsToPeak, 0)
        XCTAssertEqual(try XCTUnwrap(source.fix(at: peakDate.addingTimeInterval(45))).secondsToPeak, -45)
    }

    func testIfTheOrbitCannotBeComputedThePeakPointIsTheOneOfThePass() throws {
        let satellite = try station()
        let farSeconds = 2_840_140_800.0 // 2060-01-01
        let farAway = Date(timeIntervalSince1970: farSeconds)
        try XCTSkipUnless(satellite.look(at: farAway, observer: observer) == nil,
                          "SGP4 still propagates this element set 34 years from its epoch")
        let item = passItem(satellite, peakAt: farSeconds)
        let source = SatelliteAimSource.peak(item, observer: observer)
        let fix = try XCTUnwrap(source.fix(at: farAway.addingTimeInterval(-10)))
        XCTAssertEqual(fix.horizontal, HorizontalCoordinate(azimuth: 123, altitude: 45))
        XCTAssertEqual(fix.secondsToPeak, 10)
    }

    // MARK: Identity

    func testEverySourceHasItsOwnIdentityAndACopyKeepsIt() throws {
        let item = passItem(try station(), peakAt: peakSeconds)
        let first = SatelliteAimSource.follow(item, observer: observer)
        let second = SatelliteAimSource.follow(item, observer: observer)
        let peak = SatelliteAimSource.peak(item, observer: observer)
        let copy = first
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, peak.id)
        XCTAssertEqual(first.id, copy.id)
    }

    func testTheDirectionOfAFixIsTheUnitVectorOfItsHorizontalPosition() {
        let fix = SatelliteAimFix(horizontal: HorizontalCoordinate(azimuth: 90, altitude: 0), label: "x", look: nil,
                                  secondsToPeak: nil)
        XCTAssertEqual(fix.direction.x, 1, accuracy: 1e-12)
        XCTAssertEqual(fix.direction.y, 0, accuracy: 1e-12)
        XCTAssertEqual(fix.direction.z, 0, accuracy: 1e-12)
    }
}

/// The satellite Aim is following or waiting for (`SatelliteAimSession`).
@MainActor
final class TonightSatelliteAimSessionTests: XCTestCase {
    private let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.2705, elevation: 1655))

    /// Records that a change was announced; the observation callback is `@Sendable`, so it cannot capture a local variable.
    private final class Flag: @unchecked Sendable {
        var raised = false
    }

    private func source(title: String) throws -> SatelliteAimSource {
        let elements = try OrbitalElements(
            name: title, catalogNumber: 90_001, epoch: Date(timeIntervalSince1970: 1_792_294_095), meanMotion: 15.5,
            eccentricity: 0.001, inclination: 51.6, rightAscensionOfAscendingNode: 50, argumentOfPericenter: 100,
            meanAnomaly: 10)
        let satellite = Satellite(elements: elements)
        let peak = SatellitePassPoint(date: Date(timeIntervalSince1970: 1_792_324_800), azimuth: 100, altitude: 50,
                                      rangeKilometers: 600, isSunlit: true, magnitude: nil)
        let pass = SatellitePass(rise: peak, culmination: peak, set: peak, visibleIntervals: [], brightest: nil,
                                 isRiseCut: false, isSetCut: false)
        let item = SatellitePassItem(satellite: satellite, group: .visual, pass: pass, peak: peak)
        return SatelliteAimSource.follow(item, observer: observer)
    }

    func testThereIsNoSatelliteTargetAtFirst() {
        XCTAssertNil(SatelliteAimSession().source)
    }

    func testStartingLeadsAimToTheSource() throws {
        let session = SatelliteAimSession()
        let chosen = try source(title: "ONE")
        session.start(chosen)
        XCTAssertEqual(session.source?.id, chosen.id)
        XCTAssertEqual(session.source?.title, "ONE")
    }

    func testStartingAnotherSourceReplacesTheFirst() throws {
        let session = SatelliteAimSession()
        session.start(try source(title: "ONE"))
        let second = try source(title: "TWO")
        session.start(second)
        XCTAssertEqual(session.source?.id, second.id)
        XCTAssertEqual(session.source?.title, "TWO")
    }

    func testStoppingGoesBackToTheOrdinaryTarget() throws {
        let session = SatelliteAimSession()
        session.start(try source(title: "ONE"))
        session.stop()
        XCTAssertNil(session.source)
        // Stopping twice is harmless.
        session.stop()
        XCTAssertNil(session.source)
    }

    func testStoppingWithNoSourceAnnouncesNoChange() throws {
        let session = SatelliteAimSession()
        let flag = Flag()
        withObservationTracking { _ = session.source } onChange: { flag.raised = true }
        session.stop()
        XCTAssertFalse(flag.raised, "nothing changed, so nobody is told")
        session.start(try source(title: "ONE"))
        XCTAssertTrue(flag.raised, "choosing a satellite is announced to the views that read it")
    }
}

import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// A scripted source of motion samples: `latestSample()` returns the sample the test chose, and `sample(at:)` the stored
/// past sample closest to the asked time, if it is within a quarter of a second of it. It records the times asked for.
private final class AimEngineScriptedSource: MotionSampleSource, @unchecked Sendable {
    private let lock = NSLock()
    private var newest: MotionSample?
    private var past: [MotionSample] = []
    private var asked: [TimeInterval] = []

    func setNewest(_ sample: MotionSample?) {
        lock.lock()
        newest = sample
        lock.unlock()
    }

    func setPast(_ samples: [MotionSample]) {
        lock.lock()
        past = samples
        lock.unlock()
    }

    var timesAskedFor: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func latestSample() -> MotionSample? {
        lock.lock()
        defer { lock.unlock() }
        return newest
    }

    func sample(at time: TimeInterval) -> MotionSample? {
        lock.lock()
        defer { lock.unlock() }
        asked.append(time)
        guard let nearest = past.min(by: { abs($0.timestamp - time) < abs($1.timestamp - time) }),
              abs(nearest.timestamp - time) <= 0.25 else { return nil }
        return nearest
    }
}

/// `AimFrameEngine`: the newest sample becomes a frame, the guidance leads to a mosaic panel, a satellite or the target
/// (in that order of precedence), and the on-target state of the trackers has hysteresis.
///
/// Geometry used throughout: the phone is held upright (back camera, portrait mount) and aims along the meridian
/// (azimuth 0) at an altitude the test chooses; the target is at azimuth 0, altitude 40. The separation is then exactly
/// the difference of the altitudes. The lens is 8 by 6 degrees, so the on-target threshold is 1.5 degrees (leaving it
/// takes 2.25) and the close threshold is 5 degrees.
@MainActor
final class AimEngineFrameTests: XCTestCase {
    private enum Fixture {
        static let catalog = Result { try Catalog.loadBundled() }
    }

    private let source = AimEngineScriptedSource()

    // MARK: Helpers

    /// A phone held upright that aims the back camera at (`azimuth`, `altitude`), turned `roll` degrees clockwise about
    /// the optical axis (seen by the photographer).
    private func makeAttitude(azimuth: Double, altitude: Double, roll: Double = 0, timestamp: TimeInterval = 0) throws -> DeviceAttitude {
        let az = AstroMath.radians(azimuth), alt = AstroMath.radians(altitude), rho = AstroMath.radians(roll)
        let forward = Vector3(cos(alt) * sin(az), cos(alt) * cos(az), sin(alt))
        let levelRight = Vector3(cos(az), -sin(az), 0)
        let levelUp = Vector3(-sin(alt) * sin(az), -sin(alt) * cos(az), cos(alt))
        let right = levelRight * cos(rho) - levelUp * sin(rho)
        let up = levelUp * cos(rho) + levelRight * sin(rho)
        // The rows of the CoreMotion matrix are the device axes in the north-west-up frame.
        func row(_ axis: Vector3) -> Vector3 { Vector3(axis.y, -axis.x, axis.z) }
        let matrix = Matrix3(rows: row(right), row(up), row(forward * -1))
        return try XCTUnwrap(DeviceAttitude(matrix: matrix, referenceAzimuth: 0, timestamp: timestamp))
    }

    private func makeSample(azimuth: Double, altitude: Double, roll: Double = 0, timestamp: TimeInterval = 1) throws -> MotionSample {
        let attitude = try makeAttitude(azimuth: azimuth, altitude: altitude, roll: roll, timestamp: timestamp)
        return MotionSample(attitude: attitude, rawAttitude: attitude, gravity: Vector3(0, -1, 0), angularSpeed: 0,
                            magneticFieldMicrotesla: nil, compassQuality: .high, timestamp: timestamp)
    }

    private func pointingAt(azimuth: Double, altitude: Double, roll: Double = 0) throws -> PointingSolution {
        PointingSolution.solve(attitude: try makeAttitude(azimuth: azimuth, altitude: altitude, roll: roll), mount: .backCameraPortrait)
    }

    private func configuration(mount: MountProfile = .backCameraPortrait, alignment: AlignmentModel = .identity,
                               lens: FrameSize = FrameSize(horizontal: 8, vertical: 6, diagonal: 10)) -> AimConfiguration {
        AimConfiguration(mount: mount, alignment: alignment, lensFrame: lens, showConstellationLines: true,
                         showConstellationNames: true, showDeepSkyObjects: true, showMilkyWay: true, deepSkyProminence: 2,
                         starMagnitudeLimit: 5, wantsCameraPreview: false, isNight: false)
    }

    private func makeEngine(_ configuration: AimConfiguration? = nil) -> AimFrameEngine {
        AimFrameEngine(motion: source, configuration: configuration ?? self.configuration())
    }

    private func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try Fixture.catalog.get().object(id: id), id)
    }

    private func skyTarget(_ object: CelestialObject, azimuth: Double = 0, altitude: Double = 40) -> SkySnapshot.Target {
        let place = HorizontalCoordinate(azimuth: azimuth, altitude: altitude)
        return SkySnapshot.Target(object: object, direction: place.unitVector, horizontal: place)
    }

    /// Chooses the target and gives it its position, the way the view model does after a sky rebuild.
    @discardableResult
    private func track(_ engine: AimFrameEngine, _ id: String, azimuth: Double = 0, altitude: Double = 40) throws -> CelestialObject {
        let target = try object(id)
        engine.setTarget(id: id)
        engine.update(target: skyTarget(target, azimuth: azimuth, altitude: altitude))
        return target
    }

    private func mosaicAim(panel: Int = 0, azimuth: Double = 0, altitude: Double = 40, roll: Double = 0,
                           orientation: MosaicOrientation = .landscape, threshold: Double = 2) -> AimMosaicAim {
        AimMosaicAim(panelIndex: panel, horizontal: HorizontalCoordinate(azimuth: azimuth, altitude: altitude), roll: roll,
                     orientation: orientation, isAboveHorizon: altitude > 0, lowestAltitude: altitude - 3,
                     onTargetThreshold: threshold)
    }

    private func satelliteFix(azimuth: Double, altitude: Double, label: String = "ISS",
                              secondsToPeak: Double? = nil) -> SatelliteAimFix {
        SatelliteAimFix(horizontal: HorizontalCoordinate(azimuth: azimuth, altitude: altitude), label: label, look: nil,
                        secondsToPeak: secondsToPeak)
    }

    /// Points the phone at the meridian at `altitude` and asks the engine for the frame.
    private func frameAt(_ engine: AimFrameEngine, altitude: Double, azimuth: Double = 0, roll: Double = 0,
                       timestamp: TimeInterval = 1) throws -> AimFrame {
        source.setNewest(try makeSample(azimuth: azimuth, altitude: altitude, roll: roll, timestamp: timestamp))
        return try XCTUnwrap(engine.frame())
    }

    /// The guidance state of the frames the phone sees at each altitude in turn.
    private func guidanceStates(_ engine: AimFrameEngine, altitudes: [Double]) throws -> [GuidanceState] {
        var states: [GuidanceState] = []
        for (index, altitude) in altitudes.enumerated() {
            let frame = try frameAt(engine, altitude: altitude, timestamp: Double(index + 1))
            states.append(try XCTUnwrap(frame.guidance).state)
        }
        return states
    }

    private func assertDirection(_ actual: HorizontalCoordinate, azimuth: Double, altitude: Double, accuracy: Double = 1e-6,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(actual.azimuth - azimuth), 0, accuracy: accuracy, "azimuth",
                       file: file, line: line)
        XCTAssertEqual(actual.altitude, altitude, accuracy: accuracy, "altitude", file: file, line: line)
    }

    // MARK: Without sensors

    func testWithoutASampleThereIsNoFrame() {
        let engine = makeEngine()
        XCTAssertNil(engine.frame())
    }

    func testWithoutASampleAFrameForACameraTimeIsNoFrameEitherAndNothingIsLookedUp() {
        let engine = makeEngine()
        XCTAssertNil(engine.frame(capturedAt: 12.5))
        XCTAssertNil(engine.frame(capturedAt: nil))
        XCTAssertEqual(source.timesAskedFor, [])
    }

    // MARK: The pointing in a frame

    func testAFrameCarriesTheNewestSampleAndWhereTheCameraPoints() throws {
        let engine = makeEngine()
        let frame = try frameAt(engine, altitude: 20, azimuth: 90, timestamp: 7)
        XCTAssertEqual(frame.sample.timestamp, 7)
        assertDirection(frame.pointing.boresight, azimuth: 90, altitude: 20)
        XCTAssertEqual(frame.pointing.roll, 0, accuracy: 1e-6)
        XCTAssertEqual(frame.pointing.boresightVector.length, 1, accuracy: 1e-12)
    }

    func testAFrameWithoutATargetMosaicOrSatelliteHasNoGuidance() throws {
        let engine = makeEngine()
        let frame = try frameAt(engine, altitude: 20, azimuth: 90)
        XCTAssertNil(frame.guidance)
        XCTAssertNil(frame.target)
        XCTAssertNil(frame.mosaic)
        XCTAssertNil(frame.satellite)
    }

    func testEachFrameFollowsTheNewestSample() throws {
        let engine = makeEngine()
        let first = try frameAt(engine, altitude: 20, azimuth: 90, timestamp: 1)
        assertDirection(first.pointing.boresight, azimuth: 90, altitude: 20)
        let second = try frameAt(engine, altitude: 35, azimuth: 200, timestamp: 2)
        XCTAssertEqual(second.sample.timestamp, 2)
        assertDirection(second.pointing.boresight, azimuth: 200, altitude: 35)
        source.setNewest(nil)
        XCTAssertNil(engine.frame())
    }

    func testTheRollOfTheCameraIsPartOfThePointing() throws {
        let engine = makeEngine()
        let frame = try frameAt(engine, altitude: 30, azimuth: 120, roll: 25)
        XCTAssertEqual(frame.pointing.roll, 25, accuracy: 1e-6)
        assertDirection(frame.pointing.boresight, azimuth: 120, altitude: 30)
    }

    func testTheMountOfTheConfigurationDecidesWhichWayIsUp() throws {
        let engine = makeEngine(configuration(mount: .backCameraPortraitUpsideDown))
        let frame = try frameAt(engine, altitude: 20, azimuth: 90)
        assertDirection(frame.pointing.boresight, azimuth: 90, altitude: 20)
        XCTAssertEqual(abs(frame.pointing.roll), 180, accuracy: 1e-6)
    }

    func testAnAlignmentSolvedForTheMountTurnsTheAzimuthByItsHeadingOffset() throws {
        // The phone reports azimuth 0 while the camera really looks at azimuth 10: the compass is 10 degrees off.
        let reported = try makeAttitude(azimuth: 0, altitude: 30)
        let point = AlignmentPoint(attitude: reported, target: HorizontalCoordinate(azimuth: 10, altitude: 30),
                                   timestamp: Date(timeIntervalSince1970: 0))
        let alignment = try AlignmentModel.solve(points: [point], mount: .backCameraPortrait)
        XCTAssertEqual(alignment.headingOffset, 10, accuracy: 1e-6)
        let engine = makeEngine(configuration(alignment: alignment))
        let frame = try frameAt(engine, altitude: 30, azimuth: 0)
        assertDirection(frame.pointing.boresight, azimuth: 10, altitude: 30)
    }

    func testAnAlignmentSolvedForAnotherMountIsNotApplied() throws {
        let reported = try makeAttitude(azimuth: 0, altitude: 30)
        let point = AlignmentPoint(attitude: reported, target: HorizontalCoordinate(azimuth: 10, altitude: 30),
                                   timestamp: Date(timeIntervalSince1970: 0))
        let alignment = try AlignmentModel.solve(points: [point], mount: .backCameraPortrait)
        let engine = makeEngine(configuration(mount: .backCameraPortraitUpsideDown, alignment: alignment))
        let frame = try frameAt(engine, altitude: 30, azimuth: 0)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 30)
    }

    func testConfigureTakesOverANewAlignmentForTheNextFrame() throws {
        let engine = makeEngine()
        assertDirection(try frameAt(engine, altitude: 30, azimuth: 0).pointing.boresight, azimuth: 0, altitude: 30)
        let point = AlignmentPoint(attitude: try makeAttitude(azimuth: 0, altitude: 30),
                                   target: HorizontalCoordinate(azimuth: 10, altitude: 30),
                                   timestamp: Date(timeIntervalSince1970: 0))
        let alignment = try AlignmentModel.solve(points: [point], mount: .backCameraPortrait)
        engine.configure(configuration(alignment: alignment))
        assertDirection(try frameAt(engine, altitude: 30, azimuth: 0).pointing.boresight, azimuth: 10, altitude: 30)
    }

    // MARK: Guidance to the target

    func testThereIsNoGuidanceUntilTheTargetsPositionIsKnown() throws {
        let engine = makeEngine()
        engine.setTarget(id: "dso.M31")
        let before = try frameAt(engine, altitude: 30)
        XCTAssertNil(before.guidance)
        XCTAssertNil(before.target)
        engine.update(target: skyTarget(try object("dso.M31")))
        let after = try frameAt(engine, altitude: 30)
        XCTAssertNotNil(after.guidance)
        XCTAssertEqual(after.target?.object.id, "dso.M31")
    }

    func testGuidanceTellsHowFarAndWhichWayToTurnToTheTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        let guidance = try XCTUnwrap(try frameAt(engine, altitude: 30).guidance)
        XCTAssertEqual(guidance.separation, 10, accuracy: 1e-9)
        XCTAssertEqual(guidance.tiltDelta, 10, accuracy: 1e-9)
        XCTAssertEqual(guidance.panDelta, 0, accuracy: 1e-6)
        XCTAssertEqual(guidance.state, .far)
        XCTAssertTrue(guidance.isTargetInFront)
        XCTAssertFalse(guidance.targetBelowHorizon)
        XCTAssertFalse(guidance.isNearZenith)
    }

    func testGuidanceToATargetToTheRightIsAPanRight() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 120, altitude: 30)
        let guidance = try XCTUnwrap(try frameAt(engine, altitude: 30, azimuth: 90).guidance)
        XCTAssertEqual(guidance.panDelta, 30, accuracy: 1e-6)
        XCTAssertEqual(guidance.tiltDelta, 0, accuracy: 1e-6)
        let other = try XCTUnwrap(try frameAt(engine, altitude: 30, azimuth: 150).guidance)
        XCTAssertEqual(other.panDelta, -30, accuracy: 1e-6)
    }

    func testTheFrameCarriesTheTargetsPositionFromTheLastSkyRebuild() throws {
        let engine = makeEngine()
        let moon = try track(engine, "moon", azimuth: 55, altitude: 12)
        let frame = try frameAt(engine, altitude: 30)
        let target = try XCTUnwrap(frame.target)
        XCTAssertEqual(target.object.id, moon.id)
        assertDirection(target.horizontal, azimuth: 55, altitude: 12, accuracy: 1e-12)
        XCTAssertNil(frame.mosaic)
        XCTAssertNil(frame.satellite)
    }

    func testAPositionForAnotherObjectIsIgnored() throws {
        let engine = makeEngine()
        engine.setTarget(id: "dso.M31")
        engine.update(target: skyTarget(try object("moon")))
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNil(frame.guidance)
        XCTAssertNil(frame.target)
    }

    func testAnUpdateWithoutAPositionKeepsTheLastOne() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.update(target: nil)
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNotNil(frame.guidance)
        XCTAssertEqual(frame.target?.object.id, "dso.M31")
    }

    func testANewPositionOfTheSameTargetReplacesTheOldOne() throws {
        let engine = makeEngine()
        let object = try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        XCTAssertEqual(try XCTUnwrap(try frameAt(engine, altitude: 30).guidance).tiltDelta, 10, accuracy: 1e-9)
        engine.update(target: skyTarget(object, azimuth: 0, altitude: 45))
        XCTAssertEqual(try XCTUnwrap(try frameAt(engine, altitude: 30).guidance).tiltDelta, 15, accuracy: 1e-9)
    }

    func testChoosingTheSameTargetAgainKeepsItsPosition() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.setTarget(id: "dso.M31")
        XCTAssertNotNil(try frameAt(engine, altitude: 30).guidance)
    }

    func testChoosingAnotherTargetForgetsThePositionUntilItsOwnArrives() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.setTarget(id: "moon")
        let forgotten = try frameAt(engine, altitude: 30)
        XCTAssertNil(forgotten.guidance)
        XCTAssertNil(forgotten.target)
        engine.update(target: skyTarget(try object("moon"), azimuth: 0, altitude: 50))
        let found = try frameAt(engine, altitude: 30)
        XCTAssertEqual(found.target?.object.id, "moon")
        XCTAssertEqual(try XCTUnwrap(found.guidance).tiltDelta, 20, accuracy: 1e-9)
    }

    func testChoosingNoTargetEndsTheGuidance() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.setTarget(id: nil)
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNil(frame.guidance)
        XCTAssertNil(frame.target)
    }

    func testChoosingAnotherTargetStartsTheOnTargetStateAfresh() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        // 1.0 degrees away puts the camera on target; 2.0 degrees is inside the hysteresis band, so it stays.
        XCTAssertEqual(try guidanceStates(engine, altitudes: [39, 38]), [.onTarget, .onTarget])
        try track(engine, "moon")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38]), [.close])
    }

    // MARK: The on-target state

    func testTheStateFollowsTheSeparationAcrossTheThresholdsWithHysteresis() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        // Separations 10, 4, 1.2, 2.0, 2.5, 4, 10 degrees.
        let states = try guidanceStates(engine, altitudes: [30, 36, 38.8, 38.0, 37.5, 36, 30])
        XCTAssertEqual(states, [.far, .close, .onTarget, .onTarget, .close, .close, .far])
    }

    func testWithinTheHysteresisBandACameraThatWasNotOnTargetStaysOff() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [36, 38.0, 38.4]), [.close, .close, .close])
    }

    func testTheOnTargetThresholdIsOneAndAHalfDegreesForThisLens() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.6]), [.onTarget])
        let strict = makeEngine()
        try track(strict, "dso.M31")
        XCTAssertEqual(try guidanceStates(strict, altitudes: [38.4]), [.close])
    }

    func testTheCloseThresholdIsFiveDegrees() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [35.1, 34.9]), [.close, .far])
    }

    func testAskingAgainForTheSameSampleGivesTheSameGuidance() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        let first = try frameAt(engine, altitude: 38.8)
        let second = try XCTUnwrap(engine.frame())
        let third = try XCTUnwrap(engine.frame())
        XCTAssertEqual(first.guidance, second.guidance)
        XCTAssertEqual(second.guidance, third.guidance)
        XCTAssertEqual(first.guidance?.state, .onTarget)
        XCTAssertEqual(first.sample.timestamp, third.sample.timestamp)
    }

    func testAskingAgainInTheHysteresisBandKeepsTheStateItReachedItFrom() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        for _ in 0..<3 {
            XCTAssertEqual(try XCTUnwrap(engine.frame()).guidance?.state, .onTarget)
        }
    }

    // MARK: Configuring

    func testANarrowerLensChangesTheThresholdAndStartsTheTrackerAfresh() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8]), [.onTarget])
        // A 4 by 2 degree lens has a threshold of 0.5 degrees: 1.2 degrees away is no longer on target.
        engine.configure(configuration(lens: FrameSize(horizontal: 4, vertical: 2, diagonal: 5)))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8]), [.close])
        XCTAssertEqual(try guidanceStates(engine, altitudes: [39.7]), [.onTarget])
    }

    func testAWiderLensRaisesTheThreshold() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        // 6 degrees away is far for the 8 by 6 degree lens (close takes less than 5).
        XCTAssertEqual(try guidanceStates(engine, altitudes: [34]), [.far])
        // 40 by 30 degrees: threshold 7.5 degrees (leaving it takes 11.25), close threshold 22.5 degrees.
        engine.configure(configuration(lens: FrameSize(horizontal: 40, vertical: 30, diagonal: 50)))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [34, 20, 10]), [.onTarget, .close, .far])
    }

    func testConfiguringWithTheSameThresholdKeepsTheOnTargetState() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        var night = configuration()
        night.isNight = true
        engine.configure(night)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.onTarget])
        // Another lens with the same short side gives the same threshold, so the state is kept as well.
        engine.configure(configuration(lens: FrameSize(horizontal: 10, vertical: 6, diagonal: 12)))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.onTarget])
    }

    func testConfigureKeepsTheTargetAndItsPosition() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.configure(configuration(lens: FrameSize(horizontal: 2, vertical: 1, diagonal: 2.5)))
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertEqual(frame.target?.object.id, "dso.M31")
        XCTAssertEqual(try XCTUnwrap(frame.guidance).tiltDelta, 10, accuracy: 1e-9)
    }

    // MARK: Guidance to a mosaic panel

    func testAMosaicLeadsTheGuidanceToItsPanel() throws {
        let engine = makeEngine()
        let aim = mosaicAim(panel: 4, azimuth: 90, altitude: 20)
        engine.setMosaic(active: true, aim: aim)
        let frame = try frameAt(engine, altitude: 20, azimuth: 60)
        let guidance = try XCTUnwrap(frame.guidance)
        XCTAssertEqual(guidance.panDelta, 30, accuracy: 1e-6)
        XCTAssertEqual(guidance.tiltDelta, 0, accuracy: 1e-6)
        XCTAssertEqual(guidance.state, .far)
        let mosaic = try XCTUnwrap(frame.mosaic)
        XCTAssertEqual(mosaic.aim, aim)
        XCTAssertEqual(mosaic.rollDelta, 0, accuracy: 1e-6)
        XCTAssertNil(frame.target)
        XCTAssertNil(frame.satellite)
    }

    func testAMosaicTakesTheGuidanceFromAChosenTarget() throws {
        // The engine knows a target only as "the object to lead to"; a running mosaic replaces it, whatever it is.
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        engine.setMosaic(active: true, aim: mosaicAim(azimuth: 90, altitude: 20))
        let frame = try frameAt(engine, altitude: 20, azimuth: 60)
        XCTAssertEqual(try XCTUnwrap(frame.guidance).panDelta, 30, accuracy: 1e-6)
        XCTAssertNil(frame.target)
        XCTAssertNotNil(frame.mosaic)
    }

    func testAMosaicTakesTheGuidanceFromASatellite() throws {
        let engine = makeEngine()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: UUID())
        engine.setMosaic(active: true, aim: mosaicAim(azimuth: 90, altitude: 20))
        let frame = try frameAt(engine, altitude: 20, azimuth: 60)
        XCTAssertEqual(try XCTUnwrap(frame.guidance).panDelta, 30, accuracy: 1e-6)
        XCTAssertNil(frame.satellite)
        XCTAssertNotNil(frame.mosaic)
    }

    func testAMosaicWithoutAPanelHasNoGuidanceAndHidesTheTarget() throws {
        // The mosaic is finished (`active` with no panel): nothing to lead to, and the target does not come back by itself.
        let engine = makeEngine()
        try track(engine, "dso.M31")
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: UUID())
        engine.setMosaic(active: true, aim: nil)
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNil(frame.guidance)
        XCTAssertNil(frame.mosaic)
        XCTAssertNil(frame.target)
        XCTAssertNil(frame.satellite)
    }

    func testEndingTheMosaicLeadsTheGuidanceBackToTheTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        engine.setMosaic(active: true, aim: mosaicAim(azimuth: 90, altitude: 20))
        XCTAssertNil(try frameAt(engine, altitude: 30).target)
        // A panel handed in with `active: false` is not used.
        engine.setMosaic(active: false, aim: mosaicAim(azimuth: 90, altitude: 20))
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNil(frame.mosaic)
        XCTAssertEqual(frame.target?.object.id, "dso.M31")
        XCTAssertEqual(try XCTUnwrap(frame.guidance).tiltDelta, 10, accuracy: 1e-9)
    }

    func testThePanelsToleranceDecidesWhenTheCameraIsOnIt() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(altitude: 40, threshold: 3))
        // 2.5 degrees away: on the panel (threshold 3), where the target's own threshold of 1.5 would say close.
        XCTAssertEqual(try guidanceStates(engine, altitudes: [37.5]), [.onTarget])
        let targetEngine = makeEngine()
        try track(targetEngine, "dso.M31")
        XCTAssertEqual(try guidanceStates(targetEngine, altitudes: [37.5]), [.close])
    }

    func testThePanelHasItsOwnHysteresis() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(altitude: 40, threshold: 2))
        // Separations 1.5 (on), 2.6 (kept: leaving takes more than 3), 3.1 (left), 2.6 (not on again below 2).
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5, 37.4, 36.9, 37.4]), [.onTarget, .onTarget, .close, .close])
    }

    func testARefreshOfTheSamePanelKeepsTheOnTargetState() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(panel: 3, altitude: 40, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.onTarget])
        // The sky has carried the panel one degree on: 2.5 degrees away now, inside the hysteresis band.
        engine.setMosaic(active: true, aim: mosaicAim(panel: 3, altitude: 41, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.onTarget])
    }

    func testANewPanelStartsTheOnTargetStateAfresh() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(panel: 3, altitude: 40, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.onTarget])
        engine.setMosaic(active: true, aim: mosaicAim(panel: 4, altitude: 41, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.close])
    }

    func testANewToleranceStartsTheOnTargetStateAfresh() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(panel: 3, altitude: 40, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.onTarget])
        engine.setMosaic(active: true, aim: mosaicAim(panel: 3, altitude: 40, threshold: 1.2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5]), [.close])
        XCTAssertEqual(try guidanceStates(engine, altitudes: [39.0]), [.onTarget])
    }

    func testLeavingTheMosaicAndComingBackStartsTheOnTargetStateAfresh() throws {
        let engine = makeEngine()
        let aim = mosaicAim(panel: 3, altitude: 40, threshold: 2)
        engine.setMosaic(active: true, aim: aim)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5, 37.5]), [.onTarget, .onTarget])
        engine.setMosaic(active: false, aim: nil)
        engine.setMosaic(active: true, aim: aim)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [37.5]), [.close])
    }

    func testAPanelWithNoPositionYetEndsTheOnTargetStateToo() throws {
        let engine = makeEngine()
        let aim = mosaicAim(panel: 3, altitude: 40, threshold: 2)
        engine.setMosaic(active: true, aim: aim)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.5, 37.5]), [.onTarget, .onTarget])
        engine.setMosaic(active: true, aim: nil)
        XCTAssertNil(try frameAt(engine, altitude: 37.5).guidance)
        engine.setMosaic(active: true, aim: aim)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [37.5]), [.close])
    }

    func testTheMosaicAndTheTargetKeepSeparateOnTargetStates() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        engine.setMosaic(active: true, aim: mosaicAim(panel: 0, altitude: 10, threshold: 2))
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.far])
        engine.setMosaic(active: false, aim: nil)
        // The target's tracker was not touched while the mosaic ran: 2.0 degrees is still inside its hysteresis band.
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.onTarget])
    }

    func testTheFrameOfAMosaicCarriesTheRollThePanelAsksFor() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(altitude: 30, roll: 50, orientation: .landscape))
        // A camera turned 20 degrees clockwise has to turn 30 more to match a panel at 50.
        let rolled = try frameAt(engine, altitude: 30, roll: 20)
        XCTAssertEqual(try XCTUnwrap(rolled.mosaic).rollDelta, 30, accuracy: 1e-6)
        XCTAssertEqual(rolled.pointing.roll, 20, accuracy: 1e-6)
        let matched = try frameAt(engine, altitude: 30, roll: 50)
        XCTAssertEqual(try XCTUnwrap(matched.mosaic).rollDelta, 0, accuracy: 1e-6)
        let past = try frameAt(engine, altitude: 30, roll: 80)
        XCTAssertEqual(try XCTUnwrap(past.mosaic).rollDelta, -30, accuracy: 1e-6)
    }

    func testAPortraitMosaicMeasuresTheRollWithTheCamerasRightSide() throws {
        let engine = makeEngine()
        // Held in portrait the panel's "up" is the camera's right, which leans 90 degrees more than the camera's up.
        engine.setMosaic(active: true, aim: mosaicAim(altitude: 30, roll: 110, orientation: .portrait))
        let frame = try frameAt(engine, altitude: 30, roll: 20)
        XCTAssertEqual(try XCTUnwrap(frame.mosaic).rollDelta, 0, accuracy: 1e-6)
        let turned = try frameAt(engine, altitude: 30, roll: 0)
        XCTAssertEqual(try XCTUnwrap(turned.mosaic).rollDelta, 20, accuracy: 1e-6)
    }

    // MARK: Guidance to a satellite

    func testASatelliteLeadsTheGuidanceInsteadOfTheTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        engine.setSatellite(satelliteFix(azimuth: 120, altitude: 30, label: "ISS", secondsToPeak: 95), sourceID: UUID())
        let frame = try frameAt(engine, altitude: 30, azimuth: 90)
        XCTAssertEqual(try XCTUnwrap(frame.guidance).panDelta, 30, accuracy: 1e-6)
        XCTAssertNil(frame.target)
        XCTAssertNil(frame.mosaic)
        let fix = try XCTUnwrap(frame.satellite)
        XCTAssertEqual(fix.label, "ISS")
        XCTAssertEqual(fix.secondsToPeak, 95)
        assertDirection(fix.horizontal, azimuth: 120, altitude: 30, accuracy: 1e-12)
    }

    func testASatelliteLeadsTheGuidanceWithoutAnyTarget() throws {
        let engine = makeEngine()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: UUID())
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertEqual(try XCTUnwrap(frame.guidance).tiltDelta, 10, accuracy: 1e-9)
        XCTAssertNotNil(frame.satellite)
        XCTAssertNil(frame.target)
    }

    func testEndingTheSatelliteLeadsTheGuidanceBackToTheTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 45)
        let id = UUID()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: id)
        XCTAssertEqual(engine.satelliteSourceID, id)
        XCTAssertEqual(try XCTUnwrap(try frameAt(engine, altitude: 30).guidance).tiltDelta, 10, accuracy: 1e-9)
        engine.setSatellite(nil, sourceID: nil)
        XCTAssertNil(engine.satelliteSourceID)
        let frame = try frameAt(engine, altitude: 30)
        XCTAssertNil(frame.satellite)
        XCTAssertEqual(frame.target?.object.id, "dso.M31")
        XCTAssertEqual(try XCTUnwrap(frame.guidance).tiltDelta, 15, accuracy: 1e-9)
    }

    func testTheSourceOfTheSatelliteIsRemembered() {
        let engine = makeEngine()
        XCTAssertNil(engine.satelliteSourceID)
        let first = UUID(), second = UUID()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: first)
        XCTAssertEqual(engine.satelliteSourceID, first)
        engine.setSatellite(satelliteFix(azimuth: 5, altitude: 41), sourceID: first)
        XCTAssertEqual(engine.satelliteSourceID, first)
        engine.setSatellite(satelliteFix(azimuth: 5, altitude: 41), sourceID: second)
        XCTAssertEqual(engine.satelliteSourceID, second)
    }

    func testASatelliteIsFollowedFromItsNewFixAtEveryTick() throws {
        let engine = makeEngine()
        let id = UUID()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: id)
        XCTAssertEqual(try XCTUnwrap(try frameAt(engine, altitude: 30).guidance).tiltDelta, 10, accuracy: 1e-9)
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 50), sourceID: id)
        XCTAssertEqual(try XCTUnwrap(try frameAt(engine, altitude: 30).guidance).tiltDelta, 20, accuracy: 1e-9)
    }

    func testTheSameSourceKeepsTheOnTargetStateAndANewOneStartsAfresh() throws {
        let engine = makeEngine()
        let id = UUID()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: id)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40, secondsToPeak: 3), sourceID: id)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.onTarget])
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: UUID())
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.close])
    }

    func testEndingTheSatelliteStartsTheOnTargetStateAfresh() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        let id = UUID()
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 40), sourceID: id)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        // The satellite and the target share one tracker, which starts afresh when the source goes.
        engine.setSatellite(nil, sourceID: nil)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.close])
    }

    func testAnUnchangedMissingSourceDoesNotResetTheTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.8, 38.0]), [.onTarget, .onTarget])
        engine.setSatellite(nil, sourceID: nil)
        XCTAssertEqual(try guidanceStates(engine, altitudes: [38.0]), [.onTarget])
    }

    // MARK: The order of precedence

    func testMosaicBeatsSatelliteAndSatelliteBeatsTarget() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 40, altitude: 30)
        engine.setSatellite(satelliteFix(azimuth: 20, altitude: 30), sourceID: UUID())
        engine.setMosaic(active: true, aim: mosaicAim(azimuth: 10, altitude: 30))
        // The phone looks at azimuth 0, altitude 30: the three places are 40, 20 and 10 degrees to the right.
        let withMosaic = try frameAt(engine, altitude: 30)
        XCTAssertEqual(try XCTUnwrap(withMosaic.guidance).panDelta, 10, accuracy: 1e-6)
        XCTAssertNotNil(withMosaic.mosaic)
        XCTAssertNil(withMosaic.satellite)
        XCTAssertNil(withMosaic.target)

        engine.setMosaic(active: false, aim: nil)
        let withSatellite = try frameAt(engine, altitude: 30)
        XCTAssertEqual(try XCTUnwrap(withSatellite.guidance).panDelta, 20, accuracy: 1e-6)
        XCTAssertNil(withSatellite.mosaic)
        XCTAssertNotNil(withSatellite.satellite)
        XCTAssertNil(withSatellite.target)

        engine.setSatellite(nil, sourceID: nil)
        let withTarget = try frameAt(engine, altitude: 30)
        XCTAssertEqual(try XCTUnwrap(withTarget.guidance).panDelta, 40, accuracy: 1e-6)
        XCTAssertNil(withTarget.mosaic)
        XCTAssertNil(withTarget.satellite)
        XCTAssertNotNil(withTarget.target)
    }

    // MARK: The frame for a camera picture

    func testWithoutATimeTheFrameForACameraPictureIsTheNewestFrame() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 99)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, timestamp: 100))
        let frame = try XCTUnwrap(engine.frame(capturedAt: nil))
        XCTAssertEqual(frame.sample.timestamp, 100)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 30)
        XCTAssertEqual(source.timesAskedFor, [])
    }

    func testTheFrameForACameraPictureUsesTheAttitudeOfThatMoment() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31", azimuth: 0, altitude: 40)
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 99.8),
                        try makeSample(azimuth: 0, altitude: 25, timestamp: 99.9),
                        try makeSample(azimuth: 0, altitude: 30, timestamp: 100)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, timestamp: 100))
        let frame = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(frame.sample.timestamp, 99.9)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 25)
        XCTAssertEqual(source.timesAskedFor, [99.9])
        // The guidance stays as of the newest sample, which is 10 degrees below the target, not 15.
        let guidance = try XCTUnwrap(frame.guidance)
        XCTAssertEqual(guidance.tiltDelta, 10, accuracy: 1e-9)
        XCTAssertEqual(guidance.separation, 10, accuracy: 1e-9)
        XCTAssertEqual(frame.target?.object.id, "dso.M31")
    }

    func testTheLookupFindsTheSampleClosestToTheCameraTime() throws {
        let engine = makeEngine()
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 99.8),
                        try makeSample(azimuth: 0, altitude: 25, timestamp: 99.9)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, timestamp: 100))
        let frame = try XCTUnwrap(engine.frame(capturedAt: 99.84))
        XCTAssertEqual(frame.sample.timestamp, 99.8)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 20)
    }

    func testWhenNoSampleIsKeptForThatTimeTheNewestFrameIsUsed() throws {
        let engine = makeEngine()
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 50)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, timestamp: 100))
        let frame = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(frame.sample.timestamp, 100)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 30)
        XCTAssertEqual(source.timesAskedFor, [99.9])
    }

    func testWhenTheSampleOfThatTimeIsTheNewestOneTheFrameIsTheNewestFrame() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        let newest = try makeSample(azimuth: 0, altitude: 38.8, timestamp: 100)
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 99), newest])
        source.setNewest(newest)
        let frame = try XCTUnwrap(engine.frame(capturedAt: 100))
        XCTAssertEqual(frame.sample.timestamp, 100)
        assertDirection(frame.pointing.boresight, azimuth: 0, altitude: 38.8)
        XCTAssertEqual(frame.guidance?.state, .onTarget)
        XCTAssertEqual(source.timesAskedFor, [100])
    }

    func testTheGuidanceOfAFrameForACameraPictureIsThatOfTheNewestSampleEveryTime() throws {
        let engine = makeEngine()
        try track(engine, "dso.M31")
        source.setPast([try makeSample(azimuth: 0, altitude: 20, timestamp: 99.9)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 38.8, timestamp: 100))
        // The newest sample is on target, the sample of the picture far from it: the state is the newest one.
        let first = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(first.guidance?.state, .onTarget)
        XCTAssertEqual(first.sample.timestamp, 99.9)
        let second = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(second.guidance, first.guidance)
    }

    func testTheFrameForACameraPictureKeepsTheMosaicAndTheSatelliteOfTheNewestFrame() throws {
        let engine = makeEngine()
        engine.setMosaic(active: true, aim: mosaicAim(panel: 2, azimuth: 0, altitude: 40, roll: 10))
        source.setPast([try makeSample(azimuth: 0, altitude: 25, roll: 30, timestamp: 99.9)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, roll: 0, timestamp: 100))
        let mosaicFrame = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(mosaicFrame.pointing.roll, 30, accuracy: 1e-6)
        let mosaic = try XCTUnwrap(mosaicFrame.mosaic)
        XCTAssertEqual(mosaic.aim.panelIndex, 2)
        // Worked out from the newest attitude (roll 0): 10 to turn, not -20.
        XCTAssertEqual(mosaic.rollDelta, 10, accuracy: 1e-6)
        XCTAssertNil(mosaicFrame.satellite)

        engine.setMosaic(active: false, aim: nil)
        engine.setSatellite(satelliteFix(azimuth: 0, altitude: 45, label: "Starlink"), sourceID: UUID())
        let satelliteFrame = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(satelliteFrame.sample.timestamp, 99.9)
        XCTAssertEqual(satelliteFrame.satellite?.label, "Starlink")
        XCTAssertEqual(try XCTUnwrap(satelliteFrame.guidance).tiltDelta, 15, accuracy: 1e-9)
        XCTAssertNil(satelliteFrame.mosaic)
    }

    func testThePastFrameUsesTheMountAndAlignmentOfTheConfiguration() throws {
        let engine = makeEngine(configuration(mount: .backCameraPortraitUpsideDown))
        source.setPast([try makeSample(azimuth: 0, altitude: 25, timestamp: 99.9)])
        source.setNewest(try makeSample(azimuth: 0, altitude: 30, timestamp: 100))
        let frame = try XCTUnwrap(engine.frame(capturedAt: 99.9))
        XCTAssertEqual(frame.sample.timestamp, 99.9)
        XCTAssertEqual(abs(frame.pointing.roll), 180, accuracy: 1e-6)
    }

    // MARK: The roll a panel asks for

    func testTheRollDeltaIsTheTurnFromTheCamerasRollToThePanelsRoll() throws {
        let level = try pointingAt(azimuth: 0, altitude: 0)
        let cases: [(panel: Double, expected: Double)] = [(0, 0), (30, 30), (-30, -30), (60, 60), (-60, -60)]
        for (panel, expected) in cases {
            let aim = mosaicAim(roll: panel, orientation: .landscape)
            XCTAssertEqual(AimFrameEngine.rollDelta(for: aim, pointing: level), expected, accuracy: 1e-6, "panel roll \(panel)")
        }
        let rolled = try pointingAt(azimuth: 0, altitude: 0, roll: 20)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 50), pointing: rolled), 30, accuracy: 1e-6)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: -50), pointing: rolled), -70, accuracy: 1e-6)
    }

    func testAPanelIsTheSameRectangleHalfACircleOnSoTheSmallerTurnIsReported() throws {
        let level = try pointingAt(azimuth: 0, altitude: 0)
        let cases: [(panel: Double, expected: Double)] = [
            (89, 89), (91, -89), (120, -60), (150, -30), (179, -1), (180, 0),
            (-89, -89), (-91, 89), (-120, 60), (-150, 30), (-179, 1),
        ]
        for (panel, expected) in cases {
            let aim = mosaicAim(roll: panel, orientation: .landscape)
            XCTAssertEqual(AimFrameEngine.rollDelta(for: aim, pointing: level), expected, accuracy: 1e-6, "panel roll \(panel)")
        }
    }

    func testTheRollDeltaIsNeverBeyondNinetyDegreesEitherWay() throws {
        for camera in stride(from: -170.0, through: 170.0, by: 20.0) {
            let pointing = try pointingAt(azimuth: 40, altitude: 25, roll: camera)
            for panel in stride(from: -175.0, through: 175.0, by: 25.0) {
                let delta = AimFrameEngine.rollDelta(for: mosaicAim(roll: panel), pointing: pointing)
                XCTAssertLessThanOrEqual(abs(delta), 90 + 1e-6, "camera \(camera), panel \(panel)")
            }
        }
    }

    func testTheRollDeltaWorksForACameraAimedHighAtAnyAzimuth() throws {
        // Aimed 60 degrees up at azimuth 200 the camera still has a clear sense of level.
        let pointing = try pointingAt(azimuth: 200, altitude: 60, roll: 15)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 45), pointing: pointing), 30, accuracy: 1e-6)
    }

    func testAPortraitPanelReadsTheCamerasRightSideAsItsUp() throws {
        let level = try pointingAt(azimuth: 0, altitude: 0)
        // The camera's right leans 90 degrees clockwise of the level for a camera with roll 0.
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 90, orientation: .portrait), pointing: level), 0, accuracy: 1e-6)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 100, orientation: .portrait), pointing: level), 10, accuracy: 1e-6)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 80, orientation: .portrait), pointing: level), -10, accuracy: 1e-6)
        let rolled = try pointingAt(azimuth: 0, altitude: 0, roll: 10)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 100, orientation: .portrait), pointing: rolled), 0, accuracy: 1e-6)
    }

    func testAtTheZenithTheCameraHasNoRollSoThePanelsRollIsTheTurn() throws {
        let zenith = try pointingAt(azimuth: 0, altitude: 90, roll: 33)
        XCTAssertEqual(AimFrameEngine.rollDelta(for: mosaicAim(roll: 40), pointing: zenith), 40, accuracy: 1e-6)
    }
}

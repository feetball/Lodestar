import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// What the Aim screen aims and draws with: the configuration gathered from the preferences, the inputs the sky snapshot
/// depends on, the sheets, the rise information for the below-horizon warning, and the tolerance of a mosaic panel.
final class AimEngineConfigurationTests: XCTestCase {
    private enum Fixture {
        static let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
        static let sydney = Observer(location: GeographicLocation(latitude: -33.87, longitude: 151.21, elevation: 20))
        /// 2026-07-16 05:00 UTC, 23:00 in Colorado.
        static let july = Date(timeIntervalSince1970: 1_784_178_000)
        static let catalog = Result { try Catalog.loadBundled() }
    }

    // MARK: Helpers

    private func configuration(mount: MountProfile = .backCameraPortrait, alignment: AlignmentModel = .identity,
                               lens: FrameSize = FrameSize(horizontal: 8, vertical: 6, diagonal: 10)) -> AimConfiguration {
        AimConfiguration(mount: mount, alignment: alignment, lensFrame: lens, showConstellationLines: true,
                         showConstellationNames: true, showDeepSkyObjects: true, showMilkyWay: true, deepSkyProminence: 2,
                         starMagnitudeLimit: 5, wantsCameraPreview: false, isNight: false)
    }

    private func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try Fixture.catalog.get().object(id: id), id)
    }

    /// A mount whose camera looks `tilt` degrees away from the phone's own back camera, towards the top edge.
    private func tiltedMount(_ tilt: Double) throws -> MountProfile {
        let angle = AstroMath.radians(tilt)
        return try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, sin(angle), -cos(angle)),
                                                 cameraUp: Vector3(0, cos(angle), sin(angle))))
    }

    /// An alignment solved for `mount` from a single point: the compass is 10 degrees off.
    private func compassAlignment(for mount: MountProfile) throws -> AlignmentModel {
        // A phone upright at azimuth 0, altitude 30, aimed with the back camera.
        let alt = AstroMath.radians(30)
        let forward = Vector3(0, cos(alt), sin(alt))
        let up = Vector3(0, -sin(alt), cos(alt))
        func row(_ axis: Vector3) -> Vector3 { Vector3(axis.y, -axis.x, axis.z) }
        let attitude = try XCTUnwrap(DeviceAttitude(matrix: Matrix3(rows: row(Vector3(1, 0, 0)), row(up), row(forward * -1)),
                                                    referenceAzimuth: 0, timestamp: 0))
        let point = AlignmentPoint(attitude: attitude, target: HorizontalCoordinate(azimuth: 10, altitude: 30),
                                   timestamp: Date(timeIntervalSince1970: 0))
        return try AlignmentModel.solve(points: [point], mount: mount)
    }

    private func makePlan(frame: FrameSize, overlap: Double, orientation: MosaicOrientation = .landscape) throws -> MosaicPlan {
        let region = MosaicRegion.horizontal(azimuthStart: 170, azimuthSpan: 30, minimumAltitude: 20, maximumAltitude: 50)
        return try MosaicPlanner.plan(region: region, frame: frame, orientation: orientation, overlap: overlap)
    }

    // MARK: The phone's camera and the lens

    func testABackCameraMountLooksAlongTheLens() {
        let mounts = [MountProfile.backCameraPortrait, .backCameraPortraitUpsideDown, .backCameraLandscapeLeft,
                      .backCameraLandscapeRight]
        for mount in mounts {
            XCTAssertTrue(AimConfiguration.phoneCameraFollowsLens(mount), mount.id)
            XCTAssertTrue(configuration(mount: mount).phoneCameraFollowsLens, mount.id)
        }
    }

    func testAPhoneLyingOnTheCameraDoesNotLookAlongTheLens() {
        for mount in [MountProfile.flatOnTopTopEdgeForward, .flatOnTopTopEdgeBack] {
            XCTAssertFalse(AimConfiguration.phoneCameraFollowsLens(mount), mount.id)
            XCTAssertFalse(configuration(mount: mount).phoneCameraFollowsLens, mount.id)
        }
    }

    func testAMountTiltedByLessThanAboutEightDegreesStillFollowsTheLens() throws {
        for tilt in [0.0, 2, 5, 8] {
            let mount = try tiltedMount(tilt)
            XCTAssertTrue(AimConfiguration.phoneCameraFollowsLens(mount), "tilt \(tilt)")
        }
    }

    func testAMountTiltedByMoreThanAboutEightDegreesDoesNot() throws {
        // The limit is a dot product of 0.99 with the back camera's axis: 8.11 degrees.
        for tilt in [8.5, 10, 45, 90, 135, 180] {
            let mount = try tiltedMount(tilt)
            XCTAssertFalse(AimConfiguration.phoneCameraFollowsLens(mount), "tilt \(tilt)")
        }
    }

    func testAMountPointingTheOtherWayFromTheBackCameraDoesNotFollowTheLens() throws {
        let frontCamera = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 0, 1), cameraUp: Vector3(0, 1, 0)))
        XCTAssertFalse(AimConfiguration.phoneCameraFollowsLens(frontCamera))
    }

    // MARK: The compass correction

    func testWithoutAnAlignmentThereIsNoHeadingOffset() {
        XCTAssertEqual(configuration().headingOffset, 0)
        XCTAssertEqual(configuration(mount: .flatOnTopTopEdgeBack).headingOffset, 0)
    }

    func testTheHeadingOffsetIsTheAlignmentsForTheMountItWasSolvedFor() throws {
        let alignment = try compassAlignment(for: .backCameraPortrait)
        XCTAssertEqual(alignment.headingOffset, 10, accuracy: 1e-6)
        XCTAssertEqual(configuration(mount: .backCameraPortrait, alignment: alignment).headingOffset, 10, accuracy: 1e-6)
    }

    func testTheHeadingOffsetIsZeroForAnotherMount() throws {
        let alignment = try compassAlignment(for: .backCameraPortrait)
        XCTAssertEqual(configuration(mount: .backCameraPortraitUpsideDown, alignment: alignment).headingOffset, 0)
        XCTAssertEqual(configuration(mount: .backCameraLandscapeLeft, alignment: alignment).headingOffset, 0)
    }

    // MARK: The on-target threshold

    func testTheOnTargetThresholdIsAQuarterOfTheShorterSideOfTheLensFrame() {
        let cases: [(horizontal: Double, vertical: Double, expected: Double)] = [
            (8, 6, 1.5), (6, 8, 1.5), (40, 27, 6.75), (27, 40, 6.75), (12, 12, 3), (2, 400, 0.5), (100, 4.8, 1.2),
        ]
        for (horizontal, vertical, expected) in cases {
            let lens = FrameSize(horizontal: horizontal, vertical: vertical, diagonal: 0)
            XCTAssertEqual(configuration(lens: lens).onTargetThreshold, expected, accuracy: 1e-12, "\(horizontal) x \(vertical)")
        }
    }

    func testTheOnTargetThresholdIsNeverBelowHalfADegree() {
        for (horizontal, vertical) in [(1.0, 1.0), (2, 2), (0.5, 3), (0, 10), (-5, 10), (10, 0)] {
            let lens = FrameSize(horizontal: horizontal, vertical: vertical, diagonal: 0)
            XCTAssertEqual(configuration(lens: lens).onTargetThreshold, 0.5, accuracy: 1e-12, "\(horizontal) x \(vertical)")
        }
        XCTAssertEqual(configuration(lens: FrameSize(horizontal: 2.2, vertical: 2.2, diagonal: 3)).onTargetThreshold, 0.55,
                       accuracy: 1e-12)
    }

    func testAFrameThatIsNotANumberGivesTheMinimumThreshold() {
        let lens = FrameSize(horizontal: .nan, vertical: 6, diagonal: 0)
        XCTAssertEqual(configuration(lens: lens).onTargetThreshold, 0.5)
        XCTAssertEqual(configuration(lens: FrameSize(horizontal: 6, vertical: .infinity, diagonal: 0)).onTargetThreshold, 0.5)
        XCTAssertEqual(configuration(lens: FrameSize(horizontal: .infinity, vertical: .infinity, diagonal: 0)).onTargetThreshold, 0.5)
    }

    // MARK: The sky options

    func testTheSkyOptionsCarryTheMagnitudeLimit() {
        var config = configuration()
        config.starMagnitudeLimit = 3.5
        XCTAssertEqual(config.skyOptions.starMagnitudeLimit, 3.5)
        config.starMagnitudeLimit = 6.5
        XCTAssertEqual(config.skyOptions.starMagnitudeLimit, 6.5)
    }

    func testConstellationsAreIncludedWhenTheirLinesOrTheirNamesAreShown() {
        let cases: [(lines: Bool, names: Bool, included: Bool)] = [
            (false, false, false), (true, false, true), (false, true, true), (true, true, true),
        ]
        for (lines, names, included) in cases {
            var config = configuration()
            config.showConstellationLines = lines
            config.showConstellationNames = names
            XCTAssertEqual(config.skyOptions.includeConstellations, included, "lines \(lines), names \(names)")
        }
    }

    func testDeepSkyAndMilkyWayFollowTheirSwitches() {
        for deepSky in [false, true] {
            for milkyWay in [false, true] {
                var config = configuration()
                config.showDeepSkyObjects = deepSky
                config.showMilkyWay = milkyWay
                XCTAssertEqual(config.skyOptions.includeDeepSky, deepSky)
                XCTAssertEqual(config.skyOptions.includeMilkyWay, milkyWay)
            }
        }
    }

    func testTheDeepSkyDetailSettingChoosesTheProminence() {
        let cases: [(setting: Int, prominence: Prominence)] = [
            (1, .showpiece), (2, .prominent), (3, .notable), (4, .obscure),
            (0, .showpiece), (-3, .showpiece), (5, .obscure), (99, .obscure),
        ]
        for (setting, prominence) in cases {
            var config = configuration()
            config.deepSkyProminence = setting
            XCTAssertEqual(config.skyOptions.deepSkyProminence, prominence, "setting \(setting)")
        }
    }

    func testTheOtherSkyOptionsKeepTheirDefaults() {
        let options = configuration().skyOptions
        let defaults = SkySnapshotOptions()
        XCTAssertEqual(options.smallBodyMagnitudeLimit, defaults.smallBodyMagnitudeLimit)
    }

    // MARK: Comparing configurations

    func testTwoConfigurationsWithTheSameValuesAreEqual() {
        XCTAssertEqual(configuration(), configuration())
    }

    func testAChangeOfAnyValueMakesTheConfigurationDifferent() throws {
        let alignment = try compassAlignment(for: .backCameraPortrait)
        let changes: [(String, (inout AimConfiguration) -> Void)] = [
            ("mount", { $0.mount = .backCameraLandscapeLeft }),
            ("alignment", { $0.alignment = alignment }),
            ("lens", { $0.lensFrame = FrameSize(horizontal: 8, vertical: 6.5, diagonal: 10) }),
            ("constellation lines", { $0.showConstellationLines.toggle() }),
            ("constellation names", { $0.showConstellationNames.toggle() }),
            ("deep sky", { $0.showDeepSkyObjects.toggle() }),
            ("milky way", { $0.showMilkyWay.toggle() }),
            ("prominence", { $0.deepSkyProminence = 3 }),
            ("magnitude", { $0.starMagnitudeLimit = 4.5 }),
            ("camera preview", { $0.wantsCameraPreview.toggle() }),
            ("night", { $0.isNight.toggle() }),
        ]
        for (name, change) in changes {
            var changed = configuration()
            change(&changed)
            XCTAssertNotEqual(changed, configuration(), name)
        }
    }

    // MARK: The inputs of the sky snapshot

    private func inputs() -> AimSkyInputs {
        AimSkyInputs(observer: Fixture.boulder, options: SkySnapshotOptions(), target: nil, horizon: nil, mosaic: nil)
    }

    func testTheSkyInputsAreEqualWhenAllTheirPartsAre() throws {
        XCTAssertEqual(inputs(), inputs())
        var a = inputs(), b = inputs()
        a.target = try object("dso.M31")
        b.target = try object("dso.M31")
        a.horizon = .constant(5)
        b.horizon = .constant(5)
        XCTAssertEqual(a, b)
    }

    func testAChangeOfAnyPartMakesTheSkyInputsDifferent() throws {
        let plan = try makePlan(frame: FrameSize(horizontal: 40, vertical: 30, diagonal: 50), overlap: 0.3)
        let moon = try object("moon")
        var otherOptions = SkySnapshotOptions()
        otherOptions.starMagnitudeLimit = 3
        let changes: [(String, (inout AimSkyInputs) -> Void)] = [
            ("observer", { $0.observer = Fixture.sydney }),
            ("options", { $0.options = otherOptions }),
            ("target", { $0.target = moon }),
            ("horizon", { $0.horizon = .constant(5) }),
            ("mosaic", { $0.mosaic = plan }),
        ]
        for (name, change) in changes {
            var changed = inputs()
            change(&changed)
            XCTAssertNotEqual(changed, inputs(), name)
        }
        var withHorizon = inputs()
        withHorizon.horizon = .constant(5)
        var otherHorizon = inputs()
        otherHorizon.horizon = .constant(6)
        XCTAssertNotEqual(withHorizon, otherHorizon)
    }

    // MARK: The sheets

    func testEachSheetIsIdentifiedByItsName() {
        XCTAssertEqual(AimSheet.targetPicker.id, "targetPicker")
        XCTAssertEqual(AimSheet.alignment.id, "alignment")
        XCTAssertEqual(AimSheet.mosaic.id, "mosaic")
        XCTAssertEqual(AimSheet.mount.id, "mount")
        XCTAssertEqual(AimSheet.help.id, "help")
        XCTAssertEqual(AimSheet(rawValue: "help"), .help)
        XCTAssertNil(AimSheet(rawValue: "settings"))
    }

    // MARK: Rising of the target

    func testAnObjectThatRisesAndSetsHasANextRiseWithinTheDay() throws {
        let m31 = try object("dso.M31")
        let info = AimRiseInfo.compute(for: m31, observer: Fixture.boulder, from: Fixture.july)
        XCTAssertEqual(info.targetID, "dso.M31")
        XCTAssertEqual(info.circumstance, .normal)
        let rise = try XCTUnwrap(info.nextRise)
        XCTAssertGreaterThan(rise, Fixture.july)
        XCTAssertLessThanOrEqual(rise, Fixture.july.addingTimeInterval(24 * 3600))
    }

    func testTheNextRiseIsTheFirstRiseOfTheDayAhead() throws {
        let m31 = try object("dso.M31")
        let day = DateInterval(start: Fixture.july, duration: 24 * 3600)
        let expected = RiseSetCalculator.riseTransitSet(for: m31, observer: Fixture.boulder, within: day)
        let info = AimRiseInfo.compute(for: m31, observer: Fixture.boulder, from: Fixture.july)
        XCTAssertEqual(info.nextRise, expected.rise)
        XCTAssertEqual(info.circumstance, expected.circumstance)
    }

    func testTheNorthCelestialPoleIsAlwaysUpInTheNorthAndNeverRises() throws {
        let pole = try object("special.ncp")
        let north = AimRiseInfo.compute(for: pole, observer: Fixture.boulder, from: Fixture.july)
        XCTAssertEqual(north.targetID, "special.ncp")
        XCTAssertEqual(north.circumstance, .alwaysUp)
        XCTAssertNil(north.nextRise)
        let south = AimRiseInfo.compute(for: pole, observer: Fixture.sydney, from: Fixture.july)
        XCTAssertEqual(south.circumstance, .alwaysDown)
        XCTAssertNil(south.nextRise)
    }

    func testTheSouthCelestialPoleIsAlwaysDownInTheNorth() throws {
        let pole = try object("special.scp")
        let info = AimRiseInfo.compute(for: pole, observer: Fixture.boulder, from: Fixture.july)
        XCTAssertEqual(info.circumstance, .alwaysDown)
        XCTAssertNil(info.nextRise)
        XCTAssertEqual(AimRiseInfo.compute(for: pole, observer: Fixture.sydney, from: Fixture.july).circumstance, .alwaysUp)
    }

    func testRiseInformationIsComparedByItsTargetItsRiseAndItsCircumstance() {
        let rise = Date(timeIntervalSince1970: 1_784_200_000)
        let info = AimRiseInfo(targetID: "moon", nextRise: rise, circumstance: .normal)
        XCTAssertEqual(info, AimRiseInfo(targetID: "moon", nextRise: rise, circumstance: .normal))
        XCTAssertNotEqual(info, AimRiseInfo(targetID: "sun", nextRise: rise, circumstance: .normal))
        XCTAssertNotEqual(info, AimRiseInfo(targetID: "moon", nextRise: rise.addingTimeInterval(1), circumstance: .normal))
        XCTAssertNotEqual(info, AimRiseInfo(targetID: "moon", nextRise: nil, circumstance: .normal))
        XCTAssertNotEqual(info, AimRiseInfo(targetID: "moon", nextRise: rise, circumstance: .alwaysUp))
    }

    // MARK: The tolerance of a mosaic panel

    func testThePanelToleranceIsAThirdOfTheOverlapOfTheShorterSideOfTheFrame() throws {
        // 40 by 30 degree frames: the shorter side is 30 degrees.
        let frame = FrameSize(horizontal: 40, vertical: 30, diagonal: 50)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: try makePlan(frame: frame, overlap: 0.3)), 3.0, accuracy: 1e-9)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: try makePlan(frame: frame, overlap: 0.15)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: try makePlan(frame: frame, overlap: 0.5)), 5.0, accuracy: 1e-9)
    }

    func testThePanelToleranceDoesNotDependOnHowTheCameraIsHeld() throws {
        let frame = FrameSize(horizontal: 40, vertical: 30, diagonal: 50)
        let landscape = try makePlan(frame: frame, overlap: 0.3, orientation: .landscape)
        let portrait = try makePlan(frame: frame, overlap: 0.3, orientation: .portrait)
        XCTAssertEqual(landscape.frame.horizontal, 40)
        XCTAssertEqual(portrait.frame.horizontal, 30)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: landscape), AimMosaicAim.onTargetThreshold(for: portrait), accuracy: 1e-12)
    }

    func testThePanelToleranceIsNeverBelowHalfADegree() throws {
        // 9 by 6 degrees with 20 percent overlap would be 0.4 degrees.
        let frame = FrameSize(horizontal: 9, vertical: 6, diagonal: 11)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: try makePlan(frame: frame, overlap: 0.2)), 0.5)
        // 18 by 12 degrees with 30 percent overlap is 1.2 degrees.
        let larger = FrameSize(horizontal: 18, vertical: 12, diagonal: 22)
        XCTAssertEqual(AimMosaicAim.onTargetThreshold(for: try makePlan(frame: larger, overlap: 0.3)), 1.2, accuracy: 1e-9)
    }

    func testAPanelAimIsComparedByAllItsParts() {
        let aim = AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                               orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2)
        XCTAssertEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                         orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 3, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                            orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 121, altitude: 30), roll: 10,
                                            orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 11,
                                            orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                            orientation: .portrait, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                            orientation: .landscape, isAboveHorizon: false, lowestAltitude: 25, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                            orientation: .landscape, isAboveHorizon: true, lowestAltitude: 24, onTargetThreshold: 2))
        XCTAssertNotEqual(aim, AimMosaicAim(panelIndex: 2, horizontal: HorizontalCoordinate(azimuth: 120, altitude: 30), roll: 10,
                                            orientation: .landscape, isAboveHorizon: true, lowestAltitude: 25, onTargetThreshold: 3))
    }
}

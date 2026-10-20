import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The inputs of the star-trail and time-lapse planners, and the sky they are shown against.
final class PlanPlannerInputsTests: XCTestCase {
    private func camera(focalLength: Double = 24, aperture: Double = 2.8, pixelPitch: Double? = 3.9) -> LensSetup {
        LensSetup(sensor: .apsC, focalLengthMillimeters: focalLength, aperture: aperture, pixelPitchMicrometers: pixelPitch)
    }

    // MARK: Star-trail inputs

    func testTrailInputsStartFromTheCamera() {
        let inputs = ToolsTrailInputs(camera: camera(focalLength: 35, aperture: 1.8, pixelPitch: 4.2))
        XCTAssertEqual(inputs.sensor, .apsC)
        XCTAssertEqual(inputs.focalLength, 35)
        XCTAssertEqual(inputs.aperture, 1.8)
        XCTAssertEqual(inputs.pixelPitch, 4.2)
    }

    func testTrailInputsKeepAnUnknownPixelPitchUnknown() {
        let inputs = ToolsTrailInputs(camera: camera(pixelPitch: nil))
        XCTAssertNil(inputs.pixelPitch)
        XCTAssertNil(inputs.setup.pixelPitchMicrometers)
    }

    func testTrailInputsStartWithTheDocumentedDefaults() {
        let inputs = ToolsTrailInputs(camera: camera())
        XCTAssertEqual(inputs.declination, 0)
        XCTAssertEqual(inputs.durationMinutes, 60)
        XCTAssertEqual(inputs.arcUnit, .degrees)
        XCTAssertEqual(inputs.arcDegrees, 10)
        XCTAssertEqual(inputs.arcPixels, 1000)
        XCTAssertEqual(inputs.rule, .npf)
        XCTAssertNil(inputs.frameSeconds)
        XCTAssertEqual(inputs.gapSeconds, StarTrailPlanner.defaultGapSeconds)
        XCTAssertEqual(inputs.gapSeconds, 1)
    }

    func testTheLongestTrailTimeIsTwentyFourHoursInMinutes() {
        XCTAssertEqual(ToolsTrailInputs.maximumMinutes, 1440)
    }

    func testTheDurationInSecondsIsMinutesTimesSixty() {
        var inputs = ToolsTrailInputs(camera: camera())
        XCTAssertEqual(inputs.durationSeconds, 3600)
        inputs.durationMinutes = 90
        XCTAssertEqual(inputs.durationSeconds, 5400)
        inputs.durationMinutes = 0.5
        XCTAssertEqual(inputs.durationSeconds, 30)
        inputs.durationMinutes = ToolsTrailInputs.maximumMinutes
        XCTAssertEqual(inputs.durationSeconds, StarTrailPlanner.maximumDurationSeconds)
    }

    func testTheSetupRebuildsTheLensFromTheInputs() {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.sensor = .fullFrame
        inputs.focalLength = 14
        inputs.aperture = 2
        inputs.pixelPitch = 5.9
        XCTAssertEqual(inputs.setup.sensor, .fullFrame)
        XCTAssertEqual(inputs.setup.focalLengthMillimeters, 14)
        XCTAssertEqual(inputs.setup.aperture, 2)
        XCTAssertEqual(inputs.setup.pixelPitchMicrometers, 5.9)
    }

    func testTheSetupLimitsTheFocalLengthToTheSupportedRange() {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.focalLength = 1
        XCTAssertEqual(inputs.setup.focalLengthMillimeters, 4)
        inputs.focalLength = 5000
        XCTAssertEqual(inputs.setup.focalLengthMillimeters, 2000)
        inputs.focalLength = .nan
        XCTAssertEqual(inputs.setup.focalLengthMillimeters, 24)
    }

    func testTheSetupLimitsTheApertureToTheSupportedRange() {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.aperture = 0.5
        XCTAssertEqual(inputs.setup.aperture, 0.95)
        inputs.aperture = 64
        XCTAssertEqual(inputs.setup.aperture, 32)
        inputs.aperture = .infinity
        XCTAssertEqual(inputs.setup.aperture, 2.8)
    }

    func testTheSetupDropsAPixelPitchOutsideTheSupportedRange() {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.pixelPitch = 0.1
        XCTAssertNil(inputs.setup.pixelPitchMicrometers)
        inputs.pixelPitch = 500
        XCTAssertNil(inputs.setup.pixelPitchMicrometers)
        inputs.pixelPitch = 4
        XCTAssertEqual(inputs.setup.pixelPitchMicrometers, 4)
        inputs.pixelPitch = nil
        XCTAssertNil(inputs.setup.pixelPitchMicrometers)
    }

    func testTrailInputsFeedTheStackingPlanner() throws {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.durationMinutes = 120
        inputs.declination = 30
        let plan = try StarTrailPlanner.stackingPlan(
            totalDuration: inputs.durationSeconds, declination: inputs.declination, setup: inputs.setup,
            rule: inputs.rule, exposureSeconds: inputs.frameSeconds, gapSeconds: inputs.gapSeconds)
        XCTAssertEqual(plan.totalDuration, 7200)
        XCTAssertEqual(plan.gapSeconds, 1)
        XCTAssertGreaterThan(plan.frameCount, 1)
        XCTAssertGreaterThanOrEqual(plan.actualDuration, 7200)
    }

    func testTrailInputsAtTheLimitsAreRejectedByThePlanner() {
        var inputs = ToolsTrailInputs(camera: camera())
        inputs.durationMinutes = ToolsTrailInputs.maximumMinutes + 1
        XCTAssertThrowsError(try StarTrailPlanner.stackingPlan(
            totalDuration: inputs.durationSeconds, declination: inputs.declination, setup: inputs.setup)) { error in
            XCTAssertEqual(error as? StarTrailError, .invalidDuration(seconds: 86_460))
        }
    }

    func testArcUnitsHaveTitlesAndIdentifiers() {
        XCTAssertEqual(ToolsTrailInputs.ArcUnit.allCases, [.degrees, .pixels])
        XCTAssertEqual(ToolsTrailInputs.ArcUnit.degrees.title, "Degrees")
        XCTAssertEqual(ToolsTrailInputs.ArcUnit.pixels.title, "Pixels")
        XCTAssertEqual(ToolsTrailInputs.ArcUnit.degrees.id, "degrees")
        XCTAssertEqual(ToolsTrailInputs.ArcUnit.pixels.id, "pixels")
        XCTAssertEqual(ToolsTrailInputs.ArcUnit(rawValue: "pixels"), .pixels)
        XCTAssertNil(ToolsTrailInputs.ArcUnit(rawValue: "arcseconds"))
    }

    // MARK: Time-lapse inputs

    func testLapseInputsStartWithTheDocumentedDefaults() {
        let inputs = ToolsLapseInputs()
        XCTAssertEqual(inputs.interval, 15)
        XCTAssertEqual(inputs.exposure, 10)
        XCTAssertEqual(inputs.frameRate, 24)
        XCTAssertEqual(inputs.basis, .clipLength)
        XCTAssertEqual(inputs.clipSeconds, 10)
        XCTAssertEqual(inputs.shootingMinutes, 60)
        XCTAssertEqual(inputs.frameCount, 240)
        XCTAssertNil(inputs.pictureMegabytes)
        XCTAssertEqual(inputs.writeSeconds, TimeLapsePlanner.defaultMinimumGapSeconds)
        XCTAssertEqual(inputs.writeSeconds, 1)
    }

    func testTheTargetFollowsTheChosenBasis() {
        var inputs = ToolsLapseInputs()
        inputs.clipSeconds = 12
        inputs.shootingMinutes = 90
        inputs.frameCount = 500

        inputs.basis = .clipLength
        XCTAssertEqual(inputs.target, .clipLength(seconds: 12))
        inputs.basis = .shootingTime
        XCTAssertEqual(inputs.target, .shootingTime(seconds: 5400))
        inputs.basis = .frames
        XCTAssertEqual(inputs.target, .frameCount(frames: 500))
    }

    func testAFrameCountIsRoundedToTheNearestWholeNumber() {
        var inputs = ToolsLapseInputs()
        inputs.basis = .frames
        inputs.frameCount = 240.4
        XCTAssertEqual(inputs.target, .frameCount(frames: 240))
        inputs.frameCount = 240.5
        XCTAssertEqual(inputs.target, .frameCount(frames: 241))
        inputs.frameCount = 240.6
        XCTAssertEqual(inputs.target, .frameCount(frames: 241))
        inputs.frameCount = 0.4
        XCTAssertEqual(inputs.target, .frameCount(frames: 0))
    }

    func testBasesHaveTitlesAndIdentifiers() {
        XCTAssertEqual(ToolsLapseInputs.Basis.allCases, [.clipLength, .shootingTime, .frames])
        XCTAssertEqual(ToolsLapseInputs.Basis.clipLength.title, "Clip")
        XCTAssertEqual(ToolsLapseInputs.Basis.shootingTime.title, "Shooting")
        XCTAssertEqual(ToolsLapseInputs.Basis.frames.title, "Pictures")
        XCTAssertEqual(ToolsLapseInputs.Basis.clipLength.id, "clipLength")
        XCTAssertEqual(ToolsLapseInputs.Basis.shootingTime.id, "shootingTime")
        XCTAssertEqual(ToolsLapseInputs.Basis.frames.id, "frames")
        XCTAssertEqual(ToolsLapseInputs.Basis(rawValue: "frames"), .frames)
        XCTAssertNil(ToolsLapseInputs.Basis(rawValue: "length"))
    }

    func testDefaultLapseInputsMakeAWorkingPlan() throws {
        let inputs = ToolsLapseInputs()
        let plan = try TimeLapsePlanner.plan(
            interval: inputs.interval, exposure: inputs.exposure, frameRate: inputs.frameRate, target: inputs.target,
            frameSizeMegabytes: inputs.pictureMegabytes, minimumGapSeconds: inputs.writeSeconds)
        // A 10 second clip at 24 frames per second is 240 pictures, 15 seconds apart: one hour of shooting.
        XCTAssertEqual(plan.frameCount, 240)
        XCTAssertEqual(plan.shootingTime, 3600, accuracy: 1e-9)
        XCTAssertEqual(plan.clipLength, 10, accuracy: 1e-9)
        XCTAssertEqual(plan.gap, 5, accuracy: 1e-9)
        XCTAssertNil(plan.storageMegabytes)
    }

    func testTheShootingTimeBasisTakesAsManyWholeIntervalsAsFit() throws {
        var inputs = ToolsLapseInputs()
        inputs.basis = .shootingTime
        inputs.shootingMinutes = 60
        let plan = try TimeLapsePlanner.plan(
            interval: inputs.interval, exposure: inputs.exposure, frameRate: inputs.frameRate, target: inputs.target,
            minimumGapSeconds: inputs.writeSeconds)
        XCTAssertEqual(plan.frameCount, 240)
    }

    func testAPictureSizeGivesTheStorage() throws {
        var inputs = ToolsLapseInputs()
        inputs.pictureMegabytes = 25
        let plan = try TimeLapsePlanner.plan(
            interval: inputs.interval, exposure: inputs.exposure, frameRate: inputs.frameRate, target: inputs.target,
            frameSizeMegabytes: inputs.pictureMegabytes, minimumGapSeconds: inputs.writeSeconds)
        XCTAssertEqual(try XCTUnwrap(plan.storageMegabytes), 6000, accuracy: 1e-9)
    }

    // MARK: Pole and target in the sky

    private func target(poleInLandscape: Bool = false, poleInPortrait: Bool = false,
                        isPoleBehind: Bool = false) -> ToolsTrailSky.Target {
        ToolsTrailSky.Target(name: "M31", declination: 41.3, separationFromPole: 48.7, poleInLandscape: poleInLandscape,
                             poleInPortrait: poleInPortrait, isPoleBehind: isPoleBehind)
    }

    func testThePoleDeclinationIsPlusOrMinusNinetyByHemisphere() {
        XCTAssertEqual(ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0, target: nil).poleDeclination, 90)
        XCTAssertEqual(ToolsTrailSky(hemisphere: .south, poleAltitude: 30, poleAzimuth: 180, target: nil).poleDeclination, -90)
    }

    func testThePoleIsAboveTheHorizonOnlyWithAPositiveAltitude() {
        XCTAssertTrue(ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0, target: nil).isPoleAboveHorizon)
        XCTAssertTrue(ToolsTrailSky(hemisphere: .north, poleAltitude: 0.001, poleAzimuth: 0, target: nil).isPoleAboveHorizon)
        XCTAssertFalse(ToolsTrailSky(hemisphere: .north, poleAltitude: 0, poleAzimuth: 0, target: nil).isPoleAboveHorizon)
        XCTAssertFalse(ToolsTrailSky(hemisphere: .south, poleAltitude: -12, poleAzimuth: 180, target: nil).isPoleAboveHorizon)
    }

    func testTheSkyKeepsItsFields() {
        let sky = ToolsTrailSky(hemisphere: .south, poleAltitude: 33.5, poleAzimuth: 181.25, target: target())
        XCTAssertEqual(sky.hemisphere, .south)
        XCTAssertEqual(sky.poleAltitude, 33.5)
        XCTAssertEqual(sky.poleAzimuth, 181.25)
        XCTAssertEqual(sky.target, target())
    }

    func testATargetBelowTheHorizonHasNoSeparationFromThePole() {
        let below = ToolsTrailSky.Target(name: "Sirius", declination: -16.7, separationFromPole: nil)
        XCTAssertNil(below.separationFromPole)
        XCTAssertFalse(below.poleInLandscape)
        XCTAssertFalse(below.poleInPortrait)
        XCTAssertFalse(below.isPoleBehind)
    }

    func testSkiesCompareByAllTheirFields() {
        let base = ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0, target: target())
        XCTAssertEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0, target: target()))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .south, poleAltitude: 40, poleAzimuth: 0, target: target()))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 41, poleAzimuth: 0, target: target()))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 1, target: target()))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0, target: nil))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0,
                                              target: target(poleInLandscape: true)))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0,
                                              target: target(poleInPortrait: true)))
        XCTAssertNotEqual(base, ToolsTrailSky(hemisphere: .north, poleAltitude: 40, poleAzimuth: 0,
                                              target: target(isPoleBehind: true)))
    }
}

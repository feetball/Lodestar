import XCTest
@testable import LodestarKit

final class StarTrailPlannerTests: XCTestCase {
    /// 24 mm on a full-frame camera with 4 µm pixels: 34.377″ per pixel.
    private let wide = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8, pixelPitchMicrometers: 4)

    /// The arcseconds in a radian.
    private let arcsecondsPerRadian = 180.0 * 3600.0 / Double.pi

    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private let date = Date(timeIntervalSince1970: 1_792_209_600)

    // MARK: Trail arcs

    func testTrailAtTheEquatorOverAnHourIsFifteenDegrees() throws {
        let trail = try StarTrailPlanner.trail(duration: 3600, declination: 0, setup: wide)
        // The sidereal rate is 15.041° per hour (the text-book "15°" is rounded).
        XCTAssertEqual(trail.rotationDegrees, 15.0, accuracy: 0.05)
        XCTAssertEqual(trail.rotationDegrees, 15.041, accuracy: 1e-9)
        XCTAssertEqual(trail.arcLengthDegrees, 15.041, accuracy: 1e-9)
        XCTAssertEqual(trail.radiusFromPoleDegrees, 90.0)
        XCTAssertEqual(trail.duration, 3600.0)
        XCTAssertEqual(trail.declination, 0.0)
        XCTAssertEqual(StarTrailPlanner.rotationRateDegreesPerHour, 15.041)
        XCTAssertFalse(trail.usedDefaultPixelPitch)
    }

    func testTrailAtDeclinationSixtyIsHalfAsLong() throws {
        let trail = try StarTrailPlanner.trail(duration: 3600, declination: 60, setup: wide)
        XCTAssertEqual(trail.arcLengthDegrees, 7.5, accuracy: 0.05)
        XCTAssertEqual(trail.arcLengthDegrees, 15.041 * 0.5, accuracy: 1e-9)
        // The star still turns by the same angle about the pole; its circle is smaller.
        XCTAssertEqual(trail.rotationDegrees, 15.041, accuracy: 1e-9)
        XCTAssertEqual(trail.radiusFromPoleDegrees, 30.0)
        // The south counts like the north.
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 3600, declination: -60, setup: wide).arcLengthDegrees, trail.arcLengthDegrees, accuracy: 1e-12)
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 3600, declination: -60, setup: wide).radiusFromPoleDegrees, 30.0)
    }

    func testTrailLengthFollowsTheCosineOfTheDeclination() throws {
        for declination in [-89.0, -45.0, 0.0, 10.0, 30.0, 75.0, 90.0] {
            for seconds in [1.0, 30.0, 3600.0, 36_000.0] {
                let trail = try StarTrailPlanner.trail(duration: seconds, declination: declination, setup: wide)
                XCTAssertEqual(trail.arcLengthDegrees, 15.041 / 3600 * seconds * cos(declination * Double.pi / 180), accuracy: 1e-9)
                XCTAssertEqual(trail.rotationDegrees, 15.041 / 3600 * seconds, accuracy: 1e-9)
            }
        }
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 3600, declination: 90, setup: wide).arcLengthDegrees, 0.0, accuracy: 1e-9)
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 3600, declination: 90, setup: wide).radiusFromPoleDegrees, 0.0)
    }

    func testPixelLengthsForAKnownPixelPitch() throws {
        // 4 µm behind 24 mm: 206 264.8″ × 0.004 mm / 24 mm = 34.377″ per pixel.
        let scale = arcsecondsPerRadian * 0.004 / 24.0
        XCTAssertEqual(scale, 34.3775, accuracy: 1e-4)
        let thirty = try StarTrailPlanner.trail(duration: 30, declination: 0, setup: wide)
        XCTAssertEqual(thirty.arcLengthPixels, 15.041 * 30.0 / scale, accuracy: 1e-9)
        XCTAssertEqual(thirty.arcLengthPixels, 13.126, accuracy: 0.001)
        let hour = try StarTrailPlanner.trail(duration: 3600, declination: 0, setup: wide)
        XCTAssertEqual(hour.arcLengthPixels, 1575.1, accuracy: 0.1)
        // At declination 60 half as many pixels.
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 3600, declination: 60, setup: wide).arcLengthPixels, hour.arcLengthPixels / 2, accuracy: 1e-6)
        // A longer lens and a smaller pixel stretch the trail: 85 mm, 3.76 µm.
        let tele = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 85, aperture: 1.8, pixelPitchMicrometers: 3.76)
        let teleScale = arcsecondsPerRadian * 0.00376 / 85.0
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 30, declination: 45, setup: tele).arcLengthPixels,
                       15.041 * 30.0 * cos(45.0 * Double.pi / 180) / teleScale, accuracy: 1e-9)
        // It agrees with the exposure calculator's own figure.
        XCTAssertEqual(try StarTrailPlanner.trail(duration: 30, declination: 45, setup: tele).arcLengthPixels,
                       ExposureCalculator.trailLengthPixels(exposureSeconds: 30, declination: 45, setup: tele))
    }

    func testMissingPixelPitchAssumesFourMicrometres() throws {
        let unknown = LensSetup(sensor: .fullFrame, focalLengthMillimeters: 24, aperture: 2.8)
        let trail = try StarTrailPlanner.trail(duration: 30, declination: 0, setup: unknown)
        XCTAssertTrue(trail.usedDefaultPixelPitch)
        XCTAssertEqual(trail.arcLengthPixels, try StarTrailPlanner.trail(duration: 30, declination: 0, setup: wide).arcLengthPixels, accuracy: 1e-9)
    }

    // MARK: Durations

    func testDurationForAGivenArc() throws {
        XCTAssertEqual(try StarTrailPlanner.duration(forArcDegrees: 15.041, declination: 0), 3600.0, accuracy: 1e-6)
        XCTAssertEqual(try StarTrailPlanner.duration(forArcDegrees: 15.041, declination: 60), 7200.0, accuracy: 1e-6)
        // A trail of 10° at declination 30°: 10 / (15.041/3600 × cos 30°) seconds.
        XCTAssertEqual(try StarTrailPlanner.duration(forArcDegrees: 10, declination: 30),
                       10.0 / (15.041 / 3600 * cos(30.0 * Double.pi / 180)), accuracy: 1e-9)
        // It undoes trail().
        for declination in [-70.0, 0.0, 25.0, 80.0] {
            let trail = try StarTrailPlanner.trail(duration: 1234.5, declination: declination, setup: wide)
            XCTAssertEqual(try StarTrailPlanner.duration(forArcDegrees: trail.arcLengthDegrees, declination: declination), 1234.5, accuracy: 1e-6)
        }
    }

    func testDurationForAGivenPixelLength() throws {
        // The shutter stays open until the trail is 20 pixels long.
        let seconds = try StarTrailPlanner.duration(forArcPixels: 20, declination: 0, setup: wide)
        XCTAssertEqual(seconds, 20.0 * (arcsecondsPerRadian * 0.004 / 24.0) / 15.041, accuracy: 1e-9)
        XCTAssertEqual(try StarTrailPlanner.trail(duration: seconds, declination: 0, setup: wide).arcLengthPixels, 20.0, accuracy: 1e-9)
        let polar = try StarTrailPlanner.duration(forArcPixels: 20, declination: 50, setup: wide)
        XCTAssertEqual(try StarTrailPlanner.trail(duration: polar, declination: 50, setup: wide).arcLengthPixels, 20.0, accuracy: 1e-9)
    }

    func testDurationErrors() {
        MosaicTestSupport.assertThrows(StarTrailError.invalidArc(value: 0)) { _ = try StarTrailPlanner.duration(forArcDegrees: 0, declination: 0) }
        MosaicTestSupport.assertThrowsKind("invalidArc") { _ = try StarTrailPlanner.duration(forArcDegrees: 361, declination: 0) }
        MosaicTestSupport.assertThrowsKind("invalidArc") { _ = try StarTrailPlanner.duration(forArcDegrees: .nan, declination: 0) }
        MosaicTestSupport.assertThrowsKind("invalidArc") { _ = try StarTrailPlanner.duration(forArcDegrees: -5, declination: 0) }
        MosaicTestSupport.assertThrows(StarTrailError.invalidDeclination(degrees: 91)) { _ = try StarTrailPlanner.duration(forArcDegrees: 5, declination: 91) }
        MosaicTestSupport.assertThrowsKind("invalidDeclination") { _ = try StarTrailPlanner.duration(forArcDegrees: 5, declination: .nan) }
        MosaicTestSupport.assertThrows(StarTrailError.noMotionAtThePole) { _ = try StarTrailPlanner.duration(forArcDegrees: 5, declination: 90) }
        MosaicTestSupport.assertThrowsKind("noMotionAtThePole") { _ = try StarTrailPlanner.duration(forArcDegrees: 5, declination: -90) }
        // 5° at declination 89.9° would take 5 / (15.041/3600 × 0.001745) s = 190 hours.
        let tooLong = MosaicTestSupport.thrown { _ = try StarTrailPlanner.duration(forArcDegrees: 5, declination: 89.9) }
        guard case let .durationTooLong(seconds)? = tooLong as? StarTrailError else { return XCTFail("\(String(describing: tooLong))") }
        XCTAssertGreaterThan(seconds, 86_400.0)
        let wide = self.wide
        MosaicTestSupport.assertThrowsKind("invalidArc") { _ = try StarTrailPlanner.duration(forArcPixels: 0, declination: 0, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidArc") { _ = try StarTrailPlanner.duration(forArcPixels: .infinity, declination: 0, setup: wide) }
        MosaicTestSupport.assertThrowsKind("noMotionAtThePole") { _ = try StarTrailPlanner.duration(forArcPixels: 10, declination: 90, setup: wide) }
        MosaicTestSupport.assertThrowsKind("durationTooLong") { _ = try StarTrailPlanner.duration(forArcPixels: 1e6, declination: 0, setup: wide) }
    }

    func testTrailErrors() throws {
        let wide = self.wide
        MosaicTestSupport.assertThrows(StarTrailError.invalidDuration(seconds: 0)) { _ = try StarTrailPlanner.trail(duration: 0, declination: 0, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidDuration") { _ = try StarTrailPlanner.trail(duration: -1, declination: 0, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidDuration") { _ = try StarTrailPlanner.trail(duration: .nan, declination: 0, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidDuration") { _ = try StarTrailPlanner.trail(duration: 86_401, declination: 0, setup: wide) }
        _ = try StarTrailPlanner.trail(duration: 86_400, declination: 0, setup: wide)
        MosaicTestSupport.assertThrows(StarTrailError.invalidDeclination(degrees: -91)) { _ = try StarTrailPlanner.trail(duration: 60, declination: -91, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidDeclination") { _ = try StarTrailPlanner.trail(duration: 60, declination: .infinity, setup: wide) }
    }

    // MARK: Stacking

    func testStackingPlanFromTheNpfRule() throws {
        // NPF: (35 × 2.8 + 30 × 4) / 24 = 9.083 s, used as 9 s. With a one-second gap a frame takes 10 s.
        let plan = try StarTrailPlanner.stackingPlan(totalDuration: 7200, declination: nil, setup: wide)
        XCTAssertEqual(plan.estimate.rule, .npf)
        XCTAssertEqual(plan.estimate.seconds, 218.0 / 24.0, accuracy: 1e-12)
        XCTAssertEqual(plan.exposureSeconds, 9.0)
        XCTAssertEqual(plan.gapSeconds, 1.0)
        XCTAssertEqual(plan.frameCount, 720)
        XCTAssertEqual(plan.actualDuration, 7200.0, accuracy: 1e-9)
        XCTAssertEqual(plan.lightSeconds, 6480.0, accuracy: 1e-9)
        XCTAssertEqual(plan.totalDuration, 7200.0)
        // A star at the equator moves 9 × 15.041″ = 135″ = 3.94 px in a frame and 0.44 px in the gap.
        XCTAssertEqual(plan.exposureTrailPixels, 15.041 * 9.0 / (arcsecondsPerRadian * 0.004 / 24.0), accuracy: 1e-9)
        XCTAssertEqual(plan.exposureTrailPixels, 3.94, accuracy: 0.01)
        XCTAssertEqual(plan.gapPixels, 0.4375, accuracy: 0.001)
        XCTAssertEqual(plan.trail.duration, 7200.0, accuracy: 1e-9)
        XCTAssertEqual(plan.trail.rotationDegrees, 15.041 * 2, accuracy: 1e-9)
        XCTAssertEqual(plan.trail.declination, 0.0)
    }

    func testStackingPlanFollowsTheRuleAndTheDeclination() throws {
        // 500 rule: 500 / 24 = 20.83 s, used as 20 s; frames of 21 s give ceil(7200 / 21) = 343.
        let rule500 = try StarTrailPlanner.stackingPlan(totalDuration: 7200, declination: nil, setup: wide, rule: .rule500)
        XCTAssertEqual(rule500.exposureSeconds, 20.0)
        XCTAssertEqual(rule500.frameCount, 343)
        XCTAssertEqual(rule500.actualDuration, 343 * 21.0, accuracy: 1e-9)
        // Near the pole stars trail less, so the exposure grows: declination 60° doubles the NPF figure to 18.17 s.
        let polar = try StarTrailPlanner.stackingPlan(totalDuration: 7200, declination: 60, setup: wide)
        XCTAssertEqual(polar.estimate.declinationFactor, 2.0, accuracy: 1e-12)
        XCTAssertEqual(polar.exposureSeconds, 18.0)
        XCTAssertEqual(polar.frameCount, 379)
        XCTAssertEqual(polar.trail.declination, 60.0)
        XCTAssertEqual(polar.trail.arcLengthDegrees, polar.trail.rotationDegrees * 0.5, accuracy: 1e-9)
        // The caller's own exposure and gap win.
        let own = try StarTrailPlanner.stackingPlan(totalDuration: 7200, declination: nil, setup: wide, exposureSeconds: 15, gapSeconds: 1)
        XCTAssertEqual(own.exposureSeconds, 15.0)
        XCTAssertEqual(own.frameCount, 450)
        let noGap = try StarTrailPlanner.stackingPlan(totalDuration: 3600, declination: nil, setup: wide, exposureSeconds: 10, gapSeconds: 0)
        XCTAssertEqual(noGap.frameCount, 360)
        XCTAssertEqual(noGap.gapPixels, 0.0)
        // A short stack still takes one frame.
        XCTAssertEqual(try StarTrailPlanner.stackingPlan(totalDuration: 5, declination: nil, setup: wide).frameCount, 1)
        XCTAssertEqual(try StarTrailPlanner.stackingPlan(totalDuration: 10.5, declination: nil, setup: wide).frameCount, 2)
    }

    func testPracticalExposure() {
        XCTAssertEqual(StarTrailPlanner.practicalExposure(9.083), 9.0)
        XCTAssertEqual(StarTrailPlanner.practicalExposure(2.0), 2.0)
        XCTAssertEqual(StarTrailPlanner.practicalExposure(1.57), 1.5)
        XCTAssertEqual(StarTrailPlanner.practicalExposure(0.1), 0.1)
        XCTAssertEqual(StarTrailPlanner.practicalExposure(0.043), 0.043)
        XCTAssertEqual(StarTrailPlanner.practicalExposure(1.99), 1.9)
    }

    func testStackingPlanErrors() throws {
        let wide = self.wide
        MosaicTestSupport.assertThrowsKind("invalidDuration") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 0, declination: nil, setup: wide) }
        MosaicTestSupport.assertThrowsKind("invalidDuration") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 90_000, declination: nil, setup: wide) }
        MosaicTestSupport.assertThrows(StarTrailError.invalidDeclination(degrees: 95)) { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: 95, setup: wide) }
        MosaicTestSupport.assertThrows(StarTrailError.invalidExposure(seconds: 0)) {
            _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, exposureSeconds: 0)
        }
        MosaicTestSupport.assertThrowsKind("invalidExposure") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, exposureSeconds: 4000) }
        MosaicTestSupport.assertThrowsKind("invalidExposure") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, exposureSeconds: .nan) }
        MosaicTestSupport.assertThrows(StarTrailError.invalidGap(seconds: -1)) { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, gapSeconds: -1) }
        MosaicTestSupport.assertThrowsKind("invalidGap") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, gapSeconds: 61) }
        MosaicTestSupport.assertThrowsKind("invalidGap") { _ = try StarTrailPlanner.stackingPlan(totalDuration: 60, declination: nil, setup: wide, gapSeconds: .nan) }
        let tooMany = MosaicTestSupport.thrown {
            _ = try StarTrailPlanner.stackingPlan(totalDuration: 86_400, declination: nil, setup: wide, exposureSeconds: 0.5, gapSeconds: 0)
        }
        XCTAssertEqual(tooMany as? StarTrailError, .tooManyFrames(count: 172_800, limit: StarTrailPlanner.maximumFrameCount))
    }

    // MARK: The pole

    func testPoleIsAtTheLatitude() {
        let frame = SkyFrame(date: date, observer: boulder)
        let pole = StarTrailPlanner.pole(frame: frame, refraction: false)
        XCTAssertEqual(pole.hemisphere, .north)
        XCTAssertEqual(pole.direction.altitude, 40.015, accuracy: 0.05)
        XCTAssertEqual(pole.direction.azimuth, 0.0, accuracy: 1e-6)
        XCTAssertTrue(pole.isAboveHorizon)
        // The pole of the reading matches the polar alignment helper.
        XCTAssertEqual(PolarAlignment.polarScopeReading(frame: frame, hemisphere: .north).poleAltitude, pole.direction.altitude, accuracy: 1e-9)
        // Refraction lifts it by about a minute of arc.
        let refracted = StarTrailPlanner.pole(frame: frame)
        XCTAssertGreaterThan(refracted.direction.altitude, pole.direction.altitude)
        XCTAssertEqual(refracted.direction.altitude, pole.direction.altitude, accuracy: 0.05)
        // The other pole is below the horizon from here, at the same angle.
        let south = StarTrailPlanner.pole(frame: frame, hemisphere: .south, refraction: false)
        XCTAssertEqual(south.direction.altitude, -40.015, accuracy: 0.05)
        XCTAssertEqual(south.direction.azimuth, 180.0, accuracy: 1e-6)
        XCTAssertFalse(south.isAboveHorizon)
        // From the southern hemisphere the south pole is the default.
        let sydney = StarTrailPlanner.pole(frame: SkyFrame(date: date, observer: Observer(location: GeographicLocation(latitude: -33.87, longitude: 151.21, elevation: 20))),
                                           refraction: false)
        XCTAssertEqual(sydney.hemisphere, .south)
        XCTAssertEqual(sydney.direction.altitude, 33.87, accuracy: 0.05)
        XCTAssertEqual(sydney.direction.azimuth, 180.0, accuracy: 1e-6)
    }

    func testPolePositionInTheFrame() throws {
        let frame = SkyFrame(date: date, observer: boulder)
        let pole = StarTrailPlanner.pole(frame: frame, refraction: false).direction
        let landscape = FieldOfView.of(sensor: .fullFrame, focalLength: 24)
        // Aimed at the pole it is in the middle.
        let centered = try XCTUnwrap(StarTrailPlanner.polePosition(pole: pole, pointing: pole, frameSize: landscape))
        XCTAssertEqual(centered.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(centered.y, 0.0, accuracy: 1e-9)
        XCTAssertEqual(centered.separation, 0.0, accuracy: 1e-6)
        XCTAssertTrue(centered.isInFrame)
        // Aimed 5° below the pole the pole is above the middle, a tenth of the way up in half-frame units.
        let below = HorizontalCoordinate(azimuth: pole.azimuth, altitude: pole.altitude - 5)
        let above = try XCTUnwrap(StarTrailPlanner.polePosition(pole: pole, pointing: below, frameSize: landscape))
        XCTAssertEqual(above.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(above.y, tan(5.0 * Double.pi / 180) / tan(landscape.vertical / 2 * Double.pi / 180), accuracy: 1e-9)
        XCTAssertEqual(above.separation, 5.0, accuracy: 1e-9)
        // Rolled a quarter turn clockwise the top of the picture points to the right and the pole falls to the left.
        let rolled = try XCTUnwrap(StarTrailPlanner.polePosition(pole: pole, pointing: below, frameSize: landscape, roll: 90))
        XCTAssertEqual(rolled.x, -tan(5.0 * Double.pi / 180) / tan(landscape.horizontal / 2 * Double.pi / 180), accuracy: 1e-9)
        XCTAssertEqual(rolled.y, 0.0, accuracy: 1e-9)
        // Portrait: the frame is turned, with the long side up.
        let portrait = try XCTUnwrap(StarTrailPlanner.polePosition(pole: pole, pointing: below, frameSize: landscape.rotated))
        XCTAssertEqual(portrait.y, tan(5.0 * Double.pi / 180) / tan(landscape.horizontal / 2 * Double.pi / 180), accuracy: 1e-9)
        // 30° away it is outside a 24 mm frame; behind the camera there is no position at all.
        let away = try XCTUnwrap(StarTrailPlanner.polePosition(
            pole: pole, pointing: HorizontalCoordinate(azimuth: pole.azimuth, altitude: pole.altitude - 35), frameSize: landscape))
        XCTAssertFalse(away.isInFrame)
        XCTAssertGreaterThan(away.y, 1.0)
        XCTAssertNil(try StarTrailPlanner.polePosition(pole: pole, pointing: HorizontalCoordinate(azimuth: 180, altitude: 10), frameSize: landscape))
        XCTAssertNil(try StarTrailPlanner.polePosition(pole: pole, pointing: HorizontalCoordinate(azimuth: 90, altitude: 0), frameSize: landscape))
        // Pointing at the zenith still works: the picture is turned with its top to the north.
        XCTAssertNotNil(try StarTrailPlanner.polePosition(pole: pole, pointing: HorizontalCoordinate(azimuth: 0, altitude: 90),
                                                          frameSize: FieldOfView.of(sensor: .fullFrame, focalLength: 14)))
        MosaicTestSupport.assertThrowsKind("invalidFrame") {
            _ = try StarTrailPlanner.polePosition(pole: pole, pointing: pole, frameSize: FrameSize(horizontal: 0, vertical: 10, diagonal: 10))
        }
        MosaicTestSupport.assertThrowsKind("invalidFrame") {
            _ = try StarTrailPlanner.polePosition(pole: pole, pointing: pole, frameSize: FrameSize(horizontal: 10, vertical: 180, diagonal: 10))
        }
    }
}

import XCTest
@testable import LodestarKit

/// The pointing code working on real sky positions from `SkyFrame`.
final class PointingIntegrationTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let observer = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    /// 2026-10-17 04:00 UTC, about 22:00 the evening before in Colorado.
    private let date = Date(timeIntervalSince1970: 1_792_209_600)

    private struct Star {
        let name: String
        let j2000: EquatorialCoordinate
    }

    private let stars = [
        Star(name: "Polaris", j2000: EquatorialCoordinate(rightAscension: 37.954561, declination: 89.264109)),
        Star(name: "Vega", j2000: EquatorialCoordinate(rightAscension: 279.234735, declination: 38.783689)),
        Star(name: "Altair", j2000: EquatorialCoordinate(rightAscension: 297.695827, declination: 8.868321)),
        Star(name: "Deneb", j2000: EquatorialCoordinate(rightAscension: 310.357980, declination: 45.280339)),
        Star(name: "Fomalhaut", j2000: EquatorialCoordinate(rightAscension: 344.412693, declination: -29.622237)),
    ]

    private func apparent(_ star: Star, frame: SkyFrame) -> HorizontalCoordinate {
        frame.horizontal(j2000: star.j2000, refraction: true)
    }

    func testTheTestSkyHasTheStarsWeNeed() {
        let frame = SkyFrame(date: date, observer: observer)
        for star in stars {
            XCTAssertGreaterThan(apparent(star, frame: frame).altitude, 10, star.name)
        }
        XCTAssertLessThan(apparent(stars[1], frame: frame).altitude, 80)
    }

    func testAimingAtAStarIsOnTargetForEveryMount() throws {
        let frame = SkyFrame(date: date, observer: observer)
        var random = PointingTestRandom(seed: 701)
        for mount in MountProfile.presets {
            for star in stars {
                let target = apparent(star, frame: frame)
                let attitude = try Support.attitude(mount: mount,
                                                    frame: Support.cameraFrame(boresight: target, rollDegrees: random.uniform(-60, 60)),
                                                    referenceAzimuth: 7.7)
                let solution = PointingSolution.solve(attitude: attitude, mount: mount)
                var tracker = GuidanceTracker(onTargetThreshold: 0.5)
                let guidance = try XCTUnwrap(tracker.update(solution: solution, target: target))
                XCTAssertEqual(guidance.state, .onTarget, "\(star.name) \(mount.id)")
                XCTAssertEqual(guidance.separation, 0, accuracy: 1e-6)
                // What the camera sees is the star: the inverse sky transform returns its catalogue place.
                let seen = frame.j2000(fromHorizontal: solution.boresight, refracted: true)
                XCTAssertEqual(seen.angularSeparation(to: star.j2000) * 3600, 0, accuracy: 3, star.name)
            }
        }
    }

    func testTheCelestialPoleIsAtTheLatitudeAndTheArrowFindsIt() throws {
        let frame = SkyFrame(date: date, observer: observer)
        let pole = frame.horizontalOfCelestialPole(north: true, refraction: true)
        XCTAssertEqual(pole.altitude, 40.015, accuracy: 0.05)
        // Camera 10° to the right of and 5° below the pole: the arrow points left and up on the screen.
        let mount = MountProfile.backCameraPortrait
        let reported = HorizontalCoordinate(azimuth: pole.azimuth + 10 / cos(AstroMath.radians(pole.altitude)), altitude: pole.altitude - 5)
        let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: reported, rollDegrees: 0))
        var tracker = GuidanceTracker(onTargetThreshold: 0.5)
        let guidance = try XCTUnwrap(tracker.update(solution: PointingSolution.solve(attitude: attitude, mount: mount), target: pole))
        XCTAssertLessThan(guidance.panDelta, 0)
        XCTAssertGreaterThan(guidance.tiltDelta, 0)
        XCTAssertGreaterThan(sin(guidance.arrowAngle), 0)
        XCTAssertLessThan(cos(guidance.arrowAngle), 0)
        XCTAssertEqual(guidance.state, .far)
    }

    func testAlignmentOnStarsRemovesCompassAndMountErrors() throws {
        // The phone's compass reads 6° off and the clamp tilts the lens 1.5°; align on Polaris, then on
        // Vega and Deneb, and check the result on stars never used.
        let frame = SkyFrame(date: date, observer: observer)
        let mount = MountProfile.backCameraLandscapeLeft
        var random = PointingTestRandom(seed: 702)
        let scenario = AlignmentTestScenario(headingOffset: 6, correction: Vector3(0.8, 1.2, 0), mount: mount)
        func point(_ star: Star, index: Int) throws -> AlignmentPoint {
            try scenario.point(target: apparent(star, frame: frame), roll: random.uniform(-20, 20), random: &random,
                               index: index, name: star.name)
        }
        var model = try AlignmentModel.identity.adding(try point(stars[1], index: 0), mount: mount)
        XCTAssertEqual(model.points.first?.name, "Vega")
        model = try model.adding(try point(stars[3], index: 1), mount: mount)
        model = try model.adding(try point(stars[0], index: 2), mount: mount)
        XCTAssertLessThan(model.rmsResidual, 0.02)
        XCTAssertEqual(model.headingOffset, 6, accuracy: 0.1)
        for star in [stars[2], stars[4]] {
            let target = apparent(star, frame: frame)
            let attitude = try scenario.point(target: target, roll: 10, random: &random).attitude
            let solution = PointingSolution.solve(attitude: attitude, mount: mount, alignment: model)
            XCTAssertEqual(solution.boresight.angularSeparation(to: target), 0, accuracy: 0.05, star.name)
            let uncorrected = PointingSolution.solve(attitude: attitude, mount: mount)
            XCTAssertGreaterThan(uncorrected.boresight.angularSeparation(to: target), 2, star.name)
        }
    }
}

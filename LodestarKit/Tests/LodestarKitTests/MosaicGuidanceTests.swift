import XCTest
@testable import LodestarKit

final class MosaicGuidanceTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))

    /// 2026-10-17 04:00 UTC, about 22:00 the evening before in Colorado: right ascension 22.7 h is on the meridian.
    private let date = Date(timeIntervalSince1970: 1_792_209_600)

    private let region = MosaicRegion.equatorial(
        center: EquatorialCoordinate(rightAscensionHours: 22.7, declination: 20), width: 60, height: 30)

    private func plan(positionAngle: Double = 0) throws -> MosaicPlan {
        try MosaicPlanner.plan(
            region: .equatorial(center: EquatorialCoordinate(rightAscensionHours: 22.7, declination: 20), width: 60, height: 30,
                                positionAngle: positionAngle),
            frame: MosaicTestSupport.frame(focalLength: 50))
    }

    // MARK: Directions

    func testEquatorialPanelsPointWhereTheSkyFrameSaysTheyAre() throws {
        let plan = try plan()
        let frame = SkyFrame(date: date, observer: boulder)
        let pointings = MosaicGuidance.pointings(for: plan, frame: frame)
        XCTAssertEqual(pointings.count, plan.panelCount)
        XCTAssertGreaterThanOrEqual(plan.panelCount, 4)
        for (index, pointing) in pointings.enumerated() {
            let panel = plan.panels[index]
            XCTAssertEqual(pointing.panelIndex, index)
            XCTAssertEqual(pointing.direction, frame.horizontal(j2000: try XCTUnwrap(panel.center.equatorialCoordinate), properMotion: nil, refraction: true))
            XCTAssertEqual(pointing.corners, try panel.corners.map {
                frame.horizontal(j2000: try XCTUnwrap($0.equatorialCoordinate), properMotion: nil, refraction: true)
            })
            XCTAssertEqual(pointing, MosaicGuidance.pointing(of: panel, in: plan, frame: frame))
            XCTAssertEqual(pointing.isAboveHorizon, pointing.direction.altitude > 0)
            XCTAssertLessThanOrEqual(pointing.lowestAltitude, pointing.direction.altitude)
        }
        let geometric = MosaicGuidance.pointings(for: plan, frame: frame, refraction: false)
        for (index, pointing) in geometric.enumerated() {
            XCTAssertEqual(pointing.direction,
                           frame.horizontal(j2000: try XCTUnwrap(plan.panels[index].center.equatorialCoordinate), properMotion: nil, refraction: false))
        }
    }

    func testRefractionRaisesPanelsNearTheHorizon() throws {
        let low = try MosaicPlanner.plan(
            region: .equatorial(center: EquatorialCoordinate(rightAscensionHours: 22.7, declination: -45), width: 10, height: 10),
            frame: MosaicTestSupport.frame(focalLength: 50))
        let frame = SkyFrame(date: date, observer: boulder)
        let refracted = MosaicGuidance.pointing(of: low.panels[0], in: low, frame: frame, refraction: true)
        let geometric = MosaicGuidance.pointing(of: low.panels[0], in: low, frame: frame, refraction: false)
        XCTAssertLessThan(geometric.direction.altitude, 10.0)
        XCTAssertGreaterThan(refracted.direction.altitude, geometric.direction.altitude)
        XCTAssertEqual(refracted.direction.azimuth, geometric.direction.azimuth, accuracy: 1e-9)
        let high = try plan()
        let middle = try XCTUnwrap(high.panels.max {
            MosaicGuidance.pointing(of: $0, in: high, frame: frame, refraction: false).direction.altitude
                < MosaicGuidance.pointing(of: $1, in: high, frame: frame, refraction: false).direction.altitude
        })
        let highRefracted = MosaicGuidance.pointing(of: middle, in: high, frame: frame, refraction: true).direction.altitude
        let highGeometric = MosaicGuidance.pointing(of: middle, in: high, frame: frame, refraction: false).direction.altitude
        XCTAssertEqual(highRefracted, highGeometric, accuracy: 0.02)
    }

    func testHorizontalPanelsStayWhereTheyAreAndStayLevel() throws {
        let horizontal = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60),
            frame: MosaicTestSupport.frame(focalLength: 24))
        let first = MosaicGuidance.pointings(for: horizontal, frame: SkyFrame(date: date, observer: boulder))
        let later = MosaicGuidance.pointings(for: horizontal,
                                             frame: SkyFrame(date: Date(timeIntervalSince1970: 1_792_209_600 + 7200), observer: boulder))
        XCTAssertEqual(first, later)
        for (index, pointing) in first.enumerated() {
            XCTAssertEqual(horizontal.panels[index].center.horizontalCoordinate, pointing.direction)
            XCTAssertEqual(try horizontal.panels[index].corners.map { try XCTUnwrap($0.horizontalCoordinate) }, pointing.corners)
            XCTAssertEqual(pointing.roll, 0.0)
            XCTAssertTrue(pointing.isAboveHorizon)
            XCTAssertLessThan(pointing.lowestAltitude, pointing.direction.altitude)
        }
    }

    func testPanelsBelowTheHorizonAreFlagged() throws {
        let south = try MosaicPlanner.plan(
            region: .equatorial(center: EquatorialCoordinate(rightAscensionHours: 10, declination: -70), width: 20, height: 10),
            frame: MosaicTestSupport.frame(focalLength: 50))
        let frame = SkyFrame(date: date, observer: boulder)
        for pointing in MosaicGuidance.pointings(for: south, frame: frame) {
            XCTAssertFalse(pointing.isAboveHorizon)
            XCTAssertLessThan(pointing.lowestAltitude, 0)
        }
        let partly = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: -10, maximumAltitude: 20),
            frame: MosaicTestSupport.frame(focalLength: 24))
        let pointing = try XCTUnwrap(MosaicGuidance.pointings(for: partly, frame: frame).first)
        XCTAssertTrue(pointing.isAboveHorizon)
        XCTAssertLessThan(pointing.lowestAltitude, 0)
    }

    // MARK: Roll

    func testRollEqualsTheParallacticAngleOfThePanel() throws {
        let plan = try plan()
        var west = 0
        var east = 0
        for hours in [0.0, 2.0, 5.0] {
            let frame = SkyFrame(date: Date(timeIntervalSince1970: 1_792_209_600 + hours * 3600), observer: boulder)
            for pointing in MosaicGuidance.pointings(for: plan, frame: frame) {
                let panel = plan.panels[pointing.panelIndex]
                let apparent = frame.apparentPlace(j2000: try XCTUnwrap(panel.center.equatorialCoordinate))
                let hourAngle = frame.hourAngle(apparentRightAscension: apparent.rightAscension)
                let expected = MosaicGuidance.parallacticAngle(hourAngle: hourAngle, declination: apparent.declination,
                                                               latitude: boulder.location.latitude)
                // The plan's pole is the J2000 pole; the pole of date is up to 0.4° away.
                XCTAssertEqual(AstroMath.normalizeSignedDegrees(pointing.roll - expected), 0.0, accuracy: 0.5, "panel \(panel.id) at +\(hours) h")
                if expected > 5 {
                    XCTAssertGreaterThan(pointing.roll, 0)
                    west += 1
                }
                if expected < -5 {
                    XCTAssertLessThan(pointing.roll, 0)
                    east += 1
                }
            }
        }
        XCTAssertTrue(west > 0 && east > 0)
    }

    func testRollTurnsTheTopOfThePictureTowardsThePole() throws {
        let plan = try plan()
        let frame = SkyFrame(date: date, observer: boulder)
        let pole = frame.horizontalOfCelestialPole(north: true, refraction: false).unitVector
        for pointing in MosaicGuidance.pointings(for: plan, frame: frame, refraction: false) {
            let camera = Support.cameraFrame(boresight: pointing.direction, rollDegrees: pointing.roll)
            let forward = pointing.direction.unitVector
            let towardsPole = (pole - forward * pole.dot(forward)).normalized
            XCTAssertEqual(camera.up.angle(to: towardsPole), 0.0, accuracy: 0.5, "panel \(pointing.panelIndex)")
        }
    }

    func testParallacticAngleKnownValues() {
        // On the meridian the pole is straight up or down.
        XCTAssertEqual(MosaicGuidance.parallacticAngle(hourAngle: 0, declination: 20, latitude: 40), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicGuidance.parallacticAngle(hourAngle: 0, declination: -30, latitude: 40), 0.0, accuracy: 1e-9)
        // On the equator a star on the celestial equator six hours west is on the horizon in the west: the pole is to the right.
        XCTAssertEqual(MosaicGuidance.parallacticAngle(hourAngle: 90, declination: 0, latitude: 0), 90.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicGuidance.parallacticAngle(hourAngle: -90, declination: 0, latitude: 0), -90.0, accuracy: 1e-9)
        // Meeus, Astronomical Algorithms, chapter 14: tan q = sin H / (tan φ cos δ − sin δ cos H).
        let meeus = AstroMath.atan2Deg(
            AstroMath.sinDeg(45),
            tan(AstroMath.radians(40)) * AstroMath.cosDeg(20) - AstroMath.sinDeg(20) * AstroMath.cosDeg(45))
        XCTAssertEqual(MosaicGuidance.parallacticAngle(hourAngle: 45, declination: 20, latitude: 40), meeus, accuracy: 1e-9)
        // It is also the angle between the directions to the pole and the zenith, measured on the sky.
        for latitude in [-60.0, -20.0, 0.0, 35.0, 70.0] {
            for declination in [-50.0, -10.0, 15.0, 60.0] {
                for hourAngle in [-150.0, -75.0, -20.0, 15.0, 80.0, 140.0] {
                    let star = CoordinateTransforms.equatorialToHorizontal(hourAngle: hourAngle, declination: declination, latitude: latitude).unitVector
                    let nearby = CoordinateTransforms.equatorialToHorizontal(hourAngle: hourAngle, declination: declination + 0.05, latitude: latitude).unitVector
                    let towardsPole = (nearby - star * nearby.dot(star)).normalized
                    let level = Vector3(0, 0, 1) - star * star.z
                    if level.length < 1e-3 { continue }
                    let up = level.normalized
                    let measured = AstroMath.atan2Deg(towardsPole.dot(star.cross(up)), towardsPole.dot(up))
                    let formula = MosaicGuidance.parallacticAngle(hourAngle: hourAngle, declination: declination, latitude: latitude)
                    XCTAssertEqual(AstroMath.normalizeSignedDegrees(measured - formula), 0.0, accuracy: 0.05,
                                   "lat \(latitude) dec \(declination) H \(hourAngle)")
                }
            }
        }
    }

    func testPositionAngleTurnsTheRollWithIt() throws {
        // With one panel at the centre, the top of the picture points along the position angle: turning the region
        // by an angle east of north turns the picture counter-clockwise on the sky, and the roll falls by that angle.
        let frame = SkyFrame(date: date, observer: boulder)
        let center = EquatorialCoordinate(rightAscensionHours: 23.5, declination: 20)
        func roll(_ positionAngle: Double) throws -> Double {
            let single = try MosaicPlanner.plan(region: .equatorial(center: center, width: 2, height: 2, positionAngle: positionAngle),
                                                frame: MosaicTestSupport.frame(focalLength: 50))
            XCTAssertEqual(single.panelCount, 1)
            return MosaicGuidance.pointing(of: single.panels[0], in: single, frame: frame).roll
        }
        let base = try roll(0)
        for angle in [10.0, 45.0, 90.0, 170.0, -30.0] {
            XCTAssertEqual(AstroMath.normalizeSignedDegrees(try roll(angle) - (base - angle)), 0.0, accuracy: 1e-3, "angle \(angle)")
        }
    }

    func testCameraRollRoundTripsThroughACameraFrame() throws {
        // The roll of a camera is the roll it was built with; the zenith has no level direction.
        let boresights = [
            HorizontalCoordinate(azimuth: 0, altitude: 0), HorizontalCoordinate(azimuth: 120, altitude: 35),
            HorizontalCoordinate(azimuth: 250, altitude: -20), HorizontalCoordinate(azimuth: 40, altitude: 80),
            HorizontalCoordinate(azimuth: 300, altitude: 89),
        ]
        for boresight in boresights {
            for roll in [-170.0, -90.0, -33.3, 0.0, 12.5, 90.0, 179.0] {
                let camera = Support.cameraFrame(boresight: boresight, rollDegrees: roll)
                XCTAssertEqual(MosaicGuidance.roll(forward: camera.forward, up: camera.up), roll, accuracy: 1e-6, "\(boresight) \(roll)")
                // The scale of the vectors and a part of up along the axis do not matter.
                XCTAssertEqual(MosaicGuidance.roll(forward: camera.forward * 3, up: camera.up * 0.5 + camera.forward * 2), roll, accuracy: 1e-6)
            }
        }
        let zenith = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 0, altitude: 90), rollDegrees: 30)
        XCTAssertEqual(MosaicGuidance.roll(forward: zenith.forward, up: zenith.up), 0.0)
        XCTAssertEqual(MosaicGuidance.roll(forward: Vector3(1, 0, 0), up: Vector3(2, 0, 0)), 0.0)
        // For a panel it is the roll of the pointing: the camera built from the pointing has that roll.
        let plan = try plan()
        let frame = SkyFrame(date: date, observer: boulder)
        for pointing in MosaicGuidance.pointings(for: plan, frame: frame, refraction: false) {
            let camera = Support.cameraFrame(boresight: pointing.direction, rollDegrees: pointing.roll)
            XCTAssertEqual(MosaicGuidance.roll(forward: camera.forward, up: camera.up), pointing.roll, accuracy: 1e-6)
        }
    }

    func testRollNearThePoleIsFinite() throws {
        let polar = try MosaicPlanner.plan(
            region: .equatorial(center: EquatorialCoordinate(rightAscensionHours: 3, declination: 85), width: 30, height: 15),
            frame: MosaicTestSupport.frame(focalLength: 35))
        let frame = SkyFrame(date: date, observer: boulder)
        for pointing in MosaicGuidance.pointings(for: polar, frame: frame) {
            XCTAssertTrue(pointing.roll.isFinite && abs(pointing.roll) <= 180.0)
            XCTAssertGreaterThan(pointing.direction.altitude, 10)
        }
    }

    // MARK: The aiming guidance

    func testAimingGuidanceReachesEveryPanelInShootingOrder() throws {
        // What the Aim screen does: take the panels in shooting order, ask for their direction at the current time,
        // hand it to the guidance as the target, and move on once it reports on target.
        let plan = try MosaicPlanner.plan(region: region, frame: MosaicTestSupport.frame(focalLength: 50),
                                          observerLatitude: boulder.location.latitude)
        let frame = SkyFrame(date: date, observer: boulder)
        let mount = MountProfile.backCameraPortrait
        var tracker = GuidanceTracker(onTargetThreshold: 0.5)
        var reached = 0
        for panel in plan.orderedPanels {
            let pointing = MosaicGuidance.pointing(of: panel, in: plan, frame: frame)
            tracker.reset()
            // A camera pointing 8° to the side is far from the panel...
            let off = HorizontalCoordinate(azimuth: pointing.direction.azimuth + 8, altitude: pointing.direction.altitude)
            let offAttitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: off, rollDegrees: pointing.roll))
            let away = try XCTUnwrap(tracker.update(solution: PointingSolution.solve(attitude: offAttitude, mount: mount), target: pointing.direction))
            XCTAssertNotEqual(away.state, .onTarget)
            // ...and on target once it is aimed at the direction, with the roll of the panel.
            let attitude = try Support.attitude(mount: mount, frame: Support.cameraFrame(boresight: pointing.direction, rollDegrees: pointing.roll))
            let guidance = try XCTUnwrap(tracker.update(solution: PointingSolution.solve(attitude: attitude, mount: mount), target: pointing.direction))
            XCTAssertEqual(guidance.state, .onTarget, "panel \(panel.id)")
            reached += 1
        }
        XCTAssertEqual(reached, plan.panelCount)
    }

    func testPointingAWholePlanIsFast() throws {
        let plan = try MosaicPlanner.plan(
            region: .equatorial(center: EquatorialCoordinate(rightAscensionHours: 22.7, declination: 20), width: 100, height: 60),
            frame: MosaicTestSupport.frame(focalLength: 35))
        let frame = SkyFrame(date: date, observer: boulder)
        _ = MosaicGuidance.pointings(for: plan, frame: frame)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<100 { _ = MosaicGuidance.pointings(for: plan, frame: frame) }
        let perCallMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 100.0 / 1e6
        XCTAssertLessThan(perCallMilliseconds, 20.0, "\(perCallMilliseconds) ms for \(plan.panelCount) panels")
    }
}

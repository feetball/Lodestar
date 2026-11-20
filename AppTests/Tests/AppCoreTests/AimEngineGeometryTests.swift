import CoreGraphics
import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The geometry of the Aim screen: the pinhole projection that lays the sky over the screen, the lens view of a phone that
/// does not look along the lens, the HUD's quarter turns, and the angle texts.
final class AimEngineGeometryTests: XCTestCase {
    private let degreeSign = "\u{00B0}"
    private let arcminuteSign = "\u{2032}"
    private let arcsecondSign = "\u{2033}"
    private let dash = "\u{2014}"

    // MARK: Helpers

    /// A phone from its three device axes written in world (east-north-up) coordinates.
    private func attitude(deviceX: Vector3, deviceY: Vector3, deviceZ: Vector3) throws -> DeviceAttitude {
        // The rows of the CoreMotion matrix are the device axes in the north-west-up frame.
        func row(_ axis: Vector3) -> Vector3 { Vector3(axis.y, -axis.x, axis.z) }
        return try XCTUnwrap(DeviceAttitude(matrix: Matrix3(rows: row(deviceX), row(deviceY), row(deviceZ)),
                                            referenceAzimuth: 0, timestamp: 0))
    }

    /// A phone held upright in portrait that aims its back camera at (`azimuth`, `altitude`), without roll.
    private func uprightAttitude(azimuth: Double, altitude: Double) throws -> DeviceAttitude {
        let az = AstroMath.radians(azimuth), alt = AstroMath.radians(altitude)
        let forward = Vector3(cos(alt) * sin(az), cos(alt) * cos(az), sin(alt))
        let right = Vector3(cos(az), -sin(az), 0)
        let up = Vector3(-sin(alt) * sin(az), -sin(alt) * cos(az), cos(alt))
        return try attitude(deviceX: right, deviceY: up, deviceZ: forward * -1)
    }

    /// A camera of 1000 by 2000 pixels (upright in portrait) whose long side spans 90 degrees. Its short side spans
    /// 2 atan(1/2) = 53.13 degrees, and a viewport of the same aspect gets a focal length of 500 points per half height.
    private func camera() throws -> CameraGeometry {
        try XCTUnwrap(CameraGeometry.portrait(longSideFieldOfView: 90, width: 1000, height: 2000))
    }

    private func assertVector(_ a: Vector3, _ b: Vector3, accuracy: Double = 1e-9, file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x", file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y", file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, "z", file: file, line: line)
    }

    /// Where the sky direction (`azimuth`, `altitude`) appears for a phone held upright at (`azimuth`, `altitude`).
    private func project(_ projection: PinholeProjection, looking look: (Double, Double), at place: (Double, Double)) throws -> ProjectedPoint {
        let attitude = try uprightAttitude(azimuth: look.0, altitude: look.1)
        let direction = HorizontalCoordinate(azimuth: place.0, altitude: place.1).unitVector
        return try XCTUnwrap(projection.project(worldDirection: direction, attitude: attitude, headingOffset: 0))
    }

    // MARK: The range of the virtual lens

    func testTheVirtualLensRangeDefaultAndPresets() {
        XCTAssertEqual(AimProjectionFactory.virtualFieldOfViewRange, 20...100)
        XCTAssertEqual(AimProjectionFactory.defaultVirtualFieldOfView, 60)
        XCTAssertEqual(AimProjectionFactory.virtualFieldOfViewPresets, [100, 60, 40, 20])
        XCTAssertTrue(AimProjectionFactory.virtualFieldOfViewPresets.allSatisfy { AimProjectionFactory.virtualFieldOfViewRange.contains($0) })
        XCTAssertTrue(AimProjectionFactory.virtualFieldOfViewPresets.contains(AimProjectionFactory.defaultVirtualFieldOfView))
    }

    // MARK: The virtual lens

    func testWithoutACameraTheVirtualLensSpansItsFieldOfViewAlongTheLongSide() throws {
        let size = CGSize(width: 400, height: 800)
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: nil, virtualFieldOfView: 60))
        XCTAssertEqual(projection.viewportWidth, 400)
        XCTAssertEqual(projection.viewportHeight, 800)
        XCTAssertEqual(projection.longSideFieldOfView, 60, accuracy: 1e-9)
        XCTAssertEqual(projection.verticalFieldOfView, 60, accuracy: 1e-9)
        XCTAssertLessThan(projection.horizontalFieldOfView, 60)
        // Half the long side (400 points) is tan(30 degrees) focal lengths.
        XCTAssertEqual(projection.focalLength, 400 / AstroMath.tanDeg(30), accuracy: 1e-9)
    }

    func testALandscapeViewportSpansTheFieldOfViewAlongItsWidth() throws {
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: CGSize(width: 800, height: 400), camera: nil,
                                                                       virtualFieldOfView: 60))
        XCTAssertEqual(projection.horizontalFieldOfView, 60, accuracy: 1e-9)
        XCTAssertLessThan(projection.verticalFieldOfView, 60)
        XCTAssertEqual(projection.focalLength, 400 / AstroMath.tanDeg(30), accuracy: 1e-9)
    }

    func testTheVirtualFieldOfViewIsKeptWithinItsRange() throws {
        let size = CGSize(width: 400, height: 800)
        let cases: [(asked: Double, used: Double)] = [
            (60, 60), (20, 20), (100, 100), (35.5, 35.5),
            (19.9, 20), (10, 20), (0, 20), (-30, 20),
            (100.1, 100), (150, 100), (179, 100), (500, 100),
        ]
        for (asked, used) in cases {
            let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: nil, virtualFieldOfView: asked))
            XCTAssertEqual(projection.longSideFieldOfView, used, accuracy: 1e-9, "asked \(asked)")
        }
    }

    func testTheBoresightLandsInTheCentreAndTenDegreesRightOfItByTheLensGeometry() throws {
        // 400 by 800 points, 60 degrees along the long side: the focal length is 400 / tan 30 degrees.
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: CGSize(width: 400, height: 800), camera: nil,
                                                                       virtualFieldOfView: 60))
        let focal = 400 / AstroMath.tanDeg(30)
        let centre = try project(projection, looking: (0, 0), at: (0, 0))
        XCTAssertEqual(centre.x, 200, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 400, accuracy: 1e-9)
        XCTAssertEqual(centre.depth, 1, accuracy: 1e-12)

        let right = try project(projection, looking: (0, 0), at: (10, 0))
        XCTAssertEqual(right.x, 200 + focal * AstroMath.tanDeg(10), accuracy: 1e-9)
        XCTAssertEqual(right.x, 322.16, accuracy: 0.01)
        XCTAssertEqual(right.y, 400, accuracy: 1e-9)
        XCTAssertEqual(right.depth, AstroMath.cosDeg(10), accuracy: 1e-12)

        let left = try project(projection, looking: (0, 0), at: (-10, 0))
        XCTAssertEqual(left.x, 200 - focal * AstroMath.tanDeg(10), accuracy: 1e-9)
        XCTAssertEqual(left.y, 400, accuracy: 1e-9)

        let up = try project(projection, looking: (0, 0), at: (0, 10))
        XCTAssertEqual(up.x, 200, accuracy: 1e-9)
        XCTAssertEqual(up.y, 400 - focal * AstroMath.tanDeg(10), accuracy: 1e-9)
        XCTAssertEqual(up.y, 277.84, accuracy: 0.01)

        let down = try project(projection, looking: (0, 0), at: (0, -10))
        XCTAssertEqual(down.y, 400 + focal * AstroMath.tanDeg(10), accuracy: 1e-9)
    }

    func testThirtyDegreesAboveTheBoresightReachesTheTopEdgeOfTheVirtualLens() throws {
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: CGSize(width: 400, height: 800), camera: nil,
                                                                       virtualFieldOfView: 60))
        XCTAssertEqual(try project(projection, looking: (90, 20), at: (90, 50)).y, 0, accuracy: 1e-9)
        XCTAssertEqual(try project(projection, looking: (90, 20), at: (90, -10)).y, 800, accuracy: 1e-9)
    }

    func testAnEmptyViewportGivesNoProjection() throws {
        let sizes = [CGSize.zero, CGSize(width: 0, height: 800), CGSize(width: 400, height: 0),
                     CGSize(width: -10, height: 800), CGSize(width: 400, height: -1)]
        for size in sizes {
            XCTAssertNil(AimProjectionFactory.projection(viewport: size, camera: nil, virtualFieldOfView: 60), "\(size)")
            XCTAssertNil(AimProjectionFactory.projection(viewport: size, camera: try camera(), virtualFieldOfView: 60), "\(size)")
        }
    }

    // MARK: The projection of a camera picture

    func testTheFocalLengthOfAPictureThatFillsTheViewportExactly() throws {
        // The same aspect: both sides fit, the width wins the tie, and 250 points are tan(26.565 degrees) = 1/2 focal lengths.
        let focal = try XCTUnwrap(AimProjectionFactory.focalLength(filling: CGSize(width: 500, height: 1000), camera: try camera()))
        XCTAssertEqual(focal, 500, accuracy: 1e-6)
        // Twice the size, twice the focal length.
        let doubled = try XCTUnwrap(AimProjectionFactory.focalLength(filling: CGSize(width: 1000, height: 2000), camera: try camera()))
        XCTAssertEqual(doubled, 1000, accuracy: 1e-6)
    }

    func testAViewportNarrowerThanThePictureShowsAllOfItsHeight() throws {
        // 400 by 1000: the picture grows until its height (2000 pixels, 90 degrees) fits and its sides are cropped.
        let size = CGSize(width: 400, height: 1000)
        let focal = try XCTUnwrap(AimProjectionFactory.focalLength(filling: size, camera: try camera()))
        XCTAssertEqual(focal, 500, accuracy: 1e-6)
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: try camera(), virtualFieldOfView: 60))
        XCTAssertEqual(projection.focalLength, 500, accuracy: 1e-6)
        XCTAssertEqual(projection.verticalFieldOfView, 90, accuracy: 1e-6)
        XCTAssertEqual(projection.horizontalFieldOfView, 2 * AstroMath.degrees(atan(200.0 / 500)), accuracy: 1e-6)
        // 45 degrees up and down reach the top and bottom edge.
        XCTAssertEqual(try project(projection, looking: (0, 0), at: (0, 45)).y, 0, accuracy: 1e-6)
        XCTAssertEqual(try project(projection, looking: (0, 0), at: (0, -45)).y, 1000, accuracy: 1e-6)
        XCTAssertEqual(try project(projection, looking: (0, 0), at: (10, 0)).x, 200 + 500 * AstroMath.tanDeg(10), accuracy: 1e-6)
    }

    func testAViewportWiderThanThePictureShowsAllOfItsWidth() throws {
        // 600 by 1000: the picture grows until its width (1000 pixels, 53.13 degrees) fits and the top and bottom are cropped.
        let size = CGSize(width: 600, height: 1000)
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: try camera(), virtualFieldOfView: 60))
        XCTAssertEqual(projection.focalLength, 600, accuracy: 1e-6)
        XCTAssertEqual(projection.horizontalFieldOfView, 2 * AstroMath.degrees(atan(0.5)), accuracy: 1e-6)
        XCTAssertLessThan(projection.verticalFieldOfView, 90)
        XCTAssertEqual(projection.verticalFieldOfView, 2 * AstroMath.degrees(atan(500.0 / 600)), accuracy: 1e-6)
    }

    func testTheCameraTakesPrecedenceOverTheVirtualLens() throws {
        let size = CGSize(width: 500, height: 1000)
        let withCamera = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: try camera(), virtualFieldOfView: 100))
        XCTAssertEqual(withCamera.focalLength, 500, accuracy: 1e-6)
        let without = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: nil, virtualFieldOfView: 100))
        XCTAssertEqual(without.focalLength, 500 / AstroMath.tanDeg(50), accuracy: 1e-9)
        XCTAssertNotEqual(withCamera.focalLength, without.focalLength)
    }

    func testAPictureWithoutUsableSizesOrFieldsOfViewHasNoFocalLength() throws {
        let size = CGSize(width: 500, height: 1000)
        func geometry(horizontal: Double = 53.13, vertical: Double = 90, width: Int = 1000, height: Int = 2000) -> CameraGeometry {
            CameraGeometry(portraitHorizontalFOV: horizontal, portraitVerticalFOV: vertical, imageWidth: width, imageHeight: height)
        }
        XCTAssertNotNil(AimProjectionFactory.focalLength(filling: size, camera: geometry()))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(width: 0)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(height: 0)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(width: -4)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: CGSize(width: 0, height: 1000), camera: geometry()))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: CGSize(width: 500, height: 0), camera: geometry()))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: CGSize(width: -500, height: 1000), camera: geometry()))
        // Equal aspect: the width's field of view is the one used.
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: .nan)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: .infinity)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: 0)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: -20)))
        XCTAssertNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: 180)))
        XCTAssertNotNil(AimProjectionFactory.focalLength(filling: size, camera: geometry(horizontal: 179.9)))
    }

    func testOnlyTheFieldOfViewOfTheSideThatFitsMatters() throws {
        // A narrow viewport fits the height, so a broken width field of view does not matter, and the reverse.
        let narrow = CGSize(width: 400, height: 1000)
        let wide = CGSize(width: 600, height: 1000)
        let brokenWidth = CameraGeometry(portraitHorizontalFOV: .nan, portraitVerticalFOV: 90, imageWidth: 1000, imageHeight: 2000)
        XCTAssertEqual(try XCTUnwrap(AimProjectionFactory.focalLength(filling: narrow, camera: brokenWidth)), 500, accuracy: 1e-6)
        XCTAssertNil(AimProjectionFactory.focalLength(filling: wide, camera: brokenWidth))
        let brokenHeight = CameraGeometry(portraitHorizontalFOV: 53.13, portraitVerticalFOV: 200, imageWidth: 1000, imageHeight: 2000)
        XCTAssertNil(AimProjectionFactory.focalLength(filling: narrow, camera: brokenHeight))
        XCTAssertNotNil(AimProjectionFactory.focalLength(filling: wide, camera: brokenHeight))
    }

    func testAnUnusablePictureFallsBackToTheVirtualLens() throws {
        let size = CGSize(width: 400, height: 800)
        let broken = CameraGeometry(portraitHorizontalFOV: 60, portraitVerticalFOV: 90, imageWidth: 0, imageHeight: 0)
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: size, camera: broken, virtualFieldOfView: 40))
        XCTAssertEqual(projection.longSideFieldOfView, 40, accuracy: 1e-9)
    }

    // MARK: The sky drawn from the lens

    func testTheLensViewOfAPhoneWhoseCameraLooksAlongTheLensIsThePhoneItself() throws {
        let phone = try uprightAttitude(azimuth: 40, altitude: 25)
        let solution = PointingSolution.solve(attitude: phone, mount: .backCameraPortrait)
        let virtual = try XCTUnwrap(AimProjectionFactory.lensViewAttitude(for: solution))
        assertVector(virtual.deviceToWorld * DeviceAttitude.backCameraAxis, solution.boresightVector)
        assertVector(virtual.deviceToWorld * Vector3(1, 0, 0), solution.screenRightVector)
        assertVector(virtual.deviceToWorld * Vector3(0, 1, 0), solution.screenUpVector)
        for (a, b) in zip([virtual.worldToDevice.r0, virtual.worldToDevice.r1, virtual.worldToDevice.r2],
                          [phone.worldToDevice.r0, phone.worldToDevice.r1, phone.worldToDevice.r2]) {
            assertVector(a, b)
        }
        XCTAssertEqual(virtual.referenceAzimuth, 0)
        XCTAssertEqual(virtual.timestamp, 0)
    }

    func testThePhoneLyingOnTheCameraIsDrawnAsAnUprightPhoneLookingAlongTheLens() throws {
        // Screen up, top edge towards the east: the optical axis (device +y) points east at the horizon, the camera's
        // up is the screen normal (the sky's up), and the camera's right is the phone's right edge (south).
        let flat = try attitude(deviceX: Vector3(0, -1, 0), deviceY: Vector3(1, 0, 0), deviceZ: Vector3(0, 0, 1))
        let solution = PointingSolution.solve(attitude: flat, mount: .flatOnTopTopEdgeForward)
        XCTAssertEqual(solution.boresight.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(solution.boresight.azimuth, 90, accuracy: 1e-9)
        XCTAssertFalse(AimConfiguration.phoneCameraFollowsLens(.flatOnTopTopEdgeForward))

        let virtual = try XCTUnwrap(AimProjectionFactory.lensViewAttitude(for: solution))
        // Its back camera looks east, its right edge points south and its top edge up.
        assertVector(virtual.deviceToWorld * DeviceAttitude.backCameraAxis, Vector3(1, 0, 0))
        assertVector(virtual.deviceToWorld * Vector3(1, 0, 0), Vector3(0, -1, 0))
        assertVector(virtual.deviceToWorld * Vector3(0, 1, 0), Vector3(0, 0, 1))
        assertVector(virtual.deviceToWorld * DeviceAttitude.backCameraAxis, solution.boresightVector)

        // Drawn through the pinhole, the lens direction is the centre and a star 10 degrees to its right lies to its right.
        let projection = try XCTUnwrap(AimProjectionFactory.projection(viewport: CGSize(width: 400, height: 800), camera: nil,
                                                                       virtualFieldOfView: 60))
        let centre = try XCTUnwrap(projection.project(worldDirection: Vector3(1, 0, 0), attitude: virtual, headingOffset: 0))
        XCTAssertEqual(centre.x, 200, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 400, accuracy: 1e-9)
        let right = try XCTUnwrap(projection.project(worldDirection: HorizontalCoordinate(azimuth: 100, altitude: 0).unitVector,
                                                     attitude: virtual, headingOffset: 0))
        XCTAssertEqual(right.x, 200 + 400 / AstroMath.tanDeg(30) * AstroMath.tanDeg(10), accuracy: 1e-9)
        XCTAssertEqual(right.y, 400, accuracy: 1e-9)
        let above = try XCTUnwrap(projection.project(worldDirection: HorizontalCoordinate(azimuth: 90, altitude: 10).unitVector,
                                                     attitude: virtual, headingOffset: 0))
        XCTAssertEqual(above.x, 200, accuracy: 1e-9)
        XCTAssertLessThan(above.y, 400)
    }

    func testTheLensViewOfAPhoneOnTheCameraWithItsTopEdgeBackLooksTheOtherWay() throws {
        // Top edge towards the photographer (north), lens pointing south: device -y is the optical axis.
        let flat = try attitude(deviceX: Vector3(1, 0, 0), deviceY: Vector3(0, 1, 0), deviceZ: Vector3(0, 0, 1))
        let solution = PointingSolution.solve(attitude: flat, mount: .flatOnTopTopEdgeBack)
        XCTAssertEqual(solution.boresight.azimuth, 180, accuracy: 1e-9)
        let virtual = try XCTUnwrap(AimProjectionFactory.lensViewAttitude(for: solution))
        assertVector(virtual.deviceToWorld * DeviceAttitude.backCameraAxis, Vector3(0, -1, 0))
        assertVector(virtual.deviceToWorld * DeviceAttitude.backCameraAxis, solution.boresightVector)
        assertVector(virtual.deviceToWorld * Vector3(1, 0, 0), solution.screenRightVector)
        assertVector(virtual.deviceToWorld * Vector3(0, 1, 0), solution.screenUpVector)
    }

    // MARK: The HUD rotation

    /// The gravity of a phone whose world-up appears `angle` degrees clockwise from the top of its screen, with `inPlane`
    /// of its length in the screen plane.
    private func gravity(angle: Double, inPlane: Double = 0.9) -> Vector3 {
        Vector3(-inPlane * AstroMath.sinDeg(angle), -inPlane * AstroMath.cosDeg(angle), -(1 - inPlane * inPlane).squareRoot())
    }

    func testTheRotationsAreQuarterTurnsClockwise() {
        XCTAssertEqual(AimHUDRotation.upright.degrees, 0)
        XCTAssertEqual(AimHUDRotation.clockwise.degrees, 90)
        XCTAssertEqual(AimHUDRotation.upsideDown.degrees, 180)
        XCTAssertEqual(AimHUDRotation.counterclockwise.degrees, 270)
        XCTAssertEqual(AimHUDRotation(rawValue: 90), .clockwise)
        XCTAssertNil(AimHUDRotation(rawValue: 45))
    }

    func testOnlySidewaysRotationsSwapWidthAndHeight() {
        XCTAssertFalse(AimHUDRotation.upright.swapsAxes)
        XCTAssertTrue(AimHUDRotation.clockwise.swapsAxes)
        XCTAssertFalse(AimHUDRotation.upsideDown.swapsAxes)
        XCTAssertTrue(AimHUDRotation.counterclockwise.swapsAxes)
    }

    func testAPhoneHeldInEachOfTheFourWaysGetsTheMatchingRotation() {
        // Gravity along -y is the phone upright. Along -x the phone's left edge points down, and the HUD turns a quarter
        // clockwise to stay upright for the reader; along +x it turns counterclockwise, along +y half a turn.
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: Vector3(0, -1, 0), mount: .backCameraPortrait), .upright)
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: Vector3(-1, 0, 0), mount: .backCameraPortrait), .clockwise)
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: Vector3(0, 1, 0), mount: .backCameraPortrait), .upsideDown)
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: Vector3(1, 0, 0), mount: .backCameraPortrait), .counterclockwise)
    }

    func testWithoutACurrentRotationTheNearestQuarterTurnWins() {
        func rotation(_ angle: Double) -> AimHUDRotation {
            AimHUDRotation.updated(from: nil, gravity: gravity(angle: angle), mount: .backCameraPortrait)
        }
        XCTAssertEqual(rotation(0), .upright)
        XCTAssertEqual(rotation(44.9), .upright)
        XCTAssertEqual(rotation(45.1), .clockwise)
        XCTAssertEqual(rotation(90), .clockwise)
        XCTAssertEqual(rotation(134.9), .clockwise)
        XCTAssertEqual(rotation(135.1), .upsideDown)
        XCTAssertEqual(rotation(180), .upsideDown)
        XCTAssertEqual(rotation(-134.9), .counterclockwise)
        XCTAssertEqual(rotation(-135.1), .upsideDown)
        XCTAssertEqual(rotation(-90), .counterclockwise)
        XCTAssertEqual(rotation(-45.1), .counterclockwise)
        XCTAssertEqual(rotation(-44.9), .upright)
    }

    func testTheGravityComponentAlongTheScreenNormalDoesNotMatterAsLongAsEnoughLiesInThePlane() {
        // More or less tilted back, the phone is still read by its in-plane gravity.
        for inPlane in [0.31, 0.5, 0.9, 1.0] {
            XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: gravity(angle: 90, inPlane: inPlane), mount: .backCameraPortrait),
                           .clockwise, "in-plane \(inPlane)")
        }
    }

    func testTheCurrentRotationIsKeptWithinTheHysteresisBand() {
        func rotation(_ angle: Double, from current: AimHUDRotation) -> AimHUDRotation {
            AimHUDRotation.updated(from: current, gravity: gravity(angle: angle), mount: .backCameraPortrait)
        }
        // Upright holds until the phone is more than 55 degrees round, although the nearest quarter turn changes at 45.
        XCTAssertEqual(rotation(54.9, from: .upright), .upright)
        XCTAssertEqual(rotation(-54.9, from: .upright), .upright)
        XCTAssertEqual(rotation(55.1, from: .upright), .clockwise)
        XCTAssertEqual(rotation(-55.1, from: .upright), .counterclockwise)
        // From the clockwise rotation (90) the band is 35 ... 145.
        XCTAssertEqual(rotation(35.1, from: .clockwise), .clockwise)
        XCTAssertEqual(rotation(144.9, from: .clockwise), .clockwise)
        XCTAssertEqual(rotation(34.9, from: .clockwise), .upright)
        XCTAssertEqual(rotation(145.1, from: .clockwise), .upsideDown)
        // The same angle gives different answers depending on where the HUD is.
        XCTAssertEqual(rotation(50, from: .upright), .upright)
        XCTAssertEqual(rotation(50, from: .clockwise), .clockwise)
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: gravity(angle: 50), mount: .backCameraPortrait), .clockwise)
    }

    func testTheHysteresisBandWrapsAroundHalfACircle() {
        func rotation(_ angle: Double, from current: AimHUDRotation) -> AimHUDRotation {
            AimHUDRotation.updated(from: current, gravity: gravity(angle: angle), mount: .backCameraPortrait)
        }
        // Counterclockwise is 270, which is -90: a phone at -100 is 10 degrees away from it, at 170 it is 100 away.
        XCTAssertEqual(rotation(-100, from: .counterclockwise), .counterclockwise)
        XCTAssertEqual(rotation(-35.1, from: .counterclockwise), .counterclockwise)
        XCTAssertEqual(rotation(180, from: .counterclockwise), .upsideDown)
        // Upside down is 180 and also -180.
        XCTAssertEqual(rotation(-170, from: .upsideDown), .upsideDown)
        XCTAssertEqual(rotation(170, from: .upsideDown), .upsideDown)
        XCTAssertEqual(rotation(125.1, from: .upsideDown), .upsideDown)
        XCTAssertEqual(rotation(124.9, from: .upsideDown), .clockwise)
        XCTAssertEqual(rotation(0, from: .upsideDown), .upright)
    }

    func testAPhoneLyingFlatKeepsTheCurrentRotation() {
        let flat = Vector3(0.1, 0.1, -0.99)
        for current in [AimHUDRotation.upright, .clockwise, .upsideDown, .counterclockwise] {
            XCTAssertEqual(AimHUDRotation.updated(from: current, gravity: flat, mount: .backCameraPortrait), current)
            XCTAssertEqual(AimHUDRotation.updated(from: current, gravity: flat, mount: .flatOnTopTopEdgeBack), current)
        }
        // Just under and just over the limit (0.3 of gravity in the screen plane).
        XCTAssertEqual(AimHUDRotation.updated(from: .upright, gravity: Vector3(-0.29, 0, -0.9571), mount: .backCameraPortrait), .upright)
        XCTAssertEqual(AimHUDRotation.updated(from: .upright, gravity: Vector3(-0.31, 0, -0.9507), mount: .backCameraPortrait), .clockwise)
    }

    func testAFlatPhoneWithoutACurrentRotationGetsTheRotationThatSuitsTheMount() {
        let flat = Vector3(0, 0, -1)
        // A phone on the camera with its lens along the bottom edge is read from behind, top edge towards the photographer.
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: flat, mount: .flatOnTopTopEdgeBack), .upsideDown)
        XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: flat, mount: .flatOnTopTopEdgeForward), .upright)
        for mount in [MountProfile.backCameraPortrait, .backCameraPortraitUpsideDown, .backCameraLandscapeLeft, .backCameraLandscapeRight] {
            XCTAssertEqual(AimHUDRotation.updated(from: nil, gravity: flat, mount: mount), .upright, mount.id)
        }
    }

    func testAnOffsetIsTurnedFromTheReadersViewToTheScreen() {
        func rotated(_ rotation: AimHUDRotation, _ width: Double, _ height: Double) -> (Double, Double) {
            let result = rotation.rotated(CGSize(width: width, height: height))
            return (Double(result.width), Double(result.height))
        }
        let upright = rotated(.upright, 10, 4)
        XCTAssertEqual(upright.0, 10, accuracy: 1e-9)
        XCTAssertEqual(upright.1, 4, accuracy: 1e-9)
        // A quarter turn clockwise: what the reader sees to the right lies towards the bottom of the screen.
        let clockwise = rotated(.clockwise, 10, 4)
        XCTAssertEqual(clockwise.0, -4, accuracy: 1e-9)
        XCTAssertEqual(clockwise.1, 10, accuracy: 1e-9)
        let upsideDown = rotated(.upsideDown, 10, 4)
        XCTAssertEqual(upsideDown.0, -10, accuracy: 1e-9)
        XCTAssertEqual(upsideDown.1, -4, accuracy: 1e-9)
        let counterclockwise = rotated(.counterclockwise, 10, 4)
        XCTAssertEqual(counterclockwise.0, 4, accuracy: 1e-9)
        XCTAssertEqual(counterclockwise.1, -10, accuracy: 1e-9)
        let zero = rotated(.clockwise, 0, 0)
        XCTAssertEqual(zero.0, 0, accuracy: 1e-12)
        XCTAssertEqual(zero.1, 0, accuracy: 1e-12)
    }

    func testFourQuarterTurnsOfAnOffsetComeBackToTheStart() {
        var offset = CGSize(width: 7, height: -3)
        for _ in 0..<4 {
            offset = AimHUDRotation.clockwise.rotated(offset)
        }
        XCTAssertEqual(Double(offset.width), 7, accuracy: 1e-9)
        XCTAssertEqual(Double(offset.height), -3, accuracy: 1e-9)
        let half = AimHUDRotation.upsideDown.rotated(AimHUDRotation.clockwise.rotated(CGSize(width: 2, height: 5)))
        let threeQuarters = AimHUDRotation.counterclockwise.rotated(CGSize(width: 2, height: 5))
        XCTAssertEqual(Double(half.width), Double(threeQuarters.width), accuracy: 1e-9)
        XCTAssertEqual(Double(half.height), Double(threeQuarters.height), accuracy: 1e-9)
    }

    // MARK: Angle text

    func testAnAngleFromOneDegreeUpIsShownWithOneDecimal() {
        XCTAssertEqual(AimFormat.angle(23.46), "23.5" + degreeSign)
        XCTAssertEqual(AimFormat.angle(23.44), "23.4" + degreeSign)
        XCTAssertEqual(AimFormat.angle(1), "1.0" + degreeSign)
        XCTAssertEqual(AimFormat.angle(1.04), "1.0" + degreeSign)
        XCTAssertEqual(AimFormat.angle(10), "10.0" + degreeSign)
        XCTAssertEqual(AimFormat.angle(99.96), "100.0" + degreeSign)
        XCTAssertEqual(AimFormat.angle(180), "180.0" + degreeSign)
    }

    func testAnAngleHasNoSign() {
        XCTAssertEqual(AimFormat.angle(-12.34), "12.3" + degreeSign)
        XCTAssertEqual(AimFormat.angle(-1), "1.0" + degreeSign)
        XCTAssertEqual(AimFormat.angle(-0.5), "30" + arcminuteSign)
    }

    func testAnAngleBelowOneDegreeIsShownInArcminutesOrArcseconds() {
        XCTAssertEqual(AimFormat.angle(0.5), "30" + arcminuteSign)
        XCTAssertEqual(AimFormat.angle(0.75), "45" + arcminuteSign)
        XCTAssertEqual(AimFormat.angle(0.1), "6" + arcminuteSign)
        XCTAssertEqual(AimFormat.angle(0.05), "3" + arcminuteSign)
        XCTAssertEqual(AimFormat.angle(0.99), "59" + arcminuteSign)
        XCTAssertEqual(AimFormat.angle(0.0003), "1" + arcsecondSign)
        XCTAssertEqual(AimFormat.angle(0.0005), "2" + arcsecondSign)
        XCTAssertEqual(AimFormat.angle(0), "0" + arcsecondSign)
    }

    func testAnAngleThatIsNotANumberIsADash() {
        XCTAssertEqual(AimFormat.angle(.nan), dash)
        XCTAssertEqual(AimFormat.angle(.infinity), dash)
        XCTAssertEqual(AimFormat.angle(-.infinity), dash)
    }

    func testSpokenAnglesAreWholeDegrees() {
        XCTAssertEqual(AimFormat.spoken(23), "23 degrees")
        XCTAssertEqual(AimFormat.spoken(23.4), "23 degrees")
        XCTAssertEqual(AimFormat.spoken(23.6), "24 degrees")
        XCTAssertEqual(AimFormat.spoken(2), "2 degrees")
        XCTAssertEqual(AimFormat.spoken(1.5), "2 degrees")
        XCTAssertEqual(AimFormat.spoken(180), "180 degrees")
    }

    func testSpokenAnglesNameOneDegreeAndLessThanOne() {
        XCTAssertEqual(AimFormat.spoken(1), "1 degree")
        XCTAssertEqual(AimFormat.spoken(1.4), "1 degree")
        XCTAssertEqual(AimFormat.spoken(0.5), "1 degree")
        XCTAssertEqual(AimFormat.spoken(0.49), "under one degree")
        XCTAssertEqual(AimFormat.spoken(0.2), "under one degree")
        XCTAssertEqual(AimFormat.spoken(0), "under one degree")
        XCTAssertEqual(AimFormat.spoken(-0.3), "under one degree")
    }

    func testSpokenAnglesIgnoreTheSignAndStopAtAFullTurn() {
        XCTAssertEqual(AimFormat.spoken(-23), "23 degrees")
        XCTAssertEqual(AimFormat.spoken(-1), "1 degree")
        XCTAssertEqual(AimFormat.spoken(360), "360 degrees")
        XCTAssertEqual(AimFormat.spoken(500), "360 degrees")
        XCTAssertEqual(AimFormat.spoken(-1000), "360 degrees")
    }

    func testASpokenAngleThatIsNotANumberIsUnknown() {
        XCTAssertEqual(AimFormat.spoken(.nan), "unknown")
        XCTAssertEqual(AimFormat.spoken(.infinity), "unknown")
        XCTAssertEqual(AimFormat.spoken(-.infinity), "unknown")
    }
}

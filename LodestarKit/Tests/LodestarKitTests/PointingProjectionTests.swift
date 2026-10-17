import XCTest
@testable import LodestarKit

final class PointingProjectionTests: XCTestCase {
    private typealias Support = PointingTestSupport

    private func makeProjection(width: Double = 390, height: Double = 844, longSideFOV: Double = 65) throws -> PinholeProjection {
        try XCTUnwrap(PinholeProjection(viewportWidth: width, viewportHeight: height, longSideFieldOfView: longSideFOV))
    }

    /// Where the sky direction (`azimuth`, `altitude`) appears in the viewport.
    private func pixel(_ projection: PinholeProjection, _ attitude: DeviceAttitude,
                       azimuth: Double, altitude: Double) throws -> ProjectedPoint {
        try XCTUnwrap(projection.project(worldDirection: HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector,
                                         attitude: attitude, headingOffset: 0))
    }

    /// A phone held upright in portrait, back camera towards `boresight` with no roll.
    private func uprightAttitude(facing boresight: HorizontalCoordinate, referenceAzimuth: Double = 0) throws -> DeviceAttitude {
        let frame = Support.cameraFrame(boresight: boresight, rollDegrees: 0)
        return try Support.attitude(mount: .backCameraPortrait, frame: frame, referenceAzimuth: referenceAzimuth)
    }

    // MARK: Geometry

    func testCentreOfTheViewportIsThePhoneCameraDirection() throws {
        var random = PointingTestRandom(seed: 301)
        let projection = try makeProjection()
        for _ in 0..<100 {
            let attitude = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: random.uniform(-180, 180)))
            let offset = random.uniform(-180, 180)
            let axis = attitude.withHeadingOffset(offset).deviceToWorld * DeviceAttitude.backCameraAxis
            let centre = try XCTUnwrap(projection.project(worldDirection: axis, attitude: attitude, headingOffset: offset))
            XCTAssertEqual(centre.x, 195, accuracy: 1e-9)
            XCTAssertEqual(centre.y, 422, accuracy: 1e-9)
            XCTAssertEqual(centre.depth, 1, accuracy: 1e-12)
            Support.assertVector(try XCTUnwrap(projection.unproject(x: 195, y: 422, attitude: attitude, headingOffset: offset)), axis)
        }
    }

    func testFieldOfViewReachesTheViewportEdges() throws {
        let projection = try makeProjection(width: 390, height: 844, longSideFOV: 65)
        let attitude = try uprightAttitude(facing: HorizontalCoordinate(azimuth: 0, altitude: 0))
        let half = 32.5
        let top = try pixel(projection, attitude, azimuth: 0, altitude: half)
        XCTAssertEqual(top.y, 0, accuracy: 1e-9)
        XCTAssertEqual(top.x, 195, accuracy: 1e-9)
        let bottom = try pixel(projection, attitude, azimuth: 0, altitude: -half)
        XCTAssertEqual(bottom.y, 844, accuracy: 1e-9)
        // The short side spans its own, smaller, field of view.
        let horizontal = projection.horizontalFieldOfView
        XCTAssertLessThan(horizontal, 65)
        let right = try pixel(projection, attitude, azimuth: horizontal / 2, altitude: 0)
        XCTAssertEqual(right.x, 390, accuracy: 1e-9)
        XCTAssertEqual(right.y, 422, accuracy: 1e-9)
        let left = try pixel(projection, attitude, azimuth: -horizontal / 2, altitude: 0)
        XCTAssertEqual(left.x, 0, accuracy: 1e-9)
        XCTAssertEqual(projection.longSideFieldOfView, 65, accuracy: 1e-9)
        XCTAssertEqual(projection.verticalFieldOfView, 65, accuracy: 1e-9)
    }

    func testLongSideIsTheWidthOfALandscapeViewport() throws {
        let projection = try makeProjection(width: 844, height: 390, longSideFOV: 65)
        XCTAssertEqual(projection.horizontalFieldOfView, 65, accuracy: 1e-9)
        XCTAssertLessThan(projection.verticalFieldOfView, 65)
        XCTAssertEqual(projection.longSideFieldOfView, 65, accuracy: 1e-9)
    }

    func testExplicitFocalLengthAndFieldOfViewAreConsistent() throws {
        let fromFOV = try makeProjection(width: 390, height: 844, longSideFOV: 70)
        let fromFocal = try XCTUnwrap(PinholeProjection(viewportWidth: 390, viewportHeight: 844, focalLength: fromFOV.focalLength))
        XCTAssertEqual(fromFocal, fromFOV)
        XCTAssertEqual(fromFOV.focalLength, 422 / tan(AstroMath.radians(35)), accuracy: 1e-9)
    }

    func testScreenOrientationMatchesTheSky() throws {
        // Upright phone facing north: east is to the right of the picture, up is up the screen,
        // and the y coordinate grows downwards.
        let projection = try makeProjection()
        let attitude = try uprightAttitude(facing: HorizontalCoordinate(azimuth: 0, altitude: 10))
        func point(_ azimuth: Double, _ altitude: Double) throws -> ProjectedPoint {
            try pixel(projection, attitude, azimuth: azimuth, altitude: altitude)
        }
        XCTAssertGreaterThan(try point(5, 10).x, 195)
        XCTAssertEqual(try point(5, 10).y, 422, accuracy: 4)
        XCTAssertLessThan(try point(-5, 10).x, 195)
        XCTAssertLessThan(try point(0, 15).y, 422)
        XCTAssertGreaterThan(try point(0, 5).y, 422)
    }

    func testScreenOrientationFollowsAPhoneRolledInTheHand() throws {
        // Phone turned 90° clockwise (as seen from behind): its right edge now points down. The
        // sky's "up" therefore appears towards the left of the screen and east towards the top.
        let facing = HorizontalCoordinate(azimuth: 0, altitude: 0)
        let attitude = try Support.attitude(mount: .backCameraPortrait,
                                            frame: Support.cameraFrame(boresight: facing, rollDegrees: 90))
        let projection = try makeProjection()
        let above = try pixel(projection, attitude, azimuth: 0, altitude: 5)
        XCTAssertLessThan(above.x, 195)
        XCTAssertEqual(above.y, 422, accuracy: 1e-6)
        let east = try pixel(projection, attitude, azimuth: 5, altitude: 0)
        XCTAssertLessThan(east.y, 422)
        XCTAssertEqual(east.x, 195, accuracy: 1e-6)
    }

    func testProjectAndUnprojectAreInverse() throws {
        var random = PointingTestRandom(seed: 302)
        let projection = try makeProjection(width: 430, height: 932, longSideFOV: 80)
        for _ in 0..<500 {
            let attitude = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: random.uniform(-180, 180)))
            let offset = random.uniform(-30, 30)
            // Pixels anywhere (also outside the viewport) survive the round trip.
            let x = random.uniform(-500, 900), y = random.uniform(-900, 1800)
            let ray = try XCTUnwrap(projection.unproject(x: x, y: y, attitude: attitude, headingOffset: offset))
            XCTAssertEqual(ray.length, 1, accuracy: 1e-12)
            let back = try XCTUnwrap(projection.project(worldDirection: ray * 7, attitude: attitude, headingOffset: offset))
            XCTAssertEqual(back.x, x, accuracy: 1e-6)
            XCTAssertEqual(back.y, y, accuracy: 1e-6)
        }
    }

    func testUnprojectedRaysMatchTheSkyDirections() throws {
        // Upright phone facing north at 10° altitude: the top of the viewport is the direction 32.5° higher.
        let projection = try makeProjection()
        let attitude = try uprightAttitude(facing: HorizontalCoordinate(azimuth: 0, altitude: 10))
        let ray = try XCTUnwrap(projection.unproject(x: 195, y: 0, attitude: attitude, headingOffset: 0))
        let coordinate = HorizontalCoordinate(vector: ray)
        XCTAssertEqual(coordinate.altitude, 42.5, accuracy: 1e-9)
        XCTAssertEqual(Support.azimuthDifference(coordinate.azimuth, 0), 0, accuracy: 1e-9)
    }

    func testDirectionsBehindOrGrazingTheCameraAreNotProjected() throws {
        let projection = try makeProjection()
        let facing = HorizontalCoordinate(azimuth: 30, altitude: 20)
        let attitude = try uprightAttitude(facing: facing)
        XCTAssertNil(projection.project(worldDirection: facing.unitVector * -1, attitude: attitude, headingOffset: 0))
        // Exactly 90° off-axis (the image plane) and just short of it.
        let sideways = Support.cameraFrame(boresight: facing, rollDegrees: 0).right
        XCTAssertNil(projection.project(worldDirection: sideways, attitude: attitude, headingOffset: 0))
        let grazing = (facing.unitVector * 1e-8 + sideways).normalized
        XCTAssertNil(projection.project(worldDirection: grazing, attitude: attitude, headingOffset: 0))
        let nearly = (facing.unitVector * 0.01 + sideways).normalized
        XCTAssertNotNil(projection.project(worldDirection: nearly, attitude: attitude, headingOffset: 0))
        XCTAssertNil(projection.project(worldDirection: .zero, attitude: attitude, headingOffset: 0))
        XCTAssertNil(projection.project(worldDirection: Vector3(.nan, 0, 1), attitude: attitude, headingOffset: 0))
        XCTAssertNil(projection.project(worldDirection: Vector3(0, .infinity, 1), attitude: attitude, headingOffset: 0))
        XCTAssertNil(projection.unproject(x: .nan, y: 3, attitude: attitude, headingOffset: 0))
        XCTAssertNil(projection.unproject(x: 3, y: .infinity, attitude: attitude, headingOffset: 0))
    }

    func testDepthShrinksAwayFromTheCentre() throws {
        let projection = try makeProjection()
        let attitude = try uprightAttitude(facing: HorizontalCoordinate(azimuth: 0, altitude: 0))
        var previous = 2.0
        for degrees in stride(from: 0.0, through: 80.0, by: 10.0) {
            let point = try pixel(projection, attitude, azimuth: degrees, altitude: 0)
            XCTAssertEqual(point.depth, cos(AstroMath.radians(degrees)), accuracy: 1e-12)
            XCTAssertLessThan(point.depth, previous)
            previous = point.depth
        }
    }

    func testBatchProjectionMatchesSingleProjection() throws {
        var random = PointingTestRandom(seed: 303)
        let projection = try makeProjection()
        let attitude = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: 12))
        let directions = (0..<200).map { _ in random.unitVector() }
        let batch = projection.project(worldDirections: directions + [.zero], attitude: attitude, headingOffset: 7)
        XCTAssertEqual(batch.count, directions.count + 1)
        for (direction, projected) in zip(directions, batch) {
            XCTAssertEqual(projected, projection.project(worldDirection: direction, attitude: attitude, headingOffset: 7))
        }
        XCTAssertNil(batch[directions.count])
        XCTAssertTrue(batch.contains { $0 == nil })
        XCTAssertTrue(batch.contains { $0 != nil })
    }

    func testHeadingOffsetAppliesToTheOverlay() throws {
        let projection = try makeProjection()
        // The phone reports azimuth 0; with a +12° compass correction it really faces azimuth 12.
        let attitude = try uprightAttitude(facing: HorizontalCoordinate(azimuth: 0, altitude: 15))
        let star = HorizontalCoordinate(azimuth: 12, altitude: 15).unitVector
        let centred = try XCTUnwrap(projection.project(worldDirection: star, attitude: attitude, headingOffset: 12))
        XCTAssertEqual(centred.x, 195, accuracy: 1e-9)
        XCTAssertEqual(centred.y, 422, accuracy: 1e-9)
        let uncorrected = try XCTUnwrap(projection.project(worldDirection: star, attitude: attitude, headingOffset: 0))
        XCTAssertGreaterThan(uncorrected.x, 195)
        // Equivalent to turning the reference frame.
        let turned = attitude.withHeadingOffset(12)
        let viaFrame = try XCTUnwrap(projection.project(worldDirection: star, attitude: turned, headingOffset: 0))
        XCTAssertEqual(viaFrame, centred)
    }

    func testContainsHonoursTheMargin() throws {
        let projection = try makeProjection()
        func point(_ x: Double, _ y: Double) -> ProjectedPoint { ProjectedPoint(x: x, y: y, depth: 1) }
        XCTAssertTrue(projection.contains(point(0, 0)))
        XCTAssertTrue(projection.contains(point(390, 844)))
        XCTAssertFalse(projection.contains(point(-1, 10)))
        XCTAssertFalse(projection.contains(point(10, 845)))
        XCTAssertTrue(projection.contains(point(-10, 850), margin: 10))
        XCTAssertFalse(projection.contains(point(-11, 850), margin: 10))
    }

    func testInvalidProjectionsAreRejected() {
        XCTAssertNil(PinholeProjection(viewportWidth: 0, viewportHeight: 800, longSideFieldOfView: 60))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: -1, longSideFieldOfView: 60))
        XCTAssertNil(PinholeProjection(viewportWidth: .nan, viewportHeight: 800, longSideFieldOfView: 60))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, longSideFieldOfView: 0))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, longSideFieldOfView: 180))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, longSideFieldOfView: .nan))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, longSideFieldOfView: -10))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, focalLength: 0))
        XCTAssertNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, focalLength: .infinity))
        XCTAssertNotNil(PinholeProjection(viewportWidth: 400, viewportHeight: 800, longSideFieldOfView: 120))
    }

    // MARK: DSLR frame outline

    private func outlineSolution(mount: MountProfile = .backCameraPortrait, roll: Double = 20) throws -> PointingSolution {
        let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 60, altitude: 30), rollDegrees: roll)
        return PointingSolution.solve(attitude: try Support.attitude(mount: mount, frame: frame), mount: mount)
    }

    func testOutlineCornersAndEdgesLieOnTheFrameBorder() throws {
        let solution = try outlineSolution()
        let samples = 6
        let outline = PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 40, verticalFOV: 27, samplesPerEdge: samples)
        XCTAssertEqual(outline.count, 4 * samples)
        let halfWidth = tan(AstroMath.radians(20)), halfHeight = tan(AstroMath.radians(13.5))
        // Picture-plane (gnomonic) coordinates of each sample: right and up of the picture.
        let plane = outline.map { direction -> (x: Double, y: Double) in
            let along = direction.dot(solution.boresightVector)
            XCTAssertEqual(direction.length, 1, accuracy: 1e-12)
            XCTAssertGreaterThan(along, 0)
            return (direction.dot(solution.cameraRightVector) / along, direction.dot(solution.cameraUpVector) / along)
        }
        for point in plane {
            XCTAssertEqual(max(abs(point.x) / halfWidth, abs(point.y) / halfHeight), 1, accuracy: 1e-9)
        }
        // The loop is the full rectangle, run clockwise as seen by the photographer: the shoelace
        // area in the right/up plane is negative.
        var doubleArea = 0.0
        for index in plane.indices {
            let a = plane[index], b = plane[(index + 1) % plane.count]
            doubleArea += a.x * b.y - b.x * a.y
        }
        XCTAssertEqual(doubleArea / 2, -4 * halfWidth * halfHeight, accuracy: 1e-9)

        // First sample is the top-left corner, then the top-right corner after `samples` points.
        let topLeft = outline[0], topRight = outline[samples]
        XCTAssertEqual(topLeft.dot(solution.cameraRightVector) / topLeft.dot(solution.boresightVector), -halfWidth, accuracy: 1e-9)
        XCTAssertEqual(topLeft.dot(solution.cameraUpVector) / topLeft.dot(solution.boresightVector), halfHeight, accuracy: 1e-9)
        XCTAssertEqual(topRight.dot(solution.cameraRightVector) / topRight.dot(solution.boresightVector), halfWidth, accuracy: 1e-9)
        XCTAssertEqual(topRight.dot(solution.cameraUpVector) / topRight.dot(solution.boresightVector), halfHeight, accuracy: 1e-9)
        // Corner distance from the boresight: atan(√(tan²(h/2) + tan²(v/2))).
        let corner = AstroMath.degrees(atan((halfWidth * halfWidth + halfHeight * halfHeight).squareRoot()))
        XCTAssertEqual(topLeft.angle(to: solution.boresightVector), corner, accuracy: 1e-9)
        // The middle of the top edge is 13.5° above the boresight.
        let middle = outline[samples / 2]
        XCTAssertEqual(middle.angle(to: solution.boresightVector), 13.5, accuracy: 1e-9)
        XCTAssertEqual(middle.dot(solution.cameraRightVector), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(middle.dot(solution.cameraUpVector), 0)
    }

    func testOutlineOfTheFieldOfViewMatchesThePhoneViewWhenAxesCoincide() throws {
        // DSLR aligned with the phone camera: its frame is a centred rectangle in the phone view.
        let projection = try makeProjection(width: 390, height: 844, longSideFOV: 70)
        let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 200, altitude: 25), rollDegrees: 0)
        let attitude = try Support.attitude(mount: .backCameraPortrait, frame: frame)
        let solution = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
        let outline = PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 20, samplesPerEdge: 1)
        XCTAssertEqual(outline.count, 4)
        let points = try outline.map { try XCTUnwrap(projection.project(worldDirection: $0, attitude: attitude, headingOffset: 0)) }
        let halfWidth = projection.focalLength * tan(AstroMath.radians(15))
        let halfHeight = projection.focalLength * tan(AstroMath.radians(10))
        let expected = [(195 - halfWidth, 422 - halfHeight), (195 + halfWidth, 422 - halfHeight),
                        (195 + halfWidth, 422 + halfHeight), (195 - halfWidth, 422 + halfHeight)]
        for (point, corner) in zip(points, expected) {
            XCTAssertEqual(point.x, corner.0, accuracy: 1e-6)
            XCTAssertEqual(point.y, corner.1, accuracy: 1e-6)
        }
        // Straight picture edges stay straight in the rectilinear view: mid-edge samples are collinear.
        let fine = PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 20, samplesPerEdge: 4)
        let top = try fine[0..<4].map { try XCTUnwrap(projection.project(worldDirection: $0, attitude: attitude, headingOffset: 0)) }
        for point in top { XCTAssertEqual(point.y, top[0].y, accuracy: 1e-6) }
    }

    func testOutlineRejectsInvalidArguments() throws {
        let solution = try outlineSolution()
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 0, verticalFOV: 20, samplesPerEdge: 4).isEmpty)
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 180, samplesPerEdge: 4).isEmpty)
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: .nan, verticalFOV: 20, samplesPerEdge: 4).isEmpty)
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: -5, samplesPerEdge: 4).isEmpty)
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 20, samplesPerEdge: 0).isEmpty)
        XCTAssertTrue(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 20, samplesPerEdge: -3).isEmpty)
        XCTAssertEqual(PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 30, verticalFOV: 20, samplesPerEdge: 5000).count, 4000)
        // A very wide lens still gives finite directions.
        let wide = PinholeProjection.dslrFrameOutline(solution: solution, horizontalFOV: 120, verticalFOV: 100, samplesPerEdge: 3)
        XCTAssertEqual(wide.count, 12)
        XCTAssertTrue(wide.allSatisfy { $0.isFinite })
    }

    func testOutlineFollowsTheMountOrientation() throws {
        // With the phone turned to landscape in the clamp the DSLR's up is the phone's side edge, but
        // the outline is defined by the camera's own axes and does not change with the mount.
        let frame = Support.cameraFrame(boresight: HorizontalCoordinate(azimuth: 60, altitude: 30), rollDegrees: 20)
        let a = PointingSolution.solve(attitude: try Support.attitude(mount: .backCameraPortrait, frame: frame), mount: .backCameraPortrait)
        let landscape = try Support.attitude(mount: .backCameraLandscapeRight, frame: frame)
        let b = PointingSolution.solve(attitude: landscape, mount: .backCameraLandscapeRight)
        let outlineA = PinholeProjection.dslrFrameOutline(solution: a, horizontalFOV: 40, verticalFOV: 27, samplesPerEdge: 3)
        let outlineB = PinholeProjection.dslrFrameOutline(solution: b, horizontalFOV: 40, verticalFOV: 27, samplesPerEdge: 3)
        for (u, v) in zip(outlineA, outlineB) { Support.assertVector(u, v, accuracy: 1e-9) }
    }
}

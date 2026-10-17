import XCTest
@testable import LodestarKit

extension PointingTestSupport {
    /// A preset together with the geometry derived by hand: the camera axes in device coordinates and
    /// the device-frame screen directions in which a move to the camera's right / up is drawn.
    struct ExpectedMount {
        let mount: MountProfile
        let axis: Vector3
        let up: Vector3
        let right: Vector3
        let screenRight: Vector3
        let screenUp: Vector3
    }

    static let expectedMounts: [ExpectedMount] = [
        // Phone upright in portrait, back camera along the lens.
        ExpectedMount(mount: .backCameraPortrait, axis: Vector3(0, 0, -1), up: Vector3(0, 1, 0),
                      right: Vector3(1, 0, 0), screenRight: Vector3(1, 0, 0), screenUp: Vector3(0, 1, 0)),
        // Phone upside down: the camera's up is the bottom edge, its right the left edge.
        ExpectedMount(mount: .backCameraPortraitUpsideDown, axis: Vector3(0, 0, -1), up: Vector3(0, -1, 0),
                      right: Vector3(-1, 0, 0), screenRight: Vector3(-1, 0, 0), screenUp: Vector3(0, -1, 0)),
        // UIDeviceOrientation.landscapeLeft: top edge to the photographer's left, bottom edge to the right.
        ExpectedMount(mount: .backCameraLandscapeLeft, axis: Vector3(0, 0, -1), up: Vector3(1, 0, 0),
                      right: Vector3(0, -1, 0), screenRight: Vector3(0, -1, 0), screenUp: Vector3(1, 0, 0)),
        // UIDeviceOrientation.landscapeRight: top edge to the photographer's right.
        ExpectedMount(mount: .backCameraLandscapeRight, axis: Vector3(0, 0, -1), up: Vector3(-1, 0, 0),
                      right: Vector3(0, 1, 0), screenRight: Vector3(0, 1, 0), screenUp: Vector3(-1, 0, 0)),
        // Lying on top of the camera, top edge towards the lens: right edge = camera right,
        // "tilt up" drawn towards the top edge.
        ExpectedMount(mount: .flatOnTopTopEdgeForward, axis: Vector3(0, 1, 0), up: Vector3(0, 0, 1),
                      right: Vector3(1, 0, 0), screenRight: Vector3(1, 0, 0), screenUp: Vector3(0, 1, 0)),
        // Lying on top with the top edge towards the photographer: the lens points down the screen.
        ExpectedMount(mount: .flatOnTopTopEdgeBack, axis: Vector3(0, -1, 0), up: Vector3(0, 0, 1),
                      right: Vector3(-1, 0, 0), screenRight: Vector3(-1, 0, 0), screenUp: Vector3(0, -1, 0)),
    ]
}

final class PointingMountTests: XCTestCase {
    private typealias Support = PointingTestSupport

    func testPresetsMatchTheHandDerivedGeometry() {
        XCTAssertEqual(Support.expectedMounts.count, MountProfile.presets.count)
        for expected in Support.expectedMounts {
            let mount = expected.mount
            Support.assertVector(mount.cameraAxis, expected.axis, accuracy: 1e-12, mount.id)
            Support.assertVector(mount.cameraUp, expected.up, accuracy: 1e-12, mount.id)
            Support.assertVector(mount.cameraRight, expected.right, accuracy: 1e-12, mount.id)
            Support.assertVector(mount.screenRight, expected.screenRight, accuracy: 1e-12, mount.id)
            Support.assertVector(mount.screenUp, expected.screenUp, accuracy: 1e-12, mount.id)
        }
        XCTAssertEqual(Support.expectedMounts.map { $0.mount.id }, MountProfile.presets.map { $0.id })
    }

    func testPresetsAreOrthonormalRightHandedAndDistinct() {
        for mount in MountProfile.presets {
            XCTAssertEqual(mount.cameraAxis.length, 1, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.cameraUp.length, 1, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.cameraAxis.dot(mount.cameraUp), 0, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.cameraRight.length, 1, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.screenRight.length, 1, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.screenUp.length, 1, accuracy: 1e-12, mount.id)
            XCTAssertEqual(mount.screenRight.z, 0, mount.id)
            XCTAssertEqual(mount.screenUp.z, 0, mount.id)
            XCTAssertEqual(mount.screenRight.dot(mount.screenUp), 0, accuracy: 1e-12, mount.id)
            // Seen from the front of the screen the arrow plane is not mirrored.
            Support.assertVector(mount.screenRight.cross(mount.screenUp), Vector3(0, 0, 1), accuracy: 1e-12, mount.id)
        }
        XCTAssertEqual(Set(MountProfile.presets.map { $0.id }).count, MountProfile.presets.count)
        XCTAssertEqual(Set(MountProfile.presets.map { $0.name }).count, MountProfile.presets.count)
    }

    func testLandscapeNamesFollowUIDeviceOrientation() {
        // landscapeLeft: the top edge (device +y) is on the photographer's left, the bottom edge
        // (home button / charging port) on the right.
        let left = MountProfile.backCameraLandscapeLeft
        XCTAssertLessThan(left.cameraRight.dot(Vector3(0, 1, 0)), -0.99)
        XCTAssertGreaterThan(left.cameraRight.dot(Vector3(0, -1, 0)), 0.99)
        // The portrait phone's right edge (+x) is then at the top of the picture.
        XCTAssertGreaterThan(left.cameraUp.dot(Vector3(1, 0, 0)), 0.99)
        let right = MountProfile.backCameraLandscapeRight
        XCTAssertGreaterThan(right.cameraRight.dot(Vector3(0, 1, 0)), 0.99)
        XCTAssertGreaterThan(right.cameraUp.dot(Vector3(-1, 0, 0)), 0.99)
    }

    func testFlatOnTopMountsPointAlongTheTopOrBottomEdge() {
        XCTAssertEqual(MountProfile.flatOnTopTopEdgeForward.cameraAxis, Vector3(0, 1, 0))
        XCTAssertEqual(MountProfile.flatOnTopTopEdgeBack.cameraAxis, Vector3(0, -1, 0))
        // The screen normal (towards the user, device +z) is the camera's up for both.
        XCTAssertEqual(MountProfile.flatOnTopTopEdgeForward.cameraUp, Vector3(0, 0, 1))
        XCTAssertEqual(MountProfile.flatOnTopTopEdgeBack.cameraUp, Vector3(0, 0, 1))
    }

    func testTiltingTheMountKeepsTheScreenMapping() throws {
        // Between the upright phone (axis −z) and the phone lying down (axis +y) the lens axis
        // swings in the y–z plane; the screen keeps showing right as right and up as up.
        for degrees in stride(from: 0.0, through: 90.0, by: 15.0) {
            let theta = AstroMath.radians(degrees)
            let mount = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, sin(theta), -cos(theta)),
                                                         cameraUp: Vector3(0, cos(theta), sin(theta))))
            Support.assertVector(mount.screenRight, Vector3(1, 0, 0), accuracy: 1e-12, "\(degrees)°")
            Support.assertVector(mount.screenUp, Vector3(0, 1, 0), accuracy: 1e-12, "\(degrees)°")
        }
    }

    func testScreenMappingIsAlwaysAProperRotationOfTheViewPlane() throws {
        var random = PointingTestRandom(seed: 71)
        var accepted = 0
        for _ in 0..<500 {
            guard let mount = MountProfile.custom(cameraAxis: random.unitVector(), cameraUp: random.unitVector()) else { continue }
            accepted += 1
            XCTAssertEqual(mount.screenRight.z, 0)
            XCTAssertEqual(mount.screenUp.z, 0)
            XCTAssertEqual(mount.screenRight.length, 1, accuracy: 1e-12)
            XCTAssertEqual(mount.screenUp.length, 1, accuracy: 1e-12)
            XCTAssertEqual(mount.screenRight.dot(mount.screenUp), 0, accuracy: 1e-9)
            Support.assertVector(mount.screenRight.cross(mount.screenUp), Vector3(0, 0, 1), accuracy: 1e-9)
        }
        XCTAssertGreaterThan(accepted, 400)
    }

    func testAxisPointingOutOfTheScreenStillHasAMapping() throws {
        let mount = try XCTUnwrap(MountProfile.custom(cameraAxis: Vector3(0, 0, 1), cameraUp: Vector3(0, 1, 0)))
        XCTAssertEqual(mount.screenRight.length, 1, accuracy: 1e-12)
        XCTAssertEqual(mount.screenUp.length, 1, accuracy: 1e-12)
        Support.assertVector(mount.screenRight.cross(mount.screenUp), Vector3(0, 0, 1), accuracy: 1e-12)
    }

    func testCustomMountMatchesTheEquivalentPreset() throws {
        for expected in Support.expectedMounts {
            let custom = try XCTUnwrap(MountProfile.custom(cameraAxis: expected.axis * 3, cameraUp: expected.up * 0.5))
            Support.assertVector(custom.cameraAxis, expected.mount.cameraAxis, accuracy: 1e-12)
            Support.assertVector(custom.cameraUp, expected.mount.cameraUp, accuracy: 1e-12)
            Support.assertVector(custom.screenRight, expected.mount.screenRight, accuracy: 1e-12)
            Support.assertVector(custom.screenUp, expected.mount.screenUp, accuracy: 1e-12)
        }
    }

    func testCustomMountMakesUpPerpendicularToTheAxis() throws {
        let mount = try XCTUnwrap(MountProfile.custom(name: "Tilted", cameraAxis: Vector3(0, 0, -2), cameraUp: Vector3(0.1, 1, 0.3)))
        XCTAssertEqual(mount.name, "Tilted")
        XCTAssertEqual(mount.id, "custom")
        Support.assertVector(mount.cameraAxis, Vector3(0, 0, -1), accuracy: 1e-12)
        Support.assertVector(mount.cameraUp, Vector3(0.1, 1, 0).normalized, accuracy: 1e-12)
    }

    func testCustomMountRejectsDegenerateInput() {
        let up = Vector3(0, 1, 0)
        XCTAssertNil(MountProfile.custom(cameraAxis: .zero, cameraUp: up))
        XCTAssertNil(MountProfile.custom(cameraAxis: up, cameraUp: .zero))
        XCTAssertNil(MountProfile.custom(cameraAxis: up, cameraUp: up * 2)) // parallel
        XCTAssertNil(MountProfile.custom(cameraAxis: up, cameraUp: up * -1)) // anti-parallel
        XCTAssertNil(MountProfile.custom(cameraAxis: up, cameraUp: Vector3(0.05, 1, 0))) // within 3° of parallel
        XCTAssertNotNil(MountProfile.custom(cameraAxis: up, cameraUp: Vector3(0.5, 1, 0)))
        XCTAssertNil(MountProfile.custom(cameraAxis: Vector3(.nan, 0, 1), cameraUp: up))
        XCTAssertNil(MountProfile.custom(cameraAxis: up, cameraUp: Vector3(0, .infinity, 0)))
    }

    func testNamesAreLengthCapped() throws {
        let mount = try XCTUnwrap(MountProfile.custom(name: String(repeating: "x", count: 500),
                                                     cameraAxis: Vector3(0, 0, -1), cameraUp: Vector3(0, 1, 0)))
        XCTAssertEqual(mount.name.count, 80)
    }

    func testCodableRoundTrip() throws {
        let custom = try XCTUnwrap(MountProfile.custom(name: "Hot shoe, tilted", cameraAxis: Vector3(0.1, 0.5, -0.8),
                                                      cameraUp: Vector3(0, 0.8, 0.5)))
        for mount in MountProfile.presets + [custom] {
            let data = try JSONEncoder().encode(mount)
            let decoded = try JSONDecoder().decode(MountProfile.self, from: data)
            XCTAssertEqual(decoded.id, mount.id)
            XCTAssertEqual(decoded.name, mount.name)
            Support.assertVector(decoded.cameraAxis, mount.cameraAxis, accuracy: 1e-15)
            Support.assertVector(decoded.cameraUp, mount.cameraUp, accuracy: 1e-15)
            Support.assertVector(decoded.screenRight, mount.screenRight, accuracy: 1e-15)
            Support.assertVector(decoded.screenUp, mount.screenUp, accuracy: 1e-15)
        }
    }

    func testDecodingRejectsInvalidGeometry() {
        let degenerate = """
        {"id":"x","name":"x","cameraAxis":{"x":0,"y":0,"z":0},"cameraUp":{"x":0,"y":1,"z":0}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(MountProfile.self, from: Data(degenerate.utf8)))
        let parallel = """
        {"id":"x","name":"x","cameraAxis":{"x":0,"y":1,"z":0},"cameraUp":{"x":0,"y":2,"z":0}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(MountProfile.self, from: Data(parallel.utf8)))
    }
}

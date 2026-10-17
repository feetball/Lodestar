import XCTest
@testable import LodestarKit

/// A small deterministic random source (SplitMix64) so the property tests give the same results on
/// every platform and compiler version.
struct PointingTestRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextBits() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [low, high).
    mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * Double(nextBits() >> 11) / 9_007_199_254_740_992.0
    }

    /// Standard normal (Box–Muller).
    mutating func gaussian() -> Double {
        let u1 = max(uniform(0, 1), 1e-300), u2 = uniform(0, 1)
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    mutating func unitVector() -> Vector3 {
        let z = uniform(-1, 1), angle = uniform(0, 2 * Double.pi)
        let r = (1 - z * z).squareRoot()
        return Vector3(r * cos(angle), r * sin(angle), z)
    }

    /// A uniformly distributed proper rotation (from a normalised Gaussian quaternion).
    mutating func rotation() -> Matrix3 {
        var w = gaussian(), x = gaussian(), y = gaussian(), z = gaussian()
        let norm = (w * w + x * x + y * y + z * z).squareRoot()
        w /= norm; x /= norm; y /= norm; z /= norm
        return Matrix3(rows: Vector3(1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
                       Vector3(2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
                       Vector3(2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))
    }

    mutating func horizontal(altitude: ClosedRange<Double> = -90...90) -> HorizontalCoordinate {
        HorizontalCoordinate(azimuth: uniform(0, 360), altitude: uniform(altitude.lowerBound, altitude.upperBound))
    }

    /// A small random rotation whose three rotation-vector components have standard deviation `sigmaDegrees`.
    mutating func smallRotation(sigmaDegrees: Double) -> Matrix3 {
        let vector = Vector3(gaussian(), gaussian(), gaussian()) * (sigmaDegrees * Double.pi / 180)
        return Matrix3.rotation(axis: vector, angleRadians: vector.length)
    }
}

/// Test fixtures built from the geometric definition of the frames, deliberately not from the
/// library's own formulas.
enum PointingTestSupport {
    typealias CameraFrame = (right: Vector3, up: Vector3, forward: Vector3)

    /// A phone attitude from the device axes written in ENU world coordinates. The rows of the
    /// CoreMotion matrix are the device axes in the reference frame, whose x axis has true azimuth
    /// `referenceAzimuth`, whose z axis is up and whose y axis is 90° counter-clockwise of x.
    static func attitude(deviceX: Vector3, deviceY: Vector3, deviceZ: Vector3,
                         referenceAzimuth psi: Double = 0, timestamp: TimeInterval = 0) throws -> DeviceAttitude {
        let s = sin(psi * Double.pi / 180), c = cos(psi * Double.pi / 180)
        let referenceX = Vector3(s, c, 0), referenceY = Vector3(-c, s, 0), referenceZ = Vector3(0, 0, 1)
        func row(_ axis: Vector3) -> Vector3 {
            Vector3(axis.dot(referenceX), axis.dot(referenceY), axis.dot(referenceZ))
        }
        return try XCTUnwrap(DeviceAttitude(matrix: Matrix3(rows: row(deviceX), row(deviceY), row(deviceZ)),
                                            referenceAzimuth: psi, timestamp: timestamp))
    }

    /// The camera axes in the world for a boresight and a roll: roll 0 has the camera's right side
    /// level, positive roll tilts the right side down (clockwise as seen by the photographer).
    static func cameraFrame(boresight: HorizontalCoordinate, rollDegrees: Double) -> CameraFrame {
        let forward = boresight.unitVector
        let levelRight = forward.cross(Vector3(0, 0, 1)).normalized
        let levelUp = levelRight.cross(forward)
        let s = sin(rollDegrees * Double.pi / 180), c = cos(rollDegrees * Double.pi / 180)
        return (levelRight * c - levelUp * s, levelUp * c + levelRight * s, forward)
    }

    /// The phone attitude for which the camera (the mount's axes turned by `correction`, a rotation
    /// vector in degrees applied in the device frame) has the given world frame.
    static func attitude(mount: MountProfile, correction: Vector3 = .zero, frame: CameraFrame,
                         referenceAzimuth: Double = 0, timestamp: TimeInterval = 0) throws -> DeviceAttitude {
        let turn = Matrix3.rotation(axis: correction, angleRadians: correction.length * Double.pi / 180)
        let axis = turn * mount.cameraAxis, up = turn * mount.cameraUp, right = axis.cross(up)
        // Device axis i in the world: the camera frame vectors weighted by that axis's components.
        func deviceAxis(_ component: (Vector3) -> Double) -> Vector3 {
            frame.right * component(right) + frame.up * component(up) + frame.forward * component(axis)
        }
        return try attitude(deviceX: deviceAxis { $0.x }, deviceY: deviceAxis { $0.y }, deviceZ: deviceAxis { $0.z },
                            referenceAzimuth: referenceAzimuth, timestamp: timestamp)
    }

    static func assertVector(_ a: Vector3, _ b: Vector3, accuracy: Double = 1e-9, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, message, file: file, line: line)
    }

    static func assertMatrix(_ a: Matrix3, _ b: Matrix3, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        assertVector(a.r0, b.r0, accuracy: accuracy, file: file, line: line)
        assertVector(a.r1, b.r1, accuracy: accuracy, file: file, line: line)
        assertVector(a.r2, b.r2, accuracy: accuracy, file: file, line: line)
    }

    static func assertRotation(_ m: Matrix3, accuracy: Double = 1e-9,
                               file: StaticString = #filePath, line: UInt = #line) {
        assertMatrix(m * m.transposed, .identity, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(m.determinant, 1, accuracy: accuracy, file: file, line: line)
    }

    /// Signed azimuth difference in degrees, wrapped to (−180, 180].
    static func azimuthDifference(_ a: Double, _ b: Double) -> Double {
        AstroMath.normalizeSignedDegrees(a - b)
    }
}

/// Conventions of the device attitude: frames, signs and sanity orientations.
final class PointingAttitudeTests: XCTestCase {
    private typealias Support = PointingTestSupport

    // MARK: Reference frames

    func testReferenceTransformAtZeroAzimuthIsNorthWestUp() {
        let t = DeviceAttitude.referenceTransform(azimuth: 0)
        Support.assertVector(t * Vector3(0, 1, 0), Vector3(1, 0, 0), accuracy: 1e-15) // north is x
        Support.assertVector(t * Vector3(-1, 0, 0), Vector3(0, 1, 0), accuracy: 1e-15) // west is y
        Support.assertVector(t * Vector3(0, 0, 1), Vector3(0, 0, 1), accuracy: 1e-15) // up is z
        Support.assertVector(t * Vector3(1, 0, 0), Vector3(0, -1, 0), accuracy: 1e-15) // east is −y
    }

    func testReferenceTransformPutsTheAzimuthDirectionOnTheXAxis() {
        for psi in [-170.0, -90, -12.5, 0, 33, 90, 135, 180, 271] {
            let t = DeviceAttitude.referenceTransform(azimuth: psi)
            let along = HorizontalCoordinate(azimuth: psi, altitude: 0).unitVector
            let counterClockwise = HorizontalCoordinate(azimuth: psi - 90, altitude: 0).unitVector
            Support.assertVector(t * along, Vector3(1, 0, 0), accuracy: 1e-12)
            Support.assertVector(t * counterClockwise, Vector3(0, 1, 0), accuracy: 1e-12)
            Support.assertRotation(t, accuracy: 1e-12)
        }
    }

    func testReferenceTransformComposesWithAZRotation() {
        for (psi, delta) in [(0.0, 12.0), (-40, 75), (170, 30), (33, -200)] {
            let combined = DeviceAttitude.referenceTransform(azimuth: psi + delta)
            let composed = DeviceAttitude.referenceTransform(azimuth: psi) * Matrix3.rotationZ(delta * Double.pi / 180)
            Support.assertMatrix(combined, composed, accuracy: 1e-12)
        }
    }

    // MARK: Sanity orientations

    func testUprightFacingNorthWithScreenTowardsTheUser() throws {
        // Device x = east, y = up, z = south; in NWU the rows of the CoreMotion matrix are
        // (0,−1,0), (0,0,1), (−1,0,0).
        let nwu = Matrix3(rows: Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
        let attitude = try XCTUnwrap(DeviceAttitude(matrix: nwu))
        Support.assertVector(attitude.deviceToWorld * DeviceAttitude.backCameraAxis, Vector3(0, 1, 0), accuracy: 1e-15)
        let solution = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
        XCTAssertEqual(solution.boresight.azimuth, 0, accuracy: 1e-9)
        XCTAssertEqual(solution.boresight.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(solution.roll, 0, accuracy: 1e-9)
        // The same orientation built from the physical axes gives the same matrix.
        let built = try Support.attitude(deviceX: Vector3(1, 0, 0), deviceY: Vector3(0, 0, 1), deviceZ: Vector3(0, -1, 0))
        Support.assertMatrix(built.matrix, nwu, accuracy: 1e-15)
    }

    func testFlatOnATableScreenUpTopEdgeEastLooksAtTheNadir() throws {
        // Device y = east, z = up, so x = y × z = south.
        let attitude = try Support.attitude(deviceX: Vector3(0, -1, 0), deviceY: Vector3(1, 0, 0), deviceZ: Vector3(0, 0, 1))
        let nwu = Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
        Support.assertMatrix(attitude.matrix, nwu, accuracy: 1e-15)
        let camera = attitude.deviceToWorld * DeviceAttitude.backCameraAxis
        Support.assertVector(camera, Vector3(0, 0, -1), accuracy: 1e-15)
        XCTAssertEqual(PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait).boresight.altitude, -90, accuracy: 1e-9)
    }

    func testUprightPhoneFacingEachCompassPoint() throws {
        // Held upright the back camera looks along the horizon; the right edge points 90° clockwise of it.
        for azimuth in [0.0, 90, 180, 270, 45, 359.5] {
            let forward = HorizontalCoordinate(azimuth: azimuth, altitude: 0).unitVector
            let right = HorizontalCoordinate(azimuth: azimuth + 90, altitude: 0).unitVector
            let attitude = try Support.attitude(deviceX: right, deviceY: Vector3(0, 0, 1), deviceZ: forward * -1)
            let solution = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait)
            XCTAssertEqual(Support.azimuthDifference(solution.boresight.azimuth, azimuth), 0, accuracy: 1e-9)
            XCTAssertEqual(solution.boresight.altitude, 0, accuracy: 1e-9)
        }
        // The lead's example, written out: facing east the right edge points south, z points west.
        let east = Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
        let solution = PointingSolution.solve(attitude: try XCTUnwrap(DeviceAttitude(matrix: east)), mount: .backCameraPortrait)
        XCTAssertEqual(solution.boresight.azimuth, 90, accuracy: 1e-9)
    }

    func testTiltingTheUprightPhoneBackRaisesTheCamera() throws {
        // Facing north, top edge leaning back by 30°: the back camera looks 30° above the horizon.
        let up = AstroMath.radians(30)
        let top = Vector3(0, -sin(up), cos(up)) // leaning away from the camera direction
        let towardsUser = Vector3(0, -cos(up), -sin(up))
        let attitude = try Support.attitude(deviceX: Vector3(1, 0, 0), deviceY: top, deviceZ: towardsUser)
        let boresight = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait).boresight
        XCTAssertEqual(boresight.altitude, 30, accuracy: 1e-9)
        XCTAssertEqual(boresight.azimuth, 0, accuracy: 1e-9)
    }

    func testReferenceAzimuthTurnsAnyReferenceFrameIntoTheWorld() throws {
        // The same physical pose (upright, facing the reference frame's own x axis) read in frames
        // of different heading: the camera azimuth equals the frame's azimuth.
        let facing = Matrix3(rows: Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
        for psi in [12.0, -8, 135, -170, 180] {
            let attitude = try XCTUnwrap(DeviceAttitude(matrix: facing, referenceAzimuth: psi))
            let boresight = PointingSolution.solve(attitude: attitude, mount: .backCameraPortrait).boresight
            XCTAssertEqual(Support.azimuthDifference(boresight.azimuth, psi), 0, accuracy: 1e-9, "ψ = \(psi)")
        }
    }

    func testHeadingOffsetAddsToTheAzimuth() throws {
        let attitude = try Support.attitude(
            deviceX: Vector3(1, 0, 0), deviceY: Vector3(0, 0, 1), deviceZ: Vector3(0, -1, 0), referenceAzimuth: 20)
        for offset in [12.0, -30, 400, 0] {
            let shifted = attitude.withHeadingOffset(offset)
            let before = HorizontalCoordinate(vector: attitude.deviceToWorld * DeviceAttitude.backCameraAxis)
            let after = HorizontalCoordinate(vector: shifted.deviceToWorld * DeviceAttitude.backCameraAxis)
            XCTAssertEqual(Support.azimuthDifference(after.azimuth, before.azimuth + offset), 0, accuracy: 1e-9)
            XCTAssertEqual(after.altitude, before.altitude, accuracy: 1e-9)
            XCTAssertEqual(shifted.timestamp, attitude.timestamp)
        }
        XCTAssertEqual(attitude.withHeadingOffset(.nan), attitude)
        XCTAssertEqual(attitude.withHeadingOffset(.infinity), attitude)
    }

    // MARK: Validation

    func testNearlyOrthonormalMatricesAreCleanedUp() throws {
        var random = PointingTestRandom(seed: 11)
        for _ in 0..<50 {
            let exact = random.rotation()
            let noisy = Matrix3(rows: exact.r0 * 1.01 + random.unitVector() * 0.004,
                                exact.r1 * 0.99 + random.unitVector() * 0.004,
                                exact.r2 * 1.005 + random.unitVector() * 0.004)
            let attitude = try XCTUnwrap(DeviceAttitude(matrix: noisy))
            Support.assertRotation(attitude.matrix, accuracy: 1e-12)
            // The cleaned matrix stays close to the exact one.
            XCTAssertLessThan((attitude.matrix.r0 - exact.r0).length, 0.02)
        }
    }

    func testInvalidMatricesAreRejected() {
        let nan = Matrix3(rows: Vector3(.nan, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
        let zero = Matrix3(rows: .zero, .zero, .zero)
        let reflection = Matrix3(rows: Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
        let stretched = Matrix3(rows: Vector3(2, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
        let skewed = Matrix3(rows: Vector3(1, 0.5, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
        for matrix in [nan, zero, reflection, stretched, skewed] {
            XCTAssertNil(DeviceAttitude(matrix: matrix))
        }
        XCTAssertNil(DeviceAttitude(matrix: .identity, referenceAzimuth: .nan))
        XCTAssertNil(DeviceAttitude(matrix: .identity, referenceAzimuth: .infinity))
        XCTAssertNil(DeviceAttitude(matrix: .identity, timestamp: .nan))
        XCTAssertNotNil(DeviceAttitude(matrix: .identity))
    }

    func testReferenceAzimuthIsNormalisedToSignedDegrees() throws {
        XCTAssertEqual(try XCTUnwrap(DeviceAttitude(matrix: .identity, referenceAzimuth: 190)).referenceAzimuth, -170, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(DeviceAttitude(matrix: .identity, referenceAzimuth: -180)).referenceAzimuth, 180, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(DeviceAttitude(matrix: .identity, referenceAzimuth: 725)).referenceAzimuth, 5, accuracy: 1e-12)
    }

    func testCodableRoundTripAndRejection() throws {
        var random = PointingTestRandom(seed: 5)
        let original = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: -12.5, timestamp: 1234.5))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeviceAttitude.self, from: data)
        XCTAssertEqual(decoded, original)

        let corrupted = """
        {"matrix":{"r0":{"x":2,"y":0,"z":0},"r1":{"x":0,"y":1,"z":0},"r2":{"x":0,"y":0,"z":1}},
         "referenceAzimuth":0,"timestamp":0}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(DeviceAttitude.self, from: Data(corrupted.utf8)))
    }

    // MARK: Properties of random attitudes

    func testWorldAndDeviceTransformsAreInverseRotations() throws {
        var random = PointingTestRandom(seed: 21)
        for _ in 0..<200 {
            let attitude = try XCTUnwrap(DeviceAttitude(matrix: random.rotation(), referenceAzimuth: random.uniform(-180, 180)))
            Support.assertRotation(attitude.worldToDevice)
            Support.assertRotation(attitude.deviceToWorld)
            Support.assertMatrix(attitude.worldToDevice * attitude.deviceToWorld, .identity)
            // World up expressed in the device frame is the third column of the CoreMotion matrix,
            // whatever the reference heading.
            Support.assertVector(attitude.worldToDevice * Vector3(0, 0, 1), attitude.matrix.c2)
        }
    }

    func testDeviceAxesInTheWorldMatchTheirDefinition() throws {
        var random = PointingTestRandom(seed: 22)
        for _ in 0..<100 {
            let x = random.unitVector()
            let helper = random.unitVector()
            let y = (helper - x * x.dot(helper)).normalized
            let z = x.cross(y)
            let psi = random.uniform(-180, 180)
            let attitude = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z, referenceAzimuth: psi)
            Support.assertVector(attitude.deviceToWorld * Vector3(1, 0, 0), x)
            Support.assertVector(attitude.deviceToWorld * Vector3(0, 1, 0), y)
            Support.assertVector(attitude.deviceToWorld * Vector3(0, 0, 1), z)
        }
    }

    // MARK: Gyro-lock reference frames

    func testArbitraryFrameAzimuthIsRecoveredFromSimultaneousAttitudes() throws {
        var random = PointingTestRandom(seed: 31)
        for _ in 0..<200 {
            let x = random.unitVector()
            let helper = random.unitVector()
            let y = (helper - x * x.dot(helper)).normalized
            let z = x.cross(y)
            let trueNorth = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z)
            let psi = random.uniform(-180, 180)
            let arbitrary = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z, referenceAzimuth: psi)
            let recovered = try XCTUnwrap(ReferenceFrames.referenceAzimuth(
                ofArbitraryFrameAttitude: arbitrary.matrix, knownFrameAttitude: trueNorth.matrix))
            XCTAssertEqual(Support.azimuthDifference(recovered, psi), 0, accuracy: 1e-9)
        }
    }

    func testArbitraryFrameAzimuthWorksFromAMagneticFrame() throws {
        let x = Vector3(0.3, 0.5, 0.2).normalized
        let y = (Vector3(0, 0, 1) - x * x.z).normalized
        let z = x.cross(y)
        let declination = -14.0
        let magnetic = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z, referenceAzimuth: declination)
        let arbitrary = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z, referenceAzimuth: 77)
        let recovered = try XCTUnwrap(ReferenceFrames.referenceAzimuth(
            ofArbitraryFrameAttitude: arbitrary.matrix, knownFrameAttitude: magnetic.matrix, knownFrameAzimuth: declination))
        XCTAssertEqual(recovered, 77, accuracy: 1e-9)
    }

    func testGyroLockKeepsTheCameraDirectionAcrossTheSwitch() throws {
        // Aim the camera, then switch to a gyro-only frame: the camera direction must not change.
        var random = PointingTestRandom(seed: 32)
        for _ in 0..<50 {
            let frame = Support.cameraFrame(boresight: random.horizontal(altitude: -60...80), rollDegrees: random.uniform(-30, 30))
            let compass = try Support.attitude(mount: .backCameraPortrait, frame: frame)
            let gyro = try Support.attitude(mount: .backCameraPortrait, frame: frame, referenceAzimuth: random.uniform(-180, 180))
            let psi = try XCTUnwrap(ReferenceFrames.referenceAzimuth(
                ofArbitraryFrameAttitude: gyro.matrix, knownFrameAttitude: compass.matrix))
            let adopted = try XCTUnwrap(DeviceAttitude(matrix: gyro.matrix, referenceAzimuth: psi))
            Support.assertVector(adopted.deviceToWorld * DeviceAttitude.backCameraAxis,
                                 compass.deviceToWorld * DeviceAttitude.backCameraAxis)
        }
    }

    func testArbitraryFrameAzimuthToleratesSmallInconsistencies() throws {
        var random = PointingTestRandom(seed: 33)
        let x = Vector3(0.6, -0.3, 0.4).normalized
        let y = (Vector3(0, 0, 1) - x * x.z).normalized
        let z = x.cross(y)
        let trueNorth = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z)
        for _ in 0..<50 {
            let psi = random.uniform(-180, 180)
            let arbitrary = try Support.attitude(deviceX: x, deviceY: y, deviceZ: z, referenceAzimuth: psi)
            // The two samples are 0.05° apart in attitude, as when the phone is not perfectly still.
            let jittered = random.smallRotation(sigmaDegrees: 0.05) * arbitrary.matrix
            let recovered = try XCTUnwrap(ReferenceFrames.referenceAzimuth(
                ofArbitraryFrameAttitude: jittered, knownFrameAttitude: trueNorth.matrix))
            XCTAssertEqual(Support.azimuthDifference(recovered, psi), 0, accuracy: 0.5)
        }
    }

    func testArbitraryFrameAzimuthRejectsInconsistentInput() throws {
        let level = Matrix3.identity
        let tilted = Matrix3.rotationX(AstroMath.radians(25))
        XCTAssertNil(ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: tilted, knownFrameAttitude: level))
        let invalid = Matrix3(rows: Vector3(.nan, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
        XCTAssertNil(ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: invalid, knownFrameAttitude: level))
        XCTAssertNil(ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: level, knownFrameAttitude: invalid))
        XCTAssertNil(ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: level, knownFrameAttitude: level,
                                                      knownFrameAzimuth: .infinity))
        // Identical matrices in frames of equal heading give zero.
        let sameFrame = try XCTUnwrap(ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: level, knownFrameAttitude: level))
        XCTAssertEqual(sameFrame, 0, accuracy: 1e-12)
    }

    // MARK: Rotation helpers

    func testRotationVectorMatrixMatchesAxisAngleRotation() {
        var random = PointingTestRandom(seed: 41)
        for _ in 0..<200 {
            let vector = random.unitVector() * random.uniform(0, 3)
            let expected = Matrix3.rotation(axis: vector, angleRadians: vector.length)
            Support.assertMatrix(PointingMath.rotationMatrix(rotationVector: vector), expected, accuracy: 1e-12)
        }
        for tiny in [0.0, 1e-12, 1e-9, 1e-6, 1e-4] {
            let vector = Vector3(0.6, -0.48, 0.64) * tiny
            let matrix = PointingMath.rotationMatrix(rotationVector: vector)
            Support.assertRotation(matrix, accuracy: 1e-14)
            Support.assertVector(matrix * Vector3(0, 0, 1), Vector3(0, 0, 1) + vector.cross(Vector3(0, 0, 1)), accuracy: 1e-8)
        }
    }

    func testYawedRaisesTheAzimuth() {
        var random = PointingTestRandom(seed: 42)
        for _ in 0..<100 {
            let direction = random.horizontal(altitude: -80...80)
            let offset = random.uniform(-200, 200)
            let yawed = HorizontalCoordinate(vector: PointingMath.yawed(direction.unitVector, byAzimuth: offset))
            XCTAssertEqual(Support.azimuthDifference(yawed.azimuth, direction.azimuth + offset), 0, accuracy: 1e-9)
            XCTAssertEqual(yawed.altitude, direction.altitude, accuracy: 1e-9)
        }
    }
}

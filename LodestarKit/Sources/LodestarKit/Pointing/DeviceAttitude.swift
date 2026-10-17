import Foundation

/// The orientation of the phone as reported by CoreMotion, together with the reference frame
/// the numbers are expressed in.
///
/// ## Frames
///
/// * **Device frame** (iOS): x towards the right edge of the phone held in portrait, y towards its
///   top edge, z out of the screen towards the user. The back camera looks along −z.
/// * **Reference frame**: the `CMRotationMatrix` `M` of a `CMAttitude` satisfies
///   `v_device = M · v_reference`, so the rows of `M` are the device axes written in the reference
///   frame. For `.xTrueNorthZVertical` the reference frame is x = north, y = west, z = up ("NWU");
///   `.xMagneticNorthZVertical` is the same with x = magnetic north; `.xArbitraryZVertical` has
///   z = up and a horizontal x axis of unknown heading.
/// * **World frame**: local East–North–Up (ENU), as everywhere else in LodestarKit.
///
/// The reference frame is described by `referenceAzimuth`, the true azimuth of its x axis: 0° for
/// true north, the magnetic declination for magnetic north, and the heading found by
/// `ReferenceFrames` for an arbitrary frame. Together with the matrix this gives
/// `worldToDevice = M · T(ψ)` where `T(ψ)` rotates ENU coordinates into the reference frame.
///
/// A `CMDeviceMotion` sample converts row by row:
///
///     let m = motion.attitude.rotationMatrix
///     let attitude = DeviceAttitude(
///         matrix: Matrix3(rows: Vector3(m.m11, m.m12, m.m13),
///                         Vector3(m.m21, m.m22, m.m23),
///                         Vector3(m.m31, m.m32, m.m33)),
///         referenceAzimuth: 0,            // .xTrueNorthZVertical
///         timestamp: motion.timestamp)
public struct DeviceAttitude: Hashable, Codable, Sendable {
    /// The direction the phone's own back camera looks along, in device coordinates.
    public static let backCameraAxis = Vector3(0, 0, -1)

    /// Largest deviation from orthonormality that is accepted (and cleaned up) in a sensor matrix.
    private static let orthonormalityTolerance = 0.05
    /// Matrices this close to a rotation are used as they are, so a stored attitude reads back unchanged.
    private static let exactnessTolerance = 1e-12

    /// The CoreMotion rotation matrix, `v_device = matrix · v_reference`.
    public let matrix: Matrix3
    /// True azimuth of the reference frame's x axis in degrees, (−180, 180].
    public let referenceAzimuth: Double
    /// Sample time in seconds (`CMDeviceMotion.timestamp`, a monotonic clock); used by
    /// `AttitudeSmoother`, which needs it to increase from sample to sample.
    public let timestamp: TimeInterval

    /// Creates an attitude from a sensor matrix. The matrix is orthonormalised; `nil` is returned
    /// when any input is not finite or the matrix is not close to a proper rotation.
    public init?(matrix: Matrix3, referenceAzimuth: Double = 0, timestamp: TimeInterval = 0) {
        guard matrix.isFinite, referenceAzimuth.isFinite, timestamp.isFinite,
              Self.isRotation(matrix, tolerance: Self.orthonormalityTolerance) else { return nil }
        let cleaned = Self.isRotation(matrix, tolerance: Self.exactnessTolerance) ? matrix : matrix.orthonormalized()
        self.init(orthonormal: cleaned, referenceAzimuth: referenceAzimuth, timestamp: timestamp)
    }

    /// Creates an attitude from a matrix that is already a proper rotation.
    init(orthonormal matrix: Matrix3, referenceAzimuth: Double, timestamp: TimeInterval) {
        self.matrix = matrix
        self.referenceAzimuth = AstroMath.normalizeSignedDegrees(referenceAzimuth)
        self.timestamp = timestamp
    }

    /// Rotation from ENU world coordinates to device coordinates.
    public var worldToDevice: Matrix3 {
        matrix * Self.referenceTransform(azimuth: referenceAzimuth)
    }

    /// Rotation from device coordinates to ENU world coordinates.
    public var deviceToWorld: Matrix3 { worldToDevice.transposed }

    /// The same physical orientation interpreted with the reference frame's x axis `degrees`
    /// further clockwise (east) — the compass correction. A world azimuth computed from the result
    /// equals the uncorrected azimuth plus `degrees`. A non-finite offset is ignored.
    public func withHeadingOffset(_ degrees: Double) -> DeviceAttitude {
        guard degrees.isFinite, degrees != 0 else { return self }
        return DeviceAttitude(orthonormal: matrix, referenceAzimuth: referenceAzimuth + degrees, timestamp: timestamp)
    }

    /// `T(ψ)`: converts ENU coordinates to coordinates in a reference frame that is vertical and
    /// whose x axis has true azimuth `azimuth`. At 0° this is the NWU frame of
    /// `.xTrueNorthZVertical`; the y axis is 90° counter-clockwise (seen from above) of x.
    public static func referenceTransform(azimuth: Double) -> Matrix3 {
        let s = AstroMath.sinDeg(azimuth), c = AstroMath.cosDeg(azimuth)
        return Matrix3(rows: Vector3(s, c, 0), Vector3(-c, s, 0), Vector3(0, 0, 1))
    }

    private static func isRotation(_ m: Matrix3, tolerance: Double) -> Bool {
        abs(m.r0.lengthSquared - 1) <= tolerance
            && abs(m.r1.lengthSquared - 1) <= tolerance
            && abs(m.r2.lengthSquared - 1) <= tolerance
            && abs(m.r0.dot(m.r1)) <= tolerance
            && abs(m.r0.dot(m.r2)) <= tolerance
            && abs(m.r1.dot(m.r2)) <= tolerance
            && m.determinant > 0
    }

    private enum CodingKeys: String, CodingKey {
        case matrix, referenceAzimuth, timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let matrix = try container.decode(Matrix3.self, forKey: .matrix)
        let azimuth = try container.decode(Double.self, forKey: .referenceAzimuth)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        guard let attitude = DeviceAttitude(matrix: matrix, referenceAzimuth: azimuth, timestamp: timestamp) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "The attitude is not finite or its matrix is not a rotation."))
        }
        self = attitude
    }
}

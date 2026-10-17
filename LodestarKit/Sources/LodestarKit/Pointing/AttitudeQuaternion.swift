import Foundation

/// A unit quaternion `w + xi + yj + zk` for the rotations of device attitudes.
struct AttitudeQuaternion: Sendable {
    var w: Double
    var x: Double
    var y: Double
    var z: Double

    /// The quaternion of a proper rotation matrix (Shepperd's method).
    init(_ m: Matrix3) {
        let trace = m[0, 0] + m[1, 1] + m[2, 2]
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            w = s / 4
            x = (m[2, 1] - m[1, 2]) / s
            y = (m[0, 2] - m[2, 0]) / s
            z = (m[1, 0] - m[0, 1]) / s
        } else if m[0, 0] > m[1, 1] && m[0, 0] > m[2, 2] {
            let s = (1 + m[0, 0] - m[1, 1] - m[2, 2]).squareRoot() * 2
            w = (m[2, 1] - m[1, 2]) / s
            x = s / 4
            y = (m[0, 1] + m[1, 0]) / s
            z = (m[0, 2] + m[2, 0]) / s
        } else if m[1, 1] > m[2, 2] {
            let s = (1 + m[1, 1] - m[0, 0] - m[2, 2]).squareRoot() * 2
            w = (m[0, 2] - m[2, 0]) / s
            x = (m[0, 1] + m[1, 0]) / s
            y = s / 4
            z = (m[1, 2] + m[2, 1]) / s
        } else {
            let s = (1 + m[2, 2] - m[0, 0] - m[1, 1]).squareRoot() * 2
            w = (m[1, 0] - m[0, 1]) / s
            x = (m[0, 2] + m[2, 0]) / s
            y = (m[1, 2] + m[2, 1]) / s
            z = s / 4
        }
        self = normalized
    }

    private init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    /// The rotation matrix of the (normalised) quaternion.
    var matrix: Matrix3 {
        let q = normalized
        return Matrix3(
            rows: Vector3(1 - 2 * (q.y * q.y + q.z * q.z), 2 * (q.x * q.y - q.z * q.w), 2 * (q.x * q.z + q.y * q.w)),
            Vector3(2 * (q.x * q.y + q.z * q.w), 1 - 2 * (q.x * q.x + q.z * q.z), 2 * (q.y * q.z - q.x * q.w)),
            Vector3(2 * (q.x * q.z - q.y * q.w), 2 * (q.y * q.z + q.x * q.w), 1 - 2 * (q.x * q.x + q.y * q.y)))
    }

    var normalized: AttitudeQuaternion {
        let length = Self.norm(w, x, y, z)
        guard length > 0 else { return AttitudeQuaternion(w: 1, x: 0, y: 0, z: 0) }
        return AttitudeQuaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    func dot(_ other: AttitudeQuaternion) -> Double {
        w * other.w + x * other.x + y * other.y + z * other.z
    }

    /// The rotation angle in degrees (0…180) that turns `self` into `other`.
    func angle(to other: AttitudeQuaternion) -> Double {
        AstroMath.degrees(2 * arcLength(to: other))
    }

    /// Spherical interpolation along the shortest arc: `self` at `t = 0`, `other` at `t = 1`.
    func slerp(to other: AttitudeQuaternion, _ t: Double) -> AttitudeQuaternion {
        let target = nearerSign(of: other)
        let theta = arcLength(to: other)
        let sine = sin(theta)
        // For an arc this short the linear blend is exact to rounding error.
        let from = sine > 1e-12 ? sin((1 - t) * theta) / sine : 1 - t
        let to = sine > 1e-12 ? sin(t * theta) / sine : t
        return AttitudeQuaternion(w: from * w + to * target.w, x: from * x + to * target.x,
                                  y: from * y + to * target.y, z: from * z + to * target.z).normalized
    }

    /// `q` and `−q` are the same rotation; returns the one nearer to `self`.
    private func nearerSign(of other: AttitudeQuaternion) -> AttitudeQuaternion {
        dot(other) < 0 ? AttitudeQuaternion(w: -other.w, x: -other.x, y: -other.y, z: -other.z) : other
    }

    /// Angle in radians (0…π/2) between the unit 4-vectors `self` and the nearer of ±`other`,
    /// as `2·atan2(|p − q|, |p + q|)`, which stays accurate for tiny angles.
    private func arcLength(to other: AttitudeQuaternion) -> Double {
        let q = nearerSign(of: other)
        let difference = Self.norm(w - q.w, x - q.x, y - q.y, z - q.z)
        let sum = Self.norm(w + q.w, x + q.x, y + q.y, z + q.z)
        return 2 * atan2(difference, sum)
    }

    private static func norm(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        (a * a + b * b + c * c + d * d).squareRoot()
    }
}

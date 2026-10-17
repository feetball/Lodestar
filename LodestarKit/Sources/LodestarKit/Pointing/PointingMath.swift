import Foundation

/// Rotation helpers shared by the pointing code.
enum PointingMath {
    /// Local vertical in the ENU world frame.
    static let worldUp = Vector3(0, 0, 1)

    /// The rotation matrix of a rotation vector (axis direction × angle in radians), using the
    /// Rodrigues formula with coefficients that stay accurate as the angle tends to zero.
    static func rotationMatrix(rotationVector w: Vector3) -> Matrix3 {
        let angle = w.length
        let sine = sinc(angle)
        let half = sinc(angle / 2)
        let versine = 0.5 * half * half // (1 − cos θ) / θ²
        let k = Matrix3(rows: Vector3(0, -w.z, w.y), Vector3(w.z, 0, -w.x), Vector3(-w.y, w.x, 0))
        let k2 = k * k
        return Matrix3(rows: Vector3(1, 0, 0) + k.r0 * sine + k2.r0 * versine,
                       Vector3(0, 1, 0) + k.r1 * sine + k2.r1 * versine,
                       Vector3(0, 0, 1) + k.r2 * sine + k2.r2 * versine)
    }

    /// Rotates a world-frame vector about the vertical so that its azimuth grows by `degrees`
    /// (clockwise as seen from above).
    static func yawed(_ vector: Vector3, byAzimuth degrees: Double) -> Vector3 {
        let s = AstroMath.sinDeg(degrees), c = AstroMath.cosDeg(degrees)
        return Vector3(vector.x * c + vector.y * s, -vector.x * s + vector.y * c, vector.z)
    }

    private static func sinc(_ x: Double) -> Double {
        abs(x) < 1e-8 ? 1 - x * x / 6 : sin(x) / x
    }
}

import Foundation

/// Numeric helpers shared by the astronomy code.
///
/// All angles are in degrees unless a parameter or result name ends in `Radians`.
public enum AstroMath {
    public static let radiansPerDegree = Double.pi / 180
    public static let degreesPerRadian = 180 / Double.pi
    public static let arcsecondsPerDegree = 3600.0
    public static let arcsecondsPerRadian = 180 * 3600 / Double.pi

    /// Converts degrees to radians.
    public static func radians(_ degrees: Double) -> Double { degrees * radiansPerDegree }

    /// Converts radians to degrees.
    public static func degrees(_ radians: Double) -> Double { radians * degreesPerRadian }

    /// Reduces an angle to the range [0, 360). Non-finite input is returned unchanged.
    public static func normalizeDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return degrees }
        var reduced = degrees.truncatingRemainder(dividingBy: 360)
        if reduced < 0 { reduced += 360 }
        // `-tiny + 360` can round to exactly 360.
        return reduced >= 360 ? 0 : reduced
    }

    /// Reduces an angle to the range (-180, 180]. Non-finite input is returned unchanged.
    public static func normalizeSignedDegrees(_ degrees: Double) -> Double {
        let reduced = normalizeDegrees(degrees)
        return reduced > 180 ? reduced - 360 : reduced
    }

    /// Restricts `value` to the closed range `lower...upper`.
    public static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }

    public static func sinDeg(_ degrees: Double) -> Double { sin(degrees * radiansPerDegree) }
    public static func cosDeg(_ degrees: Double) -> Double { cos(degrees * radiansPerDegree) }
    public static func tanDeg(_ degrees: Double) -> Double { tan(degrees * radiansPerDegree) }

    /// Arcsine in degrees; the argument is clamped to [-1, 1] to absorb rounding error.
    public static func asinDeg(_ x: Double) -> Double { asin(clamp(x, -1, 1)) * degreesPerRadian }

    /// Arccosine in degrees; the argument is clamped to [-1, 1] to absorb rounding error.
    public static func acosDeg(_ x: Double) -> Double { acos(clamp(x, -1, 1)) * degreesPerRadian }

    /// Two-argument arctangent in degrees, in (-180, 180].
    public static func atan2Deg(_ y: Double, _ x: Double) -> Double { atan2(y, x) * degreesPerRadian }

    /// Evaluates `c[0] + c[1]·x + c[2]·x² + …` with Horner's scheme.
    public static func polynomial(_ x: Double, _ coefficients: [Double]) -> Double {
        var result = 0.0
        for coefficient in coefficients.reversed() {
            result = result * x + coefficient
        }
        return result
    }
}

/// A three-component vector of `Double`s (positions, directions, velocities).
public struct Vector3: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.init(x: x, y: y, z: z)
    }

    public static let zero = Vector3(0, 0, 0)

    public var lengthSquared: Double { x * x + y * y + z * z }
    public var length: Double { lengthSquared.squareRoot() }

    /// The vector scaled to unit length, or `.zero` when the vector has no length.
    public var normalized: Vector3 {
        let l = length
        return l > 0 ? self / l : .zero
    }

    /// `true` when all components are finite.
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }

    public func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(y * other.z - z * other.y,
                z * other.x - x * other.z,
                x * other.y - y * other.x)
    }

    /// Angle between two vectors in radians, numerically stable for small and near-π angles.
    public func angleRadians(to other: Vector3) -> Double {
        atan2(cross(other).length, dot(other))
    }

    /// Angle between two vectors in degrees.
    public func angle(to other: Vector3) -> Double {
        AstroMath.degrees(angleRadians(to: other))
    }

    public var description: String { "(\(x), \(y), \(z))" }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static prefix func - (v: Vector3) -> Vector3 { Vector3(-v.x, -v.y, -v.z) }
    public static func * (v: Vector3, s: Double) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
    public static func * (s: Double, v: Vector3) -> Vector3 { v * s }
    public static func / (v: Vector3, s: Double) -> Vector3 { Vector3(v.x / s, v.y / s, v.z / s) }
    public static func += (a: inout Vector3, b: Vector3) { a = a + b }
    public static func -= (a: inout Vector3, b: Vector3) { a = a - b }
}

/// A 3×3 matrix stored as three row vectors.
///
/// `m * v` is the ordinary matrix–vector product. The `rotationX/Y/Z` constructors are *active*
/// right-handed rotations (they rotate vectors counter-clockwise when viewed from the tip of the
/// axis). The `frameRotationX/Y/Z` constructors are the *passive* rotations used by SOFA and Meeus
/// (`R1`, `R2`, `R3`): they re-express a fixed vector in a frame rotated by the given angle.
public struct Matrix3: Hashable, Codable, Sendable, CustomStringConvertible {
    public var r0: Vector3
    public var r1: Vector3
    public var r2: Vector3

    public init(rows r0: Vector3, _ r1: Vector3, _ r2: Vector3) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }

    public init(columns c0: Vector3, _ c1: Vector3, _ c2: Vector3) {
        self.init(rows: Vector3(c0.x, c1.x, c2.x),
                  Vector3(c0.y, c1.y, c2.y),
                  Vector3(c0.z, c1.z, c2.z))
    }

    public static let identity = Matrix3(rows: Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

    /// Element access with zero-based indices.
    public subscript(row: Int, column: Int) -> Double {
        precondition((0..<3).contains(row) && (0..<3).contains(column), "Matrix3 index out of range")
        let r: Vector3
        switch row {
        case 0: r = r0
        case 1: r = r1
        default: r = r2
        }
        switch column {
        case 0: return r.x
        case 1: return r.y
        default: return r.z
        }
    }

    public var c0: Vector3 { Vector3(r0.x, r1.x, r2.x) }
    public var c1: Vector3 { Vector3(r0.y, r1.y, r2.y) }
    public var c2: Vector3 { Vector3(r0.z, r1.z, r2.z) }

    public var transposed: Matrix3 { Matrix3(rows: c0, c1, c2) }

    public var determinant: Double { r0.dot(r1.cross(r2)) }

    /// `true` when all elements are finite.
    public var isFinite: Bool { r0.isFinite && r1.isFinite && r2.isFinite }

    public static func * (m: Matrix3, v: Vector3) -> Vector3 {
        Vector3(m.r0.dot(v), m.r1.dot(v), m.r2.dot(v))
    }

    public static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        let bc0 = b.c0, bc1 = b.c1, bc2 = b.c2
        return Matrix3(rows: Vector3(a.r0.dot(bc0), a.r0.dot(bc1), a.r0.dot(bc2)),
                       Vector3(a.r1.dot(bc0), a.r1.dot(bc1), a.r1.dot(bc2)),
                       Vector3(a.r2.dot(bc0), a.r2.dot(bc1), a.r2.dot(bc2)))
    }

    /// Active rotation about the x axis.
    public static func rotationX(_ angleRadians: Double) -> Matrix3 {
        let c = cos(angleRadians), s = sin(angleRadians)
        return Matrix3(rows: Vector3(1, 0, 0), Vector3(0, c, -s), Vector3(0, s, c))
    }

    /// Active rotation about the y axis.
    public static func rotationY(_ angleRadians: Double) -> Matrix3 {
        let c = cos(angleRadians), s = sin(angleRadians)
        return Matrix3(rows: Vector3(c, 0, s), Vector3(0, 1, 0), Vector3(-s, 0, c))
    }

    /// Active rotation about the z axis.
    public static func rotationZ(_ angleRadians: Double) -> Matrix3 {
        let c = cos(angleRadians), s = sin(angleRadians)
        return Matrix3(rows: Vector3(c, -s, 0), Vector3(s, c, 0), Vector3(0, 0, 1))
    }

    /// Passive (frame) rotation about the x axis — SOFA/Meeus `R1(θ)`.
    public static func frameRotationX(_ angleRadians: Double) -> Matrix3 { rotationX(angleRadians).transposed }

    /// Passive (frame) rotation about the y axis — SOFA/Meeus `R2(θ)`.
    public static func frameRotationY(_ angleRadians: Double) -> Matrix3 { rotationY(angleRadians).transposed }

    /// Passive (frame) rotation about the z axis — SOFA/Meeus `R3(θ)`.
    public static func frameRotationZ(_ angleRadians: Double) -> Matrix3 { rotationZ(angleRadians).transposed }

    /// Active rotation by `angleRadians` about an arbitrary axis (Rodrigues' formula).
    /// Returns `.identity` when the axis has no length.
    public static func rotation(axis: Vector3, angleRadians: Double) -> Matrix3 {
        let k = axis.normalized
        guard k != .zero else { return .identity }
        let c = cos(angleRadians), s = sin(angleRadians), t = 1 - c
        return Matrix3(
            rows: Vector3(t * k.x * k.x + c, t * k.x * k.y - s * k.z, t * k.x * k.z + s * k.y),
            Vector3(t * k.x * k.y + s * k.z, t * k.y * k.y + c, t * k.y * k.z - s * k.x),
            Vector3(t * k.x * k.z - s * k.y, t * k.y * k.z + s * k.x, t * k.z * k.z + c))
    }

    /// The nearest proper rotation obtained by Gram–Schmidt orthonormalisation of the rows
    /// (row 0 keeps its direction, row 1 is made perpendicular to it, row 2 = row 0 × row 1).
    /// Useful to clean up sensor-supplied rotation matrices.
    public func orthonormalized() -> Matrix3 {
        let x = r0.normalized
        let y = (r1 - x * x.dot(r1)).normalized
        return Matrix3(rows: x, y, x.cross(y))
    }

    public var description: String { "[\(r0), \(r1), \(r2)]" }
}

import Foundation

/// Two-body heliocentric motion of a small body from `OrbitalElements`, for every eccentricity.
///
/// Kepler's equation is solved in universal variables (Stumpff functions; Bate, Mueller & White, *Fundamentals of
/// Astrodynamics*, §4.4; Vallado 2013, §2.3), starting at perihelion: with `χ` the universal anomaly, `α = (1 − e)/q`
/// and `z = αχ²`, the time since perihelion `Δt` satisfies `k·Δt = e·χ³·S(z) + q·χ`, the distance is
/// `r = q + e·χ²·C(z)` and the perifocal position is `x = q − χ²·C(z)`, `y = √(q(1 + e))·χ·(1 − z·S(z))`. One formula
/// covers ellipses, parabolas and hyperbolas without a special case near `e = 1`. The left-hand side increases
/// monotonically with `χ` (its derivative is `r ≥ q`) and `|χ| ≤ k|Δt|/q`, so a safeguarded Newton iteration
/// (bisection whenever a step leaves the bracket) always converges, typically in four to six steps.
///
/// Elliptic orbits are reduced to |Δt| ≤ half a period first, so any date works; for parabolic and hyperbolic orbits
/// the date must be within `maximumUnboundSpanDays` of perihelion (the body is then far beyond Neptune anyway).
/// Planetary perturbations are not modelled: see `SmallBodyEphemeris` for the resulting error.
public enum OrbitPropagator {
    /// The Gaussian gravitational constant k in AU^1.5 per day (IAU 1976; the Sun's GM is k² in AU³/day²).
    public static let gaussianGravitationalConstant = 0.01720209895

    /// The largest |t − perihelion| in days for which a parabolic or hyperbolic orbit is evaluated (about 137 years).
    public static let maximumUnboundSpanDays = 50_000.0

    private static let maximumIterations = 100
    private static let relativeTolerance = 1e-14

    /// Rotation from the J2000 mean ecliptic to the J2000 mean equator (the one the planetary theory uses).
    private static let eclipticToEquatorialJ2000 = Matrix3.rotationX(AstroMath.radians(Obliquity.j2000))

    /// A position in the orbital plane: `x` towards perihelion, `y` 90° ahead in the direction of motion, and the
    /// distance `r` from the Sun, all in AU.
    struct Perifocal {
        let x: Double
        let y: Double
        let r: Double
    }

    /// The heliocentric position in AU at `julianDayTT` in the mean ecliptic and equinox of J2000.0, or `nil`
    /// if the date is not finite or too far from perihelion for an unbound orbit.
    public static func heliocentricEcliptic(of elements: OrbitalElements, at julianDayTT: Double) -> Vector3? {
        guard let perifocal = perifocal(q: elements.perihelionDistanceAU, e: elements.eccentricity,
                                        days: julianDayTT - elements.perihelionJulianDayTT) else { return nil }
        let cosI = AstroMath.cosDeg(elements.inclination)
        let sinI = AstroMath.sinDeg(elements.inclination)
        let cosNode = AstroMath.cosDeg(elements.longitudeOfAscendingNode)
        let sinNode = AstroMath.sinDeg(elements.longitudeOfAscendingNode)
        let cosPeri = AstroMath.cosDeg(elements.argumentOfPerihelion)
        let sinPeri = AstroMath.sinDeg(elements.argumentOfPerihelion)
        let px = cosNode * cosPeri - sinNode * sinPeri * cosI
        let py = sinNode * cosPeri + cosNode * sinPeri * cosI
        let pz = sinPeri * sinI
        let qx = -cosNode * sinPeri - sinNode * cosPeri * cosI
        let qy = -sinNode * sinPeri + cosNode * cosPeri * cosI
        let qz = cosPeri * sinI
        let position = Vector3(perifocal.x * px + perifocal.y * qx,
                               perifocal.x * py + perifocal.y * qy,
                               perifocal.x * pz + perifocal.y * qz)
        return position.isFinite ? position : nil
    }

    /// The heliocentric position in AU at `julianDayTT` in the mean equatorial frame of J2000.0 (the frame of
    /// `BodyState.geocentricJ2000`), or `nil` as for `heliocentricEcliptic(of:at:)`.
    public static func heliocentricJ2000(of elements: OrbitalElements, at julianDayTT: Double) -> Vector3? {
        heliocentricEcliptic(of: elements, at: julianDayTT).map { eclipticToEquatorialJ2000 * $0 }
    }

    /// The distance from the Sun in AU at `julianDayTT`; `nil` as for `heliocentricEcliptic(of:at:)`. Cheaper than the position.
    public static func heliocentricDistance(of elements: OrbitalElements, at julianDayTT: Double) -> Double? {
        perifocal(q: elements.perihelionDistanceAU, e: elements.eccentricity,
                  days: julianDayTT - elements.perihelionJulianDayTT)?.r
    }

    /// The Stumpff function `C(z) = (1 − cos √z) / z`, continued analytically to `z < 0` with the hyperbolic cosine.
    static func stumpffC(_ z: Double) -> Double {
        if abs(z) < 1.0 {
            var term = 0.5
            var sum = 0.5
            for k in 1...13 {
                term *= -z / ((2.0 * Double(k) + 1) * (2.0 * Double(k) + 2))
                sum += term
            }
            return sum
        }
        if z > 0 { return (1 - cos(z.squareRoot())) / z }
        return (cosh((-z).squareRoot()) - 1) / -z
    }

    /// The Stumpff function `S(z) = (√z − sin √z) / z^1.5`, continued analytically to `z < 0` with the hyperbolic sine.
    static func stumpffS(_ z: Double) -> Double {
        if abs(z) < 1.0 {
            var term = 1.0 / 6.0
            var sum = 1.0 / 6.0
            for k in 1...13 {
                term *= -z / ((2.0 * Double(k) + 2) * (2.0 * Double(k) + 3))
                sum += term
            }
            return sum
        }
        if z > 0 {
            let root = z.squareRoot()
            return (root - sin(root)) / (root * root * root)
        }
        let root = (-z).squareRoot()
        return (sinh(root) - root) / (root * root * root)
    }

    /// The orbital-plane position `days` after perihelion for a conic with perihelion distance `q` and eccentricity `e`,
    /// or `nil` if an input is not finite, `q <= 0`, `e < 0`, or `days` is beyond `maximumUnboundSpanDays` for an
    /// unbound orbit.
    static func perifocal(q: Double, e: Double, days: Double) -> Perifocal? {
        guard q > 0, e >= 0, days.isFinite else { return nil }
        let k = gaussianGravitationalConstant
        var elapsed = days
        if e < 1 {
            let a = q / (1 - e)
            let period = 2 * Double.pi * a * a.squareRoot() / k
            guard period.isFinite else { return nil }
            elapsed -= (elapsed / period + 0.5).rounded(.down) * period
        } else if abs(elapsed) > maximumUnboundSpanDays {
            return nil
        }
        if elapsed == 0 { return Perifocal(x: q, y: 0, r: q) }

        let alpha = (1 - e) / q
        let tau = k * abs(elapsed)
        var low = 0.0
        var high = tau / q
        var chi = initialGuess(q: q, e: e, tau: tau)
        if !(chi > low && chi < high) { chi = 0.5 * high }
        for _ in 0..<maximumIterations {
            let z = alpha * chi * chi
            let residual = e * chi * chi * chi * stumpffS(z) + q * chi - tau
            if residual == 0 { break }
            if residual > 0 { high = chi } else { low = chi }
            let derivative = e * chi * chi * stumpffC(z) + q
            var next = chi - residual / derivative
            if !(next > low && next < high) { next = 0.5 * (low + high) }
            let step = abs(next - chi)
            chi = next
            if step <= relativeTolerance * chi { break }
        }
        let z = alpha * chi * chi
        let c = stumpffC(z)
        let x = q - chi * chi * c
        let y = (q * (1 + e)).squareRoot() * chi * (1 - z * stumpffS(z))
        let r = e * chi * chi * c + q
        let signedY = elapsed < 0 ? -y : y
        guard x.isFinite, signedY.isFinite, r.isFinite else { return nil }
        return Perifocal(x: x, y: signedY, r: r)
    }

    /// The root of Barker's cubic `e·χ³/6 + q·χ = τ` (the parabolic solution) for `e >= 0.1`, else the upper bound
    /// `τ/q`; the start of the Newton iteration.
    private static func initialGuess(q: Double, e: Double, tau: Double) -> Double {
        if e < 0.1 { return tau / q }
        let p = 6 * q / e
        let c = 6 * tau / e
        let u = cbrt(c / 2 + (c * c / 4 + p * p * p / 27).squareRoot())
        return u - p / (3 * u)
    }
}

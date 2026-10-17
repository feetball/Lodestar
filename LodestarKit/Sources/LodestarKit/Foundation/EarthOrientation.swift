import Foundation

/// Obliquity of the ecliptic.
public enum Obliquity {
    /// Mean obliquity at J2000.0 in degrees (23° 26′ 21.448″).
    public static let j2000 = 23.0 + 26.0 / 60 + 21.448 / 3600

    /// Mean obliquity of date in degrees (IAU 1980, Meeus 22.2).
    public static func mean(_ jd: JulianDate) -> Double {
        let t = jd.centuriesTT
        let arcseconds = AstroMath.polynomial(t, [21.448, -46.8150, -0.00059, 0.001813])
        return 23.0 + 26.0 / 60 + arcseconds / 3600
    }
}

/// Nutation in longitude (Δψ) and obliquity (Δε), IAU 1980 theory (Meeus, Table 22.A).
public struct Nutation: Hashable, Codable, Sendable {
    /// Nutation in longitude Δψ, degrees.
    public let longitude: Double
    /// Nutation in obliquity Δε, degrees.
    public let obliquity: Double

    public init(longitude: Double, obliquity: Double) {
        self.longitude = longitude
        self.obliquity = obliquity
    }

    /// Evaluates the 63-term IAU 1980 series (accuracy ≈ 0.001″).
    public init(julianDate jd: JulianDate) {
        let t = jd.centuriesTT
        let d = AstroMath.radians(AstroMath.polynomial(t, [297.85036, 445_267.111_480, -0.001_914_2, 1.0 / 189_474]))
        let m = AstroMath.radians(AstroMath.polynomial(t, [357.52772, 35_999.050_340, -0.000_160_3, -1.0 / 300_000]))
        let mPrime = AstroMath.radians(AstroMath.polynomial(t, [134.96298, 477_198.867_398, 0.008_697_2, 1.0 / 56_250]))
        let f = AstroMath.radians(AstroMath.polynomial(t, [93.27191, 483_202.017_538, -0.003_682_5, 1.0 / 327_270]))
        let omega = AstroMath.radians(AstroMath.polynomial(t, [125.04452, -1_934.136_261, 0.002_070_8, 1.0 / 450_000]))

        var deltaPsi = 0.0
        var deltaEpsilon = 0.0
        for term in Self.terms {
            let argument = Double(term.d) * d + Double(term.m) * m + Double(term.mPrime) * mPrime
                + Double(term.f) * f + Double(term.omega) * omega
            deltaPsi += (term.psi + term.psiT * t) * sin(argument)
            deltaEpsilon += (term.epsilon + term.epsilonT * t) * cos(argument)
        }
        // Coefficients are in units of 0.0001″.
        self.init(longitude: deltaPsi / 10_000 / 3600, obliquity: deltaEpsilon / 10_000 / 3600)
    }

    /// Rotation from the mean equator & equinox of date to the true equator & equinox of date,
    /// `N = R1(−ε) · R3(−Δψ) · R1(ε₀)`.
    public func matrix(meanObliquity: Double) -> Matrix3 {
        let meanEpsilon = AstroMath.radians(meanObliquity)
        let trueEpsilon = AstroMath.radians(meanObliquity + obliquity)
        let psi = AstroMath.radians(longitude)
        return Matrix3.frameRotationX(-trueEpsilon) * Matrix3.frameRotationZ(-psi) * Matrix3.frameRotationX(meanEpsilon)
    }

    private struct Term {
        let d: Int8, m: Int8, mPrime: Int8, f: Int8, omega: Int8
        let psi: Double, psiT: Double, epsilon: Double, epsilonT: Double

        init(_ d: Int8, _ m: Int8, _ mPrime: Int8, _ f: Int8, _ omega: Int8,
             _ psi: Double, _ psiT: Double, _ epsilon: Double, _ epsilonT: Double) {
            self.d = d
            self.m = m
            self.mPrime = mPrime
            self.f = f
            self.omega = omega
            self.psi = psi
            self.psiT = psiT
            self.epsilon = epsilon
            self.epsilonT = epsilonT
        }
    }

    /// Meeus, Astronomical Algorithms (2nd ed.), Table 22.A: multiples of D, M, M′, F, Ω and the
    /// sine (Δψ) / cosine (Δε) coefficients in 0.0001″, with their T-rates.
    private static let terms: [Term] = [
        Term(0, 0, 0, 0, 1, -171_996, -174.2, 92_025, 8.9),
        Term(-2, 0, 0, 2, 2, -13_187, -1.6, 5_736, -3.1),
        Term(0, 0, 0, 2, 2, -2_274, -0.2, 977, -0.5),
        Term(0, 0, 0, 0, 2, 2_062, 0.2, -895, 0.5),
        Term(0, 1, 0, 0, 0, 1_426, -3.4, 54, -0.1),
        Term(0, 0, 1, 0, 0, 712, 0.1, -7, 0),
        Term(-2, 1, 0, 2, 2, -517, 1.2, 224, -0.6),
        Term(0, 0, 0, 2, 1, -386, -0.4, 200, 0),
        Term(0, 0, 1, 2, 2, -301, 0, 129, -0.1),
        Term(-2, -1, 0, 2, 2, 217, -0.5, -95, 0.3),
        Term(-2, 0, 1, 0, 0, -158, 0, 0, 0),
        Term(-2, 0, 0, 2, 1, 129, 0.1, -70, 0),
        Term(0, 0, -1, 2, 2, 123, 0, -53, 0),
        Term(2, 0, 0, 0, 0, 63, 0, 0, 0),
        Term(0, 0, 1, 0, 1, 63, 0.1, -33, 0),
        Term(2, 0, -1, 2, 2, -59, 0, 26, 0),
        Term(0, 0, -1, 0, 1, -58, -0.1, 32, 0),
        Term(0, 0, 1, 2, 1, -51, 0, 27, 0),
        Term(-2, 0, 2, 0, 0, 48, 0, 0, 0),
        Term(0, 0, -2, 2, 1, 46, 0, -24, 0),
        Term(2, 0, 0, 2, 2, -38, 0, 16, 0),
        Term(0, 0, 2, 2, 2, -31, 0, 13, 0),
        Term(0, 0, 2, 0, 0, 29, 0, 0, 0),
        Term(-2, 0, 1, 2, 2, 29, 0, -12, 0),
        Term(0, 0, 0, 2, 0, 26, 0, 0, 0),
        Term(-2, 0, 0, 2, 0, -22, 0, 0, 0),
        Term(0, 0, -1, 2, 1, 21, 0, -10, 0),
        Term(0, 2, 0, 0, 0, 17, -0.1, 0, 0),
        Term(2, 0, -1, 0, 1, 16, 0, -8, 0),
        Term(-2, 2, 0, 2, 2, -16, 0.1, 7, 0),
        Term(0, 1, 0, 0, 1, -15, 0, 9, 0),
        Term(-2, 0, 1, 0, 1, -13, 0, 7, 0),
        Term(0, -1, 0, 0, 1, -12, 0, 6, 0),
        Term(0, 0, 2, -2, 0, 11, 0, 0, 0),
        Term(2, 0, -1, 2, 1, -10, 0, 5, 0),
        Term(2, 0, 1, 2, 2, -8, 0, 3, 0),
        Term(0, 1, 0, 2, 2, 7, 0, -3, 0),
        Term(-2, 1, 1, 0, 0, -7, 0, 0, 0),
        Term(0, -1, 0, 2, 2, -7, 0, 3, 0),
        Term(2, 0, 0, 2, 1, -7, 0, 3, 0),
        Term(2, 0, 1, 0, 0, 6, 0, 0, 0),
        Term(-2, 0, 2, 2, 2, 6, 0, -3, 0),
        Term(-2, 0, 1, 2, 1, 6, 0, -3, 0),
        Term(2, 0, -2, 0, 1, -6, 0, 3, 0),
        Term(2, 0, 0, 0, 1, -6, 0, 3, 0),
        Term(0, -1, 1, 0, 0, 5, 0, 0, 0),
        Term(-2, -1, 0, 2, 1, -5, 0, 3, 0),
        Term(-2, 0, 0, 0, 1, -5, 0, 3, 0),
        Term(0, 0, 2, 2, 1, -5, 0, 3, 0),
        Term(-2, 0, 2, 0, 1, 4, 0, 0, 0),
        Term(-2, 1, 0, 2, 1, 4, 0, 0, 0),
        Term(0, 0, 1, -2, 0, 4, 0, 0, 0),
        Term(-1, 0, 1, 0, 0, -4, 0, 0, 0),
        Term(-2, 1, 0, 0, 0, -4, 0, 0, 0),
        Term(1, 0, 0, 0, 0, -4, 0, 0, 0),
        Term(0, 0, 1, 2, 0, 3, 0, 0, 0),
        Term(0, 0, -2, 2, 2, -3, 0, 0, 0),
        Term(-1, -1, 1, 0, 0, -3, 0, 0, 0),
        Term(0, 1, 1, 0, 0, -3, 0, 0, 0),
        Term(0, -1, 1, 2, 2, -3, 0, 0, 0),
        Term(2, -1, -1, 2, 2, -3, 0, 0, 0),
        Term(0, 0, 3, 2, 2, -3, 0, 0, 0),
        Term(2, -1, 0, 2, 2, -3, 0, 0, 0),
    ]
}

/// General precession (IAU 1976, Lieske et al. 1977).
public enum Precession {
    /// Rotation taking J2000 mean equatorial vectors to the mean equator & equinox of `jd`,
    /// `P = R3(−z) · R2(θ) · R3(−ζ)` (Meeus 21.2 with the starting epoch at J2000).
    public static func matrixFromJ2000(to jd: JulianDate) -> Matrix3 {
        let t = jd.centuriesTT
        let arcsecondsToRadians = 1 / AstroMath.arcsecondsPerRadian
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsecondsToRadians
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsecondsToRadians
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsecondsToRadians
        return Matrix3.frameRotationZ(-z) * Matrix3.frameRotationY(theta) * Matrix3.frameRotationZ(-zeta)
    }
}

/// Low-precision solar quantities (Meeus ch. 25, ≈ 0.01°), used for annual aberration.
public enum SolarCoordinates {
    /// Mean anomaly of the Sun in degrees, [0, 360).
    public static func meanAnomaly(_ jd: JulianDate) -> Double {
        let t = jd.centuriesTT
        return AstroMath.normalizeDegrees(AstroMath.polynomial(t, [357.52911, 35_999.050_29, -0.000_153_7]))
    }

    /// Geometric (true) ecliptic longitude of the Sun referred to the mean equinox of date, degrees.
    public static func geometricLongitude(_ jd: JulianDate) -> Double {
        let t = jd.centuriesTT
        let meanLongitude = AstroMath.polynomial(t, [280.46646, 36_000.769_83, 0.000_303_2])
        let m = AstroMath.radians(meanAnomaly(jd))
        let center = (1.914_602 - 0.004_817 * t - 0.000_014 * t * t) * sin(m)
            + (0.019_993 - 0.000_101 * t) * sin(2 * m)
            + 0.000_289 * sin(3 * m)
        return AstroMath.normalizeDegrees(meanLongitude + center)
    }
}

/// Annual aberration of light caused by the Earth's orbital velocity.
public enum Aberration {
    /// Constant of aberration κ in arcseconds.
    public static let constantArcseconds = 20.49552

    /// The Earth's orbital velocity as a fraction of the speed of light (β = v/c), expressed in the
    /// J2000 equatorial frame. Includes the orbital-eccentricity terms (Meeus 23.3).
    public static func earthVelocity(_ jd: JulianDate) -> Vector3 {
        let t = jd.centuriesTT
        let sunLongitude = AstroMath.radians(SolarCoordinates.geometricLongitude(jd))
        let eccentricity = AstroMath.polynomial(t, [0.016_708_634, -0.000_042_037, -0.000_000_126_7])
        let perihelion = AstroMath.radians(AstroMath.polynomial(t, [102.937_35, 1.719_46, 0.000_46]))
        let kappa = constantArcseconds / AstroMath.arcsecondsPerRadian

        // Velocity in the mean ecliptic & equinox of date.
        let ecliptic = Vector3(kappa * (sin(sunLongitude) - eccentricity * sin(perihelion)),
                               -kappa * (cos(sunLongitude) - eccentricity * cos(perihelion)),
                               0)
        let meanEquatorialOfDate = Matrix3.rotationX(AstroMath.radians(Obliquity.mean(jd))) * ecliptic
        return Precession.matrixFromJ2000(to: jd).transposed * meanEquatorialOfDate
    }

    /// Applies first-order aberration to a unit direction: the apparent direction is displaced
    /// towards the observer's velocity. Returns a unit vector.
    public static func apply(to direction: Vector3, earthVelocity: Vector3) -> Vector3 {
        (direction + earthVelocity).normalized
    }

    /// Removes first-order aberration from an apparent unit direction (inverse of `apply`).
    public static func remove(from apparentDirection: Vector3, earthVelocity: Vector3) -> Vector3 {
        (apparentDirection - earthVelocity).normalized
    }
}

import Foundation

extension Ephemeris {
    /// Apparent visual magnitudes of the Sun, Moon and planets.
    ///
    /// The planets follow A. Mallama & J. L. Hilton, "Computing Apparent Planetary Magnitudes for
    /// The Astronomical Almanac" (*Astronomy and Computing* 25, 2018; arXiv:1808.01973), section 3.
    /// There `r` is the Sun–planet and `d` the Earth–planet distance in AU and `α` the Sun–planet–Earth
    /// phase angle in degrees. Mars omits the sub-Earth-longitude and Ls corrections (about ±0.05 mag).
    /// Jupiter, Saturn, Uranus and Neptune use the equations for the phase angles seen from the
    /// Earth (up to 12°, 6.5°, 3.1° and 1.9°).
    enum Photometry {
        /// Visual magnitude of the Sun, −26.74 at 1 AU.
        static func sun(distanceAU: Double) -> Double {
            -26.74 + 5 * log10(distanceAU)
        }

        /// Visual magnitude of the Moon from Allen's phase law, −12.73 + 0.026 α + 4×10⁻⁹ α⁴ at the
        /// mean Earth–Moon distance, scaled for the actual Sun–Moon and Earth–Moon distances.
        static func moon(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double) -> Double {
            let meanEarthDistanceAU = 384_400 / SkyFrame.kilometersPerAU
            return -12.73 + 0.026 * α + 4e-9 * pow(α, 4) + 5 * log10(r * d / meanEarthDistanceAU)
        }

        /// Visual magnitude of a planet, or `nil` for the Sun and the Moon.
        ///
        /// - Parameters:
        ///   - heliocentric: The planet's position relative to the Sun (J2000 equatorial, AU).
        ///   - geocentric: The planet's position relative to the Earth (J2000 equatorial, AU).
        ///   - phaseAngle: The Sun–planet–Earth angle in degrees.
        static func planet(_ body: SolarSystemBody, heliocentric: Vector3, geocentric: Vector3,
                           phaseAngle α: Double, julianDate: JulianDate) -> Double? {
            let r = heliocentric.length
            let d = geocentric.length
            switch body {
            case .sun, .moon:
                return nil
            case .mercury:
                return mercury(sunDistance: r, earthDistance: d, phaseAngle: α)
            case .venus:
                return venus(sunDistance: r, earthDistance: d, phaseAngle: α)
            case .mars:
                return mars(sunDistance: r, earthDistance: d, phaseAngle: α)
            case .jupiter:
                return jupiter(sunDistance: r, earthDistance: d, phaseAngle: α)
            case .saturn:
                let pole = poleDirection(rightAscension: 40.589 - 0.036 * julianDate.centuriesTT,
                                         declination: 83.537 - 0.004 * julianDate.centuriesTT)
                return saturn(sunDistance: r, earthDistance: d, phaseAngle: α,
                              sunLatitude: subLatitude(of: -heliocentric, pole: pole),
                              earthLatitude: subLatitude(of: -geocentric, pole: pole))
            case .uranus:
                let pole = poleDirection(rightAscension: 257.311, declination: -15.175)
                return uranus(sunDistance: r, earthDistance: d,
                              sunLatitude: planetographic(subLatitude(of: -heliocentric, pole: pole)),
                              earthLatitude: planetographic(subLatitude(of: -geocentric, pole: pole)))
            case .neptune:
                return neptune(sunDistance: r, earthDistance: d, year: julianDate.julianYearTT)
            }
        }

        // MARK: Mallama & Hilton equations

        /// Equation 2.
        static func mercury(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double) -> Double {
            5 * log10(r * d) - 0.613
                + AstroMath.polynomial(α, [0, 6.3280e-2, -1.6336e-3, 3.3644e-5, -3.4265e-7, 1.6893e-9, -3.0334e-12])
        }

        /// Equations 3 (α ≤ 163.7°) and 4.
        static func venus(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double) -> Double {
            5 * log10(r * d) + (α <= 163.7
                ? AstroMath.polynomial(α, [-4.384, -1.044e-3, 3.687e-4, -2.814e-6, 8.938e-9])
                : AstroMath.polynomial(α, [236.05828, -2.81914, 8.39034e-3]))
        }

        /// Equations 6 (α ≤ 50°) and 7, without the sub-Earth-longitude and Ls terms.
        static func mars(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double) -> Double {
            5 * log10(r * d) + (α <= 50
                ? AstroMath.polynomial(α, [-1.601, 0.02267, -0.0001302])
                : AstroMath.polynomial(α, [-0.367, -0.02573, 0.0003445]))
        }

        /// Equation 8 (α ≤ 12°, which covers every geocentric view).
        static func jupiter(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double) -> Double {
            5 * log10(r * d) + AstroMath.polynomial(α, [-9.395, -3.7e-4, 6.16e-4])
        }

        /// Equation 10 for the globe and rings. The latitudes are the planetocentric sub-solar and
        /// sub-Earth latitudes with respect to the ring plane, in degrees; the effective inclination
        /// is their geometric mean, or zero when the rings are lit from the other side than seen.
        static func saturn(sunDistance r: Double, earthDistance d: Double, phaseAngle α: Double,
                           sunLatitude: Double, earthLatitude: Double) -> Double {
            let product = sunLatitude * earthLatitude
            let sineOfInclination = product > 0 ? AstroMath.sinDeg(product.squareRoot()) : 0
            return 5 * log10(r * d) - 8.914 - 1.825 * sineOfInclination + 0.026 * α
                - 0.378 * sineOfInclination * exp(-2.25 * α)
        }

        /// Equation 14. The latitudes are the planetographic sub-solar and sub-Earth latitudes, in
        /// degrees; the phase angle is ignored (Uranus never exceeds 3.1°).
        static func uranus(sunDistance r: Double, earthDistance d: Double,
                           sunLatitude: Double, earthLatitude: Double) -> Double {
            5 * log10(r * d) - 7.110 - 8.4e-4 * (abs(sunLatitude) + abs(earthLatitude)) / 2
        }

        /// Equation 16 (the phase angle is ignored; Neptune never exceeds 1.9°).
        static func neptune(sunDistance r: Double, earthDistance d: Double, year: Double) -> Double {
            let brightness = year < 1980 ? -6.89 : (year <= 2000 ? -6.89 - 0.0054 * (year - 1980) : -7.00)
            return 5 * log10(r * d) + brightness
        }

        // MARK: Rotation poles

        /// Planetocentric latitude in degrees of the sub-point seen along `direction` (from the
        /// planet's centre), relative to the planet's equator.
        private static func subLatitude(of direction: Vector3, pole: Vector3) -> Double {
            AstroMath.asinDeg(direction.normalized.dot(pole))
        }

        /// Converts a planetocentric latitude of Uranus to a planetographic one (equation 13,
        /// flattening 0.0022927).
        private static func planetographic(_ planetocentric: Double) -> Double {
            let flattening = 0.0022927
            return AstroMath.degrees(atan(AstroMath.tanDeg(planetocentric) / ((1 - flattening) * (1 - flattening))))
        }

        /// Unit vector towards a rotation pole given in J2000 equatorial coordinates (IAU 2009 values).
        private static func poleDirection(rightAscension: Double, declination: Double) -> Vector3 {
            EquatorialCoordinate(rightAscension: rightAscension, declination: declination).unitVector
        }
    }
}

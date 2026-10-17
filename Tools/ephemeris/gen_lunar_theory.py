"""Generate Sources/LodestarKit/Ephemeris/LunarTheory.swift from the verified Meeus Tables 47.A and 47.B.

Usage: python -I gen_lunar_theory.py <output.swift>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meeus_lunar_tables import TABLE_A, TABLE_B  # noqa: E402


def rows_a():
    lines = []
    for d, m, mp, f, sl, sr in TABLE_A:
        lines.append(f"            PeriodicTerm({d}, {m}, {mp}, {f}, longitude: {sl}, distance: {sr}),")
    return "\n".join(lines)


def rows_b():
    lines = []
    for d, m, mp, f, sb in TABLE_B:
        lines.append(f"            LatitudeTerm({d}, {m}, {mp}, {f}, latitude: {sb}),")
    return "\n".join(lines)


source = f"""import Foundation

extension Ephemeris {{
    /// The Moon's geocentric position from the truncated ELP-2000/82 lunar theory of
    /// Jean Meeus, *Astronomical Algorithms* (2nd ed., 1998), chapter 47: 60 periodic terms for
    /// longitude and distance (Table 47.A), 60 for latitude (Table 47.B) and the additive
    /// terms for Venus, Jupiter and the flattening of the Earth. Measured against JPL's DE440s over
    /// 1950–2049 the direction is good to 8″ and the distance to 45 km (1.2×10⁻⁴). The coefficients
    /// were checked row by row against two independent MIT-licensed implementations of the same
    /// tables, `moonposition` in github.com/soniakeys/meeus and `moonposition.js` in
    /// github.com/commenthol/astronomia.
    enum LunarTheory {{
        /// Geometric geocentric position, referred to the mean equinox and ecliptic of date.
        struct Position {{
            /// Ecliptic longitude in degrees, [0, 360).
            let longitude: Double
            /// Ecliptic latitude in degrees.
            let latitude: Double
            /// Distance between the centres of the Earth and the Moon in kilometres.
            let distanceKilometers: Double
        }}

        /// The Moon's geocentric position in AU in the mean equatorial frame of J2000.0 as seen one
        /// light-time ago (the Moon moves about 0.7″ while its light travels to the Earth).
        static func geocentricJ2000(_ jd: JulianDate) -> Vector3 {{
            let t = jd.centuriesTT
            let distanceAU = geocentricEcliptic(centuries: t).distanceKilometers / SkyFrame.kilometersPerAU
            let lightTimeCenturies = distanceAU * Ephemeris.lightTimePerAU / JulianDate.daysPerJulianCentury
            let position = geocentricEcliptic(centuries: t - lightTimeCenturies)
            let ecliptic = EclipticCoordinate(longitude: position.longitude, latitude: position.latitude).unitVector
                * (position.distanceKilometers / SkyFrame.kilometersPerAU)
            let meanEquatorialOfDate = Matrix3.rotationX(AstroMath.radians(Obliquity.mean(jd))) * ecliptic
            return Precession.matrixFromJ2000(to: jd).transposed * meanEquatorialOfDate
        }}

        /// The Moon's geometric position at `t` Julian centuries of TT since J2000.0, without light-time.
        static func geocentricEcliptic(centuries t: Double) -> Position {{
            let meanLongitude = AstroMath.polynomial(t, [218.3164477, 481_267.881_234_21, -0.0015786,
                                                         1.0 / 538_841, -1.0 / 65_194_000])
            let d = AstroMath.radians(AstroMath.polynomial(t, [297.8501921, 445_267.1114034, -0.0018819,
                                                               1.0 / 545_868, -1.0 / 113_065_000]))
            let m = AstroMath.radians(AstroMath.polynomial(t, [357.5291092, 35_999.0502909, -0.0001536,
                                                               1.0 / 24_490_000]))
            let mPrime = AstroMath.radians(AstroMath.polynomial(t, [134.9633964, 477_198.8675055, 0.0087414,
                                                                    1.0 / 69_699, -1.0 / 14_712_000]))
            let f = AstroMath.radians(AstroMath.polynomial(t, [93.2720950, 483_202.0175233, -0.0036539,
                                                               -1.0 / 3_526_000, 1.0 / 863_310_000]))
            let lPrime = AstroMath.radians(meanLongitude)
            let a1 = AstroMath.radians(119.75 + 131.849 * t)
            let a2 = AstroMath.radians(53.09 + 479_264.290 * t)
            let a3 = AstroMath.radians(313.45 + 481_266.484 * t)

            // Eccentricity of the Earth's orbit damps terms in the solar anomaly M.
            let e = 1 - 0.002516 * t - 0.0000074 * t * t
            let eSquared = e * e

            // The argument of a term: its integer multiples of D, M, M′ and F.
            let combination = {{ (d1: Int8, m1: Int8, mPrime1: Int8, f1: Int8) -> Double in
                Double(d1) * d + Double(m1) * m + Double(mPrime1) * mPrime + Double(f1) * f
            }}

            var sumLongitude = 3958 * sin(a1) + 1962 * sin(lPrime - f) + 318 * sin(a2)
            var sumDistance = 0.0
            for term in longitudeDistanceTerms {{
                let argument = combination(term.d, term.m, term.mPrime, term.f)
                let scale = eccentricityFactor(multiplierOfM: term.m, e: e, eSquared: eSquared)
                sumLongitude += term.longitude * scale * sin(argument)
                sumDistance += term.distance * scale * cos(argument)
            }}

            var sumLatitude = -2235 * sin(lPrime) + 382 * sin(a3) + 175 * sin(a1 - f)
                + 175 * sin(a1 + f) + 127 * sin(lPrime - mPrime) - 115 * sin(lPrime + mPrime)
            for term in latitudeTerms {{
                let argument = combination(term.d, term.m, term.mPrime, term.f)
                let scale = eccentricityFactor(multiplierOfM: term.m, e: e, eSquared: eSquared)
                sumLatitude += term.latitude * scale * sin(argument)
            }}

            // Sums are in millionths of a degree (longitude, latitude) and thousandths of a kilometre.
            return Position(longitude: AstroMath.normalizeDegrees(meanLongitude + sumLongitude / 1e6),
                            latitude: sumLatitude / 1e6,
                            distanceKilometers: 385_000.56 + sumDistance / 1e3)
        }}

        private static func eccentricityFactor(multiplierOfM multiplier: Int8, e: Double, eSquared: Double) -> Double {{
            switch multiplier {{
            case 0: 1
            case 1, -1: e
            default: eSquared
            }}
        }}

        /// A row of Table 47.A: multiples of D, M, M′ and F with the sine coefficient of the
        /// longitude (10⁻⁶ degree) and the cosine coefficient of the distance (10⁻³ km).
        private struct PeriodicTerm {{
            let d: Int8, m: Int8, mPrime: Int8, f: Int8
            let longitude: Double
            let distance: Double

            init(_ d: Int8, _ m: Int8, _ mPrime: Int8, _ f: Int8, longitude: Double, distance: Double) {{
                self.d = d
                self.m = m
                self.mPrime = mPrime
                self.f = f
                self.longitude = longitude
                self.distance = distance
            }}
        }}

        /// A row of Table 47.B: multiples of D, M, M′ and F with the sine coefficient of the
        /// latitude (10⁻⁶ degree).
        private struct LatitudeTerm {{
            let d: Int8, m: Int8, mPrime: Int8, f: Int8
            let latitude: Double

            init(_ d: Int8, _ m: Int8, _ mPrime: Int8, _ f: Int8, latitude: Double) {{
                self.d = d
                self.m = m
                self.mPrime = mPrime
                self.f = f
                self.latitude = latitude
            }}
        }}

        /// Table 47.A.
        private static let longitudeDistanceTerms: [PeriodicTerm] = [
{rows_a()}
        ]

        /// Table 47.B.
        private static let latitudeTerms: [LatitudeTerm] = [
{rows_b()}
        ]
    }}
}}
"""
open(sys.argv[1], "w", encoding="utf-8").write(source)
print("written", sys.argv[1])

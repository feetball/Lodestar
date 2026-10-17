import Foundation

extension Ephemeris {
    /// The Moon's geocentric position from the truncated ELP-2000/82 lunar theory of
    /// Jean Meeus, *Astronomical Algorithms* (2nd ed., 1998), chapter 47: 60 periodic terms for
    /// longitude and distance (Table 47.A), 60 for latitude (Table 47.B) and the additive
    /// terms for Venus, Jupiter and the flattening of the Earth. Measured against JPL's DE440s over
    /// 1950–2049 the direction is good to 8″ and the distance to 45 km (1.2×10⁻⁴). The coefficients
    /// were checked row by row against two independent MIT-licensed implementations of the same
    /// tables, `moonposition` in github.com/soniakeys/meeus and `moonposition.js` in
    /// github.com/commenthol/astronomia.
    enum LunarTheory {
        /// Geometric geocentric position, referred to the mean equinox and ecliptic of date.
        struct Position {
            /// Ecliptic longitude in degrees, [0, 360).
            let longitude: Double
            /// Ecliptic latitude in degrees.
            let latitude: Double
            /// Distance between the centres of the Earth and the Moon in kilometres.
            let distanceKilometers: Double
        }

        /// The Moon's geocentric position in AU in the mean equatorial frame of J2000.0 as seen one
        /// light-time ago (the Moon moves about 0.7″ while its light travels to the Earth).
        static func geocentricJ2000(_ jd: JulianDate) -> Vector3 {
            let t = jd.centuriesTT
            let distanceAU = geocentricEcliptic(centuries: t).distanceKilometers / SkyFrame.kilometersPerAU
            let lightTimeCenturies = distanceAU * Ephemeris.lightTimePerAU / JulianDate.daysPerJulianCentury
            let position = geocentricEcliptic(centuries: t - lightTimeCenturies)
            let ecliptic = EclipticCoordinate(longitude: position.longitude, latitude: position.latitude).unitVector
                * (position.distanceKilometers / SkyFrame.kilometersPerAU)
            let meanEquatorialOfDate = Matrix3.rotationX(AstroMath.radians(Obliquity.mean(jd))) * ecliptic
            return Precession.matrixFromJ2000(to: jd).transposed * meanEquatorialOfDate
        }

        /// The Moon's geometric position at `t` Julian centuries of TT since J2000.0, without light-time.
        static func geocentricEcliptic(centuries t: Double) -> Position {
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
            let combination = { (d1: Int8, m1: Int8, mPrime1: Int8, f1: Int8) -> Double in
                Double(d1) * d + Double(m1) * m + Double(mPrime1) * mPrime + Double(f1) * f
            }

            var sumLongitude = 3958 * sin(a1) + 1962 * sin(lPrime - f) + 318 * sin(a2)
            var sumDistance = 0.0
            for term in longitudeDistanceTerms {
                let argument = combination(term.d, term.m, term.mPrime, term.f)
                let scale = eccentricityFactor(multiplierOfM: term.m, e: e, eSquared: eSquared)
                sumLongitude += term.longitude * scale * sin(argument)
                sumDistance += term.distance * scale * cos(argument)
            }

            var sumLatitude = -2235 * sin(lPrime) + 382 * sin(a3) + 175 * sin(a1 - f)
                + 175 * sin(a1 + f) + 127 * sin(lPrime - mPrime) - 115 * sin(lPrime + mPrime)
            for term in latitudeTerms {
                let argument = combination(term.d, term.m, term.mPrime, term.f)
                let scale = eccentricityFactor(multiplierOfM: term.m, e: e, eSquared: eSquared)
                sumLatitude += term.latitude * scale * sin(argument)
            }

            // Sums are in millionths of a degree (longitude, latitude) and thousandths of a kilometre.
            return Position(longitude: AstroMath.normalizeDegrees(meanLongitude + sumLongitude / 1e6),
                            latitude: sumLatitude / 1e6,
                            distanceKilometers: 385_000.56 + sumDistance / 1e3)
        }

        private static func eccentricityFactor(multiplierOfM multiplier: Int8, e: Double, eSquared: Double) -> Double {
            switch multiplier {
            case 0: 1
            case 1, -1: e
            default: eSquared
            }
        }

        /// A row of Table 47.A: multiples of D, M, M′ and F with the sine coefficient of the
        /// longitude (10⁻⁶ degree) and the cosine coefficient of the distance (10⁻³ km).
        private struct PeriodicTerm {
            let d: Int8, m: Int8, mPrime: Int8, f: Int8
            let longitude: Double
            let distance: Double

            init(_ d: Int8, _ m: Int8, _ mPrime: Int8, _ f: Int8, longitude: Double, distance: Double) {
                self.d = d
                self.m = m
                self.mPrime = mPrime
                self.f = f
                self.longitude = longitude
                self.distance = distance
            }
        }

        /// A row of Table 47.B: multiples of D, M, M′ and F with the sine coefficient of the
        /// latitude (10⁻⁶ degree).
        private struct LatitudeTerm {
            let d: Int8, m: Int8, mPrime: Int8, f: Int8
            let latitude: Double

            init(_ d: Int8, _ m: Int8, _ mPrime: Int8, _ f: Int8, latitude: Double) {
                self.d = d
                self.m = m
                self.mPrime = mPrime
                self.f = f
                self.latitude = latitude
            }
        }

        /// Table 47.A.
        private static let longitudeDistanceTerms: [PeriodicTerm] = [
            PeriodicTerm(0, 0, 1, 0, longitude: 6288774, distance: -20905355),
            PeriodicTerm(2, 0, -1, 0, longitude: 1274027, distance: -3699111),
            PeriodicTerm(2, 0, 0, 0, longitude: 658314, distance: -2955968),
            PeriodicTerm(0, 0, 2, 0, longitude: 213618, distance: -569925),
            PeriodicTerm(0, 1, 0, 0, longitude: -185116, distance: 48888),
            PeriodicTerm(0, 0, 0, 2, longitude: -114332, distance: -3149),
            PeriodicTerm(2, 0, -2, 0, longitude: 58793, distance: 246158),
            PeriodicTerm(2, -1, -1, 0, longitude: 57066, distance: -152138),
            PeriodicTerm(2, 0, 1, 0, longitude: 53322, distance: -170733),
            PeriodicTerm(2, -1, 0, 0, longitude: 45758, distance: -204586),
            PeriodicTerm(0, 1, -1, 0, longitude: -40923, distance: -129620),
            PeriodicTerm(1, 0, 0, 0, longitude: -34720, distance: 108743),
            PeriodicTerm(0, 1, 1, 0, longitude: -30383, distance: 104755),
            PeriodicTerm(2, 0, 0, -2, longitude: 15327, distance: 10321),
            PeriodicTerm(0, 0, 1, 2, longitude: -12528, distance: 0),
            PeriodicTerm(0, 0, 1, -2, longitude: 10980, distance: 79661),
            PeriodicTerm(4, 0, -1, 0, longitude: 10675, distance: -34782),
            PeriodicTerm(0, 0, 3, 0, longitude: 10034, distance: -23210),
            PeriodicTerm(4, 0, -2, 0, longitude: 8548, distance: -21636),
            PeriodicTerm(2, 1, -1, 0, longitude: -7888, distance: 24208),
            PeriodicTerm(2, 1, 0, 0, longitude: -6766, distance: 30824),
            PeriodicTerm(1, 0, -1, 0, longitude: -5163, distance: -8379),
            PeriodicTerm(1, 1, 0, 0, longitude: 4987, distance: -16675),
            PeriodicTerm(2, -1, 1, 0, longitude: 4036, distance: -12831),
            PeriodicTerm(2, 0, 2, 0, longitude: 3994, distance: -10445),
            PeriodicTerm(4, 0, 0, 0, longitude: 3861, distance: -11650),
            PeriodicTerm(2, 0, -3, 0, longitude: 3665, distance: 14403),
            PeriodicTerm(0, 1, -2, 0, longitude: -2689, distance: -7003),
            PeriodicTerm(2, 0, -1, 2, longitude: -2602, distance: 0),
            PeriodicTerm(2, -1, -2, 0, longitude: 2390, distance: 10056),
            PeriodicTerm(1, 0, 1, 0, longitude: -2348, distance: 6322),
            PeriodicTerm(2, -2, 0, 0, longitude: 2236, distance: -9884),
            PeriodicTerm(0, 1, 2, 0, longitude: -2120, distance: 5751),
            PeriodicTerm(0, 2, 0, 0, longitude: -2069, distance: 0),
            PeriodicTerm(2, -2, -1, 0, longitude: 2048, distance: -4950),
            PeriodicTerm(2, 0, 1, -2, longitude: -1773, distance: 4130),
            PeriodicTerm(2, 0, 0, 2, longitude: -1595, distance: 0),
            PeriodicTerm(4, -1, -1, 0, longitude: 1215, distance: -3958),
            PeriodicTerm(0, 0, 2, 2, longitude: -1110, distance: 0),
            PeriodicTerm(3, 0, -1, 0, longitude: -892, distance: 3258),
            PeriodicTerm(2, 1, 1, 0, longitude: -810, distance: 2616),
            PeriodicTerm(4, -1, -2, 0, longitude: 759, distance: -1897),
            PeriodicTerm(0, 2, -1, 0, longitude: -713, distance: -2117),
            PeriodicTerm(2, 2, -1, 0, longitude: -700, distance: 2354),
            PeriodicTerm(2, 1, -2, 0, longitude: 691, distance: 0),
            PeriodicTerm(2, -1, 0, -2, longitude: 596, distance: 0),
            PeriodicTerm(4, 0, 1, 0, longitude: 549, distance: -1423),
            PeriodicTerm(0, 0, 4, 0, longitude: 537, distance: -1117),
            PeriodicTerm(4, -1, 0, 0, longitude: 520, distance: -1571),
            PeriodicTerm(1, 0, -2, 0, longitude: -487, distance: -1739),
            PeriodicTerm(2, 1, 0, -2, longitude: -399, distance: 0),
            PeriodicTerm(0, 0, 2, -2, longitude: -381, distance: -4421),
            PeriodicTerm(1, 1, 1, 0, longitude: 351, distance: 0),
            PeriodicTerm(3, 0, -2, 0, longitude: -340, distance: 0),
            PeriodicTerm(4, 0, -3, 0, longitude: 330, distance: 0),
            PeriodicTerm(2, -1, 2, 0, longitude: 327, distance: 0),
            PeriodicTerm(0, 2, 1, 0, longitude: -323, distance: 1165),
            PeriodicTerm(1, 1, -1, 0, longitude: 299, distance: 0),
            PeriodicTerm(2, 0, 3, 0, longitude: 294, distance: 0),
            PeriodicTerm(2, 0, -1, -2, longitude: 0, distance: 8752),
        ]

        /// Table 47.B.
        private static let latitudeTerms: [LatitudeTerm] = [
            LatitudeTerm(0, 0, 0, 1, latitude: 5128122),
            LatitudeTerm(0, 0, 1, 1, latitude: 280602),
            LatitudeTerm(0, 0, 1, -1, latitude: 277693),
            LatitudeTerm(2, 0, 0, -1, latitude: 173237),
            LatitudeTerm(2, 0, -1, 1, latitude: 55413),
            LatitudeTerm(2, 0, -1, -1, latitude: 46271),
            LatitudeTerm(2, 0, 0, 1, latitude: 32573),
            LatitudeTerm(0, 0, 2, 1, latitude: 17198),
            LatitudeTerm(2, 0, 1, -1, latitude: 9266),
            LatitudeTerm(0, 0, 2, -1, latitude: 8822),
            LatitudeTerm(2, -1, 0, -1, latitude: 8216),
            LatitudeTerm(2, 0, -2, -1, latitude: 4324),
            LatitudeTerm(2, 0, 1, 1, latitude: 4200),
            LatitudeTerm(2, 1, 0, -1, latitude: -3359),
            LatitudeTerm(2, -1, -1, 1, latitude: 2463),
            LatitudeTerm(2, -1, 0, 1, latitude: 2211),
            LatitudeTerm(2, -1, -1, -1, latitude: 2065),
            LatitudeTerm(0, 1, -1, -1, latitude: -1870),
            LatitudeTerm(4, 0, -1, -1, latitude: 1828),
            LatitudeTerm(0, 1, 0, 1, latitude: -1794),
            LatitudeTerm(0, 0, 0, 3, latitude: -1749),
            LatitudeTerm(0, 1, -1, 1, latitude: -1565),
            LatitudeTerm(1, 0, 0, 1, latitude: -1491),
            LatitudeTerm(0, 1, 1, 1, latitude: -1475),
            LatitudeTerm(0, 1, 1, -1, latitude: -1410),
            LatitudeTerm(0, 1, 0, -1, latitude: -1344),
            LatitudeTerm(1, 0, 0, -1, latitude: -1335),
            LatitudeTerm(0, 0, 3, 1, latitude: 1107),
            LatitudeTerm(4, 0, 0, -1, latitude: 1021),
            LatitudeTerm(4, 0, -1, 1, latitude: 833),
            LatitudeTerm(0, 0, 1, -3, latitude: 777),
            LatitudeTerm(4, 0, -2, 1, latitude: 671),
            LatitudeTerm(2, 0, 0, -3, latitude: 607),
            LatitudeTerm(2, 0, 2, -1, latitude: 596),
            LatitudeTerm(2, -1, 1, -1, latitude: 491),
            LatitudeTerm(2, 0, -2, 1, latitude: -451),
            LatitudeTerm(0, 0, 3, -1, latitude: 439),
            LatitudeTerm(2, 0, 2, 1, latitude: 422),
            LatitudeTerm(2, 0, -3, -1, latitude: 421),
            LatitudeTerm(2, 1, -1, 1, latitude: -366),
            LatitudeTerm(2, 1, 0, 1, latitude: -351),
            LatitudeTerm(4, 0, 0, 1, latitude: 331),
            LatitudeTerm(2, -1, 1, 1, latitude: 315),
            LatitudeTerm(2, -2, 0, -1, latitude: 302),
            LatitudeTerm(0, 0, 1, 3, latitude: -283),
            LatitudeTerm(2, 1, 1, -1, latitude: -229),
            LatitudeTerm(1, 1, 0, -1, latitude: 223),
            LatitudeTerm(1, 1, 0, 1, latitude: 223),
            LatitudeTerm(0, 1, -2, -1, latitude: -220),
            LatitudeTerm(2, 1, -1, -1, latitude: -220),
            LatitudeTerm(1, 0, 1, 1, latitude: -185),
            LatitudeTerm(2, -1, -2, -1, latitude: 181),
            LatitudeTerm(0, 1, 2, 1, latitude: -177),
            LatitudeTerm(4, 0, -2, -1, latitude: 176),
            LatitudeTerm(4, -1, -1, -1, latitude: 166),
            LatitudeTerm(1, 0, 1, -1, latitude: -164),
            LatitudeTerm(4, 0, 1, -1, latitude: 132),
            LatitudeTerm(1, 0, -1, -1, latitude: -119),
            LatitudeTerm(4, -1, 0, -1, latitude: 115),
            LatitudeTerm(2, -2, 0, 1, latitude: 107),
        ]
    }
}

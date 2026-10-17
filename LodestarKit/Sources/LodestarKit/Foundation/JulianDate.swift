import Foundation

/// An instant expressed as a Julian Date in two time scales.
///
/// `ut` is the Julian Date in Universal Time (UT1, taken as equal to UTC — the difference is
/// below 0.9 s and irrelevant for this app). `tt` is Terrestrial Time, `ut + ΔT`, the uniform
/// time scale used by the ephemeris theories.
public struct JulianDate: Hashable, Comparable, Codable, Sendable {
    /// Julian Date of the J2000.0 epoch (2000 January 1, 12:00 TT).
    public static let j2000 = 2_451_545.0
    /// Julian Date of the Unix epoch (1970 January 1, 00:00 UTC).
    public static let unixEpoch = 2_440_587.5
    public static let daysPerJulianCentury = 36_525.0
    public static let secondsPerDay = 86_400.0

    /// Julian Date in UT1 (≈ UTC).
    public let ut: Double
    /// ΔT = TT − UT in seconds.
    public let deltaT: Double

    /// Julian Date in Terrestrial Time.
    public var tt: Double { ut + deltaT / Self.secondsPerDay }

    public init(ut: Double, deltaT: Double) {
        self.ut = ut
        self.deltaT = deltaT
    }

    /// Creates a Julian Date from UT, estimating ΔT for that epoch.
    public init(ut: Double) {
        self.init(ut: ut, deltaT: Self.deltaT(decimalYear: Self.decimalYear(julianDay: ut)))
    }

    /// Creates a Julian Date from TT (e.g. for published examples given in dynamical time),
    /// estimating ΔT for that epoch.
    public init(tt: Double) {
        let deltaT = Self.deltaT(decimalYear: Self.decimalYear(julianDay: tt))
        self.init(ut: tt - deltaT / Self.secondsPerDay, deltaT: deltaT)
    }

    /// Creates a Julian Date from a `Date` (POSIX time is UTC without leap seconds).
    public init(date: Date) {
        self.init(ut: date.timeIntervalSince1970 / Self.secondsPerDay + Self.unixEpoch)
    }

    /// The instant as a `Date`.
    public var date: Date {
        Date(timeIntervalSince1970: (ut - Self.unixEpoch) * Self.secondsPerDay)
    }

    /// Julian centuries of TT since J2000.0.
    public var centuriesTT: Double { (tt - Self.j2000) / Self.daysPerJulianCentury }

    /// Julian centuries of UT since J2000.0.
    public var centuriesUT: Double { (ut - Self.j2000) / Self.daysPerJulianCentury }

    /// The epoch as a Julian year in TT, e.g. 2026.79.
    public var julianYearTT: Double { 2000 + (tt - Self.j2000) / 365.25 }

    /// A Julian Date `days` later (ΔT is re-estimated for the new epoch).
    public func addingDays(_ days: Double) -> JulianDate {
        JulianDate(ut: ut + days)
    }

    public static func < (lhs: JulianDate, rhs: JulianDate) -> Bool { lhs.ut < rhs.ut }

    /// The decimal year corresponding to a Julian Day number (Julian-year approximation).
    public static func decimalYear(julianDay: Double) -> Double {
        2000 + (julianDay - j2000) / 365.25
    }

    /// Julian Day for a proleptic Gregorian calendar date and time (Meeus, ch. 7).
    public static func julianDay(year: Int, month: Int, day: Int,
                                 hour: Int = 0, minute: Int = 0, second: Double = 0) -> Double {
        var y = Double(year)
        var m = Double(month)
        if month <= 2 {
            y -= 1
            m += 12
        }
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        let dayFraction = (Double(hour) + Double(minute) / 60 + second / 3600) / 24
        return (365.25 * (y + 4716)).rounded(.down)
            + (30.6001 * (m + 1)).rounded(.down)
            + Double(day) + dayFraction + b - 1524.5
    }

    /// Estimated ΔT = TT − UT in seconds.
    ///
    /// Uses the Espenak & Meeus (2006) polynomials up to 2005, measured annual values from
    /// 2005 to 2026, a linear blend towards the Espenak & Meeus long-term expression between 2026
    /// and 2050, and that expression afterwards. Errors are well below a few seconds for the
    /// 20th and 21st centuries, which is negligible for pointing purposes.
    public static func deltaT(decimalYear y: Double) -> Double {
        guard y.isFinite else { return 69.2 }
        if y >= measuredDeltaTStart && y <= measuredDeltaTEnd {
            let position = y - measuredDeltaTStart
            let index = min(Int(position), measuredDeltaT.count - 2)
            let fraction = position - Double(index)
            return measuredDeltaT[index] + (measuredDeltaT[index + 1] - measuredDeltaT[index]) * fraction
        }
        if y > measuredDeltaTEnd && y < 2050 {
            let start = measuredDeltaT[measuredDeltaT.count - 1]
            let end = longTermDeltaT(year: 2050) - 0.5628 * (2150 - 2050)
            return start + (end - start) * (y - measuredDeltaTEnd) / (2050 - measuredDeltaTEnd)
        }
        if y >= 2050 && y < 2150 {
            return longTermDeltaT(year: y) - 0.5628 * (2150 - y)
        }
        if y >= 2150 || y < 1800 {
            return longTermDeltaT(year: y)
        }
        if y < 1860 {
            let t = y - 1800
            return AstroMath.polynomial(t, [13.72, -0.332447, 0.0068612, 0.0041116, -0.00037436,
                                            0.0000121272, -0.0000001699, 0.000000000875])
        }
        if y < 1900 {
            let t = y - 1860
            return AstroMath.polynomial(t, [7.62, 0.5737, -0.251754, 0.01680668, -0.0004473624, 1.0 / 233_174])
        }
        if y < 1920 {
            let t = y - 1900
            return AstroMath.polynomial(t, [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197])
        }
        if y < 1941 {
            let t = y - 1920
            return AstroMath.polynomial(t, [21.20, 0.84493, -0.076100, 0.0020936])
        }
        if y < 1961 {
            let t = y - 1950
            return AstroMath.polynomial(t, [29.07, 0.407, -1 / 233.0, 1 / 2547.0])
        }
        if y < 1986 {
            let t = y - 1975
            return AstroMath.polynomial(t, [45.45, 1.067, -1 / 260.0, -1 / 718.0])
        }
        let t = y - 2000
        return AstroMath.polynomial(t, [63.86, 0.3345, -0.060374, 0.0017275, 0.000651814, 0.00002373599])
    }

    private static func longTermDeltaT(year y: Double) -> Double {
        let u = (y - 1820) / 100
        return -20 + 32 * u * u
    }

    private static let measuredDeltaTStart = 2005.0
    private static let measuredDeltaTEnd = 2026.0
    /// ΔT at the start of each year 2005…2026 (seconds), from IERS/USNO determinations.
    private static let measuredDeltaT: [Double] = [
        64.69, 64.85, 65.15, 65.46, 65.78, 66.07, 66.32, 66.60, 66.91, 67.28, 67.64,
        68.10, 68.59, 68.97, 69.22, 69.36, 69.36, 69.29, 69.20, 69.18, 69.14, 69.11,
    ]
}

/// Sidereal time (Earth rotation angle relative to the equinox).
public enum SiderealTime {
    /// Greenwich mean sidereal time in degrees, [0, 360) (IAU 1982 expression, Meeus 12.4).
    public static func greenwichMean(_ jd: JulianDate) -> Double {
        let d = jd.ut - JulianDate.j2000
        let t = d / JulianDate.daysPerJulianCentury
        let theta = 280.460_618_37 + 360.985_647_366_29 * d + 0.000_387_933 * t * t - t * t * t / 38_710_000
        return AstroMath.normalizeDegrees(theta)
    }

    /// Greenwich apparent sidereal time in degrees: mean sidereal time plus the equation of the
    /// equinoxes (Δψ·cos ε).
    public static func greenwichApparent(_ jd: JulianDate, nutation: Nutation, trueObliquity: Double) -> Double {
        AstroMath.normalizeDegrees(greenwichMean(jd) + nutation.longitude * AstroMath.cosDeg(trueObliquity))
    }
}

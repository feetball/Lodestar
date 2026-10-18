import Foundation

/// Numerical helpers shared by the event finders. Times are Julian Dates in UT ("ut", days); the Julian Date of an
/// instant carries the ΔT estimate of `JulianDate`, so every finder sees the same ephemeris time.
enum EventSearch {
    /// The Sun's mean rate of ecliptic longitude in degrees per day.
    static let meanSolarRate = 0.985_647_3
    /// Days in the tropical year.
    static let tropicalYearDays = 365.242_2
    /// Longest interval the calculator accepts, in days (a little over ten years).
    static let maximumSpanDays = 3_660.0

    private static let obliquityJ2000Radians = AstroMath.radians(Obliquity.j2000)

    /// The Julian Date (UT) of `date`.
    static func ut(_ date: Date) -> Double { JulianDate(date: date).ut }

    /// The instant of a UT Julian Date.
    static func instant(_ ut: Double) -> Date { JulianDate(ut: ut).date }

    /// `true` when `from` and `to` are in order and inside the years 1 to 4001 (`Date.distantPast`, `Date.distantFuture`),
    /// where the ephemerides and the calendar arithmetic are well defined; a non-finite date is never usable. (The
    /// comparison is on the `Double` seconds: `Date`'s own `>=` is `!(<)` and would accept NaN.)
    static func isUsable(from: Date, to: Date) -> Bool {
        let start = from.timeIntervalSinceReferenceDate
        let end = to.timeIntervalSinceReferenceDate
        return start.isFinite && end.isFinite && end >= start
            && start >= Date.distantPast.timeIntervalSinceReferenceDate
            && end <= Date.distantFuture.timeIntervalSinceReferenceDate
    }

    /// `to` limited to `maximumSpanDays` after `from`.
    static func limitedEnd(from: Date, to: Date) -> Date {
        let limit = from.addingTimeInterval(maximumSpanDays * JulianDate.secondsPerDay)
        return to > limit ? limit : to
    }

    /// The Sun's apparent geocentric ecliptic longitude in degrees, referred to the equinox of J2000.0.
    static func sunLongitudeJ2000(_ jd: JulianDate) -> Double {
        let sun = Ephemeris.geocentricJ2000(of: .sun, at: jd)
        let y = sun.y * cos(obliquityJ2000Radians) + sun.z * sin(obliquityJ2000Radians)
        return AstroMath.normalizeDegrees(AstroMath.atan2Deg(y, sun.x))
    }

    /// The Sun's apparent geocentric ecliptic longitude of date in degrees (true equinox of date).
    static func sunLongitudeOfDate(_ jd: JulianDate) -> Double {
        Ephemeris.state(of: .sun, at: jd).eclipticLongitudeOfDate
    }

    /// The UT Julian Date near `guess` at which `longitude` equals `target` degrees, by Newton steps with the Sun's
    /// mean rate (the true rate stays within 4 % of it, so the error shrinks by a factor of 25 each step).
    static func solveSolarLongitude(target: Double, guess: Double, longitude: (JulianDate) -> Double) -> Double {
        var ut = guess
        for _ in 0..<12 {
            let error = AstroMath.normalizeSignedDegrees(longitude(JulianDate(ut: ut)) - target)
            let step = error / meanSolarRate
            ut -= step
            if abs(step) < 1e-9 { break }
        }
        return ut
    }

    /// Brent's method for a root of `function` between `lower` and `upper`, or `nil` when the function has the same
    /// sign at both ends. Stops when the bracket is shorter than `tolerance`.
    static func root(of function: (Double) -> Double, lower: Double, upper: Double, tolerance: Double) -> Double? {
        let valueAtLower = function(lower)
        let valueAtUpper = function(upper)
        guard valueAtLower.isFinite, valueAtUpper.isFinite else { return nil }
        if (valueAtLower > 0) == (valueAtUpper > 0), valueAtLower != 0, valueAtUpper != 0 { return nil }
        return RiseSetCalculator.Profile.root(of: function, lower: lower, upper: upper, valueAtLower: valueAtLower,
                                               valueAtUpper: valueAtUpper, tolerance: tolerance)
    }

    /// The argument that minimises the unimodal `function` on `lower...upper` (golden-section search) and its value.
    static func minimum(of function: (Double) -> Double, lower: Double, upper: Double,
                        tolerance: Double) -> (time: Double, value: Double) {
        let peak = RiseSetCalculator.Profile.maximum(of: { -function($0) }, lower: lower, upper: upper,
                                                     tolerance: tolerance)
        return (peak.time, -peak.value)
    }

    /// The argument that maximises the unimodal `function` on `lower...upper` and its value.
    static func maximum(of function: (Double) -> Double, lower: Double, upper: Double,
                        tolerance: Double) -> (time: Double, value: Double) {
        RiseSetCalculator.Profile.maximum(of: function, lower: lower, upper: upper, tolerance: tolerance)
    }

    /// Sample indices of the strict local maxima of a series (`>` before and `>=` after, so a plateau counts once,
    /// at its first sample).
    static func localMaxima(_ values: [Double]) -> [Int] {
        var found = [Int]()
        if values.count < 3 { return found }
        for index in 1..<(values.count - 1) where values[index] > values[index - 1] && values[index] >= values[index + 1] {
            found.append(index)
        }
        return found
    }

    /// Sample indices of the local minima of a series (`<=` before, `<` after).
    static func localMinima(_ values: [Double]) -> [Int] {
        var found = [Int]()
        if values.count < 3 { return found }
        for index in 1..<(values.count - 1) where values[index] <= values[index - 1] && values[index] < values[index + 1] {
            found.append(index)
        }
        return found
    }

    /// `events` in order of date; events with the same date keep their order (a stable sort).
    static func sortedByDate(_ events: [AstronomicalEvent]) -> [AstronomicalEvent] {
        events.enumerated().sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Number of grid intervals of at most `step` days over `span` days, at least 1.
    static func intervalCount(span: Double, step: Double) -> Int {
        let count = (span / step).rounded(.up)
        return count.isFinite ? max(1, Int(min(count, 1_000_000_000))) : 1
    }
}

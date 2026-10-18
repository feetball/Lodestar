import Foundation

/// The stretch of an interval around the highest point of an altitude curve in which the altitude stays at or above a
/// threshold: the "best window" of an event.
struct AltitudeWindowResult {
    /// First instant of the window (UT Julian Date).
    let start: Double
    /// Last instant of the window.
    let end: Double
    /// The instant of the greatest altitude inside the window.
    let peakTime: Double
    /// The altitude at `peakTime`.
    let peakAltitude: Double
}

/// Finds the best window of an altitude curve.
enum AltitudeWindow {
    /// Most samples taken in one search.
    static let maximumSampleCount = 2_000

    private static let edgeTolerance = 1e-6
    private static let peakTolerance = 1e-5

    /// The window around the highest sample of `altitude` on `start...end` (UT Julian Dates, at most `step` days between
    /// samples) in which the curve stays at or above `threshold`; the edges inside the interval are refined with Brent's
    /// method and the peak with a golden-section search. `nil` when no sample reaches the threshold.
    static func best(start: Double, end: Double, step: Double, threshold: Double,
                     altitude: (Double) -> Double) -> AltitudeWindowResult? {
        guard start.isFinite, end.isFinite, end >= start, step > 0 else { return nil }
        let span = end - start
        let count = max(1, Int(min((span / step).rounded(.up), Double(maximumSampleCount))))
        let times = (0...count).map { $0 == count ? end : start + span * Double($0) / Double(count) }
        let altitudes = times.map { altitude($0) }
        var best = -1
        for index in 0...count where altitudes[index] >= threshold && (best < 0 || altitudes[index] > altitudes[best]) {
            best = index
        }
        if best < 0 { return nil }
        var left = best
        while left > 0, altitudes[left - 1] >= threshold { left -= 1 }
        var right = best
        while right < count, altitudes[right + 1] >= threshold { right += 1 }
        let windowStart: Double
        if left == 0 {
            windowStart = start
        } else {
            windowStart = EventSearch.root(of: { altitude($0) - threshold }, lower: times[left - 1], upper: times[left],
                                           tolerance: edgeTolerance) ?? times[left]
        }
        let windowEnd: Double
        if right == count {
            windowEnd = end
        } else {
            windowEnd = EventSearch.root(of: { altitude($0) - threshold }, lower: times[right], upper: times[right + 1],
                                         tolerance: edgeTolerance) ?? times[right]
        }
        var peakTime = times[best]
        var peakAltitude = altitudes[best]
        if best >= 1, best < count {
            let peak = EventSearch.maximum(of: altitude, lower: times[best - 1], upper: times[best + 1],
                                           tolerance: peakTolerance)
            if peak.value >= peakAltitude {
                peakTime = AstroMath.clamp(peak.time, windowStart, windowEnd)
                peakAltitude = peak.value
            }
        }
        return AltitudeWindowResult(start: windowStart, end: windowEnd, peakTime: peakTime, peakAltitude: peakAltitude)
    }
}

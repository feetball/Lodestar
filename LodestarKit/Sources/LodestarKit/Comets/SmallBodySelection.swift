import Foundation

/// A comet or asteroid that is bright enough to photograph, with the moment it is brightest.
public struct BrightSmallBody: Hashable, Sendable {
    /// The body.
    public let body: SmallBody
    /// Its state at the brightest sampled moment (among those far enough from the Sun): the magnitude, the elongation,
    /// the distances and the position.
    public let peak: SmallBodyState

    public init(body: SmallBody, peak: SmallBodyState) {
        self.body = body
        self.peak = peak
    }

    /// The magnitude at the peak (the state has one, otherwise the body would not have been selected).
    public var peakMagnitude: Double { peak.apparentMagnitude ?? Double.infinity }

    /// The moment of the peak.
    public var peakDate: Date { peak.julianDate.date }
}

/// Picks the bright comets (and asteroids) out of thousands of orbit records, for "bright comets now" and "this
/// month" lists.
///
/// A cheap prefilter discards almost every record without computing a position: from the distance from the Sun over the
/// period (a Kepler solution at both ends, plus the perihelion or aphelion when the period contains it) and the fact
/// that the Earth stays between 0.983 and 1.017 AU from the Sun, it bounds the brightest the object can possibly get
/// (`M1 + 5 log Δmin + K1 log rmin`; for an asteroid `H + 5 log(r Δ)min`), and drops it if that is fainter than the limit.
/// The survivors are sampled (daily, at most `maximumSampleCount` samples; the Earth is computed once per sample for all
/// of them), the best sample is refined by a golden-section search, and the brightest state with enough elongation is kept.
///
/// **Cost** (desktop CPU, warm): the 963 comets of `CometEls.txt` take about 1 ms for `brightNow` and 2 ms for a month;
/// 43 000 near-Earth asteroids (`NEA.txt`) take 60 ms and 0.5 s (their orbits come close to the Earth's, so the prefilter
/// keeps many of them). Records that survive the prefilter cost about 5 microseconds per sample plus 24 states for the
/// refinement. Sorting is by peak magnitude, brightest first, ties by identifier.
public enum SmallBodySelection {
    /// The most samples taken over an interval, 64 (spans over 63 days are sampled more coarsely than daily).
    public static let maximumSampleCount = 64

    /// The Earth's smallest distance from the Sun in AU, rounded down.
    private static let earthMinimumDistance = 0.9831

    /// The Earth's largest distance from the Sun in AU, rounded up.
    private static let earthMaximumDistance = 1.0169

    /// The smallest Earth distance used in the prefilter, 0.001 AU (150 000 km).
    private static let minimumEarthDistance = 0.001

    /// Safety margin of the prefilter in magnitudes.
    private static let prefilterMargin = 0.35

    private static let refinementIterations = 24

    /// The bodies that reach `magnitudeLimit` while at least `minimumElongation` from the Sun at some moment in
    /// `interval`, brightest first.
    ///
    /// - Parameters:
    ///   - bodies: The candidates (for example the result of `CometElementsParser.parse`).
    ///   - interval: The period; the sampling is daily up to 63 days and coarser beyond.
    ///   - magnitudeLimit: The faintest magnitude accepted (non-finite: nothing is selected).
    ///   - minimumElongation: Smallest angle from the Sun in degrees, clamped to 0…180.
    ///   - kind: Only comets or only asteroids; `nil` for both.
    ///   - maximumCount: The most results to return (0 or less: none).
    public static func brightest(in bodies: [SmallBody], during interval: DateInterval,
                                 magnitudeLimit: Double = SmallBodyEphemeris.defaultMagnitudeLimit,
                                 minimumElongation: Double = SmallBodyEphemeris.defaultMinimumElongation,
                                 kind: SmallBodyKind? = nil, maximumCount: Int = 100) -> [BrightSmallBody] {
        let days = interval.duration / JulianDate.secondsPerDay
        let count = days > 0 ? min(maximumSampleCount, max(2, Int(days.rounded(.up)) + 1)) : 1
        return select(bodies, start: interval.start, stepDays: count > 1 ? days / Double(count - 1) : 0.0, count: count,
                      magnitudeLimit: magnitudeLimit, minimumElongation: minimumElongation, kind: kind,
                      maximumCount: maximumCount)
    }

    /// The bodies that are at most `magnitudeLimit` and at least `minimumElongation` from the Sun at `date`, brightest first.
    public static func brightNow(in bodies: [SmallBody], at date: Date,
                                 magnitudeLimit: Double = SmallBodyEphemeris.defaultMagnitudeLimit,
                                 minimumElongation: Double = SmallBodyEphemeris.defaultMinimumElongation,
                                 kind: SmallBodyKind? = nil, maximumCount: Int = 100) -> [BrightSmallBody] {
        select(bodies, start: date, stepDays: 0.0, count: 1, magnitudeLimit: magnitudeLimit,
               minimumElongation: minimumElongation, kind: kind, maximumCount: maximumCount)
    }

    private static func select(_ bodies: [SmallBody], start: Date, stepDays: Double, count: Int, magnitudeLimit: Double,
                               minimumElongation: Double, kind: SmallBodyKind?, maximumCount: Int) -> [BrightSmallBody] {
        guard magnitudeLimit.isFinite, minimumElongation.isFinite, maximumCount > 0 else { return [] }
        let elongationLimit = AstroMath.clamp(minimumElongation, 0.0, 180.0)
        let first = JulianDate(date: start)
        let last = first.addingDays(stepDays * Double(count - 1))
        var earths: [SmallBodyEphemeris.EarthReference]?
        var found = [BrightSmallBody]()
        for body in bodies {
            if let kind, body.kind != kind { continue }
            if body.photometry == nil { continue }
            if brightestPossible(for: body, startTT: first.tt, endTT: last.tt) > magnitudeLimit { continue }
            if earths == nil {
                earths = (0..<count).map { index in
                    SmallBodyEphemeris.EarthReference(julianDate: index == 0 ? first : first.addingDays(stepDays * Double(index)))
                }
            }
            guard let samples = earths else { continue }
            var best: SmallBodyState?
            var bestIndex = 0
            for index in samples.indices {
                guard let state = SmallBodyEphemeris.state(of: body, earth: samples[index]) else { continue }
                if !qualifies(state, elongationLimit) { continue }
                if let current = best {
                    if magnitude(state) < magnitude(current) {
                        best = state
                        bestIndex = index
                    }
                } else {
                    best = state
                    bestIndex = index
                }
            }
            guard var peak = best else { continue }
            if count > 1 {
                let low = max(0, bestIndex - 1)
                let high = min(count - 1, bestIndex + 1)
                peak = refined(body, seed: peak, from: samples[low].julianDate, to: samples[high].julianDate,
                               elongationLimit: elongationLimit)
            }
            if magnitude(peak) <= magnitudeLimit { found.append(BrightSmallBody(body: body, peak: peak)) }
        }
        found.sort { a, b in
            if a.peakMagnitude < b.peakMagnitude { return true }
            if b.peakMagnitude < a.peakMagnitude { return false }
            return compareIdentifiers(a.body.id, b.body.id) < 0
        }
        return found.count > maximumCount ? Array(found[0..<maximumCount]) : found
    }

    private static func magnitude(_ state: SmallBodyState) -> Double { state.apparentMagnitude ?? Double.infinity }

    private static func qualifies(_ state: SmallBodyState, _ elongationLimit: Double) -> Bool {
        state.apparentMagnitude != nil && state.elongation >= elongationLimit
    }

    /// Orders identifiers by Unicode scalar values (the same order in Kotlin and Swift).
    private static func compareIdentifiers(_ a: String, _ b: String) -> Int {
        let left = Array(a.unicodeScalars)
        let right = Array(b.unicodeScalars)
        let common = min(left.count, right.count)
        for index in 0..<common where left[index] != right[index] {
            return left[index].value < right[index].value ? -1 : 1
        }
        return left.count < right.count ? -1 : (left.count > right.count ? 1 : 0)
    }

    /// Golden-section search for the brightest qualifying state between `from` and `to`, starting from `seed` (so the
    /// result is never fainter than the seed).
    private static func refined(_ body: SmallBody, seed: SmallBodyState, from: JulianDate, to: JulianDate,
                                elongationLimit: Double) -> SmallBodyState {
        let ratio = 0.6180339887498949
        var best = seed
        var low = from.ut
        var high = to.ut
        guard high > low else { return best }
        func evaluate(_ ut: Double) -> Double {
            guard let state = SmallBodyEphemeris.state(of: body, at: JulianDate(ut: ut)) else { return Double.infinity }
            if !qualifies(state, elongationLimit) { return Double.infinity }
            let value = magnitude(state)
            if value < magnitude(best) { best = state }
            return value
        }
        var c = high - ratio * (high - low)
        var d = low + ratio * (high - low)
        var fc = evaluate(c)
        var fd = evaluate(d)
        for _ in 0..<refinementIterations {
            if fc < fd {
                high = d
                d = c
                fd = fc
                c = high - ratio * (high - low)
                fc = evaluate(c)
            } else {
                low = c
                c = d
                fc = fd
                d = low + ratio * (high - low)
                fd = evaluate(d)
            }
        }
        return best
    }

    /// A lower bound of the magnitude `body` can have between `startTT` and `endTT` (Julian Days TT): the brightest
    /// conceivable combination of the smallest distance from the Sun over the period and the smallest possible
    /// distance from the Earth. `-∞` when no bound can be computed.
    static func brightestPossible(for body: SmallBody, startTT: Double, endTT: Double) -> Double {
        guard let photometry = body.photometry else { return Double.infinity }
        let orbit = body.orbit
        guard let atStart = OrbitPropagator.heliocentricDistance(of: orbit, at: startTT),
              let atEnd = OrbitPropagator.heliocentricDistance(of: orbit, at: endTT) else { return -Double.infinity }
        var nearest = min(atStart, atEnd)
        var farthest = max(atStart, atEnd)
        let passage = orbit.perihelionJulianDayTT
        if let period = orbit.periodDays {
            let perihelionCount = ((startTT - passage) / period).rounded(.up)
            if passage + perihelionCount * period <= endTT { nearest = orbit.perihelionDistanceAU }
            let aphelionCount = ((startTT - passage) / period - 0.5).rounded(.up)
            if passage + (aphelionCount + 0.5) * period <= endTT {
                farthest = orbit.aphelionDistanceAU ?? farthest
            }
        } else if passage >= startTT && passage <= endTT {
            nearest = orbit.perihelionDistanceAU
        }
        let earthDistance = max(minimumEarthDistance, max(nearest - earthMaximumDistance, earthMinimumDistance - farthest))
        switch photometry {
        case .comet(let magnitudes):
            let sunDistance = magnitudes.totalSlope >= 0 ? nearest : farthest
            return magnitudes.totalMagnitude + 5 * log10(earthDistance) + magnitudes.totalSlope * log10(sunDistance) - prefilterMargin
        case .asteroid(let magnitudes):
            return magnitudes.absoluteMagnitude + 5 * log10(nearest * earthDistance) - prefilterMargin
        }
    }
}

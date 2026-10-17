import Foundation

extension RiseSetCalculator {
    /// One evaluation of an altitude curve.
    struct Sample {
        /// Geometric altitude of the target's centre in degrees.
        let centreAltitude: Double
        /// Degrees added to the centre altitude before it is compared with a horizon threshold, for
        /// targets whose limb (not centre) defines the event and whose size varies (the Moon).
        let limbAllowance: Double

        init(centreAltitude: Double, limbAllowance: Double = 0) {
            self.centreAltitude = centreAltitude
            self.limbAllowance = limbAllowance
        }

        /// The altitude that is compared with a horizon threshold.
        var limbAltitude: Double { centreAltitude + limbAllowance }
    }

    /// An altitude curve sampled at regular instants, with root and extremum refinement.
    ///
    /// Times are seconds since the Foundation reference date. Sampling is regular with a step no
    /// larger than requested; sign changes are bracketed between samples and refined with Brent's
    /// method, extremes with golden-section search. Pairs of crossings that fall between two samples
    /// (a target that only just touches the horizon) are found by testing each local extreme of the
    /// samples.
    struct Profile {
        typealias Evaluator = (Double) -> Sample

        /// Upper bound on the number of samples; longer intervals are sampled more coarsely.
        static let maximumSampleCount = 100_000

        let times: [Double]
        let samples: [Sample]

        /// Samples the curve from `start` to `end` (seconds since the reference date) with at most
        /// `step` seconds between samples. An empty or invalid interval yields a single sample at `start`.
        init(start: Double, end: Double, step: Double, evaluate: Evaluator) {
            let span = end - start
            var intervalCount = 0
            if span.isFinite, span > 0, step.isFinite, step > 0 {
                intervalCount = Int(min((span / step).rounded(.up), Double(Self.maximumSampleCount - 1)))
            }
            var times = [Double]()
            var samples = [Sample]()
            times.reserveCapacity(intervalCount + 1)
            samples.reserveCapacity(intervalCount + 1)
            for index in 0...intervalCount {
                let fraction = Double(index) / Double(max(intervalCount, 1))
                let time = index == intervalCount && intervalCount > 0 ? end : start + span * fraction
                times.append(time)
                samples.append(evaluate(time))
            }
            self.times = times
            self.samples = samples
        }

        /// Samples the curve over a `DateInterval`.
        init(interval: DateInterval, step: TimeInterval, evaluate: Evaluator) {
            self.init(start: interval.start.timeIntervalSinceReferenceDate,
                      end: interval.end.timeIntervalSinceReferenceDate, step: step, evaluate: evaluate)
        }

        /// How close (degrees) a local extreme of the samples must come to a threshold before the curve
        /// is searched for a pair of crossings between samples. Between two samples at most 10 minutes
        /// apart the curve cannot rise above the sampled maximum by more than a few hundredths of a degree.
        private static let grazingMargin = 0.05

        /// Every instant at which the limb altitude passes through `threshold`, in time order.
        func crossings(of threshold: Double, tolerance: Double, evaluate: Evaluator) -> [AltitudeCrossing] {
            let margin = samples.map { $0.limbAltitude - threshold }
            let function: (Double) -> Double = { evaluate($0).limbAltitude - threshold }
            var found = [AltitudeCrossing]()
            for index in 0..<(times.count - 1) {
                let current = margin[index], next = margin[index + 1]
                guard current.isFinite, next.isFinite else { continue }
                if (current < 0) != (next < 0) {
                    let time = Self.root(of: function, lower: times[index], upper: times[index + 1],
                                         valueAtLower: current, valueAtUpper: next, tolerance: tolerance)
                    found.append(AltitudeCrossing(time: Date(timeIntervalSinceReferenceDate: time),
                                                  kind: next >= 0 ? .rising : .setting))
                } else if index > 0, margin[index - 1].isFinite, (margin[index - 1] < 0) == (current < 0) {
                    found.append(contentsOf: hiddenCrossings(at: index, margin: margin, function: function,
                                                             tolerance: tolerance))
                }
            }
            return found
        }

        /// The pair of crossings, if any, hidden between samples `index - 1 ... index + 1`, which all lie
        /// on the same side of the threshold: the curve dips to the other side around an extreme at `index`.
        private func hiddenCrossings(at index: Int, margin: [Double], function: (Double) -> Double,
                                     tolerance: Double) -> [AltitudeCrossing] {
            // `orientation` makes the curve `g` negative on the sampled side, so the dip is a maximum of `g`.
            let orientation = margin[index] < 0 ? 1.0 : -1.0
            let before = orientation * margin[index - 1]
            let here = orientation * margin[index]
            let after = orientation * margin[index + 1]
            guard here > before, here >= after, here > -Self.grazingMargin else { return [] }

            let peak = Self.maximum(of: { orientation * function($0) }, lower: times[index - 1],
                                    upper: times[index + 1], tolerance: tolerance)
            guard peak.value > 0 else { return [] }
            let peakMargin = orientation * peak.value
            let first = Self.root(of: function, lower: times[index - 1], upper: peak.time,
                                  valueAtLower: margin[index - 1], valueAtUpper: peakMargin, tolerance: tolerance)
            let second = Self.root(of: function, lower: peak.time, upper: times[index + 1],
                                   valueAtLower: peakMargin, valueAtUpper: margin[index + 1], tolerance: tolerance)
            let sampledBelow = orientation > 0
            return [AltitudeCrossing(time: Date(timeIntervalSinceReferenceDate: first),
                                     kind: sampledBelow ? .rising : .setting),
                    AltitudeCrossing(time: Date(timeIntervalSinceReferenceDate: second),
                                     kind: sampledBelow ? .setting : .rising)]
        }

        /// Every local maximum of the centre altitude strictly inside the interval (upper culminations).
        func upperCulminations(tolerance: Double, evaluate: Evaluator) -> [AltitudeCulmination] {
            guard times.count >= 2 else { return [] }
            let altitude: (Double) -> Double = { evaluate($0).centreAltitude }
            let last = times.count - 1
            var found = [AltitudeCulmination]()

            func append(_ peak: (time: Double, value: Double)) {
                found.append(AltitudeCulmination(time: Date(timeIntervalSinceReferenceDate: peak.time),
                                                 altitude: peak.value))
            }
            // A curve that starts by falling away from its first sample, or ends by rising towards
            // its last, may peak inside the first or last interval; a search that runs into the end of
            // the interval means there is no peak.
            let boundaryGuard = max(1, 4 * tolerance)
            if samples[0].centreAltitude > samples[1].centreAltitude {
                let peak = Self.maximum(of: altitude, lower: times[0], upper: times[1], tolerance: tolerance)
                if peak.time - times[0] > boundaryGuard { append(peak) }
            }
            for index in 1..<max(last, 1) {
                let before = samples[index - 1].centreAltitude
                let here = samples[index].centreAltitude
                let after = samples[index + 1].centreAltitude
                guard before.isFinite, here.isFinite, after.isFinite, here > before, here >= after else { continue }
                append(Self.maximum(of: altitude, lower: times[index - 1], upper: times[index + 1],
                                    tolerance: tolerance))
            }
            if samples[last].centreAltitude > samples[last - 1].centreAltitude {
                let peak = Self.maximum(of: altitude, lower: times[last - 1], upper: times[last], tolerance: tolerance)
                if times[last] - peak.time > boundaryGuard { append(peak) }
            }
            return found
        }

        /// The lowest centre altitude reached inside the interval, refined around the lowest sample.
        /// (Samples whose altitude is not finite are never the lowest.)
        func lowestPoint(tolerance: Double, evaluate: Evaluator) -> (time: Double, altitude: Double) {
            var lowest = 0
            for index in samples.indices where samples[index].centreAltitude < samples[lowest].centreAltitude {
                lowest = index
            }
            guard times.count >= 2 else { return (times[0], samples[0].centreAltitude) }
            let trough = Self.maximum(of: { -evaluate($0).centreAltitude },
                                      lower: times[max(lowest - 1, 0)], upper: times[min(lowest + 1, times.count - 1)],
                                      tolerance: tolerance)
            return (trough.time, -trough.value)
        }

        // MARK: Numerical search

        /// Brent's method for a root of `function` bracketed by `lower` and `upper`, whose function
        /// values must have opposite signs (or be zero). Stops when the bracket is shorter than `tolerance`.
        static func root(of function: (Double) -> Double, lower: Double, upper: Double,
                         valueAtLower: Double, valueAtUpper: Double, tolerance: Double) -> Double {
            var a = lower, b = upper, fa = valueAtLower, fb = valueAtUpper
            if fa == 0 { return a }
            if fb == 0 { return b }
            var c = a, fc = fa
            var step = b - a, previousStep = step
            for _ in 0..<100 {
                if (fb > 0) == (fc > 0) {
                    c = a
                    fc = fa
                    step = b - a
                    previousStep = step
                }
                if abs(fc) < abs(fb) {
                    a = b
                    b = c
                    c = a
                    fa = fb
                    fb = fc
                    fc = fa
                }
                let tolerance1 = 2 * Double.ulpOfOne * abs(b) + 0.5 * tolerance
                let midpoint = 0.5 * (c - b)
                if abs(midpoint) <= tolerance1 || fb == 0 { return b }
                if abs(previousStep) >= tolerance1, abs(fa) > abs(fb) {
                    // Inverse quadratic interpolation, or the secant method when only two points are distinct.
                    let ratio = fb / fa
                    var p: Double, q: Double
                    if a == c {
                        p = 2 * midpoint * ratio
                        q = 1 - ratio
                    } else {
                        let qa = fa / fc, r = fb / fc
                        p = ratio * (2 * midpoint * qa * (qa - r) - (b - a) * (r - 1))
                        q = (qa - 1) * (r - 1) * (ratio - 1)
                    }
                    if p > 0 { q = -q }
                    p = abs(p)
                    if 2 * p < min(3 * midpoint * q - abs(tolerance1 * q), abs(previousStep * q)) {
                        previousStep = step
                        step = p / q
                    } else {
                        step = midpoint
                        previousStep = step
                    }
                } else {
                    step = midpoint
                    previousStep = step
                }
                a = b
                fa = fb
                b += abs(step) > tolerance1 ? step : (midpoint >= 0 ? tolerance1 : -tolerance1)
                fb = function(b)
            }
            return b
        }

        /// Golden-section search for the maximum of a unimodal `function` on `lower ... upper`.
        static func maximum(of function: (Double) -> Double, lower: Double, upper: Double,
                            tolerance: Double) -> (time: Double, value: Double) {
            let inverseGolden = (5.0.squareRoot() - 1) / 2
            var a = lower, b = upper
            var c = b - inverseGolden * (b - a)
            var d = a + inverseGolden * (b - a)
            var fc = function(c), fd = function(d)
            for _ in 0..<200 where abs(b - a) > tolerance {
                if fc > fd {
                    b = d
                    d = c
                    fd = fc
                    c = b - inverseGolden * (b - a)
                    fc = function(c)
                } else {
                    a = c
                    c = d
                    fc = fd
                    d = a + inverseGolden * (b - a)
                    fd = function(d)
                }
            }
            return fc > fd ? (c, fc) : (d, fd)
        }
    }
}

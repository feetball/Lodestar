import Foundation

extension NightPlanner {
    /// The altitude of one target sampled at evenly spaced instants, with interpolation between samples.
    ///
    /// The profile stores the sine of the altitude, the vertical component of the direction to the target.
    /// Unlike the altitude itself it stays smooth when a target passes close to the zenith, where the
    /// altitude has a sharp peak. Between samples the curve is the cubic through the four nearest samples
    /// (fewer for very short profiles). For samples ten minutes apart that is accurate to about 1e-7
    /// in the sine, which is below a second for crossings and maxima.
    ///
    /// Positions along the profile are measured in seconds from its first sample.
    struct AltitudeProfile {
        /// Seconds between samples.
        let step: TimeInterval
        /// Sine of the altitude at each sample; at least two values.
        let sines: [Double]

        private static let bisectionSteps = 40
        private static let goldenSectionSteps = 60

        /// The length of the profile in seconds.
        var duration: TimeInterval { step * Double(sines.count - 1) }

        /// The highest point between two offsets: its position in seconds and its sine.
        ///
        /// The offsets are clamped to the profile. The maximum may lie on either end.
        func maximum(from startOffset: TimeInterval,
                     to endOffset: TimeInterval) -> (offset: TimeInterval, sine: Double) {
            let last = Double(sines.count - 1)
            let lower = AstroMath.clamp(startOffset / step, 0, last)
            let upper = AstroMath.clamp(endOffset / step, lower, last)
            var best = (index: lower, sine: sine(atIndex: lower))
            let atUpper = sine(atIndex: upper)
            if atUpper > best.sine { best = (upper, atUpper) }

            let firstSample = Int(lower.rounded(.up)), lastSample = Int(upper.rounded(.down))
            if firstSample <= lastSample {
                var peak = firstSample
                for index in firstSample...lastSample where sines[index] > sines[peak] { peak = index }
                let refined = refinedMaximum(lower: max(Double(peak) - 1, lower), upper: min(Double(peak) + 1, upper))
                let candidate = refined.sine > sines[peak] ? refined : (Double(peak), sines[peak])
                if candidate.sine > best.sine { best = candidate }
            }
            return (best.index * step, best.sine)
        }

        /// The stretches of the profile, as offsets in seconds, where the sine is at least `threshold`.
        func offsets(atOrAbove threshold: Double) -> [(start: TimeInterval, end: TimeInterval)] {
            var result = [(start: TimeInterval, end: TimeInterval)]()
            var opened: TimeInterval? = sines[0] >= threshold ? 0 : nil
            for cell in 0..<(sines.count - 1) where (sines[cell] >= threshold) != (sines[cell + 1] >= threshold) {
                let crossing = crossingOffset(inCell: cell, threshold: threshold)
                if sines[cell + 1] >= threshold {
                    opened = crossing
                } else if let start = opened {
                    result.append((start, crossing))
                    opened = nil
                }
            }
            if let start = opened { result.append((start, duration)) }
            return result.filter { $0.end > $0.start }
        }

        // MARK: Interpolation and search

        /// The interpolated sine at a fractional sample index between 0 and the last sample.
        func sine(atIndex position: Double) -> Double {
            let count = min(4, sines.count)
            let first = min(max(Int(position.rounded(.down)) - 1, 0), sines.count - count)
            var total = 0.0
            for a in 0..<count {
                var term = sines[first + a]
                for b in 0..<count where b != a {
                    term *= (position - Double(first + b)) / Double(a - b)
                }
                total += term
            }
            return total
        }

        /// The offset in seconds where the interpolated curve crosses `threshold` between samples `cell`
        /// and `cell + 1`, which lie on opposite sides of it (bisection).
        private func crossingOffset(inCell cell: Int, threshold: Double) -> TimeInterval {
            var lower = Double(cell), upper = Double(cell + 1)
            let startsAbove = sines[cell] >= threshold
            for _ in 0..<Self.bisectionSteps {
                let middle = (lower + upper) / 2
                if (sine(atIndex: middle) >= threshold) == startsAbove { lower = middle } else { upper = middle }
            }
            return (lower + upper) / 2 * step
        }

        /// Golden-section search for the highest point of the interpolated curve between two sample
        /// indices, which must bracket a single peak.
        private func refinedMaximum(lower: Double, upper: Double) -> (index: Double, sine: Double) {
            let inverseGolden = (5.0.squareRoot() - 1) / 2
            var a = lower, b = upper
            var c = b - inverseGolden * (b - a), d = a + inverseGolden * (b - a)
            var atC = sine(atIndex: c), atD = sine(atIndex: d)
            for _ in 0..<Self.goldenSectionSteps where b - a > 1e-9 {
                if atC > atD {
                    b = d
                    d = c
                    atD = atC
                    c = b - inverseGolden * (b - a)
                    atC = sine(atIndex: c)
                } else {
                    a = c
                    c = d
                    atC = atD
                    d = a + inverseGolden * (b - a)
                    atD = sine(atIndex: d)
                }
            }
            return atC > atD ? (c, atC) : (d, atD)
        }
    }
}

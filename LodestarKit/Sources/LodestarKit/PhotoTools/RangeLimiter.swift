/// Limits numbers to a range, replacing values that are not numbers.
enum RangeLimiter {
    /// Returns `value` limited to `range`, or `fallback` if `value` is not finite.
    static func limit(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

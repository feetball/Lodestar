/// Locale-independent number rendering built on integer arithmetic.
///
/// Rounding happens once, on the finest displayed unit, and the result is split with integer
/// division. Rounding carries (59.96 s becoming the next minute, 359.96° becoming 0°) therefore
/// need no special cases, and output never depends on the user's locale.
enum NumberText {
    /// The largest number of decimal places the public formatters render; larger requests are clamped.
    static let maximumDecimals = 6

    /// 2^53: every integer below this magnitude is exactly representable as a `Double`.
    private static let exactIntegerLimit = 9_007_199_254_740_992.0

    /// Clamps a caller-supplied number of decimal places to `0...maximumDecimals`.
    static func clampedDecimals(_ decimals: Int) -> Int {
        min(max(decimals, 0), maximumDecimals)
    }

    /// 10 raised to a small non-negative power.
    static func powerOfTen(_ exponent: Int) -> Int64 {
        var result: Int64 = 1
        for _ in 0..<max(exponent, 0) { result *= 10 }
        return result
    }

    /// Left-pads the decimal digits of a non-negative integer with zeros.
    static func padded(_ value: Int64, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    // MARK: Fixed point

    /// A non-negative value scaled by 10^decimals and rounded half away from zero.
    struct FixedPoint {
        /// The value multiplied by 10^`decimals`.
        let units: Int64
        let decimals: Int

        /// Whether the value rounded to zero at the requested precision.
        var isZero: Bool { units == 0 }

        /// The digits with a "." decimal mark and no sign, for example "40.0150".
        var text: String {
            let scale = NumberText.powerOfTen(decimals)
            let whole = String(units / scale)
            guard decimals > 0 else { return whole }
            return whole + "." + NumberText.padded(units % scale, width: decimals)
        }
    }

    /// Rounds a finite, non-negative value to `decimals` places, or returns nil when the value is
    /// negative, not finite or too large to be rendered exactly.
    static func fixedPoint(magnitude: Double, decimals: Int) -> FixedPoint? {
        guard magnitude.isFinite, magnitude >= 0 else { return nil }
        let places = clampedDecimals(decimals)
        let scaled = (magnitude * Double(powerOfTen(places))).rounded()
        guard scaled < exactIntegerLimit else { return nil }
        return FixedPoint(units: Int64(scaled), decimals: places)
    }

    /// Renders a non-negative value with at most `maxDecimals` places and without trailing zeros,
    /// for example "2.5", "13" or "0.25".
    static func trimmed(magnitude: Double, maxDecimals: Int) -> String? {
        guard let fixed = fixedPoint(magnitude: magnitude, decimals: maxDecimals) else { return nil }
        var text = fixed.text
        if fixed.decimals > 0 {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// Renders a non-negative value with exactly `decimals` places for display text, falling back to
    /// Swift's own description for values that cannot be scaled to an integer (huge or not finite).
    static func fixedDescription(_ value: Double, decimals: Int) -> String {
        fixedPoint(magnitude: value, decimals: decimals)?.text ?? "\(value)"
    }

    /// Like `trimmed(magnitude:maxDecimals:)` for display text, with the same fallback as
    /// `fixedDescription(_:decimals:)`.
    static func trimmedDescription(_ value: Double, maxDecimals: Int) -> String {
        trimmed(magnitude: value, maxDecimals: maxDecimals) ?? "\(value)"
    }

    // MARK: Sexagesimal

    /// A non-negative quantity split into whole units, minutes and seconds.
    struct Sexagesimal {
        /// Whole hours or degrees.
        let whole: Int64
        /// Whole minutes, 0...59.
        let minutes: Int64
        /// Seconds multiplied by 10^`decimals`, below 60 × 10^`decimals`.
        let secondsUnits: Int64
        let decimals: Int

        /// Whether every component rounded to zero at the requested precision.
        var isZero: Bool { whole == 0 && minutes == 0 && secondsUnits == 0 }

        /// The seconds with at least two integer digits, for example "05" or "17.3".
        var secondsText: String {
            let scale = NumberText.powerOfTen(decimals)
            let integer = NumberText.padded(secondsUnits / scale, width: 2)
            guard decimals > 0 else { return integer }
            return integer + "." + NumberText.padded(secondsUnits % scale, width: decimals)
        }
    }

    /// Splits a finite, non-negative quantity (hours or degrees) into whole units, minutes and
    /// seconds, rounding at the requested seconds precision so that carries propagate upward.
    static func sexagesimal(magnitude: Double, secondsDecimals: Int) -> Sexagesimal? {
        guard magnitude.isFinite, magnitude >= 0 else { return nil }
        let places = clampedDecimals(secondsDecimals)
        let scale = powerOfTen(places)
        let unitsPerWhole = 3600 * scale
        let scaled = (magnitude * Double(unitsPerWhole)).rounded()
        guard scaled < exactIntegerLimit else { return nil }
        let total = Int64(scaled)
        let remainder = total % unitsPerWhole
        return Sexagesimal(
            whole: total / unitsPerWhole,
            minutes: remainder / (60 * scale),
            secondsUnits: remainder % (60 * scale),
            decimals: places
        )
    }
}

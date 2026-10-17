// Durations and camera exposure times are formatted by `AngleFormatter` as well, so that all
// display formatting shares one entry point, one `TypographyStyle` and one placeholder. Rounding
// carries propagate here too: 59.6 s is "1m 00s", never "0m 60s".
extension AngleFormatter {
    /// Durations beyond this many seconds (about 31,700 years) are treated as not renderable.
    private static let maximumDurationSeconds = 1e12

    /// Formats a duration with at most two units, for example "12s", "4m 30s" or "1h 05m".
    ///
    /// Below one minute the value is shown in whole seconds, below one hour in minutes and
    /// seconds, and from one hour on in hours and whole minutes (seconds are dropped). Hours are
    /// not folded into days. Negative durations get a minus sign unless they round to zero.
    public static func formatDuration(seconds: Double, style: TypographyStyle = .unicode) -> String {
        guard seconds.isFinite, abs(seconds) < maximumDurationSeconds else { return style.placeholder }
        let magnitude = abs(seconds)

        let text: String
        let isZero: Bool
        let wholeSeconds = Int64(magnitude.rounded())
        if wholeSeconds < 60 {
            text = "\(wholeSeconds)s"
            isZero = wholeSeconds == 0
        } else if wholeSeconds < 3600 {
            text = "\(wholeSeconds / 60)m \(NumberText.padded(wholeSeconds % 60, width: 2))s"
            isZero = false
        } else {
            // Round on the displayed unit so that 1h 59m 40s carries to "2h 00m".
            let wholeMinutes = Int64((magnitude / 60).rounded())
            text = "\(wholeMinutes / 60)h \(NumberText.padded(wholeMinutes % 60, width: 2))m"
            isZero = false
        }
        return seconds < 0 && !isZero ? style.minus + text : text
    }

    /// Formats a camera exposure time the way a shutter-speed dial reads.
    ///
    /// - Below 0.25 s: a fraction, "1/250 s" (the denominator is the reciprocal rounded to an integer).
    /// - 0.25 s up to 1 s: up to two decimals, "0.8 s" or "0.25 s".
    /// - 1 s up to 10 s: up to one decimal, "2.5 s" or "4 s".
    /// - 10 s up to a minute: whole seconds, "13 s".
    /// - A minute or longer: as `formatDuration(seconds:style:)`, "2m 30s".
    ///
    /// Zero, negative and non-finite exposures produce the placeholder.
    public static func formatExposure(seconds: Double, style: TypographyStyle = .unicode) -> String {
        guard seconds.isFinite, seconds > 0 else { return style.placeholder }

        if seconds < 0.25 {
            // Capped so that absurdly short times cannot overflow the integer conversion.
            let denominator = min((1 / seconds).rounded(), 1e9)
            return "1/\(Int64(denominator)) s"
        }
        if seconds < 1 {
            return decimalSeconds(seconds, maxDecimals: 2, style: style)
        }
        if seconds < 10 {
            return decimalSeconds(seconds, maxDecimals: 1, style: style)
        }
        // 59.5 s and above round up to a full minute and are shown as a duration.
        if seconds < 59.5 {
            return "\(Int64(seconds.rounded())) s"
        }
        return formatDuration(seconds: seconds, style: style)
    }

    private static func decimalSeconds(_ seconds: Double, maxDecimals: Int, style: TypographyStyle) -> String {
        guard let text = NumberText.trimmed(magnitude: seconds, maxDecimals: maxDecimals) else {
            return style.placeholder
        }
        return text + " s"
    }
}

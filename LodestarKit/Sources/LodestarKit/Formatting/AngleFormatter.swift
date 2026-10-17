/// Formats angles, sky and geographic coordinates, durations and exposure times for display, and
/// parses angles and coordinates from text.
///
/// ## Formatting
///
/// Output is independent of the user's locale: the decimal mark is always ".", and negative
/// values use U+2212 (or "-" in the `.ascii` style). Rounding is applied once at the finest
/// displayed unit, so carries behave as a reader expects: 59.96 s becomes the next minute and
/// 23h 59m 59.99s becomes 00h 00m 00.0s. Values that are not finite, or that cannot be rendered,
/// produce a placeholder (an em dash, or "--" in the `.ascii` style). The number of decimals is
/// clamped to 0...6.
///
/// ## Parsing
///
/// The `parse…` functions read text typed or pasted by a person. They return `nil` for anything
/// they do not fully understand, and never trap. The rules shared by all of them:
///
/// - Input longer than 64 characters (Unicode scalars) is rejected.
/// - Letters are case-insensitive, and whitespace around and between fields is ignored.
/// - A minus sign may be "-", U+2212 or any Unicode hyphen or dash used as one, such as the en
///   dash. A degree mark is `°` (also `º` and `˚`) or the letter `d`; minutes and seconds are
///   marked with `′` `″`, the apostrophe and quotation marks that smart punctuation produces
///   instead (`'` `"` `’` `”`), two apostrophes for seconds, or the letters `m` and `s`.
/// - The decimal mark is "." or ",". Only ASCII digits are accepted.
/// - Fields are separated by whitespace, ":" or their unit marks, so `05:35:17`, `5 35 17`,
///   `5h35m17s` and `5h 35m 17s` are equivalent. There are at most three fields, only the last may
///   be fractional, and minutes and seconds must be below 60.
/// - A leading hemisphere letter or sign applies to the whole value, so `−00° 30′` is -0.5 even
///   though its degrees are zero. A hemisphere letter together with a minus sign is rejected, as
///   is a hemisphere letter at both ends.
/// - Text produced by the angle and coordinate formatters, in either `TypographyStyle`, can be
///   parsed back.
public enum AngleFormatter: Sendable {

    // MARK: Right ascension and declination

    /// Formats a right ascension as hours, minutes and seconds, for example "05h 35m 17.3s".
    ///
    /// The value is wrapped into [0h, 24h) before formatting, so -1 h is "23h 00m 00.0s" and
    /// 24 h is "00h 00m 00.0s".
    ///
    /// - Parameters:
    ///   - hours: Right ascension in hours.
    ///   - secondsDecimals: Decimal places of the seconds field.
    ///   - style: The typography to use.
    public static func formatRightAscension(
        hours: Double,
        secondsDecimals: Int = 1,
        style: TypographyStyle = .unicode
    ) -> String {
        guard hours.isFinite else { return style.placeholder }
        var wrapped = hours.truncatingRemainder(dividingBy: 24)
        if wrapped < 0 { wrapped += 24 }
        guard let parts = NumberText.sexagesimal(magnitude: wrapped, secondsDecimals: secondsDecimals) else {
            return style.placeholder
        }
        // Rounding can carry 23h 59m 59.99s up to 24h, which is 0h.
        let hoursText = NumberText.padded(parts.whole % 24, width: 2)
        return "\(hoursText)h \(NumberText.padded(parts.minutes, width: 2))m \(parts.secondsText)s"
    }

    /// Formats a declination with an explicit sign, for example "−05° 23′ 28″" or "+41° 16′ 09″".
    ///
    /// Zero, and values that round to zero, carry a plus sign. Values beyond ±90° are clamped.
    ///
    /// - Parameters:
    ///   - degrees: Declination in degrees.
    ///   - secondsDecimals: Decimal places of the arcsecond field.
    ///   - style: The typography to use.
    public static func formatDeclination(
        degrees: Double,
        secondsDecimals: Int = 0,
        style: TypographyStyle = .unicode
    ) -> String {
        guard degrees.isFinite else { return style.placeholder }
        let clamped = min(max(degrees, -90), 90)
        guard let parts = NumberText.sexagesimal(magnitude: abs(clamped), secondsDecimals: secondsDecimals) else {
            return style.placeholder
        }
        let sign = clamped < 0 && !parts.isZero ? style.minus : "+"
        return degreesMinutesSeconds(parts, sign: sign, degreesWidth: 2, style: style)
    }

    // MARK: Decimal and sexagesimal degrees

    /// Formats an angle in decimal degrees without wrapping, for example "123.4°".
    ///
    /// Negative values get a minus sign; a value that rounds to zero does not.
    public static func formatDegrees(
        _ degrees: Double,
        decimals: Int = 1,
        style: TypographyStyle = .unicode
    ) -> String {
        guard let value = NumberText.fixedPoint(magnitude: abs(degrees), decimals: decimals) else {
            return style.placeholder
        }
        let sign = degrees < 0 && !value.isZero ? style.minus : ""
        return sign + value.text + style.degree
    }

    /// Formats an angle in decimal degrees with an explicit sign, for example "+45.3°" or "−5.2°".
    ///
    /// Zero, and values that round to zero, carry a plus sign.
    public static func formatSignedDegrees(
        _ degrees: Double,
        decimals: Int = 1,
        style: TypographyStyle = .unicode
    ) -> String {
        guard let value = NumberText.fixedPoint(magnitude: abs(degrees), decimals: decimals) else {
            return style.placeholder
        }
        let sign = degrees < 0 && !value.isZero ? style.minus : "+"
        return sign + value.text + style.degree
    }

    /// Formats an azimuth wrapped into [0°, 360°), for example "123.4°".
    ///
    /// Wrapping happens after rounding, so 359.96° at one decimal reads "0.0°" and never "360.0°".
    public static func formatAzimuth(
        _ degrees: Double,
        decimals: Int = 1,
        style: TypographyStyle = .unicode
    ) -> String {
        guard degrees.isFinite else { return style.placeholder }
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        guard let value = NumberText.fixedPoint(magnitude: wrapped, decimals: decimals) else {
            return style.placeholder
        }
        let turn = 360 * NumberText.powerOfTen(value.decimals)
        let carried = NumberText.FixedPoint(units: value.units % turn, decimals: value.decimals)
        return carried.text + style.degree
    }

    /// Formats an angle as degrees, arcminutes and arcseconds, for example "123° 27′ 24″".
    ///
    /// Degrees are not padded; minutes and seconds always have two integer digits. Negative values
    /// get a minus sign unless they round to zero.
    public static func formatDMS(
        _ degrees: Double,
        secondsDecimals: Int = 0,
        style: TypographyStyle = .unicode
    ) -> String {
        guard let parts = NumberText.sexagesimal(magnitude: abs(degrees), secondsDecimals: secondsDecimals) else {
            return style.placeholder
        }
        let sign = degrees < 0 && !parts.isZero ? style.minus : ""
        return degreesMinutesSeconds(parts, sign: sign, degreesWidth: 1, style: style)
    }

    // MARK: Geographic coordinates

    /// Formats a latitude with a hemisphere letter, for example "40.0150° N".
    ///
    /// Values beyond ±90° are clamped. Zero, and values that round to zero, are "N".
    public static func formatLatitude(
        _ degrees: Double,
        decimals: Int = 4,
        style: TypographyStyle = .unicode
    ) -> String {
        guard degrees.isFinite else { return style.placeholder }
        let clamped = min(max(degrees, -90), 90)
        guard let value = NumberText.fixedPoint(magnitude: abs(clamped), decimals: decimals) else {
            return style.placeholder
        }
        let hemisphere = clamped < 0 && !value.isZero ? "S" : "N"
        return value.text + style.degree + " " + hemisphere
    }

    /// Formats a longitude with a hemisphere letter, for example "105.2705° W".
    ///
    /// The longitude is wrapped into (-180°, 180°], so 190° is "170.0000° W" and -180° is
    /// "180.0000° E". Zero, and values that round to zero, are "E".
    public static func formatLongitude(
        _ degrees: Double,
        decimals: Int = 4,
        style: TypographyStyle = .unicode
    ) -> String {
        guard degrees.isFinite else { return style.placeholder }
        var wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 {
            wrapped -= 360
        } else if wrapped <= -180 {
            wrapped += 360
        }
        guard let value = NumberText.fixedPoint(magnitude: abs(wrapped), decimals: decimals) else {
            return style.placeholder
        }
        // The antimeridian is written as east however it was reached.
        let isAntimeridian = value.units == 180 * NumberText.powerOfTen(value.decimals)
        let hemisphere = wrapped < 0 && !value.isZero && !isAntimeridian ? "W" : "E"
        return value.text + style.degree + " " + hemisphere
    }

    // MARK: Compass

    /// The compass point whose sector contains an azimuth; see `CompassPoint.init(azimuth:)`.
    public static func compassPoint(azimuth: Double) -> CompassPoint {
        CompassPoint(azimuth: azimuth)
    }

    // MARK: Helpers

    /// Assembles "±DD° MM′ SS″" from rounded parts.
    private static func degreesMinutesSeconds(
        _ parts: NumberText.Sexagesimal,
        sign: String,
        degreesWidth: Int,
        style: TypographyStyle
    ) -> String {
        let degrees = NumberText.padded(parts.whole, width: degreesWidth)
        let minutes = NumberText.padded(parts.minutes, width: 2)
        return "\(sign)\(degrees)\(style.degree) \(minutes)\(style.arcminute) \(parts.secondsText)\(style.arcsecond)"
    }
}

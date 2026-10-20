import Foundation
import LodestarKit

/// App-level formatting: times in the observer's time zone and coordinates in the user's
/// preferred style. Angle text comes from LodestarKit's `AngleFormatter`.
enum AppFormat {
    /// Placeholder for unknown values.
    static let missing = "—"

    // MARK: Time

    /// Short local time, e.g. "21:34" or "9:34 PM" (follows the user's 12/24-hour preference).
    static func time(_ date: Date?, in timeZone: TimeZone) -> String {
        guard let date else { return missing }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// Abbreviated date and short time, e.g. "Oct 17, 21:34".
    static func dateTime(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: timeZone))
    }

    /// Weekday and date, e.g. "Fri, Oct 17".
    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, timeZone: timeZone)
        style = style.weekday(.abbreviated).month(.abbreviated).day()
        return date.formatted(style)
    }

    /// Relative description, e.g. "in 2h 05m" or "12m ago".
    static func relative(_ date: Date, from now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        let text = AngleFormatter.formatDuration(seconds: abs(interval))
        return interval >= 0 ? "in \(text)" : "\(text) ago"
    }

    // MARK: Angles

    static func rightAscension(_ coordinate: EquatorialCoordinate, style: CoordinateStyle) -> String {
        switch style {
        case .sexagesimal: return AngleFormatter.formatRightAscension(hours: coordinate.rightAscensionHours)
        // Wraps after rounding, so 359.9996° reads "0.000°", never "360.000°".
        case .decimal: return AngleFormatter.formatAzimuth(coordinate.rightAscension, decimals: 3)
        }
    }

    static func declination(_ coordinate: EquatorialCoordinate, style: CoordinateStyle) -> String {
        switch style {
        case .sexagesimal: return AngleFormatter.formatDeclination(degrees: coordinate.declination)
        case .decimal: return AngleFormatter.formatSignedDegrees(coordinate.declination, decimals: 3)
        }
    }

    /// Altitude with sign, e.g. "+34.2°".
    static func altitude(_ degrees: Double) -> String {
        AngleFormatter.formatSignedDegrees(degrees, decimals: 1)
    }

    /// Azimuth with compass point, e.g. "123.4° SE".
    static func azimuth(_ degrees: Double) -> String {
        "\(AngleFormatter.formatAzimuth(degrees, decimals: 1)) \(AngleFormatter.compassPoint(azimuth: degrees).abbreviation)"
    }

    /// An angular distance in the most readable unit: "12.3°", "45′" or "30″".
    static func separation(_ degrees: Double) -> String {
        guard degrees.isFinite else { return missing }
        let magnitude = abs(degrees)
        if magnitude >= 1 { return AngleFormatter.formatDegrees(magnitude, decimals: magnitude >= 10 ? 0 : 1) }
        if magnitude * 60 >= 1 {
            // 59.5 arcminutes and more round up to the next unit, a whole degree.
            let minutes = Int((magnitude * 60).rounded())
            return minutes < 60 ? "\(minutes)′" : AngleFormatter.formatDegrees(1, decimals: 1)
        }
        // 59.5 arcseconds and more round up to a whole arcminute.
        let seconds = Int((magnitude * 3600).rounded())
        return seconds < 60 ? "\(seconds)″" : "1′"
    }

    /// Apparent magnitude, e.g. "mag 3.4" or "mag −1.5".
    static func magnitude(_ value: Double?) -> String {
        guard let value, value.isFinite else { return missing }
        // The sign follows the rounded value, so -0.04 reads "mag 0.0", not "mag −0.0".
        let shown = (abs(value) * 10).rounded() / 10
        let text = shown.formatted(.number.precision(.fractionLength(1)))
        return "mag \(value < 0 && shown > 0 ? "\u{2212}" : "")\(text)"
    }

    /// A percentage with no decimals, e.g. "64%".
    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return missing }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

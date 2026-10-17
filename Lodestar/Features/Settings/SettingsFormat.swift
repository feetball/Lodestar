import Foundation
import LodestarKit

/// Text for locations, accuracies and time zones in Settings and Onboarding.
enum SettingsFormat {
    /// "40.0150° N, 105.2705° W".
    static func coordinates(of location: GeographicLocation) -> String {
        "\(AngleFormatter.formatLatitude(location.latitude)), \(AngleFormatter.formatLongitude(location.longitude))"
    }

    /// Whole metres above sea level, e.g. "1650 m".
    static func elevation(_ metres: Double) -> String {
        "\(metres.formatted(.number.precision(.fractionLength(0)).grouping(.never))) m"
    }

    /// A position error radius, e.g. "±35 m" or "±2.4 km".
    static func accuracy(metres: Double) -> String {
        guard metres.isFinite, metres >= 0 else { return AppFormat.missing }
        if metres < 1000 { return "\u{00B1}\(Int(metres.rounded())) m" }
        return "\u{00B1}\((metres / 1000).formatted(.number.precision(.fractionLength(1)))) km"
    }

    /// The offset from UTC, e.g. "UTC−6" or "UTC+5:30".
    static func utcOffset(of zone: TimeZone, at date: Date) -> String {
        let totalMinutes = zone.secondsFromGMT(for: date) / 60
        let sign = totalMinutes < 0 ? "\u{2212}" : "+"
        let hours = abs(totalMinutes) / 60
        let minutes = abs(totalMinutes) % 60
        guard minutes != 0 else { return "UTC\(sign)\(hours)" }
        return "UTC\(sign)\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    /// Whether `zone` is the fixed-offset fallback derived from a longitude rather than a real regional zone.
    static func isNominal(_ zone: TimeZone) -> Bool {
        zone.identifier.hasPrefix("GMT")
    }

    /// The zone's name and offset, e.g. "America/New York · UTC−5", or the offset alone for an estimated zone.
    static func describe(_ zone: TimeZone, at date: Date) -> String {
        let offset = utcOffset(of: zone, at: date)
        if isNominal(zone) { return "\(offset) (estimated from longitude)" }
        return "\(zone.identifier.replacingOccurrences(of: "_", with: " ")) \u{00B7} \(offset)"
    }
}

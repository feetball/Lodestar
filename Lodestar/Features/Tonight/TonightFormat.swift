import Foundation
import LodestarKit

/// Text for the Tonight cards: time windows, durations, directions and clock positions.
enum TonightFormat {
    // MARK: Time

    /// A window of time in the observer's time zone, such as "21:40 – 04:12".
    static func window(_ interval: DateInterval, in timeZone: TimeZone) -> String {
        "\(AppFormat.time(interval.start, in: timeZone)) \u{2013} \(AppFormat.time(interval.end, in: timeZone))"
    }

    /// Every window of a list, separated by commas; the placeholder for an empty list.
    static func windows(_ intervals: [DateInterval], in timeZone: TimeZone) -> String {
        guard !intervals.isEmpty else { return AppFormat.missing }
        return intervals.map { window($0, in: timeZone) }.joined(separator: ", ")
    }

    /// The windows as a spoken phrase, such as "9:40 PM to 4:12 AM".
    static func spokenWindows(_ intervals: [DateInterval], in timeZone: TimeZone) -> String {
        intervals
            .map { "\(AppFormat.time($0.start, in: timeZone)) to \(AppFormat.time($0.end, in: timeZone))" }
            .joined(separator: " and ")
    }

    /// A length of time in hours and minutes, such as "6h 32m" or "45m".
    static func duration(hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0m" }
        let minutes = Int((hours * 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let remainder = minutes % 60
        return "\(minutes / 60)h \(remainder < 10 ? "0" : "")\(remainder)m"
    }

    /// How far a night is from tonight: "Tonight", "Tomorrow night", "3 nights ago".
    static func nightLabel(nightsFromTonight nights: Int) -> String {
        switch nights {
        case 0: return "Tonight"
        case 1: return "Tomorrow night"
        case -1: return "Last night"
        case 2...: return "In \(nights) nights"
        default: return "\(-nights) nights ago"
        }
    }

    /// The zone's usual abbreviation at `date`, such as "MDT".
    static func zoneName(_ timeZone: TimeZone, at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    // MARK: Directions

    /// From this altitude up, a target is so close to the zenith that its compass direction means little.
    static let overheadAltitude = 85.0

    /// A compass point and an azimuth, such as "SSE · 158°", or "Overhead" near the zenith.
    static func direction(azimuth: Double, altitude: Double) -> String {
        guard altitude < overheadAltitude else { return "Overhead" }
        let point = AngleFormatter.compassPoint(azimuth: azimuth).abbreviation
        return "\(point) \u{00B7} \(AngleFormatter.formatAzimuth(azimuth, decimals: 0))"
    }

    /// Where to look, as a short phrase: "facing SSE", or "overhead" near the zenith.
    static func facing(azimuth: Double, altitude: Double) -> String {
        guard altitude < overheadAltitude else { return "overhead" }
        return "facing " + AngleFormatter.compassPoint(azimuth: azimuth).abbreviation
    }

    /// The same phrase for VoiceOver: "facing south-southeast".
    static func spokenFacing(azimuth: Double, altitude: Double) -> String {
        guard altitude < overheadAltitude else { return "overhead" }
        return "facing " + AngleFormatter.compassPoint(azimuth: azimuth).fullName.lowercased()
    }

    /// The clock time for a direction measured clockwise from 12 o'clock: 30° per hour, so 315° is "10:30".
    static func clockPosition(angle: Double) -> String {
        guard angle.isFinite else { return AppFormat.missing }
        let totalMinutes = Int((AstroMath.normalizeDegrees(angle) * 2).rounded()) % 720
        let hour = totalMinutes / 60 == 0 ? 12 : totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hour):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    // MARK: Objects

    /// The object's first designation when it differs from its name, such as "M 31" for the Andromeda Galaxy.
    static func designation(of object: CelestialObject) -> String? {
        object.designations.first.flatMap { designation in
            designation.compare(object.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                ? nil : designation
        }
    }

    /// Type, constellation, magnitude and size on one line: "Galaxy · Andromeda · mag 3.4 · 178′ × 70′".
    static func description(of object: CelestialObject) -> String {
        var parts = [object.category.displayName]
        if let constellation = object.constellationName {
            parts.append(constellation)
        }
        if let magnitude = object.magnitude {
            parts.append(AppFormat.magnitude(magnitude))
        }
        if let size = object.angularSize {
            parts.append(size.description)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

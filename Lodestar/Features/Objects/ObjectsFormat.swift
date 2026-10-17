import Foundation
import LodestarKit

/// Text for object rows: names, one-line descriptions, positions and rising times.
enum ObjectsFormat {
    /// The first designation of an object when it differs from its name, such as "M 31" for the Andromeda Galaxy.
    static func extraDesignation(of object: CelestialObject) -> String? {
        object.designations.first.flatMap { isName(of: object, $0) ? nil : $0 }
    }

    /// The first few designations that differ from the object's name, such as "M 31 · NGC 224"; `nil` when there
    /// are none.
    static func designationsLine(of object: CelestialObject) -> String? {
        let others = object.designations.filter { !isName(of: object, $0) }
        return others.isEmpty ? nil : others.prefix(4).joined(separator: " \u{00B7} ")
    }

    private static func isName(of object: CelestialObject, _ designation: String) -> Bool {
        designation.compare(object.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Type, constellation and magnitude on one line, such as "Galaxy · Andromeda · mag 3.4".
    ///
    /// `magnitude` overrides the catalog magnitude for objects whose brightness changes. With `spoken` the parts are
    /// separated by commas and "magnitude" is written out.
    static func subtitle(of object: CelestialObject, magnitude: Double?, spoken: Bool = false) -> String {
        var parts = [object.category.displayName]
        if let constellation = object.constellationName {
            parts.append(constellation)
        }
        if let magnitude = magnitude ?? object.magnitude {
            let text = AppFormat.magnitude(magnitude)
            parts.append(spoken ? text.replacingOccurrences(of: "mag ", with: "magnitude ") : text)
        }
        return parts.joined(separator: spoken ? ", " : " \u{00B7} ")
    }

    /// Altitude and compass direction of an object above the horizon, such as "↑34° SE".
    static func altitudeAndDirection(of position: ObjectSkyPosition) -> String {
        let altitude = AngleFormatter.formatDegrees(position.altitude, decimals: 0)
        let direction = AngleFormatter.compassPoint(azimuth: position.azimuth).abbreviation
        return "\u{2191}\(altitude) \(direction)"
    }

    /// When an object below the horizon next rises, such as "Rises 21:34" or "Rises tomorrow 02:10";
    /// `nil` when no rising is known.
    static func risingText(for position: ObjectSkyPosition, in timeZone: TimeZone) -> String? {
        if position.neverRises {
            return "Never rises here"
        }
        guard let rise = position.nextRise else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: position.computedAt),
                                           to: calendar.startOfDay(for: rise)).day ?? 0
        switch days {
        case ..<1: return "Rises \(AppFormat.time(rise, in: timeZone))"
        case 1: return "Rises tomorrow \(AppFormat.time(rise, in: timeZone))"
        default: return "Rises \(AppFormat.dateTime(rise, in: timeZone))"
        }
    }

    /// The row's position as a spoken phrase, such as "34° above the horizon, southeast".
    private static func spokenPosition(_ position: ObjectSkyPosition, in timeZone: TimeZone) -> String {
        if position.isAboveHorizon {
            let altitude = AngleFormatter.formatDegrees(position.altitude, decimals: 0)
            let direction = AngleFormatter.compassPoint(azimuth: position.azimuth).fullName.lowercased()
            return "\(altitude) above the horizon, \(direction)"
        }
        if let rising = risingText(for: position, in: timeZone) {
            return "Below the horizon, \(rising.lowercased())"
        }
        return "Below the horizon"
    }

    /// Everything a row shows, as one VoiceOver label.
    static func spokenSummary(of object: CelestialObject, position: ObjectSkyPosition?, isFavorite: Bool,
                              in timeZone: TimeZone) -> String {
        var parts = [object.name]
        if let designation = extraDesignation(of: object) {
            parts.append(designation)
        }
        parts.append(subtitle(of: object, magnitude: position?.magnitude, spoken: true))
        if let position {
            parts.append(spokenPosition(position, in: timeZone))
        }
        if isFavorite {
            parts.append("Favorite")
        }
        return parts.joined(separator: ", ")
    }
}

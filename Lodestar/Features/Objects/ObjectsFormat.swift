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

    /// The catalogue designations after the first one that differ from the object's name, such as
    /// "Caldwell 20 \u{00B7} Sh2-117" for the North America Nebula (whose first designation is "NGC 7000"); `nil` when
    /// there are none. Only deep-sky objects have them.
    static func moreDesignations(of object: CelestialObject) -> String? {
        guard object.isDeepSky else { return nil }
        let first = extraDesignation(of: object)
        let others = object.designations.filter { !isName(of: object, $0) && $0 != first }
        return others.isEmpty ? nil : others.prefix(3).joined(separator: " \u{00B7} ")
    }

    /// The third line of a row: how prominent a deep-sky object is (when `showsProminence`) and its further
    /// catalogue designations, such as "Showpiece \u{00B7} Sh2-155"; `nil` when there is nothing to add.
    static func catalogueLine(of object: CelestialObject, showsProminence: Bool) -> String? {
        var parts: [String] = []
        if showsProminence, object.isDeepSky {
            parts.append(object.prominence.displayName)
        }
        if let more = moreDesignations(of: object) {
            parts.append(more)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private static func isName(of object: CelestialObject, _ designation: String) -> Bool {
        designation.compare(object.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Type, constellation and magnitude on one line, such as "Galaxy · Andromeda · mag 3.4".
    ///
    /// `magnitude` overrides the catalog magnitude for objects whose brightness changes. With `spoken` the parts are
    /// separated by commas and "magnitude" is written out. A comet or an asteroid gets its kind, magnitude estimate,
    /// elongation and warnings from `position` instead.
    static func subtitle(of object: CelestialObject, magnitude: Double?, spoken: Bool = false,
                         position: ObjectSkyPosition? = nil) -> String {
        if object.smallBody != nil {
            return SmallBodyText.subtitle(of: object, info: position?.smallBody, isComputed: position != nil,
                                          spoken: spoken)
        }
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

    /// When an object below the horizon next rises, such as "Rises 21:34" or "Rises tomorrow 02:10"; with a recorded
    /// skyline "Clears skyline 21:34". `nil` when no rising is known.
    ///
    /// Only a star or a deep-sky object that stays down is said to never rise; the Sun, the Moon and the planets move,
    /// so for them it is only that no rising falls within the search window.
    static func risingText(for position: ObjectSkyPosition, in timeZone: TimeZone) -> String? {
        if position.neverRises {
            return position.usesSkyline ? "Never clears the skyline" : "Never rises here"
        }
        if position.noRiseInWindow {
            return position.usesSkyline ? "Won't clear within a day" : "Won't rise within a day"
        }
        guard let rise = position.nextRise else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: position.computedAt),
                                           to: calendar.startOfDay(for: rise)).day ?? 0
        let verb = position.usesSkyline ? "Clears skyline" : "Rises"
        switch days {
        case ..<1: return "\(verb) \(AppFormat.time(rise, in: timeZone))"
        case 1: return "\(verb) tomorrow \(AppFormat.time(rise, in: timeZone))"
        default: return "\(verb) \(AppFormat.dateTime(rise, in: timeZone))"
        }
    }

    /// What a row says of an object that is not visible: "Behind skyline" or "Below horizon".
    static func hiddenText(for position: ObjectSkyPosition) -> String {
        position.isBehindSkyline ? "Behind skyline" : "Below horizon"
    }

    /// The row's position as a spoken phrase, such as "34° above the horizon, southeast".
    private static func spokenPosition(_ position: ObjectSkyPosition, in timeZone: TimeZone) -> String {
        if position.isAboveHorizon {
            let altitude = AngleFormatter.formatDegrees(position.altitude, decimals: 0)
            let direction = AngleFormatter.compassPoint(azimuth: position.azimuth).fullName.lowercased()
            return "\(altitude) above the horizon, \(direction)"
        }
        let hidden = position.isBehindSkyline ? "Behind the skyline" : "Below the horizon"
        if let rising = risingText(for: position, in: timeZone) {
            return "\(hidden), \(rising.lowercased())"
        }
        return hidden
    }

    /// Everything a row shows, as one VoiceOver label.
    static func spokenSummary(of object: CelestialObject, position: ObjectSkyPosition?, isFavorite: Bool,
                              in timeZone: TimeZone, showsProminence: Bool = false) -> String {
        var parts = [SmallBodyText.displayName(object)]
        if let designation = extraDesignation(of: object) {
            parts.append(designation)
        }
        parts.append(subtitle(of: object, magnitude: position?.magnitude, spoken: true, position: position))
        if let line = catalogueLine(of: object, showsProminence: showsProminence) {
            parts.append(line.replacingOccurrences(of: " \u{00B7} ", with: ", "))
        }
        if let position {
            parts.append(spokenPosition(position, in: timeZone))
        }
        if isFavorite {
            parts.append("Favorite")
        }
        return parts.joined(separator: ", ")
    }
}

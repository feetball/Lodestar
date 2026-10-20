import Foundation
import LodestarKit

/// Text for the events screens: dates in the observer's zone, one-line summaries and visibility wording.
enum EventsFormat {
    // MARK: Symbols

    /// The SF Symbol for an event kind.
    static func symbol(for event: AstronomicalEvent) -> String {
        switch event.details {
        case .meteorShower: return "sparkles"
        case .conjunction(let conjunction): return conjunction.involvesMoon ? "moon.circle" : "circle.grid.2x1.fill"
        case .opposition: return "arrow.left.arrow.right.circle"
        case .greatestElongation: return "angle"
        case .earthApsis: return "globe.europe.africa"
        case .season: return "sun.max"
        case .fullMoonSpecial: return "moonphase.full.moon"
        case .lunarEclipse: return "moon.circle.fill"
        case .solarEclipse: return "sun.max.fill"
        }
    }

    // MARK: Dates

    /// Weekday, date and time, such as "Wed, Aug 12 \u{00B7} 02:09".
    static func dayAndTime(_ date: Date, in timeZone: TimeZone) -> String {
        "\(AppFormat.day(date, in: timeZone)) \u{00B7} \(AppFormat.time(date, in: timeZone))"
    }

    /// Weekday, date with year and time, such as "Wednesday, August 12, 2026 at 02:09".
    static func fullDateTime(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .shortened, timeZone: timeZone))
    }

    /// The month a calendar section is titled with, such as "August 2026".
    static func month(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).month(.wide).year())
    }

    /// The zone's usual abbreviation at `date`, such as "CDT".
    static func zoneName(_ timeZone: TimeZone, at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    /// How far off an event is: "Today", "Tomorrow", "In 12 days", "Yesterday", "3 days ago". Days are local days.
    static func countdown(to date: Date, from now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...: return "In \(days) days"
        default: return "\(-days) days ago"
        }
    }

    /// A viewing window, such as "22:10 \u{2013} 04:50". A time never splits from its "PM", and the dash stays with the
    /// time after it, so a line can break only before the dash.
    static func window(_ interval: DateInterval, in timeZone: TimeZone) -> String {
        let start = AppFormat.time(interval.start, in: timeZone).replacingOccurrences(of: " ", with: "\u{00A0}")
        let end = AppFormat.time(interval.end, in: timeZone).replacingOccurrences(of: " ", with: "\u{00A0}")
        return "\(start) \u{2013}\u{00A0}\(end)"
    }

    /// A window as a spoken phrase, such as "10:10 PM to 4:50 AM".
    static func spokenWindow(_ interval: DateInterval, in timeZone: TimeZone) -> String {
        "\(AppFormat.time(interval.start, in: timeZone)) to \(AppFormat.time(interval.end, in: timeZone))"
    }

    // MARK: Visibility

    /// "Visible from here" or "Not visible from here"; `nil` for events that are not seen in the sky.
    static func visibilityText(of entry: EventsEntry) -> String? {
        entry.isVisibleFromHere.map { $0 ? "Visible from here" : "Not visible from here" }
    }

    /// The wording for the Moon's effect on a meteor shower.
    static func moonText(_ interference: EventsMoonInterference) -> String {
        let percent = AppFormat.percent(interference.illuminatedFraction)
        switch interference.level {
        case .moonDown: return "Moon \(percent) lit, but below the horizon at the best time"
        case .little: return "Moon \(percent) lit: little interference"
        case .moderate: return "Moon \(percent) lit: moonlight hides the fainter meteors"
        case .strong: return "Moon \(percent) lit: strong moonlight, only the brighter meteors show"
        }
    }

    /// A short form of `moonText`, for lists.
    static func shortMoonText(_ interference: EventsMoonInterference) -> String {
        switch interference.level {
        case .moonDown: return "Moon down at the best time"
        case .little: return "Little Moon interference"
        case .moderate: return "Some moonlight"
        case .strong: return "Strong moonlight"
        }
    }

    // MARK: Summaries

    /// One line about an event, for lists. `isSouthernHemisphere` words the seasons; `timeZone` the local times.
    static func summary(of entry: EventsEntry, isSouthernHemisphere: Bool, timeZone: TimeZone) -> String {
        let event = entry.event
        switch event.details {
        case .meteorShower(let peak):
            var parts = ["ZHR \(peak.shower.zhr)", "Moon \(AppFormat.percent(peak.moonIlluminatedFraction)) lit"]
            if let altitude = event.visibility?.altitude, altitude > 0 {
                parts.append("radiant \(AngleFormatter.formatDegrees(altitude, decimals: 0)) high")
            }
            return parts.joined(separator: " \u{00B7} ")
        case .conjunction(let conjunction):
            var parts = ["\(AppFormat.separation(conjunction.separation)) apart"]
            if conjunction.topocentric?.isOccultation == true {
                parts.append("occultation from here")
            }
            return parts.joined(separator: " \u{00B7} ")
        case .opposition(let opposition):
            var parts: [String] = []
            if let magnitude = opposition.apparentMagnitude {
                parts.append(AppFormat.magnitude(magnitude))
            }
            parts.append("\(astronomicalUnits(opposition.distanceAU)) away")
            return parts.joined(separator: " \u{00B7} ")
        case .greatestElongation(let elongation):
            var parts = ["\(AngleFormatter.formatDegrees(elongation.angle, decimals: 0)) "
                         + "\(elongation.direction == .east ? "east" : "west") of the Sun",
                         elongation.direction == .east ? "evening sky" : "morning sky"]
            if let magnitude = elongation.apparentMagnitude {
                parts.append(AppFormat.magnitude(magnitude))
            }
            return parts.joined(separator: " \u{00B7} ")
        case .earthApsis(let apsis):
            return "\(astronomicalUnits(apsis.distanceAU, decimals: 3)) from the Sun"
        case .season(let season):
            return seasonSummary(season.kind, isSouthernHemisphere: isSouthernHemisphere)
        case .fullMoonSpecial(let special):
            let distance = special.distanceKilometers.formatted(.number.precision(.fractionLength(0)))
            let size = (special.angularDiameterArcseconds / 60).formatted(.number.precision(.fractionLength(1)))
            return "\(distance) km away \u{00B7} \(size)\u{2032} across"
        case .lunarEclipse(let eclipse):
            return lunarSummary(eclipse)
        case .solarEclipse(let eclipse):
            return solarSummary(eclipse, hasObserver: event.visibility != nil, timeZone: timeZone)
        }
    }

    private static func astronomicalUnits(_ value: Double, decimals: Int = 2) -> String {
        "\(value.formatted(.number.precision(.fractionLength(decimals)))) AU"
    }

    private static func seasonSummary(_ kind: SeasonKind, isSouthernHemisphere: Bool) -> String {
        switch (kind, isSouthernHemisphere) {
        case (.marchEquinox, false), (.septemberEquinox, true): return "Spring begins \u{00B7} day and night nearly equal"
        case (.marchEquinox, true), (.septemberEquinox, false): return "Autumn begins \u{00B7} day and night nearly equal"
        case (.juneSolstice, false), (.decemberSolstice, true): return "Summer begins \u{00B7} longest day"
        case (.juneSolstice, true), (.decemberSolstice, false): return "Winter begins \u{00B7} shortest day"
        }
    }

    private static func lunarSummary(_ eclipse: LunarEclipse) -> String {
        switch eclipse.kind {
        case .penumbral:
            return "Penumbral magnitude \(magnitude(eclipse.penumbralMagnitude))"
        case .partial:
            return "Umbral magnitude \(magnitude(eclipse.umbralMagnitude))"
        case .total:
            return "Umbral magnitude \(magnitude(eclipse.umbralMagnitude)) \u{00B7} totality "
                + AngleFormatter.formatDuration(seconds: eclipse.totalDuration)
        }
    }

    private static func solarSummary(_ eclipse: SolarEclipse, hasObserver: Bool, timeZone: TimeZone) -> String {
        guard hasObserver, let local = eclipse.local else {
            return "\(eclipse.kind.displayName), greatest eclipse \(AppFormat.time(eclipse.greatest, in: timeZone))"
        }
        let maximum = AppFormat.time(local.maximum, in: timeZone)
        switch local.kind {
        case .none:
            return "No eclipse visible from here"
        case .partial:
            return "Partial here: \(AppFormat.percent(local.obscuration)) covered, maximum \(maximum)"
        case .annular:
            return "Annular here: \(AngleFormatter.formatDuration(seconds: local.centralDuration)) at \(maximum)"
        case .total:
            return "Total here: \(AngleFormatter.formatDuration(seconds: local.centralDuration)) at \(maximum)"
        }
    }

    /// An eclipse magnitude with three decimals, such as "1.172".
    static func magnitude(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    // MARK: Spoken

    /// Everything a row shows, as one VoiceOver label.
    static func spokenSummary(of entry: EventsEntry, isSouthernHemisphere: Bool, timeZone: TimeZone) -> String {
        var parts = [entry.event.title, entry.event.date.formatted(Date.FormatStyle(date: .complete, time: .shortened,
                                                                                    timeZone: timeZone))]
        parts.append(summary(of: entry, isSouthernHemisphere: isSouthernHemisphere, timeZone: timeZone))
        if let interference = entry.moonInterference {
            parts.append(moonText(interference))
        }
        if let visibility = visibilityText(of: entry) {
            parts.append(visibility)
        }
        return parts.joined(separator: ", ")
    }
}

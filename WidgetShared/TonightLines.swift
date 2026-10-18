import Foundation
import LodestarKit

/// The words for the "Open Lodestar" state, which has no night to describe.
enum TonightNeedsLocationText {
    static let full = "Open Lodestar to set your location"
    static let short = "Open Lodestar for location"
    static let spoken = "Lodestar. Open the app to set your location."
}

/// The words a widget, a complication or the watch screen shows for one night at one moment, with the spoken
/// versions for VoiceOver. Times follow the user's 12 or 24 hour setting and are shown in the place's time zone.
struct TonightLines: Equatable {
    // Darkness
    /// "Dark tonight", "Dark now", "Dark ended", "Dark all night" or "No full darkness".
    let darkTitle: String
    /// "9:40 PM – 4:12 AM"; `nil` when there is no window to name.
    let darkWindow: String?
    /// One short line for inline slots and corners: "Dark 9:40–4:12".
    let darkInline: String
    /// The same line, shorter still, for a corner: "9:40–4:12"; nil without a window.
    let darkCompactWindow: String?

    // Moon
    /// "Waxing Crescent".
    let moonName: String
    /// "34%".
    let moonPercent: String
    /// "Sets 1:12 AM", "Rises 10:30 PM", "Above horizon" or "Below horizon".
    let moonHorizon: String
    /// An SF Symbol name for the phase.
    let moonSymbol: String
    /// The sunlit fraction, 0...1.
    let moonFraction: Double
    let isSouthernHemisphere: Bool

    // Milky Way core
    /// "11:10 PM – 3:40 AM"; `nil` when the core is not up in the dark.
    let coreWindow: String?
    /// "Moon-free", "Moon up", or "Not up in the dark".
    let coreNote: String

    // Event
    let eventTitle: String?
    let eventSymbol: String?
    /// "Tonight", "Tomorrow", "In 12 days" or a date.
    let eventWhen: String?

    // VoiceOver
    let spokenDark: String
    let spokenMoon: String
    let spokenCore: String
    /// `nil` without an event.
    let spokenEvent: String?

    init(night: TonightNight, now: Date) {
        let zone = night.timeZone
        isSouthernHemisphere = night.isSouthernHemisphere

        switch night.darkness {
        case .none:
            darkTitle = "No full darkness"
            darkWindow = nil
            darkInline = "No full darkness"
            darkCompactWindow = nil
            spokenDark = "No full darkness tonight."
        case .allNight:
            darkTitle = "Dark all night"
            darkWindow = nil
            darkInline = "Dark all night"
            darkCompactWindow = nil
            spokenDark = "Dark all night."
        case .window(let interval, let phase):
            let window = TonightText.window(interval, in: zone)
            let compact = TonightText.compactWindow(interval, in: zone)
            let start = TonightText.time(interval.start, in: zone)
            let end = TonightText.time(interval.end, in: zone)
            darkWindow = window
            darkCompactWindow = compact
            switch phase {
            case .upcoming:
                darkTitle = "Dark tonight"
                darkInline = "Dark \(compact)"
                spokenDark = "Dark from \(start) to \(end)."
            case .inProgress:
                darkTitle = "Dark now"
                darkInline = "Dark until \(TonightText.time(interval.end, in: zone, compact: true))"
                spokenDark = "Dark now, until \(end)."
            case .over:
                darkTitle = "Dark ended"
                darkInline = "Dark ended \(TonightText.time(interval.end, in: zone, compact: true))"
                spokenDark = "Dark ended at \(end)."
            }
        }

        let moon = night.moon
        moonName = moon.phase.displayName
        moonPercent = TonightText.percent(moon.illuminatedFraction)
        moonSymbol = moon.phase.symbolName
        moonFraction = moon.illuminatedFraction
        let spokenPercent = "\(Int((moon.illuminatedFraction * 100).rounded())) percent lit"
        switch moon.horizon {
        case .sets(let date):
            moonHorizon = "Sets \(TonightText.time(date, in: zone))"
            spokenMoon = "Moon, \(moon.phase.displayName.lowercased()), \(spokenPercent), sets at "
                + "\(TonightText.time(date, in: zone))."
        case .rises(let date):
            moonHorizon = "Rises \(TonightText.time(date, in: zone))"
            spokenMoon = "Moon, \(moon.phase.displayName.lowercased()), \(spokenPercent), rises at "
                + "\(TonightText.time(date, in: zone))."
        case .up:
            moonHorizon = "Above horizon"
            spokenMoon = "Moon, \(moon.phase.displayName.lowercased()), \(spokenPercent), above the horizon."
        case .down:
            moonHorizon = "Below horizon"
            spokenMoon = "Moon, \(moon.phase.displayName.lowercased()), \(spokenPercent), below the horizon."
        }

        switch night.core {
        case .none:
            coreWindow = nil
            coreNote = "Not up in the dark"
            spokenCore = "Milky Way core not up in the dark."
        case .window(let interval, let isMoonFree):
            coreWindow = TonightText.window(interval, in: zone)
            coreNote = isMoonFree ? "Moon-free" : "Moon up"
            spokenCore = "Milky Way core up from \(TonightText.time(interval.start, in: zone)) to "
                + "\(TonightText.time(interval.end, in: zone)), \(isMoonFree ? "moon-free" : "with the Moon up")."
        }

        if let event = night.event {
            let when = TonightText.when(of: event, now: now, in: zone)
            eventTitle = event.title
            eventSymbol = event.symbolName
            eventWhen = when
            spokenEvent = "Next event: \(event.title), \(when.lowercased())."
        } else {
            eventTitle = nil
            eventSymbol = nil
            eventWhen = nil
            spokenEvent = nil
        }
    }

    /// What VoiceOver reads: tonight's darkness and Moon, and on request the core and the next event.
    func spoken(includingCore: Bool, includingEvent: Bool) -> String {
        var parts = ["Tonight.", spokenDark, spokenMoon]
        if includingCore { parts.append(spokenCore) }
        if includingEvent, let spokenEvent { parts.append(spokenEvent) }
        return parts.joined(separator: " ")
    }
}

/// Number and time formatting for the lines.
enum TonightText {
    /// "9:40 PM" or "21:40", as the user's clock is set. `compact` leaves out AM and PM: "9:40".
    static func time(_ date: Date, in timeZone: TimeZone, compact: Bool = false) -> String {
        if compact {
            let style = Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .omitted)).minute()
            return date.formatted(style)
        }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// "9:40 PM – 4:12 AM".
    static func window(_ interval: DateInterval, in timeZone: TimeZone) -> String {
        "\(time(interval.start, in: timeZone)) \u{2013} \(time(interval.end, in: timeZone))"
    }

    /// "9:40–4:12".
    static func compactWindow(_ interval: DateInterval, in timeZone: TimeZone) -> String {
        "\(time(interval.start, in: timeZone, compact: true))\u{2013}\(time(interval.end, in: timeZone, compact: true))"
    }

    /// A percentage with no decimals, such as "34%".
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "\u{2014}" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// How far off an event is: "Tonight", "Today", "Tomorrow", "In 12 days", or the date beyond a month.
    static func when(of event: TonightNight.Event, now: Date, in timeZone: TimeZone) -> String {
        if event.isTonight { return "Tonight" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: event.date)).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Tomorrow"
        case 2...30: return "In \(days) days"
        default:
            return event.date.formatted(Date.FormatStyle(timeZone: timeZone).month(.abbreviated).day())
        }
    }
}

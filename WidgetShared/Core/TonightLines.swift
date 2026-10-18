import Foundation
import LodestarKit

/// The words for the "Open Lodestar" state, which has no night to describe.
enum TonightNeedsLocationText {
    static let full = "Open Lodestar to set your location"
    static let short = "Open Lodestar for location"
    static let spoken = "Lodestar. Open the app to set your location."
}

/// One thing a widget shows: the dark windows, the Moon, the Milky Way core or the next event. The same fields, and
/// the same words, as the Android widgets.
struct TonightItem: Equatable {
    let label: String
    /// The label where there is little room.
    let shortLabel: String
    /// A short note beside the label that marks what is happening now ("now", "up", "in 3 days"), or `nil`.
    let badge: String?
    /// A figure at the other end of the label's line (the Moon's lit part), or `nil`.
    let trailing: String?
    /// The main text: a time window, a phase, an event title.
    let value: String
    /// The line under it, or `nil`.
    let detail: String?
    /// A last line for the roomiest layouts, or `nil`.
    let extra: String?
    /// The whole item as VoiceOver says it.
    let spoken: String
}

/// The words a widget, a complication or the watch screen shows for one night at one moment: the four items, short
/// forms for the Lock Screen and the watch, and the spoken versions for VoiceOver. Times follow the user's 12 or 24
/// hour setting and are shown in the place's time zone.
struct TonightLines: Equatable {
    /// The widget's title.
    static let title = "Tonight"
    /// The name of the place the device's own location stands for (the app calls it the same).
    static let placeName = "Current Location"

    let dark: TonightItem
    let moon: TonightItem
    let core: TonightItem
    let event: TonightItem

    // The Moon's drawing
    /// The sunlit fraction, 0...1.
    let moonFraction: Double
    let moonIsWaxing: Bool
    let isSouthernHemisphere: Bool

    // Short forms
    /// One short line for inline slots: "Dark 9:40–4:12", "Dark until 4:12", "Dark ended 4:12".
    let darkInline: String
    /// The first dark window with compact times, "9:40–4:12", for corners; `nil` without one.
    let darkCompactWindow: String?
    /// "34% · Sets 1:12 AM": the Moon's lit part and what it does next.
    let moonCompact: String
    /// "Milky Way 11:10–3:40", or why there is no window.
    let coreCompact: String
    /// The event's title and how far away it is, "Orionids peak · in 3 days"; `nil` without an event.
    let eventCompact: String?
    /// The event's SF Symbol; `nil` without an event.
    let eventSymbol: String?

    init(night: TonightNight, now: Date) {
        let writer = Writer(night: night, now: now)
        dark = writer.dark()
        moon = writer.moon()
        core = writer.core()
        event = writer.event()
        moonFraction = night.moon.illuminatedFraction
        moonIsWaxing = night.moon.isWaxing
        isSouthernHemisphere = night.isSouthernHemisphere
        darkInline = writer.darkInline()
        darkCompactWindow = night.darkness.windows.first.map { TonightText.compactWindow($0, in: night.timeZone) }
        moonCompact = writer.moonCompact()
        coreCompact = writer.coreCompact()
        eventCompact = writer.eventCompact()
        eventSymbol = night.event?.symbolName
    }

    /// What VoiceOver reads: tonight's darkness and Moon, and on request the core and the next event.
    func spoken(includingCore: Bool, includingEvent: Bool) -> String {
        var parts = ["\(Self.title) at \(Self.placeName).", dark.spoken, moon.spoken]
        if includingCore { parts.append(core.spoken) }
        if includingEvent { parts.append(event.spoken) }
        return parts.joined(separator: " ")
    }

    // MARK: Writer

    private struct Writer {
        let night: TonightNight
        let now: Date

        private var zone: TimeZone { night.timeZone }

        private func time(_ date: Date, compact: Bool = false) -> String {
            TonightText.time(date, in: zone, compact: compact)
        }

        private func window(_ interval: DateInterval) -> String {
            TonightText.window(interval, in: zone)
        }

        private func spokenWindows(_ intervals: [DateInterval]) -> String {
            intervals.map { "\(time($0.start)) to \(time($0.end))" }.joined(separator: " and ")
        }

        private func isNow(_ intervals: [DateInterval]) -> Bool {
            intervals.contains { $0.start <= now && now < $0.end }
        }

        // MARK: Darkness

        func dark() -> TonightItem {
            let darkness = night.darkness
            if darkness.windows.isEmpty {
                return TonightItem(label: "Dark", shortLabel: "Dark", badge: nil, trailing: nil,
                                   value: "No full darkness", detail: "The Sun stays above \u{2212}18\u{00B0}", extra: nil,
                                   spoken: "Darkness: there is no full astronomical darkness tonight.")
            }
            let badge = isNow(darkness.windows) ? "now" : nil
            let moonFree = moonFreeText(darkness)
            let value = darkness.isAllNight ? "All night" : darkness.windows.map(window).joined(separator: ", ")
            let spokenWhen = darkness.isAllNight ? "all night" : "from \(spokenWindows(darkness.windows))"
            return TonightItem(
                label: "Dark", shortLabel: "Dark", badge: badge, trailing: nil, value: value,
                detail: "\(TonightText.duration(hours: darkness.hours)) of darkness", extra: moonFree,
                spoken: "Darkness \(badge != nil ? "now, " : "")\(spokenWhen), "
                    + "\(TonightText.spokenDuration(hours: darkness.hours)). \(moonFree).")
        }

        private func moonFreeText(_ darkness: TonightNight.Darkness) -> String {
            let minute = 1.0 / 60
            if darkness.moonFreeHours >= darkness.hours - minute { return "The Moon stays down" }
            if darkness.moonFreeHours <= minute { return "Moonlit all through" }
            return "\(TonightText.duration(hours: darkness.moonFreeHours)) without the Moon"
        }

        /// "Dark 9:40–4:12" before the dark, "Dark until 4:12" during it, "Dark ended 4:12" after it.
        func darkInline() -> String {
            let darkness = night.darkness
            guard let first = darkness.windows.first, let last = darkness.windows.last else { return "No full darkness" }
            if darkness.isAllNight { return "Dark all night" }
            let end = time(last.end, compact: true)
            if now < first.start { return "Dark \(TonightText.compactWindow(first, in: zone))" }
            if now < last.end { return "Dark until \(end)" }
            return "Dark ended \(end)"
        }

        // MARK: Moon

        func moon() -> TonightItem {
            let moon = night.moon
            let phase = moon.phase.displayName
            let percent = TonightText.percent(moon.illuminatedFraction)
            let badge = isUp ? "up" : nil
            return TonightItem(
                label: "Moon", shortLabel: "Moon", badge: badge, trailing: percent, value: phase,
                detail: horizon(moon), extra: nil,
                spoken: "Moon: \(phase), \(percent) lit\(badge != nil ? ", up now" : ""). \(spokenHorizon(moon))")
        }

        private var isUp: Bool { night.moon.upIntervals.contains { $0.start <= now && now < $0.end } }

        private func horizon(_ moon: TonightNight.Moon) -> String {
            switch moon.circumstance {
            case .alwaysUp: return "Up all night"
            case .alwaysDown: return "Down all night"
            case .normal:
                switch (moon.rise, moon.set) {
                case let (rise?, set?) where set < rise: return "Sets \(time(set)) \u{00B7} rises \(time(rise))"
                case let (rise?, set?): return "Rises \(time(rise)) \u{00B7} sets \(time(set))"
                case let (rise?, nil): return "Rises \(time(rise))"
                case let (nil, set?): return "Sets \(time(set))"
                case (nil, nil): return "Up all night"
                }
            }
        }

        private func spokenHorizon(_ moon: TonightNight.Moon) -> String {
            switch moon.circumstance {
            case .alwaysUp: return "It is up all night."
            case .alwaysDown: return "It is down all night."
            case .normal:
                switch (moon.rise, moon.set) {
                case let (rise?, set?) where set < rise: return "It sets at \(time(set)) and rises at \(time(rise))."
                case let (rise?, set?): return "It rises at \(time(rise)) and sets at \(time(set))."
                case let (rise?, nil): return "It rises at \(time(rise))."
                case let (nil, set?): return "It sets at \(time(set))."
                case (nil, nil): return "It is up all night."
                }
            }
        }

        /// "34% · Sets 1:12 AM": what the Moon does next, which suits a narrow slot better than the whole night.
        func moonCompact() -> String {
            let moon = night.moon
            let percent = TonightText.percent(moon.illuminatedFraction)
            let next = [moon.rise.map { (date: $0, text: "Rises") }, moon.set.map { (date: $0, text: "Sets") }]
                .compactMap { $0 }
                .filter { $0.date > now }
                .min { $0.date < $1.date }
            if let next { return "\(percent) \u{00B7} \(next.text) \(time(next.date))" }
            return "\(percent) \u{00B7} \(isUp ? "Above horizon" : "Below horizon")"
        }

        // MARK: Milky Way core

        func core() -> TonightItem {
            let core = night.core
            let label = "Milky Way core"
            let short = "Milky Way"
            if !core.hasDarkness {
                return TonightItem(label: label, shortLabel: short, badge: nil, trailing: nil,
                                   value: "No darkness", detail: "Too bright to photograph", extra: nil,
                                   spoken: "Milky Way core: it cannot be photographed, because there is no full darkness tonight.")
            }
            if core.windows.isEmpty {
                return TonightItem(label: label, shortLabel: short, badge: nil, trailing: nil,
                                   value: "Low in the dark", detail: "Below 10\u{00B0} while it is dark", extra: nil,
                                   spoken: "Milky Way core: it stays below 10 degrees while it is dark.")
            }
            let badge = isNow(core.windows) ? "now" : nil
            return TonightItem(
                label: label, shortLabel: short, badge: badge, trailing: nil,
                value: core.windows.map(window).joined(separator: ", "), detail: best(core), extra: nil,
                spoken: "Milky Way core visible \(badge != nil ? "now, " : "")from \(spokenWindows(core.windows))."
                    + (spokenBest(core).map { " \($0)" } ?? ""))
        }

        /// "Best 2:40 AM · 28° SE".
        private func best(_ core: TonightNight.Core) -> String? {
            guard let bestTime = core.bestTime else { return nil }
            guard let altitude = core.maxAltitude else { return "Best \(time(bestTime))" }
            let height = AngleFormatter.formatDegrees(altitude, decimals: 0)
            guard let azimuth = core.bestAzimuth else { return "Best \(time(bestTime)) \u{00B7} \(height)" }
            return "Best \(time(bestTime)) \u{00B7} \(height) \(AngleFormatter.compassPoint(azimuth: azimuth).abbreviation)"
        }

        private func spokenBest(_ core: TonightNight.Core) -> String? {
            guard let bestTime = core.bestTime else { return nil }
            guard let altitude = core.maxAltitude else { return "Best at \(time(bestTime))." }
            let height = AngleFormatter.formatDegrees(altitude, decimals: 0)
            guard let azimuth = core.bestAzimuth else { return "Best at \(time(bestTime)), \(height) up." }
            let direction = AngleFormatter.compassPoint(azimuth: azimuth).fullName.lowercased()
            return "Best at \(time(bestTime)), \(height) up in the \(direction)."
        }

        /// "Milky Way 11:10–3:40", or "Milky Way: low in the dark".
        func coreCompact() -> String {
            let core = night.core
            guard core.hasDarkness, !core.windows.isEmpty else {
                return "Milky Way: \(self.core().value.lowercased())"
            }
            return "Milky Way " + core.windows.map { TonightText.compactWindow($0, in: zone) }.joined(separator: ", ")
        }

        // MARK: Event

        func event() -> TonightItem {
            let label = "Next event"
            guard let event = night.event else {
                return TonightItem(label: label, shortLabel: "Next", badge: nil, trailing: nil,
                                   value: "Nothing in view", detail: "No events are coming up", extra: nil,
                                   spoken: "Next event: none is coming up.")
            }
            let extra = [
                event.showerRate.map { "Up to \($0) an hour" },
                event.bestWindow.map { "Best view \(window($0))" },
                event.isVisibleFromHere == false ? "Not visible from here" : nil,
            ].compactMap { $0 }.joined(separator: " \u{00B7} ")
            let day = TonightText.day(event.date, in: zone)
            return TonightItem(
                label: label, shortLabel: "Next", badge: badge(for: event), trailing: nil, value: event.title,
                detail: "\(day) \u{00B7} \(time(event.date))", extra: extra.isEmpty ? nil : extra,
                spoken: "Next event: \(event.title), \(day) at \(time(event.date))."
                    + (extra.isEmpty ? "" : " \(extra)."))
        }

        /// How far away the event is, "in 3 days"; `nil` once it has passed.
        private func badge(for event: TonightNight.Event) -> String? {
            let distance = TonightText.distance(to: event.date, from: now, in: zone)
            guard distance != "Passed" else { return nil }
            return distance.prefix(1).lowercased() + distance.dropFirst()
        }

        func eventCompact() -> String? {
            guard let event = night.event else { return nil }
            guard let badge = badge(for: event) else { return event.title }
            return "\(event.title) \u{00B7} \(badge)"
        }
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

    /// "Sat, Nov 14".
    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, timeZone: timeZone)
        style = style.weekday(.abbreviated).month(.abbreviated).day()
        return date.formatted(style)
    }

    /// A percentage with no decimals, such as "34%".
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "\u{2014}" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// A length of time in hours and minutes, such as "6h 32m" or "45m".
    static func duration(hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0m" }
        let minutes = Int((hours * 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let remainder = minutes % 60
        return "\(minutes / 60)h \(remainder < 10 ? "0" : "")\(remainder)m"
    }

    /// A length of time for VoiceOver: "7 hours 9 minutes".
    static func spokenDuration(hours: Double) -> String {
        let minutes = hours.isFinite && hours > 0 ? Int((hours * 60).rounded()) : 0
        let whole = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if whole > 0 { parts.append(whole == 1 ? "1 hour" : "\(whole) hours") }
        if rest > 0 || whole == 0 { parts.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return parts.joined(separator: " ")
    }

    /// How far away `date` is, by local days: "Today", "Tomorrow", "In 5 days", "In 3 weeks", "In 4 months", and
    /// "Passed" for an earlier day (the same wording as the Android widgets).
    static func distance(to date: Date, from now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return date >= now || days == 0 ? "Today" : "Passed"
        case 1: return "Tomorrow"
        case ...14: return "In \(days) days"
        case ..<90: return "In \(days / 7) weeks"
        default: return "In \(days / 30) months"
        }
    }
}

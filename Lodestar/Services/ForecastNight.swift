import Foundation

/// One stretch of the night with its cloud cover in percent: the time from a forecast time to the next one, cut to the
/// night.
struct CloudSlot: Sendable, Equatable {
    let start: Date
    let end: Date
    let total: Double
    let low: Double
    let medium: Double
    let high: Double

    /// The length in seconds.
    var seconds: TimeInterval { end.timeIntervalSince(start) }
}

/// What the night's cloud forecast says, in numbers and in words. Pure.
enum ForecastNight {
    /// A slot with less total cloud than this (percent) counts as clear.
    static let clearBelow = 30.0
    /// A night with at least this much cloud on average (percent) counts as cloudy.
    static let cloudyFrom = 70.0
    /// The shortest clear stretch worth naming, in seconds (shorter nights name half their length).
    static let minimumClearSpell: TimeInterval = 2 * 3600

    /// The forecast's slots that overlap `night`, cut to it, in time order. Hourly forecast times give one-hour slots; the
    /// six-hourly times further ahead give six-hour slots. Empty when the forecast does not reach the night.
    static func slots(_ forecast: CloudForecast, night: DateInterval) -> [CloudSlot] {
        guard night.end > night.start else { return [] }
        var slots: [CloudSlot] = []
        let hours = forecast.hours
        for (index, entry) in hours.enumerated() {
            let next = index + 1 < hours.count ? hours[index + 1].time : entry.time.addingTimeInterval(3600)
            let start = max(entry.time, night.start)
            let end = min(next, night.end)
            guard end > start else { continue }
            slots.append(CloudSlot(start: start, end: end, total: entry.total, low: entry.low, medium: entry.medium,
                                   high: entry.high))
        }
        return slots
    }

    /// The time-weighted mean total cloud of `slots` in percent.
    static func meanTotal(_ slots: [CloudSlot]) -> Double {
        let seconds = slots.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return 0 }
        return slots.reduce(0) { $0 + $1.total * $1.seconds } / seconds
    }

    /// A stretch of clear sky.
    struct ClearSpell: Equatable {
        let start: Date
        let end: Date

        var seconds: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The unbroken clear stretches of `slots` (total cloud under `clearBelow`), in time order.
    static func clearSpells(_ slots: [CloudSlot]) -> [ClearSpell] {
        var spells: [ClearSpell] = []
        var start: Date?
        var end: Date?
        for slot in slots {
            let isClear = slot.total < clearBelow
            if isClear, start != nil, let open = end, slot.start == open {
                end = slot.end
                continue
            }
            if let start, let end { spells.append(ClearSpell(start: start, end: end)) }
            start = isClear ? slot.start : nil
            end = isClear ? slot.end : nil
        }
        if let start, let end { spells.append(ClearSpell(start: start, end: end)) }
        return spells
    }

    /// The clear spells in a few words, for example "Mostly clear after 23:00", "Mostly clear until 01:00", "Clear from
    /// 22:00 to 02:00", "Clear all night", "Cloudy all night" or "No long clear spell". `timeText` formats a time of
    /// day. `nil` for no slots.
    static func summary(_ slots: [CloudSlot], timeText: (Date) -> String) -> String? {
        guard let first = slots.first, let last = slots.last else { return nil }
        let total = slots.reduce(0) { $0 + $1.seconds }
        let spells = clearSpells(slots)
        let clearSeconds = spells.reduce(0) { $0 + $1.seconds }
        if clearSeconds >= 0.9 * total { return "Clear all night" }
        guard let longest = spells.max(by: { $0.seconds < $1.seconds }),
              longest.seconds >= min(minimumClearSpell, total / 2) else {
            return meanTotal(slots) >= cloudyFrom ? "Cloudy all night" : "No long clear spell"
        }
        if longest.end == last.end { return "Mostly clear after \(timeText(longest.start))" }
        if longest.start == first.start { return "Mostly clear until \(timeText(longest.end))" }
        return "Clear from \(timeText(longest.start)) to \(timeText(longest.end))"
    }

    /// The sentence a screen reader reads for the cloud strip: the span, the extremes of the total cloud and the
    /// `summary`. `nil` for no slots.
    static func spokenSummary(_ slots: [CloudSlot], timeText: (Date) -> String) -> String? {
        guard let first = slots.first, let last = slots.last,
              let clearest = slots.min(by: { $0.total < $1.total }),
              let cloudiest = slots.max(by: { $0.total < $1.total }) else { return nil }
        var parts = [
            "Cloud cover from \(timeText(first.start)) to \(timeText(last.end)).",
            "Total cloud runs from \(Int(clearest.total)) percent at \(timeText(clearest.start)) "
                + "to \(Int(cloudiest.total)) percent at \(timeText(cloudiest.start)).",
        ]
        if let text = summary(slots, timeText: timeText) { parts.append("\(text).") }
        return parts.joined(separator: " ")
    }
}

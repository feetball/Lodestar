import Foundation

/// One stretch of the night with its cloud cover in percent and the weather of its forecast time (see `CloudHour`): the
/// time from a forecast time to the next one, cut to the night.
struct CloudSlot: Sendable, Equatable {
    let start: Date
    let end: Date
    let total: Double
    let low: Double
    let medium: Double
    let high: Double
    let temperature: Double?
    let dewPoint: Double?
    let humidity: Double?
    let windSpeed: Double?
    let windGust: Double?
    let windFromDirection: Double?
    let fog: Double?

    init(start: Date, end: Date, total: Double, low: Double, medium: Double, high: Double, temperature: Double? = nil,
         dewPoint: Double? = nil, humidity: Double? = nil, windSpeed: Double? = nil, windGust: Double? = nil,
         windFromDirection: Double? = nil, fog: Double? = nil) {
        self.start = start
        self.end = end
        self.total = total
        self.low = low
        self.medium = medium
        self.high = high
        self.temperature = temperature
        self.dewPoint = dewPoint
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windFromDirection = windFromDirection
        self.fog = fog
    }

    /// The length in seconds.
    var seconds: TimeInterval { end.timeIntervalSince(start) }

    /// Air temperature minus dew point in °C, never below 0; `nil` when either is missing.
    var dewPointSpread: Double? { ForecastNight.dewPointSpread(temperature: temperature, dewPoint: dewPoint) }
}

/// Lens fogging: the dew-point spread (air temperature minus dew point) is below `ForecastNight.dewSpreadBelow` °C.
struct DewWarning: Sendable, Equatable {
    /// The start of the first slot of the night with such a spread.
    let from: Date
    /// The smallest spread of the night in °C.
    let minimumSpread: Double

    /// The spread gets below `ForecastNight.dewVeryLikelyBelow` °C.
    var isVeryLikely: Bool { minimumSpread < ForecastNight.dewVeryLikelyBelow }
}

/// How much the wind matters for a long exposure, by the strongest sustained wind of the night.
enum WindLevel: String, Sendable {
    /// Under `ForecastNight.windBreezyFrom` m/s.
    case calm
    /// From `ForecastNight.windBreezyFrom` m/s: long exposures may shake.
    case breezy
    /// From `ForecastNight.windWindyFrom` m/s: weigh the tripod down.
    case windy
    /// From `ForecastNight.windStrongFrom` m/s.
    case strong
}

/// The wind of the night.
struct WindSummary: Sendable, Equatable {
    /// The strongest sustained wind in m/s.
    let maximum: Double
    /// The strongest gust in m/s, when the forecast has gusts for the night.
    let gust: Double?
    /// Where the strongest wind blows from, in degrees clockwise from north, when known.
    let fromDirection: Double?

    /// The level of `maximum`.
    var level: WindLevel {
        if maximum >= ForecastNight.windStrongFrom { return .strong }
        if maximum >= ForecastNight.windWindyFrom { return .windy }
        if maximum >= ForecastNight.windBreezyFrom { return .breezy }
        return .calm
    }
}

/// Fog likely during the night: the forecast times with a fog area fraction of at least `ForecastNight.fogFrom` percent.
struct FogSummary: Sendable, Equatable {
    /// The start of the first such slot.
    let from: Date
    /// The time of the night they cover together.
    let seconds: TimeInterval
}

/// The air temperature range of the night in °C.
struct TemperatureRange: Sendable, Equatable {
    let minimum: Double
    let maximum: Double
}

/// One row of the night's hourly table: the forecast of one slot (`time` is the start of the slot).
struct NightHour: Sendable, Equatable {
    let time: Date
    let cloud: Double
    let temperature: Double?
    let dewPointSpread: Double?
    let windSpeed: Double?
    let windGust: Double?
    let humidity: Double?
}

/// What the forecast says about the night besides the clouds. Every part is `nil` (or empty) where the forecast has no data.
struct NightConditions: Sendable, Equatable {
    let dew: DewWarning?
    let wind: WindSummary?
    let fog: FogSummary?
    let temperature: TemperatureRange?
    let hourly: [NightHour]
}

/// What the night's cloud forecast says, in numbers and in words. Pure.
enum ForecastNight {
    /// A slot with less total cloud than this (percent) counts as clear.
    static let clearBelow = 30.0
    /// A night with at least this much cloud on average (percent) counts as cloudy.
    static let cloudyFrom = 70.0
    /// The shortest clear stretch worth naming, in seconds (shorter nights name half their length).
    static let minimumClearSpell: TimeInterval = 2 * 3600
    /// The dew-point spread (°C) below which dew forms on a lens.
    static let dewSpreadBelow = 2.0
    /// A spread (°C) below this makes lens fogging very likely.
    static let dewVeryLikelyBelow = 1.0
    /// The sustained wind (m/s) from which long exposures may shake.
    static let windBreezyFrom = 5.0
    /// The sustained wind (m/s) from which the tripod needs weight.
    static let windWindyFrom = 8.0
    /// The sustained wind (m/s) that counts as strong.
    static let windStrongFrom = 12.0
    /// A fog area fraction (percent) from which a slot counts as foggy.
    static let fogFrom = 50.0

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
                                   high: entry.high, temperature: entry.temperature, dewPoint: entry.dewPoint,
                                   humidity: entry.humidity, windSpeed: entry.windSpeed, windGust: entry.windGust,
                                   windFromDirection: entry.windFromDirection, fog: entry.fog))
        }
        return slots
    }

    /// The time-weighted mean total cloud of `slots` in percent.
    static func meanTotal(_ slots: [CloudSlot]) -> Double {
        let seconds = slots.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return 0 }
        return slots.reduce(0) { $0 + $1.total * $1.seconds } / seconds
    }

    /// Air temperature minus dew point in °C, never below 0 (a dew point above the air is rounding); `nil` when either is `nil`.
    static func dewPointSpread(temperature: Double?, dewPoint: Double?) -> Double? {
        guard let temperature, let dewPoint else { return nil }
        return max(temperature - dewPoint, 0)
    }

    /// Lens fogging in `slots`: from the first slot whose dew-point spread is below `dewSpreadBelow` °C, with the
    /// smallest spread of the night. `nil` when the spread stays at `dewSpreadBelow` °C or more, or the forecast has no
    /// dew point.
    static func dew(_ slots: [CloudSlot]) -> DewWarning? {
        var from: Date?
        var minimum = Double.infinity
        for slot in slots {
            guard let spread = slot.dewPointSpread else { continue }
            if spread < dewSpreadBelow, from == nil { from = slot.start }
            if spread < minimum { minimum = spread }
        }
        guard let from else { return nil }
        return DewWarning(from: from, minimumSpread: minimum)
    }

    /// The wind in `slots`: the strongest sustained wind (with where it blows from) and the strongest gust. `nil` when
    /// the forecast has no wind speed for the night; the gust is `nil` when it has no gusts.
    static func wind(_ slots: [CloudSlot]) -> WindSummary? {
        var maximum: Double?
        var direction: Double?
        var gust: Double?
        for slot in slots {
            if let speed = slot.windSpeed, speed > (maximum ?? -.infinity) {
                maximum = speed
                direction = slot.windFromDirection
            }
            if let slotGust = slot.windGust, slotGust > (gust ?? -.infinity) { gust = slotGust }
        }
        guard let maximum else { return nil }
        return WindSummary(maximum: maximum, gust: gust, fromDirection: direction)
    }

    /// The fog in `slots`: the slots with a fog area fraction of at least `fogFrom` percent. `nil` when there are none.
    static func fog(_ slots: [CloudSlot]) -> FogSummary? {
        var from: Date?
        var seconds: TimeInterval = 0
        for slot in slots {
            guard let fog = slot.fog, fog >= fogFrom else { continue }
            if from == nil { from = slot.start }
            seconds += slot.seconds
        }
        guard let from else { return nil }
        return FogSummary(from: from, seconds: seconds)
    }

    /// The lowest and highest air temperature in `slots`. `nil` when the forecast has no temperature for the night.
    static func temperature(_ slots: [CloudSlot]) -> TemperatureRange? {
        var minimum: Double?
        var maximum: Double?
        for slot in slots {
            guard let value = slot.temperature else { continue }
            if value < (minimum ?? .infinity) { minimum = value }
            if value > (maximum ?? -.infinity) { maximum = value }
        }
        guard let minimum, let maximum else { return nil }
        return TemperatureRange(minimum: minimum, maximum: maximum)
    }

    /// One row per slot of `slots`, for the hourly table.
    static func hourly(_ slots: [CloudSlot]) -> [NightHour] {
        slots.map {
            NightHour(time: $0.start, cloud: $0.total, temperature: $0.temperature, dewPointSpread: $0.dewPointSpread,
                      windSpeed: $0.windSpeed, windGust: $0.windGust, humidity: $0.humidity)
        }
    }

    /// Everything the forecast says about the night in `slots` besides the clouds.
    static func conditions(_ slots: [CloudSlot]) -> NightConditions {
        NightConditions(dew: dew(slots), wind: wind(slots), fog: fog(slots), temperature: temperature(slots),
                        hourly: hourly(slots))
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

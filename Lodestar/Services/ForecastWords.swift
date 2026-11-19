import Foundation
import LodestarKit

/// What a chip under the cloud strip is about.
enum ForecastChipKind: String, Sendable {
    case dew
    case wind
    case fog
    case temperature
}

/// One chip of the forecast card: `text` is what it shows, `spoken` what VoiceOver says, `isWarning` whether it is
/// drawn in the warning tone.
struct ForecastChip: Sendable, Equatable {
    let kind: ForecastChipKind
    let text: String
    let spoken: String
    let isWarning: Bool
}

/// The words of the night's dew, wind, fog and temperature on the forecast card. The Android app has the same texts.
/// `timeText` formats a time of day in the observer's time zone.
enum ForecastWords {
    /// Shown for a value the forecast does not have.
    static let missing = "—"

    static let breezy = "Breezy: long exposures may shake"
    static let windy = "Windy: weigh the tripod down"
    static let strong = "Strong wind: expect shaky frames"

    /// "Lens fogging likely from 23:40", "very likely" when the spread gets under `ForecastNight.dewVeryLikelyBelow` °C.
    static func dewHint(_ warning: DewWarning, timeText: (Date) -> String) -> String {
        "Lens fogging \(warning.isVeryLikely ? "very likely" : "likely") from \(timeText(warning.from))"
    }

    /// The advice for `level`; `nil` for a calm night.
    static func windHint(_ level: WindLevel) -> String? {
        switch level {
        case .calm: return nil
        case .breezy: return breezy
        case .windy: return windy
        case .strong: return strong
        }
    }

    /// The one line for the most important warning of the night: the dew first, then the wind. `nil` when there is none.
    static func hint(_ conditions: NightConditions, timeText: (Date) -> String) -> String? {
        if let dew = conditions.dew { return dewHint(dew, timeText: timeText) }
        return conditions.wind.flatMap { windHint($0.level) }
    }

    /// The chips for `conditions` in the order dew, wind, fog, temperature; only those the forecast has something for.
    static func chips(_ conditions: NightConditions, system: ForecastUnitSystem, timeText: (Date) -> String) -> [ForecastChip] {
        var chips: [ForecastChip] = []
        if let dew = conditions.dew {
            let spoken = "\(dewHint(dew, timeText: timeText)). The air gets within "
                + "\(ForecastUnits.spokenDifference(dew.minimumSpread, system)) of the dew point."
            chips.append(ForecastChip(kind: .dew, text: "Dew from \(timeText(dew.from))", spoken: spoken, isWarning: true))
        }
        if let wind = conditions.wind { chips.append(windChip(wind, system: system)) }
        if let fog = conditions.fog {
            let hours = max(1, Int((fog.seconds / 3600).rounded()))
            let spoken = "Fog expected for about \(hours) \(hours == 1 ? "hour" : "hours") from \(timeText(fog.from))."
            chips.append(ForecastChip(kind: .fog, text: "Fog from \(timeText(fog.from))", spoken: spoken, isWarning: true))
        }
        if let range = conditions.temperature {
            chips.append(ForecastChip(
                kind: .temperature,
                text: ForecastUnits.temperatureRange(range.minimum, range.maximum, system),
                spoken: "Air temperature \(ForecastUnits.spokenTemperatureRange(range.minimum, range.maximum, system)).",
                isWarning: false))
        }
        return chips
    }

    private static func windChip(_ wind: WindSummary, system: ForecastUnitSystem) -> ForecastChip {
        let speed = ForecastUnits.speedValue(wind.maximum, system)
        let gust = wind.gust.map { ForecastUnits.speedValue($0, system) }.flatMap { $0 > speed ? $0 : nil }
        let text = "Wind \(ForecastUnits.speed(wind.maximum, system))" + (gust.map { ", gusts \($0)" } ?? "")
        let direction = wind.fromDirection.map { " from \(AngleFormatter.compassPoint(azimuth: $0).abbreviation)" } ?? ""
        let spoken = "Wind up to \(ForecastUnits.spokenSpeed(wind.maximum, system))\(direction)"
            + (gust.map { ", gusts up to \($0)" } ?? "") + "."
            + (windHint(wind.level).map { " \($0)." } ?? "")
        return ForecastChip(kind: .wind, text: text, spoken: spoken, isWarning: wind.level != .calm)
    }

    // MARK: The hourly table

    /// The column headings of the hourly table: time, cloud, temperature, dew gap, wind.
    static func hourlyHeaders(_ system: ForecastUnitSystem) -> [String] {
        ["Time", "Cloud", "Temp (\(ForecastUnits.temperatureUnit(system)))",
         "Dew gap (\(ForecastUnits.temperatureUnit(system)))", "Wind (\(ForecastUnits.speedUnit(system)))"]
    }

    /// The cells of `hour` under `hourlyHeaders`: the time, the cloud in percent and the numbers without their units.
    static func hourlyCells(_ hour: NightHour, system: ForecastUnitSystem, timeText: (Date) -> String) -> [String] {
        [
            timeText(hour.time),
            "\(Int(hour.cloud.rounded()))%",
            hour.temperature.map { ForecastUnits.signed(ForecastUnits.temperatureValue($0, system)) } ?? missing,
            hour.dewPointSpread.map { ForecastUnits.differenceValue($0, system) } ?? missing,
            hour.windSpeed.map { String(ForecastUnits.speedValue($0, system)) } ?? missing,
        ]
    }

    /// What VoiceOver says for `hour`: its time and the values the forecast has for it.
    static func hourlySpoken(_ hour: NightHour, system: ForecastUnitSystem, timeText: (Date) -> String) -> String {
        var parts = ["\(timeText(hour.time)).", "Cloud \(Int(hour.cloud.rounded())) percent."]
        if let value = hour.temperature { parts.append("Temperature \(ForecastUnits.spokenTemperature(value, system)).") }
        if let value = hour.dewPointSpread { parts.append("Dew gap \(ForecastUnits.spokenDifference(value, system)).") }
        if let value = hour.windSpeed { parts.append("Wind \(ForecastUnits.spokenSpeed(value, system)).") }
        if let value = hour.humidity { parts.append("Humidity \(Int(value.rounded())) percent.") }
        return parts.joined(separator: " ")
    }
}

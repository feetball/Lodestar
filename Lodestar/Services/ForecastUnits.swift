import Foundation

/// The units the forecast values are shown in: metric (°C, m/s) or US customary (°F, mph).
enum ForecastUnitSystem: String, Sendable {
    /// Degrees Celsius and metres per second.
    case metric
    /// Degrees Fahrenheit and miles per hour, for the regions that use US customary units.
    case us
}

/// Temperature and wind speed as text in a `ForecastUnitSystem`. The forecast is always in °C and m/s; whole degrees and
/// whole speeds are rounded half away from zero, spreads show one decimal. The Android app has the same texts.
enum ForecastUnits {
    /// Miles per hour in one metre per second.
    static let milesPerHourPerMetrePerSecond = 3600.0 / 1609.344

    /// The minus sign of a negative number.
    static let minus = "\u{2212}"

    private static let space = "\u{00A0}"

    /// The system of `locale`'s region (CLDR): US customary where the region uses it, metric everywhere else.
    static func system(for locale: Locale) -> ForecastUnitSystem {
        locale.measurementSystem == .us ? .us : .metric
    }

    /// "°C" or "°F".
    static func temperatureUnit(_ system: ForecastUnitSystem) -> String { system == .us ? "°F" : "°C" }

    /// "m/s" or "mph".
    static func speedUnit(_ system: ForecastUnitSystem) -> String { system == .us ? "mph" : "m/s" }

    /// `celsius` in whole degrees of `system`.
    static func temperatureValue(_ celsius: Double, _ system: ForecastUnitSystem) -> Int {
        let degrees = system == .us ? celsius * 9.0 / 5.0 + 32.0 : celsius
        return Int(degrees.rounded())
    }

    /// `metresPerSecond` in whole units of `system`.
    static func speedValue(_ metresPerSecond: Double, _ system: ForecastUnitSystem) -> Int {
        let speed = system == .us ? metresPerSecond * milesPerHourPerMetrePerSecond : metresPerSecond
        return Int(speed.rounded())
    }

    /// A whole number with a real minus sign: "−3", "0", "4".
    static func signed(_ value: Int) -> String { value < 0 ? "\(minus)\(-value)" : "\(value)" }

    /// A temperature such as "−3 °C" (a no-break space before the unit).
    static func temperature(_ celsius: Double, _ system: ForecastUnitSystem) -> String {
        "\(signed(temperatureValue(celsius, system)))\(space)\(temperatureUnit(system))"
    }

    /// A temperature range such as "−3…4 °C"; one temperature, "3 °C", when both ends round to the same.
    static func temperatureRange(_ minimum: Double, _ maximum: Double, _ system: ForecastUnitSystem) -> String {
        let low = temperatureValue(minimum, system)
        let high = temperatureValue(maximum, system)
        if low == high { return temperature(minimum, system) }
        return "\(signed(low))…\(signed(high))\(space)\(temperatureUnit(system))"
    }

    /// A wind speed such as "6 m/s" or "13 mph".
    static func speed(_ metresPerSecond: Double, _ system: ForecastUnitSystem) -> String {
        "\(speedValue(metresPerSecond, system))\(space)\(speedUnit(system))"
    }

    /// A temperature difference of `celsius` with one decimal: "1.4" (the number only; a difference has no offset).
    static func differenceValue(_ celsius: Double, _ system: ForecastUnitSystem) -> String {
        String(format: "%.1f", system == .us ? celsius * 9.0 / 5.0 : celsius)
    }

    /// A temperature difference with its unit: "1.4 °C".
    static func difference(_ celsius: Double, _ system: ForecastUnitSystem) -> String {
        "\(differenceValue(celsius, system))\(space)\(temperatureUnit(system))"
    }

    // MARK: Spoken

    /// "minus 3 degrees Celsius".
    static func spokenTemperature(_ celsius: Double, _ system: ForecastUnitSystem) -> String {
        let value = temperatureValue(celsius, system)
        return "\(spokenNumber(value)) \(spokenTemperatureUnit(system, singular: value == 1 || value == -1))"
    }

    /// "from minus 3 to 4 degrees Celsius"; one temperature, "3 degrees Celsius", when both ends round to the same.
    static func spokenTemperatureRange(_ minimum: Double, _ maximum: Double, _ system: ForecastUnitSystem) -> String {
        let low = temperatureValue(minimum, system)
        let high = temperatureValue(maximum, system)
        if low == high { return spokenTemperature(minimum, system) }
        return "from \(spokenNumber(low)) to \(spokenNumber(high)) \(spokenTemperatureUnit(system, singular: false))"
    }

    /// "6 metres per second" or "13 miles per hour" ("1 metre per second", "1 mile per hour").
    static func spokenSpeed(_ metresPerSecond: Double, _ system: ForecastUnitSystem) -> String {
        let value = speedValue(metresPerSecond, system)
        let unit = system == .us ? "mile" : "metre"
        return "\(value) \(value == 1 ? unit : "\(unit)s") per \(system == .us ? "hour" : "second")"
    }

    /// "1.4 degrees Celsius".
    static func spokenDifference(_ celsius: Double, _ system: ForecastUnitSystem) -> String {
        "\(differenceValue(celsius, system)) \(spokenTemperatureUnit(system, singular: false))"
    }

    private static func spokenTemperatureUnit(_ system: ForecastUnitSystem, singular: Bool) -> String {
        let degrees = singular ? "degree" : "degrees"
        return system == .us ? "\(degrees) Fahrenheit" : "\(degrees) Celsius"
    }

    private static func spokenNumber(_ value: Int) -> String { value < 0 ? "minus \(-value)" : "\(value)" }
}

import Foundation

/// Cloud cover at one forecast time, in percent of the sky (0 to 100): the whole sky and the low, medium and high
/// layers. MET Norway gives hourly values for about the first two and a half days, then every six hours.
struct CloudHour: Sendable, Equatable {
    let time: Date
    let total: Double
    let low: Double
    let medium: Double
    let high: Double
}

/// MET Norway's cloud forecast for one grid point.
struct CloudForecast: Sendable, Equatable {
    /// When the forecast was produced (`updated_at`).
    let issuedAt: Date
    /// The grid point's latitude, as MET Norway reports it (the request's rounded value).
    let latitude: Double?
    /// The grid point's longitude.
    let longitude: Double?
    /// The forecast times in ascending order.
    let hours: [CloudHour]

    /// The last time the forecast covers.
    var end: Date? { hours.last?.time }

    /// Tells which request this forecast answers, as `OnlineCoordinates.key` does; `nil` when the answer names no place.
    var key: String? {
        guard let latitude, let longitude else { return nil }
        return OnlineCoordinates.key(latitude: latitude, longitude: longitude)
    }
}

/// Reads the answer of MET Norway's Locationforecast 2.0 (`complete` or `compact`).
enum ForecastParser {
    /// The fewest forecast times a usable answer has.
    static let minimumHours = 6

    /// Throws `OnlineDataError` when `data` is not a forecast with cloud values.
    static func parse(_ data: Data) throws -> OnlineParsed<CloudForecast> {
        OnlineParsed(value: try parseForecast(data))
    }

    /// The forecast in `data`. Throws `OnlineDataError` when there is none.
    static func parseForecast(_ data: Data) throws -> CloudForecast {
        let element: Any
        do {
            element = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw OnlineDataError("Not JSON: \(error.localizedDescription)")
        }
        guard let root = element as? [String: Any] else { throw OnlineDataError("Not a forecast.") }
        guard let properties = root["properties"] as? [String: Any] else { throw OnlineDataError("No properties.") }
        guard let series = properties["timeseries"] as? [Any] else { throw OnlineDataError("No time series.") }
        guard let issued = ((properties["meta"] as? [String: Any])?["updated_at"] as? String).flatMap(date(from:)) else {
            throw OnlineDataError("No issue time.")
        }
        var hours: [CloudHour] = []
        hours.reserveCapacity(series.count)
        for entry in series {
            guard let item = entry as? [String: Any], let time = (item["time"] as? String).flatMap(date(from:)),
                  let details = (((item["data"] as? [String: Any])?["instant"] as? [String: Any])?["details"]) as? [String: Any],
                  let total = percent(details, "cloud_area_fraction") else { continue }
            hours.append(CloudHour(time: time, total: total,
                                   low: percent(details, "cloud_area_fraction_low") ?? 0,
                                   medium: percent(details, "cloud_area_fraction_medium") ?? 0,
                                   high: percent(details, "cloud_area_fraction_high") ?? 0))
        }
        guard hours.count >= minimumHours else { throw OnlineDataError("Too few forecast times.") }
        for index in 1..<hours.count where hours[index].time <= hours[index - 1].time {
            throw OnlineDataError("Forecast times out of order.")
        }
        let coordinates = ((root["geometry"] as? [String: Any])?["coordinates"] as? [Any]).flatMap { $0.count >= 2 ? $0 : nil }
        let longitude = coordinates.flatMap { ($0[0] as? NSNumber)?.doubleValue }
        let latitude = coordinates.flatMap { ($0[1] as? NSNumber)?.doubleValue }
        return CloudForecast(issuedAt: issued, latitude: latitude, longitude: longitude, hours: hours)
    }

    private static func percent(_ details: [String: Any], _ name: String) -> Double? {
        guard let value = (details[name] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }

    /// An ISO 8601 time such as "2026-10-18T19:00:00Z".
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

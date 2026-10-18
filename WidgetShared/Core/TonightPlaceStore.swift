import Foundation

/// Remembers the last places in the process's own defaults: there is no App Group, so the widget, the watch app and
/// the complications each keep their own copy.
enum TonightPlaceStore {
    /// Where a remembered place came from.
    enum Source: String {
        /// The device's own location, as measured by Core Location.
        case device
        /// The observer the iPhone app sent to the watch.
        case phone
    }

    private static func key(_ source: Source) -> String { "lodestar.tonight.place.\(source.rawValue)" }

    static func load(_ source: Source) -> TonightPlace? {
        guard let data = UserDefaults.standard.data(forKey: key(source)) else { return nil }
        return try? JSONDecoder().decode(TonightPlace.self, from: data)
    }

    static func save(_ place: TonightPlace, as source: Source) {
        guard let data = try? JSONEncoder().encode(place) else { return }
        UserDefaults.standard.set(data, forKey: key(source))
    }
}

/// How the iPhone app tells the watch where its observer is: an `applicationContext` dictionary of property-list
/// values. The iPhone app sends the same keys (`Lodestar/Features/Widgets/WatchObserverLink.swift`).
enum TonightPhoneContext {
    static let latitudeKey = "lat"
    static let longitudeKey = "lon"
    static let elevationKey = "elevation"
    static let timeZoneKey = "timeZone"

    /// The place a context describes, or `nil` when it lacks a valid one.
    static func place(from context: [String: Any]) -> TonightPlace? {
        guard let latitude = context[latitudeKey] as? Double, let longitude = context[longitudeKey] as? Double
        else { return nil }
        let elevation = context[elevationKey] as? Double ?? 0
        let zone = context[timeZoneKey] as? String ?? TimeZone.current.identifier
        return TonightPlace(latitude: latitude, longitude: longitude, elevation: elevation, timeZoneIdentifier: zone)
    }
}

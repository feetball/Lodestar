import Foundation
import LodestarKit

/// The resolved observing context every astronomy computation in the app uses.
struct ObserverContext: Equatable, Sendable {
    /// Location and atmosphere for LodestarKit.
    var observer: Observer
    /// Time zone used to present times (rise/set, twilight) for this location.
    var timeZone: TimeZone
    /// Display name, e.g. "Current Location" or a saved site's name.
    var name: String
    var source: LocationSource
    /// GPS horizontal accuracy in metres (device location only).
    var horizontalAccuracy: Double?
    /// When the device location was measured (device location only).
    var timestamp: Date?
    /// The skyline that applies at the site: its recorded skyline, the terrain horizon computed from elevation data, or
    /// the recorded one with the terrain filling the stretches that were not swept; nil for an open horizon (always nil
    /// for the device location).
    var horizon: HorizonProfile?
    /// Where `horizon` comes from; nil when there is none.
    var horizonSource: HorizonSource?

    var location: GeographicLocation { observer.location }

    /// A calendar in the observer's time zone (Gregorian).
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Where the skyline of an `ObserverContext` comes from. `label` is how the screens name it.
enum HorizonSource: Sendable, Hashable {
    /// The skyline the user recorded by sweeping the phone.
    case recorded
    /// The skyline computed from elevation data.
    case terrain
    /// The recorded skyline where the sweep reached, the terrain horizon in the stretches it left open.
    case recordedAndTerrain

    var label: String {
        switch self {
        case .recorded: return "Recorded skyline"
        case .terrain: return "Terrain horizon"
        case .recordedAndTerrain: return "Recorded + terrain"
        }
    }
}

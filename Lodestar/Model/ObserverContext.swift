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
    /// The site's recorded skyline, or nil for an open horizon (always nil for the device location).
    var horizon: HorizonProfile?

    var location: GeographicLocation { observer.location }

    /// A calendar in the observer's time zone (Gregorian).
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

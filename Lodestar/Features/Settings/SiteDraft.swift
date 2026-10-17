import Foundation
import LodestarKit

/// The editable text of an observing site, and what it means once it is complete.
struct SiteDraft: Equatable {
    var name: String
    var latitudeText: String
    var longitudeText: String
    /// Metres above sea level.
    var elevation: Double

    /// A draft without a position.
    init(name: String) {
        self.name = name
        latitudeText = ""
        longitudeText = ""
        elevation = 0
    }

    /// A draft at the device's position. The altitude is used only when the fix says it is valid.
    init(name: String, fix: LocationFix) {
        self.init(name: name)
        if let location = GeographicLocation.validated(latitude: fix.latitude, longitude: fix.longitude) {
            setPosition(location)
        }
        if fix.verticalAccuracy > 0, fix.altitude.isFinite {
            let range = GeographicLocation.elevationRange
            elevation = AstroMath.clamp(fix.altitude, range.lowerBound, range.upperBound)
        }
    }

    /// A draft of a saved site. Coordinates are written to a micro-degree (about 10 cm) so editing the name leaves
    /// the position as it was.
    init(site: SavedSite) {
        self.init(name: site.name)
        setPosition(site.location)
        elevation = site.elevation
    }

    /// The position the text describes, or `nil` while the latitude or longitude is incomplete or out of range.
    var location: GeographicLocation? {
        guard let latitude = AngleFormatter.parseLatitude(latitudeText),
              let longitude = AngleFormatter.parseLongitude(longitudeText) else { return nil }
        return GeographicLocation.validated(latitude: latitude, longitude: longitude, elevation: elevation)
    }

    var isLatitudeValid: Bool { AngleFormatter.parseLatitude(latitudeText) != nil }
    var isLongitudeValid: Bool { AngleFormatter.parseLongitude(longitudeText) != nil }

    /// Writes latitude and longitude as text; the elevation is left alone.
    mutating func setPosition(_ location: GeographicLocation) {
        latitudeText = AngleFormatter.formatLatitude(location.latitude, decimals: 6)
        longitudeText = AngleFormatter.formatLongitude(location.longitude, decimals: 6)
    }
}

/// How far the lookup of a site's time zone has got.
enum SiteTimeZoneStatus: Equatable {
    case waitingForCoordinates
    case resolving
    /// A regional zone found by the geocoder.
    case resolved(TimeZone)
    /// The geocoder gave no answer; the zone is estimated from the longitude.
    case approximate(TimeZone)

    /// The zone found or estimated so far.
    var timeZone: TimeZone? {
        switch self {
        case .resolved(let zone), .approximate(let zone): return zone
        case .waitingForCoordinates, .resolving: return nil
        }
    }
}

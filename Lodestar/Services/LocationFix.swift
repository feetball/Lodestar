import CoreLocation
import Foundation
import LodestarKit

/// A device position reduced to plain values.
struct LocationFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Metres above sea level; meaningful only when `verticalAccuracy` is positive.
    var altitude: Double
    /// Radius of uncertainty in metres.
    var horizontalAccuracy: Double
    /// Altitude uncertainty in metres; not positive when the altitude is invalid.
    var verticalAccuracy: Double
    var timestamp: Date

    /// Great-circle distance in metres to `other` (spherical Earth, accurate to a fraction of a percent).
    func distance(to other: LocationFix) -> Double {
        let phi1 = AstroMath.radians(latitude), phi2 = AstroMath.radians(other.latitude)
        let sinHalfLatitude = sin((phi2 - phi1) / 2)
        let sinHalfLongitude = sin(AstroMath.radians(other.longitude - longitude) / 2)
        let haversine = sinHalfLatitude * sinHalfLatitude + cos(phi1) * cos(phi2) * sinHalfLongitude * sinHalfLongitude
        return 2 * 6_371_000 * asin(min(1, haversine.squareRoot()))
    }
}

extension LocationFix {
    /// Copies a Core Location sample; `nil` when it has no valid position (negative accuracy or bad coordinates).
    init?(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  altitude: location.altitude, horizontalAccuracy: location.horizontalAccuracy,
                  verticalAccuracy: location.verticalAccuracy, timestamp: location.timestamp)
    }
}

/// Decides when a new fix replaces the observer location that all sky computations use.
///
/// Every observer change recomputes the sky, so GPS jitter must not reach it: the first fix is adopted, later ones
/// only when the device moved noticeably or the position became much more precise.
struct StableLocationFilter: Sendable {
    /// Metres the device must move before the location is replaced.
    static let movementThreshold = 250.0
    /// A fix replaces the location when its accuracy radius shrank by at least this factor …
    static let accuracyImprovementFactor = 2.0
    /// … and by at least this many metres.
    static let minimumAccuracyGain = 500.0

    private var anchor: LocationFix?

    /// The location to use from now on if `fix` should replace the current one, otherwise `nil`.
    mutating func accept(_ fix: LocationFix) -> GeographicLocation? {
        if let anchor {
            let moved = anchor.distance(to: fix) > Self.movementThreshold
            let moreAccurate = fix.horizontalAccuracy * Self.accuracyImprovementFactor < anchor.horizontalAccuracy
                && anchor.horizontalAccuracy - fix.horizontalAccuracy > Self.minimumAccuracyGain
            guard moved || moreAccurate else { return nil }
        }
        guard let location = Self.location(from: fix) else { return nil }
        anchor = fix
        return location
    }

    /// The fix as an observer location; the elevation is used only when the altitude is valid.
    private static func location(from fix: LocationFix) -> GeographicLocation? {
        let range = GeographicLocation.elevationRange
        let elevation = fix.verticalAccuracy > 0 && fix.altitude.isFinite
            ? AstroMath.clamp(fix.altitude, range.lowerBound, range.upperBound)
            : 0
        return GeographicLocation.validated(latitude: fix.latitude, longitude: fix.longitude, elevation: elevation)
    }
}

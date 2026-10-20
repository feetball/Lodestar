import CoreLocation
import Foundation
import LodestarKit
import Observation

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

/// The device location, with when-in-use authorization and a stabilised observer position.
///
/// Reduced ("approximate") accuracy is fine for the sky: a few kilometres change altitudes and azimuths by well
/// under a tenth of a degree. Heading is not used; aiming relies on `MotionService`.
@MainActor
@Observable
final class LocationService {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isReducedAccuracy = false
    /// The latest raw fix, kept only while location updates run. It is dropped when they stop (a saved site became the
    /// source, the app went to the background, access was lost), so that where the device used to be is never offered
    /// as where it is.
    private(set) var fix: LocationFix?
    /// The observer location for sky computations: set on the first fix, then replaced only when the device moved
    /// more than 250 m or its accuracy improved substantially. The elevation is the fix's when its vertical
    /// accuracy is valid, otherwise 0.
    private(set) var stableLocation: GeographicLocation?
    /// A message for the user (no coordinates) when location updates fail; cleared by the next good fix.
    private(set) var lastErrorDescription: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var delegate: LocationManagerDelegate?
    @ObservationIgnored private var filter = StableLocationFilter()
    @ObservationIgnored private var wantsUpdates = false
    @ObservationIgnored private var isUpdating = false

    init() {
        // Core Location calls the delegate on the thread that created the manager, which here is the main thread.
        let delegate = LocationManagerDelegate(
            onAuthorizationChange: { [weak self] in
                Task { @MainActor [weak self] in self?.refreshAuthorization() }
            },
            onFix: { [weak self] fix in
                Task { @MainActor [weak self] in self?.receive(fix) }
            },
            onFailure: { [weak self] message in
                Task { @MainActor [weak self] in self?.receive(failureMessage: message) }
            })
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        refreshAuthorization()
    }

    /// Location access is granted while the app is in use.
    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// The user (or a restriction) has turned location access off.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Shows the system permission prompt, but only if the user has not been asked yet.
    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Starts location updates as soon as access is granted. Idempotent.
    func start() {
        wantsUpdates = true
        refreshAuthorization()
    }

    /// Stops location updates. Idempotent.
    func stop() {
        wantsUpdates = false
        stopUpdates()
    }

    // MARK: Private

    /// Stops the manager if it runs and drops the fix, which is no longer current. Idempotent.
    private func stopUpdates() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
        if fix != nil { fix = nil }
    }

    /// Reads the authorization from the manager and starts or stops updates accordingly. Properties are written
    /// only when they change, because this runs every time the app asks for location.
    private func refreshAuthorization() {
        let status = manager.authorizationStatus
        if authorization != status {
            authorization = status
            // A message about missing access no longer applies once access is granted.
            if isAuthorized, lastErrorDescription != nil { lastErrorDescription = nil }
        }
        refreshAccuracy()
        if isAuthorized {
            if wantsUpdates && !isUpdating {
                manager.startUpdatingLocation()
                isUpdating = true
            }
        } else {
            stopUpdates()
        }
    }

    private func refreshAccuracy() {
        let isReduced = manager.accuracyAuthorization == .reducedAccuracy
        if isReducedAccuracy != isReduced { isReducedAccuracy = isReduced }
    }

    private func receive(_ newFix: LocationFix) {
        // A fix that was already on its way to the main actor when updates stopped is not current any more.
        guard isUpdating else { return }
        // Hops to the main actor are not strictly ordered; never go back in time.
        if let current = fix, newFix.timestamp < current.timestamp { return }
        fix = newFix
        if lastErrorDescription != nil { lastErrorDescription = nil }
        refreshAccuracy()
        if let location = filter.accept(newFix) {
            stableLocation = location
        }
    }

    private func receive(failureMessage: String) {
        lastErrorDescription = failureMessage
    }
}

/// Receives Core Location callbacks and forwards plain values; it holds no state of its own.
private final class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    private let onAuthorizationChange: @Sendable () -> Void
    private let onFix: @Sendable (LocationFix) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(onAuthorizationChange: @escaping @Sendable () -> Void,
         onFix: @escaping @Sendable (LocationFix) -> Void,
         onFailure: @escaping @Sendable (String) -> Void) {
        self.onAuthorizationChange = onAuthorizationChange
        self.onFix = onFix
        self.onFailure = onFailure
        super.init()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let newest = locations.last, let fix = LocationFix(newest) {
            onFix(fix)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let message = Self.message(for: error) {
            onFailure(message)
        }
    }

    /// A user-presentable message for a Core Location failure, or `nil` for the transient "no fix yet" case,
    /// which Core Location recovers from by itself.
    private static func message(for error: Error) -> String? {
        switch (error as? CLError)?.code {
        case .locationUnknown?:
            return nil
        case .denied?:
            return "Location access is turned off for Lodestar."
        case .network?:
            return "Your location could not be determined because the network is unavailable."
        default:
            return "Your location could not be determined."
        }
    }
}

import CoreLocation
import Foundation

/// Finds where the device is, for a widget, a complication or the watch app: a fresh approximate fix when Core
/// Location delivers one in time, otherwise the last one it knew, otherwise the one remembered from earlier.
///
/// Reduced accuracy is plenty for the sky. Nothing here asks the user anything in a widget; the app (or the watch
/// app) shows the permission prompt, and the widget shares the app's authorization.
@MainActor
final class TonightLocator {
    /// How long a request waits for Core Location.
    static let requestTimeout: Duration = .seconds(8)

    /// A Core Location sample reduced to plain values.
    private struct Fix: Sendable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let verticalAccuracy: Double

        init(_ location: CLLocation) {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            altitude = location.altitude
            verticalAccuracy = location.verticalAccuracy
        }
    }

    private let manager = CLLocationManager()
    private var delegate: Delegate?
    private var waiter: CheckedContinuation<Fix?, Never>?
    private var timeout: Task<Void, Never>?

    init() {
        let delegate = Delegate(
            onFix: { [weak self] fix in Task { @MainActor [weak self] in self?.finish(fix) } },
            onFailure: { [weak self] in Task { @MainActor [weak self] in self?.finish(nil) } })
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Whether Core Location lets this process read the location.
    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            #if os(watchOS)
            return false
            #else
            return manager.isAuthorizedForWidgetUpdates
            #endif
        }
    }

    /// What to tell the user when there is no place: to allow location where they have not been asked yet, to change it
    /// in Settings where they said no (or location is restricted).
    var locationIssue: TonightLocationIssue {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return .deniedOrRestricted
        default:
            return .notAsked
        }
    }

    /// Shows the permission prompt, but only if the user has not been asked yet. For apps, not widgets.
    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// The device's place, or `nil` without authorization or any earlier fix. A fresh fix is remembered.
    func currentPlace() async -> TonightPlace? {
        guard isAuthorized else { return nil }
        let fix: Fix?
        if let fresh = await requestFix() {
            fix = fresh
        } else {
            fix = manager.location.map(Fix.init)
        }
        guard let fix, let place = Self.place(from: fix) else { return TonightPlaceStore.load(.device) }
        TonightPlaceStore.save(place, as: .device)
        return place
    }

    // MARK: Private

    private func requestFix() async -> Fix? {
        guard waiter == nil else { return nil }
        return await withCheckedContinuation { continuation in
            waiter = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.requestTimeout)
                self?.finish(nil)
            }
            manager.requestLocation()
        }
    }

    private func finish(_ fix: Fix?) {
        guard let continuation = waiter else { return }
        waiter = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(returning: fix)
    }

    /// The elevation is the fix's when its vertical accuracy is valid, otherwise 0.
    private static func place(from fix: Fix) -> TonightPlace? {
        TonightPlace(latitude: fix.latitude, longitude: fix.longitude,
                     elevation: fix.verticalAccuracy > 0 ? fix.altitude : 0,
                     timeZoneIdentifier: TimeZone.current.identifier)
    }

    /// Receives Core Location's callbacks and forwards plain values.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        private let onFix: @Sendable (Fix) -> Void
        private let onFailure: @Sendable () -> Void

        init(onFix: @escaping @Sendable (Fix) -> Void, onFailure: @escaping @Sendable () -> Void) {
            self.onFix = onFix
            self.onFailure = onFailure
            super.init()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            if let newest = locations.last, newest.horizontalAccuracy >= 0 {
                onFix(Fix(newest))
            } else {
                onFailure()
            }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            onFailure()
        }
    }
}

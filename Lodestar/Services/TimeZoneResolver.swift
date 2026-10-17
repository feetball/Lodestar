import CoreLocation
import Foundation
import LodestarKit
#if compiler(>=6.2)
import MapKit
#endif

/// Finds the time zone of an observing site so rise, set and twilight times can be shown in local time.
///
/// The lookup reverse-geocodes one user-chosen coordinate, which is the app's only network use besides map
/// tiles. It gives up after `lookupTimeout`; callers fall back to `nominalTimeZone(longitude:)`.
enum TimeZoneResolver {
    /// Longest wait for the geocoding service.
    private static let lookupTimeout: Duration = .seconds(8)

    /// The IANA time zone at `location`, or `nil` when the service is unreachable, slow or has no answer.
    static func timeZone(for location: GeographicLocation) async -> TimeZone? {
        let point = CLLocation(latitude: location.latitude, longitude: location.longitude)
        // First answer wins: the lookup and the deadline both post to one stream, and the lookup is abandoned if
        // the deadline fires first (the system geocoders do not reliably honour task cancellation).
        let (answers, channel) = AsyncStream.makeStream(of: TimeZone?.self, bufferingPolicy: .unbounded)
        let lookup = Task {
            channel.yield(await reverseGeocodedTimeZone(at: point))
            channel.finish()
        }
        let deadline = Task {
            try? await Task.sleep(for: lookupTimeout)
            channel.yield(nil)
            channel.finish()
        }
        defer {
            lookup.cancel()
            deadline.cancel()
        }
        for await answer in answers { return answer }
        return nil
    }

    /// A fixed-offset zone from the longitude alone (15° per hour), for use offline. It ignores political
    /// borders and daylight saving time, so it is only a stopgap.
    static func nominalTimeZone(longitude: Double) -> TimeZone {
        guard longitude.isFinite else { return .gmt }
        let hours = min(max((longitude / 15).rounded(), -12), 14)
        return TimeZone(secondsFromGMT: Int(hours) * 3600) ?? .gmt
    }

    // MARK: Geocoding

    private static func reverseGeocodedTimeZone(at point: CLLocation) async -> TimeZone? {
        #if compiler(>=6.2)
        // MKReverseGeocodingRequest exists only in the iOS 26 SDK (Swift 6.2 or later) and at runtime on iOS 26.
        if #available(iOS 26.0, *), let zone = await mapKitTimeZone(at: point) {
            return zone
        }
        #endif
        return await geocoderTimeZone(at: point)
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    @MainActor
    private static func mapKitTimeZone(at point: CLLocation) async -> TimeZone? {
        guard let request = MKReverseGeocodingRequest(location: point) else { return nil }
        let mapItems = (try? await request.mapItems) ?? []
        return mapItems.lazy.compactMap(\.timeZone).first
    }
    #endif

    /// `CLGeocoder` is deprecated in the iOS 26 SDK but remains the only reverse geocoder before iOS 26 (and
    /// the fallback when MapKit has no time zone for the place). This is the one place that uses it.
    private static func geocoderTimeZone(at point: CLLocation) async -> TimeZone? {
        let placemarks = (try? await CLGeocoder().reverseGeocodeLocation(point)) ?? []
        return placemarks.lazy.compactMap(\.timeZone).first
    }
}

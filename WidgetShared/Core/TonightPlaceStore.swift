import Foundation

/// Remembers the last places in the process's own defaults: there is no App Group, so the widget, the watch app and
/// the complications each keep their own copy.
enum TonightPlaceStore {
    /// Where a remembered place came from.
    enum Source: String {
        /// The device's own location, as measured by Core Location.
        case device
        /// The iPhone app's observer: what the iPhone app remembers for its intents, and the label of a watch screen
        /// that is for the place the iPhone sent (`TonightPhonePlace`). The complications use `device`.
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

    private static let phonePlaceKey = "lodestar.tonight.phonePlace"

    /// The place the iPhone last sent to the watch app, with what it was and when it was sent. Only the watch app keeps
    /// one; it is not the `phone` slot above, which holds a bare place and is the iPhone app's own.
    static func loadPhonePlace() -> TonightPhonePlace? {
        guard let data = UserDefaults.standard.data(forKey: phonePlaceKey) else { return nil }
        return try? JSONDecoder().decode(TonightPhonePlace.self, from: data)
    }

    static func savePhonePlace(_ phonePlace: TonightPhonePlace) {
        guard let data = try? JSONEncoder().encode(phonePlace) else { return }
        UserDefaults.standard.set(data, forKey: phonePlaceKey)
    }
}

/// A place the iPhone app sent to the watch, with what the watch needs to judge how long to trust it. The iPhone's own
/// location is only right while the iPhone stays where it is, and nothing tells the watch when it moves, so it is used
/// for a while after it was sent and not for ever; a site the user chose holds until the user chooses another.
struct TonightPhonePlace: Sendable, Equatable, Codable {
    /// What the place stands for on the iPhone.
    enum Kind: String, Sendable, Codable {
        /// The iPhone's own location.
        case device
        /// A site the user chose.
        case savedSite
    }

    /// How long after it was sent the iPhone's own location is still used: an evening's observing, not a journey.
    static let deviceFreshness: TimeInterval = 3 * 3_600
    /// How far ahead of the watch's clock a send time may lie before it is not believed.
    static let clockTolerance: TimeInterval = 5 * 60

    let place: TonightPlace
    let kind: Kind
    /// When the iPhone sent the place; `nil` when it did not say (an older iPhone app).
    let sentAt: Date?

    /// Whether the watch should work for this place at `now` rather than for its own location. The iPhone's own
    /// location is fresh for `deviceFreshness` after it was sent, and never without a send time.
    func isFresh(at now: Date) -> Bool {
        switch kind {
        case .savedSite:
            return true
        case .device:
            guard let sentAt else { return false }
            let age = now.timeIntervalSince(sentAt)
            return age >= -Self.clockTolerance && age <= Self.deviceFreshness
        }
    }
}

/// How the iPhone app tells the watch where its observer is: an `applicationContext` dictionary of property-list
/// values. The iPhone app builds it with `context(for:)` (`Lodestar/Features/Widgets/WatchObserverLink.swift`) and the
/// watch app reads it with `phonePlace(from:)`.
enum TonightPhoneContext {
    static let latitudeKey = "lat"
    static let longitudeKey = "lon"
    static let elevationKey = "elevation"
    static let timeZoneKey = "timeZone"
    /// Whether the place is the iPhone's own location or a saved site: the raw value of `TonightPhonePlace.Kind`.
    static let kindKey = "kind"
    /// When the iPhone sent the place, in seconds since 1970.
    static let sentAtKey = "sentAt"

    /// The dictionary that tells the watch about `phonePlace`.
    static func context(for phonePlace: TonightPhonePlace) -> [String: Any] {
        let place = phonePlace.place
        var context: [String: Any] = [
            latitudeKey: place.latitude, longitudeKey: place.longitude, elevationKey: place.elevation,
            timeZoneKey: place.timeZoneIdentifier, kindKey: phonePlace.kind.rawValue,
        ]
        if let sentAt = phonePlace.sentAt {
            context[sentAtKey] = sentAt.timeIntervalSince1970
        }
        return context
    }

    /// The place a context describes with its kind and send time, or `nil` when it lacks a valid place. A context
    /// without a kind is the iPhone's own location, and one without a send time is never fresh: both are what an older
    /// iPhone app sends, and the watch is safer measuring for itself than trusting a place of unknown age.
    static func phonePlace(from context: [String: Any]) -> TonightPhonePlace? {
        guard let place = place(from: context) else { return nil }
        let kind = (context[kindKey] as? String).flatMap(TonightPhonePlace.Kind.init(rawValue:)) ?? .device
        let sentAt = (context[sentAtKey] as? Double).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        return TonightPhonePlace(place: place, kind: kind, sentAt: sentAt)
    }

    /// The place a context describes, or `nil` when it lacks a valid one.
    static func place(from context: [String: Any]) -> TonightPlace? {
        guard let latitude = context[latitudeKey] as? Double, let longitude = context[longitudeKey] as? Double
        else { return nil }
        let elevation = context[elevationKey] as? Double ?? 0
        let zone = context[timeZoneKey] as? String ?? TimeZone.current.identifier
        return TonightPlace(latitude: latitude, longitude: longitude, elevation: elevation, timeZoneIdentifier: zone)
    }
}

import Foundation
import LodestarKit

// The values the widgets, the complications and the watch app show. Plain, Sendable values only: the work is done
// by `TonightBuilder`, the words come from `TonightLines`, and nothing here depends on SwiftUI or WidgetKit.

/// Where "tonight" is worked out for: a place on Earth and the time zone its clocks follow.
struct TonightPlace: Sendable, Equatable, Codable {
    /// Degrees, north positive.
    let latitude: Double
    /// Degrees, east positive.
    let longitude: Double
    /// Metres above sea level.
    let elevation: Double
    let timeZoneIdentifier: String

    /// A place, or `nil` when a coordinate is not finite or out of range. An unknown time zone becomes the device's.
    init?(latitude: Double, longitude: Double, elevation: Double, timeZoneIdentifier: String) {
        guard let location = GeographicLocation.validated(latitude: latitude, longitude: longitude,
                                                          elevation: min(max(elevation, -1_000), 12_000))
        else { return nil }
        self.init(location: location, timeZoneIdentifier: timeZoneIdentifier)
    }

    private init(location: GeographicLocation, timeZoneIdentifier: String) {
        latitude = location.latitude
        longitude = location.longitude
        elevation = location.elevation
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier ?? TimeZone.current.identifier
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var observer: Observer {
        Observer(location: GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation))
    }

    /// A made-up place at 40° north whose longitude fits the device's time zone, so the clock times of a gallery
    /// preview look like local ones without using anybody's location.
    static func preview() -> TonightPlace {
        let zone = TimeZone.current
        let longitude = Double(zone.secondsFromGMT()) / 3_600 * 15
        return TonightPlace(location: GeographicLocation(latitude: 40, longitude: longitude),
                            timeZoneIdentifier: zone.identifier)
    }
}

/// What a widget or complication shows at one moment of its timeline.
struct TonightEntry: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        /// No place is known: the user has to open Lodestar (and allow location) first.
        case needsLocation
        case night(TonightNight)
    }

    /// The moment the entry is meant for.
    let date: Date
    let content: Content

    static func needsLocation(at date: Date) -> TonightEntry {
        TonightEntry(date: date, content: .needsLocation)
    }
}

/// The night that is under way, or the coming one once the Sun has risen on the night before (the same rule as the
/// app's Tonight tab), with what the widgets show of it. The Android widgets show the same four things.
struct TonightNight: Sendable, Equatable {
    let timeZone: TimeZone
    /// The Moon is drawn as seen from the northern hemisphere and mirrored south of the equator.
    let isSouthernHemisphere: Bool
    let darkness: Darkness
    let moon: Moon
    let core: Core
    /// The next event worth a look, or `nil` when none is listed.
    let event: Event?

    /// The astronomical darkness (Sun more than 18° below the horizon) of the night.
    struct Darkness: Sendable, Equatable {
        /// The stretches with the Sun below −18°, in time order; empty where the Sun never gets that low.
        let windows: [DateInterval]
        let hours: Double
        /// The hours of `hours` in which the Moon is down as well.
        let moonFreeHours: Double
        /// The whole night is dark (polar winter).
        let isAllNight: Bool
    }

    /// The Moon on the night: its phase at dusk and when it is up.
    struct Moon: Sendable, Equatable {
        let phase: MoonPhaseName
        /// The sunlit fraction of the disc, 0...1.
        let illuminatedFraction: Double
        let isWaxing: Bool
        /// The first rise and set within the night.
        let rise: Date?
        let set: Date?
        let circumstance: RiseTransitSet.Circumstance
        /// The stretches of the night in which the Moon is above the horizon.
        let upIntervals: [DateInterval]
    }

    /// The Galactic Centre, the brightest part of the Milky Way.
    struct Core: Sendable, Equatable {
        /// `false` where the Sun never gets 18° below the horizon tonight.
        let hasDarkness: Bool
        /// The stretches in which it is at least 10° up in the dark (slivers shorter than a quarter of an hour left out).
        let windows: [DateInterval]
        let bestTime: Date?
        let maxAltitude: Double?
        let bestAzimuth: Double?
    }

    /// An event from the events engine.
    struct Event: Sendable, Equatable {
        let title: String
        /// An SF Symbol name.
        let symbolName: String
        /// When it happens (for a solar eclipse that can be seen, its maximum here).
        let date: Date
        /// Whether it can be seen from the place; `nil` for events that are not seen in the sky (equinoxes, solstices).
        let isVisibleFromHere: Bool?
        /// The stretch around the best view, for events that can be seen.
        let bestWindow: DateInterval?
        /// Meteors an hour at the best, for a meteor shower.
        let showerRate: Int?
    }
}

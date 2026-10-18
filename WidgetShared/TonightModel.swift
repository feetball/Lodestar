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
/// app's Tonight tab), as seen at one moment.
struct TonightNight: Sendable, Equatable {
    let timeZone: TimeZone
    /// The phase symbols are drawn for the northern hemisphere; they are mirrored south of the equator.
    let isSouthernHemisphere: Bool
    let darkness: Darkness
    let moon: Moon
    let core: Core
    /// The next event worth a look, or `nil` when none is listed for the coming weeks.
    let event: Event?

    /// The astronomical darkness (Sun more than 18° below the horizon).
    enum Darkness: Sendable, Equatable {
        /// Where the Sun never gets 18° below the horizon tonight.
        case none
        /// The whole night is dark (polar winter).
        case allNight
        case window(DateInterval, Phase)

        enum Phase: Sendable, Equatable {
            case upcoming, inProgress, over
        }
    }

    struct Moon: Sendable, Equatable {
        let phase: MoonPhaseName
        /// The sunlit fraction of the disc, 0...1.
        let illuminatedFraction: Double
        let isWaxing: Bool
        let horizon: Horizon

        enum Horizon: Sendable, Equatable {
            /// Up now, and sets then.
            case sets(Date)
            /// Down now, and rises then.
            case rises(Date)
            /// Up for the rest of the night.
            case up
            /// Down for the rest of the night.
            case down
        }
    }

    /// The Galactic Centre, the brightest part of the Milky Way.
    enum Core: Sendable, Equatable {
        /// It does not get 10° above the horizon in the dark.
        case none
        /// The stretch in which it is at least 10° up in the dark; `isMoonFree` when the Moon is down in it.
        case window(DateInterval, isMoonFree: Bool)
    }

    struct Event: Sendable, Equatable {
        let title: String
        /// An SF Symbol name.
        let symbolName: String
        /// The day it is about: the start of the viewing window, otherwise the event's own time.
        let date: Date
        /// Whether its viewing window starts in the night this entry describes.
        let isTonight: Bool
    }
}

import Foundation
import LodestarKit

/// Which night the Tonight screen shows.
enum TonightNightChoice: Equatable, Sendable {
    /// The night under way, or the coming one once the Sun has risen. It moves on by itself.
    case tonight
    /// The night that starts on the local date of an instant.
    case date(Date)
}

/// Everything a night depends on besides the sky catalog: where the observer is and which night is wanted.
struct TonightNightKey: Equatable, Sendable {
    let context: ObserverContext
    let choice: TonightNightChoice
}

/// The work order for `TonightCalculator`: plain values only, so it can cross to a background task.
struct TonightInput: Sendable {
    let key: TonightNightKey
    /// The present moment, which decides what "tonight" is.
    let now: Date
    /// The sky catalog, or `nil` while it is still loading.
    let catalog: Catalog?
}

/// A deep-sky object ranked for the night.
struct TonightTarget: Identifiable, Sendable {
    let object: CelestialObject
    /// The highest geometric altitude reached while it is dark, in degrees.
    let peakAltitude: Double
    /// When that happens.
    let peakTime: Date
    /// The azimuth at that moment, in degrees from north through east.
    let peakAzimuth: Double
    /// The hours of darkness the object spends at or above `TonightCalculator.minimumTargetAltitude`.
    let hoursAboveMinimum: Double

    var id: String { object.id }
}

/// The best-targets list, or the reason there is none.
enum TonightTargetsOutcome: Sendable {
    /// The targets, best first; empty when no listed object climbs high enough.
    case ranked([TonightTarget])
    /// The Sun never gets 18° below the horizon, so there is no dark time to rank in.
    case noDarkness
    /// The sky catalog has not been loaded yet.
    case catalogPending
}

/// Everything the Tonight screen shows about one night.
struct TonightReport: Sendable {
    let summary: NightSummary
    let timeZone: TimeZone
    let timeline: TonightTimelineModel
    let targets: TonightTargetsOutcome
    /// Local noon of the date of the night under way (or coming): the zero of `nightsFromTonight`.
    let tonightStart: Date
    /// How many nights this one is after tonight: 1 is tomorrow night, -1 is last night.
    let nightsFromTonight: Int

    /// Local noon of the date this night starts on.
    var nightStart: Date { summary.night.start }

    /// When tonight turns into the next night: sunrise, or the end of the night when the Sun does not rise.
    var expiry: Date { summary.twilight.sunrise ?? summary.night.end }
}

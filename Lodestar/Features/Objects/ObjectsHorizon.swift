import Foundation
import LodestarKit

/// Rise, set and "visible now" over the site's recorded skyline. Pure, so it can run on any thread.
enum ObjectsHorizon {
    /// The skyline to apply for `context`: the site's recorded one, or `nil` for an open horizon. A flat profile
    /// counts as none.
    static func skyline(of context: ObserverContext?) -> HorizonProfile? {
        guard let horizon = context?.horizon, !horizon.isFlat else { return nil }
        return horizon
    }

    /// When `object` clears the skyline (`rise`), is highest (`transit`) and sinks behind it (`set`) within
    /// `interval`; `.alwaysUp` means it is visible throughout and `.alwaysDown` that it stays hidden.
    static func riseTransitSet(for object: CelestialObject, visibility: HorizonVisibility, observer: Observer,
                               within interval: DateInterval) -> RiseTransitSet {
        switch object.position {
        case .fixed(let coordinate, let properMotion):
            return visibility.riseTransitSet(forJ2000: coordinate, properMotion: properMotion, observer: observer,
                                             within: interval)
        case .solarSystem(let body):
            return visibility.riseTransitSet(for: body, observer: observer, within: interval)
        case .celestialPole(let north):
            // The pole stands still at the latitude, due north or due south.
            let altitude = north ? observer.location.latitude : -observer.location.latitude
            let isVisible = visibility.isVisible(altitude: altitude, azimuth: north ? 0 : 180)
            return RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: altitude,
                                  circumstance: isVisible ? .alwaysUp : .alwaysDown)
        }
    }

    /// Whether `object` is above the skyline at `date`. Uses the refracted position the lists already have.
    static func isVisible(altitude: Double, azimuth: Double, visibility: HorizonVisibility) -> Bool {
        visibility.isVisible(altitude: altitude, azimuth: azimuth, refracted: true)
    }
}

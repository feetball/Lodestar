import Foundation

extension MeridianClock {
    /// The transits of an object across the local meridian within `searchHalfSpan` of `date`.
    ///
    /// Fixed objects and solar-system bodies are as for the other overloads; a comet or an asteroid costs a few
    /// milliseconds and has no transit while its orbit cannot be evaluated; a celestial pole never transits, so both
    /// results are `nil`.
    public static func transit(for object: CelestialObject, around date: Date, observer: Observer) -> MeridianTransits {
        switch object.position {
        case .fixed(let coordinate, let properMotion):
            return transit(forJ2000: coordinate, properMotion: properMotion, around: date, observer: observer)
        case .solarSystem(let body):
            return transit(for: body, around: date, observer: observer)
        case .smallBody(let body):
            return transits(around: date) { instant in
                let frame = SkyFrame(date: instant, observer: observer)
                return frame.topocentricEquatorial(of: body).map { frame.hourAngle(apparentRightAscension: $0.rightAscension) }
                    ?? .nan
            }
        case .celestialPole:
            return MeridianTransits(next: nil, previous: nil)
        }
    }
}

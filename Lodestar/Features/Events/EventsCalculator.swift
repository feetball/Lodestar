import Foundation
import LodestarKit

/// The astronomy behind the events screens. Pure, so it can run on any thread.
enum EventsCalculator {
    /// The options every list uses: the zone of the observer's site, and a 3° limit for the Moon's conjunctions and for
    /// the planets' (the engine's default for the Moon, 5°, gives far more than a calendar needs).
    static func options(timeZone: TimeZone) -> EventOptions {
        EventOptions(planetConjunctionThreshold: 3, moonConjunctionThreshold: 3, timeZone: timeZone)
    }

    /// The events of the next twelve months for the observer, in time order, with their visibility.
    static func entries(for key: EventsKey) -> [EventsEntry] {
        let events = EventCalculator.events(from: key.dayStart, to: key.end, observer: key.observer,
                                            options: options(timeZone: key.timeZone))
        return events.map { entry(for: $0, observer: key.observer) }
    }

    /// The event with what the lists need besides its numbers.
    static func entry(for event: AstronomicalEvent, observer: Observer) -> EventsEntry {
        EventsEntry(event: event, moonInterference: moonInterference(of: event, observer: observer))
    }

    /// For a meteor shower: how bright the Moon is at the peak and whether it is up at the best time.
    static func moonInterference(of event: AstronomicalEvent, observer: Observer) -> EventsMoonInterference? {
        guard case .meteorShower(let peak) = event.details else { return nil }
        let date = event.visibility?.bestTime ?? event.date
        let moon = SkyFrame(date: date, observer: observer).horizontal(of: .moon, refraction: false)
        let fraction = peak.moonIlluminatedFraction
        return EventsMoonInterference(
            illuminatedFraction: fraction, moonAltitude: moon.altitude,
            level: EventsMoonInterference.level(illuminatedFraction: fraction, moonAltitude: moon.altitude))
    }

    // MARK: Framing

    /// The 35 mm equivalent focal lengths a lens suggestion is rounded down to.
    static let standardFocalLengths: [Double] = [14, 20, 24, 35, 50, 70, 85, 100, 135, 200, 300, 400, 500, 600, 800]

    /// How many separations wide a frame should be so that the pair sits comfortably inside it.
    static let framingMargin = 3.0

    /// A focal length, in millimetres on a full-frame camera, whose long side (36 mm) is about three separations wide:
    /// the longest standard focal length that still holds the pair with room around it. At least 14 mm.
    static func suggestedFocalLength(separation: Double) -> Double {
        guard separation.isFinite, separation > 0 else { return standardFocalLengths[0] }
        let frameWidth = AstroMath.clamp(separation * framingMargin, 0.5, 120)
        let exact = 18 / tan(frameWidth / 2 * Double.pi / 180)
        return standardFocalLengths.last { $0 <= exact } ?? standardFocalLengths[0]
    }

    // MARK: Aiming

    /// A place in the sky to point at for an event, ready to become a catalog object or a custom target.
    enum AimSubject: Sendable, Hashable {
        /// The Sun, the Moon or a planet.
        case body(SolarSystemBody)
        /// A fixed J2000 place, named: a reference star or the Pleiades.
        case fixed(name: String, EquatorialCoordinate)
        /// The radiant of a shower at a J2000 place.
        case radiant(name: String, EquatorialCoordinate)

        var title: String {
            switch self {
            case .body(let body): return body.displayName
            case .fixed(let name, _): return name
            case .radiant(let name, _): return name
            }
        }
    }

    /// What to point at for `event`, main subject first (the engine's `aimTargets`). A shower's radiant is the place at
    /// `now` while the shower is active, otherwise at the peak.
    static func aimSubjects(of event: AstronomicalEvent, now: Date) -> [AimSubject] {
        event.aimTargets.map { target in
            switch target {
            case .body(let body):
                return .body(body)
            case .fixed(let position, _):
                return .fixed(name: starName(at: position, in: event), position)
            case .radiant(let shower):
                let date = shower.isActive(at: now) ? now : event.date
                return .radiant(name: "\(shower.name) radiant", shower.radiant(at: date))
            }
        }
    }

    /// The name of the reference star or cluster a conjunction is with, found by its place.
    private static func starName(at position: EquatorialCoordinate, in event: AstronomicalEvent) -> String {
        guard case .conjunction(let conjunction) = event.details else { return "Target" }
        for target in [conjunction.first, conjunction.second] {
            if case .star(let star) = target, star.position == position { return star.displayName }
        }
        return "Target"
    }
}

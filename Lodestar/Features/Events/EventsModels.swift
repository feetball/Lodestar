import Foundation
import LodestarKit

/// What one run of the events calculator is asked for: where the observer is, in which time zone the days are
/// counted and from which local day the next twelve months run.
struct EventsKey: Sendable, Equatable {
    /// How far the observer may move before the events are worked out again, in kilometres. Their visibility and the
    /// local circumstances of an eclipse change slowly with the place.
    static let placeToleranceKilometers = 100.0
    /// How far ahead the calendar looks, in days.
    static let spanDays = 366

    let observer: Observer
    let timeZone: TimeZone
    /// The start of the local day the calendar begins with.
    let dayStart: Date

    init(context: ObserverContext, now: Date) {
        observer = context.observer
        timeZone = context.timeZone
        dayStart = context.calendar.startOfDay(for: now)
    }

    /// The end of the span (inclusive), the same local time `spanDays` later.
    var end: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: Self.spanDays, to: dayStart)
            ?? dayStart.addingTimeInterval(Double(Self.spanDays) * 86_400)
    }

    /// Whether events worked out for `self` can stand in for `other`: the same local day and zone, and a place
    /// within `placeToleranceKilometers`.
    func covers(_ other: EventsKey) -> Bool {
        dayStart == other.dayStart && timeZone.identifier == other.timeZone.identifier && isNear(other)
    }

    /// Whether `other` is within `placeToleranceKilometers` of the place, whatever the day.
    func isNear(_ other: EventsKey) -> Bool {
        Self.distanceKilometers(from: observer.location, to: other.observer.location) <= Self.placeToleranceKilometers
    }

    /// The great-circle distance between two places on a spherical Earth.
    static func distanceKilometers(from first: GeographicLocation, to second: GeographicLocation) -> Double {
        let radians = Double.pi / 180
        let latitude1 = first.latitude * radians
        let latitude2 = second.latitude * radians
        let deltaLatitude = latitude2 - latitude1
        let deltaLongitude = (second.longitude - first.longitude) * radians
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 6_371 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// How much moonlight disturbs a meteor shower at its best time.
struct EventsMoonInterference: Sendable, Hashable {
    enum Level: Sendable, Hashable {
        /// The Moon is below the horizon at the best time.
        case moonDown
        /// A thin Moon: faint meteors are still there.
        case little
        /// A half Moon: the fainter meteors are lost.
        case moderate
        /// A bright Moon: only the brighter meteors show.
        case strong
    }

    /// The illuminated fraction of the Moon at the peak, 0...1.
    let illuminatedFraction: Double
    /// The Moon's geometric altitude at the best time (or at the peak), in degrees.
    let moonAltitude: Double
    let level: Level

    /// The level for a Moon that is `illuminatedFraction` lit and `moonAltitude` high.
    static func level(illuminatedFraction: Double, moonAltitude: Double) -> Level {
        if moonAltitude <= 0 { return .moonDown }
        if illuminatedFraction < 0.25 { return .little }
        if illuminatedFraction < 0.6 { return .moderate }
        return .strong
    }
}

/// One event of the calendar with what the lists need besides the engine's own numbers.
struct EventsEntry: Identifiable, Hashable, Sendable {
    let event: AstronomicalEvent
    /// Set for meteor showers.
    let moonInterference: EventsMoonInterference?

    var id: String {
        "\(event.kind.rawValue).\(Int(event.date.timeIntervalSince1970)).\(event.title)"
    }

    /// `true` when there is something to see from the observer's place; `nil` for events that are not seen in the
    /// sky (equinoxes, solstices) and without an observer.
    var isVisibleFromHere: Bool? {
        event.visibility.map(\.isObservable)
    }
}

/// The groups the calendar's filter offers. An event can belong to several: a Moon–Venus conjunction is a
/// conjunction and a Moon event, a lunar eclipse is an eclipse and a Moon event.
enum EventsCategory: String, CaseIterable, Identifiable, Sendable {
    case meteorShowers, conjunctions, eclipses, planets, moon, seasons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meteorShowers: return "Meteor Showers"
        case .conjunctions: return "Conjunctions"
        case .eclipses: return "Eclipses"
        case .planets: return "Planets"
        case .moon: return "Moon"
        case .seasons: return "Seasons"
        }
    }

    var systemImage: String {
        switch self {
        case .meteorShowers: return "sparkles"
        case .conjunctions: return "circle.grid.2x1.fill"
        case .eclipses: return "circle.lefthalf.filled"
        case .planets: return "circle.circle"
        case .moon: return "moon"
        case .seasons: return "sun.max"
        }
    }

    /// Whether the category contains `event`.
    ///
    /// - Meteor showers: the peaks of the showers.
    /// - Conjunctions: every conjunction.
    /// - Eclipses: lunar and solar eclipses.
    /// - Planets: oppositions, greatest elongations and conjunctions of two planets.
    /// - Moon: special full Moons, lunar eclipses and every conjunction with the Moon.
    /// - Seasons: equinoxes and solstices (and the Earth's apsides, when they are asked for).
    func includes(_ event: AstronomicalEvent) -> Bool {
        switch (self, event.details) {
        case (.meteorShowers, .meteorShower):
            return true
        case (.conjunctions, .conjunction):
            return true
        case (.eclipses, .lunarEclipse), (.eclipses, .solarEclipse):
            return true
        case (.planets, .opposition), (.planets, .greatestElongation):
            return true
        case let (.planets, .conjunction(conjunction)):
            return !conjunction.involvesMoon && Self.isPlanet(conjunction.second)
        case (.moon, .fullMoonSpecial), (.moon, .lunarEclipse):
            return true
        case let (.moon, .conjunction(conjunction)):
            return conjunction.involvesMoon
        case (.seasons, .season), (.seasons, .earthApsis):
            return true
        default:
            return false
        }
    }

    private static func isPlanet(_ target: ConjunctionTarget) -> Bool {
        if case .body(let body) = target { return body.isPlanet }
        return false
    }
}

/// Opens the calendar screen from a `NavigationLink(value:)`.
struct EventsCalendarRoute: Hashable {}

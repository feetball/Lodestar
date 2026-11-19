import Foundation
import LodestarKit
import Observation

/// One predicted transit of the ISS or of Tiangong across the Sun or the Moon, with the name the screens show.
struct EventsTransitItem: Identifiable, Hashable, Sendable {
    let transit: SatelliteTransit
    let satelliteName: String

    /// Tells transits apart: the satellite, the body and the moment.
    var id: String {
        "\(transit.catalogNumber)/\(transit.body.rawValue)/\(Int64((transit.date.timeIntervalSince1970 * 1000).rounded()))"
    }
}

/// What the transit section of the calendar can show at a given moment.
enum EventsTransitAvailability: Sendable {
    /// The satellite feed is switched off.
    case off
    /// The feed is on but there is no element set for the ISS or Tiangong, or it is too old for exact times.
    case needsData
    /// Fresh element sets are there.
    case ready
}

/// Predicting the transits the calendar lists. Pure.
enum EventsTransits {
    /// The calendar looks this many days ahead.
    static let horizonDays = 14.0
    /// Transits are listed when the centreline is within this ground distance, in metres.
    static let maxGroundDistanceMeters = 50_000.0
    /// The most transits the section lists.
    static let listLimit = 20

    private static let tiangongName = "Tiangong"
    private static let bodies: [SolarSystemBody] = [.sun, .moon]

    /// The ISS and Tiangong of `library` whose element sets are within their freshness limit at `date`.
    static func satellites(in library: SatelliteLibrary, at date: Date) -> [PassSatellite] {
        library.passSatellites.filter { entry in
            let number = entry.satellite.catalogNumber
            return (number == SatelliteLibrary.issCatalogNumber || number == SatelliteLibrary.tiangongCatalogNumber)
                && entry.isFresh(at: date)
        }
    }

    /// What the section shows for the feed switch and the library at `date`.
    static func availability(isFeedOn: Bool, library: SatelliteLibrary, at date: Date) -> EventsTransitAvailability {
        if !isFeedOn { return .off }
        return satellites(in: library, at: date).isEmpty ? .needsData : .ready
    }

    /// The transits of the Sun and the Moon by `satellites` in the `horizonDays` days from `start`, from `observer`'s
    /// site or within `maxGroundDistanceMeters` of it, by time. About a quarter of a second on a phone: run it off the
    /// main actor.
    static func compute(satellites: [PassSatellite], observer: Observer, start: Date) -> [EventsTransitItem] {
        let end = start.addingTimeInterval(horizonDays * 86_400)
        var found: [EventsTransitItem] = []
        for entry in satellites {
            let name = entry.satellite.catalogNumber == SatelliteLibrary.issCatalogNumber ? "ISS" : tiangongName
            for body in bodies {
                let transits = SatelliteTransitFinder.transits(
                    satellite: entry.satellite, body: body, observer: observer, from: start, to: end,
                    maxGroundDistanceMeters: maxGroundDistanceMeters
                )
                found.append(contentsOf: transits.map { EventsTransitItem(transit: $0, satelliteName: name) })
            }
        }
        return found.sorted { $0.transit.date < $1.transit.date }
    }

    /// The transits that have not happened yet at `now`, at most `listLimit`.
    static func upcoming(_ items: [EventsTransitItem], now: Date) -> [EventsTransitItem] {
        Array(items.filter { $0.transit.date >= now }.prefix(listLimit))
    }
}

/// What a set of transits was computed for: the element sets and the place (to 0.002°, about 200 m).
struct EventsTransitKey: Hashable, Sendable {
    let catalogNumbers: [Int]
    let epochMilliseconds: [Int64]
    let latitudeSteps: Int64
    let longitudeSteps: Int64

    private static let positionStep = 0.002

    init(satellites: [PassSatellite], observer: Observer) {
        catalogNumbers = satellites.map { $0.satellite.catalogNumber }
        epochMilliseconds = satellites.map { Int64(($0.satellite.elements.epoch.timeIntervalSince1970 * 1000).rounded()) }
        latitudeSteps = Int64((observer.location.latitude / Self.positionStep).rounded())
        longitudeSteps = Int64((observer.location.longitude / Self.positionStep).rounded())
    }
}

/// The transits for the current satellite data and observing place, found once off the main actor and kept for the
/// session, so opening the calendar again does not search again. They are found again when an element set or the place
/// changes, and every six hours as the window moves on.
@MainActor
@Observable
final class EventsTransitModel {
    /// The one model of the app session.
    static let shared = EventsTransitModel()

    /// The window is moved on after this long.
    static let refreshAfter: TimeInterval = 6 * 3_600

    /// The transits, by time; `nil` until they have been worked out.
    private(set) var items: [EventsTransitItem]?

    @ObservationIgnored private var key: EventsTransitKey?
    @ObservationIgnored private var pendingKey: EventsTransitKey?
    @ObservationIgnored private var computedAt = Date.distantPast
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts a search for `satellites` and `observer` unless the transits are already current at `now`, or a search for
    /// the same inputs is under way. Cheap to call often.
    func refresh(satellites: [PassSatellite], observer: Observer, now: Date) {
        let wanted = EventsTransitKey(satellites: satellites, observer: observer)
        if key == wanted, now.timeIntervalSince(computedAt) < Self.refreshAfter { return }
        if pendingKey == wanted { return }
        pendingKey = wanted
        task?.cancel()
        task = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                EventsTransits.compute(satellites: satellites, observer: observer, start: now)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.items = found
            self.key = wanted
            self.computedAt = now
            self.pendingKey = nil
        }
    }

    /// Forgets the transits (the satellite data went away).
    func clear() {
        task?.cancel()
        task = nil
        items = nil
        key = nil
        pendingKey = nil
    }
}

import Foundation
import LodestarKit
import Observation

/// Where one object is in the observer's sky at the moment it was computed, and when it next rises.
///
/// With a recorded skyline "above the horizon" means above the skyline, and rising is clearing it.
struct ObjectSkyPosition: Sendable, Equatable {
    /// Apparent altitude in degrees (refraction included), as the Aim screen shows it.
    let altitude: Double
    /// Azimuth in degrees from north through east.
    let azimuth: Double
    /// The next rising (clearing the skyline, if there is one) within `ObjectsPositionCalculator.riseSearchWindow`.
    let nextRise: Date?
    /// `true` when an object that keeps its place among the stars (a star, a deep-sky object or a celestial pole)
    /// stays below the horizon (or behind the skyline) throughout the search window, which is for good.
    let neverRises: Bool
    /// `true` when the Sun, the Moon, a planet, a comet or an asteroid has no rising in the search window. It moves, so
    /// that says nothing about later days.
    let noRiseInWindow: Bool
    /// The current magnitude of the Sun, the Moon, the planets, comets and asteroids, whose brightness changes; `nil`
    /// for other objects.
    let magnitude: Double?
    /// The instant the position was computed for.
    let computedAt: Date
    /// `true` when the object is above the horizon and, with a recorded skyline, above that too.
    let isAboveHorizon: Bool
    /// `true` when the object is above the horizon but hidden behind the recorded skyline.
    let isBehindSkyline: Bool
    /// Whether a recorded skyline decided the answers.
    let usesSkyline: Bool
    /// For a comet or an asteroid: distances, elongation and warnings now; `nil` for other objects and when its orbit
    /// cannot be evaluated.
    var smallBody: SmallBodyInfo?
    /// The instant the search for the rising started from, or `nil` when that is not known. A rising found less than
    /// `ObjectsPositionCalculator.risingReuseAge` ago is kept when the position is worked out again.
    var risingSearchedAt: Date?
}

/// Computes sky positions for lists of objects. Pure, so it can run on any thread.
enum ObjectsPositionCalculator {
    /// How far ahead the next rising is looked for, in seconds. A little over a day, so every object that rises at
    /// all has a rising in the window even when its rising time moves by almost an hour a day, as the Moon's does.
    static let riseSearchWindow: TimeInterval = 25 * 3600

    /// How long a rising found by a search is kept, in seconds. The search costs far more than the position, and
    /// the rising barely moves meanwhile (the Moon's moves by about 50 minutes a day, which is under a minute in
    /// five), so the position is worked out again on every pass and the rising only when this has passed.
    static let risingReuseAge: TimeInterval = 5 * 60

    /// What a search for the next rising of one object found, and the instant it started from.
    private struct Rising {
        let nextRise: Date?
        let neverRises: Bool
        let noRiseInWindow: Bool
        let searchedAt: Date
    }

    /// The position of every object in `objects` at `date`, keyed by object identifier. With a `skyline` the
    /// visibility and the rising times are judged over it. `known` holds earlier positions for the same observer and
    /// skyline: an object's rising is taken from there while it is no older than `risingReuseAge` and still ahead,
    /// and searched for again otherwise.
    static func positions(for objects: [CelestialObject], observer: Observer, skyline: HorizonProfile? = nil,
                          date: Date,
                          keepingRisingsOf known: [String: ObjectSkyPosition] = [:]) -> [String: ObjectSkyPosition] {
        let frame = SkyFrame(date: date, observer: observer)
        let visibility = skyline.map(HorizonVisibility.init(profile:))
        var result = [String: ObjectSkyPosition](minimumCapacity: objects.count)
        for object in objects {
            let horizontal = frame.horizontal(of: object, refraction: true)
            var isAbove = horizontal.altitude > 0
            if let visibility {
                isAbove = ObjectsHorizon.isVisible(altitude: horizontal.altitude, azimuth: horizontal.azimuth,
                                                   visibility: visibility)
            }
            let rising = known[object.id].flatMap { keptRising(of: $0, at: date) }
                ?? searchRising(of: object, observer: observer, visibility: visibility, from: date)
            result[object.id] = ObjectSkyPosition(
                altitude: horizontal.altitude,
                azimuth: horizontal.azimuth,
                nextRise: rising.nextRise,
                neverRises: rising.neverRises,
                noRiseInWindow: rising.noRiseInWindow,
                magnitude: object.isSolarSystem ? frame.currentMagnitude(of: object) : nil,
                computedAt: date,
                isAboveHorizon: isAbove,
                isBehindSkyline: visibility != nil && horizontal.altitude > 0 && !isAbove,
                usesSkyline: visibility != nil,
                smallBody: object.smallBody.flatMap { SmallBodyInfo.compute($0, frame: frame) },
                risingSearchedAt: rising.searchedAt)
        }
        return result
    }

    /// Searches `riseSearchWindow` from `date` for the next rising of `object`, over the skyline when there is one.
    private static func searchRising(of object: CelestialObject, observer: Observer, visibility: HorizonVisibility?,
                                     from date: Date) -> Rising {
        let window = DateInterval(start: date, duration: riseSearchWindow)
        let events: RiseTransitSet
        if let visibility {
            events = ObjectsHorizon.riseTransitSet(for: object, visibility: visibility, observer: observer,
                                                   within: window)
        } else {
            events = RiseSetCalculator.riseTransitSet(for: object, observer: observer, within: window)
        }
        let staysBelow = events.circumstance == .alwaysDown
        let isStationary = staysAmongStars(object)
        return Rising(nextRise: events.rise, neverRises: staysBelow && isStationary,
                      noRiseInWindow: staysBelow && !isStationary, searchedAt: date)
    }

    /// The rising `position` carries, when it still holds at `date`: found no more than `risingReuseAge` ago, and
    /// not yet past, since a rising that has happened is no longer the next one.
    private static func keptRising(of position: ObjectSkyPosition, at date: Date) -> Rising? {
        guard let searchedAt = position.risingSearchedAt else { return nil }
        let age = date.timeIntervalSince(searchedAt)
        guard age >= 0, age <= risingReuseAge else { return nil }
        if let rise = position.nextRise, rise <= date { return nil }
        return Rising(nextRise: position.nextRise, neverRises: position.neverRises,
                      noRiseInWindow: position.noRiseInWindow, searchedAt: searchedAt)
    }

    /// Whether the object keeps its place among the stars, so that a rising missing from the search window is missing
    /// for good. The solar-system bodies and the small bodies move, and may rise on a later day.
    private static func staysAmongStars(_ object: CelestialObject) -> Bool {
        switch object.position {
        case .fixed, .celestialPole: return true
        case .solarSystem, .smallBody: return false
        }
    }
}

/// Keeps the sky positions of the objects on screen up to date for the current observer.
///
/// The Objects list sorts and filters by these positions and shows them in every row. They are computed off the
/// main actor and refreshed every 30 s while the list is visible. The search for each object's next rising costs far
/// more than its position, so a rising is kept for a few minutes (`ObjectsPositionCalculator.risingReuseAge`).
///
/// When the list asks for them (the "Hours Visible Tonight" order or filter), the same loop also works out how many
/// hours tonight each tracked object is above the skyline (`tonight`). That is done once per observer, skyline and
/// night, for the objects that have no hours yet, and kept until one of them changes.
@MainActor
@Observable
final class ObjectsPositionModel {
    /// How often positions are recomputed while the list is on screen.
    static let refreshInterval: Duration = .seconds(30)
    /// Positions computed less than this many seconds ago are reused when the tracked objects change. It is shorter
    /// than `refreshInterval` on purpose: the rows show the altitude, so every pass works every position out again.
    static let reuseAge: TimeInterval = 25

    /// The latest position of each tracked object, keyed by object identifier.
    private(set) var positions: [String: ObjectSkyPosition] = [:]

    /// Tonight's hours above the skyline of each tracked object, keyed by object identifier; empty until computed.
    private(set) var tonight: [String: UnobstructedVisibility] = [:]

    /// What tonight's hours were computed for.
    private struct TonightKey: Equatable {
        let observer: Observer
        let skyline: HorizonProfile?
        let night: ObjectsNight
    }

    @ObservationIgnored private var observer: Observer?
    @ObservationIgnored private var skyline: HorizonProfile?
    @ObservationIgnored private var tonightKey: TonightKey?

    /// The latest position of the object with `id`, or `nil` when it is not tracked or not yet computed.
    func position(for id: String) -> ObjectSkyPosition? {
        positions[id]
    }

    /// Computes the positions of the objects `tracked` returns now and then every `refreshInterval` until the
    /// calling task is cancelled. `tracked` is asked again on every pass, so the objects can change over time. With
    /// `wantsTonight` it also keeps tonight's hours above the skyline up to date; `timeZone` decides which night is
    /// tonight.
    func keepFresh(observer: Observer, skyline: HorizonProfile?, timeZone: TimeZone, clock: SkyClock,
                   wantsTonight: Bool, tracking tracked: @MainActor () -> [CelestialObject]) async {
        while !Task.isCancelled {
            let objects = tracked()
            await refresh(objects, observer: observer, skyline: skyline, date: clock.now)
            if wantsTonight {
                await refreshTonight(objects, observer: observer, skyline: skyline, timeZone: timeZone,
                                     date: clock.now)
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Forgets every position and every hour, for when there is no observer.
    func clear() {
        positions = [:]
        observer = nil
        skyline = nil
        tonight = [:]
        tonightKey = nil
    }

    /// Works out tonight's hours for the `objects` that have none. Another observer, another skyline or the next night
    /// makes every known hour wrong, so those start again.
    private func refreshTonight(_ objects: [CelestialObject], observer: Observer, skyline: HorizonProfile?,
                                timeZone: TimeZone, date: Date) async {
        let night = await Task.detached(priority: .utility) {
            ObjectsTonight.night(observer: observer, timeZone: timeZone, now: date)
        }.value
        let key = TonightKey(observer: observer, skyline: skyline, night: night)
        let isNewKey = tonightKey != key
        let missing = isNewKey ? objects : objects.filter { tonight[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let computed = await Task.detached(priority: .utility) {
            ObjectsTonight.visibility(of: missing, observer: observer, night: night, skyline: skyline)
        }.value
        guard !Task.isCancelled else { return }
        tonight = isNewKey ? computed : tonight.merging(computed) { _, new in new }
        tonightKey = key
    }

    private func refresh(_ objects: [CelestialObject], observer: Observer, skyline: HorizonProfile?,
                         date: Date) async {
        // Another place or another skyline makes every known position wrong.
        let isNewObserver = self.observer != observer || self.skyline != skyline
        let outdated = isNewObserver ? objects : objects.filter { object in
            guard let known = positions[object.id] else { return true }
            return date.timeIntervalSince(known.computedAt) > Self.reuseAge
        }
        guard !outdated.isEmpty else { return }
        let earlier: [String: ObjectSkyPosition] = isNewObserver ? [:] : positions
        let computed = await Task.detached(priority: .utility) {
            ObjectsPositionCalculator.positions(for: outdated, observer: observer, skyline: skyline, date: date,
                                                keepingRisingsOf: earlier)
        }.value
        guard !Task.isCancelled else { return }
        if isNewObserver {
            positions = computed
            self.observer = observer
            self.skyline = skyline
        } else {
            positions.merge(computed) { _, new in new }
        }
    }
}

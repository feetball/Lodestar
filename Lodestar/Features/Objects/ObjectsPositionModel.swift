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
    /// `true` when the object stays below the horizon (or behind the skyline) throughout the search window.
    let neverRises: Bool
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
}

/// Computes sky positions for lists of objects. Pure, so it can run on any thread.
enum ObjectsPositionCalculator {
    /// How far ahead the next rising is looked for, in seconds. A little over a day, so every object that rises at
    /// all has a rising in the window even when its rising time moves by almost an hour a day, as the Moon's does.
    static let riseSearchWindow: TimeInterval = 25 * 3600

    /// The position of every object in `objects` at `date`, keyed by object identifier. With a `skyline` the
    /// visibility and the rising times are judged over it.
    static func positions(for objects: [CelestialObject], observer: Observer, skyline: HorizonProfile? = nil,
                          date: Date) -> [String: ObjectSkyPosition] {
        let frame = SkyFrame(date: date, observer: observer)
        let window = DateInterval(start: date, duration: riseSearchWindow)
        let visibility = skyline.map(HorizonVisibility.init(profile:))
        var result = [String: ObjectSkyPosition](minimumCapacity: objects.count)
        for object in objects {
            let horizontal = frame.horizontal(of: object, refraction: true)
            let events: RiseTransitSet
            var isAbove = horizontal.altitude > 0
            if let visibility {
                events = ObjectsHorizon.riseTransitSet(for: object, visibility: visibility, observer: observer,
                                                       within: window)
                isAbove = ObjectsHorizon.isVisible(altitude: horizontal.altitude, azimuth: horizontal.azimuth,
                                                   visibility: visibility)
            } else {
                events = RiseSetCalculator.riseTransitSet(for: object, observer: observer, within: window)
            }
            result[object.id] = ObjectSkyPosition(
                altitude: horizontal.altitude,
                azimuth: horizontal.azimuth,
                nextRise: events.rise,
                neverRises: events.circumstance == .alwaysDown,
                magnitude: object.isSolarSystem ? frame.currentMagnitude(of: object) : nil,
                computedAt: date,
                isAboveHorizon: isAbove,
                isBehindSkyline: visibility != nil && horizontal.altitude > 0 && !isAbove,
                usesSkyline: visibility != nil,
                smallBody: object.smallBody.flatMap { SmallBodyInfo.compute($0, frame: frame) })
        }
        return result
    }
}

/// Keeps the sky positions of the objects on screen up to date for the current observer.
///
/// The Objects list sorts and filters by these positions and shows them in every row. They are computed off the
/// main actor and refreshed every 30 s while the list is visible.
@MainActor
@Observable
final class ObjectsPositionModel {
    /// How often positions are recomputed while the list is on screen.
    static let refreshInterval: Duration = .seconds(30)
    /// Positions computed less than this many seconds ago are reused when the tracked objects change.
    static let reuseAge: TimeInterval = 25

    /// The latest position of each tracked object, keyed by object identifier.
    private(set) var positions: [String: ObjectSkyPosition] = [:]

    @ObservationIgnored private var observer: Observer?
    @ObservationIgnored private var skyline: HorizonProfile?

    /// The latest position of the object with `id`, or `nil` when it is not tracked or not yet computed.
    func position(for id: String) -> ObjectSkyPosition? {
        positions[id]
    }

    /// Computes the positions of the objects `tracked` returns now and then every `refreshInterval` until the
    /// calling task is cancelled. `tracked` is asked again on every pass, so the objects can change over time.
    func keepFresh(observer: Observer, skyline: HorizonProfile?, clock: SkyClock,
                   tracking tracked: @MainActor () -> [CelestialObject]) async {
        while !Task.isCancelled {
            await refresh(tracked(), observer: observer, skyline: skyline, date: clock.now)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Forgets every position, for when there is no observer.
    func clear() {
        positions = [:]
        observer = nil
        skyline = nil
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
        let computed = await Task.detached(priority: .utility) {
            ObjectsPositionCalculator.positions(for: outdated, observer: observer, skyline: skyline, date: date)
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

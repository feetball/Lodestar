import Foundation
import LodestarKit

/// The night the Objects list judges "tonight" by: the one under way, or the coming one once the Sun has risen.
struct ObjectsNight: Sendable, Equatable {
    /// Local noon at which the night starts; it changes when tonight turns into the next night.
    let start: Date
    /// The hours of astronomical darkness, or `nil` when the Sun does not get that low.
    let darkness: DateInterval?
}

/// How many hours tonight each object is above the site's skyline and at least `minimumAltitude` high during
/// astronomical darkness: the numbers behind the Objects list's "Hours Visible Tonight" order and "Visible ≥ 1 h
/// Tonight" filter. Pure, so it can run on any thread.
///
/// The altitude is the Tonight screen's minimum (the planner's default), so an object's hours here are the hours the
/// Tonight screen counts. Without a skyline the horizon is flat.
enum ObjectsTonight {
    /// The lowest altitude, in degrees, at which an object counts as visible: the Tonight screen's minimum.
    static let minimumAltitude = NightPlanner.defaultMinimumAltitude
    /// The hours of visibility "Visible ≥ 1 h Tonight" asks for.
    static let minimumHours = 1.0

    /// The twilight of the night that contains `date`: the one that began at noon yesterday while it is still before
    /// sunrise, otherwise the one that begins at noon today.
    static func twilight(observer: Observer, timeZone: TimeZone, date: Date) -> NightTwilight {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let twilightOfNight = { (day: Date) -> NightTwilight in
            TwilightCalculator.night(startingOn: day, observer: observer, timeZone: timeZone)
        }
        let underWay = TwilightCalculator.nightUnderWay(at: date, calendar: calendar, twilightOfNight: twilightOfNight)
        return underWay?.twilight ?? twilightOfNight(date)
    }

    /// The night under way at `now` (the coming one by day).
    static func night(observer: Observer, timeZone: TimeZone, now: Date) -> ObjectsNight {
        let twilight = twilight(observer: observer, timeZone: timeZone, date: now)
        return ObjectsNight(start: twilight.interval.start, darkness: twilight.astronomicalNight)
    }

    /// The hours of `night` each of `objects` is clear of `skyline` (the flat horizon when `nil`), keyed by object
    /// identifier. The deep-sky objects and stars, which are most of a catalog, go through the planner's cheap batch
    /// (about 1 s for 11,000 objects with a skyline on a desktop, a few seconds on a phone); the Sun, Moon, planets,
    /// comets and asteroids one at a time (a few milliseconds each).
    static func visibility(of objects: [CelestialObject], observer: Observer, night: ObjectsNight,
                           skyline: HorizonProfile?) -> [String: UnobstructedVisibility] {
        var result = [String: UnobstructedVisibility](minimumCapacity: objects.count)
        guard let darkness = night.darkness else {
            for object in objects {
                result[object.id] = UnobstructedVisibility(intervals: [], isBehindSkyline: false)
            }
            return result
        }
        var fixed: [CelestialObject] = []
        var places: [EquatorialCoordinate] = []
        var motions: [ProperMotion?] = []
        for object in objects {
            if case .fixed(let place, let motion) = object.position {
                fixed.append(object)
                places.append(place)
                motions.append(motion)
            } else {
                result[object.id] = visibility(of: object, observer: observer, darkness: darkness, skyline: skyline)
            }
        }
        let batch = NightPlanner.unobstructedVisibility(ofFixed: places, properMotions: motions, observer: observer,
                                                        during: darkness, minimumAltitude: minimumAltitude,
                                                        horizon: skyline)
        for (object, found) in zip(fixed, batch) {
            result[object.id] = found
        }
        return result
    }

    /// How long `object` is clear of `skyline` during `darkness` (the planner's one-object calls, a few milliseconds).
    static func visibility(of object: CelestialObject, observer: Observer, darkness: DateInterval,
                           skyline: HorizonProfile?) -> UnobstructedVisibility {
        let found: TargetVisibility
        switch object.position {
        case .fixed(let place, let motion):
            return NightPlanner.unobstructedVisibility(ofFixed: [place], properMotions: [motion], observer: observer,
                                                       during: darkness, minimumAltitude: minimumAltitude,
                                                       horizon: skyline)[0]
        case .solarSystem(let body):
            found = NightPlanner.visibility(of: body, observer: observer, during: darkness,
                                            minimumAltitude: minimumAltitude, horizon: skyline)
        case .celestialPole, .smallBody:
            // A pole stands still at the latitude, and a comet or an asteroid moves against the stars: both follow
            // the catalog's own position.
            let place: (SkyFrame) -> HorizontalCoordinate = { $0.horizontal(of: object, refraction: false) }
            found = NightPlanner.visibility(of: place, observer: observer, during: darkness,
                                            minimumAltitude: minimumAltitude, horizon: skyline)
        }
        return UnobstructedVisibility(intervals: found.unobstructedIntervals, isBehindSkyline: found.isBehindSkyline)
    }
}

import Foundation
import LodestarKit

/// The astronomy behind the Tonight screen. Pure, so it can run on any thread.
enum TonightCalculator {
    /// The lowest altitude, in degrees, at which a deep-sky object still counts as a target.
    static let minimumTargetAltitude = NightPlanner.defaultMinimumAltitude
    /// The most targets the list shows.
    static let targetLimit = 12

    /// Plans the night that `input` asks for: twilight, Moon, Milky Way, planets and the best targets.
    static func report(for input: TonightInput) -> TonightReport {
        let context = input.key.context
        let calendar = context.calendar
        let tonight = tonightDate(now: input.now, context: context)
        let requested: Date
        switch input.key.choice {
        case .tonight: requested = tonight
        case .date(let date): requested = date
        }
        let summary = NightPlanner.summary(nightStartingOn: requested, observer: context.observer,
                                           timeZone: context.timeZone)
        let tonightStart = localNoon(of: tonight, calendar: calendar)
        let nights = calendar.dateComponents([.day], from: calendar.startOfDay(for: tonightStart),
                                             to: calendar.startOfDay(for: summary.night.start)).day ?? 0
        return TonightReport(
            summary: summary, timeZone: context.timeZone,
            timeline: TonightTimelineModel(summary: summary, timeZone: context.timeZone),
            targets: targets(for: summary, catalog: input.catalog),
            tonightStart: tonightStart, nightsFromTonight: nights)
    }

    /// An instant on the date of the night that is under way at `now`, or of the coming night once the Sun
    /// has risen on the night before.
    private static func tonightDate(now: Date, context: ObserverContext) -> Date {
        let yesterday = context.calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let previous = TwilightCalculator.night(startingOn: yesterday, observer: context.observer,
                                                timeZone: context.timeZone)
        if now < previous.interval.end, now < (previous.sunrise ?? previous.interval.end) {
            return yesterday
        }
        return now
    }

    /// Noon of the calendar day that contains `date`: the instant the screen uses to stand for a night.
    static func localNoon(of date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(12 * 3600)
    }

    // MARK: Best targets

    private static func targets(for summary: NightSummary, catalog: Catalog?) -> TonightTargetsOutcome {
        guard summary.hasAstronomicalDarkness else { return .noDarkness }
        guard let catalog else { return .catalogPending }
        return .ranked(rankedTargets(in: catalog, summary: summary))
    }

    /// The listed deep-sky objects that climb to at least `minimumTargetAltitude` in the dark, best first, at
    /// most `targetLimit` of them.
    private static func rankedTargets(in catalog: Catalog, summary: NightSummary) -> [TonightTarget] {
        var objects: [CelestialObject] = []
        var places: [EquatorialCoordinate] = []
        var motions: [ProperMotion?] = []
        for object in catalog.listedObjects where isDeepSky(object) {
            guard case .fixed(let place, let motion) = object.position else { continue }
            objects.append(object)
            places.append(place)
            motions.append(motion)
        }
        let visibilities = NightPlanner.visibility(ofFixed: places, properMotions: motions, during: summary,
                                                   darkness: .astronomical, minimumAltitude: minimumTargetAltitude)
        var candidates: [(object: CelestialObject, visibility: TargetVisibility, peak: Double, score: Double)] = []
        for (object, visibility) in zip(objects, visibilities) {
            guard let peak = visibility.maxAltitudeDuringDarkness, peak >= minimumTargetAltitude,
                  visibility.bestTime != nil else { continue }
            candidates.append((object, visibility, peak, score(of: object, peakAltitude: peak)))
        }
        candidates.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.object.id < rhs.object.id
        }
        return candidates.prefix(targetLimit).compactMap { candidate in
            guard let time = candidate.visibility.bestTime else { return nil }
            let frame = SkyFrame(date: time, observer: summary.observer)
            return TonightTarget(
                object: candidate.object, peakAltitude: candidate.peak, peakTime: time,
                peakAzimuth: frame.horizontal(of: candidate.object, refraction: false).azimuth,
                hoursAboveMinimum: candidate.visibility.hoursAboveMinimum)
        }
    }

    private static func isDeepSky(_ object: CelestialObject) -> Bool {
        switch object.group {
        case .galaxies, .nebulae, .clusters: return true
        case .solarSystem, .stars, .special: return false
        }
    }

    /// Rates an object for a wide-field camera: higher in the dark is better, and so are brighter and larger.
    /// Each part runs from 0 to 1; brightness counts most.
    private static func score(of object: CelestialObject, peakAltitude: Double) -> Double {
        let altitude = AstroMath.clamp((peakAltitude - minimumTargetAltitude) / (90 - minimumTargetAltitude), 0, 1)
        // Magnitude 3 and brighter is full marks, magnitude 11 and fainter none.
        let brightness = object.magnitude.flatMap { $0.isFinite ? AstroMath.clamp((11 - $0) / 8, 0, 1) : nil } ?? 0
        // 5′ is a speck, 2° or more a big target for a wide lens.
        let size = object.angularSize.map { AstroMath.clamp(log10($0.majorArcminutes / 5) / 1.4, 0, 1) } ?? 0
        return altitude + 1.5 * brightness + 0.8 * size
    }
}

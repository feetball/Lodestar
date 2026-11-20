import Foundation
import LodestarKit

/// What the Tonight screen shows about comets and asteroids for one night: the comets of the "Bright Comets" card
/// (empty when there is none) and the comets and asteroids that are genuinely good tonight, for the Best Targets list.
struct SmallBodyTonight: Sendable {
    let bright: [SmallBodyListEntry]
    let targets: [TonightTarget]

    static let none = SmallBodyTonight(bright: [], targets: [])
}

/// How a comet of the "Bright Comets" card stands in the dark hours of the night, said the way the Best Targets rows
/// say it: the highest it gets, and for how long it is above `TonightCalculator.minimumTargetAltitude`.
struct SmallBodyNightSight: Sendable, Equatable {
    /// The highest geometric altitude reached while it is dark, in degrees.
    let peakAltitude: Double
    /// When that happens.
    let peakTime: Date
    /// The hours of darkness it is at or above `TonightCalculator.minimumTargetAltitude` (and above the skyline, when
    /// `isOverSkyline`).
    let hoursAboveMinimum: Double
    /// Whether the site's recorded skyline was applied.
    let isOverSkyline: Bool

    /// "Highest 34° at 23:40 · 3h 10m above 20°", or with a skyline "… · 3.4 h clear of your skyline". A comet that
    /// never gets high enough says so: "Stays below 20° while it is dark", "Behind your skyline while it is dark".
    func text(in timeZone: TimeZone, spoken: Bool = false) -> String {
        let minimum = Int(TonightCalculator.minimumTargetAltitude)
        let degrees = spoken ? " degrees" : "\u{00B0}"
        guard hoursAboveMinimum > 0 else {
            if isOverSkyline, peakAltitude >= TonightCalculator.minimumTargetAltitude {
                return "Behind your skyline while it is dark"
            }
            return "Stays below \(minimum)\(degrees) while it is dark"
        }
        let best = "Highest \(AngleFormatter.formatDegrees(peakAltitude, decimals: 0)) at "
            + AppFormat.time(peakTime, in: timeZone)
        let above = isOverSkyline
            ? "\(ObjectsFormat.hours(hoursAboveMinimum, spoken: spoken)) clear of your skyline"
            : "\(TonightFormat.duration(hours: hoursAboveMinimum)) above \(minimum)\(degrees)"
        guard !spoken else { return "\(best), \(above)" }
        return TonightFormat.dotted([TonightFormat.solid(best), TonightFormat.solid(above)])
    }
}

/// Plans the comets and asteroids of a night. Pure, so it can run on any thread (a few milliseconds).
enum SmallBodyTonightPlanner {
    /// The most comets the card shows.
    static let cardCount = 3
    /// The faintest magnitude the card lists: a camera on a tripod.
    static let cardMagnitudeLimit = 10.0
    /// The most comets and asteroids added to the Best Targets list.
    static let targetCount = 3
    /// The faintest magnitude of a Best Target: binoculars or a wide-field camera.
    static let targetMagnitudeLimit = 8.0
    /// A Best Target must spend at least this many hours of the dark above `TonightCalculator.minimumTargetAltitude`.
    static let minimumHours = 1.0
    /// The candidates looked at: the brightest ones at the night's reference time.
    private static let candidateLimit = 30

    /// The comets for the card (bright at the night's reference time) and the comets and asteroids worth a place among
    /// the Best Targets: at most `targetMagnitudeLimit`, 25° or more from the Sun, and at least
    /// `TonightCalculator.minimumTargetAltitude` high for `minimumHours` in the dark (over the skyline, if there is
    /// one). Small bodies are not deep-sky objects, so only the few that are clearly good are ranked; the card lists
    /// the rest.
    static func plan(catalog: Catalog, summary: NightSummary, skyline: HorizonProfile?) -> SmallBodyTonight {
        let bodies = SmallBodyBrightLists.bodies(in: catalog)
        guard !bodies.isEmpty else { return .none }
        let date = summary.referenceDate
        let bright = SmallBodyBrightLists.entries(in: catalog, at: date, period: .now, limit: cardMagnitudeLimit,
                                                  kind: .comets, maximumCount: cardCount)
            .map { entry -> SmallBodyListEntry in
                var entry = entry
                entry.night = nightSight(of: entry.object, summary: summary, skyline: skyline)
                return entry
            }
        return SmallBodyTonight(bright: bright,
                                targets: targets(catalog: catalog, summary: summary, skyline: skyline, date: date,
                                                 bodies: bodies))
    }

    private static func targets(catalog: Catalog, summary: NightSummary, skyline: HorizonProfile?, date: Date,
                                bodies: [SmallBody]) -> [TonightTarget] {
        guard summary.hasAstronomicalDarkness else { return [] }
        let minimum = TonightCalculator.minimumTargetAltitude
        let candidates = SmallBodySelection.brightNow(in: bodies, at: date, magnitudeLimit: targetMagnitudeLimit,
                                                      maximumCount: candidateLimit)
        var targets: [TonightTarget] = []
        for candidate in candidates {
            if targets.count >= targetCount { break }
            guard let object = catalog.object(id: candidate.body.id) else { continue }
            let found = visibility(of: object, summary: summary, skyline: skyline)
            if skyline != nil, found.intervalsAboveMinimum.isEmpty { continue }
            guard let peak = found.maxAltitudeDuringDarkness, let time = found.bestTime,
                  !peak.isNaN, peak >= minimum, found.hoursAboveMinimum >= minimumHours else { continue }
            // Judged where it stands at its best moment: bright enough and clear of the Sun's glow then.
            let frame = SkyFrame(date: time, observer: summary.observer)
            guard let info = SmallBodyInfo.compute(candidate.body, frame: frame), let magnitude = info.magnitude,
                  info.isPhotographable, magnitude <= targetMagnitudeLimit else { continue }
            targets.append(TonightTarget(
                object: object, peakAltitude: peak, peakTime: time,
                peakAzimuth: frame.horizontal(of: object, refraction: false).azimuth,
                hoursAboveMinimum: found.hoursAboveMinimum,
                note: SmallBodyText.summary(of: object, info: info)))
        }
        return targets
    }

    /// How `object` stands in the dark hours of the night; `nil` when there is no astronomical darkness to judge by.
    private static func nightSight(of object: CelestialObject, summary: NightSummary,
                                   skyline: HorizonProfile?) -> SmallBodyNightSight? {
        guard summary.hasAstronomicalDarkness else { return nil }
        let found = visibility(of: object, summary: summary, skyline: skyline)
        guard let peak = found.maxAltitudeDuringDarkness, let time = found.bestTime, !peak.isNaN else { return nil }
        return SmallBodyNightSight(peakAltitude: peak, peakTime: time, hoursAboveMinimum: found.hoursAboveMinimum,
                                   isOverSkyline: skyline != nil)
    }

    /// How well `object` can be observed during the dark hours of the night (the planner's one-object call, about 1 ms).
    private static func visibility(of object: CelestialObject, summary: NightSummary,
                                   skyline: HorizonProfile?) -> TargetVisibility {
        let position: (SkyFrame) -> HorizontalCoordinate = { frame in frame.horizontal(of: object, refraction: false) }
        let minimum = TonightCalculator.minimumTargetAltitude
        if let skyline {
            return NightPlanner.visibility(of: position, during: summary, darkness: .astronomical,
                                           minimumAltitude: minimum, horizon: skyline)
        }
        return NightPlanner.visibility(of: position, during: summary, darkness: .astronomical,
                                       minimumAltitude: minimum)
    }
}

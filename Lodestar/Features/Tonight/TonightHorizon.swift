import Foundation
import LodestarKit

/// Applies the observing site's recorded skyline to a night's summary: the Moon, the Milky Way's core and the planets
/// are judged by when they clear and sink behind the trees and ridges instead of by a flat horizon. Pure, so it can
/// run on any thread.
enum TonightHorizon {
    /// The Galactic Centre (Sagittarius A*), J2000: 17h 45m 40.04s, −29° 00′ 28.1″.
    static let galacticCentre = EquatorialCoordinate(rightAscensionHours: 17 + 45.0 / 60 + 40.04 / 3600,
                                                     declination: -(29 + 28.1 / 3600))

    /// The skyline to apply for `context`: the site's recorded one, or `nil` for an open horizon. A flat profile counts
    /// as none, so it neither slows the planner down nor shows a "skyline applied" note.
    static func skyline(of context: ObserverContext) -> HorizonProfile? {
        guard let horizon = context.horizon, !horizon.isFlat else { return nil }
        return horizon
    }

    /// `flat`, with the Moon, the core and the planets recomputed over `horizon`.
    ///
    /// The Moon is "up" while it is above the skyline, and the dark hours without the Moon follow that. The core and
    /// the planets are usable while they are above the skyline and at least their minimum altitude high in the dark.
    static func summary(_ flat: NightSummary, applying horizon: HorizonProfile) -> NightSummary {
        let visibility = HorizonVisibility(profile: horizon)
        let observer = flat.observer
        let moonEvents = visibility.riseTransitSet(for: .moon, observer: observer, within: flat.night)
        let moonUp = visibility.visibleWindows(of: .moon, observer: observer, within: flat.night)
        let moon = MoonSummary(phase: flat.moon.phase, riseTransitSet: moonEvents, upIntervals: moonUp)
        let moonFree = subtracting(moonUp, from: flat.astronomicalDarknessIntervals)
        // The core and the planets are ranked against the dark hours, so they need the Moon's new hours first.
        let withMoon = NightSummary(
            observer: observer, night: flat.night, twilight: flat.twilight, referenceDate: flat.referenceDate,
            moon: moon, astronomicalDarknessIntervals: flat.astronomicalDarknessIntervals,
            darknessIntervals: moonFree, milkyWayCore: flat.milkyWayCore, planets: flat.planets)
        return NightSummary(
            observer: observer, night: flat.night, twilight: flat.twilight, referenceDate: flat.referenceDate,
            moon: moon, astronomicalDarknessIntervals: flat.astronomicalDarknessIntervals,
            darknessIntervals: moonFree,
            milkyWayCore: milkyWayCore(of: withMoon, horizon: horizon),
            planets: withMoon.planets.map { adjusted($0, in: withMoon, horizon: horizon) })
    }

    // MARK: Milky Way core and planets

    private static func milkyWayCore(of summary: NightSummary, horizon: HorizonProfile) -> MilkyWayCoreVisibility {
        let minimum = MilkyWayCoreVisibility.minimumAltitude
        let core = [galacticCentre]
        let inDark = NightPlanner.visibility(ofFixed: core, during: summary, darkness: .astronomical,
                                             minimumAltitude: minimum, horizon: horizon)[0]
        let moonFree = NightPlanner.visibility(ofFixed: core, during: summary, darkness: .moonFree,
                                               minimumAltitude: minimum, horizon: horizon)[0]
        let best = moonFree.intervalsAboveMinimum.isEmpty ? inDark : moonFree
        let hasWindow = !best.intervalsAboveMinimum.isEmpty
        let bestTime = hasWindow ? best.bestTime : nil
        let azimuth = bestTime.map {
            SkyFrame(date: $0, observer: summary.observer).horizontal(j2000: galacticCentre, refraction: false).azimuth
        }
        return MilkyWayCoreVisibility(
            riseTransitSet: inDark.riseTransitSet,
            visibleIntervals: inDark.intervalsAboveMinimum,
            moonFreeVisibleIntervals: moonFree.intervalsAboveMinimum,
            bestTime: bestTime,
            maxAltitude: hasWindow ? best.maxAltitudeDuringDarkness : nil,
            bestAzimuth: azimuth)
    }

    private static func adjusted(_ planet: PlanetVisibility, in summary: NightSummary,
                                 horizon: HorizonProfile) -> PlanetVisibility {
        let found = NightPlanner.visibility(of: planet.body, during: summary, darkness: .astronomical,
                                            minimumAltitude: PlanetVisibility.minimumAltitude, horizon: horizon)
        let isUsable = !found.intervalsAboveMinimum.isEmpty
        return PlanetVisibility(
            body: planet.body, riseTransitSet: found.riseTransitSet, visibleIntervals: found.intervalsAboveMinimum,
            maxAltitudeDuringDarkness: isUsable ? found.maxAltitudeDuringDarkness : planet.maxAltitudeDuringDarkness,
            magnitude: planet.magnitude)
    }

    // MARK: Intervals

    /// The parts of `base` that are not covered by `removed`. Both lists are in time order, without overlaps.
    static func subtracting(_ removed: [DateInterval], from base: [DateInterval]) -> [DateInterval] {
        let cuts = removed.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in base {
            var cursor = interval.start
            for cut in cuts where cut.end > cursor && cut.start < interval.end {
                if cut.start > cursor {
                    result.append(DateInterval(start: cursor, end: cut.start))
                }
                cursor = max(cursor, cut.end)
            }
            if cursor < interval.end {
                result.append(DateInterval(start: cursor, end: interval.end))
            }
        }
        return result
    }
}

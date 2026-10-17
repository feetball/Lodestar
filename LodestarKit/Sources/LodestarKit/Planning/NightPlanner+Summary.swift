import Foundation

extension NightPlanner {
    /// Summarises the night that starts on a local date: twilight, the Moon, the dark hours, the Milky
    /// Way's core and the planets.
    ///
    /// The night runs from local noon of the date to local noon of the next day, so one summary covers an
    /// evening and the morning after it. Darkness means astronomical darkness (the Sun more than 18° below
    /// the horizon), reported with and without the Moon above the horizon. The Moon's phase and the
    /// planets' magnitudes are evaluated at astronomical dusk (`NightSummary.referenceDate`). A summary
    /// takes a few milliseconds and shares no state, so it can be computed on any thread.
    ///
    /// - Parameters:
    ///   - localDate: Any instant on the desired date in `timeZone`.
    ///   - observer: The place of observation.
    ///   - timeZone: The time zone that defines the local date and noon.
    public static func summary(nightStartingOn localDate: Date, observer: Observer,
                               timeZone: TimeZone) -> NightSummary {
        let twilight = TwilightCalculator.night(startingOn: localDate, observer: observer, timeZone: timeZone)
        let night = twilight.interval
        let astronomical = IntervalSet.normalized(twilight.astronomicalNight.map { [$0] } ?? [])
        let referenceDate = twilight.astronomicalDusk ?? twilight.solarMidnight

        let moon = moonSummary(observer: observer, night: night, referenceDate: referenceDate)
        let sampler = DarknessSampler(observer: observer, intervals: astronomical)
        let moonFree = IntervalSet.subtracting(moon.upIntervals, from: astronomical)
        let referenceTime = JulianDate(date: referenceDate)
        return NightSummary(
            observer: observer, night: night, twilight: twilight, referenceDate: referenceDate, moon: moon,
            astronomicalDarknessIntervals: astronomical, darknessIntervals: moonFree,
            milkyWayCore: milkyWayCore(observer: observer, night: night, sampler: sampler, moonFree: moonFree),
            planets: SolarSystemBody.allCases.filter(\.isPlanet).map {
                planetVisibility($0, observer: observer, night: night, sampler: sampler, referenceTime: referenceTime)
            })
    }

    // MARK: Moon

    private static func moonSummary(observer: Observer, night: DateInterval, referenceDate: Date) -> MoonSummary {
        let events = RiseSetCalculator.riseTransitSet(for: .moon, observer: observer, within: night)
        let crossings = RiseSetCalculator.crossings(of: .moon, observer: observer, within: night)
        return MoonSummary(
            phase: MoonPhaseCalculator.info(at: referenceDate), riseTransitSet: events,
            upIntervals: upIntervals(crossings: crossings, circumstance: events.circumstance, within: night))
    }

    /// The stretches of `window` in which a body is above the horizon, given all its horizon crossings
    /// there. With no crossing the body is up throughout or not at all, as `circumstance` says;
    /// otherwise it starts the window up when the first crossing is a setting.
    static func upIntervals(crossings: [AltitudeCrossing], circumstance: RiseTransitSet.Circumstance,
                            within window: DateInterval) -> [DateInterval] {
        var risenAt: Date?
        if let first = crossings.first {
            if first.kind == .setting { risenAt = window.start }
        } else if circumstance == .alwaysUp {
            risenAt = window.start
        }
        var intervals = [DateInterval]()
        for crossing in crossings {
            switch crossing.kind {
            case .rising:
                risenAt = crossing.time
            case .setting:
                if let start = risenAt { intervals.append(DateInterval(start: start, end: crossing.time)) }
                risenAt = nil
            }
        }
        if let start = risenAt { intervals.append(DateInterval(start: start, end: window.end)) }
        return IntervalSet.normalized(intervals)
    }

    // MARK: Milky Way core and planets

    private static func milkyWayCore(observer: Observer, night: DateInterval, sampler: DarknessSampler,
                                     moonFree: [DateInterval]) -> MilkyWayCoreVisibility {
        let core = MilkyWayCoreVisibility.galacticCentre
        let direction = core.unitVector
        let profile = sampler.profile { $0.horizontalVector(j2000UnitVector: direction).z }
        let visible = profile.intervals(atOrAbove: AstroMath.sinDeg(MilkyWayCoreVisibility.minimumAltitude))
        let moonFreeVisible = IntervalSet.intersection(visible, moonFree)
        let best = profile.maximum(within: moonFreeVisible.isEmpty ? visible : moonFreeVisible)
        let bestAzimuth = best.map {
            SkyFrame(date: $0.date, observer: observer).horizontal(j2000: core, refraction: false).azimuth
        }
        return MilkyWayCoreVisibility(
            riseTransitSet: RiseSetCalculator.riseTransitSet(forJ2000: core, observer: observer, within: night),
            visibleIntervals: visible, moonFreeVisibleIntervals: moonFreeVisible,
            bestTime: best?.date, maxAltitude: best.map { AstroMath.asinDeg($0.sine) }, bestAzimuth: bestAzimuth)
    }

    private static func planetVisibility(_ body: SolarSystemBody, observer: Observer, night: DateInterval,
                                         sampler: DarknessSampler, referenceTime: JulianDate) -> PlanetVisibility {
        let profile = sampler.profile(of: body)
        let peak = profile.maximum(within: profile.darkness)
        return PlanetVisibility(
            body: body,
            riseTransitSet: RiseSetCalculator.riseTransitSet(for: body, observer: observer, within: night),
            visibleIntervals: profile.intervals(atOrAbove: AstroMath.sinDeg(PlanetVisibility.minimumAltitude)),
            maxAltitudeDuringDarkness: peak.map { AstroMath.asinDeg($0.sine) },
            magnitude: Ephemeris.state(of: body, at: referenceTime).apparentMagnitude)
    }
}

import Foundation
import LodestarKit

/// The astronomy behind the object detail screen. Pure, so it can run on any thread.
enum ObjectDetailCalculator {
    /// The spacing of the altitude curve's samples, in seconds.
    static let sampleStep: TimeInterval = 600

    /// Computes the current state of an object and the night around `input.date`.
    static func snapshot(for input: ObjectDetailInput) -> ObjectDetailSnapshot {
        let observer = input.context.observer
        let reusableNight = input.previousNight.flatMap { $0.expiry > input.date ? $0 : nil }
        let tonight = reusableNight ?? night(of: input.object, context: input.context, containing: input.date)
        return ObjectDetailSnapshot(
            current: current(of: input.object, observer: observer, at: input.date),
            night: tonight,
            moon: moonConditions(for: input.object, observer: observer, night: tonight, now: input.date))
    }

    // MARK: Now

    /// Where the object is, how bright, how large and how lit at `date`.
    static func current(of object: CelestialObject, observer: Observer, at date: Date) -> ObjectDetailCurrent {
        let frame = SkyFrame(date: date, observer: observer)
        var distance = object.distanceLightYears.map(ObjectDetailDistance.lightYears)
        var illuminatedFraction: Double?
        var moonPhase: MoonPhaseInfo?
        if case .solarSystem(let body) = object.position {
            let state = frame.state(of: body)
            distance = body == .moon ? .kilometers(state.distanceKilometers) : .astronomicalUnits(state.distanceAU)
            illuminatedFraction = state.illuminatedFraction
            moonPhase = body == .moon ? MoonPhaseCalculator.info(at: date) : nil
        }
        return ObjectDetailCurrent(
            date: date,
            horizontal: frame.horizontal(of: object, refraction: true),
            equatorial: frame.apparentEquatorial(of: object),
            magnitude: frame.currentMagnitude(of: object),
            angularSize: frame.currentAngularSize(of: object),
            distance: distance,
            illuminatedFraction: illuminatedFraction,
            moonPhase: moonPhase)
    }

    // MARK: Tonight

    /// The night that is under way at `date`, or the coming one when it is day.
    static func night(of object: CelestialObject, context: ObserverContext,
                      containing date: Date) -> ObjectDetailNight {
        let observer = context.observer
        let twilight = currentTwilight(context: context, date: date)
        let interval = twilight.interval
        let chartStart = twilight.sunset ?? interval.start
        let chartEnd = max(twilight.sunrise ?? interval.end, chartStart)
        let chartRange = DateInterval(start: chartStart, end: chartEnd)

        let events = RiseSetCalculator.riseTransitSet(for: object, observer: observer, within: interval)
        let samples = altitudeSamples(of: object, observer: observer, over: chartRange)
        let darkness = twilight.astronomicalNight
        return ObjectDetailNight(
            interval: interval,
            chartRange: chartRange,
            twilight: twilight,
            darkness: darkness,
            events: events,
            transitAltitude: events.transitAltitude.map {
                Refraction.apparentAltitude(trueAltitude: $0, atmosphere: observer.atmosphere)
            },
            samples: samples,
            twilightBands: twilightBands(of: twilight, within: chartRange),
            hourTicks: hourTicks(in: chartRange, calendar: context.calendar),
            bestInDarkness: bestPoint(of: object, observer: observer, samples: samples, darkness: darkness,
                                      transit: events.transit))
    }

    /// The twilight of the night that contains `date`: the one that began at noon yesterday while it is still
    /// before sunrise, otherwise the one that begins at noon today.
    private static func currentTwilight(context: ObserverContext, date: Date) -> NightTwilight {
        let yesterday = context.calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        let previous = TwilightCalculator.night(startingOn: yesterday, observer: context.observer,
                                                timeZone: context.timeZone)
        if date < previous.interval.end, date < (previous.sunrise ?? previous.interval.end) {
            return previous
        }
        return TwilightCalculator.night(startingOn: date, observer: context.observer, timeZone: context.timeZone)
    }

    private static func apparentAltitude(of object: CelestialObject, observer: Observer, at date: Date) -> Double {
        SkyFrame(date: date, observer: observer).horizontal(of: object, refraction: true).altitude
    }

    private static func altitudeSamples(of object: CelestialObject, observer: Observer,
                                        over range: DateInterval) -> [ObjectDetailAltitudeSample] {
        let gaps = range.duration > 0 ? max(1, Int((range.duration / sampleStep).rounded(.up))) : 0
        return (0...gaps).map { step in
            let date = step == gaps ? range.end : range.start.addingTimeInterval(Double(step) * sampleStep)
            return ObjectDetailAltitudeSample(date: date,
                                              altitude: apparentAltitude(of: object, observer: observer, at: date))
        }
    }

    /// The highest apparent altitude during `darkness`, looked for at the samples, the ends of the darkness and
    /// the transit, so that a culmination between two samples is not missed.
    private static func bestPoint(of object: CelestialObject, observer: Observer,
                                  samples: [ObjectDetailAltitudeSample], darkness: DateInterval?,
                                  transit: Date?) -> ObjectDetailPeak? {
        guard let darkness else { return nil }
        var candidates = samples.filter { darkness.contains($0.date) }
            .map { ObjectDetailPeak(date: $0.date, altitude: $0.altitude) }
        var extraDates = [darkness.start, darkness.end]
        if let transit, darkness.contains(transit) {
            extraDates.append(transit)
        }
        candidates += extraDates.map {
            ObjectDetailPeak(date: $0, altitude: apparentAltitude(of: object, observer: observer, at: $0))
        }
        return candidates.max { $0.altitude < $1.altitude }
    }

    /// Hourly labels for the time axis: every hour, every two hours or every four, depending on the length.
    private static func hourTicks(in range: DateInterval, calendar: Calendar) -> [Date] {
        let spacing = range.duration > 18 * 3600 ? 4 : (range.duration > 9 * 3600 ? 2 : 1)
        var ticks: [Date] = []
        var cursor = range.start
        for _ in 0..<48 {
            guard let next = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                                               matchingPolicy: .nextTime),
                  next <= range.end else { break }
            if calendar.component(.hour, from: next) % spacing == 0 {
                ticks.append(next)
            }
            cursor = next
        }
        return ticks
    }

    // MARK: Twilight shading

    /// The stretches of the chart in which the Sun lights the sky: daylight and civil, nautical and astronomical
    /// twilight. Full darkness has no band. Works at every latitude, including where the Sun does not set.
    private static func twilightBands(of twilight: NightTwilight,
                                      within range: DateInterval) -> [ObjectDetailTwilightBand] {
        /// The time the Sun is below `threshold`, or `nil` if it never gets that low during the night.
        func below(_ threshold: Double, evening: Date?, morning: Date?) -> DateInterval? {
            guard twilight.sunAltitudeAtMidnight < threshold else { return nil }
            let start = evening ?? twilight.interval.start
            let end = morning ?? twilight.interval.end
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        let horizon = below(RiseSetCalculator.sunHorizonAltitude, evening: twilight.sunset, morning: twilight.sunrise)
        let civil = below(TwilightCalculator.civilAltitude, evening: twilight.civilDusk, morning: twilight.civilDawn)
        let nautical = below(TwilightCalculator.nauticalAltitude, evening: twilight.nauticalDusk,
                             morning: twilight.nauticalDawn)
        let astronomical = below(TwilightCalculator.astronomicalAltitude, evening: twilight.astronomicalDusk,
                                 morning: twilight.astronomicalDawn)

        let regions: [(brightness: Int, intervals: [DateInterval])] = [
            (4, remove(horizon, from: [range])),
            (3, remove(civil, from: horizon.map { [$0] } ?? [])),
            (2, remove(nautical, from: civil.map { [$0] } ?? [])),
            (1, remove(astronomical, from: nautical.map { [$0] } ?? [])),
        ]
        return regions.flatMap { region in
            region.intervals.compactMap { interval -> ObjectDetailTwilightBand? in
                guard let visible = interval.intersection(with: range), visible.duration > 0 else { return nil }
                return ObjectDetailTwilightBand(interval: visible, brightness: region.brightness)
            }
        }
    }

    /// The parts of `intervals` not covered by `removed`.
    private static func remove(_ removed: DateInterval?, from intervals: [DateInterval]) -> [DateInterval] {
        guard let removed else { return intervals }
        return intervals.flatMap { interval -> [DateInterval] in
            var pieces: [DateInterval] = []
            if removed.start > interval.start {
                pieces.append(DateInterval(start: interval.start, end: min(removed.start, interval.end)))
            }
            if removed.end < interval.end {
                pieces.append(DateInterval(start: max(removed.end, interval.start), end: interval.end))
            }
            return pieces
        }
    }

    // MARK: Photography

    /// How the object fits the lens, and the exposure limits for its declination.
    static func photography(of object: CelestialObject, size: AngularSize?, declination: Double?,
                            lens: LensSetup) -> ObjectDetailPhotography {
        let frame = FieldOfView.of(sensor: lens.sensor, focalLength: lens.focalLengthMillimeters)
        let framing = size
            .flatMap { frame.framing(objectMajorArcmin: $0.majorArcminutes,
                                     minorArcmin: $0.minorArcminutes ?? $0.majorArcminutes) }
            .map { ObjectDetailFraming(majorFraction: $0.majorAxisFraction, minorFraction: $0.minorAxisFraction) }
        let tracksStars = object.category != .sun && object.category != .moon
        func exposure(_ rule: ExposureRule) -> ExposureEstimate? {
            tracksStars ? ExposureCalculator.maxExposure(rule: rule, setup: lens, declination: declination) : nil
        }
        return ObjectDetailPhotography(frame: frame, framing: framing,
                                       npf: exposure(.npf), rule500: exposure(.rule500))
    }

    /// How the Moon affects the object: now while the sky is dark, otherwise at the object's best time tonight.
    ///
    /// The impact is a rule of thumb from the Moon's illuminated fraction and its distance from the object.
    static func moonConditions(for object: CelestialObject, observer: Observer, night: ObjectDetailNight,
                               now: Date) -> ObjectDetailMoonConditions? {
        guard object.category != .sun, object.category != .moon else { return nil }
        let isDark = night.darkness?.contains(now) ?? false
        let date = isDark ? now : (night.bestInDarkness?.date ?? now)
        let frame = SkyFrame(date: date, observer: observer)
        let moon = frame.horizontal(of: .moon, refraction: false)
        let separation = frame.horizontal(of: object, refraction: false).angularSeparation(to: moon)
        let illuminatedFraction = frame.state(of: .moon).illuminatedFraction ?? 0
        let impact = moonImpact(moonAltitude: moon.altitude, separation: separation,
                                illuminatedFraction: illuminatedFraction)
        return ObjectDetailMoonConditions(date: date, isNow: date == now, separation: separation,
                                          illuminatedFraction: illuminatedFraction, impact: impact)
    }

    private static func moonImpact(moonAltitude: Double, separation: Double,
                                   illuminatedFraction: Double) -> ObjectDetailMoonConditions.Impact {
        guard moonAltitude > 0 else { return .moonDown }
        // Moonlight scatters across the whole sky but is strongest near the Moon.
        let proximity = min(max(1 - separation / 120, 0.25), 1)
        switch illuminatedFraction * proximity {
        case 0.5...: return .severe
        case 0.2...: return .moderate
        default: return .minor
        }
    }
}

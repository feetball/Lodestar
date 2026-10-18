import Foundation

// The Tonight planner's visibility calls with a skyline. They answer with the same `TargetVisibility` as the
// calls without `horizon`, so a screen switches by adding the argument:
//
// - `riseTransitSet.rise` / `.set` are when the target first clears the skyline / sinks behind it in the night
//   (`circumstance` `.alwaysUp`: visible all night, `.alwaysDown`: hidden all night); `transit` is the culmination.
// - `intervalsAboveMinimum` (and `hoursAboveMinimum`) are the dark stretches in which the target is above the
//   skyline AND at least `minimumAltitude` high.
// - `maxAltitudeDuringDarkness` and `bestTime` are the highest point among those stretches. A target that is
//   never usable has no such stretch; its values then describe its highest point in the dark, hidden or not,
//   so filter on `intervalsAboveMinimum.isEmpty` (not on the altitude) to drop hidden targets.

extension NightPlanner {
    /// How well a target, described by a position function, can be observed during the dark hours of a night
    /// over `horizon`. See `visibility(of:during:darkness:minimumAltitude:)` for the parameters; the function
    /// must return geometric coordinates (`refraction: false`). The cost is a few hundred position evaluations,
    /// each building a `SkyFrame`.
    public static func visibility(of position: (SkyFrame) -> HorizontalCoordinate, during summary: NightSummary,
                                  darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> TargetVisibility {
        visibilityOverHorizon(of: position, observer: summary.observer, night: summary.night,
                              darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude,
                              horizon: horizon)
    }

    /// The position-function overload for a span that stands for both the night and its dark time.
    public static func visibility(of position: (SkyFrame) -> HorizontalCoordinate, observer: Observer,
                                  during interval: DateInterval, minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> TargetVisibility {
        visibilityOverHorizon(of: position, observer: observer, night: interval, darkness: [interval],
                              minimumAltitude: minimumAltitude, horizon: horizon)
    }

    /// How well the Sun, the Moon or a planet can be observed during the dark hours of a night over `horizon`;
    /// the Sun and the Moon count by their upper limb.
    public static func visibility(of body: SolarSystemBody, during summary: NightSummary,
                                  darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> TargetVisibility {
        visibilityOverHorizon(of: body, observer: summary.observer, night: summary.night,
                              darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude,
                              horizon: horizon)
    }

    /// The body overload for a span that stands for both the night and its dark time.
    public static func visibility(of body: SolarSystemBody, observer: Observer, during interval: DateInterval,
                                  minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> TargetVisibility {
        visibilityOverHorizon(of: body, observer: observer, night: interval, darkness: [interval],
                              minimumAltitude: minimumAltitude, horizon: horizon)
    }

    /// How well each of many fixed targets can be observed during the dark hours of a night over `horizon`:
    /// the Tonight list. The frames of the night are built once and shared (a thousand targets take about
    /// half a second, about twice the cost without a skyline). The targets are J2000 places with optional
    /// proper motions, as in `visibility(ofFixed:properMotions:during:darkness:minimumAltitude:)`.
    ///
    /// - Returns: One `TargetVisibility` per target, in the order given.
    public static func visibility(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?] = [],
                                  during summary: NightSummary, darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> [TargetVisibility] {
        visibilityOverHorizon(ofFixed: targets, properMotions: properMotions, observer: summary.observer,
                              night: summary.night, darkness: summary.darkness(darkness),
                              minimumAltitude: minimumAltitude, horizon: horizon)
    }

    /// The batch overload for a span that stands for both the night and its dark time.
    public static func visibility(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?] = [],
                                  observer: Observer, during interval: DateInterval,
                                  minimumAltitude: Double = defaultMinimumAltitude,
                                  horizon: HorizonProfile) -> [TargetVisibility] {
        visibilityOverHorizon(ofFixed: targets, properMotions: properMotions, observer: observer, night: interval,
                              darkness: [interval], minimumAltitude: minimumAltitude, horizon: horizon)
    }

    // MARK: Implementation

    private static func visibilityOverHorizon(of position: (SkyFrame) -> HorizontalCoordinate, observer: Observer,
                                              night: DateInterval, darkness: [DateInterval],
                                              minimumAltitude: Double, horizon: HorizonProfile) -> TargetVisibility {
        withoutActuallyEscaping(position) { position in
            HorizonVisibility(profile: horizon).targetVisibility(
                HorizonFunctionTrack { position(SkyFrame(date: $0, observer: observer)) },
                night: night, darkness: darkness, offset: 0, minimumAltitude: minimumAltitude)
        }
    }

    private static func visibilityOverHorizon(of body: SolarSystemBody, observer: Observer, night: DateInterval,
                                              darkness: [DateInterval], minimumAltitude: Double,
                                              horizon: HorizonProfile) -> TargetVisibility {
        let offset = body == .sun ? RiseSetCalculator.sunHorizonAltitude - RiseSetCalculator.standardHorizonAltitude : 0
        return HorizonVisibility(profile: horizon).targetVisibility(
            HorizonBodyTrack(frames: HorizonSkyFrames(observer: observer), body: body),
            night: night, darkness: darkness, offset: offset, minimumAltitude: minimumAltitude)
    }

    private static func visibilityOverHorizon(ofFixed targets: [EquatorialCoordinate],
                                              properMotions: [ProperMotion?], observer: Observer,
                                              night: DateInterval, darkness: [DateInterval],
                                              minimumAltitude: Double, horizon: HorizonProfile) -> [TargetVisibility] {
        let visibility = HorizonVisibility(profile: horizon)
        let frames = HorizonSkyFrames(observer: observer)
        return targets.indices.map { index in
            let target = targets[index]
            let motion = index < properMotions.count ? properMotions[index] : nil
            guard target.unitVector.isFinite else { return visibility.neverVisible(minimumAltitude: minimumAltitude) }
            let track = HorizonFixedTrack(frames: frames, position: target, properMotion: motion)
            return visibility.targetVisibility(track, night: night, darkness: darkness, offset: 0,
                                               minimumAltitude: minimumAltitude)
        }
    }
}

import Foundation

extension NightPlanner {
    // MARK: One target at a time

    /// How well a target, described by a position function, can be observed during the dark hours of a night.
    ///
    /// The function is called with a `SkyFrame` for each sample instant (every 10 minutes at most across
    /// the dark intervals) and must return the target's geometric horizontal coordinates (use
    /// `refraction: false`). Rise, transit and set use the standard horizon of −0.5667°; for the Sun and
    /// the Moon, whose events are those of the upper limb, pass the body to
    /// `visibility(of:during:darkness:minimumAltitude:)` instead.
    ///
    /// - Parameters:
    ///   - position: The target's horizontal coordinates in the given frame.
    ///   - summary: The night, from `summary(nightStartingOn:observer:timeZone:)`.
    ///   - darkness: Which dark intervals of the night to count.
    ///   - minimumAltitude: The altitude in degrees from which the target is usable.
    public static func visibility(of position: (SkyFrame) -> HorizontalCoordinate, during summary: NightSummary,
                                  darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> TargetVisibility {
        visibility(of: position, observer: summary.observer, night: summary.night,
                   darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude)
    }

    /// How well a target, described by a position function, can be observed during `interval`, which
    /// stands for both the night (for rise, transit and set) and its dark time. See
    /// `visibility(of:during:darkness:minimumAltitude:)`. The cost grows with the length of the interval;
    /// it is meant for spans of up to a few days.
    public static func visibility(of position: (SkyFrame) -> HorizontalCoordinate, observer: Observer,
                                  during interval: DateInterval,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> TargetVisibility {
        visibility(of: position, observer: observer, night: interval, darkness: [interval],
                   minimumAltitude: minimumAltitude)
    }

    /// How well the Sun, the Moon or a planet can be observed during the dark hours of a night.
    ///
    /// Rise, transit and set follow `RiseSetCalculator.riseTransitSet(for:observer:within:)`, so the Moon's
    /// events are those of its upper limb, as in `NightSummary.moon`.
    ///
    /// - Parameters:
    ///   - body: The Sun, the Moon or a planet.
    ///   - summary: The night, from `summary(nightStartingOn:observer:timeZone:)`.
    ///   - darkness: Which dark intervals of the night to count.
    ///   - minimumAltitude: The altitude in degrees from which the body is usable.
    public static func visibility(of body: SolarSystemBody, during summary: NightSummary,
                                  darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> TargetVisibility {
        visibility(of: body, observer: summary.observer, night: summary.night,
                   darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude)
    }

    /// How well the Sun, the Moon or a planet can be observed during `interval`, which stands for both
    /// the night and its dark time. See `visibility(of:during:darkness:minimumAltitude:)`.
    public static func visibility(of body: SolarSystemBody, observer: Observer, during interval: DateInterval,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> TargetVisibility {
        visibility(of: body, observer: observer, night: interval, darkness: [interval],
                   minimumAltitude: minimumAltitude)
    }

    // MARK: Many fixed targets

    /// How well each of many fixed targets can be observed during the dark hours of a night.
    ///
    /// This is the fast path for ranking a catalog (a thousand objects take a few hundredths of a second):
    /// the sky frames for the dark hours are built once and shared by all targets. The targets are J2000
    /// catalog places, moved by their proper motion to the middle of the night when one is given, and
    /// include annual aberration. A target whose coordinates are not finite never rises. To judge a single
    /// object, pass an array of one.
    ///
    /// - Parameters:
    ///   - targets: The J2000 places of the objects.
    ///   - properMotions: The proper motion of each target, in the order of `targets`; a missing or `nil`
    ///     entry means the object has no known proper motion.
    ///   - summary: The night, from `summary(nightStartingOn:observer:timeZone:)`.
    ///   - darkness: Which dark intervals of the night to count.
    ///   - minimumAltitude: The altitude in degrees from which a target is usable.
    /// - Returns: One `TargetVisibility` per target, in the order given.
    public static func visibility(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?] = [],
                                  during summary: NightSummary, darkness: DarknessKind = .astronomical,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> [TargetVisibility] {
        visibility(ofFixed: targets, properMotions: properMotions, observer: summary.observer,
                   night: summary.night, darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude)
    }

    /// How well each of many fixed targets can be observed during `interval`, which stands for both
    /// the night and its dark time. See `visibility(ofFixed:properMotions:during:darkness:minimumAltitude:)`.
    public static func visibility(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?] = [],
                                  observer: Observer, during interval: DateInterval,
                                  minimumAltitude: Double = defaultMinimumAltitude) -> [TargetVisibility] {
        visibility(ofFixed: targets, properMotions: properMotions, observer: observer, night: interval,
                   darkness: [interval], minimumAltitude: minimumAltitude)
    }

    // MARK: Implementation

    private static func visibility(of position: (SkyFrame) -> HorizontalCoordinate, observer: Observer,
                                   night: DateInterval, darkness: [DateInterval],
                                   minimumAltitude: Double) -> TargetVisibility {
        let sampler = DarknessSampler(observer: observer, intervals: darkness)
        let profile = sampler.profile { AstroMath.sinDeg(position($0).altitude) }
        let events = RiseSetCalculator.riseTransitSet(
            of: { position(SkyFrame(date: $0, observer: observer)).altitude },
            threshold: RiseSetCalculator.standardHorizonAltitude, within: night)
        return targetVisibility(profile: profile, events: events, minimumAltitude: minimumAltitude)
    }

    private static func visibility(of body: SolarSystemBody, observer: Observer, night: DateInterval,
                                   darkness: [DateInterval], minimumAltitude: Double) -> TargetVisibility {
        let sampler = DarknessSampler(observer: observer, intervals: darkness)
        return targetVisibility(profile: sampler.profile(of: body),
                                events: RiseSetCalculator.riseTransitSet(for: body, observer: observer, within: night),
                                minimumAltitude: minimumAltitude)
    }

    private static func visibility(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?],
                                   observer: Observer, night: DateInterval, darkness: [DateInterval],
                                   minimumAltitude: Double) -> [TargetVisibility] {
        let sampler = DarknessSampler(observer: observer, intervals: darkness)
        let middle = night.start.addingTimeInterval(night.duration / 2)
        let years = SkyFrame(date: middle, observer: observer).yearsSinceJ2000
        return targets.indices.map { index in
            let target = targets[index]
            let motion = index < properMotions.count ? properMotions[index] : nil
            let direction = motion?.applyToUnitVector(of: target, years: years) ?? target.unitVector
            guard direction.isFinite else {
                return targetVisibility(profile: DarknessProfile(stretches: []), events: Self.neverRises,
                                        minimumAltitude: minimumAltitude)
            }
            let profile = sampler.profile { $0.horizontalVector(j2000UnitVector: direction).z }
            let events = RiseSetCalculator.riseTransitSet(forJ2000: target, properMotion: motion,
                                                          observer: observer, within: night)
            return targetVisibility(profile: profile, events: events, minimumAltitude: minimumAltitude)
        }
    }

    /// The rise, transit and set of a target that has no usable position.
    private static let neverRises = RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: nil,
                                                   circumstance: .alwaysDown)

    private static func targetVisibility(profile: DarknessProfile, events: RiseTransitSet,
                                         minimumAltitude: Double) -> TargetVisibility {
        let minimum = minimumAltitude.isFinite ? AstroMath.clamp(minimumAltitude, -90, 90) : defaultMinimumAltitude
        let peak = profile.maximum(within: profile.darkness)
        return TargetVisibility(
            riseTransitSet: events, minimumAltitude: minimum,
            maxAltitudeDuringDarkness: peak.map { AstroMath.asinDeg($0.sine) }, bestTime: peak?.date,
            intervalsAboveMinimum: profile.intervals(atOrAbove: AstroMath.sinDeg(minimum)))
    }
}

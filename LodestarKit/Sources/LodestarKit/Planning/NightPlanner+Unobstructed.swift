import Foundation

/// How long one target is clear of the skyline during the dark hours of a night.
///
/// Clear means above the skyline (the flat horizon when there is none) and at least the minimum altitude high; see
/// `NightPlanner.unobstructedVisibility(ofFixed:properMotions:during:darkness:minimumAltitude:horizon:)`.
public struct UnobstructedVisibility: Sendable, Hashable {
    /// The stretches of darkness in which the target is clear, in time order. They are the `unobstructedIntervals`
    /// that `TargetVisibility` reports for the same target, night, darkness and skyline.
    public let intervals: [DateInterval]
    /// `true` when the target reaches the minimum altitude in the dark but is never above the skyline then. Always
    /// `false` without a skyline.
    public let isBehindSkyline: Bool

    /// The hours of darkness in `intervals`.
    public var hours: Double {
        NightPlanner.IntervalSet.totalDuration(of: intervals) / 3600
    }

    /// Creates a record.
    public init(intervals: [DateInterval], isBehindSkyline: Bool) {
        self.intervals = intervals
        self.isBehindSkyline = isBehindSkyline
    }
}

extension NightPlanner {
    /// How long each of many fixed targets is clear of the skyline during the dark hours of a night.
    ///
    /// This is the cheap way to ask "how many hours tonight is it above my skyline?" of a whole catalog: it finds the
    /// stretches above the skyline and the minimum altitude and nothing else (no rise, transit and set, no best
    /// time), and builds the sky frames of the night once for all targets. On a desktop JVM, warmed up (the Kotlin
    /// twin), 11,000 targets take about 0.8 s with a skyline and a few hundredths of a second without, a quarter and a
    /// twentieth of what `visibility(ofFixed:...)` with the same arguments costs (3 s and 0.9 s); a phone needs
    /// several times that, so run it off the main thread. The result per target is the one
    /// `visibility(ofFixed:...).unobstructedIntervals` gives, to within a second.
    ///
    /// The targets are J2000 catalog places, moved by their proper motion to the middle of the night when one is
    /// given, and include annual aberration. A target whose coordinates are not finite is never clear. For the Sun,
    /// the Moon, the planets and objects that move on their own, use `visibility(of:...)` with a body or a position
    /// function.
    ///
    /// - Parameters:
    ///   - targets: The J2000 places of the objects.
    ///   - properMotions: The proper motion of each target, in the order of `targets`; a missing or `nil` entry means
    ///     the object has no known proper motion.
    ///   - summary: The night, from `summary(nightStartingOn:observer:timeZone:)`.
    ///   - darkness: Which dark intervals of the night to count.
    ///   - minimumAltitude: The altitude in degrees from which a target is usable; not finite means the default.
    ///   - horizon: The site's skyline, or `nil` for a flat horizon.
    /// - Returns: One `UnobstructedVisibility` per target, in the order given.
    public static func unobstructedVisibility(ofFixed targets: [EquatorialCoordinate],
                                              properMotions: [ProperMotion?] = [], during summary: NightSummary,
                                              darkness: DarknessKind = .astronomical,
                                              minimumAltitude: Double = defaultMinimumAltitude,
                                              horizon: HorizonProfile? = nil) -> [UnobstructedVisibility] {
        unobstructed(ofFixed: targets, properMotions: properMotions, observer: summary.observer, night: summary.night,
                     darkness: summary.darkness(darkness), minimumAltitude: minimumAltitude, horizon: horizon)
    }

    /// How long each of many fixed targets is clear of the skyline during `interval`, which stands for both the
    /// night and its dark time. See
    /// `unobstructedVisibility(ofFixed:properMotions:during:darkness:minimumAltitude:horizon:)`.
    public static func unobstructedVisibility(ofFixed targets: [EquatorialCoordinate],
                                              properMotions: [ProperMotion?] = [], observer: Observer,
                                              during interval: DateInterval,
                                              minimumAltitude: Double = defaultMinimumAltitude,
                                              horizon: HorizonProfile? = nil) -> [UnobstructedVisibility] {
        unobstructed(ofFixed: targets, properMotions: properMotions, observer: observer, night: interval,
                     darkness: [interval], minimumAltitude: minimumAltitude, horizon: horizon)
    }

    // MARK: Implementation

    private static func unobstructed(ofFixed targets: [EquatorialCoordinate], properMotions: [ProperMotion?],
                                     observer: Observer, night: DateInterval, darkness: [DateInterval],
                                     minimumAltitude: Double, horizon: HorizonProfile?) -> [UnobstructedVisibility] {
        let minimum = minimumAltitude.isFinite ? AstroMath.clamp(minimumAltitude, -90, 90) : defaultMinimumAltitude
        let sampler = DarknessSampler(observer: observer, intervals: darkness)
        let middle = night.start.addingTimeInterval(night.duration / 2)
        let years = SkyFrame(date: middle, observer: observer).yearsSinceJ2000
        let threshold = AstroMath.sinDeg(minimum)

        // The stretches above the minimum altitude over a flat horizon, as `visibility` finds them.
        func openHorizon(_ index: Int) -> [DateInterval] {
            let target = targets[index]
            let motion = index < properMotions.count ? properMotions[index] : nil
            let direction = motion?.applyToUnitVector(of: target, years: years) ?? target.unitVector
            guard direction.isFinite else { return [] }
            return sampler.profile { $0.horizontalVector(j2000UnitVector: direction).z }
                .intervals(atOrAbove: threshold)
        }

        guard let horizon else {
            return targets.indices.map { UnobstructedVisibility(intervals: openHorizon($0), isBehindSkyline: false) }
        }
        let clear = HorizonVisibility(profile: horizon).visibleWindows(
            ofFixed: targets, properMotions: properMotions, observer: observer, during: darkness,
            minimumAltitude: minimum)
        return targets.indices.map { index in
            let windows = clear[index]
            return UnobstructedVisibility(intervals: windows,
                                          isBehindSkyline: windows.isEmpty && !openHorizon(index).isEmpty)
        }
    }
}

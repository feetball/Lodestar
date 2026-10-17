import Foundation

/// Which dark time a visibility calculation counts.
public enum DarknessKind: String, CaseIterable, Codable, Sendable {
    /// The Sun is more than 18° below the horizon.
    case astronomical
    /// The Sun is more than 18° below the horizon and the Moon is below the horizon too (the Moon's upper
    /// limb, after standard refraction, as in `RiseSetCalculator`).
    case moonFree
}

/// How well a target can be observed during the dark hours of one night.
///
/// Altitudes are geometric (no refraction), the altitude of the target's centre seen from the
/// observer. The target is judged only while it is dark; `riseTransitSet` covers the whole night.
public struct TargetVisibility: Sendable, Hashable {
    /// When the target rises, culminates and sets in the night, with the horizon at −0.5667°
    /// (see `RiseSetCalculator`).
    public let riseTransitSet: RiseTransitSet
    /// The altitude, in degrees, that `intervalsAboveMinimum` and `hoursAboveMinimum` refer to.
    public let minimumAltitude: Double
    /// The highest altitude reached while it is dark, in degrees. It is negative for a target that
    /// stays below the horizon, and `nil` when there is no darkness at all. The value is good to a few
    /// thousandths of a degree, and to 0.03° for a target that passes within a degree of the zenith.
    public let maxAltitudeDuringDarkness: Double?
    /// The instant of `maxAltitudeDuringDarkness`; `nil` when there is no darkness.
    public let bestTime: Date?
    /// The stretches of darkness in which the target is at or above `minimumAltitude`, in time order.
    public let intervalsAboveMinimum: [DateInterval]

    /// The hours of darkness the target spends at or above `minimumAltitude`.
    public var hoursAboveMinimum: Double {
        NightPlanner.IntervalSet.totalDuration(of: intervalsAboveMinimum) / 3600
    }

    /// Creates a visibility record.
    public init(riseTransitSet: RiseTransitSet, minimumAltitude: Double, maxAltitudeDuringDarkness: Double?,
                bestTime: Date?, intervalsAboveMinimum: [DateInterval]) {
        self.riseTransitSet = riseTransitSet
        self.minimumAltitude = minimumAltitude
        self.maxAltitudeDuringDarkness = maxAltitudeDuringDarkness
        self.bestTime = bestTime
        self.intervalsAboveMinimum = intervalsAboveMinimum
    }
}

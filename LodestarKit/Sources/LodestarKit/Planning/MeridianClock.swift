import Foundation

/// The transits of a target across the local meridian that bracket an instant.
public struct MeridianTransits: Sendable, Hashable {
    /// The first transit after the instant, or `nil` when none falls within `MeridianClock.searchHalfSpan` of it: the
    /// Moon's transits are 24 h 50 min apart, so the one on the far side of a transit that has just passed can lie
    /// beyond a day; a target that never transits (a celestial pole, a comet whose orbit cannot be evaluated) has none.
    public let next: Date?
    /// The last transit at or before the instant, with the same limits as `next`.
    public let previous: Date?

    /// Creates the pair of transits.
    public init(next: Date?, previous: Date?) {
        self.next = next
        self.previous = previous
    }
}

/// How long a German equatorial mount can keep tracking before it must flip, and whether it must already.
public struct MeridianFlipWindow: Sendable, Hashable {
    /// Seconds of Universal Time until the hour angle reaches the mount's meridian limit at the sidereal rate;
    /// negative once the limit is behind the mount (the time since it was passed, negated).
    public let secondsUntilLimit: Double

    /// Creates a flip window.
    public init(secondsUntilLimit: Double) {
        self.secondsUntilLimit = secondsUntilLimit
    }

    /// `true` when the target has reached or passed the meridian limit: the mount has to flip.
    public var isPastLimit: Bool { secondsUntilLimit <= 0 }
}

/// The hour angle of a target and the time to its meridian transit, for equatorial mounts that flip at the meridian.
///
/// The hour angle is the angle between the local meridian and the target's hour circle, measured along the equator:
/// zero at the transit, negative in the east (the target has yet to transit), positive in the west (it has transited).
/// Everything here uses the apparent, topocentric place of date, the one the mount's own coordinates refer to.
///
/// A transit is the instant the hour angle is zero: for a star it is also the instant of greatest altitude (the upper
/// culmination of `RiseSetCalculator`); for a body that moves in declination (the Moon above all, whose greatest
/// altitude can come minutes away from the transit) it is the hour angle that counts for a mount.
public enum MeridianClock {
    /// The transit search looks this far (one day, in seconds) before and after the instant.
    public static let searchHalfSpan: TimeInterval = 86_400

    /// The meridian limits `flipWindow(hourAngle:limitDegrees:)` accepts, in degrees past the meridian; others are
    /// clamped into it.
    public static let limitDegreesRange: ClosedRange<Double> = 0...30

    /// The local hour angle of an apparent place, in hours, signed with west positive, in (−12, 12].
    ///
    /// Costs one `SkyFrame` (a few microseconds).
    ///
    /// - Parameters:
    ///   - apparent: The place in the true equator and equinox of date (`SkyFrame.apparentPlace`,
    ///     `SkyFrame.topocentricEquatorial`, `apparentEquatorial(of:)`).
    /// - Returns: The hour angle, or NaN when `apparent` is not finite.
    public static func hourAngle(of apparent: EquatorialCoordinate, at date: Date, observer: Observer) -> Double {
        guard apparent.rightAscension.isFinite else { return .nan }
        return SkyFrame(date: date, observer: observer).hourAngle(apparentRightAscension: apparent.rightAscension) / 15
    }

    /// The transits of a fixed object, found within `searchHalfSpan` of `date`.
    ///
    /// Costs about 300 sky frames (a few milliseconds).
    ///
    /// - Parameters:
    ///   - position: The J2000 catalog place of the object.
    ///   - properMotion: Its proper motion, if known.
    public static func transit(forJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                               around date: Date, observer: Observer) -> MeridianTransits {
        transits(around: date) { instant in
            let frame = SkyFrame(date: instant, observer: observer)
            return frame.hourAngle(apparentRightAscension: frame.apparentPlace(j2000: position,
                                                                                properMotion: properMotion).rightAscension)
        }
    }

    /// The transits of a solar-system `body`, found within `searchHalfSpan` of `date`.
    ///
    /// Costs about 300 ephemeris evaluations (up to a few tens of milliseconds for the Moon).
    public static func transit(for body: SolarSystemBody, around date: Date, observer: Observer) -> MeridianTransits {
        transits(around: date) { instant in
            let frame = SkyFrame(date: instant, observer: observer)
            return frame.hourAngle(apparentRightAscension: frame.topocentricEquatorial(of: body).rightAscension)
        }
    }

    /// The time until a mount that may track `limitDegrees` past the meridian must flip, at the sidereal rate.
    ///
    /// - Parameters:
    ///   - hourAngle: The hour angle of the target in hours, west positive (as `hourAngle(of:at:observer:)` returns
    ///     it); values outside (−12, 12] are wrapped into it.
    ///   - limitDegrees: How far past the meridian the mount may track, in degrees of hour angle (a German equatorial
    ///     mount: 0 flips at the meridian, 10 allows 40 minutes of sidereal time); clamped to `limitDegreesRange`.
    /// - Returns: `nil` when an argument is not finite.
    public static func flipWindow(hourAngle: Double, limitDegrees: Double) -> MeridianFlipWindow? {
        guard hourAngle.isFinite, limitDegrees.isFinite else { return nil }
        let limit = AstroMath.clamp(limitDegrees, limitDegreesRange.lowerBound, limitDegreesRange.upperBound)
        let angle = AstroMath.normalizeSignedDegrees(hourAngle * 15)
        return MeridianFlipWindow(secondsUntilLimit: (limit - angle) / SiderealTime.degreesPerSecond)
    }

    /// The transits within `searchHalfSpan` of `date` of a target whose hour angle in degrees at an instant is
    /// `hourAngleDegrees` (NaN where it cannot be evaluated).
    ///
    /// The search is `RiseSetCalculator.upperCulminations` on cos(hour angle), which has exactly one maximum per transit
    /// whatever the target does in declination.
    static func transits(around date: Date, hourAngleDegrees: (Date) -> Double) -> MeridianTransits {
        let window = DateInterval(start: date.addingTimeInterval(-searchHalfSpan),
                                  end: date.addingTimeInterval(searchHalfSpan))
        let times = RiseSetCalculator.upperCulminations(of: { AstroMath.cosDeg(hourAngleDegrees($0)) }, within: window)
            .map(\.time)
        return MeridianTransits(next: times.first { $0 > date }, previous: times.last { $0 <= date })
    }
}

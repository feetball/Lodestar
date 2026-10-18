import Foundation

/// When targets are visible over a `HorizonProfile`: above the real skyline instead of the flat horizon.
///
/// A target is **visible** while it is not hidden by the skyline at its azimuth. The test is on the
/// target's geometric (not refracted) altitude: it must reach `thresholdAltitude(skylineAltitude:)` of the
/// skyline altitude there, i.e. the altitude at which atmospheric refraction lifts the target to the skyline.
/// For the flat profile this is exactly the horizon of `RiseSetCalculator`, −0.5667° for stars, planets and
/// deep-sky objects and the Moon's upper limb, −0.8333° for the Sun's centre (its upper limb); the refraction
/// allowance shrinks with the skyline altitude as the standard refraction does (0.09° at 10°, nil at 60°). The
/// Moon is visible once its upper limb clears the skyline, the Sun likewise. Refraction is the standard
/// atmosphere (1010 mbar, 10 °C), whatever the observer's weather.
///
/// "Rising" below means **clearing the skyline** and "setting" means **sinking behind it**: the crossings are
/// `AltitudeCrossing`s and the first rise, transit and set a `RiseTransitSet` (whose `rise` is when the
/// target first clears the skyline in the interval and `set` when it first sinks behind it; `transit` is
/// the upper culmination, whether or not hidden then). `alwaysUp` means visible throughout, `alwaysDown`
/// hidden throughout.
///
/// The searches work like `RiseSetCalculator`'s: the margin (altitude minus skyline threshold) is sampled
/// and its sign changes refined to a quarter of a second, with pairs of crossings between two samples (a target
/// that just grazes a ridge) found as well. A flat profile is sampled every 10 minutes, any other every
/// `fineSampleInterval` seconds (the target moves at most half a degree in that time), so features of the
/// skyline as small as its 1° resolution are seen; a change of visibility that lasts less than that and
/// does not come within 0.05° of a sample can be missed. A search over one night costs a few hundred margin
/// evaluations, about 0.1 ms for a fixed object and 0.2 ms for the Moon; the batch functions share the frames
/// of the night between objects.
///
/// Immutable and thread safe: every call builds its own working state.
public struct HorizonVisibility: Sendable, Hashable {
    /// The skyline-only value of the `minimumAltitude` parameters: no minimum altitude.
    public static let noMinimumAltitude = -90.0

    /// Seconds between samples when the profile is not flat: in that time a target moves at most half a
    /// degree across the sky, so the 1° features of a skyline cannot slip between samples.
    public static let fineSampleInterval = 120.0

    /// The standard refraction at the horizon (apparent altitude 0), in degrees, as `Refraction` computes it.
    private static let horizonRefraction = Refraction.refractionForApparentAltitude(0)

    /// The skyline.
    public let profile: HorizonProfile

    /// The geometric altitude thresholds at every whole degree of azimuth, and the first one again at 360°.
    private let geometricThresholds: [Double]
    /// The apparent skyline altitudes, and the first one again at 360°.
    private let apparentThresholds: [Double]
    private let isFlat: Bool

    /// Prepares the visibility searches for `profile`.
    public init(profile: HorizonProfile) {
        self.profile = profile
        geometricThresholds = (0...HorizonProfile.binCount).map {
            Self.thresholdAltitude(skylineAltitude: profile.altitudes[$0 % HorizonProfile.binCount])
        }
        apparentThresholds = (0...HorizonProfile.binCount).map { profile.altitudes[$0 % HorizonProfile.binCount] }
        isFlat = profile.isFlat
    }

    public static func == (lhs: HorizonVisibility, rhs: HorizonVisibility) -> Bool {
        lhs.profile == rhs.profile
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(profile)
    }

    /// The geometric altitude, in degrees, at which a target is seen at the apparent altitude
    /// `skylineAltitude`: the horizon altitude of `RiseSetCalculator` (−0.5667°) for 0°, and the same
    /// allowance scaled by the standard refraction at that altitude otherwise (0.09° at 10°), so that
    /// `thresholdAltitude(skylineAltitude: 0) == RiseSetCalculator.standardHorizonAltitude`. Below 0° the
    /// allowance stays at −0.5667°. A skyline altitude that is not finite gives NaN.
    public static func thresholdAltitude(skylineAltitude: Double) -> Double {
        guard skylineAltitude.isFinite else { return .nan }
        let ratio = Refraction.refractionForApparentAltitude(max(skylineAltitude, 0)) / horizonRefraction
        return skylineAltitude + RiseSetCalculator.standardHorizonAltitude * ratio
    }

    // MARK: At one instant

    /// How far above the skyline a target is, in degrees: its altitude minus the skyline threshold at
    /// `azimuth`. Zero or more means visible. NaN when the numbers are not finite.
    ///
    /// - Parameters:
    ///   - altitude: Altitude of the target's centre in degrees.
    ///   - azimuth: Azimuth in degrees (any angle; wrapped).
    ///   - refracted: `false` (default) when `altitude` is geometric, `true` when it is the apparent altitude
    ///     (as returned by `SkyFrame.horizontal(..., refraction: true)`).
    public func margin(altitude: Double, azimuth: Double, refracted: Bool = false) -> Double {
        altitude - lookupHorizonTable(refracted ? apparentThresholds : geometricThresholds,
                                      AstroMath.normalizeDegrees(azimuth))
    }

    /// Whether a target at `altitude` and `azimuth` is above the skyline (`margin >= 0`); see `margin`.
    public func isVisible(altitude: Double, azimuth: Double, refracted: Bool = false) -> Bool {
        margin(altitude: altitude, azimuth: azimuth, refracted: refracted) >= 0
    }

    /// Whether a fixed object (a J2000 `position` with optional `properMotion`) is above the skyline at `date`.
    public func isVisible(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                          observer: Observer, at date: Date) -> Bool {
        visible(HorizonFixedTrack(frames: HorizonSkyFrames(observer: observer), position: position,
                                  properMotion: properMotion), at: date, offset: 0, refracted: false)
    }

    /// Whether the Sun, the Moon or a planet is above the skyline at `date` (the Sun and the Moon by their
    /// upper limb).
    public func isVisible(of body: SolarSystemBody, observer: Observer, at date: Date) -> Bool {
        visible(HorizonBodyTrack(frames: HorizonSkyFrames(observer: observer), body: body), at: date,
                offset: offset(for: body), refracted: false)
    }

    /// Whether a target described by `position` is above the skyline at `date`.
    ///
    /// - Parameters:
    ///   - position: The target's horizontal coordinates at an instant: geometric, or apparent with `refracted`.
    ///   - refracted: Whether `position` returns refracted (apparent) altitudes.
    public func isVisible(of position: (Date) -> HorizontalCoordinate, at date: Date,
                          refracted: Bool = false) -> Bool {
        withoutActuallyEscaping(position) { position in
            visible(HorizonFunctionTrack(position: position), at: date, offset: 0, refracted: refracted)
        }
    }

    // MARK: Clearing and sinking behind the skyline

    /// Every instant in `interval` at which a fixed object clears the skyline (`rising`) or sinks behind it
    /// (`setting`), in time order.
    ///
    /// - Parameters:
    ///   - position: The J2000 place of the object.
    ///   - properMotion: Its proper motion, if known.
    ///   - minimumAltitude: An altitude in degrees the object must also reach (the Tonight planner's
    ///     minimum); the crossings are those of "above the skyline and above `minimumAltitude`". The default,
    ///     `noMinimumAltitude`, asks for the skyline only.
    public func crossings(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                          observer: Observer, within interval: DateInterval,
                          minimumAltitude: Double = noMinimumAltitude) -> [AltitudeCrossing] {
        search(HorizonFixedTrack(frames: HorizonSkyFrames(observer: observer), position: position,
                                 properMotion: properMotion),
               interval: interval, offset: 0, minimumAltitude: minimumAltitude, refracted: false,
               sampleInterval: nil, tolerance: nil).crossings
    }

    /// Every instant in `interval` at which the Sun, the Moon or a planet clears the skyline (`rising`) or sinks
    /// behind it (`setting`), in time order. The Sun and the Moon count by their upper limb. This is the call for
    /// "the Moon rises behind the ridge at 23:40". See the fixed-object overload for `minimumAltitude`.
    public func crossings(of body: SolarSystemBody, observer: Observer, within interval: DateInterval,
                          minimumAltitude: Double = noMinimumAltitude) -> [AltitudeCrossing] {
        search(HorizonBodyTrack(frames: HorizonSkyFrames(observer: observer), body: body),
               interval: interval, offset: offset(for: body), minimumAltitude: minimumAltitude, refracted: false,
               sampleInterval: nil, tolerance: nil).crossings
    }

    /// Every instant in `interval` at which a target described by `position` clears the skyline or sinks behind
    /// it. The function must be continuous in time. See the fixed-object overload for `minimumAltitude`.
    ///
    /// - Parameters:
    ///   - position: The target's horizontal coordinates at an instant: geometric, or apparent with `refracted`.
    ///   - refracted: Whether `position` returns refracted (apparent) altitudes.
    ///   - sampleInterval: Seconds between samples, 1…600; `nil` chooses 600 for a flat profile and
    ///     `fineSampleInterval` otherwise.
    ///   - tolerance: The resolution of the returned times in seconds (at least a millisecond).
    public func crossings(of position: (Date) -> HorizontalCoordinate, within interval: DateInterval,
                          refracted: Bool = false, minimumAltitude: Double = noMinimumAltitude,
                          sampleInterval: TimeInterval? = nil,
                          tolerance: TimeInterval = RiseSetCalculator.defaultTolerance) -> [AltitudeCrossing] {
        withoutActuallyEscaping(position) { position in
            search(HorizonFunctionTrack(position: position), interval: interval, offset: 0,
                   minimumAltitude: minimumAltitude, refracted: refracted, sampleInterval: sampleInterval,
                   tolerance: tolerance).crossings
        }
    }

    /// The first time a fixed object clears the skyline, culminates and sinks behind it inside `interval`
    /// (see the type documentation for the meaning of rise and set here).
    public func riseTransitSet(forJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                               observer: Observer, within interval: DateInterval) -> RiseTransitSet {
        riseTransitSet(HorizonFixedTrack(frames: HorizonSkyFrames(observer: observer), position: position,
                                         properMotion: properMotion),
                       interval: interval, offset: 0, refracted: false, sampleInterval: nil, tolerance: nil)
    }

    /// The first time the Sun, the Moon or a planet clears the skyline, culminates and sinks behind it inside
    /// `interval`; the Sun and the Moon by their upper limb.
    public func riseTransitSet(for body: SolarSystemBody, observer: Observer,
                               within interval: DateInterval) -> RiseTransitSet {
        riseTransitSet(HorizonBodyTrack(frames: HorizonSkyFrames(observer: observer), body: body),
                       interval: interval, offset: offset(for: body), refracted: false, sampleInterval: nil,
                       tolerance: nil)
    }

    /// The first time a target described by `position` clears the skyline, culminates and sinks behind it inside
    /// `interval`. See the generic `crossings(of:within:refracted:minimumAltitude:sampleInterval:tolerance:)`
    /// for the parameters.
    public func riseTransitSet(of position: (Date) -> HorizontalCoordinate, within interval: DateInterval,
                               refracted: Bool = false, sampleInterval: TimeInterval? = nil,
                               tolerance: TimeInterval = RiseSetCalculator.defaultTolerance) -> RiseTransitSet {
        withoutActuallyEscaping(position) { position in
            riseTransitSet(HorizonFunctionTrack(position: position), interval: interval, offset: 0,
                           refracted: refracted, sampleInterval: sampleInterval, tolerance: tolerance)
        }
    }

    // MARK: Visible windows

    /// The stretches of `intervals` (for example tonight's darkness) in which a fixed object is above the
    /// skyline and at least `minimumAltitude` high, sorted and without overlaps. Cost: a few hundred margin
    /// evaluations (about 0.07 ms) for a night.
    public func visibleWindows(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                               observer: Observer, during intervals: [DateInterval],
                               minimumAltitude: Double = noMinimumAltitude) -> [DateInterval] {
        windows(HorizonFixedTrack(frames: HorizonSkyFrames(observer: observer), position: position,
                                  properMotion: properMotion),
                intervals: intervals, offset: 0, minimumAltitude: minimumAltitude, refracted: false,
                sampleInterval: nil, tolerance: nil)
    }

    /// The stretches of `interval` in which a fixed object is above the skyline; see the overload for several
    /// intervals.
    public func visibleWindows(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                               observer: Observer, within interval: DateInterval,
                               minimumAltitude: Double = noMinimumAltitude) -> [DateInterval] {
        visibleWindows(ofJ2000: position, properMotion: properMotion, observer: observer, during: [interval],
                       minimumAltitude: minimumAltitude)
    }

    /// The stretches of `intervals` in which the Sun, the Moon or a planet is above the skyline (see the
    /// fixed-object overload).
    public func visibleWindows(of body: SolarSystemBody, observer: Observer, during intervals: [DateInterval],
                               minimumAltitude: Double = noMinimumAltitude) -> [DateInterval] {
        windows(HorizonBodyTrack(frames: HorizonSkyFrames(observer: observer), body: body),
                intervals: intervals, offset: offset(for: body), minimumAltitude: minimumAltitude,
                refracted: false, sampleInterval: nil, tolerance: nil)
    }

    /// The stretches of `interval` in which the Sun, the Moon or a planet is above the skyline.
    public func visibleWindows(of body: SolarSystemBody, observer: Observer, within interval: DateInterval,
                               minimumAltitude: Double = noMinimumAltitude) -> [DateInterval] {
        visibleWindows(of: body, observer: observer, during: [interval], minimumAltitude: minimumAltitude)
    }

    /// The stretches of `intervals` in which a target described by `position` is above the skyline (see the
    /// fixed-object overload and the generic `crossings` for the parameters).
    public func visibleWindows(of position: (Date) -> HorizontalCoordinate, during intervals: [DateInterval],
                               refracted: Bool = false, minimumAltitude: Double = noMinimumAltitude,
                               sampleInterval: TimeInterval? = nil,
                               tolerance: TimeInterval = RiseSetCalculator.defaultTolerance) -> [DateInterval] {
        withoutActuallyEscaping(position) { position in
            windows(HorizonFunctionTrack(position: position), intervals: intervals, offset: 0,
                    minimumAltitude: minimumAltitude, refracted: refracted, sampleInterval: sampleInterval,
                    tolerance: tolerance)
        }
    }

    /// The stretches of `interval` in which a target described by `position` is above the skyline.
    public func visibleWindows(of position: (Date) -> HorizontalCoordinate, within interval: DateInterval,
                               refracted: Bool = false, minimumAltitude: Double = noMinimumAltitude,
                               sampleInterval: TimeInterval? = nil,
                               tolerance: TimeInterval = RiseSetCalculator.defaultTolerance) -> [DateInterval] {
        visibleWindows(of: position, during: [interval], refracted: refracted, minimumAltitude: minimumAltitude,
                       sampleInterval: sampleInterval, tolerance: tolerance)
    }

    /// The visible windows of many fixed objects in the same `intervals`, one array per object in the order
    /// given (700 objects through a night take about a tenth of a second). The frames of the night are built
    /// once and shared; a position that is not finite is never visible.
    ///
    /// - Parameters:
    ///   - positions: The J2000 places of the objects.
    ///   - properMotions: The proper motion of each object in the order of `positions`; a missing or `nil`
    ///     entry means none.
    public func visibleWindows(ofFixed positions: [EquatorialCoordinate], properMotions: [ProperMotion?] = [],
                               observer: Observer, during intervals: [DateInterval],
                               minimumAltitude: Double = noMinimumAltitude) -> [[DateInterval]] {
        let frames = HorizonSkyFrames(observer: observer)
        let dark = NightPlanner.IntervalSet.normalized(intervals)
        return positions.indices.map { index in
            let position = positions[index]
            guard position.unitVector.isFinite else { return [] }
            let motion = index < properMotions.count ? properMotions[index] : nil
            return windows(HorizonFixedTrack(frames: frames, position: position, properMotion: motion),
                           intervals: dark, offset: 0, minimumAltitude: minimumAltitude, refracted: false,
                           sampleInterval: nil, tolerance: nil)
        }
    }

    // MARK: Planner records

    /// Rise, transit and set over the skyline during `night` and the usable windows in `darkness`, as the
    /// Tonight planner's `TargetVisibility` (see `NightPlanner.visibility` with a `horizon`).
    func targetVisibility(_ track: HorizonSkyTrack, night: DateInterval, darkness: [DateInterval], offset: Double,
                          minimumAltitude: Double) -> TargetVisibility {
        let minimum = clampedMinimum(minimumAltitude)
        let skyline = search(track, interval: night, offset: offset, minimumAltitude: Self.noMinimumAltitude,
                             refracted: false, sampleInterval: nil, tolerance: nil)
        let peaks = culminations(of: track, interval: night, tolerance: RiseSetCalculator.defaultTolerance)
        let summary = events(of: skyline, culmination: peaks.first)
        let dark = NightPlanner.IntervalSet.normalized(darkness)
        let usable = windows(track, intervals: dark, offset: offset, minimumAltitude: minimum, refracted: false,
                             sampleInterval: nil, tolerance: nil)
        if dark.isEmpty {
            return TargetVisibility(riseTransitSet: summary, minimumAltitude: minimum, maxAltitudeDuringDarkness: nil,
                                    bestTime: nil, intervalsAboveMinimum: [])
        }

        // The best moment is the highest point while the target is usable; a target that never is is judged
        // by its highest point in the dark, hidden or not.
        let spans = usable.isEmpty ? dark : usable
        var bestTime: Date?
        var bestAltitude = -Double.infinity
        func consider(_ time: Date, _ altitude: Double) {
            if altitude > bestAltitude {
                bestAltitude = altitude
                bestTime = time
            }
        }
        for span in spans {
            for time in [span.start, span.end] {
                track.evaluate(time: time.timeIntervalSinceReferenceDate, wantsAzimuth: false)
                consider(time, track.altitude)
            }
            for culmination in peaks where culmination.time >= span.start && culmination.time <= span.end {
                consider(culmination.time, culmination.altitude)
            }
        }
        return TargetVisibility(riseTransitSet: summary, minimumAltitude: minimum,
                                maxAltitudeDuringDarkness: bestTime != nil ? bestAltitude : nil,
                                bestTime: bestTime, intervalsAboveMinimum: usable)
    }

    /// The record of a target that has no usable position: it never rises.
    func neverVisible(minimumAltitude: Double) -> TargetVisibility {
        TargetVisibility(
            riseTransitSet: RiseTransitSet(rise: nil, transit: nil, set: nil, transitAltitude: nil,
                                           circumstance: .alwaysDown),
            minimumAltitude: clampedMinimum(minimumAltitude), maxAltitudeDuringDarkness: nil, bestTime: nil,
            intervalsAboveMinimum: [])
    }

    private func clampedMinimum(_ minimumAltitude: Double) -> Double {
        minimumAltitude.isFinite ? AstroMath.clamp(minimumAltitude, -90, 90) : NightPlanner.defaultMinimumAltitude
    }

    // MARK: Search

    /// The crossings found in a search and whether the target was visible at the start.
    private struct Search {
        let crossings: [AltitudeCrossing]
        let visibleAtStart: Bool

        var circumstance: RiseTransitSet.Circumstance {
            if !crossings.isEmpty { return .normal }
            return visibleAtStart ? .alwaysUp : .alwaysDown
        }
    }

    private func visible(_ track: HorizonSkyTrack, at date: Date, offset: Double, refracted: Bool) -> Bool {
        let evaluate = HorizonMargin(track: track, table: refracted ? apparentThresholds : geometricThresholds,
                                     offset: offset, minimumAltitude: Self.noMinimumAltitude, wantsAzimuth: !isFlat)
        return evaluate.margin(at: date.timeIntervalSinceReferenceDate) >= 0
    }

    private func search(_ track: HorizonSkyTrack, interval: DateInterval, offset: Double, minimumAltitude: Double,
                        refracted: Bool, sampleInterval: TimeInterval?, tolerance: TimeInterval?) -> Search {
        let evaluate = HorizonMargin(track: track, table: refracted ? apparentThresholds : geometricThresholds,
                                     offset: offset, minimumAltitude: minimumAltitude, wantsAzimuth: !isFlat)
        let profile = RiseSetCalculator.Profile(interval: interval, step: step(sampleInterval),
                                                evaluate: { evaluate.sample(at: $0) })
        let crossings = profile.crossings(of: 0, tolerance: resolution(tolerance), evaluate: { evaluate.sample(at: $0) })
        return Search(crossings: crossings, visibleAtStart: profile.samples[0].limbAltitude >= 0)
    }

    private func windows(_ track: HorizonSkyTrack, intervals: [DateInterval], offset: Double, minimumAltitude: Double,
                         refracted: Bool, sampleInterval: TimeInterval?, tolerance: TimeInterval?) -> [DateInterval] {
        var result = [DateInterval]()
        for interval in NightPlanner.IntervalSet.normalized(intervals) {
            let found = search(track, interval: interval, offset: offset, minimumAltitude: minimumAltitude,
                               refracted: refracted, sampleInterval: sampleInterval, tolerance: tolerance)
            result.append(contentsOf: NightPlanner.upIntervals(crossings: found.crossings,
                                                               circumstance: found.circumstance, within: interval))
        }
        return NightPlanner.IntervalSet.normalized(result)
    }

    private func riseTransitSet(_ track: HorizonSkyTrack, interval: DateInterval, offset: Double, refracted: Bool,
                                sampleInterval: TimeInterval?, tolerance: TimeInterval?) -> RiseTransitSet {
        let found = search(track, interval: interval, offset: offset, minimumAltitude: Self.noMinimumAltitude,
                           refracted: refracted, sampleInterval: sampleInterval, tolerance: tolerance)
        let culmination = culminations(of: track, interval: interval, tolerance: resolution(tolerance)).first
        return events(of: found, culmination: culmination)
    }

    private func events(of found: Search, culmination: AltitudeCulmination?) -> RiseTransitSet {
        RiseTransitSet(rise: found.crossings.first { $0.kind == .rising }?.time,
                       transit: culmination?.time,
                       set: found.crossings.first { $0.kind == .setting }?.time,
                       transitAltitude: culmination?.altitude,
                       circumstance: found.circumstance)
    }

    private func culminations(of track: HorizonSkyTrack, interval: DateInterval,
                              tolerance: TimeInterval) -> [AltitudeCulmination] {
        let evaluate = HorizonAltitude(track: track)
        let profile = RiseSetCalculator.Profile(interval: interval, step: RiseSetCalculator.maximumSampleInterval,
                                                evaluate: { evaluate.sample(at: $0) })
        return profile.upperCulminations(tolerance: tolerance, evaluate: { evaluate.sample(at: $0) })
    }

    private func step(_ sampleInterval: TimeInterval?) -> TimeInterval {
        let automatic = isFlat ? RiseSetCalculator.maximumSampleInterval : Self.fineSampleInterval
        guard let sampleInterval, sampleInterval.isFinite else { return automatic }
        return AstroMath.clamp(sampleInterval, 1, RiseSetCalculator.maximumSampleInterval)
    }

    private func resolution(_ tolerance: TimeInterval?) -> TimeInterval {
        if let tolerance, tolerance.isFinite { return max(tolerance, 0.001) }
        return RiseSetCalculator.defaultTolerance
    }

    /// The offset of a body's threshold from the standard one: the Sun's centre sits a semi-diameter lower.
    private func offset(for body: SolarSystemBody) -> Double {
        body == .sun ? RiseSetCalculator.sunHorizonAltitude - RiseSetCalculator.standardHorizonAltitude : 0
    }
}

/// Linear interpolation of a 361-entry table (one entry per whole degree of azimuth and the first repeated at
/// 360°) at `azimuth` in [0, 360); NaN for any other value.
func lookupHorizonTable(_ table: [Double], _ azimuth: Double) -> Double {
    guard azimuth >= 0, azimuth < 360 else { return .nan }
    let lower = Int(azimuth)
    let fraction = azimuth - Double(lower)
    let first = table[lower]
    return first + (table[lower + 1] - first) * fraction
}

/// The margin of a track over the skyline as an altitude curve for `RiseSetCalculator.Profile`: the altitude
/// of the centre plus the limb allowance minus the threshold at the track's azimuth (negative while hidden), and
/// with a minimum altitude the lower of that and the margin over the minimum.
final class HorizonMargin {
    private let track: HorizonSkyTrack
    private let table: [Double]
    private let offset: Double
    private let minimumAltitude: Double
    private let wantsAzimuth: Bool

    init(track: HorizonSkyTrack, table: [Double], offset: Double, minimumAltitude: Double, wantsAzimuth: Bool) {
        self.track = track
        self.table = table
        self.offset = offset
        self.minimumAltitude = minimumAltitude
        self.wantsAzimuth = wantsAzimuth
    }

    /// The margin as a sample for the rise/set machinery.
    func sample(at time: Double) -> RiseSetCalculator.Sample {
        RiseSetCalculator.Sample(centreAltitude: margin(at: time))
    }

    /// The margin at `time` (seconds since the Foundation reference date); NaN when the position is not finite.
    func margin(at time: Double) -> Double {
        track.evaluate(time: time, wantsAzimuth: wantsAzimuth)
        let altitude = track.altitude
        let overSkyline = altitude + track.limbAllowance - (offset + lookupHorizonTable(table, track.azimuth))
        if minimumAltitude <= HorizonVisibility.noMinimumAltitude { return overSkyline }
        // Swift's `min` ignores a NaN second argument, like the Kotlin helper `swiftMin`.
        return min(overSkyline, altitude - minimumAltitude)
    }
}

/// The altitude of a track's centre as an altitude curve for `RiseSetCalculator.Profile` (culminations).
final class HorizonAltitude {
    private let track: HorizonSkyTrack

    init(track: HorizonSkyTrack) {
        self.track = track
    }

    /// The centre altitude as a sample for the rise/set machinery.
    func sample(at time: Double) -> RiseSetCalculator.Sample {
        track.evaluate(time: time, wantsAzimuth: false)
        return RiseSetCalculator.Sample(centreAltitude: track.altitude)
    }
}

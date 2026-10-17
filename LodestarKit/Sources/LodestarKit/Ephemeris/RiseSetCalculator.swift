import Foundation

/// An instant at which a target's altitude passes through a horizon threshold.
public struct AltitudeCrossing: Sendable, Hashable {
    /// The direction of a crossing.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// The altitude increases through the threshold.
        case rising
        /// The altitude decreases through the threshold.
        case setting
    }

    /// The instant of the crossing.
    public let time: Date
    /// Whether the altitude was rising or setting through the threshold.
    public let kind: Kind

    /// Creates a crossing.
    public init(time: Date, kind: Kind) {
        self.time = time
        self.kind = kind
    }
}

/// An upper culmination: a local maximum of a target's altitude.
public struct AltitudeCulmination: Sendable, Hashable {
    /// The instant of maximum altitude.
    public let time: Date
    /// Geometric altitude of the target's centre at `time`, in degrees.
    public let altitude: Double

    /// Creates a culmination.
    public init(time: Date, altitude: Double) {
        self.time = time
        self.altitude = altitude
    }
}

/// The first rise, transit and set of a target inside a time window.
public struct RiseTransitSet: Sendable, Hashable {
    /// Whether the target crosses the horizon in the window at all.
    public enum Circumstance: String, Sendable, Hashable, Codable {
        /// The target crosses the horizon at least once in the window.
        case normal
        /// The target stays above the horizon throughout the window (circumpolar, midnight Sun).
        case alwaysUp
        /// The target stays below the horizon throughout the window.
        case alwaysDown
    }

    /// The first rising crossing in the window, if any.
    public let rise: Date?
    /// The first upper culmination (maximum altitude) strictly inside the window, if any. It is
    /// reported whether or not the target is above the horizon then.
    public let transit: Date?
    /// The first setting crossing in the window, if any.
    public let set: Date?
    /// Geometric altitude of the centre at `transit`, in degrees.
    public let transitAltitude: Double?
    /// Whether the target rises and sets in the window, or stays above or below the horizon throughout.
    public let circumstance: Circumstance

    /// Creates a rise, transit and set summary.
    public init(rise: Date?, transit: Date?, set: Date?, transitAltitude: Double?, circumstance: Circumstance) {
        self.rise = rise
        self.transit = transit
        self.set = set
        self.transitAltitude = transitAltitude
        self.circumstance = circumstance
    }
}

/// Finds when targets rise, culminate and set.
///
/// All altitudes are **geometric** (no refraction) and topocentric, referring to the target's
/// centre; the horizon thresholds below absorb refraction and the apparent size of the Sun and
/// Moon. A search samples the altitude curve every 10 minutes at most, brackets sign changes
/// and refines them to better than a second, so targets that rise or set twice, or only graze
/// the horizon, inside the window are found; a window that contains no crossing is reported
/// as always up or always down.
public enum RiseSetCalculator {
    /// Horizon altitude for stars, planets and deep-sky objects: 34′ of refraction.
    public static let standardHorizonAltitude = -0.5667
    /// Horizon altitude for the Sun's centre: 34′ of refraction plus 16′ of semi-diameter.
    public static let sunHorizonAltitude = -0.8333
    /// The largest interval between altitude samples, in seconds.
    public static let maximumSampleInterval: TimeInterval = 600

    /// The resolution, in seconds, of the event times the searches return.
    public static let defaultTolerance: TimeInterval = 0.25

    // MARK: Generic searches

    /// All instants within `interval` at which `altitude` (degrees) passes through `threshold`.
    ///
    /// - Parameters:
    ///   - altitude: The altitude of the target in degrees at a given instant. It must be
    ///     continuous; values that are not finite are skipped.
    ///   - sampleInterval: Seconds between samples, clamped to 1...`maximumSampleInterval`.
    ///   - tolerance: The resolution of the returned times in seconds (at least a millisecond).
    public static func crossings(of altitude: (Date) -> Double, threshold: Double, within interval: DateInterval,
                                 sampleInterval: TimeInterval = maximumSampleInterval,
                                 tolerance: TimeInterval = defaultTolerance) -> [AltitudeCrossing] {
        withEvaluator(for: altitude) { evaluate in
            let profile = Profile(interval: interval, step: clampedStep(sampleInterval), evaluate: evaluate)
            return profile.crossings(of: threshold, tolerance: clampedTolerance(tolerance), evaluate: evaluate)
        }
    }

    /// All upper culminations (local maxima of `altitude`) strictly inside `interval`.
    public static func upperCulminations(of altitude: (Date) -> Double, within interval: DateInterval,
                                         sampleInterval: TimeInterval = maximumSampleInterval,
                                         tolerance: TimeInterval = defaultTolerance) -> [AltitudeCulmination] {
        withEvaluator(for: altitude) { evaluate in
            let profile = Profile(interval: interval, step: clampedStep(sampleInterval), evaluate: evaluate)
            return profile.upperCulminations(tolerance: clampedTolerance(tolerance), evaluate: evaluate)
        }
    }

    /// The first rise, transit and set of a target whose `altitude` is compared with `threshold`.
    public static func riseTransitSet(of altitude: (Date) -> Double, threshold: Double,
                                      within interval: DateInterval) -> RiseTransitSet {
        withEvaluator(for: altitude) { evaluate in
            riseTransitSet(threshold: threshold, within: interval, evaluate: evaluate)
        }
    }

    // MARK: Solar-system bodies

    /// The first rise, transit and set of `body` inside `interval`, for an observer.
    ///
    /// The Sun uses `sunHorizonAltitude`; the planets `standardHorizonAltitude`. For the Moon the
    /// event is the upper limb touching the horizon after 34′ of refraction, i.e. the centre's
    /// topocentric altitude equals `standardHorizonAltitude` minus the Moon's apparent semi-diameter;
    /// this agrees to within seconds with Meeus' `0.7275·π − 0.5667°` threshold for the
    /// geocentric altitude (which would be about π ≈ 1° too high for a topocentric one).
    public static func riseTransitSet(for body: SolarSystemBody, observer: Observer,
                                      within interval: DateInterval) -> RiseTransitSet {
        riseTransitSet(threshold: threshold(for: body), within: interval,
                       evaluate: evaluator(for: body, observer: observer))
    }

    /// All crossings of `body`'s horizon (see `riseTransitSet(for:observer:within:)`) inside `interval`.
    public static func crossings(of body: SolarSystemBody, observer: Observer,
                                 within interval: DateInterval) -> [AltitudeCrossing] {
        let evaluate = evaluator(for: body, observer: observer)
        let profile = Profile(interval: interval, step: maximumSampleInterval, evaluate: evaluate)
        return profile.crossings(of: threshold(for: body), tolerance: defaultTolerance, evaluate: evaluate)
    }

    /// All upper culminations of `body` inside `interval`.
    public static func upperCulminations(of body: SolarSystemBody, observer: Observer,
                                         within interval: DateInterval) -> [AltitudeCulmination] {
        let evaluate = evaluator(for: body, observer: observer)
        let profile = Profile(interval: interval, step: maximumSampleInterval, evaluate: evaluate)
        return profile.upperCulminations(tolerance: defaultTolerance, evaluate: evaluate)
    }

    // MARK: Fixed positions

    /// The first rise, transit and set of a fixed object inside `interval`, using
    /// `standardHorizonAltitude`.
    ///
    /// - Parameters:
    ///   - position: The J2000 catalog place of the object.
    ///   - properMotion: Its proper motion, if known.
    public static func riseTransitSet(forJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                                      observer: Observer, within interval: DateInterval) -> RiseTransitSet {
        riseTransitSet(threshold: standardHorizonAltitude, within: interval,
                       evaluate: evaluator(forJ2000: position, properMotion: properMotion, observer: observer))
    }

    /// All crossings of the standard horizon by a fixed object inside `interval`.
    public static func crossings(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                                 observer: Observer, within interval: DateInterval) -> [AltitudeCrossing] {
        let evaluate = evaluator(forJ2000: position, properMotion: properMotion, observer: observer)
        let profile = Profile(interval: interval, step: maximumSampleInterval, evaluate: evaluate)
        return profile.crossings(of: standardHorizonAltitude, tolerance: defaultTolerance, evaluate: evaluate)
    }

    /// All upper culminations of a fixed object inside `interval`.
    public static func upperCulminations(ofJ2000 position: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                                         observer: Observer, within interval: DateInterval) -> [AltitudeCulmination] {
        let evaluate = evaluator(forJ2000: position, properMotion: properMotion, observer: observer)
        let profile = Profile(interval: interval, step: maximumSampleInterval, evaluate: evaluate)
        return profile.upperCulminations(tolerance: defaultTolerance, evaluate: evaluate)
    }

    // MARK: Shared machinery

    /// The horizon threshold for the limb-adjusted altitude of `body`.
    private static func threshold(for body: SolarSystemBody) -> Double {
        body == .sun ? sunHorizonAltitude : standardHorizonAltitude
    }

    private static func riseTransitSet(threshold: Double, within interval: DateInterval,
                                       evaluate: Profile.Evaluator) -> RiseTransitSet {
        let profile = Profile(interval: interval, step: maximumSampleInterval, evaluate: evaluate)
        let crossings = profile.crossings(of: threshold, tolerance: defaultTolerance, evaluate: evaluate)
        let culmination = profile.upperCulminations(tolerance: defaultTolerance, evaluate: evaluate).first
        let circumstance: RiseTransitSet.Circumstance
        if !crossings.isEmpty {
            circumstance = .normal
        } else {
            circumstance = profile.samples[0].limbAltitude >= threshold ? .alwaysUp : .alwaysDown
        }
        return RiseTransitSet(rise: crossings.first { $0.kind == .rising }?.time,
                              transit: culmination?.time,
                              set: crossings.first { $0.kind == .setting }?.time,
                              transitAltitude: culmination?.altitude,
                              circumstance: circumstance)
    }

    /// Adapts a caller's altitude function (`Date` → degrees) to the profile's evaluator, which works
    /// in seconds since the reference date.
    private static func withEvaluator<Result>(for altitude: (Date) -> Double,
                                              _ search: (Profile.Evaluator) -> Result) -> Result {
        withoutActuallyEscaping(altitude) { altitude in
            search { Sample(centreAltitude: altitude(Date(timeIntervalSinceReferenceDate: $0))) }
        }
    }

    /// Altitude of a solar-system body for an observer.
    static func evaluator(for body: SolarSystemBody, observer: Observer) -> Profile.Evaluator {
        let sampler = Sampler(target: .body(body), observer: observer)
        return { sampler.sample(at: $0) }
    }

    /// Altitude of a fixed object (apparent place including aberration) for an observer.
    private static func evaluator(forJ2000 position: EquatorialCoordinate, properMotion: ProperMotion?,
                                  observer: Observer) -> Profile.Evaluator {
        let sampler = Sampler(target: .fixed(position, properMotion), observer: observer)
        return { sampler.sample(at: $0) }
    }

    private static func clampedStep(_ step: TimeInterval) -> TimeInterval {
        step.isFinite ? AstroMath.clamp(step, 1, maximumSampleInterval) : maximumSampleInterval
    }

    private static func clampedTolerance(_ tolerance: TimeInterval) -> TimeInterval {
        tolerance.isFinite ? max(tolerance, 0.001) : defaultTolerance
    }
}

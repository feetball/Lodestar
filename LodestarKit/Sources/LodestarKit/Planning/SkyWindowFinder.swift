import Foundation

/// A patch of sky: an azimuth range and an altitude range, as a photographer frames "over that ridge" or "in that
/// gap between the trees".
///
/// Altitudes are **apparent** (refracted), like the skyline of a `HorizonProfile` and what a camera sees. The ends of
/// both ranges belong to the window.
public struct SkyWindow: Sendable, Hashable {
    /// The widest tolerance `around(azimuth:tolerance:minimumAltitude:maximumAltitude:)` and
    /// `skylinePoint(azimuth:horizon:azimuthTolerance:altitudeAbove:)` accept, in degrees: half the circle.
    public static let maximumAzimuthTolerance = 180.0
    /// The azimuth tolerance `skylinePoint(azimuth:horizon:azimuthTolerance:altitudeAbove:)` uses when none is given,
    /// in degrees.
    public static let defaultSkylineTolerance = 3.0

    /// The azimuths of the window, from north through east.
    public let azimuth: AzimuthRange
    /// The lower edge in degrees, [-90, 90].
    public let minimumAltitude: Double
    /// The upper edge in degrees, [minimumAltitude, 90].
    public let maximumAltitude: Double

    /// The window with the given ranges; `nil` unless both altitudes are finite and
    /// `-90 <= minimumAltitude <= maximumAltitude <= 90`.
    public init?(azimuth: AzimuthRange, minimumAltitude: Double, maximumAltitude: Double) {
        guard minimumAltitude.isFinite, maximumAltitude.isFinite else { return nil }
        guard minimumAltitude >= -90, maximumAltitude <= 90, minimumAltitude <= maximumAltitude else { return nil }
        self.azimuth = azimuth
        self.minimumAltitude = minimumAltitude
        self.maximumAltitude = maximumAltitude
    }

    /// The window centred on `azimuth` and extending `tolerance` degrees to either side (the whole circle at 180°);
    /// `nil` when the azimuth or tolerance is not finite or the tolerance is outside
    /// 0…`maximumAzimuthTolerance`, or for altitudes `init(azimuth:minimumAltitude:maximumAltitude:)` rejects.
    public static func around(azimuth: Double, tolerance: Double, minimumAltitude: Double,
                              maximumAltitude: Double) -> SkyWindow? {
        guard azimuth.isFinite, tolerance.isFinite else { return nil }
        guard tolerance >= 0, tolerance <= maximumAzimuthTolerance else { return nil }
        return SkyWindow(azimuth: AzimuthRange(start: azimuth - tolerance, length: 2 * tolerance),
                         minimumAltitude: minimumAltitude, maximumAltitude: maximumAltitude)
    }

    /// The window just above the skyline at `azimuth`: `azimuthTolerance` degrees to either side, and from
    /// `altitudeAbove.lowerBound` to `altitudeAbove.upperBound` degrees above the skyline altitude at `azimuth`
    /// (limited to −90…90°). `nil` when a number is not finite, the tolerance is outside
    /// 0…`maximumAzimuthTolerance` or `altitudeAbove` is outside −90…90°.
    ///
    /// - Parameters:
    ///   - azimuth: The azimuth of the gap or ridge in degrees (any angle).
    ///   - horizon: The recorded skyline.
    ///   - azimuthTolerance: Half the width of the window in degrees.
    ///   - altitudeAbove: The edges of the window above the skyline altitude, in degrees; 0…10 by default.
    public static func skylinePoint(azimuth: Double, horizon: HorizonProfile,
                                    azimuthTolerance: Double = defaultSkylineTolerance,
                                    altitudeAbove: ClosedRange<Double> = 0...10) -> SkyWindow? {
        guard azimuth.isFinite else { return nil }
        guard altitudeAbove.lowerBound.isFinite, altitudeAbove.upperBound.isFinite else { return nil }
        guard altitudeAbove.lowerBound >= -90, altitudeAbove.upperBound <= 90 else { return nil }
        let skyline = horizon.altitude(at: azimuth)
        return around(azimuth: azimuth, tolerance: azimuthTolerance,
                      minimumAltitude: AstroMath.clamp(skyline + altitudeAbove.lowerBound, -90, 90),
                      maximumAltitude: AstroMath.clamp(skyline + altitudeAbove.upperBound, -90, 90))
    }
}

/// What `SkyWindowFinder` follows across the sky.
public enum SkyWindowTarget: Sendable, Hashable {
    /// The Sun, the Moon or a planet.
    case body(SolarSystemBody)
    /// A fixed place: a J2000 position with an optional proper motion.
    case fixed(EquatorialCoordinate, properMotion: ProperMotion? = nil)
    /// The Galactic Centre, the core of the Milky Way (see `MilkyWayCoreVisibility.galacticCentre`).
    case milkyWayCore
    /// Any object of the catalog, a custom target, a comet or an asteroid.
    case catalogObject(CelestialObject)
}

/// How dark the sky must be for a match, judged by the altitude of the Sun's centre.
public enum SkyWindowDarkness: String, CaseIterable, Codable, Sendable {
    /// The Sun is more than 18° below the horizon.
    case astronomical
    /// The Sun is more than 12° below the horizon.
    case nautical
    /// The Sun is more than 6° below the horizon: any darkness at all, twilight included.
    case civil
    /// No condition on the Sun: for the Sun and the Moon themselves, and for daytime alignments.
    case anyTime

    /// The Sun must be below this altitude in degrees; `nil` for no condition.
    public var sunAltitudeLimit: Double? {
        switch self {
        case .astronomical: return TwilightCalculator.astronomicalAltitude
        case .nautical: return TwilightCalculator.nauticalAltitude
        case .civil: return TwilightCalculator.civilAltitude
        case .anyTime: return nil
        }
    }
}

/// What a match may ask of the Moon.
public enum SkyWindowMoonRule: Sendable, Hashable {
    /// The Moon does not matter.
    case unrestricted
    /// The Moon's upper limb is below the horizon (the moment `NightSummary.moon` counts as down).
    case belowHorizon
    /// The sunlit fraction of the Moon's disc is at most `fraction`, [0, 1], whether or not the Moon is up. This
    /// judges the phase only; use `belowHorizon` to ask for the Moon to be down.
    case illuminatedAtMost(Double)
}

/// Why a search could not run.
public enum SkyWindowError: Error, Hashable, Sendable {
    /// `from` or `to` is not a usable date, or `to` precedes `from`.
    case invalidRange(from: Date, to: Date)
    /// The range touches more than `limit` nights (`SkyWindowFinder.maximumNightCount`).
    case rangeTooLong(limit: Int)
    /// The target's position is not a finite place on the sky.
    case invalidTarget
    /// The illuminated fraction of the Moon rule is not a number in [0, 1].
    case invalidMoonRule(fraction: Double)
}

/// The Moon at the middle of a match.
public struct SkyWindowMoonState: Sendable, Hashable {
    /// The apparent altitude of the Moon's centre in degrees.
    public let altitude: Double
    /// The sunlit fraction of the disc, [0, 1].
    public let illuminatedFraction: Double
    /// Whether the Moon's upper limb is above the horizon (−0.5667°, as `RiseSetCalculator`).
    public let isUp: Bool

    /// Creates a Moon state.
    public init(altitude: Double, illuminatedFraction: Double, isUp: Bool) {
        self.altitude = altitude
        self.illuminatedFraction = illuminatedFraction
        self.isUp = isUp
    }
}

/// One stretch of one night in which the target stands in the window.
public struct SkyWindowMatch: Sendable, Hashable {
    /// The night (local noon to local noon) the match belongs to.
    public let night: DateInterval
    /// The first and last moment of the stretch, good to `SkyWindowFinder.refinementTolerance` seconds, inside the
    /// dark time and the search range. A match never crosses local noon, where nights are cut.
    public let interval: DateInterval
    /// The target's azimuth at `midpoint` in degrees.
    public let azimuth: Double
    /// The target's apparent altitude at `midpoint` in degrees.
    public let altitude: Double
    /// The Moon at `midpoint`.
    public let moon: SkyWindowMoonState
    /// Whether the target's apparent centre is at or above the skyline at `midpoint` (always `true` over the flat
    /// horizon unless the target is below it).
    public let isAboveSkyline: Bool

    /// The instant half way between the start and the end of `interval`.
    public var midpoint: Date { interval.start.addingTimeInterval(interval.duration / 2) }

    /// Creates a match.
    public init(night: DateInterval, interval: DateInterval, azimuth: Double, altitude: Double,
                moon: SkyWindowMoonState, isAboveSkyline: Bool) {
        self.night = night
        self.interval = interval
        self.azimuth = azimuth
        self.altitude = altitude
        self.moon = moon
        self.isAboveSkyline = isAboveSkyline
    }
}

/// Finds when a target stands over a patch of sky: "when does the Milky Way core stand over that ridge?".
///
/// For every night (local noon to local noon, as `NightPlanner`) the search samples the target every
/// `sampleInterval` seconds and keeps the moments at which it is inside the `SkyWindow`, the Sun is dark enough and
/// the Moon rule holds; each entry and exit is then refined by bisection to `refinementTolerance` seconds. A
/// crossing shorter than the sampling interval that falls between two samples can be missed; the narrowest window
/// that is certain to be found at the fastest azimuth rate is a few degrees wide.
///
/// Positions come from the horizon module's sky tracks (frames shared per six hours, the Moon and Sun interpolated
/// from ephemeris nodes), geometric and then refracted with the observer's atmosphere. Cost: a night is 288 samples,
/// of which only those with the Sun low enough evaluate the target (about 55 000 horizontal transforms for a year of
/// astronomical darkness at mid-latitudes; 105 000 with `SkyWindowDarkness.anyTime`), plus about 6 evaluations per
/// entry or exit. A fixed target or a planet takes a few hundred milliseconds for a year, a Moon rule about the
/// same again, and a comet or asteroid, whose orbit is propagated for every sample, a few seconds. Limits: a range
/// touches at most `maximumNightCount` nights and the result holds at most `maximumMatchCount` matches (the
/// earliest). A call shares no state and may run on any thread.
///
/// A search that is no longer wanted can be stopped: it checks `Task.isCancelled` before every night and throws
/// `CancellationError` when the task it runs in has been cancelled, so it ends within one night's work. It throws
/// instead of returning the matches found so far, because that list would read as a complete answer (and an empty
/// one as "no match").
public enum SkyWindowFinder {
    /// The longest gap between samples, in seconds.
    public static let sampleInterval = 300.0
    /// The resolution of the entry and exit times, in seconds.
    public static let refinementTolerance = 10.0
    /// The most nights a range may touch.
    public static let maximumNightCount = 400
    /// The most matches returned; a result of this size may have been cut short.
    public static let maximumMatchCount = 200

    /// The stretches in which `target` stands in `window` while the sky is dark enough and the Moon rule holds, in
    /// time order.
    ///
    /// - Parameters:
    ///   - target: What to follow.
    ///   - window: The patch of sky.
    ///   - observer: The place of observation; its atmosphere refracts the altitudes.
    ///   - horizon: The skyline used to set `SkyWindowMatch.isAboveSkyline`; `nil` is the flat horizon.
    ///   - from: The start of the search range.
    ///   - to: The end of the search range.
    ///   - darkness: How low the Sun must be; `SkyWindowDarkness.astronomical` by default.
    ///   - moon: What the Moon must do; no condition by default.
    ///   - timeZone: The time zone that defines the nights.
    /// - Throws: `SkyWindowError.invalidRange` for an unusable range, `SkyWindowError.rangeTooLong` beyond
    ///   `maximumNightCount` nights, `SkyWindowError.invalidTarget` for a target without a finite position and
    ///   `SkyWindowError.invalidMoonRule` for a fraction outside [0, 1]; `CancellationError` when the calling task is
    ///   cancelled before the search has finished.
    public static func matches(target: SkyWindowTarget, window: SkyWindow, observer: Observer,
                               horizon: HorizonProfile? = nil, from: Date, to: Date,
                               darkness: SkyWindowDarkness = .astronomical,
                               moon: SkyWindowMoonRule = .unrestricted, timeZone: TimeZone) throws -> [SkyWindowMatch] {
        if case .illuminatedAtMost(let fraction) = moon, !(fraction >= 0 && fraction <= 1) {
            throw SkyWindowError.invalidMoonRule(fraction: fraction)
        }
        let start = from.timeIntervalSinceReferenceDate
        let end = to.timeIntervalSinceReferenceDate
        guard start.isFinite, end.isFinite, end >= start else { throw SkyWindowError.invalidRange(from: from, to: to) }
        let nights = try nightsTouching(from: from, to: to, timeZone: timeZone)
        let search = try Search(target: target, window: window, observer: observer, horizon: horizon,
                                darkness: darkness, rule: moon)
        var found = [SkyWindowMatch]()
        for night in nights {
            try Task.checkCancellation()
            let rangeStart = max(night.start.timeIntervalSinceReferenceDate, start)
            let rangeEnd = min(night.end.timeIntervalSinceReferenceDate, end)
            guard rangeEnd > rangeStart else { continue }
            search.scan(night: night, rangeStart: rangeStart, rangeEnd: rangeEnd, into: &found)
            if found.count >= maximumMatchCount { break }
        }
        return found
    }

    /// The nights, local noon to local noon, that touch `from`…`to`.
    private static func nightsTouching(from: Date, to: Date, timeZone: TimeZone) throws -> [DateInterval] {
        var nights = [DateInterval]()
        var night = TwilightCalculator.nightInterval(startingOn: from, timeZone: timeZone)
        if from < night.start {
            night = TwilightCalculator.nightInterval(startingOn: night.start.addingTimeInterval(-86_400),
                                                     timeZone: timeZone)
        }
        while night.start < to {
            if nights.count == maximumNightCount { throw SkyWindowError.rangeTooLong(limit: maximumNightCount) }
            nights.append(night)
            night = TwilightCalculator.nightInterval(startingOn: night.end, timeZone: timeZone)
        }
        return nights
    }

    /// The state of one search: the tracks of the target, the Sun and the Moon, and the test every sample goes through.
    private final class Search {
        private let window: SkyWindow
        private let observer: Observer
        private let darkness: SkyWindowDarkness
        private let rule: SkyWindowMoonRule
        private let skyline: HorizonVisibility
        private let track: HorizonSkyTrack
        private let sun: HorizonSkyTrack
        private let moonTrack: HorizonSkyTrack

        init(target: SkyWindowTarget, window: SkyWindow, observer: Observer, horizon: HorizonProfile?,
             darkness: SkyWindowDarkness, rule: SkyWindowMoonRule) throws {
            let frames = HorizonSkyFrames(observer: observer)
            self.window = window
            self.observer = observer
            self.darkness = darkness
            self.rule = rule
            skyline = HorizonVisibility(profile: horizon ?? .flat)
            track = try Self.makeTrack(target, frames: frames, observer: observer)
            sun = HorizonBodyTrack(frames: frames, body: .sun)
            moonTrack = HorizonBodyTrack(frames: frames, body: .moon)
        }

        private static func makeTrack(_ target: SkyWindowTarget, frames: HorizonSkyFrames,
                                      observer: Observer) throws -> HorizonSkyTrack {
            switch target {
            case .body(let body):
                return HorizonBodyTrack(frames: frames, body: body)
            case .fixed(let coordinate, let properMotion):
                return try fixedTrack(coordinate, properMotion, frames: frames)
            case .milkyWayCore:
                return try fixedTrack(MilkyWayCoreVisibility.galacticCentre, nil, frames: frames)
            case .catalogObject(let object):
                switch object.position {
                case .fixed(let coordinate, let properMotion):
                    return try fixedTrack(coordinate, properMotion, frames: frames)
                case .solarSystem(let body):
                    return HorizonBodyTrack(frames: frames, body: body)
                case .celestialPole, .smallBody:
                    return HorizonFunctionTrack { SkyFrame(date: $0, observer: observer).horizontal(of: object, refraction: false) }
                }
            }
        }

        private static func fixedTrack(_ coordinate: EquatorialCoordinate, _ properMotion: ProperMotion?,
                                       frames: HorizonSkyFrames) throws -> HorizonSkyTrack {
            guard coordinate.unitVector.isFinite else { throw SkyWindowError.invalidTarget }
            return HorizonFixedTrack(frames: frames, position: coordinate, properMotion: properMotion)
        }

        /// Whether the target is in the window, the sky dark enough and the Moon rule met at `time` (seconds since the
        /// reference date).
        func isMatch(_ time: Double) -> Bool {
            if let limit = darkness.sunAltitudeLimit {
                sun.evaluate(time: time, wantsAzimuth: false)
                guard sun.altitude < limit else { return false }
            }
            track.evaluate(time: time, wantsAzimuth: true)
            let azimuth = track.azimuth
            guard azimuth.isFinite, window.azimuth.contains(azimuth) else { return false }
            let altitude = apparentAltitude()
            guard altitude >= window.minimumAltitude, altitude <= window.maximumAltitude else { return false }
            switch rule {
            case .unrestricted:
                return true
            case .belowHorizon:
                return !isMoonUp(time)
            case .illuminatedAtMost(let fraction):
                return MoonPhaseCalculator.info(at: Date(timeIntervalSinceReferenceDate: time)).illuminatedFraction <= fraction
            }
        }

        private func apparentAltitude() -> Double {
            Refraction.apparentAltitude(trueAltitude: track.altitude, atmosphere: observer.atmosphere)
        }

        private func isMoonUp(_ time: Double) -> Bool {
            moonTrack.evaluate(time: time, wantsAzimuth: false)
            return moonTrack.altitude + moonTrack.limbAllowance >= RiseSetCalculator.standardHorizonAltitude
        }

        /// The time of the edge of a stretch, within `refinementTolerance`: `inside` is a sample that matches,
        /// `outside` the neighbouring one that does not; returns the matching time closest to the edge.
        private func edge(inside: Double, outside: Double) -> Double {
            var matching = inside
            var other = outside
            while abs(other - matching) > SkyWindowFinder.refinementTolerance {
                let middle = (matching + other) / 2
                if isMatch(middle) { matching = middle } else { other = middle }
            }
            return matching
        }

        /// Adds the matches of one night's `rangeStart`…`rangeEnd` (seconds since the reference date) to `found`.
        func scan(night: DateInterval, rangeStart: Double, rangeEnd: Double, into found: inout [SkyWindowMatch]) {
            let duration = rangeEnd - rangeStart
            let gapCount = Int((duration / SkyWindowFinder.sampleInterval).rounded(.up))
            let step = duration / Double(gapCount)
            func timeAt(_ index: Int) -> Double { index == gapCount ? rangeEnd : rangeStart + Double(index) * step }
            var first = -1
            for index in 0...gapCount {
                let inside = isMatch(timeAt(index))
                if inside && first < 0 { first = index }
                if inside && index < gapCount { continue }
                if first < 0 { continue }
                let last = inside ? index : index - 1
                let entry = first == 0 ? timeAt(0) : edge(inside: timeAt(first), outside: timeAt(first - 1))
                let exit = last == gapCount ? timeAt(gapCount) : edge(inside: timeAt(last), outside: timeAt(last + 1))
                found.append(match(night: night, entry: entry, exit: exit))
                if found.count >= SkyWindowFinder.maximumMatchCount { return }
                first = -1
            }
        }

        private func match(night: DateInterval, entry: Double, exit: Double) -> SkyWindowMatch {
            let middle = entry + (exit - entry) / 2
            track.evaluate(time: middle, wantsAzimuth: true)
            let altitude = apparentAltitude()
            let azimuth = track.azimuth
            moonTrack.evaluate(time: middle, wantsAzimuth: false)
            let moonAltitude = Refraction.apparentAltitude(trueAltitude: moonTrack.altitude,
                                                           atmosphere: observer.atmosphere)
            let moon = SkyWindowMoonState(
                altitude: moonAltitude,
                illuminatedFraction: MoonPhaseCalculator.info(at: Date(timeIntervalSinceReferenceDate: middle))
                    .illuminatedFraction,
                isUp: moonTrack.altitude + moonTrack.limbAllowance >= RiseSetCalculator.standardHorizonAltitude)
            return SkyWindowMatch(
                night: night,
                interval: DateInterval(start: Date(timeIntervalSinceReferenceDate: entry),
                                       end: Date(timeIntervalSinceReferenceDate: exit)),
                azimuth: azimuth, altitude: altitude, moon: moon,
                isAboveSkyline: skyline.margin(altitude: altitude, azimuth: azimuth, refracted: true) >= 0)
        }
    }
}

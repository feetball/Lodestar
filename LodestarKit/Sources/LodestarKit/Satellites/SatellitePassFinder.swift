import Foundation

/// A moment of a pass: where the satellite is in the sky.
public struct SatellitePassPoint: Hashable, Sendable {
    /// The instant.
    public let date: Date
    /// Azimuth from true north through east, [0, 360).
    public let azimuth: Double
    /// Geometric altitude in degrees.
    public let altitude: Double
    /// Distance from the observer.
    public let rangeKilometers: Double
    /// Whether the satellite is in sunlight (`EarthShadow.sunlitThreshold`).
    public let isSunlit: Bool
    /// The apparent magnitude, if the satellite is lit and its intrinsic magnitude is known.
    public let magnitude: Double?

    public init(date: Date, azimuth: Double, altitude: Double, rangeKilometers: Double, isSunlit: Bool, magnitude: Double?) {
        self.date = date
        self.azimuth = azimuth
        self.altitude = altitude
        self.rangeKilometers = rangeKilometers
        self.isSunlit = isSunlit
        self.magnitude = magnitude
    }

    /// The point as a horizontal coordinate.
    public var horizontal: HorizontalCoordinate { HorizontalCoordinate(azimuth: azimuth, altitude: altitude) }

    /// The point as an ENU unit vector (x east, y north, z up).
    public var direction: Vector3 { horizontal.unitVector }
}

/// One pass of a satellite above the observer's minimum altitude.
///
/// A pass that is already under way at the start of the search window, or still under way at its end, is cut
/// there: `rise` (or `set`) is then the window's edge and `isRiseCut` (or `isSetCut`) is `true`. The
/// `culmination` is the highest point of the part inside the window.
public struct SatellitePass: Hashable, Sendable {
    /// Where the satellite reaches the minimum altitude.
    public let rise: SatellitePassPoint
    /// The highest point of the pass.
    public let culmination: SatellitePassPoint
    /// Where the satellite drops below the minimum altitude.
    public let set: SatellitePassPoint
    /// The parts of the pass in which the satellite is sunlit and the sky is dark (chronological; usually zero or one).
    public let visibleIntervals: [DateInterval]
    /// The brightest visible moment, if the intrinsic magnitude is known.
    public let brightest: SatellitePassPoint?
    /// `true` when the pass began before the search window.
    public let isRiseCut: Bool
    /// `true` when the pass continues after the search window.
    public let isSetCut: Bool

    public init(
        rise: SatellitePassPoint, culmination: SatellitePassPoint, set: SatellitePassPoint,
        visibleIntervals: [DateInterval], brightest: SatellitePassPoint?, isRiseCut: Bool, isSetCut: Bool
    ) {
        self.rise = rise
        self.culmination = culmination
        self.set = set
        self.visibleIntervals = visibleIntervals
        self.brightest = brightest
        self.isRiseCut = isRiseCut
        self.isSetCut = isSetCut
    }

    /// From `rise` to `set`.
    public var interval: DateInterval { DateInterval(start: rise.date, end: self.set.date) }

    /// Seconds from `rise` to `set`.
    public var duration: Double { self.set.date.timeIntervalSince(rise.date) }

    /// `true` when some part of the pass can be seen (`visibleIntervals` is not empty).
    public var isVisible: Bool { !visibleIntervals.isEmpty }

    /// The visible parts' first start and last end, or `nil` for a pass that cannot be seen.
    public var visibleSpan: DateInterval? {
        guard let first = visibleIntervals.first, let last = visibleIntervals.last else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }
}

/// Finds the passes of satellites over one observer in a time window.
///
/// A *pass* is a stretch in which the satellite's geometric altitude is at least `minimumAltitude`; for each
/// the finder reports rise, culmination (highest point) and set, and the *visible* parts, in which the satellite
/// is also sunlit (at least half of the Sun's disc visible from it, see `EarthShadow`) while the Sun's
/// centre is lower than `darknessSunAltitude` for the observer.
///
/// **Method.** The altitude is sampled with steps that adapt to the distance: a satellite that is `g` degrees
/// below the threshold at range `ρ` cannot reach it in less than `ρ·sin g / v` seconds (`v` is an upper bound of
/// its speed), so the step is that long, between 1 s and 15 minutes. Rise and set are bracketed by sampling every
/// 10 s inside a pass and refined by bisection to 0.01 s, the culmination by a golden-section search to
/// 0.05 s, the visible edges by sampling every 5 s (every 30 s for passes of an hour and more) and bisection to
/// 0.05 s, the brightest point from these samples refined by a golden-section search. No pass is missed (a pass shorter than a second at the very threshold
/// excepted).
///
/// **Cost.** A low-Earth-orbit satellite over three days takes about 3 ms (a deep-space one up to 20 ms), i.e.
/// 100 satellites for three days about 0.4 s on a desktop and about a second on a phone. The window is limited to
/// `maximumWindowDays`. Creating the finder costs the Sun's hourly ephemeris for the window (about 0.5 ms for three
/// days); one finder serves any number of satellites and threads.
///
/// **Accuracy.** The times are those of the SGP4 model (see `Sgp4Propagator`); against Skyfield, which uses
/// the same propagator, rise, culmination and set agree within a second.
public struct SatellitePassFinder: Sendable {
    /// The default minimum altitude of a pass, 10°.
    public static let defaultMinimumAltitude = 10.0
    /// The default Sun altitude below which the sky is dark, -6° (the end of civil twilight).
    public static let defaultDarknessSunAltitude = -6.0
    /// The longest window searched, in days.
    public static let maximumWindowDays = 30.0

    /// The observer.
    public let observer: Observer
    /// The search window; clipped to `maximumWindowDays`.
    public let interval: DateInterval
    /// The altitude in degrees that defines rise and set (default 10).
    public let minimumAltitude: Double
    /// The Sun altitude in degrees below which the sky counts as dark (default -6).
    public let darknessSunAltitude: Double

    private let startTime: Double
    private let endTime: Double
    private let threshold: Double
    private let evaluator: SatelliteEvaluator

    public init(
        observer: Observer,
        interval: DateInterval,
        minimumAltitude: Double = SatellitePassFinder.defaultMinimumAltitude,
        darknessSunAltitude: Double = SatellitePassFinder.defaultDarknessSunAltitude
    ) {
        self.observer = observer
        self.interval = interval
        self.minimumAltitude = minimumAltitude
        self.darknessSunAltitude = darknessSunAltitude
        let start = interval.start.timeIntervalSinceReferenceDate
        let end = min(interval.end.timeIntervalSinceReferenceDate, start + Self.maximumWindowDays * JulianDate.secondsPerDay)
        self.startTime = start
        self.endTime = end
        self.threshold = minimumAltitude.isFinite ? AstroMath.clamp(minimumAltitude, -5.0, 85.0) : Self.defaultMinimumAltitude
        self.evaluator = SatelliteEvaluator(
            observer: observer,
            sunTrack: SatelliteSunTrack.create(start: start, end: max(start, end))
        )
    }

    /// All passes of `satellite` that overlap the window, in chronological order. A satellite that SGP4 cannot
    /// propagate (a decayed one, or one far from its epoch) yields none.
    public func passes(of satellite: Satellite) -> [SatellitePass] {
        guard endTime > startTime, startTime.isFinite, endTime.isFinite else { return [] }
        return SatellitePassSearch(
            satellite: satellite, evaluator: evaluator, startTime: startTime, endTime: endTime,
            threshold: threshold, darkness: darknessSunAltitude
        ).run()
    }
}

/// Root and maximum finding on smooth functions of time.
enum SatelliteSearch {
    /// The root of `function` in `[low, high]` given `function(low) < 0 <= function(high)`, by bisection.
    static func bisect(_ function: (Double) -> Double, _ low: Double, _ high: Double, _ tolerance: Double) -> Double {
        var a = low
        var b = high
        var iterations = 0
        while b - a > tolerance && iterations < 60 {
            let middle = 0.5 * (a + b)
            if function(middle) >= 0.0 { b = middle } else { a = middle }
            iterations += 1
        }
        return 0.5 * (a + b)
    }

    /// The maximizer of the unimodal `function` on `[low, high]` by golden-section search.
    static func maximize(_ function: (Double) -> Double, _ low: Double, _ high: Double, _ tolerance: Double) -> Double {
        let ratio = (5.0.squareRoot() - 1.0) / 2.0
        var a = low
        var b = high
        var c = b - ratio * (b - a)
        var d = a + ratio * (b - a)
        var fc = function(c)
        var fd = function(d)
        var iterations = 0
        while b - a > tolerance && iterations < 80 {
            if fc > fd {
                b = d
                d = c
                fd = fc
                c = b - ratio * (b - a)
                fc = function(c)
            } else {
                a = c
                c = d
                fc = fd
                d = a + ratio * (b - a)
                fd = function(d)
            }
            iterations += 1
        }
        return 0.5 * (a + b)
    }
}

/// One satellite's pass search. Local state only.
final class SatellitePassSearch {
    private let satellite: Satellite
    private let evaluator: SatelliteEvaluator
    private let startTime: Double
    private let endTime: Double
    private let threshold: Double
    private let darkness: Double
    private let propagator: Sgp4Propagator
    private let geometry: SatelliteObserverGeometry
    private var state = [Double](repeating: 0, count: 6)
    private let maximumSpeed: Double

    private static let failedAltitude = -1_000.0
    private static let failureStep = 120.0
    private static let minimumStep = 1.0
    private static let maximumStep = 900.0
    private static let safetyFactor = 0.9
    private static let passStep = 10.0
    private static let longPassStep = 60.0
    private static let rootTolerance = 0.01
    private static let culminationTolerance = 0.05
    private static let visibilityStep = 5.0
    private static let visibilityTolerance = 0.05
    private static let daylightMargin = 1.5
    private static let daylightSpacing = 600.0
    private static let visibilitySamples = 120.0
    private static let longVisibilityStep = 30.0

    init(
        satellite: Satellite, evaluator: SatelliteEvaluator, startTime: Double, endTime: Double,
        threshold: Double, darkness: Double
    ) {
        self.satellite = satellite
        self.evaluator = evaluator
        self.startTime = startTime
        self.endTime = endTime
        self.threshold = threshold
        self.darkness = darkness
        self.propagator = satellite.propagator
        self.geometry = evaluator.geometry
        self.maximumSpeed = satellite.propagator.maximumSpeedKilometersPerSecond
    }

    /// The topocentric sample at `time`, or `nil` if SGP4 fails there.
    private func sample(_ time: Double) -> SatelliteTopocentric? {
        let minutes = (time - propagator.epochReferenceSeconds) / 60.0
        if propagator.propagateRaw(minutes, into: &state) != 0 { return nil }
        return geometry.look(state[0], state[1], state[2], state[3], state[4], state[5], evaluator.gmst(time))
    }

    /// The geometric altitude at `time`; very low (-1000) where SGP4 fails, so that failures count as "below".
    private func altitude(_ time: Double) -> Double { sample(time)?.altitude ?? Self.failedAltitude }

    func run() -> [SatellitePass] {
        var passes: [SatellitePass] = []
        var time = startTime
        while time < endTime {
            let current = sample(time)
            let currentAltitude = current?.altitude ?? Self.failedAltitude
            if currentAltitude >= threshold {
                // Already above the threshold: the pass is under way at the window's start (or begins right
                // after the previous one ended).
                let followed = followPass(riseTime: time, isRiseCut: time == startTime)
                passes.append(followed.pass)
                time = followed.end + 1.0
                continue
            }
            let next = min(time + safeStep(current, currentAltitude), endTime)
            if altitude(next) >= threshold {
                let riseTime = SatelliteSearch.bisect({ self.altitude($0) - self.threshold }, time, next, Self.rootTolerance)
                let followed = followPass(riseTime: riseTime, isRiseCut: false)
                passes.append(followed.pass)
                time = followed.end + 1.0
            } else {
                time = next
            }
        }
        return passes
    }

    /// The longest step after which the satellite cannot have reached the threshold, in seconds.
    private func safeStep(_ current: SatelliteTopocentric?, _ altitude: Double) -> Double {
        guard let current else { return Self.failureStep }
        let gap = min(threshold - altitude, 90.0)
        let seconds = Self.safetyFactor * current.range * sin(gap * Double.pi / 180.0) / maximumSpeed
        return min(max(seconds, Self.minimumStep), Self.maximumStep)
    }

    /// Follows a pass from `riseTime` to its set (or the end of the window) and returns it with the time it ended.
    private func followPass(riseTime: Double, isRiseCut: Bool) -> (pass: SatellitePass, end: Double) {
        var times: [Double] = [riseTime]
        var altitudes: [Double] = [altitude(riseTime)]
        var setTime = endTime
        var isSetCut = true
        var current = riseTime
        while true {
            let age = current - riseTime
            let next = min(current + (age <= 1_800.0 ? Self.passStep : Self.longPassStep), endTime)
            if next <= current { break }
            let nextAltitude = altitude(next)
            if nextAltitude < threshold {
                // `threshold - altitude` turns from negative to non-negative where the satellite sets.
                setTime = SatelliteSearch.bisect({ self.threshold - self.altitude($0) }, current, next, Self.rootTolerance)
                isSetCut = false
                times.append(setTime)
                altitudes.append(threshold)
                break
            }
            times.append(next)
            altitudes.append(nextAltitude)
            current = next
            if next >= endTime { break }
        }

        var best = 0
        for index in altitudes.indices where altitudes[index] > altitudes[best] {
            best = index
        }
        let low = times[max(best - 1, 0)]
        let high = times[min(best + 1, times.count - 1)]
        let culminationTime: Double
        if high > low {
            culminationTime = SatelliteSearch.maximize({ self.altitude($0) }, low, high, Self.culminationTolerance)
        } else {
            culminationTime = times[best]
        }
        let rise = pointAt(riseTime)
        let culmination = pointAt(culminationTime)
        let set = pointAt(setTime)
        let visible = visibleParts(riseTime: riseTime, setTime: setTime)
        let pass = SatellitePass(
            rise: rise, culmination: culmination, set: set, visibleIntervals: visible.intervals,
            brightest: visible.brightest, isRiseCut: isRiseCut, isSetCut: isSetCut
        )
        return (pass, setTime)
    }

    private func pointAt(_ time: Double) -> SatellitePassPoint {
        if let look = evaluator.look(satellite, time, &state) {
            return SatellitePassPoint(
                date: look.date, azimuth: look.azimuth, altitude: look.altitude,
                rangeKilometers: look.rangeKilometers, isSunlit: look.isSunlit, magnitude: look.magnitude
            )
        }
        return SatellitePassPoint(
            date: Date(timeIntervalSinceReferenceDate: time), azimuth: 0.0, altitude: threshold,
            rangeKilometers: 0.0, isSunlit: false, magnitude: nil
        )
    }

    /// The apparent magnitude at `time`; positive infinity where it is unknown.
    private func magnitude(_ time: Double) -> Double {
        evaluator.look(satellite, time, &state)?.magnitude ?? Double.infinity
    }

    private struct Visibility {
        let intervals: [DateInterval]
        let brightest: SatellitePassPoint?
    }

    /// Whether the satellite can be seen at `time` (sunlit, observer dark); the satellite is above the threshold.
    private func isVisible(_ time: Double) -> Bool {
        let minutes = (time - propagator.epochReferenceSeconds) / 60.0
        if propagator.propagateRaw(minutes, into: &state) != 0 { return false }
        let sun = evaluator.sunPosition(time)
        let fraction = EarthShadow.illuminatedFraction(state[0], state[1], state[2], sun.x, sun.y, sun.z)
        if fraction < EarthShadow.sunlitThreshold { return false }
        return evaluator.sunAltitude(sun, evaluator.gmst(time)) < darkness
    }

    private func visibleParts(riseTime: Double, setTime: Double) -> Visibility {
        let duration = setTime - riseTime
        if duration <= 0.0 { return Visibility(intervals: [], brightest: nil) }
        // A pass in full daylight cannot be seen. The Sun's altitude changes by at most 15 degrees an hour, so
        // with samples at most ten minutes apart it stays within 1.25 degrees of the lowest sample in between.
        let checks = max(3, Int((duration / Self.daylightSpacing).rounded(.up)) + 1)
        var allLight = true
        for index in 0..<checks {
            let time = riseTime + duration * Double(index) / Double(checks - 1)
            if evaluator.sunAltitude(evaluator.sunPosition(time), evaluator.gmst(time)) < darkness + Self.daylightMargin {
                allLight = false
                break
            }
        }
        if allLight { return Visibility(intervals: [], brightest: nil) }

        let spacing = min(max(Self.visibilityStep, duration / Self.visibilitySamples), Self.longVisibilityStep)
        let count = max(1, Int((duration / spacing).rounded(.up)))
        let step = duration / Double(count)
        var intervals: [DateInterval] = []
        var intervalStart = Double.nan
        var previousTime = riseTime
        var previous = isVisible(riseTime)
        if previous { intervalStart = riseTime }
        var brightestTime = Double.nan
        var brightestMagnitude = Double.infinity
        let tracksMagnitude = satellite.intrinsicMagnitude != nil
        if previous && tracksMagnitude {
            let look = evaluator.look(satellite, riseTime, &state)
            if let value = look?.magnitude, value < brightestMagnitude {
                brightestMagnitude = value
                brightestTime = riseTime
            }
        }
        for index in 1...count {
            let time = index == count ? setTime : riseTime + Double(index) * step
            let visible = isVisible(time)
            if visible != previous {
                let edge = SatelliteSearch.bisect(
                    { self.isVisible($0) == visible ? 1.0 : -1.0 },
                    previousTime, time, Self.visibilityTolerance
                )
                if visible {
                    intervalStart = edge
                } else {
                    intervals.append(DateInterval(
                        start: Date(timeIntervalSinceReferenceDate: intervalStart),
                        end: Date(timeIntervalSinceReferenceDate: edge)
                    ))
                }
            }
            if visible && tracksMagnitude {
                if let value = evaluator.look(satellite, time, &state)?.magnitude, value < brightestMagnitude {
                    brightestMagnitude = value
                    brightestTime = time
                }
            }
            previous = visible
            previousTime = time
        }
        if previous {
            intervals.append(DateInterval(
                start: Date(timeIntervalSinceReferenceDate: intervalStart),
                end: Date(timeIntervalSinceReferenceDate: setTime)
            ))
        }
        if brightestTime.isNaN { return Visibility(intervals: intervals, brightest: nil) }
        // Refine the brightest sample within its neighbours and its visible part.
        let part = intervals.first {
            let begin = $0.start.timeIntervalSinceReferenceDate
            let finish = $0.end.timeIntervalSinceReferenceDate
            return brightestTime >= begin - 1.0e-6 && brightestTime <= finish + 1.0e-6
        }
        if let part {
            let low = max(brightestTime - step, part.start.timeIntervalSinceReferenceDate)
            let high = min(brightestTime + step, part.end.timeIntervalSinceReferenceDate)
            if high > low {
                let refined = SatelliteSearch.maximize({ -self.magnitude($0) }, low, high, Self.culminationTolerance)
                if magnitude(refined) < brightestMagnitude { brightestTime = refined }
            }
        }
        return Visibility(intervals: intervals, brightest: pointAt(brightestTime))
    }
}

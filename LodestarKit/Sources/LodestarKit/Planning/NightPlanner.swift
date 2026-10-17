import Foundation

/// Plans a night of astrophotography: when it is dark, when the Moon is up, when the Milky Way's core
/// and the planets are visible, and which targets rise highest in the dark.
///
/// All altitudes are geometric (no refraction) unless a caller's own position function says otherwise,
/// and refer to the centre of the target. Times are `Date`s; "the night starting on" a local date runs
/// from local noon to local noon (see `TwilightCalculator`).
public enum NightPlanner {
    /// The minimum altitude, in degrees, that `visibility` counts as usable when none is given.
    public static let defaultMinimumAltitude = 20.0

    /// The largest number of samples `altitudeCurve` returns.
    public static let maximumCurveSampleCount = 100_000

    // MARK: Altitude curves

    /// Samples where a target is in the sky across an interval.
    ///
    /// The samples are evenly spaced from the start to the end of the interval, with at most `step`
    /// seconds between them (the spacing grows if that would take more than `maximumCurveSampleCount`
    /// samples). A `SkyFrame` is built for every sample and handed to `position`, which returns the
    /// target's horizontal coordinates; return geometric coordinates (`refraction: false`) for a
    /// geometric curve. An empty interval gives a single sample at its start.
    ///
    /// - Parameters:
    ///   - observer: The place of observation.
    ///   - interval: The time span to sample.
    ///   - step: The largest gap between samples in seconds; a value that is not positive or not
    ///     finite is replaced by 10 minutes, and values below a second by one second.
    ///   - position: The target's horizontal coordinates in the given frame.
    public static func altitudeCurve(observer: Observer, interval: DateInterval, step: TimeInterval = 600,
                                     position: (SkyFrame) -> HorizontalCoordinate) -> [AltitudeSample] {
        let duration = interval.duration.isFinite ? max(interval.duration, 0) : 0
        let gapCount = curveGapCount(duration: duration, step: step)
        let spacing = gapCount > 0 ? duration / Double(gapCount) : 0
        return (0...gapCount).map { index in
            let date = index == gapCount && gapCount > 0
                ? interval.end : interval.start.addingTimeInterval(Double(index) * spacing)
            let horizontal = position(SkyFrame(date: date, observer: observer))
            return AltitudeSample(date: date, altitude: horizontal.altitude, azimuth: horizontal.azimuth)
        }
    }

    /// The number of gaps between the samples of a curve over `duration` seconds: enough that none is
    /// longer than `step`, and not so many that the curve would exceed `maximumCurveSampleCount` samples.
    static func curveGapCount(duration: TimeInterval, step: TimeInterval) -> Int {
        let requested = step.isFinite && step > 0 ? max(step, 1) : 600
        return Int(min((duration / requested).rounded(.up), Double(maximumCurveSampleCount - 1)))
    }

    /// Samples the geometric altitude and azimuth of a fixed object, given by its J2000 catalog place
    /// and optional proper motion, across an interval. See `altitudeCurve(observer:interval:step:position:)`.
    public static func altitudeCurve(ofJ2000 place: EquatorialCoordinate, properMotion: ProperMotion? = nil,
                                     observer: Observer, interval: DateInterval,
                                     step: TimeInterval = 600) -> [AltitudeSample] {
        altitudeCurve(observer: observer, interval: interval, step: step) {
            $0.horizontal(j2000: place, properMotion: properMotion, refraction: false)
        }
    }

    /// Samples the geometric altitude and azimuth of the Sun, the Moon or a planet across an interval.
    /// See `altitudeCurve(observer:interval:step:position:)`.
    public static func altitudeCurve(of body: SolarSystemBody, observer: Observer, interval: DateInterval,
                                     step: TimeInterval = 600) -> [AltitudeSample] {
        altitudeCurve(observer: observer, interval: interval, step: step) {
            $0.horizontal(of: body, refraction: false)
        }
    }
}

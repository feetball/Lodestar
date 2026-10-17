import Foundation

/// Sunset, the three twilights and sunrise around one night at a place.
///
/// The "night starting on" a local date runs from local noon of that date to local noon of the next
/// day (23 or 25 hours across a daylight-saving change). Events are `nil` when the Sun does not
/// cross the corresponding altitude in that window, as in the polar summer or winter.
public struct NightTwilight: Sendable, Hashable {
    /// The Sun's centre passes −0.8333° (the upper limb touches the horizon, with refraction).
    public let sunset: Date?
    /// The Sun reaches −6° in the evening.
    public let civilDusk: Date?
    /// The Sun reaches −12° in the evening.
    public let nauticalDusk: Date?
    /// The Sun reaches −18° in the evening: the sky is fully dark from here.
    public let astronomicalDusk: Date?
    /// The Sun climbs back through −18° in the morning.
    public let astronomicalDawn: Date?
    /// The Sun climbs back through −12°.
    public let nauticalDawn: Date?
    /// The Sun climbs back through −6°.
    public let civilDawn: Date?
    /// The Sun's centre climbs back through −0.8333°.
    public let sunrise: Date?
    /// Local noon of the starting date to local noon of the next day.
    public let interval: DateInterval
    /// The instant of the Sun's lowest altitude in the interval (solar midnight).
    public let solarMidnight: Date
    /// The Sun's geometric altitude at `solarMidnight`, in degrees.
    public let sunAltitudeAtMidnight: Double

    /// The period between astronomical dusk and dawn, when the Sun is below −18°.
    ///
    /// `nil` when the Sun does not get that low (white nights). When it stays below −18° through
    /// the whole interval (polar winter) this is the whole `interval`.
    public var astronomicalNight: DateInterval? {
        switch (astronomicalDusk, astronomicalDawn) {
        case let (dusk?, dawn?) where dawn > dusk:
            return DateInterval(start: dusk, end: dawn)
        case let (dusk?, nil):
            return DateInterval(start: dusk, end: interval.end)
        case let (nil, dawn?):
            return DateInterval(start: interval.start, end: dawn)
        default:
            return sunAltitudeAtMidnight < TwilightCalculator.astronomicalAltitude
                && astronomicalDusk == nil && astronomicalDawn == nil ? interval : nil
        }
    }

    /// Creates a night from its events.
    public init(sunset: Date?, civilDusk: Date?, nauticalDusk: Date?, astronomicalDusk: Date?,
                astronomicalDawn: Date?, nauticalDawn: Date?, civilDawn: Date?, sunrise: Date?,
                interval: DateInterval, solarMidnight: Date, sunAltitudeAtMidnight: Double) {
        self.sunset = sunset
        self.civilDusk = civilDusk
        self.nauticalDusk = nauticalDusk
        self.astronomicalDusk = astronomicalDusk
        self.astronomicalDawn = astronomicalDawn
        self.nauticalDawn = nauticalDawn
        self.civilDawn = civilDawn
        self.sunrise = sunrise
        self.interval = interval
        self.solarMidnight = solarMidnight
        self.sunAltitudeAtMidnight = sunAltitudeAtMidnight
    }
}

/// Computes sunset, twilight and sunrise times.
public enum TwilightCalculator {
    /// Sun altitude at the end of civil twilight, in degrees.
    public static let civilAltitude = -6.0
    /// Sun altitude at the end of nautical twilight, in degrees.
    public static let nauticalAltitude = -12.0
    /// Sun altitude at the end of astronomical twilight, in degrees.
    public static let astronomicalAltitude = -18.0

    /// The twilight times of the night that starts on the local calendar day containing `localDate`.
    ///
    /// - Parameters:
    ///   - localDate: Any instant on the desired date in `timeZone`.
    ///   - observer: The place of observation.
    ///   - timeZone: The time zone that defines the local date and noon. The Gregorian calendar is used.
    public static func night(startingOn localDate: Date, observer: Observer, timeZone: TimeZone) -> NightTwilight {
        let interval = nightInterval(startingOn: localDate, timeZone: timeZone)
        let evaluate = RiseSetCalculator.evaluator(for: .sun, observer: observer)
        let profile = RiseSetCalculator.Profile(interval: interval, step: RiseSetCalculator.maximumSampleInterval,
                                                evaluate: evaluate)
        let lowest = profile.lowestPoint(tolerance: RiseSetCalculator.defaultTolerance, evaluate: evaluate)
        let midnight = Date(timeIntervalSinceReferenceDate: lowest.time)

        /// The evening (setting) and morning (rising) crossings of a threshold on either side of midnight.
        func crossings(of threshold: Double) -> (evening: Date?, morning: Date?) {
            let found = profile.crossings(of: threshold, tolerance: RiseSetCalculator.defaultTolerance,
                                          evaluate: evaluate)
            return (found.last { $0.kind == .setting && $0.time <= midnight }?.time,
                    found.first { $0.kind == .rising && $0.time >= midnight }?.time)
        }
        let horizon = crossings(of: RiseSetCalculator.sunHorizonAltitude)
        let civil = crossings(of: civilAltitude)
        let nautical = crossings(of: nauticalAltitude)
        let astronomical = crossings(of: astronomicalAltitude)
        return NightTwilight(
            sunset: horizon.evening, civilDusk: civil.evening, nauticalDusk: nautical.evening,
            astronomicalDusk: astronomical.evening, astronomicalDawn: astronomical.morning,
            nauticalDawn: nautical.morning, civilDawn: civil.morning, sunrise: horizon.morning,
            interval: interval, solarMidnight: midnight, sunAltitudeAtMidnight: lowest.altitude)
    }

    /// Local noon on the calendar day of `date` to local noon on the next day. A date outside the years
    /// 1 to 4001 (`Date.distantPast ... Date.distantFuture`), or one that is not finite, is replaced by
    /// the nearest limit (or the reference date), where the calendar arithmetic is well defined.
    static func nightInterval(startingOn date: Date, timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let seconds = date.timeIntervalSinceReferenceDate
        let usable = seconds.isFinite
            ? min(max(date, .distantPast), .distantFuture) : Date(timeIntervalSinceReferenceDate: 0)
        let dayStart = calendar.startOfDay(for: usable)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(12 * 3600)
        let nextNoon = calendar.date(byAdding: .day, value: 1, to: noon) ?? noon.addingTimeInterval(24 * 3600)
        return DateInterval(start: noon, end: nextNoon)
    }
}

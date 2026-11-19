import Foundation
import LodestarKit

/// Where an object stands against the local meridian at one instant: its hour angle and the transits around it. The
/// Now card shows it as "Hour angle −1h 23m · transits in 1 h 23 min".
struct ObjectDetailMeridian: Sendable, Equatable {
    /// The hour angle in hours, west positive, in (−12, 12].
    let hourAngle: Double
    /// The first transit after `date` within a day, if any.
    let next: Date?
    /// The last transit at or before `date` within a day, if any.
    let previous: Date?
    /// The instant the hour angle and the transits were computed for.
    let date: Date

    /// The hour angle and transits of `object` at `date`, or `nil` for an object that has none: a celestial pole, or a
    /// comet or asteroid whose orbit cannot be evaluated (`isEvaluable` false).
    ///
    /// - Parameter apparent: The object's apparent place at `date` (true equator and equinox of date).
    static func of(_ object: CelestialObject, observer: Observer, date: Date, apparent: EquatorialCoordinate,
                   isEvaluable: Bool = true) -> ObjectDetailMeridian? {
        if !isEvaluable { return nil }
        if case .celestialPole = object.position { return nil }
        let hourAngle = MeridianClock.hourAngle(of: apparent, at: date, observer: observer)
        guard hourAngle.isFinite else { return nil }
        let transits = MeridianClock.transit(for: object, around: date, observer: observer)
        return ObjectDetailMeridian(hourAngle: hourAngle, next: transits.next, previous: transits.previous, date: date)
    }

    /// The hour angle for display: "−1h 23m" (sexagesimal) or "−1.389 h" (decimal); "+" in the west.
    func hourAngleText(style: CoordinateStyle) -> String {
        Self.hourAngleText(hourAngle, style: style)
    }

    /// "transits in 1 h 23 min" while the object is east of the meridian, "transited 25 min ago" once it is west of it;
    /// `nil` when that transit is more than a day away.
    var transitText: String? {
        if hourAngle < 0 {
            return next.flatMap { Self.transitIn(seconds: $0.timeIntervalSince(date)) }
        }
        return previous.flatMap { Self.transitedAgo(seconds: date.timeIntervalSince($0)) }
    }

    /// The value of the card's row: "−1h 23m · transits in 1 h 23 min".
    func rowText(style: CoordinateStyle) -> String {
        [hourAngleText(style: style), transitText].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// The hour angle in hours as "−1h 23m", "+0h 25m" or "0h 00m"; or "−1.389 h", "+0.417 h", "0.000 h".
    static func hourAngleText(_ hours: Double, style: CoordinateStyle) -> String {
        let magnitude = abs(hours)
        guard hours.isFinite, magnitude <= 24 else { return AppFormat.missing }
        switch style {
        case .sexagesimal:
            let minutes = Int64((magnitude * 60).rounded())
            let rest = minutes % 60
            return sign(of: hours, isZero: minutes == 0) + "\(minutes / 60)h \(rest < 10 ? "0" : "")\(rest)m"
        case .decimal:
            let thousandths = Int64((magnitude * 1000).rounded())
            let rest = thousandths % 1000
            let padding = rest < 10 ? "00" : (rest < 100 ? "0" : "")
            return sign(of: hours, isZero: thousandths == 0) + "\(thousandths / 1000).\(padding)\(rest) h"
        }
    }

    /// "transits in 1 h 23 min" for the transit `seconds` ahead; "transits now" within half a minute.
    static func transitIn(seconds: Double) -> String? {
        guard let minutes = wholeMinutes(seconds) else { return nil }
        return minutes == 0 ? "transits now" : "transits in \(durationText(minutes: minutes))"
    }

    /// "transited 25 min ago" for the transit `seconds` behind; "just now" within half a minute.
    static func transitedAgo(seconds: Double) -> String? {
        guard let minutes = wholeMinutes(seconds) else { return nil }
        return minutes == 0 ? "transited just now" : "transited \(durationText(minutes: minutes)) ago"
    }

    /// A span of `minutes` as "25 min", "1 h" or "1 h 23 min".
    static func durationText(minutes: Int64) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// `seconds` rounded to whole minutes (never negative, at most a year); `nil` when it is not finite.
    private static func wholeMinutes(_ seconds: Double) -> Int64? {
        guard seconds.isFinite else { return nil }
        return Int64((min(max(seconds, 0), 365 * 86_400) / 60).rounded())
    }

    private static func sign(of value: Double, isZero: Bool) -> String {
        isZero ? "" : (value < 0 ? "\u{2212}" : "+")
    }
}

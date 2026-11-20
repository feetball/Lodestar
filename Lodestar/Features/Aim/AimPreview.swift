import Foundation
import LodestarKit

/// The rules of the time preview: the sky, the target and the guidance of the Aim screen worked out for a moment other
/// than now (`AimViewModel.previewOffset`), while the phone's pointing stays live. Pure functions for the date logic
/// and the wording.
enum AimPreview {
    /// The farthest the preview can be from now, either way: 48 hours, in seconds.
    static let limit: TimeInterval = 48 * 3600

    /// An offset closer to now than this many seconds is live: stepping forward and back ends the preview exactly.
    static let liveTolerance: TimeInterval = 30

    /// The apparent altitude of the Sun's centre above which it is day, in degrees: its upper limb at the horizon (the
    /// −0.833° of sunrise and sunset) seen through standard refraction, which lifts the centre by about 0.57°.
    static let daylightAltitude = -0.27

    /// A step of the time bar.
    enum Step: CaseIterable, Identifiable {
        case backHour, backQuarter, forwardQuarter, forwardHour

        var id: Self { self }

        var seconds: TimeInterval {
            switch self {
            case .backHour: return -3600
            case .backQuarter: return -900
            case .forwardQuarter: return 900
            case .forwardHour: return 3600
            }
        }

        var title: String {
            switch self {
            case .backHour: return "\u{2212}1 h"
            case .backQuarter: return "\u{2212}15 min"
            case .forwardQuarter: return "+15 min"
            case .forwardHour: return "+1 h"
            }
        }

        var spokenTitle: String {
            switch self {
            case .backHour: return "One hour earlier"
            case .backQuarter: return "Fifteen minutes earlier"
            case .forwardQuarter: return "Fifteen minutes later"
            case .forwardHour: return "One hour later"
            }
        }
    }

    /// `seconds` as a preview offset: limited to ±48 hours, 0 (live) for anything within `liveTolerance` of now and for
    /// a value that is not a number.
    static func normalized(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, abs(seconds) >= liveTolerance else { return 0 }
        return min(max(seconds, -limit), limit)
    }

    /// The instant the sky is worked out for: `now` moved by `offset` seconds (the same instant when live).
    static func date(now: Date, offset: TimeInterval) -> Date {
        offset == 0 ? now : now.addingTimeInterval(offset)
    }

    /// The preview offset that shows the sky at `date` when it is `now`: `normalized`, so far dates are held at the limit.
    static func offset(to date: Date, from now: Date) -> TimeInterval {
        normalized(date.timeIntervalSince(now))
    }

    /// Whether the Sun is up when its centre stands at the apparent `sunAltitude` degrees.
    static func isDaylight(sunAltitude: Double) -> Bool {
        sunAltitude > daylightAltitude
    }

    /// Whether `date` falls on the same calendar day as `now` in `timeZone`.
    static func isSameDay(_ date: Date, as now: Date, in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: now)
    }

    // MARK: Wording

    /// The text of the chip: "Preview 02:15", with the weekday (`day`) when the time is not today, and in daylight
    /// "Preview · Daylight at 14:20".
    static func chipText(time: String, day: String?, isDaylight: Bool) -> String {
        let moment = day.map { "\($0) \(time)" } ?? time
        return isDaylight ? "Preview \u{00B7} Daylight at \(moment)" : "Preview \(moment)"
    }

    /// What VoiceOver says for the chip.
    static func spokenChip(time: String, day: String?, isDaylight: Bool) -> String {
        let moment = day.map { "\($0) \(time)" } ?? time
        return "Previewing the sky at \(moment)." + (isDaylight ? " The Sun is up." : "")
    }

    /// "Will be at altitude 34° at 02:15" or "Will be below the horizon at 02:15"; past tense ("Was") for an earlier time.
    static func placeNote(altitude: Double, time: String, isFuture: Bool) -> String {
        let verb = isFuture ? "Will be" : "Was"
        if altitude < 0 { return "\(verb) below the horizon at \(time)" }
        return "\(verb) at altitude \(AngleFormatter.formatDegrees(altitude, decimals: 0)) at \(time)"
    }

    /// "Will be behind your skyline at 02:15".
    static func skylineNote(time: String, isFuture: Bool) -> String {
        "\(isFuture ? "Will be" : "Was") behind your skyline at \(time)"
    }

    /// The note for a target below the horizon, with the time of its next rise when there is one (`riseTime`).
    static func belowHorizonNote(time: String, riseTime: String?, doesNotRise: Bool, isFuture: Bool) -> String {
        let base = placeNote(altitude: -1, time: time, isFuture: isFuture)
        if let riseTime { return "\(base) \u{00B7} rises \(riseTime)" }
        if doesNotRise { return "\(base) \u{00B7} does not rise in the next 24 hours" }
        return base
    }

    /// What VoiceOver says about the target: "Jupiter will be at altitude 34 degrees at 02:15."
    static func spokenPlace(name: String, altitude: Double, time: String, isFuture: Bool) -> String {
        let verb = isFuture ? "will be" : "was"
        if altitude < 0 { return "\(name) \(verb) below the horizon at \(time)." }
        return "\(name) \(verb) at altitude \(AimFormat.spoken(altitude)) at \(time)."
    }
}

import Foundation
import LodestarKit

/// The words of the satellite features. The Android app uses the same texts.
enum SatelliteText {
    static let cardTitle = "Satellite passes"
    static let allPasses = "All passes"
    static let passesTitle = "Satellite Passes"
    static let loading = "Loading orbit data\u{2026}"
    static let finding = "Finding passes\u{2026}"
    static let noPassesTonight = "No visible passes on this night."
    static let noPasses = "No visible passes in the next three days."
    static let nightOver = "This night is over."
    static let tooFar = "Passes can be predicted only three days ahead."
    static let stale = "Orbit data is too old for exact times. Update it in Settings \u{25B8} Online Data."
    static let staleTag = "orbit data too old"
    static let visibleOnly = "Visible passes only: the satellite is lit by the Sun while the sky is dark, at least 10\u{00B0} up."
    static let attribution = "Orbital data: CelesTrak, T. S. Kelso"
    static let follow = "Follow in Aim"
    static let wait = "Wait at the peak"
    static let actionsNote = "Follow in Aim guides the camera to the satellite's live position. Wait at the peak guides "
        + "it to the point where the pass is highest, with a countdown."
    static let rideAlongBelow = "Below the horizon"
    static let pathNote = "Seen from below: north at the top, east on the left. The solid line is where you can see it; "
        + "the rings mark 30\u{00B0} and 60\u{00B0} above the horizon."
    static let offTitle = "Satellite Passes Are Off"
    static let offMessage = "Switch on Satellite passes in Settings \u{25B8} Online Data to see when the ISS and other "
        + "bright satellites cross your sky."

    /// "21:34 – 21:39".
    static func span(_ item: SatellitePassItem, in timeZone: TimeZone) -> String {
        "\(AppFormat.time(item.start, in: timeZone)) \u{2013} \(AppFormat.time(item.end, in: timeZone))"
    }

    /// "peak 67° NE": the culmination's altitude and compass point.
    static func peak(_ point: SatellitePassPoint) -> String {
        "peak \(AngleFormatter.formatDegrees(point.altitude, decimals: 0)) "
            + AngleFormatter.compassPoint(azimuth: point.azimuth).abbreviation
    }

    /// "mag −3.2", or "—" when the brightness is unknown.
    static func magnitude(_ item: SatellitePassItem) -> String { AppFormat.magnitude(item.pass.brightest?.magnitude) }

    /// The length of a pass part: "5 min 18 s", "42 s".
    static func duration(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0).rounded())
        return whole < 60 ? "\(whole) s" : "\(whole / 60) min \(whole % 60) s"
    }

    /// A time of day with seconds in the user's 12 or 24 hour style: "21:34:12" or "9:34:12 PM".
    static func timeWithSeconds(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .standard, timeZone: timeZone))
    }

    /// "21:34:12 · 225° SW · 10°": time, azimuth with compass point, altitude.
    static func point(_ point: SatellitePassPoint, in timeZone: TimeZone) -> String {
        "\(timeWithSeconds(point.date, in: timeZone)) \u{00B7} \(AppFormat.azimuth(point.azimuth)) \u{00B7} "
            + AngleFormatter.formatDegrees(point.altitude, decimals: 0)
    }

    /// The compass point in words, lower case: "south-west".
    private static func direction(_ azimuth: Double) -> String {
        AngleFormatter.compassPoint(azimuth: azimuth).fullName.lowercased()
    }

    /// What a screen reader says for the sky path of a pass.
    static func spokenPath(_ item: SatellitePassItem, in timeZone: TimeZone) -> String {
        let pass = item.pass
        let visible = pass.visibleSpan.map {
            " Visible from \(AppFormat.time($0.start, in: timeZone)) to \(AppFormat.time($0.end, in: timeZone))."
        } ?? ""
        return "Sky path of the \(item.name) pass. It rises in the \(direction(pass.rise.azimuth)), reaches "
            + "\(Int(pass.culmination.altitude.rounded())) degrees in the \(direction(pass.culmination.azimuth)) and "
            + "sets in the \(direction(pass.set.azimuth)).\(visible)"
    }

    // MARK: Aim

    /// "Range 612 km · 0.62°/s · Sunlit" or "… · In Earth's shadow".
    static func followInfo(rangeKilometers: Double, angularSpeed: Double, isSunlit: Bool) -> String {
        let range = Int(rangeKilometers.rounded()).formatted(.number)
        let speed = angularSpeed.formatted(.number.precision(.fractionLength(2)))
        return "Range \(range) km \u{00B7} \(speed)\u{00B0}/s \u{00B7} \(isSunlit ? "Sunlit" : "In Earth's shadow")"
    }

    /// The countdown to the peak: "Peak in 2:41", "At the peak now", "Peak passed 0:42 ago".
    static func peakCountdown(_ seconds: Double) -> String {
        guard seconds.isFinite else { return AppFormat.missing }
        if abs(seconds) < 2 { return "At the peak now" }
        let text = clock(Int(abs(seconds).rounded()))
        return seconds > 0 ? "Peak in \(text)" : "Peak passed \(text) ago"
    }

    /// "2:41" or "1:02:03".
    static func clock(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A note about the pass of a followed satellite while it is not in it: "Rises 21:34 (in 12m)" before, "The pass is
    /// over" after; `nil` during the pass.
    static func passNote(now: Date, rise: Date, set: Date, timeText: (Date) -> String) -> String? {
        if now < rise { return "Rises \(timeText(rise)) (\(AppFormat.relative(rise, from: now)))" }
        if now > set { return "The pass is over" }
        return nil
    }

    // MARK: Streak warning

    /// The chip in Aim: "Starlink: 3 crossings in 30 s · 12% streak risk". With no crossing: "Starlink: no crossings in
    /// 30 s · 8% streak risk".
    static func streakChip(crossings: Int, exposureSeconds: Int, risk: Double) -> String {
        let count: String
        switch crossings {
        case 0: count = "no crossings"
        case 1: count = "1 crossing"
        default: count = "\(crossings) crossings"
        }
        return "Starlink: \(count) in \(exposureSeconds) s \u{00B7} \(AppFormat.percent(min(max(risk, 0), 1))) streak risk"
    }

    static let streakStaleChip = "Starlink data too old"
    static let noCrossings = "No satellite is expected to cross the frame during this exposure."
    static let streakNote = "A prediction from the Starlink orbit data for the exposure that keeps stars sharp with your "
        + "lens (the NPF rule). A satellite's brightness varies; the magnitude is unknown for most."
    static let streakSheetTitle = "Starlink crossings"

    /// The numbers behind the chip: "47 sunlit satellites above 20° right now. About 0.8 crossings a minute in this
    /// frame; 12% chance of a streak in a 30 s exposure."
    static func streakSummary(exposureSeconds: Int, sunlitAbove20: Int, crossingsPerMinute: Double, risk: Double) -> String {
        let rate = crossingsPerMinute.formatted(.number.precision(.fractionLength(1)))
        let satellites = sunlitAbove20 == 1 ? "1 sunlit satellite" : "\(sunlitAbove20) sunlit satellites"
        return "\(satellites) above 20\u{00B0} right now. About \(rate) crossings a minute in this frame; "
            + "\(AppFormat.percent(min(max(risk, 0), 1))) chance of a streak in a \(exposureSeconds) s exposure."
    }

    /// One crossing: "21:34:12 – 21:34:19 · mag —", with "already in frame" when it began before the exposure.
    static func crossing(_ crossing: SatelliteCrossing, in timeZone: TimeZone) -> String {
        let early = crossing.startsBeforeExposure ? " \u{00B7} already in frame" : ""
        return "\(timeWithSeconds(crossing.entry.date, in: timeZone)) \u{2013} "
            + "\(timeWithSeconds(crossing.exit.date, in: timeZone)) \u{00B7} \(AppFormat.magnitude(crossing.magnitude))\(early)"
    }
}

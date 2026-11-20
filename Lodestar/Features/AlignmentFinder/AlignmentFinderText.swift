import Foundation
import LodestarKit

/// The words of the Alignment Finder; the same on both platforms, so keep them in step with the Android
/// `AlignmentFinderText`.
enum AlignmentFinderText {
    static let title = "Alignment Finder"

    static let intro = "Finds the nights on which a target stands over a patch of sky, such as the Milky Way core over "
        + "a ridge or in a gap between trees."

    static let noSkylineTitle = "No skyline recorded"

    static let noSkyline = "This site has no recorded skyline, so there is nothing to pick from. Open the site in "
        + "Settings \u{25B8} Location and choose Record Skyline\u{2026}, or use an azimuth and altitude window."

    static let skylineFooter = "Tap or drag the strip to pick a direction. The window runs from the skyline up to 10\u{00B0} "
        + "above it, so the target is in the gap or just over the ridge."

    static let windowFooter = "Altitudes are as seen, with refraction. Azimuth runs from north through east: 90\u{00B0} is "
        + "east, 180\u{00B0} south, 270\u{00B0} west."

    static let dimFooter = "Dim keeps the nights on which at most this share of the Moon\u{2019}s disc is lit, whether or "
        + "not it is up."

    static let searching = "Searching\u{2026}"

    static let needsObject = "Choose an object to search for."

    static let needsLocation = "Choose a location first."

    static let cutShort = "Showing the first 200 matches. Choose a shorter period or a narrower window to see the rest."

    static let pastNote = "Times are in the time zone of the observing site. Matches that have already ended are left out."

    static let sunNote = "There is no Aim button for the Sun. Use a solar filter and aim from the Aim tab."

    /// The note under a match whose target is below the skyline in the middle of it.
    static let behindSkyline = "Behind your skyline"

    /// An azimuth as degrees and the compass point, e.g. "225° SW".
    static func direction(_ degrees: Int) -> String {
        "\(degrees)\u{00B0} \(AngleFormatter.compassPoint(azimuth: Double(degrees)).abbreviation)"
    }

    /// An altitude in whole degrees, e.g. "18°".
    static func altitude(_ degrees: Double) -> String {
        "\(Int(degrees.rounded()))\u{00B0}"
    }

    /// The header of a night's group, e.g. "Night of Sat, Mar 7".
    static func nightHeader(_ night: DateInterval, in zone: TimeZone) -> String {
        "Night of \(AppFormat.day(night.start, in: zone))"
    }

    /// A match's day and times, e.g. "Sun, Mar 8 · 02:10–02:45".
    static func rowTitle(_ match: SkyWindowMatch, in zone: TimeZone) -> String {
        "\(AppFormat.day(match.interval.start, in: zone)) \u{00B7} "
            + "\(AppFormat.time(match.interval.start, in: zone))\u{2013}\(AppFormat.time(match.interval.end, in: zone))"
    }

    /// What the target and the Moon do in the middle of a match, e.g. "Alt 18° · Az 225° SW · Moon down".
    static func rowDetail(_ match: SkyWindowMatch) -> String {
        "Alt \(altitude(match.altitude)) \u{00B7} Az \(direction(Int(match.azimuth.rounded()) % 360)) \u{00B7} "
            + moon(match.moon)
    }

    /// The Moon's state, e.g. "Moon down" or "Moon up, 63% lit".
    static func moon(_ state: SkyWindowMoonState) -> String {
        state.isUp ? "Moon up, \(AppFormat.percent(state.illuminatedFraction)) lit" : "Moon down"
    }

    /// What a row says to a screen reader, one sentence per fact.
    static func rowDescription(_ match: SkyWindowMatch, in zone: TimeZone) -> String {
        "\(rowTitle(match, in: zone)). \(rowDetail(match))." + (match.isAboveSkyline ? "" : " \(behindSkyline).")
    }

    /// The title of the empty state.
    static func emptyTitle(_ reason: AlignmentFinderEmptyReason, for request: AlignmentFinderRequest) -> String {
        switch reason {
        case .neverDark: return "No darkness in this period"
        case .onlyWithMoon: return "Only with the Moon in the way"
        case .onlyInLight: return "Only in daylight or twilight"
        case .neverInWindow: return request.isAtSkyline ? "Never over this part of the skyline" : "Never in this window"
        }
    }

    /// The explanation of the empty state, over `days` days.
    static func emptyMessage(_ reason: AlignmentFinderEmptyReason, for request: AlignmentFinderRequest,
                             days: Int) -> String {
        switch reason {
        case .neverDark:
            return "At this place the Sun does not get low enough for this darkness setting in the next \(days) days. "
                + "Choose \u{201C}Any darkness\u{201D} or \u{201C}Any time\u{201D}."
        case .onlyWithMoon:
            return "The target does stand there in the next \(days) days, but only when the Moon is up or brighter "
                + "than the Moon setting allows. Choose \u{201C}Any\u{201D} for the Moon, or a longer period."
        case .onlyInLight:
            return "The target does stand there in the next \(days) days, but only when the sky is lighter than the "
                + "darkness setting allows. Choose \u{201C}Any darkness\u{201D} or \u{201C}Any time\u{201D}."
        case .neverInWindow:
            if request.isAtSkyline {
                return "In the next \(days) days the target never passes through the strip of sky just above the "
                    + "skyline there. Try another direction, a wider tolerance or a longer period."
            }
            return "In the next \(days) days the target never passes through this window, in daylight or at night. "
                + "Try a wider window or a longer period."
        }
    }
}

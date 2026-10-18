import Foundation
import LodestarKit

/// The words used for a site's recorded skyline, shared by the site editor, the site list and the recording screen.
enum HorizonText {
    /// The skyline counts as covering the sky where it rises at least this many degrees.
    private static let coveringAltitude = 1.0

    private static let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

    /// "Open horizon" without a skyline, otherwise "Recorded · 86% covered · highest 14° in the east". "Covered" is
    /// the share of the horizon where trees, hills or buildings rise at least 1° above it.
    static func status(of profile: HorizonProfile?) -> String {
        guard let profile else { return "Open horizon" }
        let altitudes = profile.altitudes
        let covered = altitudes.filter { $0 >= coveringAltitude }.count
        let share = Int((Double(covered) / Double(max(altitudes.count, 1)) * 100).rounded())
        var highest = 0
        for index in altitudes.indices where altitudes[index] > altitudes[highest] {
            highest = index
        }
        let peak = AngleFormatter.formatDegrees(altitudes[highest], decimals: 0)
        return "Recorded \u{00B7} \(share)% covered \u{00B7} highest \(peak) in the \(direction(of: Double(highest)))"
    }

    /// The nearest of the eight main directions, e.g. "north-east" written "northeast".
    static func direction(of azimuth: Double) -> String {
        let sector = Int((AstroMath.normalizeDegrees(azimuth) / 45).rounded()) % directions.count
        return directions[sector]
    }

    /// "80°–95°, 200°–260°": the stretches of azimuth that are still to be swept (at most three are listed).
    static func describe(_ ranges: [AzimuthRange]) -> String {
        let listed = ranges.prefix(3).map { range in
            // A range starts at the lower edge of its first bin and ends at the upper edge of its last.
            "\(Int(range.start.rounded(.up)) % 360)\u{00B0}\u{2013}\(Int(range.end.rounded(.down)) % 360)\u{00B0}"
        }
        let more = ranges.count > listed.count ? " and more" : ""
        return listed.joined(separator: ", ") + more
    }
}

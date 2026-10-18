import Foundation
import LodestarKit

/// The words and numbers the horizon screens show.
enum HorizonText {
    static let openHorizon = "Open horizon"

    /// A highest point counts as reached by every bin within this many degrees of the maximum.
    private static let highestTolerance = 0.05
    /// If the bins at the highest altitude, spread round the circle, average out to less than this share of their
    /// number (as unit vectors), the skyline is about as high everywhere.
    private static let spreadResultant = 0.2
    /// Gaps are listed up to this many before "and N more".
    private static let listedGaps = 3
    private static let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

    /// The state of a site's skyline as stored now: "Open horizon" or "Recorded · 86% covered · highest 14° in the east".
    static func status(of site: SavedSite) -> String {
        status(of: site.horizon, coverage: HorizonCoverageMemory.recall(for: site))
    }

    /// "Open horizon" without a skyline, otherwise "Recorded · 86% covered · highest 14° in the east". The coverage
    /// is left out when it is not known: the share of the circle a sweep reached is not part of the stored skyline.
    static func status(of profile: HorizonProfile?, coverage: Double?) -> String {
        guard let profile, !profile.isFlat else { return openHorizon }
        var parts = ["Recorded"]
        if let coverage {
            parts.append("\(AppFormat.percent(coverage)) covered")
        }
        parts.append(highest(profile))
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "highest 14° in the east".
    static func highest(_ profile: HorizonProfile) -> String {
        "highest \(AngleFormatter.formatDegrees(profile.maximumAltitude, decimals: 0)) \(highestPlace(profile))"
    }

    /// Where the skyline is highest: "in the east", or "all round" when it is about as high everywhere.
    static func highestPlace(_ profile: HorizonProfile) -> String {
        let maximum = profile.maximumAltitude
        var east = 0.0
        var north = 0.0
        var count = 0
        for (index, altitude) in profile.altitudes.enumerated() where altitude >= maximum - highestTolerance {
            east += AstroMath.sinDeg(Double(index))
            north += AstroMath.cosDeg(Double(index))
            count += 1
        }
        guard count > 0, (east * east + north * north).squareRoot() >= spreadResultant * Double(count) else {
            return "all round"
        }
        return "in the \(direction(of: AstroMath.atan2Deg(east, north)))"
    }

    /// The nearest of the eight main directions, e.g. "northeast".
    static func direction(of azimuth: Double) -> String {
        let sector = Int((AstroMath.normalizeDegrees(azimuth) / 45).rounded()) % directions.count
        return directions[sector]
    }

    /// "80°–95°": the whole degrees an unrecorded stretch covers (a range starts at the lower edge of a bin).
    static func gapText(_ gap: AzimuthRange) -> String {
        let bins = HorizonProfile.binCount
        let first = ((Int((gap.start + 0.5).rounded()) % bins) + bins) % bins
        let last = ((Int((gap.start + gap.length - 0.5).rounded()) % bins) + bins) % bins
        return first == last ? "\(first)\u{00B0}" : "\(first)\u{00B0}\u{2013}\(last)\u{00B0}"
    }

    /// The first stretches that are still to sweep: "80°–95°, 200°–260° and 2 more".
    static func gapsText(_ gaps: [AzimuthRange]) -> String {
        let listed = gaps.prefix(listedGaps).map(gapText).joined(separator: ", ")
        let more = gaps.count - listedGaps
        return more > 0 ? "\(listed) and \(more) more" : listed
    }

    /// The great-circle distance between two places in metres (spherical Earth: enough for a warning).
    static func distanceMetres(_ a: GeographicLocation, _ b: GeographicLocation) -> Double {
        let latitudeA = AstroMath.radians(a.latitude)
        let latitudeB = AstroMath.radians(b.latitude)
        let sinLatitude = sin((latitudeB - latitudeA) / 2)
        let sinLongitude = sin(AstroMath.radians(b.longitude - a.longitude) / 2)
        let half = sinLatitude * sinLatitude + cos(latitudeA) * cos(latitudeB) * sinLongitude * sinLongitude
        return 2 * 6_371_000 * asin(min(max(half, 0), 1).squareRoot())
    }
}

/// The share of the circle a sweep reached, remembered next to a site's skyline. The stored skyline is only the 360
/// altitudes, so the coverage lives in this device's preferences together with a fingerprint of the skyline it belongs
/// to; a skyline from elsewhere (a restore, another version) simply has no coverage to show.
enum HorizonCoverageMemory {
    private static func key(_ siteID: UUID) -> String {
        "lodestar.horizon.coverage.\(siteID.uuidString)"
    }

    /// The coverage recorded with `site`'s skyline, or `nil` when there is none or the skyline has changed since.
    static func recall(for site: SavedSite) -> Double? {
        guard let horizon = site.horizon, let text = UserDefaults.standard.string(forKey: key(site.id)) else {
            return nil
        }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == fingerprint(of: horizon), let coverage = Double(parts[1]),
              (0.0...1.0).contains(coverage) else { return nil }
        return coverage
    }

    /// Remembers `coverage` for `horizon` of the site `siteID`; forgets it when there is no skyline.
    static func store(siteID: UUID, horizon: HorizonProfile?, coverage: Double) {
        if let horizon {
            UserDefaults.standard.set("\(fingerprint(of: horizon)):\(coverage)", forKey: key(siteID))
        } else {
            UserDefaults.standard.removeObject(forKey: key(siteID))
        }
    }

    /// A short, stable text for a skyline (FNV-1a over its altitudes in tenths of a degree).
    static func fingerprint(of profile: HorizonProfile) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for altitude in profile.altitudes {
            let tenths = Int16(truncatingIfNeeded: Int((altitude * 10).rounded()))
            let bytes = [UInt8(truncatingIfNeeded: tenths), UInt8(truncatingIfNeeded: tenths >> 8)]
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return String(hash, radix: 16)
    }
}

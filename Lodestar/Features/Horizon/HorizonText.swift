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
/// to; a skyline from elsewhere (a restore, another version) simply has no coverage to show. The degrees that were
/// swept are kept too (as 90 hex digits after the coverage), so a later sweep that keeps the old skyline for the rest
/// can add up what both reached; entries stored without them still read, they just cannot be added up exactly.
enum HorizonCoverageMemory {
    /// What is remembered with a skyline.
    struct Entry: Equatable {
        /// The share of the circle swept, 0…1.
        let coverage: Double
        /// For each whole degree 0…359, whether it was swept; `nil` when it was not stored.
        let mask: [Bool]?
    }

    private static func key(_ siteID: UUID) -> String {
        "lodestar.horizon.coverage.\(siteID.uuidString)"
    }

    /// The coverage recorded with `site`'s skyline, or `nil` when there is none or the skyline has changed since.
    static func recall(for site: SavedSite) -> Double? {
        entry(for: site)?.coverage
    }

    /// Everything remembered with `site`'s skyline, or `nil` when there is nothing or the skyline has changed since.
    static func entry(for site: SavedSite) -> Entry? {
        guard let horizon = site.horizon, let text = UserDefaults.standard.string(forKey: key(site.id)) else {
            return nil
        }
        let parts = text.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0] == fingerprint(of: horizon), let coverage = Double(parts[1]),
              (0.0...1.0).contains(coverage) else { return nil }
        return Entry(coverage: coverage, mask: parts.count == 3 ? decode(parts[2]) : nil)
    }

    /// Remembers `coverage` (and the swept degrees, if known) for `horizon` of the site `siteID`; forgets it when
    /// there is no skyline.
    static func store(siteID: UUID, horizon: HorizonProfile?, coverage: Double, mask: [Bool]? = nil) {
        guard let horizon else {
            forget(siteID: siteID)
            return
        }
        var text = "\(fingerprint(of: horizon)):\(coverage)"
        if let mask, mask.count == HorizonProfile.binCount {
            text += ":\(encode(mask))"
        }
        UserDefaults.standard.set(text, forKey: key(siteID))
    }

    /// Drops what is remembered for the site `siteID`.
    static func forget(siteID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(siteID))
    }

    /// What is known of the circle when a sweep that reached `mask` is saved over `site`'s skyline and the old one
    /// stays wherever the sweep did not reach: both sweeps added up. `nil` when nothing is remembered about the old
    /// skyline, because then it is not known how much of it was ever swept.
    static func merged(sweep mask: [Bool], over site: SavedSite) -> Entry? {
        guard let old = entry(for: site) else { return nil }
        guard let oldMask = old.mask, oldMask.count == mask.count else {
            // Stored without the degrees: all that can be said is that at least the larger of the two shares is known.
            return Entry(coverage: max(old.coverage, share(of: mask)), mask: nil)
        }
        let union = zip(oldMask, mask).map { $0 || $1 }
        return Entry(coverage: share(of: union), mask: union)
    }

    private static func share(of mask: [Bool]) -> Double {
        Double(mask.filter { $0 }.count) / Double(HorizonProfile.binCount)
    }

    /// One hex digit per four degrees, the lowest degree in the lowest bit.
    private static func encode(_ mask: [Bool]) -> String {
        var text = ""
        for start in stride(from: 0, to: mask.count, by: 4) {
            var nibble = 0
            for offset in 0..<4 where start + offset < mask.count && mask[start + offset] {
                nibble |= 1 << offset
            }
            text += String(nibble, radix: 16)
        }
        return text
    }

    /// The degrees `encode` wrote, or `nil` when the text is not exactly one circle of them.
    private static func decode(_ text: String) -> [Bool]? {
        guard text.count * 4 == HorizonProfile.binCount else { return nil }
        var mask = [Bool]()
        mask.reserveCapacity(HorizonProfile.binCount)
        for digit in text {
            guard let nibble = Int(String(digit), radix: 16) else { return nil }
            for offset in 0..<4 {
                mask.append(nibble & (1 << offset) != 0)
            }
        }
        return mask
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

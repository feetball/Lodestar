import Foundation

/// Why a full Moon is special.
public enum FullMoonCategory: String, CaseIterable, Sendable, Hashable, Codable {
    /// The full Moon is unusually close: its geocentric distance is at most
    /// `FullMoonSpecialFinder.supermoonMaximumDistanceKilometers`.
    case supermoon
    /// The full Moon is unusually far: its geocentric distance is at least
    /// `FullMoonSpecialFinder.micromoonMinimumDistanceKilometers`.
    case micromoon
    /// The second full Moon of a calendar month in the chosen time zone.
    case blueMoon

    /// The English name, e.g. "Supermoon".
    public var displayName: String {
        switch self {
        case .supermoon: "Supermoon"
        case .micromoon: "Micromoon"
        case .blueMoon: "Blue Moon"
        }
    }
}

/// A full Moon that is a supermoon, a micromoon or a blue moon.
public struct FullMoonSpecial: Sendable, Hashable {
    /// Why it is special: one to three categories in the order of `FullMoonCategory`.
    public let categories: [FullMoonCategory]
    /// The Moon's geocentric distance at the full Moon in kilometres.
    public let distanceKilometers: Double
    /// The Moon's geocentric angular diameter at the full Moon in arcseconds.
    public let angularDiameterArcseconds: Double

    public init(categories: [FullMoonCategory], distanceKilometers: Double, angularDiameterArcseconds: Double) {
        self.categories = categories
        self.distanceKilometers = distanceKilometers
        self.angularDiameterArcseconds = angularDiameterArcseconds
    }
}

/// Finds the supermoons, micromoons and blue moons.
///
/// **Definitions.** The full Moon is the instant of lunar elongation 180°. A *supermoon* is a full Moon whose
/// geocentric centre distance is at most `supermoonMaximumDistanceKilometers` (362 500 km). This is the working form
/// of R. Nolle's "within 90 % of its closest perigee" rule: the full Moon falls within about a day of a perigee of
/// the closest kind, and the cut reproduces the usual lists (for 2026: 3 January at 362 312 km, 24 November and
/// 24 December). A *micromoon* is the mirror image, at least `micromoonMinimumDistanceKilometers` (400 600 km), which
/// is as far from the extreme apogee (406 720 km) as the supermoon cut is from the extreme perigee (356 371 km;
/// J. Meeus, *Astronomical Algorithms*, ch. 50). A *blue moon* is the second of two full Moons in one calendar month
/// of the given time zone (the "monthly" blue moon).
///
/// Cost for one year: about 10 ms (the phases are shared with the eclipse finders when `EventCalculator` runs them).
public enum FullMoonSpecialFinder {
    /// Largest geocentric distance of a supermoon, in kilometres.
    public static let supermoonMaximumDistanceKilometers = 362_500.0
    /// Smallest geocentric distance of a micromoon, in kilometres.
    public static let micromoonMinimumDistanceKilometers = 400_600.0

    /// The special full Moons from `from` to `to` (both inclusive), as events without visibility, in time order.
    /// `timeZone` decides which full Moons share a calendar month.
    public static func events(from: Date, to: Date, timeZone: TimeZone = .gmt) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let end = EventSearch.limitedEnd(from: from, to: to)
        return events(from: from, to: end, timeZone: timeZone,
                      phases: PhaseTable(from: monthStart(of: from, timeZone: timeZone), to: end))
    }

    /// The finder with the full Moons already known; `phases` must start at or before the start of the month of `from`.
    static func events(from: Date, to: Date, timeZone: TimeZone, phases: PhaseTable) -> [AstronomicalEvent] {
        var found = [AstronomicalEvent]()
        var lastMonth = Int.min
        var countInMonth = 0
        for full in phases.fullMoons {
            let key = monthKey(of: full, timeZone: timeZone)
            if key != lastMonth {
                lastMonth = key
                countInMonth = 0
            }
            countInMonth += 1
            if full < from || full > to { continue }
            let jd = JulianDate(date: full)
            let distance = Ephemeris.geocentricJ2000(of: .moon, at: jd).length * SkyFrame.kilometersPerAU
            var categories = [FullMoonCategory]()
            if distance <= supermoonMaximumDistanceKilometers { categories.append(.supermoon) }
            if distance >= micromoonMinimumDistanceKilometers { categories.append(.micromoon) }
            if countInMonth == 2 { categories.append(.blueMoon) }
            if categories.isEmpty { continue }
            let diameter = Ephemeris.state(of: .moon, at: jd).angularDiameterArcseconds
            found.append(AstronomicalEvent(
                date: full,
                details: .fullMoonSpecial(FullMoonSpecial(categories: categories, distanceKilometers: distance,
                                                          angularDiameterArcseconds: diameter)),
                visibility: nil))
        }
        return found
    }

    /// The start of the calendar month of `date` in `timeZone`.
    static func monthStart(of date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// A number that is the same for all instants of one calendar month in `timeZone` and grows with time.
    private static func monthKey(of date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 12 + (components.month ?? 1) - 1
    }
}

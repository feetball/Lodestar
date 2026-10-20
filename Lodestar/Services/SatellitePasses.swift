import Foundation
import LodestarKit

/// The two lists of the Passes screen.
enum SatellitePassFilter: String, CaseIterable, Identifiable, Sendable {
    /// Only the International Space Station.
    case iss
    /// The ISS and every other satellite of the lists.
    case bright

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iss: return "ISS"
        case .bright: return "Bright satellites"
        }
    }
}

/// One visible pass of one satellite.
struct SatellitePassItem: Identifiable, Hashable, Sendable {
    let satellite: Satellite
    let group: ElementSetGroup
    let pass: SatellitePass
    /// The highest point of the pass while it can be seen. The pass's own culmination can lie in Earth's shadow, after
    /// the visible part has ended (`SatellitePasses.visiblePeak`).
    let peak: SatellitePassPoint

    /// Tells passes apart: the satellite and the rise time to the minute (two searches find the same rise within a few
    /// milliseconds, and the passes of one satellite are far more than a minute apart).
    var id: String { "\(satellite.catalogNumber)@\(Int64((pass.rise.date.timeIntervalSince1970 / 60).rounded()))" }

    /// Whether this is the International Space Station.
    var isISS: Bool { satellite.catalogNumber == SatelliteLibrary.issCatalogNumber }

    /// "ISS" for the station, else the name of the element set.
    var name: String { isISS ? "ISS" : satellite.name }

    /// When the satellite becomes visible; the rise time for a pass without a visible part.
    var start: Date { pass.visibleSpan?.start ?? pass.rise.date }

    /// When it stops being visible.
    var end: Date { pass.visibleSpan?.end ?? pass.set.date }

    /// Whether the element set is within its group's freshness limit at `date`.
    func isFresh(at date: Date) -> Bool { group.isFresh(satellite.elements, at: date) }

    static func == (lhs: SatellitePassItem, rhs: SatellitePassItem) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Finding and selecting the passes the screens show. Pure.
enum SatellitePasses {
    /// The Passes screen looks this many days ahead.
    static let horizonDays = 3

    /// The search starts this long before `start`, so that a pass already under way at `start` is found whole: the
    /// finder cuts a pass at the start of its window (rise, peak and visible span of what is left). Longer than any
    /// pass of a low-orbit satellite.
    private static let lead: TimeInterval = 3_600

    /// Every visible pass (sunlit satellite, dark sky, above 10°) of the library's ISS and bright satellites that is
    /// not over at `start`, in the next `horizonDays` days, by the time it becomes visible. Takes about a second on a
    /// phone: run it off the main actor.
    static func compute(library: SatelliteLibrary, observer: Observer, start: Date) -> [SatellitePassItem] {
        let finder = SatellitePassFinder(observer: observer,
                                         interval: DateInterval(start: start.addingTimeInterval(-lead),
                                                                duration: Double(horizonDays) * 86_400 + lead))
        var items: [SatellitePassItem] = []
        for entry in library.passSatellites {
            for pass in finder.passes(of: entry.satellite) where pass.isVisible {
                // The passes that ended before `start` were searched for only to leave the others whole.
                guard let span = pass.visibleSpan, span.end > start else { continue }
                let peak = visiblePeak(of: pass, satellite: entry.satellite, observer: observer)
                items.append(SatellitePassItem(satellite: entry.satellite, group: entry.group, pass: pass, peak: peak))
            }
        }
        return items.sorted { $0.start < $1.start }
    }

    /// The highest point of `pass` while it can be seen. The pass's culmination can lie outside the visible part (the
    /// satellite enters Earth's shadow before it gets there). The altitude rises up to the culmination and falls after
    /// it, so the highest point of a visible part that does not hold the culmination is its end nearer to it.
    static func visiblePeak(of pass: SatellitePass, satellite: Satellite, observer: Observer) -> SatellitePassPoint {
        let culmination = pass.culmination
        var best: SatellitePassPoint?
        for part in pass.visibleIntervals {
            if part.start <= culmination.date && culmination.date <= part.end { return culmination }
            let date = culmination.date < part.start ? part.start : part.end
            guard let look = satellite.look(at: date, observer: observer) else { continue }
            let point = SatellitePassPoint(date: look.date, azimuth: look.azimuth, altitude: look.altitude,
                                           rangeKilometers: look.rangeKilometers, isSunlit: look.isSunlit,
                                           magnitude: look.magnitude)
            if let current = best, current.altitude >= point.altitude { continue }
            best = point
        }
        return best ?? culmination
    }

    /// The passes for a `filter` of the Passes screen, in the order given.
    static func filtered(_ items: [SatellitePassItem], filter: SatellitePassFilter) -> [SatellitePassItem] {
        switch filter {
        case .iss: return items.filter(\.isISS)
        case .bright: return items
        }
    }

    /// The passes not over at `now`.
    static func upcoming(_ items: [SatellitePassItem], now: Date) -> [SatellitePassItem] {
        items.filter { $0.end > now }
    }

    /// The visible passes that fall in `night` and are not over at `now`, the ISS first and each satellite's passes in
    /// time order, at most `limit` of them.
    static func tonight(_ items: [SatellitePassItem], night: DateInterval, now: Date, limit: Int) -> [SatellitePassItem] {
        let inNight = upcoming(items, now: now).filter { $0.start < night.end && $0.end > night.start }
        let sorted = inNight.filter(\.isISS).sorted { $0.start < $1.start }
            + inNight.filter { !$0.isISS }.sorted { $0.start < $1.start }
        return Array(sorted.prefix(limit))
    }
}

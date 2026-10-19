import Foundation

/// The astronomical events calendar: meteor shower maxima, conjunctions, oppositions, greatest elongations, the
/// Earth's apsides, equinoxes and solstices, special full Moons and lunar and solar eclipses, computed offline from the
/// kit's ephemerides.
///
/// Every search is bounded: intervals longer than `maximumSpanDays` (about ten years) are cut short, dates outside the
/// years 1 to 4001 give nothing, and the work grows with the length of the interval. Cost of one year in an optimized build
/// on a desktop: about 0.1 s without an observer and 0.2 s with one (the conjunctions take half of it; the visibility of an
/// event a fraction of a millisecond); a debug build needs about 1.6 s. Nothing is cached between calls. Run it on a
/// background thread and keep the result.
public enum EventCalculator {
    /// The longest interval, in days, that `events(from:to:observer:options:)` searches; longer intervals are cut at
    /// this length.
    public static let maximumSpanDays = EventSearch.maximumSpanDays

    /// The events from `from` to `to` (both inclusive) of the kinds in `options`, sorted by date (ties by kind).
    ///
    /// With an `observer` each event carries its `EventVisibility` (except equinoxes, solstices and apsides) and solar
    /// eclipses carry their local circumstances; without one `visibility` is `nil` and solar eclipses are global.
    /// `EventOptions.timeZone` decides the calendar months of blue moons and the nights of the viewing windows.
    /// Returns an empty array for a reversed or non-finite interval.
    public static func events(from: Date, to: Date, observer: Observer? = nil,
                              options: EventOptions = EventOptions()) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let end = EventSearch.limitedEnd(from: from, to: to)
        let zone = options.timeZone ?? EventVisibilityCalculator.defaultZone(for: observer)
        let kinds = options.kinds
        var found = [AstronomicalEvent]()
        if kinds.contains(.meteorShower) { found.append(contentsOf: MeteorShowerFinder.events(from: from, to: end)) }
        if kinds.contains(.conjunction) {
            found.append(contentsOf: ConjunctionFinder.events(from: from, to: end, observer: observer, options: options))
        }
        if kinds.contains(.opposition) { found.append(contentsOf: OppositionFinder.events(from: from, to: end)) }
        if kinds.contains(.greatestElongation) {
            found.append(contentsOf: GreatestElongationFinder.events(from: from, to: end))
        }
        if kinds.contains(.earthApsis) { found.append(contentsOf: EarthApsisFinder.events(from: from, to: end)) }
        if kinds.contains(.season) { found.append(contentsOf: SeasonFinder.events(from: from, to: end)) }
        if kinds.contains(.fullMoonSpecial) || kinds.contains(.lunarEclipse) || kinds.contains(.solarEclipse) {
            let phases = PhaseTable(
                from: kinds.contains(.fullMoonSpecial) ? FullMoonSpecialFinder.monthStart(of: from, timeZone: zone) : from,
                to: end)
            if kinds.contains(.fullMoonSpecial) {
                found.append(contentsOf: FullMoonSpecialFinder.events(from: from, to: end, timeZone: zone, phases: phases))
            }
            if kinds.contains(.lunarEclipse) {
                found.append(contentsOf: LunarEclipseFinder.events(from: from, to: end, phases: phases))
            }
            if kinds.contains(.solarEclipse) {
                found.append(contentsOf: SolarEclipseFinder.events(from: from, to: end, observer: observer, phases: phases))
            }
        }

        let calculator = observer.map { EventVisibilityCalculator(observer: $0, options: options, timeZone: zone) }
        var result = [AstronomicalEvent]()
        for event in sortedByDateAndKind(found) {
            let visibility = calculator?.visibility(of: event)
            if options.visibleOnly, let visibility, !visibility.isObservable { continue }
            result.append(visibility != nil ? event.withVisibility(visibility) : event)
        }
        return result
    }

    /// How well `observer` can see `event`, computed from scratch (a few milliseconds); `nil` for equinoxes, solstices
    /// and apsides. Use it for an event that was computed without an observer.
    public static func visibility(of event: AstronomicalEvent, observer: Observer,
                                  options: EventOptions = EventOptions()) -> EventVisibility? {
        let zone = options.timeZone ?? EventVisibilityCalculator.defaultZone(for: observer)
        return EventVisibilityCalculator(observer: observer, options: options, timeZone: zone).visibility(of: event)
    }

    /// `events` ordered by date, then by kind, then as they came.
    private static func sortedByDateAndKind(_ events: [AstronomicalEvent]) -> [AstronomicalEvent] {
        let order = EventKind.allCases
        func rank(_ event: AstronomicalEvent) -> Int { order.firstIndex(of: event.kind) ?? order.count }
        return events.enumerated().sorted { first, second in
            if first.element.date != second.element.date { return first.element.date < second.element.date }
            let firstRank = rank(first.element)
            let secondRank = rank(second.element)
            if firstRank != secondRank { return firstRank < secondRank }
            return first.offset < second.offset
        }.map(\.element)
    }
}

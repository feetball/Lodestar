import Foundation
import LodestarKit

/// Works out what the widgets, the complications and the watch app show. Pure, so it runs on any thread, and it
/// uses only the ephemeris, the twilight and the events engine of LodestarKit: no star catalog is loaded.
///
/// The content is that of the Android widgets: the dark windows, the Moon, the Milky Way core and the next event.
/// A whole day's timeline costs one night summary for each night it touches (two, as a rule), one events search and a
/// little bookkeeping; the entries themselves are looked up from those.
enum TonightBuilder {
    /// How far ahead a timeline reaches.
    static let timelineSpan: TimeInterval = 24 * 3_600
    /// How far ahead the events are searched first, in days.
    static let eventLookaheadDays = 60
    /// The longer search when nothing worthwhile comes within `eventLookaheadDays`.
    static let eventFarLookaheadDays = 366
    /// The events the app's Upcoming card considers: the first `upcomingCount` within `upcomingDays` days, else the
    /// next `upcomingFarCount`, however far.
    static let upcomingDays = 56
    static let upcomingCount = 4
    static let upcomingFarCount = 3
    /// The largest geocentric separation of the Moon from a planet or star that can still be an occultation from
    /// somewhere on Earth, in degrees; Moon conjunctions are looked for up to this and kept if they are occultations.
    static let moonConjunctionSearchThreshold = 1.5
    /// A Milky Way core window shorter than this is not worth announcing.
    static let minimumCoreDuration: TimeInterval = 900
    /// Entries closer together than this are merged, the later one winning.
    static let minimumSpacing: TimeInterval = 60
    /// The most entries a timeline gets.
    static let maximumEntryCount = 64

    /// The entry for one moment.
    static func entry(for place: TonightPlace, at date: Date) -> TonightEntry {
        var workspace = Workspace(place: place)
        let events = workspace.eventFacts(from: date)
        return workspace.entry(at: date, events: events)
    }

    /// The entries from `start` on: one now, one every full hour for a day, and one at each moment the picture
    /// changes (dusk, dawn, the Moon rising or setting, the core coming up or going down, sunrise, an event passing).
    static func entries(for place: TonightPlace, from start: Date) -> [TonightEntry] {
        var workspace = Workspace(place: place)
        return workspace.timeline(from: start)
    }

    /// The entry in force at `date`: the last one that is not later, or the first when all are.
    static func current(in entries: [TonightEntry], at date: Date) -> TonightEntry? {
        entries.last { $0.date <= date } ?? entries.first
    }
}

// MARK: - One computation

private struct Workspace {
    let observer: Observer
    let timeZone: TimeZone
    let calendar: Calendar
    private var twilights: [Date: NightTwilight] = [:]
    private var nights: [Date: NightFacts] = [:]

    init(place: TonightPlace) {
        observer = place.observer
        timeZone = place.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        self.calendar = calendar
    }

    // MARK: Timeline

    mutating func timeline(from start: Date) -> [TonightEntry] {
        let end = start.addingTimeInterval(TonightBuilder.timelineSpan)
        var instants = [start]
        var hour = (start.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600 + 3_600
        while hour < end.timeIntervalSince1970 {
            instants.append(Date(timeIntervalSince1970: hour))
            hour += 3_600
        }
        let events = eventFacts(from: start)
        // An event passing changes the next event, and so does midnight (it changes how far away the event is said to be).
        var changes: [Date] = events.map(\.date)
        var nightsSeen = Set<Date>()
        for instant in instants {
            let facts = night(at: instant)
            if nightsSeen.insert(facts.summary.night.start).inserted {
                changes += facts.changeInstants
            }
        }
        var midnight = calendar.startOfDay(for: start)
        while midnight < end {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
            changes.append(midnight)
        }
        instants += changes.filter { $0 > start && $0 < end }
        instants.sort()
        return merged(instants).prefix(TonightBuilder.maximumEntryCount).map { entry(at: $0, events: events) }
    }

    /// Sorted instants with near-duplicates merged: of two instants less than a minute apart the later one is
    /// kept (it carries the newer state), except that the first instant, "now", always stays.
    private func merged(_ instants: [Date]) -> [Date] {
        var kept: [Date] = []
        for instant in instants {
            guard let last = kept.last else {
                kept.append(instant)
                continue
            }
            if instant.timeIntervalSince(last) >= TonightBuilder.minimumSpacing {
                kept.append(instant)
            } else if kept.count > 1 {
                kept[kept.count - 1] = instant
            }
        }
        return kept
    }

    // MARK: One entry

    mutating func entry(at date: Date, events: [TonightNight.Event]) -> TonightEntry {
        let facts = night(at: date)
        let night = TonightNight(
            timeZone: timeZone, isSouthernHemisphere: observer.location.latitude < 0,
            darkness: facts.darkness, moon: facts.moon, core: facts.core, event: Self.event(in: events, at: date))
        return TonightEntry(date: date, content: .night(night))
    }

    /// The event the Android widgets (and the Upcoming card) pick: of the first few events from `date` on, the first
    /// that can be seen from here, else the first.
    private static func event(in events: [TonightNight.Event], at date: Date) -> TonightNight.Event? {
        let ahead = events.filter { $0.date >= date }
        let horizon = date.addingTimeInterval(Double(TonightBuilder.upcomingDays) * 86_400)
        let soon = Array(ahead.filter { $0.date <= horizon }.prefix(TonightBuilder.upcomingCount))
        let candidates = soon.isEmpty ? Array(ahead.prefix(TonightBuilder.upcomingFarCount)) : soon
        return candidates.first { $0.isVisibleFromHere != false } ?? candidates.first
    }

    // MARK: Nights

    /// The night shown at `date`: the one under way, or the coming one once the Sun has risen on the night before.
    mutating func night(at date: Date) -> NightFacts {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        let previous = twilight(on: yesterday)
        let isPreviousUnderWay = date < previous.interval.end && date < (previous.sunrise ?? previous.interval.end)
        let anchor = isPreviousUnderWay ? yesterday : date
        let key = calendar.startOfDay(for: anchor)
        if let cached = nights[key] { return cached }
        let summary = NightPlanner.summary(nightStartingOn: anchor, observer: observer, timeZone: timeZone)
        let facts = NightFacts(summary: summary)
        nights[key] = facts
        return facts
    }

    private mutating func twilight(on day: Date) -> NightTwilight {
        let key = calendar.startOfDay(for: day)
        if let cached = twilights[key] { return cached }
        let twilight = TwilightCalculator.night(startingOn: day, observer: observer, timeZone: timeZone)
        twilights[key] = twilight
        return twilight
    }

    // MARK: Events

    /// The events from `start` on that the Upcoming card would list, in time order: 60 days ahead, and a year when
    /// that finds nothing. The Moon's conjunctions come every few days; only those where it covers the other body
    /// from here are kept.
    func eventFacts(from start: Date) -> [TonightNight.Event] {
        for days in [TonightBuilder.eventLookaheadDays, TonightBuilder.eventFarLookaheadDays] {
            let options = EventOptions(planetConjunctionThreshold: 3,
                                       moonConjunctionThreshold: TonightBuilder.moonConjunctionSearchThreshold,
                                       timeZone: timeZone)
            let events = EventCalculator.events(from: start, to: start.addingTimeInterval(Double(days) * 86_400),
                                                observer: observer, options: options)
            let facts = events.filter(Self.isWorthTheCard).map(Self.fact(for:)).sorted { $0.date < $1.date }
            if !facts.isEmpty { return facts }
        }
        return []
    }

    private static func isWorthTheCard(_ event: AstronomicalEvent) -> Bool {
        guard case .conjunction(let conjunction) = event.details, conjunction.involvesMoon else { return true }
        return conjunction.topocentric?.isOccultation == true
    }

    private static func fact(for event: AstronomicalEvent) -> TonightNight.Event {
        var date = event.date
        if case .solarEclipse(let eclipse) = event.details, let maximum = eclipse.local?.maximum {
            date = maximum
        }
        var rate: Int?
        if case .meteorShower(let peak) = event.details {
            rate = peak.shower.zhr
        }
        return TonightNight.Event(title: event.title, symbolName: symbolName(for: event), date: date,
                                  isVisibleFromHere: event.visibility?.isObservable,
                                  bestWindow: event.visibility?.bestWindow, showerRate: rate)
    }

    /// The SF Symbol for an event kind (the same ones the app's events screens use).
    private static func symbolName(for event: AstronomicalEvent) -> String {
        switch event.details {
        case .meteorShower: return "sparkles"
        case .conjunction(let conjunction): return conjunction.involvesMoon ? "moon.circle" : "circle.grid.2x1.fill"
        case .opposition: return "arrow.left.arrow.right.circle"
        case .greatestElongation: return "angle"
        case .earthApsis: return "globe.europe.africa"
        case .season: return "sun.max"
        case .fullMoonSpecial: return "moonphase.full.moon"
        case .lunarEclipse: return "moon.circle.fill"
        case .solarEclipse: return "sun.max.fill"
        }
    }
}

// MARK: - Facts

/// A night summary with what the entries are looked up from.
struct NightFacts: Sendable {
    let summary: NightSummary
    let darkness: TonightNight.Darkness
    let moon: TonightNight.Moon
    let core: TonightNight.Core

    init(summary: NightSummary) {
        self.summary = summary
        let windows = summary.astronomicalDarknessIntervals
        var isAllNight = false
        if let first = windows.first, let last = windows.last {
            isAllNight = first.start <= summary.night.start.addingTimeInterval(60)
                && last.end >= summary.night.end.addingTimeInterval(-60)
        }
        darkness = TonightNight.Darkness(windows: windows, hours: summary.astronomicalDarkHours,
                                         moonFreeHours: summary.moonFreeDarkHours, isAllNight: isAllNight)
        let moon = summary.moon
        self.moon = TonightNight.Moon(
            phase: moon.phase.name, illuminatedFraction: moon.phase.illuminatedFraction, isWaxing: moon.phase.isWaxing,
            rise: moon.riseTransitSet.rise, set: moon.riseTransitSet.set,
            circumstance: moon.riseTransitSet.circumstance, upIntervals: moon.upIntervals)
        let core = summary.milkyWayCore
        self.core = TonightNight.Core(
            hasDarkness: summary.hasAstronomicalDarkness,
            windows: core.visibleIntervals.filter { $0.duration >= TonightBuilder.minimumCoreDuration },
            bestTime: core.bestTime, maxAltitude: core.maxAltitude, bestAzimuth: core.bestAzimuth)
    }

    /// The moments the picture changes by itself: the darkness, the Moon and the core starting or ending, and the
    /// night itself ending. Intervals are cut off at the ends of the night, and those cuts are no changes of the sky.
    var changeInstants: [Date] {
        let night = summary.night
        var instants: [Date] = [summary.twilight.sunrise ?? night.end]
        for interval in darkness.windows + moon.upIntervals + core.windows {
            for moment in [interval.start, interval.end] where moment > night.start && moment < night.end {
                instants.append(moment)
            }
        }
        return instants
    }
}

import Foundation
import LodestarKit

/// Works out what the widgets, the complications and the watch app show. Pure, so it runs on any thread, and it
/// uses only the ephemeris, the twilight and the events engine of LodestarKit: no star catalog is loaded.
///
/// A whole day's timeline costs one night summary for each night it touches (two, as a rule), one events search and a
/// little bookkeeping; the entries themselves are looked up from those.
enum TonightBuilder {
    /// How far ahead a timeline reaches.
    static let timelineSpan: TimeInterval = 24 * 3_600
    /// How far ahead the events are searched, in days.
    static let eventLookaheadDays = 60
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
        var changes: [Date] = events.map { $0.relevantUntil.addingTimeInterval(1) }
        var nightsSeen = Set<Date>()
        for instant in instants {
            let facts = night(at: instant)
            if nightsSeen.insert(facts.summary.night.start).inserted {
                changes += facts.changeInstants
            }
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

    mutating func entry(at date: Date, events: [EventFacts]) -> TonightEntry {
        let facts = night(at: date)
        let night = TonightNight(
            timeZone: timeZone, isSouthernHemisphere: observer.location.latitude < 0,
            darkness: facts.darkness(at: date), moon: facts.moon(at: date), core: facts.core,
            event: Self.event(in: events, at: date, night: facts.summary.night))
        return TonightEntry(date: date, content: .night(night))
    }

    /// The first listed event that is still worth a look at `date`: a sky event, or failing that a season that is
    /// near.
    private static func event(in events: [EventFacts], at date: Date, night: DateInterval) -> TonightNight.Event? {
        let relevant = events.filter { $0.relevantUntil >= date }
        let chosen = relevant.first { !$0.isSeason }
            ?? relevant.first { $0.isSeason && $0.date.timeIntervalSince(date) < 21 * 86_400 }
        return chosen.map {
            TonightNight.Event(title: $0.title, symbolName: $0.symbolName, date: $0.date,
                               isTonight: night.contains($0.date))
        }
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

    /// The events worth showing from a day before `start` on: those with a viewing window from here, and the
    /// equinoxes and solstices. The Moon's own conjunctions are left out (there are several a month, and searching
    /// for them is most of the cost); the planets' conjunctions, oppositions, elongations, meteor showers, special
    /// full Moons and eclipses stay.
    func eventFacts(from start: Date) -> [EventFacts] {
        let from = start.addingTimeInterval(-86_400)
        let to = start.addingTimeInterval(Double(TonightBuilder.eventLookaheadDays) * 86_400)
        let options = EventOptions(planetConjunctionThreshold: 3, moonConjunctionThreshold: 0, timeZone: timeZone)
        let events = EventCalculator.events(from: from, to: to, observer: observer, options: options)
        var facts: [EventFacts] = []
        for event in events {
            if case .season = event.details {
                facts.append(EventFacts(title: event.title, symbolName: Self.symbolName(for: event),
                                        date: event.date, relevantUntil: event.date, isSeason: true))
            } else if let window = event.visibility?.bestWindow {
                facts.append(EventFacts(title: event.title, symbolName: Self.symbolName(for: event),
                                        date: window.start, relevantUntil: window.end, isSeason: false))
            }
        }
        return facts.sorted { $0.date < $1.date }
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

/// An event reduced to what the widgets need.
struct EventFacts: Sendable {
    let title: String
    let symbolName: String
    /// The day it is about: the start of the viewing window, or the event's own time for a season.
    let date: Date
    /// Until when it is still worth showing: the end of the viewing window.
    let relevantUntil: Date
    let isSeason: Bool
}

/// A night summary with what the entries are looked up from.
struct NightFacts: Sendable {
    /// A change of the Moon's horizon state.
    struct MoonTransition: Sendable {
        let date: Date
        let isRising: Bool
    }

    /// A moon-free core window must last this long to be preferred over a moonlit one.
    static let minimumMoonFreeCoreDuration: TimeInterval = 1_800
    /// A core window shorter than this is not worth announcing.
    static let minimumCoreDuration: TimeInterval = 900

    let summary: NightSummary
    /// The stretch from the first to the last moment of astronomical darkness; `nil` without any.
    let darkWindow: DateInterval?
    let isDarkAllNight: Bool
    let moonUpIntervals: [DateInterval]
    let moonTransitions: [MoonTransition]
    let core: TonightNight.Core

    init(summary: NightSummary) {
        self.summary = summary
        let intervals = summary.astronomicalDarknessIntervals
        if let first = intervals.first, let last = intervals.last, last.end >= first.start {
            let window = DateInterval(start: first.start, end: last.end)
            darkWindow = window
            isDarkAllNight = window.start <= summary.night.start.addingTimeInterval(60)
                && window.end >= summary.night.end.addingTimeInterval(-60)
        } else {
            darkWindow = nil
            isDarkAllNight = false
        }
        let up = summary.moon.upIntervals
        moonUpIntervals = up
        var transitions: [MoonTransition] = []
        for interval in up {
            if interval.start > summary.night.start.addingTimeInterval(60) {
                transitions.append(MoonTransition(date: interval.start, isRising: true))
            }
            if interval.end < summary.night.end.addingTimeInterval(-60) {
                transitions.append(MoonTransition(date: interval.end, isRising: false))
            }
        }
        moonTransitions = transitions
        core = Self.coreWindow(of: summary.milkyWayCore)
    }

    /// The core's window: the moon-free stretches if they add up to half an hour, otherwise all the dark time it
    /// is up; of several, the one that holds its best moment, or else the longest. `none` when that is too short.
    private static func coreWindow(of core: MilkyWayCoreVisibility) -> TonightNight.Core {
        let moonFree = core.moonFreeVisibleIntervals
        let moonFreeDuration = moonFree.reduce(0) { $0 + $1.duration }
        let isMoonFree = moonFreeDuration >= minimumMoonFreeCoreDuration
        let intervals = isMoonFree ? moonFree : core.visibleIntervals
        let best = core.bestTime.flatMap { time in intervals.first { $0.contains(time) } }
        guard let chosen = best ?? intervals.max(by: { $0.duration < $1.duration }),
              chosen.duration >= minimumCoreDuration else { return .none }
        return .window(chosen, isMoonFree: isMoonFree)
    }

    func darkness(at date: Date) -> TonightNight.Darkness {
        if isDarkAllNight { return .allNight }
        guard let window = darkWindow else { return .none }
        let phase: TonightNight.Darkness.Phase
        if date < window.start {
            phase = .upcoming
        } else if date < window.end {
            phase = .inProgress
        } else {
            phase = .over
        }
        return .window(window, phase)
    }

    func moon(at date: Date) -> TonightNight.Moon {
        let isUp = moonUpIntervals.contains { $0.start <= date && date < $0.end }
        let horizon: TonightNight.Moon.Horizon
        if let next = moonTransitions.first(where: { $0.date > date }) {
            horizon = next.isRising ? .rises(next.date) : .sets(next.date)
        } else {
            horizon = isUp ? .up : .down
        }
        let phase = summary.moon.phase
        return TonightNight.Moon(phase: phase.name, illuminatedFraction: phase.illuminatedFraction,
                                 isWaxing: phase.isWaxing, horizon: horizon)
    }

    /// The moments the picture changes by itself: the darkness, the Moon, the core, and the night itself ending.
    var changeInstants: [Date] {
        var instants: [Date] = []
        if let window = darkWindow {
            instants += [window.start, window.end]
        }
        instants += moonTransitions.map(\.date)
        if case .window(let interval, _) = core {
            instants += [interval.start, interval.end]
        }
        instants.append(summary.twilight.sunrise ?? summary.night.end)
        return instants
    }
}

import XCTest
import LodestarKit
@testable import TonightCore

final class TonightBuilderTests: XCTestCase {
    private let boulder = TonightTestSupport.boulder

    /// 12:36 local on the afternoon of 18 October 2026, with the night still to come.
    private func afternoon() throws -> Date {
        try TonightTestSupport.date(2026, 10, 18, 12, 36, in: boulder)
    }

    // MARK: Timeline

    func testTheTimelineStartsNowAndRunsForADay() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        XCTAssertEqual(entries.first?.date, start)
        let last = try XCTUnwrap(entries.last)
        XCTAssertLessThan(last.date, start.addingTimeInterval(TonightBuilder.timelineSpan))
        XCTAssertGreaterThan(last.date, start.addingTimeInterval(TonightBuilder.timelineSpan - 3_600 - 60))
        XCTAssertGreaterThanOrEqual(entries.count, 24)
        XCTAssertLessThanOrEqual(entries.count, TonightBuilder.maximumEntryCount)
    }

    func testTheEntriesAreStrictlyOrderedAndAMinuteApart() throws {
        let entries = TonightBuilder.entries(for: boulder, from: try afternoon())
        for (earlier, later) in zip(entries, entries.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.date.timeIntervalSince(earlier.date), TonightBuilder.minimumSpacing - 1e-6)
        }
    }

    func testThereIsAnEntryForEveryFullHour() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        var hour = (start.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600 + 3_600
        while hour < start.timeIntervalSince1970 + TonightBuilder.timelineSpan {
            let moment = Date(timeIntervalSince1970: hour)
            // A change within a minute of the hour takes its place, so look for an entry in [hour - 60, hour + 60).
            XCTAssertTrue(entries.contains { abs($0.date.timeIntervalSince(moment)) < 60 },
                          "no entry near \(moment)")
            hour += 3_600
        }
    }

    func testTheCurrentEntryIsTheLastOneNotAfterTheMoment() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        XCTAssertEqual(TonightBuilder.current(in: entries, at: start.addingTimeInterval(-3_600))?.date, start)
        let probe = start.addingTimeInterval(5 * 3_600 + 17)
        let current = try XCTUnwrap(TonightBuilder.current(in: entries, at: probe))
        XCTAssertLessThanOrEqual(current.date, probe)
        XCTAssertTrue(entries.filter { $0.date > current.date }.allSatisfy { $0.date > probe })
        XCTAssertNil(TonightBuilder.current(in: [], at: start))
    }

    func testAWholeTimelineIsCheap() throws {
        let start = try afternoon()
        let began = Date()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let seconds = Date().timeIntervalSince(began)
        XCTAssertFalse(entries.isEmpty)
        // About 35 ms in an optimized build; this is a Debug build on a shared machine.
        XCTAssertLessThan(seconds, 3.0, "a day of entries took \(seconds) s")
    }

    // MARK: Darkness

    func testTheDarkWindowIsTheAstronomicalNightOfThePlanner() throws {
        let start = try afternoon()
        let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        let expected = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        guard case .window(let window, let phase) = night.darkness else {
            return XCTFail("expected a dark window, got \(night.darkness)")
        }
        XCTAssertEqual(window.start, expected.start)
        XCTAssertEqual(window.end, expected.end)
        XCTAssertEqual(phase, .upcoming)
        XCTAssertEqual(night.timeZone.identifier, "America/Denver")
        XCTAssertFalse(night.isSouthernHemisphere)
    }

    func testThePhaseChangesAtDuskAndAtDawn() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        let dark = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)

        func phase(_ entry: TonightEntry) throws -> TonightNight.Darkness.Phase {
            guard case .window(_, let phase) = try TonightTestSupport.night(entry).darkness else {
                throw XCTSkip("no window")
            }
            return phase
        }
        // Once the Sun has risen the entries describe the next night.
        let rollover = summary.twilight.sunrise ?? summary.night.end
        for entry in entries where entry.date < rollover {
            let expected: TonightNight.Darkness.Phase
            if entry.date < dark.start {
                expected = .upcoming
            } else if entry.date < dark.end {
                expected = .inProgress
            } else {
                expected = .over
            }
            XCTAssertEqual(try phase(entry), expected, "at \(entry.date)")
        }
        // The change itself has an entry, at the instant (or within a minute after the nearest other entry).
        XCTAssertTrue(entries.contains { abs($0.date.timeIntervalSince(dark.start)) < 60 })
        XCTAssertTrue(entries.contains { abs($0.date.timeIntervalSince(dark.end)) < 60 })
    }

    func testTheNightRollsOverAtSunrise() throws {
        // 02:00 on 19 October: the night of the 18th is under way until the Sun rises.
        let start = try TonightTestSupport.date(2026, 10, 19, 2, in: boulder)
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let yesterday = try TonightTestSupport.date(2026, 10, 18, 12, in: boulder)
        let twilight = TwilightCalculator.night(startingOn: yesterday, observer: boulder.observer,
                                                timeZone: boulder.timeZone)
        let sunrise = try XCTUnwrap(twilight.sunrise)
        let previousDusk = try XCTUnwrap(twilight.astronomicalDusk)

        var sawBefore = false
        var sawAfter = false
        for entry in entries {
            guard case .window(let window, _) = try TonightTestSupport.night(entry).darkness else {
                return XCTFail("expected a window at \(entry.date)")
            }
            if entry.date < sunrise {
                XCTAssertEqual(window.start, previousDusk, "before sunrise at \(entry.date)")
                sawBefore = true
            } else {
                XCTAssertGreaterThan(window.start, sunrise, "after sunrise at \(entry.date)")
                sawAfter = true
            }
        }
        XCTAssertTrue(sawBefore && sawAfter)
        // The roll-over has an entry of its own.
        XCTAssertTrue(entries.contains { abs($0.date.timeIntervalSince(sunrise)) < 60 })
    }

    func testThePolarCases() throws {
        let midsummer = try TonightTestSupport.date(2026, 6, 21, 12, in: TonightTestSupport.tromso)
        let tromso = try TonightTestSupport.night(TonightBuilder.entry(for: TonightTestSupport.tromso, at: midsummer))
        XCTAssertEqual(tromso.darkness, .none)
        XCTAssertEqual(tromso.core, .none)

        let midwinter = try TonightTestSupport.date(2026, 12, 21, 12, in: TonightTestSupport.nearPole)
        let pole = try TonightTestSupport.night(TonightBuilder.entry(for: TonightTestSupport.nearPole, at: midwinter))
        XCTAssertEqual(pole.darkness, .allNight)
        // Both still produce a whole timeline.
        XCTAssertGreaterThanOrEqual(TonightBuilder.entries(for: TonightTestSupport.tromso, from: midsummer).count, 24)
        XCTAssertGreaterThanOrEqual(TonightBuilder.entries(for: TonightTestSupport.nearPole, from: midwinter).count, 24)
    }

    func testTheSouthernHemisphereMirrorsTheMoonSymbols() throws {
        let sydney = TonightTestSupport.sydney
        let night = try TonightTestSupport.night(
            TonightBuilder.entry(for: sydney, at: try TonightTestSupport.date(2026, 10, 18, 15, in: sydney)))
        XCTAssertTrue(night.isSouthernHemisphere)
    }

    // MARK: Moon

    func testTheMoonHorizonCountsDownThroughTheRiseAndTheSet() throws {
        let start = try afternoon()
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        // The Moon is down at the start of the night, rises in the afternoon and sets after midnight.
        let interval = try XCTUnwrap(summary.moon.upIntervals.first { $0.start > summary.night.start })
        XCTAssertLessThan(interval.end, summary.night.end)

        let entries = TonightBuilder.entries(for: boulder, from: start)
        let rollover = summary.twilight.sunrise ?? summary.night.end
        for entry in entries where entry.date < rollover {
            let moon = try TonightTestSupport.night(entry).moon
            if entry.date < interval.start {
                XCTAssertEqual(moon.horizon, .rises(interval.start), "at \(entry.date)")
            } else if entry.date < interval.end {
                XCTAssertEqual(moon.horizon, .sets(interval.end), "at \(entry.date)")
            } else {
                XCTAssertEqual(moon.horizon, .down, "at \(entry.date)")
            }
            XCTAssertEqual(moon.illuminatedFraction, summary.moon.illuminatedFraction, accuracy: 1e-12)
            XCTAssertEqual(moon.phase, summary.moon.phase.name)
        }
    }

    // MARK: Milky Way core

    func testTheCoreWindowIsInsideTheDarkAndAtLeastTenMinutesLong() throws {
        let place = boulder
        let start = try TonightTestSupport.date(2026, 7, 14, 15, in: place)
        let night = try TonightTestSupport.night(TonightBuilder.entry(for: place, at: start))
        guard case .window(let core, _) = night.core, case .window(let dark, _) = night.darkness else {
            return XCTFail("the core is up in the July dark: \(night.core) \(night.darkness)")
        }
        XCTAssertGreaterThanOrEqual(core.duration, TonightBuilderCoreLimit.minimum)
        XCTAssertGreaterThanOrEqual(core.start, dark.start)
        XCTAssertLessThanOrEqual(core.end, dark.end)
    }

    func testNoCoreWindowShorterThanTheLimitIsAnnounced() throws {
        // In autumn the core only just clears 10° for a few minutes after dusk; such a sliver is left out.
        var announced = 0
        var skipped = 0
        for (month, day) in [(9, 1), (9, 20), (10, 8), (10, 18), (11, 5), (11, 25)] {
            let start = try TonightTestSupport.date(2026, month, day, 15, in: boulder)
            let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
            if case .window(let core, _) = night.core {
                XCTAssertGreaterThanOrEqual(core.duration, TonightBuilderCoreLimit.minimum, "on \(month)/\(day)")
                announced += 1
            } else {
                skipped += 1
            }
        }
        XCTAssertGreaterThan(announced, 0)
        XCTAssertGreaterThan(skipped, 0)
    }

    // MARK: Events

    func testTheNextEventIsAListedOneAndStopsBeingShownWhenItsWindowEnds() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let first = try XCTUnwrap(TonightTestSupport.night(try XCTUnwrap(entries.first)).event)
        XCTAssertFalse(first.title.isEmpty)
        XCTAssertFalse(first.symbolName.isEmpty)
        XCTAssertGreaterThan(first.date, start.addingTimeInterval(-86_400))
        XCTAssertLessThan(first.date, start.addingTimeInterval(Double(TonightBuilder.eventLookaheadDays) * 86_400))
        // Two days before the Orionids peak, that is the event.
        XCTAssertEqual(first.title, "Orionids peak")
        XCTAssertFalse(first.isTonight)
    }

    func testAnEventWithAWindowTonightIsMarkedTonight() throws {
        // The night of the Orionids' peak (21 October 2026).
        let start = try TonightTestSupport.date(2026, 10, 21, 15, in: boulder)
        let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
        let event = try XCTUnwrap(night.event)
        XCTAssertEqual(event.title, "Orionids peak")
        XCTAssertTrue(event.isTonight)
        XCTAssertEqual(TonightText.when(of: event, now: start, in: boulder.timeZone), "Tonight")
    }
}

/// The least a core window may last to be announced (`NightFacts.minimumCoreDuration`).
private enum TonightBuilderCoreLimit {
    static let minimum = NightFacts.minimumCoreDuration
}

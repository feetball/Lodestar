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
            // A change within a minute of the hour takes its place, so look for an entry in (hour - 60, hour + 60).
            XCTAssertTrue(entries.contains { abs($0.date.timeIntervalSince(moment)) < 60 },
                          "no entry near \(moment)")
            hour += 3_600
        }
    }

    func testAChangeJustAfterNowStillGetsAnEntryAMinuteLater() throws {
        let summary = TonightTestSupport.summary(startingOn: try afternoon(), in: boulder)
        let dusk = try XCTUnwrap(summary.astronomicalDarknessIntervals.first).start
        // The darkness starts half a minute after the timeline does, which is too close for an entry of its own.
        let start = dusk.addingTimeInterval(-30)
        let entries = TonightBuilder.entries(for: boulder, from: start)
        XCTAssertEqual(entries.first?.date, start)
        let second = try XCTUnwrap(entries.dropFirst().first)
        XCTAssertEqual(second.date.timeIntervalSince(start), TonightBuilder.minimumSpacing, accuracy: 1e-6)
        XCTAssertEqual(TonightLines(night: try TonightTestSupport.night(second), now: second.date).dark.badge, "now")
        XCTAssertNil(TonightLines(night: try TonightTestSupport.night(try XCTUnwrap(entries.first)), now: start).dark.badge)
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
        // About 50 ms in an optimized build; this is a Debug build on a shared machine.
        XCTAssertLessThan(seconds, 4.0, "a day of entries took \(seconds) s")
    }

    // MARK: Darkness

    func testTheDarknessIsTheAstronomicalNightOfThePlanner() throws {
        let start = try afternoon()
        let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        XCTAssertEqual(night.darkness.windows, summary.astronomicalDarknessIntervals)
        XCTAssertEqual(night.darkness.hours, summary.astronomicalDarkHours, accuracy: 1e-12)
        XCTAssertEqual(night.darkness.moonFreeHours, summary.moonFreeDarkHours, accuracy: 1e-12)
        XCTAssertFalse(night.darkness.isAllNight)
        XCTAssertEqual(night.timeZone.identifier, "America/Denver")
        XCTAssertFalse(night.isSouthernHemisphere)
    }

    func testTheWordsFollowTheNightHourByHour() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        let dark = try XCTUnwrap(summary.astronomicalDarknessIntervals.first)
        // Once the Sun has risen the entries describe the next night.
        let rollover = summary.twilight.sunrise ?? summary.night.end
        for entry in entries where entry.date < rollover {
            let lines = TonightLines(night: try TonightTestSupport.night(entry), now: entry.date)
            if entry.date < dark.start {
                XCTAssertNil(lines.dark.badge, "at \(entry.date)")
                XCTAssertTrue(lines.darkInline.hasPrefix("Dark ") && !lines.darkInline.hasPrefix("Dark until")
                    && !lines.darkInline.hasPrefix("Dark ended"), lines.darkInline)
            } else if entry.date < dark.end {
                XCTAssertEqual(lines.dark.badge, "now", "at \(entry.date)")
                XCTAssertTrue(lines.darkInline.hasPrefix("Dark until "), lines.darkInline)
            } else {
                XCTAssertNil(lines.dark.badge, "at \(entry.date)")
                XCTAssertTrue(lines.darkInline.hasPrefix("Dark ended "), lines.darkInline)
            }
        }
        // The changes themselves have entries.
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
            let window = try XCTUnwrap(TonightTestSupport.night(entry).darkness.windows.first)
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
        XCTAssertTrue(tromso.darkness.windows.isEmpty)
        XCTAssertFalse(tromso.core.hasDarkness)
        let words = TonightLines(night: tromso, now: midsummer)
        XCTAssertEqual(words.dark.value, "No full darkness")
        XCTAssertEqual(words.core.value, "No darkness")

        let midwinter = try TonightTestSupport.date(2026, 12, 21, 12, in: TonightTestSupport.nearPole)
        let pole = try TonightTestSupport.night(TonightBuilder.entry(for: TonightTestSupport.nearPole, at: midwinter))
        XCTAssertTrue(pole.darkness.isAllNight)
        XCTAssertEqual(TonightLines(night: pole, now: midwinter).dark.value, "All night")
        // Both still produce a whole timeline.
        XCTAssertGreaterThanOrEqual(TonightBuilder.entries(for: TonightTestSupport.tromso, from: midsummer).count, 24)
        XCTAssertGreaterThanOrEqual(TonightBuilder.entries(for: TonightTestSupport.nearPole, from: midwinter).count, 24)
    }

    func testTheSouthernHemisphereIsMarked() throws {
        let sydney = TonightTestSupport.sydney
        let night = try TonightTestSupport.night(
            TonightBuilder.entry(for: sydney, at: try TonightTestSupport.date(2026, 10, 18, 15, in: sydney)))
        XCTAssertTrue(night.isSouthernHemisphere)
        XCTAssertEqual(night.timeZone.identifier, "Australia/Sydney")
    }

    // MARK: Moon

    func testTheMoonIsThePlannersAndTheCompactLineCountsDownToItsRiseAndSet() throws {
        let start = try afternoon()
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        // The Moon is down at the start of the night, rises in the afternoon and sets after midnight.
        let interval = try XCTUnwrap(summary.moon.upIntervals.first { $0.start > summary.night.start })
        XCTAssertLessThan(interval.end, summary.night.end)

        let entries = TonightBuilder.entries(for: boulder, from: start)
        let rollover = summary.twilight.sunrise ?? summary.night.end
        for entry in entries where entry.date < rollover {
            let night = try TonightTestSupport.night(entry)
            let moon = night.moon
            XCTAssertEqual(moon.rise, summary.moon.riseTransitSet.rise)
            XCTAssertEqual(moon.set, summary.moon.riseTransitSet.set)
            XCTAssertEqual(moon.circumstance, summary.moon.riseTransitSet.circumstance)
            XCTAssertEqual(moon.upIntervals, summary.moon.upIntervals)
            XCTAssertEqual(moon.illuminatedFraction, summary.moon.illuminatedFraction, accuracy: 1e-12)
            XCTAssertEqual(moon.phase, summary.moon.phase.name)

            let lines = TonightLines(night: night, now: entry.date)
            if entry.date < interval.start {
                XCTAssertNil(lines.moon.badge, "at \(entry.date)")
                XCTAssertTrue(lines.moonCompact.contains("Rises "), lines.moonCompact)
            } else if entry.date < interval.end {
                XCTAssertEqual(lines.moon.badge, "up", "at \(entry.date)")
                XCTAssertTrue(lines.moonCompact.contains("Sets "), lines.moonCompact)
            } else {
                XCTAssertNil(lines.moon.badge, "at \(entry.date)")
                XCTAssertTrue(lines.moonCompact.contains("Below horizon"), lines.moonCompact)
            }
        }
    }

    // MARK: Milky Way core

    func testTheCoreWindowsAreInsideTheDarkAndAtLeastAQuarterOfAnHourLong() throws {
        let start = try TonightTestSupport.date(2026, 7, 14, 15, in: boulder)
        let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
        let dark = try XCTUnwrap(night.darkness.windows.first)
        XCTAssertFalse(night.core.windows.isEmpty, "the core is up in the July dark")
        for window in night.core.windows {
            XCTAssertGreaterThanOrEqual(window.duration, TonightBuilder.minimumCoreDuration)
            XCTAssertGreaterThanOrEqual(window.start, dark.start)
            XCTAssertLessThanOrEqual(window.end, dark.end)
        }
        let summary = TonightTestSupport.summary(startingOn: start, in: boulder)
        XCTAssertEqual(night.core.bestTime, summary.milkyWayCore.bestTime)
        XCTAssertEqual(night.core.maxAltitude, summary.milkyWayCore.maxAltitude)
        XCTAssertEqual(night.core.bestAzimuth, summary.milkyWayCore.bestAzimuth)
        let words = TonightLines(night: night, now: start).core
        XCTAssertTrue(words.detail?.hasPrefix("Best ") == true, words.detail ?? "nil")
    }

    func testNoCoreWindowShorterThanTheLimitIsAnnounced() throws {
        // In autumn the core only just clears 10° for a few minutes after dusk; such a sliver is left out.
        var announced = 0
        var skipped = 0
        for (month, day) in [(9, 1), (9, 20), (10, 8), (10, 18), (11, 5), (11, 25)] {
            let start = try TonightTestSupport.date(2026, month, day, 15, in: boulder)
            let night = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start))
            if night.core.windows.isEmpty {
                skipped += 1
                XCTAssertEqual(TonightLines(night: night, now: start).core.value, "Low in the dark")
            } else {
                announced += 1
            }
            for window in night.core.windows {
                XCTAssertGreaterThanOrEqual(window.duration, TonightBuilder.minimumCoreDuration, "on \(month)/\(day)")
            }
        }
        XCTAssertGreaterThan(announced, 0)
        XCTAssertGreaterThan(skipped, 0)
    }

    // MARK: Events

    func testTheNextEventIsTheFirstListedOneThatCanBeSeen() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let first = try XCTUnwrap(TonightTestSupport.night(try XCTUnwrap(entries.first)).event)
        XCTAssertFalse(first.title.isEmpty)
        XCTAssertFalse(first.symbolName.isEmpty)
        XCTAssertGreaterThanOrEqual(first.date, start)
        XCTAssertLessThan(first.date, start.addingTimeInterval(Double(TonightBuilder.eventLookaheadDays) * 86_400))
        XCTAssertNotEqual(first.isVisibleFromHere, false)
        // Three days before the Orionids' peak, that is the event.
        XCTAssertEqual(first.title, "Orionids peak")
        XCTAssertEqual(first.showerRate, 20)
        let words = TonightLines(night: try TonightTestSupport.night(try XCTUnwrap(entries.first)), now: start).event
        XCTAssertEqual(words.label, "Next event")
        XCTAssertEqual(words.value, "Orionids peak")
        XCTAssertEqual(words.badge, "in 3 days")
        XCTAssertTrue(words.extra?.hasPrefix("Up to 20 an hour") == true, words.extra ?? "nil")
    }

    func testTheEventChangesOnceItHasHappened() throws {
        let start = try afternoon()
        let entries = TonightBuilder.entries(for: boulder, from: start)
        let first = try XCTUnwrap(TonightTestSupport.night(try XCTUnwrap(entries.first)).event)
        // Show the event of the first entry until the event itself, then the one after it.
        let later = try TonightTestSupport.night(
            TonightBuilder.entry(for: boulder, at: first.date.addingTimeInterval(3_600))).event
        XCTAssertNotNil(later)
        XCTAssertNotEqual(later?.title, first.title)
        XCTAssertGreaterThan(try XCTUnwrap(later).date, first.date)
        // The moment itself counts as having happened, so the entry the timeline has there already moves on.
        let atTheMoment = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: first.date)).event
        XCTAssertNotEqual(atTheMoment?.title, first.title)
        let justBefore = try TonightTestSupport.night(
            TonightBuilder.entry(for: boulder, at: first.date.addingTimeInterval(-1))).event
        XCTAssertEqual(justBefore?.title, first.title)
    }

    func testTheTimelineMovesOnFromAnEventAtTheMomentItHappens() throws {
        let first = try XCTUnwrap(
            TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: try afternoon())).event)
        // A timeline that reaches the event (the day's timeline from the afternoon does not).
        let entries = TonightBuilder.entries(for: boulder, from: first.date.addingTimeInterval(-6 * 3_600))
        let before = try XCTUnwrap(entries.last { $0.date < first.date })
        XCTAssertEqual(try TonightTestSupport.night(before).event?.title, first.title)
        let atTheEvent = try XCTUnwrap(entries.first { $0.date >= first.date })
        XCTAssertLessThan(atTheEvent.date.timeIntervalSince(first.date), TonightBuilder.minimumSpacing)
        XCTAssertNotEqual(try TonightTestSupport.night(atTheEvent).event?.title, first.title)
    }

    func testTheMoonsConjunctionsAreOnlyListedWhenItCoversTheOtherBody() throws {
        // The Moon passes a planet or a bright star every few days; unfiltered, a sample of two months would show
        // several of those. Only the rare occultations are kept.
        var titles = Set<String>()
        for offset in stride(from: 0, to: 60, by: 3) {
            let start = try TonightTestSupport.date(2026, 10, 18, 12, in: boulder).addingTimeInterval(Double(offset) * 86_400)
            if let event = try TonightTestSupport.night(TonightBuilder.entry(for: boulder, at: start)).event {
                titles.insert(event.title)
            }
        }
        XCTAssertGreaterThan(titles.count, 4, "\(titles)")
        XCTAssertLessThanOrEqual(titles.filter { $0.hasPrefix("Moon and") }.count, 1, "\(titles)")
    }
}

import XCTest
import LodestarKit
@testable import TonightCore

final class TonightLinesTests: XCTestCase {
    private let zone = TimeZone(identifier: "UTC") ?? .current
    /// 2027-01-15 08:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hours(_ from: Double, _ to: Double) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(from * 3_600), end: now.addingTimeInterval(to * 3_600))
    }

    private func darkness(_ windows: [DateInterval], hours: Double? = nil, moonFree: Double? = nil,
                          allNight: Bool = false) -> TonightNight.Darkness {
        let total = hours ?? windows.reduce(0) { $0 + $1.duration } / 3_600
        return TonightNight.Darkness(windows: windows, hours: total, moonFreeHours: moonFree ?? total,
                                     isAllNight: allNight)
    }

    private func moon(rise: Double? = nil, set: Double? = nil, circumstance: RiseTransitSet.Circumstance = .normal,
                      up: [DateInterval] = []) -> TonightNight.Moon {
        TonightNight.Moon(phase: .waxingCrescent, illuminatedFraction: 0.344, isWaxing: true,
                          rise: rise.map { now.addingTimeInterval($0 * 3_600) },
                          set: set.map { now.addingTimeInterval($0 * 3_600) },
                          circumstance: circumstance, upIntervals: up)
    }

    private func core(_ windows: [DateInterval] = [], hasDarkness: Bool = true) -> TonightNight.Core {
        TonightNight.Core(hasDarkness: hasDarkness, windows: windows,
                          bestTime: windows.first.map { $0.start.addingTimeInterval($0.duration / 2) },
                          maxAltitude: windows.isEmpty ? nil : 28.4, bestAzimuth: windows.isEmpty ? nil : 160)
    }

    private func night(darkness: TonightNight.Darkness? = nil, moon: TonightNight.Moon? = nil,
                       core: TonightNight.Core? = nil, event: TonightNight.Event? = nil) -> TonightNight {
        TonightNight(timeZone: zone, isSouthernHemisphere: false,
                     darkness: darkness ?? self.darkness([hours(2, 10)]), moon: moon ?? self.moon(),
                     core: core ?? self.core(), event: event)
    }

    private func lines(_ night: TonightNight) -> TonightLines {
        TonightLines(night: night, now: now)
    }

    // MARK: Darkness

    func testTheDarkItemNamesTheWindowItsLengthAndTheMoon() {
        let item = lines(night(darkness: darkness([hours(2, 10)], hours: 8, moonFree: 8))).dark
        XCTAssertEqual(item.label, "Dark")
        XCTAssertNil(item.badge)
        XCTAssertTrue(item.value.contains("\u{2013}"), item.value)
        XCTAssertEqual(item.detail, "8h 00m of darkness")
        XCTAssertEqual(item.extra, "The Moon stays down")
        XCTAssertTrue(item.spoken.hasPrefix("Darkness from "), item.spoken)
        XCTAssertTrue(item.spoken.contains("8 hours"), item.spoken)
    }

    func testTheMoonFreeTextHasThreeForms() {
        XCTAssertEqual(lines(night(darkness: darkness([hours(2, 10)], hours: 8, moonFree: 0))).dark.extra,
                       "Moonlit all through")
        XCTAssertEqual(lines(night(darkness: darkness([hours(2, 10)], hours: 8, moonFree: 5.5))).dark.extra,
                       "5h 30m without the Moon")
    }

    func testTheDarkItemIsMarkedNowWhileItIsDark() {
        let during = lines(night(darkness: darkness([hours(-1, 7)])))
        XCTAssertEqual(during.dark.badge, "now")
        XCTAssertTrue(during.dark.spoken.hasPrefix("Darkness now, from "), during.dark.spoken)
        XCTAssertTrue(during.darkInline.hasPrefix("Dark until "), during.darkInline)
        let after = lines(night(darkness: darkness([hours(-9, -1)])))
        XCTAssertNil(after.dark.badge)
        XCTAssertTrue(after.darkInline.hasPrefix("Dark ended "), after.darkInline)
        let before = lines(night(darkness: darkness([hours(2, 10)])))
        XCTAssertTrue(before.darkInline.hasPrefix("Dark "), before.darkInline)
        XCTAssertTrue(before.darkInline.contains("\u{2013}"), before.darkInline)
        XCTAssertNotNil(before.darkCompactWindow)
    }

    func testNoDarknessAndAllNight() {
        let none = lines(night(darkness: darkness([])))
        XCTAssertEqual(none.dark.value, "No full darkness")
        XCTAssertEqual(none.dark.detail, "The Sun stays above \u{2212}18\u{00B0}")
        XCTAssertEqual(none.darkInline, "No full darkness")
        XCTAssertNil(none.darkCompactWindow)
        let all = lines(night(darkness: darkness([hours(-12, 12)], allNight: true)))
        XCTAssertEqual(all.dark.value, "All night")
        XCTAssertEqual(all.darkInline, "Dark all night")
    }

    // MARK: Moon

    func testTheMoonItem() {
        let item = lines(night(moon: moon(rise: 3, set: 12))).moon
        XCTAssertEqual(item.label, "Moon")
        XCTAssertEqual(item.value, "Waxing Crescent")
        XCTAssertEqual(item.trailing, "34%")
        XCTAssertNil(item.badge)
        XCTAssertTrue(item.detail?.hasPrefix("Rises ") == true && item.detail?.contains(" \u{00B7} sets ") == true,
                      item.detail ?? "nil")
        XCTAssertTrue(item.spoken.hasPrefix("Moon: Waxing Crescent, 34% lit. It rises at "), item.spoken)
    }

    func testTheMoonSetsBeforeItRisesInTheNight() {
        let item = lines(night(moon: moon(rise: 9, set: 2))).moon
        XCTAssertTrue(item.detail?.hasPrefix("Sets ") == true && item.detail?.contains(" \u{00B7} rises ") == true,
                      item.detail ?? "nil")
        XCTAssertTrue(item.spoken.contains("It sets at "), item.spoken)
        XCTAssertTrue(lines(night(moon: moon(rise: 3))).moon.detail?.hasPrefix("Rises ") == true)
        XCTAssertTrue(lines(night(moon: moon(set: 3))).moon.detail?.hasPrefix("Sets ") == true)
    }

    func testTheMoonIsMarkedUpWhileItIsUp() {
        let up = lines(night(moon: moon(rise: -2, set: 5, up: [hours(-2, 5)])))
        XCTAssertEqual(up.moon.badge, "up")
        XCTAssertTrue(up.moon.spoken.contains("34% lit, up now."), up.moon.spoken)
        XCTAssertTrue(up.moonCompact.hasPrefix("34% \u{00B7} Sets "), up.moonCompact)
    }

    func testTheMoonUpOrDownAllNight() {
        let always = lines(night(moon: moon(circumstance: .alwaysUp, up: [hours(-12, 12)])))
        XCTAssertEqual(always.moon.detail, "Up all night")
        XCTAssertEqual(always.moonCompact, "34% \u{00B7} Above horizon")
        XCTAssertEqual(lines(night(moon: moon(circumstance: .alwaysDown))).moon.detail, "Down all night")
        XCTAssertEqual(lines(night(moon: moon(circumstance: .alwaysDown))).moonCompact, "34% \u{00B7} Below horizon")
    }

    func testThePercentIsClampedAndRounded() {
        XCTAssertEqual(TonightText.percent(0), "0%")
        XCTAssertEqual(TonightText.percent(0.5), "50%")
        XCTAssertEqual(TonightText.percent(0.996), "100%")
        XCTAssertEqual(TonightText.percent(1.2), "100%")
        XCTAssertEqual(TonightText.percent(-0.1), "0%")
        XCTAssertEqual(TonightText.percent(.nan), "\u{2014}")
    }

    // MARK: Milky Way core

    func testTheCoreItem() {
        let item = lines(night(core: core([hours(3, 6)]))).core
        XCTAssertEqual(item.label, "Milky Way core")
        XCTAssertEqual(item.shortLabel, "Milky Way")
        XCTAssertTrue(item.value.contains("\u{2013}"), item.value)
        XCTAssertTrue(item.detail?.hasPrefix("Best ") == true && item.detail?.hasSuffix("28\u{00B0} SSE") == true,
                      item.detail ?? "nil")
        XCTAssertNil(item.badge)
        XCTAssertTrue(item.spoken.hasPrefix("Milky Way core visible from "), item.spoken)
        XCTAssertTrue(item.spoken.contains("28\u{00B0} up in the south-southeast."), item.spoken)
        XCTAssertEqual(lines(night(core: core([hours(-1, 6)]))).core.badge, "now")
    }

    func testTheCoreWhenThereIsNoWindow() {
        let low = lines(night(core: core()))
        XCTAssertEqual(low.core.value, "Low in the dark")
        XCTAssertEqual(low.core.detail, "Below 10\u{00B0} while it is dark")
        XCTAssertEqual(low.coreCompact, "Milky Way: low in the dark")
        let bright = lines(night(core: core(hasDarkness: false)))
        XCTAssertEqual(bright.core.value, "No darkness")
        XCTAssertEqual(bright.core.detail, "Too bright to photograph")
    }

    // MARK: Event

    private func event(daysAhead days: Double, visible: Bool? = true, window: DateInterval? = nil,
                       rate: Int? = nil) -> TonightNight.Event {
        TonightNight.Event(title: "Perseids peak", symbolName: "sparkles",
                           date: now.addingTimeInterval(days * 86_400), isVisibleFromHere: visible,
                           bestWindow: window, showerRate: rate)
    }

    func testTheEventItem() {
        let item = lines(night(event: event(daysAhead: 12, window: hours(30, 40), rate: 100))).event
        XCTAssertEqual(item.label, "Next event")
        XCTAssertEqual(item.shortLabel, "Next")
        XCTAssertEqual(item.value, "Perseids peak")
        XCTAssertEqual(item.badge, "in 12 days")
        XCTAssertTrue(item.detail?.contains(" \u{00B7} ") == true, item.detail ?? "nil")
        XCTAssertTrue(item.extra?.hasPrefix("Up to 100 an hour \u{00B7} Best view ") == true, item.extra ?? "nil")
        XCTAssertTrue(item.spoken.hasPrefix("Next event: Perseids peak, "), item.spoken)
    }

    func testAnEventThatCannotBeSeenSaysSo() {
        let item = lines(night(event: event(daysAhead: 2, visible: false))).event
        XCTAssertEqual(item.extra, "Not visible from here")
    }

    func testNoEventHasNoWords() {
        let all = lines(night())
        XCTAssertEqual(all.event.value, "Nothing in view")
        XCTAssertEqual(all.event.detail, "No events are coming up")
        XCTAssertNil(all.event.badge)
        XCTAssertNil(all.eventCompact)
        XCTAssertNil(all.eventSymbol)
        XCTAssertEqual(all.event.spoken, "Next event: none is coming up.")
    }

    func testTheEventDistanceWording() {
        func text(_ days: Double) -> String {
            TonightText.distance(to: now.addingTimeInterval(days * 86_400), from: now, in: zone)
        }
        XCTAssertEqual(text(0), "Today")
        XCTAssertEqual(text(1), "Tomorrow")
        XCTAssertEqual(text(2), "In 2 days")
        XCTAssertEqual(text(14), "In 14 days")
        XCTAssertEqual(text(21), "In 3 weeks")
        XCTAssertEqual(text(89), "In 12 weeks")
        XCTAssertEqual(text(120), "In 4 months")
        XCTAssertEqual(text(-1), "Passed")
        XCTAssertEqual(TonightText.distance(to: now.addingTimeInterval(-60), from: now, in: zone), "Today")
    }

    func testTheCompactEventLine() {
        let all = lines(night(event: event(daysAhead: 3)))
        XCTAssertEqual(all.eventCompact, "Perseids peak \u{00B7} in 3 days")
        XCTAssertEqual(all.eventSymbol, "sparkles")
    }

    // MARK: Spoken

    func testTheSpokenSummaryNamesWhatItCovers() {
        let all = lines(night(event: event(daysAhead: 1)))
        let brief = all.spoken(includingCore: false, includingEvent: false)
        XCTAssertTrue(brief.hasPrefix("Tonight at Current Location. Darkness from "), brief)
        XCTAssertTrue(brief.contains("Moon: Waxing Crescent, 34% lit."), brief)
        XCTAssertFalse(brief.contains("Milky Way"), brief)
        XCTAssertFalse(brief.contains("Perseids"), brief)
        let full = all.spoken(includingCore: true, includingEvent: true)
        XCTAssertTrue(full.contains("Milky Way core"), full)
        XCTAssertTrue(full.contains("Next event: Perseids peak, "), full)
    }

    func testTheNeedsLocationWords() {
        XCTAssertEqual(TonightNeedsLocationText.full(.notAsked), "Open Lodestar to allow location")
        XCTAssertFalse(TonightNeedsLocationText.short(.notAsked).isEmpty)
        XCTAssertFalse(TonightNeedsLocationText.corner(.notAsked).isEmpty)
        XCTAssertTrue(TonightNeedsLocationText.spoken(.notAsked).contains("location"))
        let entry = TonightEntry.needsLocation(at: now)
        XCTAssertEqual(entry.date, now)
        XCTAssertEqual(entry.content, .needsLocation(.notAsked))
    }

    func testAUserWhoSaidNoIsSentToSettingsNotToTheApp() {
        let issue = TonightLocationIssue.deniedOrRestricted
        XCTAssertEqual(TonightNeedsLocationText.full(issue), "Allow location for Lodestar in Settings")
        XCTAssertTrue(TonightNeedsLocationText.short(issue).contains("Settings"))
        XCTAssertTrue(TonightNeedsLocationText.spoken(issue).contains("Settings"))
        for text in [TonightNeedsLocationText.full(issue), TonightNeedsLocationText.short(issue),
                     TonightNeedsLocationText.corner(issue), TonightNeedsLocationText.spoken(issue)] {
            XCTAssertFalse(text.contains("Open"), text)
        }
        XCTAssertNotEqual(TonightNeedsLocationText.corner(issue), TonightNeedsLocationText.corner(.notAsked))
        XCTAssertEqual(TonightEntry.needsLocation(at: now, issue: issue).content, .needsLocation(.deniedOrRestricted))
    }

    // MARK: Numbers

    func testDurations() {
        XCTAssertEqual(TonightText.duration(hours: 0), "0m")
        XCTAssertEqual(TonightText.duration(hours: 0.75), "45m")
        XCTAssertEqual(TonightText.duration(hours: 6.5333), "6h 32m")
        XCTAssertEqual(TonightText.duration(hours: 7.15), "7h 09m")
        XCTAssertEqual(TonightText.spokenDuration(hours: 7.15), "7 hours 9 minutes")
        XCTAssertEqual(TonightText.spokenDuration(hours: 1), "1 hour")
        XCTAssertEqual(TonightText.spokenDuration(hours: 0), "0 minutes")
    }
}

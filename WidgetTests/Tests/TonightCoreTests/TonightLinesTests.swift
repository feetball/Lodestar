import XCTest
import LodestarKit
@testable import TonightCore

final class TonightLinesTests: XCTestCase {
    private let zone = TimeZone(identifier: "UTC") ?? .current
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func night(darkness: TonightNight.Darkness = .none, horizon: TonightNight.Moon.Horizon = .down,
                       core: TonightNight.Core = .none, event: TonightNight.Event? = nil) -> TonightNight {
        TonightNight(timeZone: zone, isSouthernHemisphere: false, darkness: darkness,
                     moon: TonightNight.Moon(phase: .waxingCrescent, illuminatedFraction: 0.344, isWaxing: true,
                                             horizon: horizon),
                     core: core, event: event)
    }

    private var window: DateInterval {
        DateInterval(start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(9 * 3_600))
    }

    func testTheDarknessTitleFollowsThePhase() {
        XCTAssertEqual(TonightLines(night: night(darkness: .window(window, .upcoming)), now: now).darkTitle, "Dark tonight")
        XCTAssertEqual(TonightLines(night: night(darkness: .window(window, .inProgress)), now: now).darkTitle, "Dark now")
        XCTAssertEqual(TonightLines(night: night(darkness: .window(window, .over)), now: now).darkTitle, "Dark ended")
        XCTAssertEqual(TonightLines(night: night(darkness: .allNight), now: now).darkTitle, "Dark all night")
        let none = TonightLines(night: night(darkness: .none), now: now)
        XCTAssertEqual(none.darkTitle, "No full darkness")
        XCTAssertNil(none.darkWindow)
        XCTAssertNil(none.darkCompactWindow)
    }

    func testTheWindowIsShownWithBothTimes() throws {
        let lines = TonightLines(night: night(darkness: .window(window, .upcoming)), now: now)
        let text = try XCTUnwrap(lines.darkWindow)
        XCTAssertTrue(text.contains("\u{2013}"), text)
        XCTAssertTrue(text.contains(":"), text)
        XCTAssertTrue(lines.darkInline.hasPrefix("Dark "), lines.darkInline)
        XCTAssertTrue(lines.darkInline.contains("\u{2013}"), lines.darkInline)
        XCTAssertTrue(try XCTUnwrap(lines.darkCompactWindow).contains("\u{2013}"))
    }

    func testTheInlineLineNamesTheEndWhileDarkAndAfterwards() {
        let during = TonightLines(night: night(darkness: .window(window, .inProgress)), now: now)
        XCTAssertTrue(during.darkInline.hasPrefix("Dark until "), during.darkInline)
        let after = TonightLines(night: night(darkness: .window(window, .over)), now: now)
        XCTAssertTrue(after.darkInline.hasPrefix("Dark ended "), after.darkInline)
    }

    func testTheMoonLine() {
        let sets = TonightLines(night: night(horizon: .sets(now)), now: now)
        XCTAssertEqual(sets.moonName, "Waxing Crescent")
        XCTAssertEqual(sets.moonPercent, "34%")
        XCTAssertTrue(sets.moonHorizon.hasPrefix("Sets "), sets.moonHorizon)
        XCTAssertEqual(sets.moonSymbol, "moonphase.waxing.crescent")
        XCTAssertTrue(TonightLines(night: night(horizon: .rises(now)), now: now).moonHorizon.hasPrefix("Rises "))
        XCTAssertEqual(TonightLines(night: night(horizon: .up), now: now).moonHorizon, "Above horizon")
        XCTAssertEqual(TonightLines(night: night(horizon: .down), now: now).moonHorizon, "Below horizon")
    }

    func testThePercentIsClampedAndRounded() {
        XCTAssertEqual(TonightText.percent(0), "0%")
        XCTAssertEqual(TonightText.percent(0.5), "50%")
        XCTAssertEqual(TonightText.percent(0.996), "100%")
        XCTAssertEqual(TonightText.percent(1.2), "100%")
        XCTAssertEqual(TonightText.percent(-0.1), "0%")
        XCTAssertEqual(TonightText.percent(.nan), "\u{2014}")
    }

    func testTheCoreLine() {
        let up = TonightLines(night: night(core: .window(window, isMoonFree: true)), now: now)
        XCTAssertNotNil(up.coreWindow)
        XCTAssertEqual(up.coreNote, "Moon-free")
        let moonlit = TonightLines(night: night(core: .window(window, isMoonFree: false)), now: now)
        XCTAssertEqual(moonlit.coreNote, "Moon up")
        let none = TonightLines(night: night(core: .none), now: now)
        XCTAssertNil(none.coreWindow)
        XCTAssertEqual(none.coreNote, "Not up in the dark")
    }

    func testTheEventWording() {
        let tonight = TonightNight.Event(title: "Perseids peak", symbolName: "sparkles", date: now, isTonight: true)
        XCTAssertEqual(TonightText.when(of: tonight, now: now, in: zone), "Tonight")

        func event(daysAhead days: Double) -> TonightNight.Event {
            TonightNight.Event(title: "Event", symbolName: "sparkles", date: now.addingTimeInterval(days * 86_400),
                               isTonight: false)
        }
        XCTAssertEqual(TonightText.when(of: event(daysAhead: 0), now: now, in: zone), "Today")
        XCTAssertEqual(TonightText.when(of: event(daysAhead: 1), now: now, in: zone), "Tomorrow")
        XCTAssertEqual(TonightText.when(of: event(daysAhead: 12), now: now, in: zone), "In 12 days")
        XCTAssertEqual(TonightText.when(of: event(daysAhead: 30), now: now, in: zone), "In 30 days")
        let far = TonightText.when(of: event(daysAhead: 45), now: now, in: zone)
        XCTAssertFalse(far.hasPrefix("In "), far)
        XCTAssertEqual(TonightText.when(of: event(daysAhead: -1), now: now, in: zone), "Today")
    }

    func testTheSpokenSummaryNamesWhatItCovers() {
        let event = TonightNight.Event(title: "Perseids peak", symbolName: "sparkles", date: now, isTonight: true)
        let lines = TonightLines(night: night(darkness: .window(window, .upcoming), horizon: .sets(now),
                                              core: .window(window, isMoonFree: true), event: event), now: now)
        let brief = lines.spoken(includingCore: false, includingEvent: false)
        XCTAssertTrue(brief.hasPrefix("Tonight. Dark from "), brief)
        XCTAssertTrue(brief.contains("Moon, waxing crescent, 34 percent lit, sets at "), brief)
        XCTAssertFalse(brief.contains("Milky Way"), brief)
        XCTAssertFalse(brief.contains("Perseids"), brief)
        let full = lines.spoken(includingCore: true, includingEvent: true)
        XCTAssertTrue(full.contains("Milky Way core up from "), full)
        XCTAssertTrue(full.hasSuffix("Next event: Perseids peak, tonight."), full)
    }

    func testNoEventHasNoWords() {
        let lines = TonightLines(night: night(), now: now)
        XCTAssertNil(lines.eventTitle)
        XCTAssertNil(lines.eventSymbol)
        XCTAssertNil(lines.eventWhen)
        XCTAssertNil(lines.spokenEvent)
    }

    func testTheNeedsLocationWords() {
        XCTAssertEqual(TonightNeedsLocationText.full, "Open Lodestar to set your location")
        XCTAssertFalse(TonightNeedsLocationText.short.isEmpty)
        XCTAssertTrue(TonightNeedsLocationText.spoken.contains("location"))
        let entry = TonightEntry.needsLocation(at: now)
        XCTAssertEqual(entry.date, now)
        XCTAssertEqual(entry.content, .needsLocation)
    }
}

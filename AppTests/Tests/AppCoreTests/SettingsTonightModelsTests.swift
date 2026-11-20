import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The value types of `TonightModels.swift`: the night choice, the key a night is computed for, and the report.
final class SettingsTonightModelsTests: XCTestCase {
    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
    private let denver = TimeZone(identifier: "America/Denver")!
    /// 2026-08-12 18:00 UTC, which is the 12th in Denver.
    private let august = Date(timeIntervalSince1970: 1_786_557_600)

    private func makeContext(name: String = "Home", source: LocationSource = .device) -> ObserverContext {
        ObserverContext(observer: boulder, timeZone: denver, name: name, source: source,
                        horizontalAccuracy: nil, timestamp: nil, horizon: nil)
    }

    // MARK: The choice of night

    func testTonightEqualsTonightOnly() {
        XCTAssertEqual(TonightNightChoice.tonight, TonightNightChoice.tonight)
        XCTAssertNotEqual(TonightNightChoice.tonight, TonightNightChoice.date(august))
    }

    func testADateChoiceComparesByInstant() {
        XCTAssertEqual(TonightNightChoice.date(august), TonightNightChoice.date(august))
        XCTAssertNotEqual(TonightNightChoice.date(august), TonightNightChoice.date(august.addingTimeInterval(86_400)))
    }

    // MARK: The key of a night

    func testTheSameContextAndChoiceMakeEqualKeys() {
        let a = TonightNightKey(context: makeContext(), choice: .tonight)
        let b = TonightNightKey(context: makeContext(), choice: .tonight)
        XCTAssertEqual(a, b)
    }

    func testAnotherChoiceMakesAnotherKey() {
        let tonight = TonightNightKey(context: makeContext(), choice: .tonight)
        let dated = TonightNightKey(context: makeContext(), choice: .date(august))
        XCTAssertNotEqual(tonight, dated)
        XCTAssertEqual(dated, TonightNightKey(context: makeContext(), choice: .date(august)))
    }

    func testAnotherContextMakesAnotherKey() {
        let home = TonightNightKey(context: makeContext(), choice: .tonight)
        XCTAssertNotEqual(home, TonightNightKey(context: makeContext(name: "Cabin"), choice: .tonight))
        XCTAssertNotEqual(home, TonightNightKey(context: makeContext(source: .site(UUID())), choice: .tonight))
    }

    // MARK: The report

    func testTheReportsNightStartsAtLocalNoonOfTheNightsDate() {
        let context = makeContext()
        let summary = NightPlanner.summary(nightStartingOn: august, observer: boulder, timeZone: denver)
        let report = TonightReport(summary: summary, timeZone: denver,
                                   timeline: TonightTimelineModel(summary: summary, timeZone: denver),
                                   targets: .noDarkness, tonightStart: summary.night.start, nightsFromTonight: 0,
                                   tonightExpiry: summary.night.end, appliesSkyline: false)
        XCTAssertEqual(report.nightStart, summary.night.start)
        let components = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: report.nightStart)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(report.nightStart.addingTimeInterval(86_400), summary.night.end)
    }

    func testTheReportKeepsWhatItWasGiven() {
        let summary = NightPlanner.summary(nightStartingOn: august, observer: boulder, timeZone: denver)
        let expiry = summary.night.end
        var report = TonightReport(summary: summary, timeZone: denver,
                                   timeline: TonightTimelineModel(summary: summary, timeZone: denver),
                                   targets: .catalogPending, tonightStart: summary.night.start, nightsFromTonight: -1,
                                   tonightExpiry: expiry, appliesSkyline: true)
        XCTAssertEqual(report.timeZone, denver)
        XCTAssertEqual(report.nightsFromTonight, -1)
        XCTAssertEqual(report.tonightExpiry, expiry)
        XCTAssertEqual(report.tonightStart, summary.night.start)
        XCTAssertTrue(report.appliesSkyline)
        XCTAssertNil(report.smallBodies)
        guard case .catalogPending = report.targets else { return XCTFail("the targets outcome changed") }
        report.smallBodies = []
        XCTAssertEqual(report.smallBodies?.count, 0)
    }
}

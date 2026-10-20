import Foundation
import XCTest
@testable import AppCore

/// The night's cloud forecast: slots cut to the night, the mean, the clear spells and the two summaries.
final class OnlineForecastNightTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_792_281_600)

    /// `base` plus `hours` hours.
    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    /// A time of day as "t<hours>", so that the texts do not depend on a time zone or a locale.
    private func label(_ date: Date) -> String { "t\(Int((date.timeIntervalSince(base) / 3600).rounded()))" }

    private func hour(_ hours: Double, _ total: Double, low: Double = 0, medium: Double = 0, high: Double = 0) -> CloudHour {
        CloudHour(time: at(hours), total: total, low: low, medium: medium, high: high)
    }

    private func forecast(_ hours: [CloudHour]) -> CloudForecast {
        CloudForecast(issuedAt: base, latitude: nil, longitude: nil, hours: hours)
    }

    private func night(_ from: Double, _ to: Double) -> DateInterval { DateInterval(start: at(from), end: at(to)) }

    private func slot(_ from: Double, _ to: Double, _ total: Double) -> CloudSlot {
        CloudSlot(start: at(from), end: at(to), total: total, low: 0, medium: 0, high: 0)
    }

    /// One-hour slots from hour 0 with the given totals.
    private func hourly(_ totals: [Double]) -> [CloudSlot] {
        totals.enumerated().map { slot(Double($0.offset), Double($0.offset + 1), $0.element) }
    }

    // MARK: Constants

    func testTheThresholds() {
        XCTAssertEqual(ForecastNight.clearBelow, 30)
        XCTAssertEqual(ForecastNight.cloudyFrom, 70)
        XCTAssertEqual(ForecastNight.minimumClearSpell, 7200)
    }

    func testASlotKnowsItsLength() {
        XCTAssertEqual(slot(1, 3.5, 10).seconds, 9000, accuracy: 1e-9)
    }

    // MARK: Slots

    func testSlotsAreCutToTheNight() {
        let hours = [hour(0, 10), hour(1, 20), hour(2, 30), hour(3, 40)]
        let slots = ForecastNight.slots(forecast(hours), night: night(0.5, 2.5))
        XCTAssertEqual(slots.map(\.start), [at(0.5), at(1), at(2)])
        XCTAssertEqual(slots.map(\.end), [at(1), at(2), at(2.5)])
        XCTAssertEqual(slots.map(\.total), [10, 20, 30])
    }

    func testSlotsCarryTheLayers() {
        let slots = ForecastNight.slots(forecast([hour(0, 50, low: 5, medium: 15, high: 25), hour(1, 60)]),
                                        night: night(0, 1))
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].total, 50)
        XCTAssertEqual(slots[0].low, 5)
        XCTAssertEqual(slots[0].medium, 15)
        XCTAssertEqual(slots[0].high, 25)
    }

    func testTheLastForecastTimeCountsForOneHour() {
        let hours = [hour(0, 10), hour(1, 20), hour(2, 30)]
        let slots = ForecastNight.slots(forecast(hours), night: night(0, 5))
        XCTAssertEqual(slots.map(\.start), [at(0), at(1), at(2)])
        XCTAssertEqual(slots.map(\.end), [at(1), at(2), at(3)])
    }

    func testSixHourlyTimesGiveSixHourSlots() {
        let hours = [hour(0, 10), hour(1, 20), hour(2, 30), hour(8, 40), hour(14, 50)]
        let slots = ForecastNight.slots(forecast(hours), night: night(0, 10))
        XCTAssertEqual(slots.map(\.start), [at(0), at(1), at(2), at(8)])
        XCTAssertEqual(slots.map(\.end), [at(1), at(2), at(8), at(10)])
        XCTAssertEqual(slots.map(\.total), [10, 20, 30, 40])
        XCTAssertEqual(slots[2].seconds, 6 * 3600, accuracy: 1e-9)
    }

    func testAnEarlierForecastGivesNoSlots() {
        let hours = [hour(0, 10), hour(1, 20), hour(2, 30)]
        XCTAssertTrue(ForecastNight.slots(forecast(hours), night: night(10, 12)).isEmpty)
    }

    func testALaterForecastGivesNoSlots() {
        let hours = [hour(10, 10), hour(11, 20), hour(12, 30)]
        XCTAssertTrue(ForecastNight.slots(forecast(hours), night: night(0, 5)).isEmpty)
    }

    func testAnEmptyForecastGivesNoSlots() {
        XCTAssertTrue(ForecastNight.slots(forecast([]), night: night(0, 5)).isEmpty)
    }

    func testANightOfNoLengthGivesNoSlots() {
        let hours = [hour(0, 10), hour(1, 20)]
        XCTAssertTrue(ForecastNight.slots(forecast(hours), night: DateInterval(start: at(1), end: at(1))).isEmpty)
    }

    func testAForecastThatStartsInsideTheNightGivesSlotsFromItsFirstTime() {
        let hours = [hour(2, 10), hour(3, 20)]
        let slots = ForecastNight.slots(forecast(hours), night: night(0, 4))
        XCTAssertEqual(slots.map(\.start), [at(2), at(3)])
        XCTAssertEqual(slots.map(\.end), [at(3), at(4)])
    }

    func testPartialCoverageAtTheEndOfTheNight() {
        // The forecast stops after hour 3 (+1 h): the night goes on to hour 8.
        let hours = [hour(0, 10), hour(1, 10), hour(2, 10), hour(3, 10)]
        let slots = ForecastNight.slots(forecast(hours), night: night(1, 8))
        XCTAssertEqual(slots.first?.start, at(1))
        XCTAssertEqual(slots.last?.end, at(4))
    }

    // MARK: Mean

    func testTheMeanOfNoSlotsIsZero() {
        XCTAssertEqual(ForecastNight.meanTotal([]), 0)
    }

    func testTheMeanIsWeightedByTime() {
        XCTAssertEqual(ForecastNight.meanTotal([slot(0, 1, 100), slot(1, 4, 0)]), 25, accuracy: 1e-9)
        XCTAssertEqual(ForecastNight.meanTotal(hourly([10, 20, 30])), 20, accuracy: 1e-9)
    }

    func testTheMeanOfSlotsOfNoLengthIsZero() {
        XCTAssertEqual(ForecastNight.meanTotal([slot(1, 1, 90)]), 0)
    }

    // MARK: Clear spells

    func testClearSpellsAreTheUnbrokenStretchesUnderThirtyPercent() {
        let spells = ForecastNight.clearSpells(hourly([10, 20, 50, 5, 5]))
        XCTAssertEqual(spells, [ForecastNight.ClearSpell(start: at(0), end: at(2)),
                                ForecastNight.ClearSpell(start: at(3), end: at(5))])
        XCTAssertEqual(spells.map(\.seconds), [7200, 7200])
    }

    func testThirtyPercentIsNotClear() {
        let spells = ForecastNight.clearSpells(hourly([29.9, 30, 29.9]))
        XCTAssertEqual(spells, [ForecastNight.ClearSpell(start: at(0), end: at(1)),
                                ForecastNight.ClearSpell(start: at(2), end: at(3))])
    }

    func testAGapBetweenClearSlotsSeparatesTheSpells() {
        let spells = ForecastNight.clearSpells([slot(0, 1, 10), slot(2, 3, 10)])
        XCTAssertEqual(spells.count, 2)
    }

    func testClearSlotsThatTouchFormOneSpell() {
        let spells = ForecastNight.clearSpells([slot(0, 1, 10), slot(1, 3, 0), slot(3, 3.5, 29)])
        XCTAssertEqual(spells, [ForecastNight.ClearSpell(start: at(0), end: at(3.5))])
    }

    func testCloudyOrEmptySlotsHaveNoSpells() {
        XCTAssertTrue(ForecastNight.clearSpells([]).isEmpty)
        XCTAssertTrue(ForecastNight.clearSpells(hourly([30, 80, 100])).isEmpty)
    }

    func testASpellThatEndsTheListIsKept() {
        let spells = ForecastNight.clearSpells(hourly([80, 10, 10]))
        XCTAssertEqual(spells, [ForecastNight.ClearSpell(start: at(1), end: at(3))])
    }

    // MARK: Summary

    func testNoSlotsGiveNoSummary() {
        XCTAssertNil(ForecastNight.summary([], timeText: label))
        XCTAssertNil(ForecastNight.spokenSummary([], timeText: label))
    }

    func testAClearNightIsClearAllNight() {
        XCTAssertEqual(ForecastNight.summary(hourly([10, 10, 10, 10, 10, 10]), timeText: label), "Clear all night")
        XCTAssertEqual(ForecastNight.summary([slot(0, 0.5, 0)], timeText: label), "Clear all night")
    }

    func testNineTenthsClearIsClearAllNight() {
        var totals = Array(repeating: 10.0, count: 19)
        totals.append(90)
        XCTAssertEqual(ForecastNight.summary(hourly(totals), timeText: label), "Clear all night")
    }

    func testEightTenthsClearIsNotClearAllNight() {
        let totals: [Double] = [90, 90] + Array(repeating: 10.0, count: 8)
        XCTAssertEqual(ForecastNight.summary(hourly(totals), timeText: label), "Mostly clear after t2")
    }

    func testClearAtTheEndIsMostlyClearAfter() {
        XCTAssertEqual(ForecastNight.summary(hourly([80, 80, 80, 10, 10, 10]), timeText: label), "Mostly clear after t3")
    }

    func testClearAtTheStartIsMostlyClearUntil() {
        XCTAssertEqual(ForecastNight.summary(hourly([10, 10, 10, 80, 80, 80]), timeText: label), "Mostly clear until t3")
    }

    func testClearInTheMiddleNamesBothTimes() {
        XCTAssertEqual(ForecastNight.summary(hourly([80, 80, 10, 10, 10, 80, 80]), timeText: label), "Clear from t2 to t5")
    }

    func testTheLongestSpellIsNamed() {
        // A one-hour and a three-hour spell: the three-hour one wins.
        XCTAssertEqual(ForecastNight.summary(hourly([80, 10, 80, 80, 10, 10, 10, 80, 80]), timeText: label),
                       "Clear from t4 to t7")
    }

    func testACloudyNightIsCloudyAllNight() {
        XCTAssertEqual(ForecastNight.summary(hourly([80, 80, 80, 80, 80, 80]), timeText: label), "Cloudy all night")
    }

    func testSeventyPercentOnAverageIsCloudy() {
        XCTAssertEqual(ForecastNight.summary(hourly(Array(repeating: 70.0, count: 6)), timeText: label), "Cloudy all night")
        XCTAssertEqual(ForecastNight.summary(hourly(Array(repeating: 69.0, count: 6)), timeText: label), "No long clear spell")
    }

    func testBrokenSkyHasNoLongClearSpell() {
        XCTAssertEqual(ForecastNight.summary(hourly([10, 90, 10, 90, 10, 90]), timeText: label), "No long clear spell")
    }

    func testATwoHourSpellIsLongEnoughAndOneHourIsNot() {
        let twoHours = hourly([90, 90, 90, 10, 10, 90, 90, 90])
        XCTAssertEqual(ForecastNight.summary(twoHours, timeText: label), "Clear from t3 to t5")
        let oneHour = hourly([50, 50, 50, 10, 50, 50, 50, 50])
        XCTAssertEqual(ForecastNight.summary(oneHour, timeText: label), "No long clear spell")
    }

    func testASpellJustUnderTwoHoursIsNotLongEnough() {
        // Eight hours: 3 h cloudy, 1 h 59 min clear, 3 h 1 min cloudy.
        let justUnder = [
            slot(0, 3, 50),
            CloudSlot(start: at(3), end: at(3).addingTimeInterval(7140), total: 10, low: 0, medium: 0, high: 0),
            CloudSlot(start: at(3).addingTimeInterval(7140), end: at(8), total: 50, low: 0, medium: 0, high: 0),
        ]
        XCTAssertEqual(ForecastNight.summary(justUnder, timeText: label), "No long clear spell")
        let exactly = [slot(0, 3, 50), slot(3, 5, 10), slot(5, 8, 50)]
        XCTAssertEqual(ForecastNight.summary(exactly, timeText: label), "Clear from t3 to t5")
    }

    func testAShortNightNamesAClearSpellOfHalfItsLength() {
        // Two hours: one clear, one cloudy. The clear hour is half the night, which is enough.
        XCTAssertEqual(ForecastNight.summary(hourly([10, 90]), timeText: label), "Mostly clear until t1")
        XCTAssertEqual(ForecastNight.summary(hourly([90, 10]), timeText: label), "Mostly clear after t1")
    }

    func testAShortCloudyNight() {
        XCTAssertEqual(ForecastNight.summary([slot(0, 0.5, 90)], timeText: label), "Cloudy all night")
    }

    // MARK: Spoken summary

    func testTheSpokenSummaryNamesTheSpanTheExtremesAndTheSummary() {
        let slots = hourly([10, 20, 15, 12, 18, 25])
        XCTAssertEqual(ForecastNight.spokenSummary(slots, timeText: label),
                       "Cloud cover from t0 to t6. Total cloud runs from 10 percent at t0 to 25 percent at t5. Clear all night.")
    }

    func testTheSpokenPercentagesAreWholeNumbersCutOff() {
        let slots = hourly([12.9, 80.7, 50, 50, 50, 50])
        XCTAssertEqual(ForecastNight.spokenSummary(slots, timeText: label),
                       "Cloud cover from t0 to t6. Total cloud runs from 12 percent at t0 to 80 percent at t1. No long clear spell.")
    }

    func testTheSpokenSummaryOfACloudyNight() {
        let slots = hourly([75, 80, 90, 85, 95, 70])
        XCTAssertEqual(ForecastNight.spokenSummary(slots, timeText: label),
                       "Cloud cover from t0 to t6. Total cloud runs from 70 percent at t5 to 95 percent at t4. Cloudy all night.")
    }

    func testTheSpokenSummaryOfASingleSlot() {
        XCTAssertEqual(ForecastNight.spokenSummary([slot(2, 3, 40)], timeText: label),
                       "Cloud cover from t2 to t3. Total cloud runs from 40 percent at t2 to 40 percent at t2. No long clear spell.")
    }

    // MARK: From a forecast to words

    func testAForecastBecomesASummaryOfTheNight() {
        let hours = (0..<10).map { hour(Double($0), $0 < 4 ? 90 : 5) }
        let slots = ForecastNight.slots(forecast(hours), night: night(1, 9))
        XCTAssertEqual(slots.count, 8)
        XCTAssertEqual(ForecastNight.summary(slots, timeText: label), "Mostly clear after t4")
        XCTAssertEqual(ForecastNight.meanTotal(slots), (3 * 90.0 + 5 * 5.0) / 8, accuracy: 1e-9)
    }
}

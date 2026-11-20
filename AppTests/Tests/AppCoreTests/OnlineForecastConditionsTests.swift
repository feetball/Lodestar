import Foundation
import XCTest
@testable import AppCore

/// What the night's forecast says besides the clouds (Services/ForecastNight.swift): dew, wind, fog, the temperature range and
/// the hourly table.
final class OnlineForecastConditionsTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_792_281_600)

    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    private func slot(_ from: Double, _ to: Double, temperature: Double? = nil, dewPoint: Double? = nil,
                      humidity: Double? = nil, wind: Double? = nil, gust: Double? = nil, from direction: Double? = nil,
                      fog: Double? = nil, total: Double = 10) -> CloudSlot {
        CloudSlot(start: at(from), end: at(to), total: total, low: 0, medium: 0, high: 0, temperature: temperature,
                  dewPoint: dewPoint, humidity: humidity, windSpeed: wind, windGust: gust, windFromDirection: direction,
                  fog: fog)
    }

    // MARK: Constants

    func testTheThresholds() {
        XCTAssertEqual(ForecastNight.dewSpreadBelow, 2)
        XCTAssertEqual(ForecastNight.dewVeryLikelyBelow, 1)
        XCTAssertEqual(ForecastNight.windBreezyFrom, 5)
        XCTAssertEqual(ForecastNight.windWindyFrom, 8)
        XCTAssertEqual(ForecastNight.windStrongFrom, 12)
        XCTAssertEqual(ForecastNight.fogFrom, 50)
    }

    // MARK: The dew-point spread

    func testTheSpreadIsTheAirTemperatureMinusTheDewPoint() {
        XCTAssertEqual(ForecastNight.dewPointSpread(temperature: 8, dewPoint: 5.5), 2.5)
        XCTAssertEqual(slot(0, 1, temperature: 8, dewPoint: 5.5).dewPointSpread, 2.5)
    }

    func testTheSpreadIsNeverNegative() {
        XCTAssertEqual(ForecastNight.dewPointSpread(temperature: 5, dewPoint: 5.2), 0)
    }

    func testWithoutBothValuesThereIsNoSpread() {
        XCTAssertNil(ForecastNight.dewPointSpread(temperature: nil, dewPoint: 5))
        XCTAssertNil(ForecastNight.dewPointSpread(temperature: 5, dewPoint: nil))
        XCTAssertNil(slot(0, 1, temperature: 5).dewPointSpread)
    }

    // MARK: Dew

    func testDewIsWarnedOfFromTheFirstSlotWithASmallSpread() throws {
        let slots = [slot(0, 1, temperature: 10, dewPoint: 5), slot(1, 2, temperature: 8, dewPoint: 6.5),
                     slot(2, 3, temperature: 7, dewPoint: 6)]
        let warning = try XCTUnwrap(ForecastNight.dew(slots))
        XCTAssertEqual(warning.from, at(1))
        XCTAssertEqual(warning.minimumSpread, 1)
        XCTAssertFalse(warning.isVeryLikely, "a spread of 1 °C is not below the limit for very likely")
    }

    func testAnAlmostZeroSpreadMakesDewVeryLikely() throws {
        let warning = try XCTUnwrap(ForecastNight.dew([slot(0, 1, temperature: 6, dewPoint: 5.5)]))
        XCTAssertEqual(warning.minimumSpread, 0.5)
        XCTAssertTrue(warning.isVeryLikely)
    }

    func testTheSmallestSpreadOfTheNightIsReported() throws {
        let slots = [slot(0, 1, temperature: 7, dewPoint: 5.5), slot(1, 2, temperature: 6, dewPoint: 5.9)]
        let warning = try XCTUnwrap(ForecastNight.dew(slots))
        XCTAssertEqual(warning.from, at(0))
        XCTAssertEqual(warning.minimumSpread, 0.1, accuracy: 1e-9)
    }

    func testNoDewWhileTheSpreadStaysWideOrIsUnknown() {
        XCTAssertNil(ForecastNight.dew([slot(0, 1, temperature: 10, dewPoint: 5), slot(1, 2, temperature: 9, dewPoint: 7)]))
        XCTAssertNil(ForecastNight.dew([slot(0, 1)]))
        XCTAssertNil(ForecastNight.dew([]))
    }

    // MARK: Wind

    func testTheStrongestWindOfTheNightIsReportedWithItsDirectionAndTheStrongestGust() throws {
        let slots = [slot(0, 1, wind: 3, gust: 6, from: 90), slot(1, 2, wind: 7, gust: 9, from: 225),
                     slot(2, 3, wind: 4, gust: 12, from: 180)]
        let summary = try XCTUnwrap(ForecastNight.wind(slots))
        XCTAssertEqual(summary.maximum, 7)
        XCTAssertEqual(summary.gust, 12)
        XCTAssertEqual(summary.fromDirection, 225)
        XCTAssertEqual(summary.level, .breezy)
    }

    func testTheLevelsOfTheWind() {
        func level(_ speed: Double) -> WindLevel { WindSummary(maximum: speed, gust: nil, fromDirection: nil).level }
        XCTAssertEqual(level(0), .calm)
        XCTAssertEqual(level(4.9), .calm)
        XCTAssertEqual(level(5), .breezy)
        XCTAssertEqual(level(7.9), .breezy)
        XCTAssertEqual(level(8), .windy)
        XCTAssertEqual(level(11.9), .windy)
        XCTAssertEqual(level(12), .strong)
        XCTAssertEqual(level(30), .strong)
        XCTAssertEqual(WindLevel.strong.rawValue, "strong")
    }

    func testWithoutGustsOrDirectionsTheWindHasNeither() throws {
        let summary = try XCTUnwrap(ForecastNight.wind([slot(0, 1, wind: 2)]))
        XCTAssertEqual(summary.maximum, 2)
        XCTAssertNil(summary.gust)
        XCTAssertNil(summary.fromDirection)
        XCTAssertEqual(summary.level, .calm)
    }

    func testAGustCanBeStrongerInAnotherSlotThanTheWind() throws {
        let summary = try XCTUnwrap(ForecastNight.wind([slot(0, 1, wind: 5, from: 10), slot(1, 2, gust: 15)]))
        XCTAssertEqual(summary.maximum, 5)
        XCTAssertEqual(summary.gust, 15)
        XCTAssertEqual(summary.fromDirection, 10)
    }

    func testWithoutAWindSpeedThereIsNoWind() {
        XCTAssertNil(ForecastNight.wind([slot(0, 1)]))
        XCTAssertNil(ForecastNight.wind([slot(0, 1, gust: 9)]), "gusts alone do not make a wind")
        XCTAssertNil(ForecastNight.wind([]))
    }

    // MARK: Fog

    func testFogCoversTheSlotsAtOrAboveTheLimit() throws {
        let slots = [slot(0, 1, fog: 10), slot(1, 2, fog: 50), slot(2, 4, fog: 80), slot(4, 5, fog: 49.9)]
        let summary = try XCTUnwrap(ForecastNight.fog(slots))
        XCTAssertEqual(summary.from, at(1))
        XCTAssertEqual(summary.seconds, 3 * 3600)
    }

    func testNoFogBelowTheLimitOrWithoutData() {
        XCTAssertNil(ForecastNight.fog([slot(0, 1, fog: 49), slot(1, 2)]))
        XCTAssertNil(ForecastNight.fog([]))
    }

    // MARK: Temperature and the table

    func testTheTemperatureRangeIsTheLowestAndHighestOfTheNight() throws {
        let slots = [slot(0, 1, temperature: 4), slot(1, 2), slot(2, 3, temperature: -3), slot(3, 4, temperature: 9)]
        let range = try XCTUnwrap(ForecastNight.temperature(slots))
        XCTAssertEqual(range.minimum, -3)
        XCTAssertEqual(range.maximum, 9)
    }

    func testOneTemperatureIsBothEnds() throws {
        let range = try XCTUnwrap(ForecastNight.temperature([slot(0, 1, temperature: 4)]))
        XCTAssertEqual(range, TemperatureRange(minimum: 4, maximum: 4))
    }

    func testWithoutATemperatureThereIsNoRange() {
        XCTAssertNil(ForecastNight.temperature([slot(0, 1)]))
        XCTAssertNil(ForecastNight.temperature([]))
    }

    func testTheHourlyTableHasOneRowPerSlot() {
        let slots = [slot(0, 1, temperature: 8, dewPoint: 6, humidity: 90, wind: 3, gust: 5, total: 20),
                     slot(1, 2, total: 80)]
        XCTAssertEqual(ForecastNight.hourly(slots), [
            NightHour(time: at(0), cloud: 20, temperature: 8, dewPointSpread: 2, windSpeed: 3, windGust: 5, humidity: 90),
            NightHour(time: at(1), cloud: 80, temperature: nil, dewPointSpread: nil, windSpeed: nil, windGust: nil,
                      humidity: nil),
        ])
        XCTAssertTrue(ForecastNight.hourly([]).isEmpty)
    }

    func testTheConditionsGatherEveryPart() {
        let slots = [slot(0, 1, temperature: 6, dewPoint: 5.5, wind: 9, from: 270, fog: 60)]
        let conditions = ForecastNight.conditions(slots)
        XCTAssertEqual(conditions.dew?.minimumSpread, 0.5)
        XCTAssertEqual(conditions.wind?.level, .windy)
        XCTAssertEqual(conditions.fog?.seconds, 3600)
        XCTAssertEqual(conditions.temperature, TemperatureRange(minimum: 6, maximum: 6))
        XCTAssertEqual(conditions.hourly.count, 1)
        let empty = ForecastNight.conditions([])
        XCTAssertNil(empty.dew)
        XCTAssertNil(empty.wind)
        XCTAssertNil(empty.fog)
        XCTAssertNil(empty.temperature)
        XCTAssertTrue(empty.hourly.isEmpty)
    }

    // MARK: From the forecast

    func testTheSlotsCarryTheWeatherOfTheirForecastTimes() throws {
        let hours = [
            CloudHour(time: at(0), total: 10, low: 5, medium: 3, high: 2, temperature: 7, dewPoint: 5, humidity: 80, windSpeed: 4,
                      windGust: 8, windFromDirection: 200, fog: 12),
            CloudHour(time: at(1), total: 20, low: 0, medium: 0, high: 0),
        ]
        let forecast = CloudForecast(issuedAt: base, latitude: nil, longitude: nil, hours: hours)
        let slots = ForecastNight.slots(forecast, night: DateInterval(start: at(0), end: at(2)))
        let first = try XCTUnwrap(slots.first)
        XCTAssertEqual(first.temperature, 7)
        XCTAssertEqual(first.dewPoint, 5)
        XCTAssertEqual(first.humidity, 80)
        XCTAssertEqual(first.windSpeed, 4)
        XCTAssertEqual(first.windGust, 8)
        XCTAssertEqual(first.windFromDirection, 200)
        XCTAssertEqual(first.fog, 12)
        XCTAssertNil(slots[1].temperature)
        XCTAssertEqual(ForecastNight.conditions(slots).temperature, TemperatureRange(minimum: 7, maximum: 7))
    }
}

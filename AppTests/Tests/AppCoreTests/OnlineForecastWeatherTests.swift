import Foundation
import XCTest
@testable import AppCore

/// What the night's forecast says besides the clouds: the dew-point spread and the lens fogging it warns of, the wind, the
/// fog, the temperature range and the hourly table.
final class OnlineForecastWeatherTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_792_281_600)

    /// `base` plus `hours` hours.
    private func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

    /// A one-hour slot from hour `from` with the given weather.
    private func slot(_ from: Double, temperature: Double? = nil, dewPoint: Double? = nil, humidity: Double? = nil,
                      windSpeed: Double? = nil, windGust: Double? = nil, windFrom: Double? = nil, fog: Double? = nil,
                      total: Double = 10) -> CloudSlot {
        CloudSlot(start: at(from), end: at(from + 1), total: total, low: 0, medium: 0, high: 0, temperature: temperature,
                  dewPoint: dewPoint, humidity: humidity, windSpeed: windSpeed, windGust: windGust,
                  windFromDirection: windFrom, fog: fog)
    }

    // MARK: Dew-point spread

    func testTheSpreadIsTheAirMinusTheDewPoint() {
        XCTAssertEqual(try XCTUnwrap(ForecastNight.dewPointSpread(temperature: 8, dewPoint: 5.5)), 2.5, accuracy: 1e-12)
    }

    func testADewPointAboveTheAirGivesNoNegativeSpread() {
        XCTAssertEqual(ForecastNight.dewPointSpread(temperature: 4, dewPoint: 4.3), 0)
    }

    func testTheSpreadIsUnknownWithoutBothValues() {
        XCTAssertNil(ForecastNight.dewPointSpread(temperature: nil, dewPoint: 3))
        XCTAssertNil(ForecastNight.dewPointSpread(temperature: 3, dewPoint: nil))
        XCTAssertNil(ForecastNight.dewPointSpread(temperature: nil, dewPoint: nil))
    }

    func testASlotAndAForecastHourKnowTheirSpread() {
        XCTAssertEqual(try XCTUnwrap(slot(0, temperature: 10, dewPoint: 6).dewPointSpread), 4, accuracy: 1e-12)
        XCTAssertNil(slot(0, temperature: 10).dewPointSpread)
        let hour = CloudHour(time: base, total: 0, low: 0, medium: 0, high: 0, temperature: 2, dewPoint: 1.5)
        XCTAssertEqual(try XCTUnwrap(hour.dewPointSpread), 0.5, accuracy: 1e-12)
    }

    func testTheForecastsWeatherReachesTheSlots() {
        let hours = [
            CloudHour(time: at(0), total: 5, low: 1, medium: 2, high: 3, temperature: 7, dewPoint: 4, humidity: 80,
                      windSpeed: 3, windGust: 6, windFromDirection: 270, fog: 20),
            CloudHour(time: at(1), total: 5, low: 1, medium: 2, high: 3),
        ]
        let forecast = CloudForecast(issuedAt: base, latitude: nil, longitude: nil, hours: hours)
        let slots = ForecastNight.slots(forecast, night: DateInterval(start: at(0), end: at(2)))
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].temperature, 7)
        XCTAssertEqual(slots[0].dewPoint, 4)
        XCTAssertEqual(slots[0].humidity, 80)
        XCTAssertEqual(slots[0].windSpeed, 3)
        XCTAssertEqual(slots[0].windGust, 6)
        XCTAssertEqual(slots[0].windFromDirection, 270)
        XCTAssertEqual(slots[0].fog, 20)
        XCTAssertNil(slots[1].temperature)
        XCTAssertNil(slots[1].windSpeed)
        XCTAssertNil(slots[1].fog)
    }

    // MARK: Dew

    func testNoDewWarningWhileTheSpreadStaysAtTwoDegreesOrMore() {
        let slots = [slot(0, temperature: 10, dewPoint: 8), slot(1, temperature: 9, dewPoint: 5)]
        XCTAssertNil(ForecastNight.dew(slots))
    }

    func testNoDewWarningWithoutADewPoint() {
        XCTAssertNil(ForecastNight.dew([slot(0, temperature: 10), slot(1)]))
        XCTAssertNil(ForecastNight.dew([]))
    }

    func testTheDewWarningStartsAtTheFirstSlotBelowTwoDegreesAndNamesTheSmallestSpread() throws {
        let slots = [
            slot(0, temperature: 10, dewPoint: 5),
            slot(1, temperature: 9, dewPoint: 7.5),
            slot(2, temperature: 8, dewPoint: 7.2),
            slot(3, temperature: 7, dewPoint: 7),
        ]
        let warning = try XCTUnwrap(ForecastNight.dew(slots))
        XCTAssertEqual(warning.from, at(1))
        XCTAssertEqual(warning.minimumSpread, 0, accuracy: 1e-12)
        XCTAssertTrue(warning.isVeryLikely)
    }

    func testASpreadOfTwoDegreesIsNotAWarningAndOneDegreeIsNotVeryLikely() throws {
        XCTAssertNil(ForecastNight.dew([slot(0, temperature: 10, dewPoint: 8)]))
        let warning = try XCTUnwrap(ForecastNight.dew([slot(0, temperature: 10, dewPoint: 9)]))
        XCTAssertEqual(warning.minimumSpread, 1, accuracy: 1e-12)
        XCTAssertFalse(warning.isVeryLikely)
    }

    func testASlotWithoutADewPointDoesNotHideALaterWarning() throws {
        let warning = try XCTUnwrap(ForecastNight.dew([slot(0), slot(1, temperature: 5, dewPoint: 4.5)]))
        XCTAssertEqual(warning.from, at(1))
        XCTAssertEqual(warning.minimumSpread, 0.5, accuracy: 1e-12)
    }

    // MARK: Wind

    func testTheWindIsTheStrongestSustainedWindWithItsDirectionAndTheStrongestGust() throws {
        let slots = [
            slot(0, windSpeed: 3, windGust: 5, windFrom: 90),
            slot(1, windSpeed: 7, windGust: 9, windFrom: 200),
            slot(2, windSpeed: 4, windGust: 12, windFrom: 10),
        ]
        let wind = try XCTUnwrap(ForecastNight.wind(slots))
        XCTAssertEqual(wind.maximum, 7)
        XCTAssertEqual(wind.gust, 12)
        XCTAssertEqual(wind.fromDirection, 200)
    }

    func testTheWindHasNoGustWhenTheForecastHasNone() throws {
        let wind = try XCTUnwrap(ForecastNight.wind([slot(0, windSpeed: 2), slot(1, windSpeed: 1)]))
        XCTAssertEqual(wind.maximum, 2)
        XCTAssertNil(wind.gust)
        XCTAssertNil(wind.fromDirection)
    }

    func testThereIsNoWindWithoutAWindSpeed() {
        XCTAssertNil(ForecastNight.wind([slot(0, windGust: 8), slot(1)]))
        XCTAssertNil(ForecastNight.wind([]))
    }

    func testAWindOfZeroIsStillAWind() throws {
        let wind = try XCTUnwrap(ForecastNight.wind([slot(0, windSpeed: 0, windFrom: 45)]))
        XCTAssertEqual(wind.maximum, 0)
        XCTAssertEqual(wind.fromDirection, 45)
        XCTAssertEqual(wind.level, .calm)
    }

    func testTheWindLevelsBeginAtTheirThresholds() {
        func level(_ speed: Double) -> WindLevel { WindSummary(maximum: speed, gust: nil, fromDirection: nil).level }
        XCTAssertEqual(level(4.9), .calm)
        XCTAssertEqual(level(ForecastNight.windBreezyFrom), .breezy)
        XCTAssertEqual(level(7.9), .breezy)
        XCTAssertEqual(level(ForecastNight.windWindyFrom), .windy)
        XCTAssertEqual(level(11.9), .windy)
        XCTAssertEqual(level(ForecastNight.windStrongFrom), .strong)
        XCTAssertEqual(level(30), .strong)
        XCTAssertEqual([WindLevel.calm, .breezy, .windy, .strong].map(\.rawValue), ["calm", "breezy", "windy", "strong"])
    }

    // MARK: Fog

    func testFogIsTheSlotsWithAtLeastHalfAFogAreaFraction() throws {
        let slots = [slot(0, fog: 10), slot(1, fog: 50), slot(2, fog: 80), slot(3, fog: 49.9), slot(4, fog: 60)]
        let fog = try XCTUnwrap(ForecastNight.fog(slots))
        XCTAssertEqual(fog.from, at(1))
        XCTAssertEqual(fog.seconds, 3 * 3600)
    }

    func testNoFogWithoutFogSlots() {
        XCTAssertNil(ForecastNight.fog([slot(0, fog: 0), slot(1, fog: 49), slot(2)]))
        XCTAssertNil(ForecastNight.fog([]))
    }

    // MARK: Temperature

    func testTheTemperatureRangeIsTheLowestAndTheHighest() throws {
        let slots = [slot(0, temperature: 4), slot(1, temperature: -2.5), slot(2), slot(3, temperature: 9)]
        let range = try XCTUnwrap(ForecastNight.temperature(slots))
        XCTAssertEqual(range.minimum, -2.5)
        XCTAssertEqual(range.maximum, 9)
    }

    func testOneTemperatureIsARangeOfOne() throws {
        let range = try XCTUnwrap(ForecastNight.temperature([slot(0, temperature: 3)]))
        XCTAssertEqual(range, TemperatureRange(minimum: 3, maximum: 3))
    }

    func testThereIsNoRangeWithoutATemperature() {
        XCTAssertNil(ForecastNight.temperature([slot(0), slot(1)]))
        XCTAssertNil(ForecastNight.temperature([]))
    }

    // MARK: Hourly table and everything together

    func testTheHourlyTableHasOneRowPerSlot() {
        let slots = [
            slot(0, temperature: 6, dewPoint: 4, humidity: 75, windSpeed: 2, windGust: 4, total: 20),
            slot(1, total: 95),
        ]
        let rows = ForecastNight.hourly(slots)
        XCTAssertEqual(rows, [
            NightHour(time: at(0), cloud: 20, temperature: 6, dewPointSpread: 2, windSpeed: 2, windGust: 4, humidity: 75),
            NightHour(time: at(1), cloud: 95, temperature: nil, dewPointSpread: nil, windSpeed: nil, windGust: nil,
                      humidity: nil),
        ])
        XCTAssertEqual(ForecastNight.hourly([]), [])
    }

    func testTheConditionsGatherEveryPart() throws {
        let slots = [
            slot(0, temperature: 5, dewPoint: 4.5, windSpeed: 6, windGust: 10, windFrom: 180, fog: 70),
            slot(1, temperature: 3, dewPoint: 0, windSpeed: 2, fog: 10),
        ]
        let conditions = ForecastNight.conditions(slots)
        XCTAssertEqual(conditions.dew?.from, at(0))
        XCTAssertEqual(conditions.dew?.minimumSpread, 0.5)
        XCTAssertEqual(conditions.wind, WindSummary(maximum: 6, gust: 10, fromDirection: 180))
        XCTAssertEqual(conditions.fog, FogSummary(from: at(0), seconds: 3600))
        XCTAssertEqual(conditions.temperature, TemperatureRange(minimum: 3, maximum: 5))
        XCTAssertEqual(conditions.hourly.count, 2)
    }

    func testTheConditionsOfAForecastWithoutWeatherAreEmpty() {
        let conditions = ForecastNight.conditions([slot(0), slot(1)])
        XCTAssertNil(conditions.dew)
        XCTAssertNil(conditions.wind)
        XCTAssertNil(conditions.fog)
        XCTAssertNil(conditions.temperature)
        XCTAssertEqual(conditions.hourly.count, 2)
    }
}

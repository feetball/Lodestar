import XCTest
import LodestarKit
@testable import ForecastCore

/// The weather values of the forecast: reading them, the night's dew, wind, fog and temperature, and their words. The
/// answer in `Fixtures/met-locationforecast-oslo.json` is a real Locationforecast 2.0 `complete` answer for 59.9, 10.7
/// (issued 2026-11-19T18:29:06Z), cut to 31 forecast times and to the details this app reads (data: MET Norway,
/// CC BY 4.0). Its hourly part runs from 2026-11-21T18:00Z to 2026-11-22T00:00Z, then it has one time every six hours up
/// to 2026-11-28T00:00Z; the six-hourly times have no gusts and no fog. The Kotlin tests of the Android app mirror these.
final class ForecastWeatherTests: XCTestCase {
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let minus = "\u{2212}"
    private let nbsp = "\u{00A0}"

    private func timeText(_ date: Date) -> String { clock.string(from: date) }

    private func at(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { preconditionFailure("bad test date \(text)") }
        return date
    }

    private func fixture() throws -> CloudForecast {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "met-locationforecast-oslo", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try ForecastParser.parseForecast(Data(contentsOf: url))
    }

    private func slots(_ forecast: CloudForecast, _ from: String, _ to: String) -> [CloudSlot] {
        ForecastNight.slots(forecast, night: DateInterval(start: at(from), end: at(to)))
    }

    /// A forecast of hourly times from 2026-11-20T18:00Z, one `CloudHour` per entry of `hours`.
    private func hourly(_ hours: ((Date) -> CloudHour)...) -> CloudForecast {
        let start = at("2026-11-20T18:00:00Z")
        let entries = hours.enumerated().map { index, make in make(start.addingTimeInterval(Double(index) * 3600)) }
        return CloudForecast(issuedAt: start, latitude: 59.9, longitude: 10.7, hours: entries)
    }

    private func hour(_ temperature: Double? = nil, _ dewPoint: Double? = nil, wind: Double? = nil, gust: Double? = nil,
                      fog: Double? = nil, direction: Double? = nil) -> (Date) -> CloudHour {
        { time in
            CloudHour(time: time, total: 20, low: 5, medium: 10, high: 15, temperature: temperature, dewPoint: dewPoint,
                      humidity: 70, windSpeed: wind, windGust: gust, windFromDirection: direction, fog: fog)
        }
    }

    private func night(_ forecast: CloudForecast, from: String = "2026-11-20T18:00:00Z",
                       to: String = "2026-11-21T06:00:00Z") -> [CloudSlot] {
        slots(forecast, from, to)
    }

    /// A forecast answer whose only forecast times all have the weather `details`.
    private func answer(_ details: String, count: Int = 6) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = at("2026-11-20T18:00:00Z")
        let entries = (0..<count).map { index in
            "{\"time\":\"\(formatter.string(from: start.addingTimeInterval(Double(index) * 3600)))\","
                + "\"data\":{\"instant\":{\"details\":{\(details)}}}}"
        }
        let text = "{\"geometry\":{\"coordinates\":[10.7,59.9,0]},\"properties\":{\"meta\":{\"updated_at\":"
            + "\"2026-11-20T17:30:00Z\"},\"timeseries\":[\(entries.joined(separator: ","))]}}"
        return Data(text.utf8)
    }

    // MARK: Reading

    func testTheWeatherOfARealAnswerIsRead() throws {
        let forecast = try fixture()
        XCTAssertEqual(forecast.hours.count, 31)
        XCTAssertEqual(forecast.key, "59.9,10.7")
        let first = try XCTUnwrap(forecast.hours.first)
        XCTAssertEqual(first.time, at("2026-11-21T18:00:00Z"))
        XCTAssertEqual(first.total, 37.2)
        XCTAssertEqual(first.temperature, 1.9)
        XCTAssertEqual(first.dewPoint, -5.0)
        XCTAssertEqual(first.humidity, 60.4)
        XCTAssertEqual(first.windSpeed, 5.3)
        XCTAssertEqual(first.windGust, 8.1)
        XCTAssertEqual(first.windFromDirection, 349.0)
        XCTAssertEqual(first.fog, 0.0)
        XCTAssertEqual(try XCTUnwrap(first.dewPointSpread), 6.9, accuracy: 1e-9)
        XCTAssertTrue(forecast.hours.allSatisfy { $0.temperature != nil && $0.dewPoint != nil && $0.windSpeed != nil })
    }

    func testTheSixHourlyTimesHaveNoGustsAndNoFog() throws {
        let sixHourly = try fixture().hours[7]
        XCTAssertEqual(sixHourly.time, at("2026-11-22T06:00:00Z"))
        XCTAssertEqual(sixHourly.temperature, 1.7)
        XCTAssertEqual(sixHourly.windSpeed, 6.5)
        XCTAssertEqual(sixHourly.windFromDirection, 350.7)
        XCTAssertNil(sixHourly.windGust)
        XCTAssertNil(sixHourly.fog)
    }

    func testAnAnswerWithoutWeatherValuesReadsWithNils() throws {
        let forecast = try ForecastParser.parseForecast(answer(
            "\"cloud_area_fraction\":40.0,\"cloud_area_fraction_high\":10.0,\"cloud_area_fraction_low\":20.0,"
                + "\"cloud_area_fraction_medium\":30.0"))
        let hour = try XCTUnwrap(forecast.hours.first)
        XCTAssertEqual(hour.total, 40.0)
        XCTAssertNil(hour.temperature)
        XCTAssertNil(hour.dewPoint)
        XCTAssertNil(hour.humidity)
        XCTAssertNil(hour.windSpeed)
        XCTAssertNil(hour.windGust)
        XCTAssertNil(hour.windFromDirection)
        XCTAssertNil(hour.fog)
        XCTAssertNil(hour.dewPointSpread)
    }

    func testValuesOutsideTheirRangeAreDropped() throws {
        let bad = try XCTUnwrap(ForecastParser.parseForecast(answer(
            "\"cloud_area_fraction\":10,\"air_temperature\":60.5,\"dew_point_temperature\":-90.5,\"wind_speed\":100.5,"
                + "\"wind_speed_of_gust\":-0.5,\"wind_from_direction\":360.5,\"relative_humidity\":-3,"
                + "\"fog_area_fraction\":140")).hours.first)
        XCTAssertNil(bad.temperature)
        XCTAssertNil(bad.dewPoint)
        XCTAssertNil(bad.windSpeed)
        XCTAssertNil(bad.windGust)
        XCTAssertNil(bad.windFromDirection)
        XCTAssertNil(bad.humidity)
        XCTAssertNil(bad.fog)
        let edges = try XCTUnwrap(ForecastParser.parseForecast(answer(
            "\"cloud_area_fraction\":10,\"air_temperature\":-90,\"dew_point_temperature\":60,\"wind_speed\":100,"
                + "\"wind_speed_of_gust\":0,\"wind_from_direction\":360,\"relative_humidity\":100,"
                + "\"fog_area_fraction\":0")).hours.first)
        XCTAssertEqual(edges.temperature, -90.0)
        XCTAssertEqual(edges.dewPoint, 60.0)
        XCTAssertEqual(edges.windSpeed, 100.0)
        XCTAssertEqual(edges.windGust, 0.0)
        XCTAssertEqual(edges.windFromDirection, 0.0)
        XCTAssertEqual(edges.humidity, 100.0)
        XCTAssertEqual(edges.fog, 0.0)
    }

    func testValuesThatAreNotNumbersAreDropped() throws {
        let hour = try XCTUnwrap(ForecastParser.parseForecast(answer(
            "\"cloud_area_fraction\":10,\"air_temperature\":\"warm\",\"dew_point_temperature\":null,"
                + "\"wind_speed\":\"fast\",\"fog_area_fraction\":\"none\"")).hours.first)
        XCTAssertNil(hour.temperature)
        XCTAssertNil(hour.dewPoint)
        XCTAssertNil(hour.windSpeed)
        XCTAssertNil(hour.fog)
    }

    func testADewPointAboveTheAirIsASpreadOfZero() throws {
        let hour = CloudHour(time: at("2026-11-20T18:00:00Z"), total: 0, low: 0, medium: 0, high: 0, temperature: 1.0,
                             dewPoint: 1.2)
        XCTAssertEqual(try XCTUnwrap(hour.dewPointSpread), 0.0)
    }

    // MARK: Dew

    func testDewStartsAtTheFirstSlotWithASpreadUnderTwoAndKeepsTheSmallestSpread() throws {
        let night = slots(try fixture(), "2026-11-26T18:00:00Z", "2026-11-27T12:00:00Z")
        let dew = try XCTUnwrap(ForecastNight.dew(night))
        XCTAssertEqual(dew.from, at("2026-11-27T00:00:00Z"))
        XCTAssertEqual(dew.minimumSpread, 1.8, accuracy: 1e-9)
        XCTAssertFalse(dew.isVeryLikely)
        XCTAssertEqual(ForecastWords.dewHint(dew, timeText: timeText), "Lens fogging likely from 00:00")
    }

    func testASpreadOfTwoOrMoreAllNightGivesNoDew() throws {
        let forecast = hourly(hour(0, -2), hour(0, -2), hour(1, -3))
        XCTAssertNil(ForecastNight.dew(night(forecast)))
        let real = slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z")
        XCTAssertNil(ForecastNight.dew(real))
    }

    func testDewIsJustUnderTwoAndVeryLikelyUnderOne() throws {
        let under = try XCTUnwrap(ForecastNight.dew(night(hourly(hour(0, -2.1), hour(0, -1.99)))))
        XCTAssertEqual(under.from, at("2026-11-20T19:00:00Z"))
        XCTAssertFalse(under.isVeryLikely)
        let one = try XCTUnwrap(ForecastNight.dew(night(hourly(hour(0, -3), hour(0, -1)))))
        XCTAssertFalse(one.isVeryLikely)
        let veryLikely = try XCTUnwrap(ForecastNight.dew(night(hourly(hour(0, -3), hour(0, -1.5), hour(0, -0.9)))))
        XCTAssertTrue(veryLikely.isVeryLikely)
        XCTAssertEqual(veryLikely.minimumSpread, 0.9, accuracy: 1e-9)
        XCTAssertEqual(veryLikely.from, at("2026-11-20T19:00:00Z"))
        XCTAssertEqual(ForecastWords.dewHint(veryLikely, timeText: timeText), "Lens fogging very likely from 19:00")
    }

    func testDewFromTheStartOfANightThatBeginsMidHourNamesThatTime() throws {
        let forecast = hourly(hour(0, -1.5), hour(0, -1.5), hour(0, -1.5))
        let night = night(forecast, from: "2026-11-20T18:40:00Z", to: "2026-11-20T21:00:00Z")
        let dew = try XCTUnwrap(ForecastNight.dew(night))
        XCTAssertEqual(ForecastWords.dewHint(dew, timeText: timeText), "Lens fogging likely from 18:40")
        let chips = ForecastWords.chips(ForecastNight.conditions(night), system: .metric, timeText: timeText)
        XCTAssertEqual(chips.first?.text, "Dew from 18:40")
    }

    func testSlotsWithoutADewPointAreIgnoredForTheDew() throws {
        let forecast = hourly(hour(0, nil), hour(nil, -1), hour(0, -0.5))
        let dew = try XCTUnwrap(ForecastNight.dew(night(forecast)))
        XCTAssertEqual(dew.from, at("2026-11-20T20:00:00Z"))
        XCTAssertNil(ForecastNight.dew(night(hourly(hour(0, nil), hour(nil, -1)))))
    }

    // MARK: Wind

    func testTheWindOfTheNightIsItsStrongestSlot() throws {
        let wind = try XCTUnwrap(ForecastNight.wind(slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z")))
        XCTAssertEqual(wind.maximum, 6.6)
        XCTAssertEqual(wind.gust, 10.2)
        XCTAssertEqual(wind.fromDirection, 354.0)
        XCTAssertEqual(wind.level, .breezy)
    }

    func testTheWindLevelsStartAtFiveEightAndTwelve() throws {
        func level(_ speed: Double) throws -> WindLevel {
            try XCTUnwrap(ForecastNight.wind(night(hourly(hour(wind: speed))))).level
        }
        XCTAssertEqual(try level(0), .calm)
        XCTAssertEqual(try level(4.9), .calm)
        XCTAssertEqual(try level(5.0), .breezy)
        XCTAssertEqual(try level(7.9), .breezy)
        XCTAssertEqual(try level(8.0), .windy)
        XCTAssertEqual(try level(11.9), .windy)
        XCTAssertEqual(try level(12.0), .strong)
        XCTAssertEqual(try level(30.0), .strong)
    }

    func testTheWindLevelFollowsTheSustainedWindNotTheGust() throws {
        let wind = try XCTUnwrap(ForecastNight.wind(night(hourly(hour(wind: 3, gust: 15), hour(wind: 4, gust: 6)))))
        XCTAssertEqual(wind.maximum, 4.0)
        XCTAssertEqual(wind.gust, 15.0)
        XCTAssertEqual(wind.level, .calm)
    }

    func testNoWindSpeedGivesNoWindSummary() throws {
        XCTAssertNil(ForecastNight.wind(night(hourly(hour(gust: 9), hour()))))
        let calm = try XCTUnwrap(ForecastNight.wind(slots(try fixture(), "2026-11-26T18:00:00Z", "2026-11-27T12:00:00Z")))
        XCTAssertEqual(calm.maximum, 3.7)
        XCTAssertNil(calm.gust)
        XCTAssertEqual(calm.level, .calm)
    }

    // MARK: Fog and temperature

    func testFogCountsTheSlotsWithAtLeastFiftyPercent() throws {
        let forecast = hourly(hour(fog: 10), hour(fog: 49.9), hour(fog: 50), hour(fog: 80), hour(fog: 20), hour(fog: 60), hour())
        let fog = try XCTUnwrap(ForecastNight.fog(night(forecast)))
        XCTAssertEqual(fog.from, at("2026-11-20T20:00:00Z"))
        XCTAssertEqual(fog.seconds, 3 * 3600.0)
        XCTAssertNil(ForecastNight.fog(night(hourly(hour(fog: 49.9), hour(), hour(fog: 0)))))
        XCTAssertNil(ForecastNight.fog(slots(try fixture(), "2026-11-21T18:00:00Z", "2026-11-22T06:00:00Z")))
    }

    func testTheTemperatureRangeIsTheLowestAndHighestOfTheNight() throws {
        let range = try XCTUnwrap(ForecastNight.temperature(night(hourly(hour(2), hour(-3.5), hour(), hour(4.2), hour(1)))))
        XCTAssertEqual(range.minimum, -3.5)
        XCTAssertEqual(range.maximum, 4.2)
        XCTAssertNil(ForecastNight.temperature(night(hourly(hour(), hour()))))
        let real = try XCTUnwrap(ForecastNight.temperature(slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z")))
        XCTAssertEqual(real.minimum, 1.9)
        XCTAssertEqual(real.maximum, 3.4)
    }

    // MARK: The hourly table

    func testTheHourlyTableHasOneRowPerSlotOfTheNight() throws {
        let rows = ForecastNight.conditions(slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z")).hourly
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.first?.time, at("2026-11-21T18:40:00Z"))
        XCTAssertEqual(rows[1].time, at("2026-11-21T19:00:00Z"))
        XCTAssertEqual(rows.last?.time, at("2026-11-22T00:00:00Z"))
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(first.cloud, 37.2)
        XCTAssertEqual(first.temperature, 1.9)
        XCTAssertEqual(try XCTUnwrap(first.dewPointSpread), 6.9, accuracy: 1e-9)
        XCTAssertEqual(first.windSpeed, 5.3)
        XCTAssertEqual(first.humidity, 60.4)
    }

    func testTheSixHourlyPartGivesSixHourRows() throws {
        let rows = ForecastNight.conditions(slots(try fixture(), "2026-11-26T18:00:00Z", "2026-11-27T12:00:00Z")).hourly
        XCTAssertEqual(rows.map { timeText($0.time) }, ["18:00", "00:00", "06:00"])
    }

    // MARK: Words and units

    func testTheChipsOfARealNightInMetricAndUsUnits() throws {
        let conditions = ForecastNight.conditions(slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z"))
        let metric = ForecastWords.chips(conditions, system: .metric, timeText: timeText)
        XCTAssertEqual(metric.map { $0.kind }, [.wind, .temperature])
        XCTAssertEqual(metric[0].text, "Wind 7\(nbsp)m/s, gusts 10")
        XCTAssertTrue(metric[0].isWarning)
        XCTAssertEqual(metric[1].text, "2…3\(nbsp)°C")
        XCTAssertFalse(metric[1].isWarning)
        XCTAssertEqual(metric[0].spoken, "Wind up to 7 metres per second from N, gusts up to 10. Breezy: long exposures may shake.")
        XCTAssertEqual(metric[1].spoken, "Air temperature from 2 to 3 degrees Celsius.")
        let us = ForecastWords.chips(conditions, system: .us, timeText: timeText)
        XCTAssertEqual(us[0].text, "Wind 15\(nbsp)mph, gusts 23")
        XCTAssertEqual(us[1].text, "35…38\(nbsp)°F")
        XCTAssertEqual(us[0].spoken, "Wind up to 15 miles per hour from N, gusts up to 23. Breezy: long exposures may shake.")
    }

    func testTheChipsAreDewWindFogTemperatureAndOnlyThoseThereIsDataFor() throws {
        let forecast = hourly(
            hour(-1, -2, wind: 9, fog: 70, direction: 90), hour(-2, -2.5, wind: 8.5, fog: 60, direction: 100),
            hour(-3, -3.2, wind: 3, fog: 10, direction: 100))
        let conditions = ForecastNight.conditions(night(forecast))
        let chips = ForecastWords.chips(conditions, system: .metric, timeText: timeText)
        XCTAssertEqual(chips.map { $0.kind }, [.dew, .wind, .fog, .temperature])
        XCTAssertEqual(chips[0].text, "Dew from 18:00")
        XCTAssertTrue(chips[0].isWarning)
        XCTAssertEqual(chips[0].spoken, "Lens fogging very likely from 18:00. The air gets within 0.2 degrees Celsius of the dew point.")
        XCTAssertEqual(chips[1].text, "Wind 9\(nbsp)m/s")
        XCTAssertEqual(chips[1].spoken, "Wind up to 9 metres per second from E. Windy: weigh the tripod down.")
        XCTAssertEqual(chips[2].text, "Fog from 18:00")
        XCTAssertEqual(chips[2].spoken, "Fog expected for about 2 hours from 18:00.")
        XCTAssertTrue(chips[2].isWarning)
        XCTAssertEqual(chips[3].text, "\(minus)3…\(minus)1\(nbsp)°C")
        XCTAssertEqual(chips[3].spoken, "Air temperature from minus 3 to minus 1 degrees Celsius.")
        XCTAssertTrue(ForecastWords.chips(ForecastNight.conditions(night(hourly(hour(), hour()))), system: .metric,
                                          timeText: timeText).isEmpty)
    }

    func testTheHintNamesTheDewFirstThenTheWind() {
        let both = ForecastNight.conditions(night(hourly(hour(0, -0.5, wind: 13))))
        XCTAssertEqual(ForecastWords.hint(both, timeText: timeText), "Lens fogging very likely from 18:00")
        let windy = ForecastNight.conditions(night(hourly(hour(0, -5, wind: 8))))
        XCTAssertEqual(ForecastWords.hint(windy, timeText: timeText), "Windy: weigh the tripod down")
        let breezy = ForecastNight.conditions(night(hourly(hour(0, -5, wind: 5))))
        XCTAssertEqual(ForecastWords.hint(breezy, timeText: timeText), "Breezy: long exposures may shake")
        let strong = ForecastNight.conditions(night(hourly(hour(0, -5, wind: 12))))
        XCTAssertEqual(ForecastWords.hint(strong, timeText: timeText), "Strong wind: expect shaky frames")
        let calm = ForecastNight.conditions(night(hourly(hour(0, -5, wind: 4, fog: 90))))
        XCTAssertNil(ForecastWords.hint(calm, timeText: timeText))
        XCTAssertNil(ForecastWords.hint(ForecastNight.conditions([]), timeText: timeText))
    }

    func testAGustThatRoundsToTheWindIsNotNamed() {
        let wind = ForecastNight.conditions(night(hourly(hour(wind: 6, gust: 6.4))))
        XCTAssertEqual(ForecastWords.chips(wind, system: .metric, timeText: timeText).first?.text, "Wind 6\(nbsp)m/s")
    }

    func testTheHourlyCellsAndHeaders() throws {
        let rows = ForecastNight.conditions(slots(try fixture(), "2026-11-21T18:40:00Z", "2026-11-22T00:30:00Z")).hourly
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(ForecastWords.hourlyHeaders(.metric), ["Time", "Cloud", "Temp (°C)", "Dew gap (°C)", "Wind (m/s)"])
        XCTAssertEqual(ForecastWords.hourlyHeaders(.us), ["Time", "Cloud", "Temp (°F)", "Dew gap (°F)", "Wind (mph)"])
        XCTAssertEqual(ForecastWords.hourlyCells(first, system: .metric, timeText: timeText), ["18:40", "37%", "2", "6.9", "5"])
        XCTAssertEqual(ForecastWords.hourlyCells(first, system: .us, timeText: timeText), ["18:40", "37%", "35", "12.4", "12"])
        let missing = NightHour(time: at("2026-11-20T18:00:00Z"), cloud: 99.5, temperature: nil, dewPointSpread: nil,
                                windSpeed: nil, windGust: nil, humidity: nil)
        XCTAssertEqual(ForecastWords.hourlyCells(missing, system: .metric, timeText: timeText), ["18:00", "100%", "—", "—", "—"])
        XCTAssertEqual(ForecastWords.hourlySpoken(missing, system: .metric, timeText: timeText), "18:00. Cloud 100 percent.")
        XCTAssertEqual(
            ForecastWords.hourlySpoken(first, system: .metric, timeText: timeText),
            "18:40. Cloud 37 percent. Temperature 2 degrees Celsius. Dew gap 6.9 degrees Celsius. "
                + "Wind 5 metres per second. Humidity 60 percent.")
    }

    func testTemperaturesAreRoundedHalfAwayFromZeroWithARealMinusSign() {
        XCTAssertEqual(ForecastUnits.temperature(2.5, .metric), "3\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.temperature(-2.5, .metric), "\(minus)3\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.temperature(-0.4, .metric), "0\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.temperatureRange(-3.2, 3.6, .metric), "\(minus)3…4\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.temperatureRange(2.6, 3.4, .metric), "3\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.temperature(0, .us), "32\(nbsp)°F")
        XCTAssertEqual(ForecastUnits.temperatureRange(-3, 4, .us), "27…39\(nbsp)°F")
        XCTAssertEqual(ForecastUnits.temperature(-20, .us), "\(minus)4\(nbsp)°F")
    }

    func testSpeedsAndDifferencesInBothSystems() {
        XCTAssertEqual(ForecastUnits.speed(5.5, .metric), "6\(nbsp)m/s")
        XCTAssertEqual(ForecastUnits.speed(6, .us), "13\(nbsp)mph")
        XCTAssertEqual(ForecastUnits.speedValue(5, .us), 11)
        XCTAssertEqual(ForecastUnits.spokenSpeed(1.2, .metric), "1 metre per second")
        XCTAssertEqual(ForecastUnits.spokenSpeed(1, .us), "2 miles per hour")
        XCTAssertEqual(ForecastUnits.spokenSpeed(0.5, .us), "1 mile per hour")
        XCTAssertEqual(ForecastUnits.differenceValue(1.4, .metric), "1.4")
        XCTAssertEqual(ForecastUnits.difference(1.4, .us), "2.5\(nbsp)°F")
        XCTAssertEqual(ForecastUnits.difference(0, .metric), "0.0\(nbsp)°C")
        XCTAssertEqual(ForecastUnits.spokenTemperature(-19, .us), "minus 2 degrees Fahrenheit")
        XCTAssertEqual(ForecastUnits.spokenTemperature(0.8, .metric), "1 degree Celsius")
        XCTAssertEqual(ForecastUnits.spokenTemperature(-1.2, .metric), "minus 1 degree Celsius")
    }

    func testTheUnitSystemFollowsTheRegion() {
        XCTAssertEqual(ForecastUnits.system(for: Locale(identifier: "en_US")), .us)
        XCTAssertEqual(ForecastUnits.system(for: Locale(identifier: "de_DE")), .metric)
        XCTAssertEqual(ForecastUnits.system(for: Locale(identifier: "nb_NO")), .metric)
    }
}

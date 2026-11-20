import Foundation
import XCTest
@testable import AppCore

/// MET Norway Locationforecast 2.0 answers: valid, too short, malformed, out of order, percentages clamped.
final class OnlineForecastParserTests: XCTestCase {
    /// 2026-10-18T00:00:00Z.
    private let midnight = 1_792_281_600.0

    private func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    /// The time of hour `hour` of 2026-10-18 as MET Norway writes it.
    private func time(_ hour: Int) -> String { "2026-10-18T\(two(hour)):00:00Z" }

    /// One time series entry with the given `details` members (raw JSON values).
    private func entry(time: String, _ details: [String: String]) -> String {
        let members = details.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        return "{\"time\":\"\(time)\",\"data\":{\"instant\":{\"details\":{\(members)}}}}"
    }

    /// An entry for `hour` with a total cloud cover and optionally the layers.
    private func hourEntry(_ hour: Int, total: String? = "50", low: String? = nil, medium: String? = nil,
                           high: String? = nil) -> String {
        var details = ["air_temperature": "4.2", "wind_speed": "3.1"]
        if let total { details["cloud_area_fraction"] = total }
        if let low { details["cloud_area_fraction_low"] = low }
        if let medium { details["cloud_area_fraction_medium"] = medium }
        if let high { details["cloud_area_fraction_high"] = high }
        return entry(time: time(hour), details)
    }

    /// A whole answer. `nil` for `updatedAt` or `coordinates` leaves that member out.
    private func document(_ entries: [String], updatedAt: String? = "2026-10-18T18:30:00Z",
                          coordinates: String? = "[-96.8,32.8,150]") -> Data {
        let meta = updatedAt.map { "{\"updated_at\":\"\($0)\"}" } ?? "{}"
        var members: [String] = ["\"type\":\"Feature\""]
        if let coordinates { members.append("\"geometry\":{\"type\":\"Point\",\"coordinates\":\(coordinates)}") }
        members.append("\"properties\":{\"meta\":\(meta),\"timeseries\":[\(entries.joined(separator: ","))]}")
        return Data(("{" + members.joined(separator: ",") + "}").utf8)
    }

    /// `count` hourly entries from hour 0 with the total cloud `10 * hour + 5`.
    private func series(_ count: Int) -> [String] {
        (0..<count).map { hourEntry($0, total: "\($0 * 10 + 5)") }
    }

    private func message(_ data: Data) -> String? {
        do {
            _ = try ForecastParser.parseForecast(data)
            return nil
        } catch let error as OnlineDataError {
            return error.message
        } catch {
            return "unexpected error: \(error)"
        }
    }

    // MARK: Valid answers

    func testAValidAnswerIsRead() throws {
        let entries = (0..<8).map { hourEntry($0, total: "\($0 * 10 + 5)", low: "\($0)", medium: "\($0 + 1)", high: "\($0 + 2)") }
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.count, 8)
        XCTAssertEqual(forecast.hours[0].time.timeIntervalSince1970, midnight, accuracy: 0.001)
        XCTAssertEqual(forecast.hours[3].time.timeIntervalSince1970, midnight + 3 * 3600, accuracy: 0.001)
        XCTAssertEqual(forecast.hours[3].total, 35)
        XCTAssertEqual(forecast.hours[3].low, 3)
        XCTAssertEqual(forecast.hours[3].medium, 4)
        XCTAssertEqual(forecast.hours[3].high, 5)
        XCTAssertEqual(forecast.hours[7].total, 75)
        XCTAssertEqual(forecast.end, forecast.hours[7].time)
        XCTAssertEqual(forecast.end?.timeIntervalSince1970 ?? 0, midnight + 7 * 3600, accuracy: 0.001)
    }

    func testTheIssueTimeIsUpdatedAt() throws {
        let forecast = try ForecastParser.parseForecast(document(series(6)))
        XCTAssertEqual(forecast.issuedAt.timeIntervalSince1970, midnight + 18.5 * 3600, accuracy: 0.001)
    }

    func testThePlaceIsTheGridPointWithLongitudeFirst() throws {
        let forecast = try ForecastParser.parseForecast(document(series(6)))
        XCTAssertEqual(try XCTUnwrap(forecast.longitude), -96.8, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(forecast.latitude), 32.8, accuracy: 1e-9)
        XCTAssertEqual(forecast.key, "32.8,-96.8")
    }

    func testTheAltitudeOfTheGridPointIsNotKept() throws {
        // CloudForecast has no elevation at all; two answers that differ only in the altitude are equal.
        let low = try ForecastParser.parseForecast(document(series(6), coordinates: "[-96.8,32.8,0]"))
        let high = try ForecastParser.parseForecast(document(series(6), coordinates: "[-96.8,32.8,2500]"))
        XCTAssertEqual(low, high)
    }

    func testACoordinatePairWithoutAltitudeIsEnough() throws {
        let forecast = try ForecastParser.parseForecast(document(series(6), coordinates: "[10.5,-20.25]"))
        XCTAssertEqual(forecast.longitude, 10.5)
        XCTAssertEqual(forecast.latitude, -20.25)
    }

    func testMissingOrShortCoordinatesLeaveThePlaceOut() throws {
        for coordinates in [nil, "[-96.8]", "[]", "[\"a\",\"b\"]", "\"text\"", "{}"] as [String?] {
            let forecast = try ForecastParser.parseForecast(document(series(6), coordinates: coordinates))
            XCTAssertNil(forecast.latitude, coordinates ?? "no coordinates")
            XCTAssertNil(forecast.longitude, coordinates ?? "no coordinates")
            XCTAssertNil(forecast.key, coordinates ?? "no coordinates")
        }
    }

    func testTheParseFunctionWrapsTheForecastWithoutAnEpoch() throws {
        let parsed = try ForecastParser.parse(document(series(6)))
        XCTAssertEqual(parsed.value.hours.count, 6)
        XCTAssertNil(parsed.dataEpoch)
    }

    func testTimesWithFractionalSecondsAreRead() throws {
        var entries = series(6)
        entries[2] = entry(time: "2026-10-18T02:00:00.000Z", ["cloud_area_fraction": "20"])
        let forecast = try ForecastParser.parseForecast(document(entries, updatedAt: "2026-10-18T18:30:00.000Z"))
        XCTAssertEqual(forecast.hours[2].time.timeIntervalSince1970, midnight + 2 * 3600, accuracy: 0.001)
        XCTAssertEqual(forecast.issuedAt.timeIntervalSince1970, midnight + 18.5 * 3600, accuracy: 0.001)
    }

    func testOtherDetailMembersAreIgnored() throws {
        let entries = (0..<6).map { hour in
            entry(time: time(hour), ["cloud_area_fraction": "40", "fog_area_fraction": "7", "relative_humidity": "93.5"])
        }
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.map(\.total), Array(repeating: 40.0, count: 6))
    }

    func testIntegerAndDecimalValuesAreBothAccepted() throws {
        var entries = series(6)
        entries[0] = hourEntry(0, total: "12.5", low: "7", medium: "0.25", high: "100")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours[0].total, 12.5)
        XCTAssertEqual(forecast.hours[0].low, 7)
        XCTAssertEqual(forecast.hours[0].medium, 0.25)
        XCTAssertEqual(forecast.hours[0].high, 100)
    }

    // MARK: Layers and percentages

    func testMissingLayersAreZero() throws {
        let forecast = try ForecastParser.parseForecast(document(series(6)))
        for hour in forecast.hours {
            XCTAssertEqual(hour.low, 0)
            XCTAssertEqual(hour.medium, 0)
            XCTAssertEqual(hour.high, 0)
        }
    }

    func testPercentagesAreClampedToZeroToOneHundred() throws {
        var entries = series(6)
        entries[0] = hourEntry(0, total: "130", low: "-5", medium: "100.5", high: "100")
        entries[1] = hourEntry(1, total: "-0.5", low: "250", medium: "-100", high: "0")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours[0].total, 100)
        XCTAssertEqual(forecast.hours[0].low, 0)
        XCTAssertEqual(forecast.hours[0].medium, 100)
        XCTAssertEqual(forecast.hours[0].high, 100)
        XCTAssertEqual(forecast.hours[1].total, 0)
        XCTAssertEqual(forecast.hours[1].low, 100)
        XCTAssertEqual(forecast.hours[1].medium, 0)
        XCTAssertEqual(forecast.hours[1].high, 0)
    }

    func testValuesInsideTheRangeAreKeptExactly() throws {
        var entries = series(6)
        entries[0] = hourEntry(0, total: "0", low: "0.01", medium: "99.99", high: "100")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours[0].total, 0)
        XCTAssertEqual(forecast.hours[0].low, 0.01, accuracy: 1e-12)
        XCTAssertEqual(forecast.hours[0].medium, 99.99, accuracy: 1e-12)
        XCTAssertEqual(forecast.hours[0].high, 100)
    }

    func testAValueThatIsNotANumberCountsAsMissing() throws {
        var entries = series(6)
        entries[0] = hourEntry(0, total: "40", low: "\"30\"", medium: "null", high: "[1]")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours[0].total, 40)
        XCTAssertEqual(forecast.hours[0].low, 0)
        XCTAssertEqual(forecast.hours[0].medium, 0)
        XCTAssertEqual(forecast.hours[0].high, 0)
    }

    // MARK: Skipped entries

    func testEntriesWithoutATotalAreSkipped() throws {
        var entries = series(7)
        entries[3] = hourEntry(3, total: nil, low: "10")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.count, 6)
        XCTAssertEqual(forecast.hours.map { Int($0.time.timeIntervalSince1970 - midnight) / 3600 }, [0, 1, 2, 4, 5, 6])
    }

    func testEntriesWithATextTotalAreSkipped() throws {
        var entries = series(7)
        entries[0] = hourEntry(0, total: "\"50\"")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.count, 6)
        XCTAssertEqual(Int(forecast.hours[0].time.timeIntervalSince1970 - midnight), 3600)
    }

    func testEntriesWithABadTimeAreSkipped() throws {
        var entries = series(8)
        entries[2] = entry(time: "soon", ["cloud_area_fraction": "10"])
        entries[4] = "{\"data\":{\"instant\":{\"details\":{\"cloud_area_fraction\":10}}}}"
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.map { Int($0.time.timeIntervalSince1970 - midnight) / 3600 }, [0, 1, 3, 5, 6, 7])
    }

    func testEntriesWithoutDetailsOrOfTheWrongShapeAreSkipped() throws {
        var entries = series(6)
        entries.append("{\"time\":\"2026-10-18T06:00:00Z\"}")
        entries.append("{\"time\":\"2026-10-18T07:00:00Z\",\"data\":{\"instant\":{}}}")
        entries.append("null")
        entries.append("42")
        entries.append("\"text\"")
        entries.append("{}")
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.count, 6)
    }

    // MARK: Too few times

    func testExactlySixTimesAreEnough() throws {
        XCTAssertEqual(ForecastParser.minimumHours, 6)
        XCTAssertEqual(try ForecastParser.parseForecast(document(series(6))).hours.count, 6)
    }

    func testFiveTimesAreTooFew() {
        XCTAssertEqual(message(document(series(5))), "Too few forecast times.")
        XCTAssertEqual(message(document(series(0))), "Too few forecast times.")
    }

    func testSkippedEntriesCountAgainstTheMinimum() {
        var entries = series(6)
        entries[5] = hourEntry(5, total: nil)
        XCTAssertEqual(message(document(entries)), "Too few forecast times.")
    }

    // MARK: Order

    func testTimesMustAscend() {
        var entries = series(6)
        entries.swapAt(2, 3)
        XCTAssertEqual(message(document(entries)), "Forecast times out of order.")
    }

    func testARepeatedTimeIsOutOfOrder() {
        var entries = series(7)
        entries[4] = entries[3]
        XCTAssertEqual(message(document(entries)), "Forecast times out of order.")
    }

    func testUnevenButAscendingTimesAreFine() throws {
        // Hourly, then every six hours, as MET Norway sends them.
        let hours = [0, 1, 2, 3, 9, 15, 21]
        let entries = hours.map { hourEntry($0, total: "30") }
        let forecast = try ForecastParser.parseForecast(document(entries))
        XCTAssertEqual(forecast.hours.count, 7)
        XCTAssertEqual(forecast.end?.timeIntervalSince1970 ?? 0, midnight + 21 * 3600, accuracy: 0.001)
    }

    // MARK: Malformed answers

    func testBytesThatAreNotJSONAreRefused() {
        XCTAssertEqual(message(Data("this is not json".utf8))?.hasPrefix("Not JSON:"), true)
        XCTAssertEqual(message(Data())?.hasPrefix("Not JSON:"), true)
        XCTAssertEqual(message(Data("{\"properties\":".utf8))?.hasPrefix("Not JSON:"), true)
    }

    func testAnythingButAnObjectAtTheTopIsNotAForecast() {
        XCTAssertEqual(message(Data("[1,2,3]".utf8)), "Not a forecast.")
        XCTAssertEqual(message(Data("[]".utf8)), "Not a forecast.")
    }

    func testAnAnswerWithoutPropertiesIsRefused() {
        XCTAssertEqual(message(Data("{}".utf8)), "No properties.")
        XCTAssertEqual(message(Data("{\"properties\":[]}".utf8)), "No properties.")
        XCTAssertEqual(message(Data("{\"properties\":\"x\"}".utf8)), "No properties.")
    }

    func testAnAnswerWithoutATimeSeriesIsRefused() {
        XCTAssertEqual(message(Data("{\"properties\":{}}".utf8)), "No time series.")
        XCTAssertEqual(message(Data("{\"properties\":{\"timeseries\":{}}}".utf8)), "No time series.")
        XCTAssertEqual(message(Data("{\"properties\":{\"timeseries\":\"x\"}}".utf8)), "No time series.")
    }

    func testAnAnswerWithoutAValidIssueTimeIsRefused() {
        XCTAssertEqual(message(document(series(6), updatedAt: nil)), "No issue time.")
        XCTAssertEqual(message(document(series(6), updatedAt: "yesterday")), "No issue time.")
        XCTAssertEqual(message(document(series(6), updatedAt: "2026-10-18")), "No issue time.")
        XCTAssertEqual(message(Data("{\"properties\":{\"timeseries\":[]}}".utf8)), "No issue time.")
    }

    func testTheIssueTimeIsCheckedBeforeTheNumberOfTimes() {
        XCTAssertEqual(message(document([], updatedAt: nil)), "No issue time.")
    }

    // MARK: The value types

    func testAForecastWithoutHoursHasNoEndAndKeepsItsPlaceKey() {
        let forecast = CloudForecast(issuedAt: Date(timeIntervalSince1970: 0), latitude: 32.84, longitude: -96.77, hours: [])
        XCTAssertNil(forecast.end)
        XCTAssertEqual(forecast.key, "32.8,-96.8")
    }

    func testAForecastNeedsBothCoordinatesForAKey() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertNil(CloudForecast(issuedAt: date, latitude: 32.8, longitude: nil, hours: []).key)
        XCTAssertNil(CloudForecast(issuedAt: date, latitude: nil, longitude: -96.8, hours: []).key)
    }

    func testTheKeyOfAnAnswerMatchesTheKeyOfTheRequest() throws {
        let requestKey = OnlineCoordinates.key(latitude: 32.8473, longitude: -96.7712)
        let forecast = try ForecastParser.parseForecast(document(series(6), coordinates: "[-96.8,32.8,150]"))
        XCTAssertEqual(forecast.key, requestKey)
    }

    func testCloudHoursCompareByValue() {
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(CloudHour(time: date, total: 1, low: 2, medium: 3, high: 4),
                       CloudHour(time: date, total: 1, low: 2, medium: 3, high: 4))
        XCTAssertNotEqual(CloudHour(time: date, total: 1, low: 2, medium: 3, high: 4),
                          CloudHour(time: date, total: 1, low: 2, medium: 3, high: 5))
    }
}

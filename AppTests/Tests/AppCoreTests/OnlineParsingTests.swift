import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `OnlineParsing`: the validation of a download with the engine's parsers (satellite element sets, comets, the forecast).
final class OnlineParsingTests: XCTestCase {
    /// 2026-10-18T03:28:15Z, the epoch of the sample records.
    private let sampleEpoch = 1_792_294_095.0
    /// An hour after the sample epoch.
    private let now = Date(timeIntervalSince1970: 1_792_297_695)

    // MARK: Fixtures

    /// One CelesTrak OMM record (a low Earth orbit that the engine accepts) for `number` at `epoch`.
    private func omm(_ number: Int, epoch: String = "2026-10-18T03:28:15") -> String {
        let fields = [
            "\"OBJECT_NAME\":\"TEST SAT \(number)\"",
            "\"OBJECT_ID\":\"2020-001A\"",
            "\"EPOCH\":\"\(epoch)\"",
            "\"MEAN_MOTION\":15.5",
            "\"ECCENTRICITY\":0.001",
            "\"INCLINATION\":51.6",
            "\"RA_OF_ASC_NODE\":10",
            "\"ARG_OF_PERICENTER\":20",
            "\"MEAN_ANOMALY\":30",
            "\"EPHEMERIS_TYPE\":0",
            "\"CLASSIFICATION_TYPE\":\"U\"",
            "\"NORAD_CAT_ID\":\(number)",
            "\"ELEMENT_SET_NO\":7",
            "\"REV_AT_EPOCH\":99",
            "\"BSTAR\":0.0001",
            "\"MEAN_MOTION_DOT\":0.00001",
            "\"MEAN_MOTION_DDOT\":0",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func list(_ records: [String]) -> Data { Data(("[" + records.joined(separator: ",") + "]").utf8) }

    /// A record the engine skips (no epoch, no elements).
    private let unusable = "{}"

    // Real lines of the Minor Planet Center's comet file (copied from the engine's test data).
    private let haleBopp = "    CJ95O010  1997 03 29.0284  0.925995  0.994895  130.7313  281.8097   89.7335  20261017  -2.0  4.0  C/1995 O1 (Hale-Bopp)                                    MPC194091"
    private let halley = "0001P         2061 08  1.5218  0.570945  0.968030  112.1616   59.2610  162.1917  20261017   5.5  3.2  1P/Halley                                                MPC191592"
    private let encke = "0002P         2027 02 10.2276  0.338603  0.847319  187.2873  334.0197   11.3480  20261017  14.4  4.0  2P/Encke                                                 MPC xxxxx"
    private let ponsBrooks = "0012P         2024 04 21.2066  0.781920  0.954748  199.0355  255.8678   74.1469  20261017   5.0  6.0  12P/Pons-Brooks                                          MPEC 2026-TI5"

    private func cometData(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    private func message(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch let error as OnlineDataError {
            return error.message
        } catch {
            return "unexpected error: \(error)"
        }
    }

    private func forecastJSON(hours: Int) -> Data {
        let entries = (0..<hours).map { hour -> String in
            let stamp = hour < 10 ? "0\(hour)" : "\(hour)"
            return "{\"time\":\"2026-10-18T\(stamp):00:00Z\",\"data\":{\"instant\":{\"details\":{\"cloud_area_fraction\":\(hour * 10)}}}}"
        }
        return Data(("{\"geometry\":{\"coordinates\":[-96.8,32.8,150]},\"properties\":{\"meta\":{\"updated_at\":\"2026-10-18T00:30:00Z\"},"
            + "\"timeseries\":[\(entries.joined(separator: ","))]}}").utf8)
    }

    // MARK: Satellites

    func testStationsBecomeASatelliteGroup() throws {
        let parsed = try OnlineParsing.parse(.stations, data: list([omm(25544), omm(48274)]), now: now)
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.group, .stations)
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [25544, 48274])
        XCTAssertEqual(group.skippedCount, 0)
        XCTAssertEqual(group.newest?.epoch.timeIntervalSince1970 ?? 0, sampleEpoch, accuracy: 0.001)
    }

    func testEachSatelliteResourceKeepsItsOwnGroup() throws {
        let pairs: [(OnlineResource, ElementSetGroup)] = [(.stations, .stations), (.visual, .visual), (.starlink, .starlink)]
        for (resource, group) in pairs {
            let parsed = try OnlineParsing.parse(resource, data: list([omm(12345)]), now: now)
            guard case .satellites(let value) = parsed.value else { return XCTFail("expected satellites for \(resource)") }
            XCTAssertEqual(value.group, group, "\(resource)")
        }
    }

    func testTheDataEpochIsTheNewestEpochOfTheDownload() throws {
        let records = [omm(1, epoch: "2026-10-17T03:28:15"), omm(2, epoch: "2026-10-18T03:28:15"), omm(3, epoch: "2026-10-16T00:00:00")]
        let parsed = try OnlineParsing.parse(.visual, data: list(records), now: now)
        XCTAssertEqual(parsed.dataEpoch?.timeIntervalSince1970 ?? 0, sampleEpoch, accuracy: 0.001)
    }

    func testTheNewestElementSetOfAnObjectWins() throws {
        let records = [omm(1, epoch: "2026-10-17T03:28:15"), omm(2, epoch: "2026-10-17T03:28:15"), omm(1, epoch: "2026-10-18T03:28:15")]
        let parsed = try OnlineParsing.parse(.visual, data: list(records), now: now)
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [1, 2])
        XCTAssertEqual(group.satellites[0].elements.epoch.timeIntervalSince1970, sampleEpoch, accuracy: 0.001)
        XCTAssertEqual(group.satellites[1].elements.epoch.timeIntervalSince1970, sampleEpoch - 86_400, accuracy: 0.001)
    }

    func testElementSetsMoreThanADayInTheFutureAreDropped() throws {
        // `now` is 03:28:15 + 1 h on 18 October: the limit is 04:28:15 on 19 October.
        let records = [
            omm(1),
            omm(2, epoch: "2026-10-19T03:28:15"),  // 1 h inside the limit
            omm(3, epoch: "2026-10-19T05:00:00"),  // 32 min beyond it
            omm(4, epoch: "2026-10-30T00:00:00"),
        ]
        let parsed = try OnlineParsing.parse(.visual, data: list(records), now: now)
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [1, 2])
        // Dropped for the date, not skipped as unusable.
        XCTAssertEqual(group.skippedCount, 0)
        XCTAssertEqual(parsed.dataEpoch?.timeIntervalSince1970 ?? 0, sampleEpoch + 86_400, accuracy: 0.001)
    }

    func testADownloadOnlyFromTheFutureHasNothingUsable() {
        let text = message { _ = try OnlineParsing.parse(.visual, data: self.list([self.omm(1, epoch: "2026-10-30T00:00:00")]), now: self.now) }
        XCTAssertEqual(text, "No usable element sets.")
    }

    func testAnEmptyListHasNothingUsable() {
        XCTAssertEqual(message { _ = try OnlineParsing.parse(.stations, data: Data("[]".utf8), now: self.now) },
                       "No usable element sets.")
    }

    func testAFewUnusableRecordsAreCountedAndTolerated() throws {
        // One bad record next to one good one: as many bad as good is still accepted.
        let parsed = try OnlineParsing.parse(.visual, data: list([omm(1), unusable]), now: now)
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.satellites.count, 1)
        XCTAssertEqual(group.skippedCount, 1)
    }

    func testMoreUnusableRecordsThanUsableOnesIsRefused() {
        let text = message { _ = try OnlineParsing.parse(.visual, data: self.list([self.omm(1), self.unusable, self.unusable]), now: self.now) }
        XCTAssertEqual(text, "Too many unusable records.")
    }

    func testDataThatIsNotAnElementListIsRefused() {
        for bytes in [Data("not json".utf8), Data(), Data("42".utf8), Data("\"text\"".utf8), Data("[{".utf8)] {
            let text = message { _ = try OnlineParsing.parse(.stations, data: bytes, now: self.now) }
            XCTAssertEqual(text?.hasPrefix("Not a CelesTrak element list:"), true, String(decoding: bytes, as: UTF8.self))
        }
    }

    func testASingleObjectIsAcceptedLikeAList() throws {
        let parsed = try OnlineParsing.parse(.stations, data: Data(omm(25544).utf8), now: now)
        guard case .satellites(let group) = parsed.value else { return XCTFail("expected satellites") }
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [25544])
    }

    // MARK: Comets

    func testCometsAreParsedInFileOrder() throws {
        let parsed = try OnlineParsing.parse(.comets, data: cometData([haleBopp, halley, encke]), now: now)
        guard case .comets(let bodies) = parsed.value else { return XCTFail("expected comets") }
        XCTAssertEqual(bodies.map(\.id), ["comet.C/1995 O1", "comet.1P", "comet.2P"])
        XCTAssertEqual(bodies[0].name, "Hale-Bopp")
        XCTAssertNil(parsed.dataEpoch)
    }

    func testTheCometFileMayHaveBlankLinesAndWindowsLineEnds() throws {
        let text = [ponsBrooks, "", "   ", halley].joined(separator: "\r\n") + "\r\n"
        let bodies = try OnlineParsing.comets(Data(text.utf8))
        XCTAssertEqual(bodies.map(\.id), ["comet.12P", "comet.1P"])
    }

    func testBytesAboveASCIIAreReadAsLatin1WithoutFailing() throws {
        // One junk line is tolerated next to four comets, so the file as a whole is accepted.
        var data = cometData([haleBopp, halley, encke, ponsBrooks])
        data.append(contentsOf: [0x0A, 0xE9, 0xFF, 0x80])
        let bodies = try OnlineParsing.comets(data)
        XCTAssertEqual(bodies.count, 4)
    }

    func testAFileWithoutCometsIsRefused() {
        XCTAssertEqual(message { _ = try OnlineParsing.comets(Data()) }, "No comets in the file.")
        XCTAssertEqual(message { _ = try OnlineParsing.comets(Data("\n\n".utf8)) }, "No comets in the file.")
        XCTAssertEqual(message { _ = try OnlineParsing.comets(Data("<html>Service unavailable</html>".utf8)) },
                       "No comets in the file.")
    }

    func testTheShareOfRejectedLinesIsAQuarter() {
        XCTAssertEqual(OnlineParsing.maximumRejectedShare, 0.25, accuracy: 0.0)
    }

    func testOneRejectedLineAmongFourCometsIsTolerated() throws {
        let lines = [haleBopp, halley, encke, ponsBrooks, "this is not a comet line"]
        let bodies = try OnlineParsing.comets(cometData(lines))
        XCTAssertEqual(bodies.count, 4)
    }

    func testTwoRejectedLinesAmongFourCometsAreRefused() {
        let lines = [haleBopp, halley, encke, ponsBrooks, "this is not a comet line", "neither is this"]
        XCTAssertEqual(message { _ = try OnlineParsing.comets(self.cometData(lines)) },
                       "2 lines of the comet file were rejected.")
    }

    func testRepeatedCometsCountAsRejectedLines() {
        let lines = [haleBopp, halley, encke, ponsBrooks, haleBopp, halley]
        XCTAssertEqual(message { _ = try OnlineParsing.comets(self.cometData(lines)) },
                       "2 lines of the comet file were rejected.")
    }

    func testOneRepeatedCometAmongFourIsTolerated() throws {
        let bodies = try OnlineParsing.comets(cometData([haleBopp, halley, encke, ponsBrooks, haleBopp]))
        XCTAssertEqual(bodies.count, 4)
    }

    func testAOneCometFileToleratesNoRejectedLine() throws {
        XCTAssertEqual(try OnlineParsing.comets(cometData([haleBopp])).count, 1)
        let text = message { _ = try OnlineParsing.comets(self.cometData([self.haleBopp, "junk"])) }
        XCTAssertEqual(text?.contains("rejected"), true)
    }

    func testTheCometParseFunctionDoesNotNeedTheClock() throws {
        let early = try OnlineParsing.parse(.comets, data: cometData([haleBopp]), now: Date(timeIntervalSince1970: 0))
        let late = try OnlineParsing.parse(.comets, data: cometData([haleBopp]), now: Date(timeIntervalSince1970: 4_000_000_000))
        guard case .comets(let a) = early.value, case .comets(let b) = late.value else { return XCTFail("expected comets") }
        XCTAssertEqual(a, b)
    }

    // MARK: Forecast

    func testTheForecastIsParsedWithoutAnEpoch() throws {
        let parsed = try OnlineParsing.parse(.forecast, data: forecastJSON(hours: 8), now: now)
        guard case .forecast(let forecast) = parsed.value else { return XCTFail("expected a forecast") }
        XCTAssertEqual(forecast.hours.count, 8)
        XCTAssertEqual(forecast.hours[5].total, 50)
        XCTAssertEqual(forecast.key, "32.8,-96.8")
        XCTAssertNil(parsed.dataEpoch)
    }

    func testAForecastThatIsTooShortIsRefused() {
        XCTAssertEqual(message { _ = try OnlineParsing.parse(.forecast, data: self.forecastJSON(hours: 3), now: self.now) },
                       "Too few forecast times.")
    }

    func testTheWrongKindOfDataIsRefusedForEachResource() {
        let comets = cometData([haleBopp])
        XCTAssertNotNil(message { _ = try OnlineParsing.parse(.forecast, data: comets, now: self.now) })
        XCTAssertNotNil(message { _ = try OnlineParsing.parse(.stations, data: comets, now: self.now) })
        XCTAssertNotNil(message { _ = try OnlineParsing.parse(.comets, data: self.forecastJSON(hours: 8), now: self.now) })
        XCTAssertNotNil(message { _ = try OnlineParsing.parse(.visual, data: self.forecastJSON(hours: 8), now: self.now) })
    }

    // MARK: Values

    func testTheErrorKeepsItsMessage() {
        XCTAssertEqual(OnlineDataError("No luck").message, "No luck")
    }

    func testAParsedValueKeepsItsEpoch() {
        let epoch = Date(timeIntervalSince1970: 5)
        XCTAssertEqual(OnlineParsed(value: 1, dataEpoch: epoch).dataEpoch, epoch)
        XCTAssertNil(OnlineParsed(value: 1).dataEpoch)
    }
}

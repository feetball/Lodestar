import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Reading a downloaded CelesTrak group (`SatelliteGroup.parse`), what makes it fresh, and the library the pass lists are
/// built from (`SatelliteLibrary`, `PassSatellite`).
///
/// The element sets are CelesTrak OMM JSON records written here; the ISS record is the one of 2026-10-18 that the
/// LodestarKit tests use.
final class TonightSatelliteLibraryTests: XCTestCase {
    private let day = 86_400.0
    private let issNumber = 25_544
    private let tiangongNumber = 48_274

    private func instant(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: iso), iso)
    }

    /// One OMM record with the orbit of the ISS; only the name, number, epoch and mean anomaly vary.
    private func record(_ name: String, _ number: Int, epoch: String, meanAnomaly: Double = 82.2363) -> String {
        "{\"OBJECT_NAME\":\"\(name)\",\"OBJECT_ID\":\"1998-067A\",\"EPOCH\":\"\(epoch)\",\"MEAN_MOTION\":15.48918166,"
            + "\"ECCENTRICITY\":0.00067803,\"INCLINATION\":51.6328,\"RA_OF_ASC_NODE\":51.6259,"
            + "\"ARG_OF_PERICENTER\":277.7856,\"MEAN_ANOMALY\":\(meanAnomaly),\"EPHEMERIS_TYPE\":0,"
            + "\"CLASSIFICATION_TYPE\":\"U\",\"NORAD_CAT_ID\":\(number),\"ELEMENT_SET_NO\":999,\"REV_AT_EPOCH\":59081,"
            + "\"BSTAR\":0.00014456442,\"MEAN_MOTION_DOT\":7.503e-05,\"MEAN_MOTION_DDOT\":0}"
    }

    private func json(_ records: [String]) -> Data {
        Data("[\(records.joined(separator: ","))]".utf8)
    }

    private func parsed(_ group: ElementSetGroup, _ records: [String], now: String = "2026-10-25T00:00:00Z") throws
        -> SatelliteGroup {
        try SatelliteGroup.parse(group: group, data: json(records), now: try instant(now)).value
    }

    private func message(of error: Error) -> String? {
        (error as? OnlineDataError)?.message
    }

    // MARK: Reading a download

    func testADownloadBecomesAGroupOfSatellites() throws {
        let result = try SatelliteGroup.parse(
            group: .stations, data: json([record("ISS (ZARYA)", issNumber, epoch: "2026-10-18T03:28:15"),
                                          record("CSS (TIANHE)", tiangongNumber, epoch: "2026-10-18T06:02:02")]),
            now: try instant("2026-10-19T00:00:00Z"))
        let group = result.value
        XCTAssertEqual(group.group, .stations)
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [issNumber, tiangongNumber])
        XCTAssertEqual(group.satellites.map(\.name), ["ISS (ZARYA)", "CSS (TIANHE)"])
        XCTAssertEqual(group.skippedCount, 0)
    }

    func testTheNewestElementSetDecidesTheDataEpoch() throws {
        let result = try SatelliteGroup.parse(
            group: .visual, data: json([record("OLD", 90_001, epoch: "2026-10-17T00:00:00"),
                                        record("NEW", 90_002, epoch: "2026-10-19T12:00:00"),
                                        record("MIDDLE", 90_003, epoch: "2026-10-18T00:00:00")]),
            now: try instant("2026-10-20T00:00:00Z"))
        let expected = try instant("2026-10-19T12:00:00Z")
        XCTAssertEqual(result.value.newest?.catalogNumber, 90_002)
        XCTAssertEqual(try XCTUnwrap(result.value.newest).epoch.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(result.dataEpoch).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(result.dataEpoch, result.value.newest?.epoch)
    }

    func testAnObjectListedTwiceKeepsItsNewestElementSet() throws {
        let group = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-17T00:00:00", meanAnomaly: 10),
                                           record("ISS", issNumber, epoch: "2026-10-18T00:00:00", meanAnomaly: 20),
                                           record("ISS", issNumber, epoch: "2026-10-16T00:00:00", meanAnomaly: 30)])
        XCTAssertEqual(group.satellites.count, 1)
        XCTAssertEqual(group.satellites[0].elements.meanAnomaly, 20, accuracy: 1e-9)
    }

    func testElementSetsMoreThanADayInTheFutureAreDropped() throws {
        // A clock or data error: the epoch of FUTURE is a week after `now`.
        let group = try parsed(.visual, [record("NOW", 90_001, epoch: "2026-10-18T00:00:00"),
                                         record("FUTURE", 90_002, epoch: "2026-10-26T00:00:00")],
                               now: "2026-10-19T00:00:00Z")
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [90_001])
        XCTAssertEqual(group.newest?.catalogNumber, 90_001)
    }

    func testTheFutureToleranceIsOneDay() throws {
        // `now` is 2026-10-19T00:00:00Z: an epoch 23 hours later is kept, 25 hours later dropped.
        let group = try parsed(.visual, [record("KEPT", 90_001, epoch: "2026-10-19T23:00:00"),
                                         record("DROPPED", 90_002, epoch: "2026-10-20T01:00:00")],
                               now: "2026-10-19T00:00:00Z")
        XCTAssertEqual(group.satellites.map(\.catalogNumber), [90_001])
    }

    func testADownloadWhoseEveryElementSetIsInTheFutureHasNoUsableData() throws {
        XCTAssertThrowsError(try parsed(.visual, [record("FUTURE", 90_002, epoch: "2026-11-30T00:00:00")],
                                        now: "2026-10-19T00:00:00Z")) { error in
            XCTAssertEqual(self.message(of: error), "No usable element sets.")
        }
    }

    func testAnEmptyListHasNoUsableData() {
        XCTAssertThrowsError(try SatelliteGroup.parse(group: .stations, data: Data("[]".utf8), now: Date(timeIntervalSince1970: 1_792_324_800))) { error in
            XCTAssertEqual(self.message(of: error), "No usable element sets.")
        }
    }

    func testTextThatIsNotJSONIsRejectedAsNotAnElementList() {
        for text in ["", "hello", "<html>Forbidden</html>", "403"] {
            XCTAssertThrowsError(try SatelliteGroup.parse(group: .stations, data: Data(text.utf8), now: Date(timeIntervalSince1970: 1_792_324_800)), text) { error in
                XCTAssertTrue(self.message(of: error)?.hasPrefix("Not a CelesTrak element list: ") == true,
                              "\(text): \(String(describing: self.message(of: error)))")
            }
        }
    }

    func testAnEmptyDownloadSaysWhyItIsNotAnElementList() {
        XCTAssertThrowsError(try SatelliteGroup.parse(group: .stations, data: Data(), now: Date(timeIntervalSince1970: 1_792_324_800))) { error in
            XCTAssertEqual(self.message(of: error),
                           "Not a CelesTrak element list: The element sets are not valid JSON: the input is empty")
        }
    }

    func testAFewUnusableRecordsAreCountedAndTolerated() throws {
        let valid = record("ISS", issNumber, epoch: "2026-10-18T00:00:00")
        let result = try SatelliteGroup.parse(group: .stations, data: Data("[\(valid),5]".utf8),
                                              now: try instant("2026-10-19T00:00:00Z"))
        XCTAssertEqual(result.value.satellites.count, 1)
        XCTAssertEqual(result.value.skippedCount, 1)
    }

    func testRecordsMissingRequiredFieldsAreSkipped() throws {
        let valid = record("ISS", issNumber, epoch: "2026-10-18T00:00:00")
        let result = try SatelliteGroup.parse(group: .stations, data: Data("[\(valid),{\"OBJECT_NAME\":\"EMPTY\"}]".utf8),
                                              now: try instant("2026-10-19T00:00:00Z"))
        XCTAssertEqual(result.value.satellites.map(\.catalogNumber), [issNumber])
        XCTAssertEqual(result.value.skippedCount, 1)
    }

    func testMoreUnusableRecordsThanUsableOnesMeanTheFormatHasChanged() throws {
        let valid = record("ISS", issNumber, epoch: "2026-10-18T00:00:00")
        XCTAssertThrowsError(try SatelliteGroup.parse(group: .stations, data: Data("[\(valid),5,6]".utf8),
                                                      now: try instant("2026-10-19T00:00:00Z"))) { error in
            XCTAssertEqual(self.message(of: error), "Too many unusable records.")
        }
    }

    func testOnlyUnusableRecordsHaveNoUsableData() throws {
        XCTAssertThrowsError(try SatelliteGroup.parse(group: .stations, data: Data("[5,6,7]".utf8),
                                                      now: try instant("2026-10-19T00:00:00Z"))) { error in
            XCTAssertEqual(self.message(of: error), "No usable element sets.")
        }
    }

    // MARK: Freshness of a group

    func testAGroupIsFreshWhileItsNewestElementSetIsWithinTheLimitOfItsKind() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let epoch = try XCTUnwrap(stations.newest).epoch
        XCTAssertTrue(stations.isFresh(at: epoch))
        XCTAssertTrue(stations.isFresh(at: epoch.addingTimeInterval(3 * day - 60)))
        XCTAssertFalse(stations.isFresh(at: epoch.addingTimeInterval(3 * day + 60)))
        let visual = try parsed(.visual, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        XCTAssertTrue(visual.isFresh(at: epoch.addingTimeInterval(7 * day - 60)))
        XCTAssertFalse(visual.isFresh(at: epoch.addingTimeInterval(7 * day + 60)))
    }

    func testAGroupWithoutAnElementSetIsNeverFresh() {
        let empty = SatelliteGroup(group: .visual, satellites: [], newest: nil, skippedCount: 0)
        XCTAssertFalse(empty.isFresh(at: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(empty.isFresh(at: Date(timeIntervalSince1970: 1_792_324_800)))
    }

    func testAPassSatelliteIsJudgedByItsOwnElementSetAndTheLimitOfItsGroup() throws {
        let group = try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-18T00:00:00")])
        let satellite = try XCTUnwrap(group.satellites.first)
        let epoch = satellite.elements.epoch
        let strict = PassSatellite(satellite: satellite, group: .stations)
        let relaxed = PassSatellite(satellite: satellite, group: .visual)
        let fourDays = epoch.addingTimeInterval(4 * day)
        XCTAssertFalse(strict.isFresh(at: fourDays))
        XCTAssertTrue(relaxed.isFresh(at: fourDays))
    }

    // MARK: The library

    func testTheEmptyLibraryHasNoData() {
        let empty = SatelliteLibrary.empty
        XCTAssertNil(empty.stations)
        XCTAssertNil(empty.visual)
        XCTAssertNil(empty.starlink)
        XCTAssertEqual(empty.generation, 0)
        XCTAssertTrue(empty.passSatellites.isEmpty)
        XCTAssertFalse(empty.hasPassData)
    }

    func testTheBrightStationsAreTheISSAndTiangong() {
        XCTAssertEqual(SatelliteLibrary.issCatalogNumber, 25_544)
        XCTAssertEqual(SatelliteLibrary.tiangongCatalogNumber, 48_274)
    }

    func testAddingAGroupFillsItsSlotAndCountsTheChange() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let visual = try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-18T00:00:00")])
        let starlink = try parsed(.starlink, [record("STARLINK-1", 44_714, epoch: "2026-10-18T00:00:00")])

        let withStations = SatelliteLibrary.empty.with(stations)
        XCTAssertTrue(withStations.stations === stations)
        XCTAssertNil(withStations.visual)
        XCTAssertNil(withStations.starlink)
        XCTAssertEqual(withStations.generation, 1)

        let withVisual = withStations.with(visual)
        XCTAssertTrue(withVisual.stations === stations)
        XCTAssertTrue(withVisual.visual === visual)
        XCTAssertEqual(withVisual.generation, 2)

        let all = withVisual.with(starlink)
        XCTAssertTrue(all.starlink === starlink)
        XCTAssertEqual(all.generation, 3)

        // The libraries are values: adding a group does not change the one it started from.
        XCTAssertNil(withStations.visual)
        XCTAssertEqual(withStations.generation, 1)
    }

    func testANewDownloadOfAGroupReplacesTheOldOne() throws {
        let first = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-17T00:00:00")])
        let second = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let library = SatelliteLibrary.empty.with(first).with(second)
        XCTAssertTrue(library.stations === second)
        XCTAssertEqual(library.generation, 2)
    }

    func testRemovingTheSatelliteFeedClearsTheStationsAndTheVisualGroupOnly() throws {
        let library = SatelliteLibrary.empty
            .with(try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")]))
            .with(try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-18T00:00:00")]))
            .with(try parsed(.starlink, [record("STARLINK-1", 44_714, epoch: "2026-10-18T00:00:00")]))
        let without = library.without(.satellites)
        XCTAssertNil(without.stations)
        XCTAssertNil(without.visual)
        XCTAssertTrue(without.starlink === library.starlink)
        XCTAssertEqual(without.generation, library.generation + 1)
        XCTAssertTrue(without.passSatellites.isEmpty)
        XCTAssertFalse(without.hasPassData)
    }

    func testRemovingTheStarlinkFeedClearsOnlyStarlink() throws {
        let library = SatelliteLibrary.empty
            .with(try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")]))
            .with(try parsed(.starlink, [record("STARLINK-1", 44_714, epoch: "2026-10-18T00:00:00")]))
        let without = library.without(.starlink)
        XCTAssertNil(without.starlink)
        XCTAssertTrue(without.stations === library.stations)
        XCTAssertEqual(without.generation, library.generation + 1)
        XCTAssertEqual(without.passSatellites.map(\.satellite.catalogNumber), [issNumber])
    }

    func testRemovingAnotherFeedChangesNothing() throws {
        let library = SatelliteLibrary.empty
            .with(try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")]))
        for feed in [OnlineFeed.comets, .clouds] {
            let same = library.without(feed)
            XCTAssertTrue(same.stations === library.stations, "\(feed)")
            XCTAssertEqual(same.generation, library.generation, "\(feed)")
        }
    }

    // MARK: Which satellites the pass lists use

    func testTheStationGroupContributesOnlyTheISSAndTiangong() throws {
        let stations = try parsed(.stations, [
            record("POISK", 36_086, epoch: "2026-10-18T00:00:00"),
            record("CSS (TIANHE)", tiangongNumber, epoch: "2026-10-18T00:00:00"),
            record("ISS (ZARYA)", issNumber, epoch: "2026-10-18T00:00:00"),
            record("ISS (NAUKA)", 49_044, epoch: "2026-10-18T00:00:00"),
        ])
        let library = SatelliteLibrary.empty.with(stations)
        XCTAssertEqual(library.passSatellites.map(\.satellite.catalogNumber), [issNumber, tiangongNumber])
        XCTAssertTrue(library.hasPassData)
        XCTAssertEqual(library.passSatellites.map(\.group), [.stations, .stations])
    }

    func testTheVisualGroupContributesEverySatelliteInItsOrder() throws {
        let visual = try parsed(.visual, [
            record("HST", 20_580, epoch: "2026-10-18T00:00:00"),
            record("ROCKET BODY", 90_001, epoch: "2026-10-18T00:00:00"),
            record("COSMOS", 90_002, epoch: "2026-10-18T00:00:00"),
        ])
        let library = SatelliteLibrary.empty.with(visual)
        XCTAssertEqual(library.passSatellites.map(\.satellite.catalogNumber), [20_580, 90_001, 90_002])
        XCTAssertEqual(library.passSatellites.map(\.group), [.visual, .visual, .visual])
    }

    func testTheISSComesFirstWhereverItIsListed() throws {
        let visual = try parsed(.visual, [
            record("HST", 20_580, epoch: "2026-10-18T00:00:00"),
            record("ISS (ZARYA)", issNumber, epoch: "2026-10-18T00:00:00"),
            record("COSMOS", 90_002, epoch: "2026-10-18T00:00:00"),
        ])
        XCTAssertEqual(SatelliteLibrary.empty.with(visual).passSatellites.map(\.satellite.catalogNumber),
                       [issNumber, 20_580, 90_002])
    }

    func testTheISSAndTiangongAreJudgedByTheStationLimitWhicheverDownloadTheyCameWith() throws {
        let visual = try parsed(.visual, [
            record("ISS (ZARYA)", issNumber, epoch: "2026-10-18T00:00:00"),
            record("CSS (TIANHE)", tiangongNumber, epoch: "2026-10-18T00:00:00"),
            record("HST", 20_580, epoch: "2026-10-18T00:00:00"),
        ])
        let library = SatelliteLibrary.empty.with(visual)
        let groups = Dictionary(uniqueKeysWithValues: library.passSatellites.map { ($0.satellite.catalogNumber, $0.group) })
        XCTAssertEqual(groups[issNumber], .stations)
        XCTAssertEqual(groups[tiangongNumber], .stations)
        XCTAssertEqual(groups[20_580], .visual)
    }

    func testASatelliteInBothGroupsIsListedOnceWithTheNewerElementSet() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00", meanAnomaly: 10),
                                              record("CSS", tiangongNumber, epoch: "2026-10-18T00:00:00")])
        let visual = try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-18T00:00:00"),
                                          record("ISS", issNumber, epoch: "2026-10-19T00:00:00", meanAnomaly: 20)])
        let library = SatelliteLibrary.empty.with(stations).with(visual)
        XCTAssertEqual(library.passSatellites.map(\.satellite.catalogNumber), [issNumber, tiangongNumber, 20_580])
        let iss = try XCTUnwrap(library.passSatellites.first)
        XCTAssertEqual(iss.satellite.elements.meanAnomaly, 20, accuracy: 1e-9, "the visual download is newer")
        XCTAssertEqual(iss.group, .stations)
    }

    func testAnOlderSecondDownloadDoesNotReplaceANewerElementSet() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-19T00:00:00", meanAnomaly: 10)])
        let visual = try parsed(.visual, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00", meanAnomaly: 20)])
        let library = SatelliteLibrary.empty.with(visual).with(stations)
        let iss = try XCTUnwrap(library.passSatellites.first)
        XCTAssertEqual(library.passSatellites.count, 1)
        XCTAssertEqual(iss.satellite.elements.meanAnomaly, 10, accuracy: 1e-9)
    }

    func testWithEqualEpochsTheStationDownloadIsKept() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00", meanAnomaly: 10)])
        let visual = try parsed(.visual, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00", meanAnomaly: 20)])
        let library = SatelliteLibrary.empty.with(visual).with(stations)
        XCTAssertEqual(try XCTUnwrap(library.passSatellites.first).satellite.elements.meanAnomaly, 10, accuracy: 1e-9)
    }

    func testStarlinkIsNotPartOfThePassLists() throws {
        let library = SatelliteLibrary.empty.with(try parsed(.starlink, [record("STARLINK-1", 44_714, epoch: "2026-10-18T00:00:00")]))
        XCTAssertTrue(library.passSatellites.isEmpty)
        XCTAssertFalse(library.hasPassData)
    }

    // MARK: Stale data

    func testNothingIsStaleWithoutData() throws {
        XCTAssertFalse(SatelliteLibrary.empty.isPassDataStale(at: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(SatelliteLibrary.empty.isPassDataStale(at: try instant("2030-01-01T00:00:00Z")))
    }

    func testStationDataGoesStaleAfterThreeDays() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let library = SatelliteLibrary.empty.with(stations)
        let epoch = try XCTUnwrap(stations.newest).epoch
        XCTAssertFalse(library.isPassDataStale(at: epoch))
        XCTAssertFalse(library.isPassDataStale(at: epoch.addingTimeInterval(3 * day - 60)))
        XCTAssertTrue(library.isPassDataStale(at: epoch.addingTimeInterval(3 * day + 60)))
    }

    func testVisualDataGoesStaleAfterSevenDays() throws {
        let visual = try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-18T00:00:00")])
        let library = SatelliteLibrary.empty.with(visual)
        let epoch = try XCTUnwrap(visual.newest).epoch
        XCTAssertFalse(library.isPassDataStale(at: epoch.addingTimeInterval(7 * day - 60)))
        XCTAssertTrue(library.isPassDataStale(at: epoch.addingTimeInterval(7 * day + 60)))
    }

    func testOneStaleGroupMakesThePassDataStale() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let visual = try parsed(.visual, [record("HST", 20_580, epoch: "2026-10-08T00:00:00")])
        let library = SatelliteLibrary.empty.with(stations).with(visual)
        // On 19 October the stations are a day old, but the visual group is eleven days old.
        let at = try instant("2026-10-19T00:00:00Z")
        XCTAssertTrue(stations.isFresh(at: at))
        XCTAssertFalse(visual.isFresh(at: at))
        XCTAssertTrue(library.isPassDataStale(at: at))
    }

    func testStarlinkDoesNotMakeThePassDataStale() throws {
        let stations = try parsed(.stations, [record("ISS", issNumber, epoch: "2026-10-18T00:00:00")])
        let starlink = try parsed(.starlink, [record("STARLINK-1", 44_714, epoch: "2026-09-01T00:00:00")])
        let library = SatelliteLibrary.empty.with(stations).with(starlink)
        let at = try XCTUnwrap(stations.newest).epoch.addingTimeInterval(1 * day)
        XCTAssertFalse(starlink.isFresh(at: at))
        XCTAssertFalse(library.isPassDataStale(at: at))
    }
}

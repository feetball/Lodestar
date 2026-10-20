import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// Finding and selecting the passes the screens show (`SatellitePasses`).
///
/// The search runs on a small library built here: the ISS element set of 2026-10-18 (the one the LodestarKit tests use, for
/// which Boulder has four visible passes in the three days after 04:00 UTC) and a second satellite on the same orbit but a
/// different place along it. The selection functions are tried on hand-made passes.
final class TonightSatellitePassesTests: XCTestCase {
    private let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.2705, elevation: 1655))
    /// 2026-10-18T04:00:00Z.
    private let start = Date(timeIntervalSince1970: 1_792_296_000)
    private let threeDays = 3 * 86_400.0

    private func instant(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: iso), iso)
    }

    private func record(_ name: String, _ number: Int, meanAnomaly: Double) -> String {
        "{\"OBJECT_NAME\":\"\(name)\",\"OBJECT_ID\":\"1998-067A\",\"EPOCH\":\"2026-10-18T03:28:15.076416\","
            + "\"MEAN_MOTION\":15.48918166,\"ECCENTRICITY\":0.00067803,\"INCLINATION\":51.6328,"
            + "\"RA_OF_ASC_NODE\":51.6259,\"ARG_OF_PERICENTER\":277.7856,\"MEAN_ANOMALY\":\(meanAnomaly),"
            + "\"EPHEMERIS_TYPE\":0,\"CLASSIFICATION_TYPE\":\"U\",\"NORAD_CAT_ID\":\(number),\"ELEMENT_SET_NO\":999,"
            + "\"REV_AT_EPOCH\":59081,\"BSTAR\":0.00014456442,\"MEAN_MOTION_DOT\":7.503e-05,\"MEAN_MOTION_DDOT\":0}"
    }

    private func group(_ group: ElementSetGroup, _ records: [String]) throws -> SatelliteGroup {
        try SatelliteGroup.parse(group: group, data: Data("[\(records.joined(separator: ","))]".utf8),
                                 now: try instant("2026-10-19T00:00:00Z")).value
    }

    private func issLibrary() throws -> SatelliteLibrary {
        SatelliteLibrary.empty.with(try group(.stations, [record("ISS (ZARYA)", 25_544, meanAnomaly: 82.2363)]))
    }

    private func twoSatelliteLibrary() throws -> SatelliteLibrary {
        try issLibrary().with(try group(.visual, [record("SECOND", 90_001, meanAnomaly: 200)]))
    }

    private func station() throws -> Satellite {
        let elements = try ElementSetParser.parseTwoLine(
            line1: "1 25544U 98067A   26291.14461894  .00007503  00000+0  14456-3 0  9994",
            line2: "2 25544  51.6328  51.6259 0006780 277.7856  82.2363 15.48918166590814", name: "ISS (ZARYA)")
        return Satellite(elements: elements)
    }

    private func other(_ number: Int) throws -> Satellite {
        let elements = try OrbitalElements(
            name: "SAT \(number)", catalogNumber: number, epoch: Date(timeIntervalSince1970: 1_792_294_095),
            meanMotion: 15.5, eccentricity: 0.001, inclination: 51.6, rightAscensionOfAscendingNode: 50,
            argumentOfPericenter: 100, meanAnomaly: 10)
        return Satellite(elements: elements)
    }

    private func point(_ seconds: Double, altitude: Double = 30) -> SatellitePassPoint {
        SatellitePassPoint(date: Date(timeIntervalSince1970: seconds), azimuth: 100, altitude: altitude,
                           rangeKilometers: 600, isSunlit: true, magnitude: nil)
    }

    /// A pass whose visible part runs from `from` to `to` (seconds since 1970).
    private func item(_ satellite: Satellite, from: Double, to: Double) -> SatellitePassItem {
        let culmination = point((from + to) / 2)
        let pass = SatellitePass(
            rise: point(from - 60, altitude: 10), culmination: culmination, set: point(to + 60, altitude: 10),
            visibleIntervals: [DateInterval(start: Date(timeIntervalSince1970: from),
                                            end: Date(timeIntervalSince1970: to))],
            brightest: nil, isRiseCut: false, isSetCut: false)
        return SatellitePassItem(satellite: satellite, group: .stations, pass: pass, peak: culmination)
    }

    // MARK: The search

    func testThePassesScreenLooksThreeDaysAhead() {
        XCTAssertEqual(SatellitePasses.horizonDays, 3)
    }

    func testAnEmptyLibraryHasNoPasses() {
        XCTAssertTrue(SatellitePasses.compute(library: .empty, observer: boulder, start: start).isEmpty)
    }

    func testTheISSHasSeveralVisiblePassesInThreeDays() throws {
        let items = SatellitePasses.compute(library: try issLibrary(), observer: boulder, start: start)
        // The LodestarKit tests find four visible passes of this element set from 04:00 UTC.
        XCTAssertGreaterThanOrEqual(items.count, 4)
        XCTAssertLessThanOrEqual(items.count, 12)
        for item in items {
            XCTAssertTrue(item.isISS)
            XCTAssertEqual(item.name, "ISS")
            XCTAssertEqual(item.group, .stations)
            XCTAssertEqual(item.satellite.catalogNumber, 25_544)
        }
    }

    func testEveryPassIsVisibleAndNotOverAtTheStart() throws {
        let items = SatellitePasses.compute(library: try issLibrary(), observer: boulder, start: start)
        for item in items {
            XCTAssertTrue(item.pass.isVisible, item.id)
            XCTAssertGreaterThan(item.end, start, item.id)
            XCTAssertLessThanOrEqual(item.start, item.end, item.id)
            // Passes under way at the start are found whole, from up to an hour earlier.
            XCTAssertGreaterThanOrEqual(item.pass.rise.date, start.addingTimeInterval(-3_601), item.id)
            XCTAssertLessThanOrEqual(item.start, start.addingTimeInterval(threeDays), item.id)
            for part in item.pass.visibleIntervals {
                XCTAssertGreaterThanOrEqual(part.start, item.pass.rise.date, item.id)
                XCTAssertLessThanOrEqual(part.end, item.pass.set.date, item.id)
            }
        }
    }

    func testThePassesAreInTheOrderTheyBecomeVisible() throws {
        let items = SatellitePasses.compute(library: try twoSatelliteLibrary(), observer: boulder, start: start)
        XCTAssertFalse(items.isEmpty)
        for (earlier, later) in zip(items, items.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.start, later.start)
        }
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "no pass is listed twice")
    }

    func testTheSecondSatelliteIsListedUnderItsOwnGroupAndName() throws {
        let items = SatellitePasses.compute(library: try twoSatelliteLibrary(), observer: boulder, start: start)
        let others = items.filter { !$0.isISS }
        XCTAssertFalse(items.filter(\.isISS).isEmpty)
        for item in others {
            XCTAssertEqual(item.satellite.catalogNumber, 90_001)
            XCTAssertEqual(item.name, "SECOND")
            XCTAssertEqual(item.group, .visual)
        }
    }

    func testAPassThatIsOverAtTheStartIsLeftOut() throws {
        let library = try issLibrary()
        let first = try XCTUnwrap(SatellitePasses.compute(library: library, observer: boulder, start: start).first)
        let later = first.end.addingTimeInterval(1)
        let items = SatellitePasses.compute(library: library, observer: boulder, start: later)
        XCTAssertTrue(items.allSatisfy { $0.end > later })
        XCTAssertFalse(items.contains { abs($0.start.timeIntervalSince(first.start)) < 5 })
    }

    func testStartingLaterKeepsTheLaterPassesWhole() throws {
        let library = try issLibrary()
        let all = SatellitePasses.compute(library: library, observer: boulder, start: start)
        let second = try XCTUnwrap(all.dropFirst().first)
        // Start in the middle of the second pass: it is still listed, with its whole visible part.
        let middle = second.start.addingTimeInterval(second.end.timeIntervalSince(second.start) / 2)
        let items = SatellitePasses.compute(library: library, observer: boulder, start: middle)
        let same = try XCTUnwrap(items.first { abs($0.start.timeIntervalSince(second.start)) < 5 })
        XCTAssertEqual(same.start.timeIntervalSince(second.start), 0, accuracy: 1)
        XCTAssertEqual(same.end.timeIntervalSince(second.end), 0, accuracy: 1)
        XCTAssertFalse(items.contains { abs($0.start.timeIntervalSince(all[0].start)) < 5 })
    }

    func testTheSearchGivesTheSameAnswerTwice() throws {
        let library = try issLibrary()
        let first = SatellitePasses.compute(library: library, observer: boulder, start: start)
        let again = SatellitePasses.compute(library: library, observer: boulder, start: start)
        XCTAssertEqual(first.map(\.id), again.map(\.id))
        XCTAssertEqual(first.map(\.start), again.map(\.start))
    }

    // MARK: The highest visible point

    func testThePeakOfAPassIsInsideItsVisiblePart() throws {
        let items = SatellitePasses.compute(library: try issLibrary(), observer: boulder, start: start)
        for item in items {
            let culmination = item.pass.culmination
            let inside = item.pass.visibleIntervals.contains { $0.start <= culmination.date && culmination.date <= $0.end }
            if inside {
                XCTAssertEqual(item.peak, culmination, item.id)
            } else {
                // The satellite entered the Earth's shadow, or the sky was still bright, before it got there: the peak
                // is the end of a visible part, the one nearer the culmination.
                XCTAssertTrue(item.pass.visibleIntervals.contains { $0.start == item.peak.date || $0.end == item.peak.date },
                              item.id)
            }
            XCTAssertGreaterThanOrEqual(item.peak.date, item.start, item.id)
            XCTAssertLessThanOrEqual(item.peak.date, item.end, item.id)
            XCTAssertGreaterThanOrEqual(item.peak.altitude, 9.9, item.id)
            XCTAssertLessThanOrEqual(item.peak.altitude, culmination.altitude + 1e-3, item.id)
        }
    }

    /// A pass of the ISS around 2026-10-18T12:00:00Z with the visible parts and culmination given as seconds from there.
    private func syntheticPass(culmination: Double, parts: [(Double, Double)]) -> SatellitePass {
        let base = 1_792_324_800.0
        let point = SatellitePassPoint(date: Date(timeIntervalSince1970: base + culmination), azimuth: 100, altitude: 55,
                                       rangeKilometers: 500, isSunlit: true, magnitude: -3)
        return SatellitePass(
            rise: SatellitePassPoint(date: Date(timeIntervalSince1970: base - 1_000), azimuth: 200, altitude: 10,
                                     rangeKilometers: 1_500, isSunlit: true, magnitude: nil),
            culmination: point,
            set: SatellitePassPoint(date: Date(timeIntervalSince1970: base + 1_000), azimuth: 20, altitude: 10,
                                    rangeKilometers: 1_500, isSunlit: true, magnitude: nil),
            visibleIntervals: parts.map { DateInterval(start: Date(timeIntervalSince1970: base + $0.0),
                                                       end: Date(timeIntervalSince1970: base + $0.1)) },
            brightest: nil, isRiseCut: false, isSetCut: false)
    }

    func testAVisiblePartHoldingTheCulminationGivesTheCulmination() throws {
        let pass = syntheticPass(culmination: 100, parts: [(0, 300)])
        XCTAssertEqual(SatellitePasses.visiblePeak(of: pass, satellite: try station(), observer: boulder), pass.culmination)
    }

    func testTheEdgesOfAVisiblePartHoldTheCulmination() throws {
        let satellite = try station()
        let atStart = syntheticPass(culmination: 0, parts: [(0, 300)])
        let atEnd = syntheticPass(culmination: 300, parts: [(0, 300)])
        XCTAssertEqual(SatellitePasses.visiblePeak(of: atStart, satellite: satellite, observer: boulder), atStart.culmination)
        XCTAssertEqual(SatellitePasses.visiblePeak(of: atEnd, satellite: satellite, observer: boulder), atEnd.culmination)
    }

    func testWhenTheShadowCutsThePassShortThePeakIsTheEndNearestTheCulmination() throws {
        let satellite = try station()
        // The visible part ends 60 seconds before the culmination.
        let pass = syntheticPass(culmination: 400, parts: [(0, 340)])
        let peak = SatellitePasses.visiblePeak(of: pass, satellite: satellite, observer: boulder)
        let end = Date(timeIntervalSince1970: 1_792_324_800 + 340)
        let look = try XCTUnwrap(satellite.look(at: end, observer: boulder))
        XCTAssertEqual(peak.date, end)
        XCTAssertEqual(peak.altitude, look.altitude)
        XCTAssertEqual(peak.azimuth, look.azimuth)
        XCTAssertEqual(peak.rangeKilometers, look.rangeKilometers)
        XCTAssertEqual(peak.isSunlit, look.isSunlit)
        XCTAssertEqual(peak.magnitude, look.magnitude)
    }

    func testWhenThePassBecomesVisibleOnlyAfterTheCulminationThePeakIsTheStartOfTheVisiblePart() throws {
        let satellite = try station()
        let pass = syntheticPass(culmination: -50, parts: [(100, 400)])
        let peak = SatellitePasses.visiblePeak(of: pass, satellite: satellite, observer: boulder)
        let begin = Date(timeIntervalSince1970: 1_792_324_800 + 100)
        let look = try XCTUnwrap(satellite.look(at: begin, observer: boulder))
        XCTAssertEqual(peak.date, begin)
        XCTAssertEqual(peak.altitude, look.altitude)
    }

    func testOfTwoVisiblePartsTheHigherEndWins() throws {
        let satellite = try station()
        // Culmination at 500: the first part ends at 300 and the second begins at 700.
        let pass = syntheticPass(culmination: 500, parts: [(0, 300), (700, 900)])
        let peak = SatellitePasses.visiblePeak(of: pass, satellite: satellite, observer: boulder)
        let base = 1_792_324_800.0
        let before = try XCTUnwrap(satellite.look(at: Date(timeIntervalSince1970: base + 300), observer: boulder))
        let after = try XCTUnwrap(satellite.look(at: Date(timeIntervalSince1970: base + 700), observer: boulder))
        if after.altitude > before.altitude {
            XCTAssertEqual(peak.date, Date(timeIntervalSince1970: base + 700))
            XCTAssertEqual(peak.altitude, after.altitude)
        } else {
            XCTAssertEqual(peak.date, Date(timeIntervalSince1970: base + 300))
            XCTAssertEqual(peak.altitude, before.altitude)
        }
    }

    func testAPassWithoutAVisiblePartPeaksAtItsCulmination() throws {
        let pass = syntheticPass(culmination: 100, parts: [])
        XCTAssertEqual(SatellitePasses.visiblePeak(of: pass, satellite: try station(), observer: boulder), pass.culmination)
    }

    func testIfTheOrbitCannotBeComputedAtTheEdgeOfTheVisiblePartThePeakIsTheCulmination() throws {
        let satellite = try station()
        let farSeconds = 2_840_140_800.0 // 2060-01-01
        try XCTSkipUnless(satellite.look(at: Date(timeIntervalSince1970: farSeconds + 340), observer: boulder) == nil,
                          "SGP4 still propagates this element set 34 years from its epoch")
        let pass = SatellitePass(
            rise: point(farSeconds - 1_000, altitude: 10), culmination: point(farSeconds + 400),
            set: point(farSeconds + 1_000, altitude: 10),
            visibleIntervals: [DateInterval(start: Date(timeIntervalSince1970: farSeconds),
                                            end: Date(timeIntervalSince1970: farSeconds + 340))],
            brightest: nil, isRiseCut: false, isSetCut: false)
        XCTAssertEqual(SatellitePasses.visiblePeak(of: pass, satellite: satellite, observer: boulder), pass.culmination)
    }

    // MARK: Selecting

    func testTheISSFilterKeepsOnlyTheStationInTheOrderGiven() throws {
        let iss = try station()
        let second = try other(90_001)
        let items = [item(second, from: 100, to: 200), item(iss, from: 400, to: 500), item(second, from: 600, to: 700),
                     item(iss, from: 50, to: 90)]
        XCTAssertEqual(SatellitePasses.filtered(items, filter: .iss).map(\.id), [items[1].id, items[3].id])
    }

    func testTheBrightFilterKeepsEverything() throws {
        let items = [item(try other(90_001), from: 100, to: 200), item(try station(), from: 400, to: 500)]
        XCTAssertEqual(SatellitePasses.filtered(items, filter: .bright).map(\.id), items.map(\.id))
        XCTAssertTrue(SatellitePasses.filtered([], filter: .iss).isEmpty)
    }

    func testUpcomingPassesAreThoseThatAreNotOver() throws {
        let satellite = try station()
        let items = [item(satellite, from: 100, to: 200), item(satellite, from: 300, to: 400),
                     item(satellite, from: 500, to: 600)]
        let now = Date(timeIntervalSince1970: 350)
        XCTAssertEqual(SatellitePasses.upcoming(items, now: now).map(\.id), [items[1].id, items[2].id])
    }

    func testAPassEndingExactlyNowIsOver() throws {
        let items = [item(try station(), from: 100, to: 200)]
        XCTAssertEqual(SatellitePasses.upcoming(items, now: Date(timeIntervalSince1970: 199.999)).count, 1)
        XCTAssertTrue(SatellitePasses.upcoming(items, now: Date(timeIntervalSince1970: 200)).isEmpty)
    }

    private func night(_ from: Double, _ to: Double) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: from), end: Date(timeIntervalSince1970: to))
    }

    func testTonightKeepsThePassesOfTheNightTheISSFirstThenTheOthersInTimeOrder() throws {
        let iss = try station()
        let second = try other(90_001)
        let a = item(iss, from: 1_000, to: 1_100)
        let b = item(second, from: 900, to: 1_000)
        let c = item(iss, from: 2_000, to: 2_100)
        let d = item(second, from: 500, to: 600)  // before the night
        let e = item(second, from: 3_000, to: 3_100)  // after the night
        let result = SatellitePasses.tonight([e, c, b, d, a], night: night(800, 2_500),
                                             now: Date(timeIntervalSince1970: 0), limit: 10)
        XCTAssertEqual(result.map(\.id), [a.id, c.id, b.id])
    }

    func testTonightSortsEachGroupByTheStartOfItsVisiblePart() throws {
        let second = try other(90_001)
        let third = try other(90_002)
        let late = item(second, from: 1_500, to: 1_600)
        let early = item(third, from: 900, to: 1_000)
        let middle = item(second, from: 1_200, to: 1_300)
        let result = SatellitePasses.tonight([late, early, middle], night: night(800, 2_500),
                                             now: Date(timeIntervalSince1970: 0), limit: 10)
        XCTAssertEqual(result.map(\.id), [early.id, middle.id, late.id])
    }

    func testTonightHasAtMostTheLimitOfPassesAndTheISSKeepsItsPlace() throws {
        let iss = try station()
        let second = try other(90_001)
        let items = [item(second, from: 900, to: 1_000), item(iss, from: 1_000, to: 1_100),
                     item(iss, from: 2_000, to: 2_100)]
        let two = SatellitePasses.tonight(items, night: night(800, 2_500), now: Date(timeIntervalSince1970: 0), limit: 2)
        XCTAssertEqual(two.map(\.id), [items[1].id, items[2].id])
        let one = SatellitePasses.tonight(items, night: night(800, 2_500), now: Date(timeIntervalSince1970: 0), limit: 1)
        XCTAssertEqual(one.map(\.id), [items[1].id])
        XCTAssertTrue(SatellitePasses.tonight(items, night: night(800, 2_500), now: Date(timeIntervalSince1970: 0),
                                              limit: 0).isEmpty)
    }

    func testTonightLeavesOutPassesThatAreOver() throws {
        let iss = try station()
        let items = [item(iss, from: 1_000, to: 1_100), item(iss, from: 2_000, to: 2_100)]
        let during = SatellitePasses.tonight(items, night: night(800, 2_500), now: Date(timeIntervalSince1970: 1_050), limit: 10)
        XCTAssertEqual(during.map(\.id), [items[0].id, items[1].id])
        let after = SatellitePasses.tonight(items, night: night(800, 2_500), now: Date(timeIntervalSince1970: 1_100), limit: 10)
        XCTAssertEqual(after.map(\.id), [items[1].id])
    }

    func testTonightNeedsAnOverlapWithTheNightNotJustAContact() throws {
        let iss = try station()
        let endsAsTheNightStarts = item(iss, from: 700, to: 800)
        let startsAsTheNightEnds = item(iss, from: 2_500, to: 2_600)
        let straddlesTheStart = item(iss, from: 750, to: 850)
        let straddlesTheEnd = item(iss, from: 2_450, to: 2_550)
        let result = SatellitePasses.tonight(
            [endsAsTheNightStarts, startsAsTheNightEnds, straddlesTheStart, straddlesTheEnd], night: night(800, 2_500),
            now: Date(timeIntervalSince1970: 0), limit: 10)
        XCTAssertEqual(result.map(\.id), [straddlesTheStart.id, straddlesTheEnd.id])
    }

    func testTonightWithNoPassesIsEmpty() {
        XCTAssertTrue(SatellitePasses.tonight([], night: night(0, 100), now: Date(timeIntervalSince1970: 0), limit: 5).isEmpty)
    }
}

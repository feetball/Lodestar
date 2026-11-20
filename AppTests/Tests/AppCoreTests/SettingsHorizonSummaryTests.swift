import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The words for the skyline that applies at a site (`HorizonText.summary`, `applied`, `spokenName` and the status of a site that
/// has a terrain horizon only).
final class SettingsHorizonSummaryTests: XCTestCase {
    private let dot = "\u{00B7}"
    private let ridge = HorizonProfile.constant(14)
    private let hills = HorizonProfile.constant(9)

    func testNothingIsAnOpenHorizon() {
        XCTAssertEqual(HorizonText.summary(of: .open, coverage: nil), "Open horizon")
        XCTAssertEqual(HorizonText.summary(of: .open, coverage: 0.5), "Open horizon")
        let flat = ResolvedHorizon(profile: .constant(0), source: .recorded)
        XCTAssertEqual(HorizonText.summary(of: flat, coverage: nil), "Open horizon")
    }

    func testARecordedSkylineSaysHowMuchWasCovered() {
        let resolved = ResolvedHorizon(profile: ridge, source: .recorded)
        XCTAssertEqual(HorizonText.summary(of: resolved, coverage: 0.86),
                       "Recorded \(dot) \(AppFormat.percent(0.86)) covered \(dot) highest 14\u{00B0} all round")
        XCTAssertEqual(HorizonText.summary(of: resolved, coverage: nil), "Recorded \(dot) highest 14\u{00B0} all round")
    }

    func testTheTerrainHorizonHasNoCoverage() {
        let resolved = ResolvedHorizon(profile: hills, source: .terrain)
        XCTAssertEqual(HorizonText.summary(of: resolved, coverage: 0.5), "Terrain horizon \(dot) highest 9\u{00B0} all round")
    }

    func testRecordedAndTerrainSaysWhatBothContribute() {
        let resolved = ResolvedHorizon(profile: ridge, source: .recordedAndTerrain)
        XCTAssertEqual(HorizonText.summary(of: resolved, coverage: 0.4),
                       "Recorded + terrain \(dot) \(AppFormat.percent(0.4)) covered \(dot) highest 14\u{00B0} all round")
    }

    func testTheNotesSayWhichSkylineWasApplied() {
        XCTAssertEqual(HorizonText.applied(.recorded), "Recorded skyline applied")
        XCTAssertEqual(HorizonText.applied(.terrain), "Terrain horizon applied")
        XCTAssertEqual(HorizonText.applied(.recordedAndTerrain), "Recorded + terrain applied")
        XCTAssertEqual(HorizonText.applied(nil), "Skyline applied")
    }

    func testTheSpokenNames() {
        XCTAssertEqual(HorizonText.spokenName(.recorded), "recorded skyline")
        XCTAssertEqual(HorizonText.spokenName(nil), "recorded skyline")
        XCTAssertEqual(HorizonText.spokenName(.terrain), "terrain horizon")
        XCTAssertEqual(HorizonText.spokenName(.recordedAndTerrain), "recorded and terrain skyline")
    }

    func testASiteWithOnlyATerrainHorizonHasNoRecordedSkyline() throws {
        let site = try XCTUnwrap(SavedSite(name: "Hills", latitude: 10, longitude: 20, terrainHorizon: hills))
        XCTAssertEqual(HorizonText.status(of: site), HorizonText.noRecordedSkyline)
        XCTAssertEqual(HorizonText.noRecordedSkyline, "No recorded skyline")
        XCTAssertEqual(HorizonText.summary(of: site), "Terrain horizon \(dot) highest 9\u{00B0} all round")
    }

    func testASiteWithNothingIsAnOpenHorizonInBothWords() throws {
        let site = try XCTUnwrap(SavedSite(name: "Open", latitude: 10, longitude: 20))
        XCTAssertEqual(HorizonText.status(of: site), "Open horizon")
        XCTAssertEqual(HorizonText.summary(of: site), "Open horizon")
    }

    func testASiteWithARecordedSkylineIsSummedUpAsRecorded() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        HorizonCoverageMemory.forget(siteID: site.id)
        XCTAssertEqual(HorizonText.summary(of: site), "Recorded \(dot) highest 14\u{00B0} all round")
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.5)
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        XCTAssertEqual(HorizonText.summary(of: site),
                       "Recorded \(dot) \(AppFormat.percent(0.5)) covered \(dot) highest 14\u{00B0} all round")
    }

    // MARK: What a sweep reached

    private func mask(sweeping range: ClosedRange<Int>) -> [Bool] {
        (0..<HorizonProfile.binCount).map { range.contains($0) }
    }

    func testTheSweptDegreesAreRememberedWithTheCoverage() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        let swept = mask(sweeping: 0...179)
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.5, mask: swept)
        let entry = try XCTUnwrap(HorizonCoverageMemory.entry(for: site))
        XCTAssertEqual(entry.coverage, 0.5)
        XCTAssertEqual(entry.mask, swept)
        XCTAssertEqual(HorizonCoverageMemory.recall(for: site), 0.5)
    }

    func testACoverageStoredWithoutTheDegreesHasNoMask() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.25)
        XCTAssertNil(try XCTUnwrap(HorizonCoverageMemory.entry(for: site)).mask)
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.25, mask: [true, false])
        XCTAssertNil(try XCTUnwrap(HorizonCoverageMemory.entry(for: site)).mask, "a mask of the wrong length is not kept")
    }

    func testAChangedSkylineForgetsItsCoverage() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.5)
        var changed = site
        changed.horizon = .constant(20)
        XCTAssertNil(HorizonCoverageMemory.recall(for: changed))
    }

    func testStoringNoSkylineForgetsTheCoverage() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.5)
        HorizonCoverageMemory.store(siteID: site.id, horizon: nil, coverage: 0.5)
        XCTAssertNil(HorizonCoverageMemory.recall(for: site))
    }

    func testTwoSweepsAreAddedUp() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.25, mask: mask(sweeping: 0...89))
        let merged = try XCTUnwrap(HorizonCoverageMemory.merged(sweep: mask(sweeping: 180...269), over: site))
        XCTAssertEqual(merged.coverage, 0.5, accuracy: 1e-9)
        XCTAssertEqual(merged.mask?.filter { $0 }.count, 180)
    }

    func testWithoutTheOldDegreesTheLargerShareIsAllThatIsKnown() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        defer { HorizonCoverageMemory.forget(siteID: site.id) }
        HorizonCoverageMemory.store(siteID: site.id, horizon: ridge, coverage: 0.75)
        let merged = try XCTUnwrap(HorizonCoverageMemory.merged(sweep: mask(sweeping: 0...89), over: site))
        XCTAssertEqual(merged.coverage, 0.75)
        XCTAssertNil(merged.mask)
        let wider = try XCTUnwrap(HorizonCoverageMemory.merged(sweep: mask(sweeping: 0...359), over: site))
        XCTAssertEqual(wider.coverage, 1)
    }
}

import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `SiteHorizon` (Features/Horizon/SiteHorizon.swift): which skyline applies at a site, and where it comes from.
final class SettingsSiteHorizonTests: XCTestCase {
    private let ridge = HorizonProfile.constant(15)
    private let hills = HorizonProfile.constant(5)
    private let north = [AzimuthRange(start: 330, length: 60)]

    func testWithNothingTheHorizonIsOpen() {
        XCTAssertEqual(SiteHorizon.resolve(recorded: nil, terrain: nil, gaps: []), .open)
        XCTAssertNil(ResolvedHorizon.open.profile)
        XCTAssertNil(ResolvedHorizon.open.source)
    }

    func testAFlatSkylineIsAnOpenHorizon() {
        XCTAssertEqual(SiteHorizon.resolve(recorded: .constant(0), terrain: nil, gaps: []), .open)
        XCTAssertEqual(SiteHorizon.resolve(recorded: nil, terrain: .constant(0), gaps: []), .open)
    }

    func testARecordedSkylineAloneIsTheRecordedOne() {
        let resolved = SiteHorizon.resolve(recorded: ridge, terrain: nil, gaps: [])
        XCTAssertEqual(resolved.source, .recorded)
        XCTAssertNotNil(resolved.profile)
    }

    func testTerrainAloneIsTheTerrainHorizon() {
        let resolved = SiteHorizon.resolve(recorded: nil, terrain: hills, gaps: [])
        XCTAssertEqual(resolved.source, .terrain)
        XCTAssertNotNil(resolved.profile)
    }

    func testAFlatRecordingGivesWayToTheTerrain() {
        XCTAssertEqual(SiteHorizon.resolve(recorded: .constant(0), terrain: hills, gaps: []).source, .terrain)
    }

    func testTerrainInTheGapsOfARecordingIsBothTogether() {
        let resolved = SiteHorizon.resolve(recorded: ridge, terrain: hills, gaps: north)
        XCTAssertEqual(resolved.source, .recordedAndTerrain)
        XCTAssertNotNil(resolved.profile)
    }

    func testARecordingWithoutGapsStaysRecordedHoweverMuchTerrainIsStored() {
        XCTAssertEqual(SiteHorizon.resolve(recorded: ridge, terrain: hills, gaps: []).source, .recorded)
    }

    func testASiteWithoutAnySkylineHasAnOpenHorizon() throws {
        let site = try XCTUnwrap(SavedSite(name: "Open", latitude: 10, longitude: 20))
        XCTAssertEqual(SiteHorizon.resolve(site), .open)
    }

    func testASiteWithARecordedSkylineAndNoTerrainUsesTheRecordedOne() throws {
        let site = try XCTUnwrap(SavedSite(name: "Ridge", latitude: 10, longitude: 20, horizon: ridge))
        XCTAssertEqual(SiteHorizon.resolve(site).source, .recorded)
    }

    func testASiteWithOnlyTerrainUsesTheTerrain() throws {
        let site = try XCTUnwrap(SavedSite(name: "Hills", latitude: 10, longitude: 20, terrainHorizon: hills))
        XCTAssertEqual(SiteHorizon.resolve(site).source, .terrain)
    }

    func testTheSourceNamesItself() {
        XCTAssertEqual(HorizonSource.recorded.label, "Recorded skyline")
        XCTAssertEqual(HorizonSource.terrain.label, "Terrain horizon")
        XCTAssertEqual(HorizonSource.recordedAndTerrain.label, "Recorded + terrain")
    }

    func testTheTerrainHorizonOfASiteSurvivesTheRoundTripOfTheSettings() throws {
        let site = try XCTUnwrap(SavedSite(name: "Hills", latitude: 10, longitude: 20, terrainHorizon: hills))
        let decoded = try JSONDecoder().decode(SavedSite.self, from: JSONEncoder().encode(site))
        XCTAssertEqual(decoded.terrainHorizon, hills)
        XCTAssertNil(decoded.horizon)
    }
}

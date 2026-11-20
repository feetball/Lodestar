import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `AimSkyContent`: the sky snapshot with the drawing groups the overlay derives from it: stars grouped by brightness and
/// tint, the named stars, the deep-sky symbols in drawing order, the Milky Way layers and the skyline.
final class AimEngineSkyContentTests: XCTestCase {
    private enum Fixture {
        static let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
        /// 2026-07-16 05:00 UTC, 23:00 in Colorado.
        static let july = Date(timeIntervalSince1970: 1_784_178_000)
        static let catalog = Result { try Catalog.loadBundled() }
    }

    // MARK: Helpers

    private func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try Fixture.catalog.get().object(id: id), id)
    }

    private func direction(azimuth: Double = 90, altitude: Double = 45) -> Vector3 {
        HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector
    }

    private func star(_ id: String, magnitude: Double, colorIndex: Double? = nil, name: String? = nil,
                      azimuth: Double = 90, altitude: Double = 45) -> SkySnapshot.Star {
        SkySnapshot.Star(id: id, direction: direction(azimuth: azimuth, altitude: altitude), magnitude: magnitude,
                         colorIndex: colorIndex, name: name)
    }

    private func deepSky(_ object: CelestialObject, azimuth: Double = 90, altitude: Double = 45,
                         majorAxis: Double? = nil) -> SkySnapshot.DeepSky {
        SkySnapshot.DeepSky(object: object, direction: direction(azimuth: azimuth, altitude: altitude), majorAxis: majorAxis)
    }

    private func snapshot(stars: [SkySnapshot.Star] = [], deepSky: [SkySnapshot.DeepSky] = [],
                          milkyWay: [SkySnapshot.MilkyWayBand] = []) -> SkySnapshot {
        SkySnapshot(date: Fixture.july, observer: Fixture.boulder, stars: stars, bodies: [], deepSky: deepSky,
                    constellations: [], milkyWay: milkyWay, target: nil, mosaic: [], smallBodies: [])
    }

    /// "brightness/tint/below" for each star group, in drawing order.
    private func labels(_ content: AimSkyContent) -> [String] {
        content.starGroups.map { "\($0.brightness)/\($0.tint)/\($0.isBelowHorizon)" }
    }

    // MARK: Brightness classes

    func testBrightnessClassesFollowTheMagnitude() {
        let cases: [(magnitude: Double, level: Int)] = [
            (-100, 0), (-30, 0), (-1.46, 0), (-0.01, 0),
            (0, 1), (0.99, 1), (1, 2), (1.5, 2), (2.5, 3), (3.99, 4), (4.5, 5), (4.99, 5),
            (5, 6), (5.5, 6), (9, 6), (30, 6), (100, 6),
        ]
        for (magnitude, level) in cases {
            XCTAssertEqual(AimStarGroup.brightness(of: magnitude), level, "magnitude \(magnitude)")
        }
        XCTAssertEqual(AimStarGroup.brightnessLevels, 7)
    }

    func testAMagnitudeThatIsNotANumberIsTheFaintestClass() {
        XCTAssertEqual(AimStarGroup.brightness(of: .nan), 6)
        XCTAssertEqual(AimStarGroup.brightness(of: .infinity), 6)
        XCTAssertEqual(AimStarGroup.brightness(of: -.infinity), 6)
    }

    // MARK: Tints

    func testTintsFollowTheColourIndex() {
        let cases: [(index: Double?, tint: Int)] = [
            (-0.3, 0), (0, 0), (0.29, 0), (0.3, 1), (0.6, 1), (0.94, 1), (0.95, 2), (1.5, 2), (3, 2),
            (nil, 1), (.nan, 1), (.infinity, 1), (-.infinity, 1),
        ]
        for (index, tint) in cases {
            XCTAssertEqual(AimStarGroup.tint(of: index), tint, "colour index \(String(describing: index))")
        }
    }

    func testAGroupTakesItsLookFromItsKey() {
        let key = AimStarGroup.Key(brightness: 3, tint: 2, isBelowHorizon: true)
        let directions = [direction(azimuth: 10), direction(azimuth: 20)]
        let group = AimStarGroup(key: key, directions: directions)
        XCTAssertEqual(group.brightness, 3)
        XCTAssertEqual(group.tint, 2)
        XCTAssertTrue(group.isBelowHorizon)
        XCTAssertEqual(group.directions, directions)
        XCTAssertNotEqual(key, AimStarGroup.Key(brightness: 3, tint: 2, isBelowHorizon: false))
        XCTAssertEqual(key, AimStarGroup.Key(brightness: 3, tint: 2, isBelowHorizon: true))
    }

    // MARK: Star groups

    func testAnEmptySkyHasNoGroupsNoNamesNoMarkersAndNoSkyline() {
        let content = AimSkyContent(snapshot: snapshot())
        XCTAssertTrue(content.starGroups.isEmpty)
        XCTAssertTrue(content.namedStars.isEmpty)
        XCTAssertTrue(content.deepSky.isEmpty)
        XCTAssertTrue(content.deepSkyDirections.isEmpty)
        XCTAssertTrue(content.deepSkyCommonDirections.isEmpty)
        XCTAssertTrue(content.milkyWay.isEmpty)
        XCTAssertNil(content.skyline)
    }

    func testStarsOfTheSameLookShareAGroupInTheOrderOfTheSnapshot() {
        let first = star("a", magnitude: 0.5, colorIndex: 0.6, azimuth: 10)
        let second = star("b", magnitude: 0.7, colorIndex: 0.6, azimuth: 20)
        let third = star("c", magnitude: 0.9, colorIndex: 0.5, azimuth: 30)
        let content = AimSkyContent(snapshot: snapshot(stars: [first, second, third]))
        XCTAssertEqual(labels(content), ["1/1/false"])
        XCTAssertEqual(content.starGroups[0].directions, [first.direction, second.direction, third.direction])
    }

    func testGroupsAreDrawnFaintestFirst() {
        let stars = [
            star("a", magnitude: -1.0, colorIndex: 0.0, azimuth: 10),
            star("b", magnitude: 0.5, colorIndex: 0.6, azimuth: 20),
            star("c", magnitude: 0.7, colorIndex: 0.6, azimuth: 30),
            star("d", magnitude: 4.2, colorIndex: 1.2, azimuth: 40),
            star("e", magnitude: 4.2, colorIndex: 1.2, azimuth: 50, altitude: -10),
            star("f", magnitude: 6.5, colorIndex: nil, azimuth: 60),
        ]
        let content = AimSkyContent(snapshot: snapshot(stars: stars))
        XCTAssertEqual(labels(content), ["6/1/false", "5/2/true", "5/2/false", "1/1/false", "0/0/false"])
        XCTAssertEqual(content.starGroups.map { $0.directions.count }, [1, 1, 1, 2, 1])
        XCTAssertEqual(content.starGroups[3].directions, [stars[1].direction, stars[2].direction])
    }

    func testTheSameBrightnessAndTintSplitIntoOneGroupAboveAndOneBelowTheHorizon() {
        let stars = [
            star("up", magnitude: 2.2, colorIndex: 0.5, azimuth: 10, altitude: 30),
            star("down", magnitude: 2.4, colorIndex: 0.5, azimuth: 20, altitude: -30),
            star("up2", magnitude: 2.6, colorIndex: 0.5, azimuth: 30, altitude: 5),
        ]
        let content = AimSkyContent(snapshot: snapshot(stars: stars))
        XCTAssertEqual(labels(content), ["3/1/true", "3/1/false"])
        XCTAssertEqual(content.starGroups[0].directions, [stars[1].direction])
        XCTAssertEqual(content.starGroups[1].directions, [stars[0].direction, stars[2].direction])
    }

    func testAStarOnTheHorizonIsNotBelowIt() {
        let content = AimSkyContent(snapshot: snapshot(stars: [star("a", magnitude: 2, altitude: 0),
                                                              star("b", magnitude: 2, altitude: -0.01)]))
        XCTAssertEqual(labels(content), ["3/1/true", "3/1/false"])
    }

    // MARK: Named stars

    func testStarsWithANameAndMagnitudeThreeOrBrighterAreLabelled() {
        let stars = [
            star("sirius", magnitude: -1.46, name: "Sirius", azimuth: 10),
            star("unnamed", magnitude: 1.0, name: nil, azimuth: 20),
            star("vega", magnitude: 0.03, name: "Vega", azimuth: 30),
            star("edge", magnitude: 3.0, name: "Hamal", azimuth: 40),
            star("faint", magnitude: 3.01, name: "Dubhe", azimuth: 50),
            star("setting", magnitude: 2.0, name: "Hidden", azimuth: 60, altitude: -5),
        ]
        let content = AimSkyContent(snapshot: snapshot(stars: stars))
        XCTAssertEqual(content.namedStars.map(\.name), ["Sirius", "Vega", "Hamal", "Hidden"])
        XCTAssertEqual(content.namedStars.map(\.isHidden), [false, false, false, true])
        XCTAssertEqual(content.namedStars.map(\.magnitude), [-1.46, 0.03, 3.0, 2.0])
        XCTAssertEqual(content.namedStars[0].direction, stars[0].direction)
        XCTAssertEqual(content.namedStars[3].direction, stars[5].direction)
    }

    func testAStarWithoutANameIsNeverLabelled() {
        let content = AimSkyContent(snapshot: snapshot(stars: [star("a", magnitude: -1, name: nil)]))
        XCTAssertTrue(content.namedStars.isEmpty)
        XCTAssertEqual(content.starGroups.count, 1)
    }

    // MARK: The skyline

    func testWithoutASkylineOnlyTheHorizonHidesStars() {
        let content = AimSkyContent(snapshot: snapshot(stars: [star("low", magnitude: 2, altitude: 10)]), horizon: nil)
        XCTAssertNil(content.skyline)
        XCTAssertEqual(labels(content), ["3/1/false"])
    }

    func testStarsBehindTheSkylineAreTreatedLikeThoseBelowTheHorizon() throws {
        let stars = [
            star("behind", magnitude: 2.2, name: "Behind", azimuth: 90, altitude: 10),
            star("above", magnitude: 2.4, name: "Above", azimuth: 100, altitude: 30),
            star("below", magnitude: 2.6, name: "Below", azimuth: 110, altitude: -10),
        ]
        let content = AimSkyContent(snapshot: snapshot(stars: stars), horizon: .constant(20))
        XCTAssertEqual(try XCTUnwrap(content.skyline).highestAltitude, 20)
        XCTAssertEqual(labels(content), ["3/1/true", "3/1/false"])
        XCTAssertEqual(content.starGroups[0].directions, [stars[0].direction, stars[2].direction])
        XCTAssertEqual(content.starGroups[1].directions, [stars[1].direction])
        XCTAssertEqual(content.namedStars.map(\.isHidden), [true, false, true])
    }

    func testAFlatSkylineHidesWhatTheHorizonHides() {
        let stars = [star("up", magnitude: 2, altitude: 3), star("down", magnitude: 2, altitude: -3)]
        let content = AimSkyContent(snapshot: snapshot(stars: stars), horizon: .flat)
        XCTAssertNotNil(content.skyline)
        XCTAssertEqual(labels(content), ["3/1/true", "3/1/false"])
    }

    func testTheSkylineHidesOnlyWhereItRises() throws {
        // A hill of 30 degrees in the east only: the same star is hidden behind it and visible in the west.
        var altitudes = [Double](repeating: 0, count: HorizonProfile.binCount)
        for azimuth in 80...100 { altitudes[azimuth] = 30 }
        let hill = try XCTUnwrap(HorizonProfile(altitudes: altitudes))
        let stars = [star("east", magnitude: 2, azimuth: 90, altitude: 15), star("west", magnitude: 2, azimuth: 270, altitude: 15)]
        let content = AimSkyContent(snapshot: snapshot(stars: stars), horizon: hill)
        XCTAssertEqual(labels(content), ["3/1/true", "3/1/false"])
        XCTAssertEqual(content.starGroups[0].directions, [stars[0].direction])
        XCTAssertEqual(content.starGroups[1].directions, [stars[1].direction])
    }

    // MARK: Deep-sky markers

    func testAMarkerTakesItsFieldsFromTheObject() throws {
        let m31 = try object("dso.M31")
        let marker = AimDeepSkyMarker(deepSky(m31, azimuth: 123, altitude: 33, majorAxis: 3.0), isHidden: false)
        XCTAssertEqual(marker.name, "Andromeda Galaxy")
        XCTAssertEqual(marker.direction, direction(azimuth: 123, altitude: 33))
        XCTAssertEqual(marker.shape, .ellipse)
        XCTAssertEqual(marker.diameter, 3.0)
        XCTAssertEqual(marker.magnitude, m31.magnitude)
        XCTAssertEqual(marker.prominence, m31.prominence.rawValue)
        XCTAssertFalse(marker.isDark)
        XCTAssertFalse(marker.isHidden)
        let hidden = AimDeepSkyMarker(deepSky(m31), isHidden: true)
        XCTAssertTrue(hidden.isHidden)
    }

    func testAnObjectWithoutASizeHasDiameterZero() throws {
        let marker = AimDeepSkyMarker(deepSky(try object("dso.M31"), majorAxis: nil), isHidden: false)
        XCTAssertEqual(marker.diameter, 0)
    }

    func testTheShapeFollowsTheKindOfObject() throws {
        let cases: [(id: String, category: ObjectCategory, shape: AimDeepSkyMarker.Shape)] = [
            ("dso.M31", .galaxy, .ellipse),
            ("dso.HCG92", .galaxyGroup, .ellipse),
            ("dso.M6", .openCluster, .clusterDot),
            ("dso.M2", .globularCluster, .clusterDot),
            ("dso.M24", .starAssociation, .clusterDot),
            ("dso.NGC281", .emissionNebula, .square),
            ("dso.M78", .reflectionNebula, .square),
            ("dso.B1", .darkNebula, .square),
            ("dso.M8", .nebula, .square),
            ("dso.M57", .planetaryNebula, .square),
            ("dso.M1", .supernovaRemnant, .square),
            ("dso.M42", .clusterWithNebula, .square),
            ("dso.M40", .doubleStar, .circle),
            ("dso.M73", .other, .circle),
            ("special.galacticCenter", .milkyWay, .circle),
        ]
        for (id, category, shape) in cases {
            let found = try object(id)
            XCTAssertEqual(found.category, category, "\(id) is no longer of this kind in the catalog")
            XCTAssertEqual(AimDeepSkyMarker(deepSky(found), isHidden: false).shape, shape, id)
        }
    }

    func testOnlyDarkNebulaeAreDark() throws {
        for id in ["dso.B1", "dso.B2"] {
            XCTAssertTrue(AimDeepSkyMarker(deepSky(try object(id)), isHidden: false).isDark, id)
        }
        for id in ["dso.M31", "dso.M42", "dso.M8", "dso.M1", "dso.M73"] {
            XCTAssertFalse(AimDeepSkyMarker(deepSky(try object(id)), isHidden: false).isDark, id)
        }
    }

    func testADarkNebulaHasNoMagnitude() throws {
        XCTAssertNil(AimDeepSkyMarker(deepSky(try object("dso.B1")), isHidden: false).magnitude)
    }

    func testMarkersAreSortedByProminenceThenBrightnessThenName() throws {
        // Showpieces: the Andromeda Galaxy (mag 3.4) before M 2 (mag 6.3) before the galactic centre (no magnitude);
        // then one prominent, one notable and three obscure dark nebulae without magnitude, ordered by name.
        let ids = ["dso.B3", "dso.NGC2060", "special.galacticCenter", "dso.B1", "dso.NGC1555", "dso.M2", "dso.B2", "dso.M31"]
        let objects = try ids.map { try object($0) }
        XCTAssertEqual(objects.map { $0.prominence.rawValue }, [4, 3, 1, 4, 2, 1, 4, 1], "the catalog's ratings changed")
        let entries = objects.enumerated().map { deepSky($1, azimuth: Double($0) * 40) }
        let content = AimSkyContent(snapshot: snapshot(deepSky: entries))

        let expectedIDs = ["dso.M31", "dso.M2", "special.galacticCenter", "dso.NGC1555", "dso.NGC2060", "dso.B1", "dso.B2", "dso.B3"]
        XCTAssertEqual(content.deepSky.map(\.name), try expectedIDs.map { try object($0).name })
        XCTAssertEqual(content.deepSkyDirections, content.deepSky.map(\.direction))
        XCTAssertEqual(content.deepSkyDirections.first, entries[7].direction)
    }

    func testTheCommonDirectionsAreTheMarkersOfProminenceThreeOrBetter() throws {
        let ids = ["dso.B1", "dso.NGC2060", "dso.M31", "dso.NGC1555", "dso.B2"]
        let objects = try ids.map { try object($0) }
        let entries = objects.enumerated().map { deepSky($1, azimuth: Double($0) * 40) }
        let content = AimSkyContent(snapshot: snapshot(deepSky: entries))
        // Sorted: M31 (1), NGC 1555 (2), NGC 2060 (3), then the two obscure dark nebulae.
        XCTAssertEqual(content.deepSky.count, 5)
        XCTAssertEqual(content.deepSkyCommonDirections.count, 3)
        XCTAssertEqual(content.deepSkyCommonDirections, Array(content.deepSkyDirections.prefix(3)))
        XCTAssertEqual(content.deepSkyCommonDirections, [entries[2].direction, entries[3].direction, entries[1].direction])
    }

    func testWhenNothingIsObscureTheCommonDirectionsAreAllOfThem() throws {
        let entries = [deepSky(try object("dso.M31"), azimuth: 10), deepSky(try object("dso.M2"), azimuth: 20)]
        let content = AimSkyContent(snapshot: snapshot(deepSky: entries))
        XCTAssertEqual(content.deepSkyCommonDirections, content.deepSkyDirections)
        XCTAssertEqual(content.deepSkyCommonDirections.count, 2)
    }

    func testWhenOnlyObscureObjectsAreThereTheCommonDirectionsAreNone() throws {
        let content = AimSkyContent(snapshot: snapshot(deepSky: [deepSky(try object("dso.B1"))]))
        XCTAssertEqual(content.deepSky.count, 1)
        XCTAssertTrue(content.deepSkyCommonDirections.isEmpty)
    }

    func testMarkersBelowTheHorizonOrBehindTheSkylineAreHidden() throws {
        let m31 = try object("dso.M31"), m2 = try object("dso.M2"), m6 = try object("dso.M6")
        let entries = [
            deepSky(m31, azimuth: 10, altitude: 45),
            deepSky(m2, azimuth: 20, altitude: -10),
            deepSky(m6, azimuth: 30, altitude: 10),
        ]
        // The markers are sorted, so the flags are read by name.
        func hidden(_ content: AimSkyContent) -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: content.deepSky.map { ($0.name, $0.isHidden) })
        }
        let unwalled = AimSkyContent(snapshot: snapshot(deepSky: entries))
        XCTAssertEqual(hidden(unwalled), [m31.name: false, m2.name: true, m6.name: false])
        let walled = AimSkyContent(snapshot: snapshot(deepSky: entries), horizon: .constant(20))
        XCTAssertEqual(hidden(walled), [m31.name: false, m2.name: true, m6.name: true])
    }

    // MARK: The Milky Way

    func testTheMilkyWayLayersAreMadeFromTheBandsThatCanBeDrawn() {
        let triangle = [direction(azimuth: 90, altitude: 40), direction(azimuth: 100, altitude: 40), direction(azimuth: 95, altitude: 50)]
        let hole = [direction(azimuth: 94, altitude: 42), direction(azimuth: 96, altitude: 42), direction(azimuth: 95, altitude: 44)]
        let bands = [
            SkySnapshot.MilkyWayBand(level: 1, polygons: [triangle], holes: []),
            // Two points make no outline and the band cannot be cut up either: it is left out as a whole.
            SkySnapshot.MilkyWayBand(level: 2, polygons: [Array(triangle.prefix(2))], holes: []),
            SkySnapshot.MilkyWayBand(level: 3, polygons: [triangle], holes: [hole]),
        ]
        let content = AimSkyContent(snapshot: snapshot(milkyWay: bands))
        XCTAssertEqual(content.milkyWay.count, 2)
        XCTAssertEqual(content.milkyWay[0].rings.count, 1)
        XCTAssertEqual(content.milkyWay[0].rings[0].vertices, triangle)
        XCTAssertEqual(content.milkyWay[1].rings.count, 2)
        XCTAssertEqual(content.milkyWay[1].rings[1].vertices, hole)
    }

    // MARK: Building from the catalog

    func testBuildingMakesTheSnapshotAndTheGroupsFromTheSameInputs() throws {
        let inputs = AimSkyInputs(observer: Fixture.boulder, options: SkySnapshotOptions(), target: nil, horizon: nil, mosaic: nil)
        let content = AimSkyContent.build(catalog: try Fixture.catalog.get(), inputs: inputs, date: Fixture.july)
        XCTAssertEqual(content.snapshot.date, Fixture.july)
        XCTAssertEqual(content.snapshot.observer, Fixture.boulder)
        XCTAssertNil(content.skyline)
        XCTAssertNil(content.snapshot.target)

        // Every star lands in exactly one group.
        XCTAssertGreaterThan(content.snapshot.stars.count, 100)
        XCTAssertEqual(content.starGroups.reduce(0) { $0 + $1.directions.count }, content.snapshot.stars.count)
        // The groups are drawn faintest first.
        let keys = content.starGroups.map { [$0.brightness, $0.tint, $0.isBelowHorizon ? 1 : 0] }
        let faintestFirst = Array(keys.sorted { $0.lexicographicallyPrecedes($1) }.reversed())
        XCTAssertEqual(keys, faintestFirst)

        // The named stars are the bright ones with a name, brightest first.
        XCTAssertGreaterThan(content.namedStars.count, 5)
        XCTAssertTrue(content.namedStars.allSatisfy { $0.magnitude <= 3.0 && !$0.name.isEmpty })
        let magnitudes = content.namedStars.map(\.magnitude)
        XCTAssertEqual(magnitudes, magnitudes.sorted())

        // The deep-sky markers are the snapshot's, the most prominent first.
        XCTAssertGreaterThan(content.deepSky.count, 20)
        XCTAssertEqual(content.deepSky.count, content.snapshot.deepSky.count)
        XCTAssertEqual(content.deepSkyDirections.count, content.deepSky.count)
        XCTAssertTrue(content.deepSky.allSatisfy { $0.prominence <= Prominence.prominent.rawValue })
        let prominences = content.deepSky.map(\.prominence)
        XCTAssertEqual(prominences, prominences.sorted())
        XCTAssertEqual(content.deepSkyCommonDirections.count, content.deepSky.count)
        XCTAssertFalse(content.milkyWay.isEmpty)
    }

    func testBuildingKeepsTheTargetOfTheInputs() throws {
        let moon = try object("moon")
        let inputs = AimSkyInputs(observer: Fixture.boulder, options: SkySnapshotOptions(), target: moon, horizon: nil, mosaic: nil)
        let content = AimSkyContent.build(catalog: try Fixture.catalog.get(), inputs: inputs, date: Fixture.july)
        XCTAssertEqual(content.snapshot.target?.object.id, "moon")
    }

    func testBuildingWithTheOptionsLeftOutHasNothingToGroup() throws {
        var options = SkySnapshotOptions()
        options.starMagnitudeLimit = -10
        options.includeDeepSky = false
        options.includeMilkyWay = false
        options.includeConstellations = false
        let inputs = AimSkyInputs(observer: Fixture.boulder, options: options, target: nil, horizon: nil, mosaic: nil)
        let content = AimSkyContent.build(catalog: try Fixture.catalog.get(), inputs: inputs, date: Fixture.july)
        XCTAssertTrue(content.starGroups.isEmpty)
        XCTAssertTrue(content.namedStars.isEmpty)
        XCTAssertTrue(content.deepSky.isEmpty)
        XCTAssertTrue(content.milkyWay.isEmpty)
    }

    func testBuildingWithASkylineHidesMoreStarsThanTheHorizonDoes() throws {
        let catalog = try Fixture.catalog.get()
        let plain = AimSkyInputs(observer: Fixture.boulder, options: SkySnapshotOptions(), target: nil, horizon: nil, mosaic: nil)
        var walled = plain
        walled.horizon = .constant(15)
        let unwalled = AimSkyContent.build(catalog: catalog, inputs: plain, date: Fixture.july)
        let behind = AimSkyContent.build(catalog: catalog, inputs: walled, date: Fixture.july)
        XCTAssertEqual(try XCTUnwrap(behind.skyline).highestAltitude, 15)

        func hiddenCount(_ content: AimSkyContent) -> Int {
            content.starGroups.filter(\.isBelowHorizon).reduce(0) { $0 + $1.directions.count }
        }
        let belowHorizon = unwalled.snapshot.stars.filter { $0.direction.z < 0 }.count
        let belowSkyline = unwalled.snapshot.stars.filter { $0.direction.z < AstroMath.sinDeg(15) }.count
        XCTAssertEqual(hiddenCount(unwalled), belowHorizon)
        XCTAssertEqual(hiddenCount(behind), belowSkyline)
        XCTAssertGreaterThan(belowSkyline, belowHorizon)
    }
}

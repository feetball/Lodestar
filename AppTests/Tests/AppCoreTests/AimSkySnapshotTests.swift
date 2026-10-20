import LodestarKit
import XCTest
@testable import AppCore

/// The sky computed once per refresh for the chart and the aim screen: its contents for a fixed place and time, and
/// the options that decide what it holds.
final class AimSkySnapshotTests: XCTestCase {
    private enum Fixture {
        static let boulder = Observer(location: GeographicLocation(latitude: 40.015, longitude: -105.27, elevation: 1650))
        /// 2026-07-16 05:00 UTC, 23:00 in Colorado: the Sun is 22 degrees below the horizon, the Moon is a thin
        /// crescent two days after new.
        static let july = Date(timeIntervalSince1970: 1_784_178_000)
        static let catalog = Result { try Catalog.loadBundled() }
        static let asteroidCatalog = Result { () throws -> Catalog in
            let bodies = try BundledAsteroids.load().bodies
            return try Fixture.catalog.get().withSmallBodies(bodies)
        }
        static let baseline = Result { () throws -> SkySnapshot in
            let catalog = try Fixture.catalog.get()
            return SkySnapshotBuilder.build(catalog: catalog, observer: Fixture.boulder, date: Fixture.july,
                                            options: SkySnapshotOptions(), target: nil)
        }
        /// The MPC line of C/2023 A3 (Tsuchinshan-ATLAS), copied from the LodestarKit test data.
        static let cometLine =
            "    CK23A030  2024 09 27.8337  0.391312  1.000180  308.5842   21.6759  139.0991  20261017   6.5  3.2  C/2023 A3 (Tsuchinshan-ATLAS)                            MPEC 2026-O98"
    }

    private var boulder: Observer { Fixture.boulder }
    private var july: Date { Fixture.july }

    // MARK: Helpers

    private func loadedCatalog() throws -> Catalog {
        try Fixture.catalog.get()
    }

    private func baseline() throws -> SkySnapshot {
        try Fixture.baseline.get()
    }

    private func frame() -> SkyFrame {
        SkyFrame(date: july, observer: boulder)
    }

    private func lens(_ focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: .fullFrame, focalLength: focalLength)
    }

    /// Options that leave out everything but what a test asks for.
    private func lean() -> SkySnapshotOptions {
        var options = SkySnapshotOptions()
        options.starMagnitudeLimit = -10
        options.includeConstellations = false
        options.includeDeepSky = false
        options.includeMilkyWay = false
        return options
    }

    private func build(_ options: SkySnapshotOptions, catalog: Catalog? = nil, target: CelestialObject? = nil,
                       mosaic: MosaicPlan? = nil) throws -> SkySnapshot {
        SkySnapshotBuilder.build(catalog: try catalog ?? loadedCatalog(), observer: boulder, date: july, options: options,
                                 target: target, mosaic: mosaic)
    }

    private func assertSameSpot(_ a: HorizontalCoordinate, _ b: HorizontalCoordinate, accuracy: Double = 1e-9,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.altitude, b.altitude, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(a.azimuth - b.azimuth), 0.0, accuracy: accuracy, file: file, line: line)
    }

    // MARK: The instant and the observer

    func testTheSnapshotRecordsItsInstantAndObserver() throws {
        let snapshot = try baseline()
        XCTAssertEqual(snapshot.date, july)
        XCTAssertEqual(snapshot.observer, boulder)
        XCTAssertEqual(snapshot.frame.observer, boulder)
        XCTAssertEqual(snapshot.frame.date.timeIntervalSince1970, july.timeIntervalSince1970, accuracy: 0.01)
    }

    // MARK: Stars

    func testStarsAreBrightestFirstAndNoneIsFainterThanTheLimit() throws {
        let stars = try baseline().stars
        XCTAssertGreaterThan(stars.count, 500)
        XCTAssertTrue(stars.allSatisfy { $0.magnitude <= 5.0 })
        for (brighter, fainter) in zip(stars, stars.dropFirst()) {
            XCTAssertLessThanOrEqual(brighter.magnitude, fainter.magnitude)
        }
        XCTAssertEqual(stars[0].id, "star.hip32349")
        XCTAssertEqual(stars[0].name, "Sirius")
        XCTAssertEqual(stars[0].magnitude, -1.44, accuracy: 1e-9)
    }

    func testTheStarLimitIsInclusiveAndMakesTheListShorter() throws {
        let brightest = try XCTUnwrap(try loadedCatalog().renderStars.first)
        var options = lean()
        options.starMagnitudeLimit = brightest.magnitude
        XCTAssertEqual(try build(options).stars.map { $0.id }, [brightest.id])
        options.starMagnitudeLimit = brightest.magnitude - 0.001
        XCTAssertTrue(try build(options).stars.isEmpty)
        options.starMagnitudeLimit = 2
        let bright = try build(options).stars.count
        options.starMagnitudeLimit = 4
        let more = try build(options).stars.count
        XCTAssertGreaterThan(bright, 10)
        XCTAssertGreaterThan(more, bright)
        XCTAssertLessThan(more, try baseline().stars.count)
    }

    func testAStarFarBelowTheHorizonKeepsItsGeometricDirection() throws {
        // Sirius is 60 degrees below the horizon at this time: no refraction there.
        let snapshot = try baseline()
        let sirius = try XCTUnwrap(snapshot.stars.first { $0.name == "Sirius" })
        let position = try XCTUnwrap(try loadedCatalog().object(id: sirius.id)?.j2000)
        let geometric = frame().horizontal(j2000: position, properMotion: nil, refraction: false)
        XCTAssertLessThan(geometric.altitude, -5.0)
        assertSameSpot(HorizontalCoordinate(vector: sirius.direction), geometric)
    }

    func testAStarAboveTheHorizonIsSeenRefracted() throws {
        // Arcturus is 43 degrees up in the southwest.
        let snapshot = try baseline()
        let arcturus = try XCTUnwrap(snapshot.stars.first { $0.name == "Arcturus" })
        let position = try XCTUnwrap(try loadedCatalog().object(id: arcturus.id)?.j2000)
        let refracted = frame().horizontal(j2000: position, properMotion: nil, refraction: true)
        let geometric = frame().horizontal(j2000: position, properMotion: nil, refraction: false)
        let seen = HorizontalCoordinate(vector: arcturus.direction)
        assertSameSpot(seen, refracted, accuracy: 1e-6)
        // About a minute of arc at 43 degrees.
        XCTAssertGreaterThan(seen.altitude - geometric.altitude, 0.005)
        XCTAssertLessThan(seen.altitude - geometric.altitude, 0.05)
    }

    func testEveryDirectionOfTheSkyIsAUnitVector() throws {
        let snapshot = try baseline()
        for star in snapshot.stars { XCTAssertEqual(star.direction.length, 1.0, accuracy: 1e-9, star.id) }
        for body in snapshot.bodies { XCTAssertEqual(body.direction.length, 1.0, accuracy: 1e-9, body.id) }
        for item in snapshot.deepSky { XCTAssertEqual(item.direction.length, 1.0, accuracy: 1e-9, item.id) }
        for figure in snapshot.constellations {
            XCTAssertEqual(figure.label.length, 1.0, accuracy: 1e-9, figure.abbreviation)
            for line in figure.lines {
                for point in line { XCTAssertEqual(point.length, 1.0, accuracy: 1e-9, figure.abbreviation) }
            }
        }
    }

    // MARK: The Sun, the Moon and the planets

    func testTheSolarSystemBodiesAreTheSunTheMoonAndTheSevenPlanets() throws {
        let snapshot = try baseline()
        XCTAssertEqual(snapshot.bodies.map { $0.id }, ["sun", "moon", "planet.mercury", "planet.venus", "planet.mars",
                                                       "planet.jupiter", "planet.saturn", "planet.uranus", "planet.neptune"])
    }

    func testObjectIdentifiersOfTheBodies() {
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .sun), "sun")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .moon), "moon")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .mercury), "planet.mercury")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .venus), "planet.venus")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .mars), "planet.mars")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .jupiter), "planet.jupiter")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .saturn), "planet.saturn")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .uranus), "planet.uranus")
        XCTAssertEqual(SkySnapshotBuilder.objectID(for: .neptune), "planet.neptune")
    }

    func testEveryBodyStandsWhereTheEngineSaysItIsSeenRefracted() throws {
        let snapshot = try baseline()
        XCTAssertEqual(snapshot.bodies.count, SolarSystemBody.allCases.count)
        for (body, state) in zip(SolarSystemBody.allCases, snapshot.bodies) {
            assertSameSpot(state.horizontal, frame().horizontal(of: body, refraction: true))
            XCTAssertEqual(state.direction, state.horizontal.unitVector, state.id)
        }
    }

    func testTheSunIsBelowTheHorizonAtMidnightInJulyAt40North() throws {
        let sun = try XCTUnwrap(try baseline().bodies.first { $0.id == "sun" })
        // At 23:00 local time the Sun stands about 22 degrees below the horizon (and at midnight, 28).
        XCTAssertLessThan(sun.horizontal.altitude, -15.0)
        XCTAssertLessThan(sun.direction.z, 0.0)
        // Its disc is about half a degree across.
        XCTAssertGreaterThan(sun.angularDiameter, 0.5)
        XCTAssertLessThan(sun.angularDiameter, 0.55)
    }

    func testTheMoonIsAThinWaxingCrescentTwoDaysAfterNew() throws {
        let moon = try XCTUnwrap(try baseline().bodies.first { $0.id == "moon" })
        XCTAssertEqual(moon.isWaxing, true)
        let lit = try XCTUnwrap(moon.illuminatedFraction)
        XCTAssertGreaterThan(lit, 0.0)
        XCTAssertLessThan(lit, 0.2)
        XCTAssertGreaterThan(moon.angularDiameter, 0.45)
        XCTAssertLessThan(moon.angularDiameter, 0.6)
    }

    // MARK: Deep-sky objects

    private func deepSky(upTo prominence: Prominence) throws -> [SkySnapshot.DeepSky] {
        var options = lean()
        options.includeDeepSky = true
        options.deepSkyProminence = prominence
        return try build(options).deepSky
    }

    func testTheDefaultSnapshotHoldsTheProminentDeepSkyObjectsAndTheGalacticCentre() throws {
        let items = try baseline().deepSky
        let ids = Set(items.map { $0.id })
        let repeated = Dictionary(grouping: items, by: { $0.id }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertEqual(ids.count, items.count, "an object appears once; listed twice: \(repeated)")
        XCTAssertTrue(ids.contains("dso.M31"))
        XCTAssertTrue(ids.contains("special.galacticCenter"))
        XCTAssertFalse(ids.contains("special.ncp"), "the poles are not fixed places")
        XCTAssertFalse(ids.contains("special.scp"))
        XCTAssertTrue(items.allSatisfy { $0.prominence <= .prominent })
        XCTAssertTrue(items.contains { $0.prominence == .prominent })
    }

    func testTheProminenceSettingDecidesHowDeepTheListGoes() throws {
        let showpieces = try deepSky(upTo: .showpiece)
        let prominent = try deepSky(upTo: .prominent)
        let everything = try deepSky(upTo: .obscure)
        XCTAssertTrue(showpieces.allSatisfy { $0.prominence == .showpiece })
        XCTAssertTrue(showpieces.contains { $0.id == "dso.M31" })
        XCTAssertTrue(showpieces.contains { $0.id == "special.galacticCenter" })
        XCTAssertLessThan(showpieces.count, prominent.count)
        XCTAssertLessThan(prominent.count, everything.count)
        let catalog = try loadedCatalog()
        XCTAssertGreaterThan(everything.count, catalog.deepSkyObjects(upTo: .obscure).count)
        let repeated = Dictionary(grouping: everything, by: { $0.id }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertEqual(Set(everything.map { $0.id }).count, everything.count, "listed twice: \(repeated)")
    }

    func testTheMajorAxisIsGivenInDegreesWhenTheCatalogKnowsIt() throws {
        let items = try deepSky(upTo: .obscure)
        let m31 = try XCTUnwrap(items.first { $0.id == "dso.M31" })
        XCTAssertEqual(try XCTUnwrap(m31.majorAxis), 177.83 / 60, accuracy: 0.01)
        for item in items {
            XCTAssertEqual(item.majorAxis == nil, item.object.angularSize == nil, item.id)
        }
    }

    func testADeepSkyObjectLowInTheSkyIsSeenRefracted() throws {
        // M31 is 15 degrees up in the northeast.
        let m31 = try XCTUnwrap(try baseline().deepSky.first { $0.id == "dso.M31" })
        let position = try XCTUnwrap(m31.object.j2000)
        let refracted = frame().horizontal(j2000: position, properMotion: nil, refraction: true)
        let geometric = frame().horizontal(j2000: position, properMotion: nil, refraction: false)
        let seen = HorizontalCoordinate(vector: m31.direction)
        assertSameSpot(seen, refracted, accuracy: 1e-6)
        XCTAssertGreaterThan(seen.altitude - geometric.altitude, 0.02)
        XCTAssertLessThan(seen.altitude - geometric.altitude, 0.15)
    }

    func testDeepSkyObjectsCanBeLeftOut() throws {
        var options = lean()
        options.includeDeepSky = false
        options.deepSkyProminence = .obscure
        XCTAssertTrue(try build(options).deepSky.isEmpty)
    }

    // MARK: Constellations and the Milky Way

    func testTheConstellationFiguresCarryTheirNamesLinesAndLabels() throws {
        let catalog = try loadedCatalog()
        let figures = try baseline().constellations
        XCTAssertEqual(figures.count, 88)
        XCTAssertEqual(Set(figures.map { $0.id }).count, 88)
        for (figure, constellation) in zip(figures, catalog.constellations) {
            XCTAssertEqual(figure.abbreviation, constellation.abbreviation)
            XCTAssertEqual(figure.name, constellation.name)
            XCTAssertEqual(figure.id, constellation.abbreviation)
            XCTAssertEqual(figure.lines.map { $0.count }, constellation.lines.map { $0.count }, figure.abbreviation)
        }
        XCTAssertTrue(figures.contains { !$0.lines.isEmpty })
    }

    func testConstellationsCanBeLeftOut() throws {
        var options = lean()
        options.includeConstellations = false
        XCTAssertTrue(try build(options).constellations.isEmpty)
        options.includeConstellations = true
        XCTAssertEqual(try build(options).constellations.count, 88)
    }

    func testTheMilkyWayHasItsFiveLevelsWithTheRingsOfTheCatalog() throws {
        let catalog = try loadedCatalog()
        let bands = try baseline().milkyWay
        XCTAssertEqual(bands.map { $0.level }, [1, 2, 3, 4, 5])
        for (band, level) in zip(bands, catalog.milkyWay.levels) {
            XCTAssertEqual(band.polygons.map { $0.count }, level.polygons.map { $0.count }, "level \(band.level)")
            XCTAssertEqual(band.holes.map { $0.count }, level.holes.map { $0.count }, "level \(band.level)")
            XCTAssertFalse(band.polygons.isEmpty, "level \(band.level)")
            for vertex in band.polygons.flatMap({ $0 }).prefix(50) {
                XCTAssertEqual(vertex.length, 1.0, accuracy: 1e-9, "level \(band.level)")
            }
        }
    }

    func testTheMilkyWayCanBeLeftOut() throws {
        var options = lean()
        options.includeMilkyWay = false
        XCTAssertTrue(try build(options).milkyWay.isEmpty)
        options.includeMilkyWay = true
        XCTAssertEqual(try build(options).milkyWay.count, 5)
    }

    // MARK: The target

    func testWithoutATargetTheSnapshotHasNone() throws {
        XCTAssertNil(try baseline().target)
    }

    func testTheTargetIsWhereTheEngineSeesItRefracted() throws {
        let catalog = try loadedCatalog()
        for id in ["dso.M31", "planet.jupiter", "star.hip69673"] {
            let object = try XCTUnwrap(catalog.object(id: id), id)
            let target = try XCTUnwrap(try build(lean(), target: object).target, id)
            XCTAssertEqual(target.object, object, id)
            assertSameSpot(target.horizontal, frame().horizontal(of: object, refraction: true))
            XCTAssertEqual(target.direction, target.horizontal.unitVector, id)
        }
    }

    // MARK: Comets and asteroids

    func testWithoutSmallBodiesThereAreNoMarkers() throws {
        XCTAssertTrue(try baseline().smallBodies.isEmpty)
        let m31 = try XCTUnwrap(try loadedCatalog().object(id: "dso.M31"))
        XCTAssertTrue(try build(lean(), target: m31).smallBodies.isEmpty)
    }

    func testACometThatIsTheTargetIsDrawnWhateverItsBrightness() throws {
        let body = try CometElementsParser.parseLine(Fixture.cometLine)
        let catalog = try loadedCatalog().withSmallBodies([body])
        let comet = try XCTUnwrap(catalog.object(id: body.id))
        var options = lean()
        options.smallBodyMagnitudeLimit = -100
        let snapshot = try build(options, catalog: catalog, target: comet)
        XCTAssertEqual(snapshot.smallBodies.count, 1)
        let marker = try XCTUnwrap(snapshot.smallBodies.first)
        XCTAssertEqual(marker.id, body.id)
        XCTAssertTrue(marker.isComet)
        assertSameSpot(marker.horizontal, frame().horizontal(of: comet, refraction: true), accuracy: 1e-6)
        XCTAssertEqual(marker.direction, marker.horizontal.unitVector)
        XCTAssertEqual(snapshot.target?.object, comet)
    }

    func testSmallBodiesFainterThanTheLimitAreLeftOutUnlessTheyAreTheTarget() throws {
        let catalog = try Fixture.asteroidCatalog.get()
        var options = lean()
        options.smallBodyMagnitudeLimit = -100
        XCTAssertTrue(try build(options, catalog: catalog).smallBodies.isEmpty)

        let vesta = try XCTUnwrap(catalog.object(id: "asteroid.4"))
        let markers = try build(options, catalog: catalog, target: vesta).smallBodies
        XCTAssertEqual(markers.map { $0.id }, ["asteroid.4"])
        XCTAssertFalse(try XCTUnwrap(markers.first).isComet)
    }

    func testTheBrightSmallBodiesAreListedBrightestFirstWithTheTargetAheadOfThem() throws {
        let catalog = try Fixture.asteroidCatalog.get()
        let options = lean()
        let plain = try build(options, catalog: catalog).smallBodies
        XCTAssertLessThanOrEqual(plain.count, SmallBodySkyMarkers.maximumCount)
        for marker in plain {
            let magnitude = try XCTUnwrap(marker.magnitude, marker.id)
            XCTAssertLessThanOrEqual(magnitude, options.smallBodyMagnitudeLimit, marker.id)
        }
        for (a, b) in zip(plain, plain.dropFirst()) {
            XCTAssertLessThanOrEqual(try XCTUnwrap(a.magnitude), try XCTUnwrap(b.magnitude))
        }

        let vesta = try XCTUnwrap(catalog.object(id: "asteroid.4"))
        let withTarget = try build(options, catalog: catalog, target: vesta).smallBodies
        XCTAssertEqual(withTarget.first?.id, "asteroid.4")
        XCTAssertEqual(withTarget.filter { $0.id == "asteroid.4" }.count, 1)
    }

    func testNoMoreThanEightyMarkersAreKept() throws {
        let catalog = try Fixture.asteroidCatalog.get()
        var options = lean()
        options.smallBodyMagnitudeLimit = 30
        let markers = try build(options, catalog: catalog).smallBodies
        XCTAssertEqual(markers.count, SmallBodySkyMarkers.maximumCount)
        XCTAssertEqual(SmallBodySkyMarkers.maximumCount, 80)
    }

    // MARK: The mosaic

    func testWithoutAMosaicThereAreNoOutlines() throws {
        XCTAssertTrue(try baseline().mosaic.isEmpty)
    }

    func testThePanelsOfAHorizontalMosaicAreDrawnWhereTheyAre() throws {
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(24))
        let outlines = try build(lean(), mosaic: plan).mosaic
        XCTAssertEqual(outlines.count, plan.panelCount)
        for (outline, panel) in zip(outlines, plan.panels) {
            XCTAssertEqual(outline.index, panel.index)
            XCTAssertEqual(outline.id, panel.index)
            XCTAssertEqual(outline.shootingPosition, panel.shootingPosition)
            XCTAssertEqual(outline.center.angle(to: panel.center.unitVector), 0.0, accuracy: 1e-9)
            XCTAssertEqual(outline.corners.count, 4)
            for (corner, expected) in zip(outline.corners, panel.corners) {
                XCTAssertEqual(corner.angle(to: expected.unitVector), 0.0, accuracy: 1e-9)
            }
        }
    }

    func testThePanelsOfAnEquatorialMosaicFollowTheStars() throws {
        let center = EquatorialCoordinate(rightAscensionHours: 17.5, declination: 0)
        let plan = try MosaicPlanner.plan(region: .equatorial(center: center, width: 80, height: 50), frame: lens(50))
        XCTAssertEqual(plan.panelCount, 9)
        let outlines = try build(lean(), mosaic: plan).mosaic
        XCTAssertEqual(outlines.map { $0.index }, Array(0..<9))
        for (outline, panel) in zip(outlines, plan.panels) {
            XCTAssertEqual(outline.shootingPosition, panel.shootingPosition)
            let coordinate = try XCTUnwrap(panel.center.equatorialCoordinate)
            let expected = frame().horizontal(j2000: coordinate, properMotion: nil, refraction: true)
            assertSameSpot(HorizontalCoordinate(vector: outline.center), expected, accuracy: 1e-6)
            XCTAssertEqual(outline.corners.count, 4)
            let corner = try XCTUnwrap(panel.corners[0].equatorialCoordinate)
            let expectedCorner = frame().horizontal(j2000: corner, properMotion: nil, refraction: true)
            assertSameSpot(HorizontalCoordinate(vector: outline.corners[0]), expectedCorner, accuracy: 1e-6)
        }
    }

    // MARK: The options

    func testTheDefaultOptions() {
        let options = SkySnapshotOptions()
        XCTAssertEqual(options.starMagnitudeLimit, 5.0)
        XCTAssertTrue(options.includeConstellations)
        XCTAssertTrue(options.includeDeepSky)
        XCTAssertTrue(options.includeMilkyWay)
        XCTAssertEqual(options.deepSkyProminence, .prominent)
        XCTAssertEqual(options.smallBodyMagnitudeLimit, SmallBodySkyMarkers.defaultMagnitudeLimit)
        XCTAssertEqual(options.smallBodyMagnitudeLimit, 9.0)
    }

    func testOptionsAreEqualWhenAllTheirSettingsAre() {
        XCTAssertEqual(SkySnapshotOptions(), SkySnapshotOptions())
        var other = SkySnapshotOptions()
        other.starMagnitudeLimit = 6
        XCTAssertNotEqual(SkySnapshotOptions(), other)
        other = SkySnapshotOptions()
        other.includeMilkyWay = false
        XCTAssertNotEqual(SkySnapshotOptions(), other)
        other = SkySnapshotOptions()
        other.deepSkyProminence = .obscure
        XCTAssertNotEqual(SkySnapshotOptions(), other)
    }

    func testTheDeepSkyDetailSettingMapsToAProminenceAndIsPulledIntoRange() {
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 1), .showpiece)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 2), .prominent)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 3), .notable)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 4), .obscure)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 0), .showpiece)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: -7), .showpiece)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: 5), .obscure)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: Int.max), .obscure)
        XCTAssertEqual(SkySnapshotOptions.prominence(forSetting: Int.min), .showpiece)
    }
}

import XCTest
@testable import LodestarKit

final class CatalogModelTests: XCTestCase {
    // MARK: Categories and groups

    func testCategoryDisplayNames() {
        let names: [ObjectCategory: String] = [
            .sun: "Sun", .moon: "Moon", .planet: "Planet", .comet: "Comet", .asteroid: "Asteroid", .star: "Star",
            .doubleStar: "Double Star",
            .galaxy: "Galaxy", .galaxyGroup: "Galaxy Group", .emissionNebula: "Emission Nebula",
            .reflectionNebula: "Reflection Nebula", .darkNebula: "Dark Nebula", .nebula: "Nebula",
            .planetaryNebula: "Planetary Nebula", .supernovaRemnant: "Supernova Remnant",
            .openCluster: "Open Cluster", .globularCluster: "Globular Cluster",
            .clusterWithNebula: "Cluster with Nebula", .starAssociation: "Star Association",
            .asterism: "Asterism", .milkyWay: "Milky Way", .celestialPole: "Celestial Pole",
            .custom: "Custom Target", .other: "Other",
        ]
        XCTAssertEqual(ObjectCategory.allCases.count, 24)
        XCTAssertEqual(Set(names.keys), Set(ObjectCategory.allCases))
        for (category, name) in names {
            XCTAssertEqual(category.displayName, name)
        }
        XCTAssertEqual(Set(ObjectCategory.allCases.map(\.displayName)).count, 24, "display names are unique")
    }

    func testCategorySymbolNamesLookLikeSFSymbols() {
        for category in ObjectCategory.allCases {
            let name = category.systemImageName
            XCTAssertFalse(name.isEmpty)
            XCTAssertTrue(name.unicodeScalars.allSatisfy { ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "." },
                          "\(category): \(name)")
            XCTAssertFalse(name.hasPrefix(".") || name.hasSuffix(".") || name.contains(".."), name)
        }
        for group in ObjectGroup.allCases {
            XCTAssertFalse(group.systemImageName.isEmpty)
        }
        XCTAssertEqual(Set(ObjectGroup.allCases.map(\.systemImageName)).count, ObjectGroup.allCases.count)
        // Every symbol was looked up in Apple's symbol availability data (SF Symbols 1.0 to 3.0: iOS 13 to 15), so
        // each is available on iOS 17. A new name has to be verified the same way and added here.
        let verified: Set<String> = [
            "sun.max", "moon", "circle.circle", "star", "star.leadinghalf.filled", "hurricane", "circle.hexagongrid",
            "cloud.fill", "cloud.sun", "cloud.fog.fill", "cloud", "circle.dotted", "burst", "sparkles", "aqi.medium",
            "cloud.moon", "aqi.low", "star.circle", "moon.stars", "scope", "plus.circle", "sparkle", "circle.fill",
        ]
        let used = Set(ObjectCategory.allCases.map(\.systemImageName)).union(ObjectGroup.allCases.map(\.systemImageName))
        XCTAssertEqual(used.subtracting(verified), [])
        XCTAssertEqual(verified.subtracting(used), [], "the list names only symbols that are used")
    }

    func testCategoryGroups() {
        let groups: [ObjectGroup: [ObjectCategory]] = [
            .solarSystem: [.sun, .moon, .planet, .comet, .asteroid],
            .stars: [.star, .doubleStar, .asterism],
            .galaxies: [.galaxy, .galaxyGroup],
            .nebulae: [.emissionNebula, .reflectionNebula, .darkNebula, .nebula, .planetaryNebula, .supernovaRemnant, .clusterWithNebula],
            .clusters: [.openCluster, .globularCluster, .starAssociation],
            .special: [.milkyWay, .celestialPole, .custom, .other],
        ]
        for (group, categories) in groups {
            XCTAssertEqual(Set(group.categories), Set(categories), "\(group)")
            for category in categories {
                XCTAssertEqual(category.group, group, "\(category)")
            }
        }
        XCTAssertEqual(Set(groups.values.flatMap { $0 }), Set(ObjectCategory.allCases))
        XCTAssertEqual(groups.values.map(\.count).reduce(0, +), ObjectCategory.allCases.count, "no category in two groups")
    }

    func testGroupDisplayNames() {
        XCTAssertEqual(ObjectGroup.allCases, [.solarSystem, .stars, .galaxies, .nebulae, .clusters, .special])
        XCTAssertEqual(ObjectGroup.allCases.map(\.displayName),
                       ["Solar System", "Stars", "Galaxies", "Nebulae", "Star Clusters", "Special"])
    }

    func testCategoryAndGroupCodingUseTheCaseNames() throws {
        for category in ObjectCategory.allCases {
            let data = try JSONEncoder().encode([category])
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(category.rawValue)\"]")
            XCTAssertEqual(try JSONDecoder().decode([ObjectCategory].self, from: data), [category])
        }
        XCTAssertEqual(ObjectCategory(rawValue: "doubleStar"), .doubleStar)
        XCTAssertNil(ObjectCategory(rawValue: "DoubleStar"))
        XCTAssertEqual(try JSONDecoder().decode([ObjectGroup].self, from: Data(#"["solarSystem","special"]"#.utf8)),
                       [.solarSystem, .special])
        XCTAssertThrowsError(try JSONDecoder().decode([ObjectGroup].self, from: Data(#"["planets"]"#.utf8)))
    }

    // MARK: Angular size

    func testAngularSizeRejectsInvalidMajorAxes() {
        for major in [0.0, -1, .nan, .infinity, -.infinity, AngularSize.maximumArcminutes * 2] {
            XCTAssertNil(AngularSize(majorArcminutes: major), "\(major)")
        }
        XCTAssertNotNil(AngularSize(majorArcminutes: 0.001))
        XCTAssertNotNil(AngularSize(majorArcminutes: AngularSize.maximumArcminutes))
    }

    func testAngularSizeCleansTheOptionalValues() throws {
        XCTAssertEqual(AngularSize(majorArcminutes: 10, minorArcminutes: 4)?.minorArcminutes, 4)
        XCTAssertEqual(AngularSize(majorArcminutes: 10, minorArcminutes: 10)?.minorArcminutes, 10)
        for minor in [0.0, -1, .nan, .infinity, 10.5] {
            XCTAssertNil(AngularSize(majorArcminutes: 10, minorArcminutes: minor)?.minorArcminutes, "\(minor)")
        }
        let angles: [(Double, Double?)] = [(0, 0), (45, 45), (179.5, 179.5), (180, 0), (360, 0), (190, 10), (-10, 170),
                                          (725, 5), (.nan, nil), (.infinity, nil)]
        for (angle, expected) in angles {
            XCTAssertEqual(AngularSize(majorArcminutes: 5, positionAngle: angle)?.positionAngle, expected, "\(angle)")
        }
        XCTAssertNil(AngularSize(majorArcminutes: 5)?.positionAngle)
        XCTAssertEqual(AngularSize(majorArcminutes: 5, minorArcminutes: 2, positionAngle: 30),
                       AngularSize(majorArcminutes: 5, minorArcminutes: 2, positionAngle: 30))
    }

    func testAngularSizeDescriptions() throws {
        func text(_ major: Double, _ minor: Double? = nil) throws -> String {
            try XCTUnwrap(AngularSize(majorArcminutes: major, minorArcminutes: minor)).description
        }
        XCTAssertEqual(try text(178, 69.7), "178′ × 70′")
        XCTAssertEqual(try text(150, 150), "150′")
        XCTAssertEqual(try text(646, 550), "646′ × 550′")
        XCTAssertEqual(try text(12), "12′")
        XCTAssertEqual(try text(12.4), "12′")
        XCTAssertEqual(try text(8.4, 4), "8.4′ × 4′")
        XCTAssertEqual(try text(9.96), "10′")
        XCTAssertEqual(try text(1.2, 0.5), "1.2′ × 0.5′")
        XCTAssertEqual(try text(1), "1′")
        XCTAssertEqual(try text(0.6), "36″")
        XCTAssertEqual(try text(0.5, 0.25), "30″ × 15″")
        XCTAssertEqual(try text(0.1), "6″")
        XCTAssertEqual(try text(0.01), "0.6″")
        XCTAssertEqual(try text(0.99), "59″")
        XCTAssertEqual(try text(0.9917), "1′", "59.5″ would round to 60″, which is written as one arcminute")
        XCTAssertEqual(try text(0.9999, 0.5), "1′ × 0.5′")
        XCTAssertEqual(try text(21600), "21600′")
        XCTAssertEqual(String(describing: try XCTUnwrap(AngularSize(majorArcminutes: 30.5))), "31′")
    }

    func testAngularSizeCoding() throws {
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 178, minorArcminutes: 70, positionAngle: 35))
        let decoded = try JSONDecoder().decode(AngularSize.self, from: JSONEncoder().encode(size))
        XCTAssertEqual(decoded, size)
        let minimal = try JSONDecoder().decode(AngularSize.self, from: Data(#"{"majorArcminutes":5}"#.utf8))
        XCTAssertEqual(minimal, AngularSize(majorArcminutes: 5))
        for json in [#"{"majorArcminutes":0}"#, #"{"majorArcminutes":-3}"#, #"{"minorArcminutes":2}"#, #"{"majorArcminutes":"big"}"#, "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(AngularSize.self, from: Data(json.utf8)), json)
        }
        // A minor axis that is too long is dropped on decoding, as it is on creation.
        XCTAssertNil(try JSONDecoder().decode(AngularSize.self, from: Data(#"{"majorArcminutes":5,"minorArcminutes":9}"#.utf8)).minorArcminutes)
    }

    // MARK: Custom targets

    func testCustomTargetBasics() throws {
        let position = EquatorialCoordinate(rightAscension: 123.4, declination: -45.6)
        let target = CelestialObject.custom(name: "My Field", j2000: position)
        XCTAssertTrue(target.id.hasPrefix("custom."))
        let uuid = String(target.id.dropFirst("custom.".count))
        XCTAssertNotNil(UUID(uuidString: uuid), target.id)
        XCTAssertEqual(target.name, "My Field")
        XCTAssertEqual(target.category, .custom)
        XCTAssertEqual(target.group, .special)
        XCTAssertEqual(target.position, .fixed(position, nil))
        XCTAssertEqual(target.j2000, position)
        XCTAssertTrue(target.isListed)
        XCTAssertFalse(target.isSolarSystem)
        XCTAssertTrue(target.designations.isEmpty)
        XCTAssertTrue(target.alternateNames.isEmpty)
        XCTAssertNil(target.magnitude)
        XCTAssertNil(target.angularSize)
        XCTAssertNil(target.constellation)
        XCTAssertEqual(target.subtitle, "Custom Target")
        XCTAssertNotEqual(target.id, CelestialObject.custom(name: "My Field", j2000: position).id, "every call makes a new identifier")
    }

    func testCustomTargetCanBeRestoredWithItsIdentifier() throws {
        let uuid = UUID()
        let position = EquatorialCoordinate(rightAscension: 10, declination: 20)
        let first = CelestialObject.custom(id: uuid, name: "Saved", j2000: position)
        let second = CelestialObject.custom(id: uuid, name: "Saved", j2000: position)
        XCTAssertEqual(first.id, "custom.\(uuid.uuidString)")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        let renamed = CelestialObject.custom(id: uuid, name: "Renamed", j2000: position)
        XCTAssertNotEqual(first, renamed, "equality compares every property")
        XCTAssertEqual(first.hashValue, renamed.hashValue, "hashing uses the identifier only")
        XCTAssertEqual(Set([first, second, renamed]).count, 2)
    }

    func testCustomTargetNamesAreCleanedUp() {
        let position = EquatorialCoordinate(rightAscension: 0, declination: 0)
        func name(_ raw: String) -> String { CelestialObject.custom(name: raw, j2000: position).name }
        XCTAssertEqual(name("  My Target \n"), "My Target")
        XCTAssertEqual(name("A\nB\tC  D"), "A B C D")
        XCTAssertEqual(name("A\u{200B}B"), "AB")
        XCTAssertEqual(name("tab\u{0007}bell"), "tabbell")
        XCTAssertEqual(name("Ångström — Nebula"), "Ångström — Nebula")
        XCTAssertEqual(name("日本語の名前"), "日本語の名前")
        XCTAssertEqual(name("e\u{0301}"), "e\u{0301}")
        for empty in ["", "   ", "\n\t ", "\u{0000}\u{0007}", "\u{200B}"] {
            XCTAssertEqual(name(empty), CelestialObject.defaultCustomName, "\(empty.unicodeScalars.map(\.value))")
        }
        XCTAssertEqual(CelestialObject.defaultCustomName, "Custom Target")
    }

    func testCustomTargetNamesAreCappedAtSixtyCharacters() {
        let position = EquatorialCoordinate(rightAscension: 0, declination: 0)
        func name(_ raw: String) -> String { CelestialObject.custom(name: raw, j2000: position).name }
        XCTAssertEqual(CelestialObject.maximumCustomNameLength, 60)
        XCTAssertEqual(name(String(repeating: "x", count: 60)).count, 60)
        XCTAssertEqual(name(String(repeating: "x", count: 61)).count, 60)
        XCTAssertEqual(name(String(repeating: "🔭", count: 100)), String(repeating: "🔭", count: 60))
        XCTAssertEqual(name(String(repeating: "e\u{0301}", count: 70)).count, 60)
        XCTAssertEqual(name(String(repeating: "a", count: 59) + " bbb"), String(repeating: "a", count: 59), "no trailing space after the cut")
        let start = Date()
        XCTAssertEqual(name(String(repeating: "word ", count: 400_000)).count, 59)
        XCTAssertEqual(name(String(repeating: " ", count: 2_000_000) + "end"), "end")
        XCTAssertEqual(name("z" + String(repeating: "\u{0301}", count: 1_000_000)).unicodeScalars.count, 8 * 60)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testCustomTargetPositionsAreMadeFinite() {
        let nan = CelestialObject.custom(name: "NaN", j2000: EquatorialCoordinate(rightAscension: .nan, declination: .nan))
        XCTAssertEqual(nan.j2000, EquatorialCoordinate(rightAscension: 0, declination: 0))
        // The coordinate type clamps an infinite declination to the pole; an infinite right ascension survives it.
        let infinite = CelestialObject.custom(name: "Inf", j2000: EquatorialCoordinate(rightAscension: .infinity, declination: -.infinity))
        XCTAssertEqual(infinite.j2000, EquatorialCoordinate(rightAscension: 0, declination: -90))
        let wrapped = CelestialObject.custom(name: "Wrap", j2000: EquatorialCoordinate(rightAscension: 400, declination: 95))
        XCTAssertEqual(wrapped.j2000?.rightAscension ?? -1, 40, accuracy: 1e-12)
        XCTAssertEqual(wrapped.j2000?.declination, 90)
    }

    func testCustomTargetsAreNotPartOfTheCatalog() throws {
        let catalog = try CatalogFixture.catalog()
        let target = CelestialObject.custom(name: "Elsewhere", j2000: EquatorialCoordinate(rightAscension: 1, declination: 1))
        XCTAssertNil(catalog.object(id: target.id))
        XCTAssertTrue(catalog.search("Elsewhere").isEmpty)
    }

    // MARK: Object values

    func testSubtitles() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.object(id: "dso.M31")?.subtitle, "Galaxy \u{00B7} Andromeda \u{00B7} mag 3.4")
        XCTAssertEqual(catalog.object(id: "star.hip32349")?.subtitle, "Star \u{00B7} Canis Major \u{00B7} mag \u{2212}1.4")
        XCTAssertEqual(catalog.object(id: "star.hip71683")?.subtitle, "Star \u{00B7} Centaurus \u{00B7} mag 0.0",
                       "magnitude -0.01 rounds to zero without a sign")
        XCTAssertEqual(catalog.object(id: "dso.M45")?.subtitle, "Open Cluster \u{00B7} Taurus \u{00B7} mag 1.2")
        XCTAssertEqual(catalog.object(id: "planet.mars")?.subtitle, "Planet")
        XCTAssertEqual(catalog.object(id: "sun")?.subtitle, "Sun")
        XCTAssertEqual(catalog.object(id: "special.ncp")?.subtitle, "Celestial Pole \u{00B7} Ursa Minor")
        XCTAssertEqual(catalog.object(id: "special.galacticCenter")?.subtitle, "Milky Way \u{00B7} Sagittarius")
        XCTAssertEqual(catalog.object(id: "dso.B33")?.subtitle, "Dark Nebula \u{00B7} Orion")
    }

    func testObjectPositionValueSemantics() {
        let coordinate = EquatorialCoordinate(rightAscension: 10, declination: 20)
        let motion = ProperMotion(raMilliarcsecondsPerYear: 1, decMilliarcsecondsPerYear: 2)
        XCTAssertEqual(ObjectPosition.fixed(coordinate, motion), .fixed(coordinate, motion))
        XCTAssertNotEqual(ObjectPosition.fixed(coordinate, motion), .fixed(coordinate, nil))
        XCTAssertNotEqual(ObjectPosition.solarSystem(.sun), .solarSystem(.moon))
        XCTAssertNotEqual(ObjectPosition.celestialPole(north: true), .celestialPole(north: false))
        XCTAssertEqual(Set([ObjectPosition.solarSystem(.sun), .solarSystem(.sun), .celestialPole(north: true)]).count, 2)
    }

    func testRankingMagnitudePlacesSolarSystemBodiesByBrightness() {
        let order: [SolarSystemBody] = [.sun, .moon, .venus, .jupiter, .mars, .mercury, .saturn, .uranus, .neptune]
        let ranking = order.map { CelestialObject(id: $0.rawValue, name: $0.displayName, category: .planet,
                                                  position: .solarSystem($0), isListed: true).rankingMagnitude }
        XCTAssertEqual(ranking, ranking.sorted())
        XCTAssertEqual(Set(ranking).count, 9)
        let nebula = CelestialObject(id: "x", name: "x", category: .nebula,
                                     position: .fixed(EquatorialCoordinate(rightAscension: 0, declination: 0), nil), isListed: true)
        XCTAssertEqual(nebula.rankingMagnitude, .infinity)
        XCTAssertLessThan(ranking.last ?? 0, 10)
    }

    // MARK: Sharing between tasks

    private func requireSendable<Value: Sendable>(_ type: Value.Type) {}

    func testThePublicTypesAreSendable() {
        requireSendable(Catalog.self)
        requireSendable(CelestialObject.self)
        requireSendable(CatalogSearchResult.self)
        requireSendable(CatalogSearchResult.MatchKind.self)
        requireSendable(CatalogSortOrder.self)
        requireSendable(RenderStar.self)
        requireSendable(Constellation.self)
        requireSendable(MilkyWayOutline.self)
        requireSendable(MilkyWayOutline.Level.self)
        requireSendable(ObjectCategory.self)
        requireSendable(ObjectGroup.self)
        requireSendable(ObjectPosition.self)
        requireSendable(AngularSize.self)
        requireSendable(CatalogError.self)
        requireSendable(CatalogFile.self)
        requireSendable(CatalogLoadReport.self)
    }

    func testACatalogCanBeUsedFromOtherTasks() async throws {
        let catalog = try CatalogFixture.catalog()
        let results = await Task.detached { catalog.search("m31", limit: 3).map(\.object.id) }.value
        XCTAssertEqual(results.first, "dso.M31")
        let sirius = try XCTUnwrap(catalog.object(id: "star.hip32349"))
        let observer = Observer(location: GeographicLocation(latitude: 40, longitude: -105, elevation: 0))
        let position = await Task.detached {
            SkyFrame(date: Date(timeIntervalSince1970: 0), observer: observer).horizontal(of: sirius)
        }.value
        XCTAssertTrue((-90...90).contains(position.altitude))
    }

    // MARK: Errors and the load report

    func testErrorDescriptionsNameTheFile() {
        let errors: [CatalogError] = [
            .missingResource(.stars), .unreadable(.deepSkyObjects, reason: "disk"), .malformed(.constellations, reason: "truncated"),
            .unsupportedSchema(.milkyWay, version: 7), .unsupportedSchema(.stars, version: nil),
            .noValidRecords(.deepSkyObjects, rejected: 3),
        ]
        let files = ["stars.json", "dsos.json", "constellations.json", "milkyway.json", "stars.json", "dsos.json"]
        for (error, file) in zip(errors, files) {
            XCTAssertTrue(error.description.contains(file), error.description)
            XCTAssertEqual(error.errorDescription, error.description)
            XCTAssertEqual(error.localizedDescription, error.description)
        }
        XCTAssertTrue(CatalogError.malformed(.stars, reason: "truncated").description.contains("truncated"))
        XCTAssertTrue(CatalogError.unsupportedSchema(.milkyWay, version: 7).description.contains("7"))
        XCTAssertEqual(CatalogFile.allCases.map(\.fileName), ["stars.json", "dsos.json", "constellations.json", "milkyway.json"])
    }

    func testLoadReportKeepsOnlyTheFirstIssues() {
        var report = CatalogLoadReport()
        XCTAssertTrue(report.isClean)
        for index in 0..<100 {
            report.reject(\.stars, "problem \(index)")
        }
        XCTAssertEqual(report.stars.rejected, 100)
        XCTAssertEqual(report.rejectedCount, 100)
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.issues.count, CatalogLoadReport.maximumIssueCount)
        XCTAssertEqual(report.issues.first, "problem 0")
        report.reject(\.milkyWayRings, "ring")
        XCTAssertEqual(report.rejectedCount, 101)
        XCTAssertEqual(report.milkyWayRings.rejected, 1)
        XCTAssertEqual(report.issues.count, CatalogLoadReport.maximumIssueCount, "the list is capped")
    }
}

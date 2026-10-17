import XCTest
@testable import LodestarKit

final class CatalogSortingTests: XCTestCase {
    private func deepSky(id: String, name: String? = nil, magnitude: Double? = nil, number: Int? = nil) -> String {
        let names = name.map { #","names":["\#($0)"]"# } ?? ""
        let magnitudeMember = magnitude.map { #","vm":\#($0)"# } ?? ""
        let messier = number.map { #","m":\#($0)"# } ?? ""
        return #"{"id":"\#(id)"\#(messier)\#(names),"t":"G","ra":10.0,"de":20.0,"c":"And"\#(magnitudeMember)}"#
    }

    private func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        var state = seed
        var result = items
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            result.swapAt(index, Int((state >> 33) % UInt64(index + 1)))
        }
        return result
    }

    // MARK: By name

    func testNamesSortAlphabeticallyWithNumbersInNumericOrder() throws {
        var records: [String] = []
        for number in 1...12 {
            records.append(deepSky(id: "M" + String(number), number: number))
        }
        records += [deepSky(id: "NGC9"), deepSky(id: "NGC10"), deepSky(id: "NGC100")]
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: records)
        let objects = catalog.objects.filter { $0.id.hasPrefix("dso.") }
        let expected = (1...12).map { "M \($0)" } + ["NGC 9", "NGC 10", "NGC 100"]
        XCTAssertEqual(catalog.sorted(objects, by: .name).map(\.name), expected)
        for seed in 1...5 {
            XCTAssertEqual(catalog.sorted(shuffled(objects, seed: UInt64(seed)), by: .name).map(\.name), expected, "seed \(seed)")
        }
    }

    func testNamesSortIgnoringCaseDiacriticsAndGreekLetters() throws {
        let stars = [
            CatalogFixture.star(hip: 1, name: "Zed"), CatalogFixture.star(hip: 2, name: "Éclair"),
            CatalogFixture.star(hip: 3, name: "Eagle"), CatalogFixture.star(hip: 4, name: "Ångström"),
            CatalogFixture.star(hip: 5, name: "fomalhaut"), CatalogFixture.star(hip: 6, extra: #","b":"γ""#),
            CatalogFixture.star(hip: 7, name: "Hadar"), CatalogFixture.star(hip: 8, name: "the-end"),
        ]
        let catalog = try CatalogFixture.syntheticCatalog(stars: stars)
        let objects = catalog.objects.filter { $0.id.hasPrefix("star.") }
        XCTAssertEqual(catalog.sorted(objects, by: .name).map(\.name),
                       ["Ångström", "Eagle", "Éclair", "fomalhaut", "γ Ori", "Hadar", "the-end", "Zed"])
    }

    func testNamesWithoutLatinLettersOrDigitsComeFirstInCharacterOrder() throws {
        let catalog = try CatalogFixture.catalog()
        let position = EquatorialCoordinate(rightAscension: 1, declination: 1)
        let targets = ["Орион", "日本", "Zed", "Андромеда", "★★", "M 5"].map { CelestialObject.custom(name: $0, j2000: position) }
        let expected = ["Андромеда", "Орион", "★★", "日本", "M 5", "Zed"]
        XCTAssertEqual(catalog.sorted(targets, by: .name).map(\.name), expected)
        XCTAssertEqual(catalog.sorted(targets.reversed(), by: .name).map(\.name), expected)
        XCTAssertEqual(catalog.sorted(shuffled(targets, seed: 3), by: .name).map(\.name), expected)
    }

    func testEqualNamesAreOrderedByIdentifier() throws {
        let stars = [CatalogFixture.star(hip: 30, name: "Twin"), CatalogFixture.star(hip: 20, name: "twin"),
                     CatalogFixture.star(hip: 10, name: "TWIN"), CatalogFixture.star(hip: 100, name: "Twin ")]
        let catalog = try CatalogFixture.syntheticCatalog(stars: stars)
        let objects = catalog.objects.filter { $0.id.hasPrefix("star.") }
        let expected = ["star.hip10", "star.hip100", "star.hip20", "star.hip30"]
        XCTAssertEqual(catalog.sorted(objects, by: .name).map(\.id), expected)
        XCTAssertEqual(catalog.sorted(objects.reversed(), by: .name).map(\.id), expected)
        XCTAssertEqual(catalog.sorted(shuffled(objects, seed: 7), by: .name).map(\.id), expected)
    }

    // MARK: By magnitude

    func testMagnitudeOrderPutsBrightObjectsFirstAndUnknownMagnitudesLast() throws {
        let stars = [CatalogFixture.star(hip: 1, name: "Dim", magnitude: 6.2), CatalogFixture.star(hip: 2, name: "Bright", magnitude: -0.5),
                     CatalogFixture.star(hip: 3, name: "Middle", magnitude: 3.1), CatalogFixture.star(hip: 4, name: "Twin B", magnitude: 3.1),
                     CatalogFixture.star(hip: 5, name: "Twin A", magnitude: 3.1)]
        let dsos = [deepSky(id: "NGC1", name: "Faint Smudge", magnitude: 11), deepSky(id: "NGC2", name: "Unknown Cloud"),
                    deepSky(id: "NGC3", name: "Another Unknown"), deepSky(id: "NGC4", name: "Negative", magnitude: -2.5)]
        let catalog = try CatalogFixture.syntheticCatalog(stars: stars, deepSky: dsos)
        let sorted = catalog.sorted(catalog.objects, by: .magnitude)
        let names = sorted.map(\.name)
        // Solar-system bodies are placed by a typical peak magnitude, among the other objects.
        XCTAssertEqual(Array(names.prefix(16)),
                       ["Sun", "Moon", "Venus", "Jupiter", "Negative", "Mars", "Mercury", "Bright", "Saturn", "Middle", "Twin A",
                        "Twin B", "Uranus", "Dim", "Neptune", "Faint Smudge"])
        // Objects without a magnitude come last, ordered by name.
        let tail = sorted.suffix(5)
        XCTAssertTrue(tail.allSatisfy { $0.rankingMagnitude == .infinity })
        XCTAssertEqual(tail.map(\.name), ["Another Unknown", "Galactic Center", "North Celestial Pole", "South Celestial Pole", "Unknown Cloud"])
        for seed in 1...5 {
            XCTAssertEqual(catalog.sorted(shuffled(catalog.objects, seed: UInt64(seed)), by: .magnitude).map(\.id), sorted.map(\.id), "seed \(seed)")
        }
    }

    func testSolarSystemBodiesSortByTypicalBrightness() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.sorted(catalog.objects(in: .solarSystem), by: .magnitude).map(\.id),
                       ["sun", "moon", "planet.venus", "planet.jupiter", "planet.mars", "planet.mercury", "planet.saturn",
                        "planet.uranus", "planet.neptune"])
        XCTAssertEqual(catalog.sorted(catalog.objects(in: .solarSystem), by: .name).map(\.id),
                       ["planet.jupiter", "planet.mars", "planet.mercury", "moon", "planet.neptune", "planet.saturn", "sun",
                        "planet.uranus", "planet.venus"])
    }

    func testSortingTheWholeCatalog() throws {
        let catalog = try CatalogFixture.catalog()
        let byMagnitude = catalog.sorted(catalog.objects, by: .magnitude)
        XCTAssertEqual(byMagnitude.count, catalog.objects.count)
        XCTAssertEqual(Set(byMagnitude.map(\.id)), Set(catalog.objects.map(\.id)))
        let rankings = byMagnitude.map(\.rankingMagnitude)
        XCTAssertEqual(rankings, rankings.sorted())
        XCTAssertEqual(Array(byMagnitude.prefix(3).map(\.id)), ["sun", "moon", "planet.venus"])
        let unknown = byMagnitude.drop { $0.rankingMagnitude != .infinity }
        XCTAssertFalse(unknown.isEmpty)
        XCTAssertTrue(unknown.allSatisfy { $0.magnitude == nil && !$0.isSolarSystem }, "unknown magnitudes are contiguous at the end")
        XCTAssertTrue(unknown.contains { $0.id == "special.ncp" })

        let byName = catalog.sorted(catalog.listedObjects, by: .name)
        let keys = byName.map { SearchText.key(for: $0.name).bytes }
        for (first, second) in zip(keys, keys.dropFirst()) {
            XCTAssertFalse(SearchText.naturalPrecedes(second, first))
        }
        XCTAssertEqual(catalog.sorted(byName, by: .name).map(\.id), byName.map(\.id), "sorting is idempotent")
        XCTAssertEqual(catalog.sorted(byName.reversed(), by: .name).map(\.id), byName.map(\.id))
        XCTAssertEqual(catalog.sorted(shuffled(byName, seed: 99), by: .name).map(\.id), byName.map(\.id))
    }

    func testSortingEdgeCases() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertTrue(catalog.sorted([], by: .name).isEmpty)
        XCTAssertTrue(catalog.sorted([], by: .magnitude).isEmpty)
        let single = [try XCTUnwrap(catalog.object(id: "dso.M31"))]
        XCTAssertEqual(catalog.sorted(single, by: .name), single)
        XCTAssertEqual(catalog.sorted(single + single, by: .magnitude), single + single, "duplicates are kept")
        let custom = CelestialObject.custom(name: "Alpha custom", j2000: EquatorialCoordinate(rightAscension: 1, declination: 1))
        let mixed = catalog.sorted([try XCTUnwrap(catalog.object(id: "dso.M31")), custom, try XCTUnwrap(catalog.object(id: "sun"))], by: .name)
        XCTAssertEqual(mixed.map(\.name), ["Alpha custom", "Andromeda Galaxy", "Sun"], "objects that are not in the catalog sort too")
        XCTAssertEqual(CatalogSortOrder.allCases, [.name, .magnitude])
    }
}

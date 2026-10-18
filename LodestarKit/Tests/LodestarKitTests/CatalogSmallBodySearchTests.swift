import XCTest
@testable import LodestarKit

private typealias Fixture = CatalogSmallBodyFixture

/// Search, listing, ordering and the runtime add/replace of comets and asteroids in a catalog.
final class CatalogSmallBodySearchTests: XCTestCase {
    private func bundled() throws -> Catalog { try CatalogFixture.catalog() }

    private func catalog() throws -> Catalog { try Fixture.catalog() }

    private func ids(_ results: [CatalogSearchResult]) -> [String] { results.map(\.id) }

    private func first(_ query: String) throws -> CatalogSearchResult {
        try XCTUnwrap(try catalog().search(query, limit: 5).first, query)
    }

    // MARK: Search by designation and name

    func testCometsAreFoundByDesignationAndName() throws {
        let byName = try first("Tsuchinshan")
        XCTAssertEqual(byName.id, "comet.C/2023 A3")
        XCTAssertEqual(byName.kind, .prefix)
        XCTAssertEqual(byName.matchedText, "Tsuchinshan-ATLAS")

        let byDesignation = try first("C/2023 A3")
        XCTAssertEqual(byDesignation.id, "comet.C/2023 A3")
        XCTAssertEqual(byDesignation.kind, .exact)
        XCTAssertEqual(byDesignation.matchedText, "C/2023 A3")
        for spelling in ["c/2023 a3", "C2023A3", "c 2023 a3", "2023 A3"] {
            XCTAssertEqual(try first(spelling).id, "comet.C/2023 A3", spelling)
        }
        XCTAssertEqual(try first("2023 A3").kind, .wordPrefix)

        let title = try first("C/2023 A3 (Tsuchinshan-ATLAS)")
        XCTAssertEqual(title.id, "comet.C/2023 A3")
        XCTAssertEqual(title.kind, .exact)
        XCTAssertEqual(title.matchedText, "C/2023 A3 (Tsuchinshan-ATLAS)")

        // "Atlas" is also a star of the Pleiades, an exact match, which ranks above the later word of the comet's name.
        let atlas = try catalog().search("atlas")
        XCTAssertEqual(atlas.first?.id, "star.hip17847")
        XCTAssertEqual(atlas.first?.kind, .exact)
        let comet = try XCTUnwrap(atlas.first { $0.id == "comet.C/2023 A3" })
        XCTAssertEqual(comet.kind, .wordPrefix, "a later word of the name")

        XCTAssertEqual(try first("12P").id, "comet.12P")
        XCTAssertEqual(try first("12P").kind, .exact)
        XCTAssertEqual(try first("Pons-Brooks").id, "comet.12P")
        XCTAssertEqual(try first("pons brooks").id, "comet.12P")
        XCTAssertEqual(try first("12P/Pons-Brooks").id, "comet.12P")
        XCTAssertEqual(try first("Halley").id, "comet.1P")
        XCTAssertEqual(try first("Hale-Bopp").id, "comet.C/1995 O1")
        XCTAssertEqual(try first("encke").id, "comet.2P")
    }

    func testAsteroidsAreFoundByNumberAndName() throws {
        let byName = try first("Vesta")
        XCTAssertEqual(byName.id, "asteroid.4")
        XCTAssertEqual(byName.kind, .exact)
        XCTAssertEqual(byName.matchedText, "Vesta")

        let byTitle = try first("4 Vesta")
        XCTAssertEqual(byTitle.id, "asteroid.4")
        XCTAssertEqual(byTitle.kind, .exact)
        XCTAssertEqual(byTitle.matchedText, "(4) Vesta")
        XCTAssertEqual(try first("(4) Vesta").id, "asteroid.4")

        XCTAssertEqual(try first("Ceres").id, "asteroid.1")
        XCTAssertEqual(try first("1 Ceres").id, "asteroid.1")
        XCTAssertEqual(try first("Eros").id, "asteroid.433")
        XCTAssertEqual(try first("2024 YR4").id, "asteroid.2024 YR4")
        XCTAssertEqual(try first("2024 YR4").kind, .exact)
        XCTAssertEqual(try first("yr4").id, "asteroid.2024 YR4")

        // The number alone is an exact match of the designation "(4)".
        let byNumber = try first("4")
        XCTAssertEqual(byNumber.id, "asteroid.4")
        XCTAssertEqual(byNumber.kind, .exact)
        XCTAssertEqual(byNumber.matchedText, "(4)")
    }

    func testTheObjectsOfAResultAreTheCatalogObjects() throws {
        let catalog = try catalog()
        let bundled = try bundled()
        for query in ["Vesta", "Tsuchinshan", "12P", "yr4"] {
            let result = try first(query)
            XCTAssertEqual(catalog.object(id: result.id), result.object, query)
            XCTAssertTrue(catalog.smallBodies.contains(result.object), query)
            XCTAssertTrue(catalog.objects.contains(result.object), query)
        }
        XCTAssertEqual(catalog.object(id: "asteroid.4"), CelestialObject(smallBody: try Fixture.vesta))
        XCTAssertEqual(catalog.object(id: "asteroid.4")?.smallBody, try Fixture.vesta)
        XCTAssertNil(catalog.object(id: "asteroid.99999"))
        XCTAssertNil(bundled.object(id: "asteroid.4"), "the bundled catalog has no small bodies")
        XCTAssertTrue(bundled.search("Vesta").allSatisfy { $0.object.category != .asteroid })
    }

    func testBundledSearchResultsAreUnchangedByAddedBodies() throws {
        let catalog = try catalog()
        let bundled = try bundled()
        for query in ["sirius", "m31", "alpha cma", "vega", "orion", "jupiter", "andgal", "zzzz", "m 31", "α¹ cen", "mars"] {
            XCTAssertEqual(bundled.search(query), catalog.search(query), query)
            XCTAssertEqual(bundled.search(query, limit: 3), catalog.search(query, limit: 3), query)
        }
    }

    func testResultsOfBothSourcesAreMergedByKindThenRank() throws {
        // Three exact matches of "Sirius": the star, a showpiece comet fainter than it and one brighter than any star.
        let dim = try Fixture.comet("C/2040 S1", "Sirius", 3.0)
        let brilliant = try Fixture.comet("C/2040 S2", "Sirius", -5.0)
        let merged = try bundled().withSmallBodies([dim, brilliant])
        let results = merged.search("sirius")
        XCTAssertEqual(Array(ids(results).prefix(3)), ["comet.C/2040 S2", "star.hip32349", "comet.C/2040 S1"])
        XCTAssertTrue(results.prefix(3).allSatisfy { $0.kind == .exact })
        // The same result list as if all objects were in one index: nothing is lost with a small limit.
        XCTAssertEqual(Array(results.prefix(2)), merged.search("sirius", limit: 2))
        XCTAssertEqual(Array(results.prefix(1)), merged.search("sirius", limit: 1))
        XCTAssertTrue(merged.search("sirius", limit: 0).isEmpty)
        XCTAssertTrue(merged.search("sirius", limit: -3).isEmpty)
        // A better kind of match beats a better object: "Siriusfoo" is only a prefix of the comet's name.
        let prefixOnly = try bundled().withSmallBodies([try Fixture.comet("C/2040 S3", "Siriusfoo", -9.0)])
        XCTAssertEqual(Array(ids(prefixOnly.search("sirius")).prefix(2)), ["star.hip32349", "comet.C/2040 S3"])
    }

    func testFuzzySuggestionsOnlyAppearWithoutBetterMatchesInEitherSource() throws {
        let bundled = try bundled()
        // "ponbro" is only a loose match of "Pons-Brooks" (and of nothing in the bundled data): suggested.
        let loose = try catalog().search("ponbro")
        XCTAssertEqual(ids(loose), ["comet.12P"])
        XCTAssertEqual(loose.first?.kind, .fuzzy)
        // "andgal" is only a loose match of the Andromeda Galaxy; an exact match among the small bodies hides it.
        XCTAssertTrue(bundled.search("andgal").allSatisfy { $0.kind == .fuzzy })
        let named = bundled.withSmallBodies([try Fixture.comet("C/2041 A1", "Andgal", 9.0)])
        XCTAssertEqual(ids(named.search("andgal")), ["comet.C/2041 A1"])
        // And the other way round: a loose match among the small bodies does not appear next to a real match.
        let looseComet = bundled.withSmallBodies([try Fixture.comet("C/2041 B1", "Mxx 3y 1z", 9.0)])
        XCTAssertEqual(bundled.search("m31"), looseComet.search("m31"))
        XCTAssertEqual(ids(looseComet.search("mxx3y1z")), ["comet.C/2041 B1"])
    }

    func testLimitsAreConsistentWithTheFullResultAndTheOrderIsTotal() throws {
        let real = try Fixture.comets + Fixture.asteroids
        let many = try bundled().withSmallBodies(SyntheticOrbits(seed: 5).bodies(400) + real)
        for query in ["a", "m", "c", "ve", "1", "s1", "c/s", "orion", "andgal", "pons", "4", "(s", "xyzzy"] {
            let full = many.search(query, limit: Int.max)
            XCTAssertEqual(full.count, Set(full.map(\.id)).count, "\(query): every object once")
            for limit in [1, 2, 3, 7, 50, 200] {
                XCTAssertEqual(Array(full.prefix(limit)), many.search(query, limit: limit), "\(query) limit \(limit)")
            }
            // Better kinds first; equal kinds in the order of listed, prominence, brightness estimate, name, identifier.
            for (lhs, rhs) in zip(full, full.dropFirst()) {
                let ordered = lhs.kind < rhs.kind
                    || (lhs.kind == rhs.kind && CatalogOrdering.searchOrder(CatalogOrdering.item(for: lhs.object),
                                                                            CatalogOrdering.item(for: rhs.object)))
                XCTAssertTrue(ordered, "\(query): \(lhs.id) before \(rhs.id)")
            }
        }
    }

    // MARK: Listing and ordering

    func testSolarSystemListsIncludeTheListedSmallBodies() throws {
        let catalog = try catalog()
        let bundled = try bundled()
        let group = catalog.objects(in: .solarSystem)
        let listedSmall = catalog.smallBodies.filter(\.isListed)
        XCTAssertEqual(group.count, 9 + listedSmall.count)
        XCTAssertTrue(bundled.objects(in: .solarSystem).allSatisfy { group.contains($0) })
        XCTAssertTrue(listedSmall.allSatisfy { group.contains($0) })
        XCTAssertFalse(group.contains { $0.id == "asteroid.2024 YR4" }, "an obscure asteroid is not listed")
        XCTAssertEqual(group, catalog.sorted(group, by: .name), "sorted by name")
        // The other groups are the bundled ones.
        for other in ObjectGroup.allCases where other != .solarSystem {
            XCTAssertEqual(bundled.objects(in: other), catalog.objects(in: other), other.rawValue)
        }
        XCTAssertTrue(listedSmall.allSatisfy { catalog.listedObjects.contains($0) })
        XCTAssertFalse(catalog.listedObjects.contains { $0.id == "asteroid.2024 YR4" })
        XCTAssertEqual(catalog.listedObjects.count, bundled.listedObjects.count + listedSmall.count)
        XCTAssertEqual(bundled.listedObjects, Array(catalog.listedObjects.prefix(bundled.listedObjects.count)))
    }

    func testSmallBodiesComeAfterTheBundledObjectsBrightestFirst() throws {
        let catalog = try catalog()
        let bundled = try bundled()
        XCTAssertEqual(catalog.objects.count, bundled.objects.count + 9)
        XCTAssertEqual(bundled.objects, Array(catalog.objects.prefix(bundled.objects.count)))
        XCTAssertEqual(catalog.smallBodies, Array(catalog.objects.dropFirst(bundled.objects.count)))
        let estimates = catalog.smallBodies.map(\.rankingMagnitude)
        XCTAssertEqual(estimates, estimates.sorted())
        XCTAssertEqual(catalog.smallBodies.first?.id, "comet.C/1995 O1")
        XCTAssertEqual(catalog.smallBodies.last?.id, "asteroid.2024 YR4")
        let ceresAndVesta = [CelestialObject(smallBody: try Fixture.ceres), CelestialObject(smallBody: try Fixture.vesta)]
        XCTAssertEqual(catalog.sorted(ceresAndVesta, by: .magnitude).map(\.id), ["asteroid.4", "asteroid.1"])
        XCTAssertEqual(catalog.sorted(ceresAndVesta.reversed(), by: .name).map(\.id), ["asteroid.1", "asteroid.4"])
    }

    func testOrderDoesNotDependOnTheOrderOfTheInput() throws {
        let all = try Fixture.comets + Fixture.asteroids
        let forward = try bundled().withSmallBodies(all)
        let backward = try bundled().withSmallBodies(all.reversed())
        XCTAssertEqual(forward.smallBodies, backward.smallBodies)
        XCTAssertEqual(forward.objects(in: .solarSystem), backward.objects(in: .solarSystem))
        for query in ["a", "c/20", "vesta", "p", "1"] {
            XCTAssertEqual(forward.search(query, limit: 20), backward.search(query, limit: 20), query)
        }
    }

    // MARK: Add and replace at run time

    func testWithSmallBodiesLeavesTheOriginalAndSharesTheBundledData() throws {
        let bundled = try bundled()
        let objectCount = bundled.objects.count
        let added = bundled.withSmallBodies([try Fixture.tsuchinshanAtlas, try Fixture.ceres])
        XCTAssertEqual(bundled.objects.count, objectCount)
        XCTAssertTrue(bundled.smallBodies.isEmpty)
        XCTAssertNil(bundled.object(id: "comet.C/2023 A3"))
        XCTAssertEqual(Set(added.smallBodies.map(\.id)), ["comet.C/2023 A3", "asteroid.1"])
        XCTAssertEqual(added.objects.count, objectCount + 2)
        XCTAssertNotNil(added.object(id: "comet.C/2023 A3"))
        XCTAssertNotNil(added.object(id: "star.hip32349"), "the bundled objects are still found")
        XCTAssertEqual(bundled.renderStars, added.renderStars)
        XCTAssertEqual(bundled.deepSkyObjects, added.deepSkyObjects)
        XCTAssertEqual(bundled.constellations, added.constellations)
        XCTAssertEqual(bundled.loadReport, added.loadReport)
        XCTAssertEqual(bundled.deepSkyObjects(upTo: .showpiece), added.deepSkyObjects(upTo: .showpiece))
        XCTAssertEqual(bundled.objects(in: .messier), added.objects(in: .messier))
        XCTAssertEqual(bundled.searchIndex.objectsByRank, added.searchIndex.objectsByRank)
        XCTAssertEqual(bundled.constellation(abbreviation: "CMa"), added.constellation(abbreviation: "CMa"))
    }

    func testWithSmallBodiesReplacesTheEarlierSet() throws {
        let bundled = try bundled()
        let first = bundled.withSmallBodies([try Fixture.tsuchinshanAtlas, try Fixture.ceres])
        let second = first.withSmallBodies([try Fixture.vesta])
        XCTAssertEqual(second.smallBodies.map(\.id), ["asteroid.4"])
        XCTAssertNil(second.object(id: "comet.C/2023 A3"))
        XCTAssertNil(second.object(id: "asteroid.1"))
        XCTAssertTrue(second.search("Tsuchinshan").allSatisfy { $0.object.category != .comet })
        XCTAssertEqual(second.search("vesta").first?.id, "asteroid.4")
        // The first catalog still has its set.
        XCTAssertEqual(first.smallBodies.count, 2)
        XCTAssertEqual(first.search("Tsuchinshan").first?.id, "comet.C/2023 A3")
        // An empty list removes them all; on a catalog without any, it is the catalog itself.
        let none = second.withSmallBodies([])
        XCTAssertTrue(none.smallBodies.isEmpty)
        XCTAssertEqual(none.objects, bundled.objects)
        XCTAssertTrue(bundled.withSmallBodies([]) === bundled)
        XCTAssertEqual(bundled.search("vesta"), none.search("vesta"))
    }

    func testAddingSmallBodiesKeepsTheOthersAndReplacesTheSameIdentifier() throws {
        let bundled = try bundled()
        let first = bundled.withSmallBodies([try Fixture.tsuchinshanAtlas, try Fixture.ceres])
        let fresherCeres = try withNewerEpoch(try Fixture.ceres)
        let second = first.addingSmallBodies([try Fixture.vesta, fresherCeres])
        XCTAssertEqual(Set(second.smallBodies.map(\.id)), ["comet.C/2023 A3", "asteroid.1", "asteroid.4"])
        XCTAssertEqual(second.smallBodies.count, 3)
        XCTAssertEqual(second.object(id: "asteroid.1")?.smallBody, fresherCeres, "the new elements replace the old ones")
        XCTAssertEqual(first.object(id: "asteroid.1")?.smallBody, try Fixture.ceres, "the first catalog is unchanged")
        XCTAssertEqual(second.search("Ceres").filter { $0.id == "asteroid.1" }.count, 1, "no duplicate in the results")
        XCTAssertEqual(second.smallBodies,
                       bundled.withSmallBodies([try Fixture.tsuchinshanAtlas, try Fixture.vesta, fresherCeres]).smallBodies)
        // Adding nothing changes nothing.
        XCTAssertEqual(first.smallBodies, first.addingSmallBodies([]).smallBodies)
        XCTAssertEqual(bundled.objects, bundled.addingSmallBodies([]).objects)
    }

    func testTheLastBodyWithAnIdentifierWins() throws {
        let bundled = try bundled()
        let fresherCeres = try withNewerEpoch(try Fixture.ceres)
        let ceres = try Fixture.ceres
        let catalogWithBoth = bundled.withSmallBodies([ceres, try Fixture.vesta, fresherCeres, ceres])
        XCTAssertEqual(catalogWithBoth.smallBodies.count, 2)
        XCTAssertEqual(catalogWithBoth.object(id: "asteroid.1")?.smallBody, ceres, "the last one is the original again")
        let other = bundled.withSmallBodies([ceres, fresherCeres])
        XCTAssertEqual(other.object(id: "asteroid.1")?.smallBody, fresherCeres)
        XCTAssertEqual(other.smallBodies.count, 1)
    }

    func testACometAndAnAsteroidWithTheSameNumberDoNotClash() throws {
        // The identifier includes the kind: "comet.1P" and "asteroid.1" never meet, and 1P is not Ceres.
        let both = try bundled().withSmallBodies([try Fixture.halley, try Fixture.ceres])
        XCTAssertEqual(both.search("1P").first?.id, "comet.1P")
        XCTAssertEqual(both.search("1 Ceres").first?.id, "asteroid.1")
        XCTAssertEqual(both.smallBodies.count, 2)
    }

    func testAtMostTheMaximumNumberOfBodiesIsTaken() throws {
        XCTAssertEqual(Catalog.maximumSmallBodyCount, 100_000)
        let synthetic = SyntheticOrbits(seed: 20_261_018).bodies(Catalog.maximumSmallBodyCount + 50)
        XCTAssertEqual(synthetic.count, Catalog.maximumSmallBodyCount + 50)
        let many = try bundled().withSmallBodies(synthetic)
        XCTAssertEqual(many.smallBodies.count, Catalog.maximumSmallBodyCount)
        XCTAssertEqual(Set(many.smallBodies.map(\.id)), Set(synthetic.prefix(Catalog.maximumSmallBodyCount).map(\.id)))
        XCTAssertNil(many.object(id: try XCTUnwrap(synthetic.last).id))
        XCTAssertNotNil(many.object(id: try XCTUnwrap(synthetic.first).id))
        // A body beyond the limit that replaces one within it is still taken.
        let replaced = SyntheticOrbits(seed: 1).bodies(3)
        XCTAssertEqual(try bundled().withSmallBodies(replaced + replaced).smallBodies.count, 3)
    }

    func testNameAndIdentifierLookupsOfSyntheticBodies() throws {
        let bodies = SyntheticOrbits(seed: 77).bodies(300)
        let many = try bundled().withSmallBodies(bodies)
        XCTAssertEqual(many.smallBodies.count, 300)
        for body in bodies.prefix(40) {
            let object = try XCTUnwrap(many.object(id: body.id), body.id)
            XCTAssertEqual(object.smallBody, body)
            XCTAssertEqual(many.search(body.title, limit: 3).first?.id, body.id, body.id)
            XCTAssertEqual(object.category, body.kind == .comet ? .comet : .asteroid)
        }
    }

    // MARK: Helpers

    /// The same asteroid with another epoch: a refreshed element set that has the identifier of the old one.
    private func withNewerEpoch(_ body: SmallBody) throws -> SmallBody {
        let orbit = try XCTUnwrap(SmallBodyElements.fromMeanAnomaly(
            semiMajorAxisAU: try XCTUnwrap(body.orbit.semiMajorAxisAU), eccentricity: body.orbit.eccentricity,
            inclination: body.orbit.inclination, argumentOfPerihelion: body.orbit.argumentOfPerihelion,
            longitudeOfAscendingNode: body.orbit.longitudeOfAscendingNode, meanAnomaly: 100,
            epochJulianDayTT: body.orbit.epochJulianDayTT + 200))
        return try XCTUnwrap(SmallBody(designation: body.designation, name: body.name, kind: body.kind, number: body.number,
                                       orbit: orbit, photometry: body.photometry))
    }
}

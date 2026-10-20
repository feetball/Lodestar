import XCTest
import LodestarKit
@testable import AppCore

/// A synthetic catalog with objects in every catalogue the filter knows, built from the JSON of the real data files.
private enum ObjectsCatalogueFixture {
    private static let loaded: Result<Catalog, Error> = Result { try ObjectsCatalogueFixture.makeCatalog() }

    static func catalog() throws -> Catalog {
        try loaded.get()
    }

    static func object(_ id: String) throws -> CelestialObject {
        try XCTUnwrap(try catalog().object(id: id), id)
    }

    private static func file(_ key: String, _ records: [String]) -> Data {
        Data(#"{"schema":1,"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    private static func galaxy(_ id: String, extra: String = "") -> String {
        #"{"id":"\#(id)","t":"G","ra":10.0,"de":20.0,"c":"And","vm":9.0,"p":3\#(extra)}"#
    }

    private static func cluster(_ id: String, extra: String = "") -> String {
        #"{"id":"\#(id)","t":"OCl","ra":20.0,"de":20.0,"c":"And","vm":9.0,"p":3\#(extra)}"#
    }

    private static func dark(_ id: String) -> String {
        #"{"id":"\#(id)","t":"DrkN","ra":30.0,"de":20.0,"c":"And","p":4}"#
    }

    private static func makeCatalog() throws -> Catalog {
        let deepSky = [
            galaxy("M31", extra: #","m":31,"ngc":[224]"#),
            // Two NGC numbers and a Messier number: it is listed once in the NGC list, at its first number.
            #"{"id":"NGC6523","m":8,"ngc":[6523,6533],"t":"HII","ra":270.9,"de":-24.4,"c":"Sgr","vm":6.0,"p":1}"#,
            cluster("NGC7000", extra: #","ngc":[7000],"cat":["C20"]"#),
            galaxy("NGC100", extra: #","ngc":[100]"#),
            // An NGC object that also has an IC number.
            galaxy("NGC200", extra: #","ngc":[200],"ic":[50]"#),
            galaxy("IC30", extra: #","ic":[30]"#),
            galaxy("Sh2-155"),
            dark("B33"), dark("B67"), dark("B67a"), dark("B67z"), dark("B68"), dark("LDN1622"),
            // Collinder 399 that is also Melotte 111.
            cluster("Cl399", extra: #","cat":["Mel111"]"#),
            cluster("Mel20"), cluster("Tr14"), cluster("St2"),
            galaxy("ESO56-115"),
        ]
        let stars = [#"{"hip":1001,"n":"Alpha Test","c":"Ori","ra":10.0,"de":20.0,"m":0.5}"#]
        let constellations = [
            #"{"abbr":"And","name":"Andromeda","genitive":"Andromedae","label":[10.0,40.0],"lines":[[[10.0,30.0],[20.0,40.0]]]}"#,
        ]
        let milkyWay = [#"{"level":1,"polygons":[[[10,10],[20,10],[20,20]]],"holes":[]}"#]
        return try Catalog(starsData: file("stars", stars), dsosData: file("objects", deepSky),
                           constellationsData: file("constellations", constellations),
                           milkyWayData: file("levels", milkyWay))
    }
}

final class ObjectsCatalogueFilterTests: XCTestCase {
    private func ids(_ filter: ObjectsCatalogueFilter) throws -> [String] {
        filter.objects(in: try ObjectsCatalogueFixture.catalog()).map(\.id)
    }

    private func key(_ filter: ObjectsCatalogueFilter, _ id: String) throws -> Double? {
        filter.numberKey(of: try ObjectsCatalogueFixture.object(id))
    }

    // MARK: Names

    func testTheFiltersAreInChipOrderWithTheirRawValuesAsIdentifiers() {
        XCTAssertEqual(ObjectsCatalogueFilter.allCases,
                       [.all, .messier, .caldwell, .sharpless, .barnard, .lynds, .ngcIC, .clusters])
        XCTAssertEqual(ObjectsCatalogueFilter.allCases.map(\.id),
                       ["all", "messier", "caldwell", "sharpless", "barnard", "lynds", "ngcIC", "clusters"])
    }

    func testTitles() {
        XCTAssertEqual(ObjectsCatalogueFilter.allCases.map(\.title),
                       ["All", "Messier", "Caldwell", "Sharpless", "Barnard", "Lynds", "NGC/IC", "Clusters"])
    }

    func testFullTitles() {
        XCTAssertEqual(ObjectsCatalogueFilter.allCases.map(\.fullTitle),
                       ["All objects", "Messier catalogue", "Caldwell catalogue",
                        "Sharpless catalogue of emission nebulae", "Barnard catalogue of dark nebulae",
                        "Lynds catalogue of dark nebulae", "NGC and IC catalogues",
                        "Collinder, Melotte, Trumpler and Stock clusters"])
    }

    func testTheEngineCataloguesBehindEachFilter() {
        XCTAssertEqual(ObjectsCatalogueFilter.all.catalogues, [])
        XCTAssertEqual(ObjectsCatalogueFilter.messier.catalogues, [.messier])
        XCTAssertEqual(ObjectsCatalogueFilter.caldwell.catalogues, [.caldwell])
        XCTAssertEqual(ObjectsCatalogueFilter.sharpless.catalogues, [.sharpless])
        XCTAssertEqual(ObjectsCatalogueFilter.barnard.catalogues, [.barnard])
        XCTAssertEqual(ObjectsCatalogueFilter.lynds.catalogues, [.lynds])
        XCTAssertEqual(ObjectsCatalogueFilter.ngcIC.catalogues, [.ngc, .ic])
        XCTAssertEqual(ObjectsCatalogueFilter.clusters.catalogues, [.collinder, .melotte, .trumpler, .stock])
    }

    func testEveryCatalogueBelongsToExactlyOneFilterExceptAll() {
        var seen: [DeepSkyCatalogue] = []
        for filter in ObjectsCatalogueFilter.allCases {
            seen += filter.catalogues
        }
        XCTAssertEqual(Set(seen), Set(DeepSkyCatalogue.allCases))
        XCTAssertEqual(seen.count, DeepSkyCatalogue.allCases.count)
    }

    // MARK: Membership

    func testAllContainsEveryObject() throws {
        let catalog = try ObjectsCatalogueFixture.catalog()
        XCTAssertTrue(catalog.objects.allSatisfy { ObjectsCatalogueFilter.all.contains($0) })
    }

    func testAFilterContainsTheObjectsWithANumberInItsCatalogues() throws {
        let m31 = try ObjectsCatalogueFixture.object("dso.M31")
        XCTAssertTrue(ObjectsCatalogueFilter.messier.contains(m31))
        XCTAssertTrue(ObjectsCatalogueFilter.ngcIC.contains(m31), "M 31 is also NGC 224")
        XCTAssertFalse(ObjectsCatalogueFilter.caldwell.contains(m31))
        XCTAssertFalse(ObjectsCatalogueFilter.sharpless.contains(m31))
        XCTAssertFalse(ObjectsCatalogueFilter.clusters.contains(m31))
        let northAmerica = try ObjectsCatalogueFixture.object("dso.NGC7000")
        XCTAssertTrue(ObjectsCatalogueFilter.caldwell.contains(northAmerica))
        XCTAssertTrue(ObjectsCatalogueFilter.ngcIC.contains(northAmerica))
        XCTAssertFalse(ObjectsCatalogueFilter.messier.contains(northAmerica))
        XCTAssertTrue(ObjectsCatalogueFilter.sharpless.contains(try ObjectsCatalogueFixture.object("dso.Sh2-155")))
        XCTAssertTrue(ObjectsCatalogueFilter.barnard.contains(try ObjectsCatalogueFixture.object("dso.B33")))
        XCTAssertTrue(ObjectsCatalogueFilter.lynds.contains(try ObjectsCatalogueFixture.object("dso.LDN1622")))
        XCTAssertTrue(ObjectsCatalogueFilter.clusters.contains(try ObjectsCatalogueFixture.object("dso.Tr14")))
        XCTAssertTrue(ObjectsCatalogueFilter.clusters.contains(try ObjectsCatalogueFixture.object("dso.St2")))
    }

    func testObjectsWithoutACatalogueNumberBelongToNoFilterButAll() throws {
        for id in ["star.hip1001", "sun", "planet.mars", "special.ncp", "dso.ESO56-115"] {
            let object = try ObjectsCatalogueFixture.object(id)
            XCTAssertTrue(ObjectsCatalogueFilter.all.contains(object), id)
            for filter in ObjectsCatalogueFilter.allCases where filter != .all {
                XCTAssertFalse(filter.contains(object), "\(id) in \(filter.title)")
            }
        }
    }

    func testCustomTargetsBelongToAllOnly() {
        let target = CelestialObject.custom(name: "Mine", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertTrue(ObjectsCatalogueFilter.all.contains(target))
        XCTAssertFalse(ObjectsCatalogueFilter.messier.contains(target))
        XCTAssertFalse(ObjectsCatalogueFilter.ngcIC.contains(target))
    }

    // MARK: Catalogue lists

    func testAllHasNoCatalogueList() throws {
        XCTAssertEqual(try ids(.all), [])
    }

    func testTheMessierListIsInNumberOrder() throws {
        // M 8 (NGC 6523) before M 31.
        XCTAssertEqual(try ids(.messier), ["dso.NGC6523", "dso.M31"])
    }

    func testTheCaldwellSharplessBarnardAndLyndsLists() throws {
        XCTAssertEqual(try ids(.caldwell), ["dso.NGC7000"])
        XCTAssertEqual(try ids(.sharpless), ["dso.Sh2-155"])
        XCTAssertEqual(try ids(.lynds), ["dso.LDN1622"])
        // By number, then by letter: B 67, B 67a, B 67z, B 68.
        XCTAssertEqual(try ids(.barnard), ["dso.B33", "dso.B67", "dso.B67a", "dso.B67z", "dso.B68"])
    }

    func testTheNGCAndICListJoinsBothListsAndHoldsAnObjectOnce() throws {
        // NGC 100, 200, 224, 6523, 7000, then IC 30 and (IC 50 is NGC 200, already listed).
        XCTAssertEqual(try ids(.ngcIC),
                       ["dso.NGC100", "dso.NGC200", "dso.M31", "dso.NGC6523", "dso.NGC7000", "dso.IC30"])
    }

    func testTheClustersListFollowsCollinderMelotteTrumplerStockAndHoldsAnObjectOnce() throws {
        // Cl 399 is also Mel 111: it is listed once, with the Collinder clusters.
        XCTAssertEqual(try ids(.clusters), ["dso.Cl399", "dso.Mel20", "dso.Tr14", "dso.St2"])
    }

    func testEveryObjectOfACatalogueListIsContainedInItsFilter() throws {
        for filter in ObjectsCatalogueFilter.allCases {
            for object in filter.objects(in: try ObjectsCatalogueFixture.catalog()) {
                XCTAssertTrue(filter.contains(object), "\(object.id) in \(filter.title)")
            }
        }
    }

    // MARK: Number keys

    func testTheNumberKeyOfAMessierObjectIsItsNumberTimesTen() throws {
        XCTAssertEqual(try key(.all, "dso.M31"), 310)
        XCTAssertEqual(try key(.messier, "dso.M31"), 310)
        XCTAssertEqual(try key(.all, "dso.NGC6523"), 80, "Messier 8 counts, not NGC 6523")
    }

    func testTheNumberKeyUsesTheFirstCatalogueOfTheNumberingOrderForAll() throws {
        // Messier, Caldwell, NGC, IC, Sharpless, Barnard, Lynds, Collinder, Melotte, Trumpler, Stock.
        XCTAssertEqual(try key(.all, "dso.NGC7000"), 1_000_200, "Caldwell 20 comes before NGC 7000")
        XCTAssertEqual(try key(.all, "dso.NGC100"), 2_001_000)
        XCTAssertEqual(try key(.all, "dso.IC30"), 3_000_300)
        XCTAssertEqual(try key(.all, "dso.Sh2-155"), 4_001_550)
        XCTAssertEqual(try key(.all, "dso.B33"), 5_000_330)
        XCTAssertEqual(try key(.all, "dso.LDN1622"), 6_016_220)
        XCTAssertEqual(try key(.all, "dso.Cl399"), 7_003_990, "Collinder 399 comes before Melotte 111")
        XCTAssertEqual(try key(.all, "dso.Mel20"), 8_000_200)
        XCTAssertEqual(try key(.all, "dso.Tr14"), 9_000_140)
        XCTAssertEqual(try key(.all, "dso.St2"), 10_000_020)
    }

    func testTheNumberKeyOfAFilterCountsOnlyItsOwnCatalogues() throws {
        XCTAssertEqual(try key(.caldwell, "dso.NGC7000"), 200)
        XCTAssertEqual(try key(.ngcIC, "dso.NGC7000"), 70_000)
        XCTAssertNil(try key(.messier, "dso.NGC7000"))
        XCTAssertNil(try key(.sharpless, "dso.NGC7000"))
    }

    func testTheNumberKeyOfANGCICFilterPutsNGCBeforeICAndTakesTheFirstNumber() throws {
        XCTAssertEqual(try key(.ngcIC, "dso.NGC100"), 1_000)
        XCTAssertEqual(try key(.ngcIC, "dso.NGC200"), 2_000, "NGC 200 is also IC 50: the NGC number counts")
        XCTAssertEqual(try key(.ngcIC, "dso.IC30"), 1_000_300, "IC comes after NGC")
        XCTAssertEqual(try key(.ngcIC, "dso.NGC6523"), 65_230, "the first of NGC 6523 and NGC 6533")
        XCTAssertEqual(try key(.ngcIC, "dso.M31"), 2_240, "M 31 is NGC 224")
    }

    func testTheNumberKeyOfTheClustersFilterFollowsTheListOrder() throws {
        XCTAssertEqual(try key(.clusters, "dso.Cl399"), 3_990)
        XCTAssertEqual(try key(.clusters, "dso.Mel20"), 1_000_200)
        XCTAssertEqual(try key(.clusters, "dso.Tr14"), 2_000_140)
        XCTAssertEqual(try key(.clusters, "dso.St2"), 3_000_020)
    }

    func testTheLetterOfANumberOrdersItAfterTheBareNumber() throws {
        let plain = try XCTUnwrap(try key(.barnard, "dso.B67"))
        let lower = try XCTUnwrap(try key(.barnard, "dso.B67a"))
        let far = try XCTUnwrap(try key(.barnard, "dso.B67z"))
        let next = try XCTUnwrap(try key(.barnard, "dso.B68"))
        XCTAssertEqual(plain, 670)
        XCTAssertEqual(lower, 671, "a counts 1")
        XCTAssertEqual(far, 679, "letters from i on are all capped at 9")
        XCTAssertEqual(next, 680)
        XCTAssertLessThan(far, next)
    }

    func testObjectsWithoutANumberInTheFilterHaveNoKey() throws {
        for filter in ObjectsCatalogueFilter.allCases {
            XCTAssertNil(try key(filter, "star.hip1001"), filter.title)
            XCTAssertNil(try key(filter, "sun"), filter.title)
            XCTAssertNil(try key(filter, "dso.ESO56-115"), filter.title)
        }
    }
}

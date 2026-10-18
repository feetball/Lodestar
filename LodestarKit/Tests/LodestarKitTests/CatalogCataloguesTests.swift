import XCTest
@testable import LodestarKit

/// The deep-sky catalogues beyond Messier and NGC/IC (Caldwell, Sharpless 2, Barnard, Lynds, Collinder, Melotte,
/// Trumpler, Stock), the `cat` and `p` members of the data records, prominence and the catalogue lists.
///
/// Positions are checked against published values (SIMBAD and Wikipedia are named where they are used) with the
/// tolerance the source catalogue allows: Sharpless and Lynds give the center of a region or cloud to a fraction
/// of its size.
final class CatalogCataloguesTests: XCTestCase {
    private func catalog() throws -> Catalog { try CatalogFixture.catalog() }

    private func obj(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> CelestialObject {
        try XCTUnwrap(try catalog().object(id: id), id, file: file, line: line)
    }

    /// Angular distance in degrees between a J2000 position and an object.
    private func distance(_ ra: Double, _ dec: Double, _ id: String) throws -> Double {
        let position = try XCTUnwrap(try obj(id).j2000, id)
        let dRa = (position.rightAscension - ra) * cos((position.declination + dec) / 2 * Double.pi / 180)
        let dDec = position.declination - dec
        return (dRa * dRa + dDec * dDec).squareRoot()
    }

    private func ids(_ results: [CatalogSearchResult]) -> [String] { results.map(\.object.id) }

    // MARK: Counts

    func testCatalogueListsHaveTheCountsOfTheirCatalogues() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.objects(in: .messier).count, 110)
        XCTAssertEqual(catalog.objects(in: .caldwell).count, 109)
        XCTAssertEqual(catalog.objects(in: .sharpless).count, 313)
        XCTAssertEqual(catalog.objects(in: .barnard).count, 349)
        XCTAssertEqual(catalog.objects(in: .lynds).count, 398)
        XCTAssertEqual(catalog.objects(in: .ngc).count, 1225)
        XCTAssertEqual(catalog.objects(in: .ic).count, 167)
        XCTAssertEqual(catalog.objects(in: .collinder).count, 17)
        XCTAssertEqual(catalog.objects(in: .melotte).count, 9)
        XCTAssertEqual(catalog.objects(in: .trumpler).count, 2)
        XCTAssertEqual(catalog.objects(in: .stock).count, 1)
        XCTAssertEqual(catalog.deepSkyObjects.count, 2441 - catalog.loadReport.deepSkyObjects.merged)
        XCTAssertEqual(catalog.deepSkyObjects, catalog.objects.filter(\.isDeepSky))
        XCTAssertEqual(catalog.loadReport.rejectedCount, 0)
    }

    func testEveryCatalogueListIsOrderedByNumberAndHasNoRepeats() throws {
        let catalog = try catalog()
        for catalogue in DeepSkyCatalogue.allCases {
            let list = catalog.objects(in: catalogue)
            XCTAssertEqual(list.count, Set(list.map(\.id)).count, "\(catalogue) repeats an object")
            var previous: CatalogNumber?
            for object in list {
                XCTAssertTrue(object.catalogues.contains(catalogue), "\(object.id) is not in \(catalogue)")
                let number = try XCTUnwrap(object.catalogNumbers.first { $0.catalogue == catalogue })
                if let previous {
                    XCTAssertTrue(previous.number < number.number
                                  || (previous.number == number.number && previous.suffix <= number.suffix),
                                  "\(catalogue): \(previous.label) before \(number.label)")
                }
                previous = number
            }
        }
        func numbers(_ catalogue: DeepSkyCatalogue) -> [Int] {
            catalog.objects(in: catalogue).map { object in object.catalogNumbers.first { $0.catalogue == catalogue }?.number ?? 0 }
        }
        XCTAssertEqual(numbers(.caldwell), Array(1...109))
        XCTAssertEqual(numbers(.sharpless), Array(1...313))
        XCTAssertEqual(numbers(.messier), Array(1...110))
        XCTAssertEqual(catalog.objects(in: .messier).first?.id, "dso.M1")
    }

    func testCatalogNumbersAgreeWithTheDataFile() throws {
        let catalog = try catalog()
        let prefixes: [String: DeepSkyCatalogue] = [
            "M": .messier, "NGC": .ngc, "IC": .ic, "C": .caldwell, "B": .barnard, "LDN": .lynds,
            "Cl": .collinder, "Mel": .melotte, "Tr": .trumpler, "St": .stock,
        ]

        func number(_ text: String) -> CatalogNumber? {
            if text.hasPrefix("Sh2-") { return Int(text.dropFirst(4)).map { CatalogNumber(catalogue: .sharpless, number: $0) } }
            let prefix = String(text.prefix { $0.isASCII && $0.isLetter })
            let digits = String(text.dropFirst(prefix.count).prefix { $0.isASCII && $0.isNumber })
            let suffix = String(text.dropFirst(prefix.count + digits.count))
            guard let catalogue = prefixes[prefix], let value = Int(digits),
                  suffix.isEmpty || (suffix.count == 1 && suffix.first?.isASCII == true && suffix.first?.isLetter == true) else {
                return nil
            }
            return CatalogNumber(catalogue: catalogue, number: value, suffix: suffix)
        }

        var checked = 0
        for record in try CatalogFixture.rawDeepSky() {
            guard let object = catalog.object(id: "dso.\(record.id)") else { continue }
            var expected: [CatalogNumber] = []
            func add(_ candidate: CatalogNumber?) {
                if let candidate, !expected.contains(candidate) { expected.append(candidate) }
            }
            if let messier = record.m { add(CatalogNumber(catalogue: .messier, number: messier)) }
            for value in record.ngc ?? [] { add(CatalogNumber(catalogue: .ngc, number: value)) }
            for value in record.ic ?? [] { add(CatalogNumber(catalogue: .ic, number: value)) }
            add(number(record.id))
            for designation in record.cat ?? [] { add(number(designation)) }
            XCTAssertEqual(object.catalogNumbers, expected, record.id)
            var catalogues: [DeepSkyCatalogue] = []
            for entry in expected where !catalogues.contains(entry.catalogue) { catalogues.append(entry.catalogue) }
            XCTAssertEqual(object.catalogues, catalogues, record.id)
            checked += 1
        }
        XCTAssertEqual(checked, 2441 - catalog.loadReport.deepSkyObjects.merged)
    }

    // MARK: Caldwell

    func testCaldwellObjectsAreWhereMooresListPutsThem() throws {
        let catalog = try catalog()
        // Patrick Moore, 1995 (as in the Wikipedia list of Caldwell objects): Caldwell number -> NGC/IC object.
        let expected: [Int: String] = [
            1: "NGC188", 2: "NGC40", 4: "NGC7023", 5: "IC342", 6: "NGC6543", 11: "NGC7635",
            13: "NGC457", 19: "IC5146", 20: "NGC7000", 27: "NGC6888", 31: "IC405", 33: "NGC6992",
            34: "NGC6960", 38: "NGC4565", 39: "NGC2392", 49: "NGC2238", 55: "NGC7009", 63: "NGC7293",
            65: "NGC253", 77: "NGC5128", 80: "NGC5139", 92: "NGC3372", 94: "NGC4755", 103: "NGC2070",
            106: "NGC104", 109: "NGC3195",
        ]
        let byNumber = catalog.objects(in: .caldwell)
        for (number, id) in expected {
            let object = byNumber[number - 1]
            XCTAssertEqual(object.id, "dso.\(id)", "Caldwell \(number)")
            XCTAssertTrue(object.designations.contains("Caldwell \(number)"), "Caldwell \(number): \(object.designations)")
        }
        // The four Caldwell objects that have no NGC or IC number are objects of their own.
        XCTAssertEqual(byNumber[8].id, "dso.C9")
        XCTAssertEqual(byNumber[13].id, "dso.C14")
        XCTAssertEqual(byNumber[40].id, "dso.C41")
        XCTAssertEqual(byNumber[98].id, "dso.C99")
        XCTAssertEqual(byNumber[8].name, "Cave Nebula")
        XCTAssertEqual(byNumber[13].name, "Double Cluster")
        XCTAssertEqual(byNumber[40].name, "Hyades")
        XCTAssertEqual(byNumber[98].name, "Coalsack Nebula")
        XCTAssertEqual(try obj("dso.NGC7000").designations[1], "Caldwell 20")
        XCTAssertTrue(byNumber.allSatisfy { $0.prominence == .showpiece && $0.isListed })
        XCTAssertEqual(byNumber.last?.designations.last, "Caldwell 109")
    }

    // MARK: Sharpless

    func testSharplessRegionsAreEmissionNebulaeWithTheirSizes() throws {
        let catalog = try catalog()
        let regions = catalog.objects(in: .sharpless)
        XCTAssertEqual(regions.count, 313)
        let sharplessOnly = regions.filter { $0.id.hasPrefix("dso.Sh2-") }
        XCTAssertEqual(sharplessOnly.count, 313 - 47, "47 regions are other objects of the catalog")
        for region in sharplessOnly {
            XCTAssertNotNil(region.angularSize, region.id)
            XCTAssertNil(region.magnitude, region.id)
            XCTAssertNotNil(region.constellation, region.id)
            XCTAssertTrue([.emissionNebula, .planetaryNebula, .supernovaRemnant].contains(region.category), region.id)
        }
        // The catalogue lists every region as HII; five are known to be something else.
        XCTAssertEqual(Set(sharplessOnly.filter { $0.category == .planetaryNebula }.map(\.id)),
                       ["dso.Sh2-188", "dso.Sh2-216", "dso.Sh2-274", "dso.Sh2-290"])
        XCTAssertEqual(sharplessOnly.filter { $0.category == .supernovaRemnant }.map(\.id), ["dso.Sh2-240"])
        // Sizes are the largest extent of the region in arcminutes (Sharpless 1959, CDS VII/20).
        XCTAssertEqual(try obj("dso.Sh2-1").angularSize?.majorArcminutes, 150)
        XCTAssertEqual(try obj("dso.Sh2-129").angularSize?.majorArcminutes, 140)
        XCTAssertEqual(try obj("dso.Sh2-276").angularSize?.majorArcminutes, 1200)
        XCTAssertEqual(try obj("dso.Sh2-274").angularSize?.majorArcminutes, 8)
        // A circular region has equal axes (Sh2-240 is circular), others only the major axis.
        XCTAssertEqual(try obj("dso.Sh2-240").angularSize?.minorArcminutes, 180)
        XCTAssertNil(try obj("dso.Sh2-129").angularSize?.minorArcminutes)
        XCTAssertEqual(try obj("dso.Sh2-129").designations.first, "Sh2-129")
        XCTAssertEqual(try obj("dso.Sh2-1").name, "Sh2-1")
    }

    func testSharplessRegionsThatAreOtherObjectsAreDesignationsOfThem() throws {
        // Sh2-25 is the Lagoon Nebula, Sh2-117 the North America Nebula, Sh2-281 the Orion Nebula, Sh2-275 the
        // Rosette Nebula, Sh2-190 the Heart Nebula, Sh2-184 the Pacman Nebula, Sh2-155 the Cave Nebula.
        let pairs: [Int: String] = [
            25: "dso.M8", 30: "dso.M20", 45: "dso.M17", 49: "dso.M16", 117: "dso.NGC7000", 281: "dso.M42",
            275: "dso.NGC2238", 190: "dso.IC1805", 199: "dso.IC1848", 184: "dso.NGC281", 155: "dso.C9",
            103: "dso.NGC6960", 220: "dso.NGC1499", 248: "dso.IC443", 277: "dso.NGC2024", 298: "dso.NGC2359",
            244: "dso.M1",
        ]
        let catalog = try catalog()
        let regions = catalog.objects(in: .sharpless)
        for (number, id) in pairs {
            let region = regions[number - 1]
            XCTAssertEqual(region.id, id, "Sh2-\(number)")
            XCTAssertTrue(region.designations.contains("Sh2-\(number)"), "\(region.designations)")
            XCTAssertTrue(region.catalogNumbers.contains(CatalogNumber(catalogue: .sharpless, number: number)))
        }
        XCTAssertEqual(try obj("dso.M8").designations, ["M 8", "NGC 6523", "NGC 6533", "Sh2-25"])
        XCTAssertEqual(try obj("dso.NGC7000").designations, ["NGC 7000", "Caldwell 20", "Sh2-117"])
        XCTAssertEqual(try obj("dso.NGC7000").catalogNumbers, [
            CatalogNumber(catalogue: .ngc, number: 7000), CatalogNumber(catalogue: .caldwell, number: 20),
            CatalogNumber(catalogue: .sharpless, number: 117),
        ])
        XCTAssertEqual(try obj("dso.NGC7000").catalogues, [.ngc, .caldwell, .sharpless])
        XCTAssertEqual(try obj("dso.NGC7000").catalogNumbers.last?.label, "Sh2-117")
        XCTAssertEqual(try obj("dso.NGC7000").catalogNumbers[1].label, "C 20")
    }

    // MARK: Names

    func testPopularNamesOfTheNewCatalogues() throws {
        let names: [String: String] = [
            "dso.Sh2-129": "Flying Bat Nebula", "dso.Sh2-240": "Spaghetti Nebula", "dso.Sh2-132": "Lion Nebula",
            "dso.Sh2-101": "Tulip Nebula", "dso.Sh2-136": "Ghost Nebula", "dso.Sh2-157": "Lobster Claw Nebula",
            "dso.Sh2-261": "Lower's Nebula", "dso.Sh2-274": "Medusa Nebula", "dso.Sh2-276": "Barnard's Loop",
            "dso.Sh2-308": "Dolphin Head Nebula", "dso.Sh2-264": "Lambda Orionis Ring",
            "dso.Sh2-108": "Gamma Cygni Nebula", "dso.Sh2-290": "Abell 31", "dso.C9": "Cave Nebula",
            "dso.B33": "Horsehead Nebula", "dso.B72": "Snake Nebula", "dso.B78": "Pipe Nebula",
            "dso.B86": "Ink Spot Nebula", "dso.B150": "Seahorse Nebula",
            "dso.LDN1622": "Boogeyman Nebula", "dso.LDN1235": "Shark Nebula",
            "dso.Mel20": "Alpha Persei Cluster", "dso.Cl69": "Lambda Orionis Cluster",
            "dso.Cl70": "Orion's Belt Cluster", "dso.St2": "Muscleman Cluster",
        ]
        for (id, name) in names {
            XCTAssertEqual(try obj(id).name, name, id)
            XCTAssertTrue(try obj(id).isListed, "\(id): a named object is never obscure")
        }
        XCTAssertEqual(try obj("dso.Sh2-276").constellationName.map { String($0.prefix(5)) }, "Orion")
        XCTAssertEqual(try obj("dso.Sh2-129").constellationName, "Cepheus")
    }

    // MARK: Dark nebulae

    func testBarnardAndLyndsDarkNebulae() throws {
        let catalog = try catalog()
        let barnard = catalog.objects(in: .barnard)
        XCTAssertEqual(barnard.count, 349)
        XCTAssertTrue(barnard.allSatisfy { $0.category == .darkNebula && $0.magnitude == nil })
        // Barnard numbers: 1 to 175 (three of them omitted by the source) and 201 to 370; some carry a letter.
        let numbers = barnard.compactMap { object in object.catalogNumbers.first { $0.catalogue == .barnard } }
        XCTAssertEqual(numbers.count, 349)
        XCTAssertEqual(numbers.first?.label, "B 1")
        XCTAssertTrue(numbers.contains { $0.suffix == "a" })
        XCTAssertLessThanOrEqual(numbers.map(\.number).max() ?? 0, 370)
        XCTAssertEqual(try obj("dso.B33").designations, ["Barnard 33"])
        XCTAssertEqual(try obj("dso.B33").angularSize?.majorArcminutes, 6)
        XCTAssertEqual(try obj("dso.B33").angularSize?.minorArcminutes, 4)
        XCTAssertEqual(try obj("dso.B78").angularSize?.majorArcminutes, 180)
        XCTAssertTrue(try obj("dso.B67a").designations.contains("Barnard 67a"))

        let lynds = catalog.objects(in: .lynds)
        XCTAssertEqual(lynds.count, 398)
        XCTAssertTrue(lynds.allSatisfy { $0.category == .darkNebula && $0.magnitude == nil })
        XCTAssertEqual(try obj("dso.LDN1622").designations, ["LDN 1622"])
        XCTAssertEqual(try obj("dso.LDN1622").name, "Boogeyman Nebula")
        // The cut: the darkest clouds (opacity 6) and the large ones (an area of at least a square degree,
        // a circle 67.7' across); 248 clouds are that large.
        XCTAssertEqual(lynds.filter { ($0.angularSize?.majorArcminutes ?? 0) >= 67.7 }.count, 248)
        XCTAssertEqual(lynds.filter { ($0.angularSize?.majorArcminutes ?? 0) < 67.7 }.count, 150)
        // Area-equivalent diameter of LDN 1622 (0.122 square degrees): 2 * sqrt(0.122 / pi) degrees.
        XCTAssertEqual(try obj("dso.LDN1622").angularSize?.majorArcminutes ?? 0, 2 * (0.122 / Double.pi).squareRoot() * 60, accuracy: 0.01)
    }

    func testOpenClustersOfTheDiasList() throws {
        let catalog = try catalog()
        func numbers(_ catalogue: DeepSkyCatalogue) -> [Int] {
            catalog.objects(in: catalogue).map { object in object.catalogNumbers.first { $0.catalogue == catalogue }?.number ?? 0 }
        }
        // Collinder 50 (the Hyades, C 41) and 258 (Harvard 5) are the same objects as in OpenNGC.
        XCTAssertEqual(numbers(.collinder), [50, 65, 69, 70, 89, 121, 132, 140, 173, 258, 302, 316, 359, 399, 408, 464, 471])
        XCTAssertEqual(numbers(.melotte), [20, 22, 25, 31, 71, 72, 101, 105, 111])
        XCTAssertEqual(catalog.objects(in: .trumpler).map(\.id), ["dso.Tr24", "dso.IC1396"])
        XCTAssertEqual(catalog.objects(in: .stock).map(\.id), ["dso.St2"])
        let alphaPersei = try obj("dso.Mel20")
        XCTAssertEqual(alphaPersei.category, .openCluster)
        XCTAssertEqual(alphaPersei.angularSize?.majorArcminutes, 300)
        XCTAssertEqual(alphaPersei.constellation, "Per")
        XCTAssertEqual(alphaPersei.designations, ["Melotte 20"])
        XCTAssertEqual(alphaPersei.prominence, .prominent)
        // Clusters larger than 10 degrees are moving groups, not clusters: Collinder 285 is left out.
        XCTAssertNil(catalog.object(id: "dso.Cl285"))
        // The Pleiades are Melotte 22, the Hyades Melotte 25 and Collinder 50.
        XCTAssertEqual(try obj("dso.M45").designations, ["M 45", "Melotte 22"])
        XCTAssertEqual(try obj("dso.C41").designations, ["Caldwell 41", "Melotte 25", "Collinder 50"])
        XCTAssertEqual(try obj("dso.IC1396").designations, ["IC 1396", "Sh2-131", "Trumpler 37"])
    }

    // MARK: Published positions

    func testPositionsMatchPublishedValues() throws {
        // Medusa Nebula = Sh2-274 = Abell 21: SIMBAD 07 29 02.69 +13 14 48.4 (Wikipedia, Medusa Nebula).
        // Sharpless' center is good to a few arcminutes of this 8' nebula.
        XCTAssertLessThan(try distance(112.26121, 13.24678, "dso.Sh2-274"), 0.05)
        // Snake Nebula = Barnard 72: 17 23 30 -23 38 (Wikipedia, Snake Nebula).
        XCTAssertLessThan(try distance(260.875, -23.6333, "dso.B72"), 0.05)
        // Horsehead Nebula = Barnard 33: 05 40 59 -02 27 30 (OpenNGC addendum).
        XCTAssertLessThan(try distance(85.245833, -2.458333, "dso.B33"), 1e-5)
        // Tulip Nebula = Sh2-101: 20 00 29.37 +35 19 13.9 (Wikipedia, Sh 2-101); Sharpless' center is 6' away.
        XCTAssertLessThan(try distance(300.12238, 35.32053, "dso.Sh2-101"), 0.15)
        // Spaghetti Nebula = Simeis 147 = Sh2-240: 05 39 06 +27 59 55 (Wikipedia); the nebula is 3 degrees wide.
        XCTAssertLessThan(try distance(84.775, 27.99861, "dso.Sh2-240"), 0.5)
        // Pipe Nebula bowl = Barnard 78: 17 32 -25 35 (Barnard 1927, J2000 as in CDS VII/220A).
        XCTAssertLessThan(try distance(263.0, -25.5833, "dso.B78"), 0.05)
        // Cave Nebula = Caldwell 9 = Sh2-155 at the position OpenNGC gives.
        XCTAssertLessThan(try distance(344.475, 62.518333, "dso.C9"), 1e-5)
        // Lynds' center of LDN 1622 (CDS VII/7A, 05 52.0 +02 00 at B1950, precessed); the Boogeyman Nebula
        // is at about 05 54 +01 50.
        XCTAssertLessThan(try distance(88.65, 2.008, "dso.LDN1622"), 0.01)
        XCTAssertLessThan(try distance(88.5, 1.83, "dso.LDN1622"), 0.4)
    }

    func testPositionsAgreeWithTheRowsOfTheSourceCatalogues() throws {
        // Rows quoted from the CDS files: Sharpless VII/20 (B1900.0), Lynds VII/7A (B1950.0), Barnard VII/220A and
        // Dias B/ocl (J2000.0), as hours, minutes, seconds and degrees, arcminutes, arcseconds.
        struct Row {
            let id: String
            let jd: Double
            let ra: (Double, Double, Double)
            let sign: Double
            let dec: (Double, Double, Double)
        }
        let b1900 = 2415020.31352, b1950 = 2433282.4235, j2000 = 2451545.0
        let rows = [
            Row(id: "dso.Sh2-1", jd: b1900, ra: (15, 52, 48), sign: -1, dec: (25, 50, 0)),
            Row(id: "dso.Sh2-129", jd: b1900, ra: (21, 9, 12), sign: 1, dec: (59, 33, 0)),
            Row(id: "dso.Sh2-240", jd: b1900, ra: (5, 34, 42), sign: 1, dec: (28, 3, 0)),
            Row(id: "dso.Sh2-274", jd: b1900, ra: (7, 23, 30), sign: 1, dec: (13, 28, 0)),
            Row(id: "dso.Sh2-276", jd: b1900, ra: (5, 22, 30), sign: -1, dec: (4, 3, 0)),
            Row(id: "dso.Sh2-308", jd: b1900, ra: (6, 50, 0), sign: -1, dec: (23, 49, 0)),
            Row(id: "dso.LDN673", jd: b1950, ra: (19, 18.5, 0), sign: 1, dec: (11, 10, 0)),
            Row(id: "dso.LDN1235", jd: b1950, ra: (22, 14, 0), sign: 1, dec: (73, 10, 0)),
            Row(id: "dso.LDN1622", jd: b1950, ra: (5, 52, 0), sign: 1, dec: (2, 0, 0)),
            Row(id: "dso.B72", jd: j2000, ra: (17, 23, 35), sign: -1, dec: (23, 37, 0)),
            Row(id: "dso.B78", jd: j2000, ra: (17, 32, 0), sign: -1, dec: (25, 35, 0)),
            Row(id: "dso.B86", jd: j2000, ra: (18, 3, 1), sign: -1, dec: (27, 52, 0)),
            Row(id: "dso.B150", jd: j2000, ra: (20, 50, 39), sign: 1, dec: (60, 18, 0)),
            Row(id: "dso.Mel20", jd: j2000, ra: (3, 24, 19), sign: 1, dec: (49, 51, 42)),
            Row(id: "dso.Cl70", jd: j2000, ra: (5, 35, 30), sign: -1, dec: (1, 6, 0)),
            Row(id: "dso.St2", jd: j2000, ra: (2, 14, 43), sign: 1, dec: (59, 29, 6)),
            Row(id: "dso.Tr24", jd: j2000, ra: (16, 57, 0), sign: -1, dec: (40, 40, 0)),
        ]
        for row in rows {
            let ra = (row.ra.0 + row.ra.1 / 60 + row.ra.2 / 3600) * 15
            let dec = row.sign * (row.dec.0 + row.dec.1 / 60 + row.dec.2 / 3600)
            let expected = precessToJ2000(ra: ra, dec: dec, fromJulianDate: row.jd, j2000: j2000)
            let position = try XCTUnwrap(try obj(row.id).j2000, row.id)
            XCTAssertEqual(position.rightAscension, expected.ra, accuracy: 1e-4, row.id)
            XCTAssertEqual(position.declination, expected.dec, accuracy: 1e-4, row.id)
        }
    }

    /// IAU 1976 precession (Lieske) of a position from the equinox of date `fromJulianDate` to J2000, by rotation matrices.
    private func precessToJ2000(ra: Double, dec: Double, fromJulianDate fromJd: Double, j2000: Double) -> (ra: Double, dec: Double) {
        if fromJd == j2000 { return (ra, dec) }
        let t0 = (fromJd - j2000) / 36525.0
        let t = (j2000 - fromJd) / 36525.0
        let arcsecond = Double.pi / 648000.0
        let zeta = ((2306.2181 + 1.39656 * t0 - 0.000139 * t0 * t0) * t + (0.30188 - 0.000344 * t0) * t * t + 0.017998 * t * t * t) * arcsecond
        let z = ((2306.2181 + 1.39656 * t0 - 0.000139 * t0 * t0) * t + (1.09468 + 0.000066 * t0) * t * t + 0.018203 * t * t * t) * arcsecond
        let theta = ((2004.3109 - 0.8533 * t0 - 0.000217 * t0 * t0) * t - (0.42665 + 0.000217 * t0) * t * t - 0.041833 * t * t * t) * arcsecond
        let a = ra * Double.pi / 180, d = dec * Double.pi / 180
        var x = cos(d) * cos(a), y = cos(d) * sin(a), w = sin(d)
        // R3(-z) R2(theta) R3(-zeta)
        var nx = x * cos(zeta) - y * sin(zeta)
        var ny = x * sin(zeta) + y * cos(zeta)
        x = nx; y = ny
        nx = x * cos(theta) - w * sin(theta)
        let nw = x * sin(theta) + w * cos(theta)
        x = nx; w = nw
        nx = x * cos(z) - y * sin(z)
        ny = x * sin(z) + y * cos(z)
        var resultRa = atan2(ny, nx) * 180 / Double.pi
        if resultRa < 0 { resultRa += 360 }
        return (resultRa, asin(max(-1, min(1, w))) * 180 / Double.pi)
    }

    // MARK: Search

    func testTheNewDesignationsFindTheirObjectsWhateverTheSpelling() throws {
        let catalog = try catalog()
        let expectations: [(String, String)] = [
            // Sharpless: the catalogue number with and without the leading 2, spaces, hyphen or none.
            ("Sh2-155", "dso.C9"), ("Sh 2-155", "dso.C9"), ("sh2155", "dso.C9"), ("Sharpless 155", "dso.C9"),
            ("Sharpless 2-155", "dso.C9"), ("Sh2-129", "dso.Sh2-129"), ("Sh 2-129", "dso.Sh2-129"),
            // Search keys have no punctuation: below Sh2-100 "Sharpless 2-45" would read as "Sharpless 245".
            ("Sharpless 45", "dso.M17"), ("Sharpless 245", "dso.Sh2-245"), ("Sharpless 25", "dso.M8"),
            ("Sharpless 225", "dso.Sh2-225"), ("Sh2-45", "dso.M17"), ("Sh 2-245", "dso.Sh2-245"),
            ("Sharpless 129", "dso.Sh2-129"), ("Sh2-240", "dso.Sh2-240"), ("Sh2-25", "dso.M8"),
            // Barnard.
            ("B33", "dso.B33"), ("B 33", "dso.B33"), ("Barnard 33", "dso.B33"), ("barnard33", "dso.B33"),
            ("B72", "dso.B72"), ("Barnard 72", "dso.B72"), ("B67a", "dso.B67a"), ("Barnard 67a", "dso.B67a"),
            // Lynds.
            ("LDN 1622", "dso.LDN1622"), ("LDN1622", "dso.LDN1622"), ("Lynds 1622", "dso.LDN1622"),
            ("L 1622", "dso.LDN1622"), ("ldn 1235", "dso.LDN1235"),
            // Caldwell.
            ("C14", "dso.C14"), ("C 14", "dso.C14"), ("Caldwell 14", "dso.C14"), ("caldwell14", "dso.C14"),
            ("C20", "dso.NGC7000"), ("Caldwell 20", "dso.NGC7000"), ("C 63", "dso.NGC7293"),
            ("Caldwell 80", "dso.NGC5139"), ("C 106", "dso.NGC104"), ("C9", "dso.C9"),
            // Collinder, Melotte, Trumpler, Stock.
            ("Cr 399", "dso.Cl399"), ("Cr399", "dso.Cl399"), ("Cl 399", "dso.Cl399"), ("Collinder 399", "dso.Cl399"),
            ("Mel 20", "dso.Mel20"), ("Melotte 20", "dso.Mel20"), ("Mel20", "dso.Mel20"),
            ("Mel 22", "dso.M45"), ("Mel 25", "dso.C41"), ("Cr 50", "dso.C41"), ("Cr 70", "dso.Cl70"),
            ("Tr 24", "dso.Tr24"), ("Trumpler 24", "dso.Tr24"), ("Tr 37", "dso.IC1396"), ("St 2", "dso.St2"),
            ("Stock 2", "dso.St2"),
            // Names.
            ("Boogeyman", "dso.LDN1622"), ("Flying Bat", "dso.Sh2-129"), ("Horsehead", "dso.B33"),
            ("Spaghetti Nebula", "dso.Sh2-240"), ("Cave Nebula", "dso.C9"), ("Snake Nebula", "dso.B72"),
            ("Simeis 147", "dso.Sh2-240"), ("Abell 21", "dso.Sh2-274"), ("Abell 31", "dso.Sh2-290"),
        ]
        for (query, id) in expectations {
            let first = try XCTUnwrap(catalog.search(query).first, query)
            XCTAssertEqual(first.object.id, id, query)
            XCTAssertTrue([.exact, .prefix, .wordPrefix].contains(first.kind), "\(query): \(first.kind)")
        }
        // The designations are exact matches, not prefix matches of something longer.
        for query in ["Sh2-155", "B33", "LDN 1622", "C14", "Cr 399", "Mel 20", "Caldwell 14", "Barnard 33"] {
            XCTAssertEqual(catalog.search(query).first?.kind, .exact, query)
        }
    }

    func testTheMatchedTextOfAnAliasIsTheDesignationAsShown() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.search("Sharpless 155").first?.matchedText, "Sh2-155")
        XCTAssertEqual(catalog.search("C 20").first?.matchedText, "Caldwell 20")
        XCTAssertEqual(catalog.search("B33").first?.matchedText, "Barnard 33")
        XCTAssertEqual(catalog.search("Lynds 1622").first?.matchedText, "LDN 1622")
        XCTAssertEqual(catalog.search("Cr 399").first?.matchedText, "Collinder 399")
        XCTAssertEqual(catalog.search("Mel 22").first?.matchedText, "Melotte 22")
    }

    func testSearchingACataloguePrefixListsItsObjects() throws {
        let catalog = try catalog()
        let caldwell = catalog.search("caldwell", limit: 200)
        XCTAssertEqual(caldwell.count, 109)
        XCTAssertEqual(Set(ids(caldwell)), Set(catalog.objects(in: .caldwell).map(\.id)))
        XCTAssertTrue(caldwell.allSatisfy { $0.kind == .prefix })
        let sharpless = catalog.search("sharpless", limit: 400)
        XCTAssertEqual(sharpless.count, 313)
        let barnard = catalog.search("barnard 3", limit: 400)
        XCTAssertTrue(!barnard.isEmpty && barnard.allSatisfy { $0.object.catalogues.contains(.barnard) })
        let exact = catalog.search("sh2-1", limit: 400)
        XCTAssertEqual(exact.first?.object.id, "dso.Sh2-1")
        XCTAssertEqual(exact.first?.kind, .exact)
        XCTAssertTrue(exact.dropFirst().allSatisfy { $0.kind == .prefix })
        // Every result of a LDN query is a cloud, a Barnard object is never found by a Lynds number.
        XCTAssertTrue(catalog.search("ldn 16", limit: 100).allSatisfy { $0.object.id.hasPrefix("dso.LDN16") })
    }

    func testFamousDarkNebulaeOutrankFaintGalaxiesInSearch() throws {
        let catalog = try catalog()
        // "horse" matches the name "Horsehead Nebula"; the showpiece comes first even without a magnitude.
        XCTAssertEqual(catalog.search("horse", limit: 5).first?.object.id, "dso.B33")
        // Within one kind of match no obscure object comes before a showpiece.
        let hits = catalog.search("nebula", limit: 400)
        for (first, second) in zip(hits, hits.dropFirst()) where first.kind == second.kind && first.object.isListed == second.object.isListed {
            XCTAssertLessThanOrEqual(first.object.prominence, second.object.prominence, "\(first.object.id) before \(second.object.id)")
        }
    }

    // MARK: Prominence

    func testProminenceCountsAndListingOfTheBundledCatalog() throws {
        let catalog = try catalog()
        let deepSky = catalog.deepSkyObjects
        let counts = Prominence.allCases.map { level in deepSky.filter { $0.prominence == level }.count }
        // The bundled data (Tools/README.md) has 253 showpieces, 234 prominent, 508 notable and 1446 obscure
        // deep-sky records; two notable ones, NGC 1990 and IC 1318, are the stars Alnilam and Sadr and not objects.
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.merged, 2)
        XCTAssertEqual(counts, [253, 234, 506, 1446])
        XCTAssertEqual(deepSky.filter(\.isListed).count, 993)
        for level in Prominence.allCases {
            XCTAssertEqual(catalog.deepSkyObjects(upTo: level), deepSky.filter { $0.prominence <= level }, "\(level)")
        }
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .obscure), deepSky)
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .showpiece).count, 253)
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .prominent).count, 253 + 234)
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .notable).count, 253 + 234 + 506)
        XCTAssertTrue(catalog.deepSkyObjects(upTo: .showpiece).allSatisfy { $0.prominence == .showpiece })
    }

    func testProminenceFollowsTheDocumentedRules() throws {
        let catalog = try catalog()
        for object in catalog.deepSkyObjects {
            let isPlainStar = object.category == .star || object.category == .doubleStar
            // Messier and Caldwell objects are showpieces.
            if object.catalogues.contains(.messier) || object.catalogues.contains(.caldwell) {
                XCTAssertEqual(object.prominence, .showpiece, object.id)
            }
            // Anything brighter than magnitude 4 is a showpiece; brighter than 8 at least prominent.
            if let magnitude = object.magnitude, !isPlainStar {
                if magnitude <= 4 { XCTAssertEqual(object.prominence, .showpiece, object.id) }
                if magnitude <= 8 { XCTAssertLessThanOrEqual(object.prominence, .prominent, object.id) }
                if magnitude <= 10 { XCTAssertLessThanOrEqual(object.prominence, .notable, "\(object.id) is bright enough to be listed") }
            }
            // An object with a common name is never obscure.
            if object.name != object.designations.first { XCTAssertLessThanOrEqual(object.prominence, .notable, object.id) }
            // Dark nebulae have no magnitude: unnamed Lynds clouds are notable from 3 degrees across and
            // obscure under 20 arcminutes (in between it depends on their opacity).
            if object.id.hasPrefix("dso.LDN"), object.name == object.designations.first {
                let size = object.angularSize?.majorArcminutes ?? 0
                if size >= 180 { XCTAssertEqual(object.prominence, .notable, "\(object.id) (\(size)')") }
                if size < 20 { XCTAssertEqual(object.prominence, .obscure, "\(object.id) (\(size)')") }
            }
            // Listed means notable or better.
            XCTAssertEqual(object.isListed, object.prominence <= .notable, object.id)
        }
        // Spot checks of the rules for objects without magnitude.
        XCTAssertEqual(try obj("dso.B33").prominence, .showpiece)
        XCTAssertEqual(try obj("dso.LDN1622").prominence, .showpiece)
        XCTAssertEqual(try obj("dso.Sh2-129").prominence, .showpiece)
        XCTAssertEqual(try obj("dso.B72").prominence, .prominent)
        XCTAssertEqual(try obj("dso.LDN1235").prominence, .prominent)
        XCTAssertEqual(try obj("dso.Sh2-261").prominence, .prominent)
        XCTAssertEqual(try obj("dso.Sh2-274").prominence, .notable, "the Medusa Nebula is named but small")
        XCTAssertEqual(try obj("dso.B1").prominence, .obscure)
        XCTAssertEqual(try obj("dso.Sh2-4").prominence, .obscure)
        XCTAssertEqual(try obj("dso.M31").prominence, .showpiece)
        XCTAssertEqual(try obj("dso.ESO56-115").prominence, .showpiece, "the Large Magellanic Cloud is brighter than 4")
        XCTAssertEqual(try obj("dso.IC1459").prominence, .obscure, "a magnitude 10.5 galaxy")
    }

    func testEverythingTheFirstReleaseListedIsStillListed() throws {
        let catalog = try catalog()
        for object in catalog.deepSkyObjects {
            let id = String(object.id.dropFirst("dso.".count))
            let named = object.name != object.designations.first
            let size = object.angularSize?.majorArcminutes ?? 0
            let openNgc = id.hasPrefix("NGC") || id.hasPrefix("IC")
            let plainStar = object.category == .star || object.category == .doubleStar
            let nebula: Set<ObjectCategory> = [.emissionNebula, .reflectionNebula, .nebula, .supernovaRemnant, .clusterWithNebula]
            if object.catalogues.contains(.messier) || named { XCTAssertTrue(object.isListed, object.id) }
            if let magnitude = object.magnitude, openNgc, !plainStar, magnitude <= 10 { XCTAssertTrue(object.isListed, object.id) }
            if openNgc, object.magnitude == nil, nebula.contains(object.category), size >= 10 {
                XCTAssertTrue(object.isListed, "\(object.id) is a large nebula")
            }
        }
    }

    func testStarsAndBuiltInObjectsHaveTheirProminence() throws {
        let catalog = try catalog()
        for id in ["sun", "moon", "planet.mars", "planet.neptune", "special.galacticCenter", "special.ncp", "special.scp"] {
            XCTAssertEqual(try obj(id).prominence, .showpiece, id)
        }
        XCTAssertEqual(try obj("star.hip32349").prominence, .showpiece, "Sirius")
        XCTAssertEqual(try obj("star.hip11767").prominence, .prominent, "Polaris, magnitude 2.0")
        for star in catalog.objects where star.id.hasPrefix("star.") {
            XCTAssertEqual(star.prominence, Prominence(starMagnitude: try XCTUnwrap(star.magnitude)), star.id)
        }
        XCTAssertEqual(Prominence(starMagnitude: -1.4), .showpiece)
        XCTAssertEqual(Prominence(starMagnitude: 1.5), .showpiece)
        XCTAssertEqual(Prominence(starMagnitude: 1.51), .prominent)
        XCTAssertEqual(Prominence(starMagnitude: 3.5), .prominent)
        XCTAssertEqual(Prominence(starMagnitude: 3.51), .notable)
        XCTAssertEqual(Prominence(starMagnitude: 5.0), .notable)
        XCTAssertEqual(Prominence(starMagnitude: 5.01), .obscure)
        XCTAssertEqual(Prominence(starMagnitude: .infinity), .obscure)
        let custom = CelestialObject.custom(name: "My target", j2000: EquatorialCoordinate(rightAscension: 10, declination: 20))
        XCTAssertEqual(custom.prominence, .showpiece)
        XCTAssertTrue(custom.catalogNumbers.isEmpty && custom.catalogues.isEmpty && !custom.isDeepSky)
        XCTAssertTrue(try obj("dso.M31").isDeepSky)
        XCTAssertFalse(try obj("star.hip32349").isDeepSky)
    }

    func testTheEnumerationsAndLabels() throws {
        XCTAssertEqual(Prominence.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertTrue(Prominence.showpiece < .prominent && Prominence.notable < .obscure)
        XCTAssertEqual(Prominence.lastListed, .notable)
        for level in Prominence.allCases {
            XCTAssertEqual(Prominence(rawValue: level.rawValue), level)
            XCTAssertFalse(level.displayName.isEmpty)
        }
        XCTAssertNil(Prominence(rawValue: 0))
        XCTAssertNil(Prominence(rawValue: 5))
        XCTAssertEqual(Prominence.allCases.map(\.displayName), ["Showpiece", "Prominent", "Notable", "Obscure"])
        for catalogue in DeepSkyCatalogue.allCases {
            XCTAssertEqual(DeepSkyCatalogue(rawValue: catalogue.rawValue), catalogue)
            XCTAssertFalse(catalogue.displayName.isEmpty || catalogue.abbreviation.isEmpty)
        }
        XCTAssertNil(DeepSkyCatalogue(rawValue: "Messier"))
        XCTAssertEqual(DeepSkyCatalogue.allCases.map(\.rawValue),
                       ["messier", "caldwell", "ngc", "ic", "sharpless", "barnard", "lynds", "collinder", "melotte", "trumpler", "stock"])
        XCTAssertEqual(CatalogNumber(catalogue: .messier, number: 31).label, "M 31")
        XCTAssertEqual(CatalogNumber(catalogue: .ngc, number: 7000).label, "NGC 7000")
        XCTAssertEqual(CatalogNumber(catalogue: .caldwell, number: 14).label, "C 14")
        XCTAssertEqual(CatalogNumber(catalogue: .sharpless, number: 155).label, "Sh2-155")
        XCTAssertEqual(CatalogNumber(catalogue: .barnard, number: 67, suffix: "a").label, "B 67a")
        XCTAssertEqual(CatalogNumber(catalogue: .lynds, number: 1622).label, "LDN 1622")
        XCTAssertEqual(CatalogNumber(catalogue: .collinder, number: 399).label, "Cr 399")
        XCTAssertEqual(CatalogNumber(catalogue: .melotte, number: 20).label, "Mel 20")
    }

    // MARK: Designations

    func testCompactDesignationsAreSpelledAndParsed() throws {
        let spelled: [(String, String, [String])] = [
            ("M31", "M 31", ["Messier 31"]),
            ("NGC7000", "NGC 7000", []),
            ("C14", "Caldwell 14", ["C 14"]),
            ("Sh2-155", "Sh2-155", ["Sh 2-155", "Sharpless 155", "Sharpless 2-155"]),
            ("Sh2-45", "Sh2-45", ["Sh 2-45", "Sharpless 45"]),
            ("LDN1622", "LDN 1622", ["Lynds 1622", "L 1622"]),
            ("B67a", "Barnard 67a", ["B 67a"]),
            ("Cl399", "Collinder 399", ["Cl 399", "Cr 399"]),
            ("Mel20", "Melotte 20", ["Mel 20"]),
            ("Tr24", "Trumpler 24", ["Tr 24"]),
            ("St2", "Stock 2", ["St 2"]),
            ("ESO56-115", "ESO 56-115", []),
            ("IC2431_NED02", "IC 2431 NED02", []),
        ]
        for (id, display, aliases) in spelled {
            let spelling = CatalogDesignation.spelling(ofIdentifier: id)
            XCTAssertEqual(spelling.display, display, id)
            XCTAssertEqual(spelling.aliases, aliases, id)
        }
        let numbers: [(String, CatalogNumber)] = [
            ("M31", CatalogNumber(catalogue: .messier, number: 31)), ("NGC7000", CatalogNumber(catalogue: .ngc, number: 7000)),
            ("IC434", CatalogNumber(catalogue: .ic, number: 434)), ("C14", CatalogNumber(catalogue: .caldwell, number: 14)),
            ("Sh2-155", CatalogNumber(catalogue: .sharpless, number: 155)),
            ("B67a", CatalogNumber(catalogue: .barnard, number: 67, suffix: "a")),
            ("LDN1622", CatalogNumber(catalogue: .lynds, number: 1622)), ("Cl399", CatalogNumber(catalogue: .collinder, number: 399)),
            ("Mel20", CatalogNumber(catalogue: .melotte, number: 20)), ("Tr24", CatalogNumber(catalogue: .trumpler, number: 24)),
            ("St2", CatalogNumber(catalogue: .stock, number: 2)),
            ("NGC2818A", CatalogNumber(catalogue: .ngc, number: 2818, suffix: "A")),
        ]
        for (text, number) in numbers {
            XCTAssertEqual(CatalogDesignation.catalogNumber(of: text), number, text)
            XCTAssertTrue(CatalogDesignation.isCompact(text), text)
        }
        for text in ["ESO56-115", "H20", "PGC143", "UGC5373", "MWSC3171", "IC2431_NED02", "HCG92", "Sh2", "Sh2-", ""] {
            XCTAssertNil(CatalogDesignation.catalogNumber(of: text), text)
        }
        for text in ["H20", "PGC143", "Sh2"] { XCTAssertTrue(CatalogDesignation.isCompact(text), text) }
        for text in ["", "20", "C", "C0", "c20", "Sh2-", "Sh2-0", "Sh2-12345", "C1234567", "ABCDEFG1", "B67ab", "B67_", "C 20", "C-20", "ESO56-115"] {
            XCTAssertFalse(CatalogDesignation.isCompact(text), text)
        }
    }

    // MARK: Decoding the new members

    private func deepSky(_ members: [(String, String)]) -> String {
        "{" + members.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
    }

    private let base: [(String, String)] = [("t", "\"HII\""), ("ra", "314.8"), ("de", "44.5"), ("c", "\"Cyg\""),
                                            ("maj", "120"), ("min", "30")]

    func testCrossDesignationsAndProminenceAreDecoded() throws {
        let record = deepSky([("id", "\"NGC7000\""), ("ngc", "[7000]"), ("cat", "[\"C20\",\"Sh2-117\"]"),
                              ("names", "[\"North America Nebula\"]")] + base + [("p", "1")])
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: [record])
        XCTAssertTrue(catalog.loadReport.isClean, "\(catalog.loadReport.issues)")
        let object = try XCTUnwrap(catalog.object(id: "dso.NGC7000"))
        XCTAssertEqual(object.designations, ["NGC 7000", "Caldwell 20", "Sh2-117"])
        XCTAssertEqual(object.name, "North America Nebula")
        XCTAssertEqual(object.prominence, .showpiece)
        XCTAssertTrue(object.isListed)
        XCTAssertEqual(object.catalogNumbers, [
            CatalogNumber(catalogue: .ngc, number: 7000), CatalogNumber(catalogue: .caldwell, number: 20),
            CatalogNumber(catalogue: .sharpless, number: 117),
        ])
        XCTAssertEqual(ids(catalog.search("C 20")), ["dso.NGC7000"])
        XCTAssertEqual(ids(catalog.search("Sharpless 117")), ["dso.NGC7000"])
        XCTAssertEqual(ids(catalog.search("Sh 2-117")), ["dso.NGC7000"])
        XCTAssertEqual(catalog.search("C20").first?.matchedText, "Caldwell 20")
        XCTAssertEqual(catalog.objects(in: .caldwell), [object])
        XCTAssertEqual(catalog.objects(in: .sharpless), [object])
        XCTAssertEqual(catalog.objects(in: .ngc), [object])
        XCTAssertTrue(catalog.objects(in: .messier).isEmpty)
    }

    func testRecordsWithoutTheNewMembersLoadAsBefore() throws {
        let catalog = try CatalogFixture.syntheticCatalog()
        XCTAssertTrue(catalog.loadReport.isClean)
        let object = try XCTUnwrap(catalog.object(id: "dso.M1"))
        XCTAssertEqual(object.prominence, .notable, "no p: notable")
        XCTAssertTrue(object.isListed)
        XCTAssertEqual(object.designations, ["M 1"])
        XCTAssertEqual(object.catalogNumbers, [CatalogNumber(catalogue: .messier, number: 1)])
        XCTAssertEqual(catalog.deepSkyObjects, [object])
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .notable), [object])
        XCTAssertTrue(catalog.deepSkyObjects(upTo: .prominent).isEmpty)
        // null is the same as absent.
        let withNulls = try CatalogFixture.syntheticCatalog(
            deepSky: [deepSky([("id", "\"NGC1\""), ("cat", "null"), ("p", "null")] + base)])
        XCTAssertTrue(withNulls.loadReport.isClean)
        XCTAssertEqual(withNulls.object(id: "dso.NGC1")?.prominence, .notable)
    }

    func testObscureRecordsAreNotListedButCanBeFoundAndTheyAreInTheirCatalogue() throws {
        let records = [
            deepSky([("id", "\"B5\""), ("cat", "[\"LDN100\"]")] + base + [("p", "4")]),
            deepSky([("id", "\"B6\"")] + base + [("p", "3")]),
            deepSky([("id", "\"B7\"")] + base + [("p", "2")]),
            deepSky([("id", "\"B7a\"")] + base + [("p", "1")]),
        ]
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: records)
        XCTAssertTrue(catalog.loadReport.isClean, "\(catalog.loadReport.issues)")
        let obscure = try XCTUnwrap(catalog.object(id: "dso.B5"))
        XCTAssertEqual(obscure.prominence, .obscure)
        XCTAssertFalse(obscure.isListed)
        XCTAssertFalse(catalog.listedObjects.contains { $0.id == "dso.B5" })
        XCTAssertTrue(catalog.objects(in: .nebulae).allSatisfy { $0.id != "dso.B5" })
        XCTAssertEqual(catalog.objects(in: .nebulae).map(\.id), ["dso.B6", "dso.B7", "dso.B7a"])
        XCTAssertEqual(Array(ids(catalog.search("B5")).prefix(1)), ["dso.B5"])
        XCTAssertEqual(catalog.objects(in: .barnard).map(\.id), ["dso.B5", "dso.B6", "dso.B7", "dso.B7a"])
        XCTAssertEqual(catalog.objects(in: .lynds).map(\.id), ["dso.B5"])
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .showpiece).map(\.id), ["dso.B7a"])
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .prominent).map(\.id), ["dso.B7", "dso.B7a"])
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .notable).map(\.id), ["dso.B6", "dso.B7", "dso.B7a"])
        XCTAssertEqual(catalog.deepSkyObjects(upTo: .obscure).count, 4)
        XCTAssertEqual(catalog.objects(in: .barnard).map { $0.catalogNumbers.first?.label }, ["B 5", "B 6", "B 7", "B 7a"])
    }

    func testSearchRanksProminenceBeforeMagnitude() throws {
        func galaxy(_ number: Int, kind: String = "G", magnitude: String? = nil, prominence: Int) -> String {
            deepSky([("id", "\"NGC\(number)\""), ("ngc", "[\(number)]"), ("t", "\"\(kind)\""), ("ra", "10"), ("de", "10"),
                     ("c", "\"And\"")] + (magnitude.map { [("vm", $0)] } ?? []) + [("p", "\(prominence)")])
        }
        let records = [
            galaxy(101, magnitude: "11.0", prominence: 4),
            galaxy(102, kind: "DrkN", prominence: 1),
            galaxy(103, magnitude: "9.0", prominence: 3),
            galaxy(104, magnitude: "10.0", prominence: 3),
            galaxy(105, prominence: 3),
        ]
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: records)
        XCTAssertEqual(ids(catalog.search("ngc 10", limit: 10)),
                       ["dso.NGC102", "dso.NGC103", "dso.NGC104", "dso.NGC105", "dso.NGC101"],
                       "the unlisted object comes last; then prominence, magnitude (unknown last), name")
    }

    // MARK: Malformed variants

    private func rejected(_ members: [(String, String)], file: StaticString = #filePath, line: UInt = #line) throws -> Catalog {
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: [CatalogFixture.defaultDeepSky, deepSky(members)])
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 1, "\(members)", file: file, line: line)
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.rejected, 1, "\(members)", file: file, line: line)
        XCTAssertEqual(catalog.objects.filter(\.isDeepSky).map(\.id), ["dso.M1"], file: file, line: line)
        return catalog
    }

    private func accepted(_ members: [(String, String)], file: StaticString = #filePath, line: UInt = #line) throws -> Catalog {
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: [CatalogFixture.defaultDeepSky, deepSky(members)])
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 2, "\(catalog.loadReport.issues)", file: file, line: line)
        XCTAssertTrue(catalog.loadReport.isClean, file: file, line: line)
        return catalog
    }

    func testProminenceOutsideOneToFourRejectsTheRecord() throws {
        for value in ["0", "5", "-1", "100", "9223372036854775807", "-9223372036854775808"] {
            let catalog = try rejected([("id", "\"NGC1\"")] + base + [("p", value)])
            XCTAssertEqual(catalog.loadReport.issues, ["dsos[1]: p \(value) out of range"], value)
        }
        for value in ["1", "2", "3", "4"] { _ = try accepted([("id", "\"NGC1\"")] + base + [("p", value)]) }
    }

    func testProminenceOfTheWrongTypeMakesTheRecordUnreadable() throws {
        for value in ["\"2\"", "2.5", "true", "[2]", "{}"] {
            let catalog = try rejected([("id", "\"NGC1\"")] + base + [("p", value)])
            XCTAssertEqual(catalog.loadReport.issues, ["dsos[1]: record has the wrong shape"], value)
        }
    }

    func testMalformedCrossDesignationsRejectTheRecord() throws {
        let bad = ["ESO56-115", "20", "C", "C0", "Sh2-", "Sh2-0", "Sh2-12345", "C1234567", "B67ab", "C 20", " ", "",
                   "Sh2-1a", "ÄB12"]
        for entry in bad {
            let catalog = try rejected([("id", "\"NGC1\"")] + base + [("cat", "[\"\(entry)\"]")])
            let issue = try XCTUnwrap(catalog.loadReport.issues.first)
            XCTAssertEqual(catalog.loadReport.issues.count, 1, entry)
            XCTAssertTrue(issue.hasPrefix("dsos[1]: cat"), "\(entry): \(issue)")
        }
        XCTAssertEqual(try rejected([("id", "\"NGC1\"")] + base + [("cat", "[\"ESO56-115\"]")]).loadReport.issues,
                       ["dsos[1]: cat entry ESO56-115 is not a catalogue designation"])
        XCTAssertEqual(try rejected([("id", "\"NGC1\"")] + base + [("cat", "[\"\(String(repeating: "A", count: 17))1\"]")]).loadReport.issues,
                       ["dsos[1]: cat is too long"])
        XCTAssertEqual(try rejected([("id", "\"NGC1\"")] + base + [("cat", "[\"C\\u00002\"]")]).loadReport.issues,
                       ["dsos[1]: cat contains control characters"])
        let seventeen = (1...17).map { "\"C\($0)\"" }.joined(separator: ",")
        XCTAssertEqual(try rejected([("id", "\"NGC1\"")] + base + [("cat", "[\(seventeen)]")]).loadReport.issues,
                       ["dsos[1]: cat has too many entries"])
        _ = try accepted([("id", "\"NGC1\"")] + base + [("cat", "[\((1...16).map { "\"C\($0)\"" }.joined(separator: ","))]")])
    }

    func testCrossDesignationsOfTheWrongShapeMakeTheRecordUnreadable() throws {
        for value in ["\"C20\"", "[20]", "[null]", "[[\"C20\"]]", "{}", "true", "[\"C20\",5]"] {
            let catalog = try rejected([("id", "\"NGC1\"")] + base + [("cat", value)])
            XCTAssertEqual(catalog.loadReport.issues, ["dsos[1]: record has the wrong shape"], value)
        }
    }

    func testCrossDesignationsAreTrimmedAndDeduplicated() throws {
        let catalog = try accepted([("id", "\"NGC1\""), ("ngc", "[1]")] + base
                                   + [("cat", "[\" C20 \",\"C20\",\"NGC1\",\"Sh2-117\",\"Sh2-117\"]")])
        let object = try XCTUnwrap(catalog.object(id: "dso.NGC1"))
        // NGC1 repeats the object's own NGC number: the designation is shown once.
        XCTAssertEqual(object.designations, ["NGC 1", "Caldwell 20", "Sh2-117"])
        XCTAssertEqual(object.catalogNumbers.count, 3)
    }

    func testTheSchemaVersionStaysOne() throws {
        XCTAssertEqual(Catalog.supportedSchemaVersion, 1)
        let data = try Catalog.bundledData(for: .deepSkyObjects)
        XCTAssertTrue(String(decoding: data.prefix(12), as: UTF8.self).hasPrefix("{\"schema\":1,"))
        XCTAssertLessThan(data.count, 600 * 1024, "dsos.json is \(data.count) bytes")
    }
}

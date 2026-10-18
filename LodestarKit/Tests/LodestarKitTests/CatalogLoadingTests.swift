import XCTest
@testable import LodestarKit

// MARK: - Shared support for the catalog tests

/// The bundled catalog, loaded once, and the raw records of the data files for independent checks.
enum CatalogFixture {
    private static let loaded = Result { try Catalog.loadBundled() }

    static func catalog() throws -> Catalog { try loaded.get() }

    /// A star record as it appears in `stars.json`.
    struct RawStar: Decodable {
        let hip: Int?
        let hr: Int?
        let hd: Int?
        let hyg: Int?
        let n: String?
        let b: String?
        let f: Int?
        let c: String
        let ra: Double
        let de: Double
        let pa: Double?
        let pd: Double?
        let m: Double
        let ci: Double?
        let sp: String?
        let d: Double?
    }

    /// A deep-sky record as it appears in `dsos.json`.
    struct RawDeepSky: Decodable {
        let id: String
        let m: Int?
        let ngc: [Int]?
        let ic: [Int]?
        let names: [String]?
        let t: String
        let ra: Double
        let de: Double
        let c: String
        let vm: Double?
        let bm: Double?
        let maj: Double?
        let min: Double?
        let pa: Double?
        let h: String?
        let sb: Double?
        let cat: [String]?
        let p: Int?
    }

    private struct StarFile: Decodable { let stars: [RawStar] }
    private struct DeepSkyFile: Decodable { let objects: [RawDeepSky] }

    static func rawStars() throws -> [RawStar] {
        try JSONDecoder().decode(StarFile.self, from: Catalog.bundledData(for: .stars)).stars
    }

    static func rawDeepSky() throws -> [RawDeepSky] {
        try JSONDecoder().decode(DeepSkyFile.self, from: Catalog.bundledData(for: .deepSkyObjects)).objects
    }

    /// A catalog of the given JSON records (strings of one JSON object each) in the real file layout.
    static func syntheticCatalog(stars: [String] = [defaultStar], deepSky: [String] = [defaultDeepSky],
                                 constellations: [String] = [defaultConstellation],
                                 milkyWayLevels: [String] = [defaultMilkyWayLevel]) throws -> Catalog {
        try Catalog(starsData: file("stars", stars), dsosData: file("objects", deepSky),
                    constellationsData: file("constellations", constellations),
                    milkyWayData: file("levels", milkyWayLevels))
    }

    static func file(_ key: String, _ records: [String], schema: String = "1") -> Data {
        Data(#"{"schema":\#(schema),"\#(key)":[\#(records.joined(separator: ","))]}"#.utf8)
    }

    static let defaultStar = #"{"hip":1,"n":"Test Star","c":"Ori","ra":10.0,"de":20.0,"m":2.5}"#
    static let defaultDeepSky = #"{"id":"M1","m":1,"t":"SNR","ra":83.6,"de":22.0,"c":"Tau","vm":8.4,"maj":8,"min":4}"#
    static let defaultConstellation = #"{"abbr":"Ori","name":"Orion","genitive":"Orionis","label":[83.0,5.0],"lines":[[[80.0,0.0],[85.0,10.0]]]}"#
    static let defaultMilkyWayLevel = #"{"level":1,"polygons":[[[10,10],[20,10],[20,20]]],"holes":[]}"#

    /// A synthetic star record with the given extra JSON members.
    static func star(hip: Int, name: String? = nil, magnitude: Double = 5, extra: String = "") -> String {
        let nameMember = name.map { #""n":"\#($0)","# } ?? ""
        return #"{"hip":\#(hip),\#(nameMember)"c":"Ori","ra":10.0,"de":20.0,"m":\#(magnitude)\#(extra)}"#
    }
}

// MARK: - Loading the bundled catalog

final class CatalogLoadingTests: XCTestCase {
    func testLoadsTheBundledFilesWithoutRejectingAnyRecord() throws {
        let catalog = try CatalogFixture.catalog()
        let report = catalog.loadReport
        XCTAssertTrue(report.isClean, "\(report.issues)")
        XCTAssertEqual(report.rejectedCount, 0)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.stars.accepted, try CatalogFixture.rawStars().count)
        XCTAssertEqual(report.deepSkyObjects.accepted + report.deepSkyObjects.merged, try CatalogFixture.rawDeepSky().count)
        XCTAssertEqual(report.constellations.accepted, 88)
        XCTAssertEqual(report.constellations.rejected, 0)
        XCTAssertEqual(report.stars.merged, 0)
    }

    func testBundledCountsMatchTheDataFiles() throws {
        let catalog = try CatalogFixture.catalog()
        let stars = try CatalogFixture.rawStars()
        let deepSky = try CatalogFixture.rawDeepSky()
        XCTAssertEqual(stars.count, 9001)
        XCTAssertEqual(deepSky.count, 2441)
        XCTAssertEqual(catalog.renderStars.count, stars.count)
        XCTAssertEqual(catalog.constellations.count, 88)
        XCTAssertEqual(catalog.milkyWay.levels.count, 5)
        let merged = catalog.loadReport.deepSkyObjects.merged
        XCTAssertEqual(catalog.objects.count, 9 + 3 + (deepSky.count - merged) + stars.count)
        XCTAssertEqual(catalog.listedObjects.count, catalog.objects.filter(\.isListed).count)
        XCTAssertEqual(catalog.listedObjects.map(\.id), catalog.objects.filter(\.isListed).map(\.id))
    }

    func testObjectsAreOrderedSolarSystemSpecialDeepSkyThenStarsByMagnitude() throws {
        let catalog = try CatalogFixture.catalog()
        let objects = catalog.objects
        XCTAssertEqual(objects.prefix(9).map(\.id), ["sun", "moon", "planet.mercury", "planet.venus", "planet.mars",
                                                     "planet.jupiter", "planet.saturn", "planet.uranus", "planet.neptune"])
        XCTAssertEqual(objects[9..<12].map(\.id), ["special.galacticCenter", "special.ncp", "special.scp"])
        let firstStar = try XCTUnwrap(objects.firstIndex { $0.id.hasPrefix("star.") })
        XCTAssertTrue(objects[12..<firstStar].allSatisfy { $0.id.hasPrefix("dso.") })
        XCTAssertTrue(objects[firstStar...].allSatisfy { $0.id.hasPrefix("star.") })
        XCTAssertEqual(objects[12].id, "dso.M1", "deep-sky objects keep the file order: Messier first")
        let magnitudes = objects[firstStar...].compactMap(\.magnitude)
        XCTAssertEqual(magnitudes.count, objects.count - firstStar)
        XCTAssertEqual(magnitudes, magnitudes.sorted())
        XCTAssertEqual(objects[firstStar].id, "star.hip32349", "Sirius is the brightest star")
    }

    func testIdentifiersAreUniqueWellFormedAndResolvable() throws {
        let catalog = try CatalogFixture.catalog()
        let identifiers = catalog.objects.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "duplicate identifiers")
        let prefixes = ["dso.", "star.hip", "star.hr", "star.hyg", "planet.", "special."]
        for object in catalog.objects {
            XCTAssertFalse(object.id.isEmpty)
            XCTAssertTrue(object.id == "sun" || object.id == "moon" || prefixes.contains(where: object.id.hasPrefix), object.id)
            XCTAssertEqual(catalog.object(id: object.id)?.id, object.id)
        }
        XCTAssertNil(catalog.object(id: ""))
        XCTAssertNil(catalog.object(id: "dso.M999"))
        XCTAssertNil(catalog.object(id: "custom.00000000-0000-0000-0000-000000000000"))
    }

    func testAllMessierObjectsArePresent() throws {
        let catalog = try CatalogFixture.catalog()
        for number in 1...110 {
            let object = try XCTUnwrap(catalog.object(id: "dso.M\(number)"), "M\(number) is missing")
            XCTAssertEqual(object.designations.first, "M \(number)")
            XCTAssertTrue(object.isListed)
            XCTAssertNotNil(object.constellation)
        }
        XCTAssertEqual(catalog.object(id: "dso.M31")?.name, "Andromeda Galaxy")
        XCTAssertEqual(catalog.object(id: "dso.M31")?.designations, ["M 31", "NGC 224"])
        XCTAssertEqual(catalog.object(id: "dso.M31")?.constellation, "And")
        XCTAssertEqual(catalog.object(id: "dso.M31")?.constellationName, "Andromeda")
        XCTAssertEqual(catalog.object(id: "dso.M2")?.name, "M 2", "objects without a common name are named by catalog number")
        XCTAssertEqual(catalog.object(id: "dso.M102")?.designations, ["M 102", "NGC 5866"])
        XCTAssertEqual(catalog.object(id: "dso.NGC7000")?.name, "North America Nebula")
        XCTAssertEqual(catalog.object(id: "dso.IC434")?.designations, ["IC 434"])
    }

    func testEveryFixedPositionIsFiniteAndInRange() throws {
        let catalog = try CatalogFixture.catalog()
        var fixed = 0
        for object in catalog.objects {
            switch object.position {
            case .fixed(let coordinate, let motion):
                fixed += 1
                XCTAssertTrue(coordinate.rightAscension.isFinite && (0..<360).contains(coordinate.rightAscension), object.id)
                XCTAssertTrue(coordinate.declination.isFinite && (-90...90).contains(coordinate.declination), object.id)
                XCTAssertEqual(object.j2000, coordinate)
                if let motion {
                    XCTAssertTrue(motion.raMilliarcsecondsPerYear.isFinite && motion.decMilliarcsecondsPerYear.isFinite, object.id)
                }
            case .solarSystem, .celestialPole:
                XCTAssertNil(object.j2000)
            }
            if let magnitude = object.magnitude { XCTAssertTrue(magnitude.isFinite, object.id) }
            if let index = object.colorIndex { XCTAssertTrue(index.isFinite, object.id) }
            if let distance = object.distanceLightYears { XCTAssertTrue(distance.isFinite && distance > 0, object.id) }
            if let size = object.angularSize {
                XCTAssertTrue(size.majorArcminutes > 0 && size.majorArcminutes.isFinite, object.id)
            }
            XCTAssertFalse(object.name.isEmpty)
        }
        XCTAssertEqual(fixed, catalog.objects.count - 9 - 2)
    }

    func testStarsFollowTheNamingAndListingRules() throws {
        let catalog = try CatalogFixture.catalog()
        for star in try CatalogFixture.rawStars() {
            let id = star.hip.map { "star.hip\($0)" } ?? star.hr.map { "star.hr\($0)" } ?? "star.hyg\(star.hyg ?? 0)"
            let object = try XCTUnwrap(catalog.object(id: id), id)
            var expectedName = star.n
            if expectedName == nil, let bayer = star.b { expectedName = "\(bayer) \(star.c)" }
            if expectedName == nil, let flamsteed = star.f { expectedName = "\(flamsteed) \(star.c)" }
            if expectedName == nil, let hr = star.hr { expectedName = "HR \(hr)" }
            if expectedName == nil, let hd = star.hd { expectedName = "HD \(hd)" }
            if expectedName == nil, let hip = star.hip { expectedName = "HIP \(hip)" }
            XCTAssertEqual(object.name, expectedName, id)
            XCTAssertEqual(object.category, star.hip == CatalogFactory.quasarHipparcosNumber ? .other : .star, id)
            XCTAssertEqual(object.isListed, star.n != nil || star.m <= 3.5, id)
            XCTAssertEqual(object.magnitude, star.m)
            XCTAssertEqual(object.constellation, star.c)
            XCTAssertNotNil(object.constellationName, id)
            XCTAssertEqual(object.colorIndex, star.ci)
            XCTAssertEqual(object.spectralType, star.sp)
            XCTAssertEqual(object.j2000, EquatorialCoordinate(rightAscension: star.ra, declination: star.de))
            XCTAssertEqual(object.distanceLightYears == nil, star.d == nil)
            if let parsecs = star.d, let lightYears = object.distanceLightYears {
                XCTAssertEqual(lightYears, parsecs * 3.2615637771674, accuracy: 1e-6)
            }
            guard case .fixed(_, let motion) = object.position else { return XCTFail(id) }
            XCTAssertEqual(motion?.raMilliarcsecondsPerYear, star.pa)
            XCTAssertEqual(motion?.decMilliarcsecondsPerYear, star.pd)
            // Designations come in a fixed order: Bayer, Flamsteed, then catalog numbers.
            var expectedDesignations: [String] = []
            if let bayer = star.b { expectedDesignations.append("\(bayer) \(star.c)") }
            if let flamsteed = star.f { expectedDesignations.append("\(flamsteed) \(star.c)") }
            let numbers = ["HR \(star.hr ?? 0)", "HD \(star.hd ?? 0)", "HIP \(star.hip ?? 0)"]
            let present = [star.hr != nil, star.hd != nil, star.hip != nil]
            for (number, isPresent) in zip(numbers, present) {
                XCTAssertEqual(object.designations.contains(number), isPresent, "\(id) \(number)")
            }
            for designation in expectedDesignations {
                XCTAssertTrue(object.designations.contains(designation), "\(id) \(designation)")
            }
            let catalogNumbers = object.designations.filter { $0.hasPrefix("HR ") || $0.hasPrefix("HD ") || $0.hasPrefix("HIP ") }
            XCTAssertEqual(catalogNumbers, numbers.enumerated().filter { present[$0.offset] }.map(\.element), id)
        }
    }

    func testBayerDesignationsListTheLongFormWithTheGenitive() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.object(id: "star.hip32349")?.designations,
                       ["α CMa", "Alpha Canis Majoris", "9 CMa", "HR 2491", "HD 48915", "HIP 32349"])
        XCTAssertEqual(catalog.object(id: "star.hip71683")?.designations,
                       ["α¹ Cen", "Alpha¹ Centauri", "HR 5459", "HD 128620", "HIP 71683"])
        XCTAssertEqual(catalog.object(id: "star.hip11767")?.designations.prefix(3), ["α UMi", "Alpha Ursae Minoris", "1 UMi"])
        XCTAssertEqual(catalog.object(id: "star.hip27989")?.name, "Betelgeuse")
        XCTAssertEqual(catalog.object(id: "star.hip27989")?.designations.prefix(2), ["α Ori", "Alpha Orionis"])
    }

    func testStarsWithoutAProperNameAreNamedByTheirDesignation() throws {
        let catalog = try CatalogFixture.catalog()
        let stars = try CatalogFixture.rawStars()
        let bayer = try XCTUnwrap(stars.first { $0.n == nil && $0.b != nil })
        let flamsteed = try XCTUnwrap(stars.first { $0.n == nil && $0.b == nil && $0.f != nil })
        let harvard = try XCTUnwrap(stars.first { $0.n == nil && $0.b == nil && $0.f == nil && $0.hr != nil })
        let hipparcos = try XCTUnwrap(stars.first { $0.n == nil && $0.b == nil && $0.f == nil && $0.hr == nil && $0.hip != nil })
        func name(_ star: CatalogFixture.RawStar) -> String? {
            catalog.object(id: star.hip.map { "star.hip\($0)" } ?? "star.hr\(star.hr ?? 0)")?.name
        }
        XCTAssertEqual(name(bayer), "\(bayer.b ?? "") \(bayer.c)")
        XCTAssertEqual(name(flamsteed), "\(flamsteed.f ?? 0) \(flamsteed.c)")
        XCTAssertEqual(name(harvard), "HR \(harvard.hr ?? 0)")
        XCTAssertEqual(name(hipparcos), "HIP \(hipparcos.hip ?? 0)")
        XCTAssertEqual(catalog.object(id: "star.hip3801")?.name.hasSuffix(" Cas"), true)
    }

    func testStarsWithOnlyAHygRowAreIdentifiedByIt() throws {
        let catalog = try CatalogFixture.catalog()
        let rows = try CatalogFixture.rawStars().filter { $0.hip == nil && $0.hr == nil }
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let object = try XCTUnwrap(catalog.object(id: "star.hyg\(try XCTUnwrap(row.hyg))"))
            XCTAssertEqual(object.name, row.n)
            XCTAssertTrue(object.designations.contains("HYG \(row.hyg ?? 0)"))
            XCTAssertTrue(object.isListed, "named stars are listed")
        }
        XCTAssertEqual(catalog.object(id: "star.hyg118720")?.name, "Wolf 359")
    }

    func testDeepSkyObjectsFollowTheNamingAndCategoryRules() throws {
        let catalog = try CatalogFixture.catalog()
        var merged = 0
        for record in try CatalogFixture.rawDeepSky() {
            guard let object = catalog.object(id: "dso.\(record.id)") else {
                merged += 1
                XCTAssertTrue(record.t == "*" || record.t == "**", "\(record.id) vanished")
                XCTAssertNil(record.m)
                continue
            }
            XCTAssertEqual(object.isListed, (record.p ?? 3) <= 3, record.id)
            XCTAssertEqual(object.prominence.rawValue, record.p ?? 3, record.id)
            XCTAssertEqual(object.group == .special, object.category == .other || object.category == .milkyWay)
            XCTAssertEqual(object.category, expectedCategory(forOpenNGCType: record.t), record.id)
            XCTAssertEqual(object.magnitude, record.vm ?? record.bm, record.id)
            XCTAssertEqual(object.constellation, record.c)
            XCTAssertNotNil(object.constellationName, record.id)
            XCTAssertEqual(object.j2000, EquatorialCoordinate(rightAscension: record.ra, declination: record.de))
            XCTAssertEqual(object.alternateNames, Array((record.names ?? []).dropFirst()), record.id)
            XCTAssertNil(object.colorIndex)
            XCTAssertNil(object.spectralType)
            XCTAssertNil(object.distanceLightYears)
            let numberNames = [record.m.map { "M \($0)" }].compactMap { $0 }
                + (record.ngc ?? []).map { "NGC \($0)" } + (record.ic ?? []).map { "IC \($0)" }
            if let first = record.names?.first {
                XCTAssertEqual(object.name, first, record.id)
            } else if let first = numberNames.first {
                XCTAssertEqual(object.name, first, record.id)
            }
            XCTAssertEqual(Array(object.designations.prefix(numberNames.count)), numberNames, record.id)
            XCTAssertFalse(object.designations.isEmpty)
            XCTAssertEqual(object.angularSize?.majorArcminutes, record.maj, record.id)
            XCTAssertEqual(object.angularSize?.minorArcminutes, record.maj == nil ? nil : record.min, record.id)
            if record.maj != nil, let angle = record.pa {
                XCTAssertEqual(object.angularSize?.positionAngle, angle.truncatingRemainder(dividingBy: 180), record.id)
            }
        }
        XCTAssertEqual(merged, catalog.loadReport.deepSkyObjects.merged)
        XCTAssertEqual(merged, 2)
    }

    func testOtherCatalogDesignationsAreSpelledOut() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.object(id: "dso.C14")?.designations, ["Caldwell 14"])
        XCTAssertEqual(catalog.object(id: "dso.C9")?.designations, ["Caldwell 9", "Sh2-155"])
        XCTAssertEqual(catalog.object(id: "dso.C41")?.designations, ["Caldwell 41", "Melotte 25", "Collinder 50"])
        XCTAssertEqual(catalog.object(id: "dso.Mel111")?.designations, ["Melotte 111"])
        XCTAssertEqual(catalog.object(id: "dso.B33")?.designations, ["Barnard 33"])
        XCTAssertEqual(catalog.object(id: "dso.ESO56-115")?.designations, ["ESO 56-115"])
        XCTAssertEqual(catalog.object(id: "dso.Cl399")?.designations, ["Collinder 399"])
        XCTAssertEqual(catalog.object(id: "dso.H5")?.designations, ["Harvard 5", "Collinder 258"])
        XCTAssertEqual(catalog.object(id: "dso.IC359A")?.designations, ["IC 359A"])
        XCTAssertEqual(catalog.object(id: "dso.IC2431_NED02")?.designations, ["IC 2431 NED02"])
        XCTAssertEqual(catalog.object(id: "dso.HCG92")?.designations, ["HCG 92"])
        XCTAssertEqual(catalog.object(id: "dso.PGC143")?.designations, ["PGC 143"])
        XCTAssertEqual(catalog.object(id: "dso.UGC5373")?.designations, ["UGC 5373"])
        XCTAssertEqual(catalog.object(id: "dso.MWSC3171")?.designations, ["MWSC 3171"])
        XCTAssertEqual(catalog.object(id: "dso.NGC2239")?.designations, ["NGC 2239", "NGC 2244", "Caldwell 50"])
        XCTAssertEqual(catalog.object(id: "dso.NGC281")?.designations, ["NGC 281", "IC 11", "Sh2-184"])
        XCTAssertEqual(catalog.object(id: "dso.M8")?.designations, ["M 8", "NGC 6523", "NGC 6533", "Sh2-25"])
    }

    func testListingRulesForEveryKindOfObject() throws {
        let catalog = try CatalogFixture.catalog()
        for object in catalog.objects where !object.id.hasPrefix("star.") && !object.isDeepSky {
            XCTAssertTrue(object.isListed, "\(object.id) is a solar-system or special object")
        }
        for object in catalog.deepSkyObjects {
            XCTAssertEqual(object.isListed, object.prominence <= .notable, "\(object.id) is listed unless it is obscure")
        }
        XCTAssertTrue(catalog.deepSkyObjects.contains { !$0.isListed }, "the obscure deep-sky objects are not listed")
        let stars = try CatalogFixture.rawStars()
        func object(_ star: CatalogFixture.RawStar) throws -> CelestialObject {
            try XCTUnwrap(catalog.object(id: star.hip.map { "star.hip\($0)" } ?? "star.hr\(star.hr ?? 0)"))
        }
        let faintUnnamed = try XCTUnwrap(stars.first { $0.n == nil && $0.m > 3.5 })
        let faintNamed = try XCTUnwrap(stars.first { $0.n != nil && $0.m > 6 })
        let brightUnnamed = try XCTUnwrap(stars.first { $0.n == nil && $0.m <= 3.5 })
        let boundary = try XCTUnwrap(stars.first { $0.n == nil && $0.m == 3.5 })
        XCTAssertFalse(try object(faintUnnamed).isListed, "faint unnamed stars are only found by search")
        XCTAssertTrue(try object(faintNamed).isListed, "named stars are always listed")
        XCTAssertTrue(try object(brightUnnamed).isListed)
        XCTAssertTrue(try object(boundary).isListed, "magnitude 3.5 is still listed")
        let listedStars = catalog.listedObjects.filter { $0.id.hasPrefix("star.") }
        XCTAssertEqual(listedStars.count, stars.filter { $0.n != nil || $0.m <= 3.5 }.count)
        XCTAssertEqual(catalog.listedObjects.count, 9 + 3 + catalog.deepSkyObjects.filter(\.isListed).count + listedStars.count)
    }

    func testCategoryMappingCoversEveryOpenNGCType() throws {
        let expected: [String: ObjectCategory] = [
            "G": .galaxy, "GPair": .galaxyGroup, "GTrpl": .galaxyGroup, "GGroup": .galaxyGroup,
            "OCl": .openCluster, "GCl": .globularCluster, "Cl+N": .clusterWithNebula, "PN": .planetaryNebula,
            "HII": .emissionNebula, "EmN": .emissionNebula, "RfN": .reflectionNebula, "DrkN": .darkNebula,
            "Neb": .nebula, "SNR": .supernovaRemnant, "*Ass": .starAssociation, "**": .doubleStar, "*": .star,
            "Other": .other, "Nova": .other, "NonEx": .other, "Dup": .other, "": .other, "g": .other, "unknown": .other,
        ]
        for (code, category) in expected {
            XCTAssertEqual(ObjectCategory(openNGCType: code), category, "type code \(code)")
        }
        // Every type code in the data file is one the mapping knows about, and the counts line up.
        let catalog = try CatalogFixture.catalog()
        let records = try CatalogFixture.rawDeepSky()
        var rawCounts: [String: Int] = [:]
        for record in records { rawCounts[record.t, default: 0] += 1 }
        XCTAssertTrue(Set(rawCounts.keys).isSubset(of: Set(expected.keys)), "\(Set(rawCounts.keys).subtracting(expected.keys))")
        let deepSky = catalog.objects.filter { $0.id.hasPrefix("dso.") }
        for category in Set(expected.values) {
            let inData = records.filter { ObjectCategory(openNGCType: $0.t) == category }
            let mergedAway = inData.filter { catalog.object(id: "dso.\($0.id)") == nil }.count
            XCTAssertEqual(deepSky.filter { $0.category == category }.count + mergedAway, inData.count, "\(category)")
        }
        XCTAssertEqual(deepSky.filter { $0.category == .other }.count, rawCounts["Other"] ?? 0)
        XCTAssertEqual(deepSky.filter { $0.category == .other }.map(\.id).sorted(), ["dso.M73", "dso.NGC405"])
        XCTAssertEqual(Set(deepSky.map(\.category)),
                       [.galaxy, .galaxyGroup, .openCluster, .globularCluster, .clusterWithNebula, .planetaryNebula,
                        .emissionNebula, .reflectionNebula, .darkNebula, .nebula, .supernovaRemnant, .starAssociation,
                        .doubleStar, .star, .other])
    }

    func testBuiltInSolarSystemObjects() throws {
        let catalog = try CatalogFixture.catalog()
        let expected: [(String, String, ObjectCategory, SolarSystemBody)] = [
            ("sun", "Sun", .sun, .sun), ("moon", "Moon", .moon, .moon), ("planet.mercury", "Mercury", .planet, .mercury),
            ("planet.venus", "Venus", .planet, .venus), ("planet.mars", "Mars", .planet, .mars),
            ("planet.jupiter", "Jupiter", .planet, .jupiter), ("planet.saturn", "Saturn", .planet, .saturn),
            ("planet.uranus", "Uranus", .planet, .uranus), ("planet.neptune", "Neptune", .planet, .neptune),
        ]
        for (id, name, category, body) in expected {
            let object = try XCTUnwrap(catalog.object(id: id), id)
            XCTAssertEqual(object.name, name)
            XCTAssertEqual(object.category, category)
            XCTAssertEqual(object.position, .solarSystem(body))
            XCTAssertTrue(object.isSolarSystem)
            XCTAssertTrue(object.isListed)
            XCTAssertEqual(object.group, .solarSystem)
            XCTAssertNil(object.magnitude, "brightness of solar-system bodies changes")
            XCTAssertNil(object.j2000)
            XCTAssertNil(object.constellation)
            XCTAssertEqual(object.subtitle, category.displayName)
        }
        XCTAssertTrue(try XCTUnwrap(catalog.object(id: "sun")).notes?.contains("solar filter") ?? false)
        XCTAssertNil(catalog.object(id: "planet.jupiter")?.notes)
    }

    func testBuiltInSpecialObjects() throws {
        let catalog = try CatalogFixture.catalog()
        let center = try XCTUnwrap(catalog.object(id: "special.galacticCenter"))
        XCTAssertEqual(center.category, .milkyWay)
        XCTAssertEqual(center.group, .special)
        XCTAssertEqual(center.constellation, "Sgr")
        XCTAssertEqual(center.constellationName, "Sagittarius")
        guard case .fixed(let coordinate, nil) = center.position else { return XCTFail("fixed position expected") }
        XCTAssertEqual(coordinate.rightAscensionHours, 17 + 45.0 / 60 + 40.04 / 3600, accuracy: 1e-9)
        XCTAssertEqual(coordinate.declination, -(29 + 28.1 / 3600), accuracy: 1e-9)
        // Sagittarius A* is at galactic longitude 359.94° and latitude −0.05°.
        let galactic = CoordinateTransforms.equatorialJ2000ToGalactic(coordinate)
        XCTAssertEqual(AstroMath.normalizeSignedDegrees(galactic.longitude), -0.06, accuracy: 0.05)
        XCTAssertEqual(galactic.latitude, -0.05, accuracy: 0.05)

        let north = try XCTUnwrap(catalog.object(id: "special.ncp"))
        let south = try XCTUnwrap(catalog.object(id: "special.scp"))
        XCTAssertEqual(north.position, .celestialPole(north: true))
        XCTAssertEqual(south.position, .celestialPole(north: false))
        XCTAssertEqual(north.category, .celestialPole)
        XCTAssertEqual(north.constellation, "UMi")
        XCTAssertEqual(south.constellation, "Oct")
        XCTAssertEqual(north.name, "North Celestial Pole")
        XCTAssertEqual(south.name, "South Celestial Pole")
        XCTAssertFalse(north.isSolarSystem)
        XCTAssertNil(north.j2000)
        XCTAssertEqual(catalog.objects(in: .special).filter { $0.id.hasPrefix("special.") }.count, 3)
    }

    func testAcronymsOfDeepSkyObjectsAlsoWorkAsIdentifiers() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.object(id: "dso.LMC")?.id, "dso.ESO56-115")
        XCTAssertEqual(catalog.object(id: "dso.LMC")?.name, "Large Magellanic Cloud")
        XCTAssertEqual(catalog.object(id: "dso.SMC")?.id, "dso.NGC292")
        XCTAssertEqual(catalog.object(id: "dso.ESO56-115")?.name, "Large Magellanic Cloud")
        XCTAssertEqual(catalog.object(id: "dso.ESO56-115")?.alternateNames, ["Nubecula Major", "LMC"])
        XCTAssertNil(catalog.object(id: "dso.WLM"))
        XCTAssertNil(catalog.object(id: "dso.lmc"), "identifiers are case-sensitive")
    }

    func testPlainStarRecordsOfTheDeepSkyDataAreMergedIntoTheirStars() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertNil(catalog.object(id: "dso.NGC1990"))
        XCTAssertNil(catalog.object(id: "dso.IC1318"))
        XCTAssertNotNil(catalog.object(id: "dso.NGC7114"), "a nova without a star in the catalog stays")
        XCTAssertNotNil(catalog.object(id: "dso.M40"), "Messier objects are never merged")
        let alnilam = try XCTUnwrap(catalog.object(id: "star.hip26311"))
        XCTAssertEqual(alnilam.name, "Alnilam")
        XCTAssertTrue(alnilam.designations.contains("NGC 1990"))
        XCTAssertEqual(alnilam.designations.last, "NGC 1990")
        let sadr = try XCTUnwrap(catalog.object(id: "star.hip100453"))
        XCTAssertTrue(sadr.designations.contains("IC 1318"))
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.merged, 2)
        XCTAssertEqual(catalog.search("alnilam").map(\.object.id), ["star.hip26311"])
        XCTAssertEqual(catalog.search("ic 1318").first?.object.id, "star.hip100453")
        XCTAssertEqual(catalog.search("ngc 1990").first?.matchedText, "NGC 1990")
    }

    func testPopularNamesAreAlternateNames() throws {
        let catalog = try CatalogFixture.catalog()
        let polaris = try XCTUnwrap(catalog.object(id: "star.hip11767"))
        XCTAssertEqual(polaris.name, "Polaris")
        XCTAssertEqual(polaris.alternateNames, ["North Star", "Pole Star", "Lodestar"])
        XCTAssertEqual(catalog.object(id: "star.hip32349")?.alternateNames, ["Dog Star"])
        XCTAssertEqual(catalog.object(id: "sun")?.alternateNames, ["Sol"])
        XCTAssertEqual(catalog.object(id: "moon")?.alternateNames, ["Luna"])
        XCTAssertEqual(catalog.search("pole star").first?.matchedText, "Pole Star")
        XCTAssertEqual(catalog.search("north star").first?.kind, .exact)
        // Only the stars of the table have alternate names: the names of the records merged into Alnilam and
        // Sadr are names they answer to already.
        let withAlternates = catalog.objects.filter { $0.id.hasPrefix("star.") && !$0.alternateNames.isEmpty }.map(\.id)
        XCTAssertEqual(Set(withAlternates), ["star.hip11767", "star.hip32349"])
        XCTAssertEqual(Set(CatalogFactory.popularNames.keys), [11767, 32349])
    }

    func testTheQuasarOfTheStarDataIsNotAStar() throws {
        let catalog = try CatalogFixture.catalog()
        let quasar = try XCTUnwrap(catalog.object(id: "star.hip60936"))
        XCTAssertEqual(CatalogFactory.quasarHipparcosNumber, 60936)
        XCTAssertEqual(quasar.name, "3C 273")
        XCTAssertEqual(quasar.category, .other)
        XCTAssertEqual(quasar.group, .special)
        XCTAssertTrue(quasar.isListed, "it has a proper name")
        XCTAssertEqual(quasar.constellationName, "Virgo")
        XCTAssertEqual(quasar.magnitude, 12.88)
        XCTAssertTrue(try XCTUnwrap(quasar.notes).contains("quasar"))
        XCTAssertEqual(quasar.subtitle, "Other \u{00B7} Virgo \u{00B7} mag 12.9")
        XCTAssertEqual(catalog.search("3c 273").first?.object.id, "star.hip60936")
        XCTAssertEqual(catalog.search("hip 60936").first?.object.id, "star.hip60936")
        XCTAssertFalse(catalog.objects(in: .stars).contains { $0.id == "star.hip60936" })
        XCTAssertTrue(catalog.objects(in: .special).contains { $0.id == "star.hip60936" })
        XCTAssertEqual(catalog.objects.filter { $0.id.hasPrefix("star.") && $0.category != .star }.map(\.id), ["star.hip60936"],
                       "every other entry of the star data is a star")
        XCTAssertTrue(catalog.renderStars.contains { $0.id == "star.hip60936" }, "it is still a point of light on the sky")
    }

    func testStarsMayShareTheirProperName() throws {
        let catalog = try CatalogFixture.catalog()
        let exact = catalog.search("p Eridani").filter { $0.kind == .exact }
        XCTAssertEqual(exact.map(\.object.id), ["star.hip7751", "star.hr487"], "two stars, brighter first")
        XCTAssertEqual(exact.map(\.object.name), ["p Eridani", "p Eridani"])
        XCTAssertNotEqual(exact[0].object, exact[1].object)
    }

    func testConstellationsAreCompleteAndFindableByAbbreviation() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertEqual(catalog.constellations.count, 88)
        XCTAssertEqual(Set(catalog.constellations.map(\.abbreviation)).count, 88)
        for constellation in catalog.constellations {
            XCTAssertEqual(constellation.id, constellation.abbreviation)
            XCTAssertEqual(constellation.abbreviation.count, 3)
            XCTAssertFalse(constellation.name.isEmpty)
            XCTAssertFalse(constellation.genitive.isEmpty)
            XCTAssertFalse(constellation.lines.isEmpty, constellation.name)
            XCTAssertTrue(constellation.lines.allSatisfy { $0.count >= 2 })
            XCTAssertTrue((0..<360).contains(constellation.labelPosition.rightAscension))
            XCTAssertEqual(catalog.constellation(abbreviation: constellation.abbreviation), constellation)
            XCTAssertEqual(catalog.constellation(abbreviation: constellation.abbreviation.lowercased()), constellation)
            XCTAssertEqual(catalog.constellation(abbreviation: constellation.abbreviation.uppercased()), constellation)
        }
        let orion = try XCTUnwrap(catalog.constellation(abbreviation: "Ori"))
        XCTAssertEqual(orion.name, "Orion")
        XCTAssertEqual(orion.genitive, "Orionis")
        XCTAssertEqual(catalog.constellation(abbreviation: "cma")?.name, "Canis Major")
        XCTAssertEqual(catalog.constellation(abbreviation: "CrA")?.genitive, "Coronae Australis")
        XCTAssertEqual(catalog.constellation(abbreviation: "Cru")?.genitive, "Crucis")
        XCTAssertNil(catalog.constellation(abbreviation: "Xyz"))
        XCTAssertNil(catalog.constellation(abbreviation: ""))
        XCTAssertEqual(catalog.constellations.map(\.name), catalog.constellations.map(\.name).sorted { $0.folding(options: .diacriticInsensitive, locale: nil) < $1.folding(options: .diacriticInsensitive, locale: nil) })
        // Every object's constellation resolves to a name.
        for object in catalog.objects {
            if let abbreviation = object.constellation {
                XCTAssertEqual(object.constellationName, catalog.constellation(abbreviation: abbreviation)?.name, object.id)
            }
        }
    }

    func testMilkyWayOutlineIsWellFormed() throws {
        let catalog = try CatalogFixture.catalog()
        let levels = catalog.milkyWay.levels
        XCTAssertEqual(levels.map(\.level), [1, 2, 3, 4, 5])
        XCTAssertEqual(levels[0].polygons.count, 1)
        XCTAssertEqual(levels[0].holes.count, 8)
        XCTAssertEqual(levels.map { $0.polygons.count + $0.holes.count }.reduce(0, +), catalog.loadReport.milkyWayRings.accepted)
        for level in levels {
            XCTAssertFalse(level.polygons.isEmpty)
            for ring in level.polygons + level.holes {
                XCTAssertGreaterThanOrEqual(ring.count, 3)
                XCTAssertTrue(ring.allSatisfy { $0.rightAscension.isFinite && $0.declination.isFinite })
            }
        }
    }

    func testRenderStarsAreSortedByMagnitudeAndConsistentWithTheObjects() throws {
        let catalog = try CatalogFixture.catalog()
        let stars = catalog.renderStars
        XCTAssertEqual(stars.map(\.magnitude), stars.map(\.magnitude).sorted())
        XCTAssertEqual(stars.first?.id, "star.hip32349")
        XCTAssertEqual(Set(stars.map(\.id)).count, stars.count)
        for star in stars {
            XCTAssertEqual(star.unitVector.length, 1, accuracy: 1e-12)
            XCTAssertTrue(star.magnitude.isFinite)
        }
        for star in stars.prefix(500) {
            let object = try XCTUnwrap(catalog.object(id: star.id))
            XCTAssertEqual(object.magnitude, star.magnitude)
            XCTAssertEqual(object.colorIndex, star.colorIndex)
            let coordinate = try XCTUnwrap(object.j2000)
            XCTAssertLessThan(coordinate.unitVector.angle(to: star.unitVector), 1e-9)
        }
        let named = stars.filter { $0.name != nil }
        XCTAssertEqual(named.count, 464)
        XCTAssertEqual(stars.first?.name, "Sirius")
        XCTAssertEqual(Set(named.compactMap(\.name)).count, 463, "p Eridani is named twice in the data")
    }

    func testGroupsPartitionTheListedObjects() throws {
        let catalog = try CatalogFixture.catalog()
        var seen: [String] = []
        for group in ObjectGroup.allCases {
            let objects = catalog.objects(in: group)
            XCTAssertFalse(objects.isEmpty, "\(group)")
            XCTAssertTrue(objects.allSatisfy { $0.isListed && $0.group == group }, "\(group)")
            XCTAssertEqual(objects.map(\.id), catalog.sorted(objects, by: .name).map(\.id), "\(group) is sorted by name")
            seen += objects.map(\.id)
        }
        XCTAssertEqual(Set(seen), Set(catalog.listedObjects.map(\.id)))
        XCTAssertEqual(seen.count, catalog.listedObjects.count)
        XCTAssertEqual(catalog.objects(in: .solarSystem).count, 9)
        XCTAssertTrue(catalog.objects(in: .galaxies).contains { $0.id == "dso.M31" })
        XCTAssertTrue(catalog.objects(in: .nebulae).contains { $0.id == "dso.M42" })
        XCTAssertTrue(catalog.objects(in: .clusters).contains { $0.id == "dso.M45" })
        XCTAssertTrue(catalog.objects(in: .stars).contains { $0.id == "star.hip32349" })
    }

    private func expectedCategory(forOpenNGCType code: String) -> ObjectCategory {
        switch code {
        case "G": .galaxy
        case "GPair", "GTrpl", "GGroup": .galaxyGroup
        case "OCl": .openCluster
        case "GCl": .globularCluster
        case "Cl+N": .clusterWithNebula
        case "PN": .planetaryNebula
        case "HII", "EmN": .emissionNebula
        case "RfN": .reflectionNebula
        case "DrkN": .darkNebula
        case "Neb": .nebula
        case "SNR": .supernovaRemnant
        case "*Ass": .starAssociation
        case "**": .doubleStar
        case "*": .star
        default: .other
        }
    }
}

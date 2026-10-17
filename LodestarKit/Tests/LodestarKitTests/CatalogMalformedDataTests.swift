import XCTest
@testable import LodestarKit

/// Damaged, hostile or unexpected data files: whole files that cannot be used raise a `CatalogError`,
/// single bad records are skipped and counted.
final class CatalogMalformedDataTests: XCTestCase {
    // MARK: Building records

    /// A JSON object from members in order.
    private func json(_ members: [(String, String)]) -> String {
        "{" + members.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
    }

    private let baseStar: [(String, String)] = [("hip", "2"), ("n", "\"Other Star\""), ("c", "\"Ori\""),
                                                ("ra", "10.0"), ("de", "20.0"), ("m", "3.0")]
    private let baseDeepSky: [(String, String)] = [("id", "\"NGC1\""), ("t", "\"G\""), ("ra", "10.0"), ("de", "20.0"),
                                                    ("c", "\"And\""), ("vm", "9.0"), ("maj", "8"), ("min", "4"), ("pa", "30")]

    private func changing(_ members: [(String, String)], _ key: String, to value: String?) -> [(String, String)] {
        var result = members.filter { $0.0 != key }
        if let value { result.append((key, value)) }
        return result
    }

    private func star(_ key: String, _ value: String?) -> String { json(changing(baseStar, key, to: value)) }
    private func deepSky(_ key: String, _ value: String?) -> String { json(changing(baseDeepSky, key, to: value)) }

    /// Loads the default valid star next to `record` and returns the catalog.
    private func catalog(withStar record: String) throws -> Catalog {
        try CatalogFixture.syntheticCatalog(stars: [CatalogFixture.defaultStar, record])
    }

    private func catalog(withDeepSky record: String) throws -> Catalog {
        try CatalogFixture.syntheticCatalog(deepSky: [CatalogFixture.defaultDeepSky, record])
    }

    private func assertStarRejected(_ record: String, _ note: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try catalog(withStar: record)
        XCTAssertEqual(catalog.loadReport.stars.accepted, 1, record, file: file, line: line)
        XCTAssertEqual(catalog.loadReport.stars.rejected, 1, record, file: file, line: line)
        XCTAssertEqual(catalog.objects.filter { $0.id.hasPrefix("star.") }.map(\.id), ["star.hip1"], record, file: file, line: line)
        XCTAssertEqual(catalog.loadReport.issues.count, 1, file: file, line: line)
        XCTAssertTrue(catalog.loadReport.issues[0].hasPrefix("stars[1]: "), catalog.loadReport.issues[0], file: file, line: line)
        if !note.isEmpty {
            XCTAssertTrue(catalog.loadReport.issues[0].contains(note), "\(catalog.loadReport.issues[0]) should mention \(note)", file: file, line: line)
        }
        XCTAssertFalse(catalog.loadReport.isClean, file: file, line: line)
    }

    private func assertStarAccepted(_ record: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try catalog(withStar: record)
        XCTAssertEqual(catalog.loadReport.stars.accepted, 2, "\(record) \(catalog.loadReport.issues)", file: file, line: line)
        XCTAssertEqual(catalog.loadReport.stars.rejected, 0, file: file, line: line)
        XCTAssertTrue(catalog.loadReport.isClean, file: file, line: line)
    }

    private func assertDeepSkyRejected(_ record: String, _ note: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try catalog(withDeepSky: record)
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 1, record, file: file, line: line)
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.rejected, 1, record, file: file, line: line)
        XCTAssertEqual(catalog.objects.filter { $0.id.hasPrefix("dso.") }.map(\.id), ["dso.M1"], record, file: file, line: line)
        XCTAssertTrue(catalog.loadReport.issues.first?.hasPrefix("dsos[1]: ") ?? false, "\(catalog.loadReport.issues)", file: file, line: line)
        if !note.isEmpty {
            XCTAssertTrue(catalog.loadReport.issues.first?.contains(note) ?? false, "\(catalog.loadReport.issues) should mention \(note)", file: file, line: line)
        }
    }

    private func assertError(_ expected: CatalogError, stars: Data? = nil, deepSky: Data? = nil, constellations: Data? = nil,
                             milkyWay: Data? = nil, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try Catalog(starsData: stars ?? CatalogFixture.file("stars", [CatalogFixture.defaultStar]),
                            dsosData: deepSky ?? CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky]),
                            constellationsData: constellations ?? CatalogFixture.file("constellations", [CatalogFixture.defaultConstellation]),
                            milkyWayData: milkyWay ?? CatalogFixture.file("levels", [CatalogFixture.defaultMilkyWayLevel]))
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as CatalogError {
            switch (error, expected) {
            case (.malformed(let a, _), .malformed(let b, _)),
                 (.unreadable(let a, _), .unreadable(let b, _)),
                 (.missingResource(let a), .missingResource(let b)):
                XCTAssertEqual(a, b, "\(error)", file: file, line: line)
            default:
                XCTAssertEqual(error, expected, file: file, line: line)
            }
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: Whole files

    func testTruncatedFilesAreRejected() throws {
        let files: [(CatalogFile, Data)] = try CatalogFile.allCases.map { ($0, try Catalog.bundledData(for: $0)) }
        for (file, data) in files {
            for length in [0, 1, 20, data.count / 10, data.count / 2, data.count - 5, data.count - 3] {
                let truncated = data.prefix(length)
                switch file {
                case .stars: assertError(.malformed(.stars, reason: ""), stars: truncated)
                case .deepSkyObjects: assertError(.malformed(.deepSkyObjects, reason: ""), deepSky: truncated)
                case .constellations: assertError(.malformed(.constellations, reason: ""), constellations: truncated)
                case .milkyWay: assertError(.malformed(.milkyWay, reason: ""), milkyWay: truncated)
                }
            }
        }
        // The complete files load, and so do the files without their final line break.
        XCTAssertNoThrow(try Catalog.loadBundled())
        XCTAssertNoThrow(try Catalog(starsData: try Catalog.bundledData(for: .stars).dropLast(1),
                                     dsosData: try Catalog.bundledData(for: .deepSkyObjects),
                                     constellationsData: try Catalog.bundledData(for: .constellations),
                                     milkyWayData: try Catalog.bundledData(for: .milkyWay)))
    }

    func testWrongTopLevelShapesAreRejected() {
        let shapes = ["[]", "{}", "null", "true", "123", "\"stars\"", #"{"schema":1}"#, #"{"schema":1,"stars":null}"#,
                      #"{"schema":1,"stars":"text"}"#, #"{"schema":1,"stars":{}}"#, #"{"schema":1,"stars":5}"#,
                      #"{"schema":"1","stars":[]}"#, #"{"schema":1.5,"stars":[]}"#, #"{"schema":[1],"stars":[]}"#,
                      #"{"schema":1,"objects":[]}"#, "{\"schema\":1,\"stars\":[]}garbage", "{\"schema\":1,\"stars\":[]}}", ""]
        for shape in shapes {
            assertError(.malformed(.stars, reason: ""), stars: Data(shape.utf8))
        }
    }

    func testEveryFileIsBlamedByName() {
        let bad = Data("[1,2,3]".utf8)
        assertError(.malformed(.stars, reason: ""), stars: bad)
        assertError(.malformed(.deepSkyObjects, reason: ""), deepSky: bad)
        assertError(.malformed(.constellations, reason: ""), constellations: bad)
        assertError(.malformed(.milkyWay, reason: ""), milkyWay: bad)
        assertError(.unsupportedSchema(.stars, version: 2), stars: CatalogFixture.file("stars", [CatalogFixture.defaultStar], schema: "2"))
        assertError(.unsupportedSchema(.deepSkyObjects, version: 0), deepSky: CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky], schema: "0"))
        assertError(.unsupportedSchema(.constellations, version: -1), constellations: CatalogFixture.file("constellations", [], schema: "-1"))
        assertError(.unsupportedSchema(.milkyWay, version: 99), milkyWay: CatalogFixture.file("levels", [], schema: "99"))
        assertError(.unsupportedSchema(.stars, version: nil), stars: Data(#"{"stars":[]}"#.utf8))
    }

    func testBinaryAndEncodingGarbageIsRejected() {
        let garbage: [Data] = [
            Data(), Data([0x20, 0x0A, 0x09]), Data([0x00, 0x00, 0x00, 0x00]), Data([0xFF, 0xFE, 0xFD]),
            Data(#"{"schema":1,"stars":["#.utf8) + Data([0xC3, 0x28]) + Data("]}".utf8),
            Data((0..<256).map { UInt8($0) }), Data(repeating: 0x7B, count: 10_000), Data(repeating: 0x5B, count: 10_000),
            Data("\u{FEFF}".utf8), Data(#"{'schema':1,'stars':[]}"#.utf8), Data("<xml/>".utf8),
        ]
        for data in garbage {
            assertError(.malformed(.stars, reason: ""), stars: data)
            assertError(.malformed(.milkyWay, reason: ""), milkyWay: data)
        }
    }

    func testNonFiniteAndMisspelledNumberLiteralsNeverLoadAsNumbers() {
        // Strict parsers reject the file; lenient ones read some of these as text or garbage, and the
        // record fails to decode. Either way no record with such a number is loaded.
        for literal in ["NaN", "Infinity", "-Infinity", "nan", "inf", "+1", "01", ".5", "1.", "0x10", "1e", "--1", "1e+", "-", "Inf"] {
            let record = #"{"hip":1,"c":"Ori","ra":\#(literal),"de":20.0,"m":2.5}"#
            do {
                let catalog = try Catalog(starsData: CatalogFixture.file("stars", [CatalogFixture.defaultStar, record]),
                                          dsosData: CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky]),
                                          constellationsData: CatalogFixture.file("constellations", []),
                                          milkyWayData: CatalogFixture.file("levels", []))
                // A lenient parser read the literal as a valid number: it must be a finite one.
                XCTAssertTrue(catalog.object(id: "star.hip1")?.j2000?.rightAscension.isFinite ?? true, literal)
            } catch CatalogError.malformed(let file, _) {
                XCTAssertEqual(file, .stars, literal)
            } catch {
                XCTFail("\(literal): \(error)")
            }
        }
        for literal in ["NaN", "Infinity", "-Infinity"] {
            let record = #"{"hip":1,"c":"Ori","ra":\#(literal),"de":20.0,"m":2.5}"#
            assertError(.malformed(.stars, reason: ""), stars: CatalogFixture.file("stars", [record]))
        }
    }

    func testDeeplyNestedInputIsRejectedWithoutCrashing() {
        let depth = 200_000
        let nestedArrays = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
        assertError(.malformed(.stars, reason: ""), stars: nestedArrays)
        let nestedInRecord = Data((#"{"schema":1,"stars":[{"hip":1,"x":"# + String(repeating: "[", count: depth)).utf8)
        assertError(.malformed(.stars, reason: ""), stars: nestedInRecord)
        let nestedObjects = Data((#"{"schema":1,"stars":"# + String(repeating: #"{"a":"#, count: depth)).utf8)
        assertError(.malformed(.stars, reason: ""), stars: nestedObjects)
        // Nesting inside an ignored member of a valid record is bounded too: shallow is fine, deep is refused.
        func record(withNesting depth: Int) -> Data {
            Data((#"{"schema":1,"stars":[{"hip":1,"c":"Ori","ra":1,"de":1,"m":1,"junk":"# + String(repeating: "[", count: depth)
                + String(repeating: "]", count: depth) + "}]}").utf8)
        }
        XCTAssertNoThrow(try Catalog(starsData: record(withNesting: 100), dsosData: CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky]),
                                     constellationsData: CatalogFixture.file("constellations", []),
                                     milkyWayData: CatalogFixture.file("levels", [])))
        assertError(.malformed(.stars, reason: ""), stars: record(withNesting: 1000))
    }

    func testOversizedFilesAreRejected() {
        let oversized = Data(count: Catalog.maximumFileBytes + 1)
        do {
            _ = try Catalog(starsData: oversized, dsosData: CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky]),
                            constellationsData: CatalogFixture.file("constellations", []), milkyWayData: CatalogFixture.file("levels", []))
            XCTFail("expected an error")
        } catch CatalogError.malformed(let file, let reason) {
            XCTAssertEqual(file, .stars)
            XCTAssertTrue(reason.contains("larger"), reason)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testFilesWithoutUsableObjectsAreRejected() {
        assertError(.noValidRecords(.stars, rejected: 0), stars: CatalogFixture.file("stars", []))
        assertError(.noValidRecords(.deepSkyObjects, rejected: 0), deepSky: CatalogFixture.file("objects", []))
        assertError(.noValidRecords(.stars, rejected: 3),
                    stars: CatalogFixture.file("stars", [star("ra", "\"x\""), star("de", "100"), "5"]))
        assertError(.noValidRecords(.deepSkyObjects, rejected: 2),
                    deepSky: CatalogFixture.file("objects", [deepSky("id", nil), deepSky("ra", "-3")]))
        assertError(.noValidRecords(.stars, rejected: 1), stars: CatalogFixture.file("stars", [#"{"hip":1}"#]))
    }

    func testConstellationsAndTheMilkyWayMayBeEmpty() throws {
        let catalog = try CatalogFixture.syntheticCatalog(constellations: [], milkyWayLevels: [])
        XCTAssertTrue(catalog.constellations.isEmpty)
        XCTAssertTrue(catalog.milkyWay.levels.isEmpty)
        XCTAssertNil(catalog.constellation(abbreviation: "Ori"))
        let star = try XCTUnwrap(catalog.object(id: "star.hip1"))
        XCTAssertEqual(star.constellation, "Ori", "the abbreviation is kept")
        XCTAssertNil(star.constellationName)
        XCTAssertEqual(star.subtitle, "Star \u{00B7} mag 2.5")
        XCTAssertTrue(catalog.loadReport.isClean)
        XCTAssertEqual(catalog.search("test star").first?.object.id, "star.hip1")
    }

    func testAMinimalCatalogWorks() throws {
        let catalog = try CatalogFixture.syntheticCatalog()
        XCTAssertEqual(catalog.objects.count, 9 + 3 + 1 + 1)
        XCTAssertEqual(catalog.renderStars.count, 1)
        XCTAssertEqual(catalog.constellations.map(\.abbreviation), ["Ori"])
        XCTAssertEqual(catalog.object(id: "star.hip1")?.constellationName, "Orion")
        XCTAssertEqual(catalog.object(id: "star.hip1")?.designations, ["HIP 1"])
        XCTAssertEqual(catalog.object(id: "dso.M1")?.constellation, "Tau")
        XCTAssertNil(catalog.object(id: "dso.M1")?.constellationName, "Taurus is not in the constellation file")
        XCTAssertEqual(catalog.milkyWay.levels.count, 1)
        XCTAssertEqual(catalog.search("hip 1").first?.object.id, "star.hip1")
        XCTAssertEqual(catalog.search("m1").first?.object.id, "dso.M1")
        XCTAssertEqual(catalog.objects(in: .stars).map(\.id), ["star.hip1"])
        XCTAssertTrue(catalog.loadReport.isClean)
    }

    // MARK: Star records

    func testStarRecordsWithTheWrongShapeAreSkipped() throws {
        for record in ["5", "\"star\"", "null", "[]", "[1,2]", "true", "{}", "{\"hip\":5}"] {
            try assertStarRejected(record)
        }
        for (key, value) in [("hip", "\"x\""), ("hip", "1.5"), ("hip", "[1]"), ("hip", "{}"), ("hip", "true"), ("hr", "\"y\""),
                             ("n", "5"), ("n", "[\"a\"]"), ("b", "1"), ("f", "\"x\""), ("c", "5"), ("ra", "\"12\""),
                             ("ra", "[1]"), ("de", "{}"), ("pa", "\"fast\""), ("pd", "false"), ("m", "\"bright\""),
                             ("ci", "[]"), ("sp", "7"), ("d", "\"far\"")] {
            try assertStarRejected(star(key, value), "")
        }
    }

    func testStarRecordsWithNonFiniteLookingNumbersAreSkipped() throws {
        for value in ["\"NaN\"", "\"nan\"", "\"Infinity\"", "\"-Infinity\"", "\"inf\"", "1e999", "-1e999", "1e400", "1E+999"] {
            for key in ["ra", "de", "m", "pa", "pd", "ci", "d"] {
                try assertStarRejected(star(key, value))
            }
        }
    }

    func testStarValuesOutOfRangeAreSkipped() throws {
        let rejected: [(String, String)] = [
            ("ra", "-0.5"), ("ra", "360.0001"), ("ra", "720"), ("ra", "1e10"), ("de", "90.0001"), ("de", "-90.5"), ("de", "1e6"),
            ("m", "40.5"), ("m", "-30.5"), ("m", "1e30"), ("pa", "100000.5"), ("pd", "-100001"), ("ci", "10.5"), ("ci", "-2.5"),
            ("d", "0"), ("d", "-1"), ("d", "1000001"), ("hip", "0"), ("hip", "-5"), ("hip", "100000000"), ("hr", "0"), ("hd", "-1"),
            ("f", "0"), ("f", "1000"), ("f", "-3"),
        ]
        for (key, value) in rejected {
            try assertStarRejected(star(key, value), "")
        }
        let accepted: [(String, String)] = [
            ("ra", "0"), ("ra", "360"), ("ra", "359.999999"), ("ra", "-0.0"), ("de", "90"), ("de", "-90"), ("de", "0"), ("m", "-30"), ("m", "40"),
            ("pa", "100000"), ("pd", "-100000"), ("pa", "0"), ("ci", "10"), ("ci", "-2"), ("d", "1000000"), ("d", "0.0001"), ("hip", "99999999"),
            ("f", "1"), ("f", "999"), ("sp", "\"\""), ("n", "\"\""), ("n", "null"), ("b", "null"), ("sp", "null"), ("d", "null"),
        ]
        for (key, value) in accepted {
            try assertStarAccepted(star(key, value))
        }
        let edge = try catalog(withStar: star("ra", "360"))
        XCTAssertEqual(edge.object(id: "star.hip2")?.j2000?.rightAscension, 0, "right ascension 360° wraps to 0°")
    }

    func testStarRecordsMissingRequiredValuesAreSkipped() throws {
        try assertStarRejected(star("ra", nil), "position")
        try assertStarRejected(star("de", nil), "position")
        try assertStarRejected(star("m", nil), "magnitude")
        try assertStarRejected(star("hip", nil), "hip, hr or hyg")
        try assertStarRejected(json(changing(changing(baseStar, "hip", to: nil), "hyg", to: "0")), "out of range")
        try assertStarAccepted(star("c", nil))
        try assertStarAccepted(json(changing(changing(baseStar, "hip", to: nil), "hr", to: "77")))
        try assertStarAccepted(json(changing(changing(baseStar, "hip", to: nil), "hyg", to: "123")))
    }

    func testStarTextIsValidated() throws {
        let long = String(repeating: "x", count: 81)
        try assertStarRejected(star("n", "\"\(long)\""), "too long")
        try assertStarRejected(star("n", "\"\(String(repeating: "é", count: 500))\""), "too long")
        try assertStarRejected(star("n", "\"line\\nbreak\""), "control")
        try assertStarRejected(star("n", "\"nul\\u0000byte\""), "control")
        try assertStarRejected(star("n", "\"bell\\u0007\""), "control")
        try assertStarRejected(star("sp", "\"\(String(repeating: "K", count: 25))\""), "too long")
        try assertStarRejected(star("b", "\"αβγδε\""), "too long")
        try assertStarRejected(star("b", "\"α β\""), "whitespace")
        try assertStarRejected(star("c", "\"Orion\""), "too long")
        try assertStarRejected(star("c", "\"O\""), "malformed")
        try assertStarRejected(star("c", "\"O1i\""), "malformed")
        try assertStarRejected(star("c", "\"Ωρι\""), "malformed")
        try assertStarAccepted(star("n", "\"  padded name  \""))
        try assertStarAccepted(star("n", "\"\(String(repeating: "x", count: 80))\""))
        try assertStarAccepted(star("n", "\"日本語 🔭 Åström\""))
        try assertStarAccepted(star("c", "\"or\""))
        try assertStarAccepted(star("c", "\"\""))
        let padded = try catalog(withStar: star("n", "\"  padded name  \""))
        XCTAssertEqual(padded.object(id: "star.hip2")?.name, "padded name")
    }

    func testDuplicateStarsKeepTheFirst() throws {
        let catalog = try CatalogFixture.syntheticCatalog(stars: [
            star("n", "\"First\""), star("n", "\"Second\""), star("hip", "3"),
            json(changing(changing(baseStar, "hip", to: nil), "hr", to: "5")), json(changing(changing(changing(baseStar, "hip", to: nil), "hr", to: "5"), "n", to: "\"Again\"")),
        ])
        XCTAssertEqual(catalog.loadReport.stars.accepted, 3)
        XCTAssertEqual(catalog.loadReport.stars.rejected, 2)
        XCTAssertEqual(catalog.object(id: "star.hip2")?.name, "First")
        XCTAssertNotNil(catalog.object(id: "star.hip3"))
        XCTAssertEqual(catalog.object(id: "star.hr5")?.name, "Other Star")
        XCTAssertTrue(catalog.loadReport.issues.allSatisfy { $0.contains("duplicate") }, "\(catalog.loadReport.issues)")
        // The same Hipparcos number with a different Harvard number is still the same star.
        let twice = try CatalogFixture.syntheticCatalog(stars: [star("hr", "10"), star("hr", "11")])
        XCTAssertEqual(twice.loadReport.stars.rejected, 1)
    }

    func testGoodRecordsSurviveBadNeighbours() throws {
        let bad = ["5", star("ra", "\"x\""), star("de", "99"), star("m", "\"NaN\"")]
        var records: [String] = []
        var expected: [String] = []
        for index in 1...30 {
            if index % 3 == 0 {
                records.append(bad[(index / 3) % bad.count])
            } else {
                records.append(json(changing(baseStar, "hip", to: "\(index)")))
                expected.append("star.hip\(index)")
            }
        }
        let catalog = try CatalogFixture.syntheticCatalog(stars: records)
        XCTAssertEqual(catalog.loadReport.stars.accepted, 20)
        XCTAssertEqual(catalog.loadReport.stars.rejected, 10)
        XCTAssertEqual(catalog.objects.filter { $0.id.hasPrefix("star.") }.map(\.id).sorted(), expected.sorted())
        XCTAssertEqual(catalog.renderStars.count, 20)
        XCTAssertEqual(catalog.loadReport.issues.count, 10)
        XCTAssertEqual(catalog.loadReport.rejectedCount, 10)
    }

    func testUnknownMembersAreIgnored() throws {
        let record = json(baseStar + [("extra", "{\"nested\":[1,2,{\"x\":null}]}"), ("future", "\"field\""), ("n2", "null")])
        try assertStarAccepted(record)
        let file = Data(#"{"schema":1,"source":"test","license":"x","generated":"today","stars":[\#(CatalogFixture.defaultStar)],"extra":[1,2,3]}"#.utf8)
        XCTAssertNoThrow(try Catalog(starsData: file, dsosData: CatalogFixture.file("objects", [CatalogFixture.defaultDeepSky]),
                                     constellationsData: CatalogFixture.file("constellations", []), milkyWayData: CatalogFixture.file("levels", [])))
    }

    func testTheIssueListIsBounded() throws {
        let bad = (0..<200).map { star("ra", "\($0 + 400)") }
        let catalog = try CatalogFixture.syntheticCatalog(stars: [CatalogFixture.defaultStar] + bad)
        XCTAssertEqual(catalog.loadReport.stars.rejected, 200)
        XCTAssertEqual(catalog.loadReport.issues.count, CatalogLoadReport.maximumIssueCount)
        XCTAssertEqual(catalog.loadReport.issues.first, "stars[1]: position missing or out of range")
    }

    func testAHugeNumberOfRecordsLoads() throws {
        let records = (1...5000).map { CatalogFixture.star(hip: $0, magnitude: Double($0 % 140) / 10) }
        let catalog = try CatalogFixture.syntheticCatalog(stars: records)
        XCTAssertEqual(catalog.loadReport.stars.accepted, 5000)
        XCTAssertEqual(catalog.search("hip 4999").first?.object.id, "star.hip4999")
    }

    // MARK: Deep-sky records

    func testDeepSkyRecordsWithTheWrongShapeAreSkipped() throws {
        for record in ["5", "null", "[]", "\"M1\"", "{}", #"{"id":"X"}"#] {
            try assertDeepSkyRejected(record)
        }
        for (key, value) in [("id", "5"), ("t", "[]"), ("ra", "\"1\""), ("de", "null"), ("c", "7"), ("vm", "\"9\""), ("bm", "[]"),
                             ("maj", "\"big\""), ("min", "{}"), ("pa", "\"x\""), ("names", "\"Name\""), ("names", "[1,2]"),
                             ("names", "{}"), ("ngc", "5"), ("ngc", "[\"a\"]"), ("ngc", "[1.5]"), ("ic", "\"x\""), ("m", "\"1\""),
                             ("h", "5"), ("sb", "\"22\"")] {
            try assertDeepSkyRejected(deepSky(key, value))
        }
    }

    func testDeepSkyValuesAreValidated() throws {
        let rejected: [(String, String?, String)] = [
            ("id", nil, "id"), ("id", "\"\"", "id"), ("id", "\"   \"", "id"), ("id", "\"M 1\"", "id"), ("id", "\"M1/2\"", "id"),
            ("id", "\"M1\\\"x\"", "id"), ("id", "\"é\"", "id"), ("id", "\"\(String(repeating: "A", count: 41))\"", "too long"),
            ("t", nil, "type"), ("t", "\"\"", "type"), ("t", "\"WayTooLongType\"", "too long"),
            ("ra", nil, "position"), ("ra", "-1", "position"), ("ra", "361", "position"), ("de", "91", "position"), ("de", nil, "position"),
            ("vm", "41", "vm"), ("vm", "-31", "vm"), ("bm", "1e9", "bm"), ("maj", "0", "maj"), ("maj", "-5", "maj"),
            ("maj", "21601", "maj"), ("min", "0", "min"), ("min", "-1", "min"), ("min", "9", "minor axis longer"), ("pa", "361", "pa"),
            ("pa", "-1", "pa"), ("m", "0", "Messier"), ("m", "1000", "Messier"), ("m", "-3", "Messier"), ("ngc", "[0]", "ngc"),
            ("ngc", "[100000]", "ngc"), ("ngc", "[-5]", "ngc"), ("ic", "[1, 0]", "ic"), ("sb", "0", "sb"), ("sb", "41", "sb"),
            ("sb", "-3", "sb"), ("h", "\"\(String(repeating: "S", count: 17))\"", "too long"), ("c", "\"Andromeda\"", "too long"),
            ("names", "[\"\(String(repeating: "n", count: 81))\"]", "too long"), ("names", "[\"bad\\u0007name\"]", "control"),
        ]
        for (key, value, note) in rejected {
            try assertDeepSkyRejected(deepSky(key, value), note)
        }
        try assertDeepSkyRejected(json(changing(changing(baseDeepSky, "maj", to: nil), "min", to: "4")), "without major")
    }

    func testValidDeepSkyEdgeCasesAreAccepted() throws {
        let accepted: [(String, String?)] = [
            ("vm", "-30"), ("vm", "40"), ("vm", nil), ("bm", "12.5"), ("maj", "21600"), ("min", nil),
            ("min", "8"), ("pa", "0"), ("pa", "360"), ("pa", nil), ("m", "1"), ("m", "999"), ("ngc", "[1]"), ("ngc", "[]"), ("ngc", nil),
            ("ngc", "[99999, 99999]"), ("ic", "[5386]"), ("names", "[]"), ("names", nil), ("names", "[\"\", \" \"]"), ("h", nil), ("h", "\"\""),
            ("sb", "40"), ("sb", "0.1"), ("c", nil), ("c", "\"\""), ("c", "\"And\""), ("t", "\"Unknown\""), ("t", "\"Other\""), ("ra", "360"),
            ("de", "-90"), ("id", "\"IC359A\""), ("id", "\"A_b-c.d+e\""), ("id", "\"ESO56-115\""),
        ]
        for (key, value) in accepted {
            let record = deepSky(key, value)
            let catalog = try catalog(withDeepSky: record)
            XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 2, "\(record) \(catalog.loadReport.issues)")
            XCTAssertEqual(catalog.loadReport.deepSkyObjects.rejected, 0, record)
        }
        let tiny = try catalog(withDeepSky: json(changing(changing(baseDeepSky, "maj", to: "0.001"), "min", to: "0.0005")))
        XCTAssertEqual(tiny.object(id: "dso.NGC1")?.angularSize?.majorArcminutes, 0.001)
        XCTAssertEqual(tiny.object(id: "dso.NGC1")?.angularSize?.minorArcminutes, 0.0005)
        XCTAssertEqual(tiny.loadReport.deepSkyObjects.accepted, 2)
        let unknownType = try catalog(withDeepSky: deepSky("t", "\"Unknown\""))
        XCTAssertEqual(unknownType.object(id: "dso.NGC1")?.category, .other, "unknown type codes are 'other'")
        let blankNames = try catalog(withDeepSky: deepSky("names", "[\"\", \" \", \"Real\", \"Real\", \" Real \"]"))
        XCTAssertEqual(blankNames.object(id: "dso.NGC1")?.name, "Real")
        XCTAssertEqual(blankNames.object(id: "dso.NGC1")?.alternateNames, [])
        let dup = try catalog(withDeepSky: deepSky("ngc", "[7, 7, 8, 7]"))
        XCTAssertEqual(dup.object(id: "dso.NGC1")?.designations, ["NGC 7", "NGC 8", "NGC 1"])
    }

    func testDuplicateDeepSkyIdentifiersKeepTheFirst() throws {
        let catalog = try CatalogFixture.syntheticCatalog(deepSky: [deepSky("names", "[\"First\"]"), deepSky("names", "[\"Second\"]"),
                                                                    deepSky("id", "\"NGC2\"")])
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 2)
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.rejected, 1)
        XCTAssertEqual(catalog.object(id: "dso.NGC1")?.name, "First")
        XCTAssertTrue(catalog.loadReport.issues[0].contains("duplicate"), "\(catalog.loadReport.issues)")
    }

    func testPlainStarRecordsAreOnlyMergedIntoStarsAtTheSamePlace() throws {
        let starAtOrigin = CatalogFixture.star(hip: 50, name: "Neighbor")
        let plainStar = { (id: String, ra: String, name: String) in
            #"{"id":"\#(id)","names":["\#(name)"],"t":"*","ra":\#(ra),"de":20.0,"c":"Ori","vm":3}"#
        }
        let catalog = try CatalogFixture.syntheticCatalog(stars: [starAtOrigin], deepSky: [
            plainStar("NGC10", "10.0", "Alias"),         // on the star: merged
            plainStar("NGC11", "10.0166", "Alias"),      // 0.9 arcmin away (RA offset times cos δ): merged
            plainStar("NGC12", "10.05", "Survivor"),     // about 2.8 arcmin away: stays
            #"{"id":"M40","m":40,"t":"**","ra":10.0,"de":20.0,"c":"Ori"}"#, // Messier: stays
            #"{"id":"NGC13","t":"G","ra":10.0,"de":20.0,"c":"Ori"}"#,        // not a star: stays
        ])
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.merged, 2)
        XCTAssertEqual(catalog.loadReport.deepSkyObjects.accepted, 3)
        XCTAssertNil(catalog.object(id: "dso.NGC10"))
        XCTAssertNil(catalog.object(id: "dso.NGC11"))
        XCTAssertNotNil(catalog.object(id: "dso.NGC12"))
        XCTAssertNotNil(catalog.object(id: "dso.M40"))
        XCTAssertNotNil(catalog.object(id: "dso.NGC13"))
        let neighbor = try XCTUnwrap(catalog.object(id: "star.hip50"))
        XCTAssertEqual(neighbor.designations, ["HIP 50", "NGC 10", "NGC 11"])
        XCTAssertEqual(neighbor.alternateNames, ["Alias"])
        XCTAssertEqual(catalog.search("ngc 11").first?.object.id, "star.hip50")
        XCTAssertEqual(catalog.search("alias").first?.object.id, "star.hip50")
        XCTAssertEqual(catalog.search("alias").first?.matchedText, "Alias")
        XCTAssertTrue(catalog.loadReport.isClean, "merging is not a rejection")
    }

    // MARK: Constellations and the Milky Way

    func testConstellationRecordsAreValidated() throws {
        let valid: [(String, String)] = [("abbr", "\"Ori\""), ("name", "\"Orion\""), ("genitive", "\"Orionis\""),
                                         ("label", "[83.0,5.0]"), ("lines", "[[[80.0,0.0],[85.0,10.0]]]")]
        func variant(_ key: String, _ value: String?) -> String { json(changing(valid, key, to: value)) }
        let taurus = #"{"abbr":"Tau","name":"Taurus","genitive":"Tauri","label":[65.0,15.0],"lines":[[[60.0,10.0],[70.0,20.0]]]}"#
        let bad = [variant("abbr", nil), variant("abbr", "\"Orion\""), variant("abbr", "5"), variant("name", nil), variant("name", "\"\""),
                   variant("genitive", nil), variant("label", nil), variant("label", "[1]"), variant("label", "[1,2,3]"), variant("label", "[400,0]"),
                   variant("label", "[10,95]"), variant("label", "\"x\""), "5", "null", "[]", "{}"]
        for record in bad {
            let catalog = try CatalogFixture.syntheticCatalog(constellations: [taurus, record])
            XCTAssertEqual(catalog.loadReport.constellations.accepted, 1, record)
            XCTAssertEqual(catalog.loadReport.constellations.rejected, 1, record)
            XCTAssertEqual(catalog.constellations.count, 1, record)
        }
        let good = try CatalogFixture.syntheticCatalog(constellations: [variant("lines", nil), variant("abbr", "\"Cma\"")])
        XCTAssertEqual(good.loadReport.constellations.accepted, 2)
        XCTAssertEqual(good.constellation(abbreviation: "ori")?.lines.count, 0, "a constellation without a figure is fine")
        XCTAssertEqual(good.constellation(abbreviation: "CMA")?.abbreviation, "Cma")
    }

    func testDuplicateConstellationsKeepTheFirst() throws {
        let first = CatalogFixture.defaultConstellation
        let second = first.replacingOccurrences(of: "Orion\"", with: "Second\"")
        let catalog = try CatalogFixture.syntheticCatalog(constellations: [first, second, first.replacingOccurrences(of: "\"Ori\"", with: "\"ORI\"")])
        XCTAssertEqual(catalog.constellations.count, 1)
        XCTAssertEqual(catalog.constellations.first?.name, "Orion")
        XCTAssertEqual(catalog.loadReport.constellations.rejected, 2)
        XCTAssertTrue(catalog.loadReport.issues.allSatisfy { $0.contains("duplicate") })
    }

    func testBadPolylinesAreDroppedAndTheConstellationKept() throws {
        let lines = "[[[80,0],[85,10]],[[1,2]],[],[[1,2],[\"x\",3]],[[1,2],[3]],[[1,2],[3,4,5]],[[1,2],[400,3]],[[1,2],[3,95]],[[10,10],[20,20],[30,30]],5,\"x\"]"
        let record = #"{"abbr":"Ori","name":"Orion","genitive":"Orionis","label":[83,5],"lines":\#(lines)}"#
        let catalog = try CatalogFixture.syntheticCatalog(constellations: [record])
        XCTAssertEqual(catalog.constellations.count, 1)
        XCTAssertEqual(catalog.constellations[0].lines.map(\.count), [2, 3])
        XCTAssertEqual(catalog.loadReport.constellationLines.accepted, 2)
        XCTAssertEqual(catalog.loadReport.constellationLines.rejected, 9)
        XCTAssertEqual(catalog.loadReport.constellations.rejected, 0)
        XCTAssertFalse(catalog.loadReport.isClean)
        XCTAssertTrue(catalog.loadReport.issues.contains { $0.contains("9 invalid polylines") }, "\(catalog.loadReport.issues)")
        let notArray = #"{"abbr":"Ori","name":"Orion","genitive":"Orionis","label":[83,5],"lines":"none"}"#
        let wrongType = try CatalogFixture.syntheticCatalog(constellations: [notArray])
        XCTAssertEqual(wrongType.loadReport.constellations.rejected, 1, "a lines member of the wrong type spoils the record")
    }

    func testMilkyWayLevelsAreValidatedAndSorted() throws {
        let ring = "[[10,10],[20,10],[20,20]]"
        let levels = [
            #"{"level":3,"polygons":[\#(ring)],"holes":[]}"#,
            #"{"level":1,"polygons":[\#(ring),[[1,1],[2,2]],[[1,1],[2,"x"],[3,3]],[[1,1],[2,95],[3,3]],5],"holes":[\#(ring),[]]}"#,
            #"{"level":2,"polygons":[\#(ring)]}"#,
            #"{"level":0,"polygons":[\#(ring)]}"#, #"{"level":101,"polygons":[\#(ring)]}"#, #"{"polygons":[\#(ring)]}"#,
            #"{"level":4,"polygons":[[[1,1],[2,2]]]}"#, #"{"level":5}"#, #"{"level":6,"polygons":"x"}"#, "7", "null",
        ]
        let catalog = try CatalogFixture.syntheticCatalog(milkyWayLevels: levels)
        XCTAssertEqual(catalog.milkyWay.levels.map(\.level), [1, 2, 3])
        XCTAssertEqual(catalog.milkyWay.levels[0].polygons.count, 1)
        XCTAssertEqual(catalog.milkyWay.levels[0].holes.count, 1)
        XCTAssertEqual(catalog.milkyWay.levels[1].holes.count, 0)
        XCTAssertEqual(catalog.loadReport.milkyWayRings.accepted, 4)
        XCTAssertEqual(catalog.loadReport.milkyWayRings.rejected, 4 + 1 + 8, "bad rings, plus levels that are unusable as a whole")
        XCTAssertFalse(catalog.loadReport.issues.isEmpty)
    }

    // MARK: Robustness

    func testManyConcurrentLoadsAreIndependent() throws {
        let box = ConcurrentCounts()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            let count = (try? CatalogFixture.syntheticCatalog().objects.count) ?? -1
            box.add(count)
        }
        XCTAssertEqual(box.counts(), Array(repeating: 14, count: 8))
    }

    func testRandomDamageToTheRealFilesNeverCrashes() throws {
        var state: UInt64 = 42
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33)
        }
        func damaged(_ data: Data, round: Int) -> Data {
            var bytes = [UInt8](data)
            let position = next() % bytes.count
            switch round % 3 {
            case 0:
                bytes[position] = UInt8(truncatingIfNeeded: next())
            case 1:
                bytes.removeSubrange(position..<min(bytes.count, position + 1 + next() % 40))
            default:
                bytes.insert(contentsOf: Array("\"\\u00".utf8), at: position)
            }
            return Data(bytes)
        }
        let dsos = try Catalog.bundledData(for: .deepSkyObjects)
        let constellations = try Catalog.bundledData(for: .constellations)
        let milkyWay = try Catalog.bundledData(for: .milkyWay)
        var loaded = 0, failed = 0
        for round in 0..<60 {
            do {
                let catalog = try Catalog(starsData: CatalogFixture.file("stars", [CatalogFixture.defaultStar]),
                                          dsosData: damaged(dsos, round: round), constellationsData: damaged(constellations, round: round),
                                          milkyWayData: damaged(milkyWay, round: round))
                XCTAssertGreaterThan(catalog.objects.count, 12)
                XCTAssertLessThanOrEqual(catalog.loadReport.issues.count, CatalogLoadReport.maximumIssueCount)
                loaded += 1
            } catch is CatalogError {
                failed += 1
            }
        }
        XCTAssertEqual(loaded + failed, 60)
        XCTAssertGreaterThan(loaded, 0, "most single-byte changes only spoil a record or a value")
    }
}

private final class ConcurrentCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func add(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func counts() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

import XCTest
@testable import LodestarKit

// MARK: - Text normalization

final class CatalogSearchTextTests: XCTestCase {
    private func key(_ text: String) -> String {
        String(decoding: SearchText.key(for: text).bytes, as: UTF8.self)
    }

    private func wordStarts(_ text: String) -> [Int] {
        let mask = SearchText.key(for: text).wordStarts
        return (0..<64).filter { mask & (1 << UInt64($0)) != 0 }
    }

    func testCaseAndPunctuationAreIgnored() {
        XCTAssertEqual(key("M 31"), "m31")
        XCTAssertEqual(key("m31"), "m31")
        XCTAssertEqual(key("M-31"), "m31")
        XCTAssertEqual(key("m.31"), "m31")
        XCTAssertEqual(key("  M\t31\n"), "m31")
        XCTAssertEqual(key("Messier 31"), "messier31")
        XCTAssertEqual(key("Sgr A*"), "sgra")
        XCTAssertEqual(key("h & chi Persei"), "hchipersei")
        XCTAssertEqual(key("Wolf-Lundmark-Melotte"), "wolflundmarkmelotte")
        XCTAssertEqual(key("(Orion) [Nebula]!"), "orionnebula")
    }

    func testApostrophesJoinTheirWord() {
        XCTAssertEqual(key("Barnard's Star"), "barnardsstar")
        XCTAssertEqual(key("Barnard\u{2019}s Star"), "barnardsstar")
        XCTAssertEqual(key("Barnard\u{2018}s Star"), "barnardsstar")
        XCTAssertEqual(key("Barnard`s Star"), "barnardsstar")
        XCTAssertEqual(wordStarts("Barnard's Star"), [0, 8])
        XCTAssertEqual(key("Amas de l'Ecu de Sobieski"), "amasdelecudesobieski")
    }

    func testDiacriticsAndLigaturesAreIgnored() {
        let expectations: [(String, String)] = [
            ("Boötes", "bootes"), ("Bélénos", "belenos"), ("Añañuca", "ananuca"), ("Mönch", "monch"),
            ("Tupã", "tupa"), ("Ångström", "angstrom"), ("Łódź", "lodz"), ("Æsir", "aesir"), ("straße", "strasse"),
            ("Øresund", "oresund"), ("Œuvre", "oeuvre"), ("ﬁsh", "fish"), ("Đồng", "dong"), ("Þór", "thor"),
            ("Rosalíadecastro", "rosaliadecastro"), ("Citalá", "citala"), ("ế", "e"), ("ǎ", "a"), ("ı", "i"),
            ("e\u{0301}", "e"), ("o\u{0308}", "o"), ("A\u{030A}", "a"), ("n\u{0303}", "n"),
        ]
        for (text, expected) in expectations {
            XCTAssertEqual(key(text), expected, text)
        }
    }

    func testFullWidthTextIsReadAsNormalText() {
        XCTAssertEqual(key("Ｍ３１"), "m31")
        XCTAssertEqual(key("ＮＧＣ\u{3000}７０００"), "ngc7000")
        XCTAssertEqual(key("ｓｉｒｉｕｓ"), "sirius")
        XCTAssertEqual(key("Ｓｉｒｉｕｓ！"), "sirius")
    }

    func testGreekLettersAreReadAsTheirNames() {
        let lower = Array("αβγδεζηθικλμνξοπρστυφχψω")
        let upper = Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ")
        XCTAssertEqual(lower.count, 24)
        XCTAssertEqual(upper.count, 24)
        XCTAssertEqual(GreekAlphabet.letters.count, 24)
        for (index, letter) in GreekAlphabet.letters.enumerated() {
            XCTAssertEqual(key(String(lower[index])), letter.name, "lower case \(lower[index])")
            XCTAssertEqual(key(String(upper[index])), letter.name, "upper case \(upper[index])")
            XCTAssertEqual(GreekAlphabet.index(of: lower[index].unicodeScalars[lower[index].unicodeScalars.startIndex]), index)
            XCTAssertEqual(letter.capitalizedName.lowercased(), letter.name)
        }
        XCTAssertEqual(key("ς"), "sigma", "final sigma")
        XCTAssertEqual(key("ϑ"), "theta")
        XCTAssertEqual(key("ϕ"), "phi")
        XCTAssertEqual(key("ϖ"), "pi")
        XCTAssertEqual(key("ϵ"), "epsilon")
        XCTAssertEqual(key("ϰ"), "kappa")
        XCTAssertEqual(key("ϱ"), "rho")
        XCTAssertEqual(key("ά"), "alpha", "accented Greek reads like the plain letter")
        XCTAssertEqual(key("α CMa"), "alphacma")
        XCTAssertEqual(key("αCMa"), "alphacma")
        XCTAssertEqual(wordStarts("αCMa"), [0])
        XCTAssertEqual(key("aα"), "aalpha")
        XCTAssertEqual(wordStarts("aα"), [0, 1], "a Greek letter opens a word")
        XCTAssertNil(GreekAlphabet.index(of: "a"))
        XCTAssertNil(GreekAlphabet.index(of: "\u{03A2}"), "the unassigned code point is not a letter")
        XCTAssertEqual(key("\u{03A2}x"), "x")
        XCTAssertEqual(GreekAlphabet.letters.map(\.name).count, Set(GreekAlphabet.letters.map(\.name)).count)
    }

    func testSuperscriptAndSubscriptDigitsAreDigits() {
        XCTAssertEqual(key("α¹ Cen"), "alpha1cen")
        XCTAssertEqual(key("α² Cen"), "alpha2cen")
        XCTAssertEqual(key("π³ Ori"), "pi3ori")
        XCTAssertEqual(key("x⁰¹²³⁴⁵⁶⁷⁸⁹"), "x123456789", "the leading zero is dropped like any other")
        XCTAssertEqual(key("H₂O"), "h2o")
        XCTAssertEqual(key("a₀₁₂₃₄₅₆₇₈₉"), "a123456789")
        XCTAssertEqual(key("a₁₀"), "a10")
        XCTAssertEqual(key("10⁴"), "104")
        XCTAssertEqual(key("alpha1 cen"), key("α¹ Cen"))
        XCTAssertEqual(key("alpha 1 cen"), key("α¹ Cen"))
        XCTAssertEqual(wordStarts("α¹ Cen"), [0, 6])
    }

    func testLeadingZerosOfNumbersAreDropped() {
        XCTAssertEqual(key("NGC 0224"), "ngc224")
        XCTAssertEqual(key("NGC0224"), "ngc224")
        XCTAssertEqual(key("M031"), "m31")
        XCTAssertEqual(key("HR 02491"), "hr2491")
        XCTAssertEqual(key("IC 0434"), "ic434")
        XCTAssertEqual(key("0"), "0")
        XCTAssertEqual(key("00"), "0")
        XCTAssertEqual(key("000a"), "0a")
        XCTAssertEqual(key("007"), "7")
        XCTAssertEqual(key("a007"), "a7")
        XCTAssertEqual(key("a0"), "a0")
        XCTAssertEqual(key("a00b"), "a0b")
        XCTAssertEqual(key("HD 0"), "hd0")
        XCTAssertEqual(key("100"), "100")
        XCTAssertEqual(key("1000"), "1000")
        XCTAssertEqual(key("IC 2431_NED02"), "ic2431ned2")
        XCTAssertEqual(key("IC2431_NED02"), key("ic 2431 ned 02"))
        XCTAssertEqual(wordStarts("M 031"), [0, 1])
    }

    func testWordStartsMarkTheFirstByteOfEachWord() {
        XCTAssertEqual(wordStarts("Orion Nebula"), [0, 5])
        XCTAssertEqual(wordStarts("M 31"), [0, 1])
        XCTAssertEqual(wordStarts("NGC7000"), [0])
        XCTAssertEqual(wordStarts("a-b-c"), [0, 1, 2])
        XCTAssertEqual(wordStarts("  leading space"), [0, 7])
        XCTAssertEqual(wordStarts("Alpha Canis Majoris"), [0, 5, 10])
        XCTAssertEqual(wordStarts(""), [])
    }

    func testTextWithoutLettersOrDigitsHasNoKey() {
        for text in ["", " ", "\n\t", "!!!", "—", "...", "🔭", "😀😀😀", "星空", "Орион", "\u{0000}", "\u{200B}\u{FEFF}",
                     "\u{0301}\u{0301}", "★☆", "∞", "\u{202E}"] {
            XCTAssertEqual(key(text), "", text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
        }
        XCTAssertEqual(key("🔭M31🔭"), "m31")
        XCTAssertEqual(key("Орион M42"), "m42")
    }

    func testKeysAreBounded() {
        XCTAssertEqual(SearchText.key(for: String(repeating: "a", count: 1000)).bytes.count, SearchText.maximumKeyLength)
        XCTAssertEqual(SearchText.key(for: String(repeating: "ω", count: 1000)).bytes.count, SearchText.maximumKeyLength)
        XCTAssertEqual(SearchText.key(for: "abcdefgh", maximumScalars: 5).bytes, Array("abcde".utf8))
        XCTAssertEqual(SearchText.key(for: "abc", maximumScalars: 0).bytes, [])
        XCTAssertEqual(SearchText.key(for: String(repeating: "1 ", count: 100)).wordStarts, UInt64.max,
                       "every one of the 64 stored digits opens a word")
        let long = SearchText.key(for: String(repeating: "ab ", count: 100))
        XCTAssertEqual(long.bytes.count, 64)
        XCTAssertEqual(long.wordStarts & 1, 1)
        XCTAssertEqual(SearchText.maximumQueryScalars, 64)
        XCTAssertEqual(Catalog.maximumQueryLength, 64)
    }

    func testNaturalOrderComparesNumbersByValue() {
        let unsorted = ["m10", "m2", "m1", "m100", "m21", "m3a", "m3", "abc", "ab1", "ab", "", "m"]
        let sorted = unsorted.sorted { SearchText.naturalPrecedes(Array($0.utf8), Array($1.utf8)) }
        XCTAssertEqual(sorted, ["", "ab", "ab1", "abc", "m", "m1", "m2", "m3", "m3a", "m10", "m21", "m100"])
        XCTAssertFalse(SearchText.naturalPrecedes(Array("m1".utf8), Array("m1".utf8)))
        XCTAssertTrue(SearchText.naturalPrecedes(Array("ngc9".utf8), Array("ngc10".utf8)))
        XCTAssertFalse(SearchText.naturalPrecedes(Array("ngc10".utf8), Array("ngc9".utf8)))
        XCTAssertTrue(SearchText.naturalPrecedes(Array("hd2491".utf8), Array("hd10000".utf8)))
        XCTAssertTrue(SearchText.naturalPrecedes(Array("a9b".utf8), Array("a10a".utf8)))
        XCTAssertFalse(SearchText.naturalPrecedes(Array("a10a".utf8), Array("a9b".utf8)))
    }
}

// MARK: - Searching the catalog

final class CatalogSearchTests: XCTestCase {
    private func catalog() throws -> Catalog { try CatalogFixture.catalog() }

    private func ids(_ results: [CatalogSearchResult]) -> [String] { results.map(\.object.id) }

    /// The ranking rules: kinds never get worse down the list, and results of one kind are ordered by
    /// listed objects first, then more prominent ones, then brighter ones, then name.
    private func assertRankingOrder(_ results: [CatalogSearchResult], _ query: String, file: StaticString = #filePath, line: UInt = #line) {
        for (first, second) in zip(results, results.dropFirst()) {
            XCTAssertLessThanOrEqual(first.kind, second.kind, "\(query): \(first.object.id) before \(second.object.id)", file: file, line: line)
            guard first.kind == second.kind else { continue }
            if first.object.isListed != second.object.isListed {
                XCTAssertTrue(first.object.isListed, "\(query): unlisted \(first.object.id) before listed \(second.object.id)", file: file, line: line)
                continue
            }
            if first.object.prominence != second.object.prominence {
                XCTAssertLessThan(first.object.prominence, second.object.prominence,
                                  "\(query): \(first.object.id) (\(first.object.prominence.rawValue)) before \(second.object.id) (\(second.object.prominence.rawValue))",
                                  file: file, line: line)
                continue
            }
            if first.object.rankingMagnitude != second.object.rankingMagnitude {
                XCTAssertLessThan(first.object.rankingMagnitude, second.object.rankingMagnitude,
                                  "\(query): \(first.object.id) before \(second.object.id)", file: file, line: line)
                continue
            }
            let a = Array(SearchText.key(for: first.object.name).bytes), b = Array(SearchText.key(for: second.object.name).bytes)
            XCTAssertFalse(SearchText.naturalPrecedes(b, a), "\(query): \(first.object.name) before \(second.object.name)", file: file, line: line)
        }
    }

    // MARK: Famous targets

    func testFamousTargetsCanBeFoundByName() throws {
        let catalog = try catalog()
        let expectations: [(query: String, id: String)] = [
            ("Sirius", "star.hip32349"), ("Polaris", "star.hip11767"), ("Betelgeuse", "star.hip27989"),
            ("Vega", "star.hip91262"), ("Rigel", "star.hip24436"), ("Arcturus", "star.hip69673"),
            ("Antares", "star.hip80763"), ("Proxima Centauri", "star.hip70890"), ("Barnard's Star", "star.hip87937"),
            ("M31", "dso.M31"), ("M42", "dso.M42"), ("M45", "dso.M45"), ("NGC 7000", "dso.NGC7000"),
            ("LMC", "dso.ESO56-115"), ("SMC", "dso.NGC292"), ("Omega Centauri", "dso.NGC5139"),
            ("Double Cluster", "dso.C14"), ("galactic center", "special.galacticCenter"),
            ("Galactic Centre", "special.galacticCenter"),
            ("Milky Way core", "special.galacticCenter"), ("Sgr A*", "special.galacticCenter"),
            ("Jupiter", "planet.jupiter"), ("Moon", "moon"), ("Sun", "sun"), ("Mars", "planet.mars"),
            ("Venus", "planet.venus"), ("Saturn", "planet.saturn"), ("Mercury", "planet.mercury"),
            ("Uranus", "planet.uranus"), ("Neptune", "planet.neptune"), ("NCP", "special.ncp"),
            ("South Celestial Pole", "special.scp"), ("Pleiades", "dso.M45"), ("Orion Nebula", "dso.M42"),
            ("Andromeda Galaxy", "dso.M31"), ("Crab Nebula", "dso.M1"), ("Ring Nebula", "dso.M57"),
            ("Horsehead Nebula", "dso.B33"), ("North America Nebula", "dso.NGC7000"), ("Veil Nebula", "dso.NGC6960"),
            ("Rosette Nebula", "dso.NGC2238"), ("Large Magellanic Cloud", "dso.ESO56-115"),
            ("Whirlpool Galaxy", "dso.M51"), ("Sombrero Galaxy", "dso.M104"), ("Lagoon Nebula", "dso.M8"),
            ("Trifid Nebula", "dso.M20"), ("Helix Nebula", "dso.NGC7293"), ("Hyades", "dso.C41"),
            ("North Star", "star.hip11767"), ("Pole Star", "star.hip11767"), ("Lodestar", "star.hip11767"),
            ("Dog Star", "star.hip32349"), ("Luna", "moon"), ("Sol", "sun"),
        ]
        for (query, id) in expectations {
            let results = catalog.search(query)
            XCTAssertEqual(results.first?.object.id, id, query)
            XCTAssertEqual(results.first?.kind, .exact, query)
        }
        let milkyWay = catalog.search("Milky Way")
        XCTAssertEqual(milkyWay.first?.object.id, "special.galacticCenter")
        XCTAssertEqual(milkyWay.first?.kind, .prefix, "the name is \"Milky Way Core\"")
    }

    func testCommonNamesCanBeAbbreviated() throws {
        let catalog = try catalog()
        let expectations: [(String, String, CatalogSearchResult.MatchKind)] = [
            ("andromeda", "dso.M31", .prefix), ("orion neb", "dso.M42", .prefix), ("omega cen", "dso.NGC5139", .prefix),
            ("magellanic", "dso.ESO56-115", .wordPrefix), ("double", "dso.C14", .prefix), ("pleiad", "dso.M45", .prefix),
            ("whirlpool", "dso.M51", .prefix), ("north america", "dso.NGC7000", .prefix), ("great orion", "dso.M42", .prefix),
            ("swan", "dso.M17", .prefix), ("nubecula", "dso.ESO56-115", .prefix), ("seven sisters", "dso.M45", .exact),
        ]
        for (query, id, kind) in expectations {
            let results = catalog.search(query)
            XCTAssertTrue(ids(results).contains(id), query)
            XCTAssertEqual(results.first(where: { $0.object.id == id })?.kind, kind, query)
        }
        XCTAssertEqual(catalog.search("andromeda").first?.object.id, "dso.M31", "the exact name outranks the Andromedae stars")
    }

    // MARK: Catalog designations

    func testMessierDesignationsInAllSpellings() throws {
        let catalog = try catalog()
        for spelling in ["m31", "M31", "M 31", "m 31", "Messier 31", "messier31", "MESSIER 31", "M031", "M 031", "m0031",
                         "Ｍ３１", "M-31", "M.31", "m  31", " m31 ", "M\u{00A0}31", "messier 031"] {
            let results = catalog.search(spelling)
            XCTAssertEqual(results.first?.object.id, "dso.M31", spelling)
            XCTAssertEqual(results.first?.kind, .exact, spelling)
            XCTAssertEqual(results.first?.matchedText, "M 31", spelling)
        }
        for number in 1...110 {
            XCTAssertEqual(catalog.search("M\(number)").first?.object.id, "dso.M\(number)", "M\(number)")
            XCTAssertEqual(catalog.search("messier \(number)").first?.object.id, "dso.M\(number)")
        }
        let m1 = catalog.search("m1", limit: 200)
        XCTAssertEqual(m1.first?.object.id, "dso.M1")
        XCTAssertTrue(ids(m1).contains("dso.M10") && ids(m1).contains("dso.M110"), "prefix matches follow the exact one")
        XCTAssertEqual(m1.dropFirst().first?.kind, .prefix)
    }

    func testNGCAndICDesignationsInAllSpellings() throws {
        let catalog = try catalog()
        for spelling in ["ngc224", "NGC 224", "ngc0224", "NGC 0224", "Ngc-224", "N G C 224", "NGC00224"] {
            let first = catalog.search(spelling).first
            XCTAssertEqual(first?.object.id, "dso.M31", spelling)
            XCTAssertEqual(first?.matchedText, "NGC 224", spelling)
            XCTAssertEqual(first?.kind, .exact, spelling)
        }
        XCTAssertEqual(catalog.search("ngc7000").first?.object.id, "dso.NGC7000")
        XCTAssertEqual(catalog.search("ngc 2244").first?.object.id, "dso.NGC2239")
        for spelling in ["ic 434", "IC434", "ic0434", "I C 434", "IC-434"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "dso.IC434", spelling)
        }
        XCTAssertEqual(catalog.search("ic 11").first?.object.id, "dso.NGC281")
        XCTAssertEqual(catalog.search("ic 359a").first?.object.id, "dso.IC359A")
        XCTAssertEqual(catalog.search("ic 2431 ned 02").first?.object.id, "dso.IC2431_NED02")
    }

    func testEveryNGCAndICNumberIsFindable() throws {
        let catalog = try catalog()
        var checked = 0
        for record in try CatalogFixture.rawDeepSky() {
            for (prefix, numbers) in [("NGC", record.ngc ?? []), ("IC", record.ic ?? [])] {
                for number in numbers {
                    guard catalog.object(id: "dso.\(record.id)") != nil else { continue }
                    let exact = catalog.search("\(prefix) \(number)", limit: 10).filter { $0.kind == .exact }.map(\.object.id)
                    XCTAssertTrue(exact.contains("dso.\(record.id)"), "\(prefix) \(number) -> \(record.id), found \(exact)")
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 600)
    }

    func testOtherCatalogDesignationsInAllSpellings() throws {
        let catalog = try catalog()
        for spelling in ["c14", "C 14", "caldwell 14", "Caldwell14", "c014"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "dso.C14", spelling)
            XCTAssertEqual(catalog.search(spelling).first?.kind, .exact, spelling)
        }
        XCTAssertEqual(catalog.search("mel 111").first?.object.id, "dso.Mel111")
        XCTAssertEqual(catalog.search("melotte 111").first?.object.id, "dso.Mel111")
        XCTAssertEqual(catalog.search("b33").first?.object.id, "dso.B33")
        XCTAssertEqual(catalog.search("barnard 33").first?.object.id, "dso.B33")
        XCTAssertEqual(catalog.search("collinder 399").first?.object.id, "dso.Cl399")
        XCTAssertEqual(catalog.search("cr 399").first?.object.id, "dso.Cl399")
        XCTAssertEqual(catalog.search("eso 56-115").first?.object.id, "dso.ESO56-115")
        XCTAssertEqual(catalog.search("eso56115").first?.object.id, "dso.ESO56-115")
        XCTAssertEqual(catalog.search("hcg 92").first?.object.id, "dso.HCG92")
        XCTAssertEqual(catalog.search("hickson 92").first?.object.id, "dso.HCG92")
        XCTAssertEqual(catalog.search("caldwell 14").first?.matchedText, "Caldwell 14")
        XCTAssertEqual(catalog.search("c 14").first?.matchedText, "Caldwell 14")
    }

    func testStarCatalogNumbers() throws {
        let catalog = try catalog()
        for spelling in ["hr 2491", "HR2491", "hr02491", "HR  2491", "H R 2491"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "star.hip32349", spelling)
            XCTAssertEqual(catalog.search(spelling).first?.matchedText, "HR 2491", spelling)
        }
        for spelling in ["hd 48915", "HD48915", "hd048915"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "star.hip32349", spelling)
        }
        for spelling in ["hip 32349", "HIP32349", "hip032349"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "star.hip32349", spelling)
        }
        // Every 25th star with each kind of number is found by it.
        for (offset, star) in try CatalogFixture.rawStars().enumerated() where offset % 25 == 0 {
            let id = star.hip.map { "star.hip\($0)" } ?? star.hr.map { "star.hr\($0)" } ?? "star.hyg\(star.hyg ?? 0)"
            for query in [star.hr.map { "HR \($0)" }, star.hd.map { "hd\($0)" }, star.hip.map { "HIP \($0)" }].compactMap({ $0 }) {
                let first = catalog.search(query, limit: 3).first
                XCTAssertEqual(first?.object.id, id, query)
                XCTAssertEqual(first?.kind, .exact, query)
            }
        }
    }

    func testBayerAndFlamsteedDesignationsInAllSpellings() throws {
        let catalog = try catalog()
        for spelling in ["α CMa", "alpha cma", "Alpha CMa", "ALPHA CMA", "alphacma", "alpha canis majoris", "Alpha Canis Majoris",
                         "α canis majoris", "α Canis Majoris", "alp cma", "alpcma", "alp canis majoris", "ALPHA-CMA",
                         "α  CMa", "Α CMa"] {
            let first = catalog.search(spelling).first
            XCTAssertEqual(first?.object.id, "star.hip32349", spelling)
            XCTAssertEqual(first?.kind, .exact, spelling)
        }
        for spelling in ["9 CMa", "9 canis majoris", "9cma", "09 cma"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "star.hip32349", spelling)
            XCTAssertEqual(catalog.search(spelling).first?.kind, .exact, spelling)
        }
        XCTAssertEqual(catalog.search("alf cma").first?.object.id, "star.hip32349", "SIMBAD writes alf")
        XCTAssertEqual(catalog.search("alf canis majoris").first?.kind, .exact)
        XCTAssertEqual(catalog.search("alp cma").first?.matchedText, "α CMa")
        XCTAssertEqual(catalog.search("alpha canis majoris").first?.matchedText, "Alpha Canis Majoris")
        XCTAssertEqual(catalog.search("9 canis majoris").first?.matchedText, "9 CMa")
        XCTAssertEqual(catalog.search("alpha orionis").first?.object.id, "star.hip27989")
        XCTAssertEqual(catalog.search("alpha ori").first?.object.id, "star.hip27989")
        XCTAssertEqual(catalog.search("58 ori").first?.object.id, "star.hip27989")
        XCTAssertEqual(catalog.search("beta orionis").first?.object.id, "star.hip24436", "Rigel")
        XCTAssertEqual(catalog.search("gamma crucis").first?.object.id, "star.hip61084", "Gacrux")
    }

    func testSuperscriptBayerDesignations() throws {
        let catalog = try catalog()
        for spelling in ["α¹ Cen", "alpha1 cen", "alpha 1 cen", "alpha1 centauri", "alpha 1 centauri", "alp1 cen", "α1 Cen",
                         "alpha1centauri", "Α¹ Cen", "alpha¹ cen"] {
            let first = catalog.search(spelling).first
            XCTAssertEqual(first?.object.id, "star.hip71683", spelling)
            XCTAssertEqual(first?.kind, .exact, spelling)
        }
        XCTAssertEqual(catalog.search("α² Cen").first?.object.id, "star.hip71681", "Toliman")
        XCTAssertEqual(catalog.search("alpha2 centauri").first?.object.id, "star.hip71681")
        // Without the digit both components of the pair match exactly.
        for spelling in ["alpha cen", "alpha centauri", "α Cen", "alp cen"] {
            let exact = catalog.search(spelling).filter { $0.kind == .exact }.map(\.object.id)
            XCTAssertEqual(Set(exact), ["star.hip71683", "star.hip71681"], spelling)
        }
        XCTAssertEqual(catalog.search("alpha centauri").first?.object.id, "star.hip71683", "the brighter component first")
        XCTAssertEqual(catalog.search("alpha1 centauri").first?.matchedText, "Alpha¹ Centauri")
    }

    func testEveryBayerDesignationIsFindableInEverySpelling() throws {
        let catalog = try catalog()
        let letters = GreekAlphabet.letters
        var checked = 0
        for (offset, star) in try CatalogFixture.rawStars().enumerated() where offset % 3 == 0 {
            guard let bayer = star.b, let first = bayer.unicodeScalars.first, let letter = GreekAlphabet.letter(for: first),
                  let constellation = catalog.constellation(abbreviation: star.c) else { continue }
            let id = star.hip.map { "star.hip\($0)" } ?? star.hr.map { "star.hr\($0)" } ?? "star.hyg\(star.hyg ?? 0)"
            let suffix = String(bayer.unicodeScalars.dropFirst())
            var queries = ["\(bayer) \(star.c)", "\(letter.name)\(suffix) \(star.c)", "\(letter.name) \(star.c)",
                           "\(letter.name)\(suffix) \(constellation.genitive)", "\(bayer) \(constellation.genitive)"]
            queries += letter.abbreviations.map { "\($0)\(suffix) \(star.c)" }
            for query in queries {
                let exact = catalog.search(query, limit: 20).filter { $0.kind == .exact }.map(\.object.id)
                XCTAssertTrue(exact.contains(id), "\(query) should find \(id), found \(exact)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 400)
        let abbreviations = letters.flatMap(\.abbreviations)
        XCTAssertTrue(["alp", "bet", "gam", "del", "eps", "zet", "iot", "kap", "lam", "omi", "sig", "ups", "ome", "tet", "the", "ksi", "khi"].allSatisfy(abbreviations.contains))
    }

    func testTheSpellingsOfThetaXiAndChi() throws {
        let catalog = try catalog()
        let sargas = try XCTUnwrap(catalog.search("Sargas").first?.object.id)
        for spelling in ["θ Sco", "theta sco", "the sco", "tet sco", "Theta Scorpii", "tet scorpii", "ϑ Sco"] {
            XCTAssertTrue(catalog.search(spelling, limit: 5).filter { $0.kind == .exact }.map(\.object.id).contains(sargas), spelling)
        }
        let taiyangshou = try XCTUnwrap(catalog.search("Taiyangshou").first?.object.id)
        for spelling in ["χ UMa", "chi uma", "khi uma", "Chi Ursae Majoris", "khi ursae majoris"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, taiyangshou, spelling)
        }
        for spelling in ["ξ UMa", "xi uma", "ksi uma", "Xi Ursae Majoris"] {
            let names = catalog.search(spelling, limit: 5).filter { $0.kind == .exact }.map(\.object.name)
            XCTAssertEqual(Set(names), ["Alula Australis", "Alula Australis B"], spelling)
        }
    }

    // MARK: Normalization

    func testCaseDiacriticsAndWidthDoNotMatter() throws {
        let catalog = try catalog()
        for spelling in ["sirius", "SIRIUS", "SiRiUs", "ｓｉｒｉｕｓ", "ＳＩＲＩＵＳ", "Sirius!", "(Sirius)", "'sirius'", "  sirius  ",
                         "s i r i u s", "S-I-R-I-U-S", "sir\u{00AD}ius", "sirius\u{200B}", "\u{FEFF}sirius"] {
            XCTAssertEqual(catalog.search(spelling).first?.object.id, "star.hip32349", spelling)
            XCTAssertEqual(catalog.search(spelling).first?.kind, .exact, spelling)
        }
        // Names with diacritics are found without them, and with decomposed accents.
        var checked = 0
        for star in try CatalogFixture.rawStars() {
            guard let name = star.n, name.unicodeScalars.contains(where: { $0.value > 0x7F }) else { continue }
            let id = star.hip.map { "star.hip\($0)" } ?? star.hr.map { "star.hr\($0)" } ?? "star.hyg\(star.hyg ?? 0)"
            let plain = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            XCTAssertTrue(catalog.search(plain, limit: 5).filter { $0.kind == .exact }.map(\.object.id).contains(id), "\(plain) -> \(name)")
            XCTAssertTrue(catalog.search(name.decomposedStringWithCanonicalMapping, limit: 5).map(\.object.id).contains(id), name)
            XCTAssertTrue(catalog.search(name.uppercased(), limit: 5).map(\.object.id).contains(id), name)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10)
        XCTAssertEqual(catalog.search("belenos").first?.object.name, "Bélénos")
        XCTAssertEqual(catalog.search("Bélénos").first?.object.name, "Bélénos")
        XCTAssertEqual(catalog.search("ananuca").first?.object.name, "Añañuca")
        XCTAssertEqual(catalog.search("monch").first?.object.name, "Mönch")
        XCTAssertEqual(catalog.search("tupa").first?.object.name, "Tupã")
        XCTAssertEqual(catalog.search("barnards star").first?.object.id, "star.hip87937")
        XCTAssertEqual(catalog.search("barnard’s star").first?.object.id, "star.hip87937")
    }

    func testPunctuationAndWhitespaceDifferencesAreIgnored() throws {
        let catalog = try catalog()
        for spelling in ["orion nebula", "Orion-Nebula", "orion_nebula", "orion   nebula", "orion,nebula", "orionnebula",
                         "ORION NEBULA", "orion\tnebula", "orion\nnebula", "orion.nebula", "(orion) nebula"] {
            let first = catalog.search(spelling).first
            XCTAssertEqual(first?.object.id, "dso.M42", spelling)
            XCTAssertEqual(first?.kind, .exact, spelling)
        }
    }

    // MARK: Ranking

    func testResultsAreRankedByKindThenListingProminenceBrightnessAndName() throws {
        let catalog = try catalog()
        let queries = ["a", "m", "ngc", "hr", "hd 4", "alpha", "the", "cen", "1", "7", "ori", "sag", "nebula", "cluster", "m1",
                       "ic", "hip 3", "galaxy", "star", "gam", "eta car", "mu", "ngc 1", "orion", "andromeda", "alpha cen", "c1"]
        for query in queries {
            let results = catalog.search(query, limit: 300)
            XCTAssertFalse(results.isEmpty, query)
            assertRankingOrder(results, query)
        }
    }

    func testEveryKindOfMatchIsPossible() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.search("sirius").first?.kind, .exact)
        XCTAssertEqual(catalog.search("siri").first?.kind, .prefix)
        XCTAssertEqual(catalog.search("centauri", limit: 200).first(where: { $0.object.id == "dso.NGC5139" })?.kind, .wordPrefix)
        XCTAssertEqual(catalog.search("ntauri", limit: 200).first(where: { $0.object.id == "dso.NGC5139" })?.kind, .contains)
        XCTAssertEqual(catalog.search("omgcent").first?.kind, .fuzzy)
        XCTAssertEqual(CatalogSearchResult.MatchKind.allCases, [.exact, .prefix, .wordPrefix, .contains, .fuzzy])
        XCTAssertTrue(CatalogSearchResult.MatchKind.exact < .prefix && CatalogSearchResult.MatchKind.contains < .fuzzy)
    }

    func testExactBeatsPrefixBeatsWordPrefixBeatsContains() throws {
        let catalog = try catalog()
        let results = catalog.search("rion", limit: 300)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.kind == .contains || $0.kind == .wordPrefix || $0.kind == .prefix })
        let orionis = catalog.search("orion", limit: 300)
        XCTAssertEqual(orionis.first?.kind, .prefix, "no object is called just Orion")
        XCTAssertTrue(orionis.contains { $0.kind == .wordPrefix }, "the Orionis designations match at a word start")
        assertRankingOrder(orionis, "orion")
    }

    func testBrighterObjectsComeFirstWithinOneKind() throws {
        let catalog = try catalog()
        let results = catalog.search("alpha", limit: 80)
        XCTAssertEqual(results.count, 80)
        XCTAssertTrue(results.allSatisfy { $0.kind == .prefix })
        XCTAssertEqual(results.prefix(5).map(\.object.name), ["Sirius", "Canopus", "Arcturus", "Rigil Kentaurus", "Vega"])
        assertRankingOrder(results, "alpha")
    }

    func testSyntheticRankingCoversEveryKindAndTieBreak() throws {
        let stars = [
            CatalogFixture.star(hip: 900001, name: "Zed"),
            CatalogFixture.star(hip: 900002, name: "Zedra"),
            CatalogFixture.star(hip: 900003, name: "Big Zed"),
            CatalogFixture.star(hip: 900004, name: "Azed"),
            CatalogFixture.star(hip: 900005, name: "Zeppelin Dumbo"),
            CatalogFixture.star(hip: 7000, magnitude: 2.0),
            CatalogFixture.star(hip: 7001, magnitude: 6.0),
            CatalogFixture.star(hip: 7002, name: "Seven Thousand", magnitude: 9.0),
            CatalogFixture.star(hip: 800001, name: "Tie Gamma", magnitude: 4.0),
            CatalogFixture.star(hip: 800002, name: "Tie Alpha", magnitude: 4.0),
            CatalogFixture.star(hip: 800003, name: "Tie Beta", magnitude: 2.0),
            CatalogFixture.star(hip: 800004, name: "Tie 10", magnitude: 5.0),
            CatalogFixture.star(hip: 800005, name: "Tie 2", magnitude: 5.0),
        ]
        let catalog = try CatalogFixture.syntheticCatalog(stars: stars)
        let names = { (query: String) -> [String] in catalog.search(query).map(\.object.name) }
        XCTAssertEqual(names("zed"), ["Zed", "Zedra", "Big Zed", "Azed"], "exact, prefix, word prefix, contains; no fuzzy suggestions")
        XCTAssertEqual(catalog.search("zed").map(\.kind), [.exact, .prefix, .wordPrefix, .contains])
        XCTAssertEqual(names("zpd"), ["Zeppelin Dumbo"], "the fuzzy suggestion appears when nothing else matches")
        XCTAssertEqual(catalog.search("zpd").map(\.kind), [.fuzzy])
        // Listed before unlisted, then brighter first.
        XCTAssertEqual(names("hip 700"), ["HIP 7000", "Seven Thousand", "HIP 7001"])
        XCTAssertEqual(catalog.search("hip 700").map(\.object.isListed), [true, true, false])
        // Brighter first, then alphabetical, with numbers in numeric order.
        XCTAssertEqual(names("tie"), ["Tie Beta", "Tie Alpha", "Tie Gamma", "Tie 2", "Tie 10"])
    }

    // MARK: Fuzzy matches

    func testFuzzyMatchesAreSuggestedOnlyWhenNothingElseMatches() throws {
        let catalog = try catalog()
        let results = catalog.search("andgal")
        XCTAssertEqual(results.first?.object.id, "dso.M31")
        XCTAssertTrue(results.allSatisfy { $0.kind == .fuzzy })
        XCTAssertEqual(results.first?.matchedText, "Andromeda Galaxy")
        for exactQuery in ["sirius", "m31", "lmc", "moon", "alpha cma", "ngc 7000"] {
            XCTAssertFalse(catalog.search(exactQuery).contains { $0.kind == .fuzzy }, exactQuery)
        }
        XCTAssertTrue(catalog.search("qqq").isEmpty)
        XCTAssertTrue(catalog.search("zzzzzzzz").isEmpty)
    }

    func testFuzzyMatchingNeedsThreeCharactersAndAWordStart() throws {
        let catalog = try catalog()
        XCTAssertFalse(catalog.search("ag").contains { $0.kind == .fuzzy })
        XCTAssertTrue(catalog.search("qz").isEmpty)
        XCTAssertTrue(catalog.search("zq").isEmpty)
        XCTAssertFalse(catalog.search("ndgal").contains { $0.object.id == "dso.M31" }, "the first letter must open a word")
        XCTAssertFalse(catalog.search("ngal").contains { $0.object.id == "dso.M31" })
        XCTAssertTrue(catalog.search("andgal").contains { $0.object.id == "dso.M31" })
        XCTAssertTrue(catalog.search("andmeda").contains { $0.object.id == "dso.M31" }, "a dropped letter is tolerated")
        XCTAssertTrue(catalog.search("magcloud").contains { $0.object.id == "dso.ESO56-115" })
    }

    // MARK: Matched text

    func testMatchedTextIsTheDisplayedNameOrDesignation() throws {
        let catalog = try catalog()
        let expectations: [(String, String)] = [
            ("sirius", "Sirius"), ("alp cma", "α CMa"), ("alpha canis majoris", "Alpha Canis Majoris"),
            ("hr 2491", "HR 2491"), ("hd 48915", "HD 48915"), ("hip 32349", "HIP 32349"), ("9 canis majoris", "9 CMa"),
            ("m31", "M 31"), ("ngc 224", "NGC 224"), ("andromeda gal", "Andromeda Galaxy"), ("caldwell 14", "Caldwell 14"),
            ("c 14", "Caldwell 14"), ("lmc", "LMC"), ("nubecula", "Nubecula Major"), ("orion neb", "Orion Nebula"),
            ("great orion", "Great Orion Nebula"), ("ncp", "NCP"), ("celestial north", "Celestial North Pole"),
            ("sagittarius a", "Sagittarius A*"), ("jupiter", "Jupiter"),
        ]
        for (query, text) in expectations {
            XCTAssertEqual(catalog.search(query).first?.matchedText, text, query)
        }
    }

    // MARK: Limits and unusual input

    func testLimits() throws {
        let catalog = try catalog()
        XCTAssertTrue(catalog.search("a", limit: 0).isEmpty)
        XCTAssertTrue(catalog.search("a", limit: -1).isEmpty)
        XCTAssertTrue(catalog.search("a", limit: Int.min).isEmpty)
        XCTAssertEqual(catalog.search("a", limit: 1).count, 1)
        XCTAssertEqual(catalog.search("a", limit: 7).count, 7)
        XCTAssertEqual(catalog.search("a").count, 50, "the default limit is 50")
        let all = catalog.search("a", limit: Int.max)
        XCTAssertGreaterThan(all.count, 1000)
        XCTAssertLessThanOrEqual(all.count, catalog.objects.count)
        XCTAssertEqual(Set(ids(all)).count, all.count, "an object is listed once")
        XCTAssertEqual(ids(catalog.search("a", limit: 10)), Array(ids(all).prefix(10)))
        XCTAssertEqual(ids(catalog.search("a")), Array(ids(all).prefix(50)))
        XCTAssertEqual(catalog.search("sirius", limit: 1).count, 1)
    }

    func testQueriesWithoutLettersOrDigitsFindNothing() throws {
        let catalog = try catalog()
        for query in ["", " ", "   ", "\n", "\t\r\n", "!!!", "---", "...", "—", "*", "🔭", "😀😀😀", "星空", "\u{0}", "\u{200B}",
                      "\u{0301}", "Орион", "﷽", "∞", "\u{202E}", "()[]{}", "'", "`", "\u{2019}"] {
            XCTAssertTrue(catalog.search(query).isEmpty, "\(query.unicodeScalars.map(\.value))")
        }
    }

    func testOnlyTheFirstSixtyFourCharactersOfAQueryAreUsed() throws {
        let catalog = try catalog()
        let padded = "sirius" + String(repeating: " ", count: 100) + "garbage that is ignored"
        XCTAssertEqual(catalog.search(padded).first?.object.id, "star.hip32349")
        XCTAssertEqual(catalog.search(padded).first?.kind, .exact)
        let withinLimit = "sirius" + String(repeating: " ", count: 40) + "garbage"
        XCTAssertTrue(catalog.search(withinLimit).isEmpty || catalog.search(withinLimit).first?.kind != .exact)
        XCTAssertEqual(Catalog.maximumQueryLength, 64)
        let atLimit = String(repeating: "m", count: 64)
        XCTAssertTrue(catalog.search(atLimit).isEmpty)
        XCTAssertEqual(catalog.search(String(repeating: "x", count: 100_000)).count, 0)
    }

    func testGarbageInputNeverCrashes() throws {
        let catalog = try catalog()
        let hostile: [String] = [
            String(repeating: "a", count: 1_000_000), String(repeating: "é", count: 500_000),
            String(repeating: "🔭", count: 100_000), String(repeating: "\u{0301}", count: 100_000),
            "a" + String(repeating: "\u{0301}", count: 100_000), String(repeating: "Ω", count: 100_000),
            String(repeating: "9", count: 100_000), String(repeating: "0", count: 100_000),
            String(repeating: "m31 ", count: 50_000), "\u{0000}\u{0000}\u{0000}", "%s%s%n%x", "\\", "'; DROP TABLE stars; --",
            "<script>alert(1)</script>", "../../etc/passwd", "\u{202E}\u{202D}RTL", "👨‍👩‍👧‍👦", "🇺🇸🇯🇵", "\u{FFFD}\u{FFFE}\u{FFFF}",
            "\u{10FFFF}", "\u{E000}", "\u{D7FF}", "ǅ", "ŉ", "ﬃ", "①②③", "ⅷ", "㎏", "㌀", "Ǆ", "Ꜳꜳ", "ᴀʙᴄ", "𝐒𝐢𝐫𝐢𝐮𝐬", "𝕊𝕚𝕣𝕚𝕦𝕤",
            "ａｂｃ１２３", "ＡＢＣ", "\u{FF5E}", "α" + String(repeating: "\u{0345}", count: 1000),
        ]
        for text in hostile {
            let results = catalog.search(text, limit: 5)
            XCTAssertLessThanOrEqual(results.count, 5)
            assertRankingOrder(results, String(text.prefix(20)))
        }
        // Mathematical alphanumerics decompose to plain letters.
        XCTAssertEqual(catalog.search("𝐒𝐢𝐫𝐢𝐮𝐬").first?.object.id, "star.hip32349")
        XCTAssertEqual(catalog.search("𝕊𝕚𝕣𝕚𝕦𝕤").first?.object.id, "star.hip32349")
    }

    func testRandomTextNeverCrashes() throws {
        let catalog = try catalog()
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let ranges: [ClosedRange<UInt32>] = [0x20...0x7E, 0x0...0x1F, 0xA0...0x17F, 0x370...0x3FF, 0x2000...0x206F, 0x2070...0x209F,
                                             0x300...0x36F, 0xFF00...0xFFEF, 0x1F300...0x1F64F, 0x4E00...0x4E80, 0x30...0x39, 0x41...0x5A]
        for _ in 0..<300 {
            var text = String.UnicodeScalarView()
            for _ in 0..<Int(next() % 40) {
                let range = ranges[Int(next() % UInt64(ranges.count))]
                let value = range.lowerBound + UInt32(next() % UInt64(range.upperBound - range.lowerBound + 1))
                if let scalar = Unicode.Scalar(value) { text.append(scalar) }
            }
            let results = catalog.search(String(text), limit: 8)
            XCTAssertLessThanOrEqual(results.count, 8)
            assertRankingOrder(results, String(text))
        }
    }

    func testSearchesAreRepeatableAndSafeToRunConcurrently() throws {
        let catalog = try catalog()
        let queries = ["sirius", "m31", "alpha cen", "ngc 7", "orion", "andgal", "hr 24", "a"]
        let expected = queries.map { catalog.search($0, limit: 20).map(\.object.id) }
        let box = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 64) { iteration in
            let index = iteration % queries.count
            box.record(index, catalog.search(queries[index], limit: 20).map(\.object.id))
        }
        XCTAssertEqual(box.all().count, 64)
        for (index, results) in box.all() {
            XCTAssertEqual(results, expected[index], queries[index])
        }
    }
}

/// Collects the results of concurrent searches.
private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [(Int, [String])] = []

    func record(_ index: Int, _ ids: [String]) {
        lock.lock()
        results.append((index, ids))
        lock.unlock()
    }

    func all() -> [(Int, [String])] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

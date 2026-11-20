import XCTest
@testable import LodestarKit

/// Reading and writing observing lists. The fixtures are in `Fixtures/interchange/` (see the README there): the header and
/// the first row of `telescopius_export.csv` are quoted from a real Telescopius export, `skysafari_list.skylist` has the
/// shape of the lists SkySafari 6/7 and RASC publish.
final class ObservingListCodecTests: XCTestCase {
    private let tolerance = 1e-6

    private func decode(_ fixture: String) throws -> ObservingListImport {
        try ObservingListCodec.decode(InterchangeTestSupport.fixture(fixture))
    }

    // MARK: Telescopius

    func testTelescopiusExportIsRecognisedAndReadByColumnName() throws {
        let list = try decode("telescopius_export.csv")
        XCTAssertEqual(list.format, .telescopiusCSV)
        XCTAssertTrue(list.errors.isEmpty)
        XCTAssertFalse(list.isTruncated)
        XCTAssertEqual(list.targets.count, 4)

        let pleiades = list.targets[0]
        XCTAssertEqual(pleiades.designation, "M 45")
        XCTAssertEqual(pleiades.name, "Pleiades")
        XCTAssertEqual(pleiades.alternates, ["CL MELOTTE 22", "H 0346+24", "OCL 421.0"])
        XCTAssertEqual(pleiades.line, 2)
        // 03h 46' 24" and 24º 06' 50" (the J2000 columns, not the jNow ones), arcseconds written as two quotation marks.
        XCTAssertEqual(try XCTUnwrap(pleiades.rightAscension), (3 + 46.0 / 60 + 24.0 / 3600) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(pleiades.declination), 24 + 6.0 / 60 + 50.0 / 3600, accuracy: tolerance)

        let andromeda = list.targets[1]
        XCTAssertEqual(andromeda.designation, "M 31")
        XCTAssertEqual(try XCTUnwrap(andromeda.rightAscension), (42.0 / 60 + 44.0 / 3600) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(andromeda.declination), 41 + 16.0 / 60 + 9.0 / 3600, accuracy: tolerance)
        XCTAssertEqual(andromeda.alternates, ["NGC 224", "UGC 454"])

        // No familiar name: the label of the list entry names it; a negative declination reads with its sign.
        let veil = list.targets[2]
        XCTAssertEqual(veil.designation, "NGC 7000")
        XCTAssertEqual(veil.name, "North America Nebula")
        let barnard = list.targets[3]
        XCTAssertEqual(barnard.designation, "IC 434")
        XCTAssertNil(barnard.name)
        XCTAssertEqual(try XCTUnwrap(barnard.declination), -(2 + 28.0 / 60), accuracy: tolerance)
    }

    func testTelescopiusLabelNamesAnEntryWithoutFamiliarName() throws {
        let text = "Catalogue Entry,Familiar Name,Right Ascension (j2000),Declination (j2000),Label\nNGC 6960,,20h 45' 42\",30º 43' 00\",Veil West\n"
        let target = try XCTUnwrap(ObservingListCodec.decode(text).targets.first)
        XCTAssertEqual(target.name, "Veil West")
        XCTAssertEqual(target.designation, "NGC 6960")
    }

    func testOlderTelescopiusExportsWithoutEpochColumnsAreRead() throws {
        let list = try decode("telescopius_legacy.csv")
        XCTAssertEqual(list.format, .telescopiusCSV)
        XCTAssertEqual(list.targets.map(\.designation), ["M 45", "M 42"])
        XCTAssertEqual(try XCTUnwrap(list.targets[1].rightAscension), (5 + 35.0 / 60 + 17.0 / 3600) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[1].declination), -(5 + 23.0 / 60 + 28.0 / 3600), accuracy: tolerance)
    }

    func testJNowColumnsAreNeverUsed() throws {
        let text = "Catalogue Entry,Right Ascension (jNow),Declination (jNow)\nM 31,00h 43' 46\",41º 22' 11\"\n"
        let target = try XCTUnwrap(ObservingListCodec.decode(text).targets.first)
        XCTAssertEqual(target.designation, "M 31")
        XCTAssertFalse(target.hasCoordinates)
    }

    // MARK: Generic CSV

    func testGenericCSVWithDegrees() throws {
        let list = try decode("generic_degrees.csv")
        XCTAssertEqual(list.format, .genericCSV)
        XCTAssertEqual(list.targets.count, 5)
        XCTAssertTrue(list.errors.isEmpty)
        XCTAssertEqual(list.targets[0].name, "Andromeda Galaxy")
        XCTAssertEqual(list.targets[0].designation, "M 31")
        XCTAssertEqual(try XCTUnwrap(list.targets[0].rightAscension), 10.6847, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[1].declination), -5.3911, accuracy: tolerance)
        XCTAssertEqual(list.targets[2].name, "Flame, Horsehead region")
        XCTAssertNil(list.targets[2].designation)
        XCTAssertEqual(try XCTUnwrap(list.targets[3].declination), 12.25, accuracy: tolerance)
        XCTAssertEqual(list.targets[4].name, "Moon")
        XCTAssertFalse(list.targets[4].hasCoordinates)
        XCTAssertEqual(list.targets.map(\.line), [2, 3, 4, 5, 6])
    }

    func testGenericCSVWithSexagesimalAndSemicolons() throws {
        let list = try decode("generic_sexagesimal.csv")
        XCTAssertEqual(list.format, .genericCSV)
        XCTAssertEqual(list.targets.map(\.designation), ["M 13", "NGC 6992", "M 27", "Bad Dec", "Bad RA", "Half"])
        XCTAssertEqual(try XCTUnwrap(list.targets[0].rightAscension), (16 + 41.0 / 60 + 41.6 / 3600) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[0].declination), 36 + 27.0 / 60 + 37.0 / 3600, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[1].rightAscension), (20 + 56.0 / 60 + 20.0 / 3600) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[2].declination), 22 + 43.0 / 60 + 16.0 / 3600, accuracy: tolerance)
        // Rows with a bad or half coordinate stay in the list without coordinates, and are reported with their line.
        XCTAssertEqual(list.errors, [
            ObservingListRowError(line: 5, reason: .invalidDeclination),
            ObservingListRowError(line: 6, reason: .invalidRightAscension),
            ObservingListRowError(line: 7, reason: .incompleteCoordinates),
        ])
        XCTAssertTrue(list.targets[3...].allSatisfy { !$0.hasCoordinates })
    }

    func testAPlainRightAscensionIsDegreesUnlessTheHeaderSaysHours() throws {
        let degrees = try ObservingListCodec.decode("name,ra,dec\nA,83.8,-5.4\nB,360,0\n")
        XCTAssertEqual(try XCTUnwrap(degrees.targets[0].rightAscension), 83.8, accuracy: tolerance)
        XCTAssertEqual(degrees.errors, [ObservingListRowError(line: 3, reason: .invalidRightAscension)])
        let hours = try ObservingListCodec.decode("name,RA (hours),Dec\nA,5.588,-5.4\nB,24,0\n")
        XCTAssertEqual(try XCTUnwrap(hours.targets[0].rightAscension), 5.588 * 15, accuracy: tolerance)
        XCTAssertEqual(hours.errors, [ObservingListRowError(line: 3, reason: .invalidRightAscension)])
        let marked = try ObservingListCodec.decode("name,Right Ascension,Declination\nA,83.8°,-5.4\nB,5h 35m,-5d 23m\n")
        XCTAssertEqual(try XCTUnwrap(marked.targets[0].rightAscension), 83.8, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(marked.targets[1].rightAscension), (5 + 35.0 / 60) * 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(marked.targets[1].declination), -(5 + 23.0 / 60), accuracy: tolerance)
    }

    func testHeaderNamesAreMatchedWithoutCaseAndPunctuation() throws {
        let list = try ObservingListCodec.decode("TARGET NAME,RA_J2000,DEC-J2000\nM 1,83.63,22.01\n")
        XCTAssertEqual(list.targets.first?.name, "M 1")
        XCTAssertEqual(try XCTUnwrap(list.targets.first?.rightAscension), 83.63, accuracy: tolerance)
        let onlyCoordinates = try ObservingListCodec.decode("ra,dec\n10.5,20.5\n")
        XCTAssertNil(onlyCoordinates.targets.first?.name)
        XCTAssertTrue(onlyCoordinates.targets.first?.hasCoordinates == true)
    }

    func testGuardedSpreadsheetTextIsReadBack() throws {
        let list = try ObservingListCodec.decode("name\n'=SUM(A1)\n'plain\n")
        XCTAssertEqual(list.targets.map(\.name), ["=SUM(A1)", "'plain"])
    }

    func testRowsWithoutAnythingToIdentifyThemAreReported() throws {
        let list = try ObservingListCodec.decode("name,type\nM 31,Galaxy\n,Galaxy\n,\n")
        XCTAssertEqual(list.targets.map(\.name), ["M 31"])
        XCTAssertEqual(list.errors, [ObservingListRowError(line: 3, reason: .missingName)])
    }

    func testTheRowLimitIsEnforced() throws {
        var text = "name\n"
        for index in 0..<(ObservingListCodec.maximumTargets + 3) { text += "T\(index)\n" }
        let list = try ObservingListCodec.decode(text)
        XCTAssertEqual(list.targets.count, ObservingListCodec.maximumTargets)
        XCTAssertTrue(list.isTruncated)
        XCTAssertEqual(list.targets.last?.name, "T\(ObservingListCodec.maximumTargets - 1)")
    }

    func testLongNamesAreCut() throws {
        let list = try ObservingListCodec.decode("name\n" + String(repeating: "x", count: 500) + "\n")
        XCTAssertEqual(list.targets.first?.name?.count, ObservingListCodec.maximumNameScalars)
    }

    // MARK: SkySafari

    func testSkySafariListIsRead() throws {
        let list = try decode("skysafari_list.skylist")
        XCTAssertEqual(list.format, .skySafari)
        XCTAssertEqual(list.targets.map(\.designation), ["M 35", "IC 443", "M 44", "NGC 6946", nil, "NGC 7000"])
        XCTAssertEqual(list.targets.map(\.name), [nil, nil, "Beehive Cluster", "Fireworks Galaxy", "Jupiter", nil])
        XCTAssertEqual(list.targets[0].alternates, ["NGC 2168"])
        XCTAssertEqual(list.targets[2].alternates, ["NGC 2632", "Praesepe"])
        XCTAssertEqual(list.targets[3].alternates, ["C 12", "UGC 11597"])
        XCTAssertEqual(list.targets.map(\.line), [3, 9, 15, 23, 31, 40])
        XCTAssertTrue(list.targets.allSatisfy { !$0.hasCoordinates })
        // An object without a name, and an object that is never closed.
        XCTAssertEqual(list.errors, [
            ObservingListRowError(line: 36, reason: .missingName),
            ObservingListRowError(line: 40, reason: .unterminatedObject),
        ])
    }

    func testSkySafariHeaderIsFoundWithBlankLinesByteOrderMarkAndOtherLineBreaks() throws {
        let text = "\u{FEFF}\r\n  skysafariobservinglistversion=3.0\r\nSkyObject=BeginObject\rCatalogNumber = M 1\rEndObject=SkyObject\r"
        let list = try ObservingListCodec.decode(text)
        XCTAssertEqual(list.format, .skySafari)
        XCTAssertEqual(list.targets.map(\.designation), ["M 1"])
    }

    // MARK: Writing

    private let entries = [
        ObservingListEntry(name: "Andromeda Galaxy", designation: "M 31", rightAscension: 10.6847, declination: 41.2687, typeName: "Galaxy"),
        ObservingListEntry(name: "Jupiter", typeName: "Planet"),
        ObservingListEntry(name: "=HYPERLINK(\"x\")", rightAscension: 400, declination: 5),
        ObservingListEntry(name: "Flame, Horsehead", rightAscension: 85.25, declination: -2.45),
    ]

    func testCSVExport() {
        let expected = [
            "Name,Designation,RA J2000 (deg),Dec J2000 (deg),Type",
            "Andromeda Galaxy,M 31,10.68470,41.26870,Galaxy",
            "Jupiter,,,,Planet",
            "\"'=HYPERLINK(\"\"x\"\")\",,,,",
            "\"Flame, Horsehead\",,85.25000,-2.45000,",
        ]
        XCTAssertEqual(ObservingListCodec.encodeCSV(entries), expected.joined(separator: "\r\n") + "\r\n")
    }

    func testCSVGuardsFormulasInEveryTextColumn() throws {
        // Each free-text column starts with a different character that a spreadsheet would run as a formula.
        let entry = ObservingListEntry(name: "=1+1", designation: "+2", rightAscension: 10, declination: 5, typeName: "@SUM(A1)")
        let table = try InterchangeCSV.parse(Array(ObservingListCodec.encodeCSV([entry]).unicodeScalars), maximumRecords: 10)
        XCTAssertEqual(table.records.count, 2)
        XCTAssertEqual(table.records[1].fields, ["'=1+1", "'+2", "10.00000", "5.00000", "'@SUM(A1)"])
        let minus = ObservingListEntry(name: "-1", designation: "M 1", typeName: "-cmd")
        let other = try InterchangeCSV.parse(Array(ObservingListCodec.encodeCSV([minus]).unicodeScalars), maximumRecords: 10)
        XCTAssertEqual(other.records[1].fields, ["'-1", "M 1", "", "", "'-cmd"])
    }

    func testCSVExportReadsBackThroughTheImporter() throws {
        let list = try ObservingListCodec.decode(ObservingListCodec.encodeCSV(entries))
        XCTAssertEqual(list.format, .genericCSV)
        XCTAssertTrue(list.errors.isEmpty)
        XCTAssertEqual(list.targets.map(\.name), ["Andromeda Galaxy", "Jupiter", "=HYPERLINK(\"x\")", "Flame, Horsehead"])
        XCTAssertEqual(list.targets[0].designation, "M 31")
        XCTAssertEqual(try XCTUnwrap(list.targets[0].rightAscension), 10.6847, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(list.targets[3].declination), -2.45, accuracy: tolerance)
        XCTAssertFalse(list.targets[1].hasCoordinates)
        XCTAssertFalse(list.targets[2].hasCoordinates)
    }

    func testSkySafariExport() {
        XCTAssertEqual(ObservingListCodec.encodeSkySafari(Array(entries.prefix(2))), """
        SkySafariObservingListVersion=3.0
        SortedBy=Default Order
        SkyObject=BeginObject
        \tObjectID=2,-1,-1
        \tCatalogNumber=M 31
        \tDefaultIndex=0
        EndObject=SkyObject
        SkyObject=BeginObject
        \tObjectID=2,-1,-1
        \tCommonName=Jupiter
        \tDefaultIndex=1
        EndObject=SkyObject

        """)
    }

    func testSkySafariExportReadsBackThroughTheImporter() throws {
        let list = try ObservingListCodec.decode(ObservingListCodec.encodeSkySafari(entries))
        XCTAssertEqual(list.format, .skySafari)
        XCTAssertEqual(list.targets.map(\.designation), ["M 31", nil, nil, nil])
        XCTAssertEqual(list.targets.map(\.name), [nil, "Jupiter", "=HYPERLINK(\"x\")", "Flame, Horsehead"])
        XCTAssertTrue(list.errors.isEmpty)
    }

    func testExportsAreCappedAndKeepLinesApart() {
        let many = (0..<(ObservingListCodec.maximumTargets + 5)).map { ObservingListEntry(name: "T\($0)") }
        XCTAssertEqual(ObservingListCodec.encodeCSV(many).split(separator: "\r\n").count, ObservingListCodec.maximumTargets + 1)
        let multiline = ObservingListEntry(name: "Two\nlines\r\nhere", designation: "A\tB")
        let text = ObservingListCodec.encodeSkySafari([multiline])
        XCTAssertTrue(text.contains("\tCatalogNumber=A B\n"))
        XCTAssertEqual(text.split(separator: "\n").count, 7)
    }

    // MARK: Malformed input

    func testMalformedInputGivesErrorsNotCrashes() {
        XCTAssertThrowsError(try ObservingListCodec.decode("")) { XCTAssertEqual($0 as? InterchangeError, .empty) }
        XCTAssertThrowsError(try ObservingListCodec.decode(" \r\n\t\n")) { XCTAssertEqual($0 as? InterchangeError, .empty) }
        XCTAssertThrowsError(try ObservingListCodec.decode("foo,bar\n1,2\n")) { XCTAssertEqual($0 as? InterchangeError, .missingColumns) }
        XCTAssertThrowsError(try ObservingListCodec.decode("{\"json\": true}")) { XCTAssertEqual($0 as? InterchangeError, .missingColumns) }
        XCTAssertThrowsError(try ObservingListCodec.decode("name\n\"open")) { XCTAssertEqual($0 as? InterchangeError, .unterminatedQuote(line: 2)) }
        let huge = String(repeating: "a", count: ObservingListCodec.maximumTextScalars + 1)
        XCTAssertThrowsError(try ObservingListCodec.decode(huge)) {
            XCTAssertEqual($0 as? InterchangeError, .tooLarge(maximumScalars: ObservingListCodec.maximumTextScalars))
        }
    }

    func testBinaryAndOddInputNeverTraps() throws {
        let odd = ["\u{0}\u{1}\u{2}", "name\n\u{0}\u{FFFF}\n", "name,ra,dec\nx,\u{FFFE},\u{1F31F}\n", "SkySafariObservingListVersion", "=,=,=\n=,=,=",
                   "ra,dec\n1e400,nan\n", "name,ra,dec\nA,+,-\n", "name\n" + String(repeating: "\"", count: 1001)]
        for text in odd {
            _ = try? ObservingListCodec.decode(text)
        }
        let list = try ObservingListCodec.decode("name,ra,dec\nA,1e400,nan\nB,+,-\n")
        XCTAssertEqual(list.targets.count, 2)
        XCTAssertEqual(list.errors.count, 4)
    }

    // MARK: Matching

    func testRowsAreMatchedToCatalogObjectsByDesignationAndName() throws {
        let catalog = try CatalogFixture.catalog()
        let targets = [
            ImportedTarget(name: "Andromeda Galaxy", designation: "m031", line: 2),
            ImportedTarget(name: nil, designation: "NGC 7000", line: 3),
            ImportedTarget(name: "Orion Nebula", designation: "Not a catalogue number", line: 4),
            ImportedTarget(name: "zzz unknown", designation: nil, alternates: ["qqq nothing"], line: 5),
            ImportedTarget(name: "Pleiades", designation: "M 45", alternates: ["OCL 421.0"], line: 6),
        ]
        let matches = ObservingListMatcher.match(targets, in: catalog)
        XCTAssertEqual(matches.map(\.target), targets)
        XCTAssertEqual(matches[0].object?.id, "dso.M31")
        XCTAssertEqual(matches[1].object?.id, "dso.NGC7000")
        XCTAssertEqual(matches[2].object?.id, "dso.M42")
        XCTAssertNil(matches[3].object)
        XCTAssertEqual(matches[4].object?.id, "dso.M45")
    }

    func testPartialNamesDoNotMatch() throws {
        let catalog = try CatalogFixture.catalog()
        XCTAssertNil(ObservingListMatcher.match(ImportedTarget(name: "Androm", designation: nil, line: 1), in: catalog))
        XCTAssertNotEqual(ObservingListMatcher.match(ImportedTarget(name: "M 3", designation: nil, line: 1), in: catalog)?.id, "dso.M31")
    }

    func testTelescopiusFixtureMatchesTheBundledCatalog() throws {
        let catalog = try CatalogFixture.catalog()
        let list = try decode("telescopius_export.csv")
        let matches = ObservingListMatcher.match(list.targets, in: catalog)
        XCTAssertEqual(matches[0].object?.id, "dso.M45")
        XCTAssertEqual(matches[1].object?.id, "dso.M31")
        XCTAssertEqual(matches[2].object?.id, "dso.NGC7000")
    }
}

import XCTest
@testable import LodestarKit

final class ElementSetParserTests: XCTestCase {
    private typealias Support = SatelliteTestSupport
    private let issLine1 = SatelliteTestSupport.issLine1
    private let issLine2 = SatelliteTestSupport.issLine2

    /// The error a throwing expression raises, or `nil` if it does not throw.
    private func failure(_ body: () throws -> Void) -> ElementSetError? {
        do {
            try body()
            return nil
        } catch let error as ElementSetError {
            return error
        } catch {
            return nil
        }
    }

    private func parse(_ line1: String, _ line2: String, name: String? = nil) throws -> OrbitalElements {
        try ElementSetParser.parseTwoLine(line1: line1, line2: line2, name: name)
    }

    private func civil(_ elements: OrbitalElements) -> ElementCivilDate {
        ElementCalendar.civilFromDays(Int64((elements.epoch.timeIntervalSince1970 / 86_400).rounded(.down)))
    }

    // MARK: Two-line sets

    func testParsesTheIssTwoLineSet() throws {
        let elements = try parse(issLine1, issLine2, name: "ISS (ZARYA)")
        XCTAssertEqual(elements.name, "ISS (ZARYA)")
        XCTAssertEqual(elements.objectId, "1998-067A")
        XCTAssertEqual(elements.catalogNumber, 25544)
        XCTAssertEqual(elements.classification, "U")
        XCTAssertEqual(elements.epoch.timeIntervalSince1970, Support.issEpochUnixSeconds, accuracy: 1e-5)
        XCTAssertEqual(elements.meanMotion, 15.48918166, accuracy: 1e-12)
        XCTAssertEqual(elements.eccentricity, 0.0006780, accuracy: 1e-12)
        XCTAssertEqual(elements.inclination, 51.6328, accuracy: 1e-12)
        XCTAssertEqual(elements.rightAscensionOfAscendingNode, 51.6259, accuracy: 1e-12)
        XCTAssertEqual(elements.argumentOfPericenter, 277.7856, accuracy: 1e-12)
        XCTAssertEqual(elements.meanAnomaly, 82.2363, accuracy: 1e-12)
        XCTAssertEqual(elements.ephemerisType, 0)
        XCTAssertEqual(elements.elementSetNumber, 999)
        XCTAssertEqual(elements.revolutionNumberAtEpoch, 59081)
        XCTAssertEqual(elements.bstar, 0.14456e-3, accuracy: 1e-15)
        XCTAssertEqual(elements.meanMotionDot, 7.503e-5, accuracy: 1e-15)
        XCTAssertEqual(elements.meanMotionDdot, 0.0, accuracy: 0.0)
        XCTAssertEqual(elements.periodMinutes, 1440.0 / 15.48918166, accuracy: 1e-9)
    }

    func testTheSgp4EpochIsComputedLikeTheReference() throws {
        // 00005 of the SGP4 verification file: epoch day 179.78495062 of 2000, i.e. 2000-06-27T18:50:19.7335680Z,
        // which is 18441.78495062 days after 1949-12-31T00:00Z.
        let elements = try parse(
            "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753",
            "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667"
        )
        XCTAssertEqual(elements.catalogNumber, 5)
        XCTAssertEqual(elements.objectId, "1958-002B")
        XCTAssertEqual(elements.sgp4EpochDays, 18441.78495062, accuracy: 1e-9)
        XCTAssertEqual(elements.epoch.timeIntervalSince1970, 962131819.733568, accuracy: 1e-6)
    }

    func testChecksumCountsDigitsAndMinusSigns() {
        XCTAssertEqual(ElementSetParser.checksum(issLine1), 4)
        XCTAssertEqual(ElementSetParser.checksum(issLine2), 4)
        XCTAssertEqual(ElementSetParser.checksum("0123-"), 7)
        XCTAssertEqual(ElementSetParser.checksum("123"), 6)
        XCTAssertEqual(ElementSetParser.checksum("a-b+c.d e"), 1)
        // Only the first 68 characters count.
        XCTAssertEqual(ElementSetParser.checksum(issLine1), ElementSetParser.checksum(String(issLine1.prefix(68)) + "9999"))
    }

    func testRejectsLinesOfTheWrongLength() throws {
        XCTAssertEqual(failure { _ = try parse(String(issLine1.prefix(68)), issLine2) }, .invalidLineLength(line: 1, length: 68))
        XCTAssertEqual(failure { _ = try parse(issLine1, issLine2 + "1") }, .invalidLineLength(line: 2, length: 70))
        // Trailing white space and line ends are ignored.
        XCTAssertEqual(try parse(issLine1 + "  \r\n", issLine2 + "\t\n").catalogNumber, 25544)
    }

    func testRejectsSwappedAndMislabelledLines() {
        XCTAssertEqual(failure { _ = try parse(issLine2, issLine1) }, .unexpectedLineNumber(line: 1))
        XCTAssertEqual(failure { _ = try parse(issLine1, issLine1) }, .unexpectedLineNumber(line: 2))
    }

    func testRejectsAWrongChecksum() throws {
        let corrupted = issLine1.replacingOccurrences(of: ".00007503", with: ".00007603")
        let error = failure { _ = try parse(corrupted, issLine2) }
        XCTAssertEqual(error, .checksumMismatch(line: 1, expected: 5, found: 4))
        XCTAssertEqual(
            failure { _ = try parse(issLine1, String(issLine2.prefix(68)) + "5") },
            .checksumMismatch(line: 2, expected: 4, found: 5)
        )
        XCTAssertTrue(String(describing: error!).contains("checksum"))
        // A letter in place of the checksum digit.
        guard case .invalidField(let field, _)? = failure({ _ = try parse(String(issLine1.prefix(68)) + "X", issLine2) }) else {
            return XCTFail("expected an invalid field")
        }
        XCTAssertEqual(field, "checksum")
    }

    func testRejectsDifferentObjectsOnTheTwoLines() {
        let other = Support.withChecksum(Support.replacing(issLine2, 2, 7, with: "25545"))
        XCTAssertEqual(failure { _ = try parse(issLine1, other) }, .catalogNumberMismatch(line1: 25544, line2: 25545))
    }

    private func invalidField(_ line1: String, _ line2: String) -> String? {
        if case .invalidField(let field, _)? = failure({ _ = try parse(line1, line2) }) { return field }
        return nil
    }

    func testRejectsFieldsThatAreNotNumbers() {
        let inclination = Support.withChecksum(Support.replacing(issLine2, 8, 16, with: " 5x.6328"))
        XCTAssertEqual(invalidField(issLine1, inclination), "INCLINATION")
        let eccentricity = Support.withChecksum(Support.replacing(issLine2, 26, 33, with: "00067a0"))
        XCTAssertEqual(invalidField(issLine1, eccentricity), "ECCENTRICITY")
        let drag = Support.withChecksum(Support.replacing(issLine1, 53, 61, with: " 1x456-3"))
        XCTAssertEqual(invalidField(drag, issLine2), "BSTAR")
        let epoch = Support.withChecksum(Support.replacing(issLine1, 18, 20, with: "2x"))
        XCTAssertEqual(invalidField(epoch, issLine2), "EPOCH")
        let separator = Support.withChecksum(Support.replacing(issLine1, 8, 9, with: "x"))
        XCTAssertEqual(invalidField(separator, issLine2), "separator")
        let number = Support.withChecksum(Support.replacing(issLine1, 2, 7, with: "2554 "))
        XCTAssertEqual(invalidField(number, Support.withChecksum(Support.replacing(issLine2, 2, 7, with: "2554 "))), "NORAD_CAT_ID")
    }

    private func outOfRange(_ line1: String, _ line2: String) -> String? {
        if case .valueOutOfRange(let field, _)? = failure({ _ = try parse(Support.withChecksum(line1), Support.withChecksum(line2)) }) {
            return field
        }
        return nil
    }

    func testRejectsValuesOutOfRange() throws {
        XCTAssertEqual(outOfRange(issLine1, Support.replacing(issLine2, 8, 16, with: "181.0000")), "INCLINATION")
        XCTAssertEqual(outOfRange(issLine1, Support.replacing(issLine2, 17, 25, with: "360.5000")), "RA_OF_ASC_NODE")
        XCTAssertEqual(outOfRange(issLine1, Support.replacing(issLine2, 43, 51, with: "400.0000")), "MEAN_ANOMALY")
        XCTAssertEqual(outOfRange(issLine1, Support.replacing(issLine2, 52, 63, with: " 0.00000000")), "MEAN_MOTION")
        XCTAssertEqual(outOfRange(issLine1, Support.replacing(issLine2, 52, 63, with: "100.00000000")), "MEAN_MOTION")
        // Day 400 does not exist; 366 does not exist in 2026, but day 366.5 of 2024 does.
        XCTAssertEqual(outOfRange(Support.replacing(issLine1, 20, 32, with: "400.14461894"), issLine2), "EPOCH")
        XCTAssertEqual(outOfRange(Support.replacing(issLine1, 20, 32, with: "366.50000000"), issLine2), "EPOCH")
        XCTAssertEqual(outOfRange(Support.replacing(issLine1, 20, 32, with: "  0.50000000"), issLine2), "EPOCH")
        let leap = try parse(Support.withChecksum(Support.replacing(issLine1, 18, 32, with: "24366.50000000")), issLine2)
        let leapDate = civil(leap)
        XCTAssertEqual([leapDate.year, leapDate.month, leapDate.day], [2024, 12, 31])
        XCTAssertEqual(Int64(leap.epoch.timeIntervalSince1970) % 86_400, 43_200)
    }

    func testAlpha5CatalogNumbers() throws {
        func parsed(_ code: String) throws -> Int {
            let first = Support.withChecksum(Support.replacing(issLine1, 2, 7, with: code))
            let second = Support.withChecksum(Support.replacing(issLine2, 2, 7, with: code))
            return try parse(first, second).catalogNumber
        }
        XCTAssertEqual(try parsed("A0000"), 100_000)
        XCTAssertEqual(try parsed("A0001"), 100_001)
        XCTAssertEqual(try parsed("J0000"), 180_000)  // I is skipped: H = 17, J = 18
        XCTAssertEqual(try parsed("N1234"), 221_234)  // N = 22
        XCTAssertEqual(try parsed("P0000"), 230_000)  // O is skipped: P = 23
        XCTAssertEqual(try parsed("Z9999"), 339_999)
        XCTAssertEqual(try parsed("99999"), 99_999)
        for invalid in ["I0000", "O0000", "A00x0", "a0000", "AB000"] {
            XCTAssertThrowsError(try parsed(invalid), invalid) { error in
                guard case ElementSetError.invalidField(let field, _) = error else { return XCTFail("\(error)") }
                XCTAssertEqual(field, "NORAD_CAT_ID", invalid)
            }
        }
    }

    func testBlankOptionalFieldsAreAccepted() throws {
        // SGP4-VER.TLE 88888 (Original STR#3 SGP4 test): no designator, no revolution number.
        let elements = try parse(
            "1 88888U          80275.98708465  .00073094  13844-3  66816-4 0    87",
            "2 88888  72.8435 115.9689 0086731  52.6988 110.5714 16.05824518  1058"
        )
        XCTAssertNil(elements.objectId)
        XCTAssertNil(elements.name)
        XCTAssertEqual(elements.catalogNumber, 88888)
        XCTAssertEqual(elements.elementSetNumber, 8)
        XCTAssertEqual(elements.revolutionNumberAtEpoch, 105)
        XCTAssertEqual(elements.meanMotionDdot, 0.13844e-3, accuracy: 1e-15)
        XCTAssertEqual(elements.bstar, 0.66816e-4, accuracy: 1e-15)
        XCTAssertEqual(civil(elements).year, 1980)
    }

    func testNamesAreCleaned() throws {
        XCTAssertEqual(try parse(issLine1, issLine2, name: "0 ISS (ZARYA)   ").name, "ISS (ZARYA)")
        XCTAssertEqual(try parse(issLine1, issLine2, name: " \u{01}A\u{07} B\n").name, "A B")
        XCTAssertNil(try parse(issLine1, issLine2, name: "   ").name)
        XCTAssertEqual(try parse(issLine1, issLine2, name: String(repeating: "X", count: 200)).name?.utf16.count, 80)
    }

    // MARK: Batches of two-line sets

    func testParsesTheStationsListInThreeLineFormat() throws {
        let batch = try ElementSetParser.parseTwoLineText(Support.fixtureText("satellite_stations.tle"))
        XCTAssertEqual(batch.skippedCount, 0)
        XCTAssertEqual(batch.elements.count, 17)  // four of the 21 stations have catalog numbers above 99999
        XCTAssertEqual(batch.elements[0].name, "ISS (ZARYA)")
        XCTAssertEqual(batch.elements[0].catalogNumber, 25544)
        XCTAssertEqual(batch.elements[1].name, "POISK")
        XCTAssertEqual(batch.elements[2].name, "CSS (TIANHE)")
        XCTAssertTrue(batch.elements.allSatisfy { $0.name != nil })
    }

    func testTwoLineFormatWithoutNamesAndWithWindowsLineEnds() throws {
        let text = "\(issLine1)\r\n\(issLine2)\r\n\r\n\(issLine1)\r\n\(issLine2)\r\n"
        let batch = try ElementSetParser.parseTwoLineText(text)
        XCTAssertEqual(batch.elements.count, 2)
        XCTAssertNil(batch.elements[0].name)
        XCTAssertEqual(batch.skippedCount, 0)
        XCTAssertTrue(try ElementSetParser.parseTwoLineText("").elements.isEmpty)
        XCTAssertTrue(try ElementSetParser.parseTwoLineText("\n\n  \nnothing here\n").elements.isEmpty)
    }

    func testBadRecordsAreSkippedAndReported() throws {
        let corrupted = issLine1.replacingOccurrences(of: ".00007503", with: ".00007603")
        var text = ""
        text += "GOOD ONE\n\(issLine1)\n\(issLine2)\n"
        text += "BAD CHECKSUM\n\(corrupted)\n\(issLine2)\n"
        text += "ORPHAN SECOND LINE\n\(issLine2)\n"
        text += "ORPHAN FIRST LINE\n\(issLine1)\n"
        text += "0 SPACE-TRACK STYLE\n\(issLine1)\n\(issLine2)\n"
        let batch = try ElementSetParser.parseTwoLineText(text)
        XCTAssertEqual(batch.elements.map(\.name), ["GOOD ONE", "SPACE-TRACK STYLE"])
        XCTAssertEqual(batch.skippedCount, 3)
        XCTAssertEqual(batch.skipped.map(\.index), [1, 2, 3])
        XCTAssertEqual(batch.skipped[0].error, .checksumMismatch(line: 1, expected: 5, found: 4))
        XCTAssertEqual(batch.skipped[0].name, "BAD CHECKSUM")
        XCTAssertEqual(batch.skipped[1].error, .unexpectedLineNumber(line: 1))
        XCTAssertEqual(batch.skipped[2].error, .unexpectedLineNumber(line: 2))
    }

    func testSkippedRecordsAreCappedInTheReport() throws {
        let bad = issLine1.replacingOccurrences(of: ".00007503", with: ".00007603")
        let text = String(repeating: "\(bad)\n\(issLine2)\n", count: ElementSetParser.maximumReportedSkips + 20)
        let batch = try ElementSetParser.parseTwoLineText(text)
        XCTAssertEqual(batch.skippedCount, ElementSetParser.maximumReportedSkips + 20)
        XCTAssertEqual(batch.skipped.count, ElementSetParser.maximumReportedSkips)
    }

    func testRefusesAnInputThatIsTooLarge() {
        let huge = String(repeating: " ", count: ElementSetParser.maximumInputCharacters + 1)
        XCTAssertEqual(
            failure { _ = try ElementSetParser.parseTwoLineText(huge) },
            .inputTooLarge(limit: ElementSetParser.maximumInputCharacters)
        )
        XCTAssertEqual(
            failure { _ = try ElementSetParser.parseJson(huge) },
            .inputTooLarge(limit: ElementSetParser.maximumInputCharacters)
        )
    }

    // MARK: OMM JSON

    func testParsesTheStationsListInJson() throws {
        let batch = try ElementSetParser.parseJson(Support.fixtureData("satellite_stations.json"))
        XCTAssertEqual(batch.skippedCount, 0)
        XCTAssertEqual(batch.elements.count, 21)
        let iss = batch.elements[0]
        XCTAssertEqual(iss.name, "ISS (ZARYA)")
        XCTAssertEqual(iss.objectId, "1998-067A")
        XCTAssertEqual(iss.catalogNumber, 25544)
        XCTAssertEqual(iss.epoch.timeIntervalSince1970, Support.issEpochUnixSeconds, accuracy: 1e-5)
        XCTAssertEqual(iss.meanMotion, 15.48918166, accuracy: 1e-12)
        XCTAssertEqual(iss.eccentricity, 0.00067803, accuracy: 1e-12)
        XCTAssertEqual(iss.bstar, 0.00014456442, accuracy: 1e-15)
        XCTAssertEqual(iss.meanMotionDot, 7.503e-5, accuracy: 1e-15)
        XCTAssertEqual(iss.revolutionNumberAtEpoch, 59081)
        XCTAssertEqual(batch.elements.map(\.catalogNumber).filter { $0 > 99_999 }, [100057, 100712, 100882, 101031])
        XCTAssertEqual(batch.latestPerObject().elements.count, batch.elements.count)
    }

    func testJsonAndTwoLineSetsDescribeTheSameOrbits() throws {
        var json: [Int: OrbitalElements] = [:]
        for element in try ElementSetParser.parseJson(Support.fixtureData("satellite_stations.json")).elements {
            json[element.catalogNumber] = element
        }
        let lines = try ElementSetParser.parseTwoLineText(Support.fixtureText("satellite_stations.tle")).elements
        XCTAssertEqual(lines.count, 17)
        for fromLines in lines {
            let fromJson = try XCTUnwrap(json[fromLines.catalogNumber])
            XCTAssertEqual(fromJson.epoch.timeIntervalSince1970, fromLines.epoch.timeIntervalSince1970, accuracy: 1e-3, "epoch of \(fromLines.catalogNumber)")
            XCTAssertEqual(fromJson.meanMotion, fromLines.meanMotion, accuracy: 1e-8)
            XCTAssertEqual(fromJson.eccentricity, fromLines.eccentricity, accuracy: 1e-7)
            XCTAssertEqual(fromJson.inclination, fromLines.inclination, accuracy: 1e-4)
            XCTAssertEqual(fromJson.rightAscensionOfAscendingNode, fromLines.rightAscensionOfAscendingNode, accuracy: 1e-4)
            XCTAssertEqual(fromJson.argumentOfPericenter, fromLines.argumentOfPericenter, accuracy: 1e-4)
            XCTAssertEqual(fromJson.meanAnomaly, fromLines.meanAnomaly, accuracy: 1e-4)
            XCTAssertEqual(fromJson.bstar, fromLines.bstar, accuracy: abs(fromJson.bstar) * 1e-4 + 1e-9)  // five significant digits
            XCTAssertEqual(fromJson.objectId, fromLines.objectId)
            XCTAssertEqual(fromJson.name, fromLines.name)
        }
    }

    private let sampleRecord = """
        {"OBJECT_NAME":"TEST SAT","OBJECT_ID":"2020-001A","EPOCH":"2026-10-18T03:28:15.076416","MEAN_MOTION":15.5,\
        "ECCENTRICITY":0.001,"INCLINATION":51.6,"RA_OF_ASC_NODE":10,"ARG_OF_PERICENTER":20,"MEAN_ANOMALY":30,\
        "EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":12345,"ELEMENT_SET_NO":7,"REV_AT_EPOCH":99,\
        "BSTAR":0.0001,"MEAN_MOTION_DOT":0.00001,"MEAN_MOTION_DDOT":0}
        """

    /// The sample record with members replaced by raw JSON text (`nil` renames the member so it is absent).
    private func record(_ replacing: [String: String?] = [:]) -> String {
        var text = sampleRecord
        for (key, value) in replacing {
            guard let range = text.range(of: "\"\(key)\":(\"[^\"]*\"|[^,}]+)", options: .regularExpression) else { continue }
            if let value {
                text.replaceSubrange(range, with: "\"\(key)\":\(value)")
            } else {
                text.replaceSubrange(range, with: "\"X_\(key)\":0")
            }
        }
        return text
    }

    func testJsonRecordWithEverythingAndOptionalFieldsOmitted() throws {
        let full = try XCTUnwrap(ElementSetParser.parseJson("[\(record())]").elements.first)
        XCTAssertEqual(full.name, "TEST SAT")
        XCTAssertEqual(full.catalogNumber, 12345)
        XCTAssertEqual(full.elementSetNumber, 7)
        XCTAssertEqual(full.revolutionNumberAtEpoch, 99)
        XCTAssertEqual(full.rightAscensionOfAscendingNode, 10.0, accuracy: 0.0)

        let minimal = """
            {"EPOCH":"2026-10-18T03:28:15","MEAN_MOTION":15.5,"ECCENTRICITY":0.001,"INCLINATION":51.6,\
            "RA_OF_ASC_NODE":10,"ARG_OF_PERICENTER":20,"MEAN_ANOMALY":30,"NORAD_CAT_ID":12345,"BSTAR":0.0001}
            """
        let element = try XCTUnwrap(ElementSetParser.parseJson(minimal).elements.first)
        XCTAssertNil(element.name)
        XCTAssertNil(element.objectId)
        XCTAssertEqual(element.classification, "U")
        XCTAssertEqual(element.elementSetNumber, 0)
        XCTAssertEqual(element.meanMotionDot, 0.0, accuracy: 0.0)
        XCTAssertEqual(element.epoch.timeIntervalSince1970, 1792294095.0, accuracy: 1e-6)
        XCTAssertEqual(try ElementSetParser.parseJson(record()).elements.first?.name, "TEST SAT")  // a single object, not an array
    }

    func testJsonNumbersMayBeStrings() throws {
        let text = record([
            "MEAN_MOTION": "\"15.5\"", "ECCENTRICITY": "\"1e-3\"", "NORAD_CAT_ID": "\"12345\"", "BSTAR": "\"-0.5e-4\"",
        ])
        let element = try XCTUnwrap(ElementSetParser.parseJson("[\(text)]").elements.first)
        XCTAssertEqual(element.meanMotion, 15.5, accuracy: 0.0)
        XCTAssertEqual(element.eccentricity, 0.001, accuracy: 0.0)
        XCTAssertEqual(element.catalogNumber, 12345)
        XCTAssertEqual(element.bstar, -0.5e-4, accuracy: 0.0)
        // Strings that are not JSON numbers are refused.
        for bad in ["\"15,5\"", "\"0x10\"", "\"NaN\"", "\"\"", "\"+15\"", "\".5\"", "\"1.\"", "\"015\""] {
            let batch = try ElementSetParser.parseJson("[\(record(["MEAN_MOTION": bad]))]")
            XCTAssertEqual(batch.skippedCount, 1, bad)
            guard case .invalidField(let field, _)? = batch.skipped.first?.error else { return XCTFail(bad) }
            XCTAssertEqual(field, "MEAN_MOTION", bad)
        }
    }

    func testJsonRecordsWithProblemsAreSkipped() throws {
        let records = [
            record(),  // 0 good
            record(["EPOCH": nil]),  // 1 missing EPOCH
            record(["EPOCH": "\"2026-13-18T03:28:15\""]),  // 2 month 13
            record(["EPOCH": "\"yesterday\""]),  // 3
            record(["MEAN_MOTION": "-1"]),  // 4 out of range
            record(["INCLINATION": "true"]),  // 5 wrong type
            record(["NORAD_CAT_ID": "12.5"]),  // 6 not an integer
            record(["ECCENTRICITY": "1"]),  // 7 eccentricity 1
            record(["CLASSIFICATION_TYPE": "\"UU\""]),  // 8
            "42",  // 9 not an object
            "null",  // 10
            record(["BSTAR": "[1]"]),  // 11 array
            record(["OBJECT_NAME": "7"]),  // 12 name is not a string
            record(["MEAN_ANOMALY": "1e999"]),  // 13 not finite
            record(["NORAD_CAT_ID": "null"]),  // 14 null counts as missing
            record(),  // 15 good
        ]
        let batch = try ElementSetParser.parseJson("[\(records.joined(separator: ","))]")
        XCTAssertEqual(batch.elements.count, 2)
        XCTAssertEqual(batch.skippedCount, 14)
        XCTAssertEqual(batch.skipped.map(\.index), Array(1...14))
        XCTAssertEqual(batch.skipped[0].error, .missingField(field: "EPOCH"))
        XCTAssertEqual(batch.skipped[1].error, .valueOutOfRange(field: "EPOCH", value: 13.0))
        XCTAssertEqual(batch.skipped[2].error, .invalidField(field: "EPOCH", text: "yesterday"))
        XCTAssertEqual(batch.skipped[3].error, .valueOutOfRange(field: "MEAN_MOTION", value: -1.0))
        XCTAssertEqual(batch.skipped[4].error, .invalidField(field: "INCLINATION", text: "true"))
        XCTAssertEqual(batch.skipped[5].error, .valueOutOfRange(field: "NORAD_CAT_ID", value: 12.5))
        XCTAssertEqual(batch.skipped[6].error, .valueOutOfRange(field: "ECCENTRICITY", value: 1.0))
        XCTAssertEqual(batch.skipped[7].error, .invalidField(field: "CLASSIFICATION_TYPE", text: "UU"))
        guard case .invalidRecord = batch.skipped[8].error else { return XCTFail("record 9") }
        guard case .invalidRecord = batch.skipped[9].error else { return XCTFail("record 10") }
        guard case .invalidField(let bstarField, _) = batch.skipped[10].error else { return XCTFail("record 11") }
        XCTAssertEqual(bstarField, "BSTAR")
        guard case .invalidField = batch.skipped[11].error else { return XCTFail("record 12") }
        guard case .invalidField(let anomalyField, _) = batch.skipped[12].error else { return XCTFail("record 13") }
        XCTAssertEqual(anomalyField, "MEAN_ANOMALY")
        XCTAssertEqual(batch.skipped[13].error, .missingField(field: "NORAD_CAT_ID"))
    }

    func testJsonEpochSpellings() throws {
        func epoch(_ text: String) throws -> Double {
            try XCTUnwrap(ElementSetParser.parseJson("[\(record(["EPOCH": "\"\(text)\""]))]").elements.first).epoch.timeIntervalSince1970
        }
        let base = 1792294095.0
        XCTAssertEqual(try epoch("2026-10-18T03:28:15"), base, accuracy: 1e-6)
        XCTAssertEqual(try epoch("2026-10-18T03:28:15Z"), base, accuracy: 1e-6)
        XCTAssertEqual(try epoch("2026-10-18T03:28:15.5"), base + 0.5, accuracy: 1e-6)
        XCTAssertEqual(try epoch("2026-10-18 03:28:15.076416+00:00"), base + 0.076416, accuracy: 1e-6)
        XCTAssertEqual(try epoch("2026-10-18T03:28:15.123456789"), base + 0.123456789, accuracy: 1e-6)
        for bad in ["2026-10-18", "2026-10-18T03:28", "2026-10-18T03:28:15.", "2026-10-18T03:28:15+02:00", "2026-02-30T00:00:00", "2026-10-18T24:00:00", "2026-10-18T03:28:60"] {
            let batch = try ElementSetParser.parseJson("[\(record(["EPOCH": "\"\(bad)\""]))]")
            XCTAssertEqual(batch.skippedCount, 1, bad)
        }
    }

    func testMalformedJsonIsAnError() throws {
        for text in ["", "   ", "[{", "[1,2", "\"text\"", "42", "null", "{\"a\":", "[{\"EPOCH\":}]"] {
            guard case .malformedJSON? = failure({ _ = try ElementSetParser.parseJson(text) }) else {
                return XCTFail("\(text) should be malformed")
            }
        }
        XCTAssertEqual(try ElementSetParser.parseJson("[]").elements.count, 0)
        XCTAssertEqual(try ElementSetParser.parseJson("[]").skippedCount, 0)
        XCTAssertEqual(try ElementSetParser.parseJson("{}").skippedCount, 1)
    }

    func testLatestPerObjectKeepsTheNewestEpoch() throws {
        let older = record(["EPOCH": "\"2026-10-17T03:28:15\""])
        let newer = record(["EPOCH": "\"2026-10-19T03:28:15\"", "MEAN_ANOMALY": "99"])
        let other = record(["NORAD_CAT_ID": "777"])
        let batch = try ElementSetParser.parseJson("[\(older),\(other),\(newer),\(older)]").latestPerObject()
        XCTAssertEqual(batch.elements.map(\.catalogNumber), [12345, 777])
        XCTAssertEqual(batch.elements[0].meanAnomaly, 99.0, accuracy: 0.0)
    }

    func testGroupMetadata() throws {
        XCTAssertEqual(ElementSetGroup.stations.query, "GROUP=stations&FORMAT=json")
        XCTAssertEqual(ElementSetGroup(rawValue: "starlink"), .starlink)
        XCTAssertNil(ElementSetGroup(rawValue: "unknown"))
        let iss = try Support.iss()
        let epoch = Support.issEpochUnixSeconds
        XCTAssertTrue(ElementSetGroup.stations.isFresh(iss, at: Support.date(epoch + 2 * 86_400)))
        XCTAssertFalse(ElementSetGroup.stations.isFresh(iss, at: Support.date(epoch + 4 * 86_400)))
        XCTAssertEqual(abs(iss.ageDays(Support.date(epoch + 2 * 86_400))), 2.0, accuracy: 1e-9)
        XCTAssertEqual(iss.ageDays(Support.date(epoch - 86_400)), -1.0, accuracy: 1e-9)
    }
}

import XCTest
@testable import LodestarKit

/// Parsers for the MPC comet file, the MPC one-line minor-planet format, the packed designations and the JPL
/// Small-Body Database JSON. Expected Julian Days were computed with Python's `datetime` (JD of 2000-01-01 0h = 2451544.5).
final class CometsParsingTests: XCTestCase {
    private func comet(_ line: String) throws -> SmallBody { try CometElementsParser.parseLine(line) }

    private func error(_ body: () throws -> Any, file: StaticString = #filePath, line: UInt = #line) -> SmallBodyParseError? {
        do {
            _ = try body()
            XCTFail("expected an error", file: file, line: line)
        } catch let error as SmallBodyParseError {
            return error
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
        return nil
    }

    private func cometError(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> SmallBodyParseError? {
        error({ try CometElementsParser.parseLine(text) }, file: file, line: line)
    }

    private func asteroidError(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> SmallBodyParseError? {
        error({ try MinorPlanetElementsParser.parseLine(text) }, file: file, line: line)
    }

    private func jsonError(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> SmallBodyParseError? {
        error({ try SmallBodyJSONParser.parse(text) }, file: file, line: line)
    }

    /// `line` with the characters of columns `first`...`last` (1-based) replaced by `text`, padded with spaces.
    private func replacing(_ line: String, _ first: Int, _ last: Int, _ text: String) -> String {
        let width = last - first + 1
        let scalars = Array(line.unicodeScalars)
        var padded = Array(text.unicodeScalars)
        while padded.count < width { padded.append(" ") }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[0..<(first - 1)])
        result.append(contentsOf: padded[0..<width])
        result.append(contentsOf: scalars[last...])
        return String(result)
    }

    private func cometMagnitudes(_ body: SmallBody) throws -> CometMagnitudes {
        guard case .comet(let magnitudes)? = body.photometry else {
            XCTFail("expected comet photometry")
            throw SmallBodyParseError.missingField(.absoluteMagnitude)
        }
        return magnitudes
    }

    private func asteroidMagnitudes(_ body: SmallBody) throws -> AsteroidMagnitudes {
        guard case .asteroid(let magnitudes)? = body.photometry else {
            XCTFail("expected asteroid photometry")
            throw SmallBodyParseError.missingField(.absoluteMagnitude)
        }
        return magnitudes
    }

    // MARK: MPC comets

    func testParsesHaleBopp() throws {
        let body = try comet(CometsTestData.cometHaleBopp)
        XCTAssertEqual(body.id, "comet.C/1995 O1")
        XCTAssertEqual(body.designation, "C/1995 O1")
        XCTAssertEqual(body.name, "Hale-Bopp")
        XCTAssertEqual(body.title, "C/1995 O1 (Hale-Bopp)")
        XCTAssertEqual(body.kind, .comet)
        XCTAssertNil(body.number)
        let orbit = body.orbit
        XCTAssertEqual(orbit.perihelionDistanceAU, 0.925_995)
        XCTAssertEqual(orbit.eccentricity, 0.994_895)
        XCTAssertEqual(orbit.argumentOfPerihelion, 130.7313)
        XCTAssertEqual(orbit.longitudeOfAscendingNode, 281.8097)
        XCTAssertEqual(orbit.inclination, 89.7335)
        XCTAssertEqual(orbit.perihelionJulianDayTT, 2_450_536.5284, accuracy: 1e-6)
        XCTAssertEqual(orbit.epochJulianDayTT, 2_461_330.5)
        XCTAssertEqual(orbit.shape, .elliptic)
        XCTAssertEqual(try cometMagnitudes(body).totalMagnitude, -2.0)
        XCTAssertEqual(try cometMagnitudes(body).totalSlope, 10.0)
        XCTAssertNil(try cometMagnitudes(body).nuclearMagnitude)
    }

    func testParsesNumberedPeriodicComets() throws {
        let body = try comet(CometsTestData.cometPonsBrooks)
        XCTAssertEqual(body.id, "comet.12P")
        XCTAssertEqual(body.designation, "12P")
        XCTAssertEqual(body.name, "Pons-Brooks")
        XCTAssertEqual(body.title, "12P/Pons-Brooks")
        XCTAssertEqual(body.number, 12)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_460_421.7066, accuracy: 1e-6)
        XCTAssertEqual(try cometMagnitudes(body).totalMagnitude, 5.0)
        XCTAssertEqual(try cometMagnitudes(body).totalSlope, 15.0) // slope parameter k = 6.0, K1 = 2.5 k

        let halley = try comet(CometsTestData.cometHalley)
        XCTAssertEqual(halley.designation, "1P")
        XCTAssertEqual(halley.number, 1)
        XCTAssertEqual(halley.orbit.perihelionJulianDayTT, 2_474_038.0218, accuracy: 1e-6) // 2061 Aug 1.5218, day padded with a blank
        XCTAssertEqual(try cometMagnitudes(halley).totalSlope, 8.0)
        XCTAssertEqual(halley.orbit.eccentricity, 0.968_030)
        XCTAssertEqual(halley.orbit.inclination, 162.1917)

        let encke = try comet(CometsTestData.cometEncke)
        XCTAssertEqual(encke.title, "2P/Encke")
        XCTAssertEqual(try cometMagnitudes(encke).totalMagnitude, 14.4)
    }

    func testParsesFragmentsOfSplitComets() throws {
        let biela = try comet(CometsTestData.cometBielaA)
        XCTAssertEqual(biela.designation, "3D-A")
        XCTAssertEqual(biela.name, "Biela")
        XCTAssertEqual(biela.number, 3)
        XCTAssertEqual(biela.title, "3D-A/Biela")
        XCTAssertEqual(biela.id, "comet.3D-A")
        XCTAssertEqual(biela.orbit.perihelionJulianDayTT, 2_460_646.6425, accuracy: 1e-6)

        let wachmann = try comet(CometsTestData.cometSchwassmannWachmann3Bt)
        XCTAssertEqual(wachmann.designation, "73P-BT")
        XCTAssertEqual(wachmann.number, 73)
        XCTAssertEqual(wachmann.name, "Schwassmann-Wachmann")
    }

    func testParsesAnUnnumberedCometWithoutAName() throws {
        let body = try comet(CometsTestData.cometUnnamedPeriodic)
        XCTAssertEqual(body.designation, "P/2026 N2")
        XCTAssertEqual(body.name, "")
        XCTAssertEqual(body.title, "P/2026 N2")
        XCTAssertEqual(body.displayName, "P/2026 N2")
        XCTAssertNil(body.number)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_461_309.2701, accuracy: 1e-6)
    }

    func testParsesHyperbolicAndInterstellarComets() throws {
        let atlas = try comet(CometsTestData.cometTsuchinshanAtlas)
        XCTAssertEqual(atlas.designation, "C/2023 A3")
        XCTAssertEqual(atlas.name, "Tsuchinshan-ATLAS")
        XCTAssertEqual(atlas.orbit.shape, .hyperbolic)
        XCTAssertEqual(atlas.orbit.eccentricity, 1.000_180)
        XCTAssertEqual(atlas.orbit.perihelionJulianDayTT, 2_460_581.3337, accuracy: 1e-6)
        XCTAssertEqual(try cometMagnitudes(atlas).totalMagnitude, 6.5)
        XCTAssertEqual(try cometMagnitudes(atlas).totalSlope, 8.0) // k = 3.2

        let oumuamua = try comet(CometsTestData.cometOumuamua)
        XCTAssertEqual(oumuamua.designation, "1I")
        XCTAssertEqual(oumuamua.name, "`Oumuamua")
        XCTAssertEqual(oumuamua.number, 1)
        XCTAssertEqual(oumuamua.orbit.eccentricity, 1.199_252)
        XCTAssertEqual(oumuamua.orbit.perihelionJulianDayTT, 2_458_005.9886, accuracy: 1e-6)
        XCTAssertEqual(oumuamua.orbit.epochJulianDayTT, 2_458_000.5)
        XCTAssertEqual(try cometMagnitudes(oumuamua).totalMagnitude, 23.0)
        XCTAssertEqual(try cometMagnitudes(oumuamua).totalSlope, 5.0)

        let borisov = try comet(CometsTestData.cometBorisov)
        XCTAssertEqual(borisov.title, "2I/Borisov")
        XCTAssertEqual(borisov.orbit.eccentricity, 3.345_952)

        let threeI = try comet(CometsTestData.cometAtlas3i)
        XCTAssertEqual(threeI.designation, "3I")
        XCTAssertEqual(threeI.orbit.eccentricity, 6.139_884)
        XCTAssertEqual(threeI.orbit.perihelionJulianDayTT, 2_460_977.9825, accuracy: 1e-6)
        XCTAssertEqual(threeI.orbit.epochJulianDayTT, 2_461_000.5)

        XCTAssertEqual(try comet(CometsTestData.cometSidingSpring).orbit.shape, .hyperbolic)
    }

    func testParsesLinesWithFewerDecimals() throws {
        // 18D/Perrine-Mrkos is printed with three decimals in the angles and five in q and e.
        let body = try comet(CometsTestData.cometPerrineMrkos)
        XCTAssertEqual(body.designation, "18D")
        XCTAssertEqual(body.orbit.perihelionDistanceAU, 1.59239)
        XCTAssertEqual(body.orbit.eccentricity, 0.58937)
        XCTAssertEqual(body.orbit.argumentOfPerihelion, 238.150)
        XCTAssertEqual(body.orbit.longitudeOfAscendingNode, 158.452)
        XCTAssertEqual(body.orbit.inclination, 17.664)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_460_551.412, accuracy: 1e-6)
    }

    func testAMissingEpochDefaultsToThePerihelionTime() throws {
        let body = try comet(CometsTestData.cometIkeyaMurakamiB)
        XCTAssertEqual(body.designation, "332P-B")
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_457_464.665, accuracy: 1e-6)
        XCTAssertEqual(body.orbit.epochJulianDayTT, body.orbit.perihelionJulianDayTT)
        XCTAssertEqual(try cometMagnitudes(body).totalMagnitude, 19.0)
    }

    func testOrbitTypeAMakesAnAsteroid() throws {
        let body = try comet(CometsTestData.cometAsteroidLike)
        XCTAssertEqual(body.kind, .asteroid)
        XCTAssertEqual(body.id, "asteroid.A/2018 W3")
        XCTAssertEqual(body.designation, "A/2018 W3")
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_459_317.679, accuracy: 1e-6)
        XCTAssertEqual(try cometMagnitudes(body).totalSlope, 5.0) // k = 2.0
    }

    func testCometNameFormsAreSplit() {
        func parts(_ title: String) -> [String] {
            let split = SmallBodyNaming.cometParts(title)
            return [split.designation, split.name]
        }
        XCTAssertEqual(parts("12P/Pons-Brooks"), ["12P", "Pons-Brooks"])
        XCTAssertEqual(parts("73P-B/Schwassmann-Wachmann 3"), ["73P-B", "Schwassmann-Wachmann 3"])
        XCTAssertEqual(parts("C/2023 A3 (Tsuchinshan-ATLAS)"), ["C/2023 A3", "Tsuchinshan-ATLAS"])
        XCTAssertEqual(parts("D/1993 F2-A (Shoemaker-Levy 9)"), ["D/1993 F2-A", "Shoemaker-Levy 9"])
        XCTAssertEqual(parts("P/2026 N2"), ["P/2026 N2", ""])
        XCTAssertEqual(parts("C/2010 X1 (Elenin (LINEAR (A)))"), ["C/2010 X1", "Elenin (LINEAR (A))"])
        XCTAssertEqual(parts("1I/`Oumuamua"), ["1I", "`Oumuamua"])
        XCTAssertEqual(parts("Strange"), ["Strange", ""])
        XCTAssertEqual(parts("(only)"), ["(only)", ""])
        XCTAssertEqual(parts("X/1 (a)"), ["X/1", "a"])
        XCTAssertEqual(SmallBodyNaming.cometNumber("12P"), 12)
        XCTAssertEqual(SmallBodyNaming.cometNumber("73P-B"), 73)
        XCTAssertEqual(SmallBodyNaming.cometNumber("1I"), 1)
        XCTAssertNil(SmallBodyNaming.cometNumber("C/2023 A3"))
        XCTAssertNil(SmallBodyNaming.cometNumber("1995 O1"))
        XCTAssertNil(SmallBodyNaming.cometNumber("12"))
        XCTAssertNil(SmallBodyNaming.cometNumber("12Z"))
        XCTAssertNil(SmallBodyNaming.cometNumber("12Px"))
        XCTAssertNil(SmallBodyNaming.cometNumber("0P"))
    }

    func testDesignationFallsBackToThePackedColumns() throws {
        // Without the name columns the designation is built from the number, type and packed designation.
        let numbered = replacing(CometsTestData.cometPonsBrooks, 103, 168, "")
        XCTAssertEqual(try comet(numbered).designation, "12P")
        let fragment = replacing(CometsTestData.cometBielaA, 103, 168, "")
        XCTAssertEqual(try comet(fragment).designation, "3D-A")
        let provisional = replacing(CometsTestData.cometHaleBopp, 103, 168, "")
        XCTAssertEqual(try comet(provisional).designation, "C/1995 O1")
        XCTAssertEqual(try comet(provisional).id, "comet.C/1995 O1")
        let periodic = replacing(CometsTestData.cometUnnamedPeriodic, 103, 168, "")
        XCTAssertEqual(try comet(periodic).designation, "P/2026 N2")
        XCTAssertEqual(cometError(replacing(replacing(CometsTestData.cometHaleBopp, 103, 168, ""), 6, 12, "J95O0")),
                       .invalidDesignation(text: "J95O0"))
        XCTAssertEqual(cometError(replacing(replacing(CometsTestData.cometHaleBopp, 103, 168, ""), 6, 12, "")),
                       .invalidDesignation(text: ""))
    }

    func testCometLineErrorsAreTyped() {
        let good = CometsTestData.cometPonsBrooks
        XCTAssertEqual(cometError("0012P     "), .lineTooShort(length: 10, minimum: 79))
        XCTAssertEqual(cometError(""), .lineTooShort(length: 0, minimum: 79))
        XCTAssertEqual(cometError(good + String(repeating: "x", count: 401 - good.count)), .lineTooLong(length: 401, maximum: 400))
        XCTAssertEqual(cometError(replacing(good, 5, 5, "")), .missingField(.orbitType))
        XCTAssertEqual(cometError(replacing(good, 5, 5, "Z")), .malformedField(.orbitType, text: "Z"))
        XCTAssertEqual(cometError(replacing(good, 1, 4, "00x2")), .malformedField(.cometNumber, text: "00x2"))
        XCTAssertEqual(cometError(replacing(good, 1, 4, "0000")), .malformedField(.cometNumber, text: "0000"))
        XCTAssertEqual(cometError(replacing(good, 15, 18, "")), .missingField(.perihelionYear))
        XCTAssertEqual(cometError(replacing(good, 15, 18, "20x4")), .malformedField(.perihelionYear, text: "20x4"))
        XCTAssertEqual(cometError(replacing(good, 15, 18, "1500")), .fieldOutOfRange(.perihelionYear, value: 1500.0))
        XCTAssertEqual(cometError(replacing(good, 20, 21, "13")), .fieldOutOfRange(.perihelionMonth, value: 13.0))
        XCTAssertEqual(cometError(replacing(good, 20, 21, " 0")), .fieldOutOfRange(.perihelionMonth, value: 0.0))
        XCTAssertEqual(cometError(replacing(good, 23, 29, "2x.2066")), .malformedField(.perihelionDay, text: "2x.2066"))
        XCTAssertEqual(cometError(replacing(good, 23, 29, "32.0000")), .fieldOutOfRange(.perihelionDay, value: 32.0))
        XCTAssertEqual(cometError(replacing(good, 23, 29, "-1.0000")), .fieldOutOfRange(.perihelionDay, value: -1.0))
        XCTAssertEqual(cometError(replacing(good, 31, 39, "")), .missingField(.perihelionDistance))
        XCTAssertEqual(cometError(replacing(good, 31, 39, "-0.5")), .fieldOutOfRange(.perihelionDistance, value: -0.5))
        XCTAssertEqual(cometError(replacing(good, 31, 39, "NaN")), .malformedField(.perihelionDistance, text: "NaN"))
        XCTAssertEqual(cometError(replacing(good, 42, 49, "1e0")), .malformedField(.eccentricity, text: "1e0"))
        XCTAssertEqual(cometError(replacing(good, 42, 49, "0x1p-1")), .malformedField(.eccentricity, text: "0x1p-1"))
        XCTAssertEqual(cometError(replacing(good, 42, 49, "-0.1")), .fieldOutOfRange(.eccentricity, value: -0.1))
        XCTAssertEqual(cometError(replacing(good, 52, 59, "400.0")), .fieldOutOfRange(.argumentOfPerihelion, value: 400.0))
        XCTAssertEqual(cometError(replacing(good, 62, 69, "-1.0")), .fieldOutOfRange(.longitudeOfAscendingNode, value: -1.0))
        XCTAssertEqual(cometError(replacing(good, 72, 79, "181.0")), .fieldOutOfRange(.inclination, value: 181.0))
        XCTAssertEqual(cometError(replacing(good, 72, 79, "1 8")), .malformedField(.inclination, text: "1 8"))
        XCTAssertEqual(cometError(replacing(good, 82, 89, "2026101")), .malformedField(.epoch, text: "2026101"))
        XCTAssertEqual(cometError(replacing(good, 82, 89, "20261340")), .malformedField(.epoch, text: "20261340"))
        XCTAssertEqual(cometError(replacing(good, 82, 89, "20260230")), .malformedField(.epoch, text: "20260230"))
        XCTAssertEqual(cometError(replacing(good, 82, 89, "2026-1-7")), .malformedField(.epoch, text: "2026-1-7"))
        XCTAssertEqual(cometError(replacing(good, 92, 95, "abc")), .malformedField(.absoluteMagnitude, text: "abc"))
        XCTAssertEqual(cometError(replacing(good, 92, 95, "41.0")), .fieldOutOfRange(.absoluteMagnitude, value: 41.0))
        XCTAssertEqual(cometError(replacing(good, 97, 100, "x")), .malformedField(.slopeParameter, text: "x"))
        XCTAssertEqual(cometError(replacing(good, 97, 100, "30.0")), .fieldOutOfRange(.slopeParameter, value: 30.0))
        XCTAssertEqual(cometError(replacing(good, 97, 100, "-1.0")), .fieldOutOfRange(.slopeParameter, value: -1.0))
    }

    func testCometPhotometryIsOptionalAndDefaultsTheSlope() throws {
        let good = CometsTestData.cometPonsBrooks
        XCTAssertNil(try comet(replacing(good, 92, 100, "")).photometry)
        let noSlope = try comet(replacing(good, 97, 100, ""))
        XCTAssertEqual(try cometMagnitudes(noSlope).totalMagnitude, 5.0)
        XCTAssertEqual(try cometMagnitudes(noSlope).totalSlope, 10.0)
        XCTAssertEqual(CometElementsParser.defaultSlopeParameter, 4.0)
        // A slope without an absolute magnitude is validated but gives no photometry.
        XCTAssertNil(try comet(replacing(good, 92, 95, "")).photometry)
        // The line may stop after the inclination.
        let truncated = String(good.prefix(79))
        let body = try comet(truncated)
        XCTAssertEqual(body.designation, "12P")
        XCTAssertNil(body.photometry)
    }

    func testCometFileIsReadLeniently() throws {
        let lines = [
            CometsTestData.cometPonsBrooks,
            "",
            "   ",
            "this is not a comet line at all, but it is long enough to be examined by the column reader of the parser ok",
            CometsTestData.cometHaleBopp,
            replacing(CometsTestData.cometEncke, 42, 49, "abc"),
            CometsTestData.cometPonsBrooks,
            "short",
            CometsTestData.cometHalley,
        ]
        let result = try CometElementsParser.parse(lines.joined(separator: "\r\n") + "\r\n")
        XCTAssertEqual(result.bodies.map(\.id), ["comet.12P", "comet.C/1995 O1", "comet.1P"])
        XCTAssertEqual(result.rejectedLineCount, 4)
        XCTAssertEqual(result.rejections.map(\.lineNumber), [4, 6, 7, 8])
        XCTAssertEqual(result.rejections[0].error, .malformedField(.cometNumber, text: "this"))
        XCTAssertEqual(result.rejections[1].error, .malformedField(.eccentricity, text: "abc"))
        XCTAssertEqual(result.rejections[2].error, .duplicateObject(id: "comet.12P"))
        XCTAssertEqual(result.rejections[3].error, .lineTooShort(length: 5, minimum: 79))
    }

    func testFileWithoutTrailingNewlineAndWithLfOnly() throws {
        let text = CometsTestData.cometPonsBrooks + "\n" + CometsTestData.cometHalley
        let result = try CometElementsParser.parse(text)
        XCTAssertEqual(result.bodies.count, 2)
        XCTAssertEqual(result.rejectedLineCount, 0)
        XCTAssertTrue(result.rejections.isEmpty)
        XCTAssertEqual(try CometElementsParser.parse("").bodies.count, 0)
        XCTAssertEqual(try CometElementsParser.parse("\n\n  \n").rejectedLineCount, 0)
    }

    func testOnlyTheFirstRejectionsAreReported() throws {
        let text = (1...80).map { _ in "x" }.joined(separator: "\n")
        let result = try CometElementsParser.parse(text)
        XCTAssertEqual(result.rejectedLineCount, 80)
        XCTAssertEqual(result.rejections.count, SmallBodyParseResult.maximumReportedRejections)
        XCTAssertEqual(result.rejections.count, 50)
        XCTAssertEqual(result.rejections.last?.lineNumber, 50)
    }

    func testOversizedInputIsRefused() {
        let huge = String(repeating: "x", count: SmallBodyBatch.maximumInputLength + 1)
        let expected = SmallBodyParseError.inputTooLarge(length: SmallBodyBatch.maximumInputLength + 1,
                                                         maximum: SmallBodyBatch.maximumInputLength)
        XCTAssertEqual(error({ try CometElementsParser.parse(huge) }), expected)
        XCTAssertEqual(error({ try MinorPlanetElementsParser.parse(huge) }), expected)
    }

    // MARK: MPC minor planets

    func testParsesCeresFromMPCORB() throws {
        let body = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidCeres)
        XCTAssertEqual(body.id, "asteroid.1")
        XCTAssertEqual(body.designation, "1")
        XCTAssertEqual(body.name, "Ceres")
        XCTAssertEqual(body.title, "(1) Ceres")
        XCTAssertEqual(body.number, 1)
        XCTAssertEqual(body.kind, .asteroid)
        let orbit = body.orbit
        XCTAssertEqual(orbit.perihelionDistanceAU, 2.7655526 * (1 - 0.0796923), accuracy: 1e-12)
        XCTAssertEqual(orbit.eccentricity, 0.0796923)
        XCTAssertEqual(orbit.argumentOfPerihelion, 73.29420)
        XCTAssertEqual(orbit.longitudeOfAscendingNode, 80.24863)
        XCTAssertEqual(orbit.inclination, 10.58803)
        XCTAssertEqual(orbit.epochJulianDayTT, 2_461_200.5) // K2669 = 2026 June 9
        XCTAssertEqual(try XCTUnwrap(orbit.meanAnomaly(at: 2_461_200.5)), 274.41935, accuracy: 1e-6)
        // JPL's time of perihelion for Ceres: JD 2461599.8415 (TDB).
        XCTAssertEqual(orbit.perihelionJulianDayTT, 2_461_599.8415, accuracy: 2e-3)
        XCTAssertEqual(try asteroidMagnitudes(body).absoluteMagnitude, 3.34)
        XCTAssertEqual(try asteroidMagnitudes(body).slopeParameter, 0.15)
    }

    func testParsesVestaFromMPCORB() throws {
        let body = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidVesta)
        XCTAssertEqual(body.title, "(4) Vesta")
        XCTAssertEqual(try asteroidMagnitudes(body).absoluteMagnitude, 3.25)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_460_901.5874, accuracy: 2e-3) // JPL: 2460901.58738
        XCTAssertEqual(try XCTUnwrap(body.orbit.semiMajorAxisAU), 2.3613660, accuracy: 1e-7)
        XCTAssertEqual(try XCTUnwrap(body.orbit.meanMotion), 0.27161836, accuracy: 1e-7)
    }

    func testParsesPackedNumbersAndNames() throws {
        let eros = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidEros)
        XCTAssertEqual(eros.number, 433)
        XCTAssertEqual(eros.name, "Eros")
        XCTAssertEqual(try asteroidMagnitudes(eros).absoluteMagnitude, 10.39)
        let apophis = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidApophis)
        XCTAssertEqual(apophis.number, 99942)
        XCTAssertEqual(apophis.name, "Apophis")
        XCTAssertEqual(apophis.title, "(99942) Apophis")
        let bennu = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidBennu)
        XCTAssertEqual(bennu.number, 101_955)
        XCTAssertEqual(bennu.name, "Bennu")
        XCTAssertEqual(bennu.id, "asteroid.101955")
        let unnamed = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidNumberedUnnamed)
        XCTAssertEqual(unnamed.number, 202_411)
        XCTAssertEqual(unnamed.name, "2005 RC")
        XCTAssertEqual(unnamed.title, "(202411) 2005 RC")
    }

    func testParsesProvisionalDesignations() throws {
        let yr4 = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidYr42024)
        XCTAssertEqual(yr4.designation, "2024 YR4")
        XCTAssertEqual(yr4.id, "asteroid.2024 YR4")
        XCTAssertEqual(yr4.title, "2024 YR4")
        XCTAssertNil(yr4.number)
        XCTAssertEqual(yr4.name, "")
        XCTAssertEqual(try asteroidMagnitudes(yr4).absoluteMagnitude, 23.93)
        XCTAssertEqual(yr4.orbit.eccentricity, 0.6613330)
        XCTAssertEqual(try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidYearEndEpochAa).designation, "2024 AA")
        let flagged = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidAssumedEccentricity)
        XCTAssertEqual(flagged.designation, "2006 WO130") // the cycle count 130 is packed as D0
        XCTAssertEqual(try asteroidMagnitudes(flagged).absoluteMagnitude, 26.1)
    }

    func testAnUnknownAbsoluteMagnitudeGivesNoPhotometry() throws {
        let body = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidUnknownH)
        XCTAssertEqual(body.designation, "1991 TT")
        XCTAssertNil(body.photometry) // the MPC writes 99.99
        XCTAssertNil(try MinorPlanetElementsParser.parseLine(replacing(CometsTestData.asteroidCeres, 9, 13, "")).photometry)
        let noSlope = try MinorPlanetElementsParser.parseLine(replacing(CometsTestData.asteroidCeres, 15, 19, ""))
        XCTAssertEqual(try asteroidMagnitudes(noSlope).slopeParameter, 0.15)
        XCTAssertEqual(MinorPlanetElementsParser.unknownMagnitude, 99.0)
    }

    func testAsteroidLineErrorsAreTyped() {
        let good = CometsTestData.asteroidCeres
        XCTAssertEqual(asteroidError("00001"), .lineTooShort(length: 5, minimum: 103))
        XCTAssertEqual(asteroidError(good + String(repeating: "x", count: 401 - good.count)), .lineTooLong(length: 401, maximum: 400))
        XCTAssertEqual(asteroidError(replacing(good, 21, 25, "")), .missingField(.epoch))
        XCTAssertEqual(asteroidError(replacing(good, 21, 25, "K2D69")), .malformedField(.epoch, text: "K2D69"))
        XCTAssertEqual(asteroidError(replacing(good, 21, 25, "K26W9")), .malformedField(.epoch, text: "K26W9"))
        XCTAssertEqual(asteroidError(replacing(good, 21, 25, "K2B31")), .malformedField(.epoch, text: "K2B31"))
        XCTAssertEqual(asteroidError(replacing(good, 21, 25, "X2669")), .malformedField(.epoch, text: "X2669"))
        XCTAssertEqual(asteroidError(replacing(good, 27, 35, "400.0")), .fieldOutOfRange(.meanAnomaly, value: 400.0))
        XCTAssertEqual(asteroidError(replacing(good, 27, 35, "")), .missingField(.meanAnomaly))
        XCTAssertEqual(asteroidError(replacing(good, 38, 46, "7x.2")), .malformedField(.argumentOfPerihelion, text: "7x.2"))
        XCTAssertEqual(asteroidError(replacing(good, 49, 57, "-2.0")), .fieldOutOfRange(.longitudeOfAscendingNode, value: -2.0))
        XCTAssertEqual(asteroidError(replacing(good, 60, 68, "190.0")), .fieldOutOfRange(.inclination, value: 190.0))
        XCTAssertEqual(asteroidError(replacing(good, 71, 79, "1.0")), .fieldOutOfRange(.eccentricity, value: 1.0))
        XCTAssertEqual(asteroidError(replacing(good, 71, 79, "-0.1")), .fieldOutOfRange(.eccentricity, value: -0.1))
        XCTAssertEqual(asteroidError(replacing(good, 81, 91, "0.0")), .fieldOutOfRange(.meanMotion, value: 0.0))
        XCTAssertEqual(asteroidError(replacing(good, 81, 91, "41.0")), .fieldOutOfRange(.meanMotion, value: 41.0))
        XCTAssertEqual(asteroidError(replacing(good, 93, 103, "0.0")), .fieldOutOfRange(.semiMajorAxis, value: 0.0))
        XCTAssertEqual(asteroidError(replacing(good, 93, 103, "")), .missingField(.semiMajorAxis))
        XCTAssertEqual(asteroidError(replacing(good, 9, 13, "3.x")), .malformedField(.absoluteMagnitude, text: "3.x"))
        XCTAssertEqual(asteroidError(replacing(good, 9, 13, "-9.0")), .fieldOutOfRange(.absoluteMagnitude, value: -9.0))
        XCTAssertEqual(asteroidError(replacing(good, 9, 13, "45.0")), .fieldOutOfRange(.absoluteMagnitude, value: 45.0))
        XCTAssertEqual(asteroidError(replacing(good, 15, 19, "0.1.5")), .malformedField(.slopeParameter, text: "0.1.5"))
        XCTAssertEqual(asteroidError(replacing(good, 15, 19, "1.5")), .fieldOutOfRange(.slopeParameter, value: 1.5))
        XCTAssertEqual(asteroidError(replacing(good, 1, 7, "")), .missingField(.packedDesignation))
        XCTAssertEqual(asteroidError(replacing(good, 1, 7, "0000")), .invalidDesignation(text: "0000"))
        XCTAssertEqual(asteroidError(replacing(good, 1, 7, "00000")), .invalidDesignation(text: "00000"))
        XCTAssertEqual(asteroidError(replacing(replacing(good, 1, 7, "Z24Y04R"), 167, 194, "")), .invalidDesignation(text: "Z24Y04R"))
    }

    func testMeanMotionMustAgreeWithTheSemiMajorAxis() throws {
        let good = CometsTestData.asteroidCeres
        let failure = asteroidError(replacing(good, 81, 91, "0.30000000"))
        if case .inconsistentElements? = failure {} else { XCTFail("\(String(describing: failure))") }
        // An error of less than one percent is accepted (the MPC rounds both numbers).
        _ = try MinorPlanetElementsParser.parseLine(replacing(good, 81, 91, "0.21500000"))
    }

    func testReadableDesignationIsOptional() throws {
        // Without the readable columns the number and provisional designation come from the packed columns alone.
        let noName = replacing(CometsTestData.asteroidVesta, 167, 202, "")
        let body = try MinorPlanetElementsParser.parseLine(noName)
        XCTAssertEqual(body.designation, "4")
        XCTAssertEqual(body.name, "")
        XCTAssertEqual(body.title, "(4)")
        let provisional = try MinorPlanetElementsParser.parseLine(replacing(CometsTestData.asteroidYr42024, 167, 202, ""))
        XCTAssertEqual(provisional.designation, "2024 YR4")
        // A readable designation that disagrees with the packed number gives no name.
        let mismatched = replacing(CometsTestData.asteroidVesta, 167, 194, "(5) Astraea")
        XCTAssertEqual(try MinorPlanetElementsParser.parseLine(mismatched).name, "")
        // The readable designation rescues a packed one that cannot be unpacked.
        let rescued = replacing(replacing(CometsTestData.asteroidYr42024, 1, 7, "K24Y0?R"), 167, 194, "2024 YR4")
        XCTAssertEqual(try MinorPlanetElementsParser.parseLine(rescued).designation, "2024 YR4")
    }

    func testMpcorbFileIsReadWithItsHeader() throws {
        let header = [
            "MINOR PLANET CENTER ORBIT DATABASE (MPCORB)",
            "",
            "Des'n     H     G   Epoch     M        Peri.      Node       Incl.       e            n           a        Reference #Obs #Opp    Arc    rms  Perts   Computer",
            "",
            String(repeating: "-", count: 160),
        ]
        let body = [
            CometsTestData.asteroidCeres,
            CometsTestData.asteroidVesta,
            "",
            CometsTestData.asteroidEros,
            replacing(CometsTestData.asteroidApophis, 71, 79, "1.5"),
            CometsTestData.asteroidCeres,
        ]
        let result = try MinorPlanetElementsParser.parse((header + body).joined(separator: "\n"))
        XCTAssertEqual(result.bodies.map(\.id), ["asteroid.1", "asteroid.4", "asteroid.433"])
        XCTAssertEqual(result.rejectedLineCount, 2)
        XCTAssertEqual(result.rejections.map(\.lineNumber), [10, 11])
        XCTAssertEqual(result.rejections[0].error, .fieldOutOfRange(.eccentricity, value: 1.5))
        XCTAssertEqual(result.rejections[1].error, .duplicateObject(id: "asteroid.1"))
    }

    func testFileWithoutAHeaderIsReadFromTheFirstLine() throws {
        let result = try MinorPlanetElementsParser.parse(CometsTestData.asteroidCeres + "\n" + CometsTestData.asteroidVesta)
        XCTAssertEqual(result.bodies.count, 2)
        XCTAssertEqual(result.rejectedLineCount, 0)
        // A short rule is not a header.
        let short = try MinorPlanetElementsParser.parse("-----\n" + CometsTestData.asteroidCeres)
        XCTAssertEqual(short.bodies.count, 1)
        XCTAssertEqual(short.rejectedLineCount, 1)
    }

    // MARK: Packed designations

    func testPackedMinorPlanetNumbers() {
        // Examples of https://www.minorplanetcenter.net/iau/info/PackedDes.html
        XCTAssertEqual(PackedDesignation.number("03202"), 3202)
        XCTAssertEqual(PackedDesignation.number("50000"), 50_000)
        XCTAssertEqual(PackedDesignation.number("A0345"), 100_345)
        XCTAssertEqual(PackedDesignation.number("a0017"), 360_017)
        XCTAssertEqual(PackedDesignation.number("K3289"), 203_289)
        XCTAssertEqual(PackedDesignation.number("~0000"), 620_000)
        XCTAssertEqual(PackedDesignation.number("~000z"), 620_061)
        XCTAssertEqual(PackedDesignation.number("~AZaz"), 3_140_113)
        XCTAssertEqual(PackedDesignation.number("~zzzz"), 15_396_335)
        XCTAssertNil(PackedDesignation.number("00000"))
        XCTAssertNil(PackedDesignation.number("0345"))
        XCTAssertNil(PackedDesignation.number("A03x5"))
        XCTAssertNil(PackedDesignation.number("~0 00"))
        XCTAssertNil(PackedDesignation.number("#0345"))
        XCTAssertNil(PackedDesignation.number(""))
    }

    func testPackedMinorPlanetProvisionalDesignations() {
        // Examples of the MPC document.
        XCTAssertEqual(PackedDesignation.minorPlanet("J95X00A"), "1995 XA")
        XCTAssertEqual(PackedDesignation.minorPlanet("J95X01L"), "1995 XL1")
        XCTAssertEqual(PackedDesignation.minorPlanet("J95F13B"), "1995 FB13")
        XCTAssertEqual(PackedDesignation.minorPlanet("J98SA8Q"), "1998 SQ108")
        XCTAssertEqual(PackedDesignation.minorPlanet("J98SC7V"), "1998 SV127")
        XCTAssertEqual(PackedDesignation.minorPlanet("J98SG2S"), "1998 SS162")
        XCTAssertEqual(PackedDesignation.minorPlanet("K99AJ3Z"), "2099 AZ193")
        XCTAssertEqual(PackedDesignation.minorPlanet("K08Aa0A"), "2008 AA360")
        XCTAssertEqual(PackedDesignation.minorPlanet("K07Tf8A"), "2007 TA418")
        XCTAssertEqual(PackedDesignation.minorPlanet("I45A00B"), "1845 AB")
        XCTAssertEqual(PackedDesignation.minorPlanet("PLS2040"), "2040 P-L")
        XCTAssertEqual(PackedDesignation.minorPlanet("T1S3138"), "3138 T-1")
        XCTAssertEqual(PackedDesignation.minorPlanet("T2S1010"), "1010 T-2")
        XCTAssertEqual(PackedDesignation.minorPlanet("T3S4101"), "4101 T-3")
        XCTAssertNil(PackedDesignation.minorPlanet("J95X00"))
        XCTAssertNil(PackedDesignation.minorPlanet("L95X00A"))
        XCTAssertNil(PackedDesignation.minorPlanet("J95I00A"))
        XCTAssertNil(PackedDesignation.minorPlanet("J95X00I"))
        XCTAssertNil(PackedDesignation.minorPlanet("J95X0xA"))
        XCTAssertNil(PackedDesignation.minorPlanet("J9XX00A"))
        XCTAssertNil(PackedDesignation.minorPlanet("PLS0000"))
        XCTAssertNil(PackedDesignation.minorPlanet("PLS20x0"))
    }

    func testPackedCometDesignations() {
        XCTAssertEqual(PackedDesignation.cometProvisional("J95A010"), "1995 A1")
        XCTAssertEqual(PackedDesignation.cometProvisional("J94P01b"), "1994 P1-B")
        XCTAssertEqual(PackedDesignation.cometProvisional("J94P010"), "1994 P1")
        XCTAssertEqual(PackedDesignation.cometProvisional("K48X130"), "2048 X13")
        XCTAssertEqual(PackedDesignation.cometProvisional("K33L89c"), "2033 L89-C")
        XCTAssertEqual(PackedDesignation.cometProvisional("K88AA30"), "2088 A103")
        XCTAssertNil(PackedDesignation.cometProvisional("J95A000"))
        XCTAssertNil(PackedDesignation.cometProvisional("J95A01B"))
        XCTAssertNil(PackedDesignation.cometProvisional("J95A01"))
        XCTAssertNil(PackedDesignation.cometProvisional("J95I010"))
    }

    func testPackedDates() {
        XCTAssertEqual(PackedDesignation.date("K2669"), PackedDate(year: 2026, month: 6, day: 9))
        XCTAssertEqual(PackedDesignation.date("K24AO"), PackedDate(year: 2024, month: 10, day: 24))
        XCTAssertEqual(PackedDesignation.date("K25BB"), PackedDate(year: 2025, month: 11, day: 11))
        XCTAssertEqual(PackedDesignation.date("K25CV"), PackedDate(year: 2025, month: 12, day: 31))
        XCTAssertEqual(PackedDesignation.date("J9611"), PackedDate(year: 1996, month: 1, day: 1))
        XCTAssertEqual(PackedDesignation.date("I502S"), PackedDate(year: 1850, month: 2, day: 28))
        XCTAssertEqual(PackedDesignation.date("K242T"), PackedDate(year: 2024, month: 2, day: 29))
        XCTAssertNil(PackedDesignation.date("K252T")) // 2025 is not a leap year
        XCTAssertNil(PackedDesignation.date("K24DA"))
        XCTAssertNil(PackedDesignation.date("K2401"))
        XCTAssertNil(PackedDesignation.date("K24A0"))
        XCTAssertNil(PackedDesignation.date("K24AW"))
        XCTAssertNil(PackedDesignation.date("K24"))
        XCTAssertNil(PackedDesignation.date("L2669"))
        XCTAssertNil(PackedDesignation.date("K2x69"))
    }

    // MARK: Numbers

    func testDecimalGrammar() {
        XCTAssertEqual(RecordFields.decimal("12"), 12.0)
        XCTAssertEqual(RecordFields.decimal("-0.5"), -0.5)
        XCTAssertEqual(RecordFields.decimal(".5"), 0.5)
        XCTAssertEqual(RecordFields.decimal("5."), 5.0)
        XCTAssertEqual(RecordFields.decimal("+2.5"), 2.5)
        XCTAssertEqual(RecordFields.decimal("-.25"), -0.25)
        XCTAssertNil(RecordFields.decimal(""))
        XCTAssertNil(RecordFields.decimal("."))
        XCTAssertNil(RecordFields.decimal("-"))
        XCTAssertNil(RecordFields.decimal("+."))
        XCTAssertNil(RecordFields.decimal("1.2.3"))
        XCTAssertNil(RecordFields.decimal("1 2"))
        XCTAssertNil(RecordFields.decimal("1e5"))
        XCTAssertNil(RecordFields.decimal("NaN"))
        XCTAssertNil(RecordFields.decimal("Infinity"))
        XCTAssertNil(RecordFields.decimal("0x10"))
        XCTAssertNil(RecordFields.decimal("1.5f"))
        XCTAssertNil(RecordFields.decimal("1.5d"))
        XCTAssertNil(RecordFields.decimal("--1"))
        XCTAssertNil(RecordFields.decimal(String(repeating: "1", count: 41)))
        XCTAssertEqual(RecordFields.decimal("1e5", allowExponent: true), 1e5)
        XCTAssertEqual(RecordFields.decimal("3.7E-6", allowExponent: true), 3.7e-6)
        XCTAssertEqual(RecordFields.decimal("-1.5e+3", allowExponent: true), -1.5e3)
        XCTAssertNil(RecordFields.decimal("1e", allowExponent: true))
        XCTAssertNil(RecordFields.decimal("1e+", allowExponent: true))
        XCTAssertNil(RecordFields.decimal("e5", allowExponent: true))
        XCTAssertNil(RecordFields.decimal("1e999", allowExponent: true))
        XCTAssertEqual(RecordFields.integer("12"), 12)
        XCTAssertEqual(RecordFields.integer("-7"), -7)
        XCTAssertEqual(RecordFields.integer("+5"), 5)
        XCTAssertEqual(RecordFields.integer("987654321"), 987_654_321)
        XCTAssertNil(RecordFields.integer("9876543210"))
        XCTAssertNil(RecordFields.integer("1.5"))
        XCTAssertNil(RecordFields.integer("-"))
        XCTAssertNil(RecordFields.integer(""))
        XCTAssertNil(RecordFields.integer("1 2"))
        XCTAssertEqual(RecordFields.daysInMonth(2025, 2), 28)
        XCTAssertEqual(RecordFields.daysInMonth(2024, 2), 29)
        XCTAssertEqual(RecordFields.daysInMonth(1900, 2), 28)
        XCTAssertEqual(RecordFields.daysInMonth(2000, 2), 29)
        XCTAssertEqual(RecordFields.daysInMonth(2025, 4), 30)
        XCTAssertEqual(RecordFields.daysInMonth(2025, 12), 31)
    }

    func testFixedWidthColumnsAreCountedInCharactersNotBytes() {
        // A non-ASCII name must not shift the columns that follow it, and a short line has blank columns.
        let line = FixedWidthLine("ab\u{00E9}\u{1F600} x")
        XCTAssertEqual(line.length, 6)
        XCTAssertEqual(line.text(3, 3), "\u{00E9}")
        XCTAssertEqual(line.text(4, 4), "\u{1F600}")
        XCTAssertEqual(line.text(5, 7), "x")
        XCTAssertEqual(line.text(20, 30), "")
        XCTAssertEqual(line.text(1, 5), "ab\u{00E9}\u{1F600}")
        XCTAssertEqual(FixedWidthLine("   ").text(1, 3), "")
        XCTAssertEqual(FixedWidthLine(" a b\t").text(1, 5), "a b")
    }

    func testNonAsciiNamesAreKept() throws {
        let body = try comet(replacing(CometsTestData.cometPonsBrooks, 103, 158, "12P/Pons-Br\u{00F6}oks"))
        XCTAssertEqual(body.name, "Pons-Br\u{00F6}oks")
    }

    // MARK: SmallBody

    func testSmallBodyCreationValidatesText() throws {
        let orbit = try XCTUnwrap(OrbitalElements(perihelionDistanceAU: 1.0, eccentricity: 0.5, inclination: 0.0,
                                                  argumentOfPerihelion: 0.0, longitudeOfAscendingNode: 0.0,
                                                  perihelionJulianDayTT: 2_460_000.0))
        func make(_ designation: String, _ name: String = "", number: Int? = nil) -> SmallBody? {
            SmallBody(designation: designation, name: name, kind: .comet, number: number, orbit: orbit)
        }
        let body = try XCTUnwrap(make("  C/2030 A1  ", " Test "))
        XCTAssertEqual(body.designation, "C/2030 A1")
        XCTAssertEqual(body.name, "Test")
        XCTAssertEqual(body.id, "comet.C/2030 A1")
        XCTAssertNil(body.photometry)
        XCTAssertNil(make("", "x"))
        XCTAssertNil(make("   ", "x"))
        XCTAssertNil(make("C/2030\nA1"))
        XCTAssertNil(make(String(repeating: "A", count: 81)))
        XCTAssertNotNil(make(String(repeating: "A", count: 80)))
        XCTAssertNil(make("X", String(repeating: "n", count: 81)))
        XCTAssertNil(make("X", "a\u{0007}b"))
        XCTAssertNil(make("X", "a\u{0085}b"))
        XCTAssertNil(make("X", number: 0))
        XCTAssertNil(make("X", number: 100_000_000))
        XCTAssertNotNil(make("X", number: 99_999_999))
    }

    func testTitlesFollowAstronomicalConvention() throws {
        let orbit = try XCTUnwrap(OrbitalElements(perihelionDistanceAU: 1.0, eccentricity: 0.5, inclination: 0.0,
                                                  argumentOfPerihelion: 0.0, longitudeOfAscendingNode: 0.0,
                                                  perihelionJulianDayTT: 2_460_000.0))
        func make(_ designation: String, _ name: String, _ kind: SmallBodyKind, _ number: Int?) throws -> SmallBody {
            try XCTUnwrap(SmallBody(designation: designation, name: name, kind: kind, number: number, orbit: orbit))
        }
        XCTAssertEqual(try make("12P", "Pons-Brooks", .comet, 12).title, "12P/Pons-Brooks")
        XCTAssertEqual(try make("12P", "", .comet, 12).title, "12P")
        XCTAssertEqual(try make("C/2023 A3", "Tsuchinshan-ATLAS", .comet, nil).title, "C/2023 A3 (Tsuchinshan-ATLAS)")
        XCTAssertEqual(try make("4", "Vesta", .asteroid, 4).title, "(4) Vesta")
        XCTAssertEqual(try make("44594", "", .asteroid, 44_594).title, "(44594)")
        XCTAssertEqual(try make("2024 YR4", "", .asteroid, nil).title, "2024 YR4")
        XCTAssertEqual(try make("4", "Vesta", .asteroid, 4).displayName, "Vesta")
    }

    func testSmallBodiesAreValuesWithStableIdentifiers() throws {
        let a = try comet(CometsTestData.cometPonsBrooks)
        let b = try comet(CometsTestData.cometPonsBrooks)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        // An element update keeps the identifier.
        let updated = try comet(replacing(CometsTestData.cometPonsBrooks, 31, 39, "0.781000"))
        XCTAssertEqual(a.id, updated.id)
        XCTAssertTrue(a != updated)
    }

    // MARK: Small-Body Database JSON

    func testParsesVestaFromTheSmallBodyDatabase() throws {
        let body = try SmallBodyJSONParser.parse(CometsTestData.jsonVesta)
        XCTAssertEqual(body.id, "asteroid.4")
        XCTAssertEqual(body.designation, "4")
        XCTAssertEqual(body.name, "Vesta")
        XCTAssertEqual(body.number, 4)
        XCTAssertEqual(body.kind, .asteroid)
        XCTAssertEqual(body.orbit.perihelionDistanceAU, 2.148_361_914_524_259)
        XCTAssertEqual(body.orbit.eccentricity, 0.090_203_743_828_343_95)
        XCTAssertEqual(body.orbit.inclination, 7.143_925_545_058_711)
        XCTAssertEqual(body.orbit.longitudeOfAscendingNode, 103.701_293_265_032)
        XCTAssertEqual(body.orbit.argumentOfPerihelion, 151.468_647_822_156_4)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_460_901.587_379_843, accuracy: 1e-9)
        XCTAssertEqual(body.orbit.epochJulianDayTT, 2_461_200.5)
        XCTAssertEqual(try asteroidMagnitudes(body).absoluteMagnitude, 3.25)
        XCTAssertEqual(try asteroidMagnitudes(body).slopeParameter, 0.32)
    }

    func testParsesCometsFromTheSmallBodyDatabase() throws {
        let pons = try SmallBodyJSONParser.parse(CometsTestData.jsonPonsBrooks)
        XCTAssertEqual(pons.id, "comet.12P")
        XCTAssertEqual(pons.designation, "12P")
        XCTAssertEqual(pons.name, "Pons-Brooks")
        XCTAssertEqual(pons.number, 12)
        XCTAssertEqual(pons.orbit.perihelionDistanceAU, 0.780_861_133_778_458_6)
        XCTAssertEqual(pons.orbit.perihelionJulianDayTT, 2_460_421.631_157_980_6, accuracy: 1e-9)
        XCTAssertEqual(pons.orbit.epochJulianDayTT, 2_460_211.5)
        let magnitudes = try cometMagnitudes(pons)
        XCTAssertEqual(magnitudes.totalMagnitude, 5.0)
        XCTAssertEqual(magnitudes.totalSlope, 15.0)
        XCTAssertEqual(magnitudes.nuclearMagnitude, 11.0)
        XCTAssertEqual(magnitudes.nuclearSlope, 10.0)
        XCTAssertEqual(magnitudes.nuclearPhaseCoefficient, 0.0)

        let atlas = try SmallBodyJSONParser.parse(CometsTestData.jsonTsuchinshanAtlas)
        XCTAssertEqual(atlas.designation, "C/2023 A3")
        XCTAssertEqual(atlas.name, "Tsuchinshan-ATLAS")
        XCTAssertNil(atlas.number)
        XCTAssertEqual(atlas.orbit.shape, .hyperbolic)
        XCTAssertEqual(atlas.orbit.eccentricity, 1.000_095_368_540_586)
        XCTAssertEqual(try cometMagnitudes(atlas).totalMagnitude, 8.9)
        XCTAssertEqual(try cometMagnitudes(atlas).totalSlope, 5.5)
        XCTAssertNil(try cometMagnitudes(atlas).nuclearMagnitude)

        let halley = try SmallBodyJSONParser.parse(CometsTestData.jsonHalley)
        XCTAssertEqual(halley.title, "1P/Halley")
        let halleyMagnitudes = try cometMagnitudes(halley)
        XCTAssertEqual(halleyMagnitudes.nuclearMagnitude, 13.6)
        XCTAssertEqual(halleyMagnitudes.nuclearSlope, 5.0)
        XCTAssertEqual(halleyMagnitudes.nuclearPhaseCoefficient, 0.03)
        XCTAssertEqual(halley.orbit.perihelionJulianDayTT, 2_446_469.973_616_146_677, accuracy: 1e-9)

        let threeI = try SmallBodyJSONParser.parse(CometsTestData.jsonAtlas3i)
        XCTAssertEqual(threeI.designation, "C/2025 N1")
        XCTAssertEqual(threeI.name, "ATLAS")
        XCTAssertEqual(threeI.orbit.eccentricity, 6.141_351_449_317_625)
        XCTAssertEqual(try cometMagnitudes(threeI).totalMagnitude, 12.5)
    }

    func testParsesUnnumberedAsteroidsFromTheSmallBodyDatabase() throws {
        let body = try SmallBodyJSONParser.parse(CometsTestData.jsonYr42024)
        XCTAssertEqual(body.designation, "2024 YR4")
        XCTAssertEqual(body.name, "")
        XCTAssertNil(body.number)
        XCTAssertEqual(body.id, "asteroid.2024 YR4")
        XCTAssertEqual(try asteroidMagnitudes(body).absoluteMagnitude, 23.93)
        XCTAssertEqual(try asteroidMagnitudes(body).slopeParameter, 0.15)
        let ceres = try SmallBodyJSONParser.parse(CometsTestData.jsonCeres)
        XCTAssertEqual(ceres.title, "(1) Ceres")
        XCTAssertEqual(try asteroidMagnitudes(ceres).slopeParameter, 0.12)
    }

    func testSmallBodyDatabaseAndMPCAgreeOnTheSameOrbit() throws {
        let json = try SmallBodyJSONParser.parse(CometsTestData.jsonVesta)
        let mpc = try MinorPlanetElementsParser.parseLine(CometsTestData.asteroidVesta)
        XCTAssertEqual(json.orbit.perihelionDistanceAU, mpc.orbit.perihelionDistanceAU, accuracy: 2e-6)
        XCTAssertEqual(json.orbit.eccentricity, mpc.orbit.eccentricity, accuracy: 2e-7)
        XCTAssertEqual(json.orbit.inclination, mpc.orbit.inclination, accuracy: 2e-5)
        XCTAssertEqual(json.orbit.perihelionJulianDayTT, mpc.orbit.perihelionJulianDayTT, accuracy: 2e-3)
        XCTAssertEqual(json.id, mpc.id)
    }

    func testJsonValuesMayBeNumbers() throws {
        let text = """
            {"object": {"fullname": "C/2030 A1 (Test)", "kind": "cu"},
             "orbit": {"epoch": 2460000.5, "equinox": "J2000", "elements": [
               {"name": "e", "value": 0.5}, {"name": "q", "value": 1}, {"name": "i", "value": 10},
               {"name": "om", "value": 20.5}, {"name": "w", "value": 3.0E+1}, {"name": "tp", "value": 2460100.25},
               {"name": "per", "value": null}]},
             "phys_par": [{"name": "M1", "value": 7.5}, {"name": "K1", "value": 12}]}
            """
        let body = try SmallBodyJSONParser.parse(text)
        XCTAssertEqual(body.designation, "C/2030 A1")
        XCTAssertEqual(body.name, "Test")
        XCTAssertEqual(body.orbit.perihelionDistanceAU, 1.0)
        XCTAssertEqual(body.orbit.argumentOfPerihelion, 30.0)
        XCTAssertEqual(body.orbit.perihelionJulianDayTT, 2_460_100.25)
        XCTAssertEqual(body.orbit.epochJulianDayTT, 2_460_000.5)
        XCTAssertEqual(try cometMagnitudes(body).totalMagnitude, 7.5)
        XCTAssertEqual(try cometMagnitudes(body).totalSlope, 12.0)
    }

    func testJsonFallsBackToMeanAnomalyAndDefaults() throws {
        // No tp and no q: derived from the mean anomaly, the epoch and the semi-major axis; K1 defaults to 10.
        let text = """
            {"object": {"fullname": "433 Eros (A898 PA)", "kind": "an"},
             "orbit": {"epoch": "2461200.5", "elements": [
               {"name": "e", "value": "0.2228780"}, {"name": "a", "value": "1.4582437"}, {"name": "i", "value": "10.82855"},
               {"name": "om", "value": "304.26797"}, {"name": "w", "value": "178.91814"}, {"name": "ma", "value": "62.51145"}]},
             "phys_par": [{"name": "H", "value": "10.39"}]}
            """
        let body = try SmallBodyJSONParser.parse(text)
        XCTAssertEqual(body.number, 433)
        XCTAssertEqual(body.name, "Eros")
        XCTAssertEqual(body.orbit.perihelionDistanceAU, 1.4582437 * (1 - 0.222878), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(body.orbit.meanAnomaly(at: 2_461_200.5)), 62.51145, accuracy: 1e-6)
        XCTAssertEqual(try asteroidMagnitudes(body).slopeParameter, 0.15)
        // A comet that has M1 but no K1 gets the classical slope of 10.
        let comet = text.replacingOccurrences(of: "433 Eros (A898 PA)", with: "C/2030 A1").replacingOccurrences(of: "\"an\"", with: "\"cu\"")
            .replacingOccurrences(of: "{\"name\": \"H\", \"value\": \"10.39\"}", with: "{\"name\": \"M1\", \"value\": \"8.0\"}")
        XCTAssertEqual(try cometMagnitudes(try SmallBodyJSONParser.parse(comet)).totalSlope, 10.0)
        // A comet that only has H uses the asteroid law, an asteroid that only has M1 the comet law.
        let cometWithH = text.replacingOccurrences(of: "433 Eros (A898 PA)", with: "C/2030 A1").replacingOccurrences(of: "\"an\"", with: "\"cu\"")
        XCTAssertEqual(try asteroidMagnitudes(try SmallBodyJSONParser.parse(cometWithH)).absoluteMagnitude, 10.39)
        let asteroidWithM1 = text.replacingOccurrences(of: "{\"name\": \"H\", \"value\": \"10.39\"}", with: "{\"name\": \"M1\", \"value\": \"8.0\"}")
        XCTAssertEqual(try cometMagnitudes(try SmallBodyJSONParser.parse(asteroidWithM1)).totalMagnitude, 8.0)
        // Without any magnitude parameter there is no photometry.
        XCTAssertNil(try SmallBodyJSONParser.parse(text.replacingOccurrences(of: "[{\"name\": \"H\", \"value\": \"10.39\"}]", with: "[]")).photometry)
    }

    func testAsteroidFullNames() {
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("4 Vesta (A807 FA)"), AsteroidIdentity(number: 4, designation: "4", name: "Vesta"))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("433 Eros (A898 PA)"), AsteroidIdentity(number: 433, designation: "433", name: "Eros"))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("44594 (1999 OX3)"), AsteroidIdentity(number: 44_594, designation: "44594", name: "1999 OX3"))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("7"), AsteroidIdentity(number: 7, designation: "7", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("(2024 YR4)"), AsteroidIdentity(number: nil, designation: "2024 YR4", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("2024 YR4"), AsteroidIdentity(number: nil, designation: "2024 YR4", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("99942 Apophis (2004 MN4)"), AsteroidIdentity(number: 99_942, designation: "99942", name: "Apophis"))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("(a) (b)"), AsteroidIdentity(number: nil, designation: "(a) (b)", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidFullName("123456789 X"), AsteroidIdentity(number: nil, designation: "123456789 X", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidReadable("(4) Vesta"), AsteroidIdentity(number: 4, designation: "4", name: "Vesta"))
        XCTAssertEqual(SmallBodyNaming.asteroidReadable("(202411) 2005 RC"), AsteroidIdentity(number: 202_411, designation: "202411", name: "2005 RC"))
        XCTAssertEqual(SmallBodyNaming.asteroidReadable("2024 YR4"), AsteroidIdentity(number: nil, designation: "2024 YR4", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidReadable("(x) y"), AsteroidIdentity(number: nil, designation: "(x) y", name: ""))
        XCTAssertEqual(SmallBodyNaming.asteroidReadable("()"), AsteroidIdentity(number: nil, designation: "()", name: ""))
    }

    func testJsonErrorsAreTyped() throws {
        func isInvalidJSON(_ error: SmallBodyParseError?) -> Bool {
            if case .invalidJSON? = error { return true }
            return false
        }
        XCTAssertTrue(isInvalidJSON(jsonError("")))
        XCTAssertTrue(isInvalidJSON(jsonError("{")))
        XCTAssertTrue(isInvalidJSON(jsonError("not json")))
        XCTAssertEqual(jsonError("[]"), .invalidJSON(reason: "the top level is not an object"))
        XCTAssertEqual(jsonError("42"), .invalidJSON(reason: "the top level is not an object"))
        XCTAssertEqual(jsonError("{\"code\": \"200\", \"message\": \"specified object was not found\"}"),
                       .unsupportedObject(reason: "specified object was not found"))
        XCTAssertEqual(jsonError("{}"), .unsupportedObject(reason: "the answer contains no object"))
        XCTAssertEqual(jsonError("{\"object\": {\"kind\": \"an\"}}"), .unsupportedObject(reason: "the answer contains no orbit"))
        let good = CometsTestData.jsonVesta
        func replaced(_ target: String, _ replacement: String) -> String {
            good.replacingOccurrences(of: target, with: replacement)
        }
        XCTAssertEqual(jsonError(replaced("\"kind\": \"an\"", "\"kinds\": \"an\"")), .unsupportedObject(reason: "the object has no kind"))
        XCTAssertEqual(jsonError(replaced("\"kind\": \"an\"", "\"kind\": \"sn\"")),
                       .unsupportedObject(reason: "the object kind \"sn\" is not a comet or asteroid"))
        XCTAssertEqual(jsonError(replaced("\"fullname\": \"4 Vesta (A807 FA)\"", "\"fullname\": \"  \"")), .missingField(.designation))
        XCTAssertEqual(jsonError(replaced("\"equinox\": \"J2000\"", "\"equinox\": \"B1950\"")),
                       .unsupportedObject(reason: "the elements refer to the equinox B1950"))
        XCTAssertEqual(jsonError(replaced("\"elements\"", "\"elementz\"")), .unsupportedObject(reason: "the orbit has no elements"))
        XCTAssertEqual(jsonError(replaced("\".09020374382834395\"", "\"abc\"")), .malformedField(.eccentricity, text: "abc"))
        XCTAssertEqual(jsonError(replaced("\".09020374382834395\"", "\"-0.5\"")), .fieldOutOfRange(.eccentricity, value: -0.5))
        XCTAssertEqual(jsonError(replaced("\"7.143925545058711\"", "\"200\"")), .fieldOutOfRange(.inclination, value: 200.0))
        XCTAssertEqual(jsonError(replaced("\"151.4686478221564\"", "\"NaN\"")), .malformedField(.argumentOfPerihelion, text: "NaN"))
        XCTAssertEqual(jsonError(replaced("\"value\": \"3.25\"", "\"value\": \"bright\"")), .malformedField(.absoluteMagnitude, text: "bright"))
        XCTAssertEqual(jsonError(replaced("\"value\": \"0.32\"", "\"value\": \"3\"")), .fieldOutOfRange(.slopeParameter, value: 3.0))
        XCTAssertEqual(jsonError(replaced("\"name\": \"e\"", "\"name\": \"ee\"")), .missingField(.eccentricity))
        XCTAssertEqual(jsonError(replaced("\"name\": \"i\"", "\"name\": \"ii\"")), .missingField(.inclination))
        XCTAssertEqual(jsonError(replaced("\"name\": \"om\"", "\"name\": \"oom\"")), .missingField(.longitudeOfAscendingNode))
        XCTAssertEqual(jsonError(replaced("\"name\": \"w\"", "\"name\": \"ww\"")), .missingField(.argumentOfPerihelion))
        // Neither tp nor a mean anomaly.
        let noTime = replaced("\"name\": \"tp\"", "\"name\": \"tq\"").replacingOccurrences(of: "\"name\": \"ma\"", with: "\"name\": \"mb\"")
        XCTAssertEqual(jsonError(noTime), .missingField(.perihelionTime))
        // A mean anomaly but no epoch.
        let noEpoch = replaced("\"name\": \"tp\"", "\"name\": \"tq\"").replacingOccurrences(of: "\"epoch\": \"2461200.5\"", with: "\"epochs\": \"2461200.5\"")
        XCTAssertEqual(jsonError(noEpoch), .missingField(.epoch))
        // No q and no a.
        let noShape = replaced("\"name\": \"q\"", "\"name\": \"qq\"")
        XCTAssertEqual(try SmallBodyJSONParser.parse(noShape).orbit.perihelionDistanceAU,
                       2.361_365_965_127_599 * (1 - 0.090_203_743_828_343_95), accuracy: 1e-12)
        XCTAssertEqual(jsonError(noShape.replacingOccurrences(of: "\"name\": \"a\"", with: "\"name\": \"aa\"")), .missingField(.perihelionDistance))
        // The mean anomaly needs a semi-major axis or q and an elliptic orbit.
        let noAxis = noTime.replacingOccurrences(of: "\"name\": \"mb\"", with: "\"name\": \"ma\"")
            .replacingOccurrences(of: "\"name\": \"a\"", with: "\"name\": \"aa\"").replacingOccurrences(of: "\"name\": \"q\"", with: "\"name\": \"qq\"")
        XCTAssertEqual(jsonError(noAxis), .missingField(.semiMajorAxis))
    }

    func testJsonLimitsNestingAndSize() {
        XCTAssertEqual(jsonError(String(repeating: "[", count: 33) + String(repeating: "]", count: 33)), .invalidJSON(reason: "nested too deeply"))
        XCTAssertEqual(jsonError(String(repeating: "{\"a\":", count: 40) + "1" + String(repeating: "}", count: 40)),
                       .invalidJSON(reason: "nested too deeply"))
        // Brackets inside strings do not count.
        let inString = CometsTestData.jsonVesta.replacingOccurrences(
            of: "\"signature\"",
            with: "\"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[\": \"\\\"[[[[\", \"signature\"")
        XCTAssertEqual(try SmallBodyJSONParser.parse(inString).name, "Vesta")
        let failure = jsonError(String(repeating: "x", count: SmallBodyJSONParser.maximumInputLength + 1))
        XCTAssertEqual(failure, .inputTooLarge(length: SmallBodyJSONParser.maximumInputLength + 1, maximum: SmallBodyJSONParser.maximumInputLength))
    }

    func testJsonNumericFieldsRejectOtherKinds() throws {
        let good = CometsTestData.jsonVesta
        func replaced(_ replacement: String) -> String {
            good.replacingOccurrences(of: "\".09020374382834395\"", with: replacement)
        }
        XCTAssertEqual(jsonError(replaced("true")), .malformedField(.eccentricity, text: "true"))
        XCTAssertEqual(jsonError(replaced("false")), .malformedField(.eccentricity, text: "false"))
        XCTAssertEqual(jsonError(replaced("[1]")), .malformedField(.eccentricity, text: "array"))
        XCTAssertEqual(jsonError(replaced("{}")), .malformedField(.eccentricity, text: "object"))
        // A null value counts as absent.
        XCTAssertEqual(jsonError(replaced("null")), .missingField(.eccentricity))
        // Surrounding blanks in a string value are ignored.
        let padded = try SmallBodyJSONParser.parse(good.replacingOccurrences(of: "\"2.148361914524259\"", with: "\"  2.148361914524259 \""))
        XCTAssertEqual(padded.orbit.perihelionDistanceAU, 2.148_361_914_524_259)
        // Names may be escaped in the document.
        let escaped = try SmallBodyJSONParser.parse(good.replacingOccurrences(
            of: "\"fullname\": \"4 Vesta (A807 FA)\"", with: "\"fullname\": \"4 Ves\\u0074a (A807 FA)\""))
        XCTAssertEqual(escaped.name, "Vesta")
        // A repeated element name takes the last entry.
        let repeated = good.replacingOccurrences(
            of: "{\"label\": \"e\", \"value\": \".09020374382834395\"",
            with: "{\"name\": \"e\", \"value\": \"0.5\"}, {\"label\": \"e\", \"value\": \".09020374382834395\"")
        XCTAssertEqual(try SmallBodyJSONParser.parse(repeated).orbit.eccentricity, 0.090_203_743_828_343_95)
    }

    func testErrorsDescribeThemselves() {
        XCTAssertEqual(SmallBodyParseError.fieldOutOfRange(.inclination, value: 181.0).description, "The inclination 181.0 is out of range.")
        XCTAssertEqual(SmallBodyParseError.malformedField(.eccentricity, text: "abc").description, "The eccentricity \"abc\" is not valid.")
        XCTAssertEqual(SmallBodyParseError.missingField(.epoch).description, "The epoch is missing.")
        XCTAssertEqual(SmallBodyParseError.lineTooShort(length: 5, minimum: 79).description, "The line has 5 characters; at least 79 are required.")
        XCTAssertEqual(SmallBodyParseError.lineTooLong(length: 500, maximum: 400).description, "The line has 500 characters; at most 400 are allowed.")
        XCTAssertEqual(SmallBodyParseError.invalidDesignation(text: "x").description, "The designation \"x\" is not valid.")
        XCTAssertEqual(SmallBodyParseError.duplicateObject(id: "comet.1P").description, "The object comet.1P occurs more than once.")
        XCTAssertEqual(SmallBodyParseError.invalidJSON(reason: "oops").description, "The JSON is not valid: oops.")
        XCTAssertEqual(SmallBodyParseError.unsupportedObject(reason: "why").description, "The object cannot be used: why.")
        XCTAssertEqual(SmallBodyParseError.inconsistentElements(reason: "because").description, "The orbital elements are inconsistent: because.")
        XCTAssertEqual(SmallBodyParseError.inputTooLarge(length: 9, maximum: 5).description, "The input has 9 characters; at most 5 are accepted.")
        XCTAssertEqual(SmallBodyParseError.missingField(.epoch).errorDescription, "The epoch is missing.")
        XCTAssertEqual(SmallBodyKind.comet.rawValue, "comet")
        XCTAssertEqual(SmallBodyKind(rawValue: "asteroid"), .asteroid)
        XCTAssertNil(SmallBodyKind(rawValue: "planet"))
        XCTAssertEqual(SmallBodyKind.comet.displayName, "Comet")
        XCTAssertEqual(SmallBodyKind.asteroid.displayName, "Asteroid")
        XCTAssertEqual(OrbitShape(rawValue: "hyperbolic"), .hyperbolic)
        XCTAssertNil(OrbitShape(rawValue: "circular"))
        for field in SmallBodyField.allCases {
            XCTAssertEqual(SmallBodyField(rawValue: field.rawValue), field)
            XCTAssertFalse(field.displayName.isEmpty)
        }
        XCTAssertNil(SmallBodyField(rawValue: "nothing"))
    }
}

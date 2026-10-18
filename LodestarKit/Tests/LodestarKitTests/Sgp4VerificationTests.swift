import XCTest
@testable import LodestarKit

/// Checks the SGP4/SDP4 port against the verification run of the reference implementation.
///
/// `sgp4_ver.tle` is `SGP4-VER.TLE` from Vallado's distribution (CelesTrak, "Revisiting Spacetrack Report #3",
/// AIAA 2006-6753): 33 element sets chosen to exercise every branch of the code (near-earth, deep-space,
/// 12-hour and 24-hour resonance, the Lyddane branch, low perigees, decay, the error codes 1, 4 and 6), each with
/// a start, stop and step time in minutes after its second line.
/// `sgp4_tcppver.out` is the output of the reference C++ code (`SGP4.cpp`, version 2020-07-13, `opsmode` 'i',
/// WGS-72) for that file, produced exactly as its `TestSGP4.cpp` verification run does (`tcppver.out`); the
/// generator is `Tools/make_satellite_fixtures.py`. The official MATLAB (Dec 2015) and Fortran outputs of the
/// 2006 distribution agree with it to the last printed digit for every satellite except 23599 after 420 minutes
/// (an older Lyddane rule, below 1 km); the C++ and Java v2 outputs agree with each other and with this port.
///
/// The expected values are printed with 8 decimals (position, km) and 9 decimals (velocity, km/s).
final class Sgp4VerificationTests: XCTestCase {
    private struct Case {
        let catalog: String
        let elements: OrbitalElements
        let start: Double
        let stop: Double
        let step: Double
    }

    private struct Row {
        let time: Double
        let values: [Double]
    }

    private struct Expected {
        var rows: [Row] = []
        var errors: [(Double, Int)] = []
    }

    /// The position tolerance: the reference prints 8 decimals (10 micrometres); 0.1 millimetres leaves room for
    /// the last-ulp differences of the math libraries.
    private let positionTolerance = 1.0e-7

    /// The velocity tolerance: the reference prints 9 decimals (1 micrometre per second).
    private let velocityTolerance = 1.0e-8

    private func withValidChecksum(_ line: String) -> String {
        String(line.prefix(68)) + String(ElementSetParser.checksum(line))
    }

    private func cases() throws -> [Case] {
        let lines = try SatelliteTestSupport.fixtureText("sgp4_ver.tle").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        var result: [Case] = []
        var index = 0
        while index + 1 < lines.count {
            let secondFull = lines[index + 1]
            let times = String(secondFull.dropFirst(69)).split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).compactMap { Double($0) }
            let first = withValidChecksum(String(lines[index].prefix(69)))
            let second = withValidChecksum(String(secondFull.prefix(69)))
            let elements = try ElementSetParser.parseTwoLine(line1: first, line2: second)
            result.append(Case(catalog: String(elements.catalogNumber), elements: elements, start: times[0], stop: times[1], step: times[2]))
            index += 2
        }
        return result
    }

    /// The groups of `tcppver.out`: one per element set, keyed by catalog number, in file order.
    private func expectations() throws -> [(String, Expected)] {
        var groups: [(String, Expected)] = []
        for line in try SatelliteTestSupport.fixtureText("sgp4_tcppver.out").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasSuffix("xx") {
                var name = String(trimmed.split(separator: " ")[0])
                while name.hasPrefix("0") && name.count > 1 { name.removeFirst() }
                if name == "0" { name = "" }
                groups.append((name, Expected()))
            } else if line.hasPrefix("# *** error") {
                let time = Double(line.components(separatedBy: "t:=")[1].components(separatedBy: "***")[0].trimmingCharacters(in: .whitespaces)) ?? .nan
                let code = Int(line.components(separatedBy: "code =")[1].trimmingCharacters(in: .whitespaces)) ?? 0
                groups[groups.count - 1].1.errors.append((time, code))
            } else {
                let fields = trimmed.split(whereSeparator: { $0 == " " }).prefix(7).compactMap { Double($0) }
                groups[groups.count - 1].1.rows.append(Row(time: fields[0], values: Array(fields[1...6])))
            }
        }
        return groups
    }

    func testTheFileHoldsThirtyThreeElementSetsAndTheReferenceOutputMatchesIt() throws {
        let all = try cases()
        let expected = try expectations()
        XCTAssertEqual(all.count, 33)
        XCTAssertEqual(expected.count, 33)
        XCTAssertEqual(all.map(\.catalog), expected.map(\.0))
    }

    func testTheHandMadeCasesCarryWrongChecksums() throws {
        let lines = try SatelliteTestSupport.fixtureText("sgp4_ver.tle").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        var rejected: [String] = []
        var index = 0
        while index + 1 < lines.count {
            let first = String(lines[index].prefix(69))
            let second = String(lines[index + 1].prefix(69))
            do {
                _ = try ElementSetParser.parseTwoLine(line1: first, line2: second)
            } catch ElementSetError.checksumMismatch(let line, let expected, let found) {
                rejected.append(String(first.dropFirst(2).prefix(5)))
                let wrongLine = line == 1 ? first : second
                XCTAssertEqual(expected, ElementSetParser.checksum(wrongLine))
                XCTAssertEqual(found, Int(String(wrongLine.suffix(1))))
            }
            index += 2
        }
        XCTAssertEqual(rejected, ["33333", "33334", "33335"])
    }

    func testEveryVerificationSatelliteMatchesTheReferenceToTheLastPrintedDigit() throws {
        let all = try cases()
        let expected = try expectations()
        var worstPosition = 0.0
        var worstVelocity = 0.0
        var worstWhere = ""
        var compared = 0
        for (testCase, entry) in zip(all, expected.map(\.1)) {
            let propagator = Sgp4Propagator(elements: testCase.elements)
            var rowIndex = 0
            var out = [Double](repeating: 0, count: 6)

            // The reference prints the state at the epoch first, then steps from start to stop.
            let epochCode = propagator.propagateRaw(0.0, into: &out)
            if epochCode != 0 {
                // Only 33334 (mean motion 0.00001 rev/day) fails at the epoch, with error 3; the reference then
                // stops and prints the stale contents of its output arrays, which are not a state.
                XCTAssertEqual(testCase.catalog, "33334")
                XCTAssertEqual(epochCode, 3)
                XCTAssertEqual(entry.rows.count, 1)
                continue
            }
            let (epochPosition, epochVelocity) = compare(testCase, entry.rows[rowIndex], out)
            worstPosition = max(worstPosition, epochPosition)
            worstVelocity = max(worstVelocity, epochVelocity)
            rowIndex += 1
            compared += 1

            var tsince = testCase.start
            if abs(tsince) > 1.0e-8 { tsince -= testCase.step }
            var errorIndex = 0
            var failed = false
            while tsince < testCase.stop && !failed {
                tsince += testCase.step
                if tsince > testCase.stop { tsince = testCase.stop }
                let code = propagator.propagateRaw(tsince, into: &out)
                if code != 0 {
                    let (errorTime, errorCode) = entry.errors[errorIndex]
                    XCTAssertEqual(errorTime, tsince, accuracy: 1.0e-6, "\(testCase.catalog): time of the error")
                    XCTAssertEqual(errorCode, code, "\(testCase.catalog): error code at \(tsince)")
                    errorIndex += 1
                    failed = true
                } else {
                    let row = entry.rows[rowIndex]
                    XCTAssertEqual(row.time, tsince, accuracy: 1.0e-6, "\(testCase.catalog): time of row \(rowIndex)")
                    let (dp, dv) = compare(testCase, row, out)
                    if dp > worstPosition { worstWhere = "\(testCase.catalog) at \(tsince) min" }
                    worstPosition = max(worstPosition, dp)
                    worstVelocity = max(worstVelocity, dv)
                    rowIndex += 1
                    compared += 1
                }
            }
            XCTAssertEqual(entry.rows.count, rowIndex, "\(testCase.catalog): number of rows")
            XCTAssertEqual(entry.errors.count, errorIndex, "\(testCase.catalog): number of errors")
        }
        print("SGP4 verification: \(compared) states, worst position difference \(worstPosition) km (\(worstWhere)), worst velocity difference \(worstVelocity) km/s")
        XCTAssertGreaterThan(compared, 600)
        XCTAssertLessThan(worstPosition, positionTolerance, "worst position difference at \(worstWhere)")
        XCTAssertLessThan(worstVelocity, velocityTolerance)
    }

    private func compare(_ testCase: Case, _ row: Row, _ state: [Double]) -> (Double, Double) {
        var dp = 0.0
        var dv = 0.0
        for index in 0..<3 {
            dp = max(dp, abs(state[index] - row.values[index]))
            dv = max(dv, abs(state[index + 3] - row.values[index + 3]))
        }
        XCTAssertLessThan(dp, positionTolerance, "\(testCase.catalog) at \(row.time) min: position differs by \(dp) km")
        XCTAssertLessThan(dv, velocityTolerance, "\(testCase.catalog) at \(row.time) min: velocity differs by \(dv) km/s")
        return (dp, dv)
    }
}

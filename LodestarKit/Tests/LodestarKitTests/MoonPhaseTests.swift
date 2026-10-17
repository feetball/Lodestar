import XCTest
@testable import LodestarKit

final class MoonPhaseTests: XCTestCase {
    private struct PhaseRecord: Decodable {
        let phase: String
        let unix: Double

        var kind: PrincipalMoonPhase? {
            switch phase {
            case "new": .newMoon
            case "first_quarter": .firstQuarter
            case "full": .fullMoon
            case "last_quarter": .lastQuarter
            default: nil
            }
        }
    }

    private struct SampleRecord: Decodable {
        let utc: String
        let ut1Jd: Double
        let ttJd: Double
        let illuminatedFraction: Double
        let phaseAngleDeg: Double
        let eclipticElongationDeg: Double
        let ageDays: Double
    }

    private struct File: Decodable {
        let phases: [PhaseRecord]
        let samples: [SampleRecord]
    }

    private func fixture() throws -> File {
        let file = try EphemerisFixtureStore.load(File.self, from: "moon_phases.json")
        XCTAssertGreaterThan(file.phases.count, 240, "2024–2028 holds about 248 principal phases")
        XCTAssertEqual(file.samples.count, 30)
        return file
    }

    // MARK: Names

    func testPhaseNamesFollowTheElongation() {
        let expectations: [(Double, MoonPhaseName)] = [
            (0, .newMoon), (11.2, .newMoon), (11.25, .waxingCrescent), (45, .waxingCrescent), (78.7, .waxingCrescent),
            (78.75, .firstQuarter), (90, .firstQuarter), (101.2, .firstQuarter), (101.25, .waxingGibbous),
            (135, .waxingGibbous), (168.7, .waxingGibbous), (168.75, .fullMoon), (180, .fullMoon), (191.2, .fullMoon),
            (191.25, .waningGibbous), (225, .waningGibbous), (258.7, .waningGibbous), (258.75, .lastQuarter),
            (270, .lastQuarter), (281.2, .lastQuarter), (281.25, .waningCrescent), (315, .waningCrescent),
            (348.7, .waningCrescent), (348.75, .newMoon), (359.999, .newMoon),
            // Wrapped and invalid angles.
            (360, .newMoon), (-5, .newMoon), (-45, .waningCrescent), (450, .firstQuarter),
            (.nan, .newMoon), (.infinity, .newMoon),
        ]
        for (elongation, name) in expectations {
            XCTAssertEqual(MoonPhaseName(elongation: elongation), name, "elongation \(elongation)")
        }
        // Each principal wedge spans 22.5°, each crescent or gibbous wedge 67.5°.
        var counts = [MoonPhaseName: Int]()
        for tenth in 0..<3600 { counts[MoonPhaseName(elongation: Double(tenth) / 10), default: 0] += 1 }
        for name in [MoonPhaseName.newMoon, .firstQuarter, .fullMoon, .lastQuarter] {
            XCTAssertEqual(counts[name], 225, "\(name)")
        }
        for name in [MoonPhaseName.waxingCrescent, .waxingGibbous, .waningGibbous, .waningCrescent] {
            XCTAssertEqual(counts[name], 675, "\(name)")
        }
    }

    func testDisplayNamesAndSymbols() {
        XCTAssertEqual(MoonPhaseName.allCases.count, 8)
        XCTAssertEqual(MoonPhaseName.allCases.map(\.displayName),
                       ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous",
                        "Last Quarter", "Waning Crescent"])
        XCTAssertEqual(MoonPhaseName.allCases.map(\.symbolName),
                       ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                        "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                        "moonphase.last.quarter", "moonphase.waning.crescent"])
        XCTAssertEqual(Set(MoonPhaseName.allCases.map(\.symbolName)).count, 8)
        XCTAssertEqual(PrincipalMoonPhase.allCases.map(\.elongation), [0, 90, 180, 270])
        XCTAssertEqual(PrincipalMoonPhase.allCases.map(\.name), [.newMoon, .firstQuarter, .fullMoon, .lastQuarter])
        for phase in PrincipalMoonPhase.allCases {
            XCTAssertEqual(MoonPhaseName(elongation: phase.elongation), phase.name)
            XCTAssertEqual(phase.displayName, phase.name.displayName)
            XCTAssertEqual(phase.symbolName, phase.name.symbolName)
        }
        for name in MoonPhaseName.allCases {
            let data = try? JSONEncoder().encode(name)
            XCTAssertEqual(data.flatMap { try? JSONDecoder().decode(MoonPhaseName.self, from: $0) }, name)
        }
    }

    // MARK: Meeus chapter 49

    /// Example 49.a: new moon of 1977 February 18, JDE 2443192.65118 (3h37m42s TD); DE440s gives
    /// 2443192.65116. Example 49.b: last quarter of 2044 January 21, JDE 2467636.49186 (DE440s 2467636.49187).
    func testPhaseInstantsMeeusExamples49() throws {
        let february = MoonPhaseCalculator.nextPhases(after: JulianDate(ut: 2_443_185.0).date, count: 3)
        XCTAssertEqual(february.map(\.kind), [.lastQuarter, .newMoon, .firstQuarter])
        XCTAssertEqual(JulianDate(date: february[1].date).tt, 2_443_192.65118, accuracy: 60.0 / 86_400)
        XCTAssertEqual(JulianDate(date: february[0].date).tt, 2_443_185.67220, accuracy: 60.0 / 86_400)

        let january = MoonPhaseCalculator.nextPhases(after: JulianDate(ut: 2_467_620.0).date, count: 4)
        XCTAssertEqual(january.map(\.kind), [.firstQuarter, .fullMoon, .lastQuarter, .newMoon])
        XCTAssertEqual(JulianDate(date: january[2].date).tt, 2_467_636.49186, accuracy: 60.0 / 86_400)
        XCTAssertEqual(JulianDate(date: january[1].date).tt, 2_467_629.28637, accuracy: 60.0 / 86_400)
    }

    func testIlluminationAtMeeusExample48a() {
        // The Moon on 1992 April 12 at 0h TD was 67.9 % lit and waxing. The book's elongation ψ = 110.7929° is the
        // angular distance from the Sun; the difference in ecliptic longitude, from cos ψ = cos β cos Δλ with
        // the Moon's latitude β = −3.2291°, is 110.8265°.
        let info = MoonPhaseCalculator.info(at: JulianDate(tt: 2_448_724.5).date)
        XCTAssertEqual(info.illuminatedFraction, 0.6786, accuracy: 0.0005)
        XCTAssertEqual(info.elongation, 110.8265, accuracy: 0.003)
        XCTAssertEqual(info.name, .waxingGibbous)
        XCTAssertTrue(info.isWaxing)
        // The new moon of 1992 April 3, 05:01 UT (JDE 2448715.71002 by DE440s) was 8.79 days earlier.
        XCTAssertEqual(info.ageDays, 8.79, accuracy: 0.02)
    }

    // MARK: Fixtures

    func testPrincipalPhasesMatchSkyfield() throws {
        let phases = try fixture().phases
        let start = Date(timeIntervalSince1970: try XCTUnwrap(phases.first).unix - 86_400)
        let found = MoonPhaseCalculator.nextPhases(after: start, count: phases.count)
        XCTAssertEqual(found.count, phases.count)
        for (mine, reference) in zip(found, phases) {
            XCTAssertEqual(mine.kind, reference.kind, "phase at \(Date(timeIntervalSince1970: reference.unix))")
            // Observed worst case 15 s; the requirement is 2 minutes.
            XCTAssertEqual(mine.date.timeIntervalSince1970, reference.unix, accuracy: 30,
                           "\(reference.phase) at \(Date(timeIntervalSince1970: reference.unix))")
        }
        // The phases are in time order and the sequence cycles through the four kinds.
        for (earlier, later) in zip(found, found.dropFirst()) {
            XCTAssertLessThan(earlier.date, later.date)
            let index = PrincipalMoonPhase.allCases.firstIndex(of: earlier.kind) ?? -1
            XCTAssertEqual(later.kind, PrincipalMoonPhase.allCases[(index + 1) % 4])
            let gap = later.date.timeIntervalSince(earlier.date) / 86_400
            XCTAssertTrue((6.2...8.6).contains(gap), "gap of \(gap) days")
        }
    }

    func testIlluminationElongationAndAgeMatchSkyfield() throws {
        for sample in try fixture().samples {
            let date = EphemerisFixtureStore.date(universalJulianDate: sample.ut1Jd)
            let info = MoonPhaseCalculator.info(at: date)
            let label = "at \(sample.utc)"
            XCTAssertEqual(info.date, date)
            // The requirement is 0.003; the observed worst case is 3×10⁻⁵.
            XCTAssertEqual(info.illuminatedFraction, sample.illuminatedFraction, accuracy: 0.0005, label)
            XCTAssertEqual(info.phaseAngle, sample.phaseAngleDeg, accuracy: 0.02, label)
            XCTAssertEqual(AstroMath.normalizeSignedDegrees(info.elongation - sample.eclipticElongationDeg), 0,
                           accuracy: 0.005, label)
            XCTAssertEqual(info.ageDays, sample.ageDays, accuracy: 0.002, label)
            XCTAssertEqual(info.isWaxing, sample.eclipticElongationDeg < 180, label)
            XCTAssertEqual(info.name, MoonPhaseName(elongation: sample.eclipticElongationDeg), label)
        }
    }

    // MARK: Invariants

    func testInfoIsSelfConsistentAcrossTheSky() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for step in 0..<400 {
            let date = start.addingTimeInterval(Double(step) * 3 * 3600 + 417)
            let info = MoonPhaseCalculator.info(at: date)
            let label = "step \(step)"
            XCTAssertTrue((0...1).contains(info.illuminatedFraction), label)
            XCTAssertTrue((0...180).contains(info.phaseAngle), label)
            XCTAssertTrue((0..<360).contains(info.elongation), label)
            XCTAssertTrue((0...29.9).contains(info.ageDays), "\(label): age \(info.ageDays)")
            XCTAssertEqual(info.isWaxing, info.elongation < 180, label)
            XCTAssertEqual(info.name, MoonPhaseName(elongation: info.elongation), label)
            // The lit fraction is (1 + cos i)/2 with i the phase angle, and cos i ≈ −cos β cos Δλ for the Moon's
            // ecliptic latitude β (at most 5.3°) and the elongation Δλ; and it matches the body state.
            XCTAssertEqual(info.illuminatedFraction, (1 + cos(AstroMath.radians(info.phaseAngle))) / 2, accuracy: 1e-12, label)
            XCTAssertEqual(info.illuminatedFraction, (1 - cos(AstroMath.radians(info.elongation))) / 2, accuracy: 0.003, label)
            let state = Ephemeris.state(of: .moon, at: JulianDate(date: date))
            XCTAssertEqual(info.phaseAngle, state.phaseAngle ?? .nan, accuracy: 1e-9, label)
            XCTAssertEqual(info.isWaxing, state.isWaxing, label)
            // The age tracks the elongation at the mean rate of 12.19° a day, to within the periodic
            // variations of the Moon's and the Sun's motion at both ends (up to about ±17° or 1.4 days).
            let meanAge = info.elongation / (360 / MoonPhaseCalculator.meanSynodicMonthDays)
            XCTAssertEqual(info.ageDays, meanAge, accuracy: 1.4, label)
        }
    }

    func testAgeJustAfterAndJustBeforeNewMoon() throws {
        let phases = MoonPhaseCalculator.nextPhases(after: Date(timeIntervalSince1970: 1_790_000_000), count: 8)
        let newMoon = try XCTUnwrap(phases.first { $0.kind == .newMoon }).date
        let after = MoonPhaseCalculator.info(at: newMoon.addingTimeInterval(3600))
        XCTAssertEqual(after.ageDays, 1.0 / 24, accuracy: 0.002)
        XCTAssertEqual(after.name, .newMoon)
        // The Moon's latitude (up to 5°) keeps a sliver lit even at new moon.
        XCTAssertLessThan(after.illuminatedFraction, 0.003)
        let before = MoonPhaseCalculator.info(at: newMoon.addingTimeInterval(-3600))
        XCTAssertEqual(before.ageDays, MoonPhaseCalculator.meanSynodicMonthDays, accuracy: 0.5)
        XCTAssertEqual(before.name, .newMoon)
        let fullMoon = try XCTUnwrap(phases.first { $0.kind == .fullMoon }).date
        let full = MoonPhaseCalculator.info(at: fullMoon)
        XCTAssertEqual(full.name, .fullMoon)
        XCTAssertGreaterThan(full.illuminatedFraction, 0.995)
        XCTAssertEqual(full.ageDays, 14.77, accuracy: 0.8)
        XCTAssertEqual(full.phaseAngle, 0, accuracy: 6)
        let quarter = MoonPhaseCalculator.info(at: try XCTUnwrap(phases.first { $0.kind == .firstQuarter }).date)
        XCTAssertEqual(quarter.illuminatedFraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(quarter.name, .firstQuarter)
        XCTAssertTrue(quarter.isWaxing)
    }

    // MARK: nextPhases

    func testNextPhasesArgumentsAndPaging() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(MoonPhaseCalculator.nextPhases(after: start, count: 0).isEmpty)
        XCTAssertTrue(MoonPhaseCalculator.nextPhases(after: start, count: -3).isEmpty)
        XCTAssertTrue(MoonPhaseCalculator.nextPhases(after: Date(timeIntervalSince1970: .nan), count: 4).isEmpty)

        let eight = MoonPhaseCalculator.nextPhases(after: start, count: 8)
        XCTAssertEqual(eight.count, 8)
        XCTAssertGreaterThan(try XCTUnwrap(eight.first).date, start)
        XCTAssertLessThan(try XCTUnwrap(eight.first).date.timeIntervalSince(start), 9 * 86_400)
        XCTAssertEqual(Array(eight.prefix(3).map(\.date)), MoonPhaseCalculator.nextPhases(after: start, count: 3).map(\.date))

        // Passing the date of one phase returns the phases that follow it, not the same one again.
        for index in 0..<7 {
            let following = MoonPhaseCalculator.nextPhases(after: eight[index].date, count: 1)
            XCTAssertEqual(following.first?.kind, eight[index + 1].kind)
            XCTAssertEqual(following.first?.date.timeIntervalSince(eight[index + 1].date) ?? .nan, 0, accuracy: 0.05)
        }
        // A few seconds before a phase it is the next one.
        let justBefore = MoonPhaseCalculator.nextPhases(after: eight[2].date.addingTimeInterval(-5), count: 1)
        XCTAssertEqual(justBefore.first?.kind, eight[2].kind)

        let many = MoonPhaseCalculator.nextPhases(after: start, count: 5_000)
        XCTAssertEqual(many.count, MoonPhaseCalculator.maximumPhaseCount)
        // 1000 phases are 250 lunations, about 20 years.
        XCTAssertEqual(try XCTUnwrap(many.last).date.timeIntervalSince(start) / (365.25 * 86_400), 20.2, accuracy: 0.4)
    }

    func testPhasesInTheDistantPastAndFuture() {
        for year in [1700, 1900, 2100, 2300] {
            let start = JulianDate(ut: JulianDate.julianDay(year: year, month: 1, day: 1)).date
            let phases = MoonPhaseCalculator.nextPhases(after: start, count: 5)
            XCTAssertEqual(phases.count, 5, "year \(year)")
            var previous = start
            for phase in phases {
                XCTAssertGreaterThan(phase.date, previous, "year \(year)")
                XCTAssertLessThan(phase.date.timeIntervalSince(previous), 9 * 86_400, "year \(year)")
                previous = phase.date
            }
            let info = MoonPhaseCalculator.info(at: start)
            XCTAssertTrue((0...29.9).contains(info.ageDays), "year \(year)")
        }
    }
}

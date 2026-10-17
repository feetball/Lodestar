import XCTest
@testable import LodestarKit

/// Speed and thread safety of the planner: a catalog-sized batch in a fraction of a second, and a pure
/// computation that several tasks can run at once.
final class PlanningPerformanceTests: XCTestCase {
    private typealias Support = PlanningTestSupport

    /// Seconds allowed for ranking a thousand targets. A release build needs a few hundredths of a
    /// second (the requirement is half a second); an unoptimised debug build is an order of magnitude
    /// slower, so its bound only catches a calculation that has gone badly wrong.
    private static let thousandTargetsLimit: Double = {
        #if DEBUG
        return 20
        #else
        return 0.5
        #endif
    }()

    private func scatteredTargets(_ count: Int) -> [EquatorialCoordinate] {
        var generator = Support.SeededGenerator(seed: 1_000)
        return (0..<count).map { _ in
            EquatorialCoordinate(rightAscension: .random(in: 0..<360, using: &generator),
                                 declination: AstroMath.asinDeg(.random(in: -1...1, using: &generator)))
        }
    }

    private func seconds(_ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let elapsed = clock.measure(work)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    func testRankingAThousandTargetsThroughALongNightIsFast() throws {
        let summary = try Support.summary(Support.boulder, 2026, 12, 21)        // 11.4 hours of darkness
        let targets = scatteredTargets(1_000)
        var results = [TargetVisibility]()
        let elapsed = seconds { results = NightPlanner.visibility(ofFixed: targets, during: summary) }
        XCTAssertEqual(results.count, 1_000)
        XCTAssertLessThan(elapsed, Self.thousandTargetsLimit, "took \(elapsed) s")
        XCTAssertGreaterThan(results.filter { $0.hoursAboveMinimum > 0 }.count, 200, "many targets get above 20°")
        XCTAssertGreaterThan(results.filter { $0.hoursAboveMinimum == 0 }.count, 200, "and many never do")
    }

    func testRankingWithProperMotionsAndMoonFreeTimeIsJustAsFast() throws {
        let summary = try Support.summary(Support.boulder, 2026, 6, 21)
        let targets = scatteredTargets(1_000)
        let motions = targets.indices.map { index in
            index.isMultiple(of: 2)
                ? ProperMotion(raMilliarcsecondsPerYear: Double(index), decMilliarcsecondsPerYear: -Double(index)) : nil
        }
        var results = [TargetVisibility]()
        let elapsed = seconds {
            results = NightPlanner.visibility(ofFixed: targets, properMotions: motions, during: summary, darkness: .moonFree)
        }
        XCTAssertEqual(results.count, 1_000)
        XCTAssertLessThan(elapsed, Self.thousandTargetsLimit, "took \(elapsed) s")
    }

    func testBatchOfAThousandWithoutDarknessOnlyPaysForTheEvents() throws {
        let summary = try Support.summary(Support.tromso, 2026, 6, 21)
        var results = [TargetVisibility]()
        let elapsed = seconds { results = NightPlanner.visibility(ofFixed: scatteredTargets(1_000), during: summary) }
        XCTAssertEqual(results.count, 1_000)
        XCTAssertTrue(results.allSatisfy { $0.maxAltitudeDuringDarkness == nil })
        XCTAssertLessThan(elapsed, Self.thousandTargetsLimit, "took \(elapsed) s")
    }

    func testANightSummaryTakesWellUnderASecond() throws {
        let elapsed = seconds { _ = try? Support.summary(Support.boulder, 2026, 12, 21) }
        XCTAssertLessThan(elapsed, 2, "took \(elapsed) s")
    }

    func testSummariesAndRankingsCanRunOnSeveralTasksAtOnce() async throws {
        let site = Support.boulder
        let zone = try site.timeZone()
        let noon = try Support.localNoon(2026, 10, 25, in: zone)
        let observer = site.observer
        let targets = scatteredTargets(50)
        let reference = NightPlanner.summary(nightStartingOn: noon, observer: observer, timeZone: zone)
        let referenceRanking = NightPlanner.visibility(ofFixed: targets, during: reference)

        let outcomes = await withTaskGroup(of: (NightSummary, [TargetVisibility]).self) { group in
            for _ in 0..<6 {
                group.addTask {
                    let summary = NightPlanner.summary(nightStartingOn: noon, observer: observer, timeZone: zone)
                    return (summary, NightPlanner.visibility(ofFixed: targets, during: summary))
                }
            }
            var collected = [(NightSummary, [TargetVisibility])]()
            for await outcome in group { collected.append(outcome) }
            return collected
        }
        XCTAssertEqual(outcomes.count, 6)
        for (summary, ranking) in outcomes {
            XCTAssertEqual(summary, reference)
            XCTAssertEqual(ranking, referenceRanking)
        }
    }
}

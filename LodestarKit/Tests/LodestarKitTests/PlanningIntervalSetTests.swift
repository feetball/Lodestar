import XCTest
@testable import LodestarKit

final class PlanningIntervalSetTests: XCTestCase {
    private typealias Sets = NightPlanner.IntervalSet

    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func span(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: origin.addingTimeInterval(start), end: origin.addingTimeInterval(end))
    }

    // MARK: Examples

    func testNormalizedSortsAndMergesOverlappingAndTouchingIntervals() {
        let messy = [span(30, 40), span(0, 10), span(5, 12), span(12, 20), span(35, 36), span(50, 50)]
        XCTAssertEqual(Sets.normalized(messy), [span(0, 20), span(30, 40)])
        XCTAssertEqual(Sets.normalized([]), [])
    }

    func testNormalizedDropsIntervalsWithoutFiniteEnds() {
        let endless = DateInterval(start: origin, end: Date(timeIntervalSinceReferenceDate: .infinity))
        let beginningless = DateInterval(start: Date(timeIntervalSinceReferenceDate: -.infinity), duration: 10)
        let undefined = DateInterval(start: Date(timeIntervalSinceReferenceDate: .nan), duration: 10)
        XCTAssertEqual(Sets.normalized([endless, beginningless, undefined, span(1, 1), span(2, 3)]), [span(2, 3)])
        XCTAssertEqual(Sets.intersection([undefined, span(0, 10)], [span(5, 20)]), [span(5, 10)])
        XCTAssertEqual(Sets.subtracting([undefined], from: [span(0, 10)]), [span(0, 10)])
        XCTAssertEqual(Sets.totalDuration(of: [undefined, endless, span(0, 4)]), 4)
    }

    func testIntersectionKeepsOnlyTimeCoveredByBothSets() {
        let first = [span(0, 10), span(20, 30)]
        let second = [span(5, 25), span(28, 40)]
        XCTAssertEqual(Sets.intersection(first, second), [span(5, 10), span(20, 25), span(28, 30)])
        XCTAssertEqual(Sets.intersection(first, []), [])
        XCTAssertEqual(Sets.intersection([span(0, 10)], [span(10, 20)]), [], "intervals that only touch share no time")
    }

    func testSubtractingRemovesCoveredTimeAndSplitsIntervals() {
        let base = [span(0, 100)]
        XCTAssertEqual(Sets.subtracting([span(10, 20), span(40, 50)], from: base),
                       [span(0, 10), span(20, 40), span(50, 100)])
        XCTAssertEqual(Sets.subtracting([span(-5, 120)], from: base), [])
        XCTAssertEqual(Sets.subtracting([], from: base), base)
        XCTAssertEqual(Sets.subtracting([span(0, 30)], from: base), [span(30, 100)])
        XCTAssertEqual(Sets.subtracting([span(70, 200)], from: base), [span(0, 70)])
    }

    func testTotalDurationCountsOverlapOnce() {
        XCTAssertEqual(Sets.totalDuration(of: [span(0, 10), span(5, 20), span(30, 31)]), 21, accuracy: 1e-9)
        XCTAssertEqual(Sets.totalDuration(of: []), 0)
    }

    // MARK: Randomised comparison with membership tests

    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private func randomSet(_ generator: inout Generator) -> [DateInterval] {
        (0..<generator.next(6)).map { _ in
            let start = generator.next(95)
            return span(Double(start), Double(start + 1 + generator.next(30)))
        }
    }

    private func contains(_ intervals: [DateInterval], _ seconds: Double) -> Bool {
        let instant = origin.addingTimeInterval(seconds)
        return intervals.contains { $0.start <= instant && instant < $0.end }
    }

    /// Endpoints are whole seconds, so probing at half seconds avoids every boundary.
    func testSetOperationsAgreeWithPointwiseMembership() {
        var generator = Generator(state: 2026)
        for round in 0..<300 {
            let first = randomSet(&generator), second = randomSet(&generator)
            let union = Sets.normalized(first + second)
            let both = Sets.intersection(first, second)
            let onlyFirst = Sets.subtracting(second, from: first)
            for tick in 0..<130 {
                let probe = Double(tick) + 0.5
                let inFirst = contains(first, probe), inSecond = contains(second, probe)
                XCTAssertEqual(contains(union, probe), inFirst || inSecond, "union, round \(round) at \(probe)")
                XCTAssertEqual(contains(both, probe), inFirst && inSecond, "intersection, round \(round) at \(probe)")
                XCTAssertEqual(contains(onlyFirst, probe), inFirst && !inSecond, "difference, round \(round) at \(probe)")
            }
            for result in [union, both, onlyFirst] {
                XCTAssertTrue(result.allSatisfy { $0.duration > 0 }, "round \(round)")
                for (earlier, later) in zip(result, result.dropFirst()) {
                    XCTAssertLessThan(earlier.end, later.start, "disjoint and not touching, round \(round)")
                }
            }
        }
    }
}

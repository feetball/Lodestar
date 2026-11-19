import XCTest
@testable import LodestarKit

final class SkyQualityScoreTests: XCTestCase {
    typealias Support = PlanningTestSupport

    /// An estimate of the given class (a glow index at the start of its band).
    func bortle(_ bortleClass: Int) -> BortleEstimate {
        let estimate = BortleEstimate(skyGlowIndex: bortleClass == 1 ? 0 : BortleEstimate.glowThresholds[bortleClass - 2],
                                      level: 0)
        XCTAssertEqual(estimate.bortleClass, bortleClass)
        return estimate
    }

    func score(dark: Double = 9, moonFree: Double = 9, lit: Double = 0, bortleClass: Int = 1,
               clouds: Double? = 0) -> ImagingScore {
        SkyQualityScore.imaging(astronomicalDarkHours: dark, moonFreeDarkHours: moonFree, moonIlluminatedFraction: lit,
                                bortle: bortle(bortleClass), cloudFraction: clouds)
    }

    func testTheIdealNightScoresTenAndTheWorstZero() {
        let ideal = score()
        XCTAssertEqual(ideal.total, 10, accuracy: 1e-12)
        XCTAssertEqual(ideal.rating, .excellent)
        let worst = score(dark: 0, moonFree: 0, lit: 1, bortleClass: 9, clouds: 1)
        XCTAssertEqual(worst.total, 0, accuracy: 1e-12)
        XCTAssertEqual(worst.rating, .poor)
        XCTAssertEqual(score(dark: 0, moonFree: 0, bortleClass: 9, clouds: 1).total, 0, accuracy: 1e-12)
    }

    func testComponentsSumToTheTotalAndTheirWeightsToTen() {
        for clouds in [nil, 0.0, 0.4, 1.0] as [Double?] {
            let result = score(dark: 4.5, moonFree: 3, lit: 0.6, bortleClass: 5, clouds: clouds)
            XCTAssertEqual(result.total, result.components.reduce(0) { $0 + $1.points }, accuracy: 1e-12)
            XCTAssertEqual(result.components.reduce(0) { $0 + $1.weight }, 10, accuracy: 1e-12)
            for part in result.components {
                XCTAssertEqual(part.weight * part.quality, part.points, accuracy: 1e-12)
                XCTAssertTrue((0.0...1.0).contains(part.quality) && (0.0...(part.weight + 1e-12)).contains(part.points))
            }
            let kinds: [ImagingScoreComponentKind] = [.darknessHours, .moon, .skyBrightness]
                + (clouds == nil ? [] : [.clouds])
            XCTAssertEqual(result.components.map(\.kind), kinds)
        }
    }

    func testKnownNightWithAForecast() throws {
        // 4.5 h dark: 0.75; the Moon is up 1.5 of those hours at 60 % lit: 1 - (1/3) * 0.6 = 0.8; Bortle 5: 0.5; clouds 25 %: 0.75.
        let result = score(dark: 4.5, moonFree: 3, lit: 0.6, bortleClass: 5, clouds: 0.25)
        XCTAssertEqual(result.components.map(\.weight), [2, 3, 2, 3])
        XCTAssertEqual(result.components.map(\.quality), [0.75, 0.8, 0.5, 0.75])
        XCTAssertEqual(result.components.map { ($0.points * 1e9).rounded() / 1e9 }, [1.5, 2.4, 1.0, 2.25])
        XCTAssertEqual(result.total, 7.15, accuracy: 1e-12)
        XCTAssertTrue(result.includesClouds)
        XCTAssertEqual(result.rating, .good)
        XCTAssertEqual(try XCTUnwrap(result.component(.clouds)).quality, 0.75, accuracy: 1e-12)
    }

    func testKnownNightWithoutAForecastScalesTheWeightsToTen() {
        let result = score(dark: 4.5, moonFree: 3, lit: 0.6, bortleClass: 5, clouds: nil)
        XCTAssertFalse(result.includesClouds)
        XCTAssertNil(result.component(.clouds))
        XCTAssertEqual(result.components.map(\.weight), [20.0 / 7, 30.0 / 7, 20.0 / 7])
        XCTAssertEqual(result.total, 7, accuracy: 1e-12)
        // A forecast that is not a number is no forecast.
        XCTAssertEqual(result, score(dark: 4.5, moonFree: 3, lit: 0.6, bortleClass: 5, clouds: .nan))
        // A forecast outside 0-1 is limited to it.
        XCTAssertEqual(score(clouds: 1), score(clouds: 7))
        XCTAssertEqual(score(clouds: 0), score(clouds: -3))
    }

    func testEachPartMovesTheScoreTheRightWay() {
        XCTAssertGreaterThan(score(clouds: 0.2).total, score(clouds: 0.6).total)
        for bortleClass in 1..<9 {
            XCTAssertGreaterThan(score(bortleClass: bortleClass).total, score(bortleClass: bortleClass + 1).total)
        }
        XCTAssertGreaterThan(score(moonFree: 4, lit: 0.1).total, score(moonFree: 4, lit: 0.9).total)
        XCTAssertGreaterThan(score(moonFree: 8, lit: 0.8).total, score(moonFree: 2, lit: 0.8).total)
        XCTAssertLessThan(score(dark: 3, moonFree: 3).total, score(dark: 5, moonFree: 5).total)
        // Six hours is enough: more earns nothing.
        XCTAssertEqual(score(dark: 6, moonFree: 6).total, score(dark: 12, moonFree: 12).total, accuracy: 1e-12)
        // A bright Moon that is up for an hour of a long night costs little; a new Moon costs nothing.
        XCTAssertGreaterThan(score(dark: 9, moonFree: 8, lit: 1).total, 9)
        XCTAssertEqual(score(dark: 9, moonFree: 0, lit: 0).total, 10, accuracy: 1e-12)
    }

    func testNoDarknessMeansNoDarknessAndNoMoonCredit() throws {
        let result = score(dark: 0, moonFree: 0, lit: 0, bortleClass: 1, clouds: 0)
        XCTAssertEqual(try XCTUnwrap(result.component(.darknessHours)).quality, 0)
        XCTAssertEqual(try XCTUnwrap(result.component(.moon)).quality, 0)
        XCTAssertEqual(result.total, 5, accuracy: 1e-12)
    }

    func testInputsThatAreOutOfRangeAreLimited() {
        XCTAssertEqual(score(dark: 0, moonFree: 0), score(dark: -4, moonFree: 2))
        XCTAssertEqual(score(dark: 0, moonFree: 0), score(dark: .nan, moonFree: 2))
        XCTAssertEqual(score(dark: 5, moonFree: 5), score(dark: 5, moonFree: 9))
        XCTAssertEqual(score(dark: 5, moonFree: 0), score(dark: 5, moonFree: .nan))
        XCTAssertEqual(score(moonFree: 3, lit: 1), score(moonFree: 3, lit: 4))
        XCTAssertEqual(score(moonFree: 3, lit: 0), score(moonFree: 3, lit: .nan))
    }

    func testRatingsHaveTheirBoundaries() {
        XCTAssertEqual(ImagingRating(score: 2.99), .poor)
        XCTAssertEqual(ImagingRating(score: 3), .fair)
        XCTAssertEqual(ImagingRating(score: 5.49), .fair)
        XCTAssertEqual(ImagingRating(score: 5.5), .good)
        XCTAssertEqual(ImagingRating(score: 7.99), .good)
        XCTAssertEqual(ImagingRating(score: 8), .excellent)
        XCTAssertEqual(ImagingRating(score: 10), .excellent)
        XCTAssertEqual(ImagingRating(score: .nan), .poor)
        for kind in ImagingScoreComponentKind.allCases {
            XCTAssertEqual(ImagingScoreComponentKind(rawValue: kind.rawValue), kind)
        }
        for rating in ImagingRating.allCases { XCTAssertEqual(ImagingRating(rawValue: rating.rawValue), rating) }
        XCTAssertNil(ImagingScoreComponentKind(rawValue: "sky"))
        XCTAssertNil(ImagingRating(rawValue: "great"))
    }

    func testScoreOfARealNightReadsTheSummary() throws {
        // Boulder: new moon on 10 October 2026 and full moon on 26 October (see PlanningNightSummaryTests).
        let newMoon = try Support.summary(Support.boulder, 2026, 10, 10)
        let fullMoon = try Support.summary(Support.boulder, 2026, 10, 25)
        let sky = bortle(3)
        let dark = SkyQualityScore.imaging(night: newMoon, bortle: sky, cloudFraction: 0.1)
        let bright = SkyQualityScore.imaging(night: fullMoon, bortle: sky, cloudFraction: 0.1)
        XCTAssertEqual(dark, SkyQualityScore.imaging(astronomicalDarkHours: newMoon.astronomicalDarkHours,
                                                     moonFreeDarkHours: newMoon.moonFreeDarkHours,
                                                     moonIlluminatedFraction: newMoon.moon.illuminatedFraction,
                                                     bortle: sky, cloudFraction: 0.1))
        XCTAssertGreaterThan(dark.total, 8, "new moon: \(dark.total)")
        XCTAssertLessThan(bright.total, 6, "full moon: \(bright.total)")
        XCTAssertLessThan(try XCTUnwrap(bright.component(.moon)).quality, 0.02)
        XCTAssertGreaterThan(try XCTUnwrap(dark.component(.moon)).quality, 0.97)
        XCTAssertEqual(try XCTUnwrap(dark.component(.darknessHours)).quality, 1, accuracy: 1e-12)
    }
}

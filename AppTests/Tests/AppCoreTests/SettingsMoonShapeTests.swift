import CoreGraphics
import Foundation
import XCTest
@testable import AppCore

/// `SkyChartMoonShape.litOutline`: the outline of the lit part of the Moon's disc.
///
/// With the Sun at angle 0 (towards +x on the screen) the first 25 points run along the limb from the top of the disc
/// (-y) through the Sun's side (+x) to the bottom (+y); the last 25 run back along the terminator.
final class SettingsMoonShapeTests: XCTestCase {
    private let center = CGPoint(x: 100, y: 50)
    private let radius: CGFloat = 10

    private func outline(_ fraction: Double, angle: Double = 0, radius: CGFloat = 10) -> [CGPoint] {
        SkyChartMoonShape.litOutline(center: center, radius: radius, fraction: fraction, towardsSun: angle)
    }

    private func distanceFromCenter(_ point: CGPoint) -> CGFloat {
        let dx = point.x - center.x, dy = point.y - center.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func assertPoint(_ point: CGPoint, _ x: CGFloat, _ y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: Shape of the outline

    func testTheOutlineHasFiftyPointsForEveryFraction() {
        for fraction in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0] {
            XCTAssertEqual(outline(fraction).count, 50, "fraction \(fraction)")
        }
    }

    func testTheLimbRunsFromTheTopThroughTheSunsSideToTheBottom() {
        let points = outline(0.5)
        assertPoint(points[0], 100, 40)
        assertPoint(points[12], 110, 50)
        assertPoint(points[24], 100, 60)
        for point in points[0...24] {
            XCTAssertEqual(distanceFromCenter(point), radius, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(point.x, center.x - 1e-9)
        }
    }

    func testAHalfMoonHasAStraightTerminatorThroughTheCenter() {
        let points = outline(0.5)
        assertPoint(points[25], 100, 60)
        assertPoint(points[49], 100, 40)
        for point in points[25...49] {
            XCTAssertEqual(point.x, 100, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(point.y, 40 - 1e-9)
            XCTAssertLessThanOrEqual(point.y, 60 + 1e-9)
        }
    }

    func testACrescentHasATerminatorThatBulgesTowardsTheSun() {
        let points = outline(0.25)
        for point in points[25...49] {
            XCTAssertGreaterThanOrEqual(point.x, center.x - 1e-9)
        }
        // The middle of the terminator is half a radius from the center, on the Sun's side.
        assertPoint(points[37], 105, 50)
    }

    func testAGibbousMoonHasATerminatorThatBulgesAwayFromTheSun() {
        let points = outline(0.75)
        for point in points[25...49] {
            XCTAssertLessThanOrEqual(point.x, center.x + 1e-9)
        }
        assertPoint(points[37], 95, 50)
    }

    func testANewMoonHasNoAreaTheTerminatorRetracesTheLimb() {
        let points = outline(0)
        for step in 0...24 {
            XCTAssertEqual(points[24 - step].x, points[25 + step].x, accuracy: 1e-9, "step \(step)")
            XCTAssertEqual(points[24 - step].y, points[25 + step].y, accuracy: 1e-9, "step \(step)")
        }
    }

    func testAFullMoonIsTheWholeDisc() {
        let points = outline(1)
        for point in points {
            XCTAssertEqual(distanceFromCenter(point), radius, accuracy: 1e-9)
        }
        // The terminator is the half of the circle away from the Sun.
        for point in points[25...49] {
            XCTAssertLessThanOrEqual(point.x, center.x + 1e-9)
        }
        assertPoint(points[37], 90, 50)
    }

    func testTheTerminatorWidthGrowsWithTheFraction() {
        let middles = [0.0, 0.25, 0.5, 0.75, 1.0].map { outline($0)[37].x }
        for (smaller, larger) in zip(middles, middles.dropFirst()) {
            XCTAssertLessThan(larger, smaller)
        }
        assertPoint(outline(0)[37], 110, 50)
    }

    // MARK: Fraction and direction

    func testAFractionOutsideZeroToOneIsClamped() {
        XCTAssertEqual(outline(-3), outline(0))
        XCTAssertEqual(outline(-0.0001), outline(0))
        XCTAssertEqual(outline(7), outline(1))
        XCTAssertEqual(outline(1.0001), outline(1))
    }

    func testTheOutlineTurnsWithTheDirectionOfTheSun() {
        // x right, y down: a quarter turn puts the Sun below the Moon.
        assertPoint(outline(0.5, angle: .pi / 2)[12], 100, 60)
        assertPoint(outline(0.5, angle: .pi)[12], 90, 50)
        assertPoint(outline(0.5, angle: -.pi / 2)[12], 100, 40)
        assertPoint(outline(0.5, angle: 0)[12], 110, 50)
    }

    func testTurningTheSunARoundTheDiscKeepsEveryLimbPointOnTheCircle() {
        for angle in stride(from: -Double.pi, through: Double.pi, by: Double.pi / 6) {
            for point in outline(0.3, angle: angle)[0...24] {
                XCTAssertEqual(distanceFromCenter(point), radius, accuracy: 1e-9, "angle \(angle)")
            }
        }
    }

    func testTheTerminatorTurnsWithTheSunToo() {
        let points = outline(0.5, angle: .pi / 2)
        // The straight terminator of a half Moon is then the horizontal diameter.
        for point in points[25...49] {
            XCTAssertEqual(point.y, 50, accuracy: 1e-9)
        }
        assertPoint(points[25], 90, 50)
        assertPoint(points[49], 110, 50)
    }

    // MARK: Size

    func testTheOutlineScalesWithTheRadius() {
        let points = outline(0.5, radius: 20)
        assertPoint(points[12], 120, 50)
        assertPoint(points[0], 100, 30)
    }

    func testAZeroRadiusCollapsesToTheCenter() {
        for point in outline(0.4, angle: 1, radius: 0) {
            assertPoint(point, 100, 50)
        }
    }
}

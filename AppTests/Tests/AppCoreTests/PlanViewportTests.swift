import CoreGraphics
import Foundation
import XCTest
@testable import AppCore

/// How the planisphere is placed on the screen: size, zoom, pan and rotation.
final class PlanViewportTests: XCTestCase {
    /// A tall phone-like view: the base radius is 400 / 2 - 26 = 174.
    private let tall = CGSize(width: 400, height: 800)
    /// A square view with a round base radius: 452 / 2 - 26 = 200.
    private let square = CGSize(width: 452, height: 452)

    private func assertPoint(_ point: CGPoint, _ x: Double, _ y: Double, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(point.x), x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(point.y), y, accuracy: accuracy, file: file, line: line)
    }

    private func assertSize(_ size: CGSize, _ width: Double, _ height: Double, accuracy: Double = 1e-9,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(size.width), width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(size.height), height, accuracy: accuracy, file: file, line: line)
    }

    // MARK: Constants and the base radius

    func testTheZoomRangeIsOneToFifteenAndTheRimMarginIsTwentySix() {
        XCTAssertEqual(PlanisphereViewport.zoomRange.lowerBound, 1)
        XCTAssertEqual(PlanisphereViewport.zoomRange.upperBound, 15)
        XCTAssertTrue(PlanisphereViewport.zoomRange.contains(1))
        XCTAssertTrue(PlanisphereViewport.zoomRange.contains(15))
        XCTAssertFalse(PlanisphereViewport.zoomRange.contains(0.99))
        XCTAssertFalse(PlanisphereViewport.zoomRange.contains(15.01))
        XCTAssertEqual(PlanisphereViewport.rimMargin, 26)
    }

    func testTheBaseRadiusFillsTheShorterSideLessTheRimMargin() {
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: tall)), 174, accuracy: 1e-9)
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: CGSize(width: 800, height: 400))), 174, accuracy: 1e-9)
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: square)), 200, accuracy: 1e-9)
    }

    func testTheBaseRadiusHasAFloorOfForty() {
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: CGSize(width: 100, height: 100))), 40, accuracy: 1e-9)
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: .zero)), 40, accuracy: 1e-9)
        // 132 / 2 - 26 = 40 exactly, 134 / 2 - 26 = 41.
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: CGSize(width: 132, height: 500))), 40, accuracy: 1e-9)
        XCTAssertEqual(Double(PlanisphereViewport.baseRadius(in: CGSize(width: 134, height: 500))), 41, accuracy: 1e-9)
    }

    // MARK: Initialiser

    func testTheDefaultViewportPutsTheZenithInTheMiddleOfTheView() {
        let viewport = PlanisphereViewport(size: tall)
        XCTAssertEqual(viewport.size, tall)
        XCTAssertEqual(Double(viewport.zoom), 1, accuracy: 1e-12)
        XCTAssertEqual(viewport.pan, .zero)
        XCTAssertEqual(viewport.rotation, 0, accuracy: 1e-12)
        XCTAssertEqual(Double(viewport.radius), 174, accuracy: 1e-9)
        assertPoint(viewport.center, 200, 400)
        XCTAssertEqual(Double(viewport.cosine), 1, accuracy: 1e-12)
        XCTAssertEqual(Double(viewport.sine), 0, accuracy: 1e-12)
    }

    func testZoomScalesTheRadiusAndPanMovesTheCentre() {
        let viewport = PlanisphereViewport(size: tall, zoom: 3, pan: CGSize(width: 10, height: -20))
        XCTAssertEqual(Double(viewport.radius), 522, accuracy: 1e-9)
        assertPoint(viewport.center, 210, 380)
    }

    func testRotationStoresItsCosineAndSine() {
        let viewport = PlanisphereViewport(size: tall, rotation: .pi / 2)
        XCTAssertEqual(Double(viewport.cosine), 0, accuracy: 1e-12)
        XCTAssertEqual(Double(viewport.sine), 1, accuracy: 1e-12)
        XCTAssertEqual(viewport.rotation, .pi / 2, accuracy: 1e-12)
    }

    func testAZeroSizeViewDoesNotDivideByZero() {
        let viewport = PlanisphereViewport(size: .zero, zoom: 3)
        XCTAssertEqual(Double(viewport.radius), 120, accuracy: 1e-9)
        assertPoint(viewport.center, 0, 0)
        assertPoint(viewport.middle, 0, 0)
        assertPoint(viewport.screen(CGPoint(x: 1, y: 0)), 120, 0)
        assertPoint(viewport.chartPoint(atScreen: CGPoint(x: 120, y: 0)), 1, 0)
        let back = viewport.chartPoint(atScreen: CGPoint(x: 55, y: -33))
        XCTAssertTrue(back.x.isFinite && back.y.isFinite)
        XCTAssertEqual(viewport.discRect, CGRect(x: -120, y: -120, width: 240, height: 240))
        XCTAssertEqual(Double(viewport.pointsPerRadian(at: .zero)), 60, accuracy: 1e-9)
    }

    func testViewportsAreEqualWhenAllInputsAreEqual() {
        let a = PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 5, height: 6), rotation: 0.5)
        let b = PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 5, height: 6), rotation: 0.5)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, PlanisphereViewport(size: tall, zoom: 2.5, pan: CGSize(width: 5, height: 6), rotation: 0.5))
        XCTAssertNotEqual(a, PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 5, height: 7), rotation: 0.5))
        XCTAssertNotEqual(a, PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 5, height: 6), rotation: 0.6))
        XCTAssertNotEqual(a, PlanisphereViewport(size: square, zoom: 2, pan: CGSize(width: 5, height: 6), rotation: 0.5))
    }

    // MARK: Chart to screen

    func testTheCardinalDirectionsLandOnTheHorizonCircle() {
        let viewport = PlanisphereViewport(size: tall)
        assertPoint(viewport.screen(CGPoint(x: 0, y: 0)), 200, 400)
        // North at the top, east on the left, south at the bottom, west on the right.
        assertPoint(viewport.screen(CGPoint(x: 0, y: -1)), 200, 226)
        assertPoint(viewport.screen(CGPoint(x: -1, y: 0)), 26, 400)
        assertPoint(viewport.screen(CGPoint(x: 0, y: 1)), 200, 574)
        assertPoint(viewport.screen(CGPoint(x: 1, y: 0)), 374, 400)
    }

    func testZoomAndPanMoveTheScreenPositions() {
        let viewport = PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 30, height: -10))
        // Centre (230, 390), radius 348.
        assertPoint(viewport.screen(.zero), 230, 390)
        assertPoint(viewport.screen(CGPoint(x: 0, y: -1)), 230, 42)
        assertPoint(viewport.screen(CGPoint(x: 0.5, y: 0.25)), 404, 477)
    }

    func testARotationOfNinetyDegreesTurnsTheChartClockwise() {
        let viewport = PlanisphereViewport(size: tall, rotation: .pi / 2)
        // North moves from the top to the right, east from the left to the top.
        assertPoint(viewport.screen(CGPoint(x: 0, y: -1)), 374, 400)
        assertPoint(viewport.screen(CGPoint(x: -1, y: 0)), 200, 226)
        assertPoint(viewport.screen(CGPoint(x: 0, y: 1)), 26, 400)
    }

    func testARotationOfOneHundredEightyDegreesPutsNorthAtTheBottom() {
        let viewport = PlanisphereViewport(size: tall, rotation: .pi)
        assertPoint(viewport.screen(CGPoint(x: 0, y: -1)), 200, 574)
        assertPoint(viewport.screen(CGPoint(x: -1, y: 0)), 374, 400)
    }

    func testTheZenithStaysAtTheCentreWhateverTheRotation() {
        for rotation in [0.0, 0.4, 1.1, 3.0, -2.2] {
            let viewport = PlanisphereViewport(size: tall, zoom: 4, pan: CGSize(width: 12, height: -9), rotation: rotation)
            assertPoint(viewport.screen(.zero), 212, 391)
        }
    }

    // MARK: Screen to chart

    func testChartPointAtScreenInvertsScreen() {
        let viewport = PlanisphereViewport(size: tall, zoom: 3, pan: CGSize(width: 10, height: -20), rotation: 0.7)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 0.3, y: -0.8), CGPoint(x: -1, y: 0.5), CGPoint(x: 2.5, y: 4)] {
            let back = viewport.chartPoint(atScreen: viewport.screen(point))
            assertPoint(back, Double(point.x), Double(point.y), accuracy: 1e-9)
        }
    }

    func testScreenInvertsChartPointAtScreen() {
        let viewport = PlanisphereViewport(size: tall, zoom: 5, pan: CGSize(width: -40, height: 25), rotation: -1.3)
        for position in [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 400), CGPoint(x: 399, y: 12), CGPoint(x: -50, y: 900)] {
            let back = viewport.screen(viewport.chartPoint(atScreen: position))
            assertPoint(back, Double(position.x), Double(position.y), accuracy: 1e-9)
        }
    }

    func testTheCentreOfTheViewIsTheZenithOnlyWhenNotPanned() {
        let still = PlanisphereViewport(size: tall)
        assertPoint(still.chartPoint(atScreen: still.middle), 0, 0)
        let panned = PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 87, height: 0))
        // The screen centre is now 87 / 348 = 0.25 chart units to the left of the zenith.
        assertPoint(panned.chartPoint(atScreen: panned.middle), -0.25, 0)
        assertPoint(panned.chartPoint(atScreen: panned.center), 0, 0)
    }

    // MARK: Geometry helpers

    func testTheDiscRectBoundsTheHorizonCircle() {
        XCTAssertEqual(PlanisphereViewport(size: tall).discRect, CGRect(x: 26, y: 226, width: 348, height: 348))
        let zoomed = PlanisphereViewport(size: tall, zoom: 2, pan: CGSize(width: 30, height: -10))
        XCTAssertEqual(zoomed.discRect, CGRect(x: -118, y: 42, width: 696, height: 696))
    }

    func testTheMiddleIgnoresPanAndZoom() {
        let viewport = PlanisphereViewport(size: tall, zoom: 6, pan: CGSize(width: 50, height: 50), rotation: 2)
        assertPoint(viewport.middle, 200, 400)
    }

    func testPointsPerRadianGrowsTowardsTheHorizon() {
        let viewport = PlanisphereViewport(size: tall)
        XCTAssertEqual(Double(viewport.pointsPerRadian(at: .zero)), 87, accuracy: 1e-9)
        XCTAssertEqual(Double(viewport.pointsPerRadian(at: CGPoint(x: 1, y: 0))), 174, accuracy: 1e-9)
        XCTAssertEqual(Double(viewport.pointsPerRadian(at: CGPoint(x: 0, y: -1))), 174, accuracy: 1e-9)
        // 174 * (1 + 0.25) / 2.
        XCTAssertEqual(Double(viewport.pointsPerRadian(at: CGPoint(x: 0.5, y: 0))), 108.75, accuracy: 1e-9)
        // Twice the zoom, twice the scale.
        let zoomed = PlanisphereViewport(size: tall, zoom: 2)
        XCTAssertEqual(Double(zoomed.pointsPerRadian(at: CGPoint(x: 0.5, y: 0))), 217.5, accuracy: 1e-9)
    }

    func testARimPointLiesOutsideTheHorizonCircleTowardsTheAzimuth() {
        let viewport = PlanisphereViewport(size: tall)
        assertPoint(viewport.rimPoint(azimuth: 0, outside: 26), 200, 200)
        assertPoint(viewport.rimPoint(azimuth: 90, outside: 26), 0, 400)
        assertPoint(viewport.rimPoint(azimuth: 180, outside: 26), 200, 600)
        assertPoint(viewport.rimPoint(azimuth: 270, outside: 26), 400, 400)
        assertPoint(viewport.rimPoint(azimuth: 0, outside: 0), 200, 226)
    }

    func testARimPointKeepsItsDistanceFromTheRimWhenZoomed() {
        let viewport = PlanisphereViewport(size: tall, zoom: 2)
        // Radius 348: the point is still 26 points beyond the circle, here at the top.
        assertPoint(viewport.rimPoint(azimuth: 0, outside: 26), 200, 26)
    }

    func testARimPointFollowsTheRotation() {
        let viewport = PlanisphereViewport(size: tall, rotation: .pi / 2)
        // North is on the right of the screen now.
        assertPoint(viewport.rimPoint(azimuth: 0, outside: 26), 400, 400)
    }

    // MARK: Pan while zooming

    func testZoomingAboutTheMiddleOfTheViewKeepsAZeroPan() {
        let pan = PlanisphereViewport.pan(.zero, keeping: CGPoint(x: 200, y: 400), fixedIn: tall, from: 1, to: 2)
        assertSize(pan, 0, 0)
    }

    func testZoomingAboutAnAnchorShiftsThePanSoTheAnchorStaysPut() {
        // The anchor is 100 points right of the middle; doubling the zoom moves it to 200 unless the chart shifts left.
        let pan = PlanisphereViewport.pan(.zero, keeping: CGPoint(x: 300, y: 400), fixedIn: tall, from: 1, to: 2)
        assertSize(pan, -100, 0)
    }

    func testZoomingAboutTheMiddleScalesAnExistingPan() {
        let pan = PlanisphereViewport.pan(CGSize(width: 10, height: -20), keeping: CGPoint(x: 200, y: 400),
                                          fixedIn: tall, from: 1, to: 2)
        assertSize(pan, 20, -40)
    }

    func testZoomingOutUndoesZoomingIn() {
        let anchor = CGPoint(x: 300, y: 400)
        let zoomedIn = PlanisphereViewport.pan(.zero, keeping: anchor, fixedIn: tall, from: 1, to: 2)
        let back = PlanisphereViewport.pan(zoomedIn, keeping: anchor, fixedIn: tall, from: 2, to: 1)
        assertSize(back, 0, 0)
    }

    func testTheChartPointUnderTheAnchorDoesNotMoveWhenTheZoomChanges() {
        let anchors = [CGPoint(x: 300, y: 400), CGPoint(x: 20, y: 90), CGPoint(x: 380, y: 760), CGPoint(x: 200, y: 400)]
        let steps: [(CGFloat, CGFloat)] = [(1, 2), (2, 3.5), (3.5, 15), (15, 4), (4, 1)]
        for anchor in anchors {
            var pan = CGSize(width: 14, height: -9)
            for (oldZoom, newZoom) in steps {
                let before = PlanisphereViewport(size: tall, zoom: oldZoom, pan: pan, rotation: 0.9)
                let anchored = before.chartPoint(atScreen: anchor)
                pan = PlanisphereViewport.pan(pan, keeping: anchor, fixedIn: tall, from: oldZoom, to: newZoom)
                let after = PlanisphereViewport(size: tall, zoom: newZoom, pan: pan, rotation: 0.9)
                assertPoint(after.screen(anchored), Double(anchor.x), Double(anchor.y), accuracy: 1e-6)
            }
        }
    }

    // MARK: Clamped pan

    func testTheChartCannotBeMovedAtZoomOne() {
        XCTAssertEqual(PlanisphereViewport.clampedPan(CGSize(width: 5, height: 5), zoom: 1, in: square), .zero)
        XCTAssertEqual(PlanisphereViewport.clampedPan(.zero, zoom: 1, in: square), .zero)
    }

    func testAPanWithinTheOverhangIsKept() {
        // Zoom 3 on a base radius of 200 overhangs by 400.
        XCTAssertEqual(PlanisphereViewport.clampedPan(CGSize(width: 100, height: -50), zoom: 3, in: square),
                       CGSize(width: 100, height: -50))
        XCTAssertEqual(PlanisphereViewport.clampedPan(.zero, zoom: 3, in: square), .zero)
    }

    func testAPanExactlyAtTheLimitIsKept() {
        // 240-320-400 is a Pythagorean triple: the length is exactly the limit.
        XCTAssertEqual(PlanisphereViewport.clampedPan(CGSize(width: 240, height: 320), zoom: 3, in: square),
                       CGSize(width: 240, height: 320))
    }

    func testALongerPanIsScaledBackToTheLimitKeepingItsDirection() {
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 600, height: 800), zoom: 3, in: square), 240, 320)
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: -600, height: -800), zoom: 3, in: square), -240, -320)
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 1000, height: 0), zoom: 3, in: square), 400, 0)
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 0, height: -9000), zoom: 3, in: square), 0, -400)
    }

    func testTheLimitGrowsWithTheZoomAndFollowsTheBaseRadius() {
        // Zoom 15 on a base radius of 200: 2800.
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 5000, height: 0), zoom: 15, in: square), 2800, 0)
        // Base radius 174 on the tall view, zoom 2: 174.
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 0, height: 500), zoom: 2, in: tall), 0, 174)
        // The floor of 40 applies to the limit too: zoom 2 on a tiny view.
        assertSize(PlanisphereViewport.clampedPan(CGSize(width: 100, height: 0), zoom: 2, in: .zero), 40, 0)
    }

    func testAZoomBelowOneAllowsNoPan() {
        XCTAssertEqual(PlanisphereViewport.clampedPan(CGSize(width: 10, height: 10), zoom: 0.5, in: square), .zero)
        XCTAssertEqual(PlanisphereViewport.clampedPan(.zero, zoom: 0.5, in: square), .zero)
    }

    func testAClampedPanKeepsTheMiddleOfTheViewOnTheChart() {
        for zoom: CGFloat in [1.5, 3, 15] {
            let pan = PlanisphereViewport.clampedPan(CGSize(width: 9000, height: -7000), zoom: zoom, in: tall)
            let viewport = PlanisphereViewport(size: tall, zoom: zoom, pan: pan)
            let underMiddle = viewport.chartPoint(atScreen: viewport.middle)
            let distance = (Double(underMiddle.x) * Double(underMiddle.x)
                            + Double(underMiddle.y) * Double(underMiddle.y)).squareRoot()
            // The overhang is baseRadius * (zoom - 1) points, i.e. (zoom - 1) / zoom of the chart radius.
            XCTAssertEqual(distance, Double((zoom - 1) / zoom), accuracy: 1e-9)
            XCTAssertLessThanOrEqual(distance, 1)
        }
    }
}

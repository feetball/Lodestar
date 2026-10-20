import CoreGraphics
import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// The planisphere's chart projection: azimuthal stereographic, looking up, north at the top and east on the left.
final class PlanProjectionTests: XCTestCase {
    private let tolerance = 1e-9

    /// The East-North-Up unit vector of an azimuth and altitude in degrees.
    private func enu(_ azimuth: Double, _ altitude: Double) -> Vector3 {
        HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector
    }

    private func assertPoint(_ point: CGPoint, _ x: Double, _ y: Double, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(point.x), x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(point.y), y, accuracy: accuracy, file: file, line: line)
    }

    private func assertVector(_ vector: Vector3, _ x: Double, _ y: Double, _ z: Double, accuracy: Double = 1e-9,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vector.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(vector.y, y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(vector.z, z, accuracy: accuracy, file: file, line: line)
    }

    private func distanceFromCentre(_ point: CGPoint) -> Double {
        (Double(point.x) * Double(point.x) + Double(point.y) * Double(point.y)).squareRoot()
    }

    // MARK: chartPoint

    func testTheZenithIsTheCentreOfTheChart() {
        assertPoint(PlanisphereProjection.chartPoint(Vector3(0, 0, 1)), 0, 0)
    }

    func testHorizonDirectionsLieOnTheUnitCircleWithNorthAtTheTopAndEastOnTheLeft() {
        assertPoint(PlanisphereProjection.chartPoint(Vector3(0, 1, 0)), 0, -1)
        assertPoint(PlanisphereProjection.chartPoint(Vector3(1, 0, 0)), -1, 0)
        assertPoint(PlanisphereProjection.chartPoint(Vector3(0, -1, 0)), 0, 1)
        assertPoint(PlanisphereProjection.chartPoint(Vector3(-1, 0, 0)), 1, 0)
    }

    func testEastAndWestMirrorEachOtherAcrossTheVerticalAxis() {
        let east = PlanisphereProjection.chartPoint(enu(90, 35))
        let west = PlanisphereProjection.chartPoint(enu(270, 35))
        XCTAssertLessThan(Double(east.x), 0)
        XCTAssertGreaterThan(Double(west.x), 0)
        XCTAssertEqual(Double(east.x), -Double(west.x), accuracy: tolerance)
        XCTAssertEqual(Double(east.y), Double(west.y), accuracy: tolerance)
        XCTAssertEqual(Double(east.y), 0, accuracy: tolerance)

        let northeast = PlanisphereProjection.chartPoint(enu(40, 25))
        let northwest = PlanisphereProjection.chartPoint(enu(320, 25))
        XCTAssertEqual(Double(northeast.x), -Double(northwest.x), accuracy: tolerance)
        XCTAssertEqual(Double(northeast.y), Double(northwest.y), accuracy: tolerance)
        XCTAssertLessThan(Double(northeast.y), 0)
    }

    func testNorthAndSouthMirrorEachOtherAcrossTheHorizontalAxis() {
        let north = PlanisphereProjection.chartPoint(enu(0, 50))
        let south = PlanisphereProjection.chartPoint(enu(180, 50))
        XCTAssertEqual(Double(north.y), -Double(south.y), accuracy: tolerance)
        XCTAssertEqual(Double(north.x), Double(south.x), accuracy: tolerance)
        XCTAssertLessThan(Double(north.y), 0)
        XCTAssertGreaterThan(Double(south.y), 0)
    }

    func testTheAltitudeCirclesHaveTheDocumentedRadii() {
        for azimuth in [0.0, 37.0, 123.0, 250.0, 359.0] {
            XCTAssertEqual(distanceFromCentre(PlanisphereProjection.chartPoint(enu(azimuth, 30))),
                           0.5773502692, accuracy: 1e-8)
            XCTAssertEqual(distanceFromCentre(PlanisphereProjection.chartPoint(enu(azimuth, 60))),
                           0.2679491924, accuracy: 1e-8)
            XCTAssertEqual(distanceFromCentre(PlanisphereProjection.chartPoint(enu(azimuth, 0))), 1, accuracy: 1e-8)
        }
    }

    func testDirectionsBelowTheHorizonLieOutsideTheUnitCircle() {
        // Altitude -45 degrees: tan(67.5 degrees) = 1 + sqrt(2).
        assertPoint(PlanisphereProjection.chartPoint(enu(0, -45)), 0, -2.4142135624, accuracy: 1e-8)
    }

    // MARK: retractedChartPoint

    func testRetractionLeavesDirectionsInsideTheRetractionRadiusAlone() {
        for (azimuth, altitude) in [(30.0, -70.0), (200.0, -30.0), (90.0, 10.0), (0.0, 89.0)] {
            let direction = enu(azimuth, altitude)
            let plain = PlanisphereProjection.chartPoint(direction)
            let retracted = PlanisphereProjection.retractedChartPoint(direction)
            assertPoint(retracted, Double(plain.x), Double(plain.y))
        }
    }

    func testRetractionKeepsTheOrderAcrossTheRetractionRadius() {
        // Altitude -71 degrees is at chart radius 5.976 (inside), -71.2 degrees at 6.041 (outside).
        let inside = PlanisphereProjection.retractedChartPoint(enu(0, -71))
        XCTAssertEqual(distanceFromCentre(inside), 5.975764, accuracy: 1e-5)
        let outside = PlanisphereProjection.retractedChartPoint(enu(0, -71.2))
        XCTAssertEqual(distanceFromCentre(outside), PlanisphereProjection.retractionRadius, accuracy: tolerance)
        XCTAssertGreaterThan(distanceFromCentre(PlanisphereProjection.chartPoint(enu(0, -71.2))),
                             PlanisphereProjection.retractionRadius)
    }

    func testRetractionMovesDeepDirectionsAlongTheirRayOntoTheCircle() {
        XCTAssertEqual(PlanisphereProjection.retractionRadius, 6)
        assertPoint(PlanisphereProjection.retractedChartPoint(enu(0, -75)), 0, -6)
        assertPoint(PlanisphereProjection.retractedChartPoint(enu(90, -75)), -6, 0)
        assertPoint(PlanisphereProjection.retractedChartPoint(enu(180, -80)), 0, 6)
        assertPoint(PlanisphereProjection.retractedChartPoint(enu(270, -89.9)), 6, 0)
        let slanted = PlanisphereProjection.retractedChartPoint(enu(123, -85))
        XCTAssertEqual(distanceFromCentre(slanted), 6, accuracy: tolerance)
        // The ray keeps its direction: azimuth 123 is south-east-ish, so x is negative (east is left) and y positive.
        let plain = PlanisphereProjection.chartPoint(enu(123, -85))
        XCTAssertEqual(Double(slanted.x) / Double(slanted.y), Double(plain.x) / Double(plain.y), accuracy: 1e-6)
        XCTAssertLessThan(Double(slanted.x), 0)
        XCTAssertGreaterThan(Double(slanted.y), 0)
    }

    func testTheNadirRetractsToTheBottomOfTheCircle() {
        assertPoint(PlanisphereProjection.retractedChartPoint(Vector3(0, 0, -1)), 0, 6)
        // A horizontal part below 1e-12 has no direction either.
        assertPoint(PlanisphereProjection.retractedChartPoint(Vector3(1e-13, 0, -1)), 0, 6)
    }

    // MARK: direction(ofChartPoint:)

    func testTheCentreOfTheChartIsTheZenith() {
        assertVector(PlanisphereProjection.direction(ofChartPoint: .zero), 0, 0, 1)
    }

    func testChartPointsOnTheUnitCircleAreHorizonDirections() {
        assertVector(PlanisphereProjection.direction(ofChartPoint: CGPoint(x: 0, y: -1)), 0, 1, 0)
        assertVector(PlanisphereProjection.direction(ofChartPoint: CGPoint(x: -1, y: 0)), 1, 0, 0)
        assertVector(PlanisphereProjection.direction(ofChartPoint: CGPoint(x: 0, y: 1)), 0, -1, 0)
        assertVector(PlanisphereProjection.direction(ofChartPoint: CGPoint(x: 1, y: 0)), -1, 0, 0)
    }

    func testAChartPointHalfWayOutIsAtAltitudeThirtySevenDegrees() {
        // r = 0.5: scale = 2 / 1.25 = 1.6, so (-0.8, 0, 0.6) and the altitude is asin(0.6) = 36.87 degrees.
        assertVector(PlanisphereProjection.direction(ofChartPoint: CGPoint(x: 0.5, y: 0)), -0.8, 0, 0.6)
    }

    func testTheChartPointFarOutIsNearTheNadir() {
        let direction = PlanisphereProjection.direction(ofChartPoint: CGPoint(x: 0, y: 100))
        XCTAssertLessThan(direction.z, -0.999)
        XCTAssertEqual(direction.length, 1, accuracy: tolerance)
    }

    func testChartPointAndDirectionAreInverses() {
        for azimuth in stride(from: 0.0, to: 360.0, by: 45.0) {
            for altitude in [-60.0, -10.0, 0.0, 10.0, 45.0, 80.0, 89.9] {
                let direction = enu(azimuth, altitude)
                let back = PlanisphereProjection.direction(ofChartPoint: PlanisphereProjection.chartPoint(direction))
                assertVector(back, direction.x, direction.y, direction.z, accuracy: 1e-9)
            }
        }
    }

    func testDirectionAndChartPointAreInversesFromTheChartSide() {
        for point in [CGPoint(x: 0.3, y: -0.7), CGPoint(x: -2, y: 1.5), CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 0)] {
            let back = PlanisphereProjection.chartPoint(PlanisphereProjection.direction(ofChartPoint: point))
            assertPoint(back, Double(point.x), Double(point.y), accuracy: 1e-8)
        }
    }

    func testDirectionsFromTheChartAreUnitVectors() {
        for point in [CGPoint(x: 0.3, y: -0.7), CGPoint(x: -2, y: 1.5), CGPoint(x: 40, y: -30)] {
            XCTAssertEqual(PlanisphereProjection.direction(ofChartPoint: point).length, 1, accuracy: tolerance)
        }
    }

    // MARK: radius and azimuth helpers

    func testRadiusOfAltitudeFollowsTheStereographicFormula() {
        XCTAssertEqual(PlanisphereProjection.radius(ofAltitude: 90), 0, accuracy: tolerance)
        XCTAssertEqual(PlanisphereProjection.radius(ofAltitude: 0), 1, accuracy: tolerance)
        XCTAssertEqual(PlanisphereProjection.radius(ofAltitude: 30), 0.5773502692, accuracy: 1e-9)
        XCTAssertEqual(PlanisphereProjection.radius(ofAltitude: 60), 0.2679491924, accuracy: 1e-9)
        XCTAssertEqual(PlanisphereProjection.radius(ofAltitude: -45), 2.4142135624, accuracy: 1e-9)
    }

    func testUnitVectorTowardsAnAzimuthPointsNorthUpAndEastLeft() {
        assertPoint(PlanisphereProjection.unitVector(towardsAzimuth: 0), 0, -1)
        assertPoint(PlanisphereProjection.unitVector(towardsAzimuth: 90), -1, 0)
        assertPoint(PlanisphereProjection.unitVector(towardsAzimuth: 180), 0, 1)
        assertPoint(PlanisphereProjection.unitVector(towardsAzimuth: 270), 1, 0)
        assertPoint(PlanisphereProjection.unitVector(towardsAzimuth: 45), -0.7071067812, -0.7071067812)
    }

    func testTheUnitVectorOfAnAzimuthIsTheHorizonChartPoint() {
        for azimuth in [10.0, 100.0, 215.0, 333.0] {
            let horizon = PlanisphereProjection.chartPoint(enu(azimuth, 0))
            let unit = PlanisphereProjection.unitVector(towardsAzimuth: azimuth)
            assertPoint(unit, Double(horizon.x), Double(horizon.y))
        }
    }

    // MARK: visiblePolylines

    func testNoVerticesGiveNoPolylines() {
        XCTAssertTrue(PlanisphereProjection.visiblePolylines(through: []).isEmpty)
    }

    func testASingleVertexIsNotALine() {
        XCTAssertTrue(PlanisphereProjection.visiblePolylines(through: [enu(0, 30)]).isEmpty)
    }

    func testAnArcAboveTheHorizonIsOnePolylineSubdividedIntoSteps() throws {
        // 30 degrees along the meridian in steps of at most 4 degrees: 8 steps, so 9 points.
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, 30), enu(0, 60)])
        XCTAssertEqual(lines.count, 1)
        let points = try XCTUnwrap(lines.first)
        XCTAssertEqual(points.count, 9)
        assertPoint(points[0], 0, -0.5773502692, accuracy: 1e-8)
        assertPoint(points[8], 0, -0.2679491924, accuracy: 1e-8)
        for point in points {
            XCTAssertEqual(Double(point.x), 0, accuracy: tolerance)
        }
        for (earlier, later) in zip(points, points.dropFirst()) {
            XCTAssertGreaterThan(Double(later.y), Double(earlier.y))
        }
    }

    func testAWiderMaximumStepGivesFewerPoints() throws {
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, 30), enu(0, 60)], maximumStep: 11)
        let points = try XCTUnwrap(lines.first)
        XCTAssertEqual(points.count, 4)
    }

    func testAnArcLeavingTheSkyIsCutExactlyAtTheHorizon() throws {
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, 30), enu(0, -30)], maximumStep: 7)
        XCTAssertEqual(lines.count, 1)
        let points = try XCTUnwrap(lines.first)
        // The vertex, four samples above the horizon and the crossing.
        XCTAssertEqual(points.count, 6)
        assertPoint(points[0], 0, -0.5773502692, accuracy: 1e-8)
        assertPoint(points[5], 0, -1)
    }

    func testAnArcEnteringTheSkyStartsExactlyAtTheHorizon() throws {
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, -30), enu(0, 30)], maximumStep: 7)
        XCTAssertEqual(lines.count, 1)
        let points = try XCTUnwrap(lines.first)
        XCTAssertEqual(points.count, 6)
        assertPoint(points[0], 0, -1)
        assertPoint(points[5], 0, -0.5773502692, accuracy: 1e-8)
    }

    func testAPolylineThatDipsBelowTheHorizonFallsIntoTwoPieces() throws {
        let vertices = [enu(0, 30), enu(0, -30), enu(90, 30)]
        let lines = PlanisphereProjection.visiblePolylines(through: vertices)
        XCTAssertEqual(lines.count, 2)
        let first = try XCTUnwrap(lines.first)
        let second = try XCTUnwrap(lines.last)
        let firstEnd = try XCTUnwrap(first.last)
        let secondStart = try XCTUnwrap(second.first)
        let secondEnd = try XCTUnwrap(second.last)
        assertPoint(firstEnd, 0, -1)
        // The second arc crosses the horizon half way between its ends, at azimuth 45 degrees.
        assertPoint(secondStart, -0.7071067812, -0.7071067812, accuracy: 1e-8)
        // And ends at the third vertex: altitude 30 degrees in the east, on the left of the chart.
        assertPoint(secondEnd, -0.5773502692, 0, accuracy: 1e-8)
    }

    func testAPolylineEntirelyBelowTheHorizonIsDropped() {
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, -30), enu(90, -40), enu(200, -10)])
        XCTAssertTrue(lines.isEmpty)
    }

    func testRepeatedVerticesGiveTwoEqualPoints() throws {
        let vertex = enu(120, 40)
        let lines = PlanisphereProjection.visiblePolylines(through: [vertex, vertex])
        XCTAssertEqual(lines.count, 1)
        let points = try XCTUnwrap(lines.first)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0], points[1])
    }

    func testOppositeVerticesAreJoinedInOneStep() throws {
        // No unique arc runs between opposite horizon points; the polyline goes straight to the end.
        let lines = PlanisphereProjection.visiblePolylines(through: [enu(0, 0), enu(180, 0)])
        XCTAssertEqual(lines.count, 1)
        let points = try XCTUnwrap(lines.first)
        XCTAssertEqual(points.count, 2)
        assertPoint(points[0], 0, -1)
        assertPoint(points[1], 0, 1)
    }

    // MARK: ring

    func testARingNeedsThreeVertices() {
        XCTAssertTrue(PlanisphereProjection.ring(through: []).isEmpty)
        XCTAssertTrue(PlanisphereProjection.ring(through: [enu(0, 60)]).isEmpty)
        XCTAssertTrue(PlanisphereProjection.ring(through: [enu(0, 60), enu(90, 60)]).isEmpty)
    }

    func testACoarseStepKeepsOnlyTheVerticesInOrder() {
        let vertices = [enu(0, 60), enu(90, 60), enu(180, 60), enu(270, 60)]
        let ring = PlanisphereProjection.ring(through: vertices, maximumStep: 90)
        XCTAssertEqual(ring.count, 4)
        assertPoint(ring[0], 0, -0.2679491924, accuracy: 1e-8)
        assertPoint(ring[1], -0.2679491924, 0, accuracy: 1e-8)
        assertPoint(ring[2], 0, 0.2679491924, accuracy: 1e-8)
        assertPoint(ring[3], 0.2679491924, 0, accuracy: 1e-8)
    }

    func testARingAroundTheZenithFollowsTheAltitudeCircleInTwoDegreeSteps() {
        // Adjacent vertices are 41.41 degrees apart, so each edge takes 21 steps: 4 * 21 points, the closing one dropped.
        let vertices = [enu(0, 60), enu(90, 60), enu(180, 60), enu(270, 60)]
        let ring = PlanisphereProjection.ring(through: vertices)
        XCTAssertEqual(ring.count, 84)
        assertPoint(ring[0], 0, -0.2679491924, accuracy: 1e-8)
        for point in ring {
            // The great-circle edges bulge towards the zenith, never beyond the altitude circle.
            XCTAssertLessThanOrEqual(distanceFromCentre(point), 0.2679491924 + 1e-8)
        }
    }

    func testARingAroundTheZenithContainsTheZenithAndNotTheHorizon() {
        let vertices = [enu(0, 60), enu(90, 60), enu(180, 60), enu(270, 60)]
        let ring = PlanisphereProjection.ring(through: vertices)
        XCTAssertTrue(PlanisphereProjection.contains(.zero, inRing: ring))
        XCTAssertTrue(PlanisphereProjection.contains(CGPoint(x: 0.1, y: -0.1), inRing: ring))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: 0.5, y: 0), inRing: ring))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: 1, y: 1), inRing: ring))
    }

    func testRingVerticesBelowTheRetractionRadiusAreProjectedUnchanged() {
        let vertices = [enu(0, 20), enu(120, 20), enu(240, 20)]
        let ring = PlanisphereProjection.ring(through: vertices, maximumStep: 180)
        XCTAssertEqual(ring.count, 3)
        for (point, vertex) in zip(ring, vertices) {
            let expected = PlanisphereProjection.chartPoint(vertex)
            assertPoint(point, Double(expected.x), Double(expected.y))
        }
    }

    func testARingBelowTheHorizonRunsAlongTheRetractionCircleThroughRetractionArcs() {
        // Three vertices at altitude -85 degrees, 100, 130 and 130 degrees apart in azimuth. All of them are
        // retracted onto the circle; the jumps between them are filled in steps of at most 15 degrees:
        // ceil(100/15) - 1 = 6, ceil(130/15) - 1 = 8 and 8 extra points, plus the 3 vertices.
        let vertices = [enu(0, -85), enu(100, -85), enu(230, -85)]
        let ring = PlanisphereProjection.ring(through: vertices, maximumStep: 90)
        XCTAssertEqual(ring.count, 25)
        assertPoint(ring[0], 0, -6)
        for point in ring {
            XCTAssertEqual(distanceFromCentre(point), 6, accuracy: tolerance)
        }
    }

    func testARingDippingTowardsTheNadirStaysFiniteAndInsideTheRetractionCircle() {
        let vertices = [enu(0, 60), enu(120, -80), enu(240, -80)]
        let ring = PlanisphereProjection.ring(through: vertices)
        XCTAssertGreaterThan(ring.count, 3)
        for point in ring {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
            XCTAssertLessThanOrEqual(distanceFromCentre(point), 6 + tolerance)
        }
    }

    // MARK: contains

    func testASquareContainsItsInteriorPointsOnly() {
        let square = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)]
        XCTAssertTrue(PlanisphereProjection.contains(.zero, inRing: square))
        XCTAssertTrue(PlanisphereProjection.contains(CGPoint(x: -0.5, y: 0.5), inRing: square))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: 2, y: 0), inRing: square))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: 0, y: 2), inRing: square))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: -3, y: -3), inRing: square))
    }

    func testAConcaveRingFollowsTheEvenOddRule() {
        // An L: the unit square at the top right is cut out.
        let ell = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 1),
                   CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 2), CGPoint(x: 0, y: 2)]
        XCTAssertTrue(PlanisphereProjection.contains(CGPoint(x: 0.5, y: 1.5), inRing: ell))
        XCTAssertTrue(PlanisphereProjection.contains(CGPoint(x: 1.5, y: 0.5), inRing: ell))
        XCTAssertFalse(PlanisphereProjection.contains(CGPoint(x: 1.5, y: 1.5), inRing: ell))
    }

    func testAnEmptyRingContainsNothing() {
        XCTAssertFalse(PlanisphereProjection.contains(.zero, inRing: []))
    }

    func testTheWindingDirectionOfTheRingDoesNotMatter() {
        let clockwise = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)]
        let counterClockwise = Array(clockwise.reversed())
        XCTAssertEqual(PlanisphereProjection.contains(CGPoint(x: 0.2, y: 0.3), inRing: clockwise),
                       PlanisphereProjection.contains(CGPoint(x: 0.2, y: 0.3), inRing: counterClockwise))
        XCTAssertTrue(PlanisphereProjection.contains(CGPoint(x: 0.2, y: 0.3), inRing: counterClockwise))
    }

    // MARK: PlanisphereBounds

    func testASquareAroundACentre() {
        XCTAssertEqual(PlanisphereBounds.square(around: CGPoint(x: 10, y: 20), radius: 5),
                       CGRect(x: 5, y: 15, width: 10, height: 10))
        XCTAssertEqual(PlanisphereBounds.square(around: CGPoint(x: 10, y: 20), radius: 0),
                       CGRect(x: 10, y: 20, width: 0, height: 0))
    }

    func testARectangleAroundACentre() {
        XCTAssertEqual(PlanisphereBounds.rect(around: CGPoint(x: 10, y: 20), size: CGSize(width: 6, height: 8)),
                       CGRect(x: 7, y: 16, width: 6, height: 8))
        XCTAssertEqual(PlanisphereBounds.rect(around: CGPoint(x: -4, y: 0), size: .zero),
                       CGRect(x: -4, y: 0, width: 0, height: 0))
    }
}

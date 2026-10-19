import XCTest
@testable import LodestarKit

/// Helpers shared by the mosaic and photo-planner tests. They are written independently of the planner: panel
/// membership is tested with the panel's corners (great-circle edges), and region points are generated from the
/// region's definition, not from the planner's grid.
enum MosaicTestSupport {
    /// A full-frame camera with a lens of the given focal length: the landscape frame.
    static func frame(focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: .fullFrame, focalLength: focalLength)
    }

    /// The spherical quadrilateral of a panel's corners, as the normals of its four edges.
    struct Quad {
        private let normals: [Vector3]
        private let signs: [Double]

        init(_ panel: MosaicPanel) {
            let corners = panel.corners.map(\.unitVector)
            let centroid = (corners[0] + corners[1] + corners[2] + corners[3]).normalized
            normals = (0..<4).map { corners[$0].cross(corners[($0 + 1) % 4]) }
            signs = normals.map { $0.dot(centroid) >= 0 ? 1.0 : -1.0 }
        }

        /// Whether `point` lies on the inner side of all four edges (great-circle arcs between the corners).
        func contains(_ point: Vector3) -> Bool {
            for index in 0..<4 where normals[index].dot(point) * signs[index] < -1e-9 { return false }
            return true
        }
    }

    /// Whether `point` lies inside the spherical quadrilateral of `panel`'s corners.
    static func contains(_ panel: MosaicPanel, _ point: Vector3) -> Bool {
        Quad(panel).contains(point)
    }

    /// The region's points on a lattice of `rows` by `columns`, edges included.
    static func points(region: MosaicRegion, rows: Int, columns: Int) -> [Vector3] {
        var result = [Vector3]()
        switch region {
        case let .horizontal(azimuthStart, azimuthSpan, minimumAltitude, maximumAltitude):
            for row in 0..<rows {
                let altitude = minimumAltitude + (maximumAltitude - minimumAltitude) * Double(row) / Double(rows - 1)
                for column in 0..<columns {
                    let fraction = azimuthSpan >= 360 ? Double(column) / Double(columns) : Double(column) / Double(columns - 1)
                    result.append(HorizontalCoordinate(azimuth: azimuthStart + azimuthSpan * fraction, altitude: altitude).unitVector)
                }
            }
        case let .equatorial(center, width, height, positionAngle):
            let centerVector = center.unitVector
            let rotation = Matrix3.rotation(axis: centerVector, angleRadians: -AstroMath.radians(positionAngle))
            let span = cos(AstroMath.radians(center.declination)) > 1e-9
                ? min(360, width / cos(AstroMath.radians(center.declination)))
                : 360
            for row in 0..<rows {
                let declination = AstroMath.clamp(center.declination + height * (Double(row) / Double(rows - 1) - 0.5), -90, 90)
                for column in 0..<columns {
                    let fraction = span >= 360 ? Double(column) / Double(columns) : Double(column) / Double(columns - 1)
                    let place = EquatorialCoordinate(rightAscension: center.rightAscension + span * (fraction - 0.5), declination: declination)
                    result.append(rotation * place.unitVector)
                }
            }
        }
        return result
    }

    /// The number of `points` that no panel of `plan` contains.
    static func uncovered(plan: MosaicPlan, points: [Vector3]) -> Int {
        let quads = plan.panels.map { Quad($0) }
        return points.filter { point in !quads.contains { $0.contains(point) } }.count
    }

    /// The error `body` throws, or nil if it does not throw.
    static func thrown(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    /// The name of the enum case of an error, without its payload.
    static func kind(of error: Error?) -> String {
        guard let error else { return "none" }
        return String(String(describing: error).prefix { $0 != "(" })
    }

    /// Asserts that `body` throws an error whose case is named `kind`, whatever its payload.
    static func assertThrowsKind(_ kind: String, _ message: String = "", file: StaticString = #filePath, line: UInt = #line,
                                 _ body: () throws -> Void) {
        XCTAssertEqual(Self.kind(of: thrown(body)), kind, message, file: file, line: line)
    }

    /// Asserts that `body` throws exactly `expected`.
    static func assertThrows<E: Error & Equatable>(_ expected: E, _ message: String = "", file: StaticString = #filePath,
                                                   line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertEqual(thrown(body) as? E, expected, message, file: file, line: line)
    }
}

final class MosaicPlannerTests: XCTestCase {
    private func lens(_ focalLength: Double) -> FrameSize { MosaicTestSupport.frame(focalLength: focalLength) }

    private let sky = EquatorialCoordinate(rightAscensionHours: 5, declination: 0)

    private func equatorial(_ declination: Double, _ width: Double, _ height: Double, _ positionAngle: Double = 0) -> MosaicRegion {
        .equatorial(center: EquatorialCoordinate(rightAscensionHours: 5, declination: declination), width: width,
                    height: height, positionAngle: positionAngle)
    }

    // MARK: Known counts

    func testSmallRegionNeedsOnePanel() throws {
        let plan = try MosaicPlanner.plan(region: .equatorial(center: sky, width: 20, height: 15), frame: lens(50))
        XCTAssertEqual(plan.rows, 1)
        XCTAssertEqual(plan.columnsPerRow, [1])
        XCTAssertEqual(plan.panelCount, 1)
        XCTAssertEqual(plan.gridDescription, "1 \u{00D7} 1")
        XCTAssertNil(plan.achievedOverlap)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertEqual(plan.coverage.coveredFraction, 1.0)
        let panel = plan.panels[0]
        XCTAssertEqual(panel.id, "R1C1")
        XCTAssertEqual(panel.shootingPosition, 0)
        XCTAssertEqual(plan.shootingOrder, [0])
        XCTAssertEqual(try XCTUnwrap(panel.center.equatorialCoordinate).angularSeparation(to: sky), 0.0, accuracy: 1e-9)
        XCTAssertEqual(plan.kind, .equatorial)
    }

    func testTwoColumnsAtTheEquatorAreSpacedByTheOverlap() throws {
        // At declination 0 a frame covers its own width everywhere in the band, so the spacing is 75 % of it.
        let frame = lens(50)
        let plan = try MosaicPlanner.plan(region: equatorial(0, 40, 10), frame: frame)
        XCTAssertEqual(plan.columnsPerRow, [2])
        XCTAssertEqual(plan.gridDescription, "2 \u{00D7} 1")
        let half = 0.375 * frame.horizontal
        let left = try XCTUnwrap(plan.panels[0].center.equatorialCoordinate)
        let right = try XCTUnwrap(plan.panels[1].center.equatorialCoordinate)
        XCTAssertEqual(left.rightAscension, 75.0 + half, accuracy: 1e-6)
        XCTAssertEqual(right.rightAscension, 75.0 - half, accuracy: 1e-6)
        XCTAssertEqual(left.declination, 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(plan.achievedOverlap), 0.25, accuracy: 1e-12)
    }

    func testThreeByThreeAtTheEquator() throws {
        let frame = lens(50)
        let plan = try MosaicPlanner.plan(region: equatorial(0, 80, 50), frame: frame)
        XCTAssertEqual(plan.rows, 3)
        XCTAssertEqual(plan.columnsPerRow, [3, 3, 3])
        XCTAssertTrue(plan.isRectangular)
        XCTAssertEqual(plan.columns, 3)
        let declinations = try (0..<3).map { try XCTUnwrap(try XCTUnwrap(plan.panel(row: $0, column: 1)).center.equatorialCoordinate).declination }
        XCTAssertEqual(declinations[0], 0.75 * frame.vertical, accuracy: 1e-9)
        XCTAssertEqual(declinations[1], 0.0, accuracy: 1e-9)
        XCTAssertEqual(declinations[2], -0.75 * frame.vertical, accuracy: 1e-9)
        let middle = try (0..<3).map { try XCTUnwrap(try XCTUnwrap(plan.panel(row: 1, column: $0)).center.equatorialCoordinate).rightAscension }
        XCTAssertEqual(middle[0], 75.0 + 0.75 * frame.horizontal, accuracy: 1e-6)
        XCTAssertEqual(middle[1], 75.0, accuracy: 1e-6)
        XCTAssertEqual(middle[2], 75.0 - 0.75 * frame.horizontal, accuracy: 1e-6)
        XCTAssertNil(plan.panel(row: 3, column: 0))
        XCTAssertNil(plan.panel(row: 0, column: 3))
        XCTAssertNil(plan.panel(row: -1, column: 0))
        // Rows are numbered from the pole side, columns from the east.
        XCTAssertEqual(try XCTUnwrap(plan.panel(row: 1, column: 2)).id, "R2C3")
        XCTAssertEqual(try XCTUnwrap(plan.panel(row: 1, column: 2)).index, 5)
    }

    func testRowsNearThePoleGetFewerPanels() throws {
        // A row nearer the pole is shorter on the sphere, so it needs fewer columns for the same right-ascension
        // span. Counts worked out with the closed-form width of a gnomonic frame (x and y edge solutions).
        let plan = try MosaicPlanner.plan(region: equatorial(60, 80, 50), frame: lens(50))
        XCTAssertEqual(plan.rows, 3)
        XCTAssertEqual(plan.columnsPerRow, [1, 4, 5])
        XCTAssertEqual(plan.gridDescription, "10 panels in 3 rows")
        XCTAssertFalse(plan.isRectangular)
        let declinations = try (0..<3).map { try XCTUnwrap(try XCTUnwrap(plan.panel(row: $0, column: 0)).center.equatorialCoordinate).declination }
        let frame = lens(50)
        XCTAssertEqual(declinations[0], 60.0 + 0.75 * frame.vertical, accuracy: 1e-9)
        XCTAssertEqual(declinations[1], 60.0, accuracy: 1e-9)
        XCTAssertEqual(declinations[2], 60.0 - 0.75 * frame.vertical, accuracy: 1e-9)
    }

    func testRegionThatReachesThePoleIsClamped() throws {
        let plan = try MosaicPlanner.plan(region: equatorial(70, 100, 50), frame: lens(35))
        XCTAssertEqual(plan.columnsPerRow, [2, 6])
        XCTAssertEqual(MosaicTestSupport.uncovered(plan: plan, points: MosaicTestSupport.points(region: plan.region, rows: 37, columns: 53)), 0)
        // The top row sits just below the pole.
        XCTAssertLessThan(try XCTUnwrap(plan.panels[0].center.equatorialCoordinate).declination, 90.0)
    }

    func testArchPanoramaOf24mmPortraitIsThreeByOne() throws {
        // 24 mm full frame held upright: 53.13° wide, 73.74° tall. A box of 110° of azimuth and 0° to 60° of
        // altitude: the frame covers 46.83° of azimuth at the horizon (closed form), 75 % of that is the step.
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(24), orientation: .portrait)
        XCTAssertEqual(plan.kind, .horizontal)
        XCTAssertEqual(plan.rows, 1)
        XCTAssertEqual(plan.columnsPerRow, [3])
        XCTAssertEqual(plan.gridDescription, "3 \u{00D7} 1")
        XCTAssertEqual(plan.frame.horizontal, 53.13010235415598, accuracy: 1e-9)
        XCTAssertEqual(plan.frame.vertical, 73.73979529168804, accuracy: 1e-9)
        let step = 0.75 * 46.82644889274108
        let azimuths = try plan.panels.map { try XCTUnwrap($0.center.horizontalCoordinate).azimuth }
        XCTAssertEqual(azimuths[0], 205.0 - step, accuracy: 1e-6)
        XCTAssertEqual(azimuths[1], 205.0, accuracy: 1e-6)
        XCTAssertEqual(azimuths[2], 205.0 + step, accuracy: 1e-6)
        for panel in plan.panels { XCTAssertEqual(try XCTUnwrap(panel.center.horizontalCoordinate).altitude, 30.0, accuracy: 1e-9) }
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertEqual(try XCTUnwrap(plan.achievedOverlap), 0.25, accuracy: 1e-9)
    }

    func testPanoramaColumnsGrowWithTheAzimuthSpan() throws {
        // Closed-form frame width at the horizon 46.826°; columns = ceil((span − 46.826) / 35.12) + 1.
        let expected: [(Double, Int)] = [(60, 2), (90, 3), (110, 3), (120, 4), (150, 4), (180, 5)]
        for (span, columns) in expected {
            let plan = try MosaicPlanner.plan(
                region: .horizontal(azimuthStart: 0, azimuthSpan: span, minimumAltitude: 0, maximumAltitude: 60),
                frame: lens(24), orientation: .portrait)
            XCTAssertEqual(plan.columnsPerRow, [columns], "span \(span)")
        }
    }

    func testLandscapeFramesNeedTwoRowsForTheSameArch() throws {
        let plan = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60), frame: lens(24))
        XCTAssertEqual(plan.rows, 2)
        XCTAssertEqual(plan.columnsPerRow, [2, 2])
        let altitudes = try [plan.panels[0], plan.panels[2]].map { try XCTUnwrap($0.center.horizontalCoordinate).altitude }
        let step = 0.75 * 53.13010235415598
        XCTAssertEqual(altitudes[0], 30.0 + step / 2, accuracy: 1e-9)
        XCTAssertEqual(altitudes[1], 30.0 - step / 2, accuracy: 1e-9)
    }

    func testFullCirclePanoramaWrapsAround() throws {
        let plan = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 0, azimuthSpan: 360, minimumAltitude: 0, maximumAltitude: 30), frame: lens(24))
        XCTAssertEqual(plan.columnsPerRow, [7])
        let azimuths = try plan.panels.map { try XCTUnwrap($0.center.horizontalCoordinate).azimuth }
        for index in azimuths.indices {
            let next = azimuths[(index + 1) % azimuths.count]
            XCTAssertEqual(AstroMath.normalizeDegrees(next - azimuths[index]), 360.0 / 7.0, accuracy: 1e-9, "step \(index)")
        }
        // The achieved overlap is more than requested because 360° does not divide into steps of 75 %.
        XCTAssertGreaterThan(try XCTUnwrap(plan.achievedOverlap), 0.25)
        XCTAssertEqual(plan.coverage.longitudeSpanDegrees, 360.0)
    }

    func testMilkyWayCoreRegionAt135mm() throws {
        let plan = try MosaicPlanner.plan(region: equatorial(-29, 50, 30), frame: lens(135))
        XCTAssertEqual(plan.columnsPerRow, [5, 5, 5, 4])
        XCTAssertEqual(plan.panelCount, 19)
    }

    func testAndromedaAt600mmNeedsTwoPanels() throws {
        let center = EquatorialCoordinate(rightAscension: 10.684792, declination: 41.269056)
        let size = try XCTUnwrap(AngularSize(majorArcminutes: 178, minorArcminutes: 70, positionAngle: 35))
        let region = try MosaicRegion.fitting(center: center, size: size)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(600))
        XCTAssertEqual(plan.columnsPerRow, [2])
        XCTAssertEqual(try MosaicPlanner.plan(region: region, frame: lens(200)).panelCount, 1)
    }

    // MARK: Coverage and overlap

    func testPanelsCoverTheRegionWithoutGaps() throws {
        let cases: [(MosaicRegion, FrameSize)] = [
            (.equatorial(center: sky, width: 20, height: 15), lens(50)),
            (equatorial(0, 80, 50), lens(50)),
            (equatorial(60, 80, 50), lens(50)),
            (equatorial(70, 100, 50), lens(35)),
            (equatorial(-29, 50, 30), lens(135)),
            (equatorial(-60, 100, 60), lens(24)),
            (equatorial(80, 40, 10), lens(50)),
            (equatorial(30, 60, 40, 37), lens(85)),
            (equatorial(0, 120, 70, 90), lens(24)),
            (equatorial(88, 60, 30), lens(24)),
            (.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60), lens(24)),
            (.horizontal(azimuthStart: 10, azimuthSpan: 200, minimumAltitude: -10, maximumAltitude: 80), lens(14)),
            (.horizontal(azimuthStart: 0, azimuthSpan: 360, minimumAltitude: 0, maximumAltitude: 90), lens(20)),
            (.horizontal(azimuthStart: 300, azimuthSpan: 150, minimumAltitude: 20, maximumAltitude: 70), lens(35)),
        ]
        for (region, frame) in cases {
            for orientation in MosaicOrientation.allCases {
                let plan = try MosaicPlanner.plan(region: region, frame: frame, orientation: orientation)
                let points = MosaicTestSupport.points(region: region, rows: 37, columns: 53)
                XCTAssertEqual(MosaicTestSupport.uncovered(plan: plan, points: points), 0, "\(region) \(orientation)")
                XCTAssertEqual(plan.coverage.coveredFraction, 1.0)
                XCTAssertTrue(plan.warnings.isEmpty, "\(region) \(orientation)")
                XCTAssertTrue(plan.achievedOverlap.map { $0 >= 0.25 - 1e-9 } ?? true)
            }
        }
    }

    func testSweepOfLensesAndRegionsLeavesNoGaps() throws {
        // 14 mm to 135 mm, sites near the pole and in the south, with and without a position angle, small and large regions.
        var planned = 0
        for focalLength in [14.0, 24.0, 50.0, 135.0] {
            for declination in [-60.0, 0.0, 45.0, 85.0] {
                for (width, height) in [(40.0, 25.0), (90.0, 60.0)] {
                    for orientation in MosaicOrientation.allCases {
                        for overlap in [0.1, 0.5] {
                            let region = equatorial(declination, width, height, planned % 2 == 0 ? 0 : 37)
                            let plan: MosaicPlan
                            do {
                                plan = try MosaicPlanner.plan(region: region, frame: lens(focalLength), orientation: orientation, overlap: overlap)
                            } catch MosaicError.tooManyPanels {
                                continue
                            }
                            planned += 1
                            let label = "\(focalLength) mm, dec \(declination), \(width) x \(height), \(orientation), \(overlap)"
                            XCTAssertEqual(MosaicTestSupport.uncovered(plan: plan, points: MosaicTestSupport.points(region: region, rows: 31, columns: 47)), 0, label)
                            XCTAssertFalse(plan.warnings.contains { if case .overlapNotMet = $0 { return true } else { return false } }, label)
                            XCTAssertTrue(plan.achievedOverlap.map { $0 >= overlap - 1e-9 } ?? true, label)
                        }
                    }
                }
            }
        }
        for focalLength in [14.0, 24.0, 50.0] {
            for span in [60.0, 200.0, 360.0] {
                for (low, high) in [(0.0, 30.0), (-10.0, 80.0)] {
                    for orientation in MosaicOrientation.allCases {
                        let region = MosaicRegion.horizontal(azimuthStart: 40, azimuthSpan: span, minimumAltitude: low, maximumAltitude: high)
                        let plan: MosaicPlan
                        do {
                            plan = try MosaicPlanner.plan(region: region, frame: lens(focalLength), orientation: orientation)
                        } catch MosaicError.tooManyPanels {
                            continue
                        }
                        planned += 1
                        let label = "\(focalLength) mm, span \(span), \(low) to \(high), \(orientation)"
                        XCTAssertEqual(MosaicTestSupport.uncovered(plan: plan, points: MosaicTestSupport.points(region: region, rows: 31, columns: 47)), 0, label)
                        XCTAssertTrue(plan.warnings.isEmpty, label)
                    }
                }
            }
        }
        XCTAssertGreaterThan(planned, 150, "\(planned) plans")
    }

    func testNeighbouringPanelsShareTheRequestedOverlapAtTheNarrowestAltitude() throws {
        // Walk along parallels of altitude and measure how much of a frame its right-hand neighbour also covers.
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        for overlap in [0.1, 0.25, 0.4] {
            let plan = try MosaicPlanner.plan(region: region, frame: lens(24), orientation: .portrait, overlap: overlap)
            var narrowest = 1.0
            let quads = plan.panels.map { MosaicTestSupport.Quad($0) }
            for altitude in [0.0, 15.0, 30.0, 45.0, 60.0] {
                for index in 0..<(plan.panelCount - 1) {
                    var first = 0
                    var shared = 0
                    var azimuth = 100.0
                    while azimuth < 320 {
                        let point = HorizontalCoordinate(azimuth: azimuth, altitude: altitude).unitVector
                        if quads[index].contains(point) {
                            first += 1
                            if quads[index + 1].contains(point) { shared += 1 }
                        }
                        azimuth += 0.02
                    }
                    if first > 0 { narrowest = min(narrowest, Double(shared) / Double(first)) }
                    if altitude == 0 && index == 0 {
                        XCTAssertEqual(Double(shared) / Double(first), overlap, accuracy: 0.004, "overlap \(overlap) at the horizon")
                    }
                }
            }
            XCTAssertGreaterThanOrEqual(narrowest, overlap - 0.004, "overlap \(overlap): narrowest \(narrowest)")
        }
    }

    func testFramesNeverLeaveGapsEvenWhenTheEdgesBow() throws {
        // With a 14 mm lens the frame edges bow so strongly that the tangent-line layout of three rows leaves slivers
        // at the sides; the planner has to add overlap and extend the grid.
        let region = MosaicRegion.horizontal(azimuthStart: 10, azimuthSpan: 40, minimumAltitude: -60, maximumAltitude: 60)
        let frame = lens(14)
        let full = try MosaicPlanner.plan(region: region, frame: frame, orientation: .landscape, overlap: 0.5)
        XCTAssertEqual(full.rows, 3)
        XCTAssertEqual(full.coverage.coveredFraction, 1.0)
        XCTAssertTrue(full.warnings.isEmpty)
        XCTAssertEqual(MosaicTestSupport.uncovered(plan: full, points: MosaicTestSupport.points(region: region, rows: 41, columns: 41)), 0)
        let limited = try MosaicPlanner.plan(region: region, frame: frame, orientation: .landscape, overlap: 0.5,
                                             observerLatitude: nil, reverseOrder: false, maximumAttempts: 1)
        XCTAssertEqual(limited.rows, 2)
        XCTAssertEqual(limited.warnings.count, 1)
        guard case let .overlapNotMet(coveredFraction) = limited.warnings[0] else { return XCTFail("wrong warning") }
        XCTAssertTrue(coveredFraction > 0.98 && coveredFraction < 0.995, "\(coveredFraction)")
        XCTAssertEqual(coveredFraction, limited.coverage.coveredFraction)
        XCTAssertGreaterThan(MosaicTestSupport.uncovered(plan: limited, points: MosaicTestSupport.points(region: region, rows: 41, columns: 41)), 0)
    }

    func testCornersFormAGnomonicRectangle() throws {
        let plan = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60),
            frame: lens(24), orientation: .portrait)
        for panel in plan.panels {
            let center = panel.center.unitVector
            let corners = panel.corners.map(\.unitVector)
            XCTAssertEqual(corners.count, 4)
            // The diagonal of the frame is the lens's diagonal field of view.
            XCTAssertEqual(corners[0].angle(to: corners[2]), plan.frame.diagonal, accuracy: 1e-9)
            XCTAssertEqual(corners[1].angle(to: corners[3]), plan.frame.diagonal, accuracy: 1e-9)
            // The middle of the top and bottom edges is half the frame height from the centre, the sides half the width.
            XCTAssertEqual(center.angle(to: (corners[0] + corners[1]).normalized), plan.frame.vertical / 2, accuracy: 1e-9)
            XCTAssertEqual(center.angle(to: (corners[2] + corners[3]).normalized), plan.frame.vertical / 2, accuracy: 1e-9)
            XCTAssertEqual(center.angle(to: (corners[0] + corners[3]).normalized), plan.frame.horizontal / 2, accuracy: 1e-9)
            XCTAssertEqual(center.angle(to: (corners[1] + corners[2]).normalized), plan.frame.horizontal / 2, accuracy: 1e-9)
            // Top corners have the larger altitude on a level frame.
            XCTAssertGreaterThan(try XCTUnwrap(panel.corners[0].horizontalCoordinate).altitude,
                                 try XCTUnwrap(panel.corners[3].horizontalCoordinate).altitude)
            // Left corners have the smaller azimuth, the camera looks along increasing azimuth to the right.
            XCTAssertGreaterThan(AstroMath.normalizeSignedDegrees(try XCTUnwrap(panel.corners[1].horizontalCoordinate).azimuth
                                                                  - (try XCTUnwrap(panel.corners[0].horizontalCoordinate).azimuth)), 0)
        }
    }

    func testPanelAreaIsTheSolidAngleOfTheFrame() throws {
        let plan = try MosaicPlanner.plan(region: equatorial(0, 80, 50), frame: lens(200))
        // A 10.29° × 6.87° frame is almost flat: the area is close to the product of its sides.
        let area = plan.coverage.panelAreaSquareDegrees / Double(plan.panelCount)
        XCTAssertEqual(area, 10.2855 * 6.8673, accuracy: 0.2)
        XCTAssertLessThan(area, 10.2855 * 6.8673)
        XCTAssertEqual(plan.coverage.regionAreaSquareDegrees, 3874.2788, accuracy: 0.01)
    }

    func testCoverageExtents() throws {
        let frame = lens(50)
        let plan = try MosaicPlanner.plan(region: equatorial(0, 80, 50), frame: frame)
        // Three rows with 75 % spacing: two steps plus one frame height.
        XCTAssertEqual(plan.coverage.heightDegrees, 2 * 0.75 * frame.vertical + frame.vertical, accuracy: 1e-9)
        // The central row spans two steps plus one frame width.
        XCTAssertEqual(plan.coverage.widthDegrees, 2 * 0.75 * frame.horizontal + frame.horizontal, accuracy: 1e-6)
        XCTAssertEqual(plan.coverage.longitudeSpanDegrees, plan.coverage.widthDegrees, accuracy: 1e-6)
        XCTAssertGreaterThan(plan.coverage.panelAreaSquareDegrees, plan.coverage.regionAreaSquareDegrees)
    }

    // MARK: Position angle

    func testPositionAngleTurnsThePlanAboutItsCentre() throws {
        // Turning the region by the position angle turns every panel with it, about the region's centre.
        let center = EquatorialCoordinate(rightAscensionHours: 5, declination: 25).unitVector
        for angle in [37.0, 90.0, 200.0, -45.0] {
            let base = try MosaicPlanner.plan(region: equatorial(25, 90, 40), frame: lens(85))
            let turned = try MosaicPlanner.plan(region: equatorial(25, 90, 40, angle), frame: lens(85))
            XCTAssertEqual(base.columnsPerRow, turned.columnsPerRow, "angle \(angle)")
            let rotation = Matrix3.rotation(axis: center, angleRadians: -AstroMath.radians(angle))
            for index in base.panels.indices {
                let expected = rotation * base.panels[index].center.unitVector
                XCTAssertEqual(expected.angle(to: turned.panels[index].center.unitVector), 0.0, accuracy: 1e-8, "angle \(angle) panel \(index)")
                for corner in 0..<4 {
                    let expectedCorner = rotation * base.panels[index].corners[corner].unitVector
                    XCTAssertEqual(expectedCorner.angle(to: turned.panels[index].corners[corner].unitVector), 0.0, accuracy: 1e-8)
                }
            }
        }
    }

    func testPositionAngleOfNinetyRunsTheRowsNorthSouth() throws {
        // A region 60° wide and 10° tall whose width runs north-south at position angle 90.
        let plan = try MosaicPlanner.plan(region: equatorial(0, 60, 10, 90), frame: lens(50))
        XCTAssertEqual(plan.columnsPerRow, [2])
        let first = try XCTUnwrap(plan.panels[0].center.equatorialCoordinate)
        let second = try XCTUnwrap(plan.panels[1].center.equatorialCoordinate)
        XCTAssertEqual(first.rightAscension, second.rightAscension, accuracy: 1e-6)
        XCTAssertEqual(abs(first.declination - second.declination), 0.75 * lens(50).horizontal, accuracy: 1e-6)
        // The left panel is the eastern one for an unturned plan; turned by 90° it is the northern or southern end.
        XCTAssertEqual(first.rightAscension, 75.0, accuracy: 1e-6)
        // Unturned, the same region runs east-west.
        let unturned = try MosaicPlanner.plan(region: equatorial(0, 60, 10, 0), frame: lens(50))
        XCTAssertEqual(try XCTUnwrap(unturned.panels[0].center.equatorialCoordinate).declination,
                       try XCTUnwrap(unturned.panels[1].center.equatorialCoordinate).declination, accuracy: 1e-8)
    }

    func testFittingAnObjectTurnsTheRegionAlongItsMajorAxis() throws {
        // M 31: 178′ × 70′ with the major axis at position angle 35°. With a 20 % margin: 3.56° × 1.4°.
        let center = EquatorialCoordinate(rightAscension: 10.684792, declination: 41.269056)
        let region = try MosaicRegion.fitting(center: center, size: try XCTUnwrap(AngularSize(majorArcminutes: 178, minorArcminutes: 70, positionAngle: 35)))
        guard case let .equatorial(regionCenter, width, height, positionAngle) = region else { return XCTFail("not equatorial") }
        XCTAssertEqual(regionCenter, center)
        XCTAssertEqual(width, 178.0 / 60.0 * 1.2, accuracy: 1e-12)
        XCTAssertEqual(height, 70.0 / 60.0 * 1.2, accuracy: 1e-12)
        XCTAssertEqual(positionAngle, 305.0, accuracy: 1e-12)
        // The width axis of the region points along position angle 35°: the direction 90° after the height axis.
        let plan = try MosaicPlanner.plan(region: region, frame: lens(1200))
        XCTAssertGreaterThanOrEqual(plan.columnsPerRow[0], 2)
        let first = try XCTUnwrap(plan.panel(row: 0, column: 0)).center.unitVector
        let last = try XCTUnwrap(plan.panel(row: 0, column: plan.columnsPerRow[0] - 1)).center.unitVector
        let towards = last - first
        let centerVector = center.unitVector
        let east = Vector3(-centerVector.y, centerVector.x, 0).normalized
        let north = centerVector.cross(east)
        let direction = AstroMath.atan2Deg(towards.dot(east), towards.dot(north))
        // The planner puts the left panel at the east end of its row; the row runs along the major axis, so the direction
        // from the first to the last panel is the major axis (35°) turned half a circle (215°).
        XCTAssertEqual(AstroMath.normalizeDegrees(direction), 215.0, accuracy: 0.5)
        // An object without a minor axis gives a square region; without a position angle the width runs north-south.
        let round = try MosaicRegion.fitting(center: center, size: try XCTUnwrap(AngularSize(majorArcminutes: 150)), margin: 0)
        guard case let .equatorial(_, roundWidth, roundHeight, roundAngle) = round else { return XCTFail("not equatorial") }
        XCTAssertEqual(roundWidth, 2.5, accuracy: 1e-12)
        XCTAssertEqual(roundHeight, 2.5, accuracy: 1e-12)
        XCTAssertEqual(roundAngle, 270.0, accuracy: 1e-12)
    }

    func testFittingACatalogObject() throws {
        let catalog = try Catalog.loadBundled()
        let m31 = try XCTUnwrap(catalog.object(id: "dso.M31"))
        let region = try MosaicRegion.fitting(object: m31, margin: 0.5)
        guard case let .equatorial(center, width, _, _) = region else { return XCTFail("not equatorial") }
        XCTAssertEqual(center, m31.j2000)
        XCTAssertEqual(width, try XCTUnwrap(m31.angularSize).majorArcminutes / 60 * 1.5, accuracy: 1e-12)
        MosaicTestSupport.assertThrows(MosaicError.objectNotFixed(objectID: "moon")) {
            _ = try MosaicRegion.fitting(object: try XCTUnwrap(catalog.object(id: "moon")))
        }
        MosaicTestSupport.assertThrowsKind("objectNotFixed") {
            _ = try MosaicRegion.fitting(object: try XCTUnwrap(catalog.object(id: "special.ncp")))
        }
        MosaicTestSupport.assertThrows(MosaicError.objectHasNoSize(objectID: "star.hip32349")) {
            _ = try MosaicRegion.fitting(object: try XCTUnwrap(catalog.object(id: "star.hip32349")))
        }
    }

    func testCenteredHorizontalBox() throws {
        guard case let .horizontal(start, span, minimum, maximum) = MosaicRegion.centered(
            centerAzimuth: 180, centerAltitude: 30, azimuthSpan: 120, altitudeSpan: 60) else { return XCTFail("not horizontal") }
        XCTAssertEqual(start, 120.0, accuracy: 1e-12)
        XCTAssertEqual(span, 120.0, accuracy: 1e-12)
        XCTAssertEqual(minimum, 0.0, accuracy: 1e-12)
        XCTAssertEqual(maximum, 60.0, accuracy: 1e-12)
        guard case let .horizontal(clampedStart, _, _, clampedMaximum) = MosaicRegion.centered(
            centerAzimuth: 10, centerAltitude: 80, azimuthSpan: 100, altitudeSpan: 60) else { return XCTFail("not horizontal") }
        XCTAssertEqual(clampedStart, 320.0, accuracy: 1e-12)
        XCTAssertEqual(clampedMaximum, 90.0, accuracy: 1e-12)
    }

    // MARK: Orientation and lens

    func testPortraitSwapsTheFrame() throws {
        let frame = lens(50)
        let region = equatorial(0, 20, 30)
        let landscape = try MosaicPlanner.plan(region: region, frame: frame, orientation: .landscape)
        let portrait = try MosaicPlanner.plan(region: region, frame: frame, orientation: .portrait)
        XCTAssertEqual(landscape.frame, frame)
        XCTAssertEqual(portrait.frame, frame.rotated)
        XCTAssertEqual(portrait.orientation, .portrait)
        XCTAssertEqual(landscape.rows, 2)
        XCTAssertEqual(portrait.rows, 1)
        XCTAssertEqual(portrait.columnsPerRow, [1])
        XCTAssertEqual(try MosaicPlanner.recommendedOrientation(region: region, frame: frame), .portrait)
        XCTAssertEqual(try MosaicPlanner.recommendedOrientation(region: equatorial(0, 40, 10), frame: frame), .landscape)
        XCTAssertEqual(try MosaicPlanner.recommendedOrientation(region: equatorial(0, 20, 15), frame: frame), .landscape)
        XCTAssertEqual(MosaicOrientation(rawValue: "portrait"), .portrait)
        XCTAssertNil(MosaicOrientation(rawValue: "diagonal"))
    }

    func testPlanWithALensSetupUsesItsFieldOfView() throws {
        let setup = LensSetup(sensor: .apsC, focalLengthMillimeters: 35, aperture: 2.8)
        let region = equatorial(10, 30, 20)
        let viaSetup = try MosaicPlanner.plan(region: region, setup: setup, orientation: .portrait, overlap: 0.3)
        let viaFrame = try MosaicPlanner.plan(region: region, frame: setup.fieldOfView, orientation: .portrait, overlap: 0.3)
        XCTAssertEqual(viaFrame, viaSetup)
        XCTAssertEqual(viaSetup.overlap, 0.3)
    }

    // MARK: Shooting order

    func testShootingOrderIsASerpentine() throws {
        let plan = try MosaicPlanner.plan(region: equatorial(0, 80, 50), frame: lens(50), observerLatitude: 40)
        XCTAssertEqual(plan.shootingOrder.count, 9)
        XCTAssertEqual(plan.shootingOrder.sorted(), Array(0..<9))
        for step in 0..<8 {
            let a = plan.panels[plan.shootingOrder[step]]
            let b = plan.panels[plan.shootingOrder[step + 1]]
            if a.row == b.row {
                XCTAssertEqual(abs(a.column - b.column), 1)
            } else {
                XCTAssertEqual(abs(a.row - b.row), 1)
                XCTAssertEqual(a.column, b.column)
            }
        }
        for (place, index) in plan.shootingOrder.enumerated() { XCTAssertEqual(plan.panels[index].shootingPosition, place) }
        XCTAssertEqual(plan.shootingOrder, plan.orderedPanels.map(\.index))
    }

    func testEquatorialOrderStartsWhereTheFirstPanelSets() throws {
        let region = equatorial(0, 80, 50)
        // From the northern hemisphere the western, southern corner sets first and the order runs along the rows.
        let north = try MosaicPlanner.plan(region: region, frame: lens(50), observerLatitude: 40)
        XCTAssertEqual(north.shootingOrder, [8, 7, 6, 3, 4, 5, 2, 1, 0])
        // From the southern hemisphere the northern stars set first.
        let south = try MosaicPlanner.plan(region: region, frame: lens(50), observerLatitude: -40)
        XCTAssertEqual(south.shootingOrder, [2, 1, 0, 3, 4, 5, 8, 7, 6])
        // Without a latitude the western end goes first.
        let row = try MosaicPlanner.plan(region: equatorial(0, 40, 10), frame: lens(50))
        XCTAssertEqual(row.shootingOrder, [1, 0])
        // The reverse order starts where the other ends.
        let reversed = try MosaicPlanner.plan(region: region, frame: lens(50), observerLatitude: 40, reverseOrder: true)
        XCTAssertEqual(reversed.shootingOrder, north.shootingOrder.reversed())
        XCTAssertEqual(reversed.panels[0].shootingPosition, 0)
        XCTAssertEqual(reversed.panels[8].shootingPosition, 8)
    }

    func testSettingHourAngleOfAStar() {
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 30, observerLatitude: nil), 90.0, accuracy: 1e-12)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 0, observerLatitude: 40), 90.0, accuracy: 1e-9)
        // cos H = −tan φ tan δ: a star at declination 20° seen from 40° N sets at an hour angle of 108.1°.
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 20, observerLatitude: 40),
                       AstroMath.acosDeg(-tan(AstroMath.radians(40)) * tan(AstroMath.radians(20))), accuracy: 1e-9)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 60, observerLatitude: 40), 180.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: -60, observerLatitude: 40), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 10, observerLatitude: 90), 180.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: -10, observerLatitude: 90), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MosaicPlanner.settingHourAngle(declination: 0, observerLatitude: 90), 90.0, accuracy: 1e-9)
    }

    func testHorizontalOrderStartsAtTheLeftOfTheBottomRow() throws {
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(24))
        // Two rows of two: bottom row left to right, then the top row right to left.
        XCTAssertEqual(plan.shootingOrder, [2, 3, 1, 0])
        let first = plan.orderedPanels[0]
        XCTAssertEqual(first.row, 1)
        XCTAssertEqual(first.column, 0)
        let reversed = try MosaicPlanner.plan(region: region, frame: lens(24), reverseOrder: true)
        XCTAssertEqual(reversed.shootingOrder, [0, 1, 3, 2])
    }

    // MARK: Warnings and errors

    func testMoreThanOneHundredPanelsGetsAWarning() throws {
        let plan = try MosaicPlanner.plan(region: equatorial(0, 150, 80), frame: lens(135))
        XCTAssertGreaterThan(plan.panelCount, MosaicPlanner.recommendedPanelLimit)
        XCTAssertEqual(plan.warnings, [MosaicWarning.tooManyPanels(count: plan.panelCount)])
        XCTAssertEqual(plan.coverage.coveredFraction, 1.0)
    }

    func testMosaicTooLargeToPlanIsAnError() throws {
        let error = MosaicTestSupport.thrown { _ = try MosaicPlanner.plan(region: self.equatorial(0, 360, 180), frame: self.lens(200)) }
        guard case let .tooManyPanels(count, limit)? = error as? MosaicError else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(limit, MosaicPlanner.maximumPanelCount)
        XCTAssertGreaterThan(count, limit)
        MosaicTestSupport.assertThrowsKind("tooManyPanels") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 360, minimumAltitude: -90, maximumAltitude: 90),
                                       frame: self.lens(1000))
        }
    }

    func testInvalidInputIsRejected() throws {
        let frame = lens(50)
        let good = equatorial(0, 20, 10)
        MosaicTestSupport.assertThrows(MosaicError.nonFiniteInput) {
            _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: .nan, height: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("nonFiniteInput") {
            _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: 10, height: 10, positionAngle: .infinity), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("nonFiniteInput") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: .nan, azimuthSpan: 10, minimumAltitude: 0, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrows(MosaicError.invalidWidth(value: 0)) {
            _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: 0, height: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidWidth") { _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: 361, height: 10), frame: frame) }
        MosaicTestSupport.assertThrowsKind("invalidWidth") { _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: -5, height: 10), frame: frame) }
        MosaicTestSupport.assertThrows(MosaicError.invalidHeight(value: 181)) {
            _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: 10, height: 181), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidHeight") { _ = try MosaicPlanner.plan(region: .equatorial(center: self.sky, width: 10, height: 0), frame: frame) }
        MosaicTestSupport.assertThrows(MosaicError.invalidAzimuthSpan(value: 0)) {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 0, minimumAltitude: 0, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidAzimuthSpan") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 361, minimumAltitude: 0, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrows(MosaicError.invalidAltitudeRange(minimum: 10, maximum: 10)) {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 10, minimumAltitude: 10, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidAltitudeRange") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 10, minimumAltitude: 20, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidAltitudeRange") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 10, minimumAltitude: -91, maximumAltitude: 10), frame: frame)
        }
        MosaicTestSupport.assertThrowsKind("invalidAltitudeRange") {
            _ = try MosaicPlanner.plan(region: .horizontal(azimuthStart: 0, azimuthSpan: 10, minimumAltitude: 0, maximumAltitude: 91), frame: frame)
        }
        for overlap in [0.05, 0.6, Double.nan, -1.0, Double.infinity] {
            MosaicTestSupport.assertThrowsKind("invalidOverlap", "overlap \(overlap)") {
                _ = try MosaicPlanner.plan(region: good, frame: frame, overlap: overlap)
            }
        }
        XCTAssertEqual(try MosaicPlanner.plan(region: good, frame: frame, overlap: 0.1).overlap, 0.1)
        XCTAssertEqual(try MosaicPlanner.plan(region: good, frame: frame, overlap: 0.5).overlap, 0.5)
        MosaicTestSupport.assertThrows(MosaicError.invalidFrame(horizontal: 0, vertical: 20)) {
            _ = try MosaicPlanner.plan(region: good, frame: FrameSize(horizontal: 0, vertical: 20, diagonal: 20))
        }
        MosaicTestSupport.assertThrowsKind("invalidFrame") { _ = try MosaicPlanner.plan(region: good, frame: FrameSize(horizontal: 180, vertical: 20, diagonal: 20)) }
        MosaicTestSupport.assertThrowsKind("invalidFrame") { _ = try MosaicPlanner.plan(region: good, frame: FrameSize(horizontal: 20, vertical: -1, diagonal: 20)) }
        MosaicTestSupport.assertThrowsKind("nonFiniteInput") { _ = try MosaicPlanner.plan(region: good, frame: FrameSize(horizontal: .nan, vertical: 20, diagonal: 20)) }
        MosaicTestSupport.assertThrows(MosaicError.invalidLatitude(value: 91)) {
            _ = try MosaicPlanner.plan(region: good, frame: frame, observerLatitude: 91)
        }
        MosaicTestSupport.assertThrowsKind("invalidLatitude") { _ = try MosaicPlanner.plan(region: good, frame: frame, observerLatitude: .nan) }
        let small = try XCTUnwrap(AngularSize(majorArcminutes: 60))
        MosaicTestSupport.assertThrows(MosaicError.invalidMargin(value: -0.1)) { _ = try MosaicRegion.fitting(center: self.sky, size: small, margin: -0.1) }
        MosaicTestSupport.assertThrowsKind("invalidMargin") { _ = try MosaicRegion.fitting(center: self.sky, size: small, margin: 2.5) }
        MosaicTestSupport.assertThrowsKind("invalidMargin") { _ = try MosaicRegion.fitting(center: self.sky, size: small, margin: .nan) }
        let huge = try XCTUnwrap(AngularSize(majorArcminutes: 18_000))
        MosaicTestSupport.assertThrowsKind("invalidWidth") { _ = try MosaicRegion.fitting(center: self.sky, size: huge, margin: 0.5) }
    }

    // MARK: Outline and values

    func testOutlineFollowsTheEdges() throws {
        let plan = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60),
            frame: lens(24), orientation: .portrait)
        let panel = plan.panels[0]
        let outline = panel.outline(segmentsPerEdge: 4)
        XCTAssertEqual(outline.count, 16)
        // Every fourth point is a corner.
        for corner in 0..<4 {
            XCTAssertEqual(outline[corner * 4].unitVector.angle(to: panel.corners[corner].unitVector), 0.0, accuracy: 1e-9)
        }
        // The midpoint of the top edge is on the great circle through the top corners.
        let a = panel.corners[0].unitVector
        let b = panel.corners[1].unitVector
        let normal = a.cross(b).normalized
        for index in 0...4 { XCTAssertEqual(normal.dot(outline[index].unitVector), 0.0, accuracy: 1e-9) }
        XCTAssertEqual(panel.outline(segmentsPerEdge: 0).count, 4)
        XCTAssertEqual(panel.outline(segmentsPerEdge: 1000).count, 4 * 64)
        XCTAssertNotNil(outline[0].horizontalCoordinate)
        XCTAssertNil(outline[0].equatorialCoordinate)
        let equatorialPlan = try MosaicPlanner.plan(region: equatorial(0, 20, 10), frame: lens(50))
        XCTAssertNotNil(equatorialPlan.panels[0].outline()[0].equatorialCoordinate)
    }

    func testRegionOutlineTracesTheRegion() throws {
        // A horizontal box: along the top edge from the left (the start of the azimuth range), down the right side,
        // back along the bottom edge and up the left side.
        let box = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60), frame: lens(24))
        let loops = box.regionOutline(pointsPerEdge: 8)
        XCTAssertEqual(loops.count, 1)
        let loop = try loops[0].map { try XCTUnwrap($0.horizontalCoordinate) }
        XCTAssertEqual(loop.count, 32)
        XCTAssertEqual(HorizontalCoordinate(azimuth: 150, altitude: 60).unitVector.angle(to: loop[0].unitVector), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HorizontalCoordinate(azimuth: 260, altitude: 60).unitVector.angle(to: loop[8].unitVector), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HorizontalCoordinate(azimuth: 260, altitude: 0).unitVector.angle(to: loop[16].unitVector), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HorizontalCoordinate(azimuth: 150, altitude: 0).unitVector.angle(to: loop[24].unitVector), 0.0, accuracy: 1e-9)
        for index in 0..<8 {
            XCTAssertEqual(loop[index].altitude, 60.0, accuracy: 1e-9)
            XCTAssertEqual(loop[index].azimuth, 150.0 + 110.0 * Double(index) / 8.0, accuracy: 1e-9)
            XCTAssertEqual(loop[16 + index].altitude, 0.0, accuracy: 1e-9)
            XCTAssertEqual(loop[16 + index].azimuth, 260.0 - 110.0 * Double(index) / 8.0, accuracy: 1e-9)
        }
        // An equatorial region: the top edge is at the upper declination, spread over the right-ascension span.
        let sky = try MosaicPlanner.plan(region: equatorial(20, 40, 10), frame: lens(50))
        let outline = try sky.regionOutline(pointsPerEdge: 4)[0].map { try XCTUnwrap($0.equatorialCoordinate) }
        let span = 40.0 / cos(AstroMath.radians(20))
        XCTAssertEqual(outline.count, 16)
        XCTAssertEqual(outline[0].declination, 25.0, accuracy: 1e-9)
        XCTAssertEqual(outline[0].rightAscension, 75.0 + span / 2, accuracy: 1e-9)
        XCTAssertEqual(outline[8].declination, 15.0, accuracy: 1e-9)
        XCTAssertEqual(outline[8].rightAscension, 75.0 - span / 2, accuracy: 1e-9)
        // A region that wraps all the way round is two circles.
        let ring = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 0, azimuthSpan: 360, minimumAltitude: 0, maximumAltitude: 30), frame: lens(24)).regionOutline(pointsPerEdge: 4)
        XCTAssertEqual(ring.count, 2)
        XCTAssertEqual(ring.map(\.count), [16, 16])
        XCTAssertTrue(try ring[0].allSatisfy { abs(try XCTUnwrap($0.horizontalCoordinate).altitude - 30.0) < 1e-9 })
        XCTAssertTrue(try ring[1].allSatisfy { abs(try XCTUnwrap($0.horizontalCoordinate).altitude) < 1e-9 })
        // The number of points is limited.
        XCTAssertEqual(box.regionOutline(pointsPerEdge: 0)[0].count, 8)
        XCTAssertEqual(box.regionOutline(pointsPerEdge: 1000)[0].count, 1024)
        // Turned by a position angle the outline turns with the panels.
        let center = EquatorialCoordinate(rightAscensionHours: 5, declination: 20).unitVector
        let rotation = Matrix3.rotation(axis: center, angleRadians: -AstroMath.radians(37))
        let base = try MosaicPlanner.plan(region: equatorial(20, 40, 10), frame: lens(50)).regionOutline(pointsPerEdge: 6)[0]
        let turned = try MosaicPlanner.plan(region: equatorial(20, 40, 10, 37), frame: lens(50)).regionOutline(pointsPerEdge: 6)[0]
        for index in base.indices {
            XCTAssertEqual((rotation * base[index].unitVector).angle(to: turned[index].unitVector), 0.0, accuracy: 1e-8)
        }
    }

    func testPlansAreValuesAndRepeatable() throws {
        let region = equatorial(35, 70, 45, 20)
        XCTAssertEqual(try MosaicPlanner.plan(region: region, frame: lens(50)), try MosaicPlanner.plan(region: region, frame: lens(50)))
        XCTAssertNotEqual(try MosaicPlanner.plan(region: region, frame: lens(50)), try MosaicPlanner.plan(region: region, frame: lens(85)))
        let plan = try MosaicPlanner.plan(region: region, frame: lens(50))
        XCTAssertEqual(MosaicFrameKind(rawValue: "equatorial"), .equatorial)
        XCTAssertNil(MosaicFrameKind(rawValue: "galactic"))
        XCTAssertEqual(plan.panelCount, plan.columnsPerRow.reduce(0, +))
        XCTAssertEqual(plan.rows, plan.columnsPerRow.count)
        XCTAssertEqual(plan.columns, plan.columnsPerRow.max())
    }

    func testPoleOfAnEquatorialPlanFollowsThePositionAngle() throws {
        let unturned = try MosaicPlanner.plan(region: equatorial(30, 20, 10), frame: lens(50))
        let pole = try XCTUnwrap(unturned.pole.equatorialCoordinate)
        XCTAssertEqual(pole.declination, 90.0, accuracy: 1e-9)
        let turned = try MosaicPlanner.plan(region: equatorial(30, 20, 10, 90), frame: lens(50))
        // The pole of the rows swings round the centre with the position angle: 90° east it lies on the equator-like circle.
        let center = EquatorialCoordinate(rightAscensionHours: 5, declination: 30)
        XCTAssertEqual(center.angularSeparation(to: try XCTUnwrap(unturned.pole.equatorialCoordinate)), 90.0 - 30.0, accuracy: 1e-9)
        XCTAssertEqual(center.angularSeparation(to: try XCTUnwrap(turned.pole.equatorialCoordinate)), 90.0 - 30.0, accuracy: 1e-9)
        XCTAssertLessThan(try XCTUnwrap(turned.pole.equatorialCoordinate).declination, 90.0)
        let horizontal = try MosaicPlanner.plan(
            region: .horizontal(azimuthStart: 0, azimuthSpan: 90, minimumAltitude: 0, maximumAltitude: 30), frame: lens(24))
        XCTAssertEqual(try XCTUnwrap(horizontal.pole.horizontalCoordinate).altitude, 90.0, accuracy: 1e-9)
    }

    func testPlanningIsFast() throws {
        let region = equatorial(60, 80, 50)
        let frame = lens(50)
        _ = try MosaicPlanner.plan(region: region, frame: frame)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<50 { _ = try MosaicPlanner.plan(region: region, frame: frame) }
        let perPlanMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 50.0 / 1e6
        XCTAssertLessThan(perPlanMilliseconds, 60.0, "\(perPlanMilliseconds) ms per plan")
    }
}

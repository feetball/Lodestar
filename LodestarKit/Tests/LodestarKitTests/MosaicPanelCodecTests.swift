import XCTest
@testable import LodestarKit

/// The mosaic panel writers.
final class MosaicPanelCodecTests: XCTestCase {
    private func plan(positionAngle: Double = 0) throws -> MosaicPlan {
        try MosaicPlanner.plan(
            region: .equatorial(
                center: EquatorialCoordinate(rightAscension: 10.6847, declination: 41.2687),
                width: 8, height: 5, positionAngle: positionAngle
            ),
            frame: MosaicTestSupport.frame(focalLength: 400)
        )
    }

    /// The difference of two angles in degrees, in [0, 180].
    private func separation(_ a: Double, _ b: Double) -> Double {
        abs(AstroMath.normalizeSignedDegrees(a - b))
    }

    func testRecordsFollowThePanelsOfTheplan() throws {
        let plan = try plan()
        let records = try MosaicPanelCodec.records(of: plan)
        XCTAssertEqual(records.count, plan.panelCount)
        XCTAssertGreaterThan(records.count, 1)
        for (record, panel) in zip(records, plan.panels) {
            let center = try XCTUnwrap(panel.center.equatorialCoordinate)
            XCTAssertEqual(record.panel, panel.id)
            XCTAssertEqual(record.row, panel.row + 1)
            XCTAssertEqual(record.column, panel.column + 1)
            XCTAssertEqual(record.rightAscension, center.rightAscension, accuracy: 1e-12)
            XCTAssertEqual(record.declination, center.declination, accuracy: 1e-12)
            XCTAssertEqual(record.order, panel.shootingPosition + 1)
        }
        XCTAssertEqual(records.map(\.order).sorted(), Array(1...records.count))
    }

    func testPositionAngleIsTheDirectionOfTheTopEdge() throws {
        // Rows follow the declination circles, so the top edge points north up to the convergence of the meridians.
        for record in try MosaicPanelCodec.records(of: plan()) {
            XCTAssertLessThan(separation(record.positionAngle, 0), 4, record.panel)
            XCTAssertGreaterThanOrEqual(record.positionAngle, 0)
            XCTAssertLessThan(record.positionAngle, 360)
        }
        // A region turned by 90° has its top edges pointing east.
        for record in try MosaicPanelCodec.records(of: plan(positionAngle: 90)) {
            XCTAssertLessThan(separation(record.positionAngle, 90), 4, record.panel)
        }
    }

    func testAPlanInAzimuthAndAltitudeHasNoCoordinates() throws {
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: MosaicTestSupport.frame(focalLength: 35))
        XCTAssertThrowsError(try MosaicPanelCodec.records(of: plan)) { XCTAssertEqual($0 as? InterchangeError, .horizontalPlan) }
    }

    private let records = [
        MosaicPanelRecord(panel: "R1C2", row: 1, column: 2, rightAscension: 10.6847, declination: 41.2687, positionAngle: 12.5, order: 3),
        MosaicPanelRecord(panel: "R1C1", row: 1, column: 1, rightAscension: 359.9999, declination: -0.00001, positionAngle: 0, order: 1),
        MosaicPanelRecord(panel: "R2C1", row: 2, column: 1, rightAscension: 83.8221, declination: -5.3911, positionAngle: 359.99999, order: 2),
    ]

    func testCSV() {
        XCTAssertEqual(MosaicPanelCodec.csv(records), [
            "Panel,Row,Column,RA J2000 (deg),Dec J2000 (deg),Position angle (deg),Order",
            "R1C2,1,2,10.68470,41.26870,12.50000,3",
            "R1C1,1,1,359.99990,0.00000,0.00000,1",
            "R2C1,2,1,83.82210,-5.39110,359.99999,2",
        ].joined(separator: "\r\n") + "\r\n")
    }

    func testTextListInShootingOrder() {
        XCTAssertEqual(MosaicPanelCodec.text(records, targetName: "M 31"), """
        M 31 R1C1, 00 00 00.0, +00 00 00
        M 31 R2C1, 05 35 17.3, -05 23 28
        M 31 R1C2, 00 42 44.3, +41 16 07

        """)
        XCTAssertTrue(MosaicPanelCodec.text(records, targetName: " \n ").hasPrefix("Mosaic R1C1, "))
        XCTAssertEqual(MosaicPanelCodec.text([], targetName: "x"), "")
    }

    func testTextOfARealPlanReadsBackWithTheAngleParsers() throws {
        let plan = try plan()
        let list = try MosaicPanelCodec.records(of: plan)
        for (line, record) in zip(MosaicPanelCodec.text(list, targetName: "M 31").split(separator: "\n"), list.sorted { $0.order < $1.order }) {
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(parts.count, 3)
            let hours = try XCTUnwrap(AngleFormatter.parseRightAscension(parts[1]))
            let declination = try XCTUnwrap(AngleFormatter.parseDeclination(parts[2]))
            XCTAssertEqual(hours * 15, record.rightAscension, accuracy: 0.5 * 15 / 3600 + 1e-9)
            XCTAssertEqual(declination, record.declination, accuracy: 0.5 / 3600 + 1e-9)
        }
    }
}

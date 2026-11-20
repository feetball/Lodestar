import LodestarKit
import XCTest
@testable import AppCore

/// The words for a finished mosaic: "All 4 panels shot", but not "All 1 panels shot".
///
/// `MosaicSession.shared` is the only instance there is, so every test ends the mosaic it started.
@MainActor
final class FixMosaicProgressTextTests: XCTestCase {
    private func lens(_ focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: .fullFrame, focalLength: focalLength)
    }

    /// A 20 by 15 degree area at a 50 mm lens: one panel.
    private func onePanelPlan() throws -> MosaicPlan {
        let center = EquatorialCoordinate(rightAscensionHours: 5, declination: 0)
        let plan = try MosaicPlanner.plan(region: .equatorial(center: center, width: 20, height: 15), frame: lens(50))
        XCTAssertEqual(plan.panelCount, 1)
        return plan
    }

    /// A panorama of 2 rows and 2 columns: four panels.
    private func fourPanelPlan() throws -> MosaicPlan {
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(24))
        XCTAssertEqual(plan.panelCount, 4)
        return plan
    }

    private func idleSession() -> MosaicSession {
        let session = MosaicSession.shared
        session.finish()
        return session
    }

    func testAFinishedMosaicOfOnePanelDoesNotSayOnePanels() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try onePanelPlan(), title: "Single")
        XCTAssertEqual(session.progressText, "Panel 1 of 1")
        session.advance()
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.progressText, "The panel is shot")
        XCTAssertFalse(session.progressText.contains("1 panels"))
    }

    func testAFinishedMosaicOfSeveralPanelsStillCountsThem() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "Four")
        for _ in 0..<4 { session.advance() }
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.progressText, "All 4 panels shot")
    }
}

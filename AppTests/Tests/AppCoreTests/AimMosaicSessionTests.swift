import LodestarKit
import XCTest
@testable import AppCore

/// The mosaic being shot: starting, moving through the shooting order, both ends of the steps, and finishing.
///
/// `MosaicSession.shared` is the only instance there is, so every test ends the mosaic it started.
@MainActor
final class AimMosaicSessionTests: XCTestCase {
    private func lens(_ focalLength: Double) -> FrameSize {
        FieldOfView.of(sensor: .fullFrame, focalLength: focalLength)
    }

    /// A panorama of 2 rows and 2 columns. Horizontal plans are shot from the left end of the bottom row and then in a
    /// serpentine, so the shooting order is the panels 2, 3, 1, 0.
    private func fourPanelPlan() throws -> MosaicPlan {
        let region = MosaicRegion.horizontal(azimuthStart: 150, azimuthSpan: 110, minimumAltitude: 0, maximumAltitude: 60)
        let plan = try MosaicPlanner.plan(region: region, frame: lens(24))
        XCTAssertEqual(plan.columnsPerRow, [2, 2])
        XCTAssertEqual(plan.shootingOrder, [2, 3, 1, 0])
        return plan
    }

    private func onePanelPlan() throws -> MosaicPlan {
        let center = EquatorialCoordinate(rightAscensionHours: 5, declination: 0)
        let plan = try MosaicPlanner.plan(region: .equatorial(center: center, width: 20, height: 15), frame: lens(50))
        XCTAssertEqual(plan.panelCount, 1)
        return plan
    }

    /// The shared session with no mosaic running.
    private func idleSession() -> MosaicSession {
        let session = MosaicSession.shared
        session.finish()
        return session
    }

    // MARK: Nothing running

    func testWithoutAMosaicThereIsNothingToShow() {
        let session = idleSession()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.plan)
        XCTAssertEqual(session.title, "")
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.panelCount, 0)
        XCTAssertFalse(session.isComplete)
        XCTAssertFalse(session.isLastPanel)
        XCTAssertFalse(session.canGoBack)
        XCTAssertNil(session.currentPanel)
        XCTAssertEqual(session.progressText, "")
        XCTAssertNil(session.positionText)
        XCTAssertNil(MosaicDisplay.current)
    }

    func testStepsWithoutAMosaicChangeNothing() {
        let session = idleSession()
        let revision = session.revision
        session.advance()
        session.goBack()
        session.finish()
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.revision, revision)
        XCTAssertFalse(session.isActive)
    }

    // MARK: Starting

    func testAMosaicStartsAtTheFirstPanelOfTheShootingOrder() throws {
        let session = idleSession()
        defer { session.finish() }
        let plan = try fourPanelPlan()
        let revision = session.revision
        session.start(plan: plan, title: "Milky Way arch")
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.plan, plan)
        XCTAssertEqual(session.title, "Milky Way arch")
        XCTAssertEqual(session.panelCount, 4)
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.revision, revision + 1)
        XCTAssertEqual(session.currentPanel, plan.panels[2])
        XCTAssertEqual(session.progressText, "Panel 1 of 4")
        XCTAssertEqual(session.positionText, "Row 2 of 2, column 1")
        XCTAssertFalse(session.canGoBack)
        XCTAssertFalse(session.isLastPanel)
        XCTAssertFalse(session.isComplete)
    }

    func testStartingAgainReplacesTheMosaicInProgress() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "First")
        session.advance()
        session.advance()
        XCTAssertEqual(session.step, 2)

        let single = try onePanelPlan()
        let revision = session.revision
        session.start(plan: single, title: "Second")
        XCTAssertEqual(session.title, "Second")
        XCTAssertEqual(session.plan, single)
        XCTAssertEqual(session.panelCount, 1)
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.revision, revision + 1)
    }

    // MARK: Moving through the panels

    func testAdvancingWalksTheShootingOrderAndTheGrid() throws {
        let session = idleSession()
        defer { session.finish() }
        let plan = try fourPanelPlan()
        session.start(plan: plan, title: "Walk")

        let expected: [(panel: Int, position: String)] = [
            (2, "Row 2 of 2, column 1"),
            (3, "Row 2 of 2, column 2"),
            (1, "Row 1 of 2, column 2"),
            (0, "Row 1 of 2, column 1"),
        ]
        for (step, entry) in expected.enumerated() {
            XCTAssertEqual(session.step, step)
            XCTAssertEqual(session.currentPanel, plan.panels[entry.panel], "step \(step)")
            XCTAssertEqual(session.positionText, entry.position, "step \(step)")
            XCTAssertEqual(session.progressText, "Panel \(step + 1) of 4", "step \(step)")
            XCTAssertEqual(session.canGoBack, step > 0, "step \(step)")
            XCTAssertEqual(session.isLastPanel, step == 3, "step \(step)")
            XCTAssertFalse(session.isComplete, "step \(step)")
            session.advance()
        }
    }

    func testAdvancingPastTheLastPanelCompletesTheMosaic() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "Done")
        for _ in 0..<3 { session.advance() }
        XCTAssertTrue(session.isLastPanel)

        session.advance()
        XCTAssertEqual(session.step, 4)
        XCTAssertTrue(session.isComplete)
        XCTAssertFalse(session.isLastPanel)
        XCTAssertTrue(session.canGoBack)
        XCTAssertNil(session.currentPanel)
        XCTAssertNil(session.positionText)
        XCTAssertEqual(session.progressText, "All 4 panels shot")
        XCTAssertTrue(session.isActive)
    }

    func testAdvancingAfterTheEndDoesNothing() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "End")
        for _ in 0..<4 { session.advance() }
        let revision = session.revision
        session.advance()
        XCTAssertEqual(session.step, 4)
        XCTAssertEqual(session.revision, revision)
    }

    func testGoingBackRepeatsThePreviousPanel() throws {
        let session = idleSession()
        defer { session.finish() }
        let plan = try fourPanelPlan()
        session.start(plan: plan, title: "Back")
        session.advance()
        session.advance()
        let revision = session.revision
        session.goBack()
        XCTAssertEqual(session.step, 1)
        XCTAssertEqual(session.currentPanel, plan.panels[3])
        XCTAssertEqual(session.revision, revision + 1)
    }

    func testGoingBackFromTheEndReopensTheLastPanel() throws {
        let session = idleSession()
        defer { session.finish() }
        let plan = try fourPanelPlan()
        session.start(plan: plan, title: "Reopen")
        for _ in 0..<4 { session.advance() }
        XCTAssertTrue(session.isComplete)

        session.goBack()
        XCTAssertFalse(session.isComplete)
        XCTAssertTrue(session.isLastPanel)
        XCTAssertEqual(session.step, 3)
        XCTAssertEqual(session.currentPanel, plan.panels[0])
        XCTAssertEqual(session.progressText, "Panel 4 of 4")
    }

    func testGoingBackAtTheFirstPanelDoesNothing() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "First")
        let revision = session.revision
        session.goBack()
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.revision, revision)
        XCTAssertFalse(session.canGoBack)
    }

    func testASinglePanelMosaicIsAtItsLastPanelFromTheStart() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try onePanelPlan(), title: "Single")
        XCTAssertTrue(session.isLastPanel)
        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(session.progressText, "Panel 1 of 1")
        XCTAssertEqual(session.positionText, "Row 1 of 1, column 1")
        session.advance()
        XCTAssertTrue(session.isComplete)
        XCTAssertFalse(session.isLastPanel)
        XCTAssertNil(session.currentPanel)
    }

    // MARK: Finishing

    func testFinishingEndsTheMosaic() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "Finish")
        session.advance()
        let revision = session.revision
        session.finish()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.plan)
        XCTAssertEqual(session.title, "")
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.panelCount, 0)
        XCTAssertEqual(session.progressText, "")
        XCTAssertEqual(session.revision, revision + 1)
        XCTAssertNil(MosaicDisplay.current)
    }

    func testEveryChangeCountsInTheRevision() throws {
        let session = idleSession()
        defer { session.finish() }
        let start = session.revision
        session.start(plan: try fourPanelPlan(), title: "Count")
        session.advance()
        session.advance()
        session.goBack()
        session.finish()
        XCTAssertEqual(session.revision, start + 5)
    }

    // MARK: What the overlays need

    func testThePanelsAreDrawnAsDoneCurrentNextAndLater() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "States")
        session.advance()
        XCTAssertEqual(session.state(ofShootingPosition: 0), .done)
        XCTAssertEqual(session.state(ofShootingPosition: 1), .current)
        XCTAssertEqual(session.state(ofShootingPosition: 2), .next)
        XCTAssertEqual(session.state(ofShootingPosition: 3), .later)
        XCTAssertEqual(session.state(ofShootingPosition: 99), .later)
        XCTAssertEqual(session.state(ofShootingPosition: -1), .done)
    }

    func testTheDisplayHoldsTheStepAndTheCountOfTheSharedSession() throws {
        let session = idleSession()
        defer { session.finish() }
        session.start(plan: try fourPanelPlan(), title: "Display")
        XCTAssertEqual(MosaicDisplay.current, MosaicDisplay(step: 0, count: 4))
        session.advance()
        session.advance()
        XCTAssertEqual(MosaicDisplay.current, MosaicDisplay(step: 2, count: 4))
        for _ in 0..<2 { session.advance() }
        XCTAssertEqual(MosaicDisplay.current, MosaicDisplay(step: 4, count: 4))
    }

    func testTheDisplayStatesAtTheEdgesOfTheOrder() {
        let first = MosaicDisplay(step: 0, count: 3)
        XCTAssertEqual(first.state(ofShootingPosition: 0), .current)
        XCTAssertEqual(first.state(ofShootingPosition: 1), .next)
        XCTAssertEqual(first.state(ofShootingPosition: 2), .later)

        let last = MosaicDisplay(step: 2, count: 3)
        XCTAssertEqual(last.state(ofShootingPosition: 0), .done)
        XCTAssertEqual(last.state(ofShootingPosition: 1), .done)
        XCTAssertEqual(last.state(ofShootingPosition: 2), .current)
        XCTAssertEqual(last.state(ofShootingPosition: 3), .next)

        let complete = MosaicDisplay(step: 3, count: 3)
        XCTAssertEqual(complete.state(ofShootingPosition: 2), .done)
        XCTAssertEqual(complete.state(ofShootingPosition: 3), .current)
    }

    func testDisplaysAreEqualWhenStepAndCountAre() {
        XCTAssertEqual(MosaicDisplay(step: 1, count: 4), MosaicDisplay(step: 1, count: 4))
        XCTAssertNotEqual(MosaicDisplay(step: 1, count: 4), MosaicDisplay(step: 2, count: 4))
        XCTAssertNotEqual(MosaicDisplay(step: 1, count: 4), MosaicDisplay(step: 1, count: 5))
    }
}

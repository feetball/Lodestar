import Foundation
import LodestarKit
import Observation

/// How a panel of the mosaic is drawn on the sky.
enum MosaicPanelState: Sendable {
    /// Already shot.
    case done
    /// The panel being aimed at.
    case current
    /// The panel after the current one.
    case next
    /// Further ahead in the shooting order.
    case later
}

/// The mosaic being shot: the plan, its title and which panel is next.
///
/// One instance is shared by the whole app (`MosaicSession.shared`): the Aim screen steers to the current panel and
/// moves on when a panel has been shot, and the Sky chart draws the panels. It lives as long as the app runs, so a
/// mosaic in progress survives switching tabs. Only the Aim screen changes it.
@MainActor
@Observable
final class MosaicSession {
    static let shared = MosaicSession()

    /// The plan being shot; `nil` while no mosaic is running.
    private(set) var plan: MosaicPlan?
    /// What the mosaic covers, in words: an object's name, "Milky Way arch" or the custom size.
    private(set) var title = ""
    /// The place in the shooting order of the panel being shot; equal to `panelCount` once every panel is done.
    private(set) var step = 0
    /// Counts every change of plan or step, so work that follows the session can tell when to refresh.
    private(set) var revision = 0

    private init() {}

    // MARK: Derived state

    var isActive: Bool { plan != nil }
    var panelCount: Int { plan?.panelCount ?? 0 }
    var isComplete: Bool { plan != nil && step >= panelCount }
    var isLastPanel: Bool { plan != nil && step == panelCount - 1 }
    var canGoBack: Bool { step > 0 }

    /// The panel being shot, or `nil` when there is no mosaic or it is complete.
    var currentPanel: MosaicPanel? {
        guard let plan, plan.shootingOrder.indices.contains(step) else { return nil }
        return plan.panels[plan.shootingOrder[step]]
    }

    /// "Panel 3 of 12", or "All 12 panels shot" once complete.
    var progressText: String {
        guard plan != nil else { return "" }
        return isComplete ? Self.allShotText(panelCount: panelCount) : "Panel \(step + 1) of \(panelCount)"
    }

    /// "All 12 panels shot", or "The panel is shot" for a mosaic of one panel.
    nonisolated static func allShotText(panelCount: Int) -> String {
        panelCount == 1 ? "The panel is shot" : "All \(panelCount) panels shot"
    }

    /// Where the current panel sits in the grid: "Row 2 of 3, column 1".
    var positionText: String? {
        guard let plan, let panel = currentPanel else { return nil }
        return "Row \(panel.row + 1) of \(plan.rows), column \(panel.column + 1)"
    }

    /// The state of the panel at `position` in the shooting order.
    func state(ofShootingPosition position: Int) -> MosaicPanelState {
        MosaicDisplay(step: step, count: panelCount).state(ofShootingPosition: position)
    }

    // MARK: Changes

    /// Starts shooting `plan` from its first panel, replacing any mosaic in progress.
    func start(plan: MosaicPlan, title: String) {
        self.plan = plan
        self.title = title
        step = 0
        revision += 1
    }

    /// The current panel has been shot: moves to the next, or to the finished state after the last.
    func advance() {
        guard plan != nil, step < panelCount else { return }
        step += 1
        revision += 1
    }

    /// Goes back one panel, for a shot that has to be redone.
    func goBack() {
        guard plan != nil, step > 0 else { return }
        step -= 1
        revision += 1
    }

    /// Ends the mosaic.
    func finish() {
        guard plan != nil else { return }
        plan = nil
        title = ""
        step = 0
        revision += 1
    }
}

/// What the overlays need to draw a mosaic: the step in the shooting order and the number of panels.
struct MosaicDisplay: Equatable, Sendable {
    let step: Int
    let count: Int

    /// The display of the shared session, or `nil` when no mosaic runs. Reading it inside a view's body or a
    /// timeline makes the view follow the session.
    @MainActor
    static var current: MosaicDisplay? {
        let session = MosaicSession.shared
        return session.isActive ? MosaicDisplay(step: session.step, count: session.panelCount) : nil
    }

    func state(ofShootingPosition position: Int) -> MosaicPanelState {
        if position < step { return .done }
        if position == step { return .current }
        return position == step + 1 ? .next : .later
    }
}

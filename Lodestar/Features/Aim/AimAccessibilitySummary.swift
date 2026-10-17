import SwiftUI

/// An invisible element for VoiceOver that says where the camera points relative to the target, refreshed once a
/// second. The canvas and the live numbers are not accessible, and speaking them ten times a second would be noise.
struct AimAccessibilitySummary: View {
    let model: AimViewModel
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isActive)) { _ in
            Color.clear
                .accessibilityElement()
                .accessibilityLabel(summary())
                .accessibilityAddTraits(.updatesFrequently)
        }
        .allowsHitTesting(false)
    }

    private func summary() -> String {
        guard let frame = model.engine.frame() else { return "Waiting for the motion sensors." }
        guard let target = model.guidanceTarget else { return "No target. Use the Target button to choose one." }
        guard let guidance = frame.guidance else { return "Locating \(target.name)." }
        let summary = AimGuidanceSummary(guidance)
        let note = summary.isBelowHorizon ? " Below the horizon." : ""
        return "\(target.name): \(summary.spokenText).\(note)"
    }
}

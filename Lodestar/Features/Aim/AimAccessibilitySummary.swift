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
        let skyline = model.skyContent?.skyline.map {
            " The sky overlay shades the ground below your recorded skyline, up to \(AimFormat.spoken($0.highestAltitude)) high."
        } ?? ""
        let session = model.mosaicSession
        if session.isActive {
            return mosaicSummary(session: session, frame: frame) + skyline
        }
        if let source = model.satelliteSource {
            return SatelliteAimText.spoken(source, frame: frame) + skyline
        }
        guard let target = model.guidanceTarget else { return "No target. Use the Target button to choose one." + skyline }
        guard let guidance = frame.guidance else { return "Locating \(target.name)." + skyline }
        let summary = AimGuidanceSummary(guidance)
        let note = summary.isBelowHorizon ? " Below the horizon." : ""
        return "\(target.name): \(summary.spokenText).\(note)" + skyline
    }

    /// "Mosaic of Orion Nebula, panel 3 of 12: pan right 12 degrees, tilt up 3 degrees, 15 degrees away. Rotate the
    /// camera 12 degrees clockwise."
    private func mosaicSummary(session: MosaicSession, frame: AimFrame) -> String {
        let heading = "Mosaic of \(session.title), \(session.progressText.lowercased())"
        if session.isComplete { return "\(heading). Use Finish to end it." }
        guard let guidance = frame.guidance, let mosaic = frame.mosaic else { return "\(heading). Locating the panel." }
        let summary = AimGuidanceSummary(guidance)
        let horizon = mosaic.aim.isAboveHorizon ? "" : " This panel is below the horizon."
        return "\(heading): \(summary.spokenText). \(AimMosaicRoll.spokenText(delta: mosaic.rollDelta)).\(horizon)"
    }
}

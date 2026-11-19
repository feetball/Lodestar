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
        previewLead() + liveSummary()
    }

    /// While the sky is previewed: where it is previewed at and where the target will stand then.
    private func previewLead() -> String {
        guard let moment = model.previewMoment else { return "" }
        let lead = AimPreview.spokenChip(time: moment.time, day: moment.day, isDaylight: model.isDaylightAtPreview == true)
        guard let target = model.guidanceTarget, let placed = model.engine.frame()?.target,
              !model.mosaicSession.isActive, model.isSkyBuiltForPreview else { return lead + " " }
        let place = AimPreview.spokenPlace(name: target.name, altitude: placed.horizontal.altitude, time: moment.text,
                                           isFuture: moment.isFuture)
        return lead + " " + place + " "
    }

    private func liveSummary() -> String {
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
        guard let target = model.guidanceTarget else {
            if let nearby = model.nearbyObject(in: frame) {
                return "No target. Near \(nearby.name), \(AimFormat.spoken(nearby.separation)) from center." + skyline
            }
            return "No target. Use the Target button to choose one." + skyline
        }
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

import Foundation
import LodestarKit

/// What the guidance asks of the photographer, in words and numbers for the readouts and VoiceOver.
struct AimGuidanceSummary {
    /// One movement of the tripod head.
    struct Move {
        /// "Pan right", "Tilt down".
        let verb: String
        let systemImage: String
        /// The size of the movement in degrees (always positive).
        let degrees: Double
    }

    let pan: Move
    let tilt: Move
    /// Angle between where the camera points and the target, degrees.
    let separation: Double
    let isOnTarget: Bool
    /// Azimuth is a poor guide within a few degrees of the zenith: only the arrow and the separation are reliable.
    let isNearZenith: Bool
    let isBelowHorizon: Bool

    init(_ guidance: Guidance) {
        pan = Move(verb: guidance.panDelta >= 0 ? "Pan right" : "Pan left",
                   systemImage: guidance.panDelta >= 0 ? "arrow.right" : "arrow.left",
                   degrees: abs(guidance.panDelta))
        tilt = Move(verb: guidance.tiltDelta >= 0 ? "Tilt up" : "Tilt down",
                    systemImage: guidance.tiltDelta >= 0 ? "arrow.up" : "arrow.down",
                    degrees: abs(guidance.tiltDelta))
        separation = guidance.separation
        isOnTarget = guidance.state == .onTarget
        isNearZenith = guidance.isNearZenith
        isBelowHorizon = guidance.targetBelowHorizon
    }

    /// The summary for VoiceOver, e.g. "Pan right 23 degrees, tilt up 12 degrees, 26 degrees away".
    var spokenText: String {
        if isOnTarget { return "On target" }
        let away = "\(AimFormat.spoken(separation)) away"
        if isNearZenith { return "Near the zenith, follow the arrow, \(away)" }
        return "\(pan.verb) \(AimFormat.spoken(pan.degrees)), \(tilt.verb.lowercased()) \(AimFormat.spoken(tilt.degrees)), \(away)"
    }
}

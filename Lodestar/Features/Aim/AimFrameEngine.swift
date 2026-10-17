import Foundation
import LodestarKit

/// One moment of aiming: where the camera points and how to reach the target from there.
struct AimFrame {
    let sample: MotionSample
    /// The DSLR's pointing: the phone's attitude with the mount and the alignment applied.
    let pointing: PointingSolution
    /// How to reach the target; `nil` without a target or before its position is known.
    let guidance: Guidance?
    /// The target's apparent position as of the last sky rebuild.
    let target: SkySnapshot.Target?
}

/// Turns the newest motion sample into an `AimFrame`.
///
/// It is cheap, so every consumer asks for the frame it needs when it draws (30 Hz overlay, arrow, HUD text, audio
/// ticks) instead of receiving 60 Hz updates through observable properties. It owns the guidance tracker whose
/// hysteresis keeps the on-target state steady; asking again for the same sample gives the same answer.
@MainActor
final class AimFrameEngine {
    private let motion: MotionService
    private var configuration: AimConfiguration
    private var tracker: GuidanceTracker
    private var targetID: String?
    private var target: SkySnapshot.Target?

    init(motion: MotionService, configuration: AimConfiguration) {
        self.motion = motion
        self.configuration = configuration
        tracker = GuidanceTracker(onTargetThreshold: configuration.onTargetThreshold)
    }

    func configure(_ configuration: AimConfiguration) {
        if configuration.onTargetThreshold != tracker.onTargetThreshold {
            tracker = GuidanceTracker(onTargetThreshold: configuration.onTargetThreshold)
        }
        self.configuration = configuration
    }

    /// Chooses the object guidance leads to. Its position follows with `update(target:)`; until then, and after the
    /// target changes, there is no guidance.
    func setTarget(id: String?) {
        guard id != targetID else { return }
        targetID = id
        target = nil
        tracker.reset()
    }

    /// The target's position from a freshly built snapshot; ignored if it belongs to another object.
    func update(target: SkySnapshot.Target?) {
        guard let target, target.object.id == targetID else { return }
        self.target = target
    }

    /// The frame for the newest motion sample, `nil` while the sensors deliver nothing.
    func frame() -> AimFrame? {
        guard let sample = motion.latestSample() else { return nil }
        let pointing = PointingSolution.solve(attitude: sample.attitude, mount: configuration.mount,
                                              alignment: configuration.alignment)
        var guidance: Guidance?
        if let target {
            guidance = tracker.update(solution: pointing, target: target.horizontal)
        }
        return AimFrame(sample: sample, pointing: pointing, guidance: guidance, target: target)
    }
}

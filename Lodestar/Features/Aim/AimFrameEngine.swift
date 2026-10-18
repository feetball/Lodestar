import Foundation
import LodestarKit

/// Where the camera has to point for the panel of a mosaic being shot, as of the last refresh.
struct AimMosaicAim: Equatable, Sendable {
    /// The panel's index in `MosaicPlan.panels`.
    let panelIndex: Int
    /// The panel's centre, refracted: the target of the guidance.
    let horizontal: HorizontalCoordinate
    /// The turn of the camera about its axis that the panel asks for (see `MosaicPanelPointing.roll`).
    let roll: Double
    /// How the camera is held; a camera held in portrait has the long side of the sensor along the panel's "up".
    let orientation: MosaicOrientation
    let isAboveHorizon: Bool
    /// The lowest altitude among the panel's centre and corners.
    let lowestAltitude: Double
}

/// The mosaic part of a frame: the panel and how far the camera is turned from the roll it asks for.
struct AimMosaicFrame {
    let aim: AimMosaicAim
    /// Degrees the camera has to turn clockwise, seen from behind it, to match the panel; negative turns it the other
    /// way.
    let rollDelta: Double
}

/// One moment of aiming: where the camera points and how to reach the target from there.
struct AimFrame {
    let sample: MotionSample
    /// The DSLR's pointing: the phone's attitude with the mount and the alignment applied.
    let pointing: PointingSolution
    /// How to reach the target, or the mosaic panel; `nil` without either or before its position is known.
    let guidance: Guidance?
    /// The target's apparent position as of the last sky rebuild; `nil` while a mosaic is being shot, because the
    /// guidance then leads to its panel instead.
    let target: SkySnapshot.Target?
    /// The panel being aimed at while a mosaic is being shot.
    let mosaic: AimMosaicFrame?
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
    /// Whether a mosaic is being shot (its panel replaces the target) and the panel to aim at, once known.
    private var isMosaicActive = false
    private var mosaicAim: AimMosaicAim?

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

    /// Leads the guidance to a mosaic panel instead of the target. `aim` is the panel's current place, refreshed about
    /// once a second; `active` is `false` when no mosaic runs, and with `true` and no `aim` there is no guidance (the
    /// mosaic is finished). The on-target state starts afresh when the panel changes.
    func setMosaic(active: Bool, aim: AimMosaicAim?) {
        if aim?.panelIndex != mosaicAim?.panelIndex || active != isMosaicActive {
            tracker.reset()
        }
        isMosaicActive = active
        mosaicAim = active ? aim : nil
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
        var mosaic: AimMosaicFrame?
        if isMosaicActive {
            if let aim = mosaicAim {
                guidance = tracker.update(solution: pointing, target: aim.horizontal)
                mosaic = AimMosaicFrame(aim: aim, rollDelta: Self.rollDelta(for: aim, pointing: pointing))
            }
        } else if let target {
            guidance = tracker.update(solution: pointing, target: target.horizontal)
        }
        return AimFrame(sample: sample, pointing: pointing, guidance: guidance, target: isMosaicActive ? nil : target,
                        mosaic: mosaic)
    }

    /// How far the camera has to turn clockwise to take the roll `aim` asks for.
    ///
    /// A camera held in landscape has the top of its picture along `cameraUpVector`. Held in portrait, the long side
    /// of the sensor is the panel's "up", which is the camera's right or left depending on which way it was turned:
    /// the smaller turn of the two is reported.
    static func rollDelta(for aim: AimMosaicAim, pointing: PointingSolution) -> Double {
        let forward = pointing.boresightVector
        func delta(up: Vector3) -> Double {
            AstroMath.normalizeSignedDegrees(aim.roll - MosaicGuidance.roll(forward: forward, up: up))
        }
        switch aim.orientation {
        case .landscape:
            return delta(up: pointing.cameraUpVector)
        case .portrait:
            let right = delta(up: pointing.cameraRightVector)
            let left = delta(up: pointing.cameraRightVector * -1)
            return abs(right) <= abs(left) ? right : left
        }
    }
}

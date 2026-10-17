import Foundation

/// How close the camera is to the target.
public enum GuidanceState: String, Codable, Hashable, Sendable {
    /// Within the on-target threshold (with hysteresis).
    case onTarget
    /// Not on target, but within a few frame widths.
    case close
    /// Further away.
    case far
}

/// What the photographer has to do to bring a target to the centre of the frame.
public struct Guidance: Hashable, Sendable {
    /// Beyond this absolute altitude (degrees) of the boresight or the target, azimuth is a poor
    /// guide: use `arrowAngle` and `separation` only.
    public static let nearZenithAltitude = 85.0

    /// Great-circle angle between the boresight and the target in degrees, [0, 180].
    public let separation: Double
    /// Change of azimuth that centres the target, degrees in (−180, 180]; positive means pan right
    /// (clockwise as seen from above). Unreliable when `isNearZenith`.
    public let panDelta: Double
    /// Change of altitude that centres the target in degrees; positive means tilt up.
    public let tiltDelta: Double
    /// Direction of the shortest way to the target, drawn on the phone's screen: radians
    /// counter-clockwise from "screen right" (device +x, the right edge of the portrait phone), so 0
    /// is right and π/2 is up (device +y, the top edge). The angle is in the phone's own screen axes,
    /// whichever way the phone is turned in the clamp: rotate it by the interface orientation if the
    /// UI is not drawn in portrait. Meaningless when `separation` is (nearly) zero.
    public let arrowAngle: Double
    /// `true` when the target is less than 90° from the boresight.
    public let isTargetInFront: Bool
    /// `true` when the boresight or the target is within 5° of the zenith or nadir.
    public let isNearZenith: Bool
    /// `true` when the target's apparent altitude is negative.
    public let targetBelowHorizon: Bool
    /// On target / close / far, with hysteresis supplied by `GuidanceTracker`.
    public let state: GuidanceState

    fileprivate init(solution: PointingSolution, target: HorizontalCoordinate, state: GuidanceState) {
        let boresight = solution.boresightVector
        let direction = target.unitVector
        separation = boresight.angle(to: direction)
        panDelta = AstroMath.normalizeSignedDegrees(target.azimuth - solution.boresight.azimuth)
        tiltDelta = target.altitude - solution.boresight.altitude
        arrowAngle = Self.arrowAngle(solution: solution, direction: direction)
        isTargetInFront = boresight.dot(direction) > 0
        isNearZenith = max(abs(solution.boresight.altitude), abs(target.altitude)) > Self.nearZenithAltitude
        targetBelowHorizon = target.altitude < 0
        self.state = state
    }

    /// Angle of the great-circle tangent at the boresight, measured on the screen axes. A target
    /// exactly behind the camera has no unique direction; screen-right is reported.
    private static func arrowAngle(solution: PointingSolution, direction: Vector3) -> Double {
        let boresight = solution.boresightVector
        let tangent = direction - boresight * boresight.dot(direction)
        guard tangent.length > 1e-12 else { return 0 }
        return atan2(tangent.dot(solution.screenUpVector), tangent.dot(solution.screenRightVector))
    }
}

/// Produces `Guidance` and remembers whether the camera is on target, so the on-target state does
/// not flicker at the edge of the threshold: it is entered below `onTargetThreshold` and left
/// only beyond 1.5 times that. Call `reset()` when the target changes.
public struct GuidanceTracker: Hashable, Sendable {
    /// Ratio between the leaving and entering separations.
    public static let hysteresisFactor = 1.5
    private static let minimumThreshold = 0.5

    /// Separation in degrees below which the camera counts as on target.
    public let onTargetThreshold: Double
    /// Separation in degrees below which the camera counts as close.
    public let closeThreshold: Double
    private var isOnTarget = false

    /// Creates a tracker. Non-positive or non-finite thresholds fall back to 0.5°; the close
    /// threshold defaults to three times the on-target threshold, at least 5°.
    public init(onTargetThreshold: Double, closeThreshold: Double? = nil) {
        let enter = onTargetThreshold.isFinite && onTargetThreshold > 0 ? onTargetThreshold : Self.minimumThreshold
        self.onTargetThreshold = enter
        if let close = closeThreshold, close.isFinite {
            self.closeThreshold = max(close, enter)
        } else {
            self.closeThreshold = max(3 * enter, 5)
        }
    }

    /// The suggested on-target threshold for a camera frame: a quarter of the frame's short side,
    /// at least 0.5°. Invalid field-of-view values count as zero.
    public static func defaultOnTargetThreshold(horizontalFieldOfView: Double, verticalFieldOfView: Double) -> Double {
        let horizontal = horizontalFieldOfView.isFinite ? max(horizontalFieldOfView, 0) : 0
        let vertical = verticalFieldOfView.isFinite ? max(verticalFieldOfView, 0) : 0
        return max(minimumThreshold, 0.25 * min(horizontal, vertical))
    }

    /// Guidance from the current pointing to `target` (its apparent, refracted horizontal position);
    /// `nil` when the target is not a finite direction.
    public mutating func update(solution: PointingSolution, target: HorizontalCoordinate) -> Guidance? {
        guard target.azimuth.isFinite, target.altitude.isFinite else { return nil }
        let separation = solution.boresightVector.angle(to: target.unitVector)
        if isOnTarget {
            if separation > onTargetThreshold * Self.hysteresisFactor { isOnTarget = false }
        } else if separation < onTargetThreshold {
            isOnTarget = true
        }
        let state: GuidanceState = isOnTarget ? .onTarget : (separation < closeThreshold ? .close : .far)
        return Guidance(solution: solution, target: target, state: state)
    }

    /// Forgets the on-target state, e.g. when the user picks another target.
    public mutating func reset() {
        isOnTarget = false
    }
}

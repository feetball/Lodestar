import Foundation

/// Where the camera is pointing and how it is oriented, in the world (ENU) frame.
public struct PointingSolution: Hashable, Sendable {
    /// Within this many degrees of the zenith or nadir the horizon has no direction, so `roll` is 0.
    private static let rollUndefinedWithin = 1e-4

    /// The direction the camera's optical axis points, as azimuth and altitude.
    public let boresight: HorizontalCoordinate
    /// The optical axis as an ENU unit vector.
    public let boresightVector: Vector3
    /// The camera's "up" (towards the top of the picture) as an ENU unit vector.
    public let cameraUpVector: Vector3
    /// The camera's right (towards the right of the picture) as an ENU unit vector.
    public let cameraRightVector: Vector3
    /// Rotation of the camera about its optical axis in degrees: 0 when the camera's horizontal
    /// axis is level, positive when the camera is turned clockwise as seen by the photographer
    /// (its right side lower), in (−180, 180]. Undefined, reported as 0, within 0.0001° of the
    /// zenith or nadir; it changes quickly just beyond that.
    public let roll: Double
    /// The world direction that the phone's screen draws as "right" (a unit vector perpendicular to
    /// the boresight).
    public let screenRightVector: Vector3
    /// The world direction that the phone's screen draws as "up" (a unit vector perpendicular to the
    /// boresight).
    public let screenUpVector: Vector3

    /// Combines the phone attitude, the mount and the alignment into the camera's pointing.
    ///
    /// The alignment is applied only if it was solved for this mount (`isApplicable(to:)`);
    /// otherwise the nominal mount geometry is used.
    public static func solve(attitude: DeviceAttitude, mount: MountProfile,
                             alignment: AlignmentModel = .identity) -> PointingSolution {
        let applied = alignment.isApplicable(to: mount) ? alignment : .identity
        let correction = applied.deviceCorrectionMatrix
        let axis = correction * mount.cameraAxis
        let up = correction * mount.cameraUp
        let right = axis.cross(up)
        let deviceToWorld = attitude.withHeadingOffset(applied.headingOffset).deviceToWorld

        let forwardWorld = (deviceToWorld * axis).normalized
        let upWorld = (deviceToWorld * up).normalized
        let rightWorld = (deviceToWorld * right).normalized
        return PointingSolution(
            boresight: HorizontalCoordinate(vector: forwardWorld),
            boresightVector: forwardWorld,
            cameraUpVector: upWorld,
            cameraRightVector: rightWorld,
            roll: roll(forward: forwardWorld, up: upWorld),
            screenRightVector: rightWorld * mount.screenRight.x + upWorld * mount.screenUp.x,
            screenUpVector: rightWorld * mount.screenRight.y + upWorld * mount.screenUp.y)
    }

    /// Angle of the camera's up vector from the level orientation, positive towards the right.
    private static func roll(forward: Vector3, up: Vector3) -> Double {
        let levelRight = forward.cross(PointingMath.worldUp)
        let length = levelRight.length
        guard length > AstroMath.sinDeg(Self.rollUndefinedWithin) else { return 0 }
        let right = levelRight / length
        let levelUp = right.cross(forward)
        return AstroMath.atan2Deg(up.dot(right), up.dot(levelUp))
    }
}

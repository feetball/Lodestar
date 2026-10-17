import Foundation

/// Conversions between CoreMotion reference frames.
public enum ReferenceFrames {
    /// Largest disagreement about the vertical, in degrees, between the two attitudes that is still
    /// accepted as "the same physical orientation".
    private static let maximumTiltMismatch = 10.0

    /// The true azimuth ψ of an `.xArbitraryZVertical` reference frame, found from two attitudes of
    /// the same physical orientation: one in the arbitrary frame and one in a frame of known
    /// heading (true north by default). This lets the app switch from compass-referenced attitude
    /// to gyro-only attitude (immune to magnetic disturbances) without losing the heading.
    ///
    /// Both frames describe one device orientation, so `M₁ · T(ψ₁) = M₂ · T(ψ₂)`; the yaw is read
    /// from `K = M₂ᵀ · M₁ · T(ψ₁) = T(ψ₂)` by averaging its two redundant sine and cosine entries,
    /// which tolerates small inconsistencies between the samples.
    ///
    /// - Parameters:
    ///   - arbitrary: the `CMRotationMatrix` in the arbitrary frame.
    ///   - known: the matrix recorded at the same orientation in the frame of known heading.
    ///   - knownFrameAzimuth: true azimuth of the known frame's x axis (0° for true north, the
    ///     declination for magnetic north).
    /// - Returns: ψ in degrees, (−180, 180]; `nil` when an input is not finite or the two matrices
    ///   disagree about the vertical by more than 10° (they were not taken at the same orientation).
    public static func referenceAzimuth(ofArbitraryFrameAttitude arbitrary: Matrix3,
                                        knownFrameAttitude known: Matrix3,
                                        knownFrameAzimuth: Double = 0) -> Double? {
        guard arbitrary.isFinite, known.isFinite, knownFrameAzimuth.isFinite else { return nil }
        let k = arbitrary.transposed * known * DeviceAttitude.referenceTransform(azimuth: knownFrameAzimuth)
        guard k[2, 2] >= AstroMath.cosDeg(maximumTiltMismatch) else { return nil }
        let sine = (k[0, 0] + k[1, 1]) / 2
        let cosine = (k[0, 1] - k[1, 0]) / 2
        return AstroMath.normalizeSignedDegrees(AstroMath.atan2Deg(sine, cosine))
    }
}

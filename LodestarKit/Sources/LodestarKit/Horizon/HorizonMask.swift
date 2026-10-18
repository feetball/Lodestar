import Foundation

/// A precomputed table for asking, many thousand times per frame, whether a direction in the sky is hidden
/// below the skyline.
///
/// Build one mask when the profile or the view changes (1441 table entries, about 0.05 ms) and keep it.
/// `isBelow` then costs an `atan2` and a square root and allocates nothing, so a sky view can test every star
/// it draws. The comparison is made against the profile's own altitudes, which are
/// **apparent** (as the eye sees the obstacle): test directions that are drawn with refraction applied. For a
/// geometric direction near the horizon the answer can differ by up to the refraction, about 0.5°.
public struct HorizonMask: Sendable {
    /// Table resolution: a quarter of a degree, finer than the skyline's own 1° nodes.
    private static let entriesPerDegree = 4

    /// The skyline the mask was built from.
    public let profile: HorizonProfile

    /// Sine of the skyline altitude at every `entriesPerDegree`-th of a degree; the last entry repeats the first.
    private let sines: [Double]

    /// `true` when every direction above the horizon is above the skyline (a flat profile hides nothing above it).
    private let isFlat: Bool

    /// Builds the mask for `profile`.
    public init(profile: HorizonProfile) {
        self.profile = profile
        sines = (0...(HorizonProfile.binCount * Self.entriesPerDegree)).map { index in
            AstroMath.sinDeg(profile.altitude(at: Double(index) / Double(Self.entriesPerDegree)))
        }
        isFlat = profile.isFlat
    }

    /// Whether the direction with East–North–Up components (`x`, `y`, `z`) — any length — is below the
    /// skyline, i.e. its altitude is lower than the skyline's at its azimuth. A direction exactly on the skyline is
    /// not below it; one that is not finite or has no length is not below it either.
    public func isBelow(x: Double, y: Double, z: Double) -> Bool {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length > 0, length.isFinite else { return false }
        if isFlat { return z < 0 }
        let horizontal = x * x + y * y
        if horizontal == 0 { return z < 0 }
        let azimuth = AstroMath.normalizeDegrees(AstroMath.atan2Deg(x, y))
        let position = azimuth * Double(Self.entriesPerDegree)
        let lower = Int(position)
        let fraction = position - Double(lower)
        let skyline = sines[lower] + (sines[lower + 1] - sines[lower]) * fraction
        return z < skyline * length
    }

    /// Whether the East–North–Up `direction` (any length) is below the skyline; see `isBelow(x:y:z:)`.
    public func isBelow(_ direction: Vector3) -> Bool {
        isBelow(x: direction.x, y: direction.y, z: direction.z)
    }

    /// Whether the direction at `azimuth` and `altitude` (degrees) is below the skyline.
    public func isBelow(azimuth: Double, altitude: Double) -> Bool {
        guard azimuth.isFinite, altitude.isFinite else { return false }
        return altitude < profile.altitude(at: azimuth)
    }
}

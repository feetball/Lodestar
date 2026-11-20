import Foundation

/// How a lens maps the angle `θ` of a ray from the optical axis to the distance `r` of its image from the centre
/// of the frame, for a lens of focal length `f`.
///
/// `rectilinear` lenses keep straight lines straight; fisheye lenses trade that for a much wider view and come in
/// the three classic mappings. The inverse mapping, `angleDegrees(imageRadiusMillimeters:focalLength:)`, is what the
/// field-of-view numbers and the frame outline are built on.
public enum LensProjection: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// `r = f · tan θ`: straight lines stay straight. Every ordinary lens; the angle across a frame stays below 180°.
    case rectilinear
    /// `r = f · θ`: equal angles take equal distances on the sensor (θ in radians).
    case fisheyeEquidistant
    /// `r = 2f · sin(θ / 2)`: equal solid angles take equal areas on the sensor; the common circular and diagonal fisheye.
    case fisheyeEquisolid
    /// `r = 2f · tan(θ / 2)`: keeps small shapes round, so the edges are stretched.
    case fisheyeStereographic

    /// A stable identifier, equal to the raw value.
    public var id: String { rawValue }

    /// A short name for pickers, for example "Fisheye (equisolid)".
    public var displayName: String {
        switch self {
        case .rectilinear: return "Rectilinear"
        case .fisheyeEquidistant: return "Fisheye (equidistant)"
        case .fisheyeEquisolid: return "Fisheye (equisolid)"
        case .fisheyeStereographic: return "Fisheye (stereographic)"
        }
    }

    /// Whether this is one of the fisheye mappings.
    public var isFisheye: Bool { self != .rectilinear }

    /// The angle of a ray from the optical axis, in degrees from 0 to 180, that lands `imageRadiusMillimeters` from
    /// the centre of the frame behind a lens of `focalLength` millimetres. This is the inverse of the mapping.
    ///
    /// An image distance beyond what the mapping can reach (more than `2f` for the equisolid mapping, or
    /// `π · f` for the equidistant one) gives 180°. The caller guarantees a finite, non-negative radius and a
    /// positive, finite focal length.
    public func angleDegrees(imageRadiusMillimeters: Double, focalLength: Double) -> Double {
        min(180, angleRadians(imageRadiusMillimeters: imageRadiusMillimeters, focalLength: focalLength) * 180 / .pi)
    }

    /// The forward mapping: the distance in millimetres from the centre of the frame at which a ray `angleDegrees` from
    /// the optical axis lands, or nil when the lens cannot image that angle (a rectilinear lens at 90° or more, a
    /// stereographic one at 180°) or an argument is not a finite number in range.
    public func imageRadiusMillimeters(angleDegrees: Double, focalLength: Double) -> Double? {
        guard angleDegrees.isFinite, angleDegrees >= 0, angleDegrees <= 180,
              focalLength.isFinite, focalLength > 0 else { return nil }
        let theta = angleDegrees * .pi / 180
        switch self {
        case .rectilinear: return angleDegrees < 90 ? focalLength * tan(theta) : nil
        case .fisheyeEquidistant: return focalLength * theta
        case .fisheyeEquisolid: return 2 * focalLength * sin(theta / 2)
        case .fisheyeStereographic: return angleDegrees < 180 ? 2 * focalLength * tan(theta / 2) : nil
        }
    }

    /// `angleDegrees(imageRadiusMillimeters:focalLength:)` in radians, from 0 to π, for the frame outline.
    func angleRadians(imageRadiusMillimeters: Double, focalLength: Double) -> Double {
        let ratio = imageRadiusMillimeters / focalLength
        let radians: Double
        switch self {
        case .rectilinear: radians = atan(ratio)
        case .fisheyeEquidistant: radians = ratio
        case .fisheyeEquisolid: radians = 2 * asin(min(1, ratio / 2))
        case .fisheyeStereographic: radians = 2 * atan(ratio / 2)
        }
        return min(.pi, radians)
    }
}

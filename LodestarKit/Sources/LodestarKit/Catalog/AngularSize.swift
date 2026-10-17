import Foundation

/// The apparent size of an extended object on the sky.
///
/// Sizes are the major and minor axes of the object's outline in arcminutes. Round objects (and
/// objects whose catalog entry lacks a minor axis) have no `minorArcminutes`.
public struct AngularSize: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Largest size an object can have: the whole sky, in arcminutes.
    public static let maximumArcminutes = 360.0 * 60

    /// Length of the major axis in arcminutes, greater than 0.
    public let majorArcminutes: Double
    /// Length of the minor axis in arcminutes, greater than 0 and at most `majorArcminutes`.
    public let minorArcminutes: Double?
    /// Position angle of the major axis in degrees, [0, 180): measured from north through east.
    public let positionAngle: Double?

    /// Creates a size, or returns `nil` when `majorArcminutes` is not a finite value in
    /// (0, `maximumArcminutes`].
    ///
    /// A minor axis that is not finite, not positive or longer than the major axis is dropped. The
    /// position angle is reduced modulo 180° (an axis has no direction), and dropped if not finite.
    public init?(majorArcminutes: Double, minorArcminutes: Double? = nil, positionAngle: Double? = nil) {
        guard majorArcminutes.isFinite, majorArcminutes > 0, majorArcminutes <= Self.maximumArcminutes else {
            return nil
        }
        self.majorArcminutes = majorArcminutes
        if let minor = minorArcminutes, minor.isFinite, minor > 0, minor <= majorArcminutes {
            self.minorArcminutes = minor
        } else {
            self.minorArcminutes = nil
        }
        if let angle = positionAngle, angle.isFinite {
            var reduced = angle.truncatingRemainder(dividingBy: 180)
            if reduced < 0 { reduced += 180 }
            self.positionAngle = reduced >= 180 ? 0 : reduced
        } else {
            self.positionAngle = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case majorArcminutes, minorArcminutes, positionAngle
    }

    /// Decodes a size, applying the same rules as `init?(majorArcminutes:minorArcminutes:positionAngle:)`.
    ///
    /// - Throws: `DecodingError` when the major axis is missing or not a finite, positive size.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let major = try container.decode(Double.self, forKey: .majorArcminutes)
        let minor = try container.decodeIfPresent(Double.self, forKey: .minorArcminutes)
        let angle = try container.decodeIfPresent(Double.self, forKey: .positionAngle)
        guard let size = AngularSize(majorArcminutes: major, minorArcminutes: minor, positionAngle: angle) else {
            throw DecodingError.dataCorruptedError(forKey: .majorArcminutes, in: container,
                                                   debugDescription: "The major axis must be a finite, positive size.")
        }
        self = size
    }

    /// Encodes the major axis, and the minor axis and position angle when present.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(majorArcminutes, forKey: .majorArcminutes)
        try container.encodeIfPresent(minorArcminutes, forKey: .minorArcminutes)
        try container.encodeIfPresent(positionAngle, forKey: .positionAngle)
    }

    /// The size for display, for example "178′ × 70′", "8.4′" or "36″".
    ///
    /// Sizes are rounded to whole arcminutes from 10′ up and to a tenth below that. Sizes below one
    /// arcminute (that do not round up to 60″) are given in arcseconds. Both axes use the unit of the
    /// major axis, and a minor axis that prints like the major one is left out.
    public var description: String {
        let inArcseconds = (majorArcminutes * 60).rounded() < 60
        let major = Self.format(majorArcminutes, inArcseconds: inArcseconds)
        guard let minorArcminutes else { return major }
        let minor = Self.format(minorArcminutes, inArcseconds: inArcseconds)
        return minor == major ? major : "\(major) × \(minor)"
    }

    private static func format(_ arcminutes: Double, inArcseconds: Bool) -> String {
        if inArcseconds {
            let seconds = arcminutes * 60
            return (seconds < 10 ? CatalogFormat.trimmedOneDecimal(seconds) : String(Int(seconds.rounded()))) + "″"
        }
        let text = arcminutes < 10 ? CatalogFormat.trimmedOneDecimal(arcminutes) : String(Int(arcminutes.rounded()))
        return text + "′"
    }
}

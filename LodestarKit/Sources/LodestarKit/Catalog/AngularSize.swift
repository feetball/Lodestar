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

    /// The size for display in degrees, arcminutes and arcseconds, for example "2° 58′ × 1° 10′",
    /// "8′ 24″" or "36″".
    ///
    /// Each axis is written in its two largest units: degrees and whole arcminutes from 1° up,
    /// arcminutes and whole arcseconds from 1′ up, and arcseconds below that (to a tenth under 10″).
    /// A trailing unit that is zero is left out ("2°", "25′"), and a smaller unit that follows a
    /// larger one has two digits ("1° 05′", "8′ 04″"), like the declination on the Now card. Rounding
    /// happens once, at the smallest unit shown, so 59′ 59.6″ is "1°". The axes choose their units
    /// separately, and a minor axis that prints like the major one is left out.
    public var description: String {
        let major = Self.format(majorArcminutes)
        guard let minorArcminutes else { return major }
        let minor = Self.format(minorArcminutes)
        return minor == major ? major : "\(major) × \(minor)"
    }

    private static func format(_ arcminutes: Double) -> String {
        if arcminutes >= 60 {
            let total = Int(arcminutes.rounded())
            return units(total / 60, "°", total % 60, "′")
        }
        let arcseconds = arcminutes * 60
        if arcseconds < 10 {
            return CatalogFormat.trimmedOneDecimal(arcseconds) + "″"
        }
        let total = Int(arcseconds.rounded())
        if total >= 3600 { return "1°" }
        return total >= 60 ? units(total / 60, "′", total % 60, "″") : "\(total)″"
    }

    /// A larger unit and the smaller one that follows it ("2° 58′"), or only the larger when the
    /// smaller is zero.
    private static func units(_ larger: Int, _ largerMark: String, _ smaller: Int, _ smallerMark: String) -> String {
        guard smaller > 0 else { return "\(larger)\(largerMark)" }
        return "\(larger)\(largerMark) \(smaller < 10 ? "0" : "")\(smaller)\(smallerMark)"
    }
}

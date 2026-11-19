import Foundation

/// What a part of the imaging score looks at.
public enum ImagingScoreComponentKind: String, CaseIterable, Sendable, Hashable {
    /// The hours of astronomical darkness.
    case darknessHours
    /// How much of that darkness the Moon spoils.
    case moon
    /// The brightness of the sky at the site (Bortle class).
    case skyBrightness
    /// The forecast cloud cover; only when a forecast is known.
    case clouds
}

/// A word for an imaging score.
public enum ImagingRating: String, CaseIterable, Sendable, Hashable {
    /// Below 3.
    case poor
    /// 3 to below 5.5.
    case fair
    /// 5.5 to below 8.
    case good
    /// 8 or more.
    case excellent

    /// The rating of a score from 0 to 10.
    public init(score: Double) {
        if score >= 8 {
            self = .excellent
        } else if score >= 5.5 {
            self = .good
        } else if score >= 3 {
            self = .fair
        } else {
            self = .poor
        }
    }
}

/// One part of an `ImagingScore`.
public struct ImagingScoreComponent: Sendable, Hashable {
    /// What the part looks at.
    public let kind: ImagingScoreComponentKind
    /// How good that is, 0 (useless) to 1 (ideal).
    public let quality: Double
    /// The points this part can give at most; the weights of the parts add up to 10.
    public let weight: Double
    /// What it gave: `weight * quality`. The points of the parts add up to the score.
    public let points: Double

    init(kind: ImagingScoreComponentKind, quality: Double, weight: Double, points: Double) {
        self.kind = kind
        self.quality = quality
        self.weight = weight
        self.points = points
    }
}

/// The score of a night for deep-sky imaging at one site, 0 to 10, with the parts it is made of.
public struct ImagingScore: Sendable, Hashable {
    /// The score, 0 (nothing to shoot) to 10 (new moon, a Bortle 1 sky, long dark hours, clear).
    public let total: Double
    /// The parts, in this order: darkness hours, Moon, sky brightness, and clouds when a forecast is known. Their
    /// `points` add up to `total`.
    public let components: [ImagingScoreComponent]

    init(total: Double, components: [ImagingScoreComponent]) {
        self.total = total
        self.components = components
    }

    /// `true` when the score includes the cloud forecast.
    public var includesClouds: Bool { components.contains { $0.kind == .clouds } }

    /// A word for `total`.
    public var rating: ImagingRating { ImagingRating(score: total) }

    /// The part of the given kind, or `nil` when it is not in the score.
    public func component(_ kind: ImagingScoreComponentKind) -> ImagingScoreComponent? {
        components.first { $0.kind == kind }
    }
}

/// The imaging score of a night: how good it is for photographing faint objects, from the dark hours, the Moon, the
/// sky brightness of the site and, when known, the clouds.
///
/// **Parts and weights** (points out of 10, each part gives `weight * quality`):
///
/// | Part | Weight | Quality (0 to 1) |
/// |---|---|---|
/// | Darkness hours | 2 | hours of astronomical darkness / 6, at most 1 (six hours is a good night's work); 0 with no astronomical darkness |
/// | Moon | 3 | 1 - (share of the darkness with the Moon up) x (illuminated fraction of the Moon); 0 with no astronomical darkness |
/// | Sky brightness | 2 | (9 - Bortle class) / 8: class 1 gives 1, class 9 gives 0 |
/// | Clouds | 3 | 1 - cloud fraction; left out when no forecast is known |
///
/// Without a cloud forecast the three other weights are scaled up to 10 (2.86, 4.29, 2.86) so that the total still runs
/// from 0 to 10 and the points of the parts still add up to it. The share of the darkness with the Moon up is
/// `(astronomicalDarkHours - moonFreeDarkHours) / astronomicalDarkHours`. A thin crescent that is up all night costs
/// little; a full Moon that is up for an hour of a long night costs little too. Cost: a few arithmetic operations.
public enum SkyQualityScore {
    /// The hours of astronomical darkness that earn the full darkness quality.
    public static let fullDarknessHours = 6.0

    private static let darknessWeight = 2.0
    private static let moonWeight = 3.0
    private static let skyWeight = 2.0
    private static let cloudWeight = 3.0

    /// The imaging score of the night `night` at a site of sky quality `bortle`.
    ///
    /// - Parameter cloudFraction: The forecast cloud cover of the night, 0 (clear) to 1 (overcast), or `nil` when no
    ///   fresh forecast is known. A value outside 0-1 is limited to it; one that is not a number counts as unknown.
    public static func imaging(night: NightSummary, bortle: BortleEstimate, cloudFraction: Double?) -> ImagingScore {
        imaging(astronomicalDarkHours: night.astronomicalDarkHours, moonFreeDarkHours: night.moonFreeDarkHours,
                moonIlluminatedFraction: night.moon.illuminatedFraction, bortle: bortle, cloudFraction: cloudFraction)
    }

    /// The imaging score from its inputs: `astronomicalDarkHours` and `moonFreeDarkHours` as in `NightSummary` (the
    /// second is at most the first), the Moon's `moonIlluminatedFraction` (0 to 1), the site's `bortle` and the
    /// forecast `cloudFraction` or `nil`. Hours and fractions that are negative or not numbers count as 0.
    public static func imaging(astronomicalDarkHours: Double, moonFreeDarkHours: Double,
                               moonIlluminatedFraction: Double, bortle: BortleEstimate,
                               cloudFraction: Double?) -> ImagingScore {
        let dark = nonNegative(astronomicalDarkHours)
        let moonFree = AstroMath.clamp(nonNegative(moonFreeDarkHours), 0, dark)
        let lit = AstroMath.clamp(nonNegative(moonIlluminatedFraction), 0, 1)
        let darknessQuality = AstroMath.clamp(dark / fullDarknessHours, 0, 1)
        let moonQuality = dark > 0 ? 1 - (dark - moonFree) / dark * lit : 0
        let skyQuality = (9 - Double(AstroMath.clamp(bortle.bortleClass, 1, 9))) / 8
        var clouds: Double?
        if let fraction = cloudFraction, fraction.isFinite { clouds = AstroMath.clamp(fraction, 0, 1) }

        var parts: [(kind: ImagingScoreComponentKind, weight: Double, quality: Double)] = [
            (.darknessHours, darknessWeight, darknessQuality),
            (.moon, moonWeight, moonQuality),
            (.skyBrightness, skyWeight, skyQuality),
        ]
        if let clouds { parts.append((.clouds, cloudWeight, 1 - clouds)) }
        let weightSum = parts.reduce(0) { $0 + $1.weight }
        let components = parts.map { part -> ImagingScoreComponent in
            let scaled = part.weight * 10 / weightSum
            return ImagingScoreComponent(kind: part.kind, quality: part.quality, weight: scaled,
                                         points: scaled * part.quality)
        }
        return ImagingScore(total: components.reduce(0) { $0 + $1.points }, components: components)
    }

    private static func nonNegative(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}

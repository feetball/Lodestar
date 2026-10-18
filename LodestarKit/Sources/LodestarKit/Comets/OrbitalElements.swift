import Foundation

/// The kind of a small solar-system body.
public enum SmallBodyKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// A comet (including the interstellar ones).
    case comet
    /// An asteroid (minor planet).
    case asteroid

    /// The English name, e.g. "Comet".
    public var displayName: String {
        switch self {
        case .comet: "Comet"
        case .asteroid: "Asteroid"
        }
    }
}

/// The shape of a heliocentric two-body orbit, from its eccentricity.
public enum OrbitShape: String, CaseIterable, Codable, Hashable, Sendable {
    /// `e < 1`: a closed orbit that repeats.
    case elliptic
    /// `e == 1` exactly.
    case parabolic
    /// `e > 1`: the body passes the Sun once and leaves the solar system.
    case hyperbolic
}

/// Osculating heliocentric orbital elements referred to the mean ecliptic and equinox of J2000.0, the frame of the
/// Minor Planet Center and of the JPL Small-Body Database.
///
/// The orbit is described the way comets are: by the perihelion distance `q` and the time of perihelion passage, which
/// works for every eccentricity. Asteroid elements (semi-major axis, mean anomaly at an epoch) are converted by
/// `fromMeanAnomaly`. Times are Julian Days in Terrestrial Time (TT; the difference to the TDB of JPL is below 2 ms).
///
/// Instances come from the failable initializer or `fromMeanAnomaly`, which return `nil` for values out of range.
public struct OrbitalElements: Hashable, Sendable {
    /// Perihelion distance q in AU, 0.00001 to 1000.
    public let perihelionDistanceAU: Double
    /// Eccentricity e, 0 to 100 (`< 1` elliptic, `== 1` parabolic, `> 1` hyperbolic).
    public let eccentricity: Double
    /// Inclination i to the ecliptic in degrees, [0, 180].
    public let inclination: Double
    /// Argument of perihelion ω in degrees, [0, 360).
    public let argumentOfPerihelion: Double
    /// Longitude of the ascending node Ω in degrees, [0, 360).
    public let longitudeOfAscendingNode: Double
    /// Julian Day (TT) of a perihelion passage.
    public let perihelionJulianDayTT: Double
    /// Julian Day (TT) at which the elements are osculating; informational (it tells how far the two-body motion is
    /// extrapolated), the position never depends on it.
    public let epochJulianDayTT: Double

    /// The smallest accepted perihelion distance, 0.00001 AU.
    public static let minimumPerihelionDistanceAU = 0.00001
    /// The largest accepted perihelion distance, 1000 AU.
    public static let maximumPerihelionDistanceAU = 1000.0
    /// The largest accepted eccentricity, 100.
    public static let maximumEccentricity = 100.0
    /// The earliest accepted Julian Day, 0 (4713 BC).
    public static let minimumJulianDay = 0.0
    /// The latest accepted Julian Day, 6 000 000 (about the year 11700).
    public static let maximumJulianDay = 6_000_000.0

    /// Creates elements from the comet-style description, or returns `nil` if a value is not finite or out of range
    /// (see the property documentation). Angles beyond [0, 360) are reduced.
    ///
    /// - Parameter epochJulianDayTT: The osculating epoch; defaults to the perihelion time.
    public init?(perihelionDistanceAU: Double, eccentricity: Double, inclination: Double, argumentOfPerihelion: Double,
                 longitudeOfAscendingNode: Double, perihelionJulianDayTT: Double, epochJulianDayTT: Double? = nil) {
        let epoch = epochJulianDayTT ?? perihelionJulianDayTT
        guard perihelionDistanceAU >= Self.minimumPerihelionDistanceAU,
              perihelionDistanceAU <= Self.maximumPerihelionDistanceAU else { return nil }
        guard eccentricity >= 0, eccentricity <= Self.maximumEccentricity else { return nil }
        guard inclination >= 0, inclination <= 180 else { return nil }
        guard argumentOfPerihelion.isFinite, longitudeOfAscendingNode.isFinite else { return nil }
        guard perihelionJulianDayTT >= Self.minimumJulianDay, perihelionJulianDayTT <= Self.maximumJulianDay else { return nil }
        guard epoch >= Self.minimumJulianDay, epoch <= Self.maximumJulianDay else { return nil }
        self.perihelionDistanceAU = perihelionDistanceAU
        self.eccentricity = eccentricity
        self.inclination = inclination
        self.argumentOfPerihelion = AstroMath.normalizeDegrees(argumentOfPerihelion)
        self.longitudeOfAscendingNode = AstroMath.normalizeDegrees(longitudeOfAscendingNode)
        self.perihelionJulianDayTT = perihelionJulianDayTT
        self.epochJulianDayTT = epoch
    }

    /// Creates elliptic elements from the asteroid-style description: semi-major axis and the mean anomaly at an
    /// epoch. The perihelion time is the epoch minus the mean anomaly (reduced to ±180°) divided by the mean motion
    /// `k / a^1.5`. Returns `nil` unless `0 <= e < 1` and the other values are in range.
    ///
    /// - Parameter meanAnomaly: Mean anomaly at `epochJulianDayTT` in degrees (any finite value).
    public static func fromMeanAnomaly(semiMajorAxisAU: Double, eccentricity: Double, inclination: Double,
                                       argumentOfPerihelion: Double, longitudeOfAscendingNode: Double,
                                       meanAnomaly: Double, epochJulianDayTT: Double) -> OrbitalElements? {
        guard eccentricity >= 0, eccentricity < 1 else { return nil }
        guard semiMajorAxisAU > 0, semiMajorAxisAU.isFinite, meanAnomaly.isFinite else { return nil }
        let motion = AstroMath.degrees(OrbitPropagator.gaussianGravitationalConstant / (semiMajorAxisAU * semiMajorAxisAU.squareRoot()))
        let signedAnomaly = AstroMath.normalizeSignedDegrees(meanAnomaly)
        return OrbitalElements(
            perihelionDistanceAU: semiMajorAxisAU * (1 - eccentricity), eccentricity: eccentricity,
            inclination: inclination, argumentOfPerihelion: argumentOfPerihelion,
            longitudeOfAscendingNode: longitudeOfAscendingNode,
            perihelionJulianDayTT: epochJulianDayTT - signedAnomaly / motion, epochJulianDayTT: epochJulianDayTT)
    }

    /// Elliptic, parabolic or hyperbolic.
    public var shape: OrbitShape {
        eccentricity < 1 ? .elliptic : (eccentricity > 1 ? .hyperbolic : .parabolic)
    }

    /// Semi-major axis in AU; `nil` unless the orbit is elliptic.
    public var semiMajorAxisAU: Double? {
        eccentricity < 1 ? perihelionDistanceAU / (1 - eccentricity) : nil
    }

    /// Aphelion distance in AU; `nil` unless the orbit is elliptic.
    public var aphelionDistanceAU: Double? {
        semiMajorAxisAU.map { $0 * (1 + eccentricity) }
    }

    /// Mean motion in degrees per day; `nil` unless the orbit is elliptic.
    public var meanMotion: Double? {
        semiMajorAxisAU.map { AstroMath.degrees(OrbitPropagator.gaussianGravitationalConstant / ($0 * $0.squareRoot())) }
    }

    /// Orbital period in days; `nil` unless the orbit is elliptic.
    public var periodDays: Double? {
        semiMajorAxisAU.map { 2 * Double.pi * $0 * $0.squareRoot() / OrbitPropagator.gaussianGravitationalConstant }
    }

    /// Orbital period in Julian years; `nil` unless the orbit is elliptic.
    public var periodYears: Double? {
        periodDays.map { $0 / 365.25 }
    }

    /// The mean anomaly in degrees, [0, 360), at `julianDayTT`; `nil` unless the orbit is elliptic.
    public func meanAnomaly(at julianDayTT: Double) -> Double? {
        meanMotion.map { AstroMath.normalizeDegrees($0 * (julianDayTT - perihelionJulianDayTT)) }
    }
}

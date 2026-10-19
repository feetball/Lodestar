import Foundation

/// The magnitude parameters of a comet, in the form JPL Horizons and the Small-Body Database use.
///
/// The total magnitude is `m1 = M1 + 5·log10(Δ) + K1·log10(r)` and the nuclear magnitude
/// `m2 = M2 + 5·log10(Δ) + K2·log10(r) + PC·α`, with `r` the Sun distance and `Δ` the Earth distance in AU and `α` the
/// phase angle in degrees. The MPC lists `M1` and a slope `k` with `K1 = 2.5·k` (`fromMPC`).
/// Total magnitudes of comets are rough: the coma makes them uncertain by a magnitude or more.
public struct CometMagnitudes: Hashable, Sendable {
    /// The absolute total magnitude M1 (the magnitude at r = Δ = 1 AU).
    public let totalMagnitude: Double
    /// The coefficient K1 of `log10(r)` in the total magnitude (10 is the classical default).
    public let totalSlope: Double
    /// The absolute nuclear magnitude M2, if known.
    public let nuclearMagnitude: Double?
    /// The coefficient K2 of `log10(r)` in the nuclear magnitude; present exactly when M2 is.
    public let nuclearSlope: Double?
    /// The phase coefficient PC of the nuclear magnitude in magnitudes per degree (0 when unknown).
    public let nuclearPhaseCoefficient: Double

    /// The classical default slope K1 of the total magnitude, 10.
    public static let defaultTotalSlope = 10.0

    /// Creates comet magnitudes, or returns `nil` if a value is not finite or out of range (M1, M2: −20…40;
    /// K1, K2: −5…60; PC: −0.1…0.5). The nuclear parameters are used only if both `nuclearMagnitude` and
    /// `nuclearSlope` are given.
    public init?(totalMagnitude: Double, totalSlope: Double, nuclearMagnitude: Double? = nil, nuclearSlope: Double? = nil,
                 nuclearPhaseCoefficient: Double = 0) {
        guard totalMagnitude >= -20, totalMagnitude <= 40 else { return nil }
        guard totalSlope >= -5, totalSlope <= 60 else { return nil }
        guard nuclearPhaseCoefficient >= -0.1, nuclearPhaseCoefficient <= 0.5 else { return nil }
        self.totalMagnitude = totalMagnitude
        self.totalSlope = totalSlope
        guard let nuclearMagnitude, let nuclearSlope else {
            self.nuclearMagnitude = nil
            self.nuclearSlope = nil
            self.nuclearPhaseCoefficient = 0
            return
        }
        guard nuclearMagnitude >= -20, nuclearMagnitude <= 40 else { return nil }
        guard nuclearSlope >= -5, nuclearSlope <= 60 else { return nil }
        self.nuclearMagnitude = nuclearMagnitude
        self.nuclearSlope = nuclearSlope
        self.nuclearPhaseCoefficient = nuclearPhaseCoefficient
    }

    /// Creates the magnitudes from the two numbers of the MPC comet file: the absolute magnitude and the slope
    /// parameter `k` (the total magnitude is `H + 5·log10(Δ) + 2.5·k·log10(r)`, so `K1 = 2.5·k`).
    public static func fromMPC(absoluteMagnitude: Double, slopeParameter: Double) -> CometMagnitudes? {
        CometMagnitudes(totalMagnitude: absoluteMagnitude, totalSlope: 2.5 * slopeParameter)
    }

    /// The total magnitude at Sun distance `sunDistanceAU` and Earth distance `earthDistanceAU`; `nil` if a distance
    /// is not positive.
    public func total(sunDistanceAU: Double, earthDistanceAU: Double) -> Double? {
        guard sunDistanceAU > 0, earthDistanceAU > 0, sunDistanceAU.isFinite, earthDistanceAU.isFinite else { return nil }
        return totalMagnitude + 5 * log10(earthDistanceAU) + totalSlope * log10(sunDistanceAU)
    }

    /// The nuclear magnitude (the brightness of the bare nucleus, not of the coma); `nil` without nuclear parameters
    /// or for a distance that is not positive.
    public func nuclear(sunDistanceAU: Double, earthDistanceAU: Double, phaseAngle: Double) -> Double? {
        guard let magnitude = nuclearMagnitude, let slope = nuclearSlope else { return nil }
        guard sunDistanceAU > 0, earthDistanceAU > 0, sunDistanceAU.isFinite, earthDistanceAU.isFinite else { return nil }
        return magnitude + 5 * log10(earthDistanceAU) + slope * log10(sunDistanceAU) + nuclearPhaseCoefficient * phaseAngle
    }
}

/// The H, G magnitude system of the IAU (1985; Bowell et al. 1989, *Asteroids II*) for an asteroid:
/// `V = H + 5·log10(r·Δ) − 2.5·log10((1 − G)·Φ1 + G·Φ2)` with `Φi = exp(−Ai·tan(α/2)^Bi)`,
/// `A1 = 3.33, B1 = 0.63, A2 = 1.87, B2 = 1.22`.
public struct AsteroidMagnitudes: Hashable, Sendable {
    /// H, the magnitude at r = Δ = 1 AU and zero phase angle.
    public let absoluteMagnitude: Double
    /// G, the slope parameter (0.15 when unknown).
    public let slopeParameter: Double

    /// The slope parameter assumed when a catalog gives none, 0.15.
    public static let defaultSlopeParameter = 0.15

    /// Creates the parameters, or returns `nil` if H is not in −5…40 or G not in −0.25…1.
    public init?(absoluteMagnitude: Double, slopeParameter: Double = AsteroidMagnitudes.defaultSlopeParameter) {
        guard absoluteMagnitude >= -5, absoluteMagnitude <= 40 else { return nil }
        guard slopeParameter >= -0.25, slopeParameter <= 1 else { return nil }
        self.absoluteMagnitude = absoluteMagnitude
        self.slopeParameter = slopeParameter
    }

    /// The visual magnitude at Sun distance `sunDistanceAU`, Earth distance `earthDistanceAU` and phase angle
    /// `phaseAngle` in degrees; `nil` if a distance is not positive, the phase angle is not in [0, 180) or the phase
    /// function is not positive.
    public func apparent(sunDistanceAU: Double, earthDistanceAU: Double, phaseAngle: Double) -> Double? {
        guard sunDistanceAU > 0, earthDistanceAU > 0, sunDistanceAU.isFinite, earthDistanceAU.isFinite else { return nil }
        guard phaseAngle >= 0, phaseAngle < 180 else { return nil }
        let t = tan(AstroMath.radians(phaseAngle) / 2)
        let phi1 = exp(-3.33 * pow(t, 0.63))
        let phi2 = exp(-1.87 * pow(t, 1.22))
        let flux = (1 - slopeParameter) * phi1 + slopeParameter * phi2
        guard flux > 0 else { return nil }
        return absoluteMagnitude + 5 * log10(sunDistanceAU * earthDistanceAU) - 2.5 * log10(flux)
    }
}

/// The brightness model of a `SmallBody`: the comet law or the asteroid H, G system.
public enum SmallBodyPhotometry: Hashable, Sendable {
    /// The comet total-magnitude law.
    case comet(CometMagnitudes)
    /// The asteroid H, G system.
    case asteroid(AsteroidMagnitudes)

    /// The apparent magnitude, which is the total magnitude for a comet and the visual magnitude for an asteroid; `nil`
    /// if the geometry is outside the range of the model (see `CometMagnitudes.total`, `AsteroidMagnitudes.apparent`).
    public func apparentMagnitude(sunDistanceAU: Double, earthDistanceAU: Double, phaseAngle: Double) -> Double? {
        switch self {
        case .comet(let magnitudes):
            magnitudes.total(sunDistanceAU: sunDistanceAU, earthDistanceAU: earthDistanceAU)
        case .asteroid(let magnitudes):
            magnitudes.apparent(sunDistanceAU: sunDistanceAU, earthDistanceAU: earthDistanceAU, phaseAngle: phaseAngle)
        }
    }

    /// The nuclear magnitude of a comet that has nuclear parameters; `nil` otherwise.
    public func nuclearMagnitude(sunDistanceAU: Double, earthDistanceAU: Double, phaseAngle: Double) -> Double? {
        switch self {
        case .comet(let magnitudes):
            magnitudes.nuclear(sunDistanceAU: sunDistanceAU, earthDistanceAU: earthDistanceAU, phaseAngle: phaseAngle)
        case .asteroid:
            nil
        }
    }
}

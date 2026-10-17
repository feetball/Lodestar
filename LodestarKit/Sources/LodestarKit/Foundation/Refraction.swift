import Foundation

/// Ambient conditions that scale atmospheric refraction.
public struct Atmosphere: Hashable, Codable, Sendable {
    /// Station pressure in millibars (hPa).
    public var pressureMillibars: Double
    /// Air temperature in degrees Celsius.
    public var temperatureCelsius: Double

    public init(pressureMillibars: Double = 1010, temperatureCelsius: Double = 10) {
        self.pressureMillibars = pressureMillibars
        self.temperatureCelsius = temperatureCelsius
    }

    /// 1010 mbar, 10 °C — the conditions the standard refraction formulas assume.
    public static let standard = Atmosphere()

    /// Multiplier applied to standard refraction (Meeus 16.5). Implausible inputs fall back to 1.
    public var refractionScale: Double {
        guard pressureMillibars.isFinite, temperatureCelsius.isFinite,
              (300...1100).contains(pressureMillibars),
              (-60...60).contains(temperatureCelsius) else { return 1 }
        return (pressureMillibars / 1010) * (283 / (273 + temperatureCelsius))
    }
}

/// Atmospheric refraction near the Earth's surface.
///
/// Below −1° true altitude the refraction is faded linearly to zero at −5° so the true→apparent
/// mapping stays continuous and monotonic (the formulas diverge below the horizon and objects
/// there are not visible anyway).
public enum Refraction {
    private static let fadeStart = -1.0
    private static let fadeEnd = -5.0

    /// Refraction in degrees to **add** to a true (geometric) altitude (Sæmundsson 1986, Meeus 16.4).
    public static func refractionForTrueAltitude(_ trueAltitude: Double, atmosphere: Atmosphere = .standard) -> Double {
        guard trueAltitude.isFinite else { return 0 }
        if trueAltitude >= 90 { return 0 }
        if trueAltitude < fadeStart {
            guard trueAltitude > fadeEnd else { return 0 }
            let edge = saemundsson(fadeStart) * atmosphere.refractionScale
            return edge * (trueAltitude - fadeEnd) / (fadeStart - fadeEnd)
        }
        return saemundsson(trueAltitude) * atmosphere.refractionScale
    }

    /// Refraction in degrees to **subtract** from an apparent (observed) altitude
    /// (Bennett 1982, Meeus 16.3). Accurate to about 0.07′ above the horizon.
    public static func refractionForApparentAltitude(_ apparentAltitude: Double, atmosphere: Atmosphere = .standard) -> Double {
        guard apparentAltitude.isFinite, apparentAltitude < 90 else { return 0 }
        let h = max(apparentAltitude, -1.5)
        let arcminutes = 1 / AstroMath.tanDeg(h + 7.31 / (h + 4.4))
        return max(0, arcminutes / 60) * atmosphere.refractionScale
    }

    /// The altitude at which an object at `trueAltitude` is seen.
    public static func apparentAltitude(trueAltitude: Double, atmosphere: Atmosphere = .standard) -> Double {
        min(90, trueAltitude + refractionForTrueAltitude(trueAltitude, atmosphere: atmosphere))
    }

    /// The geometric altitude of an object seen at `apparentAltitude`; the exact inverse of
    /// `apparentAltitude(trueAltitude:)` (solved by Newton iteration).
    public static func trueAltitude(apparentAltitude: Double, atmosphere: Atmosphere = .standard) -> Double {
        guard apparentAltitude.isFinite else { return apparentAltitude }
        var h = apparentAltitude - refractionForApparentAltitude(apparentAltitude, atmosphere: atmosphere)
        for _ in 0..<8 {
            let residual = Refraction.apparentAltitude(trueAltitude: h, atmosphere: atmosphere) - apparentAltitude
            if abs(residual) < 1e-10 { break }
            let step = 1e-4
            let slope = (Refraction.apparentAltitude(trueAltitude: h + step, atmosphere: atmosphere)
                - Refraction.apparentAltitude(trueAltitude: h - step, atmosphere: atmosphere)) / (2 * step)
            guard slope > 0.1 else { break }
            h -= residual / slope
        }
        return h
    }

    /// Sæmundsson's formula in degrees for standard conditions.
    private static func saemundsson(_ h: Double) -> Double {
        let arcminutes = 1.02 / AstroMath.tanDeg(h + 10.3 / (h + 5.11))
        return max(0, arcminutes / 60)
    }
}

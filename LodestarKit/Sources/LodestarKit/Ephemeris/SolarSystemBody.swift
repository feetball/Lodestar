import Foundation

/// A solar-system body whose apparent position is computed by `Ephemeris`: the Sun, the Moon and
/// the seven other planets. (The Earth is the observer's home and is not listed.)
public enum SolarSystemBody: String, CaseIterable, Codable, Sendable {
    case sun, moon, mercury, venus, mars, jupiter, saturn, uranus, neptune

    /// The English name, e.g. "Jupiter".
    public var displayName: String {
        switch self {
        case .sun: "Sun"
        case .moon: "Moon"
        case .mercury: "Mercury"
        case .venus: "Venus"
        case .mars: "Mars"
        case .jupiter: "Jupiter"
        case .saturn: "Saturn"
        case .uranus: "Uranus"
        case .neptune: "Neptune"
        }
    }

    /// Mean (volumetric) radius in kilometres: the IAU nominal solar radius, the Moon, and the
    /// planets' volumetric means. For the gas giants this is a few per cent below the equatorial
    /// radius of the visible cloud tops.
    public var meanRadiusKilometers: Double {
        switch self {
        case .sun: 695_700
        case .moon: 1_737.4
        case .mercury: 2_439.7
        case .venus: 6_051.8
        case .mars: 3_389.5
        case .jupiter: 69_911
        case .saturn: 58_232
        case .uranus: 25_362
        case .neptune: 24_622
        }
    }

    /// `true` for Mercury through Neptune; `false` for the Sun and the Moon.
    public var isPlanet: Bool {
        switch self {
        case .sun, .moon: false
        case .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune: true
        }
    }
}

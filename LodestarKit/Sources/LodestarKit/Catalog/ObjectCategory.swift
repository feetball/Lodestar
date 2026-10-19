import Foundation

/// The kind of a sky object, as shown in lists and used to pick an icon.
///
/// The cases follow the OpenNGC type codes for deep-sky objects, plus the kinds that the catalog
/// adds itself: the solar-system bodies (the Sun, the Moon, the planets and, once small bodies are added with
/// `Catalog.withSmallBodies(_:)`, comets and asteroids), the Milky Way core, the celestial poles and
/// user-created targets.
public enum ObjectCategory: String, Codable, CaseIterable, Sendable {
    case sun
    case moon
    case planet
    /// A comet; added to a catalog with `Catalog.withSmallBodies(_:)`.
    case comet
    /// An asteroid (minor planet); the bright ones are bundled, see `BundledAsteroids`.
    case asteroid
    case star
    case doubleStar
    case galaxy
    case galaxyGroup
    case emissionNebula
    case reflectionNebula
    case darkNebula
    case nebula
    case planetaryNebula
    case supernovaRemnant
    case openCluster
    case globularCluster
    case clusterWithNebula
    case starAssociation
    case asterism
    case milkyWay
    case celestialPole
    case custom
    case other

    /// The English name shown to people, for example "Emission Nebula".
    public var displayName: String {
        switch self {
        case .sun: "Sun"
        case .moon: "Moon"
        case .planet: "Planet"
        case .comet: "Comet"
        case .asteroid: "Asteroid"
        case .star: "Star"
        case .doubleStar: "Double Star"
        case .galaxy: "Galaxy"
        case .galaxyGroup: "Galaxy Group"
        case .emissionNebula: "Emission Nebula"
        case .reflectionNebula: "Reflection Nebula"
        case .darkNebula: "Dark Nebula"
        case .nebula: "Nebula"
        case .planetaryNebula: "Planetary Nebula"
        case .supernovaRemnant: "Supernova Remnant"
        case .openCluster: "Open Cluster"
        case .globularCluster: "Globular Cluster"
        case .clusterWithNebula: "Cluster with Nebula"
        case .starAssociation: "Star Association"
        case .asterism: "Asterism"
        case .milkyWay: "Milky Way"
        case .celestialPole: "Celestial Pole"
        case .custom: "Custom Target"
        case .other: "Other"
        }
    }

    /// The name of an SF Symbol that suggests the category. Every name is available on iOS 15 and later.
    public var systemImageName: String {
        switch self {
        case .sun: "sun.max"
        case .moon: "moon"
        case .planet: "circle.circle"
        case .comet: "sparkle"
        case .asteroid: "circle.fill"
        case .star: "star"
        case .doubleStar: "star.leadinghalf.filled"
        case .galaxy: "hurricane"
        case .galaxyGroup: "circle.hexagongrid"
        case .emissionNebula: "cloud.fill"
        case .reflectionNebula: "cloud.sun"
        case .darkNebula: "cloud.fog.fill"
        case .nebula: "cloud"
        case .planetaryNebula: "circle.dotted"
        case .supernovaRemnant: "burst"
        case .openCluster: "sparkles"
        case .globularCluster: "aqi.medium"
        case .clusterWithNebula: "cloud.moon"
        case .starAssociation: "aqi.low"
        case .asterism: "star.circle"
        case .milkyWay: "moon.stars"
        case .celestialPole: "scope"
        case .custom: "plus.circle"
        case .other: "sparkle"
        }
    }

    /// The browse group the category is listed under.
    public var group: ObjectGroup {
        switch self {
        case .sun, .moon, .planet, .comet, .asteroid:
            .solarSystem
        case .star, .doubleStar, .asterism:
            .stars
        case .galaxy, .galaxyGroup:
            .galaxies
        case .emissionNebula, .reflectionNebula, .darkNebula, .nebula, .planetaryNebula,
             .supernovaRemnant, .clusterWithNebula:
            .nebulae
        case .openCluster, .globularCluster, .starAssociation:
            .clusters
        case .milkyWay, .celestialPole, .custom, .other:
            .special
        }
    }

    /// Creates the category of an OpenNGC object type code (`G`, `OCl`, `PN`, ...).
    ///
    /// | Code | Category |
    /// | --- | --- |
    /// | `G` | `galaxy` |
    /// | `GPair`, `GTrpl`, `GGroup` | `galaxyGroup` |
    /// | `OCl` | `openCluster` |
    /// | `GCl` | `globularCluster` |
    /// | `Cl+N` | `clusterWithNebula` |
    /// | `PN` | `planetaryNebula` |
    /// | `HII`, `EmN` | `emissionNebula` |
    /// | `RfN` | `reflectionNebula` |
    /// | `DrkN` | `darkNebula` |
    /// | `Neb` | `nebula` |
    /// | `SNR` | `supernovaRemnant` |
    /// | `*Ass` | `starAssociation` |
    /// | `**` | `doubleStar` |
    /// | `*` | `star` |
    ///
    /// Any other code (`Other`, `Nova`, or a code this version does not know) gives `.other`. Codes are
    /// case-sensitive.
    public init(openNGCType code: String) {
        switch code {
        case "G": self = .galaxy
        case "GPair", "GTrpl", "GGroup": self = .galaxyGroup
        case "OCl": self = .openCluster
        case "GCl": self = .globularCluster
        case "Cl+N": self = .clusterWithNebula
        case "PN": self = .planetaryNebula
        case "HII", "EmN": self = .emissionNebula
        case "RfN": self = .reflectionNebula
        case "DrkN": self = .darkNebula
        case "Neb": self = .nebula
        case "SNR": self = .supernovaRemnant
        case "*Ass": self = .starAssociation
        case "**": self = .doubleStar
        case "*": self = .star
        default: self = .other
        }
    }
}

/// The groups the browse screens divide the catalog into.
public enum ObjectGroup: String, CaseIterable, Codable, Sendable {
    case solarSystem
    case stars
    case galaxies
    case nebulae
    case clusters
    case special

    /// The English name shown to people, for example "Star Clusters".
    public var displayName: String {
        switch self {
        case .solarSystem: "Solar System"
        case .stars: "Stars"
        case .galaxies: "Galaxies"
        case .nebulae: "Nebulae"
        case .clusters: "Star Clusters"
        case .special: "Special"
        }
    }

    /// The name of an SF Symbol that suggests the group. Every name is available on iOS 15 and later.
    public var systemImageName: String {
        switch self {
        case .solarSystem: "sun.max"
        case .stars: "star"
        case .galaxies: "hurricane"
        case .nebulae: "cloud"
        case .clusters: "sparkles"
        case .special: "scope"
        }
    }

    /// The categories that belong to the group, in `ObjectCategory.allCases` order.
    public var categories: [ObjectCategory] {
        ObjectCategory.allCases.filter { $0.group == self }
    }
}

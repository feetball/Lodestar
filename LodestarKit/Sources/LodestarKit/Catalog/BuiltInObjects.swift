import Foundation

/// The objects that are not in the data files: the solar-system bodies, the Milky Way core and
/// the celestial poles.
enum BuiltInObjects {
    /// The Sun, the Moon, the seven other planets and Pluto, in `SolarSystemBody.allCases` order.
    static func solarSystem() -> [CelestialObject] {
        SolarSystemBody.allCases.map { body in
            let id: String
            let category: ObjectCategory
            switch body {
            case .sun:
                id = "sun"
                category = .sun
            case .moon:
                id = "moon"
                category = .moon
            case .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto:
                id = "planet.\(body.rawValue)"
                category = .planet
            }
            return CelestialObject(
                id: id, name: body.displayName, alternateNames: alternateNames(of: body), category: category,
                position: .solarSystem(body), isListed: true, notes: notes(of: body),
                prominence: body == .pluto ? .notable : .showpiece)
        }
    }

    /// Other names people may search for.
    private static func alternateNames(of body: SolarSystemBody) -> [String] {
        switch body {
        case .sun: ["Sol"]
        case .moon: ["Luna"]
        case .pluto: ["134340 Pluto"]
        default: []
        }
    }

    /// The note of the detail view: a warning for the Sun, what to expect of Pluto.
    private static func notes(of body: SolarSystemBody) -> String? {
        switch body {
        case .sun:
            "Look at the Sun only through a certified solar filter. Pointing a camera or telescope at it without one can damage eyes and equipment."
        case .pluto:
            "A dwarf planet beyond Neptune, about magnitude 14 at its best: far too faint for the eye or a short exposure. It takes a telescope or a long lens on a tracker and stacked frames, and gives itself away by moving against the stars from night to night."
        default:
            nil
        }
    }

    /// The Milky Way core and the two celestial poles.
    static func special(constellations: ConstellationDirectory) -> [CelestialObject] {
        func constellationName(_ abbreviation: String) -> String? {
            constellations.constellation(abbreviation: abbreviation)?.name
        }
        return [
            CelestialObject(
                id: "special.galacticCenter", name: "Galactic Center", designations: ["Sgr A*"],
                alternateNames: ["Sagittarius A*", "Galactic Centre", "Milky Way Core", "Galactic Core"],
                category: .milkyWay, constellation: "Sgr", constellationName: constellationName("Sgr"),
                position: .fixed(MilkyWayCoreVisibility.galacticCentre, nil),
                isListed: true,
                notes: "The direction of Sagittarius A*, the center of the Milky Way. The brightest part of the Milky Way band, and a favorite for wide-field astrophotography.",
                prominence: .showpiece),
            CelestialObject(
                id: "special.ncp", name: "North Celestial Pole", designations: ["NCP"],
                alternateNames: ["Celestial North Pole"], category: .celestialPole,
                constellation: "UMi", constellationName: constellationName("UMi"),
                position: .celestialPole(north: true), isListed: true,
                notes: "The point in the sky that the Earth's axis points to; the stars appear to turn around it. Polaris lies within one degree of it.",
                prominence: .showpiece),
            CelestialObject(
                id: "special.scp", name: "South Celestial Pole", designations: ["SCP"],
                alternateNames: ["Celestial South Pole"], category: .celestialPole,
                constellation: "Oct", constellationName: constellationName("Oct"),
                position: .celestialPole(north: false), isListed: true,
                notes: "The southern counterpart of the north celestial pole. No bright star marks it; the faint σ Octantis lies about one degree away.",
                prominence: .showpiece),
        ]
    }
}

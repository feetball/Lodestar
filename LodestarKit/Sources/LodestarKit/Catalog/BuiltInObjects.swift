import Foundation

/// The objects that are not in the data files: the solar-system bodies, the Milky Way core and
/// the celestial poles.
enum BuiltInObjects {
    /// Right ascension of Sagittarius A* (J2000): 17h 45m 40.04s, in hours.
    private static let sagittariusARightAscensionHours = 17.0 + 45.0 / 60 + 40.04 / 3600
    /// Declination of Sagittarius A* (J2000): −29° 00′ 28.1″.
    private static let sagittariusADeclination = -(29.0 + 28.1 / 3600)

    /// The Sun, the Moon and the seven other planets, in `SolarSystemBody.allCases` order.
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
            case .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune:
                id = "planet.\(body.rawValue)"
                category = .planet
            }
            return CelestialObject(
                id: id, name: body.displayName, alternateNames: alternateNames(of: body), category: category,
                position: .solarSystem(body), isListed: true,
                notes: body == .sun
                    ? "Look at the Sun only through a certified solar filter. Pointing a camera or telescope at it without one can damage eyes and equipment."
                    : nil)
        }
    }

    /// Other names people may search for.
    private static func alternateNames(of body: SolarSystemBody) -> [String] {
        switch body {
        case .sun: ["Sol"]
        case .moon: ["Luna"]
        default: []
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
                position: .fixed(EquatorialCoordinate(rightAscensionHours: sagittariusARightAscensionHours,
                                                      declination: sagittariusADeclination), nil),
                isListed: true,
                notes: "The direction of Sagittarius A*, the center of the Milky Way. The brightest part of the Milky Way band, and a favorite for wide-field astrophotography."),
            CelestialObject(
                id: "special.ncp", name: "North Celestial Pole", designations: ["NCP"],
                alternateNames: ["Celestial North Pole"], category: .celestialPole,
                constellation: "UMi", constellationName: constellationName("UMi"),
                position: .celestialPole(north: true), isListed: true,
                notes: "The point in the sky that the Earth's axis points to; the stars appear to turn around it. Polaris lies within one degree of it."),
            CelestialObject(
                id: "special.scp", name: "South Celestial Pole", designations: ["SCP"],
                alternateNames: ["Celestial South Pole"], category: .celestialPole,
                constellation: "Oct", constellationName: constellationName("Oct"),
                position: .celestialPole(north: false), isListed: true,
                notes: "The southern counterpart of the north celestial pole. No bright star marks it; the faint σ Octantis lies about one degree away."),
        ]
    }
}

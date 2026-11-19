import Foundation

/// Which way a planet's apparent motion among the stars turns at a station.
public enum PlanetStationKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// The planet stops moving east among the stars and starts to move west.
    case retrogradeBegins
    /// The planet stops moving west and resumes its eastward, direct motion.
    case directMotionResumes

    /// The English phrase, "retrograde motion begins" or "direct motion resumes".
    public var displayName: String {
        self == .retrogradeBegins ? "retrograde motion begins" : "direct motion resumes"
    }
}

/// A planet standing still among the stars: its apparent geocentric ecliptic longitude stops increasing or decreasing.
public struct PlanetStation: Sendable, Hashable {
    /// Mercury, Venus, Mars, Jupiter, Saturn, Uranus or Neptune.
    public let planet: SolarSystemBody
    /// Whether retrograde motion begins or direct motion resumes.
    public let kind: PlanetStationKind
    /// The planet's apparent ecliptic longitude of date at the station, degrees, [0, 360).
    public let longitude: Double

    public init(planet: SolarSystemBody, kind: PlanetStationKind, longitude: Double) {
        self.planet = planet
        self.kind = kind
        self.longitude = longitude
    }
}

/// Finds the stations of Mercury to Neptune: the instants at which the rate of the apparent geocentric ecliptic
/// longitude of date changes sign.
///
/// The rate is the central difference of the longitude over half a day, sampled every two days and refined by Brent's
/// method. A longitude curve is flat at a station, so the instant is sensitive to the ephemeris, yet the 11 stations of
/// Mercury, Venus, Mars, Jupiter, Saturn and Neptune compared with JPL's DE440s (see the tests) agree to 2 minutes.
/// Cost for one year of all seven planets: about 30 ms.
public enum PlanetStations {
    private static let planets: [SolarSystemBody] = [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]
    private static let step = 2.0
    private static let halfDifference = 0.25
    private static let tolerance = 1e-6

    /// The stations of `planet` from `from` to `to` (both inclusive), as events without visibility, in time order. Gives
    /// nothing for the Sun, the Moon and bodies that are not among Mercury to Neptune, for a reversed interval and
    /// outside the years 1 to 4001; intervals longer than ten years are cut short.
    public static func find(planet: SolarSystemBody, from: Date, to: Date) -> [AstronomicalEvent] {
        guard planets.contains(planet), EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        func longitude(_ ut: Double) -> Double {
            Ephemeris.state(of: planet, at: JulianDate(ut: ut)).eclipticLongitudeOfDate
        }
        func rate(_ ut: Double) -> Double {
            AstroMath.normalizeSignedDegrees(longitude(ut + halfDifference) - longitude(ut - halfDifference))
        }
        let startUT = fromUT - step
        let count = EventSearch.intervalCount(span: toUT + step - startUT, step: step)
        var found = [AstronomicalEvent]()
        var previous = rate(startUT)
        for index in 1...count {
            let ut = startUT + Double(index) * step
            let current = rate(ut)
            let begins = previous > 0 && current <= 0
            let resumes = previous < 0 && current >= 0
            if begins || resumes {
                if let root = EventSearch.root(of: rate, lower: ut - step, upper: ut, tolerance: tolerance),
                   root >= fromUT, root <= toUT {
                    let jd = JulianDate(ut: root)
                    let station = PlanetStation(planet: planet, kind: begins ? .retrogradeBegins : .directMotionResumes,
                                                longitude: longitude(root))
                    found.append(AstronomicalEvent(date: jd.date, details: .planetStation(station), visibility: nil))
                }
            }
            previous = current
        }
        return found
    }

    /// The stations of all seven planets from `from` to `to`, in time order (the events calendar's search).
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        EventSearch.sortedByDate(planets.flatMap { find(planet: $0, from: from, to: to) })
    }
}

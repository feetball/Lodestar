import Foundation

/// An opposition: a planet at 180° of ecliptic longitude from the Sun, the moment the planet is closest to the
/// Earth's night side of the sky and rises at sunset.
public struct Opposition: Sendable, Hashable {
    /// Mars, Jupiter, Saturn, Uranus or Neptune.
    public let planet: SolarSystemBody
    /// The planet's geocentric distance at the opposition in AU.
    public let distanceAU: Double
    /// The planet's apparent magnitude at the opposition.
    public let apparentMagnitude: Double?
    /// The planet's apparent diameter in arcseconds.
    public let angularDiameterArcseconds: Double

    public init(planet: SolarSystemBody, distanceAU: Double, apparentMagnitude: Double?,
                angularDiameterArcseconds: Double) {
        self.planet = planet
        self.distanceAU = distanceAU
        self.apparentMagnitude = apparentMagnitude
        self.angularDiameterArcseconds = angularDiameterArcseconds
    }
}

/// Finds the oppositions of Mars, Jupiter, Saturn, Uranus and Neptune. Cost for one year: about 10 ms.
public enum OppositionFinder {
    private static let planets: [SolarSystemBody] = [.mars, .jupiter, .saturn, .uranus, .neptune]
    private static let step = 5.0
    private static let tolerance = 1e-6

    /// The oppositions from `from` to `to` (both inclusive), as events without visibility, in time order. The instant
    /// is when the apparent ecliptic longitude (of date) of the planet exceeds the Sun's by 180°.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        let startUT = fromUT - step
        let count = EventSearch.intervalCount(span: toUT + step - startUT, step: step)
        let sunLongitudes = (0...count).map { EventSearch.sunLongitudeOfDate(JulianDate(ut: startUT + Double($0) * step)) }
        var found = [AstronomicalEvent]()
        for planet in planets {
            func offset(_ ut: Double) -> Double {
                let jd = JulianDate(ut: ut)
                let planetLongitude = Ephemeris.state(of: planet, at: jd).eclipticLongitudeOfDate
                return AstroMath.normalizeSignedDegrees(planetLongitude - EventSearch.sunLongitudeOfDate(jd) - 180)
            }
            var previous = AstroMath.normalizeSignedDegrees(
                Ephemeris.state(of: planet, at: JulianDate(ut: startUT)).eclipticLongitudeOfDate - sunLongitudes[0] - 180)
            for index in 1...count {
                let ut = startUT + Double(index) * step
                let current = AstroMath.normalizeSignedDegrees(
                    Ephemeris.state(of: planet, at: JulianDate(ut: ut)).eclipticLongitudeOfDate - sunLongitudes[index] - 180)
                if previous > 0, current <= 0, previous - current < 90 {
                    if let root = EventSearch.root(of: offset, lower: ut - step, upper: ut, tolerance: tolerance),
                       root >= fromUT, root <= toUT {
                        let jd = JulianDate(ut: root)
                        let state = Ephemeris.state(of: planet, at: jd)
                        let opposition = Opposition(planet: planet, distanceAU: state.distanceAU,
                                                    apparentMagnitude: state.apparentMagnitude,
                                                    angularDiameterArcseconds: state.angularDiameterArcseconds)
                        found.append(AstronomicalEvent(date: jd.date, details: .opposition(opposition), visibility: nil))
                    }
                }
                previous = current
            }
        }
        return EventSearch.sortedByDate(found)
    }
}

/// Which side of the Sun a planet stands at its greatest elongation.
public enum ElongationDirection: String, CaseIterable, Sendable, Hashable, Codable {
    /// East of the Sun: an evening object.
    case east
    /// West of the Sun: a morning object.
    case west

    /// The English adjective, "Eastern" or "Western".
    public var displayName: String { self == .east ? "Eastern" : "Western" }
}

/// The greatest elongation of Mercury or Venus: the largest angular distance from the Sun of an apparition.
public struct GreatestElongation: Sendable, Hashable {
    /// Mercury or Venus.
    public let planet: SolarSystemBody
    /// East (evening sky) or west (morning sky) of the Sun.
    public let direction: ElongationDirection
    /// The elongation in degrees.
    public let angle: Double
    /// The planet's apparent magnitude then.
    public let apparentMagnitude: Double?

    public init(planet: SolarSystemBody, direction: ElongationDirection, angle: Double, apparentMagnitude: Double?) {
        self.planet = planet
        self.direction = direction
        self.angle = angle
        self.apparentMagnitude = apparentMagnitude
    }
}

/// Finds the greatest elongations of Mercury and Venus.
///
/// The maximum of the angular distance from the Sun is flat, so the instant is the zero of its derivative (a central
/// difference over one day), which is steadier than comparing nearly equal distances. Cost for one year: about 5 ms.
public enum GreatestElongationFinder {
    private static let planets: [SolarSystemBody] = [.mercury, .venus]
    private static let step = 2.0
    private static let coarseTolerance = 1e-3
    private static let tolerance = 1e-6
    private static let halfDifference = 0.5

    /// The greatest elongations from `from` to `to` (both inclusive), as events without visibility, in time order.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        let startUT = fromUT - 2 * step
        let count = EventSearch.intervalCount(span: toUT + 2 * step - startUT, step: step)
        let sunVectors = (0...count).map { Ephemeris.geocentricJ2000(of: .sun, at: JulianDate(ut: startUT + Double($0) * step)) }
        var found = [AstronomicalEvent]()
        for planet in planets {
            func elongation(_ ut: Double) -> Double {
                let jd = JulianDate(ut: ut)
                return Ephemeris.geocentricJ2000(of: planet, at: jd).angle(to: Ephemeris.geocentricJ2000(of: .sun, at: jd))
            }
            let samples = (0...count).map {
                Ephemeris.geocentricJ2000(of: planet, at: JulianDate(ut: startUT + Double($0) * step)).angle(to: sunVectors[$0])
            }
            for index in EventSearch.localMaxima(samples) {
                let coarse = EventSearch.maximum(of: elongation, lower: startUT + Double(index - 1) * step,
                                                 upper: startUT + Double(index + 1) * step,
                                                 tolerance: coarseTolerance).time
                let refined = EventSearch.root(of: { elongation($0 + halfDifference) - elongation($0 - halfDifference) },
                                               lower: coarse - 2 * halfDifference, upper: coarse + 2 * halfDifference,
                                               tolerance: tolerance) ?? coarse
                if refined < fromUT || refined > toUT { continue }
                let jd = JulianDate(ut: refined)
                let state = Ephemeris.state(of: planet, at: jd)
                let sunLongitude = EventSearch.sunLongitudeOfDate(jd)
                let east = AstroMath.normalizeSignedDegrees(state.eclipticLongitudeOfDate - sunLongitude) > 0
                let result = GreatestElongation(planet: planet, direction: east ? .east : .west,
                                                angle: state.elongation ?? elongation(refined),
                                                apparentMagnitude: state.apparentMagnitude)
                found.append(AstronomicalEvent(date: jd.date, details: .greatestElongation(result), visibility: nil))
            }
        }
        return EventSearch.sortedByDate(found)
    }
}

/// Whether the Earth is at its closest to or farthest from the Sun.
public enum EarthApsisKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// Closest to the Sun, in early January.
    case perihelion
    /// Farthest from the Sun, in early July.
    case aphelion

    /// The English name, "Perihelion" or "Aphelion".
    public var displayName: String { self == .perihelion ? "Perihelion" : "Aphelion" }
}

/// The Earth's perihelion or aphelion.
public struct EarthApsis: Sendable, Hashable {
    /// Perihelion or aphelion.
    public let kind: EarthApsisKind
    /// The Earth–Sun distance in AU at the apsis.
    public let distanceAU: Double

    public init(kind: EarthApsisKind, distanceAU: Double) {
        self.kind = kind
        self.distanceAU = distanceAU
    }
}

/// Finds the Earth's perihelion and aphelion as the extremes of the Earth–Sun distance (the Earth–Moon barycentre of the
/// VSOP87 series, as in the published tables; it differs from the Earth's centre by at most 0.00003 AU).
///
/// Each apsis is searched within a week of the mean instant of Meeus, *Astronomical Algorithms*, ch. 38 (a whole `k` is a
/// perihelion, `k + 0.5` an aphelion). The anomalistic year is longer than the calendar year, so the apsides drift through
/// the calendar by about 1.75 days a century; counting `k` instead of calendar days keeps them inside the window from the
/// year 1 to the year 4001. The planets and the Moon move the true apsis by at most about two days from the mean one.
public enum EarthApsisFinder {
    private static let halfWindow = 7.0
    private static let halfDifference = 0.5
    private static let tolerance = 1e-6
    /// The mean perihelion at `k = 0` (JDE, 2000 January 3).
    private static let meanPerihelionEpoch = 2_451_547.507
    /// Days from one mean perihelion to the next.
    private static let anomalisticYearDays = 365.259_635_8

    /// The apsides from `from` to `to` (both inclusive), as events without visibility, in time order.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        func distance(_ ut: Double) -> Double { Ephemeris.geocentricJ2000(of: .sun, at: JulianDate(ut: ut)).length }
        let firstK = Int(((fromUT - meanPerihelionEpoch) / anomalisticYearDays).rounded(.down)) - 1
        let lastK = Int(((toUT - meanPerihelionEpoch) / anomalisticYearDays).rounded(.up)) + 1
        var found = [AstronomicalEvent]()
        for k in firstK...lastK {
            for kind in EarthApsisKind.allCases {
                let phase = kind == .perihelion ? 0.0 : 0.5
                // The mean instant is in dynamical time (TT); the search runs in UT.
                let centre = JulianDate(tt: meanPerihelionEpoch + anomalisticYearDays * (Double(k) + phase)).ut
                guard let root = EventSearch.root(of: { distance($0 + halfDifference) - distance($0 - halfDifference) },
                                                  lower: centre - halfWindow, upper: centre + halfWindow,
                                                  tolerance: tolerance) else { continue }
                if root < fromUT || root > toUT { continue }
                found.append(AstronomicalEvent(date: EventSearch.instant(root),
                                               details: .earthApsis(EarthApsis(kind: kind, distanceAU: distance(root))),
                                               visibility: nil))
            }
        }
        return EventSearch.sortedByDate(found)
    }
}

/// Which equinox or solstice.
///
/// Named after the month, so it is the same in both hemispheres; the UI says "autumnal" or "vernal".
public enum SeasonKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// The Sun crosses the celestial equator northwards (longitude 0°).
    case marchEquinox
    /// The Sun is at its northernmost (longitude 90°).
    case juneSolstice
    /// The Sun crosses the celestial equator southwards (longitude 180°).
    case septemberEquinox
    /// The Sun is at its southernmost (longitude 270°).
    case decemberSolstice

    /// The English name, e.g. "June solstice".
    public var displayName: String {
        switch self {
        case .marchEquinox: "March equinox"
        case .juneSolstice: "June solstice"
        case .septemberEquinox: "September equinox"
        case .decemberSolstice: "December solstice"
        }
    }

    /// The apparent ecliptic longitude of the Sun in degrees at the event.
    public var solarLongitude: Double {
        switch self {
        case .marchEquinox: 0
        case .juneSolstice: 90
        case .septemberEquinox: 180
        case .decemberSolstice: 270
        }
    }
}

/// An equinox or a solstice.
public struct Season: Sendable, Hashable {
    /// Which of the four.
    public let kind: SeasonKind

    public init(kind: SeasonKind) {
        self.kind = kind
    }
}

/// Finds the equinoxes and solstices: the instants at which the Sun's apparent ecliptic longitude of date reaches 0°,
/// 90°, 180° and 270°, as in the tables of the U.S. Naval Observatory. Cost: about 100 µs each.
public enum SeasonFinder {
    /// The equinoxes and solstices from `from` to `to` (both inclusive), as events without visibility, in time order.
    public static func events(from: Date, to: Date) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        let startLongitude = EventSearch.sunLongitudeOfDate(JulianDate(ut: fromUT))
        var target = (startLongitude / 90).rounded(.up) * 90
        var guess = fromUT + (target - startLongitude) / EventSearch.meanSolarRate
        var found = [AstronomicalEvent]()
        while true {
            let longitude = target.truncatingRemainder(dividingBy: 360)
            let ut = EventSearch.solveSolarLongitude(target: longitude, guess: guess) { EventSearch.sunLongitudeOfDate($0) }
            if !(ut <= toUT) { break }
            if ut >= fromUT, let kind = SeasonKind.allCases.first(where: { $0.solarLongitude == longitude }) {
                found.append(AstronomicalEvent(date: EventSearch.instant(ut), details: .season(Season(kind: kind)),
                                               visibility: nil))
            }
            target += 90
            guess = ut + 91.3
        }
        return found
    }
}

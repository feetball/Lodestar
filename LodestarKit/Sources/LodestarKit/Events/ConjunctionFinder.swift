import Foundation

/// The bright stars near the ecliptic, and the Pleiades, that the Moon passes close to.
///
/// Places are Hipparcos (new reduction) J2000 positions and proper motions as in the kit's star catalog; the Pleiades
/// are the centre of the cluster M 45 (SIMBAD, 03h 47m, +24° 07′) with the proper motion of Alcyone.
public enum ReferenceStar: String, CaseIterable, Sendable, Hashable, Codable {
    /// α Leonis.
    case regulus
    /// α Virginis.
    case spica
    /// α Scorpii.
    case antares
    /// α Tauri.
    case aldebaran
    /// The Pleiades (M 45).
    case pleiades

    /// The English name, e.g. "Spica".
    public var displayName: String {
        switch self {
        case .regulus: "Regulus"
        case .spica: "Spica"
        case .antares: "Antares"
        case .aldebaran: "Aldebaran"
        case .pleiades: "The Pleiades"
        }
    }

    /// The J2000.0 catalog place.
    public var position: EquatorialCoordinate {
        switch self {
        case .regulus: EquatorialCoordinate(rightAscension: 152.092967, declination: 11.967207)
        case .spica: EquatorialCoordinate(rightAscension: 201.298243, declination: -11.161322)
        case .antares: EquatorialCoordinate(rightAscension: 247.351917, declination: -26.432002)
        case .aldebaran: EquatorialCoordinate(rightAscension: 68.980162, declination: 16.509301)
        case .pleiades: EquatorialCoordinate(rightAscension: 56.75, declination: 24.1167)
        }
    }

    /// The proper motion in mas/yr.
    public var properMotion: ProperMotion {
        switch self {
        case .regulus: ProperMotion(raMilliarcsecondsPerYear: -249.4, decMilliarcsecondsPerYear: 4.91)
        case .spica: ProperMotion(raMilliarcsecondsPerYear: -42.5, decMilliarcsecondsPerYear: -31.73)
        case .antares: ProperMotion(raMilliarcsecondsPerYear: -10.16, decMilliarcsecondsPerYear: -23.21)
        case .aldebaran: ProperMotion(raMilliarcsecondsPerYear: 62.78, decMilliarcsecondsPerYear: -189.36)
        case .pleiades: ProperMotion(raMilliarcsecondsPerYear: 19.35, decMilliarcsecondsPerYear: -43.11)
        }
    }
}

/// One of the two things that come close in a `Conjunction`: a solar-system body or a reference star.
public enum ConjunctionTarget: Sendable, Hashable {
    /// The Moon or a planet.
    case body(SolarSystemBody)
    /// A reference star or the Pleiades.
    case star(ReferenceStar)

    /// The English name, e.g. "Venus" or "Antares".
    public var displayName: String {
        switch self {
        case let .body(body): body.displayName
        case let .star(star): star.displayName
        }
    }

    /// What to point a camera at for this target.
    public var aimTarget: AimTarget {
        switch self {
        case let .body(body): .body(body)
        case let .star(star): .fixed(star.position, star.properMotion)
        }
    }
}

/// The closest approach of the Moon or a planet as seen at an observer on the ground.
public struct TopocentricApproach: Sendable, Hashable {
    /// The instant of the least topocentric separation.
    public let time: Date
    /// The least separation of the centres in degrees.
    public let separation: Double
    /// `true` when the Moon's disc covers the centre of the other body at that instant.
    public let isOccultation: Bool

    public init(time: Date, separation: Double, isOccultation: Bool) {
        self.time = time
        self.separation = separation
        self.isOccultation = isOccultation
    }
}

/// A close approach of two bodies on the sky.
public struct Conjunction: Sendable, Hashable {
    /// The first body (the Moon when it takes part, otherwise the one that comes first among the planets).
    public let first: ConjunctionTarget
    /// The second body: a planet or a reference star.
    public let second: ConjunctionTarget
    /// The least geocentric angular separation in degrees; the event's date is its instant.
    public let separation: Double
    /// The angular distance from the Sun in degrees (of the Moon, or of the midpoint of two planets); small values
    /// mean the pair stands in the glare of the Sun.
    public let solarElongation: Double
    /// `true` for the Moon when its disc can cover the other body somewhere on Earth: the geocentric separation is
    /// below the Moon's semidiameter plus its horizontal parallax plus the other body's radius.
    public let occultationPossible: Bool
    /// For the Moon with an observer: the closest approach as seen from the observer's place, where the Moon's
    /// parallax (up to about 1°) shifts it; `nil` otherwise.
    public let topocentric: TopocentricApproach?

    /// `true` when the Moon is the first body.
    public var involvesMoon: Bool { first == .body(.moon) }

    public init(first: ConjunctionTarget, second: ConjunctionTarget, separation: Double, solarElongation: Double,
                occultationPossible: Bool, topocentric: TopocentricApproach?) {
        self.first = first
        self.second = second
        self.separation = separation
        self.solarElongation = solarElongation
        self.occultationPossible = occultationPossible
        self.topocentric = topocentric
    }
}

/// Finds conjunctions: close approaches of the Moon with the planets and the reference stars, and of the planets with
/// each other.
///
/// The planets are sampled daily and the Moon every six hours; each local minimum of the separation that comes within a
/// safety margin of the threshold is refined by golden-section search on the exact geocentric apparent positions
/// (about 25 positions each). Cost for one year: about 30 ms on a desktop, dominated by the planetary positions.
public enum ConjunctionFinder {
    private static let planets: [SolarSystemBody] = [
        .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune,
    ]

    private static let planetStep = 1.0
    private static let moonStep = 0.25
    private static let pruneMargin = 0.5
    private static let refineTolerance = 1e-5
    private static let topocentricHalfWindow = 0.125

    /// The conjunctions from `from` to `to` (both inclusive) whose least separation is within the thresholds of
    /// `options` and whose solar elongation is at least `EventOptions.minimumSolarElongation`, in time order. With an
    /// `observer`, conjunctions of the Moon carry the topocentric approach.
    public static func events(from: Date, to: Date, observer: Observer? = nil,
                              options: EventOptions = EventOptions()) -> [AstronomicalEvent] {
        guard EventSearch.isUsable(from: from, to: to) else { return [] }
        let fromUT = EventSearch.ut(from)
        let toUT = EventSearch.ut(EventSearch.limitedEnd(from: from, to: to))
        let scan = Scan(fromUT: fromUT, toUT: toUT)
        var found = [AstronomicalEvent]()

        // Planet with planet.
        for i in planets.indices {
            for j in (i + 1)..<planets.count {
                let separations = (0...scan.dayCount).map { scan.planetVectors[i][$0].angle(to: scan.planetVectors[j][$0]) }
                for index in EventSearch.localMinima(separations) {
                    if estimatedMinimum(separations, index: index) > options.planetConjunctionThreshold + pruneMargin {
                        continue
                    }
                    let first = ConjunctionTarget.body(planets[i])
                    let second = ConjunctionTarget.body(planets[j])
                    if let minimum = refine(first, second, lower: scan.startUT + Double(index - 1) * planetStep,
                                            upper: scan.startUT + Double(index + 1) * planetStep) {
                        appendIfAccepted(&found, minimum: minimum, first: first, second: second, options: options,
                                         observer: observer, fromUT: fromUT, toUT: toUT)
                    }
                }
            }
        }

        // The Moon with the planets and the stars.
        let moon = ConjunctionTarget.body(.moon)
        var targets = [ConjunctionTarget]()
        for planet in planets { targets.append(.body(planet)) }
        for star in ReferenceStar.allCases { targets.append(.star(star)) }
        for (targetIndex, target) in targets.enumerated() {
            let separations = (0...scan.moonCount).map { scan.moonSeparation(targetIndex: targetIndex, moonIndex: $0) }
            for index in EventSearch.localMinima(separations) {
                if estimatedMinimum(separations, index: index) > options.moonConjunctionThreshold + pruneMargin {
                    continue
                }
                if let minimum = refine(moon, target, lower: scan.startUT + Double(index - 1) * moonStep,
                                        upper: scan.startUT + Double(index + 1) * moonStep) {
                    appendIfAccepted(&found, minimum: minimum, first: moon, second: target, options: options,
                                     observer: observer, fromUT: fromUT, toUT: toUT)
                }
            }
        }
        return EventSearch.sortedByDate(found)
    }

    /// The grids of the scan: daily planet directions, six-hourly Moon directions, fixed star directions.
    private struct Scan {
        let startUT: Double
        let dayCount: Int
        let moonCount: Int
        let planetVectors: [[Vector3]]
        let moonVectors: [Vector3]
        let starVectors: [Vector3]

        init(fromUT: Double, toUT: Double) {
            let startUT = fromUT - 3
            let dayCount = EventSearch.intervalCount(span: toUT + 3 - startUT, step: ConjunctionFinder.planetStep)
            let moonCount = EventSearch.intervalCount(span: toUT + 3 - startUT, step: ConjunctionFinder.moonStep)
            self.startUT = startUT
            self.dayCount = dayCount
            self.moonCount = moonCount
            planetVectors = ConjunctionFinder.geometricPlanetVectors(startUT: startUT, dayCount: dayCount)
            moonVectors = (0...moonCount).map {
                Ephemeris.geocentricJ2000(of: .moon, at: JulianDate(ut: startUT + Double($0) * ConjunctionFinder.moonStep))
            }
            starVectors = ReferenceStar.allCases.map { $0.position.unitVector }
        }

        /// Separation in degrees of the Moon at Moon sample `moonIndex` from planet or star `targetIndex`.
        func moonSeparation(targetIndex: Int, moonIndex: Int) -> Double {
            let moon = moonVectors[moonIndex]
            if targetIndex >= ConjunctionFinder.planets.count {
                return moon.angle(to: starVectors[targetIndex - ConjunctionFinder.planets.count])
            }
            let position = Double(moonIndex) * ConjunctionFinder.moonStep / ConjunctionFinder.planetStep
            let node = min(Int(position.rounded(.down)), dayCount - 1)
            let fraction = position - Double(node)
            let planet = planetVectors[targetIndex][node] * (1 - fraction)
                + planetVectors[targetIndex][node + 1] * fraction
            return moon.angle(to: planet)
        }
    }

    /// Geocentric directions of the planets every `planetStep` days from `startUT`, from the heliocentric series alone
    /// (no light-time or aberration: at most 0.02° off, which the coarse scan allows for). The Earth's position is
    /// computed once per date and shared by the seven planets.
    private static func geometricPlanetVectors(startUT: Double, dayCount: Int) -> [[Vector3]] {
        let theories = planets.map { theory($0) }
        var vectors = [[Vector3]](repeating: [Vector3](repeating: .zero, count: dayCount + 1), count: planets.count)
        for day in 0...dayCount {
            let tt = JulianDate(ut: startUT + Double(day) * planetStep).tt
            let earth = Ephemeris.PlanetaryTheory.heliocentricJ2000(.earth, julianDayTT: tt)
            for index in planets.indices {
                vectors[index][day] = Ephemeris.PlanetaryTheory.heliocentricJ2000(theories[index], julianDayTT: tt) - earth
            }
        }
        return vectors
    }

    private static func theory(_ body: SolarSystemBody) -> Ephemeris.PlanetaryTheory.Planet {
        switch body {
        case .mercury: .mercury
        case .venus: .venus
        case .mars: .mars
        case .jupiter: .jupiter
        case .saturn: .saturn
        case .uranus: .uranus
        case .neptune: .neptune
        case .sun, .moon: .earth
        }
    }

    /// The least separation the samples around the local minimum at `index` imply: the vertex of the parabola through
    /// the squares of the three separations (exact for motion along a straight line at constant speed).
    private static func estimatedMinimum(_ separations: [Double], index: Int) -> Double {
        let before = separations[index - 1] * separations[index - 1]
        let here = separations[index] * separations[index]
        let after = separations[index + 1] * separations[index + 1]
        let curvature = before - 2 * here + after
        if !(curvature > 0) { return separations[index] }
        let vertex = here - (after - before) * (after - before) / (8 * curvature)
        return max(vertex, 0).squareRoot()
    }

    /// The geocentric apparent direction of `target` at `jd`; planets and the Moon keep their distance (AU), stars are
    /// unit vectors.
    private static func vector(_ target: ConjunctionTarget, at jd: JulianDate) -> Vector3 {
        switch target {
        case let .body(body):
            return Ephemeris.geocentricJ2000(of: body, at: jd)
        case let .star(star):
            let moved = star.properMotion.apply(to: star.position, years: (jd.tt - JulianDate.j2000) / 365.25)
            return Aberration.apply(to: moved.unitVector, earthVelocity: Aberration.earthVelocity(jd))
        }
    }

    private static func separation(_ first: ConjunctionTarget, _ second: ConjunctionTarget, ut: Double) -> Double {
        let jd = JulianDate(ut: ut)
        return vector(first, at: jd).angle(to: vector(second, at: jd))
    }

    /// The instant of least separation in the bracket and that separation.
    private static func refine(_ first: ConjunctionTarget, _ second: ConjunctionTarget, lower: Double,
                               upper: Double) -> (time: Double, value: Double)? {
        let result = EventSearch.minimum(of: { separation(first, second, ut: $0) }, lower: lower, upper: upper,
                                         tolerance: refineTolerance)
        return result.time > lower && result.time < upper ? result : nil
    }

    private static func appendIfAccepted(_ found: inout [AstronomicalEvent], minimum: (time: Double, value: Double),
                                         first: ConjunctionTarget, second: ConjunctionTarget, options: EventOptions,
                                         observer: Observer?, fromUT: Double, toUT: Double) {
        let ut = minimum.time
        if ut < fromUT || ut > toUT { return }
        let involvesMoon = first == .body(.moon)
        let threshold = involvesMoon ? options.moonConjunctionThreshold : options.planetConjunctionThreshold
        if minimum.value > threshold { return }
        let jd = JulianDate(ut: ut)
        let sun = Ephemeris.geocentricJ2000(of: .sun, at: jd)
        let firstVector = vector(first, at: jd)
        let secondVector = vector(second, at: jd)
        let centre = involvesMoon ? firstVector : firstVector.normalized + secondVector.normalized
        let elongation = centre.angle(to: sun)
        if elongation < options.minimumSolarElongation { return }

        var occultationPossible = false
        var topocentric: TopocentricApproach?
        if involvesMoon {
            let moonDistanceKilometers = firstVector.length * SkyFrame.kilometersPerAU
            let reach = angularRadius(SolarSystemBody.moon.meanRadiusKilometers, distanceKilometers: moonDistanceKilometers)
                + AstroMath.asinDeg(SkyFrame.earthEquatorialRadiusKilometers / moonDistanceKilometers)
                + targetRadius(second, vector: secondVector)
            occultationPossible = minimum.value < reach
            if let observer { topocentric = topocentricApproach(second, observer: observer, ut: ut) }
        }
        let conjunction = Conjunction(first: first, second: second, separation: minimum.value, solarElongation: elongation,
                                      occultationPossible: occultationPossible, topocentric: topocentric)
        found.append(AstronomicalEvent(date: jd.date, details: .conjunction(conjunction), visibility: nil))
    }

    /// Angular radius in degrees of a sphere of `radiusKilometers` at `distanceKilometers`.
    private static func angularRadius(_ radiusKilometers: Double, distanceKilometers: Double) -> Double {
        AstroMath.asinDeg(AstroMath.clamp(radiusKilometers / distanceKilometers, 0, 1))
    }

    /// The angular radius in degrees of `target` at the distance of `vector` (AU); 0 for stars.
    private static func targetRadius(_ target: ConjunctionTarget, vector: Vector3) -> Double {
        switch target {
        case let .body(body):
            return angularRadius(body.meanRadiusKilometers, distanceKilometers: vector.length * SkyFrame.kilometersPerAU)
        case .star:
            return 0
        }
    }

    /// The least topocentric separation of the Moon from `target` within three hours of `ut`. The Moon is evaluated
    /// exactly; a planet is placed on the straight line through its positions at the ends of the window (its motion
    /// is uniform to better than 0.001° over six hours) and a star at its apparent place at `ut`.
    private static func topocentricApproach(_ target: ConjunctionTarget, observer: Observer,
                                            ut: Double) -> TopocentricApproach {
        let start = ut - topocentricHalfWindow
        let end = ut + topocentricHalfWindow
        var startVector = Vector3.zero
        var endVector = Vector3.zero
        var starVector = Vector3.zero
        switch target {
        case .body:
            startVector = vector(target, at: JulianDate(ut: start))
            endVector = vector(target, at: JulianDate(ut: end))
        case .star:
            starVector = vector(target, at: JulianDate(ut: ut))
        }

        func evaluate(_ time: Double) -> (separation: Double, moonRadius: Double, otherRadius: Double) {
            let frame = SkyFrame(julianDate: JulianDate(ut: time), observer: observer)
            let matrix = frame.precessionNutationMatrix
            let moon = matrix * Ephemeris.geocentricJ2000(of: .moon, at: frame.julianDate) - frame.observerPositionOfDate
            let moonRadius = angularRadius(SolarSystemBody.moon.meanRadiusKilometers,
                                           distanceKilometers: moon.length * SkyFrame.kilometersPerAU)
            switch target {
            case .body:
                let fraction = (time - start) / (end - start)
                let other = matrix * (startVector * (1 - fraction) + endVector * fraction) - frame.observerPositionOfDate
                return (moon.angle(to: other), moonRadius, targetRadius(target, vector: other))
            case .star:
                return (moon.angle(to: matrix * starVector), moonRadius, 0)
            }
        }

        let least = EventSearch.minimum(of: { evaluate($0).separation }, lower: start, upper: end,
                                        tolerance: refineTolerance)
        let radii = evaluate(least.time)
        return TopocentricApproach(time: EventSearch.instant(least.time), separation: least.value,
                                   isOccultation: least.value < radii.moonRadius + radii.otherRadius)
    }
}

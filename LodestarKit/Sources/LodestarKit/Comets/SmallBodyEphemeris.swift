import Foundation

/// Apparent positions, distances and magnitudes of comets and asteroids from their osculating elements.
///
/// The heliocentric motion is the two-body motion of `OrbitPropagator`; the Earth comes from the same truncated VSOP87B
/// theory as the planets of `Ephemeris`, and the geocentric position is built exactly as for a planet: light-time by
/// iteration (the body is seen where it was a light-time ago, the Earth where it is now), then annual aberration, so
/// `SkyFrame.horizontal(geocentricJ2000:refraction:)` works unchanged.
///
/// **Accuracy.** The Earth contributes a few arcseconds (VSOP87B) and the frame about 0.02″. The dominant error is that
/// real bodies are perturbed by the planets while the elements describe a Kepler orbit that is exact only at the epoch
/// of the elements. Measured against JPL Horizons (osculating elements taken at the test epoch itself, so only the
/// perturbation of the following weeks remains): below one arcsecond on the epoch, about one arcsecond after 15 days for
/// a comet 0.5 AU from the Earth and 0.6 arcseconds after 60 days for Halley; main-belt asteroids are within 4 arcseconds
/// after four months. Published elements that are 200 days away from the date are still good to 30 arcseconds (12P in
/// April 2024 from the Small-Body Database elements of September 2023), elements 18 years old are not (Halley in 1986 from
/// the elements of 1968: 0.7° to 6°). MPC and JPL publish new elements every few weeks to months, so refresh the element
/// files regularly (see `API.md`). Non-gravitational forces of comets are not modelled either.
/// The magnitudes are the catalogs' formulas and are uncertain by a magnitude or more for comets.
///
/// **Cost.** One `state(of:at:)` (Earth theory, aberration, Kepler solution, light-time) takes about 5 microseconds
/// on a desktop CPU, `geocentricJ2000(of:at:)` about 4.
public enum SmallBodyEphemeris {
    /// The default faintest magnitude for `SmallBodyState.isPhotographable`: 10, within reach of a camera on a tripod.
    public static let defaultMagnitudeLimit = 10.0

    /// The default smallest elongation for `SmallBodyState.isPhotographable`: 25° from the Sun.
    public static let defaultMinimumElongation = 25.0

    /// The Earth's heliocentric position, orbital velocity and apparent Sun at one instant.
    struct EarthReference {
        let julianDate: JulianDate
        /// Heliocentric position in AU, J2000 equatorial.
        let position: Vector3
        /// Velocity divided by the speed of light, J2000 equatorial.
        let velocity: Vector3
        /// The Sun's apparent geocentric position (light-time and aberration), AU, J2000 equatorial.
        let sunApparent: Vector3

        init(julianDate: JulianDate) {
            self.julianDate = julianDate
            position = Ephemeris.PlanetaryTheory.heliocentricJ2000(.earth, julianDayTT: julianDate.tt)
            velocity = Aberration.earthVelocity(julianDate)
            sunApparent = Self.aberrated(-position, velocity: velocity)
        }

        /// Applies annual aberration to a geocentric vector, preserving its length.
        func aberrated(_ vector: Vector3) -> Vector3 {
            Self.aberrated(vector, velocity: velocity)
        }

        private static func aberrated(_ vector: Vector3, velocity: Vector3) -> Vector3 {
            Aberration.apply(to: vector.normalized, earthVelocity: velocity) * vector.length
        }
    }

    /// A body's position as seen from the Earth's centre (J2000 equatorial, AU).
    struct Geometry {
        /// Direction and distance at the instant the light left the body, before aberration.
        let geometric: Vector3
        /// With annual aberration.
        let apparent: Vector3
        /// The body's position relative to the Sun when the light left it.
        let heliocentric: Vector3
    }

    /// The position, distance, phase and brightness of `body` at `julianDate`; `nil` if its orbit cannot be evaluated then.
    public static func state(of body: SmallBody, at julianDate: JulianDate) -> SmallBodyState? {
        state(of: body, earth: EarthReference(julianDate: julianDate))
    }

    /// The geocentric apparent position of `body` in AU, as `SmallBodyState.geocentricJ2000`, without the physical
    /// quantities; `nil` if the orbit cannot be evaluated at `julianDate` (an unbound orbit more than
    /// `OrbitPropagator.maximumUnboundSpanDays` from perihelion). Cheaper than `state(of:at:)`.
    public static func geocentricJ2000(of body: SmallBody, at julianDate: JulianDate) -> Vector3? {
        geometry(of: body.orbit, earth: EarthReference(julianDate: julianDate))?.apparent
    }

    static func geometry(of orbit: SmallBodyElements, earth: EarthReference) -> Geometry? {
        // Light-time: the body is seen where it was `lightTime` ago, the Earth where it is now.
        var lightTime = 0.0
        var position = Vector3.zero
        for _ in 0..<4 {
            guard let moved = OrbitPropagator.heliocentricJ2000(of: orbit, at: earth.julianDate.tt - lightTime) else { return nil }
            position = moved
            let updated = (position - earth.position).length * Ephemeris.lightTimePerAU
            let converged = abs(updated - lightTime) < 2e-6
            lightTime = updated
            if converged { break }
        }
        let geometric = position - earth.position
        return Geometry(geometric: geometric, apparent: earth.aberrated(geometric), heliocentric: position)
    }

    static func state(of body: SmallBody, earth: EarthReference) -> SmallBodyState? {
        guard let geometry = geometry(of: body.orbit, earth: earth) else { return nil }
        let phaseAngle = geometry.heliocentric.angle(to: geometry.geometric)
        let sunDistance = geometry.heliocentric.length
        let earthDistance = geometry.apparent.length
        return SmallBodyState(
            body: body, julianDate: earth.julianDate, astrometric: geometry.geometric, apparent: geometry.apparent,
            heliocentric: geometry.heliocentric, elongation: geometry.apparent.angle(to: earth.sunApparent),
            phaseAngle: phaseAngle,
            apparentMagnitude: body.photometry?.apparentMagnitude(sunDistanceAU: sunDistance, earthDistanceAU: earthDistance,
                                                                  phaseAngle: phaseAngle),
            nuclearMagnitude: body.photometry?.nuclearMagnitude(sunDistanceAU: sunDistance, earthDistanceAU: earthDistance,
                                                                phaseAngle: phaseAngle),
            tailPositionAngle: antiSolarPositionAngle(toward: geometry.geometric, away: geometry.heliocentric))
    }

    /// The position angle in degrees, [0, 360), from celestial north through east, of the direction `away` seen from the
    /// direction `toward` (both J2000 equatorial); `nil` if the direction lies along the line of sight.
    static func antiSolarPositionAngle(toward: Vector3, away: Vector3) -> Double? {
        let line = toward.normalized
        let eastRaw = Vector3(-line.y, line.x, 0.0)
        let eastLength = eastRaw.length
        guard eastLength > 1e-12 else { return nil }
        let east = eastRaw / eastLength
        let north = line.cross(east)
        let direction = away.normalized
        let towardsEast = direction.dot(east)
        let towardsNorth = direction.dot(north)
        guard (towardsEast * towardsEast + towardsNorth * towardsNorth).squareRoot() > 1e-9 else { return nil }
        return AstroMath.normalizeDegrees(AstroMath.atan2Deg(towardsEast, towardsNorth))
    }

    /// The angle of the anti-solar direction (the tail) against the vertical in the sky seen from the observer of
    /// `frame`, in degrees, (−180, 180]: 0° means the tail points straight up, +90° to the observer's right when facing
    /// the body, 180° straight down. Meant for framing: tilt the camera by this angle to put the tail along an image
    /// axis. Parallax is included; refraction is not. `nil` at the zenith or when the tail points along the line of
    /// sight.
    public static func tailAngleFromVertical(of state: SmallBodyState, in frame: SkyFrame) -> Double? {
        let topocentric = frame.precessionNutationMatrix * state.geocentricJ2000 - frame.observerPositionOfDate
        let direction = (frame.equatorialOfDateToHorizontal * topocentric).normalized
        let tail = (frame.equatorialOfDateToHorizontal * (frame.precessionNutationMatrix * state.heliocentricJ2000)).normalized
        let upRaw = Vector3(0.0, 0.0, 1.0) - direction * direction.z
        let upLength = upRaw.length
        guard upLength > 1e-9 else { return nil }
        let up = upRaw / upLength
        let right = direction.cross(up)
        let projected = tail - direction * tail.dot(direction)
        let towardsRight = projected.dot(right)
        let towardsUp = projected.dot(up)
        guard (towardsRight * towardsRight + towardsUp * towardsUp).squareRoot() > 1e-9 else { return nil }
        return AstroMath.atan2Deg(towardsRight, towardsUp)
    }

    // MARK: Rise, transit and set

    /// The geometric altitude in degrees (topocentric, no refraction) of `body`'s centre for `observer` as a function of
    /// time, in the form `RiseSetCalculator`'s generic searches expect. It is `NaN` where the orbit cannot be evaluated.
    /// Each call builds a `SkyFrame` and one `state(of:at:)` worth of geometry (about 10 microseconds).
    public static func altitude(of body: SmallBody, observer: Observer) -> (Date) -> Double {
        { date in
            let frame = SkyFrame(date: date, observer: observer)
            guard let position = geocentricJ2000(of: body, at: frame.julianDate) else { return Double.nan }
            return frame.horizontal(geocentricJ2000: position, refraction: false).altitude
        }
    }

    /// The first rise, transit and set of `body` inside `interval` for `observer`, with the standard horizon altitude
    /// (`RiseSetCalculator.standardHorizonAltitude`). Samples the altitude every ten minutes and refines the crossings
    /// (about 150 evaluations per day plus the refinement; a few milliseconds).
    public static func riseTransitSet(of body: SmallBody, observer: Observer, within interval: DateInterval) -> RiseTransitSet {
        RiseSetCalculator.riseTransitSet(of: altitude(of: body, observer: observer),
                                         threshold: RiseSetCalculator.standardHorizonAltitude, within: interval)
    }

    /// All crossings of the standard horizon by `body` inside `interval`.
    public static func crossings(of body: SmallBody, observer: Observer, within interval: DateInterval) -> [AltitudeCrossing] {
        RiseSetCalculator.crossings(of: altitude(of: body, observer: observer),
                                    threshold: RiseSetCalculator.standardHorizonAltitude, within: interval)
    }

    /// All upper culminations of `body` inside `interval`.
    public static func upperCulminations(of body: SmallBody, observer: Observer, within interval: DateInterval) -> [AltitudeCulmination] {
        RiseSetCalculator.upperCulminations(of: altitude(of: body, observer: observer), within: interval)
    }
}

extension SkyFrame {
    /// The state of `body` at this frame's instant; `nil` if its orbit cannot be evaluated then.
    public func state(of body: SmallBody) -> SmallBodyState? {
        SmallBodyEphemeris.state(of: body, at: julianDate)
    }

    /// Topocentric horizontal coordinates of `body`'s centre, optionally including refraction; `nil` as for `state(of:)`.
    public func horizontal(of body: SmallBody, refraction: Bool = true) -> HorizontalCoordinate? {
        SmallBodyEphemeris.geocentricJ2000(of: body, at: julianDate).map { horizontal(geocentricJ2000: $0, refraction: refraction) }
    }

    /// Topocentric apparent right ascension and declination of `body` (true equator and equinox of date); `nil` as for `state(of:)`.
    public func topocentricEquatorial(of body: SmallBody) -> EquatorialCoordinate? {
        SmallBodyEphemeris.geocentricJ2000(of: body, at: julianDate).map { topocentricEquatorial(geocentricJ2000: $0) }
    }

    /// Geocentric apparent right ascension and declination of `body` (true equator and equinox of date); `nil` as for `state(of:)`.
    public func geocentricApparentEquatorial(of body: SmallBody) -> EquatorialCoordinate? {
        SmallBodyEphemeris.geocentricJ2000(of: body, at: julianDate).map {
            EquatorialCoordinate(vector: precessionNutationMatrix * $0)
        }
    }
}

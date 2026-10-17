import Foundation

/// Apparent positions and physical ephemerides of the Sun, the Moon and the planets.
///
/// Sources, all with light-time applied:
/// - **Sun and planets**: truncated VSOP87B series for the Earth and each planet
///   (`PlanetaryTheory`; a few arcseconds against JPL's DE440s).
/// - **Moon**: the truncated ELP-2000/82 series of Meeus, chapter 47 (`LunarTheory`; about 10″).
///
/// Times are `JulianDate`s; TT drives the theories, so a `JulianDate` built from a `Date` carries
/// the estimated ΔT.
public enum Ephemeris {
    /// Light-time per astronomical unit in days.
    static let lightTimePerAU = SkyFrame.kilometersPerAU / 299_792.458 / JulianDate.secondsPerDay

    /// The position, distance, phase and brightness of `body` at `julianDate`.
    public static func state(of body: SolarSystemBody, at julianDate: JulianDate) -> BodyState {
        let earth = EarthState(julianDate: julianDate)
        let eclipticFrame = EclipticOfDate(julianDate: julianDate)
        switch body {
        case .sun:
            let sun = sunGeometry(earth)
            return BodyState(body: .sun, julianDate: julianDate, geocentricJ2000: sun.apparent,
                             heliocentricDistanceAU: nil, elongation: nil, phaseAngle: nil,
                             apparentMagnitude: Photometry.sun(distanceAU: sun.apparent.length),
                             isWaxing: nil, ecliptic: eclipticFrame.coordinate(of: sun.apparent))
        case .moon:
            return moonState(earth, eclipticFrame: eclipticFrame)
        case .mercury:
            return planetState(.mercury, .mercury, earth, eclipticFrame: eclipticFrame)
        case .venus:
            return planetState(.venus, .venus, earth, eclipticFrame: eclipticFrame)
        case .mars:
            return planetState(.mars, .mars, earth, eclipticFrame: eclipticFrame)
        case .jupiter:
            return planetState(.jupiter, .jupiter, earth, eclipticFrame: eclipticFrame)
        case .saturn:
            return planetState(.saturn, .saturn, earth, eclipticFrame: eclipticFrame)
        case .uranus:
            return planetState(.uranus, .uranus, earth, eclipticFrame: eclipticFrame)
        case .neptune:
            return planetState(.neptune, .neptune, earth, eclipticFrame: eclipticFrame)
        }
    }

    /// The geocentric apparent position of `body` in AU, as `BodyState.geocentricJ2000`, without
    /// the physical quantities. Much cheaper than `state(of:at:)`.
    public static func geocentricJ2000(of body: SolarSystemBody, at julianDate: JulianDate) -> Vector3 {
        switch body {
        case .moon: return LunarTheory.geocentricJ2000(julianDate)
        case .sun: return sunGeometry(EarthState(julianDate: julianDate)).apparent
        case .mercury: return planetGeometry(.mercury, EarthState(julianDate: julianDate)).apparent
        case .venus: return planetGeometry(.venus, EarthState(julianDate: julianDate)).apparent
        case .mars: return planetGeometry(.mars, EarthState(julianDate: julianDate)).apparent
        case .jupiter: return planetGeometry(.jupiter, EarthState(julianDate: julianDate)).apparent
        case .saturn: return planetGeometry(.saturn, EarthState(julianDate: julianDate)).apparent
        case .uranus: return planetGeometry(.uranus, EarthState(julianDate: julianDate)).apparent
        case .neptune: return planetGeometry(.neptune, EarthState(julianDate: julianDate)).apparent
        }
    }

    /// The apparent geocentric ecliptic longitude of the Moon minus that of the Sun, in degrees,
    /// [0, 360): 0 at new moon, 90 at first quarter, 180 at full moon, 270 at last quarter.
    static func lunarElongation(at julianDate: JulianDate) -> Double {
        let eclipticFrame = EclipticOfDate(julianDate: julianDate)
        let moon = eclipticFrame.coordinate(of: LunarTheory.geocentricJ2000(julianDate)).longitude
        let sun = eclipticFrame.coordinate(of: sunGeometry(EarthState(julianDate: julianDate)).apparent).longitude
        return AstroMath.normalizeDegrees(moon - sun)
    }

    // MARK: Geometry

    /// The Earth's heliocentric position and orbital velocity at the observation time.
    private struct EarthState {
        let julianDate: JulianDate
        /// Heliocentric position in AU, J2000 equatorial.
        let position: Vector3
        /// Velocity divided by the speed of light, J2000 equatorial.
        let velocity: Vector3

        init(julianDate: JulianDate) {
            self.julianDate = julianDate
            self.position = PlanetaryTheory.heliocentricJ2000(.earth, julianDayTT: julianDate.tt)
            self.velocity = Aberration.earthVelocity(julianDate)
        }

        /// Applies annual aberration to a geocentric vector, preserving its length.
        func aberrated(_ vector: Vector3) -> Vector3 {
            Aberration.apply(to: vector.normalized, earthVelocity: velocity) * vector.length
        }
    }

    /// A body's position as seen from the Earth's centre (J2000 equatorial, AU).
    private struct Geometry {
        /// Direction and distance at the instant the light left the body, before aberration.
        let geometric: Vector3
        /// With annual aberration (identical to `geometric` for the Moon).
        let apparent: Vector3
        /// The body's position relative to the Sun when the light left it.
        let heliocentric: Vector3
    }

    private static func sunGeometry(_ earth: EarthState) -> Geometry {
        // The Sun hardly moves in the solar-system barycentric frame during the light-time, so its
        // astrometric direction is the instantaneous one; only aberration shifts it.
        let geometric = -earth.position
        return Geometry(geometric: geometric, apparent: earth.aberrated(geometric), heliocentric: .zero)
    }

    private static func moonGeometry(_ earth: EarthState) -> Geometry {
        let geometric = LunarTheory.geocentricJ2000(earth.julianDate)
        return Geometry(geometric: geometric, apparent: geometric, heliocentric: earth.position + geometric)
    }

    private static func planetGeometry(_ planet: PlanetaryTheory.Planet, _ earth: EarthState) -> Geometry {
        // Light-time: the planet is seen where it was `lightTime` ago, the Earth where it is now.
        var lightTime = 0.0
        var position = Vector3.zero
        for _ in 0..<4 {
            position = PlanetaryTheory.heliocentricJ2000(planet, julianDayTT: earth.julianDate.tt - lightTime)
            let updated = (position - earth.position).length * lightTimePerAU
            let converged = abs(updated - lightTime) < 2e-6
            lightTime = updated
            if converged { break }
        }
        let geometric = position - earth.position
        return Geometry(geometric: geometric, apparent: earth.aberrated(geometric), heliocentric: position)
    }

    // MARK: Assembling states

    private static func moonState(_ earth: EarthState, eclipticFrame: EclipticOfDate) -> BodyState {
        let moon = moonGeometry(earth)
        let sun = sunGeometry(earth)
        let phaseAngle = moon.heliocentric.angle(to: moon.geometric)
        let ecliptic = eclipticFrame.coordinate(of: moon.apparent)
        let sunLongitude = eclipticFrame.coordinate(of: sun.apparent).longitude
        return BodyState(
            body: .moon, julianDate: earth.julianDate, geocentricJ2000: moon.apparent,
            heliocentricDistanceAU: moon.heliocentric.length,
            elongation: moon.apparent.angle(to: sun.apparent), phaseAngle: phaseAngle,
            apparentMagnitude: Photometry.moon(sunDistance: moon.heliocentric.length,
                                               earthDistance: moon.geometric.length, phaseAngle: phaseAngle),
            isWaxing: AstroMath.normalizeDegrees(ecliptic.longitude - sunLongitude) < 180,
            ecliptic: ecliptic)
    }

    private static func planetState(_ body: SolarSystemBody, _ theory: PlanetaryTheory.Planet,
                                    _ earth: EarthState, eclipticFrame: EclipticOfDate) -> BodyState {
        let planet = planetGeometry(theory, earth)
        let sun = sunGeometry(earth)
        let phaseAngle = planet.heliocentric.angle(to: planet.geometric)
        return BodyState(
            body: body, julianDate: earth.julianDate, geocentricJ2000: planet.apparent,
            heliocentricDistanceAU: planet.heliocentric.length,
            elongation: planet.apparent.angle(to: sun.apparent), phaseAngle: phaseAngle,
            apparentMagnitude: Photometry.planet(body, heliocentric: planet.heliocentric,
                                                 geocentric: planet.geometric, phaseAngle: phaseAngle,
                                                 julianDate: earth.julianDate),
            isWaxing: nil, ecliptic: eclipticFrame.coordinate(of: planet.apparent))
    }

    /// Rotation from the J2000 mean equatorial frame to the ecliptic of date with the true equinox
    /// of date (precession, nutation, then the true obliquity).
    private struct EclipticOfDate {
        let matrix: Matrix3

        init(julianDate: JulianDate) {
            let nutation = Nutation(julianDate: julianDate)
            let meanObliquity = Obliquity.mean(julianDate)
            matrix = Matrix3.rotationX(-AstroMath.radians(meanObliquity + nutation.obliquity))
                * nutation.matrix(meanObliquity: meanObliquity)
                * Precession.matrixFromJ2000(to: julianDate)
        }

        func coordinate(of vector: Vector3) -> EclipticCoordinate {
            EclipticCoordinate(vector: matrix * vector)
        }
    }
}

extension SkyFrame {
    /// The state of `body` at this frame's instant.
    public func state(of body: SolarSystemBody) -> BodyState {
        Ephemeris.state(of: body, at: julianDate)
    }

    /// Topocentric horizontal coordinates of `body`'s centre, optionally including refraction.
    public func horizontal(of body: SolarSystemBody, refraction: Bool = true) -> HorizontalCoordinate {
        horizontal(geocentricJ2000: Ephemeris.geocentricJ2000(of: body, at: julianDate), refraction: refraction)
    }

    /// Topocentric apparent right ascension and declination of `body` (true equator and equinox of date).
    public func topocentricEquatorial(of body: SolarSystemBody) -> EquatorialCoordinate {
        topocentricEquatorial(geocentricJ2000: Ephemeris.geocentricJ2000(of: body, at: julianDate))
    }

    /// Geocentric apparent right ascension and declination of `body` (true equator and equinox of date).
    public func geocentricApparentEquatorial(of body: SolarSystemBody) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: precessionNutationMatrix * Ephemeris.geocentricJ2000(of: body, at: julianDate))
    }
}

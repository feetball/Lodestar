import Foundation

/// Jupiter's physical ephemeris for one instant.
public struct JupiterPhysicalState: Sendable, Hashable {
    /// Longitude of the System I central meridian (the equatorial belt, 9h 50m rotation) of the illuminated disc as
    /// seen from the Earth, degrees, [0, 360).
    public let systemILongitude: Double
    /// Longitude of the System II central meridian (the rest of the planet, 9h 55m rotation; the Great Red Spot's
    /// system), degrees, [0, 360).
    public let systemIILongitude: Double
    /// Planetocentric declination of the Earth, degrees (how far the equator is tilted towards us).
    public let earthDeclination: Double
    /// Planetocentric declination of the Sun, degrees.
    public let sunDeclination: Double
    /// Position angle of Jupiter's north rotation pole on the sky, degrees from celestial north through east, [0, 360).
    public let positionAngle: Double
    /// Geocentric distance of the planet in AU (light-time corrected).
    public let distanceAU: Double

    public init(systemILongitude: Double, systemIILongitude: Double, earthDeclination: Double, sunDeclination: Double,
                positionAngle: Double, distanceAU: Double) {
        self.systemILongitude = systemILongitude
        self.systemIILongitude = systemIILongitude
        self.earthDeclination = earthDeclination
        self.sunDeclination = sunDeclination
        self.positionAngle = positionAngle
        self.distanceAU = distanceAU
    }
}

/// The physical ephemeris of Jupiter, after Jean Meeus, *Astronomical Algorithms*, 2nd ed., chapter 43 (steps 1 to 18,
/// the more accurate of the book's two methods, which also gives the position angle): the rotation elements of the
/// planet (pole of 1950.0 with its precession, System I and II rotation rates), the light-time corrected geometry from
/// the kit's VSOP87 positions of the Earth and Jupiter, the phase correction, and the corrections for aberration and
/// nutation of the pole's direction.
///
/// Accuracy against the book's worked example (1992 December 16, 0h TD): the central meridians agree to 0.02°, the
/// declinations to 0.01° and the position angle to 0.03° (the book prints two decimals and uses the full VSOP87).
/// One call costs about 20 µs.
public enum JupiterPhysical {
    private static let epochJD = 2_433_282.5
    private static let systemIRate = 877.900_035_39
    /// System II's rotation rate in degrees per day.
    static let systemIIRate = 870.270_035_39
    private static let systemIPhaseDegreesPerAU = 5.070_33
    private static let systemIIPhaseDegreesPerAU = 5.026_26
    private static let aberrationConstant = 0.005_693

    /// The physical ephemeris of Jupiter at `julianDate` (its TT drives the theory).
    public static func state(at julianDate: JulianDate) -> JupiterPhysicalState {
        let jde = julianDate.tt
        // Steps 1 and 2: the pole (equinox 1950.0) and the rotation phases.
        let d = jde - epochJD
        let t1 = d / JulianDate.daysPerJulianCentury
        let alpha0 = AstroMath.radians(268.0 + 0.1061 * t1)
        let delta0 = AstroMath.radians(64.5 - 0.0164 * t1)
        let w1 = 17.710 + systemIRate * d
        let w2 = 16.838 + systemIIRate * d

        // Steps 3 to 7: heliocentric ecliptic positions of date, light-time of Jupiter, geocentric rectangular coordinates.
        let meanObliquity = Obliquity.mean(julianDate)
        let toEcliptic = Matrix3.rotationX(AstroMath.radians(meanObliquity)).transposed
            * Precession.matrixFromJ2000(to: julianDate)
        let earth = toEcliptic * Ephemeris.PlanetaryTheory.heliocentricJ2000(.earth, julianDayTT: jde)
        let earthDistance = earth.length
        let earthLongitude = atan2(earth.y, earth.x)
        var delta = 4.0
        var jupiter = Vector3.zero
        var geocentric = Vector3.zero
        for _ in 0..<4 {
            let lightTime = delta * Ephemeris.lightTimePerAU
            jupiter = toEcliptic * Ephemeris.PlanetaryTheory.heliocentricJ2000(.jupiter, julianDayTT: jde - lightTime)
            geocentric = jupiter - earth
            let updated = geocentric.length
            let converged = abs(updated - delta) < 1e-9
            delta = updated
            if converged { break }
        }
        let radius = jupiter.length
        let longitude = atan2(jupiter.y, jupiter.x)
        let latitude = atan2(jupiter.z, (jupiter.x * jupiter.x + jupiter.y * jupiter.y).squareRoot())

        // Steps 8 to 10: the Sun's declination seen from Jupiter.
        let epsilon0 = AstroMath.radians(meanObliquity)
        let sinEpsilon0 = sin(epsilon0)
        let cosEpsilon0 = cos(epsilon0)
        let sinLongitude = sin(longitude)
        let cosLongitude = cos(longitude)
        let sinLatitude = sin(latitude)
        let cosLatitude = cos(latitude)
        let alphaS = atan2(cosEpsilon0 * sinLongitude - sinEpsilon0 * sinLatitude / cosLatitude, cosLongitude)
        let deltaS = asin(cosEpsilon0 * sinLatitude + sinEpsilon0 * cosLatitude * sinLongitude)
        let sinDelta0 = sin(delta0)
        let cosDelta0 = cos(delta0)
        let sunTerm: Double = -sinDelta0 * sin(deltaS) - cosDelta0 * cos(deltaS) * cos(alpha0 - alphaS)
        let sunDeclination = asin(AstroMath.clamp(sunTerm, -1.0, 1.0))

        // Steps 11 to 13: the Earth's declination and the central meridians.
        let u = geocentric.y * cosEpsilon0 - geocentric.z * sinEpsilon0
        let v = geocentric.y * sinEpsilon0 + geocentric.z * cosEpsilon0
        var alpha = atan2(u, geocentric.x)
        var delta1 = atan(v / (geocentric.x * geocentric.x + u * u).squareRoot())
        let sinDelta = sin(delta1)
        let cosDelta = cos(delta1)
        let sinAlpha0Alpha = sin(alpha0 - alpha)
        let cosAlpha0Alpha = cos(alpha0 - alpha)
        let zeta = atan2(sinDelta0 * cosDelta * cosAlpha0Alpha - sinDelta * cosDelta0, cosDelta * sinAlpha0Alpha)
        let earthTerm: Double = -sinDelta0 * sinDelta - cosDelta0 * cosDelta * cosAlpha0Alpha
        let earthDeclination = asin(AstroMath.clamp(earthTerm, -1.0, 1.0))
        var omega1 = w1 - AstroMath.degrees(zeta) - systemIPhaseDegreesPerAU * delta
        var omega2 = w2 - AstroMath.degrees(zeta) - systemIIPhaseDegreesPerAU * delta

        // Step 14: the phase correction.
        let phaseNumerator: Double = 2 * radius * delta + earthDistance * earthDistance - radius * radius - delta * delta
        var phase = AstroMath.degrees(phaseNumerator / (4 * radius * delta))
        if sin(longitude - earthLongitude) < 0 { phase = -phase }
        omega1 += phase
        omega2 += phase

        // Steps 15 to 17: aberration and nutation of the direction of Jupiter and of the pole.
        let nutation = Nutation(julianDate: julianDate)
        let dPsi = AstroMath.radians(nutation.longitude)
        let dEpsilon = AstroMath.radians(nutation.obliquity)
        let epsilon = epsilon0 + dEpsilon
        let sinEpsilon = sin(epsilon)
        let cosEpsilon = cos(epsilon)
        let sinAlpha = sin(alpha)
        let cosAlpha = cos(alpha)
        let sinEarthLongitude = sin(earthLongitude)
        let cosEarthLongitude = cos(earthLongitude)
        let aberration = AstroMath.radians(aberrationConstant)
        let aberrationAlpha: Double = (cosAlpha * cosEarthLongitude * cosEpsilon + sinAlpha * sinEarthLongitude) / cosDelta
        let tanEpsilon: Double = sinEpsilon / cosEpsilon
        let aberrationInner: Double = tanEpsilon * cosDelta - sinAlpha * sinDelta
        let aberrationDelta: Double = cosEarthLongitude * cosEpsilon * aberrationInner
            + cosAlpha * sinDelta * sinEarthLongitude
        alpha += aberration * aberrationAlpha
        delta1 += aberration * aberrationDelta
        let tanDelta = sinDelta / cosDelta
        let deltaAlpha: Double = (cosEpsilon + sinEpsilon * sinAlpha * tanDelta) * dPsi - cosAlpha * tanDelta * dEpsilon
        let deltaDelta = sinEpsilon * cosAlpha * dPsi + sinAlpha * dEpsilon
        let alphaApparent = alpha + deltaAlpha
        let deltaApparent = delta1 + deltaDelta
        let sinAlpha0 = sin(alpha0)
        let cosAlpha0 = cos(alpha0)
        let tanDelta0 = sinDelta0 / cosDelta0
        let deltaAlpha0: Double = (cosEpsilon + sinEpsilon * sinAlpha0 * tanDelta0) * dPsi - cosAlpha0 * tanDelta0 * dEpsilon
        let deltaDelta0 = sinEpsilon * cosAlpha0 * dPsi + sinAlpha0 * dEpsilon
        let alpha0Apparent = alpha0 + deltaAlpha0
        let delta0Apparent = delta0 + deltaDelta0

        // Step 18: the position angle of the pole.
        let sinDeltaApparent = sin(deltaApparent)
        let cosDeltaApparent = cos(deltaApparent)
        let sinDelta0Apparent = sin(delta0Apparent)
        let cosDelta0Apparent = cos(delta0Apparent)
        let sinDifference = sin(alpha0Apparent - alphaApparent)
        let cosDifference = cos(alpha0Apparent - alphaApparent)
        let positionAngle = atan2(
            cosDelta0Apparent * sinDifference,
            sinDelta0Apparent * cosDeltaApparent - cosDelta0Apparent * sinDeltaApparent * cosDifference)
        return JupiterPhysicalState(
            systemILongitude: AstroMath.normalizeDegrees(omega1),
            systemIILongitude: AstroMath.normalizeDegrees(omega2),
            earthDeclination: AstroMath.degrees(earthDeclination),
            sunDeclination: AstroMath.degrees(sunDeclination),
            positionAngle: AstroMath.normalizeDegrees(AstroMath.degrees(positionAngle)),
            distanceAU: delta)
    }
}

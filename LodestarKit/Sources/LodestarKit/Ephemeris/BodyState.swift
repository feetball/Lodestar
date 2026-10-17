import Foundation

/// Position and physical appearance of a solar-system body at one instant, as seen from the
/// centre of the Earth.
public struct BodyState: Sendable, Hashable {
    /// The body this state describes.
    public let body: SolarSystemBody
    /// The instant of the state (TT drives the ephemeris, UT the Earth's rotation).
    public let julianDate: JulianDate

    /// Geocentric apparent position in AU, in the mean equatorial frame of J2000.0.
    ///
    /// Light-time is applied to every body. Annual aberration is applied to the Sun and the
    /// planets but not to the Moon: for the Moon it is cancelled to first order by the Earth's
    /// motion during the light-time, so the result is the Moon's geocentric direction one
    /// light-time ago. This is the input `SkyFrame.horizontal(geocentricJ2000:refraction:)` and
    /// `SkyFrame.topocentricEquatorial(geocentricJ2000:)` expect.
    public let geocentricJ2000: Vector3

    /// Geocentric distance in AU (light-time corrected).
    public let distanceAU: Double

    /// Distance from the Sun in AU; `nil` for the Sun itself.
    public let heliocentricDistanceAU: Double?

    /// Angular distance from the Sun in degrees, [0, 180]; `nil` for the Sun.
    public let elongation: Double?

    /// The Sun–body–Earth angle in degrees, [0, 180] (0° = fully lit); `nil` for the Sun.
    public let phaseAngle: Double?

    /// Fraction of the visible disc that is sunlit, [0, 1]; `nil` for the Sun.
    public let illuminatedFraction: Double?

    /// Apparent visual magnitude. The planets follow Mallama & Hilton (2018) and are good to a
    /// few hundredths of a magnitude (Mars to about 0.05, because its surface markings are not
    /// modelled); the Moon and the Sun are good to about 0.2 magnitude.
    public let apparentMagnitude: Double?

    /// Apparent angular diameter of the body's mean disc in arcseconds, as seen from the geocentre.
    public let angularDiameterArcseconds: Double

    /// For the Moon, whether it is waxing (east of the Sun: its ecliptic longitude exceeds the
    /// Sun's by less than 180°); `nil` for every other body.
    public let isWaxing: Bool?

    /// Apparent ecliptic longitude in degrees, [0, 360): geocentric, referred to the true equinox
    /// of date (includes nutation).
    public let eclipticLongitudeOfDate: Double

    /// Apparent ecliptic latitude in degrees, [-90, 90]: geocentric, referred to the ecliptic of date.
    public let eclipticLatitudeOfDate: Double

    /// Geocentric distance in kilometres.
    public var distanceKilometers: Double { distanceAU * SkyFrame.kilometersPerAU }

    init(body: SolarSystemBody, julianDate: JulianDate, geocentricJ2000: Vector3,
         heliocentricDistanceAU: Double?, elongation: Double?, phaseAngle: Double?,
         apparentMagnitude: Double?, isWaxing: Bool?, ecliptic: EclipticCoordinate) {
        let distance = geocentricJ2000.length
        self.body = body
        self.julianDate = julianDate
        self.geocentricJ2000 = geocentricJ2000
        self.distanceAU = distance
        self.heliocentricDistanceAU = heliocentricDistanceAU
        self.elongation = elongation
        self.phaseAngle = phaseAngle
        self.illuminatedFraction = phaseAngle.map { (1 + AstroMath.cosDeg($0)) / 2 }
        self.apparentMagnitude = apparentMagnitude
        let sine = AstroMath.clamp(body.meanRadiusKilometers / (distance * SkyFrame.kilometersPerAU), 0, 1)
        self.angularDiameterArcseconds = 2 * asin(sine) * AstroMath.arcsecondsPerRadian
        self.isWaxing = isWaxing
        self.eclipticLongitudeOfDate = ecliptic.longitude
        self.eclipticLatitudeOfDate = ecliptic.latitude
    }
}

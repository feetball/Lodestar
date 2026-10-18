import Foundation

/// Position and appearance of a comet or asteroid at one instant, as seen from the centre of the Earth; the counterpart
/// of `BodyState` for the planets. Instances are produced by `SmallBodyEphemeris.state(of:at:)`. Equality compares every field.
public struct SmallBodyState: Hashable, Sendable {
    /// The body this state describes.
    public let body: SmallBody
    /// The instant of the state.
    public let julianDate: JulianDate
    /// Geocentric apparent position in AU in the mean equatorial frame of J2000.0, with light-time and annual aberration
    /// applied exactly as for the planets: the input of `SkyFrame.horizontal(geocentricJ2000:refraction:)`.
    public let geocentricJ2000: Vector3
    /// The same position without aberration (what star charts and JPL Horizons' "astrometric" column show): the
    /// direction in which the body was when the light left it.
    public let astrometricJ2000: Vector3
    /// The position relative to the Sun when the light left the body, in AU, J2000 equatorial.
    public let heliocentricJ2000: Vector3
    /// The distance from the Earth Δ in AU (light-time corrected).
    public let distanceAU: Double
    /// The distance from the Sun r in AU.
    public let heliocentricDistanceAU: Double
    /// The angular distance from the Sun in degrees, [0, 180].
    public let elongation: Double
    /// The Sun–body–Earth angle in degrees, [0, 180].
    public let phaseAngle: Double
    /// The total magnitude of a comet or the visual magnitude of an asteroid; `nil` without magnitude parameters.
    public let apparentMagnitude: Double?
    /// The magnitude of the bare nucleus of a comet that has nuclear parameters; `nil` otherwise.
    public let nuclearMagnitude: Double?
    /// The position angle of the anti-solar direction at the body in degrees, [0, 360): the direction of the Sun-to-body
    /// line extended on the sky, measured from celestial north through east (J2000 equator). The ion tail of a comet
    /// points roughly this way; the dust tail curves from it towards the trail of the orbit. `nil` when the Sun-body
    /// line points at the Earth or away from it. The tail appears foreshortened by the factor `sin(phaseAngle)`.
    public let tailPositionAngle: Double?

    /// Assembles a state from the geometry.
    init(body: SmallBody, julianDate: JulianDate, astrometric: Vector3, apparent: Vector3, heliocentric: Vector3,
         elongation: Double, phaseAngle: Double, apparentMagnitude: Double?, nuclearMagnitude: Double?,
         tailPositionAngle: Double?) {
        self.body = body
        self.julianDate = julianDate
        self.geocentricJ2000 = apparent
        self.astrometricJ2000 = astrometric
        self.heliocentricJ2000 = heliocentric
        self.distanceAU = apparent.length
        self.heliocentricDistanceAU = heliocentric.length
        self.elongation = elongation
        self.phaseAngle = phaseAngle
        self.apparentMagnitude = apparentMagnitude
        self.nuclearMagnitude = nuclearMagnitude
        self.tailPositionAngle = tailPositionAngle
    }

    /// Geocentric distance in kilometres.
    public var distanceKilometers: Double { distanceAU * SkyFrame.kilometersPerAU }

    /// Whether the body is worth a photograph: its magnitude is known and at most `magnitudeLimit`, and it stands at
    /// least `minimumElongation` degrees from the Sun (closer in, twilight and glare hide it).
    public func isPhotographable(magnitudeLimit: Double = SmallBodyEphemeris.defaultMagnitudeLimit,
                                 minimumElongation: Double = SmallBodyEphemeris.defaultMinimumElongation) -> Bool {
        guard let magnitude = apparentMagnitude else { return false }
        return magnitude <= magnitudeLimit && elongation >= minimumElongation
    }
}

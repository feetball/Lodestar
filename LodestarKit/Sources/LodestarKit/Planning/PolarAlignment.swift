import Foundation

/// Where to find the pole star in a polar scope, for aligning an equatorial mount or star tracker.
///
/// The celestial pole is not marked by a star. Polaris (north) and σ Octantis (south) lie a fraction of a
/// degree from it and circle it once per sidereal day, so the pole is found by putting the star at the
/// right place on a clock face centred on the pole.
///
/// **Clock convention.** The reading describes the polar region as an observer sees it with the naked
/// eye while looking toward the pole, with the direction of the zenith at the top (12 o'clock):
/// - At upper culmination (hour angle 0°) the star is directly above the pole: 12:00.
/// - The sky turns around the pole once per sidereal day, 15° per hour. Seen facing north it turns
///   counter-clockwise, so in the northern hemisphere the star's clock angle is minus its hour angle:
///   six hours after upper culmination Polaris is at 9:00, after twelve hours at 6:00, after eighteen at 3:00.
/// - Seen facing south the sky turns clockwise, so in the southern hemisphere the clock angle equals the
///   hour angle: six hours after upper culmination σ Octantis is at 3:00.
/// - A polar scope is a small telescope and shows the field upside down. Its (`inverted`) reading is
///   the naked-eye reading turned through 180°, six hours further round the clock.
///
/// The star's place is its apparent place of date, so the reading includes precession, nutation,
/// aberration and proper motion.
public enum PolarAlignment {
    /// The hemisphere whose celestial pole is used.
    public enum Hemisphere: String, CaseIterable, Codable, Sendable {
        /// The north celestial pole, marked by Polaris.
        case north
        /// The south celestial pole, marked by σ Octantis.
        case south

        /// The hemisphere of a geographic latitude in degrees: the equator counts as north.
        public init(latitude: Double) {
            self = latitude < 0 ? .south : .north
        }
    }

    /// How the polar region is presented.
    public enum ScopeView: String, CaseIterable, Codable, Sendable {
        /// As seen by the naked eye looking toward the pole, zenith at the top.
        case naked
        /// As seen through a polar scope without an erecting prism: turned through 180°.
        case inverted
    }

    /// A pole star with its Hipparcos astrometry.
    struct ReferenceStar {
        let name: String
        let hipparcosNumber: Int
        /// ICRS position at J2000.0.
        let position: EquatorialCoordinate
        let properMotion: ProperMotion
    }

    /// Polaris, α Ursae Minoris, HIP 11767 (Hipparcos Catalogue, ESA 1997: ICRS epoch J1991.25 position
    /// carried to J2000.0 with its proper motion; μα* = +44.22, μδ = −11.74 mas/yr).
    static let polaris = ReferenceStar(
        name: "Polaris", hipparcosNumber: 11767,
        position: EquatorialCoordinate(rightAscension: 37.954_515_35, declination: 89.264_109_51),
        properMotion: ProperMotion(raMilliarcsecondsPerYear: 44.22, decMilliarcsecondsPerYear: -11.74))

    /// σ Octantis, HIP 104382 (Hipparcos Catalogue, ESA 1997: ICRS epoch J1991.25 position carried to
    /// J2000.0 with its proper motion; μα* = +25.96, μδ = +5.02 mas/yr).
    static let sigmaOctantis = ReferenceStar(
        name: "σ Octantis", hipparcosNumber: 104382,
        position: EquatorialCoordinate(rightAscension: 317.195_190_16, declination: -88.956_499_00),
        properMotion: ProperMotion(raMilliarcsecondsPerYear: 25.96, decMilliarcsecondsPerYear: 5.02))

    /// Where the pole star of `hemisphere` stands relative to the pole at the instant of `frame`.
    ///
    /// - Parameters:
    ///   - frame: The instant and observer.
    ///   - hemisphere: Which pole to align on.
    ///   - view: Whether the reading is for the naked eye or an inverting polar scope.
    public static func polarScopeReading(frame: SkyFrame, hemisphere: Hemisphere,
                                         view: ScopeView = .naked) -> PolarScopeReading {
        let star = hemisphere == .north ? polaris : sigmaOctantis
        let apparent = frame.apparentPlace(j2000: star.position, properMotion: star.properMotion)
        let hourAngle = frame.hourAngle(apparentRightAscension: apparent.rightAscension)
        let pole = frame.horizontalOfCelestialPole(north: hemisphere == .north, refraction: false)
        let nakedEyeAngle = hemisphere == .north ? -hourAngle : hourAngle
        return PolarScopeReading(
            referenceStarName: star.name, hipparcosNumber: star.hipparcosNumber,
            hemisphere: hemisphere, view: view, hourAngle: hourAngle,
            separationFromPole: apparent.unitVector.angle(to: Vector3(0, 0, hemisphere == .north ? 1 : -1)),
            angle: AstroMath.normalizeDegrees(view == .inverted ? nakedEyeAngle + 180 : nakedEyeAngle),
            poleAltitude: pole.altitude, poleAzimuth: pole.azimuth)
    }

    /// The reading for the hemisphere of the frame's observer (north on or above the equator).
    public static func polarScopeReading(frame: SkyFrame, view: ScopeView = .naked) -> PolarScopeReading {
        polarScopeReading(frame: frame, hemisphere: Hemisphere(latitude: frame.observer.location.latitude), view: view)
    }
}

/// The place of the pole star on a polar-scope clock face.
///
/// See `PolarAlignment` for the clock convention.
public struct PolarScopeReading: Sendable, Hashable {
    /// "Polaris" or "σ Octantis".
    public let referenceStarName: String
    /// The star's Hipparcos catalogue number: 11767 or 104382.
    public let hipparcosNumber: Int
    /// The pole the reading refers to.
    public let hemisphere: PolarAlignment.Hemisphere
    /// Whether `angle` is for the naked eye or for an inverting polar scope.
    public let view: PolarAlignment.ScopeView
    /// The star's local hour angle in degrees, (−180, 180]: positive once it has passed upper culmination.
    public let hourAngle: Double
    /// The angular distance of the star from the celestial pole of date in degrees, about 0.63° for
    /// Polaris and 1.15° for σ Octantis in 2026 (the pole is drawing closer to Polaris and away from σ Octantis).
    public let separationFromPole: Double
    /// The star's direction from the pole in degrees, [0, 360), clockwise from 12 o'clock as drawn.
    public let angle: Double
    /// The altitude of the celestial pole of date in degrees: the latitude to set on the mount's
    /// scale. It is geometric; refraction raises the apparent pole by about a minute of arc at mid-latitudes.
    public let poleAltitude: Double
    /// The azimuth of the celestial pole in degrees: 0° (north) for the north pole, 180° for the south pole.
    public let poleAzimuth: Double

    /// The clock hour of `angle`, [0, 12): 0 is 12 o'clock and 10.5 is 10:30.
    public var clockPosition: Double { angle / 30 }

    /// Creates a reading.
    public init(referenceStarName: String, hipparcosNumber: Int, hemisphere: PolarAlignment.Hemisphere,
                view: PolarAlignment.ScopeView, hourAngle: Double, separationFromPole: Double, angle: Double,
                poleAltitude: Double, poleAzimuth: Double) {
        self.referenceStarName = referenceStarName
        self.hipparcosNumber = hipparcosNumber
        self.hemisphere = hemisphere
        self.view = view
        self.hourAngle = hourAngle
        self.separationFromPole = separationFromPole
        self.angle = angle
        self.poleAltitude = poleAltitude
        self.poleAzimuth = poleAzimuth
    }
}

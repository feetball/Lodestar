import Foundation

/// The equatorial reference frame in which a mount takes and reports coordinates.
///
/// The engine's places are J2000. Most amateur mounts expect "JNow"; what that means exactly is not standardised, so
/// two variants are offered. They differ by nutation and annual aberration, at most about 0.01° (40″), far below the
/// pointing accuracy of any GoTo mount.
public enum MountEpoch: String, CaseIterable, Codable, Hashable, Sendable {
    /// Mean equator and equinox of J2000.0: the catalog place, with proper motion applied to the date.
    case j2000
    /// Mean equator and equinox of date ("JNow" as planetarium programs usually send it): the J2000 place precessed to
    /// the date. No nutation, no aberration.
    case meanOfDate
    /// True equator and equinox of date, geocentric (the "local topocentric" coordinates of ASCOM): precession,
    /// nutation and annual aberration applied, as `SkyFrame.apparentPlace` computes it.
    case apparentOfDate

    /// The place a mount using this frame calls the J2000 place `j2000`, at the instant of `frame`.
    /// Proper motion, if given, moves the place from J2000 to the date first.
    public func fromJ2000(_ j2000: EquatorialCoordinate, frame: SkyFrame, properMotion: ProperMotion? = nil) -> EquatorialCoordinate {
        switch self {
        case .j2000:
            return properMotion?.apply(to: j2000, years: frame.yearsSinceJ2000) ?? j2000
        case .meanOfDate:
            let moved = properMotion?.applyToUnitVector(of: j2000, years: frame.yearsSinceJ2000) ?? j2000.unitVector
            return EquatorialCoordinate(vector: frame.precessionMatrix * moved)
        case .apparentOfDate:
            return frame.apparentPlace(j2000: j2000, properMotion: properMotion)
        }
    }

    /// The J2000 place of the position `mount` in this frame, at the instant of `frame` (the inverse of `fromJ2000`).
    public func toJ2000(_ mount: EquatorialCoordinate, frame: SkyFrame) -> EquatorialCoordinate {
        switch self {
        case .j2000:
            return mount
        case .meanOfDate:
            return EquatorialCoordinate(vector: frame.precessionMatrix.transposed * mount.unitVector)
        case .apparentOfDate:
            return EquatorialCoordinate(
                vector: Aberration.remove(from: frame.precessionNutationMatrix.transposed * mount.unitVector,
                                          earthVelocity: frame.earthVelocity))
        }
    }
}

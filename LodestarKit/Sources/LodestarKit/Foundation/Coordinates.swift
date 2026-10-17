import Foundation

/// Right ascension and declination, both in degrees.
///
/// The frame (J2000 mean, or true equator and equinox of date) is implied by the API that
/// produces or consumes the value.
public struct EquatorialCoordinate: Hashable, Codable, Sendable {
    /// Right ascension in degrees, [0, 360).
    public let rightAscension: Double
    /// Declination in degrees, [-90, 90].
    public let declination: Double

    public init(rightAscension: Double, declination: Double) {
        self.rightAscension = AstroMath.normalizeDegrees(rightAscension)
        self.declination = AstroMath.clamp(declination, -90, 90)
    }

    public init(rightAscensionHours: Double, declination: Double) {
        self.init(rightAscension: rightAscensionHours * 15, declination: declination)
    }

    /// Creates the coordinate pointing along `vector` (any non-zero length).
    /// A zero vector yields (0°, 0°).
    public init(vector: Vector3) {
        let r = vector.length
        guard r > 0 else {
            self.init(rightAscension: 0, declination: 0)
            return
        }
        self.init(rightAscension: AstroMath.atan2Deg(vector.y, vector.x),
                  declination: AstroMath.asinDeg(vector.z / r))
    }

    /// Right ascension in hours, [0, 24).
    public var rightAscensionHours: Double { rightAscension / 15 }

    /// Unit vector: x towards the equinox, z towards the north celestial pole.
    public var unitVector: Vector3 {
        let cd = AstroMath.cosDeg(declination)
        return Vector3(cd * AstroMath.cosDeg(rightAscension),
                       cd * AstroMath.sinDeg(rightAscension),
                       AstroMath.sinDeg(declination))
    }

    /// Great-circle separation in degrees.
    public func angularSeparation(to other: EquatorialCoordinate) -> Double {
        unitVector.angle(to: other.unitVector)
    }
}

/// Azimuth and altitude in degrees for an observer on the Earth's surface.
///
/// Azimuth is measured from true north towards east, [0, 360). The matching vector form is the
/// local East–North–Up (ENU) frame: x = East, y = North, z = Up.
public struct HorizontalCoordinate: Hashable, Codable, Sendable {
    /// Azimuth in degrees from north through east, [0, 360).
    public let azimuth: Double
    /// Altitude above the horizon in degrees, [-90, 90].
    public let altitude: Double

    public init(azimuth: Double, altitude: Double) {
        self.azimuth = AstroMath.normalizeDegrees(azimuth)
        self.altitude = AstroMath.clamp(altitude, -90, 90)
    }

    /// Creates the coordinate pointing along an ENU `vector` (any non-zero length).
    /// A zero vector yields (0°, 0°). At the zenith/nadir the azimuth is 0°.
    public init(vector: Vector3) {
        let r = vector.length
        guard r > 0 else {
            self.init(azimuth: 0, altitude: 0)
            return
        }
        let horizontal = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        let azimuth = horizontal > 0 ? AstroMath.atan2Deg(vector.x, vector.y) : 0
        self.init(azimuth: azimuth, altitude: AstroMath.asinDeg(vector.z / r))
    }

    /// Unit vector in the ENU frame.
    public var unitVector: Vector3 {
        let ca = AstroMath.cosDeg(altitude)
        return Vector3(ca * AstroMath.sinDeg(azimuth),
                       ca * AstroMath.cosDeg(azimuth),
                       AstroMath.sinDeg(altitude))
    }

    /// Great-circle separation in degrees.
    public func angularSeparation(to other: HorizontalCoordinate) -> Double {
        unitVector.angle(to: other.unitVector)
    }
}

/// Ecliptic longitude and latitude in degrees.
public struct EclipticCoordinate: Hashable, Codable, Sendable {
    /// Ecliptic longitude in degrees, [0, 360).
    public let longitude: Double
    /// Ecliptic latitude in degrees, [-90, 90].
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = AstroMath.normalizeDegrees(longitude)
        self.latitude = AstroMath.clamp(latitude, -90, 90)
    }

    /// Creates the coordinate pointing along `vector` (any non-zero length).
    public init(vector: Vector3) {
        let r = vector.length
        guard r > 0 else {
            self.init(longitude: 0, latitude: 0)
            return
        }
        self.init(longitude: AstroMath.atan2Deg(vector.y, vector.x),
                  latitude: AstroMath.asinDeg(vector.z / r))
    }

    /// Unit vector: x towards the equinox, z towards the north ecliptic pole.
    public var unitVector: Vector3 {
        let cb = AstroMath.cosDeg(latitude)
        return Vector3(cb * AstroMath.cosDeg(longitude),
                       cb * AstroMath.sinDeg(longitude),
                       AstroMath.sinDeg(latitude))
    }
}

/// Galactic longitude and latitude in degrees (IAU 1958 system, as realised by Hipparcos).
public struct GalacticCoordinate: Hashable, Codable, Sendable {
    /// Galactic longitude in degrees, [0, 360); 0° points to the galactic centre.
    public let longitude: Double
    /// Galactic latitude in degrees, [-90, 90].
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = AstroMath.normalizeDegrees(longitude)
        self.latitude = AstroMath.clamp(latitude, -90, 90)
    }

    /// Creates the coordinate pointing along `vector` (any non-zero length).
    public init(vector: Vector3) {
        let ecliptic = EclipticCoordinate(vector: vector)
        self.init(longitude: ecliptic.longitude, latitude: ecliptic.latitude)
    }

    /// Unit vector: x towards the galactic centre, z towards the north galactic pole.
    public var unitVector: Vector3 {
        EclipticCoordinate(longitude: longitude, latitude: latitude).unitVector
    }
}

/// A place on the Earth: geodetic latitude/longitude in degrees and elevation in metres.
public struct GeographicLocation: Hashable, Codable, Sendable {
    public static let elevationRange: ClosedRange<Double> = -1_000...12_000

    /// Geodetic latitude in degrees, north positive, [-90, 90].
    public let latitude: Double
    /// Longitude in degrees, east positive, (-180, 180].
    public let longitude: Double
    /// Height above sea level in metres.
    public let elevation: Double

    /// Creates a location, clamping the latitude, wrapping the longitude and clamping the
    /// elevation into range. Non-finite components become 0. Use `validated` for user input.
    public init(latitude: Double, longitude: Double, elevation: Double = 0) {
        self.latitude = latitude.isFinite ? AstroMath.clamp(latitude, -90, 90) : 0
        self.longitude = longitude.isFinite ? AstroMath.normalizeSignedDegrees(longitude) : 0
        self.elevation = elevation.isFinite
            ? AstroMath.clamp(elevation, Self.elevationRange.lowerBound, Self.elevationRange.upperBound)
            : 0
    }

    /// Returns a location only if every component is finite and in range
    /// (latitude [-90, 90], longitude [-180, 360], elevation within `elevationRange`).
    public static func validated(latitude: Double, longitude: Double, elevation: Double = 0) -> GeographicLocation? {
        guard latitude.isFinite, longitude.isFinite, elevation.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...360.0).contains(longitude),
              elevationRange.contains(elevation) else { return nil }
        return GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation)
    }
}

/// Conversions between the classical spherical coordinate systems.
public enum CoordinateTransforms {
    /// Ecliptic → equatorial for the given obliquity (degrees).
    public static func eclipticToEquatorial(_ ecliptic: EclipticCoordinate, obliquity: Double) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: Matrix3.rotationX(AstroMath.radians(obliquity)) * ecliptic.unitVector)
    }

    /// Equatorial → ecliptic for the given obliquity (degrees).
    public static func equatorialToEcliptic(_ equatorial: EquatorialCoordinate, obliquity: Double) -> EclipticCoordinate {
        EclipticCoordinate(vector: Matrix3.rotationX(-AstroMath.radians(obliquity)) * equatorial.unitVector)
    }

    /// Local hour angle and declination → horizontal coordinates (degrees).
    public static func equatorialToHorizontal(hourAngle: Double, declination: Double, latitude: Double) -> HorizontalCoordinate {
        HorizontalCoordinate(vector: localEquatorialToHorizontal(latitude: latitude)
            * localEquatorialVector(hourAngle: hourAngle, declination: declination))
    }

    /// Horizontal coordinates → local hour angle and declination (degrees).
    public static func horizontalToEquatorial(_ horizontal: HorizontalCoordinate,
                                              latitude: Double) -> (hourAngle: Double, declination: Double) {
        let local = localEquatorialToHorizontal(latitude: latitude).transposed * horizontal.unitVector
        let hourAngle = AstroMath.normalizeSignedDegrees(AstroMath.atan2Deg(-local.y, local.x))
        return (hourAngle, AstroMath.asinDeg(local.z))
    }

    /// Unit vector in the local equatorial frame: x towards the meridian on the equator
    /// (hour angle 0), y towards hour angle −6h (east), z towards the celestial pole.
    static func localEquatorialVector(hourAngle: Double, declination: Double) -> Vector3 {
        let cd = AstroMath.cosDeg(declination)
        return Vector3(cd * AstroMath.cosDeg(hourAngle),
                       -cd * AstroMath.sinDeg(hourAngle),
                       AstroMath.sinDeg(declination))
    }

    /// Rotation from the local equatorial frame (see `localEquatorialVector`) to ENU.
    static func localEquatorialToHorizontal(latitude: Double) -> Matrix3 {
        let sp = AstroMath.sinDeg(latitude), cp = AstroMath.cosDeg(latitude)
        return Matrix3(rows: Vector3(0, 1, 0),
                       Vector3(-sp, 0, cp),
                       Vector3(cp, 0, sp))
    }

    /// Rotation from J2000 (ICRS) equatorial to galactic coordinates (Hipparcos, vol. 1, §1.5.3).
    public static let equatorialJ2000ToGalacticMatrix = Matrix3(
        rows: Vector3(-0.054_875_560_416_215_4, -0.873_437_090_234_885_0, -0.483_835_015_548_713_2),
        Vector3(0.494_109_427_875_583_7, -0.444_829_629_960_011_2, 0.746_982_244_497_218_9),
        Vector3(-0.867_666_149_019_004_7, -0.198_076_373_431_201_5, 0.455_983_776_175_066_9))

    /// J2000 equatorial → galactic coordinates.
    public static func equatorialJ2000ToGalactic(_ equatorial: EquatorialCoordinate) -> GalacticCoordinate {
        GalacticCoordinate(vector: equatorialJ2000ToGalacticMatrix * equatorial.unitVector)
    }

    /// Galactic → J2000 equatorial coordinates.
    public static func galacticToEquatorialJ2000(_ galactic: GalacticCoordinate) -> EquatorialCoordinate {
        EquatorialCoordinate(vector: equatorialJ2000ToGalacticMatrix.transposed * galactic.unitVector)
    }
}

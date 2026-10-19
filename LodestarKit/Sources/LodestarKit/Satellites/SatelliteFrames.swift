import Foundation

/// Reference frames for satellites: SGP4's TEME frame, the Earth-fixed frame, the observer's horizon frame, and
/// the Sun's position in TEME.
///
/// **TEME to Earth-fixed.** SGP4 works in TEME (true equator, mean equinox of date). The Earth-fixed frame used
/// here is the pseudo-Earth-fixed frame, reached by turning TEME about the polar axis by Greenwich *mean* sidereal
/// time (the IAU-82 expression of the reference code) with UT1 taken as UTC. Polar motion (below 0.3″, about
/// 10 m at low-orbit distances) and UT1 - UTC (below 0.9 s, up to 0.004° of rotation) are ignored; both are far
/// below the accuracy of the elements.
///
/// **Observer.** Geodetic latitude, longitude and height on the WGS-84 ellipsoid become Earth-fixed coordinates;
/// azimuth is measured from north towards east and altitude from the local horizontal plane (the ellipsoid
/// normal, so geodetic latitude is the right one). No refraction, light time or aberration is applied: for a
/// satellite they are below 0.01°.
///
/// **Sun.** The apparent geocentric position from the engine's ephemeris, rotated to TEME with precession,
/// nutation and the equation of the equinoxes.
public enum SatelliteFrames {
    /// WGS-84 equatorial radius in kilometres.
    public static let earthEquatorialRadiusKilometers = 6378.137
    /// WGS-84 flattening.
    public static let earthFlattening = 1.0 / 298.257223563
    /// Earth's rotation rate in radians per second (the value the SGP4 reference code uses for TEME to ECEF).
    public static let earthRotationRate = 7.29211514670698e-5
    /// Julian Date of the Foundation reference date, 2001-01-01T00:00:00Z.
    static let referenceDateJulianDate = 2_451_910.5

    /// Greenwich mean sidereal time at `date`, radians in [0, 2π) (UT1 taken as UTC).
    public static func greenwichMeanSiderealTime(at date: Date) -> Double {
        Sgp4Time.greenwichSiderealTime(julianDateUt(date.timeIntervalSinceReferenceDate))
    }

    /// Julian Date (UT) of a time given as seconds since the Foundation reference date.
    static func julianDateUt(_ referenceSeconds: Double) -> Double {
        referenceDateJulianDate + referenceSeconds / JulianDate.secondsPerDay
    }

    /// Turns a TEME state into the Earth-fixed frame at `date`: the position is rotated about the pole by the
    /// sidereal angle, the velocity is the velocity relative to the rotating Earth (the inertial velocity rotated,
    /// minus ω × r).
    public static func earthFixedState(of state: TemeState, at date: Date) -> TemeState {
        let angle = greenwichMeanSiderealTime(at: date)
        let c = cos(angle)
        let s = sin(angle)
        let r = state.position
        let v = state.velocity
        let x = c * r.x + s * r.y
        let y = -s * r.x + c * r.y
        return TemeState(
            position: Vector3(x, y, r.z),
            velocity: Vector3(c * v.x + s * v.y + earthRotationRate * y, -s * v.x + c * v.y - earthRotationRate * x, v.z)
        )
    }

    /// The Earth-fixed position of a place on the WGS-84 ellipsoid, in kilometres.
    public static func earthFixedPosition(of location: GeographicLocation) -> Vector3 {
        let latitude = AstroMath.radians(location.latitude)
        let longitude = AstroMath.radians(location.longitude)
        let height = location.elevation / 1000.0
        let eccentricitySquared = earthFlattening * (2.0 - earthFlattening)
        let sinLatitude = sin(latitude)
        let primeVertical = earthEquatorialRadiusKilometers / (1.0 - eccentricitySquared * sinLatitude * sinLatitude).squareRoot()
        return Vector3(
            (primeVertical + height) * cos(latitude) * cos(longitude),
            (primeVertical + height) * cos(latitude) * sin(longitude),
            (primeVertical * (1.0 - eccentricitySquared) + height) * sinLatitude
        )
    }

    /// The Sun's geocentric apparent position in TEME at `date`, in kilometres (about 1.5e8 long): the engine's
    /// apparent place rotated with precession, nutation and the equation of the equinoxes.
    public static func sunPosition(at date: Date) -> Vector3 {
        SatelliteSunTrack.exact(date.timeIntervalSinceReferenceDate)
    }

    /// Where the satellite is in the sky: the TEME `state` at `date` seen from `observer`.
    ///
    /// - Returns: azimuth and geometric altitude in degrees, the range in kilometres and the range rate in
    ///   kilometres per second (positive when the satellite recedes).
    public static func look(at state: TemeState, date: Date, observer: Observer) -> SatelliteDirection {
        let geometry = SatelliteObserverGeometry(observer: observer)
        let r = state.position
        let v = state.velocity
        let sample = geometry.look(
            r.x, r.y, r.z, v.x, v.y, v.z,
            Sgp4Time.greenwichSiderealTime(julianDateUt(date.timeIntervalSinceReferenceDate))
        )
        return SatelliteDirection(
            azimuth: sample.azimuth,
            altitude: sample.altitude,
            rangeKilometers: sample.range,
            rangeRateKilometersPerSecond: sample.rangeRate
        )
    }
}

/// A satellite's direction and distance from an observer.
public struct SatelliteDirection: Hashable, Sendable {
    /// Azimuth in degrees from north through east, [0, 360).
    public let azimuth: Double
    /// Geometric altitude in degrees (no refraction), [-90, 90].
    public let altitude: Double
    /// Distance from the observer in kilometres.
    public let rangeKilometers: Double
    /// Rate of change of the range in kilometres per second.
    public let rangeRateKilometersPerSecond: Double

    public init(azimuth: Double, altitude: Double, rangeKilometers: Double, rangeRateKilometersPerSecond: Double) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.rangeKilometers = rangeKilometers
        self.rangeRateKilometersPerSecond = rangeRateKilometersPerSecond
    }

    /// The direction as a horizontal coordinate.
    public var horizontal: HorizontalCoordinate { HorizontalCoordinate(azimuth: azimuth, altitude: altitude) }

    /// The direction as an ENU unit vector (x east, y north, z up).
    public var unitVector: Vector3 { horizontal.unitVector }
}

/// A satellite relative to an observer in the observer's East-North-Up frame.
struct SatelliteTopocentric: Sendable {
    let east: Double
    let north: Double
    let up: Double
    let range: Double
    let rangeRate: Double
    /// Speed relative to the rotating Earth in kilometres per second.
    let relativeSpeed: Double

    /// Geometric altitude in degrees.
    var altitude: Double { AstroMath.atan2Deg(up, (east * east + north * north).squareRoot()) }

    /// Azimuth in degrees, [0, 360).
    var azimuth: Double {
        if east == 0.0 && north == 0.0 { return 0.0 }
        return AstroMath.normalizeDegrees(AstroMath.atan2Deg(east, north))
    }
}

/// The observer's Earth-fixed position and local East-North-Up axes. Immutable.
struct SatelliteObserverGeometry: Sendable {
    let observer: Observer
    let x: Double
    let y: Double
    let z: Double
    let eastX: Double
    let eastY: Double
    let northX: Double
    let northY: Double
    let northZ: Double
    let upX: Double
    let upY: Double
    let upZ: Double

    init(observer: Observer) {
        self.observer = observer
        let position = SatelliteFrames.earthFixedPosition(of: observer.location)
        x = position.x
        y = position.y
        z = position.z
        let latitude = AstroMath.radians(observer.location.latitude)
        let longitude = AstroMath.radians(observer.location.longitude)
        let sinLatitude = sin(latitude)
        let cosLatitude = cos(latitude)
        let sinLongitude = sin(longitude)
        let cosLongitude = cos(longitude)
        eastX = -sinLongitude
        eastY = cosLongitude
        northX = -sinLatitude * cosLongitude
        northY = -sinLatitude * sinLongitude
        northZ = cosLatitude
        upX = cosLatitude * cosLongitude
        upY = cosLatitude * sinLongitude
        upZ = sinLatitude
    }

    /// The satellite with TEME position (rx, ry, rz) km and velocity (vx, vy, vz) km/s, seen from the observer,
    /// for Greenwich mean sidereal time `gmst` (radians).
    func look(_ rx: Double, _ ry: Double, _ rz: Double, _ vx: Double, _ vy: Double, _ vz: Double, _ gmst: Double) -> SatelliteTopocentric {
        let c = cos(gmst)
        let s = sin(gmst)
        let ex = c * rx + s * ry
        let ey = -s * rx + c * ry
        let dx = ex - x
        let dy = ey - y
        let dz = rz - z
        let east = eastX * dx + eastY * dy
        let north = northX * dx + northY * dy + northZ * dz
        let up = upX * dx + upY * dy + upZ * dz
        let range = (dx * dx + dy * dy + dz * dz).squareRoot()
        // Velocity relative to the rotating Earth.
        let wx = c * vx + s * vy + SatelliteFrames.earthRotationRate * ey
        let wy = -s * vx + c * vy - SatelliteFrames.earthRotationRate * ex
        let rangeRate = (dx * wx + dy * wy + dz * vz) / range
        return SatelliteTopocentric(
            east: east, north: north, up: up, range: range, rangeRate: rangeRate,
            relativeSpeed: (wx * wx + wy * wy + vz * vz).squareRoot()
        )
    }

    /// The ENU unit vector towards a TEME direction (x, y, z not necessarily normalized) at sidereal angle `gmst`.
    func directionOf(_ tx: Double, _ ty: Double, _ tz: Double, _ gmst: Double) -> Vector3 {
        let c = cos(gmst)
        let s = sin(gmst)
        let ex = c * tx + s * ty
        let ey = -s * tx + c * ty
        let length = (ex * ex + ey * ey + tz * tz).squareRoot()
        return Vector3(
            (eastX * ex + eastY * ey) / length,
            (northX * ex + northY * ey + northZ * tz) / length,
            (upX * ex + upY * ey + upZ * tz) / length
        )
    }
}

/// The Sun's TEME position, exactly for one instant or interpolated over an interval: the engine's ephemeris is
/// evaluated at hourly nodes and a cubic Lagrange polynomial gives the values in between (the Sun moves 0.04° an
/// hour; the interpolation error is far below a milliarcsecond). Times are seconds since the Foundation
/// reference date. Immutable.
struct SatelliteSunTrack: Sendable {
    /// Seconds between nodes.
    static let spacing = 3_600.0
    /// The most nodes a track holds (about 200 days).
    static let maximumNodeCount = 5_000

    private let origin: Double
    private let nodes: [Vector3]

    private init(origin: Double, nodes: [Vector3]) {
        self.origin = origin
        self.nodes = nodes
    }

    /// The Sun's TEME position at `time` in kilometres (the time should lie in the interval given to `create`).
    func position(_ time: Double) -> Vector3 {
        let scaled = ((time - origin) / Self.spacing).rounded(.down)
        let raw = scaled.isFinite ? Int(min(max(scaled, -1.0e6), 1.0e6)) : 0
        let base = min(max(raw, 1), nodes.count - 3)
        let u = (time - origin) / Self.spacing - Double(base)
        let w0 = -u * (u - 1) * (u - 2) / 6
        let w1 = (u + 1) * (u - 1) * (u - 2) / 2
        let w2 = -(u + 1) * u * (u - 2) / 2
        let w3 = (u + 1) * u * (u - 1) / 6
        let n0 = nodes[base - 1]
        let n1 = nodes[base]
        let n2 = nodes[base + 1]
        let n3 = nodes[base + 2]
        return Vector3(
            n0.x * w0 + n1.x * w1 + n2.x * w2 + n3.x * w3,
            n0.y * w0 + n1.y * w1 + n2.y * w2 + n3.y * w3,
            n0.z * w0 + n1.z * w1 + n2.z * w2 + n3.z * w3
        )
    }

    /// The track for `[start, end]` (seconds since the reference date).
    static func create(start: Double, end: Double) -> SatelliteSunTrack {
        let from = start.isFinite ? start : 0.0
        let to = end.isFinite ? max(end, from) : from
        let first = (from / spacing).rounded(.down) * spacing - spacing
        let last = (to / spacing).rounded(.up) * spacing + 2 * spacing
        let count = min(max(5, Int(min((last - first) / spacing, Double(maximumNodeCount))) + 1), maximumNodeCount)
        let nodes = (0..<count).map { exact(first + Double($0) * spacing) }
        return SatelliteSunTrack(origin: first, nodes: nodes)
    }

    /// The Sun's TEME position at `time` in kilometres, from the ephemeris.
    static func exact(_ time: Double) -> Vector3 {
        let jd = JulianDate(date: Date(timeIntervalSinceReferenceDate: time))
        let sunJ2000 = Ephemeris.geocentricJ2000(of: .sun, at: jd)
        let nutation = Nutation(julianDate: jd)
        let meanObliquity = Obliquity.mean(jd)
        let trueObliquity = meanObliquity + nutation.obliquity
        let equationOfTheEquinoxes = nutation.longitude * AstroMath.cosDeg(trueObliquity)
        let toTrueOfDate = nutation.matrix(meanObliquity: meanObliquity) * Precession.matrixFromJ2000(to: jd)
        let toTeme = Matrix3.frameRotationZ(AstroMath.radians(equationOfTheEquinoxes)) * toTrueOfDate
        return (toTeme * sunJ2000) * SkyFrame.kilometersPerAU
    }
}

/// The Earth's shadow on a satellite.
///
/// The model is conical: the Earth and the Sun are discs of apparent radius `b = asin(R⊕/r)` and
/// `a = asin(R☉/d)` as seen from the satellite, and the illuminated fraction of the Sun is the part of its disc
/// not covered by the Earth's disc (Montenbruck & Gill, *Satellite Orbits*, section 3.4.2). It is 1 in full
/// sunlight, 0 in the umbra, and in between in the penumbra, which at low-orbit altitudes lasts only a few seconds.
/// The Earth is a sphere of the WGS-84 equatorial radius; its atmosphere, which dims the sunlight a little
/// before the geometric shadow, is not modelled.
///
/// A fraction of one half means the Earth's limb passes through the centre of the Sun's disc, which is the
/// criterion of a point-source (cylindrical) shadow; `isSunlit` uses it.
public enum EarthShadow {
    /// Radius of the Sun in kilometres (IAU nominal).
    public static let sunRadiusKilometers = 695_700.0
    /// The illuminated fraction at or above which `isSunlit` is `true`.
    public static let sunlitThreshold = 0.5

    /// The fraction of the Sun's disc visible from `satellite` (0 ... 1).
    ///
    /// - Parameters:
    ///   - satellite: The satellite's geocentric position in kilometres (any inertial or Earth-fixed frame).
    ///   - sun: The Sun's geocentric position in kilometres, in the same frame.
    public static func illuminatedFraction(satellite: Vector3, sun: Vector3) -> Double {
        illuminatedFraction(satellite.x, satellite.y, satellite.z, sun.x, sun.y, sun.z)
    }

    /// `true` when at least half of the Sun's disc is visible (see `illuminatedFraction`).
    public static func isSunlit(satellite: Vector3, sun: Vector3) -> Bool {
        illuminatedFraction(satellite: satellite, sun: sun) >= sunlitThreshold
    }

    static func illuminatedFraction(_ sx: Double, _ sy: Double, _ sz: Double, _ px: Double, _ py: Double, _ pz: Double) -> Double {
        let distance = (sx * sx + sy * sy + sz * sz).squareRoot()
        if !(distance > SatelliteFrames.earthEquatorialRadiusKilometers) { return 0.0 }
        let dx = px - sx
        let dy = py - sy
        let dz = pz - sz
        let sunDistance = (dx * dx + dy * dy + dz * dz).squareRoot()
        if !(sunDistance > sunRadiusKilometers) { return 1.0 }
        let a = asin(sunRadiusKilometers / sunDistance)
        let b = asin(SatelliteFrames.earthEquatorialRadiusKilometers / distance)
        let cosine = -(sx * dx + sy * dy + sz * dz) / (distance * sunDistance)
        let c = acos(AstroMath.clamp(cosine, -1.0, 1.0))
        if c >= a + b { return 1.0 }
        if c <= b - a { return 0.0 }
        if c <= a - b { return 1.0 - (b * b) / (a * a) }
        let x = (c * c + a * a - b * b) / (2.0 * c)
        let y = max(a * a - x * x, 0.0).squareRoot()
        let area = a * a * acos(AstroMath.clamp(x / a, -1.0, 1.0)) +
            b * b * acos(AstroMath.clamp((c - x) / b, -1.0, 1.0)) - c * y
        return AstroMath.clamp(1.0 - area / (Double.pi * a * a), 0.0, 1.0)
    }
}

/// Vector helpers on plain components, so the sampling loops allocate nothing.
enum SatelliteVectorMath {
    /// The angle between two vectors in degrees.
    static func angleBetween(_ ax: Double, _ ay: Double, _ az: Double, _ bx: Double, _ by: Double, _ bz: Double) -> Double {
        let cx = ay * bz - az * by
        let cy = az * bx - ax * bz
        let cz = ax * by - ay * bx
        return AstroMath.degrees(atan2((cx * cx + cy * cy + cz * cz).squareRoot(), ax * bx + ay * by + az * bz))
    }
}

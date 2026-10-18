import Foundation

/// The small errors of a two-axis mount that the alignment model can find, all in degrees.
///
/// `axis1Index` and `axis2Index` are the angles by which the encoder zero is off the documented home position (the user
/// never sets it perfectly). `baseTiltX` and `baseTiltY` tilt the primary axis away from where it should point (equatorial: the
/// polar axis error, alt-azimuth: the level error): about the local x axis (equatorial: towards the meridian point on the equator,
/// alt-azimuth: east) and about the y axis (equatorial: east, alt-azimuth: north). `orthogonality` is the angle by which the
/// secondary axis is not perpendicular to the primary axis, `cone` the angle by which the optical axis is not perpendicular to
/// the secondary axis (equatorial: not parallel to the polar axis at the home position).
public struct SkyWatcherPointingErrors: Hashable, Sendable {
    /// Offset of the encoder zero of axis 1.
    public let axis1Index: Double
    /// Offset of the encoder zero of axis 2.
    public let axis2Index: Double
    /// Tilt of the primary axis about the local x axis.
    public let baseTiltX: Double
    /// Tilt of the primary axis about the local y axis.
    public let baseTiltY: Double
    /// Non-perpendicularity of the secondary axis.
    public let orthogonality: Double
    /// Collimation (cone) error of the optical axis.
    public let cone: Double

    public init(axis1Index: Double = 0, axis2Index: Double = 0, baseTiltX: Double = 0, baseTiltY: Double = 0,
                orthogonality: Double = 0, cone: Double = 0) {
        self.axis1Index = axis1Index
        self.axis2Index = axis2Index
        self.baseTiltX = baseTiltX
        self.baseTiltY = baseTiltY
        self.orthogonality = orthogonality
        self.cone = cone
    }

    /// Equatorial mounts: how far the polar axis points too high (positive) or too low above where the celestial pole is, in
    /// degrees. Meaningful once at least two stars are aligned.
    public var polarAxisAltitudeError: Double { baseTiltY }

    /// Equatorial mounts in the northern hemisphere (the sign flips in the southern one): how far the polar axis points east
    /// (positive) or west of the true pole, as an azimuth difference at the given `latitude`.
    public func polarAxisAzimuthError(latitude: Double) -> Double {
        let scale = cos(AstroMath.radians(latitude))
        return abs(scale) < 0.05 ? 0.0 : -baseTiltX / scale
    }

    func asRadians() -> [Double] {
        [AstroMath.radians(axis1Index), AstroMath.radians(axis2Index), AstroMath.radians(baseTiltX),
         AstroMath.radians(baseTiltY), AstroMath.radians(orthogonality), AstroMath.radians(cone)]
    }

    static func fromRadians(_ values: [Double]) -> SkyWatcherPointingErrors {
        SkyWatcherPointingErrors(axis1Index: AstroMath.degrees(values[0]), axis2Index: AstroMath.degrees(values[1]),
                                 baseTiltX: AstroMath.degrees(values[2]), baseTiltY: AstroMath.degrees(values[3]),
                                 orthogonality: AstroMath.degrees(values[4]), cone: AstroMath.degrees(values[5]))
    }
}

/// One way of reaching a direction: the encoder angles of both axes and the side of the mount.
public struct SkyWatcherAxisSolution: Hashable, Sendable {
    /// The encoder angle of axis 1 in degrees, (-180, 180].
    public let axis1: Double
    /// The encoder angle of axis 2 in degrees, (-180, 180].
    public let axis2: Double
    /// The pier side this solution is on.
    public let pierSide: SkyWatcherPierSide

    public init(axis1: Double, axis2: Double, pierSide: SkyWatcherPierSide) {
        self.axis1 = axis1
        self.axis2 = axis2
        self.pierSide = pierSide
    }
}

/// The geometry of a two-axis mount as a function of its encoder angles, and its inverse.
///
/// Equatorial mounts: axis 1 turns about the polar axis, axis 2 about the declination axis. At the home position (both angles
/// 0) the counterweight hangs down and the telescope points at the pole; the hour angle of the pointing is
/// `axis1 + 90°` for axis 2 > 0 (pier side east) and `axis1 - 90°` for axis 2 < 0 (pier side west), the declination
/// `90° - |axis2|`. The counterweight is below the horizontal while `|axis1| < 90°`, so the pier side changes at the meridian.
/// In the southern hemisphere the sky is mirrored (hour angle and declination change sign), as the mount is the mirror
/// image of a northern one.
///
/// Alt-azimuth mounts: axis 1 is the azimuth (from north through east), axis 2 the altitude; home is level, pointing north.
///
/// Directions are unit vectors in the local frame of the sky: equatorial mounts use the local equatorial frame (x towards the
/// meridian point on the celestial equator, y east, z towards the north celestial pole, in both hemispheres), alt-azimuth mounts the
/// ENU horizon frame. The `errors` describe how the real mount deviates from this ideal geometry (see `SkyWatcherPointingErrors`).
public struct SkyWatcherPointingModel: Hashable, Sendable {
    /// The arrangement of the axes.
    public let mode: SkyWatcherMountMode
    /// True when the mount stands in the southern hemisphere (equatorial mounts only).
    public let isSouthernHemisphere: Bool
    /// The errors found by the alignment.
    public let errors: SkyWatcherPointingErrors

    public init(mode: SkyWatcherMountMode, isSouthernHemisphere: Bool, errors: SkyWatcherPointingErrors) {
        self.mode = mode
        self.isSouthernHemisphere = isSouthernHemisphere
        self.errors = errors
    }

    /// The direction the mount points at when the encoders read `axis1Degrees` and `axis2Degrees`.
    public func direction(axis1Degrees: Double, axis2Degrees: Double) -> Vector3 {
        SkyWatcherPointingModel.rawDirection(mode: mode, isSouthernHemisphere: isSouthernHemisphere, errors: errors.asRadians(),
                                             axis1Degrees: axis1Degrees, axis2Degrees: axis2Degrees)
    }

    /// The two ways of pointing at `direction`: the encoder angles that make `direction(axis1Degrees:axis2Degrees:)` return it, one
    /// for each side of the mount (use `SkyWatcherAxisSolution.pierSide` to pick). At the pole of the primary axis, where axis 1 is
    /// undefined, both use `preferredAxis1Degrees`.
    public func solutions(_ direction: Vector3, preferredAxis1Degrees: Double = 0) -> [SkyWatcherAxisSolution] {
        let values = errors.asRadians()
        let unit = mirrored(direction.normalized)
        let tiltX = values[2]
        let tiltY = values[3]
        let orthogonality = values[4]
        let cone = values[5]
        // Undo the tilt of the primary axis.
        let ux = unit.x * cos(tiltY) - unit.z * sin(tiltY)
        let uy = unit.y
        let uz = unit.x * sin(tiltY) + unit.z * cos(tiltY)
        let wx = ux
        let wy = uy * cos(tiltX) + uz * sin(tiltX)
        let wz = -uy * sin(tiltX) + uz * cos(tiltX)
        let qx = sin(cone)
        let qz = (wz + qx * sin(orthogonality)) / cos(orthogonality)
        let tx = qx * cos(orthogonality) + qz * sin(orthogonality)
        let radius = (wx * wx + wy * wy).squareRoot()
        let base: Double
        let spread: Double
        if radius < 1e-12 {
            base = AstroMath.radians(preferredAxis1Degrees + errors.axis1Index)
            spread = 0.0
        } else {
            base = -atan2(wy, wx)
            spread = acos(AstroMath.clamp(tx / radius, -1.0, 1.0))
        }
        let offset = mode == .equatorial ? Double.pi / 2 : 0.0
        var result: [SkyWatcherAxisSolution] = []
        for index in 0 ..< 2 {
            let theta = index == 0 ? base + spread : base - spread
            let qy = wx * sin(theta) + wy * cos(theta)
            let phi = atan2(qz, qy)
            let modelAxis1 = AstroMath.normalizeSignedDegrees(AstroMath.degrees(theta))
            let modelAxis2 = AstroMath.normalizeSignedDegrees(AstroMath.degrees(phi - offset))
            result.append(SkyWatcherAxisSolution(axis1: AstroMath.normalizeSignedDegrees(modelAxis1 - errors.axis1Index),
                                                 axis2: AstroMath.normalizeSignedDegrees(modelAxis2 - errors.axis2Index),
                                                 pierSide: side(modelAxis2)))
        }
        return result
    }

    /// The pier side for the encoder angle `axis2Degrees` of axis 2.
    public func pierSide(axis2Degrees: Double) -> SkyWatcherPierSide {
        side(AstroMath.normalizeSignedDegrees(axis2Degrees + errors.axis2Index))
    }

    /// The angle of axis 1 in the ideal geometry (the encoder angle plus the index error), (-180, 180].
    public func modelAxis1(_ axis1Degrees: Double) -> Double { AstroMath.normalizeSignedDegrees(axis1Degrees + errors.axis1Index) }

    private func side(_ modelAxis2: Double) -> SkyWatcherPierSide {
        if mode == .equatorial { return modelAxis2 >= 0 ? .east : .west }
        return abs(modelAxis2) <= 90 ? .east : .west
    }

    private func mirrored(_ vector: Vector3) -> Vector3 {
        mode == .equatorial && isSouthernHemisphere ? Vector3(vector.x, -vector.y, -vector.z) : vector
    }

    /// The model of a mount without errors.
    static func nominal(mode: SkyWatcherMountMode, isSouthernHemisphere: Bool) -> SkyWatcherPointingModel {
        SkyWatcherPointingModel(mode: mode, isSouthernHemisphere: isSouthernHemisphere, errors: SkyWatcherPointingErrors())
    }

    /// The forward geometry with the errors given in radians as `[axis1Index, axis2Index, baseTiltX, baseTiltY,
    /// orthogonality, cone]`: the optical axis `q` is rotated about the secondary axis, tilted by the orthogonality error,
    /// turned about the primary axis and finally tilted with the base.
    static func rawDirection(mode: SkyWatcherMountMode, isSouthernHemisphere: Bool, errors: [Double], axis1Degrees: Double,
                             axis2Degrees: Double) -> Vector3 {
        let theta = AstroMath.radians(axis1Degrees) + errors[0]
        let secondary = AstroMath.radians(axis2Degrees) + errors[1]
        let phi = mode == .equatorial ? secondary + Double.pi / 2 : secondary
        let tiltX = errors[2]
        let tiltY = errors[3]
        let orthogonality = errors[4]
        let cone = errors[5]
        let qx = sin(cone)
        let qy = cos(cone) * cos(phi)
        let qz = cos(cone) * sin(phi)
        // Tilt the secondary axis (rotation about y).
        let rx = qx * cos(orthogonality) + qz * sin(orthogonality)
        let ry = qy
        let rz = -qx * sin(orthogonality) + qz * cos(orthogonality)
        // Turn about the primary axis (rotation about z by -theta).
        let sx = rx * cos(theta) + ry * sin(theta)
        let sy = -rx * sin(theta) + ry * cos(theta)
        let sz = rz
        // Tilt the base: about x, then about y.
        let ux = sx
        let uy = sy * cos(tiltX) - sz * sin(tiltX)
        let uz = sy * sin(tiltX) + sz * cos(tiltX)
        let vx = ux * cos(tiltY) + uz * sin(tiltY)
        let vy = uy
        let vz = -ux * sin(tiltY) + uz * cos(tiltY)
        return mode == .equatorial && isSouthernHemisphere ? Vector3(vx, -vy, -vz) : Vector3(vx, vy, vz)
    }
}

/// Conversions between apparent places of date and the local frames of `SkyWatcherPointingModel`: the local equatorial frame
/// (x towards the meridian point on the celestial equator, y east, z towards the north celestial pole; the same in both hemispheres)
/// for equatorial mounts and the ENU horizon frame for alt-azimuth mounts. Refraction is not applied.
public enum SkyWatcherSky {
    /// The sidereal rate in degrees per second (the rate at which the local sidereal time advances).
    public static var siderealDegreesPerSecond: Double { MountNudgeRate.siderealDegreesPerSecond }

    /// The direction in the local frame of the apparent place `place` when the local apparent sidereal time is `localSiderealTime`
    /// degrees (equatorial mounts: `(cos δ cos H, -cos δ sin H, sin δ)`; `latitude` is only used for alt-azimuth mounts).
    public static func localDirection(_ place: EquatorialCoordinate, localSiderealTime: Double, latitude: Double,
                                      mode: SkyWatcherMountMode) -> Vector3 {
        let hourAngle = AstroMath.normalizeSignedDegrees(localSiderealTime - place.rightAscension)
        if mode == .altAzimuth {
            return CoordinateTransforms.equatorialToHorizontal(hourAngle: hourAngle, declination: place.declination, latitude: latitude).unitVector
        }
        let cosDeclination = AstroMath.cosDeg(place.declination)
        return Vector3(cosDeclination * AstroMath.cosDeg(hourAngle),
                       -cosDeclination * AstroMath.sinDeg(hourAngle),
                       AstroMath.sinDeg(place.declination))
    }

    /// The apparent place that a local `direction` corresponds to at the local apparent sidereal time `localSiderealTime` (the inverse of `localDirection`).
    public static func apparentPlace(_ direction: Vector3, localSiderealTime: Double, latitude: Double,
                                     mode: SkyWatcherMountMode) -> EquatorialCoordinate {
        let hourAngle: Double
        let declination: Double
        if mode == .altAzimuth {
            let solved = CoordinateTransforms.horizontalToEquatorial(HorizontalCoordinate(vector: direction), latitude: latitude)
            hourAngle = solved.hourAngle
            declination = solved.declination
        } else {
            let length = direction.length
            if !(length > 0) { return EquatorialCoordinate(rightAscension: 0, declination: 0) }
            hourAngle = AstroMath.atan2Deg(-direction.y, direction.x)
            declination = AstroMath.asinDeg(direction.z / length)
        }
        return EquatorialCoordinate(rightAscension: localSiderealTime - hourAngle, declination: declination)
    }

    /// The geometric altitude in degrees of the apparent place `place` at the local apparent sidereal time `localSiderealTime`.
    public static func altitude(_ place: EquatorialCoordinate, localSiderealTime: Double, latitude: Double) -> Double {
        let hourAngle = AstroMath.normalizeSignedDegrees(localSiderealTime - place.rightAscension)
        return CoordinateTransforms.equatorialToHorizontal(hourAngle: hourAngle, declination: place.declination, latitude: latitude).altitude
    }
}

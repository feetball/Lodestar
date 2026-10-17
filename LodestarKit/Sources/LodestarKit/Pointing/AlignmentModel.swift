import Foundation

/// One alignment measurement: the camera was centred on an object whose true position is known
/// while the phone reported `attitude`.
public struct AlignmentPoint: Hashable, Codable, Sendable {
    private static let maximumNameLength = 120

    /// The attitude fed to `PointingSolution.solve` when the camera was centred (smoothed, if the
    /// arrows are driven by a smoothed attitude), without any heading offset or correction applied.
    public let attitude: DeviceAttitude
    /// The true apparent (refracted) horizontal position of the object the camera was centred on.
    public let target: HorizontalCoordinate
    /// When the measurement was taken.
    public let timestamp: Date
    /// Display name of the object, if any.
    public let name: String?

    /// Records a measurement. `name` is shortened to 120 characters.
    public init(attitude: DeviceAttitude, target: HorizontalCoordinate, timestamp: Date, name: String? = nil) {
        self.attitude = attitude
        self.target = target
        self.timestamp = timestamp
        self.name = name.map { String($0.prefix(Self.maximumNameLength)) }
    }

    private enum CodingKeys: String, CodingKey {
        case attitude, target, timestamp, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let target = try container.decode(HorizontalCoordinate.self, forKey: .target)
        guard (0.0..<360.0).contains(target.azimuth), (-90.0...90.0).contains(target.altitude) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath + [CodingKeys.target],
                debugDescription: "The target azimuth or altitude is out of range."))
        }
        self.init(attitude: try container.decode(DeviceAttitude.self, forKey: .attitude),
                  target: target,
                  timestamp: try container.decode(Date.self, forKey: .timestamp),
                  name: try container.decodeIfPresent(String.self, forKey: .name))
    }
}

/// Why an alignment point was rejected.
public enum AlignmentError: Error, Hashable, Sendable {
    /// An attitude or target coordinate is not a finite number.
    case nonFiniteInput
    /// The phone-reported boresight is too close to the zenith or nadir for its azimuth to be
    /// meaningful (altitude shown, degrees).
    case boresightTooHigh(altitude: Double)
    /// The target is too close to the zenith or nadir for its azimuth to be meaningful
    /// (altitude shown, degrees).
    case targetTooHigh(altitude: Double)
    /// The points would need a device-frame correction larger than a mount could plausibly cause —
    /// usually a wrong object was centred, or the wrong mount profile is selected.
    case implausibleCorrection(degrees: Double)
}

/// The calibration that makes the phone's sensors agree with where the camera really points.
///
/// Two independent effects are modelled:
/// * `headingOffset` — the compass error: the corrected azimuth is the measured azimuth plus the
///   offset (a rotation about the vertical);
/// * `deviceCorrection` — the small rotation, in the phone's device frame, between the mount's
///   nominal camera axis and the camera's true axis (clamp tilt and twist). It is a rotation
///   vector: the direction is the axis, the length the angle in degrees.
///
/// One point is solved exactly (an altitude error is blamed on the mount, an azimuth error on the
/// compass). Two or more points are fitted by damped least squares, which separates the two
/// effects when the points are spread in altitude and camera roll. An alignment is only valid for
/// the mount it was solved for (`calibratedMount`); change the mount and the app should start over.
public struct AlignmentModel: Hashable, Codable, Sendable {
    /// Most points kept; adding more drops the oldest.
    public static let maximumPointCount = 12
    /// Points whose boresight or target is higher than this (or lower than its negative), in degrees,
    /// are rejected because their azimuth is ill-conditioned.
    public static let maximumAltitude = 80.0
    /// Largest accepted device-frame correction in degrees.
    public static let maximumDeviceCorrection = 45.0

    /// Compass correction in degrees, (−180, 180]; corrected azimuth = measured azimuth + offset.
    public let headingOffset: Double
    /// Device-frame rotation vector in degrees applied to the mount's camera axis and up vector.
    public let deviceCorrection: Vector3
    /// The measurements the model was fitted to, oldest first.
    public let points: [AlignmentPoint]
    /// Angular distance in degrees between the corrected boresight and the target of each point.
    public let residuals: [Double]
    /// Expected pointing error in degrees (root-mean-square over the sky and camera rolls) of the
    /// corrected camera away from the aligned points; `nil` for `identity`. It follows from the
    /// geometry of the points and an assumed centring accuracy of about 0.25° each.
    ///
    /// The residuals only say how well the points agree with each other, and a single point always
    /// agrees perfectly. This number also says how well the points separate compass error from
    /// mount error. It is about 13° (the scale of the solver's prior: "unknown") for one point and
    /// for any number of points at the same altitude and camera roll, and falls to a few tenths of
    /// a degree for three or more points spread in altitude and roll.
    public let pointingUncertainty: Double?
    /// The mount the model was solved for; `nil` for `identity`.
    public let calibratedMount: MountProfile?

    /// No correction at all.
    public static let identity = AlignmentModel(headingOffset: 0, deviceCorrection: .zero, points: [],
                                                residuals: [], pointingUncertainty: nil, calibratedMount: nil)

    init(headingOffset: Double, deviceCorrection: Vector3, points: [AlignmentPoint], residuals: [Double],
         pointingUncertainty: Double?, calibratedMount: MountProfile?) {
        self.headingOffset = AstroMath.normalizeSignedDegrees(headingOffset)
        self.deviceCorrection = deviceCorrection
        self.points = points
        self.residuals = residuals
        self.pointingUncertainty = pointingUncertainty
        self.calibratedMount = calibratedMount
    }

    /// `true` once at least one point has been recorded.
    public var isAligned: Bool { !points.isEmpty }

    /// Root-mean-square of `residuals` in degrees; 0 without points.
    public var rmsResidual: Double {
        guard !residuals.isEmpty else { return 0 }
        return (residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)).squareRoot()
    }

    /// The device-frame correction as a rotation matrix.
    var deviceCorrectionMatrix: Matrix3 {
        PointingMath.rotationMatrix(rotationVector: deviceCorrection * AstroMath.radiansPerDegree)
    }

    /// `true` when the model may be used with `mount`: it was solved for the same camera axis and up
    /// vector, or it is the identity.
    public func isApplicable(to mount: MountProfile) -> Bool {
        guard let calibrated = calibratedMount else { return true }
        return calibrated.cameraAxis.dot(mount.cameraAxis) > 1 - 1e-9
            && calibrated.cameraUp.dot(mount.cameraUp) > 1 - 1e-9
    }

    /// The compass correction to apply for `mount`: `headingOffset` when the model is applicable,
    /// otherwise 0. Use it for anything drawn from the phone's own camera (see `PinholeProjection`);
    /// `PointingSolution.solve` applies the same rule.
    public func headingOffset(for mount: MountProfile) -> Double {
        isApplicable(to: mount) ? headingOffset : 0
    }

    /// Fits a model to `points` (the newest `maximumPointCount` are used).
    ///
    /// - Throws: `AlignmentError` when a point has non-finite values, a boresight or target too
    ///   close to the zenith or nadir, or the fit needs an implausibly large mount correction.
    public static func solve(points: [AlignmentPoint], mount: MountProfile) throws -> AlignmentModel {
        let kept = Array(points.suffix(maximumPointCount))
        guard !kept.isEmpty else { return .identity }
        for point in kept { try validate(point, mount: mount) }
        let fit = AlignmentSolver.fit(kept, mount: mount)
        let correction = fit.deviceCorrection.length
        guard correction <= maximumDeviceCorrection else {
            throw AlignmentError.implausibleCorrection(degrees: correction)
        }
        return AlignmentModel(headingOffset: fit.headingOffset, deviceCorrection: fit.deviceCorrection,
                              points: kept, residuals: fit.residuals, pointingUncertainty: fit.uncertainty,
                              calibratedMount: mount)
    }

    /// The model refitted with one more point. Points recorded for a different mount are discarded.
    ///
    /// - Throws: `AlignmentError`, see `solve(points:mount:)`.
    public func adding(_ point: AlignmentPoint, mount: MountProfile) throws -> AlignmentModel {
        let earlier = isApplicable(to: mount) ? points : []
        return try Self.solve(points: earlier + [point], mount: mount)
    }

    /// The model refitted without the point at `index`; unchanged when the index is out of range.
    ///
    /// - Throws: `AlignmentError`, see `solve(points:mount:)`.
    public func removingPoint(at index: Int, mount: MountProfile) throws -> AlignmentModel {
        guard points.indices.contains(index) else { return self }
        var remaining = points
        remaining.remove(at: index)
        return try Self.solve(points: remaining, mount: mount)
    }

    private static func validate(_ point: AlignmentPoint, mount: MountProfile) throws {
        let target = point.target
        guard target.azimuth.isFinite, target.altitude.isFinite, point.attitude.matrix.isFinite else {
            throw AlignmentError.nonFiniteInput
        }
        guard abs(target.altitude) <= maximumAltitude else {
            throw AlignmentError.targetTooHigh(altitude: target.altitude)
        }
        let boresight = HorizontalCoordinate(vector: point.attitude.deviceToWorld * mount.cameraAxis)
        guard abs(boresight.altitude) <= maximumAltitude else {
            throw AlignmentError.boresightTooHigh(altitude: boresight.altitude)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case headingOffset, deviceCorrection, points, residuals, pointingUncertainty, calibratedMount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let heading = try container.decode(Double.self, forKey: .headingOffset)
        let correction = try container.decode(Vector3.self, forKey: .deviceCorrection)
        let points = try container.decode([AlignmentPoint].self, forKey: .points)
        let residuals = try container.decode([Double].self, forKey: .residuals)
        let uncertainty = try container.decodeIfPresent(Double.self, forKey: .pointingUncertainty)
        let mount = try container.decodeIfPresent(MountProfile.self, forKey: .calibratedMount)
        guard heading.isFinite, abs(heading) <= 180,
              correction.isFinite, correction.length <= Self.maximumDeviceCorrection,
              points.count <= Self.maximumPointCount, residuals.count == points.count,
              residuals.allSatisfy({ $0.isFinite && $0 >= 0 }),
              uncertainty.map({ $0.isFinite && $0 >= 0 }) ?? true,
              (uncertainty == nil) == points.isEmpty else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "The alignment contains out-of-range or inconsistent values."))
        }
        self.init(headingOffset: heading, deviceCorrection: correction, points: points, residuals: residuals,
                  pointingUncertainty: uncertainty, calibratedMount: mount)
    }
}

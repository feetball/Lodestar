import Foundation
import LodestarKit

/// What the sensor diagnostics screen shows for one motion sample.
///
/// The formulas are the self-checks of the CoreMotion convention: the attitude matrix `M` satisfies
/// `v_device = M · v_reference` with reference axes x = north, y = west, z = up, and device axes x = right edge,
/// y = top edge, z = out of the screen; the back camera looks along −z. Indices below are one-based like the
/// `m11 … m33` of `CMRotationMatrix`.
struct SensorDiagnosticsSnapshot {
    /// A hypothesis about the matrix is accepted when its gravity prediction is this close (in g) to the measurement.
    static let gravityTolerance = 0.05
    /// Poses whose two gravity predictions differ by less than this (in g) cannot tell the hypotheses apart.
    static let poseDiscrimination = 0.1
    /// The phone counts as flat when gravity is within this many degrees of straight through the screen.
    static let flatTolerance = 10.0
    /// The boresight from the matrix and from LodestarKit agree when they differ by less than this many degrees.
    static let boresightTolerance = 0.1

    enum GravityVerdict: Equatable {
        /// The matrix maps reference vectors to device vectors, as assumed.
        case pass
        /// Gravity does not match the assumed mapping.
        case fail
        /// Both mappings predict the same gravity in this pose; tilt the phone and look again.
        case inconclusive
    }

    /// The raw CoreMotion matrix `M`.
    let matrix: Matrix3
    /// True azimuth of the reference frame's x axis: the declination for magnetic north, 0 for true north.
    let referenceAzimuth: Double
    /// Gravity in device coordinates, unit g.
    let gravity: Vector3
    /// Rotation speed in degrees per second.
    let angularSpeed: Double
    /// Magnitude of the calibrated magnetic field in microtesla, when the frame provides one.
    let magneticFieldMicrotesla: Double?

    /// The back camera's direction by the formula, with the azimuth measured from the reference frame's x axis.
    let boresightInFrame: HorizontalCoordinate
    /// The same direction with the reference azimuth added: azimuth from true north.
    let boresight: HorizontalCoordinate
    /// Angle in degrees between `boresight` and what `PointingSolution` reports for the back-camera mount.
    let boresightDisagreement: Double
    /// Distance in g between gravity and `(−m13, −m23, −m33)`, the prediction if `M` maps reference to device.
    let referenceToDeviceResidual: Double
    /// Distance in g between gravity and `(−m31, −m32, −m33)`, the prediction if `M` maps device to reference.
    let deviceToReferenceResidual: Double
    let gravityVerdict: GravityVerdict
    /// Compass heading of the phone's top edge, from the reference frame's x axis; meaningful with the phone flat.
    let topEdgeHeadingInFrame: Double
    /// The same heading from true north.
    let topEdgeHeading: Double
    /// Angle in degrees between the phone lying flat, screen up, and its present pose.
    let tiltFromFlat: Double

    init(sample: MotionSample) {
        let m = sample.rawAttitude.matrix
        let azimuth = sample.rawAttitude.referenceAzimuth
        matrix = m
        referenceAzimuth = azimuth
        gravity = sample.gravity
        angularSpeed = sample.angularSpeed
        magneticFieldMicrotesla = sample.magneticFieldMicrotesla

        // Boresight: east = m32, north = −m31, up = −m33.
        let inFrame = HorizontalCoordinate(azimuth: AstroMath.atan2Deg(m[2, 1], -m[2, 0]),
                                           altitude: AstroMath.asinDeg(-m[2, 2]))
        let trueBoresight = HorizontalCoordinate(azimuth: inFrame.azimuth + azimuth, altitude: inFrame.altitude)
        let library = PointingSolution.solve(attitude: sample.rawAttitude, mount: .backCameraPortrait).boresight
        boresightInFrame = inFrame
        boresight = trueBoresight
        boresightDisagreement = trueBoresight.angularSeparation(to: library)

        // Gravity: third column of M if M maps reference to device, third row if it maps device to reference.
        let ifReferenceToDevice = Vector3(-m[0, 2], -m[1, 2], -m[2, 2])
        let ifDeviceToReference = Vector3(-m[2, 0], -m[2, 1], -m[2, 2])
        let referenceToDevice = (ifReferenceToDevice - sample.gravity).length
        referenceToDeviceResidual = referenceToDevice
        deviceToReferenceResidual = (ifDeviceToReference - sample.gravity).length
        if (ifReferenceToDevice - ifDeviceToReference).length < Self.poseDiscrimination {
            gravityVerdict = .inconclusive
        } else {
            gravityVerdict = referenceToDevice < Self.gravityTolerance ? .pass : .fail
        }

        // Top edge: row 2 of M is the device y axis in the reference frame; east = −m22, north = m21.
        let heading = AstroMath.normalizeDegrees(AstroMath.atan2Deg(-m[1, 1], m[1, 0]))
        topEdgeHeadingInFrame = heading
        topEdgeHeading = AstroMath.normalizeDegrees(heading + azimuth)
        tiltFromFlat = AstroMath.acosDeg(-sample.gravity.z)
    }

    /// Whether the top-edge heading can be compared with a compass: the phone lies roughly flat, screen up.
    var isFlat: Bool { tiltFromFlat <= Self.flatTolerance }

    /// Whether the matrix-based and the LodestarKit boresights agree.
    var boresightsAgree: Bool { boresightDisagreement < Self.boresightTolerance }
}

/// The World Magnetic Model's values at the observer, to compare with the magnetometer.
struct SensorDiagnosticsMagneticModel {
    /// Degrees, east positive.
    let declination: Double
    /// Degrees, positive downwards.
    let inclination: Double
    /// Microtesla.
    let expectedFieldMicrotesla: Double
    /// Microtesla.
    let horizontalFieldMicrotesla: Double
    let reliability: CompassReliability
    /// Whether `date` lies within the years the model is valid for.
    let isCurrent: Bool

    /// `nil` when the model gives no valid field for the position.
    init?(location: GeographicLocation, date: Date) {
        let year = WorldMagneticModel.decimalYear(from: date)
        let model = WorldMagneticModel.wmm2025
        let field = model.field(latitude: location.latitude, longitude: location.longitude,
                                altitudeMeters: location.elevation, decimalYear: year)
        guard field.isValid else { return nil }
        declination = field.declination
        inclination = field.inclination
        expectedFieldMicrotesla = field.totalIntensity / 1000
        horizontalFieldMicrotesla = field.horizontalIntensity / 1000
        reliability = field.compassReliability
        isCurrent = model.isWithinValidity(decimalYear: year)
    }

    /// How far a measured field is from the expected one, as a fraction of the expected one.
    func deviation(ofMeasured microtesla: Double) -> Double {
        abs(microtesla - expectedFieldMicrotesla) / expectedFieldMicrotesla
    }
}

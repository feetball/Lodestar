import Foundation
import LodestarKit

/// The magnetic field at the observer from the World Magnetic Model: how to turn magnetic north into true north
/// and how strong the field should be.
struct MagneticReference: Equatable, Sendable {
    /// Degrees, east positive.
    var declination: Double
    /// Microtesla.
    var expectedFieldMicrotesla: Double
}

/// How far the compass can be trusted, from CoreMotion's calibration accuracy.
enum CompassQuality: String, Sendable {
    /// No magnetic data (gyro-only frame or no magnetometer).
    case unavailable
    case uncalibrated
    case low
    case medium
    case high
}

extension CompassQuality: Comparable {
    private var rank: Int {
        switch self {
        case .unavailable: return 0
        case .uncalibrated: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 4
        }
    }

    static func < (lhs: CompassQuality, rhs: CompassQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum MotionStatus: Equatable, Sendable {
    case idle
    case starting
    case running
    /// This device has no motion sensors (the Simulator).
    case unavailable
    case failed(String)
}

/// One sensor sample in app terms (copied out of CoreMotion on the motion queue).
struct MotionSample: Sendable {
    /// Smoothed, with the reference azimuth applied (magnetic frame: WMM declination; gyro frame: transferred).
    var attitude: DeviceAttitude
    /// Unsmoothed; use it for capturing alignment points.
    var rawAttitude: DeviceAttitude
    /// Device coordinates, unit g.
    var gravity: Vector3
    /// Degrees per second, from the rotation rate.
    var angularSpeed: Double
    /// Magnitude of the calibrated field in microtesla, when the frame provides one.
    var magneticFieldMicrotesla: Double?
    var compassQuality: CompassQuality
    /// Seconds since boot (`CMLogItem.timestamp`).
    var timestamp: TimeInterval
}

/// Where the Aim frame engine gets its attitude samples: `MotionService`, or a scripted source in tests.
protocol MotionSampleSource: Sendable {
    /// The newest sample, or `nil` when none has arrived yet.
    func latestSample() -> MotionSample?
    /// The sample closest to `time` (seconds since boot, `CMLogItem.timestamp`), or `nil` when none is close to it.
    func sample(at time: TimeInterval) -> MotionSample?
}

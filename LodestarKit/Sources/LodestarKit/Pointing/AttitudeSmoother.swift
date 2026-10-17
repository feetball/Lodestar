import Foundation

/// A low-pass filter for the phone attitude, for steady arrows and a steady overlay.
///
/// Each sample is blended into the filtered attitude along the shortest rotation (spherical
/// interpolation) with an exponential time constant. The time constant adapts to the angular speed
/// of the phone, estimated from consecutive samples: at rest it is `timeConstant`, so sensor noise
/// is averaged out; while the phone moves it shrinks, so that during steady motion the filtered
/// attitude lags the true one by less than `maximumLag` degrees (a sudden step of a few degrees
/// counts as fast motion and is followed at once). The filter restarts from the raw sample after a
/// large jump, a pause in the samples, a sample that is not later than its predecessor, or a change
/// of reference frame. Samples therefore need increasing timestamps (`CMDeviceMotion.timestamp`);
/// without them the smoother passes every sample through unchanged.
public struct AttitudeSmoother: Sendable {
    /// Time constant in seconds when the phone is at rest.
    public let timeConstant: Double
    /// Upper bound, in degrees, for the lag during steady motion.
    public let maximumLag: Double
    /// A distance between the filtered and the new attitude beyond this (degrees) restarts the filter.
    public let jumpThreshold: Double
    /// A pause between samples longer than this (seconds) restarts the filter.
    public let maximumTimeGap: Double

    private var filtered: AttitudeQuaternion?
    private var previousRaw = AttitudeQuaternion(.identity)
    private var previousTimestamp: TimeInterval = 0
    private var previousAzimuth: Double = 0

    /// Creates a smoother; non-finite or non-positive arguments fall back to the defaults
    /// (0.12 s, 0.5°, 20°, 0.5 s).
    public init(timeConstant: Double = 0.12, maximumLag: Double = 0.5,
                jumpThreshold: Double = 20, maximumTimeGap: Double = 0.5) {
        func valid(_ value: Double, _ fallback: Double) -> Double { value.isFinite && value > 0 ? value : fallback }
        self.timeConstant = valid(timeConstant, 0.12)
        self.maximumLag = valid(maximumLag, 0.5)
        self.jumpThreshold = valid(jumpThreshold, 20)
        self.maximumTimeGap = valid(maximumTimeGap, 0.5)
    }

    /// Feeds one sample and returns the filtered attitude, which carries the sample's reference
    /// azimuth and timestamp.
    public mutating func update(with attitude: DeviceAttitude) -> DeviceAttitude {
        let raw = AttitudeQuaternion(attitude.matrix)
        let last = previousRaw
        let lastTimestamp = previousTimestamp
        let sameFrame = attitude.referenceAzimuth == previousAzimuth
        previousRaw = raw
        previousTimestamp = attitude.timestamp
        previousAzimuth = attitude.referenceAzimuth

        guard let current = filtered, sameFrame else {
            filtered = raw
            return attitude
        }
        let dt = attitude.timestamp - lastTimestamp
        guard dt > 0, dt <= maximumTimeGap, current.angle(to: raw) <= jumpThreshold else {
            filtered = raw
            return attitude
        }
        let speed = last.angle(to: raw) / dt
        let rate = 1 / timeConstant + speed / maximumLag
        let next = current.slerp(to: raw, 1 - exp(-dt * rate))
        filtered = next
        return DeviceAttitude(orthonormal: next.matrix, referenceAzimuth: attitude.referenceAzimuth,
                              timestamp: attitude.timestamp)
    }

    /// Forgets the filtered attitude; the next sample is passed through unchanged.
    public mutating func reset() {
        filtered = nil
    }
}

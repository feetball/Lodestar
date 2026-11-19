import Foundation

/// One timestamped camera boresight, the input of `SteadinessDetector`.
///
/// The direction is stored as a unit vector in the horizon frame (ENU). The initializers return `nil` for a
/// timestamp or direction that is not finite and for a zero direction.
public struct SteadinessSample: Hashable, Sendable {
    /// Seconds on any clock that only moves forward (the sensor clock of the attitudes, for example).
    public let timestamp: Double
    /// Unit vector of the camera boresight in the horizon frame (x east, y north, z up).
    public let direction: Vector3

    /// A sample at `timestamp` looking along `direction` (any non-zero length, normalised here); `nil` when the
    /// timestamp or direction is not finite, or the direction has no length.
    public init?(timestamp: Double, direction: Vector3) {
        let length = direction.length
        guard timestamp.isFinite, direction.isFinite, length.isFinite, length > 0 else { return nil }
        self.timestamp = timestamp
        self.direction = direction / length
    }

    /// A sample looking at `boresight`; `nil` for a non-finite timestamp.
    public init?(timestamp: Double, boresight: HorizontalCoordinate) {
        self.init(timestamp: timestamp, direction: boresight.unitVector)
    }

    /// The sample for the phone `attitude` (the one an `AlignmentPoint` stores) carried on `mount`: it is stamped
    /// with the attitude's timestamp and looks along the mount's camera axis.
    public init?(attitude: DeviceAttitude, mount: MountProfile) {
        self.init(timestamp: attitude.timestamp, direction: attitude.deviceToWorld * mount.cameraAxis)
    }
}

/// Tells whether the camera has been held still: it keeps a sliding window of the last `windowSeconds` of
/// boresight samples and reports `isSteady` once the window is full and every sample in it lies within
/// `toleranceDegrees` of the newest sample.
///
/// It is an immutable value; `adding(_:)` returns the detector for the stream so far. Each call copies the samples
/// of one window (a few dozen at sensor rates) and nothing else is kept, so a stream of any length runs in
/// constant memory. Cost per sample is one angle computation per sample in the window.
///
/// The window counts as full when the unbroken stream of samples reaches back `windowSeconds` before the newest
/// sample. The stream is unbroken until a gap of more than `maximumGapSeconds` between two samples or a sample
/// stamped earlier than its predecessor, which start it over (a detector that reports "steady" must have seen
/// the whole window). A sample with the same timestamp as the newest is ignored. Use a new detector for each
/// attempt.
///
/// Non-finite or non-positive arguments fall back to the defaults (1.5 s, 0.35°, 0.5 s).
public struct SteadinessDetector: Hashable, Sendable {
    /// Default `windowSeconds`.
    public static let defaultWindowSeconds = 1.5
    /// Default `toleranceDegrees`: a little more than the noise of a phone resting on a tripod bracket.
    public static let defaultToleranceDegrees = 0.35
    /// Default `maximumGapSeconds`.
    public static let defaultMaximumGapSeconds = 0.5

    /// Length of the window in seconds.
    public let windowSeconds: Double
    /// Largest angle in degrees between the newest sample and any other sample of the window.
    public let toleranceDegrees: Double
    /// A pause between two samples longer than this (seconds) starts the window over.
    public let maximumGapSeconds: Double
    /// `true` when the window is full and the camera stayed within the tolerance throughout it.
    public let isSteady: Bool
    /// How much of the window the camera has been still for, in [0, 1]: the time since the newest sample that is
    /// further than the tolerance from the newest one (or since the start of the stream), over `windowSeconds`.
    /// It is 1 exactly when `isSteady`.
    public let progress: Double

    private let samples: [SteadinessSample]
    private let runStart: Double

    /// Number of samples held, which is bounded by the window.
    public var sampleCount: Int { samples.count }

    /// Creates a detector with an empty window. Non-finite or non-positive arguments fall back to the defaults.
    public init(windowSeconds: Double = SteadinessDetector.defaultWindowSeconds,
                toleranceDegrees: Double = SteadinessDetector.defaultToleranceDegrees,
                maximumGapSeconds: Double = SteadinessDetector.defaultMaximumGapSeconds) {
        func valid(_ value: Double, _ fallback: Double) -> Double { value.isFinite && value > 0 ? value : fallback }
        self.init(windowSeconds: valid(windowSeconds, Self.defaultWindowSeconds),
                  toleranceDegrees: valid(toleranceDegrees, Self.defaultToleranceDegrees),
                  maximumGapSeconds: valid(maximumGapSeconds, Self.defaultMaximumGapSeconds),
                  samples: [], runStart: 0, isSteady: false, progress: 0)
    }

    private init(windowSeconds: Double, toleranceDegrees: Double, maximumGapSeconds: Double,
                 samples: [SteadinessSample], runStart: Double, isSteady: Bool, progress: Double) {
        self.windowSeconds = windowSeconds
        self.toleranceDegrees = toleranceDegrees
        self.maximumGapSeconds = maximumGapSeconds
        self.samples = samples
        self.runStart = runStart
        self.isSteady = isSteady
        self.progress = progress
    }

    /// The detector after `sample`. A sample not later than the newest one is ignored when its timestamp is equal
    /// and starts the window over when it is earlier.
    public func adding(_ sample: SteadinessSample) -> SteadinessDetector {
        guard let newest = samples.last else { return restarted(at: sample) }
        if sample.timestamp == newest.timestamp { return self }
        if !(sample.timestamp > newest.timestamp) || sample.timestamp - newest.timestamp > maximumGapSeconds {
            return restarted(at: sample)
        }
        let windowStart = sample.timestamp - windowSeconds
        var dropped = 0
        while dropped < samples.count && samples[dropped].timestamp < windowStart { dropped += 1 }
        var kept: [SteadinessSample] = []
        kept.reserveCapacity(samples.count - dropped + 1)
        for index in dropped..<samples.count { kept.append(samples[index]) }
        kept.append(sample)

        // The trailing run of samples that are within the tolerance of the newest one.
        var outside = kept.count - 1
        while outside >= 0 && sample.direction.angle(to: kept[outside].direction) <= toleranceDegrees { outside -= 1 }
        let steady = outside < 0 && runStart <= windowStart
        let begin = outside < 0 ? runStart : kept[outside + 1].timestamp
        let fraction = steady ? 1 : AstroMath.clamp((sample.timestamp - begin) / windowSeconds, 0, 1)
        return SteadinessDetector(windowSeconds: windowSeconds, toleranceDegrees: toleranceDegrees,
                                  maximumGapSeconds: maximumGapSeconds, samples: kept, runStart: runStart,
                                  isSteady: steady, progress: fraction)
    }

    private func restarted(at sample: SteadinessSample) -> SteadinessDetector {
        SteadinessDetector(windowSeconds: windowSeconds, toleranceDegrees: toleranceDegrees,
                           maximumGapSeconds: maximumGapSeconds, samples: [sample], runStart: sample.timestamp,
                           isSteady: false, progress: 0)
    }
}

/// Where a candidate star lies relative to the nearest alignment point.
public struct AlignmentPointSeparation: Hashable, Sendable {
    /// Angular separation in degrees.
    public let degrees: Double
    /// Index of that point in the array given to `AlignmentHygiene.bestSeparation(candidate:existing:)`.
    public let pointIndex: Int
    /// The point's name, if it has one.
    public let pointName: String?

    public init(degrees: Double, pointIndex: Int, pointName: String?) {
        self.degrees = degrees
        self.pointIndex = pointIndex
        self.pointName = pointName
    }
}

/// Rules that keep a star alignment trustworthy: how far apart the alignment stars should be and when an alignment
/// is too old to rely on. The steadiness check for the moment of syncing is `SteadinessDetector`.
///
/// The numbers are rules of thumb chosen for the app, not measured values.
public enum AlignmentHygiene {
    /// Alignment stars closer together than this, in degrees, make the least-squares fit ill-conditioned: the
    /// points then say little about compass error against bracket tilt.
    public static let minimumPointSeparationDegrees = 20.0

    /// Seconds after which an alignment made with the compass heading is stale: 3 hours. The compass heading does
    /// not drift; what goes wrong is slow and caused by the setting: the phone slips in its bracket, the tripod is
    /// moved near metal or cars, the magnetic surroundings change.
    public static let compassStaleAfterSeconds: TimeInterval = 3 * 3600

    /// Seconds after which an alignment made in gyro lock is stale: 90 minutes. Gyro lock holds the heading by
    /// integrating the gyroscope in a frame without an absolute reference, so its error keeps growing with time
    /// (gyro drift) on top of the bracket slips that affect the compass too.
    public static let gyroLockStaleAfterSeconds: TimeInterval = 90 * 60

    /// The age in seconds from which an alignment is stale: `gyroLockStaleAfterSeconds` in gyro lock, else
    /// `compassStaleAfterSeconds`.
    public static func staleAfterSeconds(gyroLock: Bool) -> TimeInterval {
        gyroLock ? gyroLockStaleAfterSeconds : compassStaleAfterSeconds
    }

    /// Whether an alignment made at `alignedAt` is stale at `now`: its age is at least `staleAfterSeconds`. An
    /// alignment from the future (the clock was set back) is not stale.
    public static func isStale(alignedAt: Date, now: Date, gyroLock: Bool) -> Bool {
        now.timeIntervalSince(alignedAt) >= staleAfterSeconds(gyroLock: gyroLock)
    }

    /// The existing point nearest to `candidate`, with the separation in degrees; `nil` without points. Positions
    /// are the horizontal places recorded when each point was taken, which is the frame the fit is solved in, so
    /// `candidate` should be the object's apparent horizontal position now. The first of equally near points wins.
    public static func bestSeparation(candidate: HorizontalCoordinate, existing: [AlignmentPoint]) -> AlignmentPointSeparation? {
        var best: AlignmentPointSeparation?
        for (index, point) in existing.enumerated() {
            let separation = candidate.angularSeparation(to: point.target)
            // A separation that is NaN (a non-finite candidate) is never smaller, so it is never chosen.
            if separation < (best?.degrees ?? .infinity) {
                best = AlignmentPointSeparation(degrees: separation, pointIndex: index, pointName: point.name)
            }
        }
        return best
    }

    /// The smallest separation in degrees between `candidate` and the `existing` points when it is under
    /// `minimumPointSeparationDegrees`; `nil` when it is fine or there are no points.
    public static func separationWarning(candidate: HorizontalCoordinate, existing: [AlignmentPoint]) -> Double? {
        guard let nearest = bestSeparation(candidate: candidate, existing: existing) else { return nil }
        return nearest.degrees < minimumPointSeparationDegrees ? nearest.degrees : nil
    }
}

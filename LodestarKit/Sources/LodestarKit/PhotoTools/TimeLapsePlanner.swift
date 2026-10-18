import Foundation

/// Why a time-lapse could not be planned.
public enum TimeLapseError: Error, Hashable, Sendable {
    /// The interval is not a finite number of seconds in (0, `TimeLapsePlanner.maximumIntervalSeconds`].
    case invalidInterval(seconds: Double)
    /// The exposure is not a finite number of seconds in (0, `TimeLapsePlanner.maximumIntervalSeconds`].
    case invalidExposure(seconds: Double)
    /// The frame rate is not a finite number in (0, `TimeLapsePlanner.maximumFrameRate`].
    case invalidFrameRate(framesPerSecond: Double)
    /// The clip length, shooting time or frame count is not positive or yields less than one frame.
    case invalidTarget(value: Double)
    /// The minimum gap is not a finite number of seconds in [0, `TimeLapsePlanner.maximumMinimumGapSeconds`].
    case invalidMinimumGap(seconds: Double)
    /// The frame size is not a finite number of megabytes in (0, `TimeLapsePlanner.maximumFrameSizeMegabytes`].
    case invalidFrameSize(megabytes: Double)
    /// The gap between the end of an exposure and the next shot is shorter than the camera needs to write the
    /// picture, so frames would be skipped. `minimumIntervalSeconds` is the shortest interval that works.
    case gapTooShort(gapSeconds: Double, minimumGapSeconds: Double, minimumIntervalSeconds: Double)
    /// The time-lapse would have `count` frames, more than the `limit` the planner handles.
    case tooManyFrames(count: Int, limit: Int)
}

/// What the time-lapse is planned for.
public enum TimeLapseTarget: Hashable, Sendable {
    /// A clip of this many seconds when played back at the frame rate.
    case clipLength(seconds: Double)
    /// This many seconds of shooting. The plan takes as many whole intervals as fit.
    case shootingTime(seconds: Double)
    /// This many frames.
    case frameCount(frames: Int)
}

/// How much a time-lapse asks of the camera's battery, judged by the number of exposures.
public enum BatteryDemand: String, CaseIterable, Codable, Hashable, Sendable {
    /// Up to 300 exposures: one battery is plenty.
    case light
    /// Up to 1000 exposures: a full battery, a spare in the bag.
    case moderate
    /// Up to 2500 exposures: a spare battery or external power.
    case heavy
    /// More than 2500 exposures: external power.
    case veryHeavy
}

/// The numbers of a time-lapse.
public struct TimeLapsePlan: Hashable, Sendable {
    /// The time between the starts of two exposures in seconds.
    public let interval: Double
    /// The exposure time in seconds.
    public let exposure: Double
    /// The playback frame rate in frames per second.
    public let frameRate: Double
    /// The number of frames (exposures).
    public let frameCount: Int
    /// The time the shooting takes, `frameCount × interval`, in seconds.
    public let shootingTime: Double
    /// The length of the clip, `frameCount / frameRate`, in seconds.
    public let clipLength: Double
    /// The time between the end of an exposure and the start of the next, `interval − exposure`, in seconds:
    /// what the camera has to write the picture and refocus.
    public let gap: Double
    /// How much faster than real time the clip plays: `interval × frameRate`.
    public let speedUp: Double
    /// The size of one picture in megabytes (1 MB = 1 000 000 bytes), or nil if unknown.
    public let frameSizeMegabytes: Double?
    /// The storage all frames need in megabytes, or nil if the frame size is unknown.
    public let storageMegabytes: Double?
    /// The storage in gigabytes (1 GB = 1000 MB), or nil if the frame size is unknown.
    public let storageGigabytes: Double?
    /// The number of exposures the battery has to supply: equal to `frameCount`.
    public let exposureCount: Int
    /// How demanding the number of exposures is.
    public let batteryDemand: BatteryDemand
    /// A sentence about batteries for the number of exposures, in English.
    public let batteryNote: String
}

/// Works out the numbers of a time-lapse: how many frames it takes, how long the shooting and the clip last,
/// how much storage it needs and whether the camera can keep up with the interval.
///
/// All functions are pure and take microseconds.
public enum TimeLapsePlanner {
    /// The longest interval or exposure the planner accepts: an hour.
    public static let maximumIntervalSeconds = 3_600.0

    /// The highest playback frame rate the planner accepts.
    public static let maximumFrameRate = 240.0

    /// The most frames a plan may have.
    public static let maximumFrameCount = 100_000

    /// The largest frame size the planner accepts, in megabytes.
    public static let maximumFrameSizeMegabytes = 10_000.0

    /// The shortest gap between exposures by default: one second for the camera to write the picture.
    public static let defaultMinimumGapSeconds = 1.0

    /// The largest minimum gap the planner accepts.
    public static let maximumMinimumGapSeconds = 60.0

    /// Up to this many exposures the battery demand is `BatteryDemand.light`.
    static let lightExposureLimit = 300

    /// Up to this many exposures the battery demand is `BatteryDemand.moderate`.
    static let moderateExposureLimit = 1_000

    /// Up to this many exposures the battery demand is `BatteryDemand.heavy`.
    static let heavyExposureLimit = 2_500

    /// The shortest interval that leaves the camera `minimumGapSeconds` after an exposure of `exposure` seconds.
    ///
    /// - Throws: `TimeLapseError.invalidExposure` for an exposure out of range, `TimeLapseError.invalidMinimumGap`
    ///   for a minimum gap out of range.
    public static func minimumInterval(exposure: Double,
                                       minimumGapSeconds: Double = TimeLapsePlanner.defaultMinimumGapSeconds) throws -> Double {
        guard exposure > 0, exposure <= maximumIntervalSeconds else { throw TimeLapseError.invalidExposure(seconds: exposure) }
        guard minimumGapSeconds >= 0, minimumGapSeconds <= maximumMinimumGapSeconds else {
            throw TimeLapseError.invalidMinimumGap(seconds: minimumGapSeconds)
        }
        return exposure + minimumGapSeconds
    }

    /// Plans a time-lapse.
    ///
    /// The frame count follows from the target: a clip length gives `round(clipLength × frameRate)` frames, a shooting
    /// time as many whole intervals as fit in it, and a frame count is taken as it is.
    ///
    /// - Parameters:
    ///   - interval: The time between the starts of two exposures in seconds, in (0, `maximumIntervalSeconds`].
    ///   - exposure: The exposure time in seconds, in (0, `maximumIntervalSeconds`].
    ///   - frameRate: The playback frame rate in frames per second, in (0, `maximumFrameRate`].
    ///   - target: The clip length, shooting time or frame count to plan for.
    ///   - frameSizeMegabytes: The size of one picture in megabytes, for the storage estimate; nil leaves the
    ///     storage unknown.
    ///   - minimumGapSeconds: The gap the camera needs between the end of an exposure and the next start (the
    ///     write time) in seconds, [0, `maximumMinimumGapSeconds`].
    /// - Throws: `TimeLapseError` for a value out of range, a target that yields no frames or more than
    ///   `maximumFrameCount`, or `TimeLapseError.gapTooShort` when `interval − exposure` is less than
    ///   `minimumGapSeconds`.
    public static func plan(interval: Double, exposure: Double, frameRate: Double, target: TimeLapseTarget,
                            frameSizeMegabytes: Double? = nil,
                            minimumGapSeconds: Double = TimeLapsePlanner.defaultMinimumGapSeconds) throws -> TimeLapsePlan {
        guard interval > 0, interval <= maximumIntervalSeconds else { throw TimeLapseError.invalidInterval(seconds: interval) }
        guard exposure > 0, exposure <= maximumIntervalSeconds else { throw TimeLapseError.invalidExposure(seconds: exposure) }
        guard frameRate > 0, frameRate <= maximumFrameRate else { throw TimeLapseError.invalidFrameRate(framesPerSecond: frameRate) }
        guard minimumGapSeconds >= 0, minimumGapSeconds <= maximumMinimumGapSeconds else {
            throw TimeLapseError.invalidMinimumGap(seconds: minimumGapSeconds)
        }
        if let size = frameSizeMegabytes, !(size > 0 && size <= maximumFrameSizeMegabytes) {
            throw TimeLapseError.invalidFrameSize(megabytes: size)
        }
        let gap = interval - exposure
        guard gap >= minimumGapSeconds - 1e-9 else {
            throw TimeLapseError.gapTooShort(gapSeconds: gap, minimumGapSeconds: minimumGapSeconds,
                                             minimumIntervalSeconds: exposure + minimumGapSeconds)
        }

        let frames: Double
        let requested: Double
        switch target {
        case let .clipLength(seconds):
            guard seconds > 0, seconds.isFinite else { throw TimeLapseError.invalidTarget(value: seconds) }
            frames = (seconds * frameRate).rounded()
            requested = seconds
        case let .shootingTime(seconds):
            guard seconds > 0, seconds.isFinite else { throw TimeLapseError.invalidTarget(value: seconds) }
            frames = floor(seconds / interval + 1e-9)
            requested = seconds
        case let .frameCount(count):
            frames = Double(count)
            requested = Double(count)
        }
        guard frames >= 1 else { throw TimeLapseError.invalidTarget(value: requested) }
        if frames > Double(maximumFrameCount) {
            throw TimeLapseError.tooManyFrames(count: frames >= 1e9 ? 1_000_000_000 : Int(frames), limit: maximumFrameCount)
        }
        let frameCount = Int(frames)
        let storageMegabytes = frameSizeMegabytes.map { $0 * frames }
        return TimeLapsePlan(
            interval: interval, exposure: exposure, frameRate: frameRate, frameCount: frameCount,
            shootingTime: frames * interval, clipLength: frames / frameRate, gap: gap, speedUp: interval * frameRate,
            frameSizeMegabytes: frameSizeMegabytes, storageMegabytes: storageMegabytes,
            storageGigabytes: storageMegabytes.map { $0 / 1000 }, exposureCount: frameCount,
            batteryDemand: batteryDemand(exposureCount: frameCount), batteryNote: batteryNote(exposureCount: frameCount))
    }

    /// How demanding `exposureCount` exposures are for the battery.
    public static func batteryDemand(exposureCount: Int) -> BatteryDemand {
        if exposureCount <= lightExposureLimit { return .light }
        if exposureCount <= moderateExposureLimit { return .moderate }
        if exposureCount <= heavyExposureLimit { return .heavy }
        return .veryHeavy
    }

    /// A sentence about batteries for `exposureCount` exposures, in English. The limits are rules of thumb: a
    /// typical camera battery lasts for several hundred to a couple of thousand pictures, fewer in the cold and
    /// with long exposures.
    public static func batteryNote(exposureCount: Int) -> String {
        switch batteryDemand(exposureCount: exposureCount) {
        case .light:
            "About \(exposureCount) exposures: one charged battery is plenty."
        case .moderate:
            "About \(exposureCount) exposures: start with a fully charged battery and keep a spare in the bag."
        case .heavy:
            "About \(exposureCount) exposures: bring a spare battery or external power, as cold shortens battery life."
        case .veryHeavy:
            "About \(exposureCount) exposures: use external power, such as a power bank or a dummy battery."
        }
    }
}

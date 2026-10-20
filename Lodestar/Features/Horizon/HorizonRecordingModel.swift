import Foundation
import LodestarKit
import Observation

/// What the recording screen should tell the person about the sweep, most urgent first.
enum HorizonHint: Equatable {
    /// The phone has no motion sensors (the Simulator).
    case noSensors
    /// The sensors reported an error.
    case sensorProblem(String)
    /// The first motion sample has not arrived.
    case waiting
    /// In gyro lock the heading is not known yet.
    case headingNotSet
    /// The compass is not calibrated, so its samples are dropped.
    case calibrateCompass
    /// The camera moves faster than the recorder can follow.
    case slowDown
    /// The camera points above 60° or below −10°, where there is no skyline.
    case aimAtSkyline
    /// Something nearby disturbs the compass.
    case interference
    /// The whole circle is recorded.
    case complete

    var text: String {
        switch self {
        case .noSensors:
            return "This iPhone has no motion sensors, so it cannot record a skyline."
        case .sensorProblem(let message):
            return message
        case .waiting:
            return "Waiting for the motion sensors\u{2026}"
        case .headingNotSet:
            return "Gyro Lock has no heading yet. Choose Compass as the heading source in Settings, or align on a "
                + "star first."
        case .calibrateCompass:
            return "The compass needs calibrating. Move the phone in a figure 8, away from metal and magnets."
        case .slowDown:
            return "Too fast. Turn more slowly."
        case .aimAtSkyline:
            return "Point the camera at the skyline."
        case .interference:
            return "Magnetic interference nearby. Move away from metal and electronics, or the directions may be off."
        case .complete:
            return "All the way round. Tap Done to save the skyline."
        }
    }

    var systemImage: String {
        switch self {
        case .noSensors, .sensorProblem, .headingNotSet, .calibrateCompass, .interference, .slowDown, .aimAtSkyline:
            return "exclamationmark.triangle"
        case .waiting: return "hourglass"
        case .complete: return "checkmark.circle"
        }
    }

    var tone: ChipTone {
        switch self {
        case .noSensors, .sensorProblem: return .critical
        case .waiting: return .neutral
        case .headingNotSet, .calibrateCompass, .slowDown, .aimAtSkyline, .interference: return .warning
        case .complete: return .positive
        }
    }
}

/// What the recording screen shows, refreshed about ten times a second.
struct HorizonReading: Equatable {
    /// Where the phone's back camera points now, or `nil` before the first sample.
    var azimuth: Double?
    var altitude: Double?
    /// The fraction of the circle swept so far, 0…1.
    var coverage: Double
    /// How many of the 360 bins hold a sample.
    var recordedBins: Int
    /// The skyline as it stands: swept stretches, small gaps closed, the rest from the previous skyline.
    var skyline: HorizonProfile
    /// The stretches still to be swept.
    var gaps: [AzimuthRange]
    var hint: HorizonHint?

    var hasSamples: Bool { recordedBins > 0 }
    var isComplete: Bool { recordedBins >= HorizonProfile.binCount }

    static let empty = HorizonReading(azimuth: nil, altitude: nil, coverage: 0, recordedBins: 0, skyline: .flat,
                                      gaps: [.full], hint: .waiting)
}

/// Feeds the motion sensors' newest attitude to a `HorizonRecorder` while the recording screen is open.
///
/// The recorder gets every new sample (60 per second); the observable `reading` is refreshed at ten hertz, so the view
/// tree is not invalidated with every sample.
@MainActor
@Observable
final class HorizonRecordingModel {
    /// Seconds between refreshes of the reading.
    private static let publishInterval = 0.1
    private static let loopInterval: Duration = .milliseconds(16)
    /// A rejection is shown for this long after the last sample it applied to.
    private static let hintDuration = 1.2
    /// The recorder drops samples above `maximumSweepRate`; the warning starts at this fraction of it.
    private static let warningFraction = 0.7
    /// Above this fractional deviation from the expected field strength the compass is probably disturbed (as in Aim).
    private static let interferenceThreshold = 0.25

    private(set) var reading = HorizonReading.empty

    /// The skyline stored with the site when the recording started: unswept stretches keep it.
    @ObservationIgnored let storedSkyline: HorizonProfile?
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var recorder = HorizonRecorder()
    @ObservationIgnored private var lastTimestamp: TimeInterval?
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var lastRejection: (reason: HorizonRecorder.Rejection, date: Date)?
    @ObservationIgnored private var isHeadingMissing = false
    @ObservationIgnored private var hasInterference = false

    /// - Parameters:
    ///   - app: The app model, for the motion sensors, the alignment and the mount.
    ///   - base: The site's current skyline, which unswept stretches keep.
    init(app: AppModel, base: HorizonProfile?) {
        self.app = app
        storedSkyline = base
        publish(now: Date())
    }

    // MARK: Running

    /// Reads the sensors until the task is cancelled.
    func run() async {
        while !Task.isCancelled {
            step()
            try? await Task.sleep(for: Self.loopInterval)
        }
    }

    private func step() {
        let now = Date()
        if let sample = app.motion.latestSample() {
            updateHeadingConditions(for: sample)
            if sample.timestamp != lastTimestamp {
                lastTimestamp = sample.timestamp
                add(sample, now: now)
            }
        }
        if now.timeIntervalSince(lastPublish) >= Self.publishInterval {
            publish(now: now)
        }
    }

    /// The user holds the phone, so the direction is that of its own back camera, whatever mount is set. The raw
    /// attitude is used: the smoothed one lags behind the turn by the smoothing time (2° or more at a normal sweep),
    /// which would shift the whole skyline; the recorder's median takes care of the noise. The star alignment's
    /// compass correction is applied, so azimuths are true.
    private func add(_ sample: MotionSample, now: Date) {
        let attitude = sample.rawAttitude.withHeadingOffset(app.alignment.headingOffset(for: app.mountProfile))
        let direction = HorizontalCoordinate(vector: attitude.deviceToWorld * DeviceAttitude.backCameraAxis)
        if let reason = recorder.add(azimuth: direction.azimuth, altitude: direction.altitude,
                                     timestamp: sample.timestamp, quality: headingQuality(of: sample)) {
            lastRejection = (reason, now)
        }
    }

    /// In gyro lock the heading is only meaningful once it was transferred from the compass or set by a star.
    private func updateHeadingConditions(for sample: MotionSample) {
        let motion = app.motion
        let isGyroLock = motion.headingSource == .gyroLock
        let alignment = app.alignment
        let isAligned = alignment.isAligned && alignment.isApplicable(to: app.mountProfile)
        isHeadingMissing = isGyroLock && !(motion.isGyroHeadingReferenced || isAligned)
        hasInterference = !isGyroLock && (motion.magneticDisturbance ?? 0) > Self.interferenceThreshold
    }

    /// How far the heading can be trusted, 0…1, as the engine documents; `nil` when unknown. In gyro lock the heading
    /// comes from the compass transfer or the star alignment and magnetic interference cannot move it, so it counts
    /// as perfect once it is set and as useless before.
    private func headingQuality(of sample: MotionSample) -> Double? {
        if app.motion.headingSource == .gyroLock {
            return isHeadingMissing ? 0 : 1
        }
        switch sample.compassQuality {
        case .high: return 1
        case .medium: return 0.6
        case .low: return 0.2
        case .uncalibrated: return 0
        case .unavailable: return nil
        }
    }

    // MARK: Results

    /// Forgets everything swept so far.
    func startOver() {
        recorder.reset()
        lastRejection = nil
        publish(now: Date())
    }

    /// The recording as it stands, with unswept stretches filled as `fill` says (the stored skyline stays in them
    /// for `.keepBase`). The sweep can go on afterwards.
    func finish(fill: HorizonRecorder.UnrecordedFill) -> HorizonRecorder.Recording {
        recorder.finish(fill: fill, base: storedSkyline)
    }

    /// For each whole degree 0…359, whether the sweep has reached it.
    var recordedMask: [Bool] { recorder.recordedMask }

    // MARK: Reading

    private func publish(now: Date) {
        lastPublish = now
        let recording = recorder.finish(fill: .keepBase, base: storedSkyline)
        let next = HorizonReading(
            azimuth: recorder.lastAzimuth, altitude: recorder.lastAltitude, coverage: recording.coverage,
            recordedBins: recorder.recordedBinCount, skyline: recording.profile, gaps: recording.gaps,
            hint: hint(at: now))
        if next != reading { reading = next }
    }

    /// What to tell the person, from the latest rejection (if recent), the speed and the compass conditions.
    private func hint(at now: Date) -> HorizonHint? {
        switch app.motion.status {
        case .unavailable: return .noSensors
        case .failed(let message): return .sensorProblem(message)
        case .idle, .starting, .running: break
        }
        let recent = lastRejection.flatMap { now.timeIntervalSince($0.date) < Self.hintDuration ? $0.reason : nil }
        if recent == .lowQuality {
            return isHeadingMissing ? .headingNotSet : .calibrateCompass
        }
        // Before the speed: samples out of range do not update the recorder's sweep rate, so it may be stale.
        if recent == .outOfRange { return .aimAtSkyline }
        let maximumRate = recorder.configuration.maximumSweepRate
        if recent == .tooFast || (recorder.sweepRate ?? 0) > Self.warningFraction * maximumRate {
            return .slowDown
        }
        if hasInterference { return .interference }
        if recorder.lastAzimuth == nil { return .waiting }
        if recorder.recordedBinCount >= HorizonProfile.binCount { return .complete }
        return nil
    }
}

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
            return "Recording a skyline needs the motion sensors of an iPhone, which the Simulator does not have."
        case .sensorProblem(let message):
            return message
        case .waiting:
            return "Starting the motion sensors\u{2026}"
        case .headingNotSet:
            return "The heading is not set. Align on a star in Aim, or switch the heading source to Compass."
        case .calibrateCompass:
            return "The compass needs calibrating. Wave the phone in a figure 8."
        case .slowDown:
            return "Slow down."
        case .aimAtSkyline:
            return "Aim the camera at the skyline."
        case .interference:
            return "Magnetic interference nearby. Keep away from cars and metal."
        case .complete:
            return "The whole circle is recorded. Tap Done."
        }
    }

    var systemImage: String {
        switch self {
        case .noSensors, .sensorProblem, .headingNotSet, .calibrateCompass, .interference:
            return "exclamationmark.triangle.fill"
        case .waiting: return "hourglass"
        case .slowDown: return "tortoise.fill"
        case .aimAtSkyline: return "scope"
        case .complete: return "checkmark.circle.fill"
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
    /// The skyline as it stands: swept stretches, small gaps closed, the rest from the previous skyline.
    var skyline: HorizonProfile
    /// The stretches still to be swept.
    var gaps: [AzimuthRange]
    var hint: HorizonHint?
    /// Whether a bin has been recorded at all.
    var hasSamples: Bool

    static let empty = HorizonReading(azimuth: nil, altitude: nil, coverage: 0, skyline: .flat, gaps: [.full],
                                      hint: .waiting, hasSamples: false)
}

/// Feeds the motion sensors' newest attitude to a `HorizonRecorder` while the recording screen is open.
///
/// The recorder gets every new sample (60 per second); the observable `reading` is refreshed at ten hertz, so the view
/// tree is not invalidated with every sample.
@MainActor
@Observable
final class HorizonRecordingModel {
    /// Seconds between refreshes of the reading.
    private static let publishInterval = 0.09
    private static let loopInterval: Duration = .milliseconds(16)
    /// A rejection is shown for this long after the last sample it applied to.
    private static let hintDuration = 1.2
    /// The recorder drops samples above `maximumSweepRate`; the warning starts at this fraction of it.
    private static let warningFraction = 0.7
    /// Above this fractional deviation from the expected field strength the compass is probably disturbed (as in Aim).
    private static let interferenceThreshold = 0.25

    private(set) var reading = HorizonReading.empty

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let base: HorizonProfile?
    @ObservationIgnored private var recorder = HorizonRecorder()
    @ObservationIgnored private var lastTimestamp: TimeInterval?
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var lastRejection: (reason: HorizonRecorder.Rejection, date: Date)?

    /// - Parameters:
    ///   - app: The app model, for the motion sensors, the alignment and the mount.
    ///   - base: The site's current skyline, which unswept stretches keep.
    init(app: AppModel, base: HorizonProfile?) {
        self.app = app
        self.base = base
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
        if let sample = app.motion.latestSample(), sample.timestamp != lastTimestamp {
            lastTimestamp = sample.timestamp
            add(sample, now: now)
        }
        if now.timeIntervalSince(lastPublish) >= Self.publishInterval {
            publish(now: now)
        }
    }

    /// The phone's own back camera is what the person holds along the skyline, so the mount is not applied; the
    /// star alignment's compass correction is, so azimuths are true.
    private func add(_ sample: MotionSample, now: Date) {
        let attitude = sample.attitude.withHeadingOffset(app.alignment.headingOffset(for: app.mountProfile))
        let direction = HorizontalCoordinate(vector: attitude.deviceToWorld * DeviceAttitude.backCameraAxis)
        if let reason = recorder.add(azimuth: direction.azimuth, altitude: direction.altitude,
                                     timestamp: sample.timestamp, quality: headingQuality(of: sample)) {
            lastRejection = (reason, now)
        }
    }

    /// How far the heading can be trusted, 0…1, as the engine documents; `nil` when unknown.
    private func headingQuality(of sample: MotionSample) -> Double? {
        let motion = app.motion
        if motion.headingSource == .gyroLock {
            // Immune to magnetic interference once the heading comes from the compass transfer or a star alignment.
            return motion.isGyroHeadingReferenced || app.alignment.isAligned ? 1 : 0
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

    /// The recording as it stands. The sweep can go on afterwards.
    func finish(fill: HorizonRecorder.UnrecordedFill, keepingPrevious: Bool) -> HorizonRecorder.Recording {
        recorder.finish(fill: fill, base: keepingPrevious ? base : nil)
    }

    // MARK: Reading

    private func publish(now: Date) {
        lastPublish = now
        let recording = recorder.finish(fill: .keepBase, base: base)
        let next = HorizonReading(
            azimuth: recorder.lastAzimuth, altitude: recorder.lastAltitude, coverage: recording.coverage,
            skyline: recording.profile, gaps: recording.gaps, hint: hint(at: now),
            hasSamples: recorder.recordedBinCount > 0)
        if next != reading { reading = next }
    }

    private func hint(at now: Date) -> HorizonHint? {
        let motion = app.motion
        switch motion.status {
        case .unavailable: return .noSensors
        case .failed(let message): return .sensorProblem(message)
        case .idle, .starting: return .waiting
        case .running: break
        }
        guard lastTimestamp != nil else { return .waiting }

        let configuration = recorder.configuration
        if let quality = headingQuality(), quality < configuration.minimumQuality {
            return motion.headingSource == .gyroLock ? .headingNotSet : .calibrateCompass
        }
        if let rejection = lastRejection, now.timeIntervalSince(rejection.date) < Self.hintDuration {
            switch rejection.reason {
            case .tooFast: return .slowDown
            case .outOfRange: return .aimAtSkyline
            case .lowQuality: return motion.headingSource == .gyroLock ? .headingNotSet : .calibrateCompass
            case .invalid: break
            }
        }
        if let rate = recorder.sweepRate, rate > configuration.maximumSweepRate * Self.warningFraction {
            return .slowDown
        }
        if motion.headingSource == .compass, let disturbance = motion.magneticDisturbance,
           disturbance > Self.interferenceThreshold {
            return .interference
        }
        if recorder.recordedBinCount == HorizonProfile.binCount { return .complete }
        return nil
    }

    /// The quality of the newest sample, for the standing warning about the compass.
    private func headingQuality() -> Double? {
        guard let sample = app.motion.latestSample() else { return nil }
        return headingQuality(of: sample)
    }
}

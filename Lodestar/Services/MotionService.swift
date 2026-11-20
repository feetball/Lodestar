import CoreMotion
import Foundation
import LodestarKit
import Observation
import os

/// The phone's attitude from CoreMotion at 60 Hz, as true-north-referenced `DeviceAttitude`s.
///
/// Samples are produced on a private queue and published through a lock (`latestSample()`), so render loops can
/// poll them from any thread. The observable properties are low-rate state, refreshed on the main actor about
/// twice a second while running.
///
/// Heading sources:
/// - Compass: the magnetic-north frame plus the WMM declination (works without Location Services), falling back to
///   CoreMotion's true-north frame on a device without the magnetic one.
/// - Gyro lock: once the compass frame has settled and the phone stands still, the compass heading is transferred to
///   the gyro-only frame, which magnetic disturbances cannot affect. Until then the compass frame keeps running. The
///   transfer is refused (`isGyroHeadingReferenced` stays `false`, `frameEpoch` advances) if the phone turns more
///   than a degree about the vertical or tilts by several degrees in the meantime, or if it takes longer than two
///   seconds; the heading then has to be set by star alignment.
@MainActor
@Observable
final class MotionService {
    private static let updateInterval = 1.0 / 60.0
    private static let pollInterval: Duration = .milliseconds(500)
    /// Polls without any new sample after which the sensor stream counts as stalled (about 3 s).
    private static let stalledPollLimit = 6

    private(set) var status: MotionStatus = .idle
    private(set) var compassQuality: CompassQuality = .unavailable
    /// Fractional deviation |measured field − WMM expected| / expected, `nil` when unknown. Above 0.25 the
    /// compass is probably disturbed.
    private(set) var magneticDisturbance: Double?
    /// The source the samples actually come from.
    private(set) var headingSource: HeadingSource = .compass
    /// In gyro lock: whether the heading was transferred from the compass (otherwise the user must align on a star).
    private(set) var isGyroHeadingReferenced = false
    /// Increases whenever the attitude reference changes discontinuously (frame change, failed gyro transfer,
    /// large declination step); alignments made before are invalid.
    private(set) var frameEpoch = 0
    private(set) var referenceDescription = "Not running"

    private let pipeline = OSAllocatedUnfairLock(initialState: MotionProcessor())
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "net.kuecker.Lodestar.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var lastSampleCount = 0
    @ObservationIgnored private var stalledPolls = 0

    /// The newest sample, or `nil` when none has arrived yet. Callable from any thread; cheap.
    nonisolated func latestSample() -> MotionSample? {
        #if DEBUG
        if let sample = screenshotSample.withLock({ $0 }) { return sample }
        #endif
        return pipeline.withLock { $0.latest }
    }

    /// The sample nearest `time` (seconds since boot, as `MotionSample.timestamp`) among those of the last half second,
    /// or `nil` when none is close to it. It pairs the attitude with a camera frame captured at `time`. Callable from
    /// any thread; cheap.
    nonisolated func sample(at time: TimeInterval) -> MotionSample? {
        #if DEBUG
        if let sample = screenshotSample.withLock({ $0 }) { return sample }
        #endif
        return pipeline.withLock { $0.sample(at: time) }
    }

    #if DEBUG
    /// A fixed sample that replaces the sensors in screenshot mode.
    private let screenshotSample = OSAllocatedUnfairLock<MotionSample?>(initialState: nil)

    private var isUsingScreenshotPointing: Bool { screenshotSample.withLock { $0 } != nil }

    /// Replaces the sensors with a level, portrait back-camera pointing at `boresight` (screenshot mode).
    func useScreenshotPointing(_ boresight: HorizontalCoordinate) {
        let forward = boresight.unitVector
        let up = (Vector3(0, 0, 1) - forward * forward.z).normalized
        let back = -forward
        let right = up.cross(back)
        // CoreMotion's reference frame is north-west-up; its matrix rows are the device axes.
        func northWestUp(_ v: Vector3) -> Vector3 { Vector3(v.y, -v.x, v.z) }
        let matrix = Matrix3(rows: northWestUp(right), northWestUp(up), northWestUp(back))
        guard let attitude = DeviceAttitude(matrix: matrix, referenceAzimuth: 0, timestamp: 1) else { return }
        let sample = MotionSample(attitude: attitude, rawAttitude: attitude, gravity: matrix * Vector3(0, 0, -1),
                                  angularSpeed: 0, magneticFieldMicrotesla: nil, compassQuality: .high, timestamp: 1)
        screenshotSample.withLock { $0 = sample }
        status = .running
        compassQuality = .high
        referenceDescription = "Screenshot mode"
    }
    #endif

    /// Applies the current settings. Call as often as needed: nothing restarts unless the heading source changes;
    /// a new declination takes effect on the running stream.
    func configure(headingSource: HeadingSource, smoothingTimeConstant: Double, magneticReference: MagneticReference?) {
        let availability = Self.frameAvailability()
        let restart = pipeline.withLock { processor -> MotionStreamStart? in
            processor.setSmoothing(smoothingTimeConstant)
            processor.setMagneticReference(magneticReference)
            return processor.setSource(headingSource, availability: availability)
        }
        if let restart, isActive { launch(restart) }
        publish()
    }

    /// Starts the sensors. Idempotent.
    func start() {
        #if DEBUG
        if isUsingScreenshotPointing { return }
        #endif
        guard !isActive else { return }
        guard manager.isDeviceMotionAvailable else {
            update(\.status, to: .unavailable)
            return
        }
        isActive = true
        status = .starting
        lastSampleCount = 0
        let availability = Self.frameAvailability()
        let first = pipeline.withLock { $0.start(availability: availability) }
        launch(first)
        startPolling()
        publish()
    }

    /// Stops the sensors and clears the latest sample. Idempotent.
    func stop() {
        guard isActive else { return }
        isActive = false
        manager.stopDeviceMotionUpdates()
        pollTask?.cancel()
        pollTask = nil
        pipeline.withLock { $0.stop() }
        status = .idle
        publish()
    }

    // MARK: CoreMotion

    /// (Re)starts CoreMotion in the stream's frame. The old stream's queued samples are dropped by their id.
    private func launch(_ start: MotionStreamStart) {
        manager.stopDeviceMotionUpdates()
        manager.deviceMotionUpdateInterval = Self.updateInterval
        manager.showsDeviceMovementDisplay = true // lets iOS show its figure-eight calibration prompt
        manager.startDeviceMotionUpdates(
            using: start.stream.referenceFrame, to: queue,
            withHandler: Self.makeHandler(pipeline: pipeline, streamID: start.id, onEvent: Self.makeEventSink(for: self)))
        stalledPolls = 0
    }

    private static func frameAvailability() -> MotionFrameAvailability {
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        return MotionFrameAvailability(magneticNorth: frames.contains(.xMagneticNorthZVertical),
                                       trueNorth: frames.contains(.xTrueNorthZVertical))
    }

    /// Builds the CoreMotion handler. It must be created in a nonisolated context: a closure literal formed inside
    /// a main-actor method would be inferred main-actor-isolated and trap at runtime when CoreMotion calls it on
    /// the motion queue. It only touches the lock-protected pipeline and the Sendable event sink.
    nonisolated private static func makeHandler(
        pipeline: OSAllocatedUnfairLock<MotionProcessor>,
        streamID: Int,
        onEvent: @escaping @Sendable (MotionEvent) -> Void
    ) -> CMDeviceMotionHandler {
        return { motion, error in
            if let error {
                switch MotionFailure(error) {
                case .movementRequired:
                    pipeline.withLock { $0.noteCalibrationRequested(streamID: streamID) }
                case .trueNorthUnavailable:
                    onEvent(.trueNorthUnavailable(stream: streamID))
                case .other(let code):
                    onEvent(.failed(stream: streamID, code: code))
                }
                return
            }
            guard let motion else { return }
            let input = MotionInput(motion)
            if let event = pipeline.withLock({ $0.process(input, streamID: streamID) }) {
                onEvent(event)
            }
        }
    }

    nonisolated private static func makeEventSink(for service: MotionService) -> @Sendable (MotionEvent) -> Void {
        return { [weak service] event in
            Task { @MainActor [weak service] in service?.handle(event) }
        }
    }

    private func handle(_ event: MotionEvent) {
        guard isActive else { return }
        let availability = Self.frameAvailability()
        switch event {
        case .compassSteady:
            if let next = pipeline.withLock({ $0.switchToGyroFrame() }) { launch(next) }
        case .trueNorthUnavailable(let id):
            if let next = pipeline.withLock({ $0.recoverFromTrueNorthFailure(streamID: id, availability: availability) }) {
                launch(next)
            }
        case .failed(let id, let code):
            let (isCurrent, sampleCount) = pipeline.withLock { ($0.isCurrent(streamID: id), $0.sampleCount) }
            if isCurrent {
                // The message stays until samples that arrive after the error show that the stream carries on.
                lastSampleCount = sampleCount
                stalledPolls = 0
                status = .failed("The motion sensors reported an error (code \(code)).")
            }
        }
        publish()
    }

    // MARK: Polling

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.poll()
            }
        }
    }

    private func poll() {
        let snapshot = publish()
        guard isActive else { return }
        if snapshot.sampleCount != lastSampleCount {
            lastSampleCount = snapshot.sampleCount
            stalledPolls = 0
            update(\.status, to: .running)
        } else {
            stalledPolls += 1
            if stalledPolls >= Self.stalledPollLimit { recoverFromStall() }
        }
    }

    /// No samples for a while: start over (gyro lock begins again from the compass frame).
    private func recoverFromStall() {
        status = .failed("Motion data stopped arriving.")
        let availability = Self.frameAvailability()
        let restart = pipeline.withLock { $0.start(availability: availability) }
        launch(restart)
    }

    @discardableResult
    private func publish() -> MotionSnapshot {
        let snapshot = pipeline.withLock { $0.snapshot }
        #if DEBUG
        if isUsingScreenshotPointing { return snapshot }
        #endif
        update(\.compassQuality, to: snapshot.compassQuality)
        update(\.magneticDisturbance, to: snapshot.magneticDisturbance)
        update(\.frameEpoch, to: snapshot.frameEpoch)
        update(\.isGyroHeadingReferenced, to: snapshot.phase == .referenced)
        update(\.headingSource, to: Self.effectiveSource(of: snapshot, isActive: isActive))
        update(\.referenceDescription, to: Self.description(of: snapshot, isActive: isActive))
        return snapshot
    }

    /// Writes a property only when its value changes, so observers are not woken twice a second for nothing.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<MotionService, Value>, to value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private static func effectiveSource(of snapshot: MotionSnapshot, isActive: Bool) -> HeadingSource {
        guard isActive, let stream = snapshot.stream else { return snapshot.source }
        return stream == .arbitrary ? .gyroLock : .compass
    }

    private static func description(of snapshot: MotionSnapshot, isActive: Bool) -> String {
        guard isActive, let stream = snapshot.stream else { return "Not running" }
        let isPending = snapshot.phase == .awaitingCompass || snapshot.phase == .compassCaptured
        switch stream {
        case .magneticNorth:
            let base = snapshot.isDeclinationKnown ? "Magnetic north + WMM" : "Magnetic north (declination unknown)"
            return isPending ? "\(base), gyro lock pending" : base
        case .trueNorth:
            return isPending ? "True north, gyro lock pending" : "True north"
        case .arbitrary:
            switch snapshot.phase {
            case .referenced: return "Gyro lock"
            case .awaitingGyro: return "Gyro lock (setting heading)"
            default: return "Gyro lock (heading not set)"
            }
        }
    }
}

// MARK: - CoreMotion conversions

/// How a CoreMotion error affects the stream.
private enum MotionFailure {
    /// `CMErrorDeviceRequiresMovement`: the compass needs calibrating; delivery continues.
    case movementRequired
    /// `CMErrorTrueNorthNotAvailable`: the true-north frame cannot deliver.
    case trueNorthUnavailable
    case other(code: Int)

    init(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain == CMErrorDomain else {
            self = .other(code: nsError.code)
            return
        }
        switch nsError.code {
        case Int(CMErrorDeviceRequiresMovement.rawValue): self = .movementRequired
        case Int(CMErrorTrueNorthNotAvailable.rawValue): self = .trueNorthUnavailable
        default: self = .other(code: nsError.code)
        }
    }
}

private extension MotionStream {
    var referenceFrame: CMAttitudeReferenceFrame {
        switch self {
        case .magneticNorth: return .xMagneticNorthZVertical
        case .trueNorth: return .xTrueNorthZVertical
        case .arbitrary: return .xArbitraryZVertical
        }
    }
}

extension CompassQuality {
    init(_ accuracy: CMMagneticFieldCalibrationAccuracy) {
        switch accuracy {
        case .high: self = .high
        case .medium: self = .medium
        case .low: self = .low
        case .uncalibrated: self = .uncalibrated
        @unknown default: self = .uncalibrated
        }
    }
}

extension MotionInput {
    /// Copies the values this app uses out of a (non-Sendable) CoreMotion sample.
    init(_ motion: CMDeviceMotion) {
        let m = motion.attitude.rotationMatrix
        let gravity = Vector3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        let rate = motion.rotationRate
        let field = motion.magneticField
        // The rotation rate is in device coordinates; "up" there is opposite to gravity.
        let up = Vector3(-gravity.x, -gravity.y, -gravity.z).normalized
        self.init(matrix: Matrix3(rows: Vector3(m.m11, m.m12, m.m13),
                                  Vector3(m.m21, m.m22, m.m23),
                                  Vector3(m.m31, m.m32, m.m33)),
                  gravity: gravity,
                  angularSpeed: (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot() * 180 / .pi,
                  yawRate: Vector3(rate.x, rate.y, rate.z).dot(up) * 180 / .pi,
                  fieldMicrotesla: (field.field.x * field.field.x + field.field.y * field.field.y
                                    + field.field.z * field.field.z).squareRoot(),
                  fieldAccuracy: CompassQuality(field.accuracy),
                  timestamp: motion.timestamp)
    }
}

extension MotionService: MotionSampleSource {}

import Foundation
import LodestarKit

/// The CoreMotion reference frame a stream of samples is delivered in.
enum MotionStream: Sendable, Equatable {
    /// `.xMagneticNorthZVertical`; its x axis points to magnetic north, whose true azimuth is the declination.
    case magneticNorth
    /// `.xTrueNorthZVertical`; its x axis points to true north.
    case trueNorth
    /// `.xArbitraryZVertical`; gyro only. Its heading is known only after it was transferred from a compass frame.
    case arbitrary
}

/// Which compass-referenced frames CoreMotion offers on this device.
struct MotionFrameAvailability: Sendable, Equatable {
    var magneticNorth: Bool
    var trueNorth: Bool
}

/// A request to (re)start CoreMotion in `stream`. Samples of that stream must be fed back with `id`, so samples
/// still queued from a previous stream are recognised and dropped.
struct MotionStreamStart: Sendable, Equatable {
    var stream: MotionStream
    var id: Int
}

/// What the sensor queue asks of the main actor. Each event names the stream it came from.
enum MotionEvent: Sendable, Equatable {
    /// Gyro lock: a steady compass sample is stored, switch to the gyro frame now.
    case compassSteady(stream: Int)
    /// CoreMotion reported `CMErrorTrueNorthNotAvailable`.
    case trueNorthUnavailable(stream: Int)
    /// CoreMotion reported another error.
    case failed(stream: Int, code: Int)
}

/// One CoreMotion sample reduced to plain values (copied on the motion queue).
struct MotionInput: Sendable {
    /// `CMRotationMatrix` as rows: `v_device = matrix · v_reference`.
    var matrix: Matrix3
    /// Gravity in device coordinates, unit g.
    var gravity: Vector3
    /// Rotation speed in degrees per second.
    var angularSpeed: Double
    /// Rotation rate about the vertical axis in degrees per second (counter-clockwise seen from above is positive):
    /// the part of the rotation that turns the heading.
    var yawRate: Double
    /// Magnitude of the calibrated magnetic field in microtesla; 0 when the frame provides none.
    var fieldMicrotesla: Double
    /// Calibration accuracy reported with the field.
    var fieldAccuracy: CompassQuality
    /// Seconds since boot (`CMLogItem.timestamp`).
    var timestamp: TimeInterval

    /// Whether the numbers that every step depends on are finite. CoreMotion does not deliver anything else; the
    /// check keeps a corrupt sample from reaching the filters.
    var isUsable: Bool {
        matrix.isFinite && gravity.isFinite && angularSpeed.isFinite && yawRate.isFinite && timestamp.isFinite
    }
}

/// Where the transfer of the compass heading to the gyro-only frame stands.
enum GyroLockPhase: Sendable, Equatable {
    /// Compass heading source (or not running).
    case inactive
    /// Gyro lock wanted; the compass frame runs until the phone stands still.
    case awaitingCompass
    /// A steady compass sample is stored; the frame is being switched.
    case compassCaptured
    /// The gyro frame runs; waiting for a steady sample to compute its heading.
    case awaitingGyro
    /// The gyro frame carries the heading of the compass.
    case referenced
    /// The gyro frame has no known heading: the transfer failed or there is no compass.
    case unreferenced
}

/// The low-rate state the main actor publishes.
struct MotionSnapshot: Sendable, Equatable {
    var stream: MotionStream?
    var phase: GyroLockPhase
    var source: HeadingSource
    var compassQuality: CompassQuality
    var magneticDisturbance: Double?
    var frameEpoch: Int
    var sampleCount: Int
    var isDeclinationKnown: Bool
}

/// The sensor-fusion state machine behind `MotionService`, free of CoreMotion so it can be reasoned about (and
/// tested) with plain numbers.
///
/// It turns raw samples into `MotionSample`s: attitudes referenced to true north, smoothing, compass quality and
/// magnetic disturbance. It also runs the gyro-lock transfer: the compass frame is watched until the phone
/// stands still, a steady attitude is stored, and the first steady attitude of the gyro-only frame gives that
/// frame's azimuth, so the gyro attitude continues exactly where the compass attitude was.
///
/// The service shares one instance with the motion queue behind a lock; every method is short.
struct MotionProcessor: Sendable {
    // MARK: Tuning

    /// Rotation speed below which the phone counts as standing still, in degrees per second.
    static let stillSpeed = 2.0
    /// How long the phone must stand still before a sample is trusted for the heading transfer, in seconds.
    static let steadyDuration = 0.25
    /// How long a compass frame must have been running before its heading is trusted for the transfer, in seconds:
    /// the fused heading of a freshly started stream has not settled yet.
    static let compassSettlingTime = 1.0
    /// Largest change of the gravity direction, in degrees, between the stored compass sample and the first
    /// steady gyro sample; more means the phone was tilted in between.
    static let maximumTiltChange = 3.0
    /// Most the phone may turn about the vertical axis, in degrees, between the compass sample and the heading
    /// transfer. Gravity cannot show such a turn (a plain pan), yet it would put the transferred heading off by
    /// exactly its size, so the rotation rate about the vertical is integrated and the transfer is refused beyond
    /// this. A tilt changes nothing: the transfer compares only the headings of the two frames.
    static let maximumTransferTurn = 1.0
    /// Longest interval between two samples that counts towards the integrated turn, in seconds. A longer gap
    /// (such as the one while CoreMotion switches frames) is counted at the rate of the sample that ends it.
    static let maximumSampleGap = 0.1
    /// Time allowed for the first steady gyro sample after the frame switch, in seconds.
    static let transferTimeout = 2.0
    /// A change of the compass reference azimuth beyond this many degrees makes alignments invalid.
    static let referenceStep = 0.5
    /// Declination changes smaller than this many degrees are ignored.
    static let declinationResolution = 0.01
    /// Time constant of the field-strength average, in seconds.
    static let fieldAveragingTime = 1.0
    /// Smoothing time constants below this many seconds mean "no smoothing".
    static let minimumSmoothing = 0.01
    static let defaultSmoothing = 0.12
    /// How far back published samples are kept for `sample(at:)`, in seconds: longer than a camera frame takes to
    /// reach the screen.
    static let historyDuration = 0.5
    /// A time further than this many seconds from every kept sample has no sample (a stalled sensor).
    static let historyReach = 0.1

    // MARK: Configuration

    private(set) var source: HeadingSource = .compass
    private var declination: Double?
    private var expectedField: Double?
    private var smoothingTimeConstant = MotionProcessor.defaultSmoothing

    // MARK: Stream

    private(set) var stream: MotionStream?
    private var streamID = 0
    private var phase: GyroLockPhase = .inactive
    private var gyroAzimuth: Double?
    /// The gyro frame's azimuth was derived from a magnetic frame whose declination was still unknown.
    private var gyroAzimuthLacksDeclination = false
    private var storedCompassSample: CompassSample?
    private var transferStart: TimeInterval?
    private var transferLastTimestamp: TimeInterval?
    /// Degrees the phone has turned about the vertical axis since the compass sample was stored.
    private var transferTurn = 0.0
    /// The compass reference azimuth the current alignments are valid for.
    private var referenceAzimuth: Double?

    // MARK: Filters

    private var smoother = AttitudeSmoother(timeConstant: MotionProcessor.defaultSmoothing)
    private var streamStart: TimeInterval?
    private var stillSince: TimeInterval?
    private var fieldAverage: Double?
    private var fieldTimestamp: TimeInterval?
    private var isCalibrationRequested = false

    // MARK: Results

    private(set) var latest: MotionSample?
    /// The samples published in the last `historyDuration` seconds, oldest first.
    private var history: [MotionSample] = []
    private(set) var sampleCount = 0
    private(set) var frameEpoch = 0
    private var compassQuality: CompassQuality = .unavailable
    private var magneticDisturbance: Double?

    /// A steady attitude taken in a compass frame, kept for the gyro-lock transfer.
    private struct CompassSample: Sendable {
        var matrix: Matrix3
        var azimuth: Double
        var gravity: Vector3
        /// The frame was magnetic north and the declination, hence `azimuth`, was not known yet.
        var lacksDeclination: Bool
    }

    /// The compass frame to prefer, if the device has one.
    static func compassStream(for availability: MotionFrameAvailability) -> MotionStream? {
        if availability.magneticNorth { return .magneticNorth }
        if availability.trueNorth { return .trueNorth }
        return nil
    }

    var snapshot: MotionSnapshot {
        MotionSnapshot(stream: stream, phase: phase, source: source, compassQuality: compassQuality,
                       magneticDisturbance: magneticDisturbance, frameEpoch: frameEpoch, sampleCount: sampleCount,
                       isDeclinationKnown: declination != nil)
    }

    func isCurrent(streamID id: Int) -> Bool {
        stream != nil && id == streamID
    }

    // MARK: Configuration

    /// Sets the attitude smoothing time constant in seconds; values under 0.01 turn smoothing off.
    mutating func setSmoothing(_ timeConstant: Double) {
        let value = timeConstant.isFinite ? min(max(timeConstant, 0), 2) : Self.defaultSmoothing
        guard value != smoothingTimeConstant else { return }
        smoothingTimeConstant = value
        smoother = AttitudeSmoother(timeConstant: value)
    }

    /// Sets the magnetic declination (applied to the magnetic frame without a restart) and the expected field
    /// strength. A declination step beyond `referenceStep` invalidates alignments.
    mutating func setMagneticReference(_ reference: MagneticReference?) {
        expectedField = reference.flatMap { value in
            value.expectedFieldMicrotesla.isFinite && value.expectedFieldMicrotesla > 0
                ? value.expectedFieldMicrotesla : nil
        }
        let newDeclination = reference.flatMap { $0.declination.isFinite ? $0.declination : nil }
        guard newDeclination != declination else { return }
        if let old = declination, let new = newDeclination, abs(new - old) < Self.declinationResolution { return }
        declination = newDeclination
        if stream == .magneticNorth {
            noteCompassReference(newDeclination ?? 0)
        } else if stream == .arbitrary, phase == .referenced, gyroAzimuthLacksDeclination,
                  let newDeclination, let azimuth = gyroAzimuth {
            // The gyro heading was transferred from a magnetic frame before the declination was known; add it now.
            gyroAzimuth = AstroMath.normalizeSignedDegrees(azimuth + newDeclination)
            gyroAzimuthLacksDeclination = false
            smoother.reset()
            frameEpoch += 1
        }
    }

    /// Changes the heading source. Returns the stream to restart in when the running frame must change.
    mutating func setSource(_ newSource: HeadingSource, availability: MotionFrameAvailability) -> MotionStreamStart? {
        guard newSource != source else { return nil }
        source = newSource
        guard let running = stream else { return nil }
        let compass = Self.compassStream(for: availability)
        switch newSource {
        case .gyroLock:
            // The running compass frame is what the transfer starts from: wait there for a steady phone.
            guard compass != nil, running != .arbitrary else { return nil }
            phase = .awaitingCompass
            storedCompassSample = nil
            return nil
        case .compass:
            guard running == .arbitrary, let compass else {
                if running != .arbitrary { phase = .inactive; storedCompassSample = nil }
                return nil
            }
            // Leaving the gyro frame: its heading and the compass heading differ by the accumulated drift. The heading
            // is dropped with it, so a later transfer starts clean (and a declination step does not move a new one by
            // the declination it already contains).
            frameEpoch += 1
            phase = .inactive
            gyroAzimuth = nil
            gyroAzimuthLacksDeclination = false
            return begin(compass)
        }
    }

    // MARK: Lifecycle

    /// Starts (or restarts) in the first frame the source needs: the compass frame, which for gyro lock is only the
    /// first step. Restarting while the gyro frame carries a transferred heading loses that heading, which starts a
    /// new alignment epoch.
    mutating func start(availability: MotionFrameAvailability) -> MotionStreamStart {
        if stream == .arbitrary, phase == .referenced || phase == .unreferenced { frameEpoch += 1 }
        storedCompassSample = nil
        gyroAzimuth = nil
        gyroAzimuthLacksDeclination = false
        resetTransfer()
        guard let compass = Self.compassStream(for: availability) else {
            // No compass at all: gyro only, heading unknown until the user aligns on a star.
            phase = .unreferenced
            frameEpoch += 1
            return begin(.arbitrary)
        }
        phase = source == .gyroLock ? .awaitingCompass : .inactive
        return begin(compass)
    }

    /// Gyro lock: switches to the gyro-only frame after `compassSteady`. `nil` if the event is stale.
    mutating func switchToGyroFrame() -> MotionStreamStart? {
        guard phase == .compassCaptured, storedCompassSample != nil else { return nil }
        phase = .awaitingGyro
        transferStart = nil // the turn since the capture is kept: it counts against the transfer
        return begin(.arbitrary)
    }

    /// The true-north frame cannot deliver: fall back to the magnetic frame, or to gyro only.
    mutating func recoverFromTrueNorthFailure(streamID id: Int, availability: MotionFrameAvailability) -> MotionStreamStart? {
        guard stream == .trueNorth, id == streamID else { return nil }
        if availability.magneticNorth {
            return begin(.magneticNorth)
        }
        phase = .unreferenced
        frameEpoch += 1
        return begin(.arbitrary)
    }

    /// Stops processing and forgets everything but the alignment epoch and the configuration.
    /// Stopping the gyro-only frame loses its heading, so an alignment made in it becomes invalid.
    mutating func stop() {
        if stream == .arbitrary, phase == .referenced || phase == .unreferenced { frameEpoch += 1 }
        stream = nil
        streamID += 1
        phase = .inactive
        gyroAzimuth = nil
        gyroAzimuthLacksDeclination = false
        storedCompassSample = nil
        resetTransfer()
        resetFilters()
        latest = nil
        history = []
        sampleCount = 0
        compassQuality = .unavailable
        magneticDisturbance = nil
        isCalibrationRequested = false
    }

    /// CoreMotion asked the user to move the phone to calibrate the compass.
    mutating func noteCalibrationRequested(streamID id: Int) {
        if id == streamID { isCalibrationRequested = true }
    }

    // MARK: Samples

    /// Processes one sample of stream `id`. Returns an event for the main actor when one is due.
    mutating func process(_ input: MotionInput, streamID id: Int) -> MotionEvent? {
        guard id == streamID, let stream, input.isUsable else { return nil }
        var input = input
        if !input.fieldMicrotesla.isFinite { input.fieldMicrotesla = 0 }
        sampleCount += 1
        if streamStart == nil { streamStart = input.timestamp }
        updateStillness(with: input)
        updateCompass(with: input, stream: stream)

        switch stream {
        case .magneticNorth, .trueNorth:
            let azimuth = Self.referenceAzimuth(of: stream, declination: declination)
            publish(input, azimuth: azimuth)
            if phase == .compassCaptured {
                // The frame switch is still on its way: a turn since the capture makes the stored sample stale.
                accumulateTurn(with: input)
                if abs(transferTurn) > Self.maximumTransferTurn {
                    phase = .awaitingCompass
                    storedCompassSample = nil
                    resetTransfer()
                }
            } else if phase == .awaitingCompass, isSteady(at: input.timestamp), isSettled(at: input.timestamp),
                      compassQuality != .uncalibrated {
                storedCompassSample = CompassSample(matrix: input.matrix, azimuth: azimuth, gravity: input.gravity,
                                                    lacksDeclination: stream == .magneticNorth && declination == nil)
                phase = .compassCaptured
                resetTransfer()
                transferLastTimestamp = input.timestamp
                return .compassSteady(stream: streamID)
            }
        case .arbitrary:
            if phase == .awaitingGyro { resolveTransfer(with: input) }
            // While the transfer is pending the last compass sample stays published: the phone stood still, so it
            // is still right, whereas an arbitrary-frame sample has no heading yet.
            if phase != .awaitingGyro { publish(input, azimuth: gyroAzimuth ?? 0) }
        }
        return nil
    }

    // MARK: Private

    private static func referenceAzimuth(of stream: MotionStream, declination: Double?) -> Double {
        stream == .magneticNorth ? (declination ?? 0) : 0
    }

    private mutating func begin(_ next: MotionStream) -> MotionStreamStart {
        stream = next
        streamID += 1
        resetFilters()
        if next != .arbitrary {
            noteCompassReference(Self.referenceAzimuth(of: next, declination: declination))
        }
        return MotionStreamStart(stream: next, id: streamID)
    }

    private mutating func resetTransfer() {
        transferStart = nil
        transferLastTimestamp = nil
        transferTurn = 0
    }

    private mutating func resetFilters() {
        smoother.reset()
        streamStart = nil
        stillSince = nil
        fieldAverage = nil
        fieldTimestamp = nil
    }

    /// Records the compass reference azimuth; a step beyond `referenceStep` starts a new alignment epoch.
    private mutating func noteCompassReference(_ azimuth: Double) {
        guard let known = referenceAzimuth else {
            referenceAzimuth = azimuth
            return
        }
        if abs(AstroMath.normalizeSignedDegrees(azimuth - known)) > Self.referenceStep {
            frameEpoch += 1
            referenceAzimuth = azimuth
        }
    }

    private mutating func updateStillness(with input: MotionInput) {
        if input.angularSpeed < Self.stillSpeed {
            if stillSince == nil { stillSince = input.timestamp }
        } else {
            stillSince = nil
        }
    }

    private func isSteady(at timestamp: TimeInterval) -> Bool {
        guard let since = stillSince else { return false }
        return timestamp - since >= Self.steadyDuration
    }

    private func isSettled(at timestamp: TimeInterval) -> Bool {
        guard let start = streamStart else { return false }
        return timestamp - start >= Self.compassSettlingTime
    }

    private mutating func updateCompass(with input: MotionInput, stream: MotionStream) {
        guard stream != .arbitrary, input.fieldMicrotesla.isFinite, input.fieldMicrotesla > 0 else {
            compassQuality = .unavailable
            magneticDisturbance = nil
            fieldAverage = nil
            fieldTimestamp = nil
            return
        }
        if isCalibrationRequested, input.fieldAccuracy >= .medium { isCalibrationRequested = false }
        compassQuality = isCalibrationRequested ? .uncalibrated : input.fieldAccuracy

        if let average = fieldAverage, let last = fieldTimestamp, input.timestamp > last {
            let weight = 1 - exp(-(input.timestamp - last) / Self.fieldAveragingTime)
            fieldAverage = average + weight * (input.fieldMicrotesla - average)
        } else {
            fieldAverage = input.fieldMicrotesla
        }
        fieldTimestamp = input.timestamp

        if compassQuality >= .low, let expected = expectedField, let average = fieldAverage {
            magneticDisturbance = abs(average - expected) / expected
        } else {
            magneticDisturbance = nil
        }
    }

    /// Computes the gyro frame's azimuth from the first steady sample, or gives up after `transferTimeout`.
    private mutating func resolveTransfer(with input: MotionInput) {
        if transferStart == nil { transferStart = input.timestamp }
        guard let stored = storedCompassSample else {
            failTransfer()
            return
        }
        accumulateTurn(with: input)
        if abs(transferTurn) > Self.maximumTransferTurn {
            failTransfer()
            return
        }
        if isSteady(at: input.timestamp) {
            // `stored.matrix · T(stored.azimuth)` and `input.matrix · T(ψ)` describe one orientation; solve for ψ.
            // (Passing the stored matrix with its azimuth equals passing the equivalent true-north matrix
            // `worldToDevice · T(0)ᵀ` with azimuth 0: T(0)ᵀ·T(0) is the identity.)
            if stored.gravity.angle(to: input.gravity) <= Self.maximumTiltChange,
               var azimuth = ReferenceFrames.referenceAzimuth(ofArbitraryFrameAttitude: input.matrix,
                                                              knownFrameAttitude: stored.matrix,
                                                              knownFrameAzimuth: stored.azimuth) {
                // Set for this transfer alone: an earlier one may have left it set.
                gyroAzimuthLacksDeclination = false
                if stored.lacksDeclination {
                    if let declination {
                        azimuth = AstroMath.normalizeSignedDegrees(azimuth + declination)
                    } else {
                        gyroAzimuthLacksDeclination = true
                    }
                }
                gyroAzimuth = azimuth
                phase = .referenced
                smoother.reset()
            } else {
                failTransfer()
            }
        } else if let start = transferStart, input.timestamp - start > Self.transferTimeout {
            failTransfer()
        }
    }

    /// Adds the rotation about the vertical axis since the previous sample to the turn since the capture.
    private mutating func accumulateTurn(with input: MotionInput) {
        if let last = transferLastTimestamp, input.timestamp > last {
            transferTurn += input.yawRate * min(input.timestamp - last, Self.maximumSampleGap)
        }
        transferLastTimestamp = input.timestamp
    }

    private mutating func failTransfer() {
        gyroAzimuth = nil
        gyroAzimuthLacksDeclination = false
        phase = .unreferenced
        frameEpoch += 1
        smoother.reset()
    }

    private mutating func publish(_ input: MotionInput, azimuth: Double) {
        guard let raw = DeviceAttitude(matrix: input.matrix, referenceAzimuth: azimuth, timestamp: input.timestamp) else {
            return
        }
        let smoothed = smoothingTimeConstant >= Self.minimumSmoothing ? smoother.update(with: raw) : raw
        let usesField = stream != .arbitrary && input.fieldMicrotesla.isFinite && input.fieldMicrotesla > 0
        let sample = MotionSample(attitude: smoothed, rawAttitude: raw, gravity: input.gravity,
                                  angularSpeed: input.angularSpeed,
                                  magneticFieldMicrotesla: usesField ? input.fieldMicrotesla : nil,
                                  compassQuality: compassQuality, timestamp: input.timestamp)
        latest = sample
        history.append(sample)
        // The sample just added is never older than the cut-off, so there is always an index to keep from.
        let cutoff = sample.timestamp - Self.historyDuration
        if let firstKept = history.firstIndex(where: { $0.timestamp >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }
    }

    /// The published sample whose time is nearest `time` (seconds since boot, the clock of `MotionSample.timestamp`),
    /// for matching the attitude to a camera frame captured then; `nil` when none is kept within `historyReach` of it.
    func sample(at time: TimeInterval) -> MotionSample? {
        var nearest: MotionSample?
        var nearestGap = Self.historyReach
        for sample in history {
            let gap = abs(sample.timestamp - time)
            if gap <= nearestGap {
                nearest = sample
                nearestGap = gap
            }
        }
        return nearest
    }
}

import AVFoundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import ImageIO
import LodestarKit
import os

/// One processed camera frame, upright in portrait, with the optics it was captured with, so the overlay never
/// draws one zoom over a picture taken at another. `CGImage` is immutable; the wrapper keeps the hand-off
/// independent of whether the SDK already declares it `Sendable`.
struct CameraFrame: @unchecked Sendable {
    let image: CGImage
    /// `nil` while the format's field of view is unknown.
    let geometry: CameraGeometry?
}

/// Why the capture pipeline could not start.
enum CameraEngineFailure: Error, Sendable, Equatable {
    /// There is no back wide camera (the Simulator, for example).
    case noCamera
    /// The input or output could not be added to the session.
    case configuration
    /// `startRunning()` returned without a running session.
    case notRunning
}

/// Why the system interrupted the capture session.
enum CameraInterruption: Sendable, Equatable {
    case inBackground
    case deviceInUse
    case multitasking
    case systemPressure
    case other
}

/// What the capture pipeline reports to `CameraService`, in order.
enum CameraEngineEvent: Sendable, Equatable {
    case started
    case failed(CameraEngineFailure)
    /// The strongest zoom the active format supports, at most `CameraEngine.maximumZoom` (sent after each start).
    case zoomLimit(Double)
    case interrupted(CameraInterruption)
    case interruptionEnded
    case runtimeError(isRecoverable: Bool)
}

/// The capture pipeline: back wide camera, sample buffers, optional red-monochrome filter, `CGImage` frames.
///
/// Mutable state is confined to one queue or one lock each, which is why the class is `@unchecked Sendable`:
/// - `sessionQueue`: `session`, `output` wiring, `camera`, `isConfigured`, `isExposureCeilingRaised`.
///   `startRunning()` blocks, so session work never runs on the main thread.
/// - `frameQueue` (serial, as AVFoundation requires): `redFilter`, `appliedIntensity`, `lastFrameTime`,
///   `lastGeometry`. `CMSampleBuffer`, `CVPixelBuffer` and `CIFilter` never leave it.
/// - locks: `nightIntensity`, `frameSink`, `fieldOfViewHistory`, `requestedZoom`.
final class CameraEngine: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Frames are skipped when closer together than this, a little under 1/30 s so a 30 fps camera passes every
    /// frame while a faster one is thinned to about 30 fps.
    private static let minimumFrameInterval = 0.030
    /// Longest auto-exposure time allowed for the night preview (bounded by what the format supports).
    private static let nightExposureCeiling = CMTime(value: 1, timescale: 4)
    /// The most the picture is zoomed (digitally, on the wide camera), whatever the format would allow.
    static let maximumZoom = 8.0
    /// Seconds between setting a zoom and the first frame captured with it. Frames already in the pipeline when the
    /// zoom changes keep the field of view they were captured with.
    private static let zoomLatency = 0.1
    /// Field-of-view changes remembered for frames still in flight.
    private static let fieldOfViewHistoryLength = 8

    /// A field of view along the long side of the format, valid for frames presented from `validFrom` (seconds on
    /// the session's clock) on.
    private struct FieldOfViewChange {
        let validFrom: Double
        let degrees: Double
    }

    /// Session events in order; never finishes.
    let events: AsyncStream<CameraEngineEvent>
    private let eventSink: AsyncStream<CameraEngineEvent>.Continuation

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "net.kuecker.Lodestar.camera.session")
    private let frameQueue = DispatchQueue(label: "net.kuecker.Lodestar.camera.frames", qos: .userInitiated)
    private let context = CIContext()
    private let redFilter = CIFilter.colorMatrix()
    private let observations = NotificationObservations()

    private let nightIntensity = OSAllocatedUnfairLock<Double?>(initialState: nil)
    private let frameSink = OSAllocatedUnfairLock<AsyncStream<CameraFrame>.Continuation?>(initialState: nil)
    /// Oldest first; empty while the field of view is unknown.
    private let fieldOfViewHistory = OSAllocatedUnfairLock<[FieldOfViewChange]>(initialState: [])
    private let requestedZoom = OSAllocatedUnfairLock<Double>(initialState: 1)

    // sessionQueue only
    private var camera: AVCaptureDevice?
    private var isConfigured = false
    private var isExposureCeilingRaised = false
    private var reportedZoomLimit: Double?
    // frameQueue only
    private var appliedIntensity: Double?
    private var lastFrameTime = -Double.infinity
    private var lastGeometry: CameraGeometry?

    override init() {
        (events, eventSink) = AsyncStream.makeStream(of: CameraEngineEvent.self, bufferingPolicy: .unbounded)
        super.init()
        // Red monochrome: R' = intensity × luma(R, G, B), G' = B' = 0 (CIColorMatrix: s.r = dot(s, rVector) …).
        redFilter.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redFilter.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        redFilter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        observeSession()
    }

    /// A new stream of the newest frame only (older ones are dropped), ending when the engine stops. Call before
    /// `start()`; a previous stream is finished.
    func makeFrameStream() -> AsyncStream<CameraFrame> {
        let (stream, continuation) = AsyncStream.makeStream(of: CameraFrame.self, bufferingPolicy: .bufferingNewest(1))
        frameSink.withLock { sink in
            sink?.finish()
            sink = continuation
        }
        return stream
    }

    /// Configures the session on first use and starts it; reports `.started` or `.failed` through `events`.
    func start() {
        sessionQueue.async { [self] in
            do {
                let camera = try configuredCamera()
                prepare(camera)
                resetFrameState()
                if !session.isRunning { session.startRunning() }
                // The format a preset selects is only certain once the session runs: read the optics again.
                if session.isRunning { settleOptics(of: camera) }
                eventSink.yield(session.isRunning ? .started : .failed(.notRunning))
            } catch {
                eventSink.yield(.failed((error as? CameraEngineFailure) ?? .configuration))
            }
        }
    }

    /// Stops the session and ends the frame stream.
    func stop() {
        frameSink.withLock { sink in
            sink?.finish()
            sink = nil
        }
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Switches the red-monochrome filter (`intensity` 0…1) on or off (`nil`) for the following frames. The night
    /// preview also raises the auto-exposure ceiling, so stars show up in the dark.
    func setNightFilter(_ intensity: Double?) {
        let previous = nightIntensity.withLock { current -> Double? in
            let old = current
            current = intensity
            return old
        }
        guard (previous == nil) != (intensity == nil) else { return }
        sessionQueue.async { [self] in
            if let camera { applyExposureCeiling(to: camera, force: false) }
        }
    }

    /// Zooms the picture by `factor` (1 = the full field of view), limited to what the format allows and to
    /// `maximumZoom`. The geometry of the following frames reports the narrower field of view.
    func setZoom(_ factor: Double) {
        guard factor.isFinite else { return }
        let changed = requestedZoom.withLock { current -> Bool in
            defer { current = factor }
            return current != factor
        }
        guard changed else { return }
        sessionQueue.async { [self] in
            if isConfigured, let camera { applyZoom(to: camera) }
        }
    }

    // MARK: Session (sessionQueue)

    private func configuredCamera() throws -> AVCaptureDevice {
        if isConfigured, let camera { return camera }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraEngineFailure.noCamera
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        do {
            try wirePipeline(to: device)
        } catch {
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            throw error
        }
        camera = device
        isConfigured = true
        return device
    }

    /// Adds the camera input and the video output. Rotation is fixed before the session starts because changing it
    /// afterwards rebuilds the capture pipeline.
    private func wirePipeline(to device: AVCaptureDevice) throws {
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraEngineFailure.configuration
        }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { throw CameraEngineFailure.configuration }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { throw CameraEngineFailure.configuration }
        session.addOutput(output)

        guard let connection = output.connection(with: .video) else { throw CameraEngineFailure.configuration }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        connection.preferredVideoStabilizationMode = .off // stabilization crops the field of view and adds latency
    }

    /// Fixes the optics (the requested zoom) and records the field of view that geometry is derived from.
    private func prepare(_ device: AVCaptureDevice) {
        applyZoom(to: device, isRunning: false)
        applyExposureCeiling(to: device, force: true)
    }

    /// Runs once the session is running: a format change made by the session invalidates the exposure ceiling
    /// and the zoom and may change the field of view.
    private func settleOptics(of device: AVCaptureDevice) {
        applyZoom(to: device, isRunning: false)
        applyExposureCeiling(to: device, force: true)
    }

    /// Sets the requested zoom, within the format's limits, and records the resulting field of view. While frames
    /// are flowing (`isRunning`), the new field of view applies only to frames captured after the change; otherwise
    /// it replaces what was known, as the format itself may have changed.
    private func applyZoom(to device: AVCaptureDevice, isRunning: Bool = true) {
        let limit = max(min(Double(device.activeFormat.videoMaxZoomFactor), Self.maximumZoom), 1)
        if limit != reportedZoomLimit {
            reportedZoomLimit = limit
            eventSink.yield(.zoomLimit(limit))
        }
        let factor = AstroMath.clamp(requestedZoom.withLock { $0 }, 1, limit)
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = CGFloat(factor)
            device.unlockForConfiguration()
        }
        recordFieldOfView(of: device, isRunning: isRunning)
    }

    /// Records the field of view across the long side of the active format at the current zoom.
    private func recordFieldOfView(of device: AVCaptureDevice, isRunning: Bool) {
        let format = device.activeFormat
        // With geometric distortion correction on (the default where supported) the corrected field of view applies.
        let fieldOfView = device.isGeometricDistortionCorrectionEnabled
            ? format.geometricDistortionCorrectedVideoFieldOfView
            : format.videoFieldOfView
        guard fieldOfView > 0 else { // 0 means unknown
            fieldOfViewHistory.withLock { $0 = [] }
            return
        }
        // Zooming crops the centre of the picture: the tangent of the half-angle shrinks by the zoom factor.
        let zoom = max(Double(device.videoZoomFactor), 1)
        let degrees = AstroMath.degrees(2 * atan(tan(AstroMath.radians(Double(fieldOfView)) / 2) / zoom))
        let validFrom = isRunning
            ? CMClockGetTime(session.synchronizationClock ?? CMClockGetHostTimeClock()).seconds + Self.zoomLatency
            : -Double.infinity
        let change = FieldOfViewChange(validFrom: validFrom, degrees: degrees)
        fieldOfViewHistory.withLock { history in
            guard isRunning else {
                history = [change]
                return
            }
            guard history.last?.degrees != degrees else { return }
            history.append(change)
            if history.count > Self.fieldOfViewHistoryLength { history.removeFirst() }
        }
    }

    /// The field of view a frame presented at `time` (seconds on the session's clock) was captured with: the
    /// newest change valid by then, or the oldest one known.
    private func fieldOfView(at time: Double?) -> Double? {
        fieldOfViewHistory.withLock { history in
            guard let time else { return history.last?.degrees }
            return (history.last { $0.validFrom <= time } ?? history.first)?.degrees
        }
    }

    /// Restarts the frame-rate limiter.
    private func resetFrameState() {
        frameQueue.async { [self] in
            lastFrameTime = -Double.infinity
        }
    }

    /// Night: let auto-exposure integrate up to `nightExposureCeiling` (frame rate drops accordingly). Day: back
    /// to the device default (`CMTime.invalid`). The value must lie within the format's limits or AVFoundation
    /// raises an Objective-C exception, so it is clamped.
    private func applyExposureCeiling(to device: AVCaptureDevice, force: Bool) {
        let raise = nightIntensity.withLock { $0 != nil }
        guard force || raise != isExposureCeilingRaised else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if raise {
            let format = device.activeFormat
            var ceiling = Self.nightExposureCeiling
            if CMTimeCompare(ceiling, format.maxExposureDuration) > 0 { ceiling = format.maxExposureDuration }
            if ceiling.isNumeric, CMTimeCompare(ceiling, format.minExposureDuration) >= 0 {
                device.activeMaxExposureDuration = ceiling
            }
        } else {
            device.activeMaxExposureDuration = .invalid
        }
        isExposureCeilingRaised = raise
    }

    // MARK: Frames (frameQueue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if presentationTime.isNumeric {
            let seconds = presentationTime.seconds
            let elapsed = seconds - lastFrameTime
            // A negative interval means the camera clock restarted; accept the frame.
            if elapsed >= 0 && elapsed < Self.minimumFrameInterval { return }
            lastFrameTime = seconds
        }
        guard let sink = frameSink.withLock({ $0 }),
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        defer { redFilter.inputImage = nil } // release the camera buffer as soon as the frame is rendered

        var image = CIImage(cvPixelBuffer: pixels)
        // The connection rotates the buffers to portrait; if it could not, turn them here (back camera: sensor
        // top is the phone's right side).
        if image.extent.width > image.extent.height { image = image.oriented(.right) }
        if let intensity = nightIntensity.withLock({ $0 }) {
            image = redMonochrome(image, intensity: intensity)
        }
        let frameGeometry = geometry(forFrameSize: image.extent.size,
                                     fieldOfView: fieldOfView(at: presentationTime.isNumeric ? presentationTime.seconds : nil))
        guard let frame = context.createCGImage(image, from: image.extent) else { return }
        sink.yield(CameraFrame(image: frame, geometry: frameGeometry))
    }

    private func redMonochrome(_ image: CIImage, intensity: Double) -> CIImage {
        if appliedIntensity != intensity {
            let weight = CGFloat(intensity)
            redFilter.rVector = CIVector(x: 0.2126 * weight, y: 0.7152 * weight, z: 0.0722 * weight, w: 0)
            appliedIntensity = intensity
        }
        redFilter.inputImage = image
        return redFilter.outputImage ?? image
    }

    /// The geometry of a frame, reusing the previous frame's when nothing changed.
    private func geometry(forFrameSize size: CGSize, fieldOfView: Double?) -> CameraGeometry? {
        guard let fieldOfView else { return nil }
        let width = Int(size.width), height = Int(size.height)
        if let lastGeometry, lastGeometry.imageWidth == width, lastGeometry.imageHeight == height,
           max(lastGeometry.portraitHorizontalFOV, lastGeometry.portraitVerticalFOV) == fieldOfView {
            return lastGeometry
        }
        lastGeometry = CameraGeometry.portrait(longSideFieldOfView: fieldOfView, width: width, height: height)
        return lastGeometry
    }

    // MARK: Notifications

    private func observeSession() {
        observations.observe(AVCaptureSession.runtimeErrorNotification, object: session) { [weak self] notification in
            let code = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code
            self?.eventSink.yield(.runtimeError(isRecoverable: code == AVError.Code.mediaServicesWereReset.rawValue))
        }
        observations.observe(AVCaptureSession.wasInterruptedNotification, object: session) { [weak self] notification in
            let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            let reason = rawReason.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
            self?.eventSink.yield(.interrupted(Self.interruption(for: reason)))
        }
        observations.observe(AVCaptureSession.interruptionEndedNotification, object: session) { [weak self] _ in
            self?.eventSink.yield(.interruptionEnded)
        }
    }

    private static func interruption(for reason: AVCaptureSession.InterruptionReason?) -> CameraInterruption {
        switch reason {
        case .videoDeviceNotAvailableInBackground?:
            return .inBackground
        case .audioDeviceInUseByAnotherClient?, .videoDeviceInUseByAnotherClient?:
            return .deviceInUse
        case .videoDeviceNotAvailableWithMultipleForegroundApps?:
            return .multitasking
        case .videoDeviceNotAvailableDueToSystemPressure?:
            return .systemPressure
        default:
            return .other
        }
    }
}

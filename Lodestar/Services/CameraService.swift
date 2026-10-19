import AVFoundation
import CoreGraphics
import Foundation
import LodestarKit
import Observation

/// Whether the app may use the camera, or why it cannot.
enum CameraAuthorization: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    /// This device has no usable back camera (the Simulator, for example).
    case unavailable
}

/// The optics of the delivered frames, for matching the sky overlay to the picture.
struct CameraGeometry: Sendable, Equatable {
    /// Field of view across the frame's width, degrees.
    var portraitHorizontalFOV: Double
    /// Field of view across the frame's height, degrees.
    var portraitVerticalFOV: Double
    /// Frame size in pixels; the frames are upright in portrait.
    var imageWidth: Int
    var imageHeight: Int

    /// The geometry of a frame of `width` × `height` pixels when the format's field of view,
    /// `longSideFieldOfView` degrees, spans the frame's long side. Pinhole model with square pixels; `nil` for
    /// unusable input.
    static func portrait(longSideFieldOfView: Double, width: Int, height: Int) -> CameraGeometry? {
        guard width > 0, height > 0, longSideFieldOfView > 0, longSideFieldOfView < 180 else { return nil }
        let longSide = Double(max(width, height))
        let shortSide = Double(min(width, height))
        let halfLong = AstroMath.radians(longSideFieldOfView) / 2
        let shortSideFieldOfView = AstroMath.degrees(2 * atan(tan(halfLong) * shortSide / longSide))
        let isPortrait = height >= width
        return CameraGeometry(portraitHorizontalFOV: isPortrait ? shortSideFieldOfView : longSideFieldOfView,
                              portraitVerticalFOV: isPortrait ? longSideFieldOfView : shortSideFieldOfView,
                              imageWidth: width, imageHeight: height)
    }
}

/// The live camera picture behind the sky overlay (back wide camera, 1280 × 720, upright in portrait).
///
/// `start(nightFilter:)` is meant to be called often with the current wish; it only acts when something changed.
/// All capture work happens off the main thread in `CameraEngine`.
@MainActor
@Observable
final class CameraService {
    private enum EngineState {
        case stopped, starting, running, interrupted
    }

    /// Restarts after "media services were reset" that are tried without a frame arriving in between.
    private static let maximumAutomaticRestarts = 3
    /// After a failed start or an unrecoverable error the camera is left alone this long before the next request
    /// starts it again, so a broken camera is not reopened every time the screen asks.
    private static let retryDelay: Duration = .seconds(5)
    private static let deniedMessage = "Camera access is turned off. Allow it in Settings to see the camera behind the sky."
    private static let restrictedMessage = "Camera access is restricted on this iPhone."

    private(set) var authorization: CameraAuthorization = .notDetermined
    /// The newest frame (at most 30 per second), upright in portrait; `nil` while the camera is not delivering.
    private(set) var frame: CGImage?
    /// The optics of `frame`, set together with it, once the first frame has arrived.
    private(set) var geometry: CameraGeometry?
    /// The strongest zoom the camera supports, at most `CameraEngine.maximumZoom`; that maximum until the camera
    /// has started once.
    private(set) var maximumZoom = CameraEngine.maximumZoom
    /// Whether frames are flowing.
    private(set) var isRunning = false
    /// A message for the user when the camera is denied, unavailable, interrupted or failed.
    private(set) var errorDescription: String?

    @ObservationIgnored private lazy var engine = CameraEngine()
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var engineState = EngineState.stopped
    @ObservationIgnored private var automaticRestarts = 0
    @ObservationIgnored private var retryNotBefore: ContinuousClock.Instant?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init() {
        refreshAuthorization()
    }

    /// Asks for camera access if the user has not decided yet. Returns whether access is granted.
    func requestAccess() async -> Bool {
        refreshAuthorization()
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            refreshAuthorization()
        }
        return authorization == .authorized
    }

    /// Starts the camera (asking for access the first time) or updates the running one. `nightFilter` is `nil` for
    /// natural colour, or the intensity 0…1 of the red-monochrome night filter. Idempotent; a camera that stopped
    /// because of an error is started again by the next call.
    func start(nightFilter: Double?) {
        wantsRunning = true
        refreshAuthorization()
        switch authorization {
        case .authorized:
            ensureEventTask()
            engine.setNightFilter(Self.sanitized(nightFilter))
            launchIfNeeded()
        case .notDetermined:
            // Ask only when the user taps the in-app "Enable camera" prompt (`requestAccess()`); the next
            // `start` after access is granted launches the camera.
            break
        case .denied, .restricted, .unavailable:
            break
        }
    }

    /// Zooms the picture by `factor` (1 = the camera's full field of view, at most `maximumZoom`). It is kept while
    /// the camera is stopped and applied when it starts; `geometry` follows with the frames captured at that zoom.
    func setZoom(_ factor: Double) {
        engine.setZoom(factor)
    }

    /// Stops the camera and clears the picture. Idempotent.
    func stop() {
        wantsRunning = false
        retryNotBefore = nil
        guard engineState != .stopped || frameTask != nil else { return }
        engine.stop()
        frameTask?.cancel()
        frameTask = nil
        engineState = .stopped
        automaticRestarts = 0
        isRunning = false
        frame = nil
        geometry = nil
        // A message about an interruption or failure is about a run that is over; access problems stay.
        if authorization != .unavailable { errorDescription = nil }
        refreshAuthorization()
    }

    // MARK: Authorization

    /// Reads the system's camera authorization. Properties are written only when they change, because this runs
    /// every time the camera is requested.
    private func refreshAuthorization() {
        guard authorization != .unavailable else { return }
        let status: CameraAuthorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: status = .authorized
        case .notDetermined: status = .notDetermined
        case .restricted: status = .restricted
        case .denied: status = .denied
        @unknown default: status = .denied
        }
        if authorization != status { authorization = status }
        switch status {
        case .denied:
            if errorDescription != Self.deniedMessage { errorDescription = Self.deniedMessage }
        case .restricted:
            if errorDescription != Self.restrictedMessage { errorDescription = Self.restrictedMessage }
        default:
            if errorDescription == Self.deniedMessage || errorDescription == Self.restrictedMessage {
                errorDescription = nil
            }
        }
    }

    // MARK: Engine

    private func launchIfNeeded() {
        guard engineState == .stopped else { return }
        if let retryNotBefore, ContinuousClock.now < retryNotBefore { return }
        retryNotBefore = nil
        engineState = .starting
        frameTask?.cancel()
        let frames = engine.makeFrameStream()
        frameTask = Task { [weak self] in
            for await next in frames {
                // A frame that was already on its way when the camera stopped must not bring the picture back.
                guard let self, !Task.isCancelled else { return }
                self.automaticRestarts = 0
                self.frame = next.image
                if self.geometry != next.geometry { self.geometry = next.geometry }
            }
        }
        engine.start()
    }

    private func ensureEventTask() {
        guard eventTask == nil else { return }
        let events = engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: CameraEngineEvent) {
        guard wantsRunning else { return }
        switch event {
        case .started:
            // An interruption can be reported before the start completes; it stays in force until it ends.
            if engineState != .interrupted {
                engineState = .running
                isRunning = true
                errorDescription = nil
            }
        case .zoomLimit(let limit):
            if maximumZoom != limit { maximumZoom = limit }
        case .failed(.notRunning) where engineState == .interrupted:
            // The system interrupted the start (the camera is busy elsewhere); the session resumes by itself when
            // the interruption ends, which is reported separately.
            break
        case .failed(let failure):
            engineState = .stopped
            retryNotBefore = ContinuousClock.now + Self.retryDelay
            markNotDelivering()
            geometry = nil
            switch failure {
            case .noCamera:
                authorization = .unavailable
                errorDescription = "This iPhone has no usable back camera."
            case .configuration:
                errorDescription = "The camera could not be set up."
            case .notRunning:
                errorDescription = "The camera could not be started. Another app may be using it."
            }
        case .interrupted(let reason):
            engineState = .interrupted
            markNotDelivering()
            errorDescription = Self.message(for: reason)
        case .interruptionEnded:
            if engineState == .interrupted {
                engineState = .running
                isRunning = true
                errorDescription = nil
            }
        case .runtimeError(let isRecoverable):
            engineState = .stopped
            markNotDelivering()
            geometry = nil
            if isRecoverable && automaticRestarts < Self.maximumAutomaticRestarts {
                automaticRestarts += 1
                launchIfNeeded()
            } else {
                retryNotBefore = ContinuousClock.now + Self.retryDelay
                errorDescription = "The camera stopped because of an error."
            }
        }
    }

    private func markNotDelivering() {
        isRunning = false
        frame = nil
    }

    // MARK: Text and values

    private static func message(for interruption: CameraInterruption) -> String {
        switch interruption {
        case .inBackground: return "The camera is not available while Lodestar is in the background."
        case .deviceInUse: return "The camera is being used by another app."
        case .multitasking: return "The camera is not available while another app shares the screen."
        case .systemPressure: return "The camera paused because the iPhone is too warm."
        case .other: return "The camera was interrupted."
        }
    }

    /// Intensities are limited to 0…1; a non-number counts as full intensity, the safest choice for night vision.
    private static func sanitized(_ nightFilter: Double?) -> Double? {
        guard let nightFilter else { return nil }
        return nightFilter.isFinite ? min(max(nightFilter, 0), 1) : 1
    }
}

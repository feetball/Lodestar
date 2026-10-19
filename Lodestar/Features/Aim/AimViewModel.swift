import Foundation
import LodestarKit
import Observation

/// The state and background work behind the Aim screen.
///
/// Only low-rate values are observable (the sky rebuilt every couple of seconds, the HUD rotation, the zoom). What
/// changes with every sensor sample is not published: the overlay and the readouts ask `engine` for the frame
/// when they draw, so the view tree is not invalidated 60 times a second.
@MainActor
@Observable
final class AimViewModel {
    /// Seconds between sky rebuilds. The sky moves 15″ per second, far below what the screen can show.
    private static let skyRefreshInterval = 2.0
    /// Seconds between searches for the target's next rise.
    private static let riseRefreshInterval = 60.0
    private static let loopInterval: Duration = .milliseconds(33)
    /// Where the zoom of the virtual sky is remembered, so it survives the screen being rebuilt (night mode starting
    /// at dusk rebuilds the tabs) and relaunches.
    private static let fieldOfViewKey = "lodestar.aim.virtualFieldOfView"

    let app: AppModel
    let engine: AimFrameEngine

    /// Preferences and calibration in effect; the screen refreshes them whenever the app model changes.
    private(set) var configuration: AimConfiguration
    private(set) var skyContent: AimSkyContent?
    private(set) var riseInfo: AimRiseInfo?
    private(set) var hudRotation = AimHUDRotation.upright
    /// The field of view along the screen's long side without a camera picture, in degrees.
    private(set) var virtualFieldOfView: Double
    /// An object the alignment sheet asks to be guided to; it replaces the app's target while it is set.
    var alignmentTarget: CelestialObject?

    @ObservationIgnored private var hasHUDRotation = false
    @ObservationIgnored private var pinchStartFieldOfView: Double?
    @ObservationIgnored private var wasOnTarget: Bool?

    init(app: AppModel) {
        self.app = app
        let configuration = AimConfiguration(app: app)
        self.configuration = configuration
        engine = AimFrameEngine(motion: app.motion, configuration: configuration)
        let stored = UserDefaults.standard.double(forKey: Self.fieldOfViewKey)
        let range = AimProjectionFactory.virtualFieldOfViewRange
        virtualFieldOfView = range.contains(stored) ? stored : AimProjectionFactory.defaultVirtualFieldOfView
    }

    // MARK: Derived state

    /// The object guidance leads to: the alignment sheet's choice, else the app's target.
    var guidanceTarget: CelestialObject? { alignmentTarget ?? app.target }

    /// The optics of the camera picture behind the sky, or `nil` when the virtual lens is in use: whenever the
    /// picture is not wanted or not running.
    var cameraGeometry: CameraGeometry? {
        configuration.wantsCameraPreview && app.camera.isRunning ? app.camera.geometry : nil
    }

    /// The field of view along the screen's long side in degrees: the camera's while its picture is behind the sky,
    /// else the virtual lens's.
    var fieldOfView: Double {
        cameraGeometry.map { max($0.portraitHorizontalFOV, $0.portraitVerticalFOV) } ?? virtualFieldOfView
    }

    /// The object under the reticle in `frame`, for looking around without a target.
    func nearbyObject(in frame: AimFrame) -> AimLookAround.Nearby? {
        guard let snapshot = skyContent?.snapshot else { return nil }
        return AimLookAround.nearest(to: frame.pointing.boresightVector, in: snapshot,
                                     within: AimLookAround.radius(fieldOfView: fieldOfView))
    }

    /// What the sky snapshot depends on, or `nil` while it cannot be built (no location, catalog not loaded).
    func skyInputs(for configuration: AimConfiguration) -> AimSkyInputs? {
        guard let context = app.observerContext, app.catalog.loadState == .loaded else { return nil }
        return AimSkyInputs(observer: context.observer, options: configuration.skyOptions, target: guidanceTarget)
    }

    // MARK: Configuration

    /// Takes over new preferences and calibration; nothing happens while they are unchanged.
    func apply(_ configuration: AimConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        engine.configure(configuration)
    }

    /// Points the engine at the current guidance target.
    func syncTarget() {
        engine.setTarget(id: guidanceTarget?.id)
        wasOnTarget = nil
    }

    // MARK: Background work

    /// Rebuilds the sky for `inputs` now and then every few seconds until cancelled. Restart it (`.task(id:)`)
    /// whenever the inputs change; a build still running for older inputs is discarded.
    func keepSkyCurrent(_ inputs: AimSkyInputs?) async {
        guard let inputs, let catalog = app.catalog.catalog else { return }
        while !Task.isCancelled {
            let date = app.clock.now
            let content = await Task.detached(priority: .userInitiated) {
                AimSkyContent.build(catalog: catalog, inputs: inputs, date: date)
            }.value
            guard !Task.isCancelled else { return }
            skyContent = content
            engine.update(target: content.snapshot.target)
            try? await Task.sleep(for: .seconds(Self.skyRefreshInterval))
        }
    }

    /// Keeps `riseInfo` (when the target next rises) current while there is a target.
    func keepRiseInfoCurrent(_ inputs: AimSkyInputs?) async {
        guard let inputs, let target = inputs.target else {
            riseInfo = nil
            return
        }
        let observer = inputs.observer
        while !Task.isCancelled {
            let date = app.clock.now
            let info = await Task.detached(priority: .utility) {
                AimRiseInfo.compute(for: target, observer: observer, from: date)
            }.value
            guard !Task.isCancelled else { return }
            riseInfo = info
            try? await Task.sleep(for: .seconds(Self.riseRefreshInterval))
        }
    }

    /// Runs the aiming logic about 30 times a second until cancelled: the HUD rotation, the audio ticks and the
    /// haptics for reaching and leaving the target.
    func runLoop() async {
        while !Task.isCancelled {
            step()
            try? await Task.sleep(for: Self.loopInterval)
        }
    }

    private func step() {
        guard let frame = engine.frame() else { return }
        updateHUDRotation(gravity: frame.sample.gravity)
        guard let guidance = frame.guidance else {
            if wasOnTarget != nil { stopFeedback() }
            return
        }
        app.feedback.guidanceTick(separation: guidance.separation)
        let isOnTarget = guidance.state == .onTarget
        if let wasOnTarget, wasOnTarget != isOnTarget {
            if isOnTarget {
                app.feedback.targetAcquired()
            } else {
                app.feedback.targetLost()
            }
        }
        wasOnTarget = isOnTarget
    }

    private func updateHUDRotation(gravity: Vector3) {
        let rotation = AimHUDRotation.updated(from: hasHUDRotation ? hudRotation : nil, gravity: gravity,
                                              mount: configuration.mount)
        hasHUDRotation = true
        if rotation != hudRotation { hudRotation = rotation }
    }

    /// Silences the guidance audio; call when the screen goes away.
    func stopFeedback() {
        app.feedback.stopGuidanceAudio()
        wasOnTarget = nil
    }

    // MARK: Zoom

    /// Zooms the virtual sky by a pinch's `magnification`, counted from the field of view when the pinch began.
    func updatePinch(magnification: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        let start = pinchStartFieldOfView ?? virtualFieldOfView
        pinchStartFieldOfView = start
        setVirtualFieldOfView(start / magnification)
    }

    func endPinch() {
        pinchStartFieldOfView = nil
        UserDefaults.standard.set(virtualFieldOfView, forKey: Self.fieldOfViewKey)
    }

    /// The preset the zoom button goes to next: the next narrower one, and from the narrowest back to the widest.
    var nextFieldOfViewPreset: Double {
        let presets = AimProjectionFactory.virtualFieldOfViewPresets
        return presets.first { $0 < virtualFieldOfView - 0.5 } ?? presets[0]
    }

    /// Zooms the virtual sky to the next preset.
    func stepFieldOfView() {
        setVirtualFieldOfView(nextFieldOfViewPreset)
        UserDefaults.standard.set(virtualFieldOfView, forKey: Self.fieldOfViewKey)
    }

    private func setVirtualFieldOfView(_ degrees: Double) {
        let range = AimProjectionFactory.virtualFieldOfViewRange
        virtualFieldOfView = AstroMath.clamp(degrees, range.lowerBound, range.upperBound)
    }

    // MARK: Controls

    /// Turns the camera picture on or off. At night the separate "camera at night" preference decides, so
    /// switching it off does not change the daytime choice.
    func toggleCameraPreview() {
        let store = app.settingsStore
        if !app.isNightModeActive {
            store.settings.cameraPreviewEnabled = !configuration.wantsCameraPreview
        } else if configuration.wantsCameraPreview {
            store.settings.cameraPreviewAtNight = false
        } else {
            store.settings.cameraPreviewEnabled = true
            store.settings.cameraPreviewAtNight = true
        }
    }

    /// Cycles night mode: off, on, after sunset.
    func cycleNightMode() {
        switch app.settings.nightMode {
        case .off: app.settingsStore.settings.nightMode = .on
        case .on: app.settingsStore.settings.nightMode = .automatic
        case .automatic: app.settingsStore.settings.nightMode = .off
        }
    }
}

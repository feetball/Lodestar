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
    /// Whether the engine is leading the guidance to a satellite.
    @ObservationIgnored private var hadSatellite = false
    @ObservationIgnored private var pinchStartFieldOfView: Double?
    @ObservationIgnored private var wasOnTarget: Bool?
    /// The session revision and clock second the mosaic guidance was last refreshed for.
    @ObservationIgnored private var lastMosaicRefresh: (revision: Int, date: Date)?

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

    /// The mosaic being shot, shared with the Sky chart.
    var mosaicSession: MosaicSession { MosaicSession.shared }

    /// The object guidance leads to: the alignment sheet's choice, else the app's target. There is none while a satellite
    /// is the target (`satelliteSource`).
    var guidanceTarget: CelestialObject? { alignmentTarget ?? (app.satelliteAim.source == nil ? app.target : nil) }

    /// The satellite, or the peak of its pass, that guidance leads to instead of an object. The alignment sheet's choice
    /// of a star comes first, and a mosaic in progress replaces it as it replaces the target.
    var satelliteSource: SatelliteAimSource? { alignmentTarget == nil ? app.satelliteAim.source : nil }

    /// The Starlink streak warning for the framing: worked out about once a second.
    let streak = SatelliteStreakMonitor()

    /// The optics of the camera picture behind the sky, or `nil` when the virtual lens is in use: whenever the
    /// picture is not wanted or not running.
    var cameraGeometry: CameraGeometry? {
        configuration.wantsCameraPreview && app.camera.isRunning ? app.camera.geometry : nil
    }

    /// What the sky snapshot depends on, or `nil` while it cannot be built (no location, catalog not loaded).
    func skyInputs(for configuration: AimConfiguration) -> AimSkyInputs? {
        guard let context = app.observerContext, app.catalog.loadState == .loaded else { return nil }
        return AimSkyInputs(observer: context.observer, options: configuration.skyOptions, target: guidanceTarget,
                            horizon: context.horizon, mosaic: mosaicSession.plan)
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
        refreshMosaicGuidance(force: false)
        refreshSatelliteGuidance()
        streak.tick(model: self)
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

    // MARK: Mosaic

    /// Starts shooting `plan`: the guidance leads to its first panel.
    func startMosaic(plan: MosaicPlan, title: String) {
        mosaicSession.start(plan: plan, title: title)
        refreshMosaicGuidance(force: true)
    }

    /// The current panel has been shot: guidance moves on to the next one.
    func mosaicShotTaken() {
        mosaicSession.advance()
        refreshMosaicGuidance(force: true)
    }

    /// Goes back to the previous panel.
    func mosaicPrevious() {
        mosaicSession.goBack()
        refreshMosaicGuidance(force: true)
    }

    /// Ends the mosaic; guidance leads to the target again.
    func finishMosaic() {
        mosaicSession.finish()
        refreshMosaicGuidance(force: true)
    }

    /// Points the guidance at the current panel's place in the sky at the clock's time. A panel of an equatorial plan
    /// moves with the stars, so this runs about once a second while a mosaic is shot, and at once when the panel
    /// changes. It costs microseconds: one panel, not the plan.
    private func refreshMosaicGuidance(force: Bool) {
        let session = mosaicSession
        guard let plan = session.plan else {
            if lastMosaicRefresh != nil {
                lastMosaicRefresh = nil
                engine.setMosaic(active: false, aim: nil)
                wasOnTarget = nil
            }
            return
        }
        let now = app.clock.now
        if !force, let last = lastMosaicRefresh, last.revision == session.revision, last.date == now { return }
        // A new panel starts without a remembered on-target state, so reaching it does not buzz for the old one.
        if lastMosaicRefresh?.revision != session.revision { wasOnTarget = nil }
        lastMosaicRefresh = (session.revision, now)
        guard let panel = session.currentPanel, let context = app.observerContext else {
            engine.setMosaic(active: true, aim: nil)
            return
        }
        let pointing = MosaicGuidance.pointing(of: panel, in: plan, frame: SkyFrame(date: now, observer: context.observer))
        engine.setMosaic(active: true, aim: AimMosaicAim(
            panelIndex: panel.index, horizontal: pointing.direction, roll: pointing.roll,
            orientation: plan.orientation, isAboveHorizon: pointing.isAboveHorizon,
            lowestAltitude: pointing.lowestAltitude, onTargetThreshold: AimMosaicAim.onTargetThreshold(for: plan)))
    }

    // MARK: Satellite

    /// Points the guidance at the satellite (or the peak of its pass) at the present moment. A followed satellite moves
    /// across the sky, so this runs with every sensor tick: one `SatelliteSkyContext` and one look, a few microseconds.
    /// Real time rather than the clock's second, which would make the target jump.
    private func refreshSatelliteGuidance() {
        guard let source = satelliteSource else {
            if hadSatellite {
                hadSatellite = false
                engine.setSatellite(nil, sourceID: nil)
                wasOnTarget = nil
            }
            return
        }
        // A new source starts without a remembered on-target state, so reaching it does not buzz for the old one.
        if !hadSatellite || engine.satelliteSourceID != source.id { wasOnTarget = nil }
        hadSatellite = true
        engine.setSatellite(source.fix(at: Date()), sourceID: source.id)
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

    /// Returns the virtual sky to its default field of view.
    func resetFieldOfView() {
        setVirtualFieldOfView(AimProjectionFactory.defaultVirtualFieldOfView)
        UserDefaults.standard.removeObject(forKey: Self.fieldOfViewKey)
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

import SwiftUI
import LodestarKit

/// The app's tabs.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case aim, objects, sky, tonight, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aim: return "Aim"
        case .objects: return "Objects"
        case .sky: return "Sky"
        case .tonight: return "Tonight"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .aim: return "scope"
        case .objects: return "sparkles"
        case .sky: return "circle.dotted.circle"
        case .tonight: return "moon.stars"
        case .settings: return "gearshape"
        }
    }
}

/// Root application state: owns the services, the current target and alignment, and derives the
/// observing context and display mode. Views read it with `@Environment(AppModel.self)`.
@MainActor
@Observable
final class AppModel {
    let settingsStore: SettingsStore
    let clock: SkyClock
    let location: LocationService
    let motion: MotionService
    let camera: CameraService
    let catalog: CatalogService
    let feedback: FeedbackService
    let screen: ScreenController
    /// The optional downloads (satellites, comets, cloud forecast); everything in it is off until switched on.
    let online: OnlineDataService
    /// The satellite Aim follows or waits for, if one was chosen from a pass.
    let satelliteAim: SatelliteAimSession

    /// The selected tab. Changing it starts/stops the sensors that tab needs.
    var selectedTab: AppTab = .aim {
        didSet { if selectedTab != oldValue { syncServices() } }
    }

    /// The object the Aim screen guides to.
    private(set) var target: CelestialObject?

    /// Star-alignment corrections for the current mount and heading source.
    var alignment: AlignmentModel = .identity

    /// Keeps the motion sensors running outside the Aim and Sky tabs (e.g. Sensor Diagnostics).
    var keepsMotionRunning = false {
        didSet { if keepsMotionRunning != oldValue { syncServices() } }
    }

    /// Keeps the camera picture running outside the Aim tab (the skyline recorder in Settings).
    var keepsCameraRunning = false {
        didSet { if keepsCameraRunning != oldValue { syncServices() } }
    }

    /// Keeps the screen from locking outside the Aim tab (the skyline recorder, whose sweep takes half a minute).
    var keepsScreenAwake = false {
        didSet { if keepsScreenAwake != oldValue { syncServices() } }
    }

    /// Whether the Sun is below −6° at the observer (drives automatic night mode).
    private(set) var isSunBelowCivilTwilight = false

    /// Latest scene phase reported by the app.
    private(set) var scenePhase: ScenePhase = .inactive

    /// Most saved sites whose estimated time zone is looked up again per foreground; the geocoder is rate limited.
    private static let timeZoneUpgradesPerForeground = 5

    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var timeZoneUpgradeTask: Task<Void, Never>?
    @ObservationIgnored private var hasRequestedLocationThisLaunch = false
    @ObservationIgnored private var lastAlignmentContext: AlignmentContext?
    @ObservationIgnored private var lastSunEvaluation: (date: Date, observer: Observer)?
    /// A recent target that was not in the catalog at launch (a downloaded comet whose file is applied later).
    @ObservationIgnored private var pendingTargetID: String?

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        clock = SkyClock()
        location = LocationService()
        motion = MotionService()
        camera = CameraService()
        catalog = CatalogService()
        feedback = FeedbackService()
        screen = ScreenController()
        online = OnlineDataService(catalog: catalog)
        satelliteAim = SatelliteAimSession()
        online.locationProvider = { [weak self] in self?.observerContext?.location }
        #if DEBUG
        if let demo = ScreenshotMode.current { applyScreenshotMode(demo) }
        #endif
        catalog.onSmallBodiesChange = { [weak self] in self?.smallBodiesChanged() }
    }

    #if DEBUG
    /// Demo site, fixed time, display mode and camera pointing for Simulator screenshots.
    private func applyScreenshotMode(_ demo: ScreenshotMode) {
        var settings = settingsStore.settings
        settings.hasCompletedOnboarding = true
        settings.cameraPreviewEnabled = false
        settings.nightMode = demo.nightMode ? .on : .off
        if let site = SavedSite(name: demo.siteName, latitude: demo.location.latitude,
                                longitude: demo.location.longitude, elevation: demo.location.elevation,
                                timeZoneIdentifier: demo.timeZoneIdentifier) {
            settings.savedSites = [site]
            settings.locationSource = .site(site.id)
        }
        settingsStore.settings = settings
        selectedTab = demo.screen?.tab ?? demo.tab
        if demo.addsFixtureComets { catalog.setDownloadedSmallBodies(ReviewFixtures.comets) }
        clock.freeze(at: demo.date)
        if let pointing = demo.pointing { motion.useScreenshotPointing(pointing) }
    }
    #endif

    // MARK: Derived state

    var settings: AppSettings { settingsStore.settings }

    /// Night mode as currently in effect (manual setting or automatic after sunset).
    var isNightModeActive: Bool {
        switch settings.nightMode {
        case .on: return true
        case .off: return false
        case .automatic: return isSunBelowCivilTwilight
        }
    }

    var palette: Palette {
        isNightModeActive ? .night(intensity: settings.nightIntensity) : .normal
    }

    /// The resolved observer, or nil when no location is known yet.
    var observerContext: ObserverContext? {
        let atmosphere = settings.atmosphere
        switch settings.locationSource {
        case .device:
            guard let current = location.stableLocation else { return nil }
            return ObserverContext(observer: Observer(location: current, atmosphere: atmosphere),
                                   timeZone: .autoupdatingCurrent, name: "Current Location", source: .device)
        case .site(let id):
            guard let site = settings.savedSites.first(where: { $0.id == id }) else { return nil }
            return ObserverContext(observer: Observer(location: site.location, atmosphere: atmosphere),
                                   timeZone: site.timeZone ?? .autoupdatingCurrent, name: site.name, source: .site(id),
                                   horizon: site.horizon)
        }
    }

    /// The mount geometry selected in Settings.
    var mountProfile: MountProfile {
        MountProfile.presets.first { $0.id == settings.mountPresetID } ?? .backCameraPortrait
    }

    /// The camera body + lens used for the framing rectangle and exposure tools.
    var lensSetup: LensSetup {
        let sensor: SensorFormat
        if let preset = SensorFormat.presets.first(where: { $0.id == settings.sensorID }) {
            sensor = preset
        } else {
            sensor = SensorFormat.custom(width: settings.customSensorWidth, height: settings.customSensorHeight)
        }
        return LensSetup(sensor: sensor, focalLengthMillimeters: settings.focalLength,
                         aperture: settings.aperture, pixelPitchMicrometers: settings.pixelPitch)
    }

    // MARK: Lifecycle

    /// Starts the clock and periodic maintenance and loads the bundled catalog. Call once.
    func launch() async {
        clock.start()
        startMaintenance()
        syncServices()
        await catalog.load()
        if target == nil, let id = settings.recentObjectIDs.first {
            if let object = catalog.object(id: id) { target = object } else { pendingTargetID = id }
        }
        #if DEBUG
        if let id = ScreenshotMode.current?.targetID, let object = catalog.object(id: id) {
            target = object
        }
        #endif
        evaluateSun(force: true)
        #if DEBUG
        ReviewDriver.shared.start(app: self)
        #endif
    }

    func handleScenePhase(_ phase: ScenePhase) {
        scenePhase = phase
        switch phase {
        case .active:
            clock.start()
            startMaintenance()
            online.onForeground()
            upgradeEstimatedTimeZones()
        case .background:
            settingsStore.saveNow()
            clock.stop()
            maintenanceTask?.cancel()
            maintenanceTask = nil
        default:
            break
        }
        syncServices()
    }

    /// Finishes onboarding and requests location access if the device location is used.
    func completeOnboarding() {
        settingsStore.settings.hasCompletedOnboarding = true
        if settings.locationSource == .device {
            location.requestAuthorization()
        }
        syncServices()
    }

    // MARK: Targeting

    /// Makes `object` the aiming target and switches to the Aim tab.
    func aim(at object: CelestialObject) {
        select(target: object)
        selectedTab = .aim
    }

    /// Makes `object` the aiming target without changing tabs.
    func select(target object: CelestialObject) {
        satelliteAim.stop()
        pendingTargetID = nil
        target = object
        if !object.id.hasPrefix("custom.") {
            settingsStore.noteRecent(object.id)
        }
    }

    func clearTarget() {
        pendingTargetID = nil
        target = nil
    }

    /// Downloaded comets and asteroids replaced the catalog's small bodies: a target that is one of them follows its
    /// refreshed object (newer elements; one that dropped out of the data keeps what it had), and a recent target
    /// that only now resolves is restored.
    private func smallBodiesChanged() {
        if let current = target, current.smallBody != nil, let refreshed = catalog.object(id: current.id) {
            target = refreshed
        } else if target == nil, let id = pendingTargetID, let object = catalog.object(id: id) {
            target = object
        }
        pendingTargetID = nil
    }

    // MARK: Alignment

    func resetAlignment() {
        alignment = .identity
    }

    // MARK: Service orchestration

    /// Starts exactly the services the visible screen needs and applies display rules.
    /// Safe to call often; every step is idempotent.
    func syncServices() {
        // `.inactive` is transient (Control Center, notification shade, app switcher): keep sensors,
        // camera and brightness as they are and only stop when the app moves to the background.
        let active = scenePhase != .background
        let onboarded = settings.hasCompletedOnboarding

        // Location: only for the device source, only while active. "Allow Once" expires with the
        // session, so ask again (once per launch) when the permission is undetermined.
        if active && onboarded && settings.locationSource == .device {
            if !location.isAuthorized && !location.isDenied && !hasRequestedLocationThisLaunch {
                hasRequestedLocationThisLaunch = true
                location.requestAuthorization()
            }
            location.start()
        } else {
            location.stop()
        }

        // Motion: the Aim and Sky screens show the camera's pointing direction.
        // Gyro lock keeps running on every tab: stopping the gyro-only frame would lose its heading and
        // with it the star alignment.
        let needsMotion = active && onboarded
            && (selectedTab == .aim || selectedTab == .sky || keepsMotionRunning || settings.headingSource == .gyroLock)
        if needsMotion {
            motion.configure(headingSource: settings.headingSource,
                             smoothingTimeConstant: settings.smoothingTimeConstant,
                             magneticReference: magneticReference())
            motion.start()
        } else {
            motion.stop()
        }

        // Camera preview: Aim tab only, if enabled for the current display mode, and only when the
        // phone's back camera looks along the lens (flat-on-top mounts would show the ground).
        let backCameraAlongLens = mountProfile.cameraAxis.dot(DeviceAttitude.backCameraAxis) > 0.99
        let wantsPreview = settings.cameraPreviewEnabled && backCameraAlongLens
            && (!isNightModeActive || settings.cameraPreviewAtNight)
        let aimWantsCamera = selectedTab == .aim && wantsPreview && observerContext != nil
        if active && onboarded && (aimWantsCamera || keepsCameraRunning) {
            camera.start(nightFilter: isNightModeActive ? settings.nightIntensity : nil)
        } else {
            camera.stop()
        }

        // Screen: dim at night, keep awake while aiming.
        if active {
            screen.setBrightnessOverride(isNightModeActive && settings.dimScreenAtNight ? settings.nightBrightness : nil)
            screen.setIdleTimerDisabled((selectedTab == .aim && settings.keepScreenAwake) || keepsScreenAwake)
        } else {
            screen.restore()
        }

        feedback.configure(haptics: settings.hapticsEnabled, audio: settings.audioCuesEnabled)
        invalidateAlignmentIfNeeded()
    }

    // MARK: Private

    private struct AlignmentContext: Equatable {
        var mountPresetID: String
        var headingSource: HeadingSource
        var frameEpoch: Int
    }

    /// Alignment is only valid for the mount and attitude reference it was measured with.
    private func invalidateAlignmentIfNeeded() {
        let context = AlignmentContext(mountPresetID: settings.mountPresetID,
                                       headingSource: settings.headingSource,
                                       frameEpoch: motion.frameEpoch)
        if let last = lastAlignmentContext, last != context {
            alignment = .identity
        }
        lastAlignmentContext = context
    }

    /// Magnetic declination and expected field strength at the observer from WMM2025, used when
    /// CoreMotion's true-north frame is unavailable and to detect magnetic interference.
    private func magneticReference() -> MagneticReference? {
        guard let context = observerContext else { return nil }
        let location = context.location
        let model = WorldMagneticModel.wmm2025
        let field = model.field(latitude: location.latitude, longitude: location.longitude,
                                altitudeMeters: location.elevation,
                                decimalYear: WorldMagneticModel.decimalYear(from: clock.now))
        return MagneticReference(declination: field.declination,
                                 expectedFieldMicrotesla: field.totalIntensity / 1000)
    }

    /// Looks up the real time zone of saved sites that only have the one estimated from their longitude (they were saved
    /// without a network). That estimate has no daylight saving time, so their times are an hour off for half the year.
    /// The lookups run one after the other off the main thread, a few per foreground, and a site that cannot be resolved
    /// now is simply tried again at the next foreground.
    private func upgradeEstimatedTimeZones() {
        guard timeZoneUpgradeTask == nil else { return }
        let pending = settings.savedSites.filter { $0.timeZone.map(SettingsFormat.isNominal) ?? true }
        guard !pending.isEmpty else { return }
        timeZoneUpgradeTask = Task { [weak self] in
            for site in pending.prefix(Self.timeZoneUpgradesPerForeground) {
                guard let zone = await TimeZoneResolver.timeZone(for: site.location), !SettingsFormat.isNominal(zone) else {
                    continue
                }
                self?.applyResolvedTimeZone(zone, to: site)
            }
            self?.timeZoneUpgradeTask = nil
        }
    }

    /// Stores `zone` for `site` unless the site changed while the lookup ran: it was deleted, moved, or already got a
    /// real zone (from the site editor).
    private func applyResolvedTimeZone(_ zone: TimeZone, to site: SavedSite) {
        guard var current = settings.savedSites.first(where: { $0.id == site.id }),
              current.latitude == site.latitude, current.longitude == site.longitude,
              current.timeZone.map(SettingsFormat.isNominal) ?? true else { return }
        current.timeZoneIdentifier = zone.identifier
        settingsStore.updateSite(current)
    }

    private func startMaintenance() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.performMaintenance() != nil else { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func performMaintenance() {
        evaluateSun(force: false)
        syncServices()
    }

    /// Recomputes the Sun's altitude at most every 30 s (or when the observer changes).
    private func evaluateSun(force: Bool) {
        guard let observer = observerContext?.observer else {
            // No location yet: approximate darkness by the local clock so automatic night mode
            // still protects dark-adapted eyes.
            let hour = Calendar.autoupdatingCurrent.component(.hour, from: clock.now)
            isSunBelowCivilTwilight = hour >= 20 || hour < 6
            return
        }
        let now = clock.now
        if !force, let last = lastSunEvaluation, last.observer == observer, now.timeIntervalSince(last.date) < 30 {
            return
        }
        lastSunEvaluation = (now, observer)
        let sun = SkyFrame(date: now, observer: observer).horizontal(of: .sun, refraction: false)
        isSunBelowCivilTwilight = sun.altitude < -6
    }
}

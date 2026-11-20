import Foundation
import LodestarKit

/// Where the observer's position comes from.
enum LocationSource: Codable, Hashable, Sendable {
    /// The device's current GPS position.
    case device
    /// A user-saved observing site.
    case site(UUID)
}

/// A user-saved observing site (typically a dark-sky location).
struct SavedSite: Codable, Identifiable, Hashable, Sendable {
    static let maximumNameLength = 60

    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var elevation: Double
    /// IANA time zone of the site, when known (resolved by reverse geocoding).
    var timeZoneIdentifier: String?
    /// The recorded skyline (trees, mountains), or nil for an open horizon.
    var horizon: HorizonProfile?
    /// The skyline of the terrain computed from elevation data (hills, mountains), or nil when none was computed. Unlike
    /// `horizon` a flat one is kept: it says that the terrain was looked at and is flat. It is used where no skyline was
    /// recorded, and for the stretches a partial sweep left open.
    var terrainHorizon: HorizonProfile?

    /// Validates the coordinates and trims/limits the name; returns nil for invalid input.
    init?(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, elevation: Double = 0,
          timeZoneIdentifier: String? = nil, horizon: HorizonProfile? = nil, terrainHorizon: HorizonProfile? = nil) {
        guard let location = GeographicLocation.validated(latitude: latitude, longitude: longitude, elevation: elevation) else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = trimmed.isEmpty ? "Unnamed site" : String(trimmed.prefix(Self.maximumNameLength))
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.elevation = location.elevation
        self.timeZoneIdentifier = timeZoneIdentifier.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        self.horizon = horizon.flatMap { $0.isFlat ? nil : $0 }
        self.terrainHorizon = terrainHorizon
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, elevation, timeZoneIdentifier, horizon, terrainHorizon
    }

    /// Decodes and re-validates a stored site; invalid entries throw and are dropped by the caller.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let site = SavedSite(id: try c.decode(UUID.self, forKey: .id),
                                   name: try c.decode(String.self, forKey: .name),
                                   latitude: try c.decode(Double.self, forKey: .latitude),
                                   longitude: try c.decode(Double.self, forKey: .longitude),
                                   elevation: try c.decodeIfPresent(Double.self, forKey: .elevation) ?? 0,
                                   timeZoneIdentifier: try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier),
                                   // A damaged skyline is dropped rather than losing the site.
                                   horizon: (try? c.decodeIfPresent(HorizonProfile.self, forKey: .horizon)) ?? nil,
                                   terrainHorizon: (try? c.decodeIfPresent(HorizonProfile.self, forKey: .terrainHorizon)) ?? nil) else {
            throw DecodingError.dataCorruptedError(forKey: .latitude, in: c, debugDescription: "Invalid site coordinates")
        }
        self = site
    }

    var location: GeographicLocation {
        GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation)
    }

    var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
}

/// The Great Red Spot's System II longitude as the user read it (`longitude`, degrees, [0, 360)) on the day `asOf`.
/// The kit moves it on from there with the spot's usual drift. Absent, the kit's dated default applies.
struct GreatRedSpotSetting: Codable, Equatable, Sendable {
    var longitude: Double
    var asOf: Date

    /// The spot this describes, or `nil` when the values are not usable.
    var spot: GreatRedSpot? { GreatRedSpot(longitude: longitude, epoch: asOf) }
}

enum NightModeSetting: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, on, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .automatic: return "After Sunset"
        }
    }
}

enum HeadingSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Magnetometer-referenced heading (true north via CoreMotion or WMM declination).
    case compass
    /// Gyroscope-only heading after star alignment — immune to magnetic interference, drifts slowly.
    case gyroLock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compass: return "Compass"
        case .gyroLock: return "Gyro Lock"
        }
    }
}

enum CoordinateStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case sexagesimal, decimal
    var id: String { rawValue }
    var title: String { self == .sexagesimal ? "h m s / ° ′ ″" : "Decimal" }
}

/// How fast spoken guidance talks.
enum SpokenGuidanceRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case slow, normal
    var id: String { rawValue }
    var title: String { self == .slow ? "Slow" : "Normal" }
}

/// Every persisted user preference. Decoding is forward compatible: missing or invalid keys fall
/// back to defaults, so adding a setting never wipes the user's data.
struct AppSettings: Codable, Equatable, Sendable {
    static let maximumSavedSites = 100
    static let maximumCameraProfiles = 50
    static let maximumRecents = 20
    static let maximumFavorites = 200

    /// The polar-alignment errors the exposure calculator offers, in degrees.
    static let polarErrorRange: ClosedRange<Double> = 0.1...5

    /// The ISO speeds the exposure calculator offers.
    static let exposureISORange = 100...12800

    var hasCompletedOnboarding = false

    // Location
    var locationSource: LocationSource = .device
    var savedSites: [SavedSite] = []

    // Mount and sensors
    var mountPresetID: String = MountProfile.backCameraPortrait.id
    var headingSource: HeadingSource = .compass
    /// Attitude smoothing time constant in seconds.
    var smoothingTimeConstant: Double = 0.12

    // Camera and lens (for the framing rectangle and exposure tools). The camera profiles are the source; the single
    // camera keys below them follow the active profile (see `sanitizeCamera`), so code that reads them keeps working.
    var cameraProfiles: [CameraProfile] = []
    var activeCameraProfileID: UUID?
    var sensorID: String = SensorFormat.fullFrame.id
    var customSensorWidth: Double = 36
    var customSensorHeight: Double = 24
    var focalLength: Double = 24
    var aperture: Double = 2.8
    var pixelPitch: Double?
    /// The filter in front of the sensor: it decides how far the Moon warnings are relaxed for emission nebulae.
    var imagingFilter: ImagingFilter = .none

    // Exposure calculator
    /// The angle between a tracker's axis and the pole that the Tracked section works with, in degrees.
    var polarErrorDegrees: Double = 1.0
    /// The ISO speed of the Moon section.
    var exposureISO = 100

    // Night mode
    var nightMode: NightModeSetting = .automatic
    var nightIntensity: Double = 0.7
    var dimScreenAtNight = true
    var nightBrightness: Double = 0.2
    /// Experimental: multiply-blend red overlay over the whole UI (not guaranteed to reach UIKit content).
    var redFilterOverlay = false
    var cameraPreviewEnabled = true
    var cameraPreviewAtNight = false
    /// The screen brightness of the red torch.
    var torchBrightness: Double = 0.3

    // Feedback
    var hapticsEnabled = true
    var audioCuesEnabled = false
    var keepScreenAwake = true
    /// Speaks the pan and tilt to make while aiming ("Pan right 12, tilt up 3").
    var spokenGuidance = false
    var spokenGuidanceRate: SpokenGuidanceRate = .normal
    /// Shows the aiming on the Apple Watch while Aim is open (nothing is sent without a watch).
    var aimOnWatch = true

    // Sky display
    var showConstellationLines = true
    var showConstellationNames = true
    var showDeepSkyObjects = true
    var showMilkyWay = true
    /// A thin ring on the sky chart's horizon that is brighter toward the artificial light.
    var showHorizonGlow = true
    /// Deep-sky objects drawn in the sky views, up to this `Prominence` level (1 showpieces … 4 everything).
    var deepSkyProminence = 2
    var starMagnitudeLimit: Double = 5.0
    var coordinateStyle: CoordinateStyle = .sexagesimal

    // Atmosphere (refraction)
    var temperatureCelsius: Double = 10
    var pressureMillibars: Double = 1010

    // Objects
    var favoriteObjectIDs: [String] = []
    var recentObjectIDs: [String] = []

    // Jupiter
    /// The Great Red Spot's longitude the user entered, or `nil` for the kit's dated default.
    var greatRedSpot: GreatRedSpotSetting?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        hasCompletedOnboarding = value(.hasCompletedOnboarding, d.hasCompletedOnboarding)
        locationSource = value(.locationSource, d.locationSource)
        let storedSites = (try? c.decodeIfPresent([Lossy<SavedSite>].self, forKey: .savedSites)) ?? nil
        savedSites = Array((storedSites ?? []).compactMap(\.value).prefix(Self.maximumSavedSites))
        mountPresetID = value(.mountPresetID, d.mountPresetID)
        headingSource = value(.headingSource, d.headingSource)
        smoothingTimeConstant = value(.smoothingTimeConstant, d.smoothingTimeConstant)
        let storedProfiles = (try? c.decodeIfPresent([Lossy<CameraProfile>].self, forKey: .cameraProfiles)) ?? nil
        cameraProfiles = (storedProfiles ?? []).compactMap(\.value)
        activeCameraProfileID = value(.activeCameraProfileID, d.activeCameraProfileID)
        sensorID = value(.sensorID, d.sensorID)
        customSensorWidth = value(.customSensorWidth, d.customSensorWidth)
        customSensorHeight = value(.customSensorHeight, d.customSensorHeight)
        focalLength = value(.focalLength, d.focalLength)
        aperture = value(.aperture, d.aperture)
        pixelPitch = value(.pixelPitch, d.pixelPitch)
        imagingFilter = value(.imagingFilter, d.imagingFilter)
        polarErrorDegrees = value(.polarErrorDegrees, d.polarErrorDegrees)
        exposureISO = value(.exposureISO, d.exposureISO)
        nightMode = value(.nightMode, d.nightMode)
        nightIntensity = value(.nightIntensity, d.nightIntensity)
        dimScreenAtNight = value(.dimScreenAtNight, d.dimScreenAtNight)
        nightBrightness = value(.nightBrightness, d.nightBrightness)
        redFilterOverlay = value(.redFilterOverlay, d.redFilterOverlay)
        cameraPreviewEnabled = value(.cameraPreviewEnabled, d.cameraPreviewEnabled)
        cameraPreviewAtNight = value(.cameraPreviewAtNight, d.cameraPreviewAtNight)
        torchBrightness = value(.torchBrightness, d.torchBrightness)
        hapticsEnabled = value(.hapticsEnabled, d.hapticsEnabled)
        audioCuesEnabled = value(.audioCuesEnabled, d.audioCuesEnabled)
        keepScreenAwake = value(.keepScreenAwake, d.keepScreenAwake)
        spokenGuidance = value(.spokenGuidance, d.spokenGuidance)
        spokenGuidanceRate = value(.spokenGuidanceRate, d.spokenGuidanceRate)
        aimOnWatch = value(.aimOnWatch, d.aimOnWatch)
        showConstellationLines = value(.showConstellationLines, d.showConstellationLines)
        showConstellationNames = value(.showConstellationNames, d.showConstellationNames)
        showDeepSkyObjects = value(.showDeepSkyObjects, d.showDeepSkyObjects)
        showMilkyWay = value(.showMilkyWay, d.showMilkyWay)
        showHorizonGlow = value(.showHorizonGlow, d.showHorizonGlow)
        deepSkyProminence = value(.deepSkyProminence, d.deepSkyProminence)
        starMagnitudeLimit = value(.starMagnitudeLimit, d.starMagnitudeLimit)
        coordinateStyle = value(.coordinateStyle, d.coordinateStyle)
        temperatureCelsius = value(.temperatureCelsius, d.temperatureCelsius)
        pressureMillibars = value(.pressureMillibars, d.pressureMillibars)
        favoriteObjectIDs = Array(value(.favoriteObjectIDs, d.favoriteObjectIDs).prefix(Self.maximumFavorites))
        recentObjectIDs = Array(value(.recentObjectIDs, d.recentObjectIDs).prefix(Self.maximumRecents))
        greatRedSpot = value(.greatRedSpot, d.greatRedSpot)
        sanitize()
    }

    /// Clamps numeric preferences into their supported ranges (protects against corrupted storage).
    mutating func sanitize() {
        func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
        }
        smoothingTimeConstant = clamp(smoothingTimeConstant, 0...1, 0.12)
        sanitizeCamera()
        polarErrorDegrees = clamp(polarErrorDegrees, Self.polarErrorRange, 1)
        exposureISO = min(max(exposureISO, Self.exposureISORange.lowerBound), Self.exposureISORange.upperBound)
        nightIntensity = clamp(nightIntensity, 0.25...1, 0.7)
        nightBrightness = clamp(nightBrightness, 0.01...1, 0.2)
        torchBrightness = clamp(torchBrightness, 0.01...1, 0.3)
        starMagnitudeLimit = clamp(starMagnitudeLimit, 1...6.5, 5)
        deepSkyProminence = min(max(deepSkyProminence, 1), 4)
        temperatureCelsius = clamp(temperatureCelsius, -60...60, 10)
        pressureMillibars = clamp(pressureMillibars, 300...1100, 1010)
        if case .site(let id) = locationSource, !savedSites.contains(where: { $0.id == id }) {
            locationSource = .device
        }
        if let setting = greatRedSpot, setting.spot == nil { greatRedSpot = nil }
    }

    var atmosphere: Atmosphere {
        Atmosphere(pressureMillibars: pressureMillibars, temperatureCelsius: temperatureCelsius)
    }

    /// The Great Red Spot to compute with: the user's longitude, else `GreatRedSpot.reference`.
    var greatRedSpotOrDefault: GreatRedSpot { greatRedSpot?.spot ?? .reference }

    // MARK: Camera profiles

    /// The camera and lens in use: the stored profile with `activeCameraProfileID`, else the first one, else a profile
    /// made from the single camera keys (before the profiles exist).
    var activeCameraProfile: CameraProfile {
        cameraProfiles.first { $0.id == activeCameraProfileID } ?? cameraProfiles.first ?? singleCameraProfile
    }

    /// The camera of the single camera keys as a profile, with the identifier of the migrated profile.
    private var singleCameraProfile: CameraProfile {
        CameraProfile(id: CameraProfile.migratedID, name: CameraProfile.defaultName, sensorID: sensorID,
                      customSensorWidth: customSensorWidth, customSensorHeight: customSensorHeight,
                      focalLength: focalLength, aperture: aperture, pixelPitch: pixelPitch)
    }

    /// Takes a change that the `previous` settings went through to their single camera keys alone (code that predates
    /// the profiles writes them) into the active profile. A change to the profiles themselves wins, and so does any
    /// change to the profiles made together with one to the keys; `sanitizeCamera()` then lets the keys follow the
    /// profile.
    mutating func reconcileCamera(after previous: AppSettings) {
        let keysChanged = sensorID != previous.sensorID || customSensorWidth != previous.customSensorWidth
            || customSensorHeight != previous.customSensorHeight || focalLength != previous.focalLength
            || aperture != previous.aperture || pixelPitch != previous.pixelPitch
        let profilesChanged = cameraProfiles != previous.cameraProfiles
            || activeCameraProfileID != previous.activeCameraProfileID
        guard keysChanged, !profilesChanged, !cameraProfiles.isEmpty else {
            sanitizeCamera()
            return
        }
        let activeID = activeCameraProfile.id
        if let index = cameraProfiles.firstIndex(where: { $0.id == activeID }) {
            var updated = cameraProfiles[index]
            updated.sensorID = sensorID
            updated.customSensorWidth = customSensorWidth
            updated.customSensorHeight = customSensorHeight
            updated.focalLength = focalLength
            updated.aperture = aperture
            updated.pixelPitch = pixelPitch
            cameraProfiles[index] = updated.sanitized()
        }
        sanitizeCamera()
    }

    /// Makes sure there is a camera profile and an active one (the first start with profiles turns the single camera
    /// into "My camera"), limits every profile, and sets the single camera keys to the active profile.
    mutating func sanitizeCamera() {
        var seen = Set<UUID>()
        var profiles = cameraProfiles.filter { seen.insert($0.id).inserted }.prefix(Self.maximumCameraProfiles)
            .map { $0.sanitized() }
        if profiles.isEmpty { profiles = [singleCameraProfile] }
        let active = profiles.first { $0.id == activeCameraProfileID } ?? profiles[0]
        cameraProfiles = profiles
        activeCameraProfileID = active.id
        sensorID = active.sensorID
        customSensorWidth = active.customSensorWidth
        customSensorHeight = active.customSensorHeight
        focalLength = active.focalLength
        aperture = active.aperture
        pixelPitch = active.pixelPitch
    }
}

/// Decodes an element if possible and yields `nil` instead of failing the enclosing collection.
private struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// Persists `AppSettings` as one JSON blob in `UserDefaults` (debounced writes).
@MainActor
@Observable
final class SettingsStore {
    private static let storageKey = "lodestar.settings.v1"

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            // A change that only touches the single camera keys goes to the active camera profile, and the keys
            // follow the profile otherwise.
            var reconciled = settings
            reconciled.reconcileCamera(after: oldValue)
            if reconciled != settings { settings = reconciled }
            scheduleSave()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var initial: AppSettings
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            initial = decoded
        } else {
            initial = AppSettings()
        }
        initial.sanitizeCamera()
        settings = initial
    }

    /// Writes immediately (call when the app moves to the background).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    // MARK: Convenience mutations

    func toggleFavorite(_ objectID: String) {
        if let index = settings.favoriteObjectIDs.firstIndex(of: objectID) {
            settings.favoriteObjectIDs.remove(at: index)
        } else if settings.favoriteObjectIDs.count < AppSettings.maximumFavorites {
            settings.favoriteObjectIDs.append(objectID)
        }
    }

    func noteRecent(_ objectID: String) {
        var recents = settings.recentObjectIDs.filter { $0 != objectID }
        recents.insert(objectID, at: 0)
        settings.recentObjectIDs = Array(recents.prefix(AppSettings.maximumRecents))
    }

    @discardableResult
    func addSite(_ site: SavedSite) -> Bool {
        guard settings.savedSites.count < AppSettings.maximumSavedSites else { return false }
        settings.savedSites.append(site)
        return true
    }

    func updateSite(_ site: SavedSite) {
        guard let index = settings.savedSites.firstIndex(where: { $0.id == site.id }) else { return }
        settings.savedSites[index] = site
    }

    /// Adds `profile` and makes it the active camera; `false` when the maximum number of profiles is reached.
    @discardableResult
    func addCameraProfile(_ profile: CameraProfile) -> Bool {
        guard settings.cameraProfiles.count < AppSettings.maximumCameraProfiles else { return false }
        settings.cameraProfiles.append(profile.sanitized())
        settings.activeCameraProfileID = profile.id
        return true
    }

    /// Replaces the profile that has the identifier of `profile`.
    func updateCameraProfile(_ profile: CameraProfile) {
        guard let index = settings.cameraProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        settings.cameraProfiles[index] = profile.sanitized()
    }

    /// Makes the profile with `id` the active camera.
    func activateCameraProfile(_ id: UUID) {
        guard settings.cameraProfiles.contains(where: { $0.id == id }) else { return }
        settings.activeCameraProfileID = id
    }

    /// Deletes the profile with `id`; `false` (and nothing deleted) when it is the only one.
    @discardableResult
    func removeCameraProfile(_ id: UUID) -> Bool {
        guard settings.cameraProfiles.count > 1 else { return false }
        settings.cameraProfiles.removeAll { $0.id == id }
        return true
    }

    func removeSites(withIDs ids: Set<UUID>) {
        settings.savedSites.removeAll { ids.contains($0.id) }
        settings.sanitize()
    }
}

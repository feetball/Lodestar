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

    /// Validates the coordinates and trims/limits the name; returns nil for invalid input.
    init?(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, elevation: Double = 0,
          timeZoneIdentifier: String? = nil, horizon: HorizonProfile? = nil) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, elevation, timeZoneIdentifier, horizon
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
                                   horizon: (try? c.decodeIfPresent(HorizonProfile.self, forKey: .horizon)) ?? nil) else {
            throw DecodingError.dataCorruptedError(forKey: .latitude, in: c, debugDescription: "Invalid site coordinates")
        }
        self = site
    }

    var location: GeographicLocation {
        GeographicLocation(latitude: latitude, longitude: longitude, elevation: elevation)
    }

    var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
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

/// Every persisted user preference. Decoding is forward compatible: missing or invalid keys fall
/// back to defaults, so adding a setting never wipes the user's data.
struct AppSettings: Codable, Equatable, Sendable {
    static let maximumSavedSites = 100
    static let maximumRecents = 20
    static let maximumFavorites = 200

    var hasCompletedOnboarding = false

    // Location
    var locationSource: LocationSource = .device
    var savedSites: [SavedSite] = []

    // Mount and sensors
    var mountPresetID: String = MountProfile.backCameraPortrait.id
    var headingSource: HeadingSource = .compass
    /// Attitude smoothing time constant in seconds.
    var smoothingTimeConstant: Double = 0.12

    // Camera and lens (for the framing rectangle and exposure tools)
    var sensorID: String = SensorFormat.fullFrame.id
    var customSensorWidth: Double = 36
    var customSensorHeight: Double = 24
    var focalLength: Double = 24
    var aperture: Double = 2.8
    var pixelPitch: Double?

    // Night mode
    var nightMode: NightModeSetting = .automatic
    var nightIntensity: Double = 0.7
    var dimScreenAtNight = true
    var nightBrightness: Double = 0.2
    /// Experimental: multiply-blend red overlay over the whole UI (not guaranteed to reach UIKit content).
    var redFilterOverlay = false
    var cameraPreviewEnabled = true
    var cameraPreviewAtNight = false

    // Feedback
    var hapticsEnabled = true
    var audioCuesEnabled = false
    var keepScreenAwake = true

    // Sky display
    var showConstellationLines = true
    var showConstellationNames = true
    var showDeepSkyObjects = true
    var showMilkyWay = true
    var starMagnitudeLimit: Double = 5.0
    var coordinateStyle: CoordinateStyle = .sexagesimal

    // Atmosphere (refraction)
    var temperatureCelsius: Double = 10
    var pressureMillibars: Double = 1010

    // Objects
    var favoriteObjectIDs: [String] = []
    var recentObjectIDs: [String] = []

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
        sensorID = value(.sensorID, d.sensorID)
        customSensorWidth = value(.customSensorWidth, d.customSensorWidth)
        customSensorHeight = value(.customSensorHeight, d.customSensorHeight)
        focalLength = value(.focalLength, d.focalLength)
        aperture = value(.aperture, d.aperture)
        pixelPitch = value(.pixelPitch, d.pixelPitch)
        nightMode = value(.nightMode, d.nightMode)
        nightIntensity = value(.nightIntensity, d.nightIntensity)
        dimScreenAtNight = value(.dimScreenAtNight, d.dimScreenAtNight)
        nightBrightness = value(.nightBrightness, d.nightBrightness)
        redFilterOverlay = value(.redFilterOverlay, d.redFilterOverlay)
        cameraPreviewEnabled = value(.cameraPreviewEnabled, d.cameraPreviewEnabled)
        cameraPreviewAtNight = value(.cameraPreviewAtNight, d.cameraPreviewAtNight)
        hapticsEnabled = value(.hapticsEnabled, d.hapticsEnabled)
        audioCuesEnabled = value(.audioCuesEnabled, d.audioCuesEnabled)
        keepScreenAwake = value(.keepScreenAwake, d.keepScreenAwake)
        showConstellationLines = value(.showConstellationLines, d.showConstellationLines)
        showConstellationNames = value(.showConstellationNames, d.showConstellationNames)
        showDeepSkyObjects = value(.showDeepSkyObjects, d.showDeepSkyObjects)
        showMilkyWay = value(.showMilkyWay, d.showMilkyWay)
        starMagnitudeLimit = value(.starMagnitudeLimit, d.starMagnitudeLimit)
        coordinateStyle = value(.coordinateStyle, d.coordinateStyle)
        temperatureCelsius = value(.temperatureCelsius, d.temperatureCelsius)
        pressureMillibars = value(.pressureMillibars, d.pressureMillibars)
        favoriteObjectIDs = Array(value(.favoriteObjectIDs, d.favoriteObjectIDs).prefix(Self.maximumFavorites))
        recentObjectIDs = Array(value(.recentObjectIDs, d.recentObjectIDs).prefix(Self.maximumRecents))
        sanitize()
    }

    /// Clamps numeric preferences into their supported ranges (protects against corrupted storage).
    mutating func sanitize() {
        func clamp(_ v: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            v.isFinite ? min(max(v, range.lowerBound), range.upperBound) : fallback
        }
        smoothingTimeConstant = clamp(smoothingTimeConstant, 0...1, 0.12)
        customSensorWidth = clamp(customSensorWidth, 1...100, 36)
        customSensorHeight = clamp(customSensorHeight, 1...100, 24)
        focalLength = clamp(focalLength, 4...2000, 24)
        aperture = clamp(aperture, 0.95...32, 2.8)
        if let pitch = pixelPitch { pixelPitch = pitch.isFinite && (0.5...20).contains(pitch) ? pitch : nil }
        nightIntensity = clamp(nightIntensity, 0.25...1, 0.7)
        nightBrightness = clamp(nightBrightness, 0.01...1, 0.2)
        starMagnitudeLimit = clamp(starMagnitudeLimit, 1...6.5, 5)
        temperatureCelsius = clamp(temperatureCelsius, -60...60, 10)
        pressureMillibars = clamp(pressureMillibars, 300...1100, 1010)
        if case .site(let id) = locationSource, !savedSites.contains(where: { $0.id == id }) {
            locationSource = .device
        }
    }

    var atmosphere: Atmosphere {
        Atmosphere(pressureMillibars: pressureMillibars, temperatureCelsius: temperatureCelsius)
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
            scheduleSave()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
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

    func removeSites(withIDs ids: Set<UUID>) {
        settings.savedSites.removeAll { ids.contains($0.id) }
        settings.sanitize()
    }
}

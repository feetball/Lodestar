import Foundation
import LodestarKit

/// A camera and lens the photographer uses, kept in the settings: the sensor (a preset or a custom size), focal length,
/// aperture, pixel pitch, the lens projection and, for a circular fisheye, the image circle.
///
/// The initialisers limit every value to the ranges the settings keep, so a profile made by them can be used as it
/// is. The properties are variables so that an editor can bind to them; `sanitized()` limits them again before a
/// profile is saved. The JSON form is the one of the Android app.
struct CameraProfile: Codable, Identifiable, Hashable, Sendable {
    /// The longest name of a profile, in characters.
    static let maximumNameLength = 40

    /// The sensor identifier of a profile with a custom sensor size.
    static let customSensorID = "custom"

    /// The name of the profile made from the camera of earlier versions.
    static let defaultName = "My camera"

    /// The name of a profile made from a photo that does not name its camera.
    static let photoName = "Camera from photo"

    /// The identifier of the profile made from the camera of earlier versions, the same on every device.
    static let migratedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))

    /// The supported custom sensor sizes, in millimetres.
    static let customSensorRange = 1.0...100.0

    /// The supported pixel pitches, in micrometres.
    static let pixelPitchRange = 0.5...20.0

    var id: UUID
    /// The name in the list, at most `maximumNameLength` characters.
    var name: String
    /// The id of a `SensorFormat` preset, or `customSensorID` when the sensor has the size below.
    var sensorID: String
    /// The width in millimetres of a custom sensor (kept while a preset is chosen).
    var customSensorWidth: Double
    /// The height in millimetres of a custom sensor.
    var customSensorHeight: Double
    /// The real focal length in millimetres.
    var focalLength: Double
    /// The f-number.
    var aperture: Double
    /// The pixel pitch in micrometres, or nil if unknown.
    var pixelPitch: Double?
    /// How the lens maps the sky onto the sensor.
    var projection: LensProjection
    /// The diameter in millimetres of the image circle of a circular fisheye, or nil if it covers the sensor.
    var imageCircleDiameter: Double?

    /// Creates a profile, limiting every value to its range: a number that is not finite takes the default of a 24 mm
    /// f/2.8 full-frame lens, a pixel pitch or image circle out of range is dropped, a sensor that is not a preset is
    /// custom, and a name is trimmed, cut at `maximumNameLength` and replaced by "Camera" when empty.
    init(
        id: UUID = UUID(),
        name: String,
        sensorID: String = SensorFormat.fullFrame.id,
        customSensorWidth: Double = 36,
        customSensorHeight: Double = 24,
        focalLength: Double = LensSetup.defaultFocalLengthMillimeters,
        aperture: Double = LensSetup.defaultAperture,
        pixelPitch: Double? = nil,
        projection: LensProjection = .rectilinear,
        imageCircleDiameter: Double? = nil
    ) {
        func limited(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        self.id = id
        self.name = Self.limitedName(name)
        self.sensorID = SensorFormat.presets.contains { $0.id == sensorID } ? sensorID : Self.customSensorID
        self.customSensorWidth = limited(customSensorWidth, Self.customSensorRange, 36)
        self.customSensorHeight = limited(customSensorHeight, Self.customSensorRange, 24)
        self.focalLength = limited(focalLength, LensSetup.focalLengthRange, LensSetup.defaultFocalLengthMillimeters)
        self.aperture = limited(aperture, LensSetup.apertureRange, LensSetup.defaultAperture)
        self.pixelPitch = pixelPitch.flatMap { $0.isFinite && Self.pixelPitchRange.contains($0) ? $0 : nil }
        self.projection = projection
        self.imageCircleDiameter = imageCircleDiameter.flatMap {
            $0.isFinite && LensSetup.imageCircleRange.contains($0) ? $0 : nil
        }
    }

    /// The profile of a preset: its sensor, lens, pixel pitch and projection, named after it.
    init(preset: CameraPreset, id: UUID = UUID()) {
        let isPresetSensor = SensorFormat.presets.contains { $0.id == preset.sensor.id }
        self.init(
            id: id,
            name: preset.name,
            sensorID: isPresetSensor ? preset.sensor.id : Self.customSensorID,
            customSensorWidth: preset.sensor.widthMillimeters,
            customSensorHeight: preset.sensor.heightMillimeters,
            focalLength: preset.focalLengthMillimeters,
            aperture: preset.aperture,
            pixelPitch: preset.pixelPitchMicrometers,
            projection: preset.projection
        )
    }

    /// The profile a photo suggests (see `CameraPhotoMetadata`), named after the camera that took it. What the photo
    /// does not say stays at the defaults of a 24 mm f/2.8 full-frame lens, so the photographer sees it in the
    /// editor and corrects it.
    init(photo suggestion: CameraPhotoSuggestion, id: UUID = UUID()) {
        let sensor = suggestion.sensor
        let presetID = sensor.flatMap { sensor in SensorFormat.presets.contains { $0.id == sensor.id } ? sensor.id : nil }
        self.init(
            id: id,
            name: suggestion.name ?? Self.photoName,
            sensorID: presetID ?? (sensor != nil ? Self.customSensorID : SensorFormat.fullFrame.id),
            customSensorWidth: sensor?.widthMillimeters ?? 36,
            customSensorHeight: sensor?.heightMillimeters ?? 24,
            focalLength: suggestion.focalLengthMillimeters,
            aperture: suggestion.aperture ?? LensSetup.defaultAperture,
            pixelPitch: suggestion.pixelPitchMicrometers
        )
    }

    /// The profile with every value limited again.
    func sanitized() -> CameraProfile {
        CameraProfile(
            id: id, name: name, sensorID: sensorID, customSensorWidth: customSensorWidth,
            customSensorHeight: customSensorHeight, focalLength: focalLength, aperture: aperture,
            pixelPitch: pixelPitch, projection: projection, imageCircleDiameter: imageCircleDiameter
        )
    }

    /// `name` trimmed and cut to `maximumNameLength` characters; "Camera" when nothing is left.
    static func limitedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(maximumNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? "Camera" : cut
    }

    // MARK: Derived

    /// The sensor of the profile.
    var sensor: SensorFormat {
        SensorFormat.presets.first { $0.id == sensorID }
            ?? SensorFormat.custom(width: customSensorWidth, height: customSensorHeight)
    }

    /// Whether the sensor has a custom size rather than a preset's.
    var isCustomSensor: Bool {
        !SensorFormat.presets.contains { $0.id == sensorID }
    }

    /// The profile as the camera and lens the engine works with.
    var lensSetup: LensSetup {
        LensSetup(
            sensor: sensor,
            focalLengthMillimeters: focalLength,
            aperture: aperture,
            pixelPitchMicrometers: pixelPitch,
            projection: projection,
            imageCircleDiameterMillimeters: imageCircleDiameter
        )
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, sensorID, customSensorWidth, customSensorHeight, focalLength, aperture, pixelPitch
        case projection, imageCircleDiameter
    }

    /// Decodes a stored profile. A missing or invalid identifier throws (the caller drops the entry); any other missing
    /// or invalid value takes its default, so one bad number does not lose the profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: value(.name) ?? "Camera",
            sensorID: value(.sensorID) ?? SensorFormat.fullFrame.id,
            customSensorWidth: value(.customSensorWidth) ?? 36,
            customSensorHeight: value(.customSensorHeight) ?? 24,
            focalLength: value(.focalLength) ?? LensSetup.defaultFocalLengthMillimeters,
            aperture: value(.aperture) ?? LensSetup.defaultAperture,
            pixelPitch: value(.pixelPitch),
            projection: value(.projection) ?? .rectilinear,
            imageCircleDiameter: value(.imageCircleDiameter)
        )
    }

    /// Encodes the profile; an unknown pixel pitch and a missing image circle are left out.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(sensorID, forKey: .sensorID)
        try c.encode(customSensorWidth, forKey: .customSensorWidth)
        try c.encode(customSensorHeight, forKey: .customSensorHeight)
        try c.encode(focalLength, forKey: .focalLength)
        try c.encode(aperture, forKey: .aperture)
        try c.encodeIfPresent(pixelPitch, forKey: .pixelPitch)
        try c.encode(projection, forKey: .projection)
        try c.encodeIfPresent(imageCircleDiameter, forKey: .imageCircleDiameter)
    }
}

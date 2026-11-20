import Foundation

/// What the EXIF header of a photo says about the camera and lens that took it, for pre-filling a camera profile.
///
/// Every field is optional, because cameras and editors leave tags out, and none is trusted: `suggestion()` checks
/// each value against the supported ranges and ignores what does not fit. No photo is read here; the apps read the
/// tags (`Model`, `FocalLength`, `FocalLenIn35mmFilm`, `FNumber` and the pixel dimensions) and hand the numbers over.
public struct CameraPhotoMetadata: Hashable, Sendable {

    /// The longest name a suggestion keeps, in characters.
    public static let maximumNameLength = 40

    /// The crop factors that are believed: 0.5 (large medium format) to 10 (the smallest phone sensors).
    public static let cropFactorRange: ClosedRange<Double> = 0.5...10

    /// How far a crop factor may be from a preset's, as a ratio, for the preset to be chosen: 10 %.
    public static let presetTolerance = 0.10

    /// The largest picture dimension that is believed, in pixels.
    public static let maximumPixels = 100_000

    /// The camera model (EXIF `Model`), for example "NIKON D850".
    public let cameraModel: String?

    /// The real focal length in millimetres (EXIF `FocalLength`).
    public let focalLengthMillimeters: Double?

    /// The focal length that frames the same view on full frame, in millimetres (EXIF `FocalLenIn35mmFilm`).
    public let focalLength35mmEquivalent: Double?

    /// The f-number the picture was taken at (EXIF `FNumber`).
    public let aperture: Double?

    /// The width of the picture in pixels, whichever way the camera was turned.
    public let pixelWidth: Int?

    /// The height of the picture in pixels.
    public let pixelHeight: Int?

    /// Creates the metadata of a photo; nil for what the photo does not say.
    public init(
        cameraModel: String?,
        focalLengthMillimeters: Double?,
        focalLength35mmEquivalent: Double?,
        aperture: Double?,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) {
        self.cameraModel = cameraModel
        self.focalLengthMillimeters = focalLengthMillimeters
        self.focalLength35mmEquivalent = focalLength35mmEquivalent
        self.aperture = aperture
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The camera profile the photo suggests, or nil if it has no usable focal length.
    ///
    /// The crop factor is the 35 mm equivalent over the real focal length. The sensor is the preset whose crop
    /// factor is nearest (within `presetTolerance`); a crop factor that matches no preset gives a custom sensor of
    /// that diagonal with the picture's aspect ratio (3:2 without pixel dimensions). The pixel pitch is the
    /// sensor's longer side over the picture's longer side in pixels, so it assumes the picture is not cropped
    /// or reduced.
    public func suggestion() -> CameraPhotoSuggestion? {
        guard let focalLength = focalLengthMillimeters, LensSetup.focalLengthRange.contains(focalLength) else { return nil }
        let aperture = self.aperture.flatMap { LensSetup.apertureRange.contains($0) ? $0 : nil }
        let width = pixelWidth.flatMap { (1...Self.maximumPixels).contains($0) ? $0 : nil }
        let height = pixelHeight.flatMap { (1...Self.maximumPixels).contains($0) ? $0 : nil }
        let cropFactor: Double? = focalLength35mmEquivalent.flatMap { equivalent in
            guard equivalent.isFinite, equivalent > 0 else { return nil }
            let crop = equivalent / focalLength
            return Self.cropFactorRange.contains(crop) ? crop : nil
        }
        let sensor = cropFactor.flatMap { Self.sensor(forCropFactor: $0, width: width, height: height) }
        var pitch: Double?
        if let sensor, let width, let height {
            let micrometers = 1000 * max(sensor.widthMillimeters, sensor.heightMillimeters) / Double(max(width, height))
            pitch = SensorFormat.pixelPitchRange.contains(micrometers) ? micrometers : nil
        }
        let megapixels: Double? = if let width, let height { Double(width) * Double(height) / 1_000_000 } else { nil }
        return CameraPhotoSuggestion(
            name: Self.cleanedName(cameraModel),
            sensor: sensor,
            cropFactor: cropFactor,
            focalLengthMillimeters: focalLength,
            aperture: aperture,
            pixelPitchMicrometers: pitch,
            megapixels: megapixels
        )
    }

    private static func sensor(forCropFactor cropFactor: Double, width: Int?, height: Int?) -> SensorFormat? {
        let nearest = SensorFormat.presets.min {
            abs(log(cropFactor / $0.cropFactor)) < abs(log(cropFactor / $1.cropFactor))
        }
        if let nearest, abs(cropFactor / nearest.cropFactor - 1) <= presetTolerance { return nearest }
        let diagonal = SensorFormat.fullFrame.diagonalMillimeters / cropFactor
        let longSide: Double
        let shortSide: Double
        if let width, let height {
            longSide = Double(max(width, height))
            shortSide = Double(min(width, height))
        } else {
            longSide = 3
            shortSide = 2
        }
        let sensorWidth = diagonal * longSide / hypot(longSide, shortSide)
        let sensorHeight = diagonal * shortSide / hypot(longSide, shortSide)
        return SensorFormat.validated(width: sensorWidth, height: sensorHeight)
    }

    /// The model trimmed of white space and control characters and cut to `maximumNameLength`, or nil if nothing is left.
    private static func cleanedName(_ model: String?) -> String? {
        guard let model else { return nil }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: model.unicodeScalars.filter { $0.properties.generalCategory != .control })
        let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var cut = String.UnicodeScalarView()
        cut.append(contentsOf: cleaned.unicodeScalars.prefix(maximumNameLength))
        let name = String(cut).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// The camera profile that a photo's metadata suggests; see `CameraPhotoMetadata.suggestion()`. The numbers are inside the
/// ranges of `LensSetup` and `SensorFormat`, so they can be used as they are.
public struct CameraPhotoSuggestion: Hashable, Sendable {
    /// The camera model, or nil if the photo has none.
    public let name: String?

    /// The sensor, or nil if the photo says nothing about the crop factor.
    public let sensor: SensorFormat?

    /// The crop factor the sensor was found from, or nil if it could not be worked out.
    public let cropFactor: Double?

    /// The real focal length in millimetres.
    public let focalLengthMillimeters: Double

    /// The aperture the photo was taken at, or nil if unknown.
    public let aperture: Double?

    /// The estimated pixel pitch in micrometres, or nil if it cannot be estimated.
    public let pixelPitchMicrometers: Double?

    /// The picture's resolution in millions of pixels, or nil if its size is unknown.
    public let megapixels: Double?
}

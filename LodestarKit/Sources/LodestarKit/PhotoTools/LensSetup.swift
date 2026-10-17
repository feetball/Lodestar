/// A camera and lens combination: the sensor, focal length, aperture and, optionally, pixel pitch.
///
/// Every value of this type is inside the supported ranges, whichever initialiser or decoder
/// produced it, so code that receives a `LensSetup` never has to re-validate it.
public struct LensSetup: Hashable, Codable, Sendable {

    // MARK: Ranges and defaults

    /// The supported focal lengths, in millimetres.
    public static let focalLengthRange: ClosedRange<Double> = 4...2000

    /// The supported apertures, as f-numbers.
    public static let apertureRange: ClosedRange<Double> = 0.95...32

    /// The focal length used in place of one that is not a number, in millimetres.
    public static let defaultFocalLengthMillimeters = 24.0

    /// The aperture used in place of one that is not a number.
    public static let defaultAperture = 2.8

    // MARK: Properties

    /// The camera's sensor.
    public let sensor: SensorFormat

    /// The lens focal length in millimetres (the real focal length, not the full-frame equivalent).
    public let focalLengthMillimeters: Double

    /// The working aperture as an f-number, for example 2.8.
    public let aperture: Double

    /// The sensor's pixel pitch in micrometres, or nil if unknown.
    ///
    /// The NPF exposure rule needs it; `SensorFormat.pixelPitchMicrometers(megapixels:)` derives it
    /// from the camera's resolution.
    public let pixelPitchMicrometers: Double?

    /// Creates a setup, limiting every value to its supported range.
    ///
    /// The focal length is limited to `focalLengthRange` and the aperture to `apertureRange`; a
    /// value that is not finite becomes `defaultFocalLengthMillimeters` or `defaultAperture`. A
    /// pixel pitch that is not finite or lies outside `SensorFormat.pixelPitchRange` is more likely a
    /// unit mistake than a near miss, so it is dropped and treated as unknown. Use
    /// `validated(sensor:focalLengthMillimeters:aperture:pixelPitchMicrometers:)` to reject invalid
    /// input instead of correcting it.
    ///
    /// - Parameters:
    ///   - sensor: The camera's sensor.
    ///   - focalLengthMillimeters: The lens focal length.
    ///   - aperture: The f-number.
    ///   - pixelPitchMicrometers: The pixel pitch, or nil if unknown.
    public init(
        sensor: SensorFormat,
        focalLengthMillimeters: Double,
        aperture: Double,
        pixelPitchMicrometers: Double? = nil
    ) {
        self.sensor = sensor
        self.focalLengthMillimeters = RangeLimiter.limit(
            focalLengthMillimeters, to: Self.focalLengthRange, fallback: Self.defaultFocalLengthMillimeters
        )
        self.aperture = RangeLimiter.limit(aperture, to: Self.apertureRange, fallback: Self.defaultAperture)
        self.pixelPitchMicrometers = pixelPitchMicrometers.flatMap {
            SensorFormat.pixelPitchRange.contains($0) ? $0 : nil
        }
    }

    /// Creates a setup only if every value is finite and within its supported range; otherwise
    /// returns nil. Use this for user input that should be rejected rather than corrected.
    public static func validated(
        sensor: SensorFormat,
        focalLengthMillimeters: Double,
        aperture: Double,
        pixelPitchMicrometers: Double? = nil
    ) -> LensSetup? {
        // `ClosedRange.contains` is false for NaN and infinities, so these checks also reject them.
        guard focalLengthRange.contains(focalLengthMillimeters),
              apertureRange.contains(aperture),
              pixelPitchMicrometers.map({ SensorFormat.pixelPitchRange.contains($0) }) ?? true else { return nil }
        return LensSetup(
            sensor: sensor,
            focalLengthMillimeters: focalLengthMillimeters,
            aperture: aperture,
            pixelPitchMicrometers: pixelPitchMicrometers
        )
    }

    // MARK: Derived values

    /// The focal length multiplied by the sensor's crop factor: the focal length that frames the
    /// same view on a full-frame camera.
    public var equivalentFocalLengthMillimeters: Double {
        focalLengthMillimeters * sensor.cropFactor
    }

    /// The angular size of the frame, for a camera held in landscape orientation.
    public var fieldOfView: FrameSize {
        FrameSize(sensor: sensor, focalLength: focalLengthMillimeters)
    }

    /// The angle on the sky covered by one pixel, in arcseconds, or nil if the pixel pitch is unknown.
    ///
    /// Uses the small-angle relation `pitch / focal length`, which holds near the centre of the frame.
    public var imageScaleArcsecondsPerPixel: Double? {
        pixelPitchMicrometers.map(imageScale(forPixelPitch:))
    }

    /// The angle covered by one pixel of the given pitch behind this lens, in arcseconds.
    func imageScale(forPixelPitch pitch: Double) -> Double {
        Self.arcsecondsPerMicrometerPerMillimeter * pitch / focalLengthMillimeters
    }

    /// Arcseconds subtended by a 1 µm pixel behind a 1 mm focal length: the arcseconds in a radian
    /// divided by the 1000 micrometres in a millimetre.
    private static let arcsecondsPerMicrometerPerMillimeter = 180 * 3600 / Double.pi / 1000

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case sensor, focalLengthMillimeters, aperture, pixelPitchMicrometers
    }

    /// Decodes a setup, throwing `DecodingError.dataCorrupted` if a value is outside its supported
    /// range. Stored data is rejected rather than corrected, so corruption is not hidden.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sensor = try container.decode(SensorFormat.self, forKey: .sensor)
        let focalLength = try container.decode(Double.self, forKey: .focalLengthMillimeters)
        let aperture = try container.decode(Double.self, forKey: .aperture)
        let pitch = try container.decodeIfPresent(Double.self, forKey: .pixelPitchMicrometers)
        guard let setup = LensSetup.validated(
            sensor: sensor,
            focalLengthMillimeters: focalLength,
            aperture: aperture,
            pixelPitchMicrometers: pitch
        ) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "The lens setup has a value outside the supported ranges."
                )
            )
        }
        self = setup
    }
}

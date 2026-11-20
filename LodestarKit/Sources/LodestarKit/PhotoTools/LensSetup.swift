/// A camera and lens combination: the sensor, focal length, aperture and, optionally, pixel pitch, projection and
/// image circle.
///
/// Every value of this type is inside the supported ranges, whichever initialiser or decoder
/// produced it, so code that receives a `LensSetup` never has to re-validate it.
///
/// The JSON form has the keys `sensor`, `focalLengthMillimeters`, `aperture` and, when known,
/// `pixelPitchMicrometers`; `projection` is written only for a fisheye lens and `imageCircleDiameterMillimeters`
/// only when there is an image circle, so the JSON of an ordinary lens is unchanged. Decoding reads a missing
/// `projection` as rectilinear.
public struct LensSetup: Hashable, Codable, Sendable {

    // MARK: Ranges and defaults

    /// The supported focal lengths, in millimetres.
    public static let focalLengthRange: ClosedRange<Double> = 4...2000

    /// The supported apertures, as f-numbers.
    public static let apertureRange: ClosedRange<Double> = 0.95...32

    /// The supported diameters of an image circle, in millimetres; the range of a sensor dimension.
    public static let imageCircleRange: ClosedRange<Double> = SensorFormat.dimensionRange

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

    /// How the lens maps angles to positions on the sensor; `LensProjection.rectilinear` for an ordinary lens.
    public let projection: LensProjection

    /// The diameter in millimetres of the circle the lens draws on the sensor, or nil if it covers the whole sensor.
    ///
    /// Only a circular fisheye whose image circle is smaller than the sensor has one: the frame is then that circle,
    /// or what is left of it inside the sensor.
    public let imageCircleDiameterMillimeters: Double?

    /// Creates a setup, limiting every value to its supported range.
    ///
    /// The focal length is limited to `focalLengthRange` and the aperture to `apertureRange`; a
    /// value that is not finite becomes `defaultFocalLengthMillimeters` or `defaultAperture`. A
    /// pixel pitch that is not finite or lies outside `SensorFormat.pixelPitchRange` is more likely a
    /// unit mistake than a near miss, so it is dropped and treated as unknown; so is an image circle outside
    /// `imageCircleRange`. Use
    /// `validated(sensor:focalLengthMillimeters:aperture:pixelPitchMicrometers:projection:imageCircleDiameterMillimeters:)`
    /// to reject invalid input instead of correcting it.
    ///
    /// - Parameters:
    ///   - sensor: The camera's sensor.
    ///   - focalLengthMillimeters: The lens focal length.
    ///   - aperture: The f-number.
    ///   - pixelPitchMicrometers: The pixel pitch, or nil if unknown.
    ///   - projection: The lens projection.
    ///   - imageCircleDiameterMillimeters: The diameter of the lens's image circle, or nil if it covers the sensor.
    public init(
        sensor: SensorFormat,
        focalLengthMillimeters: Double,
        aperture: Double,
        pixelPitchMicrometers: Double? = nil,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) {
        self.sensor = sensor
        self.focalLengthMillimeters = RangeLimiter.limit(
            focalLengthMillimeters, to: Self.focalLengthRange, fallback: Self.defaultFocalLengthMillimeters
        )
        self.aperture = RangeLimiter.limit(aperture, to: Self.apertureRange, fallback: Self.defaultAperture)
        self.pixelPitchMicrometers = pixelPitchMicrometers.flatMap {
            SensorFormat.pixelPitchRange.contains($0) ? $0 : nil
        }
        self.projection = projection
        self.imageCircleDiameterMillimeters = imageCircleDiameterMillimeters.flatMap {
            Self.imageCircleRange.contains($0) ? $0 : nil
        }
    }

    /// Creates a setup only if every value is finite and within its supported range; otherwise
    /// returns nil. Use this for user input that should be rejected rather than corrected.
    public static func validated(
        sensor: SensorFormat,
        focalLengthMillimeters: Double,
        aperture: Double,
        pixelPitchMicrometers: Double? = nil,
        projection: LensProjection = .rectilinear,
        imageCircleDiameterMillimeters: Double? = nil
    ) -> LensSetup? {
        // `ClosedRange.contains` is false for NaN and infinities, so these checks also reject them.
        guard focalLengthRange.contains(focalLengthMillimeters),
              apertureRange.contains(aperture),
              pixelPitchMicrometers.map({ SensorFormat.pixelPitchRange.contains($0) }) ?? true,
              imageCircleDiameterMillimeters.map({ imageCircleRange.contains($0) }) ?? true else { return nil }
        return LensSetup(
            sensor: sensor,
            focalLengthMillimeters: focalLengthMillimeters,
            aperture: aperture,
            pixelPitchMicrometers: pixelPitchMicrometers,
            projection: projection,
            imageCircleDiameterMillimeters: imageCircleDiameterMillimeters
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
        FrameSize(
            sensor: sensor,
            focalLength: focalLengthMillimeters,
            projection: projection,
            imageCircleDiameterMillimeters: imageCircleDiameterMillimeters
        )
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
        case sensor, focalLengthMillimeters, aperture, pixelPitchMicrometers, projection, imageCircleDiameterMillimeters
    }

    /// Decodes a setup, throwing `DecodingError.dataCorrupted` if a value is outside its supported
    /// range. Stored data is rejected rather than corrected, so corruption is not hidden. The keys
    /// `projection`, `pixelPitchMicrometers` and `imageCircleDiameterMillimeters` may be absent (or null), which
    /// reads as rectilinear, unknown and no image circle; an unknown projection name throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sensor = try container.decode(SensorFormat.self, forKey: .sensor)
        let focalLength = try container.decode(Double.self, forKey: .focalLengthMillimeters)
        let aperture = try container.decode(Double.self, forKey: .aperture)
        let pitch = try container.decodeIfPresent(Double.self, forKey: .pixelPitchMicrometers)
        let projection = try container.decodeIfPresent(LensProjection.self, forKey: .projection) ?? .rectilinear
        let imageCircle = try container.decodeIfPresent(Double.self, forKey: .imageCircleDiameterMillimeters)
        guard let setup = LensSetup.validated(
            sensor: sensor,
            focalLengthMillimeters: focalLength,
            aperture: aperture,
            pixelPitchMicrometers: pitch,
            projection: projection,
            imageCircleDiameterMillimeters: imageCircle
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

    /// Encodes the setup. An unknown pixel pitch, the default projection and a missing image circle are left out,
    /// so an ordinary lens keeps its JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensor, forKey: .sensor)
        try container.encode(focalLengthMillimeters, forKey: .focalLengthMillimeters)
        try container.encode(aperture, forKey: .aperture)
        try container.encodeIfPresent(pixelPitchMicrometers, forKey: .pixelPitchMicrometers)
        if projection != .rectilinear { try container.encode(projection, forKey: .projection) }
        try container.encodeIfPresent(imageCircleDiameterMillimeters, forKey: .imageCircleDiameterMillimeters)
    }
}

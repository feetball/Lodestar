/// The imaging area of a camera sensor.
///
/// Sensor formats feed the field-of-view and exposure calculations. Width and height are the
/// dimensions of the imaging area in millimetres, with the camera held in landscape orientation.
/// Use a preset such as `fullFrame`, pick one from `presets`, or build one with
/// `custom(width:height:)`. Every value of this type has a size within `dimensionRange`, so the
/// arithmetic built on it cannot meet a zero, negative or non-finite dimension; decoding rejects
/// stored data that would break this.
public struct SensorFormat: Identifiable, Hashable, Codable, Sendable {

    // MARK: Validation ranges

    /// The accepted range, in millimetres, for either dimension of a sensor.
    public static let dimensionRange: ClosedRange<Double> = 1...200

    /// The accepted range, in micrometres, for a pixel pitch.
    ///
    /// Wide enough for every consumer camera, from smartphones to low-light bodies with very large
    /// pixels, while still rejecting values that are obviously a unit mistake.
    public static let pixelPitchRange: ClosedRange<Double> = 0.3...100

    // MARK: Properties

    /// A stable identifier: the preset's name, or `custom-<width>x<height>` for custom sizes.
    public let id: String

    /// A short name for pickers, for example "Full Frame".
    public let name: String

    /// The sensor width in millimetres.
    public let widthMillimeters: Double

    /// The sensor height in millimetres.
    public let heightMillimeters: Double

    // MARK: Presets

    /// 35 mm full frame, 36 × 24 mm.
    public static let fullFrame = SensorFormat(id: "fullFrame", name: "Full Frame", width: 36, height: 24)

    /// APS-C as used by Nikon, Sony, Fujifilm and Pentax, 23.5 × 15.6 mm (crop factor about 1.53).
    public static let apsC = SensorFormat(id: "apsC", name: "APS-C", width: 23.5, height: 15.6)

    /// APS-C as used by Canon, 22.3 × 14.9 mm (crop factor about 1.61).
    public static let apsCCanon = SensorFormat(id: "apsCCanon", name: "APS-C (Canon)", width: 22.3, height: 14.9)

    /// Micro Four Thirds, 17.3 × 13 mm (crop factor about 2.0).
    public static let microFourThirds = SensorFormat(
        id: "microFourThirds", name: "Micro Four Thirds", width: 17.3, height: 13
    )

    /// One-inch type, 13.2 × 8.8 mm (crop factor about 2.7).
    public static let oneInch = SensorFormat(id: "oneInch", name: "1-inch", width: 13.2, height: 8.8)

    /// Medium format 44 × 33, 43.8 × 32.9 mm (crop factor about 0.79).
    public static let mediumFormat44x33 = SensorFormat(
        id: "mediumFormat44x33", name: "Medium Format 44\u{00D7}33", width: 43.8, height: 32.9
    )

    /// All presets, in the order a picker should list them.
    public static let presets: [SensorFormat] = [
        fullFrame, apsC, apsCCanon, microFourThirds, oneInch, mediumFormat44x33,
    ]

    /// Creates a sensor format of the given size, limiting each dimension to `dimensionRange`.
    ///
    /// A dimension that is not finite becomes the corresponding full-frame dimension (36 or
    /// 24 mm). Use `validated(width:height:)` to reject invalid input instead of adjusting it.
    ///
    /// - Parameters:
    ///   - width: The sensor width in millimetres.
    ///   - height: The sensor height in millimetres.
    public static func custom(width: Double, height: Double) -> SensorFormat {
        let width = RangeLimiter.limit(width, to: dimensionRange, fallback: fullFrame.widthMillimeters)
        let height = RangeLimiter.limit(height, to: dimensionRange, fallback: fullFrame.heightMillimeters)
        let widthLabel = NumberText.trimmedDescription(width, maxDecimals: 2)
        let heightLabel = NumberText.trimmedDescription(height, maxDecimals: 2)
        return SensorFormat(
            id: "custom-\(width)x\(height)",
            name: "Custom \(widthLabel) \u{00D7} \(heightLabel) mm",
            width: width,
            height: height
        )
    }

    /// Creates a custom sensor format only if both dimensions are finite and within
    /// `dimensionRange`; otherwise returns nil. Use this for user input that should be rejected
    /// rather than corrected.
    public static func validated(width: Double, height: Double) -> SensorFormat? {
        guard dimensionRange.contains(width), dimensionRange.contains(height) else { return nil }
        return custom(width: width, height: height)
    }

    private init(id: String, name: String, width: Double, height: Double) {
        self.id = id
        self.name = name
        self.widthMillimeters = width
        self.heightMillimeters = height
    }

    // MARK: Derived geometry

    /// The sensor diagonal in millimetres.
    public var diagonalMillimeters: Double {
        (widthMillimeters * widthMillimeters + heightMillimeters * heightMillimeters).squareRoot()
    }

    /// The crop factor: the diagonal of a 36 × 24 mm frame divided by this sensor's diagonal.
    ///
    /// A 50 mm lens on a sensor with crop factor 1.5 frames like a 75 mm lens on full frame.
    public var cropFactor: Double {
        Self.fullFrameDiagonalMillimeters / diagonalMillimeters
    }

    private static let fullFrameDiagonalMillimeters = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()

    /// Estimates the pixel pitch, the centre-to-centre spacing of photosites, from the resolution.
    ///
    /// Pixels are assumed square and to cover the whole sensor, so the pitch is
    /// `sqrt(width × height / pixelCount)`. Nominal sensor sizes are rounded, so this is an estimate;
    /// prefer the manufacturer's published pitch when it is known.
    ///
    /// - Parameter megapixels: The image resolution in millions of pixels.
    /// - Returns: The pitch in micrometres, or nil if `megapixels` is not a positive finite number or
    ///   implies a pitch outside `pixelPitchRange`.
    public func pixelPitchMicrometers(megapixels: Double) -> Double? {
        guard megapixels.isFinite, megapixels > 0 else { return nil }
        let pixelCount = megapixels * 1_000_000
        let pitch = 1000 * (widthMillimeters * heightMillimeters / pixelCount).squareRoot()
        return Self.pixelPitchRange.contains(pitch) ? pitch : nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, widthMillimeters, heightMillimeters
    }

    /// Decodes a sensor format, throwing `DecodingError.dataCorrupted` if the identifier or name
    /// is empty or oversized, or a dimension is outside `dimensionRange`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let width = try container.decode(Double.self, forKey: .widthMillimeters)
        let height = try container.decode(Double.self, forKey: .heightMillimeters)
        guard Self.isValidLabel(id), Self.isValidLabel(name),
              Self.dimensionRange.contains(width), Self.dimensionRange.contains(height) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "The sensor format has an invalid identifier, name or size."
                )
            )
        }
        self.init(id: id, name: name, width: width, height: height)
    }

    /// A label must be present and short enough to be display text rather than payload.
    private static func isValidLabel(_ label: String) -> Bool {
        !label.isEmpty && label.utf8.count <= 128
    }
}

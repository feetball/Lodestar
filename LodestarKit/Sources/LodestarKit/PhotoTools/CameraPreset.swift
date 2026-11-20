/// A ready-made camera and lens: a starter for a plain camera and the smart telescopes, whose optics are fixed.
///
/// A smart telescope's sensor size is its pixel count times its pixel pitch, so it is the whole sensor as the
/// telescope reads it out. Every value comes from the vendor's published specifications, cited at each preset; a
/// value the vendor does not publish (a pixel pitch, say) comes from the sensor maker's datasheet for the sensor
/// the vendor names, and a preset whose numbers could not be found is left out. `setup` is the preset as a
/// `LensSetup`. The presets are the static values; there is no public initialiser.
public struct CameraPreset: Identifiable, Hashable, Sendable {

    /// A stable identifier, for example `seestarS50`.
    public let id: String

    /// The name for a picker, for example "Seestar S50".
    public let name: String

    /// The sensor.
    public let sensor: SensorFormat

    /// The lens focal length in millimetres.
    public let focalLengthMillimeters: Double

    /// The aperture as an f-number.
    public let aperture: Double

    /// The pixel pitch in micrometres, or nil if the preset has none.
    public let pixelPitchMicrometers: Double?

    /// The lens projection.
    public let projection: LensProjection

    /// The preset as a camera and lens combination.
    public var setup: LensSetup {
        LensSetup(
            sensor: sensor,
            focalLengthMillimeters: focalLengthMillimeters,
            aperture: aperture,
            pixelPitchMicrometers: pixelPitchMicrometers,
            projection: projection
        )
    }

    private init(
        id: String,
        name: String,
        sensor: SensorFormat,
        focalLengthMillimeters: Double,
        aperture: Double,
        pixelPitchMicrometers: Double?,
        projection: LensProjection
    ) {
        self.id = id
        self.name = name
        self.sensor = sensor
        self.focalLengthMillimeters = focalLengthMillimeters
        self.aperture = aperture
        self.pixelPitchMicrometers = pixelPitchMicrometers
        self.projection = projection
    }

    /// A smart telescope: the sensor is `pixelsWide` × `pixelsHigh` pixels of `pixelPitchMicrometers`.
    private static func smartTelescope(
        id: String,
        name: String,
        pixelsWide: Int,
        pixelsHigh: Int,
        pixelPitchMicrometers: Double,
        focalLengthMillimeters: Double,
        aperture: Double
    ) -> CameraPreset {
        CameraPreset(
            id: id,
            name: name,
            sensor: SensorFormat.custom(
                width: Double(pixelsWide) * pixelPitchMicrometers / 1000,
                height: Double(pixelsHigh) * pixelPitchMicrometers / 1000
            ),
            focalLengthMillimeters: focalLengthMillimeters,
            aperture: aperture,
            pixelPitchMicrometers: pixelPitchMicrometers,
            projection: .rectilinear
        )
    }

    // MARK: Presets

    /// A plain full-frame camera with a 24 mm f/2.8 lens: a starting point to adjust.
    public static let fullFrame24 = CameraPreset(
        id: "fullFrame24", name: "Full-frame 24 mm f/2.8", sensor: .fullFrame,
        focalLengthMillimeters: 24, aperture: 2.8, pixelPitchMicrometers: nil, projection: .rectilinear
    )

    /// ZWO Seestar S50: Sony IMX462, 1920 × 1080, 250 mm, f/5. The vendor gives a 0.73° × 1.29° field of view.
    /// Specification: https://www.seestar.com/products/seestar-s50. The 2.9 µm pixel pitch is the IMX462's, from
    /// Sony's datasheet: https://www.sony-semicon.com/files/62/flyer_security/IMX462LQR_Flyer.pdf.
    public static let seestarS50 = smartTelescope(
        id: "seestarS50", name: "Seestar S50", pixelsWide: 1920, pixelsHigh: 1080, pixelPitchMicrometers: 2.9,
        focalLengthMillimeters: 250, aperture: 5
    )

    /// ZWO Seestar S30, telephoto camera: Sony IMX662, 1920 × 1080, 150 mm, f/5. The vendor gives a 2.46° field
    /// of view. Specification: https://www.seestar.com/products/seestar-s30-all-in-one-smart-telescope. The 2.9 µm
    /// pixel pitch is the IMX662's, from ZWO's specification of a camera with that sensor:
    /// https://www.zwoastro.com/product/asi662mc/.
    public static let seestarS30 = smartTelescope(
        id: "seestarS30", name: "Seestar S30", pixelsWide: 1920, pixelsHigh: 1080, pixelPitchMicrometers: 2.9,
        focalLengthMillimeters: 150, aperture: 5
    )

    /// ZWO Seestar S50 Pro, telephoto camera: 3840 × 2160 with a published 2.9 µm pixel pitch, 260 mm, f/5.2. The
    /// vendor gives a 2.8° field of view. Specification: https://www.seestar.com/products/seestar-s50-pro-smart-telescope.
    public static let seestarS50Pro = smartTelescope(
        id: "seestarS50Pro", name: "Seestar S50 Pro", pixelsWide: 3840, pixelsHigh: 2160,
        pixelPitchMicrometers: 2.9, focalLengthMillimeters: 260, aperture: 5.2
    )

    /// ZWO Seestar S30 Pro, telephoto camera: Sony IMX585, 3840 × 2160, 160 mm, f/5.3. The vendor gives a 4.6° field
    /// of view. Specification: https://www.seestar.com/products/seestar-s30-pro. The 2.9 µm pixel pitch is the
    /// IMX585's, from ZWO's specification of a camera with that sensor: https://www.zwoastro.com/product/asi585mc/.
    public static let seestarS30Pro = smartTelescope(
        id: "seestarS30Pro", name: "Seestar S30 Pro", pixelsWide: 3840, pixelsHigh: 2160,
        pixelPitchMicrometers: 2.9, focalLengthMillimeters: 160, aperture: 5.3
    )

    /// DwarfLab Dwarf 3, telephoto camera: Sony IMX678, 3840 × 2160, 2 µm pixels, 150 mm with a 35 mm aperture
    /// (f/4.29). The vendor gives a 3.38° diagonal field of view. Specification:
    /// https://dwarflab.com/products/dwarf-3-smart-telescope.
    public static let dwarf3Tele = smartTelescope(
        id: "dwarf3Tele", name: "Dwarf 3 (tele)", pixelsWide: 3840, pixelsHigh: 2160, pixelPitchMicrometers: 2,
        focalLengthMillimeters: 150, aperture: 150.0 / 35.0
    )

    /// DwarfLab Dwarf 3, wide-angle camera: Sony IMX307, 1920 × 1080, 6.7 mm with a 3.4 mm aperture (f/1.97). The
    /// vendor gives a 50.6° diagonal field of view. Specification: https://dwarflab.com/products/dwarf-3-smart-telescope.
    /// The vendor does not publish this camera's pixel pitch; the 2.9 µm is the IMX307's, from Sony's datasheet:
    /// https://www.sony-semicon.com/files/62/flyer_security/IMX307LQD_LQR_Flyer.pdf.
    public static let dwarf3Wide = smartTelescope(
        id: "dwarf3Wide", name: "Dwarf 3 (wide)", pixelsWide: 1920, pixelsHigh: 1080, pixelPitchMicrometers: 2.9,
        focalLengthMillimeters: 6.7, aperture: 6.7 / 3.4
    )

    /// DwarfLab Dwarf II, telephoto camera: Sony IMX415, 3840 × 2160, 1.45 µm pixels, 100 mm with a 24 mm aperture
    /// (f/4.17). The vendor gives a 3.72° diagonal field of view. Specification:
    /// https://dwarflab.com/products/dwarf-2-smart-telescope. (The vendor does not name the wide camera's sensor, so
    /// it has no preset.)
    public static let dwarf2Tele = smartTelescope(
        id: "dwarf2Tele", name: "Dwarf II (tele)", pixelsWide: 3840, pixelsHigh: 2160,
        pixelPitchMicrometers: 1.45, focalLengthMillimeters: 100, aperture: 100.0 / 24.0
    )

    /// Vaonis Vespera II: Sony IMX585, 3840 × 2160, 2.9 µm pixels, 250 mm, f/5. The vendor gives a 2.5° × 1.4°
    /// field of view. Specification: https://vaonis.com/products/vespera-2.
    public static let vesperaII = smartTelescope(
        id: "vesperaII", name: "Vespera II", pixelsWide: 3840, pixelsHigh: 2160, pixelPitchMicrometers: 2.9,
        focalLengthMillimeters: 250, aperture: 5
    )

    /// The smart telescopes, in the order a picker should list them.
    public static let smartTelescopes: [CameraPreset] = [
        seestarS50, seestarS30, seestarS50Pro, seestarS30Pro, dwarf3Tele, dwarf3Wide, dwarf2Tele, vesperaII,
    ]

    /// All presets, in the order a picker should list them: the starter, then the smart telescopes.
    public static let all: [CameraPreset] = [fullFrame24] + smartTelescopes
}

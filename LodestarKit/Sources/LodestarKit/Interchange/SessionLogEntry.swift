import Foundation

/// One line of the session log: what was shot (or tried) on a night.
///
/// Values are cleaned when the entry is created, so that an entry read from a file or typed in always is usable and
/// bounded: text is trimmed and cut (control characters removed), numbers that are not finite or out of range become
/// nil or are clamped, and coordinates only count as a pair.
///
/// Dates are instants; the night an entry belongs to follows from its site's offset from UTC (see
/// `SessionLogCodec.night(of:utcOffsetMinutes:)`).
public struct SessionLogEntry: Hashable, Sendable, Identifiable {
    /// The most characters (Unicode scalars) of the notes.
    public static let maximumNotesLength = 2_000
    /// The most characters of a target or site name.
    public static let maximumNameLength = 120
    /// The most characters of the camera and filter texts.
    public static let maximumLabelLength = 80
    /// The longest exposure of one frame, in seconds.
    public static let maximumExposureSeconds = 86_400.0
    /// The highest ISO value.
    public static let maximumISO = 409_600
    /// The most frames of an entry.
    public static let maximumFrameCount = 100_000
    /// The name of an entry whose target name is empty.
    public static let defaultTargetName = "Unnamed target"

    /// A unique identifier (a UUID string).
    public let id: String
    /// When the shooting started.
    public let date: Date
    /// The identifier of the catalog object (`CelestialObject.id`), which stays valid between launches.
    public let targetID: String
    /// The target's name as it was when the entry was made.
    public let targetName: String
    /// The target's J2000 right ascension in degrees, [0, 360), for fixed targets.
    public let rightAscension: Double?
    /// The target's J2000 declination in degrees, [-90, 90], for fixed targets.
    public let declination: Double?
    /// The observing site's name.
    public let siteName: String
    /// The site's latitude in degrees, if known (set together with `siteLongitude`).
    public let siteLatitude: Double?
    /// The site's longitude in degrees east, if known.
    public let siteLongitude: Double?
    /// The site's standard time offset from UTC in minutes, not counting daylight saving time, if known.
    public let siteUTCOffsetMinutes: Int?
    /// A summary of the camera ("Full Frame 36 × 24 mm").
    public let camera: String
    /// The focal length in millimetres, if known.
    public let focalLength: Double?
    /// The lens aperture as an f-number, if known.
    public let lensAperture: Double?
    /// The sensor's width in pixels, if known (set together with `sensorPixelsY`).
    public let sensorPixelsX: Int?
    /// The sensor's height in pixels, if known.
    public let sensorPixelsY: Int?
    /// The exposure of one frame in seconds, 0 when not recorded.
    public let exposureSeconds: Double
    /// The ISO value, 0 when not recorded.
    public let iso: Int
    /// The number of frames, 0 when not recorded.
    public let frameCount: Int
    /// The filter, empty for none.
    public let filter: String
    /// Free text, at most `maximumNotesLength` characters.
    public let notes: String
    /// Whether the target was imaged (as opposed to a plan or an attempt).
    public let isImaged: Bool

    /// Creates an entry, cleaning every value as described on the type.
    ///
    /// An `id` that is empty after cleaning is replaced by a new UUID.
    public init(
        id: String = UUID().uuidString,
        date: Date,
        targetID: String,
        targetName: String,
        rightAscension: Double? = nil,
        declination: Double? = nil,
        siteName: String = "",
        siteLatitude: Double? = nil,
        siteLongitude: Double? = nil,
        siteUTCOffsetMinutes: Int? = nil,
        camera: String = "",
        focalLength: Double? = nil,
        lensAperture: Double? = nil,
        sensorPixelsX: Int? = nil,
        sensorPixelsY: Int? = nil,
        exposureSeconds: Double = 0,
        iso: Int = 0,
        frameCount: Int = 0,
        filter: String = "",
        notes: String = "",
        isImaged: Bool = false
    ) {
        let cleanedID = InterchangeText.singleLine(id, limit: 64)
        self.id = cleanedID.isEmpty ? UUID().uuidString : cleanedID
        self.date = date
        self.targetID = InterchangeText.singleLine(targetID, limit: Self.maximumNameLength)
        let cleanedName = InterchangeText.singleLine(targetName, limit: Self.maximumNameLength)
        self.targetName = cleanedName.isEmpty ? Self.defaultTargetName : cleanedName
        if let rightAscension, let declination, rightAscension.isFinite, declination.isFinite {
            self.rightAscension = AstroMath.normalizeDegrees(rightAscension)
            self.declination = AstroMath.clamp(declination, -90, 90)
        } else {
            self.rightAscension = nil
            self.declination = nil
        }
        self.siteName = InterchangeText.singleLine(siteName, limit: Self.maximumNameLength)
        if let siteLatitude, let siteLongitude, siteLatitude.isFinite, siteLongitude.isFinite,
           abs(siteLatitude) <= 90, abs(siteLongitude) <= 180 {
            self.siteLatitude = siteLatitude
            self.siteLongitude = siteLongitude
        } else {
            self.siteLatitude = nil
            self.siteLongitude = nil
        }
        if let siteUTCOffsetMinutes, (-720...840).contains(siteUTCOffsetMinutes) {
            self.siteUTCOffsetMinutes = siteUTCOffsetMinutes
        } else {
            self.siteUTCOffsetMinutes = nil
        }
        self.camera = InterchangeText.singleLine(camera, limit: Self.maximumLabelLength)
        if let focalLength, focalLength.isFinite, focalLength >= 1, focalLength <= 100_000 {
            self.focalLength = focalLength
        } else {
            self.focalLength = nil
        }
        if let lensAperture, lensAperture.isFinite, lensAperture >= 0.3, lensAperture <= 100 {
            self.lensAperture = lensAperture
        } else {
            self.lensAperture = nil
        }
        if let sensorPixelsX, let sensorPixelsY, (1...100_000).contains(sensorPixelsX), (1...100_000).contains(sensorPixelsY) {
            self.sensorPixelsX = sensorPixelsX
            self.sensorPixelsY = sensorPixelsY
        } else {
            self.sensorPixelsX = nil
            self.sensorPixelsY = nil
        }
        self.exposureSeconds = exposureSeconds.isFinite ? AstroMath.clamp(exposureSeconds, 0, Self.maximumExposureSeconds) : 0
        self.iso = AstroMath.clamp(iso, 0, Self.maximumISO)
        self.frameCount = AstroMath.clamp(frameCount, 0, Self.maximumFrameCount)
        self.filter = InterchangeText.singleLine(filter, limit: Self.maximumLabelLength)
        self.notes = InterchangeText.multiLine(notes, limit: Self.maximumNotesLength)
        self.isImaged = isImaged
    }

    /// The exposure time of all frames together in seconds.
    public var totalExposureSeconds: Double { exposureSeconds * Double(frameCount) }

    /// Whether the entry has the target's coordinates.
    public var hasCoordinates: Bool { rightAscension != nil && declination != nil }

    /// The night the entry belongs to, see `SessionLogCodec.night(of:utcOffsetMinutes:)`; the site's offset counts, UTC
    /// when it is not known.
    public var night: Int64 {
        SessionLogCodec.night(of: date, utcOffsetMinutes: siteUTCOffsetMinutes ?? 0)
    }
}

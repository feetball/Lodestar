/// One of the 16 points of the compass rose.
///
/// Raw values count clockwise from north in steps of 22.5°, so `CompassPoint.allCases` is already
/// in compass order.
public enum CompassPoint: Int, CaseIterable, Codable, Hashable, Sendable {
    /// North, 0°.
    case north = 0
    /// North-northeast, 22.5°.
    case northNortheast
    /// Northeast, 45°.
    case northeast
    /// East-northeast, 67.5°.
    case eastNortheast
    /// East, 90°.
    case east
    /// East-southeast, 112.5°.
    case eastSoutheast
    /// Southeast, 135°.
    case southeast
    /// South-southeast, 157.5°.
    case southSoutheast
    /// South, 180°.
    case south
    /// South-southwest, 202.5°.
    case southSouthwest
    /// Southwest, 225°.
    case southwest
    /// West-southwest, 247.5°.
    case westSouthwest
    /// West, 270°.
    case west
    /// West-northwest, 292.5°.
    case westNorthwest
    /// Northwest, 315°.
    case northwest
    /// North-northwest, 337.5°.
    case northNorthwest

    /// The angular width of one compass sector, in degrees.
    public static let sectorWidth = 22.5

    /// Creates the compass point whose sector contains an azimuth.
    ///
    /// Azimuth is measured in degrees clockwise from north and is wrapped into [0°, 360°), so
    /// -90° is west and 450° is east. Each sector spans ±11.25° around its centre and includes its
    /// lower boundary: 11.25° is north-northeast and 348.75° is north.
    ///
    /// A non-finite azimuth yields `.north`; callers that must distinguish missing data should
    /// check `isFinite` first.
    public init(azimuth: Double) {
        guard azimuth.isFinite else {
            self = .north
            return
        }
        var wrapped = azimuth.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        // Sector k is centred on k × 22.5°, so the sector is azimuth ÷ 22.5 rounded to the nearest
        // integer. Halves round up, which gives every sector its lower boundary. Dividing first
        // (rather than adding 11.25° and flooring) keeps the decision exact for azimuths a single
        // floating-point step either side of a boundary.
        let sector = Int((wrapped / Self.sectorWidth).rounded()) % Self.allCases.count
        self = Self.allCases[sector]
    }

    /// The azimuth of the middle of this sector, in degrees.
    public var centerAzimuth: Double {
        Double(rawValue) * Self.sectorWidth
    }

    /// The conventional abbreviation, for example "NNE".
    public var abbreviation: String {
        switch self {
        case .north: return "N"
        case .northNortheast: return "NNE"
        case .northeast: return "NE"
        case .eastNortheast: return "ENE"
        case .east: return "E"
        case .eastSoutheast: return "ESE"
        case .southeast: return "SE"
        case .southSoutheast: return "SSE"
        case .south: return "S"
        case .southSouthwest: return "SSW"
        case .southwest: return "SW"
        case .westSouthwest: return "WSW"
        case .west: return "W"
        case .westNorthwest: return "WNW"
        case .northwest: return "NW"
        case .northNorthwest: return "NNW"
        }
    }

    /// The full English name, for example "North-northeast".
    public var fullName: String {
        switch self {
        case .north: return "North"
        case .northNortheast: return "North-northeast"
        case .northeast: return "Northeast"
        case .eastNortheast: return "East-northeast"
        case .east: return "East"
        case .eastSoutheast: return "East-southeast"
        case .southeast: return "Southeast"
        case .southSoutheast: return "South-southeast"
        case .south: return "South"
        case .southSouthwest: return "South-southwest"
        case .southwest: return "Southwest"
        case .westSouthwest: return "West-southwest"
        case .west: return "West"
        case .westNorthwest: return "West-northwest"
        case .northwest: return "Northwest"
        case .northNorthwest: return "North-northwest"
        }
    }
}

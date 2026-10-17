import Foundation

/// Where an object is, and how its position is found.
public enum ObjectPosition: Hashable, Sendable {
    /// A fixed place on the celestial sphere: the J2000 catalog position and the proper motion, if known.
    case fixed(EquatorialCoordinate, ProperMotion?)
    /// A solar-system body; its position comes from the ephemeris.
    case solarSystem(SolarSystemBody)
    /// The north or south celestial pole of date.
    case celestialPole(north: Bool)
}

/// A star, deep-sky object, solar-system body, special direction or user-made target.
///
/// Objects are immutable values. Two objects are equal when all their properties are equal, but
/// they hash by `id` alone, which is stable between app launches and catalog versions.
public struct CelestialObject: Identifiable, Hashable, Sendable {
    /// The longest name a custom target keeps, in characters.
    public static let maximumCustomNameLength = 60
    /// The name given to a custom target whose name is empty.
    public static let defaultCustomName = "Custom Target"

    /// A stable identifier: `"sun"`, `"moon"`, `"planet.mars"`, `"star.hip32349"` (or `"star.hr<n>"`,
    /// `"star.hyg<n>"` for stars without a Hipparcos number), `"dso.M31"`, `"dso.NGC7000"`,
    /// `"special.galacticCenter"`, `"special.ncp"`, `"special.scp"` or `"custom.<uuid>"`.
    public let id: String
    /// The name shown in lists.
    ///
    /// Stars use their proper name, else the Bayer designation with the constellation ("γ Cas"),
    /// else the Flamsteed number ("48 Cas"), else a catalog number ("HR 123"). Deep-sky objects use
    /// their first common name, else "M 31", "NGC 7000" or "IC 434".
    public let name: String
    /// Catalog designations, in display order: for example "M 31", "NGC 224" or "α CMa",
    /// "Alpha Canis Majoris", "9 CMa", "HR 2491", "HD 48915", "HIP 32349". May contain `name`.
    public let designations: [String]
    /// Common names other than `name`.
    public let alternateNames: [String]
    /// The kind of object.
    public let category: ObjectCategory
    /// The IAU abbreviation of the constellation the object lies in ("CMa"), if known.
    public let constellation: String?
    /// The full name of the constellation ("Canis Major"), if known.
    public let constellationName: String?
    /// The visual magnitude, if known.
    ///
    /// For the few deep-sky objects that only have a blue magnitude in the source data, that value.
    /// `nil` for the Sun, the Moon and the planets, whose brightness changes; use
    /// `SkyFrame.currentMagnitude(of:)` for those.
    public let magnitude: Double?
    /// The size of an extended object, if known.
    public let angularSize: AngularSize?
    /// Where the object is.
    public let position: ObjectPosition
    /// The B−V color index of a star, if known.
    public let colorIndex: Double?
    /// The spectral type of a star, if known.
    public let spectralType: String?
    /// The distance in light-years, if known.
    public let distanceLightYears: Double?
    /// Whether browse lists show the object.
    ///
    /// All solar-system and special objects and all deep-sky objects are listed, and so are stars
    /// with a proper name and other stars of magnitude 3.5 or brighter. The remaining stars are
    /// only found by search and drawn on the sky.
    public let isListed: Bool
    /// A short note for the detail view, if there is something worth saying.
    public let notes: String?

    init(id: String, name: String, designations: [String] = [], alternateNames: [String] = [],
         category: ObjectCategory, constellation: String? = nil, constellationName: String? = nil,
         magnitude: Double? = nil, angularSize: AngularSize? = nil, position: ObjectPosition,
         colorIndex: Double? = nil, spectralType: String? = nil, distanceLightYears: Double? = nil,
         isListed: Bool, notes: String? = nil) {
        self.id = id
        self.name = name
        self.designations = designations
        self.alternateNames = alternateNames
        self.category = category
        self.constellation = constellation
        self.constellationName = constellationName
        self.magnitude = magnitude
        self.angularSize = angularSize
        self.position = position
        self.colorIndex = colorIndex
        self.spectralType = spectralType
        self.distanceLightYears = distanceLightYears
        self.isListed = isListed
        self.notes = notes
    }

    /// Hashes the identifier only, so objects with the same identifier hash alike.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Derived values

    /// The browse group of the object's category.
    public var group: ObjectGroup { category.group }

    /// The J2000 position of a fixed object; `nil` for solar-system bodies and the poles.
    public var j2000: EquatorialCoordinate? {
        if case .fixed(let coordinate, _) = position { return coordinate }
        return nil
    }

    /// `true` for the Sun, the Moon and the planets.
    public var isSolarSystem: Bool {
        if case .solarSystem = position { return true }
        return false
    }

    /// One line describing the object, such as "Galaxy · Andromeda · mag 3.4".
    public var subtitle: String {
        var parts = [category.displayName]
        if let constellationName { parts.append(constellationName) }
        if let magnitude { parts.append("mag \(CatalogFormat.oneDecimal(magnitude))") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The magnitude used to order objects by brightness: the catalog magnitude, or for
    /// solar-system bodies a typical peak magnitude, or +∞ when nothing is known.
    var rankingMagnitude: Double {
        if let magnitude { return magnitude }
        if case .solarSystem(let body) = position { return Self.typicalPeakMagnitude(of: body) }
        return .infinity
    }

    private static func typicalPeakMagnitude(of body: SolarSystemBody) -> Double {
        switch body {
        case .sun: -26.7
        case .moon: -12.7
        case .venus: -4.4
        case .jupiter: -2.7
        case .mars: -2.0
        case .mercury: -1.9
        case .saturn: -0.2
        case .uranus: 5.7
        case .neptune: 7.8
        }
    }

    // MARK: Custom targets

    /// Creates a user-made target at a J2000 position, with a new identifier.
    ///
    /// The name is trimmed, runs of whitespace become single spaces, control characters are dropped
    /// and the result is cut to `maximumCustomNameLength` characters; an empty name becomes
    /// `defaultCustomName`. Components of `j2000` that are not finite are replaced by 0.
    public static func custom(name: String, j2000: EquatorialCoordinate) -> CelestialObject {
        custom(id: UUID(), name: name, j2000: j2000)
    }

    /// Creates a user-made target with a given identifier, to restore a target saved earlier.
    ///
    /// The object's `id` is `"custom."` followed by the UUID string. See `custom(name:j2000:)` for
    /// how the name and the position are cleaned up.
    public static func custom(id: UUID, name: String, j2000: EquatorialCoordinate) -> CelestialObject {
        let position = EquatorialCoordinate(
            rightAscension: j2000.rightAscension.isFinite ? j2000.rightAscension : 0,
            declination: j2000.declination.isFinite ? j2000.declination : 0)
        let cleanedName = cleanedCustomName(name)
        return CelestialObject(id: "custom.\(id.uuidString)",
                               name: cleanedName.isEmpty ? defaultCustomName : cleanedName,
                               category: .custom, position: .fixed(position, nil), isListed: true)
    }

    private static func cleanedCustomName(_ raw: String) -> String {
        // Bounds the work for absurdly long input before looking at grapheme clusters.
        let scalarLimit = 8 * maximumCustomNameLength
        var result = String.UnicodeScalarView()
        var keptScalars = 0
        var pendingSpace = false
        for scalar in raw.unicodeScalars {
            if keptScalars >= scalarLimit { break }
            if scalar.properties.isWhitespace {
                pendingSpace = keptScalars > 0
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned:
                continue
            default:
                break
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
                keptScalars += 1
            }
            result.append(scalar)
            keptScalars += 1
        }
        let capped = String(String(result).prefix(maximumCustomNameLength))
        return capped.trimmingCharacters(in: .whitespaces)
    }
}

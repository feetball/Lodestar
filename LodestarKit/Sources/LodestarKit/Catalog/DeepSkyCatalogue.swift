import Foundation

/// How conspicuous an object is among objects of its kind, from `showpiece` to `obscure`.
///
/// The value is part of the catalog data: for deep-sky objects it follows the rules in `Tools/README.md`
/// (catalogue membership, name, brightness and size; dark nebulae have no magnitude and are rated by name
/// and size), for stars it follows the magnitude, for comets and asteroids it follows the peak magnitude
/// estimate (`init(smallBodyPeakMagnitude:)`), and the Sun, the Moon, the planets, the Milky Way core, the
/// celestial poles and custom targets are always showpieces. A smaller value is more conspicuous, so
/// the natural order is the order of importance: `showpiece < prominent < notable < obscure`.
///
/// Use it to keep a crowded sky readable: draw (or label) only the objects up to a limit that grows as the
/// field of view narrows. The deep-sky objects that are `notable` or better are the ones
/// `CelestialObject.isListed` lists.
public enum Prominence: Int, Comparable, CaseIterable, Hashable, Sendable {
    /// Messier and Caldwell objects, the best-known named targets, and anything brighter than magnitude 4.
    case showpiece = 1
    /// Bright (brighter than magnitude 8) or well-known objects, and the larger nebulae.
    case prominent = 2
    /// Everything else that is bright, large or named enough to be worth a place in a list.
    case notable = 3
    /// Faint, small or obscure objects: found by search and by catalogue, drawn only at narrow fields.
    case obscure = 4

    /// The least prominent value a listed deep-sky object has.
    public static let lastListed = Prominence.notable
    /// Stars brighter than this (visual magnitude, inclusive) are showpieces.
    public static let showpieceStarMagnitude = 1.5
    /// Stars brighter than this (inclusive) are prominent.
    public static let prominentStarMagnitude = 3.5
    /// Stars brighter than this (inclusive) are notable; fainter ones are obscure.
    public static let notableStarMagnitude = 5.0
    /// Comets and asteroids with a peak magnitude estimate up to this value (inclusive) are showpieces: naked-eye class.
    public static let showpieceSmallBodyMagnitude = 6.0
    /// Comets and asteroids with a peak magnitude estimate up to this value (inclusive) are prominent: binocular class.
    public static let prominentSmallBodyMagnitude = 8.0
    /// Comets and asteroids with a peak magnitude estimate up to this value (inclusive) are notable: within reach of a
    /// camera on a tripod, the default limit of `SmallBodySelection`. Fainter ones, and bodies without magnitude
    /// parameters, are obscure.
    public static let notableSmallBodyMagnitude = 10.0

    /// The English name shown to people, for example "Showpiece".
    public var displayName: String {
        switch self {
        case .showpiece: "Showpiece"
        case .prominent: "Prominent"
        case .notable: "Notable"
        case .obscure: "Obscure"
        }
    }

    /// The prominence of a star of visual magnitude `starMagnitude`: 1 up to magnitude 1.5, 2 up to 3.5, 3 up
    /// to 5.0, else 4.
    public init(starMagnitude: Double) {
        if starMagnitude <= Self.showpieceStarMagnitude {
            self = .showpiece
        } else if starMagnitude <= Self.prominentStarMagnitude {
            self = .prominent
        } else if starMagnitude <= Self.notableStarMagnitude {
            self = .notable
        } else {
            self = .obscure
        }
    }

    /// The prominence of a comet or an asteroid from its peak magnitude estimate
    /// (`SmallBodyBrightness.peakMagnitudeEstimate(of:)`): 1 up to magnitude 6, 2 up to 8, 3 up to 10, else 4; a body
    /// without an estimate is 4.
    public init(smallBodyPeakMagnitude: Double?) {
        guard let magnitude = smallBodyPeakMagnitude else {
            self = .obscure
            return
        }
        if magnitude <= Self.showpieceSmallBodyMagnitude {
            self = .showpiece
        } else if magnitude <= Self.prominentSmallBodyMagnitude {
            self = .prominent
        } else if magnitude <= Self.notableSmallBodyMagnitude {
            self = .notable
        } else {
            self = .obscure
        }
    }

    public static func < (lhs: Prominence, rhs: Prominence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A deep-sky catalogue whose numbers the catalog knows, for filters and numbered lists.
public enum DeepSkyCatalogue: String, Codable, CaseIterable, Hashable, Sendable {
    /// Messier's 110 objects.
    case messier
    /// Patrick Moore's 109 Caldwell objects.
    case caldwell
    /// The New General Catalogue.
    case ngc
    /// The Index Catalogues.
    case ic
    /// Sharpless' second catalogue of HII regions (313 regions, `Sh2-1` to `Sh2-313`).
    case sharpless
    /// Barnard's catalogue of dark objects (349 of them, numbers up to 370, some with a letter).
    case barnard
    /// Lynds' catalogue of dark nebulae (the darkest and the largest clouds).
    case lynds
    /// Collinder's open clusters (the large ones).
    case collinder
    /// Melotte's open clusters.
    case melotte
    /// Trumpler's open clusters.
    case trumpler
    /// Stock's open clusters.
    case stock

    /// The English name of the catalogue ("Sharpless").
    public var displayName: String {
        switch self {
        case .messier: "Messier"
        case .caldwell: "Caldwell"
        case .ngc: "NGC"
        case .ic: "IC"
        case .sharpless: "Sharpless"
        case .barnard: "Barnard"
        case .lynds: "Lynds"
        case .collinder: "Collinder"
        case .melotte: "Melotte"
        case .trumpler: "Trumpler"
        case .stock: "Stock"
        }
    }

    /// The usual abbreviation used in labels ("Sh2", "LDN", "Cr").
    public var abbreviation: String {
        switch self {
        case .messier: "M"
        case .caldwell: "C"
        case .ngc: "NGC"
        case .ic: "IC"
        case .sharpless: "Sh2"
        case .barnard: "B"
        case .lynds: "LDN"
        case .collinder: "Cr"
        case .melotte: "Mel"
        case .trumpler: "Tr"
        case .stock: "St"
        }
    }
}

/// An object's number in a `DeepSkyCatalogue`.
public struct CatalogNumber: Hashable, Sendable {
    /// The catalogue.
    public let catalogue: DeepSkyCatalogue
    /// The number, 1 or more.
    public let number: Int
    /// The letter some numbers carry ("a" in Barnard 67a, "A" in NGC 2818A), or empty.
    public let suffix: String

    init(catalogue: DeepSkyCatalogue, number: Int, suffix: String = "") {
        self.catalogue = catalogue
        self.number = number
        self.suffix = suffix
    }

    /// The short label: "M 31", "NGC 7000", "C 14", "Sh2-155", "LDN 1622", "B 33a".
    public var label: String {
        catalogue == .sharpless ? "Sh2-\(number)" : "\(catalogue.abbreviation) \(number)\(suffix)"
    }
}

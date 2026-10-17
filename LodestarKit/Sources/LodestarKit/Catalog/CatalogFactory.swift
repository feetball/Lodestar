import Foundation

/// A text an object can be found by, and which of the object's displayed texts it stands for.
struct KeyText {
    let text: String
    /// 0 is the object's name, then come its designations, then its alternate names.
    let entry: Int
}

/// A finished object together with the texts it can be found by.
struct ObjectDraft {
    let object: CelestialObject
    let keys: [KeyText]

    /// A draft whose keys are the object's name, designations and alternate names as displayed.
    init(plain object: CelestialObject) {
        var keys = [KeyText(text: object.name, entry: 0)]
        for (index, designation) in object.designations.enumerated() {
            keys.append(KeyText(text: designation, entry: index + 1))
        }
        for (index, name) in object.alternateNames.enumerated() {
            keys.append(KeyText(text: name, entry: object.designations.count + index + 1))
        }
        self.init(object: object, keys: keys)
    }

    init(object: CelestialObject, keys: [KeyText]) {
        self.object = object
        self.keys = keys
    }
}

/// The constellations by IAU abbreviation (case-insensitive).
struct ConstellationDirectory: Sendable {
    let constellations: [Constellation]
    private let indexByAbbreviation: [String: Int]

    init(_ constellations: [Constellation]) {
        self.constellations = constellations
        var index: [String: Int] = [:]
        for (offset, constellation) in constellations.enumerated() {
            index[constellation.abbreviation.lowercased()] = offset
        }
        indexByAbbreviation = index
    }

    func constellation(abbreviation: String) -> Constellation? {
        indexByAbbreviation[abbreviation.lowercased()].map { constellations[$0] }
    }
}

/// How the catalog identifiers of the deep-sky data are written and abbreviated for people.
enum CatalogDesignation {
    struct Spelling {
        /// The form shown ("Caldwell 14").
        let display: String
        /// Other forms people type ("C 14").
        let aliases: [String]
    }

    /// Prefix of an OpenNGC identifier → the form shown and the other spellings of the prefix.
    private static let prefixes: [String: (display: String, aliases: [String])] = [
        "M": ("M", ["Messier"]),
        "NGC": ("NGC", []),
        "IC": ("IC", []),
        "C": ("Caldwell", ["C"]),
        "Mel": ("Melotte", ["Mel"]),
        "B": ("Barnard", ["B"]),
        "H": ("Harvard", ["H"]),
        "Cl": ("Collinder", ["Cl", "Cr"]),
        "ESO": ("ESO", []),
        "HCG": ("HCG", ["Hickson"]),
        "MWSC": ("MWSC", []),
        "PGC": ("PGC", []),
        "UGC": ("UGC", []),
    ]

    /// The spelling of an OpenNGC identifier such as `M31`, `C14`, `ESO56-115` or `IC2431_NED02`.
    static func spelling(ofIdentifier id: String) -> Spelling {
        let prefix = String(id.prefix(while: { $0.isASCII && $0.isLetter }))
        let number = String(id.dropFirst(prefix.count)).replacingOccurrences(of: "_", with: " ")
        guard !prefix.isEmpty, !number.isEmpty else {
            return Spelling(display: id.replacingOccurrences(of: "_", with: " "), aliases: [])
        }
        let known = prefixes[prefix] ?? (prefix, [])
        return Spelling(display: "\(known.display) \(number)", aliases: known.aliases.map { "\($0) \(number)" })
    }
}

/// Turns validated records into catalog objects and the texts they are found by.
enum CatalogFactory {
    static let lightYearsPerParsec = 3.261_563_777_167_433
    /// Stars without a proper name that are brighter than this appear in browse lists.
    static let maximumListedStarMagnitude = 3.5
    /// Popular names of a few stars that the star data does not have, by Hipparcos number.
    static let popularNames: [Int: [String]] = [
        11767: ["North Star", "Pole Star", "Lodestar"],  // Polaris
        32349: ["Dog Star"],  // Sirius
    ]
    /// The Hipparcos number of 3C 273, the one entry of the star data that is a quasar and not a star.
    static let quasarHipparcosNumber = 60936
    private static let quasarNote = "A quasar: the glowing core of a distant galaxy, about 2.4 billion light-years away, "
        + "and not a star. It is among the brightest quasars in the sky but still needs a telescope to be seen."

    /// A Bayer designation split into its Greek letter and superscript digits ("α¹" → "α" and "¹").
    private struct BayerLabel {
        let glyph: String
        let suffix: String
        let letter: GreekAlphabet.Letter?

        init?(_ text: String) {
            var scalars = text.unicodeScalars[...]
            guard let first = scalars.popFirst() else { return nil }
            glyph = String(first)
            var rest = String.UnicodeScalarView()
            rest.append(contentsOf: scalars)
            suffix = String(rest)
            letter = GreekAlphabet.letter(for: first)
        }
    }

    /// Creates a star. `duplicates` are deep-sky records that describe the same star; their
    /// designations and names are added to it, and so are the popular names the star may have. The
    /// quasar 3C 273 that the star data contains is created as an object of category `.other` with an
    /// explanatory note.
    static func star(_ entry: StarEntry, constellations: ConstellationDirectory,
                     absorbing duplicates: [DeepSkyEntry] = []) -> ObjectDraft {
        let constellation = entry.constellation.flatMap { constellations.constellation(abbreviation: $0) }
        let abbreviation = constellation?.abbreviation ?? entry.constellation
        let genitive = constellation?.genitive

        var designations: [String] = []
        // Spelling variants of designations; the entry refers to the designation they stand for.
        var variants: [KeyText] = []

        var bayerName: String?
        if let abbreviation, let label = entry.bayer.flatMap(BayerLabel.init) {
            let short = "\(label.glyph)\(label.suffix) \(abbreviation)"
            designations.append(short)
            bayerName = short
            let shortEntry = designations.count
            var longEntry = shortEntry
            if let letter = label.letter, let genitive {
                designations.append("\(letter.capitalizedName)\(label.suffix) \(genitive)")
                longEntry = designations.count
            }
            // "alpha", "alp" and "α", with and without the superscript digits, followed by the
            // constellation as abbreviation or genitive.
            let letterForms = label.letter.map { [$0.name] + $0.abbreviations } ?? [label.glyph]
            let suffixes = label.suffix.isEmpty ? [""] : [label.suffix, ""]
            for form in letterForms {
                for suffix in suffixes {
                    variants.append(KeyText(text: "\(form)\(suffix) \(abbreviation)", entry: shortEntry))
                    if let genitive {
                        variants.append(KeyText(text: "\(form)\(suffix) \(genitive)", entry: longEntry))
                    }
                }
            }
        }

        var flamsteedName: String?
        if let number = entry.flamsteed, let abbreviation {
            designations.append("\(number) \(abbreviation)")
            flamsteedName = designations.last
            if let genitive {
                variants.append(KeyText(text: "\(number) \(genitive)", entry: designations.count))
            }
        }

        var catalogName: String?
        if let number = entry.harvard {
            designations.append("HR \(number)")
            catalogName = catalogName ?? designations.last
        }
        if let number = entry.henryDraper {
            designations.append("HD \(number)")
            catalogName = catalogName ?? designations.last
        }
        if let number = entry.hipparcos {
            designations.append("HIP \(number)")
            catalogName = catalogName ?? designations.last
        } else if entry.harvard == nil, entry.henryDraper == nil, let row = entry.hygRow {
            designations.append("HYG \(row)")
            catalogName = catalogName ?? designations.last
        }

        for duplicate in duplicates {
            for spelling in spellings(of: duplicate) {
                designations.append(spelling.display)
                for alias in spelling.aliases {
                    variants.append(KeyText(text: alias, entry: designations.count))
                }
            }
        }

        let name = entry.properName ?? bayerName ?? flamsteedName ?? catalogName ?? entry.objectID
        var keys = [KeyText(text: name, entry: 0)]
        for (index, designation) in designations.enumerated() {
            keys.append(KeyText(text: designation, entry: index + 1))
        }
        keys.append(contentsOf: variants)

        // Popular names of the star, and names of the duplicates, that the star does not already answer to.
        var alternateNames: [String] = []
        let otherNames = (entry.hipparcos.flatMap { popularNames[$0] } ?? []) + duplicates.flatMap(\.names)
        if !otherNames.isEmpty {
            var knownKeys = Set(keys.map { SearchText.key(for: $0.text).bytes })
            for alternate in otherNames where knownKeys.insert(SearchText.key(for: alternate).bytes).inserted {
                alternateNames.append(alternate)
                keys.append(KeyText(text: alternate, entry: designations.count + alternateNames.count))
            }
        }

        let isQuasar = entry.hipparcos == quasarHipparcosNumber
        let object = CelestialObject(
            id: entry.objectID, name: name, designations: designations, alternateNames: alternateNames,
            category: isQuasar ? .other : .star, constellation: abbreviation, constellationName: constellation?.name,
            magnitude: entry.magnitude, position: .fixed(entry.position, entry.properMotion),
            colorIndex: entry.colorIndex, spectralType: entry.spectralType,
            distanceLightYears: entry.distanceParsecs.map { $0 * lightYearsPerParsec },
            isListed: entry.properName != nil || entry.magnitude <= maximumListedStarMagnitude,
            notes: isQuasar ? quasarNote : nil)
        return ObjectDraft(object: object, keys: keys)
    }

    static func deepSkyObject(_ entry: DeepSkyEntry, constellations: ConstellationDirectory) -> ObjectDraft {
        let constellation = entry.constellation.flatMap { constellations.constellation(abbreviation: $0) }
        let spellings = spellings(of: entry)
        let designations = spellings.map(\.display)
        let name = entry.names.first ?? designations[0]
        let alternateNames = Array(entry.names.dropFirst())

        var keys = [KeyText(text: name, entry: 0)]
        for (index, spelling) in spellings.enumerated() {
            keys.append(KeyText(text: spelling.display, entry: index + 1))
            for alias in spelling.aliases {
                keys.append(KeyText(text: alias, entry: index + 1))
            }
        }
        for (index, alternate) in alternateNames.enumerated() {
            keys.append(KeyText(text: alternate, entry: designations.count + index + 1))
        }

        var noteSentences: [String] = []
        if let hubbleType = entry.hubbleType {
            noteSentences.append("Hubble type \(hubbleType).")
        }
        if let brightness = entry.surfaceBrightness {
            noteSentences.append("Surface brightness \(CatalogFormat.oneDecimal(brightness)) mag/arcsec\u{00B2}.")
        }

        let object = CelestialObject(
            id: "dso.\(entry.id)", name: name, designations: designations, alternateNames: alternateNames,
            category: ObjectCategory(openNGCType: entry.typeCode),
            constellation: constellation?.abbreviation ?? entry.constellation, constellationName: constellation?.name,
            magnitude: entry.visualMagnitude ?? entry.blueMagnitude,
            angularSize: entry.majorAxis.flatMap {
                AngularSize(majorArcminutes: $0, minorArcminutes: entry.minorAxis, positionAngle: entry.positionAngle)
            },
            position: .fixed(entry.position, nil), isListed: true,
            notes: noteSentences.isEmpty ? nil : noteSentences.joined(separator: " "))
        return ObjectDraft(object: object, keys: keys)
    }

    /// The designations of a deep-sky record: Messier, NGC and IC numbers, then the identifier of
    /// the data file when it is from another catalog.
    static func spellings(of entry: DeepSkyEntry) -> [CatalogDesignation.Spelling] {
        var spellings: [CatalogDesignation.Spelling] = []
        if let number = entry.messier {
            spellings.append(.init(display: "M \(number)", aliases: ["Messier \(number)"]))
        }
        for number in entry.ngc {
            spellings.append(.init(display: "NGC \(number)", aliases: []))
        }
        for number in entry.ic {
            spellings.append(.init(display: "IC \(number)", aliases: []))
        }
        let own = CatalogDesignation.spelling(ofIdentifier: entry.id)
        let ownKey = SearchText.key(for: own.display).bytes
        if !spellings.contains(where: { SearchText.key(for: $0.display).bytes == ownKey }) {
            spellings.append(own)
        }
        return spellings
    }

    /// The identifier under which a deep-sky object with an acronym for a name ("LMC") also answers.
    static func acronymAlias(for alternateName: String) -> String? {
        guard (2...5).contains(alternateName.count),
              alternateName.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              alternateName.contains(where: \.isLetter) else { return nil }
        return "dso.\(alternateName)"
    }
}

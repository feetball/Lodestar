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

    /// The form shown and the other spellings of an identifier prefix, and the catalogue it stands for, if
    /// it is one of `DeepSkyCatalogue`.
    private struct Names {
        let display: String
        let aliases: [String]
        let catalogue: DeepSkyCatalogue?

        init(_ display: String, _ aliases: [String], _ catalogue: DeepSkyCatalogue? = nil) {
            self.display = display
            self.aliases = aliases
            self.catalogue = catalogue
        }
    }

    /// Prefix of a compact designation → the form shown and the other spellings of the prefix.
    private static let prefixes: [String: Names] = [
        "M": Names("M", ["Messier"], .messier),
        "NGC": Names("NGC", [], .ngc),
        "IC": Names("IC", [], .ic),
        "C": Names("Caldwell", ["C"], .caldwell),
        "Mel": Names("Melotte", ["Mel"], .melotte),
        "B": Names("Barnard", ["B"], .barnard),
        "H": Names("Harvard", ["H"]),
        "Cl": Names("Collinder", ["Cl", "Cr"], .collinder),
        "Tr": Names("Trumpler", ["Tr"], .trumpler),
        "St": Names("Stock", ["St"], .stock),
        "LDN": Names("LDN", ["Lynds", "L"], .lynds),
        "ESO": Names("ESO", []),
        "HCG": Names("HCG", ["Hickson"]),
        "MWSC": Names("MWSC", []),
        "PGC": Names("PGC", []),
        "UGC": Names("UGC", []),
    ]

    /// The prefix of the Sharpless 2 designations, which carry the catalogue number: `Sh2-155`.
    private static let sharplessPrefix = "Sh2-"
    /// The longest number a Sharpless 2 designation has (the catalogue ends at 313).
    private static let maximumSharplessDigits = 4
    /// "Sharpless 2-155" is only an alias of numbers with this many digits, see `spelling(ofIdentifier:)`.
    private static let minimumDigitsOfUnambiguousSharplessAlias = 3
    /// The longest prefix and the longest number a compact designation has.
    private static let maximumPrefixLength = 6
    private static let maximumNumberDigits = 6

    /// The spelling of a compact designation, that is an OpenNGC identifier such as `M31`, `C14`, `Sh2-155`,
    /// `LDN1622`, `ESO56-115` or `IC2431_NED02`.
    ///
    /// Sharpless regions are shown as "Sh2-155" and found as "Sh 2-155", "Sharpless 155" and, from Sh2-100
    /// on, "Sharpless 2-155". The last form is left out below 100 because a search key has no punctuation:
    /// "Sharpless 2-45" and "Sharpless 245" are the same key, and "Sharpless 245" must find Sh2-245, not M 17.
    static func spelling(ofIdentifier id: String) -> Spelling {
        if id.hasPrefix(sharplessPrefix), id.count > sharplessPrefix.count {
            let number = String(id.dropFirst(sharplessPrefix.count))
            var aliases = ["Sh 2-\(number)", "Sharpless \(number)"]
            if number.count >= minimumDigitsOfUnambiguousSharplessAlias { aliases.append("Sharpless 2-\(number)") }
            return Spelling(display: "Sh2-\(number)", aliases: aliases)
        }
        let prefix = String(id.prefix(while: { $0.isASCII && $0.isLetter }))
        let number = String(id.dropFirst(prefix.count)).replacingOccurrences(of: "_", with: " ")
        guard !prefix.isEmpty, !number.isEmpty else {
            return Spelling(display: id.replacingOccurrences(of: "_", with: " "), aliases: [])
        }
        let known = prefixes[prefix] ?? Names(prefix, [])
        return Spelling(display: "\(known.display) \(number)", aliases: known.aliases.map { "\($0) \(number)" })
    }

    /// Whether `text` is a compact designation of the kind the `cat` member of a deep-sky record holds: one to
    /// six ASCII letters, the first of them upper case, and a number of up to six digits, optionally followed
    /// by one more letter (`C20`, `Mel22`, `B67a`, `NGC2818A`, `LDN1622`), or a Sharpless 2 designation (`Sh2-117`).
    static func isCompact(_ text: String) -> Bool {
        parse(text) != nil
    }

    /// A compact designation split into its prefix, its number and the letter after the number, if any.
    private struct Parts {
        let prefix: String
        let number: Int
        let suffix: String
    }

    private static func parse(_ text: String) -> Parts? {
        if text.hasPrefix(sharplessPrefix) {
            guard let number = number(String(text.dropFirst(sharplessPrefix.count)), maximumDigits: maximumSharplessDigits) else {
                return nil
            }
            return Parts(prefix: "Sh2", number: number, suffix: "")
        }
        let prefix = String(text.prefix(while: { $0.isASCII && $0.isLetter }))
        guard !prefix.isEmpty, prefix.count <= maximumPrefixLength, prefix.first?.isUppercase == true else { return nil }
        let rest = text.dropFirst(prefix.count)
        let digits = String(rest.prefix(while: { $0.isASCII && $0.isNumber }))
        guard let number = number(digits, maximumDigits: maximumNumberDigits) else { return nil }
        let suffix = String(rest.dropFirst(digits.count))
        if suffix.count > 1 || (!suffix.isEmpty && !(suffix.first.map { $0.isASCII && $0.isLetter } ?? false)) {
            return nil
        }
        return Parts(prefix: prefix, number: number, suffix: suffix)
    }

    private static func number(_ digits: String, maximumDigits: Int) -> Int? {
        guard !digits.isEmpty, digits.count <= maximumDigits, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(digits), value >= 1 else { return nil }
        return value
    }

    /// The catalogue number of a compact designation (`M31`, `NGC7000`, `C14`, `Sh2-155`, `B67a`, `LDN1622`,
    /// `Cl399`, `Mel20`), or `nil` for an identifier of a catalogue that is not a `DeepSkyCatalogue`
    /// (`ESO56-115`, `H20`, `PGC143`) or for something that is no designation.
    static func catalogNumber(of text: String) -> CatalogNumber? {
        guard let parts = parse(text) else { return nil }
        let catalogue = parts.prefix == "Sh2" ? DeepSkyCatalogue.sharpless : prefixes[parts.prefix]?.catalogue
        guard let catalogue else { return nil }
        return CatalogNumber(catalogue: catalogue, number: parts.number, suffix: parts.suffix)
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
            notes: isQuasar ? quasarNote : nil, prominence: Prominence(starMagnitude: entry.magnitude))
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

        let prominence = entry.prominence ?? .notable
        let object = CelestialObject(
            id: "dso.\(entry.id)", name: name, designations: designations, alternateNames: alternateNames,
            category: ObjectCategory(openNGCType: entry.typeCode),
            constellation: constellation?.abbreviation ?? entry.constellation, constellationName: constellation?.name,
            magnitude: entry.visualMagnitude ?? entry.blueMagnitude,
            angularSize: entry.majorAxis.flatMap {
                AngularSize(majorArcminutes: $0, minorArcminutes: entry.minorAxis, positionAngle: entry.positionAngle)
            },
            position: .fixed(entry.position, nil), isListed: prominence <= Prominence.lastListed,
            notes: noteSentences.isEmpty ? nil : noteSentences.joined(separator: " "),
            prominence: prominence, catalogNumbers: catalogNumbers(of: entry))
        return ObjectDraft(object: object, keys: keys)
    }

    /// The designations of a deep-sky record: Messier, NGC and IC numbers, then the identifier of
    /// the data file when it is from another catalog, then the designations of other catalogues the
    /// record lists (`cat`: Caldwell, Sharpless, Melotte...). A designation that reads like an earlier one
    /// is left out.
    static func spellings(of entry: DeepSkyEntry) -> [CatalogDesignation.Spelling] {
        var spellings: [CatalogDesignation.Spelling] = []
        var keys: [[UInt8]] = []
        func add(_ spelling: CatalogDesignation.Spelling) {
            let key = SearchText.key(for: spelling.display).bytes
            if !keys.contains(key) {
                keys.append(key)
                spellings.append(spelling)
            }
        }
        if let number = entry.messier {
            add(.init(display: "M \(number)", aliases: ["Messier \(number)"]))
        }
        for number in entry.ngc {
            add(.init(display: "NGC \(number)", aliases: []))
        }
        for number in entry.ic {
            add(.init(display: "IC \(number)", aliases: []))
        }
        add(CatalogDesignation.spelling(ofIdentifier: entry.id))
        for designation in entry.cat {
            add(CatalogDesignation.spelling(ofIdentifier: designation))
        }
        return spellings
    }

    /// The catalogue numbers of a deep-sky record, in the order of its designations: Messier, NGC, IC, the
    /// identifier of the data file, then `cat`; repeats and identifiers of other catalogues are left out.
    static func catalogNumbers(of entry: DeepSkyEntry) -> [CatalogNumber] {
        var numbers: [CatalogNumber] = []
        func add(_ number: CatalogNumber?) {
            if let number, !numbers.contains(number) { numbers.append(number) }
        }
        if let messier = entry.messier { add(CatalogNumber(catalogue: .messier, number: messier)) }
        for number in entry.ngc { add(CatalogNumber(catalogue: .ngc, number: number)) }
        for number in entry.ic { add(CatalogNumber(catalogue: .ic, number: number)) }
        add(CatalogDesignation.catalogNumber(of: entry.id))
        for designation in entry.cat { add(CatalogDesignation.catalogNumber(of: designation)) }
        return numbers
    }

    /// The object of a comet or an asteroid, with the texts it can be found by: the title (entry 0), the designation
    /// ("C/2023 A3", "12P", "2024 YR4", "(4)" for a numbered asteroid, entry 1) and the common name (entry 2).
    static func smallBody(_ body: SmallBody) -> ObjectDraft {
        let estimate = SmallBodyBrightness.peakMagnitudeEstimate(of: body)
        let prominence = Prominence(smallBodyPeakMagnitude: estimate)
        let isAsteroid = body.kind == .asteroid
        let designation = isAsteroid && body.number != nil ? "(\(body.designation))" : body.designation
        let object = CelestialObject(
            id: body.id, name: body.title, designations: [designation],
            alternateNames: body.name.isEmpty ? [] : [body.name],
            category: isAsteroid ? .asteroid : .comet, position: .smallBody(body),
            isListed: prominence <= Prominence.lastListed, prominence: prominence)
        return ObjectDraft(plain: object)
    }

    /// The identifier under which a deep-sky object with an acronym for a name ("LMC") also answers.
    static func acronymAlias(for alternateName: String) -> String? {
        guard (2...5).contains(alternateName.count),
              alternateName.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              alternateName.contains(where: \.isLetter) else { return nil }
        return "dso.\(alternateName)"
    }
}

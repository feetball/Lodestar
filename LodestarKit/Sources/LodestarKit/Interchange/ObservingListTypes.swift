/// A file format `ObservingListCodec` reads.
public enum ObservingListFormat: String, CaseIterable, Hashable, Sendable {
    /// A CSV table with name or designation columns and optionally right ascension and declination columns.
    case genericCSV = "csv"
    /// A CSV export of a Telescopius target list (columns such as "Catalogue Entry" and "Familiar Name").
    case telescopiusCSV = "telescopius"
    /// A SkySafari observing list (`.skylist`).
    case skySafari = "skysafari"

    /// The name shown to people.
    public var displayName: String {
        switch self {
        case .genericCSV: "CSV"
        case .telescopiusCSV: "Telescopius CSV"
        case .skySafari: "SkySafari observing list"
        }
    }
}

/// One target read from a list.
public struct ImportedTarget: Hashable, Sendable {
    /// The name or common name ("Pleiades"), if the row has one.
    public let name: String?
    /// The designation in a catalogue ("M 45"), if the row has one.
    public let designation: String?
    /// Further designations and names of the same object ("OCL 421.0"), in file order.
    public let alternates: [String]
    /// The J2000 right ascension in degrees, [0, 360), if the row has valid coordinates.
    public let rightAscension: Double?
    /// The J2000 declination in degrees, [-90, 90], if the row has valid coordinates.
    public let declination: Double?
    /// The line the row starts on, from 1.
    public let line: Int

    public init(
        name: String?,
        designation: String?,
        alternates: [String] = [],
        rightAscension: Double? = nil,
        declination: Double? = nil,
        line: Int
    ) {
        self.name = name
        self.designation = designation
        self.alternates = alternates
        self.rightAscension = rightAscension
        self.declination = declination
        self.line = line
    }

    /// Whether the row has a valid right ascension and declination.
    public var hasCoordinates: Bool { rightAscension != nil && declination != nil }

    /// The texts to look the object up by, best first: the designation, the alternates, then the name; without repeats.
    public var searchTerms: [String] {
        var terms: [String] = []
        for term in [designation].compactMap({ $0 }) + alternates + [name].compactMap({ $0 }) where !term.isEmpty && !terms.contains(term) {
            terms.append(term)
        }
        return terms
    }

    /// The text to show for the row: the name, else the designation, else nil.
    public var displayName: String? { name ?? designation }
}

/// Why a row of a list could not be used as it is.
public struct ObservingListRowError: Hashable, Sendable {
    /// What is wrong.
    public enum Reason: String, CaseIterable, Hashable, Sendable {
        /// The row has no name, designation or coordinates.
        case missingName
        /// The right ascension is not a valid angle.
        case invalidRightAscension
        /// The declination is not a valid angle.
        case invalidDeclination
        /// Only one of right ascension and declination is given.
        case incompleteCoordinates
        /// A SkySafari object is not closed by `EndObject=SkyObject`.
        case unterminatedObject

        /// A short sentence for the person.
        public var message: String {
            switch self {
            case .missingName: "No name, designation or coordinates."
            case .invalidRightAscension: "The right ascension is not valid."
            case .invalidDeclination: "The declination is not valid."
            case .incompleteCoordinates: "Right ascension and declination must both be given."
            case .unterminatedObject: "The object is not closed by EndObject."
            }
        }
    }

    /// The line the row starts on, from 1.
    public let line: Int
    public let reason: Reason

    public init(line: Int, reason: Reason) {
        self.line = line
        self.reason = reason
    }
}

/// What `ObservingListCodec.decode(_:)` read from a file.
public struct ObservingListImport: Hashable, Sendable {
    /// The format the file was read as.
    public let format: ObservingListFormat
    /// The usable rows, in file order.
    public let targets: [ImportedTarget]
    /// The rows that had a problem, in file order. A row whose coordinates are invalid but that has a name is in
    /// `targets` (without coordinates) and here.
    public let errors: [ObservingListRowError]
    /// `true` when the file has more rows than `ObservingListCodec.maximumTargets`, which were not read.
    public let isTruncated: Bool

    public init(format: ObservingListFormat, targets: [ImportedTarget], errors: [ObservingListRowError], isTruncated: Bool) {
        self.format = format
        self.targets = targets
        self.errors = errors
        self.isTruncated = isTruncated
    }
}

/// One target to write to a list.
public struct ObservingListEntry: Hashable, Sendable {
    /// The name shown in lists ("Andromeda Galaxy").
    public let name: String
    /// The primary catalogue designation ("M 31"), if the object has one.
    public let designation: String?
    /// The J2000 right ascension in degrees, if known.
    public let rightAscension: Double?
    /// The J2000 declination in degrees, if known.
    public let declination: Double?
    /// The kind of object ("Galaxy"), if known.
    public let typeName: String?

    public init(
        name: String,
        designation: String? = nil,
        rightAscension: Double? = nil,
        declination: Double? = nil,
        typeName: String? = nil
    ) {
        self.name = name
        self.designation = designation
        self.rightAscension = rightAscension
        self.declination = declination
        self.typeName = typeName
    }
}

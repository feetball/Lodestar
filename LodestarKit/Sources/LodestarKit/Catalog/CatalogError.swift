import Foundation

/// One of the four data files a catalog is built from.
public enum CatalogFile: String, CaseIterable, Hashable, Sendable {
    case stars
    case deepSkyObjects
    case constellations
    case milkyWay

    /// The name of the bundled JSON file without its extension.
    var resourceName: String {
        switch self {
        case .stars: "stars"
        case .deepSkyObjects: "dsos"
        case .constellations: "constellations"
        case .milkyWay: "milkyway"
        }
    }

    /// The file name for messages ("stars.json").
    public var fileName: String { resourceName + ".json" }
}

/// Why a catalog could not be loaded.
///
/// Individual bad records never cause an error: they are skipped and counted in
/// `Catalog.loadReport`. Errors mean that a whole file is unusable.
public enum CatalogError: Error, Hashable, Sendable {
    /// A data file is not part of the module's resources.
    case missingResource(CatalogFile)
    /// A data file exists but could not be read.
    case unreadable(CatalogFile, reason: String)
    /// A data file is not valid JSON of the expected shape: truncated, wrong types at the top
    /// level, nested too deeply or larger than `Catalog.maximumFileBytes`.
    case malformed(CatalogFile, reason: String)
    /// A data file declares a schema version other than `Catalog.supportedSchemaVersion`.
    case unsupportedSchema(CatalogFile, version: Int?)
    /// A data file that must contain objects yielded none, because it was empty or because every
    /// record was rejected.
    case noValidRecords(CatalogFile, rejected: Int)
    /// The bundled list of bright asteroids (`BundledAsteroids`) is missing, unreadable, larger than
    /// `BundledAsteroids.maximumFileBytes` or has no valid line. It is not one of the catalog's four data files, so it
    /// has no `CatalogFile`.
    case brightAsteroidsUnavailable(reason: String)
}

extension CatalogError: LocalizedError, CustomStringConvertible {
    /// A sentence that names the data file and says what is wrong with it.
    public var description: String {
        switch self {
        case .missingResource(let file):
            "The catalog data file \(file.fileName) is missing."
        case .unreadable(let file, let reason):
            "The catalog data file \(file.fileName) could not be read: \(reason)"
        case .malformed(let file, let reason):
            "The catalog data file \(file.fileName) is malformed: \(reason)"
        case .unsupportedSchema(let file, let version):
            "The catalog data file \(file.fileName) has an unsupported schema version (\(version.map(String.init) ?? "none"))."
        case .noValidRecords(let file, let rejected):
            "The catalog data file \(file.fileName) has no valid records (\(rejected) rejected)."
        case .brightAsteroidsUnavailable(let reason):
            "The bundled bright-asteroid list is unavailable: \(reason)"
        }
    }

    /// The same sentence as `description`.
    public var errorDescription: String? { description }
}

/// What happened to the records of the data files while a catalog was loaded.
public struct CatalogLoadReport: Hashable, Sendable {
    /// How many records were taken and how many were rejected.
    public struct Counts: Hashable, Sendable {
        /// Records that passed validation and became part of the catalog.
        public internal(set) var accepted = 0
        /// Records that describe an object that is already in the catalog and were merged into it.
        public internal(set) var merged = 0
        /// Records that were skipped: undecodable, out of range, missing a required value or duplicates.
        public internal(set) var rejected = 0
    }

    /// The most problems `issues` lists.
    public static let maximumIssueCount = 25

    /// Star records.
    public internal(set) var stars = Counts()
    /// Deep-sky object records.
    public internal(set) var deepSkyObjects = Counts()
    /// Constellation records.
    public internal(set) var constellations = Counts()
    /// Stick-figure polylines of the accepted constellations.
    public internal(set) var constellationLines = Counts()
    /// Milky Way polygons and holes.
    public internal(set) var milkyWayRings = Counts()
    /// A description of the first problems found, for logging (at most `maximumIssueCount`).
    public internal(set) var issues: [String] = []

    /// The total number of rejected records, polylines and rings.
    public var rejectedCount: Int {
        stars.rejected + deepSkyObjects.rejected + constellations.rejected
            + constellationLines.rejected + milkyWayRings.rejected
    }

    /// `true` when nothing was rejected.
    public var isClean: Bool { rejectedCount == 0 }

    mutating func note(_ message: @autoclosure () -> String) {
        if issues.count < Self.maximumIssueCount {
            issues.append(message())
        }
    }

    /// Counts a rejected record in `counts` and notes why.
    mutating func reject(_ counts: WritableKeyPath<CatalogLoadReport, Counts>, _ message: @autoclosure () -> String) {
        self[keyPath: counts].rejected += 1
        note(message())
    }
}

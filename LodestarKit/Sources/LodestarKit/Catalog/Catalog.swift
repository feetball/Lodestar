import Foundation

/// A star as the sky overlay draws it.
public struct RenderStar: Identifiable, Hashable, Sendable {
    /// The identifier of the star's `CelestialObject`.
    public let id: String
    /// The J2000 catalog direction as a unit vector (x towards the equinox, z towards the pole).
    ///
    /// Proper motion is not applied; at the precision of a camera overlay it is negligible except
    /// for a handful of fast stars. Use `SkyFrame.horizontalVector(j2000UnitVector:)` to place it.
    public let unitVector: Vector3
    /// The visual magnitude.
    public let magnitude: Double
    /// The B−V color index, if known.
    public let colorIndex: Double?
    /// The proper name, for the stars that have one.
    public let name: String?
}

/// The sky catalog: stars, deep-sky objects, solar-system bodies, constellations and the Milky Way, and, when they
/// were added, comets and asteroids.
///
/// A catalog is immutable once created and safe to share between threads. Loading the bundled
/// data takes a fraction of a second, so create one catalog and keep it. Comets and asteroids arrive at run time (the
/// orbit files are downloaded); `withSmallBodies(_:)` and `addingSmallBodies(_:)` make a new catalog with them in a
/// millisecond or two and share the bundled data, so the base catalog is loaded once.
///
/// ```swift
/// let base = try Catalog.loadBundled()
/// let hits = base.search("m31")
/// let catalog = base.withSmallBodies(try BundledAsteroids.load().bodies + downloadedComets)
/// let vesta = catalog.search("vesta").first?.object          // CelestialObject, category .asteroid
/// ```
public final class Catalog: Sendable {
    /// The only version of the data files' `schema` this code reads.
    public static let supportedSchemaVersion = 1
    /// The largest data file that is accepted, in bytes.
    public static let maximumFileBytes = 64 * 1024 * 1024
    /// The most comets and asteroids a catalog takes in `withSmallBodies(_:)`, 100 000 (all of `NEA.txt` is 43 000).
    public static let maximumSmallBodyCount = 100_000

    /// Every object: the Sun, the Moon and the planets, then the Milky Way core and the celestial
    /// poles, then the deep-sky objects (Messier, NGC, IC and others), then the stars from brightest
    /// to faintest, then the comets and asteroids that were added, those with the brightest
    /// `CelestialObject.estimatedPeakMagnitude` first.
    public let objects: [CelestialObject]
    /// The objects that browse lists show (`CelestialObject.isListed`), in the order of `objects`.
    public let listedObjects: [CelestialObject]
    /// Every deep-sky object, listed or not, in the order of `objects`.
    public let deepSkyObjects: [CelestialObject]
    /// The 88 constellations in alphabetical order of their names.
    public let constellations: [Constellation]
    /// The brightness outlines of the Milky Way.
    public let milkyWay: MilkyWayOutline
    /// All stars from brightest to faintest, prepared for drawing.
    public let renderStars: [RenderStar]
    /// What happened to the records of the data files while loading.
    public let loadReport: CatalogLoadReport
    /// The comets and asteroids that were added with `withSmallBodies(_:)` or `addingSmallBodies(_:)`, as in `objects`.
    public let smallBodies: [CelestialObject]

    /// The search index of the bundled objects.
    let searchIndex: SearchIndex
    /// The small bodies' own table and search index.
    let smallBodyTable: SmallBodyTable
    private let contents: CatalogContents
    private let indexByID: [String: Int]
    private let constellationDirectory: ConstellationDirectory
    private let listedByGroup: [ObjectGroup: [CelestialObject]]
    private let deepSkyUpTo: [[CelestialObject]]
    private let byCatalogue: [DeepSkyCatalogue: [CelestialObject]]

    /// Loads the catalog from the data files bundled with the package.
    ///
    /// This reads and checks about 1.6 MB of JSON and builds the search index, which takes a few
    /// hundred milliseconds: call it off the main thread.
    ///
    /// - Throws: `CatalogError` when a file is missing, unreadable or unusable as a whole. Single
    ///   bad records are skipped and counted in `loadReport` instead.
    public static func loadBundled() throws -> Catalog {
        try Catalog(starsData: bundledData(for: .stars), dsosData: bundledData(for: .deepSkyObjects),
                    constellationsData: bundledData(for: .constellations), milkyWayData: bundledData(for: .milkyWay))
    }

    /// The raw contents of one of the bundled data files.
    static func bundledData(for file: CatalogFile) throws -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: file.resourceName, withExtension: "json")
                ?? bundle.url(forResource: file.resourceName, withExtension: "json", subdirectory: "Resources") else {
            throw CatalogError.missingResource(file)
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw CatalogError.unreadable(file, reason: error.localizedDescription)
        }
    }

    /// Creates a catalog from the JSON of the four data files (see `Tools/README.md` for the format).
    ///
    /// Records that cannot be decoded, have values out of range, lack a required value or repeat an
    /// identifier are skipped and counted in `loadReport`.
    ///
    /// - Throws: `CatalogError` when a file is not valid JSON of the expected shape, declares an
    ///   unsupported schema, exceeds `maximumFileBytes`, or contains no valid star or deep-sky object.
    public convenience init(starsData: Data, dsosData: Data, constellationsData: Data, milkyWayData: Data) throws {
        self.init(contents: try CatalogAssembler.assemble(starsData: starsData, dsosData: dsosData,
                                                          constellationsData: constellationsData,
                                                          milkyWayData: milkyWayData),
                  smallBodies: .empty)
    }

    private init(contents: CatalogContents, smallBodies small: SmallBodyTable) {
        self.contents = contents
        objects = small.isEmpty ? contents.objects : contents.objects + small.objects
        listedObjects = small.listed.isEmpty ? contents.listed : contents.listed + small.listed
        deepSkyObjects = contents.deepSky
        constellations = contents.constellations.constellations
        milkyWay = contents.milkyWay
        renderStars = contents.renderStars
        loadReport = contents.report
        smallBodies = small.objects
        searchIndex = contents.searchIndex
        smallBodyTable = small
        indexByID = contents.indexByID
        constellationDirectory = contents.constellations
        listedByGroup = small.mergedListedByGroup(contents.listedByGroup)
        deepSkyUpTo = contents.deepSkyUpTo
        byCatalogue = contents.byCatalogue
    }

    /// The object with an identifier, in constant time.
    ///
    /// Deep-sky objects that are known by an acronym also answer to it: `"dso.LMC"` finds the Large
    /// Magellanic Cloud, whose own `id` is `"dso.ESO56-115"`.
    public func object(id: String) -> CelestialObject? {
        indexByID[id].map { contents.objects[$0] } ?? smallBodyTable.object(id: id)
    }

    /// A catalog with exactly these comets and asteroids as its small bodies, and everything else (the stars, the
    /// deep-sky objects, the planets, the constellations) shared with this one. Small bodies added to this catalog
    /// before are dropped: pass the complete set, for example the bundled asteroids and the comets of the last download.
    ///
    /// Each body becomes an object (`CelestialObject(smallBody:)`) that `object(id:)`, `search(_:limit:)`,
    /// `objects(in:)` with a group and `sorted(_:by:)` find like any other, and that the `SkyFrame` functions for
    /// objects place. Bodies with the same identifier count once and the last one wins, so a list
    /// `bundled + downloaded` lets fresh elements replace stale ones. At most `maximumSmallBodyCount` different bodies
    /// are used, the first ones of the list.
    ///
    /// Cost (optimized build, desktop): 4 ms for the 216 bundled asteroids, 9 ms for 1 000 comets, 0.5 s for 43 000
    /// bodies; a phone takes a few times that, so build a large set off the main thread. The receiver is not changed.
    public func withSmallBodies(_ bodies: [SmallBody]) -> Catalog {
        if bodies.isEmpty, smallBodyTable.isEmpty { return self }
        return Catalog(contents: contents, smallBodies: SmallBodyTable.build(bodies))
    }

    /// A catalog with these comets and asteroids added to the ones this catalog has: a body whose identifier is already
    /// there is replaced, the others stay. See `withSmallBodies(_:)`.
    public func addingSmallBodies(_ bodies: [SmallBody]) -> Catalog {
        withSmallBodies(smallBodyTable.bodies + bodies)
    }

    /// The listed objects of a group, sorted by name. The listed comets and asteroids are in `.solarSystem`.
    public func objects(in group: ObjectGroup) -> [CelestialObject] {
        listedByGroup[group] ?? []
    }

    /// The deep-sky objects of a catalogue, listed or not, in the order of their catalogue numbers:
    /// Caldwell 1 to 109, Sharpless 1 to 313, and so on. An object that has several numbers in the
    /// catalogue (NGC 6523 and NGC 6533 are both M 8's) is listed once, at the first. Constant time; the
    /// list is shared.
    public func objects(in catalogue: DeepSkyCatalogue) -> [CelestialObject] {
        byCatalogue[catalogue] ?? []
    }

    /// The deep-sky objects of `maximum` prominence or better, in the order of `deepSkyObjects`: the
    /// showpieces for `.showpiece`, everything for `.obscure`. Constant time; the lists are shared. This is
    /// the list a sky view draws, with a limit that grows as the field of view narrows.
    public func deepSkyObjects(upTo maximum: Prominence) -> [CelestialObject] {
        deepSkyUpTo[maximum.rawValue - 1]
    }

    /// The constellation with an IAU abbreviation, ignoring case ("cma" finds "CMa").
    public func constellation(abbreviation: String) -> Constellation? {
        constellationDirectory.constellation(abbreviation: abbreviation)
    }

    /// `objects` ordered by `order`, for example the objects of a group or a search.
    ///
    /// The sort is deterministic: objects that compare equal are ordered by identifier.
    public func sorted(_ objects: [CelestialObject], by order: CatalogSortOrder) -> [CelestialObject] {
        CatalogOrdering.sorted(objects, by: order)
    }

    /// One of an object's displayed texts, numbered as in `KeyText.entry`: 0 is the name, then the
    /// designations, then the alternate names.
    func text(ofEntry entry: Int, in object: CelestialObject) -> String {
        if entry == 0 { return object.name }
        if entry <= object.designations.count { return object.designations[entry - 1] }
        let alternate = entry - object.designations.count - 1
        return alternate < object.alternateNames.count ? object.alternateNames[alternate] : object.name
    }
}

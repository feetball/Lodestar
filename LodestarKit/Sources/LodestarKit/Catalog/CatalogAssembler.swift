import Foundation

/// Everything a `Catalog` holds, as produced by `CatalogAssembler`.
struct CatalogContents {
    let objects: [CelestialObject]
    let constellations: ConstellationDirectory
    let milkyWay: MilkyWayOutline
    let renderStars: [RenderStar]
    let report: CatalogLoadReport
    let searchIndex: SearchIndex
    let indexByID: [String: Int]
    let listedByGroup: [ObjectGroup: [CelestialObject]]
}

/// Reads the data files, validates their records and builds the catalog's objects and search index.
enum CatalogAssembler {
    private struct ObjectTable {
        var objects: [CelestialObject] = []
        var search = SearchIndexBuilder()

        mutating func append(_ draft: ObjectDraft) {
            objects.append(draft.object)
            search.beginObject()
            for key in draft.keys {
                search.add(key.text, entry: key.entry)
            }
        }
    }

    static func assemble(starsData: Data, dsosData: Data, constellationsData: Data,
                         milkyWayData: Data) throws -> CatalogContents {
        var report = CatalogLoadReport()
        let constellations = ConstellationDirectory(try loadConstellations(constellationsData, report: &report))
        let deepSky = try loadDeepSkyObjects(dsosData, report: &report)
        let stars = try loadStars(starsData, report: &report)
        let milkyWay = try loadMilkyWay(milkyWayData, report: &report)

        // Plain-star records of the deep-sky data are stars of the star catalog: they become
        // designations of those stars instead of objects of their own.
        var duplicatesOfStar: [Int: [DeepSkyEntry]] = [:]
        var distinctDeepSky: [DeepSkyEntry] = []
        for entry in deepSky {
            if let star = duplicatedStar(of: entry, in: stars) {
                duplicatesOfStar[star, default: []].append(entry)
            } else {
                distinctDeepSky.append(entry)
            }
        }
        report.deepSkyObjects.merged = deepSky.count - distinctDeepSky.count
        report.deepSkyObjects.accepted = distinctDeepSky.count

        var table = ObjectTable()
        table.objects.reserveCapacity(stars.count + distinctDeepSky.count + 16)
        for object in BuiltInObjects.solarSystem() + BuiltInObjects.special(constellations: constellations) {
            table.append(ObjectDraft(plain: object))
        }

        var acronymAliases: [(alias: String, index: Int)] = []
        for entry in distinctDeepSky {
            let draft = CatalogFactory.deepSkyObject(entry, constellations: constellations)
            for alternate in draft.object.alternateNames {
                if let alias = CatalogFactory.acronymAlias(for: alternate) {
                    acronymAliases.append((alias, table.objects.count))
                }
            }
            table.append(draft)
        }

        var renderStars: [RenderStar] = []
        renderStars.reserveCapacity(stars.count)
        for (position, entry) in stars.enumerated() {
            let draft = CatalogFactory.star(entry, constellations: constellations,
                                            absorbing: duplicatesOfStar[position] ?? [])
            renderStars.append(RenderStar(id: draft.object.id, unitVector: entry.position.unitVector,
                                          magnitude: entry.magnitude, colorIndex: entry.colorIndex,
                                          name: entry.properName))
            table.append(draft)
        }

        var indexByID = [String: Int](minimumCapacity: table.objects.count + acronymAliases.count)
        for (index, object) in table.objects.enumerated() {
            indexByID[object.id] = index
        }
        for (alias, index) in acronymAliases where indexByID[alias] == nil {
            indexByID[alias] = index
        }

        let items = CatalogOrdering.items(for: table.objects)
        let objectsByRank = items.sorted(by: CatalogOrdering.searchOrder).map { Int32(truncatingIfNeeded: $0.index) }

        let listedByName = items.filter(\.isListed).sorted(by: CatalogOrdering.nameOrder).map { table.objects[$0.index] }
        var listedByGroup = Dictionary(grouping: listedByName, by: \.group)
        for group in ObjectGroup.allCases where listedByGroup[group] == nil {
            listedByGroup[group] = []
        }

        return CatalogContents(
            objects: table.objects, constellations: constellations, milkyWay: milkyWay, renderStars: renderStars,
            report: report, searchIndex: table.search.finish(objectsByRank: objectsByRank),
            indexByID: indexByID, listedByGroup: listedByGroup)
    }

    /// How close a deep-sky record must be to a star to be that star, in degrees.
    private static let duplicateRadius = 1.0 / 60

    /// The position in `stars` of the star that a deep-sky record merely lists a second time, if any.
    ///
    /// OpenNGC includes a few stars as plain-star records (NGC 1990 is the star Alnilam, IC 1318 is
    /// Sadr). Records of those types within an arcminute of a catalogued star are that star;
    /// Messier objects are never merged.
    private static func duplicatedStar(of entry: DeepSkyEntry, in stars: [StarEntry]) -> Int? {
        guard entry.messier == nil, entry.typeCode == "*" || entry.typeCode == "**" else { return nil }
        var nearest: (index: Int, separation: Double)?
        for (index, star) in stars.enumerated() {
            let separation = entry.position.angularSeparation(to: star.position)
            if separation <= duplicateRadius, separation < (nearest?.separation ?? .infinity) {
                nearest = (index, separation)
            }
        }
        return nearest?.index
    }

    // MARK: Files

    private static func loadConstellations(_ data: Data, report: inout CatalogLoadReport) throws -> [Constellation] {
        let file = try decode(ConstellationsFile.self, from: data, file: .constellations)
        try requireSupportedSchema(file.schema, file: .constellations)
        var constellations: [Constellation] = []
        var abbreviations = Set<String>()
        for (index, element) in file.constellations.enumerated() {
            guard let record = element.value else {
                report.reject(\.constellations, "constellations[\(index)]: record has the wrong shape")
                continue
            }
            do {
                let validated = try CatalogValidation.constellation(record)
                let abbreviation = validated.constellation.abbreviation
                guard abbreviations.insert(abbreviation.lowercased()).inserted else {
                    throw Rejection("duplicate abbreviation \(abbreviation)")
                }
                constellations.append(validated.constellation)
                report.constellations.accepted += 1
                report.constellationLines.accepted += validated.constellation.lines.count
                if !validated.rejectedLines.isEmpty {
                    report.constellationLines.rejected += validated.rejectedLines.count
                    report.note("constellations[\(index)] \(abbreviation): \(validated.rejectedLines.count) invalid polylines skipped")
                }
            } catch {
                report.reject(\.constellations, "constellations[\(index)]: \(reason(of: error))")
            }
        }
        return constellations
    }

    private static func loadDeepSkyObjects(_ data: Data, report: inout CatalogLoadReport) throws -> [DeepSkyEntry] {
        let file = try decode(DeepSkyFile.self, from: data, file: .deepSkyObjects)
        try requireSupportedSchema(file.schema, file: .deepSkyObjects)
        var entries: [DeepSkyEntry] = []
        entries.reserveCapacity(file.objects.count)
        var identifiers = Set<String>()
        for (index, element) in file.objects.enumerated() {
            guard let record = element.value else {
                report.reject(\.deepSkyObjects, "dsos[\(index)]: record has the wrong shape")
                continue
            }
            do {
                let entry = try CatalogValidation.deepSkyObject(record)
                guard identifiers.insert(entry.id).inserted else { throw Rejection("duplicate id \(entry.id)") }
                entries.append(entry)
            } catch {
                report.reject(\.deepSkyObjects, "dsos[\(index)]: \(reason(of: error))")
            }
        }
        guard !entries.isEmpty else {
            throw CatalogError.noValidRecords(.deepSkyObjects, rejected: report.deepSkyObjects.rejected)
        }
        return entries
    }

    /// The valid stars from brightest to faintest (equally bright stars keep their file order).
    private static func loadStars(_ data: Data, report: inout CatalogLoadReport) throws -> [StarEntry] {
        let file = try decode(StarsFile.self, from: data, file: .stars)
        try requireSupportedSchema(file.schema, file: .stars)
        var entries: [StarEntry] = []
        entries.reserveCapacity(file.stars.count)
        var identifiers = Set<String>()
        for (index, element) in file.stars.enumerated() {
            guard let record = element.value else {
                report.reject(\.stars, "stars[\(index)]: record has the wrong shape")
                continue
            }
            do {
                let entry = try CatalogValidation.star(record, sourceIndex: index)
                guard identifiers.insert(entry.objectID).inserted else { throw Rejection("duplicate star \(entry.objectID)") }
                entries.append(entry)
                report.stars.accepted += 1
            } catch {
                report.reject(\.stars, "stars[\(index)]: \(reason(of: error))")
            }
        }
        guard !entries.isEmpty else {
            throw CatalogError.noValidRecords(.stars, rejected: report.stars.rejected)
        }
        entries.sort { lhs, rhs in
            lhs.magnitude != rhs.magnitude ? lhs.magnitude < rhs.magnitude : lhs.sourceIndex < rhs.sourceIndex
        }
        return entries
    }

    private static func loadMilkyWay(_ data: Data, report: inout CatalogLoadReport) throws -> MilkyWayOutline {
        let file = try decode(MilkyWayFile.self, from: data, file: .milkyWay)
        try requireSupportedSchema(file.schema, file: .milkyWay)
        var levels: [MilkyWayOutline.Level] = []
        for (index, element) in file.levels.enumerated() {
            guard let record = element.value else {
                report.reject(\.milkyWayRings, "milkyway[\(index)]: level has the wrong shape")
                continue
            }
            do {
                let validated = try CatalogValidation.milkyWayLevel(record)
                levels.append(validated.level)
                report.milkyWayRings.accepted += validated.level.polygons.count + validated.level.holes.count
                if !validated.rejectedRings.isEmpty {
                    report.milkyWayRings.rejected += validated.rejectedRings.count
                    report.note("milkyway level \(validated.level.level): skipped \(validated.rejectedRings.joined(separator: ", "))")
                }
            } catch {
                report.reject(\.milkyWayRings, "milkyway[\(index)]: \(reason(of: error))")
            }
        }
        return MilkyWayOutline(levels: levels.sorted { $0.level < $1.level })
    }

    // MARK: Helpers

    private static func decode<File: Decodable>(_ type: File.Type, from data: Data, file: CatalogFile) throws -> File {
        guard data.count <= Catalog.maximumFileBytes else {
            throw CatalogError.malformed(file, reason: "larger than \(Catalog.maximumFileBytes) bytes")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw CatalogError.malformed(file, reason: describe(error))
        } catch {
            throw CatalogError.malformed(file, reason: error.localizedDescription)
        }
    }

    private static func requireSupportedSchema(_ version: Int?, file: CatalogFile) throws {
        guard version == Catalog.supportedSchemaVersion else {
            throw CatalogError.unsupportedSchema(file, version: version)
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return context.debugDescription
        case .keyNotFound(let key, _):
            return "the key \"\(key.stringValue)\" is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return "the data could not be decoded"
        }
    }

    private static func reason(of error: any Error) -> String {
        (error as? Rejection)?.reason ?? "unexpected error"
    }
}

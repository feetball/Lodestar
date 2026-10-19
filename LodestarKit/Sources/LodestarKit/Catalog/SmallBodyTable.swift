import Foundation

/// The comets and asteroids that were added to a catalog: their objects, their own small search index and the order
/// of their listings. The bundled data of the catalog is not touched, so a catalog with other small bodies shares it.
struct SmallBodyTable: Sendable {
    /// The objects, brightest estimated peak first (then by name and identifier).
    let objects: [CelestialObject]
    /// The listed objects, in the order of `objects`.
    let listed: [CelestialObject]
    /// The search index over `objects` (its object numbers are positions in `objects`); `nil` when there are none.
    let searchIndex: SearchIndex?
    private let indexByID: [String: Int]

    /// The table of a catalog without small bodies.
    static let empty = SmallBodyTable(objects: [], listed: [], searchIndex: nil, indexByID: [:])

    /// `true` when no small body was added.
    var isEmpty: Bool { objects.isEmpty }

    /// The bodies of `objects`, in their order.
    var bodies: [SmallBody] { objects.compactMap(\.smallBody) }

    /// The object with an identifier, in constant time.
    func object(id: String) -> CelestialObject? {
        indexByID[id].map { objects[$0] }
    }

    /// `base`, the listed objects of the catalog by group, with the listed small bodies merged into their groups in name
    /// order. Groups without small bodies are shared.
    func mergedListedByGroup(_ base: [ObjectGroup: [CelestialObject]]) -> [ObjectGroup: [CelestialObject]] {
        guard !listed.isEmpty else { return base }
        var result = base
        for (group, added) in Dictionary(grouping: listed, by: \.group) {
            result[group] = CatalogOrdering.sorted((base[group] ?? []) + added, by: .name)
        }
        return result
    }

    /// Makes the table of `bodies`. Bodies with the same identifier count once, the last one winning; at most
    /// `Catalog.maximumSmallBodyCount` different bodies are taken, the first ones in the order of the list.
    static func build(_ bodies: [SmallBody]) -> SmallBodyTable {
        var distinct: [String: SmallBody] = [:]
        for body in bodies {
            if distinct.count >= Catalog.maximumSmallBodyCount, distinct[body.id] == nil { continue }
            distinct[body.id] = body
        }
        guard !distinct.isEmpty else { return .empty }
        let drafts = distinct.values.map { CatalogFactory.smallBody($0) }
        let ordered = CatalogOrdering.items(for: drafts.map(\.object)).sorted(by: CatalogOrdering.magnitudeOrder)

        var table = CatalogAssembler.ObjectTable()
        for item in ordered {
            table.append(drafts[item.index])
        }
        let items = CatalogOrdering.items(for: table.objects)
        let objectsByRank = items.sorted(by: CatalogOrdering.searchOrder).map { Int32(truncatingIfNeeded: $0.index) }
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(table.objects.count)
        for (position, object) in table.objects.enumerated() {
            indexByID[object.id] = position
        }
        return SmallBodyTable(objects: table.objects, listed: table.objects.filter(\.isListed),
                              searchIndex: table.search.finish(objectsByRank: objectsByRank), indexByID: indexByID)
    }
}

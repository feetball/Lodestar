import Foundation
import LodestarKit

/// The listed objects of a catalog in name order, with each object's place in that order.
///
/// Building it sorts the whole listing, so create it once per catalog off the main actor.
struct ObjectsCatalogIndex: Sendable {
    /// Every listed object, ordered by name.
    let listed: [CelestialObject]
    private let ranks: [String: Int]

    init(catalog: Catalog) {
        listed = catalog.sorted(catalog.listedObjects, by: .name)
        ranks = Dictionary(listed.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The position of an object in name order; objects the browse lists do not include come last.
    func rank(of id: String) -> Int {
        ranks[id] ?? .max
    }
}

/// One titled block of rows in the Objects list.
struct ObjectsListSection: Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case favorites
        case recent
        case group(ObjectGroup)
        case all
        case results
    }

    let kind: Kind
    let objects: [CelestialObject]

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .group(let group): return group.displayName
        case .all: return "All Objects"
        case .results: return "Results"
        }
    }

    var systemImage: String {
        switch kind {
        case .favorites: return "star.fill"
        case .recent: return "clock"
        case .group(let group): return group.systemImageName
        case .all: return "list.bullet"
        case .results: return "magnifyingglass"
        }
    }
}

/// Turns the catalog and the user's options into the sections the Objects list shows.
enum ObjectsListBuilder {
    /// Favorites, recents and the catalog's listed objects, filtered and ordered by `options`.
    ///
    /// Without sky positions the options that need them (the horizon filter and the altitude and rise-time
    /// orders) cannot be applied; they are skipped until positions arrive.
    static func sections(options: ObjectsListOptions, catalog: Catalog, index: ObjectsCatalogIndex,
                         favoriteIDs: [String], recentIDs: [String],
                         positions: [String: ObjectSkyPosition]) -> [ObjectsListSection] {
        var effective = options
        if positions.isEmpty {
            effective.showsOnlyAboveHorizon = false
            if effective.sortOrder.needsSkyPositions {
                effective.sortOrder = .name
            }
        }
        func resolved(_ ids: [String]) -> [CelestialObject] {
            var seen = Set<String>()
            return ids.compactMap { seen.insert($0).inserted ? catalog.object(id: $0) : nil }
                .filter { passes($0, effective, positions) }
        }

        var sections: [ObjectsListSection] = []
        let favorites = ordered(resolved(favoriteIDs), by: effective.sortOrder, index: index, positions: positions)
        if !favorites.isEmpty {
            sections.append(ObjectsListSection(kind: .favorites, objects: favorites))
        }
        // Recents keep their most-recent-first order whatever the sort order is.
        let recents = resolved(recentIDs)
        if !recents.isEmpty {
            sections.append(ObjectsListSection(kind: .recent, objects: recents))
        }

        // The index is in name order and filtering and grouping keep that order, so these lists need no name sort.
        let visible = index.listed.filter { passes($0, effective, positions) }
        switch effective.grouping {
        case .none:
            let all = ordered(visible, by: effective.sortOrder, index: index, positions: positions,
                              isInNameOrder: true)
            if !all.isEmpty {
                sections.append(ObjectsListSection(kind: .all, objects: all))
            }
        case .type:
            let byGroup = Dictionary(grouping: visible, by: \.group)
            for group in ObjectGroup.allCases {
                guard let members = byGroup[group] else { continue }
                let objects = ordered(members, by: effective.sortOrder, index: index, positions: positions,
                                      isInNameOrder: true)
                sections.append(ObjectsListSection(kind: .group(group), objects: objects))
            }
        }
        return sections
    }

    // MARK: Filtering

    private static func passes(_ object: CelestialObject, _ options: ObjectsListOptions,
                               _ positions: [String: ObjectSkyPosition]) -> Bool {
        if options.showsOnlyAboveHorizon, positions[object.id]?.isAboveHorizon != true {
            return false
        }
        if options.hidesFaintObjects, let magnitude = object.magnitude,
           magnitude > ObjectsListOptions.faintMagnitudeLimit {
            return false
        }
        return true
    }

    // MARK: Ordering

    /// Sort keys compared in order; ties fall back to name order and then the identifier, so the result never
    /// depends on the input order.
    private struct SortKey: Comparable {
        var tier: Int
        var value: Double
        var rank: Int
        var id: String

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.id < rhs.id
        }
    }

    /// `objects` in the given order. `isInNameOrder` says they already are in name order, which saves sorting them.
    private static func ordered(_ objects: [CelestialObject], by order: ObjectsSortOrder, index: ObjectsCatalogIndex,
                                positions: [String: ObjectSkyPosition],
                                isInNameOrder: Bool = false) -> [CelestialObject] {
        if order == .name, isInNameOrder {
            return objects
        }
        func key(for object: CelestialObject) -> SortKey {
            let position = positions[object.id]
            func make(tier: Int = 0, _ value: Double = 0) -> SortKey {
                SortKey(tier: tier, value: value, rank: index.rank(of: object.id), id: object.id)
            }
            switch order {
            case .name:
                return make()
            case .brightness:
                // Brightest first; objects with no known magnitude come last.
                return make(position?.magnitude ?? object.magnitude ?? .infinity)
            case .altitude:
                // Highest first; objects without a position come last.
                return make(position.map { -$0.altitude } ?? .infinity)
            case .riseTime:
                // Objects already up come first, highest first; then the soonest risings; then those that never rise.
                guard let position else { return make(tier: 2) }
                if position.isAboveHorizon {
                    return make(-position.altitude)
                }
                guard let rise = position.nextRise else { return make(tier: 2) }
                return make(tier: 1, rise.timeIntervalSinceReferenceDate)
            }
        }
        return objects.map { (object: $0, key: key(for: $0)) }
            .sorted { $0.key < $1.key }
            .map(\.object)
    }
}

import Foundation
import LodestarKit

/// The listed objects of a catalog in name order, with each object's place in that order.
///
/// The order also covers the deep-sky objects the browse lists leave out, so that a catalogue list can be put in name
/// order too. Building it sorts them all, so create it once per catalog off the main actor.
struct ObjectsCatalogIndex: Sendable {
    /// Every listed object, ordered by name.
    let listed: [CelestialObject]
    private let ranks: [String: Int]

    init(catalog: Catalog) {
        listed = catalog.sorted(catalog.listedObjects, by: .name)
        let listedIDs = Set(listed.map(\.id))
        let hidden = catalog.deepSkyObjects.filter { !listedIDs.contains($0.id) }
        let everything = catalog.sorted(listed + hidden, by: .name)
        ranks = Dictionary(everything.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The position of an object in name order; objects the catalog does not know come last.
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
        /// The comets or the asteroids, which the Solar System group holds besides the Sun, the Moon and the planets.
        case smallBodies(ObjectCategory)
        case prominence(Prominence)
        case all
        case results
    }

    let kind: Kind
    let objects: [CelestialObject]
    /// Favorite comets and asteroids that have no current orbit: listed after `objects` with "no current orbit".
    var unavailable: [String] = []

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .group(let group): return group.displayName
        case .smallBodies(let category): return "\(category.displayName)s"
        case .prominence(let prominence): return Self.title(of: prominence)
        case .all: return "All Objects"
        case .results: return "Results"
        }
    }

    var systemImage: String {
        switch kind {
        case .favorites: return "star.fill"
        case .recent: return "clock"
        case .group(let group): return group.systemImageName
        case .smallBodies(let category): return category.systemImageName
        case .prominence(let prominence): return Self.systemImage(of: prominence)
        case .all: return "list.bullet"
        case .results: return "magnifyingglass"
        }
    }

    private static func title(of prominence: Prominence) -> String {
        switch prominence {
        case .showpiece: return "Showpieces"
        case .prominent: return "Prominent"
        case .notable: return "Notable"
        case .obscure: return "Obscure"
        }
    }

    private static func systemImage(of prominence: Prominence) -> String {
        switch prominence {
        case .showpiece: return "sparkles"
        case .prominent: return "sparkle"
        case .notable: return "circle.dotted"
        case .obscure: return "circle.dashed"
        }
    }
}

/// Turns the catalog and the user's options into the sections the Objects list shows.
enum ObjectsListBuilder {
    /// Favorites, recents and the catalog's listed objects (or, with a catalogue chosen, that catalogue's objects),
    /// filtered and ordered by `options`.
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
        let favorites = ordered(resolved(favoriteIDs), by: effective.sortOrder, index: index, positions: positions,
                                catalogue: effective.catalogue)
        // A favorite comet that dropped out of the orbit data stays, as "no current orbit", unless a filter is on.
        let lostFavorites = effective.showsOnlyAboveHorizon || effective.showsOnlyPopular || effective.catalogue != .all
            ? [] : SmallBodyFavorites.withoutOrbit(favoriteIDs: favoriteIDs, catalog: catalog)
        if !favorites.isEmpty || !lostFavorites.isEmpty {
            sections.append(ObjectsListSection(kind: .favorites, objects: favorites, unavailable: lostFavorites))
        }
        // Recents keep their most-recent-first order whatever the sort order is.
        let recents = resolved(recentIDs)
        if !recents.isEmpty {
            sections.append(ObjectsListSection(kind: .recent, objects: recents))
        }

        // The index is in name order and filtering and grouping keep that order, so the browse lists need no name
        // sort. A catalogue's own list is in catalogue order instead.
        let isBrowse = effective.catalogue == .all
        let source = isBrowse ? index.listed : effective.catalogue.objects(in: catalog)
        let visible = source.filter { passes($0, effective, positions) }
        func sorted(_ objects: [CelestialObject]) -> [CelestialObject] {
            ordered(objects, by: effective.sortOrder, index: index, positions: positions,
                    isInNameOrder: isBrowse, catalogue: effective.catalogue)
        }
        switch effective.grouping {
        case .none:
            let all = sorted(visible)
            if !all.isEmpty {
                sections.append(ObjectsListSection(kind: .all, objects: all))
            }
        case .type:
            let byGroup = Dictionary(grouping: visible, by: \.group)
            for group in ObjectGroup.allCases {
                guard let members = byGroup[group] else { continue }
                guard group == .solarSystem else {
                    sections.append(ObjectsListSection(kind: .group(group), objects: sorted(members)))
                    continue
                }
                // The Solar System group holds the comets and asteroids too: they get a section each.
                let parts: [(ObjectsListSection.Kind, [CelestialObject])] = [
                    (.group(group), members.filter { $0.smallBody == nil }),
                    (.smallBodies(.comet), members.filter { $0.category == .comet }),
                    (.smallBodies(.asteroid), members.filter { $0.category == .asteroid }),
                ]
                for (kind, part) in parts where !part.isEmpty {
                    sections.append(ObjectsListSection(kind: kind, objects: sorted(part)))
                }
            }
        case .prominence:
            let byProminence = Dictionary(grouping: visible, by: \.prominence)
            for prominence in Prominence.allCases {
                guard let members = byProminence[prominence] else { continue }
                sections.append(ObjectsListSection(kind: .prominence(prominence), objects: sorted(members)))
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
        // A comet or an asteroid has no catalog magnitude: its current one decides.
        let magnitude = object.magnitude ?? (object.smallBody == nil ? nil : positions[object.id]?.magnitude)
        if options.hidesFaintObjects, let magnitude, magnitude > ObjectsListOptions.faintMagnitudeLimit {
            return false
        }
        if options.showsOnlyPopular, object.prominence > ObjectsListOptions.popularProminence {
            return false
        }
        return options.catalogue.contains(object)
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
                                positions: [String: ObjectSkyPosition], isInNameOrder: Bool = false,
                                catalogue: ObjectsCatalogueFilter = .all) -> [CelestialObject] {
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
            case .number:
                // By catalogue number; objects without one come last.
                return catalogue.numberKey(of: object).map { make(tier: 0, $0) } ?? make(tier: 1)
            case .prominence:
                // Showpieces first; inside a level the brightest, objects without a magnitude after those with one.
                return make(tier: object.prominence.rawValue, position?.magnitude ?? object.magnitude ?? .infinity)
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

import Foundation

/// How a list of objects can be ordered.
public enum CatalogSortOrder: String, CaseIterable, Hashable, Sendable {
    /// Alphabetically by display name, ignoring case, diacritics and punctuation, with numbers in
    /// numeric order ("M 2" before "M 10"). Names without any Latin letter or digit, which a custom
    /// target can have, come first, ordered by their characters.
    case name
    /// Brightest first. Objects without a known magnitude come last. Solar-system bodies, whose
    /// brightness changes, are placed by a typical peak magnitude (Venus before Jupiter, and so on).
    case magnitude
}

/// The comparisons behind sorting and search ranking.
///
/// Every order ends in the object's identifier, so the result never depends on the input order.
enum CatalogOrdering {
    /// An object with the values the comparisons need, computed once.
    struct Item {
        let index: Int
        let name: String
        let nameKey: [UInt8]
        let magnitude: Double
        let isListed: Bool
        let prominence: Int
        let id: String
    }

    static func items(for objects: [CelestialObject]) -> [Item] {
        objects.enumerated().map { index, object in
            Item(index: index, name: object.name, nameKey: SearchText.key(for: object.name).bytes,
                 magnitude: object.rankingMagnitude, isListed: object.isListed,
                 prominence: object.prominence.rawValue, id: object.id)
        }
    }

    /// The values of one object that is not part of a table (its `index` is 0).
    static func item(for object: CelestialObject) -> Item {
        items(for: [object])[0]
    }

    static func sorted(_ objects: [CelestialObject], by order: CatalogSortOrder) -> [CelestialObject] {
        let items = items(for: objects)
        let ordered: [Item]
        switch order {
        case .name: ordered = items.sorted(by: nameOrder)
        case .magnitude: ordered = items.sorted(by: magnitudeOrder)
        }
        return ordered.map { objects[$0.index] }
    }

    /// Alphabetical, then by identifier.
    ///
    /// Names without a single Latin letter or digit (a custom target called "Орион") have an empty
    /// key and come first; among themselves they are ordered by their characters.
    static func nameOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        if SearchText.naturalPrecedes(lhs.nameKey, rhs.nameKey) { return true }
        if SearchText.naturalPrecedes(rhs.nameKey, lhs.nameKey) { return false }
        if lhs.nameKey.isEmpty, lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }

    /// Brighter first, then alphabetical.
    static func magnitudeOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.magnitude != rhs.magnitude { return lhs.magnitude < rhs.magnitude }
        return nameOrder(lhs, rhs)
    }

    /// Listed objects first, then more prominent ones, then brighter first, then alphabetical: the order of
    /// equally good search matches. Prominence comes before brightness so that a showpiece without a
    /// magnitude (the Horsehead Nebula) is not outranked by a faint galaxy.
    static func searchOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.isListed != rhs.isListed { return lhs.isListed }
        if lhs.prominence != rhs.prominence { return lhs.prominence < rhs.prominence }
        return magnitudeOrder(lhs, rhs)
    }
}

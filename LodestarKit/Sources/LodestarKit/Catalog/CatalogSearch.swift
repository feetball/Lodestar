import Foundation

/// One match of `Catalog.search`.
public struct CatalogSearchResult: Identifiable, Hashable, Sendable {
    /// How well a result matches the query, best first.
    public enum MatchKind: Int, Comparable, CaseIterable, Sendable {
        /// The query is the whole text, ignoring case, accents and punctuation.
        case exact
        /// The text starts with the query.
        case prefix
        /// A later word of the text starts with the query ("neb" in "Orion Nebula").
        case wordPrefix
        /// The query occurs somewhere inside the text.
        case contains
        /// The letters of the query occur in order in the text, the first one starting a word
        /// ("andgal" in "Andromeda Galaxy"). Such suggestions are only made for queries of three or
        /// more characters, and only when nothing matches in any of the better ways.
        case fuzzy

        /// Orders kinds from the best match to the worst.
        public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The identifier of the object found.
    public var id: String { object.id }
    /// The object found.
    public let object: CelestialObject
    /// The name or designation of the object that matched, as displayed ("α CMa").
    public let matchedText: String
    /// How well the text matched.
    public let kind: MatchKind
}

extension Catalog {
    /// The longest query that is looked at, in Unicode scalars; the rest is ignored.
    public static let maximumQueryLength = SearchText.maximumQueryScalars

    /// The objects that best match a query, best first.
    ///
    /// Matching ignores case, diacritics, character width, punctuation and spacing, reads Greek
    /// letters either way ("α" is "alpha" is "alp"), takes superscript digits as digits ("α¹" is
    /// "alpha1") and drops leading zeros of numbers. So "m31", "M 31", "Messier 31" and "M031" are the
    /// same query, as are "ngc224" and "NGC 0224", and "alpha cma", "alpha canis majoris" and "α CMa".
    /// It matches names, common names and the designations of every object: Messier, NGC and IC
    /// numbers, the numbers of the other deep-sky catalogues (Caldwell "C 14" and "Caldwell 14", Sharpless
    /// "Sh2-155", "Sh 2-155" and "Sharpless 155", Barnard "B33" and "Barnard 33", Lynds "LDN 1622" and
    /// "Lynds 1622", Collinder "Cr 399", Melotte "Mel 20", Trumpler "Tr 24", Stock "St 2"), Bayer and
    /// Flamsteed designations with the constellation as abbreviation or genitive, and HR, HD and HIP numbers.
    ///
    /// Results are ordered by `MatchKind`; matches of the same kind are ordered by listed objects first,
    /// then more prominent objects (`CelestialObject.prominence`), then brighter objects (objects without a
    /// magnitude last), then name. `MatchKind.fuzzy` results only appear when there are no other matches.
    ///
    /// - Parameters:
    ///   - query: The text to look for. Only its first `maximumQueryLength` characters are used. A
    ///     query without letters or digits finds nothing.
    ///   - limit: The most results to return; a limit of zero or less returns none.
    public func search(_ query: String, limit: Int = 50) -> [CatalogSearchResult] {
        let key = SearchText.key(for: query, maximumScalars: SearchText.maximumQueryScalars)
        return searchIndex.search(key.bytes, limit: limit).map { hit in
            let object = objects[hit.objectIndex]
            let source = searchIndex.source(ofKey: hit.keyIndex)
            return CatalogSearchResult(object: object, matchedText: text(ofEntry: source.entry, in: object),
                                       kind: hit.kind)
        }
    }
}

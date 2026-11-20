/// A row of an imported list and the catalog object it was matched to.
public struct ObservingListMatch: Hashable, Sendable {
    /// The row.
    public let target: ImportedTarget
    /// The catalog object, or nil when the catalog has no object with one of the row's names.
    public let object: CelestialObject?

    public init(target: ImportedTarget, object: CelestialObject?) {
        self.target = target
        self.object = object
    }
}

/// Finds the catalog objects of imported rows.
public enum ObservingListMatcher {
    /// The most results of a catalog search that are looked at for one text.
    private static let searchLimit = 8

    /// The catalog object a row stands for: the first of its `searchTerms` (designation, alternates, name) that has an
    /// exact match in `Catalog.search(_:limit:)`, which ignores case, accents, punctuation and spacing ("m31", "M 31" and
    /// "Messier 31" are one text). Matches that are only a prefix or part of a name are not taken.
    public static func match(_ target: ImportedTarget, in catalog: Catalog) -> CelestialObject? {
        for term in target.searchTerms {
            if let result = catalog.search(term, limit: searchLimit).first(where: { $0.kind == .exact }) {
                return result.object
            }
        }
        return nil
    }

    /// Matches every row. Cost: one catalog search per search term, a fraction of a millisecond each; a full list of
    /// 5,000 rows takes a second or two on a phone, so run it off the main thread.
    public static func match(_ targets: [ImportedTarget], in catalog: Catalog) -> [ObservingListMatch] {
        targets.map { ObservingListMatch(target: $0, object: match($0, in: catalog)) }
    }
}

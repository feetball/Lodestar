import Foundation

/// One search hit before it is turned into a public `CatalogSearchResult`.
struct SearchHit {
    /// The position of the object in `Catalog.objects`.
    let objectIndex: Int
    /// The index of the best matching key in the search index.
    let keyIndex: Int
    let kind: CatalogSearchResult.MatchKind
}

/// The precomputed keys of all objects, scanned linearly for each query.
///
/// Every object contributes one key per searchable text (names, designations and their spelling
/// variants). All keys live in one byte array, and each key has a mask of the letters and digits it
/// contains, so a query first discards the keys that lack one of its characters with a single
/// comparison and only looks closely at the rest. A query allocates two arrays with an entry per object
/// and the result; about 40 000 keys are scanned in a fraction of a millisecond.
struct SearchIndex: Sendable {
    /// Where a key's bytes are and what it stands for.
    struct KeyRecord: Sendable {
        /// Offset of the first byte in `text`.
        var start: Int32
        /// The object the key belongs to.
        var owner: Int32
        /// Word boundaries, see `SearchText.Key`.
        var wordStarts: UInt64
        /// Which text of the object the key was made from: 0 is its name, then its designations,
        /// then its alternate names.
        var entry: UInt16
        var length: UInt8
    }

    /// Queries shorter than this (in normalized bytes) are not matched loosely.
    static let minimumFuzzyLength = 3

    /// The bytes of all keys, one after the other.
    let text: [UInt8]
    /// The keys, grouped by object in the order of `Catalog.objects`.
    let records: [KeyRecord]
    /// Per key: the characters it contains, see `symbolMask(of:)`.
    let symbolMasks: [UInt64]
    /// The objects from the first to the last place in the order of equally good matches.
    let objectsByRank: [Int32]

    init(text: [UInt8], records: [KeyRecord], symbolMasks: [UInt64], objectsByRank: [Int32]) {
        self.text = text
        self.records = records
        self.symbolMasks = symbolMasks
        self.objectsByRank = objectsByRank
    }

    var keyCount: Int { records.count }

    /// The object and entry a key was made from.
    func source(ofKey keyIndex: Int) -> (object: Int, entry: Int) {
        let record = records[keyIndex]
        return (Int(record.owner), Int(record.entry))
    }

    /// One bit per character that can occur in a key: 0 to 25 for "a" to "z", 26 to 35 for "0" to "9".
    /// Any other byte, which no key contains, takes bit 63.
    @inline(__always)
    static func symbolBit(of byte: UInt8) -> UInt64 {
        switch byte {
        case 0x61...0x7A: 1 << UInt64(byte &- 0x61)
        case 0x30...0x39: 1 << UInt64(26 &+ (byte &- 0x30))
        default: 1 << 63
        }
    }

    /// The set of characters in `bytes`, as an or of `symbolBit(of:)`.
    ///
    /// A key can only match a query if its mask contains the query's mask.
    static func symbolMask(of bytes: [UInt8]) -> UInt64 {
        var mask: UInt64 = 0
        for byte in bytes {
            mask |= symbolBit(of: byte)
        }
        return mask
    }

    /// The best `limit` matches for a normalized query, best first.
    ///
    /// An object is ranked by its best-matching key: exact match, key starting with the query,
    /// query starting at a later word of the key, query anywhere inside the key. Only when nothing
    /// matches in one of those ways, and the query has at least `minimumFuzzyLength` bytes, are
    /// objects suggested whose keys contain the query's letters in order, the first of them opening
    /// a word. Equal ranks are ordered by `objectsByRank`.
    ///
    /// The scan runs in stages and stops as soon as the better stages have found `limit` objects,
    /// since later stages can only add objects that rank below all of those.
    func search(_ query: [UInt8], limit: Int) -> [SearchHit] {
        guard !query.isEmpty, query.count <= SearchText.maximumKeyLength, limit > 0 else { return [] }
        let queryMask = Self.symbolMask(of: query)
        return text.withUnsafeBufferPointer { text in
            records.withUnsafeBufferPointer { records in
                symbolMasks.withUnsafeBufferPointer { masks in
                    query.withUnsafeBufferPointer { query in
                        var scan = Scan(text: text, records: records, masks: masks, query: query,
                                        queryMask: queryMask, objectCount: objectsByRank.count)
                        scan.findWordMatches()
                        if scan.matchedObjects < limit {
                            scan.findInnerMatches()
                        }
                        if scan.matchedObjects == 0, query.count >= Self.minimumFuzzyLength {
                            scan.findLooseMatches()
                        }
                        return scan.hits(limit: limit, objectsByRank: objectsByRank)
                    }
                }
            }
        }
    }
}

// MARK: - Scanning

/// The state of one search: the best match found so far for every object.
private struct Scan {
    private static let noMatch = UInt8.max
    private static let kinds = CatalogSearchResult.MatchKind.allCases

    private let text: UnsafeBufferPointer<UInt8>
    private let records: UnsafeBufferPointer<SearchIndex.KeyRecord>
    private let masks: UnsafeBufferPointer<UInt64>
    private let query: UnsafeBufferPointer<UInt8>
    private let queryMask: UInt64
    /// Per object: the `MatchKind` raw value of its best match, or `noMatch`.
    private var bestKind: [UInt8]
    /// Per object: the key of its best match.
    private var bestKey: [Int32]
    /// Per kind (in `MatchKind` order): how many objects have it as their best match.
    private var objectsOfKind = [Int](repeating: 0, count: Scan.kinds.count)
    /// How many objects have a match.
    private(set) var matchedObjects = 0

    init(text: UnsafeBufferPointer<UInt8>, records: UnsafeBufferPointer<SearchIndex.KeyRecord>,
         masks: UnsafeBufferPointer<UInt64>, query: UnsafeBufferPointer<UInt8>, queryMask: UInt64, objectCount: Int) {
        self.text = text
        self.records = records
        self.masks = masks
        self.query = query
        self.queryMask = queryMask
        bestKind = [UInt8](repeating: Self.noMatch, count: objectCount)
        bestKey = [Int32](repeating: -1, count: objectCount)
    }

    /// Finds the keys equal to the query, starting with it, or with a later word that starts with it.
    mutating func findWordMatches() {
        let queryLength = query.count
        let first = query[0]
        for keyIndex in 0..<records.count where masks[keyIndex] & queryMask == queryMask {
            let record = records[keyIndex]
            let length = Int(record.length)
            guard length >= queryLength else { continue }
            let start = Int(record.start)
            let kind: CatalogSearchResult.MatchKind
            if text[start] == first, matches(at: start) {
                kind = length == queryLength ? .exact : .prefix
            } else if opensWord(record) {
                kind = .wordPrefix
            } else {
                continue
            }
            note(kind, key: keyIndex, owner: Int(record.owner))
        }
    }

    /// Finds the keys that contain the query somewhere, for the objects without a better match.
    mutating func findInnerMatches() {
        let queryLength = query.count
        let first = query[0]
        for keyIndex in 0..<records.count where masks[keyIndex] & queryMask == queryMask {
            let record = records[keyIndex]
            let length = Int(record.length)
            let owner = Int(record.owner)
            guard length >= queryLength, bestKind[owner] == Self.noMatch else { continue }
            let start = Int(record.start)
            var offset = 0
            while offset + queryLength <= length {
                if text[start + offset] == first, matches(at: start + offset) {
                    note(.contains, key: keyIndex, owner: owner)
                    break
                }
                offset += 1
            }
        }
    }

    /// Finds the keys with the query's characters in order, the first one opening a word, for the
    /// objects without any other match.
    mutating func findLooseMatches() {
        let queryLength = query.count
        let first = query[0]
        for keyIndex in 0..<records.count where masks[keyIndex] & queryMask == queryMask {
            let record = records[keyIndex]
            let length = Int(record.length)
            let owner = Int(record.owner)
            guard length >= queryLength, bestKind[owner] == Self.noMatch else { continue }
            let start = Int(record.start)
            var wordStarts = record.wordStarts
            while wordStarts != 0 {
                let offset = wordStarts.trailingZeroBitCount
                wordStarts &= wordStarts &- 1
                guard offset < length, length - offset >= queryLength, text[start + offset] == first else { continue }
                var matched = 1
                var position = offset + 1
                while matched < queryLength, position < length {
                    if text[start + position] == query[matched] { matched += 1 }
                    position += 1
                }
                if matched == queryLength {
                    note(.fuzzy, key: keyIndex, owner: owner)
                    break
                }
            }
        }
    }

    /// The best `limit` matched objects: better kinds first, equal kinds in the order of `objectsByRank`.
    func hits(limit: Int, objectsByRank: [Int32]) -> [SearchHit] {
        // The best kinds fill the result first, so only some objects of the last kind that fits are
        // wanted. One walk through the objects in rank order picks them out without sorting, and it
        // ends as soon as they are all found.
        var wanted = objectsOfKind
        var room = limit
        for kind in wanted.indices {
            wanted[kind] = min(wanted[kind], room)
            room -= wanted[kind]
        }
        var outstanding = wanted.reduce(0, +)
        guard outstanding > 0 else { return [] }
        var byKind = [[Int32]](repeating: [], count: wanted.count)
        for object in objectsByRank {
            let kind = Int(bestKind[Int(object)])
            if kind != Self.noMatch, byKind[kind].count < wanted[kind] {
                byKind[kind].append(object)
                outstanding -= 1
                if outstanding == 0 { break }
            }
        }
        var hits: [SearchHit] = []
        hits.reserveCapacity(min(limit, matchedObjects))
        for (kind, objects) in zip(Self.kinds, byKind) {
            for object in objects {
                hits.append(SearchHit(objectIndex: Int(object), keyIndex: Int(bestKey[Int(object)]), kind: kind))
            }
        }
        return hits
    }

    // MARK: Helpers

    /// Records a match for an object unless it already has an equal or better one.
    private mutating func note(_ kind: CatalogSearchResult.MatchKind, key: Int, owner: Int) {
        let current = bestKind[owner]
        let rank = UInt8(truncatingIfNeeded: kind.rawValue)
        guard rank < current else { return }
        if current == Self.noMatch {
            matchedObjects += 1
        } else {
            objectsOfKind[Int(current)] -= 1
        }
        objectsOfKind[Int(rank)] += 1
        bestKind[owner] = rank
        bestKey[owner] = Int32(truncatingIfNeeded: key)
    }

    /// Whether the query occurs in the text at `offset`, which must leave room for all of it.
    @inline(__always)
    private func matches(at offset: Int) -> Bool {
        var index = 0
        let count = query.count
        while index < count {
            if text[offset + index] != query[index] { return false }
            index += 1
        }
        return true
    }

    /// Whether a word after the first one starts with the query.
    private func opensWord(_ record: SearchIndex.KeyRecord) -> Bool {
        let start = Int(record.start)
        let length = Int(record.length)
        let first = query[0]
        var wordStarts = record.wordStarts & ~1
        while wordStarts != 0 {
            let offset = wordStarts.trailingZeroBitCount
            wordStarts &= wordStarts &- 1
            if offset + query.count <= length, text[start + offset] == first, matches(at: start + offset) {
                return true
            }
        }
        return false
    }
}

// MARK: - Building

/// Collects the keys of all objects, in object order.
struct SearchIndexBuilder {
    private var text: [UInt8] = []
    private var records: [SearchIndex.KeyRecord] = []
    private var symbolMasks: [UInt64] = []
    private var objectCount = 0
    private var firstRecordOfObject = 0

    init() {
        text.reserveCapacity(1 << 20)
        records.reserveCapacity(1 << 16)
        symbolMasks.reserveCapacity(1 << 16)
    }

    /// Starts the keys of the next object (the one after all previous ones).
    mutating func beginObject() {
        objectCount += 1
        firstRecordOfObject = records.count
    }

    /// Adds the key of `string` for the current object, unless it is empty or the object already has it.
    mutating func add(_ string: String, entry: Int) {
        let key = SearchText.key(for: string)
        guard !key.bytes.isEmpty, entry >= 0, entry <= Int(UInt16.max) else { return }
        for index in firstRecordOfObject..<records.count {
            let existing = records[index]
            if Int(existing.length) == key.bytes.count,
               text[Int(existing.start)..<(Int(existing.start) + Int(existing.length))].elementsEqual(key.bytes) {
                return
            }
        }
        records.append(SearchIndex.KeyRecord(
            start: Int32(truncatingIfNeeded: text.count), owner: Int32(truncatingIfNeeded: objectCount - 1),
            wordStarts: key.wordStarts, entry: UInt16(truncatingIfNeeded: entry),
            length: UInt8(truncatingIfNeeded: key.bytes.count)))
        symbolMasks.append(SearchIndex.symbolMask(of: key.bytes))
        text.append(contentsOf: key.bytes)
    }

    /// Completes the index with the order of equally good matches: `objectsByRank` lists the
    /// objects from the first to the last place.
    func finish(objectsByRank: [Int32]) -> SearchIndex {
        SearchIndex(text: text, records: records, symbolMasks: symbolMasks, objectsByRank: objectsByRank)
    }
}

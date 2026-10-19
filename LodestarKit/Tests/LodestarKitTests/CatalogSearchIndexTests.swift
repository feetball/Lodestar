import XCTest
@testable import LodestarKit

extension SearchIndex {
    /// The normalized text of a key, for checking the index against a plain implementation.
    func key(at keyIndex: Int) -> SearchText.Key {
        let record = records[keyIndex]
        let start = Int(record.start)
        return SearchText.Key(bytes: Array(text[start..<(start + Int(record.length))]), wordStarts: record.wordStarts)
    }
}

/// The search rules written out in the plainest way, to check the optimized scan against.
///
/// It looks at every key of the index one by one with ordinary array operations, finds the best
/// match of every object and orders the objects by kind and then by the documented tie-break:
/// listed objects first, then brighter ones, then by name.
private struct ReferenceSearch {
    struct Match: Equatable {
        let object: Int
        let key: Int
        let kind: CatalogSearchResult.MatchKind
    }

    private let keys: [SearchText.Key]
    private let owners: [Int]
    private let rankOfObject: [Int]

    init(_ catalog: Catalog) {
        let index = catalog.searchIndex
        keys = (0..<index.keyCount).map { index.key(at: $0) }
        owners = (0..<index.keyCount).map { index.source(ofKey: $0).object }
        let objects = catalog.objects
        let order = objects.indices.sorted { first, second in
            let a = objects[first], b = objects[second]
            if a.isListed != b.isListed { return a.isListed }
            if a.prominence != b.prominence { return a.prominence < b.prominence }
            if a.rankingMagnitude != b.rankingMagnitude { return a.rankingMagnitude < b.rankingMagnitude }
            let nameA = SearchText.key(for: a.name).bytes, nameB = SearchText.key(for: b.name).bytes
            if SearchText.naturalPrecedes(nameA, nameB) { return true }
            if SearchText.naturalPrecedes(nameB, nameA) { return false }
            return a.id < b.id
        }
        var rank = [Int](repeating: 0, count: objects.count)
        for (position, object) in order.enumerated() { rank[object] = position }
        rankOfObject = rank
    }

    /// Every matching object, best first.
    func matches(for query: [UInt8]) -> [Match] {
        var best: [Int: Match] = [:]
        for (keyIndex, key) in keys.enumerated() {
            guard let kind = Self.kind(of: key, matching: query) else { continue }
            let owner = owners[keyIndex]
            if let current = best[owner], current.kind <= kind { continue }
            best[owner] = Match(object: owner, key: keyIndex, kind: kind)
        }
        if best.isEmpty, query.count >= 3 {
            for (keyIndex, key) in keys.enumerated() where best[owners[keyIndex]] == nil && Self.isLoose(key, matching: query) {
                best[owners[keyIndex]] = Match(object: owners[keyIndex], key: keyIndex, kind: .fuzzy)
            }
        }
        return best.values.sorted { first, second in
            first.kind != second.kind ? first.kind < second.kind : rankOfObject[first.object] < rankOfObject[second.object]
        }
    }

    private static func kind(of key: SearchText.Key, matching query: [UInt8]) -> CatalogSearchResult.MatchKind? {
        let bytes = key.bytes
        guard bytes.count >= query.count else { return nil }
        /// Whether the query is the text of the key from `offset` on, for as long as the query goes.
        func occurs(at offset: Int) -> Bool {
            for position in 0..<query.count where bytes[offset + position] != query[position] {
                return false
            }
            return true
        }
        if occurs(at: 0) {
            return bytes.count == query.count ? .exact : .prefix
        }
        let lastOffset = bytes.count - query.count
        for offset in stride(from: 1, through: lastOffset, by: 1) where key.wordStarts & (1 << UInt64(offset)) != 0 {
            if occurs(at: offset) { return .wordPrefix }
        }
        for offset in stride(from: 1, through: lastOffset, by: 1) where occurs(at: offset) {
            return .contains
        }
        return nil
    }

    /// Whether the query's bytes occur in order in the key, the first one at the start of a word.
    private static func isLoose(_ key: SearchText.Key, matching query: [UInt8]) -> Bool {
        let bytes = key.bytes
        for start in 0..<bytes.count where key.wordStarts & (1 << UInt64(start)) != 0 && bytes[start] == query[0] {
            var matched = 0
            for position in start..<bytes.count where matched < query.count && bytes[position] == query[matched] {
                matched += 1
            }
            if matched == query.count { return true }
        }
        return false
    }
}

final class CatalogSearchIndexTests: XCTestCase {
    // MARK: Symbol masks

    func testSymbolMasksHaveOneBitPerLetterAndDigit() {
        let letters = Array("abcdefghijklmnopqrstuvwxyz".utf8)
        let digits = Array("0123456789".utf8)
        var seen: UInt64 = 0
        for byte in letters + digits {
            let bit = SearchIndex.symbolBit(of: byte)
            XCTAssertEqual(bit.nonzeroBitCount, 1, String(UnicodeScalar(byte)))
            XCTAssertEqual(seen & bit, 0, "bits are distinct")
            seen |= bit
        }
        XCTAssertEqual(seen.nonzeroBitCount, 36)
        XCTAssertEqual(SearchIndex.symbolBit(of: UInt8(ascii: "a")), 1)
        XCTAssertEqual(SearchIndex.symbolBit(of: UInt8(ascii: "z")), 1 << 25)
        XCTAssertEqual(SearchIndex.symbolBit(of: UInt8(ascii: "0")), 1 << 26)
        XCTAssertEqual(SearchIndex.symbolBit(of: UInt8(ascii: "9")), 1 << 35)
        for byte in [0, 0x2F, 0x3A, 0x40, 0x5B, 0x60, 0x7B, 0x80, 0xFF] as [UInt8] {
            XCTAssertEqual(SearchIndex.symbolBit(of: byte), 1 << 63, "\(byte) is not a character of a key")
        }
        XCTAssertEqual(SearchIndex.symbolMask(of: []), 0)
        XCTAssertEqual(SearchIndex.symbolMask(of: Array("aab09".utf8)), 1 | 2 | 1 << 26 | 1 << 35)
    }

    func testAKeyMaskContainsTheMaskOfEverythingInsideIt() throws {
        let index = try CatalogFixture.catalog().searchIndex
        for keyIndex in stride(from: 0, to: index.keyCount, by: 7) {
            let key = index.key(at: keyIndex)
            let mask = index.symbolMasks[keyIndex]
            XCTAssertEqual(mask, SearchIndex.symbolMask(of: key.bytes))
            let inner = Array(key.bytes.dropFirst().prefix(3))
            XCTAssertEqual(SearchIndex.symbolMask(of: inner) & mask, SearchIndex.symbolMask(of: inner))
        }
    }

    // MARK: The index and a plain implementation agree

    /// Queries made from the keys themselves (prefixes, inner pieces, pieces of later words, pieces with a
    /// letter left out) and from nothing in particular, so that every kind of match and every stage of the
    /// scan is exercised.
    private func queries(for index: SearchIndex) -> [[UInt8]] {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var queries: [[UInt8]] = ["a", "e", "1", "m", "ngc", "m31", "sirius", "alpha", "orion", "hd 4", "hip 3", "andgal", "zqx", "cen"]
            .map { SearchText.key(for: $0).bytes }
        #if DEBUG
        let derivedQueryCount = 40
        #else
        let derivedQueryCount = 400
        #endif
        for _ in 0..<derivedQueryCount {
            let key = index.key(at: next(index.keyCount))
            let bytes = key.bytes
            switch next(5) {
            case 0:
                queries.append(Array(bytes.prefix(1 + next(min(bytes.count, 6)))))
            case 1:
                let length = 1 + next(min(bytes.count, 5))
                let start = next(bytes.count - length + 1)
                queries.append(Array(bytes[start..<(start + length)]))
            case 2:
                let words = (0..<bytes.count).filter { key.wordStarts & (1 << UInt64($0)) != 0 }
                let start = words[next(words.count)]
                queries.append(Array(bytes[start...].prefix(1 + next(4))))
            case 3 where bytes.count >= 4:
                var dropped = Array(bytes.prefix(3 + next(5)))
                dropped.remove(at: 1 + next(dropped.count - 1))
                queries.append(dropped)
            default:
                queries.append((0..<(1 + next(5))).map { _ in UInt8(ascii: "a") + UInt8(next(26)) })
            }
        }
        return queries.filter { !$0.isEmpty }
    }

    func testTheScanAgreesWithAPlainImplementationForEveryLimit() throws {
        let catalog = try CatalogFixture.catalog()
        let reference = ReferenceSearch(catalog)
        let index = catalog.searchIndex
        var kinds = Set<CatalogSearchResult.MatchKind>()
        for query in queries(for: index) {
            let expected = reference.matches(for: query)
            kinds.formUnion(expected.map(\.kind))
            for limit in [1, 2, 7, 50, 400, Int.max] {
                let actual = index.search(query, limit: limit).map {
                    ReferenceSearch.Match(object: $0.objectIndex, key: $0.keyIndex, kind: $0.kind)
                }
                let wanted = Array(expected.prefix(limit))
                if actual != wanted {
                    let difference = zip(actual, wanted).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                        ?? min(actual.count, wanted.count)
                    XCTFail("\"\(String(decoding: query, as: UTF8.self))\", limit \(limit): \(actual.count) results instead of \(wanted.count), "
                            + "the first difference is at position \(difference): \(actual.dropFirst(difference).first.map(String.init(describing:)) ?? "none") "
                            + "instead of \(wanted.dropFirst(difference).first.map(String.init(describing:)) ?? "none")")
                }
            }
        }
        XCTAssertEqual(kinds, Set(CatalogSearchResult.MatchKind.allCases), "the queries produce every kind of match")
    }

    func testAShorterLimitGivesTheBeginningOfTheLongerResult() throws {
        let catalog = try CatalogFixture.catalog()
        for query in ["a", "m", "ngc", "alpha", "sirius", "cen", "1", "hip 12", "xqz", "andgal"] {
            let everything = catalog.search(query, limit: Int.max).map(\.object.id)
            for limit in [1, 3, 10, 50, 250] {
                XCTAssertEqual(catalog.search(query, limit: limit).map(\.object.id), Array(everything.prefix(limit)), "\(query), \(limit)")
            }
        }
    }

    func testSearchesOfAnEmptyOrOversizedQueryFindNothing() throws {
        let index = try CatalogFixture.catalog().searchIndex
        XCTAssertTrue(index.search([], limit: 10).isEmpty)
        XCTAssertTrue(index.search(Array(repeating: UInt8(ascii: "a"), count: SearchText.maximumKeyLength + 1), limit: 10).isEmpty)
        XCTAssertTrue(index.search(Array("sirius".utf8), limit: 0).isEmpty)
        XCTAssertTrue(index.search(Array("sirius".utf8), limit: -3).isEmpty)
        XCTAssertEqual(index.search(Array("sirius".utf8), limit: 1).count, 1)
        XCTAssertTrue(index.search([0xFF, 0x00], limit: 10).isEmpty, "bytes that never occur in a key match nothing")
        XCTAssertTrue(index.search(Array("SIRIUS".utf8), limit: 10).isEmpty, "queries are expected to be normalized already")
    }

    func testEveryKeyIsFoundByItself() throws {
        let catalog = try CatalogFixture.catalog()
        let index = catalog.searchIndex
        for keyIndex in stride(from: 0, to: index.keyCount, by: 41) {
            let key = index.key(at: keyIndex)
            let hits = index.search(key.bytes, limit: 5000)
            let owner = index.source(ofKey: keyIndex).object
            XCTAssertTrue(hits.contains { $0.objectIndex == owner && $0.kind == .exact },
                          "\(String(decoding: key.bytes, as: UTF8.self)) should find object \(owner) exactly")
        }
    }
}

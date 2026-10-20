import Foundation
import XCTest
@testable import AppCore

/// A temporary directory and a private defaults suite for one test; `remove()` deletes both.
private final class OnlineCacheTestsSandbox {
    let directory: URL
    let suiteName: String
    let defaults: UserDefaults

    init() {
        let id = UUID().uuidString
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnlineCacheTests-\(id)", isDirectory: true)
        suiteName = "AppCoreTests.OnlineCache.\(id)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The file cache: round trips, the header limit, damaged files, deleting.
final class OnlineCacheTests: XCTestCase {
    /// A whole-second date, so that the JSON round trip of the metadata is exact.
    private let saved = Date(timeIntervalSinceReferenceDate: 814_000_000)
    private let expires = Date(timeIntervalSinceReferenceDate: 814_003_600)
    private let epoch = Date(timeIntervalSinceReferenceDate: 813_900_000)

    private var fullMeta: OnlineCacheMeta {
        OnlineCacheMeta(savedAt: saved, etag: "\"abc123\"", lastModified: "Sun, 18 Oct 2026 19:50:18 GMT", expires: expires,
                        dataEpoch: epoch, key: "32.8,-96.8")
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// A file of the cache format built by hand. `declaredHeader` and `declaredBody` replace the true lengths.
    private func rawFile(magic: [UInt8] = [0x4C, 0x4F, 0x44, 0x31], header: Data, declaredHeader: UInt32? = nil,
                         body: Data?, declaredBody: UInt32? = nil) -> Data {
        var data = Data(magic)
        data.append(contentsOf: bigEndian(declaredHeader ?? UInt32(header.count)))
        data.append(header)
        if let body {
            data.append(contentsOf: bigEndian(declaredBody ?? UInt32(body.count)))
            data.append(body)
        }
        return data
    }

    private var minimalHeader: Data { Data("{\"savedAt\":814000000}".utf8) }

    /// `minimalHeader` padded with spaces (valid JSON) to `length` bytes.
    private func paddedHeader(_ length: Int) -> Data {
        var data = minimalHeader
        data.append(Data(repeating: 0x20, count: length - data.count))
        return data
    }

    private func place(_ box: OnlineCacheTestsSandbox, _ name: String, _ data: Data) throws {
        try FileManager.default.createDirectory(at: box.directory, withIntermediateDirectories: true)
        try data.write(to: box.directory.appendingPathComponent("\(name).cache"))
    }

    // MARK: Round trip

    func testWhatIsWrittenIsReadBack() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let bytes = Data("hello, sky".utf8)
        try cache.write("mpc-comets", bytes: bytes, meta: fullMeta)
        let entry = try XCTUnwrap(cache.read("mpc-comets"))
        XCTAssertEqual(entry.bytes, bytes)
        XCTAssertEqual(entry.meta, fullMeta)
    }

    func testAMinimalMetaRoundTrips() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let meta = OnlineCacheMeta(savedAt: saved)
        try cache.write("a", bytes: Data([1, 2, 3]), meta: meta)
        let entry = try XCTUnwrap(cache.read("a"))
        XCTAssertEqual(entry.meta, meta)
        XCTAssertNil(entry.meta.etag)
        XCTAssertNil(entry.meta.lastModified)
        XCTAssertNil(entry.meta.expires)
        XCTAssertNil(entry.meta.dataEpoch)
        XCTAssertNil(entry.meta.key)
    }

    func testEmptyBytesRoundTrip() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("empty", bytes: Data(), meta: fullMeta)
        let entry = try XCTUnwrap(cache.read("empty"))
        XCTAssertEqual(entry.bytes.count, 0)
        XCTAssertEqual(entry.meta, fullMeta)
    }

    func testLargeBytesRoundTripWithAMultiByteLength() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let bytes = Data((0..<300_000).map { UInt8($0 % 251) })
        try cache.write("big", bytes: bytes, meta: fullMeta)
        let entry = try XCTUnwrap(cache.read("big"))
        XCTAssertEqual(entry.bytes.count, 300_000)
        XCTAssertEqual(entry.bytes, bytes)
    }

    func testAnAlmostFourKilobyteHeaderStillRoundTrips() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        var meta = fullMeta
        meta.etag = String(repeating: "e", count: 3000)
        try cache.write("long-etag", bytes: Data([9]), meta: meta)
        XCTAssertEqual(cache.read("long-etag")?.meta.etag?.count, 3000)
        XCTAssertEqual(cache.readMeta("long-etag"), meta)
    }

    func testWritingAgainReplacesTheEntry() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("x", bytes: Data("first, longer content".utf8), meta: fullMeta)
        let newer = OnlineCacheMeta(savedAt: expires, key: "other")
        try cache.write("x", bytes: Data("2nd".utf8), meta: newer)
        let entry = try XCTUnwrap(cache.read("x"))
        XCTAssertEqual(entry.bytes, Data("2nd".utf8))
        XCTAssertEqual(entry.meta, newer)
    }

    func testEntriesWithDifferentNamesDoNotInterfere() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("one", bytes: Data("1".utf8), meta: OnlineCacheMeta(savedAt: saved))
        try cache.write("two", bytes: Data("2".utf8), meta: OnlineCacheMeta(savedAt: expires))
        XCTAssertEqual(cache.read("one")?.bytes, Data("1".utf8))
        XCTAssertEqual(cache.read("two")?.bytes, Data("2".utf8))
        cache.delete("one")
        XCTAssertNil(cache.read("one"))
        XCTAssertEqual(cache.read("two")?.bytes, Data("2".utf8))
    }

    func testTheDirectoryIsCreatedOnTheFirstWrite() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let nested = box.directory.appendingPathComponent("a", isDirectory: true).appendingPathComponent("b", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        try OnlineCache(directory: nested).write("x", bytes: Data([1]), meta: fullMeta)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("x.cache").path))
    }

    func testEveryResourceKeyIsAValidFileName() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        for resource in OnlineResource.allCases {
            try cache.write(resource.key, bytes: Data(resource.key.utf8), meta: fullMeta)
            XCTAssertEqual(cache.read(resource.key)?.bytes, Data(resource.key.utf8), "\(resource)")
        }
    }

    // MARK: Missing and invalid names

    func testNothingIsCachedInAnEmptyCache() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        XCTAssertNil(cache.read("anything"))
        XCTAssertNil(cache.readMeta("anything"))
    }

    func testOnlyLowercaseLettersDigitsAndHyphensMakeAName() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        for name in ["", "UPPER", "with space", "a/b", "../escape", "dot.name", "under_score", "caf\u{00E9}", "tab\t"] {
            XCTAssertThrowsError(try cache.write(name, bytes: Data([1]), meta: fullMeta), "name: \(name)")
            XCTAssertNil(cache.read(name), "name: \(name)")
            XCTAssertNil(cache.readMeta(name), "name: \(name)")
        }
        XCTAssertNoThrow(try cache.write("a-b-1", bytes: Data([1]), meta: fullMeta))
    }

    func testANameOfFortyOneCharactersIsTheLongestAllowed() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let longest = String(repeating: "a", count: 41)
        try cache.write(longest, bytes: Data([7]), meta: fullMeta)
        XCTAssertEqual(cache.read(longest)?.bytes, Data([7]))
        XCTAssertThrowsError(try cache.write(longest + "a", bytes: Data([7]), meta: fullMeta))
    }

    func testAnInvalidNameWritesNothing() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        XCTAssertThrowsError(try cache.write("../escape", bytes: Data([1]), meta: fullMeta))
        XCTAssertFalse(FileManager.default.fileExists(atPath: box.directory.deletingLastPathComponent()
            .appendingPathComponent("escape.cache").path))
    }

    func testAWriteFailsWhenTheDirectoryCannotBeCreated() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        try FileManager.default.createDirectory(at: box.directory, withIntermediateDirectories: true)
        let blocker = box.directory.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let cache = OnlineCache(directory: blocker.appendingPathComponent("sub", isDirectory: true))
        XCTAssertThrowsError(try cache.write("x", bytes: Data([1]), meta: fullMeta))
        XCTAssertNil(cache.read("x"))
    }

    // MARK: Metadata only

    func testReadMetaReturnsTheMetadataWithoutTheBytes() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("m", bytes: Data(repeating: 0xAB, count: 5000), meta: fullMeta)
        XCTAssertEqual(cache.readMeta("m"), fullMeta)
    }

    func testReadMetaStillWorksWhenOnlyTheBodyIsCutShort() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("cut", bytes: Data(repeating: 1, count: 100), meta: fullMeta)
        let url = box.directory.appendingPathComponent("cut.cache")
        let whole = try Data(contentsOf: url)
        try whole.dropLast(10).write(to: url)
        XCTAssertNil(cache.read("cut"))
        XCTAssertEqual(cache.readMeta("cut"), fullMeta)
    }

    // MARK: Damaged files

    func testAFileCutShortIsNotRead() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("short", bytes: Data("0123456789".utf8), meta: fullMeta)
        let url = box.directory.appendingPathComponent("short.cache")
        let whole = try Data(contentsOf: url)
        try whole.dropLast().write(to: url)
        XCTAssertNil(cache.read("short"))
    }

    func testAFileWithExtraBytesIsNotRead() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("long", bytes: Data("0123456789".utf8), meta: fullMeta)
        let url = box.directory.appendingPathComponent("long.cache")
        var whole = try Data(contentsOf: url)
        whole.append(0x00)
        try whole.write(to: url)
        XCTAssertNil(cache.read("long"))
    }

    func testEveryTruncationOfAFileIsRejected() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("t", bytes: Data("abcdef".utf8), meta: OnlineCacheMeta(savedAt: saved))
        let url = box.directory.appendingPathComponent("t.cache")
        let whole = try Data(contentsOf: url)
        for length in 0..<whole.count {
            try whole.prefix(length).write(to: url)
            XCTAssertNil(cache.read("t"), "length \(length)")
        }
        try whole.write(to: url)
        XCTAssertEqual(cache.read("t")?.bytes, Data("abcdef".utf8))
    }

    func testAFileWithTheWrongMagicIsNotRead() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let good = rawFile(header: minimalHeader, body: Data("x".utf8))
        try place(box, "good", good)
        XCTAssertEqual(cache.read("good")?.bytes, Data("x".utf8))
        let bad = rawFile(magic: [0x4C, 0x4F, 0x44, 0x32], header: minimalHeader, body: Data("x".utf8))
        try place(box, "bad", bad)
        XCTAssertNil(cache.read("bad"))
        XCTAssertNil(cache.readMeta("bad"))
    }

    func testAFileShorterThanTheFixedPrefixIsNotRead() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "tiny", Data([0x4C, 0x4F, 0x44, 0x31, 0, 0, 0]))
        XCTAssertNil(cache.read("tiny"))
        XCTAssertNil(cache.readMeta("tiny"))
        try place(box, "zero", Data())
        XCTAssertNil(cache.read("zero"))
        XCTAssertNil(cache.readMeta("zero"))
    }

    func testTheHeaderMayBeUpToFourKilobytes() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "limit", rawFile(header: paddedHeader(4096), body: Data("body".utf8)))
        let entry = try XCTUnwrap(cache.read("limit"))
        XCTAssertEqual(entry.bytes, Data("body".utf8))
        XCTAssertEqual(entry.meta, OnlineCacheMeta(savedAt: saved))
        XCTAssertEqual(cache.readMeta("limit"), OnlineCacheMeta(savedAt: saved))
    }

    func testAHeaderOverFourKilobytesIsRefused() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "over", rawFile(header: paddedHeader(4097), body: Data("body".utf8)))
        XCTAssertNil(cache.read("over"))
        XCTAssertNil(cache.readMeta("over"))
    }

    func testAHeaderLengthOutsideTwoToFourThousandNinetySixIsRefused() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let lengths: [UInt32] = [0, 1, 4097, 100_000, UInt32.max]
        for length in lengths {
            let name = "len-\(length)"
            try place(box, name, rawFile(header: minimalHeader, declaredHeader: length, body: Data("x".utf8)))
            XCTAssertNil(cache.read(name), name)
            XCTAssertNil(cache.readMeta(name), name)
        }
    }

    func testAHeaderLongerThanTheFileIsRefused() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "claims", rawFile(header: minimalHeader, declaredHeader: 500, body: nil))
        XCTAssertNil(cache.read("claims"))
        XCTAssertNil(cache.readMeta("claims"))
    }

    func testAHeaderThatIsNotMetadataIsRefused() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let garbage = Data("this is not json at all".utf8)
        try place(box, "garbage", rawFile(header: garbage, body: Data("x".utf8)))
        XCTAssertNil(cache.read("garbage"))
        XCTAssertNil(cache.readMeta("garbage"))
        // Valid JSON without the required time stamp.
        try place(box, "nodate", rawFile(header: Data("{}".utf8), body: Data("x".utf8)))
        XCTAssertNil(cache.read("nodate"))
        XCTAssertNil(cache.readMeta("nodate"))
    }

    func testABodyLengthThatDoesNotMatchTheFileIsRefused() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "more", rawFile(header: minimalHeader, body: Data("12345".utf8), declaredBody: 6))
        XCTAssertNil(cache.read("more"))
        try place(box, "less", rawFile(header: minimalHeader, body: Data("12345".utf8), declaredBody: 4))
        XCTAssertNil(cache.read("less"))
        try place(box, "exact", rawFile(header: minimalHeader, body: Data("12345".utf8), declaredBody: 5))
        XCTAssertEqual(cache.read("exact")?.bytes, Data("12345".utf8))
    }

    func testAFileThatEndsAfterTheHeaderIsNotRead() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "nobody", rawFile(header: minimalHeader, body: nil))
        XCTAssertNil(cache.read("nobody"))
        XCTAssertEqual(cache.readMeta("nobody"), OnlineCacheMeta(savedAt: saved))
    }

    func testABodyLengthWithTheHighBitSetIsRefusedWithoutCrashing() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try place(box, "huge", rawFile(header: minimalHeader, body: Data("x".utf8), declaredBody: 0xFFFF_FFFF))
        XCTAssertNil(cache.read("huge"))
    }

    // MARK: Update metadata

    func testUpdateMetaKeepsTheBytes() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let bytes = Data("payload".utf8)
        try cache.write("u", bytes: bytes, meta: fullMeta)
        var newer = fullMeta
        newer.savedAt = expires
        newer.expires = nil
        XCTAssertTrue(try cache.updateMeta("u", meta: newer))
        let entry = try XCTUnwrap(cache.read("u"))
        XCTAssertEqual(entry.bytes, bytes)
        XCTAssertEqual(entry.meta, newer)
    }

    func testUpdateMetaOfNothingReturnsFalse() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        XCTAssertFalse(try cache.updateMeta("none", meta: fullMeta))
        XCTAssertNil(cache.read("none"))
    }

    func testUpdateMetaOfADamagedFileReturnsFalseAndLeavesItAlone() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        let damaged = rawFile(header: minimalHeader, body: Data("12345".utf8), declaredBody: 99)
        try place(box, "dmg", damaged)
        XCTAssertFalse(try cache.updateMeta("dmg", meta: fullMeta))
        XCTAssertEqual(try Data(contentsOf: box.directory.appendingPathComponent("dmg.cache")), damaged)
    }

    // MARK: Delete

    func testDeleteRemovesTheFile() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        try cache.write("d", bytes: Data([1]), meta: fullMeta)
        let url = box.directory.appendingPathComponent("d.cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        cache.delete("d")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(cache.read("d"))
        XCTAssertNil(cache.readMeta("d"))
    }

    func testDeletingWhatIsNotThereOrHasAnInvalidNameIsHarmless() throws {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let cache = OnlineCache(directory: box.directory)
        cache.delete("missing")
        cache.delete("")
        cache.delete("../x")
        try cache.write("keep", bytes: Data([1]), meta: fullMeta)
        cache.delete("Keep")
        XCTAssertEqual(cache.read("keep")?.bytes, Data([1]))
    }
}

/// The small persistent values: switches, explanation flag, last attempt, retry wait.
final class OnlineStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_300_000)

    func testEveryFeedIsOffUntilSwitchedOn() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        for feed in OnlineFeed.allCases {
            XCTAssertFalse(store.isEnabled(feed), "\(feed)")
        }
    }

    func testSwitchesAreIndependentAndPersistent() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        store.setEnabled(.comets, true)
        store.setEnabled(.clouds, true)
        XCTAssertTrue(store.isEnabled(.comets))
        XCTAssertTrue(store.isEnabled(.clouds))
        XCTAssertFalse(store.isEnabled(.satellites))
        XCTAssertFalse(store.isEnabled(.starlink))
        // A second store on the same defaults (the next launch) sees the same switches.
        let next = OnlineStore(defaults: box.defaults)
        XCTAssertTrue(next.isEnabled(.comets))
        XCTAssertFalse(next.isEnabled(.starlink))
        store.setEnabled(.comets, false)
        XCTAssertFalse(next.isEnabled(.comets))
        XCTAssertTrue(next.isEnabled(.clouds))
    }

    func testTheSwitchIsStoredUnderTheDocumentedKey() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        store.setEnabled(.satellites, true)
        XCTAssertTrue(box.defaults.bool(forKey: "lodestar.online.enabled.satellites"))
        XCTAssertFalse(box.defaults.bool(forKey: "lodestar.online.enabled.starlink"))
    }

    func testTheExplanationFlag() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        XCTAssertFalse(store.hasExplained)
        store.hasExplained = true
        XCTAssertTrue(store.hasExplained)
        XCTAssertTrue(OnlineStore(defaults: box.defaults).hasExplained)
        store.hasExplained = false
        XCTAssertFalse(OnlineStore(defaults: box.defaults).hasExplained)
    }

    func testTheLastAttemptIsRememberedPerResource() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        for resource in OnlineResource.allCases {
            XCTAssertNil(store.lastAttempt(resource), "\(resource)")
        }
        store.setLastAttempt(.stations, date)
        XCTAssertEqual(store.lastAttempt(.stations), date)
        XCTAssertNil(store.lastAttempt(.visual))
        XCTAssertEqual(OnlineStore(defaults: box.defaults).lastAttempt(.stations), date)
    }

    func testSettingNoAttemptRemovesIt() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        store.setLastAttempt(.comets, date)
        store.setLastAttempt(.comets, nil)
        XCTAssertNil(store.lastAttempt(.comets))
    }

    func testTheAttemptSurvivesSwitchingTheFeedOff() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        store.setEnabled(.comets, true)
        store.setLastAttempt(.comets, date)
        store.setEnabled(.comets, false)
        XCTAssertEqual(store.lastAttempt(.comets), date)
    }

    func testTheFailureFlagIsRememberedPerResource() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        XCTAssertFalse(store.lastAttemptFailed(.forecast))
        store.setLastAttemptFailed(.forecast, true)
        XCTAssertTrue(store.lastAttemptFailed(.forecast))
        XCTAssertFalse(store.lastAttemptFailed(.comets))
        store.setLastAttemptFailed(.forecast, false)
        XCTAssertFalse(store.lastAttemptFailed(.forecast))
    }

    func testTheRetryWaitIsOptionalAndPerResource() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        XCTAssertNil(store.retryWait(.visual))
        store.setRetryWait(.visual, 5400)
        XCTAssertEqual(store.retryWait(.visual), 5400)
        XCTAssertNil(store.retryWait(.stations))
        store.setRetryWait(.visual, nil)
        XCTAssertNil(store.retryWait(.visual))
    }

    func testAZeroRetryWaitIsStoredAsZeroNotAsNone() {
        let box = OnlineCacheTestsSandbox()
        defer { box.remove() }
        let store = OnlineStore(defaults: box.defaults)
        store.setRetryWait(.visual, 0)
        XCTAssertEqual(store.retryWait(.visual), 0)
    }
}

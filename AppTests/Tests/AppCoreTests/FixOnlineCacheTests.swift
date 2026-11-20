import Foundation
import XCTest
@testable import AppCore

/// What the cache writes can always be read back: the reader refuses a header over 4096 bytes, so the writer drops the
/// validators (`ETag`, `Last-Modified`) of a header that would be longer, and keeps the data and the dates.
final class FixOnlineCacheTests: XCTestCase {
    /// Whole-second dates, so that the JSON round trip of the metadata is exact.
    private let saved = Date(timeIntervalSinceReferenceDate: 814_000_000)
    private let expires = Date(timeIntervalSinceReferenceDate: 814_003_600)
    private let epoch = Date(timeIntervalSinceReferenceDate: 813_900_000)
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FixOnlineCacheTests-\(UUID().uuidString)",
                                                                                  isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func meta(etag: String?, lastModified: String? = nil) -> OnlineCacheMeta {
        OnlineCacheMeta(savedAt: saved, etag: etag, lastModified: lastModified, expires: expires, dataEpoch: epoch,
                        key: "32.8,-96.8")
    }

    private func longText(_ length: Int) -> String { String(repeating: "a", count: length) }

    func testAnOversizedETagLeavesTheDataReadable() throws {
        let cache = OnlineCache(directory: directory)
        let bytes = Data("the forecast".utf8)
        try cache.write("met-forecast", bytes: bytes, meta: meta(etag: "\"" + longText(5000) + "\""))
        // A new cache value stands for the next launch.
        let entry = try XCTUnwrap(OnlineCache(directory: directory).read("met-forecast"))
        XCTAssertEqual(entry.bytes, bytes)
        XCTAssertNil(entry.meta.etag)
        XCTAssertNil(entry.meta.lastModified)
        XCTAssertEqual(entry.meta.savedAt, saved)
        XCTAssertEqual(entry.meta.expires, expires)
        XCTAssertEqual(entry.meta.dataEpoch, epoch)
        XCTAssertEqual(entry.meta.key, "32.8,-96.8")
    }

    func testAnOversizedLastModifiedLeavesTheDataReadable() throws {
        let cache = OnlineCache(directory: directory)
        let bytes = Data("the comets".utf8)
        try cache.write("mpc-comets", bytes: bytes, meta: meta(etag: "\"small\"", lastModified: longText(4500)))
        let entry = try XCTUnwrap(cache.read("mpc-comets"))
        XCTAssertEqual(entry.bytes, bytes)
        // Both validators go: they belong together, and half of a pair is worth little.
        XCTAssertNil(entry.meta.etag)
        XCTAssertNil(entry.meta.lastModified)
        XCTAssertEqual(entry.meta.savedAt, saved)
        XCTAssertEqual(entry.meta.expires, expires)
    }

    func testTheMetadataOfAnOversizedHeaderCanBeReadWithoutTheBytes() throws {
        let cache = OnlineCache(directory: directory)
        try cache.write("met-forecast", bytes: Data("x".utf8), meta: meta(etag: longText(9000)))
        let read = try XCTUnwrap(cache.readMeta("met-forecast"))
        XCTAssertEqual(read, meta(etag: nil))
    }

    func testAHeaderThatFitsKeepsItsValidators() throws {
        let cache = OnlineCache(directory: directory)
        let full = meta(etag: "\"" + longText(2000) + "\"", lastModified: "Sun, 18 Oct 2026 19:50:18 GMT")
        try cache.write("celestrak-stations", bytes: Data("x".utf8), meta: full)
        XCTAssertEqual(cache.read("celestrak-stations")?.meta, full)
    }

    func testReplacingTheMetadataWithAnOversizedOneKeepsTheBytes() throws {
        let cache = OnlineCache(directory: directory)
        let bytes = Data("kept".utf8)
        try cache.write("mpc-comets", bytes: bytes, meta: meta(etag: "\"first\""))
        XCTAssertTrue(try cache.updateMeta("mpc-comets", meta: meta(etag: nil, lastModified: longText(6000))))
        let entry = try XCTUnwrap(cache.read("mpc-comets"))
        XCTAssertEqual(entry.bytes, bytes)
        XCTAssertNil(entry.meta.lastModified)
    }
}

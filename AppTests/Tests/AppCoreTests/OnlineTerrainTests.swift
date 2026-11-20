import Foundation
import LodestarKit
import XCTest
@testable import AppCore

/// `TerrainHorizonLoader` (Services/TerrainHorizonLoader.swift): fetching the elevation tiles around a site. The downloads
/// are scripted; the inflating of a real tile needs the Compression framework and a real tile file, so it is not run here.
final class OnlineTerrainTests: XCTestCase {
    private let place = GeographicLocation(latitude: 47.5, longitude: 8.5, elevation: 400)

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlineTerrainTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// What the scripted download was asked for, and what the loader reported.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var urlList: [URL] = []
        private var progressList: [TerrainHorizonLoader.Progress] = []

        func add(_ url: URL) { lock.lock(); urlList.append(url); lock.unlock() }
        func add(_ progress: TerrainHorizonLoader.Progress) { lock.lock(); progressList.append(progress); lock.unlock() }
        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return urlList }
        var progress: [TerrainHorizonLoader.Progress] { lock.lock(); defer { lock.unlock() }; return progressList }
    }

    private func loader(_ log: Log, answer: @escaping @Sendable (URL) -> OnlineResult) -> TerrainHorizonLoader {
        TerrainHorizonLoader(directory: directory) { url in
            log.add(url)
            return answer(url)
        }
    }

    private func fetch(_ loader: TerrainHorizonLoader, _ log: Log,
                       isCancelled: @escaping @Sendable () async -> Bool = { false }) async -> TerrainHorizonLoader.Outcome {
        await loader.fetchTiles(for: place, progress: { log.add($0) }, isCancelled: isCancelled)
    }

    private func failureText(_ outcome: TerrainHorizonLoader.Outcome) -> String? {
        if case .failed(let text) = outcome { return text }
        return nil
    }

    private var wanted: [TerrainTileKey] { Array(TerrainHorizon.requiredTiles(at: place).prefix(TerrainHorizonLoader.maximumTiles)) }

    // MARK: Constants

    func testTheTilesComeFromTheAWSOpenDataTerrainTiles() {
        XCTAssertEqual(TerrainHorizonLoader.baseURL, "https://s3.amazonaws.com/elevation-tiles-prod/skadi/")
        XCTAssertEqual(TerrainHorizonLoader.maximumTiles, 4)
        XCTAssertEqual(TerrainHorizonLoader.maximumTileBytes, 40 * 1024 * 1024)
    }

    func testTheTilesAreKeptInTheCachesFolderOfTheApp() {
        XCTAssertEqual(TerrainHorizonLoader.standardDirectory().lastPathComponent, "TerrainTiles")
    }

    // MARK: Fetching

    func testTheNearestTilesAreAskedForOneByOneAtMostFour() async {
        let log = Log()
        let outcome = await fetch(loader(log) { _ in .failed(.httpError, statusCode: 404) }, log)
        XCTAssertEqual(log.urls.map(\.absoluteString), wanted.map { TerrainHorizonLoader.baseURL + $0.path })
        XCTAssertLessThanOrEqual(log.urls.count, TerrainHorizonLoader.maximumTiles)
        XCTAssertEqual(failureText(outcome), "No elevation data is available for this place.",
                       "a place without any tile has no terrain")
    }

    func testTheProgressNamesEachTileThatIsDownloaded() async {
        let log = Log()
        _ = await fetch(loader(log) { _ in .failed(.httpError, statusCode: 404) }, log)
        let count = wanted.count
        XCTAssertEqual(log.progress, wanted.enumerated().map { .downloading(index: $0.offset + 1, count: count, tile: $0.element) })
    }

    func testAnotherFailureStopsTheDownloadAndSaysWhichTile() async throws {
        let log = Log()
        let outcome = await fetch(loader(log) { _ in .failed(.timeout, statusCode: nil) }, log)
        let first = try XCTUnwrap(wanted.first)
        XCTAssertEqual(failureText(outcome),
                       "The elevation tile \(first.name) could not be downloaded. \(OnlineFailure.timeout.message(statusCode: nil))")
        XCTAssertEqual(log.urls.count, 1)
    }

    func testAnAnswerThatSaysNothingChangedIsAFailureHere() async {
        let log = Log()
        let outcome = await fetch(loader(log) { _ in .notModified(expires: nil) }, log)
        XCTAssertEqual(failureText(outcome), OnlineFailure.empty.message())
    }

    func testAFileThatIsNotATileIsRefusedAndTheProgressSaysItWasBeingRead() async throws {
        let log = Log()
        let outcome = await fetch(loader(log) { _ in
            .downloaded(bytes: Data("this is not a gzip file".utf8), etag: nil, lastModified: nil, expires: nil)
        }, log)
        XCTAssertEqual(failureText(outcome), "The file is not a gzip file.")
        let first = try XCTUnwrap(wanted.first)
        XCTAssertEqual(log.progress, [.downloading(index: 1, count: wanted.count, tile: first),
                                      .reading(index: 1, count: wanted.count, tile: first)])
    }

    func testTheCacheFolderIsEmptyAfterwards() async {
        let log = Log()
        _ = await fetch(loader(log) { _ in
            .downloaded(bytes: Data("junk".utf8), etag: nil, lastModified: nil, expires: nil)
        }, log)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(left.isEmpty, "\(left)")
    }

    func testTheTaskCanBeCancelledBetweenTheTiles() async {
        let log = Log()
        let outcome = await fetch(loader(log) { _ in .failed(.httpError, statusCode: 404) }, log,
                                  isCancelled: { true })
        guard case .cancelled = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(log.urls.isEmpty, "nothing is downloaded once it is cancelled")
    }

    func testACancelledTaskDownloadsNothing() async {
        let log = Log()
        let loader = loader(log) { _ in .failed(.httpError, statusCode: 404) }
        let task = Task { await self.fetch(loader, log) }
        task.cancel()
        let outcome = await task.value
        if case .cancelled = outcome {
            XCTAssertTrue(log.urls.isEmpty)
        } else {
            // The task may have run to its end before it saw the cancellation; it must then have ended in the usual way.
            XCTAssertEqual(failureText(outcome), "No elevation data is available for this place.")
        }
    }

    func testLeftoversOfAnInterruptedDownloadAreDeleted() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: directory.appendingPathComponent("N47E008.hgt.gz"))
        let log = Log()
        loader(log) { _ in .failed(.httpError, statusCode: 404) }.deleteLeftovers()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testTheInflaterRefusesAFileThatIsNotGzip() {
        XCTAssertThrowsError(try TerrainTileInflater.inflate(Data("not gzip".utf8))) {
            XCTAssertEqual(($0 as? TerrainTileFailure)?.message, "The file is not a gzip file.")
        }
    }
}

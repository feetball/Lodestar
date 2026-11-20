import Compression
import Foundation
import LodestarKit

/// Why a tile file could not be turned into elevations.
struct TerrainTileFailure: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// Inflates a Skadi tile file (`N47E008.hgt.gz`). The engine finds the DEFLATE data and the size it must have
/// (`GzipHeader`); the `Compression` framework (`COMPRESSION_ZLIB` is raw DEFLATE) does the rest, into a buffer of exactly
/// the size of a tile plus one byte, so a damaged or hostile file cannot make the app allocate more.
enum TerrainTileInflater {
    private static let highResolutionBytes = TerrainTile.highResolutionSamples * TerrainTile.highResolutionSamples * 2
    private static let lowResolutionBytes = TerrainTile.lowResolutionSamples * TerrainTile.lowResolutionSamples * 2

    /// The inflated file; throws `TerrainTileFailure` when `gzip` is not a gzip file of a tile or its data is damaged.
    static func inflate(_ gzip: Data) throws -> Data {
        guard let payload = GzipHeader.payloadRange(of: gzip) else { throw TerrainTileFailure("The file is not a gzip file.") }
        guard let size = GzipHeader.uncompressedLength(of: gzip), size == highResolutionBytes || size == lowResolutionBytes else {
            throw TerrainTileFailure("The file is not an elevation tile.")
        }
        // One byte more than a tile: a file that goes on after its size shows by filling it.
        var output = Data(count: size + 1)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            gzip.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let out = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(out, destination.count, input + payload.lowerBound, payload.count, nil,
                                                 COMPRESSION_ZLIB)
            }
        }
        guard written >= size else { throw TerrainTileFailure("The elevation tile is shorter than it should be, or damaged.") }
        guard written == size else { throw TerrainTileFailure("The elevation tile is longer than it should be.") }
        output.removeLast()
        return output
    }
}

/// What `OnlineDataService.computeTerrainHorizon` came to.
enum TerrainComputation: Sendable {
    /// The terrain horizon, worked out from `tilesUsed` tiles; `unavailable` lists the needed tiles the provider has no file
    /// for. `TerrainHorizonResult.missingTiles` has those and the tiles beyond the nearest
    /// `TerrainHorizonLoader.maximumTiles`.
    case done(TerrainHorizonResult, tilesUsed: Int, unavailable: [TerrainTileKey])
    /// Nothing was computed; the text says why.
    case failed(String)
    /// The user cancelled, or the feed was switched off.
    case cancelled
}

/// Downloads the elevation tiles around a site (the optional "Terrain horizons" feed). The tiles of the AWS Open Data
/// Terrain Tiles come one by one from `baseURL`, each is stored in `directory` (the app's caches), inflated, read and
/// deleted; nothing stays on the phone. At most `maximumTiles` tiles are fetched, the nearest to the site first; the engine
/// reports the others as missing.
struct TerrainHorizonLoader: Sendable {
    /// What the loader is doing, for the progress line.
    enum Progress: Equatable, Sendable {
        /// Downloading tile `index` (1-based) of `count`.
        case downloading(index: Int, count: Int, tile: TerrainTileKey)
        /// Inflating and reading tile `index` of `count`.
        case reading(index: Int, count: Int, tile: TerrainTileKey)
    }

    /// The result of `fetchTiles`.
    enum Outcome: Sendable {
        /// The tiles that could be fetched, and the needed ones the provider has no file for (HTTP 404).
        case tiles([TerrainTile], unavailable: [TerrainTileKey])
        /// Nothing usable arrived; the text says why.
        case failed(String)
        /// The task was cancelled, or `isCancelled` became true.
        case cancelled
    }

    /// The address of the tile set: tiles are `skadi/N47/N47E008.hgt.gz` below it.
    static let baseURL = "https://s3.amazonaws.com/elevation-tiles-prod/skadi/"
    /// The most tiles one computation downloads (about 11 MB each).
    static let maximumTiles = 4
    /// The most bytes a tile file may have; the largest seen is about 11 MB, the sea and the plains compress to less.
    static let maximumTileBytes = 40 * 1024 * 1024

    /// Where the tile files are kept while they are used: a folder of the app's caches.
    let directory: URL
    /// Downloads one address.
    let fetch: @Sendable (URL) async -> OnlineResult
    let baseURL: String

    init(directory: URL = TerrainHorizonLoader.standardDirectory(), baseURL: String = TerrainHorizonLoader.baseURL,
         fetch: @escaping @Sendable (URL) async -> OnlineResult) {
        self.directory = directory
        self.baseURL = baseURL
        self.fetch = fetch
    }

    /// Caches/TerrainTiles.
    static func standardDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TerrainTiles", isDirectory: true)
    }

    /// Fetches the tiles `TerrainHorizon.requiredTiles` lists for `location`, at most `maximumTiles`. `isCancelled` is asked
    /// between the steps (besides the cancellation of the task, which also stops a download that is under way).
    func fetchTiles(for location: GeographicLocation, progress: @Sendable (Progress) -> Void,
                    isCancelled: @Sendable () async -> Bool) async -> Outcome {
        let wanted = Array(TerrainHorizon.requiredTiles(at: location).prefix(Self.maximumTiles))
        var tiles: [TerrainTile] = []
        var unavailable: [TerrainTileKey] = []
        deleteLeftovers()
        defer { deleteLeftovers() }
        for (position, key) in wanted.enumerated() {
            if Task.isCancelled { return .cancelled }
            if await isCancelled() { return .cancelled }
            progress(.downloading(index: position + 1, count: wanted.count, tile: key))
            guard let url = URL(string: baseURL + key.path) else { return .failed(OnlineFailure.insecure.message()) }
            let file = directory.appendingPathComponent("\(key.name).hgt.gz", isDirectory: false)
            switch await fetch(url) {
            case .downloaded(let bytes, _, _, _):
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try bytes.write(to: file, options: .atomic)
                } catch {
                    return .failed(OnlineFailure.storage.message())
                }
            case .failed(let failure, let status, _):
                if Task.isCancelled { return .cancelled }
                if status == 404 {
                    unavailable.append(key)
                    continue
                }
                return .failed("The elevation tile \(key.name) could not be downloaded. \(failure.message(statusCode: status))")
            case .notModified:
                return .failed(OnlineFailure.empty.message())
            }
            if Task.isCancelled { return .cancelled }
            progress(.reading(index: position + 1, count: wanted.count, tile: key))
            do {
                let gzip = try Data(contentsOf: file, options: [.mappedIfSafe])
                let inflated = try TerrainTileInflater.inflate(gzip)
                let tile = try TerrainTile.parse(latitude: key.latitude, longitude: key.longitude, bytes: inflated)
                tiles.append(tile)
            } catch let failure as TerrainTileFailure {
                return .failed(failure.message)
            } catch let error as TerrainTileError {
                return .failed(error.errorDescription ?? OnlineFailure.unreadable.message())
            } catch {
                return .failed(OnlineFailure.storage.message())
            }
            try? FileManager.default.removeItem(at: file)
        }
        guard !tiles.isEmpty else { return .failed("No elevation data is available for this place.") }
        return .tiles(tiles, unavailable: unavailable)
    }

    /// Deletes what a download that was cut short (the app was closed) left in the cache folder.
    func deleteLeftovers() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

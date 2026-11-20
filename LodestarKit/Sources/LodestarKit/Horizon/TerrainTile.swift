import Foundation

/// Names one 1° × 1° elevation tile by the whole-degree latitude and longitude of its south-west corner, the way the
/// Skadi tile set does: `N47E008` covers 47–48° N, 8–9° E.
public struct TerrainTileKey: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The latitude of the south-west corner, −90…89.
    public let latitude: Int
    /// The longitude of the south-west corner, −180…179.
    public let longitude: Int

    /// The key of the corner `latitude`, `longitude` (whole degrees), or `nil` when it is outside −90…89, −180…179.
    public init?(latitude: Int, longitude: Int) {
        guard (-90...89).contains(latitude), (-180...179).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The key of the tile that contains the point, or `nil` at the north pole or the antimeridian's east side (latitude
    /// 90°, longitude 180°), outside −90…90, −180…180, or for a value that is not finite.
    public static func containing(latitude: Double, longitude: Double) -> TerrainTileKey? {
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
        return TerrainTileKey(latitude: Int(latitude.rounded(.down)), longitude: Int(longitude.rounded(.down)))
    }

    /// The Skadi name: `N47E008`, `S34W071`, `N00E000`.
    public var name: String {
        let northSouth = latitude < 0 ? "S" : "N"
        let eastWest = longitude < 0 ? "W" : "E"
        return "\(northSouth)\(Self.padded(abs(latitude), width: 2))\(eastWest)\(Self.padded(abs(longitude), width: 3))"
    }

    /// The path of the tile's file in the tile set, below its base address: `N47/N47E008.hgt.gz`.
    public var path: String { "\(name.prefix(3))/\(name).hgt.gz" }

    /// Orders by latitude, then by longitude.
    public static func < (a: TerrainTileKey, b: TerrainTileKey) -> Bool {
        a.latitude != b.latitude ? a.latitude < b.latitude : a.longitude < b.longitude
    }

    public var description: String { name }

    private static func padded(_ value: Int, width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(width - text.count, 0)) + text
    }
}

/// Why bytes could not be read as a terrain tile.
public enum TerrainTileError: Error, Hashable, Sendable, LocalizedError {
    /// The corner is outside latitude −90…89 or longitude −180…179.
    case invalidOrigin(latitude: Int, longitude: Int)
    /// The data is not 3601 × 3601 or 1201 × 1201 samples of two bytes.
    case unsupportedSize(byteCount: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidOrigin(let latitude, let longitude):
            return "The tile corner \(latitude), \(longitude) is not a valid tile."
        case .unsupportedSize(let byteCount):
            return "\(byteCount) bytes are not a 3601 \u{00D7} 3601 or 1201 \u{00D7} 1201 elevation tile."
        }
    }
}

/// One 1° × 1° tile of a digital elevation model in the SRTM `.hgt` layout, which the Skadi tile set of the AWS Open
/// Data Terrain Tiles uses: 3601 × 3601 (1 arc-second) or 1201 × 1201 (3 arc-second) big-endian signed 16-bit
/// elevations in metres, row by row from the northern edge to the southern edge and west to east in a row. The edge
/// samples lie on the tile's border, so neighbouring tiles repeat each other's edge.
///
/// A sample of −32768 is a void (no data), and so is anything outside −500…9000 m, which no place on land reaches.
/// The samples are kept in one `[Int16]` (26 MB for 3601 × 3601), which copies are shared. The tile is immutable.
public struct TerrainTile: Sendable {
    /// The samples along one side of a 1 arc-second tile.
    public static let highResolutionSamples = 3601
    /// The samples along one side of a 3 arc-second tile.
    public static let lowResolutionSamples = 1201
    /// The value of a sample without data.
    public static let voidSample = -32768
    /// The lowest elevation in metres that counts as data (the Dead Sea shore is near −430 m).
    public static let lowestElevation = -500
    /// The highest elevation in metres that counts as data (Mount Everest is 8849 m).
    public static let highestElevation = 9000

    /// The tile's name in the tile set.
    public let key: TerrainTileKey
    /// The number of samples along one side: 3601 or 1201.
    public let samplesPerSide: Int
    /// How many samples are voids.
    public let voidCount: Int

    private let samples: [Int16]

    private init(key: TerrainTileKey, samplesPerSide: Int, voidCount: Int, samples: [Int16]) {
        self.key = key
        self.samplesPerSide = samplesPerSide
        self.voidCount = voidCount
        self.samples = samples
    }

    /// The latitude of the south-west corner in whole degrees, −90…89.
    public var latitude: Int { key.latitude }

    /// The longitude of the south-west corner in whole degrees, −180…179.
    public var longitude: Int { key.longitude }

    /// Reads a tile whose south-west corner is `latitude`, `longitude` (whole degrees) from the inflated file
    /// `bytes`. Samples outside `lowestElevation`…`highestElevation` become voids.
    ///
    /// Cost: one pass over the bytes (13 million samples for a 1 arc-second tile) and one allocation, the 26 MB
    /// sample array (1201 × 1201: 2.9 MB). Call it off the main thread.
    ///
    /// - Throws: `TerrainTileError.invalidOrigin` when the corner is not a valid tile, and
    ///   `TerrainTileError.unsupportedSize` when `bytes` is not exactly one of the two sizes.
    public static func parse(latitude: Int, longitude: Int, bytes: Data) throws -> TerrainTile {
        guard let key = TerrainTileKey(latitude: latitude, longitude: longitude) else {
            throw TerrainTileError.invalidOrigin(latitude: latitude, longitude: longitude)
        }
        let side: Int
        switch bytes.count {
        case highResolutionSamples * highResolutionSamples * 2: side = highResolutionSamples
        case lowResolutionSamples * lowResolutionSamples * 2: side = lowResolutionSamples
        default: throw TerrainTileError.unsupportedSize(byteCount: bytes.count)
        }
        let count = side * side
        var voids = 0
        let samples = bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [Int16] in
            [Int16](unsafeUninitializedCapacity: count) { buffer, initialized in
                for index in 0..<count {
                    var value = (Int(raw[2 * index]) << 8) | Int(raw[2 * index + 1])
                    if value >= 32768 { value -= 65536 }
                    if value < lowestElevation || value > highestElevation {
                        buffer[index] = Int16(voidSample)
                        voids += 1
                    } else {
                        buffer[index] = Int16(value)
                    }
                }
                initialized = count
            }
        }
        return TerrainTile(key: key, samplesPerSide: side, voidCount: voids, samples: samples)
    }

    /// The elevation in metres at `latitude`, `longitude` (degrees), interpolated bilinearly between the four
    /// surrounding samples, or `nil` when the point is outside the tile (its border included), not finite, or any
    /// sample that contributes to it is a void. A sample whose weight is zero does not count, so a point exactly on a
    /// sample ignores its neighbours.
    public func elevation(at latitude: Double, longitude: Double) -> Double? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        let south = Double(key.latitude)
        let west = Double(key.longitude)
        guard latitude >= south, latitude <= south + 1, longitude >= west, longitude <= west + 1 else { return nil }
        let intervals = Double(samplesPerSide - 1)
        let x = (longitude - west) * intervals
        let y = (south + 1 - latitude) * intervals
        let column = min(Int(x.rounded(.down)), samplesPerSide - 2)
        let row = min(Int(y.rounded(.down)), samplesPerSide - 2)
        let fx = x - Double(column)
        let fy = y - Double(row)
        var total = 0.0
        for corner in 0...3 {
            let dx = corner & 1
            let dy = corner >> 1
            let weight = (dx == 0 ? 1 - fx : fx) * (dy == 0 ? 1 - fy : fy)
            if weight <= 0 { continue }
            let sample = Int(samples[(row + dy) * samplesPerSide + column + dx])
            if sample == Self.voidSample { return nil }
            total += weight * Double(sample)
        }
        return total
    }
}

import XCTest
@testable import LodestarKit

final class TerrainTileTests: XCTestCase {
    private typealias Support = TerrainTestSupport

    private let side = TerrainTile.lowResolutionSamples

    private func parse(latitude: Int = 47, longitude: Int = 8, sample: (Int, Int) -> Int) throws -> TerrainTile {
        try TerrainTile.parse(latitude: latitude, longitude: longitude, bytes: Support.bytes(side: side, sample: sample))
    }

    private func key(_ latitude: Int, _ longitude: Int) throws -> TerrainTileKey {
        try XCTUnwrap(TerrainTileKey(latitude: latitude, longitude: longitude))
    }

    /// The latitude of row `row` of a tile whose corner is 47° N.
    private func latitude(_ row: Double) -> Double { 48 - row / 1200 }

    /// The longitude of column `column` of a tile whose corner is 8° E.
    private func longitude(_ column: Double) -> Double { 8 + column / 1200 }

    // MARK: Names

    func testKeysAreNamedLikeTheTileSet() throws {
        XCTAssertEqual(try key(47, 8).name, "N47E008")
        XCTAssertEqual(try key(-34, -71).name, "S34W071")
        XCTAssertEqual(try key(0, 0).name, "N00E000")
        XCTAssertEqual(try key(-1, -1).name, "S01W001")
        XCTAssertEqual(try key(89, 179).name, "N89E179")
        XCTAssertEqual(try key(-90, -180).name, "S90W180")
        XCTAssertEqual(try key(47, 8).path, "N47/N47E008.hgt.gz")
        XCTAssertEqual(try key(-34, -71).path, "S34/S34W071.hgt.gz")
    }

    func testKeysOutsideTheGlobeAreNil() {
        XCTAssertNil(TerrainTileKey(latitude: 90, longitude: 0))
        XCTAssertNil(TerrainTileKey(latitude: -91, longitude: 0))
        XCTAssertNil(TerrainTileKey(latitude: 0, longitude: 180))
        XCTAssertNil(TerrainTileKey(latitude: 0, longitude: -181))
    }

    func testKeyContainingAPoint() {
        XCTAssertEqual(TerrainTileKey.containing(latitude: 47.5, longitude: 8.5)?.name, "N47E008")
        XCTAssertEqual(TerrainTileKey.containing(latitude: 47.0, longitude: 8.0)?.name, "N47E008")
        XCTAssertEqual(TerrainTileKey.containing(latitude: -0.5, longitude: -0.5)?.name, "S01W001")
        XCTAssertEqual(TerrainTileKey.containing(latitude: -0.0001, longitude: -0.0001)?.name, "S01W001")
        XCTAssertNil(TerrainTileKey.containing(latitude: 90, longitude: 0))
        XCTAssertNil(TerrainTileKey.containing(latitude: .nan, longitude: 0))
        XCTAssertNil(TerrainTileKey.containing(latitude: 0, longitude: .infinity))
    }

    func testKeysOrderByLatitudeThenLongitude() throws {
        let keys = try [(47, 9), (46, 9), (47, 7)].map { try key($0.0, $0.1) }
        XCTAssertEqual(keys.sorted().map(\.name), ["N46E009", "N47E007", "N47E009"])
    }

    // MARK: Parsing

    func testBigEndianSignedSamplesAreRead() throws {
        let tile = try parse { row, column in
            switch (row, column) {
            case (0, 0): return 400
            case (0, 1200): return -2
            case (1200, 0): return 256
            case (1200, 1200): return 8849
            default: return 1
            }
        }
        XCTAssertEqual(tile.latitude, 47)
        XCTAssertEqual(tile.longitude, 8)
        XCTAssertEqual(tile.samplesPerSide, 1201)
        XCTAssertEqual(tile.key.name, "N47E008")
        XCTAssertEqual(tile.elevation(at: 48, longitude: 8), 400)
        XCTAssertEqual(tile.elevation(at: 48, longitude: 9), -2)
        XCTAssertEqual(tile.elevation(at: 47, longitude: 8), 256)
        XCTAssertEqual(tile.elevation(at: 47, longitude: 9), 8849)
        XCTAssertEqual(tile.voidCount, 0)
    }

    func testTheHighByteComesFirst() throws {
        // 0x01 0x90 is 400, 0xFF 0x38 is -200 (the high byte comes first).
        var data = Support.bytes(side: side) { _, _ in 0 }
        data[0] = 0x01
        data[1] = 0x90
        data[2] = 0xFF
        data[3] = 0x38
        let tile = try TerrainTile.parse(latitude: 47, longitude: 8, bytes: data)
        XCTAssertEqual(tile.elevation(at: 48, longitude: 8), 400)
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: 48, longitude: longitude(1))), -200, accuracy: 1e-6)
    }

    func testTheOneArcSecondGridIsSupported() throws {
        let big = TerrainTile.highResolutionSamples
        let data = Support.bytes(side: big) { row, column in (row + column) % 1000 }
        XCTAssertEqual(data.count, big * big * 2)
        let tile = try TerrainTile.parse(latitude: -34, longitude: -71, bytes: data)
        XCTAssertEqual(tile.samplesPerSide, 3601)
        XCTAssertEqual(tile.key.name, "S34W071")
        // Row 0 is the northern edge (33° S), column 3600 the eastern one (70° W).
        XCTAssertEqual(tile.elevation(at: -33, longitude: -71), 0)
        XCTAssertEqual(tile.elevation(at: -33, longitude: -70), 600)
        XCTAssertEqual(tile.elevation(at: -34, longitude: -71), 600)
        XCTAssertEqual(tile.elevation(at: -34, longitude: -70), Double((3600 + 3600) % 1000))
        // Halfway along the first row: columns 1799 and 1800 hold 799 and 800.
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: -33, longitude: -71 + 1799.5 / 3600)), 799.5, accuracy: 1e-9)
    }

    func testWrongSizesAndCornersAreRefused() throws {
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 47, longitude: 8, bytes: Data(count: 1000))) {
            XCTAssertEqual($0 as? TerrainTileError, .unsupportedSize(byteCount: 1000))
        }
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 47, longitude: 8, bytes: Data())) {
            XCTAssertEqual($0 as? TerrainTileError, .unsupportedSize(byteCount: 0))
        }
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 47, longitude: 8, bytes: Data(count: side * side * 2 + 1)))
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 47, longitude: 8, bytes: Data(count: side * side * 2 - 1)))
        let data = Support.bytes(side: side) { _, _ in 0 }
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 90, longitude: 0, bytes: data)) {
            XCTAssertEqual($0 as? TerrainTileError, .invalidOrigin(latitude: 90, longitude: 0))
        }
        XCTAssertThrowsError(try TerrainTile.parse(latitude: 0, longitude: 180, bytes: data))
        XCTAssertThrowsError(try TerrainTile.parse(latitude: -91, longitude: 0, bytes: data))
    }

    // MARK: Elevation

    func testBilinearInterpolationReproducesALinearSlope() throws {
        let tile = try parse { row, column in row + 2 * column }
        // A node: row 20, column 10.
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: latitude(20), longitude: longitude(10))), 40, accuracy: 1e-6)
        // The middle of a cell: 20.25 rows and 10.5 columns from the north-west corner.
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: latitude(20.25), longitude: longitude(10.5))), 20.25 + 2 * 10.5,
                       accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: latitude(0.75), longitude: longitude(1199.5))), 0.75 + 2 * 1199.5,
                       accuracy: 1e-6)
        // The south-east corner.
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: 47, longitude: 9)), 1200 + 2400, accuracy: 1e-9)
    }

    func testTheBorderBelongsToTheTile() throws {
        let tile = try parse { _, _ in 100 }
        for (latitude, longitude) in [(47.0, 8.0), (48.0, 8.0), (47.0, 9.0), (48.0, 9.0), (47.5, 8.0), (48.0, 8.5)] {
            XCTAssertEqual(tile.elevation(at: latitude, longitude: longitude), 100, "\(latitude), \(longitude)")
        }
    }

    func testPointsOutsideTheTileAreNil() throws {
        let tile = try parse { _, _ in 100 }
        XCTAssertNil(tile.elevation(at: 46.9999, longitude: 8.5))
        XCTAssertNil(tile.elevation(at: 48.0001, longitude: 8.5))
        XCTAssertNil(tile.elevation(at: 47.5, longitude: 7.9999))
        XCTAssertNil(tile.elevation(at: 47.5, longitude: 9.0001))
        XCTAssertNil(tile.elevation(at: .nan, longitude: 8.5))
        XCTAssertNil(tile.elevation(at: 47.5, longitude: .infinity))
    }

    func testVoidsGiveNilExceptForPointsThatDoNotUseThem() throws {
        let tile = try parse { row, column in row == 601 && column == 601 ? -32768 : 50 }
        XCTAssertEqual(tile.voidCount, 1)
        // On the void and anywhere its weight is positive.
        XCTAssertNil(tile.elevation(at: latitude(601), longitude: longitude(601)))
        XCTAssertNil(tile.elevation(at: latitude(600.5), longitude: longitude(600.5)))
        XCTAssertNil(tile.elevation(at: latitude(601.25), longitude: longitude(600.9)))
        // On the node next to it the void has weight 0: row 600, column 600 are exact binary fractions of the tile.
        XCTAssertEqual(tile.elevation(at: 47.5, longitude: 8.5), 50)
        XCTAssertEqual(tile.elevation(at: 47.75, longitude: 8.25), 50)
        XCTAssertEqual(tile.elevation(at: latitude(300), longitude: longitude(900)), 50)
    }

    func testElevationsOutsideWhatLandReachesAreVoids() throws {
        let tile = try parse { row, column in
            switch (row, column) {
            case (10, 10): return 9001
            case (10, 20): return -501
            case (10, 30): return 20_000
            case (10, 40): return 9000
            case (10, 50): return -500
            default: return 3
            }
        }
        XCTAssertEqual(tile.voidCount, 3)
        XCTAssertNil(tile.elevation(at: latitude(10), longitude: longitude(10)))
        XCTAssertNil(tile.elevation(at: latitude(10), longitude: longitude(20)))
        XCTAssertNil(tile.elevation(at: latitude(10), longitude: longitude(30)))
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: latitude(10), longitude: longitude(40))), 9000, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tile.elevation(at: latitude(10), longitude: longitude(50))), -500, accuracy: 1e-6)
    }

    func testNeighbouringTilesAgreeOnTheirSharedEdge() throws {
        let ridge = { (latitude: Double, longitude: Double) -> Double in
            200 + 100 * sin(latitude * 200) * cos(longitude * 150)
        }
        let south = try Support.tile(latitude: 47, longitude: 8, elevation: ridge)
        let north = try Support.tile(latitude: 48, longitude: 8, elevation: ridge)
        for step in 0...12 {
            let longitude = 8 + Double(step) / 12
            XCTAssertEqual(south.elevation(at: 48, longitude: longitude), north.elevation(at: 48, longitude: longitude))
        }
        XCTAssertGreaterThan(try XCTUnwrap(south.elevation(at: 48, longitude: 8.3)), 100)
    }
}

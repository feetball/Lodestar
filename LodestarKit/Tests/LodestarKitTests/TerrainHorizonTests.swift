import XCTest
@testable import LodestarKit

/// `TerrainHorizon` on synthetic tiles. The expected skylines are worked out from the formula of the type description:
/// `atan((h − h0) / d) − d / (2 R′)`, `R′ = R / (1 − 0.13)`, `R` = 6 371 008.8 m. Over flat ground the horizon dips by
/// `√(2h / R′)`: 0.0423° for an eye 2 m high (the geometric dip, without refraction, is 0.0454°).
final class TerrainHorizonTests: XCTestCase {
    private typealias Support = TerrainTestSupport

    private let site = GeographicLocation(latitude: 47.5, longitude: 8.5, elevation: 0)

    private func key(_ latitude: Int, _ longitude: Int) throws -> TerrainTileKey {
        try XCTUnwrap(TerrainTileKey(latitude: latitude, longitude: longitude))
    }

    private func names(_ keys: [TerrainTileKey]) -> [String] { keys.map(\.name) }

    // MARK: Geometry

    func testApparentAltitudeOfAPointAboveTheEye() {
        // 100 m above the eye at 10 km: atan(0.01) = 0.572939° less 10 000 / (2 · 7 323 001) rad = 0.039120°.
        XCTAssertEqual(TerrainHorizon.apparentAltitude(heightDifferenceMeters: 100, distanceMeters: 10_000), 0.533819,
                       accuracy: 1e-5)
        // Level with the eye at 5 km: only the drop of the surface, 0.019560°.
        XCTAssertEqual(TerrainHorizon.apparentAltitude(heightDifferenceMeters: 0, distanceMeters: 5_000), -0.019560,
                       accuracy: 1e-5)
        // Refraction makes the drop 13% smaller than the geometric d / 2R.
        let geometric = -AstroMath.degrees(5_000.0 / (2 * TerrainHorizon.earthRadiusMeters))
        XCTAssertEqual(TerrainHorizon.apparentAltitude(heightDifferenceMeters: 0, distanceMeters: 5_000) / geometric, 0.87,
                       accuracy: 1e-12)
    }

    func testSampleDistancesFollowTheStepSchedule() {
        let distances = TerrainHorizon.sampleDistances(maximumDistanceMeters: 50_000)
        XCTAssertEqual(distances.count, 306)
        XCTAssertEqual(distances.first, 30)
        XCTAssertEqual(distances[1], 60)
        XCTAssertEqual(distances[65], 1980)
        XCTAssertEqual(distances[66], 2010)
        XCTAssertEqual(distances[67], 2110)
        XCTAssertEqual(distances[145], 9910)
        XCTAssertEqual(distances[146], 10_010)
        XCTAssertEqual(distances[147], 10_260)
        XCTAssertEqual(distances.last, 49_760)
        XCTAssertEqual(Array(TerrainHorizon.sampleDistances(maximumDistanceMeters: 1_000).prefix(3)), [30, 60, 90])
        XCTAssertEqual(TerrainHorizon.sampleDistances(maximumDistanceMeters: 1_000).count, 33)
        // Out of range values are limited, a value that is not finite means the default.
        XCTAssertEqual(TerrainHorizon.sampleDistances(maximumDistanceMeters: 5), TerrainHorizon.sampleDistances(maximumDistanceMeters: 1_000))
        XCTAssertEqual(TerrainHorizon.sampleDistances(maximumDistanceMeters: .nan), distances)
        XCTAssertEqual(TerrainHorizon.sampleDistances(maximumDistanceMeters: 1e9),
                       TerrainHorizon.sampleDistances(maximumDistanceMeters: 100_000))
    }

    // MARK: Tiles needed

    func testRequiredTilesAroundAMidLatitudeSite() {
        let tiles = TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 47.3, longitude: 8.4))
        XCTAssertEqual(tiles.first?.name, "N47E008")
        XCTAssertEqual(Set(names(tiles)), ["N47E008", "N47E007", "N47E009", "N46E008", "N46E007"])
        // The same site with a 10 km range needs only its own tile.
        XCTAssertEqual(names(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 47.3, longitude: 8.4),
                                                          maxDistanceMeters: 10_000)), ["N47E008"])
    }

    func testRequiredTilesAtTheCentreOfATileAreOrderedByDistanceThenCorner() {
        // 0.5° of longitude is 37.6 km at 47.5° N: both neighbours are in range and equally far, the western one first.
        XCTAssertEqual(names(TerrainHorizon.requiredTiles(at: site)), ["N47E008", "N47E007", "N47E009"])
    }

    func testRequiredTilesNeedSixAtMidLatitudesAndFourAtTheEquator() {
        XCTAssertEqual(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 47.9, longitude: 8.5)).count, 6)
        XCTAssertEqual(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 0.05, longitude: 0.05)).count, 4)
        XCTAssertEqual(Set(names(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 0.05, longitude: 0.05)))),
                       ["N00E000", "S01E000", "N00W001", "S01W001"])
    }

    func testRequiredTilesWrapAroundTheAntimeridian() {
        let tiles = names(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 0.5, longitude: 179.9)))
        XCTAssertTrue(tiles.contains("N00E179"))
        XCTAssertTrue(tiles.contains("N00W180"))
        XCTAssertEqual(tiles.first, "N00E179")
        let west = names(TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 0.5, longitude: -179.9)))
        XCTAssertTrue(west.contains("N00W180"))
        XCTAssertTrue(west.contains("N00E179"))
    }

    func testRequiredTilesAreFewNearThePoles() {
        let north = TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: 89.5, longitude: 10))
        XCTAssertTrue((2...TerrainHorizon.maximumTileCount).contains(north.count))
        XCTAssertEqual(north.count, Set(north).count)
        XCTAssertTrue(north.allSatisfy { $0.latitude <= 89 })
        let south = TerrainHorizon.requiredTiles(at: GeographicLocation(latitude: -90, longitude: 0))
        XCTAssertTrue((1...TerrainHorizon.maximumTileCount).contains(south.count))
        XCTAssertTrue(south.allSatisfy { $0.latitude == -90 || $0.latitude == -89 })
    }

    // MARK: Flat ground

    func testFlatTileGivesTheDipOfTheHorizonAtTwoMetres() throws {
        let result = TerrainHorizon.profile(at: site, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400)])
        // The dip: √(2 · 2 / R′) = 7.39e-4 rad = 0.0423°, a little less than the 0.0454° without refraction.
        let dip = Support.flatDip(eye: 2)
        XCTAssertEqual(dip, -0.04235, accuracy: 2e-5)
        XCTAssertEqual(result.altitudes.count, 360)
        for altitude in result.altitudes { XCTAssertEqual(altitude, dip, accuracy: 5e-5) }
        // The profile has a resolution of 0.1°, so the dip rounds to nothing.
        XCTAssertTrue(result.profile.isFlat)
        XCTAssertEqual(result.groundElevationMeters, 400)
        XCTAssertEqual(result.voidSampleShare, 0)
    }

    func testTheEyeHeightSetsTheDip() throws {
        let tiles = [try Support.flatTile(latitude: 47, longitude: 8, meters: 400)]
        // 10 m: √(2 · 10 / R′) = 0.0947°, which the profile shows as −0.1°.
        let ten = TerrainHorizon.profile(at: site, tiles: tiles, eyeHeightMeters: 10)
        XCTAssertEqual(Support.flatDip(eye: 10), -0.0947, accuracy: 1e-4)
        for altitude in ten.altitudes { XCTAssertEqual(altitude, Support.flatDip(eye: 10), accuracy: 5e-5) }
        XCTAssertTrue(ten.profile.altitudes.allSatisfy { $0 == -0.1 })
        // Out of range or not finite values are limited, or replaced by the 2 m default.
        let high = TerrainHorizon.profile(at: site, tiles: tiles, eyeHeightMeters: 1e6)
        XCTAssertEqual(high.altitudes[0], Support.flatDip(eye: 100), accuracy: 5e-5)
        XCTAssertTrue(high.profile.altitudes.allSatisfy { $0 == -0.3 })
        // An eye at the ground sees the surface fall away from the first step on: −30 m / 2R′ = −0.000117°.
        let negative = TerrainHorizon.profile(at: site, tiles: tiles, eyeHeightMeters: -5)
        XCTAssertEqual(negative.altitudes[0], TerrainHorizon.apparentAltitude(heightDifferenceMeters: 0, distanceMeters: 30),
                       accuracy: 1e-9)
        let unknown = TerrainHorizon.profile(at: site, tiles: tiles, eyeHeightMeters: .nan)
        XCTAssertEqual(unknown.altitudes[200], Support.flatDip(eye: 2), accuracy: 5e-5)
    }

    func testTheGroundOfTheTileIsTheReferenceNotTheSiteElevation() throws {
        let elevated = GeographicLocation(latitude: 47.5, longitude: 8.5, elevation: 1234)
        let result = TerrainHorizon.profile(at: elevated, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400)])
        XCTAssertEqual(result.groundElevationMeters, 400)
        XCTAssertEqual(result.altitudes[45], Support.flatDip(eye: 2), accuracy: 5e-5)
    }

    func testCoveredRangeEndsWhereTheTilesDo() throws {
        let result = TerrainHorizon.profile(at: site, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400)])
        // North and south: the tile reaches 55 km, so the whole 50 km range is covered (the last step is 49 760 m).
        XCTAssertEqual(result.coveredRangeMeters[0], 49_760)
        XCTAssertEqual(result.coveredRangeMeters[180], 49_760)
        // East and west: the tile ends 37.6 km from the centre.
        for azimuth in [90, 270] {
            XCTAssertTrue((37_000.0...37_600.0).contains(result.coveredRangeMeters[azimuth]), "\(result.coveredRangeMeters[azimuth])")
        }
        XCTAssertEqual(result.minimumCoveredRangeMeters, result.coveredRangeMeters.min())
        XCTAssertEqual(names(result.missingTiles), names([try key(47, 7), try key(47, 9)]))
        XCTAssertFalse(result.isComplete)
    }

    func testNoTilesGiveAFlatSkylineAndEveryTileMissing() {
        let result = TerrainHorizon.profile(at: GeographicLocation(latitude: 47.5, longitude: 8.5, elevation: 123), tiles: [])
        XCTAssertTrue(result.profile.isFlat)
        XCTAssertNil(result.groundElevationMeters)
        XCTAssertTrue(result.coveredRangeMeters.allSatisfy { $0 == 0 })
        XCTAssertEqual(result.missingTiles, TerrainHorizon.requiredTiles(at: site))
        XCTAssertEqual(result.voidSampleShare, 0)
        XCTAssertEqual(result.minimumCoveredRangeMeters, 0)
    }

    func testATileGivenTwiceCountsOnceAndTilesNotNeededAreIgnored() throws {
        let once = TerrainHorizon.profile(at: site, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400)])
        let twice = TerrainHorizon.profile(at: site, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400),
                                                              try Support.flatTile(latitude: 47, longitude: 8, meters: 900)])
        XCTAssertEqual(once, twice)
        let far = TerrainHorizon.profile(at: site, tiles: [try Support.flatTile(latitude: 47, longitude: 8, meters: 400),
                                                            try Support.flatTile(latitude: 10, longitude: 10, meters: 900)])
        XCTAssertEqual(once, far)
    }

    // MARK: A hill

    /// A hill 300 m high and 1 km in radius whose summit is `distance` m from the site towards `azimuth`.
    private func hillAt(azimuth: Double, distance: Double, height: Double = 300,
                        radius: Double = 1000) -> (Double, Double) -> Double {
        let apex = Support.destination(latitude: 47.5, longitude: 8.5, azimuth: azimuth, distance: distance)
        return Support.dome(apexLatitude: apex.latitude, apexLongitude: apex.longitude, height: height, radius: radius)
    }

    func testHillFiveKilometresEastRisesAboveTheHorizon() throws {
        // The summit is 5010 m east: one of the steps of the ray.
        let hill = hillAt(azimuth: 90, distance: 5_010)
        let result = TerrainHorizon.profile(at: site, tiles: [try Support.tile(latitude: 47, longitude: 8, elevation: hill)])
        // atan((300 − 2) / 5010) = 3.4041° less the drop of 5010 m, 0.0196°. The highest apparent point of a round hill is
        // a little before its summit (the hill is rising there), so the skyline is read off the whole ray.
        let summit = TerrainHorizon.apparentAltitude(heightDifferenceMeters: 300 - 2, distanceMeters: 5_010)
        XCTAssertEqual(summit, 3.3845, accuracy: 2e-4)
        let expected = Support.expectedSkyline(latitude: 47.5, longitude: 8.5, azimuth: 90, ground: 0, elevation: hill)
        XCTAssertEqual(summit, expected, accuracy: 0.05)
        XCTAssertEqual(result.altitudes[90], expected, accuracy: 0.03)
        XCTAssertEqual(result.profile.altitude(at: 90), 3.4, accuracy: 0.1)
        // The summit is the highest point of the skyline, and the hill is narrow: elsewhere is the dip.
        XCTAssertEqual(result.altitudes.indices.max { result.altitudes[$0] < result.altitudes[$1] }, 90)
        XCTAssertEqual(result.altitudes[270], Support.flatDip(eye: 2), accuracy: 5e-5)
        XCTAssertEqual(result.altitudes[0], Support.flatDip(eye: 2), accuracy: 5e-5)
        XCTAssertEqual(result.altitudes[180], Support.flatDip(eye: 2), accuracy: 5e-5)
        // The flanks fall away: a hill 1 km in radius, seen from 5 km, spans about ±11° round the east.
        XCTAssertLessThan(result.altitudes[100], result.altitudes[95])
        XCTAssertLessThan(result.altitudes[95], result.altitudes[90])
        XCTAssertLessThan(result.altitudes[85], result.altitudes[90])
        XCTAssertEqual(result.altitudes[120], Support.flatDip(eye: 2), accuracy: 5e-5)
        XCTAssertEqual(result.altitudes[95],
                       Support.expectedSkyline(latitude: 47.5, longitude: 8.5, azimuth: 95, ground: 0, elevation: hill),
                       accuracy: 0.03)
    }

    func testTheSkylineIsMeasuredFromTheEyeNotFromSeaLevel() throws {
        // The same hill with the whole land 500 m up: the site's ground is 500 m, the summit 800 m.
        let dome = hillAt(azimuth: 90, distance: 5_010)
        let raised = { (latitude: Double, longitude: Double) -> Double in 500 + dome(latitude, longitude) }
        let result = TerrainHorizon.profile(at: site, tiles: [try Support.tile(latitude: 47, longitude: 8, elevation: raised)])
        XCTAssertEqual(result.groundElevationMeters, 500)
        let expected = Support.expectedSkyline(latitude: 47.5, longitude: 8.5, azimuth: 90, ground: 500, elevation: raised)
        XCTAssertEqual(TerrainHorizon.apparentAltitude(heightDifferenceMeters: 300 - 2, distanceMeters: 5_010), expected,
                       accuracy: 0.05)
        XCTAssertEqual(result.altitudes[90], expected, accuracy: 0.03)
    }

    func testTheSkylineIsClampedToWhatAProfileCanHold() throws {
        // A 3000 m spike 300 m away is at 85°: the profile stops at 60°, the unclamped value stays in altitudes.
        let spike = hillAt(azimuth: 90, distance: 300, height: 3000, radius: 250)
        let result = TerrainHorizon.profile(at: site, tiles: [try Support.tile(latitude: 47, longitude: 8, elevation: spike)])
        XCTAssertEqual(result.groundElevationMeters, 0)
        XCTAssertGreaterThan(result.altitudes[90], 80, "\(result.altitudes[90])")
        XCTAssertEqual(result.profile.altitude(at: 90), 60)
    }

    // MARK: Seams

    func testARayCrossingATileSeamSeesTheHillOnTheOtherSide() throws {
        // The site is 1.1 km south of the seam at 48° N; the hill is 5010 m due north, in the next tile.
        let near = GeographicLocation(latitude: 47.99, longitude: 8.5, elevation: 0)
        let apex = Support.destination(latitude: 47.99, longitude: 8.5, azimuth: 0, distance: 5_010)
        let hill = Support.dome(apexLatitude: apex.latitude, apexLongitude: apex.longitude, height: 300, radius: 1000)
        let south = try Support.tile(latitude: 47, longitude: 8) { latitude, longitude in hill(latitude, longitude) }
        let north = try Support.tile(latitude: 48, longitude: 8) { latitude, longitude in hill(latitude, longitude) }
        let both = TerrainHorizon.profile(at: near, tiles: [south, north])
        let expected = Support.expectedSkyline(latitude: 47.99, longitude: 8.5, azimuth: 0, ground: 0, elevation: hill)
        XCTAssertEqual(expected, 3.3845, accuracy: 0.05)
        XCTAssertEqual(both.altitudes[0], expected, accuracy: 0.03)
        XCTAssertEqual(both.profile.altitude(at: 0), 3.4, accuracy: 0.1)
        XCTAssertGreaterThan(both.coveredRangeMeters[0], 49_000)
        XCTAssertFalse(both.missingTiles.contains(try key(48, 8)))
        XCTAssertTrue(both.missingTiles.contains(try key(47, 7)))

        // Without the northern tile the ray sees nothing beyond the seam, and the tile is reported.
        let onlySouth = TerrainHorizon.profile(at: near, tiles: [south])
        // Only the first 1.1 km of the ray is on the tile, so its highest point is the last one: −2 m / 1110 m = −0.1076°.
        XCTAssertTrue((1_080.0...1_112.0).contains(onlySouth.coveredRangeMeters[0]), "\(onlySouth.coveredRangeMeters[0])")
        XCTAssertEqual(onlySouth.altitudes[0], TerrainHorizon.apparentAltitude(heightDifferenceMeters: -2,
                                                                                 distanceMeters: onlySouth.coveredRangeMeters[0]),
                       accuracy: 1e-9)
        XCTAssertEqual(onlySouth.altitudes[0], -0.1076, accuracy: 1e-3)
        XCTAssertTrue(onlySouth.missingTiles.contains(try key(48, 8)))
        XCTAssertEqual(names(onlySouth.missingTiles).filter { $0 == "N48E008" }, names([try key(48, 8)]))
    }

    // MARK: Voids

    func testVoidsAreSeaLevelAndAreCounted() throws {
        // All land at 400 m, but everything east of 8.583° E (6.2 km from the site) is a void.
        let side = TerrainTile.lowResolutionSamples
        let data = Support.bytes(side: side) { _, column in column >= 700 ? -32768 : 400 }
        let tile = try TerrainTile.parse(latitude: 47, longitude: 8, bytes: data)
        let result = TerrainHorizon.profile(at: site, tiles: [tile])
        // Voids count as 0 m, far below the eye (400 m), so they never raise the skyline.
        XCTAssertEqual(result.altitudes[90], Support.flatDip(eye: 2), accuracy: 5e-5)
        XCTAssertGreaterThan(result.voidSampleShare, 0.05)
        XCTAssertLessThan(result.voidSampleShare, 0.5)
    }

    func testAVoidAtTheSiteFallsBackToTheSiteElevation() throws {
        // 400 m everywhere, but a void patch of 5 × 5 samples (about 90 m) round the site.
        let side = TerrainTile.lowResolutionSamples
        let data = Support.bytes(side: side) { row, column in abs(row - 600) <= 2 && abs(column - 600) <= 2 ? -32768 : 400 }
        let tile = try TerrainTile.parse(latitude: 47, longitude: 8, bytes: data)
        let located = GeographicLocation(latitude: 47.5, longitude: 8.5, elevation: 400)
        let result = TerrainHorizon.profile(at: located, tiles: [tile])
        XCTAssertNil(result.groundElevationMeters)
        // The eye is at the site's own elevation plus 2 m, so the flat ground beyond the patch gives the usual dip.
        XCTAssertEqual(result.altitudes[30], Support.flatDip(eye: 2), accuracy: 5e-5)
        XCTAssertGreaterThan(result.voidSampleShare, 0)
    }

    // MARK: Merging

    private func ramp(_ offset: Double) throws -> HorizonProfile {
        try XCTUnwrap(HorizonProfile(altitudes: (0..<360).map { offset + Double($0) / 10 }))
    }

    func testMergedUsesTheRecordedSkylineWhereTheSweepWasAndTheTerrainInTheGaps() throws {
        let recorded = HorizonProfile.constant(5)
        let terrain = try ramp(-5)
        let merged = try XCTUnwrap(HorizonProfile.merged(recorded: recorded, terrain: terrain,
                                                         gaps: [AzimuthRange(start: 79.5, length: 16)]))
        for bin in 0..<360 {
            XCTAssertEqual(merged.altitudes[bin], (80...95).contains(bin) ? terrain.altitudes[bin] : 5, "bin \(bin)")
        }
    }

    func testMergedGapsMayRunThroughNorthAndSeveralMayExist() throws {
        let recorded = HorizonProfile.constant(5)
        let terrain = try ramp(0)
        let merged = try XCTUnwrap(HorizonProfile.merged(
            recorded: recorded, terrain: terrain,
            gaps: [AzimuthRange(start: 349.5, length: 21), AzimuthRange(start: 179.5, length: 2)]))
        let fromTerrain = Set(350...359).union(0...10).union([180, 181])
        for bin in 0..<360 {
            XCTAssertEqual(merged.altitudes[bin], fromTerrain.contains(bin) ? terrain.altitudes[bin] : 5, "bin \(bin)")
        }
    }

    func testMergedWithOnlyOneSourceOrNoGapsIsThatSource() throws {
        let recorded = HorizonProfile.constant(5)
        let terrain = try ramp(0)
        XCTAssertNil(HorizonProfile.merged(recorded: nil, terrain: nil))
        XCTAssertNil(HorizonProfile.merged(recorded: nil, terrain: nil, gaps: [.full]))
        XCTAssertEqual(HorizonProfile.merged(recorded: nil, terrain: terrain), terrain)
        XCTAssertEqual(HorizonProfile.merged(recorded: nil, terrain: terrain, gaps: [AzimuthRange(start: 10, length: 5)]), terrain)
        XCTAssertEqual(HorizonProfile.merged(recorded: recorded, terrain: nil, gaps: [.full]), recorded)
        XCTAssertEqual(HorizonProfile.merged(recorded: recorded, terrain: terrain), recorded)
        XCTAssertEqual(HorizonProfile.merged(recorded: recorded, terrain: terrain, gaps: []), recorded)
        XCTAssertEqual(HorizonProfile.merged(recorded: recorded, terrain: terrain, gaps: [.full]), terrain)
    }

    // MARK: Unswept stretches

    private func mask(unswept: [ClosedRange<Int>]) -> [Bool] {
        (0..<360).map { bin in !unswept.contains { $0.contains(bin) } }
    }

    func testUnsweptRangesOfAnEmptyAndAFullSweep() {
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: [Bool](repeating: false, count: 360)), [.full])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: [Bool](repeating: true, count: 360)), [])
    }

    func testUnsweptRangesWrapThroughNorthAndStartAtTheLowerEdgeOfTheFirstDegree() {
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [200...359, 0...99])),
                       [AzimuthRange(start: 199.5, length: 260)])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [0...9])), [AzimuthRange(start: 359.5, length: 10)])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [350...359, 0...10])),
                       [AzimuthRange(start: 349.5, length: 21)])
    }

    func testUnsweptRangesAreInAzimuthOrderAndShortGapsAreFilledByTheRecorder() {
        let swept = mask(unswept: [300...320, 20...40, 100...105, 200...206])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: swept),
                       [AzimuthRange(start: 19.5, length: 21), AzimuthRange(start: 199.5, length: 7),
                        AzimuthRange(start: 299.5, length: 21)])
        // The limit is the recorder's, 6 degrees: six unswept degrees are interpolated, seven are a gap.
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [10...15])), [])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [10...16])).count, 1)
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [10...10]), maximumInterpolatedGap: 0).count, 1)
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: mask(unswept: [10...39]), maximumInterpolatedGap: 99), [])
    }

    func testUnsweptRangesOfAMaskThatIsNotACircleAreNone() {
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: []), [])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: [Bool](repeating: false, count: 359)), [])
        XCTAssertEqual(HorizonProfile.unsweptRanges(swept: [Bool](repeating: false, count: 361)), [])
    }

    func testTheRecordersOwnGapsAgreeWithUnsweptRanges() {
        // A recorder that swept 0…179 and 250…359 reports the same stretch as the mask it publishes.
        var recorder = HorizonRecorder()
        for azimuth in Array(0...179) + Array(250...359) {
            recorder.add(azimuth: Double(azimuth), altitude: 3, timestamp: Double(azimuth) * 0.02)
        }
        XCTAssertEqual(recorder.gaps, HorizonProfile.unsweptRanges(swept: recorder.recordedMask))
    }
}

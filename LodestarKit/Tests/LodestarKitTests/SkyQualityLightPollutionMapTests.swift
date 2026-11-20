import XCTest
@testable import LodestarKit

final class SkyQualityLightPollutionMapTests: XCTestCase {
    typealias Support = SkyQualityTestSupport

    /// A place of the reference table: the generator's `--report` of the shipped file (glow to five decimals).
    struct Reference {
        let name: String
        let latitude: Double
        let longitude: Double
        let level: Int
        let glow: Double
        let bortleClass: Int
    }

    let references = [
        Reference(name: "Cherry Springs State Park", latitude: 41.6627, longitude: -77.8230, level: 0, glow: 0.00050, bortleClass: 2),
        Reference(name: "Death Valley, Badwater", latitude: 36.2296, longitude: -116.7673, level: 0, glow: 0.00009, bortleClass: 1),
        Reference(name: "Big Bend, Chisos Basin", latitude: 29.2706, longitude: -103.3010, level: 0, glow: 0.00000, bortleClass: 1),
        Reference(name: "Joshua Tree, Hidden Valley", latitude: 34.0125, longitude: -116.1672, level: 0, glow: 0.01672, bortleClass: 4),
        Reference(name: "Zselic Starry Sky Park", latitude: 46.2125, longitude: 17.8689, level: 0, glow: 0.00411, bortleClass: 3),
        Reference(name: "Galloway Forest Park", latitude: 55.0450, longitude: -4.4900, level: 0, glow: 0.00239, bortleClass: 3),
        Reference(name: "Mauna Kea summit", latitude: 19.8207, longitude: -155.4681, level: 0, glow: 0.00033, bortleClass: 1),
        Reference(name: "Natural Bridges", latitude: 37.6020, longitude: -110.0140, level: 0, glow: 0.00001, bortleClass: 1),
        Reference(name: "Paranal", latitude: -24.6275, longitude: -70.4044, level: 0, glow: 0.00004, bortleClass: 1),
        Reference(name: "Roque de los Muchachos", latitude: 28.7606, longitude: -17.8816, level: 0, glow: 0.00171, bortleClass: 3),
        Reference(name: "Kielder Observatory", latitude: 55.2336, longitude: -2.6025, level: 0, glow: 0.00368, bortleClass: 3),
        Reference(name: "McDonald Observatory", latitude: 30.6714, longitude: -104.0225, level: 0, glow: 0.00010, bortleClass: 1),
        Reference(name: "Green Bank", latitude: 38.4331, longitude: -79.8397, level: 0, glow: 0.00062, bortleClass: 2),
        Reference(name: "Flagstaff, Lowell Observatory", latitude: 35.2028, longitude: -111.6646, level: 7, glow: 0.04954, bortleClass: 5),
        Reference(name: "Boulder", latitude: 40.0150, longitude: -105.2705, level: 12, glow: 0.22996, bortleClass: 7),
        Reference(name: "Palo Alto", latitude: 37.4419, longitude: -122.1430, level: 13, glow: 0.40191, bortleClass: 8),
        Reference(name: "Plano", latitude: 33.0198, longitude: -96.6989, level: 15, glow: 1.29076, bortleClass: 9),
        Reference(name: "Munich, Marienplatz", latitude: 48.1374, longitude: 11.5755, level: 15, glow: 0.61057, bortleClass: 9),
        Reference(name: "Cape Town", latitude: -33.9249, longitude: 18.4241, level: 14, glow: 0.47350, bortleClass: 8),
        Reference(name: "London, Trafalgar Square", latitude: 51.5080, longitude: -0.1281, level: 15, glow: 1.11594, bortleClass: 9),
        Reference(name: "New York, Times Square", latitude: 40.7580, longitude: -73.9855, level: 15, glow: 1.30694, bortleClass: 9),
        Reference(name: "Las Vegas, the Strip", latitude: 36.1147, longitude: -115.1728, level: 15, glow: 1.01962, bortleClass: 9),
        Reference(name: "Tokyo, Shinjuku", latitude: 35.6896, longitude: 139.7006, level: 15, glow: 1.26326, bortleClass: 9),
        Reference(name: "Pacific Ocean", latitude: 0, longitude: -150, level: 0, glow: 0, bortleClass: 1),
        Reference(name: "Sahara", latitude: 23, longitude: 10, level: 0, glow: 0, bortleClass: 1),
    ]

    /// The class (or range of classes) published for each place: park and observatory pages, NPS and IDA.
    let published: [String: ClosedRange<Int>] = [
        "Cherry Springs State Park": 2...2, "Death Valley, Badwater": 1...2, "Big Bend, Chisos Basin": 1...2,
        "Joshua Tree, Hidden Valley": 2...3, "Zselic Starry Sky Park": 3...3, "Galloway Forest Park": 2...3,
        "Mauna Kea summit": 1...1, "Natural Bridges": 1...1, "Paranal": 1...1, "Roque de los Muchachos": 1...1,
        "Kielder Observatory": 2...3, "McDonald Observatory": 1...2, "Green Bank": 3...3,
        "Flagstaff, Lowell Observatory": 5...6, "Boulder": 7...7, "Palo Alto": 7...8, "Plano": 7...8,
        "Munich, Marienplatz": 8...9, "Cape Town": 8...9, "London, Trafalgar Square": 9...9,
        "New York, Times Square": 9...9, "Las Vegas, the Strip": 9...9, "Tokyo, Shinjuku": 9...9,
        "Pacific Ocean": 1...1, "Sahara": 1...1,
    ]

    func shipped() throws -> LightPollutionMap {
        try LightPollutionMap.load()
    }

    // MARK: Decoder

    func testDecoderRoundTripsASyntheticGrid() throws {
        let cells = Support.cells { row, column in
            if row < 400 { return (column / 5 + row / 100) % 16 }
            if row < 900 { return 3 }
            if row < 1000 { return (column + row) % 2 * 9 }
            if row < 1200 { return 11 }
            return (100..<3500).contains(column) ? 15 : 0
        }
        let blob = Support.encode(cells)
        XCTAssertLessThan(blob.count, cells.count / 4)
        let map = try LightPollutionMap.parse(blob)
        XCTAssertEqual(map.levels, cells)
        for row in [0, 1, 399, 400, 899, 900, 999, 1000, 1199, 1200, 1799] {
            for column in [0, 1, 99, 100, 3499, 3500, 3599, 1234] {
                XCTAssertEqual(Int(cells[row * 3600 + column]), map.level(at: Support.centre(row: row, column: column)),
                               "\(row), \(column)")
            }
        }
    }

    func testDecoderReadsRunsOfEveryLength() throws {
        for run in [1, 2, 15, 16, 17, 143, 144, 3583, 3584, 3599, 3600] {
            let cells = Support.cells { _, column in column < run ? 7 : 2 }
            XCTAssertEqual(try Support.map(cells).levels, cells, "run \(run)")
        }
    }

    func testDecoderRejectsMalformedFiles() throws {
        let good = Support.encode(Support.darkCells())
        let body = good.subdata(in: 16..<good.count)
        XCTAssertEqual(good.count, 16 + 1800 * 3)
        XCTAssertEqual(good, Support.file(firstRow: [0xF0, 0x80, 0x1C]))
        let bad: [String: Data] = [
            "magic": Support.header(length: 5400, magic: "LPM2") + body,
            "width": Support.header(length: 5400, gridWidth: 3599) + body,
            "height": Support.header(length: 5400, gridHeight: 1799) + body,
            "levels": Support.header(length: 5400, levels: 15) + body,
            "reserved": Support.header(length: 5400, reserved: 1) + body,
            "length": Support.header(length: 5399) + body,
            "short header": good.prefix(10),
            "truncated": good.prefix(good.count - 1),
            "trailing": good + Data([0]),
            "run past the row": Support.file(firstRow: [0xF0, 0x81, 0x1C]),
            "row too short": Support.file(firstRow: [0x0F]),
            "varint too long": Support.file(firstRow: [0xF0, 0x80, 0x80, 0x80, 0x01]),
            "open varint": Support.file(firstRow: [0xF0, 0x80]),
            "too large": Data(count: LightPollutionMap.maximumFileBytes + 1),
        ]
        for (name, data) in bad {
            XCTAssertThrowsError(try LightPollutionMap.parse(data), name) { error in
                guard case SkyQualityError.lightPollutionMapUnavailable = error else {
                    return XCTFail("\(name): \(error)")
                }
                XCTAssertTrue(String(describing: error).hasPrefix("The light pollution map is unavailable: "), name)
            }
        }
    }

    func testErrorSentenceNamesTheReason() {
        let error = SkyQualityError.lightPollutionMapUnavailable(reason: "the file is not a light pollution map")
        XCTAssertEqual(error.description, "The light pollution map is unavailable: the file is not a light pollution map")
        XCTAssertEqual(error.errorDescription, error.description)
        XCTAssertEqual(error.localizedDescription, error.description)
    }

    // MARK: Cells

    func testCellsAreIndexedFromTheNorthWestCorner() throws {
        var cells = Support.darkCells()
        for (row, column, level) in [(0, 0, 1), (0, 3599, 2), (1799, 0, 3), (1799, 3599, 4), (899, 1800, 5), (900, 1799, 6)] {
            cells[row * 3600 + column] = UInt8(level)
        }
        let map = try Support.map(cells)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 90, longitude: -180)), 1)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 89.95, longitude: -179.95)), 1)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 90, longitude: 179.99)), 2)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: -90, longitude: -180)), 3)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: -90, longitude: 179.95)), 4)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 0.05, longitude: 0.05)), 5)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: -0.05, longitude: -0.05)), 6)
        // 180° E is the first column again (longitudes wrap), and a latitude beyond the pole is the pole.
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 89.95, longitude: 180)), 1)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 95, longitude: -180)), 1)
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 45, longitude: 45)), 0)
    }

    // MARK: The shipped file

    func testShippedMapLoadsAndOceansAreDark() throws {
        XCTAssertTrue((100_000...200_000).contains(try LightPollutionMap.bundledData().count))
        let map = try shipped()
        for (latitude, longitude) in [(0.0, -150.0), (-40.0, -130.0), (30.0, -40.0), (-85.0, 0.0), (72.0, -40.0)] {
            XCTAssertEqual(map.level(at: GeographicLocation(latitude: latitude, longitude: longitude)), 0,
                           "\(latitude), \(longitude)")
        }
        XCTAssertEqual(map.level(at: GeographicLocation(latitude: 23, longitude: 10)), 0)
    }

    func testKnownCitiesAreBright() throws {
        let map = try shipped()
        let cities = ["New York, Times Square", "London, Trafalgar Square", "Tokyo, Shinjuku", "Las Vegas, the Strip",
                      "Munich, Marienplatz"]
        for reference in references where cities.contains(reference.name) {
            XCTAssertGreaterThanOrEqual(
                map.level(at: GeographicLocation(latitude: reference.latitude, longitude: reference.longitude)), 14,
                reference.name)
        }
        XCTAssertGreaterThanOrEqual(map.level(at: GeographicLocation(latitude: 40.0150, longitude: -105.2705)), 12)
        XCTAssertGreaterThanOrEqual(map.level(at: GeographicLocation(latitude: 48.8566, longitude: 2.3522)), 14)
        XCTAssertGreaterThanOrEqual(map.level(at: GeographicLocation(latitude: 34.0522, longitude: -118.2437)), 14)
    }

    func testReferencePlacesKeepTheirLevelsGlowAndClass() throws {
        let map = try shipped()
        for reference in references {
            let place = GeographicLocation(latitude: reference.latitude, longitude: reference.longitude)
            XCTAssertEqual(map.level(at: place), reference.level, reference.name)
            XCTAssertEqual(map.skyGlowIndex(at: place), reference.glow, accuracy: 1e-5, reference.name)
            let estimate = map.bortleEstimate(at: place)
            XCTAssertEqual(estimate.bortleClass, reference.bortleClass, reference.name)
            XCTAssertEqual(estimate.level, reference.level, reference.name)
            XCTAssertEqual(estimate.skyGlowIndex, map.skyGlowIndex(at: place), reference.name)
        }
        // 21 of the 25 places fall in the class published for them (the table in the documentation of the map).
        let inside = references.filter { reference in
            published[reference.name].map { $0.contains(reference.bortleClass) } ?? false
        }
        XCTAssertEqual(inside.count, 21)
    }

    func testBrightCitiesAreClassNineAndDarkSitesAreLow() throws {
        let map = try shipped()
        XCTAssertEqual(map.bortleEstimate(at: GeographicLocation(latitude: 40.7580, longitude: -73.9855)).bortleClass, 9)
        XCTAssertLessThanOrEqual(map.bortleEstimate(at: GeographicLocation(latitude: 36.2296, longitude: -116.7673)).bortleClass, 2)
        XCTAssertGreaterThan(map.skyGlowIndex(at: GeographicLocation(latitude: 40.7580, longitude: -73.9855)),
                             map.skyGlowIndex(at: GeographicLocation(latitude: 40.0150, longitude: -105.2705)))
    }

    // MARK: Bortle thresholds

    func testGlowThresholdsAreMonotonicAndMapToClasses() {
        let thresholds = BortleEstimate.glowThresholds
        XCTAssertEqual(thresholds.count, 8)
        XCTAssertGreaterThan(thresholds[0], 0)
        for index in 1..<thresholds.count {
            XCTAssertGreaterThan(thresholds[index], thresholds[index - 1], "threshold \(index)")
        }
        XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: 0), 1)
        XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: -3), 1)
        XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: .nan), 1)
        XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: 1e9), 9)
        XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: .infinity), 9)
        for (index, threshold) in thresholds.enumerated() {
            XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: threshold), index + 2, "at threshold \(index)")
            XCTAssertEqual(BortleEstimate.bortleClass(forGlowIndex: threshold * 0.999), index + 1,
                           "below threshold \(index)")
        }
        var previous = 1
        var glow = 0.0
        while glow < 2 {
            let bortleClass = BortleEstimate.bortleClass(forGlowIndex: glow)
            XCTAssertGreaterThanOrEqual(bortleClass, previous, "glow \(glow)")
            previous = bortleClass
            glow += 0.0005
        }
        XCTAssertEqual(previous, 9)
    }

    func testEstimateHasALabelASummaryAndTheCaveat() {
        let labels = (1...9).map { BortleEstimate.label(forClass: $0) }
        XCTAssertEqual(Set(labels).count, 9)
        XCTAssertEqual(labels.first, "Excellent dark sky")
        XCTAssertEqual(labels.last, "Inner-city sky")
        XCTAssertEqual(BortleEstimate.label(forClass: -4), labels.first)
        XCTAssertEqual(BortleEstimate.label(forClass: 40), labels.last)
        let rural = BortleEstimate(skyGlowIndex: 0.003, level: 0)
        XCTAssertEqual(rural.bortleClass, 3)
        XCTAssertEqual(rural.label, "Rural sky")
        XCTAssertEqual(rural.summary, "Bortle ~3 (rural sky)")
        let transition = BortleEstimate(skyGlowIndex: 0.01, level: 2)
        XCTAssertEqual(transition.bortleClass, 4)
        XCTAssertEqual(transition.summary, "Bortle ~4 (rural/suburban transition)")
        XCTAssertEqual(BortleEstimate.caveat, "Estimated from 2016 satellite night-light imagery; not a sky measurement")
        XCTAssertEqual(BortleEstimate(skyGlowIndex: 0, level: 99).level, 15)
        XCTAssertEqual(BortleEstimate(skyGlowIndex: 0, level: -5).level, 0)
        let broken = BortleEstimate(skyGlowIndex: .nan, level: 3)
        XCTAssertEqual(broken.bortleClass, 1)
        XCTAssertEqual(broken.skyGlowIndex, 0)
        XCTAssertEqual(BortleEstimate(skyGlowIndex: 0.003, level: 0), rural)
    }

    // MARK: Sky glow

    func testSkyGlowOfASingleLitCellFollowsDistanceToTheMinusTwoAndAHalf() throws {
        var cells = Support.darkCells()
        cells[900 * 3600 + 1800] = 11
        let map = try Support.map(cells)
        let centre = Support.centre(row: 900, column: 1800)
        let luminance = LightPollutionMap.levelLuminance[11]
        XCTAssertEqual(luminance, 0.1125)
        // In the cell itself, and anywhere within the core distance, the cell counts at its own luminance.
        XCTAssertEqual(map.skyGlowIndex(at: centre), luminance * cos(centre.latitude * .pi / 180), accuracy: 1e-12)
        var previous = Double.greatestFiniteMagnitude
        for degrees in [0.05, 0.1, 0.2, 0.4, 0.8] {
            let site = GeographicLocation(latitude: centre.latitude, longitude: centre.longitude + degrees)
            let distance = degrees * LightPollutionMap.kilometersPerDegree * cos(centre.latitude * .pi / 180)
            let ratio = max(distance, LightPollutionMap.glowCoreKm) / LightPollutionMap.glowCoreKm
            let expected = luminance * cos(centre.latitude * .pi / 180) / pow(ratio, 2.5)
            let glow = map.skyGlowIndex(at: site)
            XCTAssertEqual(glow, expected, accuracy: expected * 1e-9, "\(degrees)°")
            XCTAssertLessThan(glow, previous, "\(degrees)°")
            previous = glow
        }
        // 1.2° is 133 km: out of reach, in every direction.
        XCTAssertEqual(map.skyGlowIndex(at: GeographicLocation(latitude: centre.latitude, longitude: centre.longitude + 1.2)), 0)
        XCTAssertEqual(map.skyGlowIndex(at: GeographicLocation(latitude: centre.latitude + 1.2, longitude: centre.longitude)), 0)
        XCTAssertEqual(map.skyGlowIndex(at: GeographicLocation(latitude: centre.latitude - 1.2, longitude: centre.longitude - 1.2)), 0)
        XCTAssertEqual(try Support.map(Support.darkCells()).skyGlowIndex(at: centre), 0)
    }

    func testSkyGlowReachesAcrossTheAntimeridian() throws {
        var east = Support.darkCells()
        east[900 * 3600 + 3599] = 12
        var west = Support.darkCells()
        west[900 * 3600 + 1799] = 12
        let across = try Support.map(east).skyGlowIndex(at: GeographicLocation(latitude: -0.05, longitude: -179.95))
        let inland = try Support.map(west).skyGlowIndex(at: GeographicLocation(latitude: -0.05, longitude: 0.05))
        XCTAssertGreaterThan(across, 0)
        XCTAssertEqual(across, inland, accuracy: inland * 1e-9)
    }

    func testADecodedAbsurdLocationLooksUpTheMapWithoutTrapping() throws {
        let map = try shipped()
        let location = try JSONDecoder().decode(GeographicLocation.self,
                                                from: Data(#"{"latitude":1e18,"longitude":1e18,"elevation":0}"#.utf8))
        XCTAssertTrue((0...15).contains(map.level(at: location)))
        XCTAssertTrue(map.skyGlowIndex(at: location).isFinite)
    }

    func testSkyGlowIsFiniteAtThePoles() throws {
        let bright = try Support.map(Support.cells { _, _ in 15 })
        for latitude in [90.0, 89.95, 85.0, -85.0, -89.95, -90.0] {
            let glow = bright.skyGlowIndex(at: GeographicLocation(latitude: latitude, longitude: 30))
            XCTAssertTrue(glow.isFinite && glow > 0, "\(latitude)")
        }
        XCTAssertGreaterThan(bright.skyGlowIndex(at: GeographicLocation(latitude: 0, longitude: 30)), 1)
    }

    // MARK: Directions

    func testDarkestDirectionOfASyntheticGradient() throws {
        // Level 10 at 0° E, one level more per 0.1° eastward: the east is brighter, the west darker.
        let map = try Support.map(Support.cells { _, column in min(max(column - 1790, 0), 15) })
        let directions = map.darkestDirection(around: GeographicLocation(latitude: 0, longitude: 0))
        XCTAssertEqual(directions.count, 16)
        XCTAssertEqual(directions.map(\.direction), CompassPoint.allCases)
        XCTAssertEqual(directions.prefix(3).map(\.azimuth), [0, 22.5, 45])
        func mean(_ point: CompassPoint) -> Double { directions[point.rawValue].meanLevel }
        XCTAssertEqual(mean(.north), 10, accuracy: 1e-12)
        XCTAssertEqual(mean(.south), 10, accuracy: 1e-12)
        XCTAssertEqual(mean(.east), 11, accuracy: 1e-12)
        XCTAssertEqual(mean(.west), 8, accuracy: 1e-12)
        XCTAssertLessThan(mean(.west), mean(.westNorthwest))
        XCTAssertGreaterThan(mean(.east), mean(.north))
        let darkest = try XCTUnwrap(directions.darkest)
        XCTAssertEqual(darkest.direction, .west)
        XCTAssertEqual(try XCTUnwrap(directions.darkestHint).direction, .west)
        XCTAssertEqual(darkest.glow, 8.0 / 15.0, accuracy: 1e-12)
        // The ring: exact at the sector centres, linear between them, periodic.
        XCTAssertEqual(directions.horizonGlow(azimuth: 270), darkest.glow, accuracy: 1e-12)
        XCTAssertEqual(directions.horizonGlow(azimuth: -90), directions.horizonGlow(azimuth: 270), accuracy: 1e-12)
        XCTAssertEqual(directions.horizonGlow(azimuth: 630), directions.horizonGlow(azimuth: 270), accuracy: 1e-12)
        XCTAssertEqual(directions.horizonGlow(azimuth: 281.25), (directions[12].glow + directions[13].glow) / 2,
                       accuracy: 1e-12)
        XCTAssertEqual(directions.horizonGlow(azimuth: 348.75), (directions[15].glow + directions[0].glow) / 2,
                       accuracy: 1e-12)
        XCTAssertEqual(directions.horizonGlow(azimuth: 360), directions[0].glow, accuracy: 1e-12)
        XCTAssertGreaterThan(directions.horizonGlow(azimuth: 90), directions.horizonGlow(azimuth: 0))
        XCTAssertGreaterThan(directions.horizonGlow(azimuth: 0), directions.horizonGlow(azimuth: 270))
        XCTAssertEqual(directions.horizonGlow(azimuth: .nan), 0)
        XCTAssertEqual([DirectionBrightness]().horizonGlow(azimuth: 10), 0)
    }

    func testDarkestDirectionHasNoHintWhereEveryDirectionIsAlike() throws {
        let flat = try Support.map(Support.cells { _, _ in 5 })
        let directions = flat.darkestDirection(around: GeographicLocation(latitude: 10, longitude: 20))
        XCTAssertTrue(directions.allSatisfy { $0.meanLevel == 5 })
        XCTAssertEqual(try XCTUnwrap(directions.darkest).direction, .north)
        XCTAssertNil(directions.darkestHint)
        XCTAssertNil([DirectionBrightness]().darkest)
        XCTAssertNil([DirectionBrightness]().darkestHint)
    }

    func testDarkestDirectionLimitsTheRadius() throws {
        let map = try Support.map(Support.cells { _, column in min(max(column - 1790, 0), 15) })
        let site = GeographicLocation(latitude: 0, longitude: 0)
        XCTAssertEqual(map.darkestDirection(around: site, radiusKm: 30), map.darkestDirection(around: site, radiusKm: .nan))
        XCTAssertEqual(map.darkestDirection(around: site), map.darkestDirection(around: site, radiusKm: 30))
        XCTAssertEqual(map.darkestDirection(around: site, radiusKm: 1), map.darkestDirection(around: site, radiusKm: -50))
        XCTAssertEqual(map.darkestDirection(around: site, radiusKm: 200), map.darkestDirection(around: site, radiusKm: 1e9))
        XCTAssertEqual(map.darkestDirection(around: site, radiusKm: .infinity).count, 16)
    }

    func testDarkestDirectionAtRealSites() throws {
        let map = try shipped()
        let newYork = map.darkestDirection(around: GeographicLocation(latitude: 40.7580, longitude: -73.9855))
        XCTAssertEqual(newYork.count, 16)
        XCTAssertTrue(newYork.allSatisfy { (0...15).contains($0.meanLevel) })
        XCTAssertTrue(newYork.allSatisfy { $0.meanLevel >= 12 })
        let ocean = map.darkestDirection(around: GeographicLocation(latitude: 0, longitude: -150))
        XCTAssertTrue(ocean.allSatisfy { $0.meanLevel == 0 })
        XCTAssertNil(ocean.darkestHint)
        XCTAssertFalse(ocean.contains { $0.glow > 0 })
    }

    func testDarkestDirectionAtBoulderMatchesTheGeneratorsModel() throws {
        // From Tools/build_light_pollution.py's model of the same rays (Python, not this code): the foothills to the
        // south-west and west are dark, Denver to the east and south-east is bright.
        let expected = [
            4.0, 7.833333333333333, 10.666666666666666, 9.833333333333334, 9.666666666666666, 12.833333333333334,
            11.666666666666666, 10.666666666666666, 7.5, 1.3333333333333333, 1.3333333333333333, 2.0, 2.0, 2.0, 2.0, 2.0,
        ]
        let directions = try shipped().darkestDirection(around: GeographicLocation(latitude: 40.0150, longitude: -105.2705))
        XCTAssertEqual(directions.count, expected.count)
        for index in expected.indices {
            XCTAssertEqual(directions[index].meanLevel, expected[index], accuracy: 1e-9, "direction \(index)")
        }
        XCTAssertEqual(try XCTUnwrap(directions.darkestHint).direction, .southSouthwest)
    }
}

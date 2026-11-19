import Foundation

/// Why the light pollution map could not be loaded.
public enum SkyQualityError: Error, Hashable, Sendable {
    /// The bundled `lightpollution.bin` is missing, unreadable, larger than `LightPollutionMap.maximumFileBytes` or
    /// malformed.
    case lightPollutionMapUnavailable(reason: String)
}

extension SkyQualityError: LocalizedError, CustomStringConvertible {
    /// A sentence that says what is wrong with the data file.
    public var description: String {
        switch self {
        case .lightPollutionMapUnavailable(let reason):
            "The light pollution map is unavailable: \(reason)"
        }
    }

    /// The same sentence as `description`.
    public var errorDescription: String? { description }
}

/// A coarse map of the artificial light at night, and from it an offline estimate of the sky quality of any site.
///
/// ```swift
/// let map = try LightPollutionMap.load()                   // once; keep the value
/// let here = GeographicLocation(latitude: 41.66, longitude: -77.82)
/// let estimate = map.bortleEstimate(at: here)              // class 1-9, label, caveat
/// let around = map.darkestDirection(around: here)          // 16 compass directions, 30 km
/// around.darkestHint?.direction                            // where the sky is darker, if it is
/// ```
///
/// **Data.** `lightpollution.bin`, a 3600 x 1800 grid of 0.1° cells (about 11 km) with 16 levels, built by
/// `Tools/build_light_pollution.py` from NASA GIBS, layer `VIIRS_Black_Marble` (Suomi NPP VIIRS day/night band composite
/// of 2016, tiles pinned in `Tools/lightpollution.lock.json`). The land's faint base texture is removed, the light is
/// averaged per cell and quantized on a log scale: level 0 is dark (below 0.0025 of the display's full scale: ocean,
/// deserts, forests, ice), level 15 the centre of a big city. The file is 137 kB; `load()` expands it to 6.5 MB (one
/// byte per cell). Credit: NASA Worldview / GIBS, Black Marble (VIIRS, Suomi NPP).
///
/// **Levels.** `level(at:)` is the nearest cell and nothing else; the data is too coarse for interpolation. A satellite
/// sees the light a place sends up, not the glow it receives: a dark cell 15 km from a town is level 0 and still has a
/// bright sky.
///
/// **Sky glow.** `skyGlowIndex(at:)` adds up the light of every cell within `glowRadiusKm` (100 km) of the site, each
/// cell's luminance (`levelLuminance`) times its area (the cosine of its latitude) times `(d / 5.5 km)^-2.5`, where `d`
/// is the distance to the cell's centre and never less than 5.5 km (Walker's law for the glow of a town, the exponent
/// -2.5 of Garstang-type models). The index is in units of "one cell of luminance 1 at the site"; a megacity gives 1 or
/// more. `bortleEstimate(at:)` turns the index into a class with `BortleEstimate.glowThresholds`.
///
/// **Calibration.** The thresholds were chosen from these places (the generator prints the table with
/// `--report`; published classes are approximate, sources differ by one class, and a satellite sees emitted light):
///
/// | Place | Published | Cell level | Glow index | Estimate |
/// |---|---|---|---|---|
/// | Cherry Springs State Park, PA | 2 | 0 | 0.0005 | 2 |
/// | Death Valley, Badwater | 1-2 | 0 | 0.00009 | 1 |
/// | Big Bend, Chisos Basin | 1-2 | 0 | 0.0 | 1 |
/// | Joshua Tree, Hidden Valley | 2-3 | 0 | 0.017 | 4 (off by one) |
/// | Zselic Starry Sky Park, HU | 3 | 0 | 0.0041 | 3 |
/// | Galloway Forest Park | 2-3 | 0 | 0.0024 | 3 |
/// | Mauna Kea summit | 1 | 0 | 0.0003 | 1 |
/// | Natural Bridges, UT | 1 | 0 | 0.00001 | 1 |
/// | Paranal, Chile | 1 | 0 | 0.00004 | 1 |
/// | Roque de los Muchachos, La Palma | 1 | 0 | 0.0017 | 3 (off by two: towns 20 km below) |
/// | Kielder Observatory, UK | 2-3 | 0 | 0.0037 | 3 |
/// | McDonald Observatory, TX | 1-2 | 0 | 0.0001 | 1 |
/// | Green Bank, WV | 3 | 0 | 0.0006 | 2 (off by one) |
/// | Flagstaff, AZ (Lowell Observatory) | 5-6 | 7 | 0.050 | 5 |
/// | Boulder, CO | 7 | 12 | 0.23 | 7 |
/// | Palo Alto, CA | 7-8 | 13 | 0.40 | 8 |
/// | Plano, TX | 7-8 | 15 | 1.29 | 9 (the whole Dallas area is lit) |
/// | Munich, Marienplatz | 8-9 | 15 | 0.61 | 9 |
/// | Cape Town, centre | 8-9 | 14 | 0.47 | 8 |
/// | London, Trafalgar Square | 9 | 15 | 1.12 | 9 |
/// | New York, Times Square | 9 | 15 | 1.31 | 9 |
/// | Las Vegas, the Strip | 9 | 15 | 1.02 | 9 |
/// | Tokyo, Shinjuku | 9 | 15 | 1.26 | 9 |
/// | Pacific Ocean (0°, 150° W), Sahara (23° N, 10° E) | 1 | 0 | 0.0 | 1 |
///
/// 21 of the 25 places fall in their published class. The estimate is good to about a class in a city and two in the
/// dark, where the satellite cannot tell a Bortle 1 from a Bortle 3 sky.
///
/// **Cost.** `level(at:)` is a lookup. `skyGlowIndex(at:)` and `bortleEstimate(at:)` visit about 1,300 cells at mid
/// latitudes (a few thousand at 70°, all of the 19 rows at the poles): tens of microseconds. `darkestDirection` makes
/// 16 x 6 lookups. Values are immutable and may be shared between threads.
public struct LightPollutionMap: Sendable {
    /// The name of the bundled file in the library's resources.
    public static let resourceFileName = "lightpollution.bin"
    /// The largest file that is accepted, 1 MiB (the shipped one is 137 kB).
    public static let maximumFileBytes = 1024 * 1024
    /// Cells per row of the grid: 3600 cells of 0.1° from 180° W eastward.
    public static let width = 3600
    /// Rows of the grid: 1800 cells of 0.1° from 90° N southward.
    public static let height = 1800
    /// The side of a cell in degrees.
    public static let cellDegrees = 0.1
    /// The number of levels, 0 (dark) to 15.
    public static let levelCount = 16
    /// The brightest level, 15.
    public static let maximumLevel = 15
    /// The radius in kilometres within which cells add to the sky glow.
    public static let glowRadiusKm = 100.0
    /// The distance in kilometres below which a cell counts as if it were this far: about half a cell.
    public static let glowCoreKm = 5.5
    /// The length of a degree of latitude in kilometres, as the generator and the glow model use it.
    public static let kilometersPerDegree = 111.195
    /// The default length of the rays of `darkestDirection(around:radiusKm:)`, 30 km.
    public static let defaultRayKm = 30.0

    /// The linear luminance (0 to about 0.5 of the display's full scale) that stands for each level in the sky-glow
    /// model: the geometric middle of the level's range; 0 for level 0. Index 0-15.
    public static let levelLuminance: [Double] = [
        0, 0.002997, 0.004306, 0.006188, 0.008891, 0.01278, 0.01836, 0.02638,
        0.03791, 0.05447, 0.07827, 0.1125, 0.1616, 0.2322, 0.3337, 0.4795,
    ]

    private static let earthRadiusKm = 6371.0088
    private static let headerBytes = 16

    /// One byte per cell, row by row from the north.
    let levels: [UInt8]

    private init(levels: [UInt8]) {
        self.levels = levels
    }

    /// Reads the bundled file and expands it to 6.5 MB; about 10 ms. Call it once, off the main thread, and keep the
    /// value.
    ///
    /// - Throws: `SkyQualityError.lightPollutionMapUnavailable` when the file is missing, unreadable, too large or
    ///   malformed.
    public static func load() throws -> LightPollutionMap {
        try parse(bundledData())
    }

    /// The raw contents of the bundled file.
    static func bundledData() throws -> Data {
        let bundle = Bundle.module
        let name = (resourceFileName as NSString).deletingPathExtension
        let fileExtension = (resourceFileName as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: fileExtension)
                ?? bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources") else {
            throw SkyQualityError.lightPollutionMapUnavailable(reason: "the resource \(resourceFileName) is missing")
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw SkyQualityError.lightPollutionMapUnavailable(reason: error.localizedDescription)
        }
    }

    /// Reads the contents of such a file; `load()` is this with the bundled bytes. The format is described in
    /// `Tools/build_light_pollution.py`: a 16-byte header, then runs per row.
    static func parse(_ data: Data) throws -> LightPollutionMap {
        func unavailable(_ reason: String) -> SkyQualityError { .lightPollutionMapUnavailable(reason: reason) }
        guard data.count <= maximumFileBytes else { throw unavailable("the file is larger than \(maximumFileBytes) bytes") }
        guard data.count >= headerBytes else { throw unavailable("the file is shorter than its header") }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x4C, bytes[1] == 0x50, bytes[2] == 0x4D, bytes[3] == 0x31 else {
            throw unavailable("the file is not a light pollution map")
        }
        let gridWidth = Int(bytes[4]) | (Int(bytes[5]) << 8)
        let gridHeight = Int(bytes[6]) | (Int(bytes[7]) << 8)
        let runLength = Int(bytes[10]) | (Int(bytes[11]) << 8) | (Int(bytes[12]) << 16) | (Int(bytes[13]) << 24)
        guard gridWidth == width, gridHeight == height, Int(bytes[8]) == levelCount, bytes[9] == 0,
              bytes[14] == 0, bytes[15] == 0 else {
            throw unavailable("the grid is not 3600 x 1800 cells of 16 levels")
        }
        guard runLength == bytes.count - headerBytes else { throw unavailable("the run data has the wrong length") }
        var cells = [UInt8](repeating: 0, count: width * height)
        var position = headerBytes
        for row in 0..<height {
            var column = 0
            while column < width {
                guard position < bytes.count else { throw unavailable("the run data ends inside a row") }
                let token = Int(bytes[position])
                position += 1
                var run = (token >> 4) + 1
                if token >> 4 == 15 {
                    var extra = 0
                    var shift = 0
                    while true {
                        guard position < bytes.count, shift <= 14 else { throw unavailable("a run length is malformed") }
                        let next = Int(bytes[position])
                        position += 1
                        extra |= (next & 0x7F) << shift
                        shift += 7
                        if next & 0x80 == 0 { break }
                    }
                    run = 16 + extra
                }
                guard run <= width - column else { throw unavailable("a run crosses the end of its row") }
                let start = row * width + column
                cells.replaceSubrange(start..<start + run, with: repeatElement(UInt8(token & 15), count: run))
                column += run
            }
        }
        guard position == bytes.count else { throw unavailable("the file has bytes after the last row") }
        return LightPollutionMap(levels: cells)
    }

    /// The row of the cell that contains `latitude`: 0 at the north pole, clamped to the grid.
    static func row(latitude: Double) -> Int {
        min(max(Int(((90 - latitude) * 10).rounded(.down)), 0), height - 1)
    }

    /// The column of the cell that contains `longitude`: 0 starts at 180° W; wraps around.
    static func column(longitude: Double) -> Int {
        let column = Int(((longitude + 180) * 10).rounded(.down))
        return ((column % width) + width) % width
    }

    /// The level, 0 (dark) to 15, of the cell that contains `location` (the nearest cell).
    public func level(at location: GeographicLocation) -> Int {
        Int(levels[Self.row(latitude: location.latitude) * Self.width + Self.column(longitude: location.longitude)])
    }

    /// The sky-glow index of a site: the light of the cells within `glowRadiusKm` weighted by area and distance (see
    /// the type's documentation). 0 in the dark, about 1 or more in the centre of a megacity. Tens of microseconds.
    public func skyGlowIndex(at location: GeographicLocation) -> Double {
        let latitude = location.latitude
        let longitude = location.longitude
        let centerRow = Self.row(latitude: latitude)
        let centerColumn = Self.column(longitude: longitude)
        let rowSpan = Int(Self.glowRadiusKm / (Self.kilometersPerDegree * Self.cellDegrees)) + 1
        let luminance = Self.levelLuminance
        var total = 0.0
        for row in max(0, centerRow - rowSpan)...min(Self.height - 1, centerRow + rowSpan) {
            let rowLatitude = 90 - (Double(row) + 0.5) * Self.cellDegrees
            let area = cos(AstroMath.radians(rowLatitude))
            let eastWest = Self.kilometersPerDegree * cos(AstroMath.radians((latitude + rowLatitude) / 2))
            let northSouth = (rowLatitude - latitude) * Self.kilometersPerDegree
            let columnSpan = min(Self.width / 2 - 1,
                                 Int(Self.glowRadiusKm / (max(eastWest, 1e-9) * Self.cellDegrees)) + 1)
            for step in -columnSpan...columnSpan {
                let column = (((centerColumn + step) % Self.width) + Self.width) % Self.width
                let level = Int(levels[row * Self.width + column])
                if level == 0 { continue }
                let delta = ((Double(column) + 0.5) * Self.cellDegrees - 180 - longitude + 540)
                    .truncatingRemainder(dividingBy: 360) - 180
                let distance = hypot(delta * eastWest, northSouth)
                if distance > Self.glowRadiusKm { continue }
                let ratio = max(distance, Self.glowCoreKm) / Self.glowCoreKm
                total += luminance[level] * area / (ratio * ratio * ratio.squareRoot())
            }
        }
        return total
    }

    /// The estimated Bortle class of the sky at `location`: `skyGlowIndex(at:)` turned into a class 1-9 with
    /// `BortleEstimate.glowThresholds`, with the cell's `level(at:)`. Tens of microseconds.
    public func bortleEstimate(at location: GeographicLocation) -> BortleEstimate {
        BortleEstimate(skyGlowIndex: skyGlowIndex(at: location), level: level(at: location))
    }

    /// The 16 compass directions around `location`, north first, each with the mean level of the cells along a ray of
    /// `radiusKm` (sampled every 5 km or less, at the middle of equal steps). The darkest direction is the hint for
    /// where to look for a darker sky: see `darkest` and `darkestHint`; `horizonGlow(azimuth:)` turns the list into a
    /// ring.
    ///
    /// - Parameter radiusKm: The length of the rays, clamped to 1-200 km; 30 when it is not a finite number.
    public func darkestDirection(around location: GeographicLocation,
                                 radiusKm: Double = LightPollutionMap.defaultRayKm) -> [DirectionBrightness] {
        let radius = radiusKm.isFinite ? AstroMath.clamp(radiusKm, 1, 200) : Self.defaultRayKm
        let samples = max(1, Int((radius / 5).rounded(.up)))
        return CompassPoint.allCases.map { direction in
            var sum = 0
            for index in 0..<samples {
                let distance = radius * (Double(index) + 0.5) / Double(samples)
                sum += level(at: Self.destination(from: location, bearing: direction.centerAzimuth, distanceKm: distance))
            }
            return DirectionBrightness(direction: direction, meanLevel: Double(sum) / Double(samples))
        }
    }

    /// The place `distanceKm` from `origin` on the initial great-circle bearing `bearing` (degrees from north).
    private static func destination(from origin: GeographicLocation, bearing: Double,
                                    distanceKm: Double) -> GeographicLocation {
        let angle = distanceKm / earthRadiusKm
        let theta = AstroMath.radians(bearing)
        let phi = AstroMath.radians(origin.latitude)
        let phi2 = asin(sin(phi) * cos(angle) + cos(phi) * sin(angle) * cos(theta))
        let lambda2 = AstroMath.radians(origin.longitude)
            + atan2(sin(theta) * sin(angle) * cos(phi), cos(angle) - sin(phi) * sin(phi2))
        return GeographicLocation(latitude: AstroMath.degrees(phi2), longitude: AstroMath.degrees(lambda2))
    }
}

/// A sky-quality estimate for one site, from `LightPollutionMap.bortleEstimate(at:)`.
///
/// The Bortle scale (Bortle, *Sky & Telescope*, February 2001) rates a sky from class 1, the darkest, to class 9, an
/// inner-city sky. The class here is an estimate from 2016 satellite night-light imagery: `caveat` must be shown with it.
public struct BortleEstimate: Sendable, Hashable {
    /// What to say with every estimate: it is not a measurement.
    public static let caveat = "Estimated from 2016 satellite night-light imagery; not a sky measurement"

    /// The sky-glow index at which classes 2, 3, ... 9 begin; class 1 is below the first. Strictly increasing, chosen
    /// from the reference places in the documentation of `LightPollutionMap`.
    public static let glowThresholds: [Double] = [0.00045, 0.0012, 0.008, 0.02, 0.06, 0.15, 0.3, 0.5]

    /// The estimated class, 1 (excellent dark sky) to 9 (inner-city sky).
    public let bortleClass: Int
    /// The light level of the site's own cell, 0 to 15.
    public let level: Int
    /// The sky-glow index the class was taken from (see `LightPollutionMap`).
    public let skyGlowIndex: Double

    /// The estimate for a glow index and a cell level: a `skyGlowIndex` that is negative or not a number counts as 0
    /// and `level` is limited to 0-15.
    public init(skyGlowIndex: Double, level: Int) {
        let glow = skyGlowIndex.isFinite && skyGlowIndex > 0 ? skyGlowIndex : 0
        self.bortleClass = Self.bortleClass(forGlowIndex: glow)
        self.level = AstroMath.clamp(level, 0, LightPollutionMap.maximumLevel)
        self.skyGlowIndex = glow
    }

    /// The name of the class in Bortle's scale, for example "Rural sky".
    public var label: String { Self.label(forClass: bortleClass) }

    /// A short phrase for site lists: "Bortle ~4 (rural/suburban transition)".
    public var summary: String { "Bortle ~\(bortleClass) (\(label.lowercased()))" }

    /// The Bortle class, 1-9, of a sky-glow index: 1 plus the number of `glowThresholds` it reaches.
    public static func bortleClass(forGlowIndex glowIndex: Double) -> Int {
        1 + glowThresholds.filter { $0 <= glowIndex }.count
    }

    /// The name of a class in Bortle's scale; the class is limited to 1-9.
    public static func label(forClass bortleClass: Int) -> String {
        switch AstroMath.clamp(bortleClass, 1, 9) {
        case 1: "Excellent dark sky"
        case 2: "Typical dark sky"
        case 3: "Rural sky"
        case 4: "Rural/suburban transition"
        case 5: "Suburban sky"
        case 6: "Bright suburban sky"
        case 7: "Suburban/urban transition"
        case 8: "City sky"
        default: "Inner-city sky"
        }
    }
}

/// The light along one compass direction from a site, from `LightPollutionMap.darkestDirection(around:radiusKm:)`.
public struct DirectionBrightness: Sendable, Hashable {
    /// The compass point; the ray runs along its centre azimuth.
    public let direction: CompassPoint
    /// The mean level, 0 to 15, of the cells sampled along the ray.
    public let meanLevel: Double

    init(direction: CompassPoint, meanLevel: Double) {
        self.direction = direction
        self.meanLevel = meanLevel
    }

    /// The azimuth of the ray in degrees, from north through east.
    public var azimuth: Double { direction.centerAzimuth }

    /// `meanLevel` as a fraction of the brightest level, 0 to 1: the strength of the glow on the horizon.
    public var glow: Double { meanLevel / Double(LightPollutionMap.maximumLevel) }
}

extension Array where Element == DirectionBrightness {
    /// The darkest direction of a list from `darkestDirection(around:radiusKm:)`: the lowest mean level, the first on a
    /// tie.
    public var darkest: DirectionBrightness? {
        var best: DirectionBrightness?
        for candidate in self {
            if let current = best, candidate.meanLevel >= current.meanLevel { continue }
            best = candidate
        }
        return best
    }

    /// The `darkest` direction, but only when it is worth saying: at least one level darker than the brightest
    /// direction. `nil` over open sea or in the middle of a uniformly lit area, where every direction is alike.
    public var darkestHint: DirectionBrightness? {
        guard let dark = darkest, let brightest = map(\.meanLevel).max() else { return nil }
        return brightest - dark.meanLevel >= 1 ? dark : nil
    }

    /// The glow on the horizon toward `azimuth`, 0 to 1, interpolated linearly between the two nearest directions of a
    /// list as returned by `darkestDirection(around:radiusKm:)` (evenly spaced from north, wrapping at north). 0 for an
    /// empty list or an azimuth that is not a finite number. For the ring of a sky chart.
    public func horizonGlow(azimuth: Double) -> Double {
        guard !isEmpty, azimuth.isFinite else { return 0 }
        var wrapped = azimuth.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        let position = wrapped / (360 / Double(count))
        let lower = position.rounded(.down)
        let first = Int(lower) % count
        let second = (first + 1) % count
        let fraction = position - lower
        return self[first].glow * (1 - fraction) + self[second].glow * fraction
    }
}

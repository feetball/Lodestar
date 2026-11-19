import Foundation

/// What `TerrainHorizon.profile(at:tiles:eyeHeightMeters:maxDistanceMeters:)` found.
public struct TerrainHorizonResult: Sendable, Hashable {
    /// The skyline: the highest apparent altitude of the terrain along each of the 360 whole-degree azimuths, limited
    /// to −10…+60° and rounded to 0.1° like every `HorizonProfile`.
    public let profile: HorizonProfile
    /// The same 360 altitudes before the limits and the rounding, in degrees. Over flat ground they are the dip of the
    /// horizon, a few hundredths of a degree for an eye 2 m high, which the 0.1° of `profile` cannot show.
    public let altitudes: [Double]
    /// The elevation of the ground at the site, from the tiles, or `nil` when no tile covers the site or its sample is
    /// a void. It is the reference of every altitude.
    public let groundElevationMeters: Double?
    /// For each azimuth, how far from the site the tiles reach without a break (0 when the first step is already
    /// outside the tiles); `TerrainHorizon.maximumRangeMeters` at most.
    public let coveredRangeMeters: [Double]
    /// The tiles within the range that were not supplied, nearest first; their terrain is not in the skyline.
    public let missingTiles: [TerrainTileKey]
    /// The share of the samples that fell on voids (water the survey could not measure, gaps) and were counted as sea
    /// level, 0…1.
    public let voidSampleShare: Double

    /// Creates a result.
    public init(profile: HorizonProfile, altitudes: [Double], groundElevationMeters: Double?, coveredRangeMeters: [Double],
                missingTiles: [TerrainTileKey], voidSampleShare: Double) {
        self.profile = profile
        self.altitudes = altitudes
        self.groundElevationMeters = groundElevationMeters
        self.coveredRangeMeters = coveredRangeMeters
        self.missingTiles = missingTiles
        self.voidSampleShare = voidSampleShare
    }

    /// The shortest of `coveredRangeMeters`: how far the data reaches in the worst direction.
    public var minimumCoveredRangeMeters: Double { coveredRangeMeters.min() ?? 0 }

    /// `true` when no tile within the range is missing.
    public var isComplete: Bool { missingTiles.isEmpty }
}

/// The skyline a site would have without trees and buildings: the highest terrain along every azimuth, computed from
/// digital elevation tiles (`TerrainTile`). Pure computation; the tiles are downloaded and inflated by the apps.
///
/// **Method.** For each of the 360 whole-degree azimuths a ray is marched over the sphere of radius
/// `earthRadiusMeters` (the mean radius of the WGS 84 ellipsoid, 6 371 008.8 m) from the site: every 30 m up to 2 km,
/// every 100 m up to 10 km and every 250 m beyond, to the range. The elevation under each step comes from the tile that
/// contains it (bilinear), a void counts as 0 m, and a step outside every tile is skipped. The apparent altitude of a
/// terrain point at distance `d` and height `h`, seen from the eye at `h0` (ground at the site plus the eye height),
/// is `atan((h − h0) / d) − d / (2 R′)` with `R′ = R / (1 − k)`: the first term is the elevation angle, the second the
/// drop of the surface below the tangent plane (`d² / 2R`) reduced by standard terrestrial refraction with the
/// coefficient `k` = `refractionCoefficient` (0.13). That is Gauss's value from the Hannover triangulation of 1826 and
/// the mean refraction coefficient geodetic instruments apply (the Leica TS13 manual gives the height correction
/// `(1 − k) d² / 2R` with `k` = 0.13); the refracted ray is treated as straight over an Earth of radius `R′` (see
/// "Atmospheric refraction", Wikipedia, `R_eff = R / (1 − k)`). Real refraction varies with the temperature gradient,
/// by day and by night (Hirt et al., J. Geophys. Res. 115, D21102, 2010); the part of the correction that refraction
/// accounts for is `k d / 2R`, 0.03° at 50 km, so a different `k` moves a ridge at the edge of the range by about that.
/// The skyline at an azimuth is the maximum over the steps. Over flat ground this gives the dip of the horizon,
/// `−√(2h / R′)` radians for an eye at height `h`: −0.042° for 2 m (the geometric dip `√(2h / R)` is −0.045°).
///
/// **Accuracy.** The elevation data is a surface model: tree tops and buildings count as ground where the survey saw
/// them. A tile has 30 m (1 arc-second) or 90 m (3 arc-second) samples, so a ridge narrower than that is missed or
/// blunted; one sample is 0.17° wide as seen from 10 km (30 m) and the profile's bins are 1° wide.
///
/// **Cost.** About 110 000 bilinear samples for the default range (360 azimuths × about 300 steps), plus
/// `TerrainTile.parse` for every tile. Call both off the main thread.
public enum TerrainHorizon {
    /// The radius of the sphere the rays run over, in metres: the mean radius of the WGS 84 ellipsoid.
    public static let earthRadiusMeters = 6_371_008.8
    /// The coefficient of standard terrestrial refraction, `k`: the ray's curvature is this share of the Earth's.
    public static let refractionCoefficient = 0.13
    /// The height of the eye above the ground, in metres, when the caller gives none.
    public static let defaultEyeHeightMeters = 2.0
    /// The range of the rays, in metres, when the caller gives none.
    public static let defaultMaximumDistanceMeters = 50_000.0
    /// The highest eye height accepted, in metres; more is limited to this.
    public static let maximumEyeHeightMeters = 100.0
    /// The shortest range accepted, in metres.
    public static let minimumRangeMeters = 1_000.0
    /// The longest range accepted, in metres.
    public static let maximumRangeMeters = 100_000.0
    /// The step of the rays, in metres, up to `nearLimitMeters`.
    public static let nearStepMeters = 30.0
    /// The step of the rays, in metres, from `nearLimitMeters` to `midLimitMeters`.
    public static let midStepMeters = 100.0
    /// The step of the rays, in metres, beyond `midLimitMeters`.
    public static let farStepMeters = 250.0
    /// The distance up to which the rays step by `nearStepMeters`, in metres.
    public static let nearLimitMeters = 2_000.0
    /// The distance up to which the rays step by `midStepMeters`, in metres.
    public static let midLimitMeters = 10_000.0
    /// `requiredTiles(at:maxDistanceMeters:)` lists at most this many tiles (a site near a pole is within 50 km of dozens).
    public static let maximumTileCount = 16

    private static let metersPerDegree = earthRadiusMeters * AstroMath.radiansPerDegree

    /// The apparent altitude in degrees of a terrain point `heightDifferenceMeters` above the eye, at the horizontal
    /// distance `distanceMeters`: `atan(Δh / d) − d / (2 R′)` with `R′ = R / (1 − k)`, see the type description.
    /// Negative below the eye's horizontal plane. `distanceMeters` must be positive.
    public static func apparentAltitude(heightDifferenceMeters: Double, distanceMeters: Double) -> Double {
        let effectiveRadius = earthRadiusMeters / (1 - refractionCoefficient)
        return AstroMath.degrees(atan(heightDifferenceMeters / distanceMeters))
            - AstroMath.degrees(distanceMeters / (2 * effectiveRadius))
    }

    /// The distances from the site, in metres, at which the rays are sampled for a range of `maximumDistanceMeters`:
    /// 30, 60 … 1980, then 2010, 2110 … 9910, then 10 010, 10 260 …, the last one not beyond the range.
    public static func sampleDistances(maximumDistanceMeters: Double) -> [Double] {
        let range = clampedRange(maximumDistanceMeters)
        var distances: [Double] = []
        var distance = nearStepMeters
        while distance <= range {
            distances.append(distance)
            if distance < nearLimitMeters {
                distance += nearStepMeters
            } else if distance < midLimitMeters {
                distance += midStepMeters
            } else {
                distance += farStepMeters
            }
        }
        return distances
    }

    /// The tiles a profile for `location` with the range `maxDistanceMeters` needs: every 1° × 1° tile that comes
    /// within that distance of the site, nearest first (the tile with the site first), at most `maximumTileCount`.
    /// A 50 km circle is 0.9° wide at the equator and 1.3° wide at 47° of latitude, so it reaches up to four tiles
    /// near the equator and up to six at mid latitudes. Ties in distance are ordered by latitude, then longitude. The
    /// distance to a tile is measured to the nearest point of its border, with a local flat-earth metric (error
    /// well under a kilometre at 50 km).
    public static func requiredTiles(at location: GeographicLocation,
                                     maxDistanceMeters: Double = defaultMaximumDistanceMeters) -> [TerrainTileKey] {
        let range = clampedRange(maxDistanceMeters)
        let latitude = location.latitude
        let longitude = location.longitude
        let latitudeSpan = range / metersPerDegree
        let longitudeSpan = min(latitudeSpan / max(AstroMath.cosDeg(latitude), 0.01), 180)
        let southmost = max(Int((latitude - latitudeSpan).rounded(.down)), -90)
        let northmost = min(Int((latitude + latitudeSpan).rounded(.down)), 89)
        let westmost = Int((longitude - longitudeSpan).rounded(.down))
        let eastmost = Int((longitude + longitudeSpan).rounded(.down))
        var found: [(meters: Double, key: TerrainTileKey)] = []
        var seen = Set<TerrainTileKey>()
        guard southmost <= northmost else { return [] }
        for row in southmost...northmost {
            for column in westmost...eastmost {
                let wrapped = ((column + 180) % 360 + 360) % 360 - 180
                guard let key = TerrainTileKey(latitude: row, longitude: wrapped) else { continue }
                let northSouth = max(Double(row) - latitude, 0, latitude - Double(row + 1))
                let eastWest = max(Double(column) - longitude, 0, longitude - Double(column + 1))
                let nearestLatitude = AstroMath.clamp(latitude, Double(row), Double(row + 1))
                let meters = hypot(northSouth, eastWest * AstroMath.cosDeg(nearestLatitude)) * metersPerDegree
                if meters <= range, seen.insert(key).inserted { found.append((meters, key)) }
            }
        }
        found.sort { $0.meters != $1.meters ? $0.meters < $1.meters : $0.key < $1.key }
        return found.prefix(maximumTileCount).map(\.key)
    }

    /// The skyline of the terrain around `location` from `tiles`.
    ///
    /// - Parameters:
    ///   - location: The site. Its elevation is used only where no tile covers the site.
    ///   - tiles: The elevation tiles; the ones the range needs are listed by `requiredTiles(at:maxDistanceMeters:)`,
    ///     and a tile that is given twice counts once. Tiles that are not needed do no harm.
    ///   - eyeHeightMeters: The height of the eye above the ground, in metres: 0…100, 2 when it is not finite.
    ///   - maxDistanceMeters: How far the rays go, in metres: 1000…100 000, 50 000 when it is not finite.
    public static func profile(at location: GeographicLocation, tiles: [TerrainTile],
                               eyeHeightMeters: Double = defaultEyeHeightMeters,
                               maxDistanceMeters: Double = defaultMaximumDistanceMeters) -> TerrainHorizonResult {
        let eye = eyeHeightMeters.isFinite
            ? AstroMath.clamp(eyeHeightMeters, 0, maximumEyeHeightMeters) : defaultEyeHeightMeters
        let range = clampedRange(maxDistanceMeters)
        var index: [Int: TerrainTile] = [:]
        for tile in tiles where index[tileCode(tile.latitude, tile.longitude)] == nil {
            index[tileCode(tile.latitude, tile.longitude)] = tile
        }
        let missing = requiredTiles(at: location, maxDistanceMeters: range)
            .filter { index[tileCode($0.latitude, $0.longitude)] == nil }
        let ground = tileAt(index, latitude: location.latitude, longitude: location.longitude)?
            .elevation(at: location.latitude, longitude: location.longitude)
        let eyeLevel = (ground ?? location.elevation) + eye

        let distances = sampleDistances(maximumDistanceMeters: range)
        let sinSteps = distances.map { sin($0 / earthRadiusMeters) }
        let cosSteps = distances.map { cos($0 / earthRadiusMeters) }
        let sinLatitude0 = AstroMath.sinDeg(location.latitude)
        let cosLatitude0 = AstroMath.cosDeg(location.latitude)
        var altitudes = [Double](repeating: 0, count: HorizonProfile.binCount)
        var covered = [Double](repeating: 0, count: HorizonProfile.binCount)
        var voids = 0
        var used = 0
        for bin in 0..<HorizonProfile.binCount {
            let azimuth = AstroMath.radians(Double(bin))
            let sinAzimuth = sin(azimuth)
            let cosAzimuth = cos(azimuth)
            var best = -Double.infinity
            var reach = 0.0
            var isContiguous = true
            for step in distances.indices {
                let sinLatitude = sinLatitude0 * cosSteps[step] + cosLatitude0 * sinSteps[step] * cosAzimuth
                let latitude = AstroMath.degrees(asin(AstroMath.clamp(sinLatitude, -1, 1)))
                var longitude = location.longitude + AstroMath.degrees(
                    atan2(sinAzimuth * sinSteps[step] * cosLatitude0, cosSteps[step] - sinLatitude0 * sinLatitude))
                if longitude >= 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
                guard let tile = tileAt(index, latitude: latitude, longitude: longitude) else {
                    isContiguous = false
                    continue
                }
                if isContiguous { reach = distances[step] }
                let elevation = tile.elevation(at: latitude, longitude: longitude)
                if elevation == nil { voids += 1 }
                used += 1
                let altitude = apparentAltitude(heightDifferenceMeters: (elevation ?? 0) - eyeLevel,
                                                distanceMeters: distances[step])
                if altitude > best { best = altitude }
            }
            altitudes[bin] = best == -Double.infinity ? 0 : best
            covered[bin] = reach
        }
        return TerrainHorizonResult(
            profile: HorizonProfile.fromClamped(altitudes), altitudes: altitudes, groundElevationMeters: ground,
            coveredRangeMeters: covered, missingTiles: missing,
            voidSampleShare: used == 0 ? 0 : Double(voids) / Double(used))
    }

    private static func clampedRange(_ meters: Double) -> Double {
        meters.isFinite ? AstroMath.clamp(meters, minimumRangeMeters, maximumRangeMeters) : defaultMaximumDistanceMeters
    }

    private static func tileCode(_ latitude: Int, _ longitude: Int) -> Int { (latitude + 90) * 360 + (longitude + 180) }

    private static func tileAt(_ index: [Int: TerrainTile], latitude: Double, longitude: Double) -> TerrainTile? {
        guard let key = TerrainTileKey.containing(latitude: latitude, longitude: longitude) else { return nil }
        return index[tileCode(key.latitude, key.longitude)]
    }
}

extension HorizonProfile {
    /// The skyline to use at a site that has a recorded skyline, a terrain skyline, or both: the recorded one where the
    /// sweep reached, the terrain one in the `gaps` the sweep left (see `unsweptRanges(swept:maximumInterpolatedGap:)`).
    /// With only one of them that one; with neither `nil`. Without `gaps` the recorded skyline wins everywhere (its
    /// coverage is not known or complete).
    public static func merged(recorded: HorizonProfile?, terrain: HorizonProfile?,
                              gaps: [AzimuthRange] = []) -> HorizonProfile? {
        guard let recorded else { return terrain }
        guard let terrain, !gaps.isEmpty else { return recorded }
        var values = recorded.altitudes
        for index in values.indices where gaps.contains(where: { $0.contains(Double(index)) }) {
            values[index] = terrain.altitudes[index]
        }
        return fromClamped(values)
    }

    /// The stretches a sweep left open, from the `swept` flags it reached (360 values, one per whole degree, like
    /// `HorizonRecorder.recordedMask`): the runs of unswept degrees longer than `maximumInterpolatedGap` (the recorder
    /// fills shorter ones by interpolation, so they are not gaps), in azimuth order, each starting at the lower edge of
    /// its first degree like `HorizonRecorder.gaps`. Nothing swept gives the whole circle; a `swept` list that is not 360
    /// long gives no gap.
    public static func unsweptRanges(
        swept: [Bool], maximumInterpolatedGap: Int = HorizonRecorder.Configuration.standard.maximumInterpolatedGap
    ) -> [AzimuthRange] {
        let count = binCount
        guard swept.count == count else { return [] }
        let limit = AstroMath.clamp(maximumInterpolatedGap, 0, 30)
        guard let first = swept.firstIndex(of: true) else { return [.full] }
        var ranges: [AzimuthRange] = []
        var start = -1
        for offset in 1...count {
            let bin = (first + offset) % count
            if !swept[bin] {
                if start < 0 { start = bin }
            } else if start >= 0 {
                let length = (bin - start + count) % count
                if length > limit { ranges.append(AzimuthRange(start: Double(start) - 0.5, length: Double(length))) }
                start = -1
            }
        }
        return ranges.sorted { $0.start < $1.start }
    }
}
